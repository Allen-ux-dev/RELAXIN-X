#ifndef ROOTHIDE_SIGNATURE_POLICY_H
#define ROOTHIDE_SIGNATURE_POLICY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define ROOTHIDE_CODE_DIRECTORY_FLAG_ADHOC UINT32_C(0x00000002)
#define ROOTHIDE_SIGNATURE_MAX_BLOB_SIZE (40U * 1024U * 1024U)

typedef enum {
    ROOTHIDE_TEAM_ID_INVALID = -1,
    ROOTHIDE_TEAM_ID_ABSENT = 0,
    ROOTHIDE_TEAM_ID_PRESENT = 1,
} roothide_team_id_state_t;

bool roothide_signature_has_macho_magic(const void *bytes, size_t size);

uint32_t roothide_signature_normalize_code_directory_flags(uint32_t flags, bool usesSPTM, bool hasTeamID);

bool roothide_signature_is_prepared(uint32_t flags,
                                    bool usesSPTM,
                                    bool hasTeamID,
                                    bool jbrandMatches,
                                    bool firstPageHashMatches);

bool roothide_signature_code_directory_layout_is_valid(uint32_t version,
                                                       uint32_t length,
                                                       uint32_t hashOffset,
                                                       uint8_t hashSize,
                                                       uint32_t specialSlotCount,
                                                       uint32_t codeSlotCount,
                                                       uint8_t pageSize);

roothide_team_id_state_t roothide_signature_team_id_state(uint32_t codeDirectoryVersion,
                                                          uint32_t teamOffset,
                                                          const void *codeDirectoryBytes,
                                                          size_t codeDirectorySize);

bool roothide_signature_superblob_is_valid(const void *superblobBytes, size_t availableSize);

bool roothide_signature_resolve_file_range(int64_t fileStart,
                                           uint64_t blobStart,
                                           size_t blobSize,
                                           uint64_t fileSize,
                                           uint64_t *resolvedStartOut);

#endif
