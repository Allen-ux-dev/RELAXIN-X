#include <libgen.h>
#include <mach-o/dyld.h>
#include <errno.h>
#include <stddef.h>
#include <stdint.h>

#include <choma/Fat.h>
#include <choma/MachO.h>
#include <choma/Host.h>
#include <choma/MachOByteOrder.h>
#include <choma/CodeDirectory.h>

#include "../codesign.h"
#include "../libjailbreak.h"
#include "../signatures.h"
#include "common.h"
#include "../log.h"
#include "signature_policy.h"

extern MachO *fat_find_preferred_slice(Fat *fat);

extern CS_DecodedBlob *csd_superblob_find_best_code_directory(CS_DecodedSuperBlob *decodedSuperblob);
extern bool code_directory_calculate_page_hash(CS_CodeDirectory *codeDir, MachO *macho, int slot, uint8_t *pageHashOut);

_Static_assert(ROOTHIDE_CODE_DIRECTORY_FLAG_ADHOC == CS_ADHOC,
               "RootHide signature policy and codesign flags must agree");

/*
If there are any unclosed file descriptors before the Dopamine process ends,
the "attempt to map verified executable page" panic may occur.
*/
static Fat *fat_init_for_writing(const char *filePath) {
    // Make sure the file already exists, otherwise ChOma will create a new file.
    if (access(filePath, W_OK) != 0) {
        JBLogError("Error: file is not writable: %s", filePath);
        return NULL;
    }

    MemoryStream *stream = file_stream_init_from_path(filePath, 0, FILE_STREAM_SIZE_AUTO, FILE_STREAM_FLAG_WRITABLE);
    if (!stream)
        return NULL;

    Fat *fat = fat_init_from_memory_stream(stream);
    if (!fat)
        memory_stream_free(stream);
    return fat;
}

static bool memory_stream_is_known_non_macho(MemoryStream *stream) {
    size_t streamSize = memory_stream_get_size(stream);
    if (streamSize == MEMORY_STREAM_SIZE_INVALID)
        return false;
    if (streamSize < sizeof(uint32_t))
        return true;

    uint8_t magic[sizeof(uint32_t)] = {0};
    if (memory_stream_read(stream, 0, sizeof(magic), magic) != 0)
        return false;
    return !roothide_signature_has_macho_magic(magic, sizeof(magic));
}

static int calc_cdhash(const uint8_t *cdBlob, size_t cdBlobSize, uint8_t hashType, void *cdhashOut) {
    if (!cdBlob || !cdhashOut || cdBlobSize < sizeof(uint64_t) || cdBlobSize > UINT32_MAX)
        return -1;

    // Longest possible buffer, truncated below because cdhash has a fixed size.
    uint8_t cdhash[CC_SHA384_DIGEST_LENGTH];

    switch (hashType) {
        case CS_HASHTYPE_SHA160_160: {
            CC_SHA1(cdBlob, (CC_LONG)cdBlobSize, cdhash);
            break;
        }

        case CS_HASHTYPE_SHA256_256:
        case CS_HASHTYPE_SHA256_160: {
            CC_SHA256(cdBlob, (CC_LONG)cdBlobSize, cdhash);
            break;
        }

        case CS_HASHTYPE_SHA384_384: {
            CC_SHA384(cdBlob, (CC_LONG)cdBlobSize, cdhash);
            break;
        }

        default:
            return -1;
    }

    memcpy(cdhashOut, cdhash, CS_CDHASH_LEN);
    return 0;
}

static MachO *fat_find_slice_by_offset(Fat *fat, uint64_t offset) {
    __block MachO *result = NULL;
    fat_enumerate_slices(fat, ^(MachO *macho, bool *stop) {
        if (macho->archDescriptor.offset == offset) {
            result = macho;
            *stop = true;
        }
    });
    return result;
}

int ensure_randomized_cdhash(const char *inputPath, void *cdhashOut) {
    return ensure_randomized_cdhash_for_slice(inputPath, -1, cdhashOut);
}

