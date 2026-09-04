#include "jbserver_global.h"
#include "jbsettings.h"

#include <libjailbreak/codesign.h>
#include <libjailbreak/libjailbreak.h>
#include <errno.h>

static bool platform_domain_allowed(audit_token_t clientToken) {
    pid_t pid = audit_token_to_pid(clientToken);
    uint32_t csflags = 0;
    if (csops_audittoken(pid, CS_OPS_STATUS, &csflags, sizeof(csflags), &clientToken) != 0)
        return false;
    return (csflags & CS_PLATFORM_BINARY);
}

int platform_set_process_debugged(uint64_t pid, bool fullyDebugged) {
    uint64_t proc = proc_find(pid);
    if (!proc)
        return ESRCH;
    return cs_allow_invalid(proc, fullyDebugged);
}

struct jbserver_domain gPlatformDomain = {
	.permissionHandler = platform_domain_allowed,
	.actions = {
		// JBS_PLATFORM_SET_PROCESS_DEBUGGED
		{
			.handler = platform_set_process_debugged,
			.args = (jbserver_arg[]){
				{ .name = "pid", .type = JBS_TYPE_UINT64, .out = false },
				{ .name = "fully-debugged", .type = JBS_TYPE_BOOL, .out = false },
				{ 0 },
			},
		},
		// JBS_PLATFORM_JBSETTINGS_SET
		{
			.handler = jbsettings_set,
			.args = (jbserver_arg[]){
				{ .name = "key", .type = JBS_TYPE_STRING, .out = false },
				{ .name = "value", .type = JBS_TYPE_XPC_GENERIC, .out = false },
				{ 0 },
			},
		},
		// JBS_PLATFORM_SET_SYSTEMWIDE_DOMAIN_ENABLED
		{
			.handler = roothide_unsupport_request,
			.args = (jbserver_arg[]){
				{ .name = "enabled", .type = JBS_TYPE_BOOL, .out = false },
				{ 0 },
			},
		},
		// JBS_PLATFORM_TRUSTCACHE_QUERY_CDHASH
		{
			.handler = trustcache_nokcall_ipc_query_cdhash,
			.args = (jbserver_arg[]){
				{ .name = "cdhash", .type = JBS_TYPE_XPC_GENERIC, .out = false },
				{ .name = "found", .type = JBS_TYPE_BOOL, .out = true },
				{ 0 },
			},
		},
		// JBS_PLATFORM_TRUSTCACHE_OWNER_STATUS
		{
			.handler = trustcache_nokcall_ipc_owner_status,
			.args = (jbserver_arg[]){
				{ 0 },
			},
		},
		{ 0 },
	},
};
