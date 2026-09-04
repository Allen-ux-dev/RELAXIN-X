#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <errno.h>
#include <stdint.h>
#include <stdbool.h>
#include <choma/MachO.h>
#include <choma/Fat.h>
#include <choma/MemoryStream.h>
#include <choma/FileStream.h>
#include <choma/CSBlob.h>
#include <choma/CodeDirectory.h>
#include <choma/Util.h>
#include <choma/Host.h>
#include <mach-o/dyld.h>
#include "signatures.h"
#include "trustcache.h"
#include "log.h"

#include "roothider.h"
#include "roothider/signature_policy.h"

bool macho_is_mappable(MachO *macho) {
    // Determine if there is any case in which the macho could be mapped

    struct mach_header *header = macho_get_mach_header(macho);

    cpu_type_t cputype = header->cputype;
    cpu_subtype_t cpusubtype = header->cpusubtype;
    bool isLibrary = (header->filetype == MH_EXECUTE);

    if (cputype != CPU_TYPE_ARM64)
        return false;

#ifdef __arm64e__

    if (cpusubtype == (CPU_SUBTYPE_ARM64E | CPU_SUBTYPE_ARM64E_ABI_V2)) {
        // New arm64e ABI always mappable on arm64e
        return true;
    } else if (cpusubtype == CPU_SUBTYPE_ARM64E && isLibrary) {
        // Old arm64e ABI only mappable for libraries on arm64e iOS 14.6+
        return true;
    }

#endif

    // Anything arm64 is always mappable on all dvices
    if ((cpusubtype == CPU_SUBTYPE_ARM64_V8) || (cpusubtype == CPU_SUBTYPE_ARM64_ALL))
        return true;

    return false;
}

bool csd_superblob_is_adhoc_signed(CS_DecodedSuperBlob *superblob) {
    CS_DecodedBlob *wrapperBlob = csd_superblob_find_blob(superblob, CSSLOT_SIGNATURESLOT, NULL);
    if (wrapperBlob) {
        if (csd_blob_get_size(wrapperBlob) > 8) {
            return false;
        }
    }
    return true;
}

bool code_signature_calculate_adhoc_cdhash(CS_SuperBlob *superblob, size_t superblobSize, cdhash_t cdhashOut) {
    if (!cdhashOut || !roothide_signature_superblob_is_valid(superblob, superblobSize))
        return false;

    bool isAdhocSigned = false;
    CS_DecodedSuperBlob *decodedSuperblob = csd_superblob_decode(superblob);
    if (decodedSuperblob) {
        isAdhocSigned = csd_superblob_is_adhoc_signed(decodedSuperblob)
            && csd_superblob_calculate_best_cdhash(decodedSuperblob, cdhashOut, NULL) == 0;
        csd_superblob_free(decodedSuperblob);
    }

    return isAdhocSigned;
}

bool macho_calculate_adhoc_cdhash(MachO *macho, cdhash_t cdhashOut) {
    if (!macho || !cdhashOut)
        return false;

    uint32_t signatureSize = 0;
    if (macho_find_code_signature_bounds(macho, NULL, &signatureSize) != 0 || signatureSize == 0
        || signatureSize > ROOTHIDE_SIGNATURE_MAX_BLOB_SIZE)
        return false;

    bool isAdhocSigned = false;
    CS_SuperBlob *superblob = macho_read_code_signature(macho);
    if (superblob) {
        isAdhocSigned = code_signature_calculate_adhoc_cdhash(superblob, signatureSize, cdhashOut);
        free(superblob);
    }

    return isAdhocSigned;
}

int fat_collect_untrusted_cdhashes(Fat *fat, cdhash_t **cdhashesOut, uint32_t *cdhashCountOut) {
    if (!fat || !fat->stream || !fat->stream->context || !cdhashesOut || !cdhashCountOut)
        return EINVAL;
    *cdhashesOut = NULL;
    *cdhashCountOut = 0;

    /*************************************** roothide specfic *************************************/
    FileStreamContext *context = (FileStreamContext *)fat->stream->context;
    int fd = context->fd;

    static char __thread filepath[PATH_MAX] = {0};
    if (fcntl(fd, F_GETPATH, filepath) != 0) {
        JBLogError("Failed to get file path for fd %d", fd);
        return errno ? errno : EBADF;
    }
    if (string_has_prefix(filepath, "/private/preboot/Cryptexes/")) {
        return 0;
    }
    if (isRemovableBundlePath(filepath) && !hasTrollstoreLiteMarker(filepath)) {
        // ignore adhoc signed apps(removable system apps or other stuffs) which is not installed via tslite
        return 0;
    }
    /*************************************** roothide specfic *************************************/

    __block cdhash_t *cdhashes = NULL;
    __block uint32_t cdhashCount = 0;
    __block int collectionStatus = 0;
    fat_enumerate_slices(fat, ^(MachO *macho, bool *stop) {
        if (macho_is_mappable(macho)) {
            cdhash_t cdhash;
            if (macho_calculate_adhoc_cdhash(macho, cdhash)) {
                if (ensure_randomized_cdhash_for_slice(filepath, macho->archDescriptor.offset, cdhash) != 0) {
                    collectionStatus = errno ? errno : ENOEXEC;
                    JBLogError("Failed to prepare RootHide signature for %s", filepath);
                    *stop = true;
                    return;
                }
                if (is_cdhash_trustcached(cdhash))
                    return;

                cdhash_t *newCdhashes = realloc(cdhashes, (cdhashCount + 1) * sizeof(cdhash_t));
                if (!newCdhashes) {
                    collectionStatus = ENOMEM;
                    *stop = true;
                    return;
                }
                cdhashes = newCdhashes;
                memcpy(cdhashes[cdhashCount], cdhash, sizeof(cdhash));
                cdhashCount++;
            }
        }
    });

    if (collectionStatus != 0) {
        free(cdhashes);
        cdhashes = NULL;
        cdhashCount = 0;
    }
    *cdhashesOut = cdhashes;
    *cdhashCountOut = cdhashCount;
    return collectionStatus;
}

int file_collect_untrusted_cdhashes(int fd, cdhash_t **cdhashesOut, uint32_t *cdhashCountOut) {
    if (fd < 0 || !cdhashesOut || !cdhashCountOut)
        return EINVAL;
    *cdhashesOut = NULL;
    *cdhashCountOut = 0;

    MemoryStream *s = file_stream_init_from_file_descriptor(fd, 0, FILE_STREAM_SIZE_AUTO, 0);
    if (!s)
        return errno ? errno : EIO;

    Fat *fat = fat_init_from_memory_stream(s);
    if (!fat) {
        memory_stream_free(s);
        return ENOEXEC;
    }

    int status = fat_collect_untrusted_cdhashes(fat, cdhashesOut, cdhashCountOut);
    fat_free(fat);
    return status;
}

int file_collect_untrusted_cdhashes_by_path(const char *path, cdhash_t **cdhashesOut, uint32_t *cdhashCountOut) {
    if (!path || !cdhashesOut || !cdhashCountOut)
        return EINVAL;
    *cdhashesOut = NULL;
    *cdhashCountOut = 0;

    int fd = open(path, O_RDONLY);
    if (fd < 0)
        return errno ? errno : EIO;
    int status = file_collect_untrusted_cdhashes(fd, cdhashesOut, cdhashCountOut);
    close(fd);
    return status;
}