typedef enum {
    SIGNATURE_PREPARATION_FAILED = -1,
    SIGNATURE_PREPARATION_READY = 0,
    SIGNATURE_PREPARATION_NEEDS_WRITE = 1,
} signature_preparation_result_t;

static bool add_u64(uint64_t left, uint64_t right, uint64_t *resultOut) {
    if (right > UINT64_MAX - left)
        return false;
    *resultOut = left + right;
    return true;
}

static bool code_directory_hash_shape_is_valid(const CS_CodeDirectory *codeDir) {
    switch (codeDir->hashType) {
        case CS_HASHTYPE_SHA160_160:
            return codeDir->hashSize == CC_SHA1_DIGEST_LENGTH;
        case CS_HASHTYPE_SHA256_256:
            return codeDir->hashSize == CC_SHA256_DIGEST_LENGTH;
        case CS_HASHTYPE_SHA256_160:
            return codeDir->hashSize == CS_CDHASH_LEN;
        case CS_HASHTYPE_SHA384_384:
            return codeDir->hashSize == CC_SHA384_DIGEST_LENGTH;
        default:
            return false;
    }
}

static bool read_code_directory(CS_DecodedBlob *codeDirBlob,
                                CS_CodeDirectory *codeDirOut,
                                void **codeDirectoryBytesOut) {
    size_t codeDirectorySize = csd_blob_get_size(codeDirBlob);
    if (codeDirectorySize < offsetof(CS_CodeDirectory, scatterOffset)
        || codeDirectorySize > ROOTHIDE_SIGNATURE_MAX_BLOB_SIZE) {
        return false;
    }

    void *codeDirectoryBytes = malloc(codeDirectorySize);
    if (!codeDirectoryBytes)
        return false;
    if (csd_blob_read(codeDirBlob, 0, codeDirectorySize, codeDirectoryBytes) != 0) {
        free(codeDirectoryBytes);
        return false;
    }

    CS_CodeDirectory codeDir = {0};
    size_t headerSize = codeDirectorySize < sizeof(codeDir) ? codeDirectorySize : sizeof(codeDir);
    memcpy(&codeDir, codeDirectoryBytes, headerSize);
    CODE_DIRECTORY_APPLY_BYTE_ORDER(&codeDir, BIG_TO_HOST_APPLIER);

    bool valid = codeDir.magic == CSMAGIC_CODEDIRECTORY && codeDir.length <= codeDirectorySize
        && code_directory_hash_shape_is_valid(&codeDir)
        && roothide_signature_code_directory_layout_is_valid(codeDir.version,
                                                             codeDir.length,
                                                             codeDir.hashOffset,
                                                             codeDir.hashSize,
                                                             codeDir.nSpecialSlots,
                                                             codeDir.nCodeSlots,
                                                             codeDir.pageSize);
    if (!valid) {
        free(codeDirectoryBytes);
        return false;
    }

    *codeDirOut = codeDir;
    *codeDirectoryBytesOut = codeDirectoryBytes;
    return true;
}

