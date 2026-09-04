#ifndef SIGNATURES_H
#define SIGNATURES_H

#include <stddef.h>

#include <choma/CodeDirectory.h>
#include <choma/Fat.h>

typedef enum {
    SIGNATURE_SOURCE_FILE,
    SIGNATURE_SOURCE_PROC,
} signature_source_t;

struct siginfo {
    signature_source_t source;
    fsignatures_t signature;
};

typedef uint8_t cdhash_t[CS_CDHASH_LEN];

bool csd_superblob_is_adhoc_signed(CS_DecodedSuperBlob *superblob);
bool macho_calculate_adhoc_cdhash(MachO *macho, cdhash_t cdhashOut);
bool code_signature_calculate_adhoc_cdhash(CS_SuperBlob *superblob, size_t superblobSize, cdhash_t cdhashOut);
int fat_collect_untrusted_cdhashes(Fat *fat, cdhash_t **cdhashesOut, uint32_t *cdhashCountOut);
int file_collect_untrusted_cdhashes(int fd, cdhash_t **cdhashesOut, uint32_t *cdhashCountOut);
int file_collect_untrusted_cdhashes_by_path(const char *path, cdhash_t **cdhashesOut, uint32_t *cdhashCountOut);
#endif
