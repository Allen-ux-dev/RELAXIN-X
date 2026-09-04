#include "signature_policy.h"

#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <string.h>

#define CODE_DIRECTORY_TEAM_ID_VERSION UINT32_C(0x00020200)
#define CSMAGIC_EMBEDDED_SIGNATURE UINT32_C(0xfade0cc0)
#define CSMAGIC_DETACHED_SIGNATURE UINT32_C(0xfade0cc1)

static size_t code_directory_header_size(uint32_t version) {
    if (version >= UINT32_C(0x00020600))
        return 0x70;
    if (version >= UINT32_C(0x00020500))
        return 0x60;
    if (version >= UINT32_C(0x00020400))
        return 0x58;
    if (version >= UINT32_C(0x00020300))
        return 0x40;
    if (version >= CODE_DIRECTORY_TEAM_ID_VERSION)
        return 0x34;
    if (version >= UINT32_C(0x00020100))
        return 0x30;
    return 0x2c;
}

static uint32_t read_big_endian_u32(const uint8_t *bytes) {
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) | ((uint32_t)bytes[2] << 8) | (uint32_t)bytes[3];
}

bool roothide_signature_has_macho_magic(const void *bytes, size_t size) {
    if (!bytes || size < sizeof(uint32_t))
        return false;

    uint32_t magic = 0;
    memcpy(&magic, bytes, sizeof(magic));
    switch (magic) {
        case MH_MAGIC:
        case MH_CIGAM:
        case MH_MAGIC_64:
        case MH_CIGAM_64:
        case FAT_MAGIC:
        case FAT_CIGAM:
        case FAT_MAGIC_64:
        case FAT_CIGAM_64:
            return true;
        default:
            return false;
    }
}

uint32_t roothide_signature_normalize_code_directory_flags(uint32_t flags, bool usesSPTM, bool hasTeamID) {
    if (usesSPTM && hasTeamID) {
        return flags & ~ROOTHIDE_CODE_DIRECTORY_FLAG_ADHOC;
    }
    return flags | ROOTHIDE_CODE_DIRECTORY_FLAG_ADHOC;
}

bool roothide_signature_is_prepared(uint32_t flags,
                                    bool usesSPTM,
                                    bool hasTeamID,
                                    bool jbrandMatches,
                                    bool firstPageHashMatches) {
    return flags == roothide_signature_normalize_code_directory_flags(flags, usesSPTM, hasTeamID) && jbrandMatches
        && firstPageHashMatches;
}

bool roothide_signature_code_directory_layout_is_valid(uint32_t version,
                                                       uint32_t length,
                                                       uint32_t hashOffset,
                                                       uint8_t hashSize,
                                                       uint32_t specialSlotCount,
                                                       uint32_t codeSlotCount,
                                                       uint8_t pageSize) {
    size_t headerSize = code_directory_header_size(version);
    if (length < headerSize || hashSize == 0 || (pageSize != 12 && pageSize != 14) || hashOffset < headerSize
        || hashOffset > length)
        return false;
    if (specialSlotCount > hashOffset / hashSize)
        return false;
    return codeSlotCount > 0 && codeSlotCount <= (length - hashOffset) / hashSize;
}

roothide_team_id_state_t roothide_signature_team_id_state(uint32_t codeDirectoryVersion,
                                                          uint32_t teamOffset,
                                                          const void *codeDirectoryBytes,
                                                          size_t codeDirectorySize) {
    if (codeDirectoryVersion < CODE_DIRECTORY_TEAM_ID_VERSION || teamOffset == 0) {
        return ROOTHIDE_TEAM_ID_ABSENT;
    }
    if (!codeDirectoryBytes || teamOffset < code_directory_header_size(codeDirectoryVersion)
        || teamOffset >= codeDirectorySize) {
        return ROOTHIDE_TEAM_ID_INVALID;
    }

    const uint8_t *teamID = (const uint8_t *)codeDirectoryBytes + teamOffset;
    size_t available = codeDirectorySize - teamOffset;
    const uint8_t *terminator = memchr(teamID, '\0', available);
    if (!terminator || terminator == teamID) {
        return ROOTHIDE_TEAM_ID_INVALID;
    }
    return ROOTHIDE_TEAM_ID_PRESENT;
}

bool roothide_signature_superblob_is_valid(const void *superblobBytes, size_t availableSize) {
    enum {
        superblobHeaderSize = 12,
        blobIndexSize = 8,
        genericBlobHeaderSize = 8,
    };

    if (!superblobBytes || availableSize < superblobHeaderSize || availableSize > ROOTHIDE_SIGNATURE_MAX_BLOB_SIZE) {
        return false;
    }

    const uint8_t *bytes = superblobBytes;
    uint32_t magic = read_big_endian_u32(bytes);
    uint32_t length = read_big_endian_u32(bytes + 4);
    uint32_t count = read_big_endian_u32(bytes + 8);
    if (magic != CSMAGIC_EMBEDDED_SIGNATURE && magic != CSMAGIC_DETACHED_SIGNATURE) {
        return false;
    }
    if (length < superblobHeaderSize || length > availableSize)
        return false;
    if (count > (length - superblobHeaderSize) / blobIndexSize)
        return false;

    size_t indexTableEnd = superblobHeaderSize + ((size_t)count * blobIndexSize);
    for (uint32_t index = 0; index < count; index++) {
        size_t indexOffset = superblobHeaderSize + ((size_t)index * blobIndexSize);
        uint32_t blobOffset = read_big_endian_u32(bytes + indexOffset + 4);
        if (blobOffset < indexTableEnd || blobOffset > length - genericBlobHeaderSize) {
            return false;
        }

        uint32_t blobLength = read_big_endian_u32(bytes + blobOffset + 4);
        if (blobLength < genericBlobHeaderSize || blobLength > length - blobOffset) {
            return false;
        }
    }
    return true;
}

bool roothide_signature_resolve_file_range(int64_t fileStart,
                                           uint64_t blobStart,
                                           size_t blobSize,
                                           uint64_t fileSize,
                                           uint64_t *resolvedStartOut) {
    if (!resolvedStartOut || fileStart < 0 || blobSize == 0 || blobSize > ROOTHIDE_SIGNATURE_MAX_BLOB_SIZE) {
        return false;
    }

    uint64_t unsignedFileStart = (uint64_t)fileStart;
    if (blobStart > UINT64_MAX - unsignedFileStart)
        return false;
    uint64_t resolvedStart = unsignedFileStart + blobStart;
    if (resolvedStart > INT64_MAX || resolvedStart > fileSize || blobSize > fileSize - resolvedStart) {
        return false;
    }

    *resolvedStartOut = resolvedStart;
    return true;
}