static bool locate_code_directory(Fat *fat,
                                  MachO *macho,
                                  const struct linkedit_data_command *linkedit,
                                  const CS_SuperBlob *superblob,
                                  const CS_DecodedBlob *codeDirBlob,
                                  const void *codeDirectoryBytes,
                                  uint64_t *codeDirectoryOffsetOut) {
    uint32_t superblobCount = BIG_TO_HOST(superblob->count);
    uint32_t superblobLength = BIG_TO_HOST(superblob->length);
    size_t codeDirectorySize = csd_blob_get_size((CS_DecodedBlob *)codeDirBlob);

    for (uint32_t index = 0; index < superblobCount; index++) {
        CS_BlobIndex blobIndex = superblob->index[index];
        BLOB_INDEX_APPLY_BYTE_ORDER(&blobIndex, BIG_TO_HOST_APPLIER);
        if (blobIndex.type != codeDirBlob->type)
            continue;
        if (blobIndex.offset > superblobLength || codeDirectorySize > superblobLength - blobIndex.offset) {
            return false;
        }
        const uint8_t *candidate = (const uint8_t *)superblob + blobIndex.offset;
        if (memcmp(candidate, codeDirectoryBytes, codeDirectorySize) != 0)
            continue;

        uint64_t codeDirectoryOffset = macho->archDescriptor.offset;
        if (!add_u64(codeDirectoryOffset, linkedit->dataoff, &codeDirectoryOffset)
            || !add_u64(codeDirectoryOffset, blobIndex.offset, &codeDirectoryOffset)) {
            return false;
        }

        size_t fileSize = memory_stream_get_size(fat->stream);
        if (fileSize == MEMORY_STREAM_SIZE_INVALID || codeDirectoryOffset > fileSize
            || codeDirectorySize > fileSize - codeDirectoryOffset) {
            return false;
        }
        *codeDirectoryOffsetOut = codeDirectoryOffset;
        return true;
    }
    return false;
}

