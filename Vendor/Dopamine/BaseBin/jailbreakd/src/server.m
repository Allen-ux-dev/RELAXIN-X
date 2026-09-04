#include <Foundation/Foundation.h>
#include <bsm/libbsm.h>
#include <errno.h>
#include <libproc.h>

#include <libjailbreak/libjailbreak.h>
#include <libjailbreak/log.h>
#include <libjailbreak/roothider.h>

void jailbreakd_reply_message(xpc_object_t reply) {
    int err = xpc_pipe_routine_reply(reply);
    if (err != 0) {
        JBLogError("Error %d sending response", err);
    }
}

void jailbreakd_received_message(mach_port_t port) {
    @autoreleasepool {
        xpc_object_t message = nil;
        int err = xpc_pipe_receive(port, &message);
        if (err != 0) {
            JBLogError("xpc_pipe_receive error %d", err);
            return;
        }

        xpc_object_t reply = xpc_dictionary_create_reply(message);

        JBD_MESSAGE_ID msgId = xpc_dictionary_get_uint64(message, "id");

        if (xpc_get_type(message) == XPC_TYPE_DICTIONARY) {
            audit_token_t auditToken = {0};
            xpc_dictionary_get_audit_token(message, &auditToken);
            uid_t clientUid = audit_token_to_euid(auditToken);
            pid_t clientPid = audit_token_to_pid(auditToken);

            switch (msgId) {
                case JBD_MSG_SPINLOCK_FIX_ONLY: {
                    pid_t pid = xpc_dictionary_get_int64(message, "pid");
                    pid_t ppid = proc_get_ppid(pid);
                    int64_t result = ENOTSUP;
                    JBLogError(
                        "spinlock fix rejected: policy=stock-dyld " "client=%d child=%d parent=%d path=%s status=%d",
                        clientPid,
                        pid,
                        ppid,
                        proc_get_path(pid, NULL),
                        ENOTSUP);
                    xpc_dictionary_set_int64(reply, "result", result);
                    break;
                }

                case JBD_MSG_SPAWN_PATCH_CHILD: {
                    int64_t result = 0;
                    pid_t pid = xpc_dictionary_get_int64(message, "pid");
                    bool resume = xpc_dictionary_get_bool(message, "resume");
                    pid_t ppid = proc_get_ppid(pid);
                    if (ppid == clientPid) {
                        if (ppid == 1 && resume == false) {
                            //`frida -f` sucks with proc_patch_dyld on ios15
                            result = proc_patch_csflags(pid);
                        } else if (roothide_patch_proc(pid) == 0) {
                            if (resume)
                                kill(pid, SIGCONT);
                        } else {
                            JBLogError("spawn patch failed: %d", pid);
                            result = -1;
                        }
                    } else {
                        JBLogError("spawn patch denied: %d", pid);
                        result = -1;
                    }
                    xpc_dictionary_set_int64(reply, "result", result);
                    break;
                }

                case JBD_MSG_SPAWN_EXEC_START: {
                    bool resume = xpc_dictionary_get_bool(message, "resume");
                    int64_t result = spawnExecPatchAdd(clientPid, resume);
                    xpc_dictionary_set_int64(reply, "result", result);
                    break;
                }

                case JBD_MSG_SPAWN_EXEC_CANCEL: {
                    int64_t result = spawnExecPatchDel(clientPid);
                    xpc_dictionary_set_int64(reply, "result", result);
                    break;
                }

                case JBD_MSG_EXEC_TRACE_START: {
                    //dead lock: jbd->ptrace->kernel->amfi port->launchd->spawn amfid->jdb
                    dispatch_async(dispatch_get_global_queue(0, 0), ^{
                        int64_t result = -1;
                        uint64_t traced = xpc_dictionary_get_uint64(message, "traced");
                        result = execTraceProcess(clientPid, traced);
                        xpc_dictionary_set_int64(reply, "result", result);
                        jailbreakd_reply_message(reply);
                    });
                    reply = nil; //reply later
                    break;
                }

                case JBD_MSG_EXEC_TRACE_CANCEL: {
                    int64_t result = -1;
                    uint64_t detached = xpc_dictionary_get_uint64(message, "detached");
                    result = execTraceCancel(clientPid, detached);
                    xpc_dictionary_set_int64(reply, "result", result);
                    break;
                }

                case JBD_MSG_TEST_CALL: {
                    int value = xpc_dictionary_get_int64(message, "value");
                    xpc_dictionary_set_int64(reply, "result", value * 2);

                    if (clientUid == 0) {
                        abort(); // crashreporter test
                    }

                    break;
                }
            }
        }
        if (reply) {
            jailbreakd_reply_message(reply);
        }
    }
}
