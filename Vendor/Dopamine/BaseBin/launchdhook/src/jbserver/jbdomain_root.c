#include "jbserver_global.h"
#include <libjailbreak/jbserver_boomerang.h>
#include <libjailbreak/trustcache_nokcall_owner.h>
#include <libjailbreak/info.h>
#include <libjailbreak/kernel.h>
#include <libjailbreak/primitives.h>
#include <libjailbreak/util.h>
#include <libjailbreak/roothider.h>
#include <errno.h>

static bool root_domain_allowed(audit_token_t clientToken) {
    return (audit_token_to_euid(clientToken) == 0);
}

static int root_get_physrw(audit_token_t *clientToken,
                           bool singlePTE,
                           uint64_t pageTableVirtualAddress,
                           uint64_t *singlePTEAsidPtr) {
    return boomerang_get_physrw(clientToken, singlePTE, pageTableVirtualAddress, singlePTEAsidPtr);
}

static int root_sign_thread(audit_token_t *clientToken, mach_port_t threadPort) {
    return boomerang_sign_thread(clientToken, threadPort);
}

static int root_get_sysinfo(xpc_object_t *sysInfoOut) {
    return boomerang_get_sysinfo(sysInfoOut);
}

static int root_steal_ucred(audit_token_t *clientToken, uint64_t ucred, uint64_t *orgUcred) {
    uint64_t kernproc = proc_find(0);
    if (!kernproc)
        return ESRCH;
    uint64_t kern_ucred = proc_ucred(kernproc);
    if (!kern_ucred)
        return errno ? errno : EFAULT;
    if (!ucred) {
        // Passing 0 to this means kernel ucred
        ucred = kern_ucred;
    }

    pid_t pid = audit_token_to_pid(*clientToken);
    uint64_t proc = proc_find(pid);
    if (!proc)
        return ESRCH;

    *orgUcred = proc_ucred(proc);
    if (!*orgUcred)
        return errno ? errno : EFAULT;
    int status = proc_ucred_update(proc, ucred);
    if (status != 0)
        return status;

#ifndef __arm64e__
    if (ucred == kern_ucred) {
        // For some reason we need to borrow this from our process just for bind mount entitlement.
        uint64_t our_label = kread_ptr(*orgUcred + koffsetof(ucred, label));
        uint64_t our_slot = mac_label_get(our_label, 0);
        mac_label_set(kread_ptr(kern_ucred + koffsetof(ucred, label)), 0, our_slot);
    } else {
        // Revert it to what it should be
        mac_label_set(kread_ptr(kern_ucred + koffsetof(ucred, label)), 0, -1);
    }
#endif
    return 0;
}

static int root_set_mac_label(audit_token_t *clientToken, uint64_t slot, uint64_t newLabel, uint64_t *orgLabel) {
    if (slot >= 3)
        return -1;

    pid_t pid = audit_token_to_pid(*clientToken);
    uint64_t proc = proc_find(pid);
    if (!proc)
        return -1;
    uint64_t ucred = proc_ucred(proc);
    if (!ucred)
        return -1;

    uint64_t label = kread_ptr(ucred + koffsetof(ucred, label));

    *orgLabel = mac_label_get(label, slot);
    mac_label_set(label, slot, newLabel);

    return 0;
}

static int root_trustcache_info(xpc_object_t *infoOut) {
    if (!infoOut)
        return EINVAL;
    *infoOut = NULL;
    tcnm_entry *entries = NULL;
    uint32_t entryCount = 0;
    int status = tcno_copy_entries(&entries, &entryCount);
    if (status != 0)
        return status;

    xpc_object_t info = xpc_array_create_empty();
    xpc_object_t trustcache = xpc_dictionary_create_empty();
    xpc_object_t hashes = xpc_array_create_empty();
    if (!info || !trustcache || !hashes) {
        if (hashes)
            xpc_release(hashes);
        if (trustcache)
            xpc_release(trustcache);
        if (info)
            xpc_release(info);
        free(entries);
        return ENOMEM;
    }
    for (uint32_t index = 0; index < entryCount; index++) {
        xpc_array_set_data(hashes, XPC_ARRAY_APPEND, entries[index].hash, sizeof(entries[index].hash));
    }
    free(entries);
    xpc_dictionary_set_value(trustcache, "cdhashes", hashes);
    xpc_array_append_value(info, trustcache);
    xpc_release(hashes);
    xpc_release(trustcache);
    *infoOut = info;
    return 0;
}