static signature_preparation_result_t prepare_signature_in_fat(Fat *fat,
                                                               const char *inputPath,
                                                               uint64_t sliceOffset,
                                                               bool mayWrite,
                                                               void *cdhashOut) {
    MachO *macho = sliceOffset == UINT64_MAX ? fat_find_preferred_slice(fat)
                                             : fat_find_slice_by_offset(fat, sliceOffset);
    if (!macho) {
        JBLogError("Error: failed to find preferred slice: %s", inputPath);
        errno = ENOEXEC;
        return SIGNATURE_PREPARATION_FAILED;
    }

    __block bool foundText = false;
    __block bool foundCodeSignature = false;
    __block uint64_t firstSectionOffset = 0;
    __block struct section_64 firstSection = {0};
    __block struct linkedit_data_command linkedit = {0};
    int enumerationStatus = macho_enumerate_load_commands(macho,
                                                          ^(struct load_command loadCommand,
                                                            uint64_t commandOffset,
                                                            void *command,
                                                            bool *stop) {
                                                              if (loadCommand.cmd == LC_SEGMENT_64 && !foundText) {
                                                                  if (loadCommand.cmdsize
                                                                      < sizeof(struct segment_command_64)
                                                                          + sizeof(struct section_64))
                                                                      return;

                                                                  struct segment_command_64 segment;
                                                                  memcpy(&segment, command, sizeof(segment));
                                                                  if (strncmp(segment.segname,
                                                                              "__TEXT",
                                                                              sizeof(segment.segname))
                                                                      != 0)
                                                                      return;
                                                                  if (segment.nsects == 0
                                                                      || segment.nsects
                                                                          > (loadCommand.cmdsize - sizeof(segment))
                                                                              / sizeof(struct section_64))
                                                                      return;

                                                                  memcpy(&firstSection,
                                                                         (uint8_t *)command + sizeof(segment),
                                                                         sizeof(firstSection));
                                                                  if (strncmp(firstSection.segname,
                                                                              "__TEXT",
                                                                              sizeof(firstSection.segname))
                                                                      != 0)
                                                                      return;
                                                                  firstSectionOffset = commandOffset + sizeof(segment);
                                                                  foundText = true;
                                                              }
                                                              if (loadCommand.cmd == LC_CODE_SIGNATURE
                                                                  && !foundCodeSignature) {
                                                                  if (loadCommand.cmdsize < sizeof(linkedit))
                                                                      return;
                                                                  memcpy(&linkedit, command, sizeof(linkedit));
                                                                  foundCodeSignature = true;
                                                              }
                                                              if (foundText && foundCodeSignature)
                                                                  *stop = true;
                                                          });
    if (enumerationStatus != 0 || !foundText || !foundCodeSignature || linkedit.datasize == 0
        || linkedit.datasize > ROOTHIDE_SIGNATURE_MAX_BLOB_SIZE) {
        JBLogError("Error: failed to parse macho file: %s", inputPath);
        errno = ENOEXEC;
        return SIGNATURE_PREPARATION_FAILED;
    }

    CS_SuperBlob *superblob = macho_read_code_signature(macho);
    if (!superblob || !roothide_signature_superblob_is_valid(superblob, linkedit.datasize)) {
        JBLogError("Error: invalid code signature: %s", inputPath);
        free(superblob);
        errno = ENOEXEC;
        return SIGNATURE_PREPARATION_FAILED;
    }

    CS_DecodedSuperBlob *decodedSuperblob = csd_superblob_decode(superblob);
    if (!decodedSuperblob || !csd_superblob_is_adhoc_signed(decodedSuperblob)) {
        JBLogError("Error: code signature is not an ad hoc wrapper: %s", inputPath);
        if (decodedSuperblob)
            csd_superblob_free(decodedSuperblob);
        free(superblob);
        errno = ENOTSUP;
        return SIGNATURE_PREPARATION_FAILED;
    }

    signature_preparation_result_t result = SIGNATURE_PREPARATION_FAILED;
    void *codeDirectoryBytes = NULL;
    do {
        CS_DecodedBlob *bestCDBlob = csd_superblob_find_best_code_directory(decodedSuperblob);
        if (!bestCDBlob)
            break;

        CS_CodeDirectory codeDir;
        if (!read_code_directory(bestCDBlob, &codeDir, &codeDirectoryBytes))
            break;

        roothide_team_id_state_t teamIDState = roothide_signature_team_id_state(codeDir.version,
                                                                                codeDir.teamOffset,
                                                                                codeDirectoryBytes,
                                                                                codeDir.length);
        if (teamIDState == ROOTHIDE_TEAM_ID_INVALID)
            break;
        bool hasTeamID = teamIDState == ROOTHIDE_TEAM_ID_PRESENT;
        bool usesSPTM = system_info_uses_sptm();

        uint64_t codeDirectoryOffset = 0;
        if (!locate_code_directory(fat,
                                   macho,
                                   &linkedit,
                                   superblob,
                                   bestCDBlob,
                                   codeDirectoryBytes,
                                   &codeDirectoryOffset))
            break;

        size_t markerOffset = sizeof(firstSection.segname) - sizeof(uint64_t);
        uint64_t currentJbrand = 0;
        uint64_t expectedJbrand = jbinfo(jbrand);
        memcpy(&currentJbrand, firstSection.segname + markerOffset, sizeof(currentJbrand));
        bool jbrandMatches = currentJbrand == expectedJbrand;
        uint32_t normalizedFlags = roothide_signature_normalize_code_directory_flags(codeDir.flags,
                                                                                     usesSPTM,
                                                                                     hasTeamID);

        if (!jbrandMatches && isRemovableBundlePath(inputPath) && !hasTrollstoreLiteMarker(inputPath)) {
            errno = EPERM;
            break;
        }

        uint8_t expectedPageHash[CC_SHA384_DIGEST_LENGTH] = {0};
        uint8_t storedPageHash[CC_SHA384_DIGEST_LENGTH] = {0};
        if (!code_directory_calculate_page_hash(&codeDir, macho, 0, expectedPageHash)
            || memory_stream_read(fat->stream,
                                  codeDirectoryOffset + codeDir.hashOffset,
                                  codeDir.hashSize,
                                  storedPageHash)
                != 0)
            break;

        bool firstPageHashMatches = memcmp(expectedPageHash, storedPageHash, codeDir.hashSize) == 0;
        if (!mayWrite
            && !roothide_signature_is_prepared(codeDir.flags,
                                               usesSPTM,
                                               hasTeamID,
                                               jbrandMatches,
                                               firstPageHashMatches)) {
            result = SIGNATURE_PREPARATION_NEEDS_WRITE;
            break;
        }

        if (mayWrite && !jbrandMatches) {
            memcpy(firstSection.segname + markerOffset, &expectedJbrand, sizeof(expectedJbrand));
            uint64_t sectionOffset = 0;
            if (!add_u64(macho->archDescriptor.offset, firstSectionOffset, &sectionOffset)
                || memory_stream_write(fat->stream, sectionOffset, sizeof(firstSection), &firstSection) != 0)
                break;
            jbrandMatches = true;

            if (!code_directory_calculate_page_hash(&codeDir, macho, 0, expectedPageHash))
                break;
        }

        if (mayWrite && codeDir.flags != normalizedFlags) {
            uint32_t encodedFlags = HOST_TO_BIG(normalizedFlags);
            if (memory_stream_write(fat->stream,
                                    codeDirectoryOffset + offsetof(CS_CodeDirectory, flags),
                                    sizeof(encodedFlags),
                                    &encodedFlags)
                != 0)
                break;
            codeDir.flags = normalizedFlags;
        }

        firstPageHashMatches = memcmp(expectedPageHash, storedPageHash, codeDir.hashSize) == 0;
        if (mayWrite && !firstPageHashMatches) {
            if (memory_stream_write(fat->stream,
                                    codeDirectoryOffset + codeDir.hashOffset,
                                    codeDir.hashSize,
                                    expectedPageHash)
                != 0)
                break;
            firstPageHashMatches = true;
        }

        if (!roothide_signature_is_prepared(codeDir.flags, usesSPTM, hasTeamID, jbrandMatches, firstPageHashMatches)) {
            result = SIGNATURE_PREPARATION_FAILED;
            break;
        }

        void *finalCodeDirectory = malloc(codeDir.length);
        if (!finalCodeDirectory)
            break;
        if (memory_stream_read(fat->stream, codeDirectoryOffset, codeDir.length, finalCodeDirectory) == 0
            && calc_cdhash(finalCodeDirectory, codeDir.length, codeDir.hashType, cdhashOut) == 0) {
            result = SIGNATURE_PREPARATION_READY;
        }
        free(finalCodeDirectory);
    } while (0);

    if (result == SIGNATURE_PREPARATION_FAILED && errno == 0)
        errno = ENOEXEC;
    free(codeDirectoryBytes);
    csd_superblob_free(decodedSuperblob);
    free(superblob);
    return result;
}

