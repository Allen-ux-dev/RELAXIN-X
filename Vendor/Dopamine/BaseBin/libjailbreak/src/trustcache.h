#ifndef TRUSTCACHE_H
#define TRUSTCACHE_H

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "trustcache_structs.h"

int trustcache_list_insert(uint64_t tcKaddr);

/* These APIs are append-only; they never replace entries by logical UUID. */
int jb_trustcache_append_entries(const struct trustcache_entry_v1 *entries, uint32_t entryCount);
int jb_trustcache_append_entry(trustcache_entry_v1 entry);
int jb_trustcache_append_cdhashes(const cdhash_t *hashes, uint32_t hashCount);

/* Compatibility spellings. They retain the same append-only contract. */
int jb_trustcache_add_entries(struct trustcache_entry_v1 *entries, uint32_t entryCount);
int jb_trustcache_add_entry(trustcache_entry_v1 entry);
int jb_trustcache_add_cdhashes(cdhash_t *hashes, uint32_t hashCount);

void jb_trustcache_debug_print(FILE *f);

/*
 * Legacy replace-by-UUID upload. No-kcall mode returns EOPNOTSUPP before any
 * protected/kernel write; callers must use the append-only APIs above.
 */
int trustcache_file_upload(trustcache_file_v1 *tc);
int trustcache_file_upload_with_uuid(trustcache_file_v1 *tc, uuid_t uuid);
int trustcache_file_build_from_cdhashes(cdhash_t *CDHashes, uint32_t CDHashCount, trustcache_file_v1 **tcOut);
int trustcache_file_build_from_path(const char *filePath, trustcache_file_v1 **tcOut);

bool is_cdhash_in_trustcache(uint64_t tcKaddr, cdhash_t CDHash);
bool is_cdhash_trustcached(cdhash_t CDHash);
int trustcache_query_cdhash(cdhash_t CDHash, bool *foundOut);

#endif