int trustcache_nokcall_ipc_append_entries(xpc_object_t entriesData) {
    if (!entriesData || xpc_get_type(entriesData) != XPC_TYPE_DATA) {
        return EINVAL;
    }
    size_t size = xpc_data_get_length(entriesData);
    if (size == 0 || size % JBS_TRUSTCACHE_ENTRY_SIZE != 0) {
        return EINVAL;
    }
    size_t entryCount = size / JBS_TRUSTCACHE_ENTRY_SIZE;
    if (entryCount > JBS_TRUSTCACHE_MAX_APPEND_ENTRIES) {
        return E2BIG;
    }
    const void *entries = xpc_data_get_bytes_ptr(entriesData);
    if (!entries)
        return EINVAL;
    _Static_assert(sizeof(tcnm_entry) == JBS_TRUSTCACHE_ENTRY_SIZE, "trust cache IPC entry size must stay stable");
    return tcno_append(entries, (uint32_t)entryCount);
}

int trustcache_nokcall_ipc_query_cdhash(xpc_object_t hashData, bool *foundOut) {
    if (!foundOut)
        return EINVAL;
    *foundOut = false;
    if (!hashData || xpc_get_type(hashData) != XPC_TYPE_DATA
        || xpc_data_get_length(hashData) != JBS_TRUSTCACHE_HASH_SIZE) {
        return EINVAL;
    }
    const uint8_t *hash = xpc_data_get_bytes_ptr(hashData);
    return hash ? tcno_query(hash, foundOut) : EINVAL;
}

int trustcache_nokcall_ipc_owner_status(void) {
    return tcno_status();
}

struct jbserver_domain gRootDomain = {
	.permissionHandler = root_domain_allowed,
	.actions = {
		// JBS_ROOT_GET_PHYSRW
		{
			.handler = root_get_physrw,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "single-pte", .type = JBS_TYPE_BOOL, .out = false },
				{ .name = "single-pte-page-table", .type = JBS_TYPE_UINT64, .out = false },
				{ .name = "single-pte-asid-ptr", .type = JBS_TYPE_UINT64, .out = true },
				{ 0 },
			},
		},
		// JBS_ROOT_SIGN_THREAD
		{
			.handler = root_sign_thread,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "thread-port", .type = JBS_TYPE_UINT64, .out = false },
				{ 0 },
			},
		},
		// JBS_ROOT_GET_SYSINFO
		{
			.handler = root_get_sysinfo,
			.args = (jbserver_arg[]){
				{ .name = "sysinfo", .type = JBS_TYPE_DICTIONARY, .out = true },
				{ 0 },
			},
		},
		// JBS_ROOT_STEAL_UCRED
		{
			.handler = root_steal_ucred,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "ucred", .type = JBS_TYPE_UINT64, .out = false },
				{ .name = "org-ucred", .type = JBS_TYPE_UINT64, .out = true },
				{ 0 },
			},
		},
		// JBS_ROOT_SET_MAC_LABEL
		{
			.handler = root_set_mac_label,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "slot", .type = JBS_TYPE_UINT64, .out = false },
				{ .name = "label", .type = JBS_TYPE_UINT64, .out = false },
				{ .name = "org-label", .type = JBS_TYPE_UINT64, .out = true },
				{ 0 },
			},
		},
		// JBS_ROOT_TRUSTCACHE_INFO
		{
			.handler = root_trustcache_info,
			.args = (jbserver_arg[]){
				{ .name = "tc-info", .type = JBS_TYPE_ARRAY, .out = true },
				{ 0 },
			},
		},
		// JBS_ROOT_TRUSTCACHE_APPEND_ENTRIES
		{
			.handler = trustcache_nokcall_ipc_append_entries,
			.args = (jbserver_arg[]){
				{ .name = "entries", .type = JBS_TYPE_XPC_GENERIC, .out = false },
				{ 0 },
			},
		},
		// JBS_ROOT_TRUSTCACHE_QUERY_CDHASH
		{
			.handler = trustcache_nokcall_ipc_query_cdhash,
			.args = (jbserver_arg[]){
				{ .name = "cdhash", .type = JBS_TYPE_XPC_GENERIC, .out = false },
				{ .name = "found", .type = JBS_TYPE_BOOL, .out = true },
				{ 0 },
			},
		},
		// JBS_ROOT_TRUSTCACHE_OWNER_STATUS
		{
			.handler = trustcache_nokcall_ipc_owner_status,
			.args = (jbserver_arg[]){
				{ 0 },
			},
		},
		{ 0 },
	},
};