/* On iOS 16 and later:
1. If an executable has running processes, opening it with O_RDWR can prevent new
   executions (EBADMACHO) until those processes exit.
2. An executable opened with O_RDWR cannot be executed until the descriptor closes.
3. Opening certain binaries with O_RDWR can deadlock against concurrent reads or
   posix_spawn calls.
*/
int ensure_randomized_cdhash_for_slice(const char *inputPath, uint64_t offset, void *cdhashOut) {
    if (!inputPath || !cdhashOut) {
        errno = EINVAL;
        return -1;
    }

    errno = 0;
    MemoryStream *stream = file_stream_init_from_path(inputPath, 0, FILE_STREAM_SIZE_AUTO, 0);
    if (!stream) {
        JBLogError("Error: failed to init read-only fat: %s", inputPath);
        return -1;
    }
    if (memory_stream_is_known_non_macho(stream)) {
        memory_stream_free(stream);
        errno = ENOEXEC;
        return -1;
    }

    Fat *fat = fat_init_from_memory_stream(stream);
    if (!fat) {
        memory_stream_free(stream);
        JBLogError("Error: failed to init read-only fat: %s", inputPath);
        return -1;
    }
    signature_preparation_result_t result = prepare_signature_in_fat(fat, inputPath, offset, false, cdhashOut);
    fat_free(fat);
    if (result == SIGNATURE_PREPARATION_READY)
        return 0;
    if (result != SIGNATURE_PREPARATION_NEEDS_WRITE)
        return -1;

    fat = fat_init_for_writing(inputPath);
    if (!fat) {
        JBLogError("Error: failed to init writable fat: %s", inputPath);
        return -1;
    }
    errno = 0;
    result = prepare_signature_in_fat(fat, inputPath, offset, true, cdhashOut);
    fat_free(fat);
    return result == SIGNATURE_PREPARATION_READY ? 0 : -1;
}
