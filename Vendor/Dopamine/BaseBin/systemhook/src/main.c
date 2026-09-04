#include "common.h"
#include "roothider.h"

#include <bsm/audit.h>
#include <crt_externs.h>
#include <errno.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <mach-o/getsect.h>
#include <mach/task_info.h>
#include <dlfcn.h>
#include <grp.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <syslog.h>
#include <unistd.h>
#include <paths.h>
#include <util.h>
#include <ptrauth.h>
#include <libjailbreak/jbclient_mach.h>
#include <libjailbreak/jbclient_xpc.h>
#include <libjailbreak/codesign.h>
#include <libjailbreak/jbroot.h>
#include <libjailbreak/setid_donor.h>
#include "../dyldhook/src/dyld_jbinfo.h"
#include "litehook.h"
#include "sandbox.h"
#include "private.h"

struct setid_donor_request {
    int controlFd;
    uid_t ruid;
    uid_t euid;
    uid_t svuid;
    gid_t rgid;
    gid_t egid;
    gid_t svgid;
    int groupCount;
    gid_t groups[NGROUPS_MAX];
};

static bool gSetidDonorProtocolActive = false;

static void setid_donor_error(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    if (gSetidDonorProtocolActive) {
        vdprintf(STDERR_FILENO, format, arguments);
        dprintf(STDERR_FILENO, "\n");
    } else {
        vsyslog(LOG_ERR, format, arguments);
    }
    va_end(arguments);
}

static int setid_donor_parse_u32(const char *value, uint32_t *resultOut) {
    if (!value || !resultOut || value[0] == '\0')
        return EINVAL;

    uint32_t result = 0;
    for (const char *cursor = value; *cursor != '\0'; cursor++) {
        if (*cursor < '0' || *cursor > '9')
            return EINVAL;
        uint32_t digit = (uint32_t)(*cursor - '0');
        if (result > (UINT32_MAX - digit) / 10)
            return ERANGE;
        result = result * 10 + digit;
    }
    *resultOut = result;
    return 0;
}

static int setid_donor_parse_request(int argc, char *const argv[], struct setid_donor_request *requestOut) {
    if (!argv || !requestOut || argc <= JB_SETID_DONOR_ARG_CONTROL_FD) {
        return EINVAL;
    }

    struct setid_donor_request request = {
        .controlFd = -1,
    };
    uint32_t value = 0;
    int status = setid_donor_parse_u32(argv[JB_SETID_DONOR_ARG_CONTROL_FD], &value);
    if (status != 0 || value > INT_MAX) {
        return status != 0 ? status : ERANGE;
    }
    request.controlFd = (int)value;
    *requestOut = request;

    if (argc < JB_SETID_DONOR_FIXED_ARGC)
        return EINVAL;

    status = setid_donor_parse_u32(argv[JB_SETID_DONOR_ARG_RUID], &value);
    if (status != 0)
        return status;
    request.ruid = (uid_t)value;

    status = setid_donor_parse_u32(argv[JB_SETID_DONOR_ARG_EUID], &value);
    if (status != 0)
        return status;
    request.euid = (uid_t)value;

    status = setid_donor_parse_u32(argv[JB_SETID_DONOR_ARG_SVUID], &value);
    if (status != 0)
        return status;
    request.svuid = (uid_t)value;

    status = setid_donor_parse_u32(argv[JB_SETID_DONOR_ARG_RGID], &value);
    if (status != 0)
        return status;
    request.rgid = (gid_t)value;

    status = setid_donor_parse_u32(argv[JB_SETID_DONOR_ARG_EGID], &value);
    if (status != 0)
        return status;
    request.egid = (gid_t)value;

    status = setid_donor_parse_u32(argv[JB_SETID_DONOR_ARG_SVGID], &value);
    if (status != 0)
        return status;
    request.svgid = (gid_t)value;

    status = setid_donor_parse_u32(argv[JB_SETID_DONOR_ARG_NGROUPS], &value);
    if (status != 0)
        return status;
    if (value == 0 || value > NGROUPS_MAX)
        return E2BIG;
    request.groupCount = (int)value;
    if (argc != JB_SETID_DONOR_FIXED_ARGC + request.groupCount) {
        return EINVAL;
    }

    for (int index = 0; index < request.groupCount; index++) {
        status = setid_donor_parse_u32(argv[JB_SETID_DONOR_FIXED_ARGC + index], &value);
        if (status != 0)
            return status;
        request.groups[index] = (gid_t)value;
    }

    *requestOut = request;
    return 0;
}

static int setid_donor_write_all(int fd, const void *buffer, size_t size) {
    const uint8_t *cursor = buffer;
    while (size > 0) {
        ssize_t written = write(fd, cursor, size);
        if (written < 0) {
            if (errno == EINTR)
                continue;
            return errno;
        }
        if (written == 0)
            return EIO;
        cursor += written;
        size -= (size_t)written;
    }
    return 0;
}

static int setid_donor_read_all(int fd, void *buffer, size_t size) {
    uint8_t *cursor = buffer;
    while (size > 0) {
        ssize_t received = read(fd, cursor, size);
        if (received < 0) {
            if (errno == EINTR)
                continue;
            return errno;
        }
        if (received == 0)
            return EPIPE;
        cursor += received;
        size -= (size_t)received;
    }
    return 0;
}

static int setid_donor_construct_identity(const struct setid_donor_request *request) {
    // Supplementary groups must be installed before the process drops root.
    // Each syscall derives a new credential through XNU; no hashed credential
    // field is modified in place.
    errno = 0;
    int result = setgroups(request->groupCount, request->groups);
    int syscallError = result == 0 ? 0 : errno;
    if (result != 0) {
        setid_donor_error(
                        "[setid-donor] phase=setgroups count=%d " "result=%d errno=%d",
                        request->groupCount,
                        result,
                        syscallError);
        return syscallError != 0 ? syscallError : EPERM;
    }

    // Install each saved ID as the temporary effective ID while the donor is
    // still root, then select the requested effective ID through the real or
    // saved-ID rule. This constructs mixed real/effective/saved credentials
    // entirely through XNU's public credential derivation path.
    errno = 0;
    result = setregid(request->rgid, request->svgid);
    syscallError = result == 0 ? 0 : errno;
    if (result != 0) {
        setid_donor_error(
                        "[setid-donor] phase=setregid rgid=%u svgid=%u " "result=%d errno=%d",
                        request->rgid,
                        request->svgid,
                        result,
                        syscallError);
        return syscallError != 0 ? syscallError : EPERM;
    }

    if (request->egid != request->svgid) {
        errno = 0;
        result = setegid(request->egid);
        syscallError = result == 0 ? 0 : errno;
        if (result != 0) {
            setid_donor_error(
                            "[setid-donor] phase=setegid egid=%u " "result=%d errno=%d",
                            request->egid,
                            result,
                            syscallError);
            return syscallError != 0 ? syscallError : EPERM;
        }
    }

    errno = 0;
    result = setreuid(request->ruid, request->svuid);
    syscallError = result == 0 ? 0 : errno;
    if (result != 0) {
        setid_donor_error(
                        "[setid-donor] phase=setreuid ruid=%u svuid=%u " "result=%d errno=%d",
                        request->ruid,
                        request->svuid,
                        result,
                        syscallError);
        return syscallError != 0 ? syscallError : EPERM;
    }

    if (request->euid != request->svuid) {
        errno = 0;
        result = seteuid(request->euid);
        syscallError = result == 0 ? 0 : errno;
        if (result != 0) {
            setid_donor_error(
                            "[setid-donor] phase=seteuid euid=%u " "result=%d errno=%d",
                            request->euid,
                            result,
                            syscallError);
            return syscallError != 0 ? syscallError : EPERM;
        }
    }

    return 0;
}

static int setid_donor_verify_identity(const struct setid_donor_request *request) {
    uid_t observedRuid = getuid();
    uid_t observedEuid = geteuid();
    gid_t observedRgid = getgid();
    gid_t observedEgid = getegid();
    if (observedRuid != request->ruid || observedEuid != request->euid || observedRgid != request->rgid
        || observedEgid != request->egid) {
        setid_donor_error(
                        "[setid-donor] phase=verify-ids status=%d " "expected=%u/%u/%u/%u observed=%u/%u/%u/%u",
                        EIO,
                        request->ruid,
                        request->euid,
                        request->rgid,
                        request->egid,
                        observedRuid,
                        observedEuid,
                        observedRgid,
                        observedEgid);
        return EIO;
    }

    gid_t groups[NGROUPS_MAX] = {0};
    int groupCount = getgroups(NGROUPS_MAX, groups);
    if (groupCount < 0) {
        int status = errno != 0 ? errno : EIO;
        setid_donor_error( "[setid-donor] phase=verify-groups status=%d " "getgroups_errno=%d", status, errno);
        return status;
    }
    if (groupCount != request->groupCount) {
        setid_donor_error(
                        "[setid-donor] phase=verify-groups status=%d " "expected_count=%d observed_count=%d",
                        EIO,
                        request->groupCount,
                        groupCount);
        return EIO;
    }
    for (int index = 0; index < groupCount; index++) {
        if (groups[index] == request->groups[index])
            continue;
        setid_donor_error(
                        "[setid-donor] phase=verify-groups status=%d " "mismatch_index=%d expected=%u observed=%u",
                        EIO,
                        index,
                        request->groups[index],
                        groups[index]);
        return EIO;
    }
    return 0;
}

__attribute__((noreturn)) static void setid_donor_run(int argc, char *const argv[]) {
    struct setid_donor_request request = {
        .controlFd = -1,
    };
    // Keep the donor protocol independent of launchd until it exits. In
    // particular, do not initialize syslog while launchd is synchronously
    // waiting for this process to become ready.
    gSetidDonorProtocolActive = true;

    int status = setid_donor_parse_request(argc, argv, &request);
    if (status != 0) {
        setid_donor_error( "[setid-donor] phase=parse pid=%d status=%d", getpid(), status);
    } else {
        status = setid_donor_construct_identity(&request);
    }
    if (status == 0)
        status = setid_donor_verify_identity(&request);

    if (request.controlFd >= 0) {
        struct jb_setid_donor_reply reply = {
            .magic = JB_SETID_DONOR_MAGIC,
            .status = status,
            .donorPid = status == 0 ? getpid() : 0,
        };
        int writeStatus = setid_donor_write_all(request.controlFd, &reply, sizeof(reply));
        if (writeStatus != 0) {
            setid_donor_error(
                            "[setid-donor] phase=reply pid=%d " "status=%d write_status=%d",
                            getpid(),
                            status,
                            writeStatus);
        }
        if (status == 0 && writeStatus != 0)
            status = writeStatus;

        if (status == 0) {
            struct jb_setid_donor_ack ack = {0};
            int ackStatus = setid_donor_read_all(request.controlFd, &ack, sizeof(ack));
            if (ackStatus == 0 && ack.magic != JB_SETID_DONOR_MAGIC) {
                ackStatus = EPROTO;
            }
            if (ackStatus == 0 && ack.status != 0) {
                ackStatus = ack.status;
            }
            if (ackStatus != 0) {
                setid_donor_error(
                                "[setid-donor] phase=ack pid=%d " "status=%d operation_status=%d",
                                getpid(),
                                ackStatus,
                                ack.status);
            }
            status = ackStatus;
        }
        close(request.controlFd);
    }

    if (status != 0) {
        setid_donor_error( "[setid-donor] phase=exit pid=%d status=%d exit_code=127", getpid(), status);
    }
    _exit(status == 0 ? 0 : 127);
}

static void setid_donor_run_if_requested(void) {
    int *argcPointer = _NSGetArgc();
    char ***argvPointer = _NSGetArgv();
    if (!argcPointer || !argvPointer || !*argvPointer || *argcPointer <= JB_SETID_DONOR_ARG_MARKER) {
        return;
    }

    char **argv = *argvPointer;
    if (!argv[JB_SETID_DONOR_ARG_MARKER] || strcmp(argv[JB_SETID_DONOR_ARG_MARKER], JB_SETID_DONOR_ARGUMENT) != 0) {
        return;
    }
    setid_donor_run(*argcPointer, argv);
}

bool gFullyDebugged = false;
static void *gLibSandboxHandle;
char *JB_BootUUID = NULL;
char *JB_RootPath = NULL;
char *get_jbroot(void) {
    return JB_RootPath;
}

static char gExecutablePath[PATH_MAX];
static int load_executable_path(void) {
    char executablePath[PATH_MAX];
    uint32_t bufsize = PATH_MAX;
    if (_NSGetExecutablePath(executablePath, &bufsize) == 0) {
        if (realpath(executablePath, gExecutablePath) != NULL)
            return 0;
        if (strlcpy(gExecutablePath, executablePath, sizeof(gExecutablePath)) < sizeof(gExecutablePath)) {
            return 0;
        }
    }
    return -1;
}

static bool setid_should_fail_closed_after_checkin_error(void) {
    if (getuid() != geteuid() || getgid() != getegid())
        return true;
    if (issetugid() != 0)
        return true;

    if (gExecutablePath[0] == '\0' && load_executable_path() != 0) {
        return false;
    }
    struct stat executableStat = {0};
    return stat(gExecutablePath, &executableStat) == 0 && S_ISREG(executableStat.st_mode)
        && (executableStat.st_mode & (S_ISUID | S_ISGID)) != 0;
}

static char *JB_SandboxExtensions = NULL;

static bool process_requires_mach_checkin(void) {
    const char *programName = getprogname();
    if (!programName)
        return false;

    return !strcmp(programName, "com.apple.WebKit.WebContent")
        || !strcmp(programName, "com.apple.WebKit.WebContent.CaptivePortal");
}

static int perform_process_checkin(void) {
    if (!process_requires_mach_checkin()) {
        return jbclient_process_checkin(&JB_RootPath, &JB_BootUUID, &JB_SandboxExtensions, &gFullyDebugged);
    }

    // WebContent's sandbox rejects the XPC request but permits the existing
    // launchd Mach protocol. Keep storage alive for the rest of the process.
    static struct jbserver_mach_msg_checkin_reply machCheckinStorage;
    int status = jbclient_mach_process_checkin(machCheckinStorage.jbRootPath,
                                               machCheckinStorage.bootUUID,
                                               machCheckinStorage.sandboxExtensions,
                                               &gFullyDebugged);
    if (status != 0)
        return status;

    JB_RootPath = machCheckinStorage.jbRootPath;
    JB_BootUUID = machCheckinStorage.bootUUID;
    JB_SandboxExtensions = machCheckinStorage.sandboxExtensions;
    return 0;
}

void consume_tokenized_sandbox_extensions(char *sandboxExtensions) {
    if (sandboxExtensions[0] == '\0')
        return;

    char *it = sandboxExtensions;
    char *last = sandboxExtensions;
    while (*(++it) != '\0') {
        if (*it == '|') {
            *it = '\0';
            sandbox_extension_consume(last);
            last = &it[1];
            *it = '|';
        }
    }
    sandbox_extension_consume(last);
}

void *(*sandbox_apply_orig)(void *) = NULL;
void *sandbox_apply_hook(void *a1) {
    void *r = sandbox_apply_orig(a1);
    consume_tokenized_sandbox_extensions(JB_SandboxExtensions);
    return r;
}

int dyld_hook_routine(void **dyld, int idx, void *hook, void **orig, uint16_t pacSalt) {
    if (!dyld)
        return -1;

    uint64_t dyldPacDiversifier = ((uint64_t)dyld & ~(0xFFFFull << 48)) | (0x63FAull << 48);
    void **dyldFuncPtrs = ptrauth_auth_data(*dyld, ptrauth_key_process_independent_data, dyldPacDiversifier);
    if (!dyldFuncPtrs)
        return -1;

    if (vm_protect(mach_task_self_,
                   (mach_vm_address_t)&dyldFuncPtrs[idx],
                   sizeof(void *),
                   false,
                   VM_PROT_READ | VM_PROT_WRITE)
        == 0) {
        uint64_t location = (uint64_t)&dyldFuncPtrs[idx];
        uint64_t pacDiversifier = (location & ~(0xFFFFull << 48)) | ((uint64_t)pacSalt << 48);

        *orig = ptrauth_auth_and_resign(dyldFuncPtrs[idx],
                                        ptrauth_key_process_independent_code,
                                        pacDiversifier,
                                        ptrauth_key_function_pointer,
                                        0);
        dyldFuncPtrs[idx] = ptrauth_auth_and_resign(hook,
                                                    ptrauth_key_function_pointer,
                                                    0,
                                                    ptrauth_key_process_independent_code,
                                                    pacDiversifier);
        vm_protect(mach_task_self_, (mach_vm_address_t)&dyldFuncPtrs[idx], sizeof(void *), false, VM_PROT_READ);
        return 0;
    }

    return -1;
}

// dlsym calls use __builtin_return_address(0) to determine what library called it
// Since we hook them, if we just call the original function on our own, the return address will always point to systemhook
// Therefore we must ensure the call to the original function is a tail call, which ensures that the stack and lr are restored and the compiler turns the call into a direct branch
// This is done via __attribute__((musttail)), this way __builtin_return_address(0) will point to the original calling library instead of systemhook

void *(*dyld_dlsym_orig)(void *dyld, void *handle, const char *name);
void *dyld_dlsym_hook(void *dyld, void *handle, const char *name) {
    if (handle == gLibSandboxHandle && !strcmp(name, "sandbox_apply")) {
        // We abuse the fact that libsystem_sandbox will call dlsym to get the sandbox_apply pointer here
        // Because we can just return a different pointer, we avoid doing instruction replacements
        return sandbox_apply_hook;
    }
    __attribute__((musttail)) return dyld_dlsym_orig(dyld, handle, name);
}

int ptrace_hook(int request, pid_t pid, caddr_t addr, int data) {
    int r = syscall(SYS_ptrace, request, pid, addr, data);

    // ptrace works on any process when the caller is unsandboxed,
    // but when the victim process does not have the get-task-allow entitlement,
    // it will fail to set the debug flags, therefore we patch ptrace to manually apply them
    // processes that have tweak injection enabled will have their debug flags already set
    // this is only relevant for ones that don't, e.g. if you disable tweak injection on an app via choicy
    // but still want to be able to attach a debugger to them
    if (r == 0 && (request == PT_ATTACHEXC || request == PT_ATTACH)) {
        jbclient_platform_set_process_debugged(pid, true);
        jbclient_platform_set_process_debugged(getpid(), true);
    }

    return r;
}

#ifndef __arm64e__

// The NECP subsystem is the only thing in the kernel that ever checks CS_VALID on userspace processes (Only on iOS >=16)
// In order to not break system functionality, we need to readd CS_VALID before any of these are invoked

int necp_match_policy_hook(uint8_t *parameters, size_t parameters_size, void *returned_result) {
    jbclient_cs_revalidate();
    return syscall(SYS_necp_match_policy, parameters, parameters_size, returned_result);
}

int necp_open_hook(int flags) {
    jbclient_cs_revalidate();
    return syscall(SYS_necp_open, flags);
}

int necp_client_action_hook(int necp_fd,
                            uint32_t action,
                            uuid_t client_id,
                            size_t client_id_len,
                            uint8_t *buffer,
                            size_t buffer_size) {
    jbclient_cs_revalidate();
    return syscall(SYS_necp_client_action, necp_fd, action, client_id, client_id_len, buffer, buffer_size);
}

int necp_session_open_hook(int flags) {
    jbclient_cs_revalidate();
    return syscall(SYS_necp_session_open, flags);
}

int necp_session_action_hook(int necp_fd,
                             uint32_t action,
                             uint8_t *in_buffer,
                             size_t in_buffer_length,
                             uint8_t *out_buffer,
                             size_t out_buffer_length) {
    jbclient_cs_revalidate();
    return syscall(SYS_necp_session_action,
                   necp_fd,
                   action,
                   in_buffer,
                   in_buffer_length,
                   out_buffer,
                   out_buffer_length);
}

// For the userland, there are multiple processes that will check CS_VALID for one reason or another
// As we inject system wide (or at least almost system wide), we can just patch the source of the info though - csops itself
// Additionally we also remove CS_DEBUGGED while we're at it, as on arm64e this also is not set and everything is fine
// That way we have unified behaviour between both arm64 and arm64e

int csops_hook(pid_t pid, unsigned int ops, void *useraddr, size_t usersize) {
    int rv = syscall(SYS_csops, pid, ops, useraddr, usersize);
    if (rv != 0)
        return rv;
    if (ops == CS_OPS_STATUS) {
        if (useraddr && usersize == sizeof(uint32_t)) {
            uint32_t *csflag = (uint32_t *)useraddr;
            *csflag |= CS_VALID;
            *csflag &= ~CS_DEBUGGED;
            if (pid == getpid() && gFullyDebugged) {
                *csflag |= CS_DEBUGGED;
            }
        }
    }
    return rv;
}

int csops_audittoken_hook(pid_t pid, unsigned int ops, void *useraddr, size_t usersize, audit_token_t *token) {
    int rv = syscall(SYS_csops_audittoken, pid, ops, useraddr, usersize, token);
    if (rv != 0)
        return rv;
    if (ops == CS_OPS_STATUS) {
        if (useraddr && usersize == sizeof(uint32_t)) {
            uint32_t *csflag = (uint32_t *)useraddr;
            *csflag |= CS_VALID;
            *csflag &= ~CS_DEBUGGED;
            if (pid == getpid() && gFullyDebugged) {
                *csflag |= CS_DEBUGGED;
            }
        }
    }
    return rv;
}

#endif

bool should_enable_tweaks(void) {
    if (access(JBROOT_PATH("/basebin/.safe_mode"), F_OK) == 0) {
        return false;
    }

    char *tweaksDisabledEnv = getenv("DISABLE_TWEAKS");
    if (tweaksDisabledEnv) {
        if (!strcmp(tweaksDisabledEnv, "1")) {
            return false;
        }
    }

    /******************* roothide specific ***************/
    const char *safeModeValue = getenv("_SafeMode");
    if (safeModeValue) {
        if (!strcmp(safeModeValue, "1")) {
            return false;
        }
    }
    const char *msSafeModeValue = getenv("_MSSafeMode");
    if (msSafeModeValue) {
        if (!strcmp(msSafeModeValue, "1")) {
            return false;
        }
    }
    /******************* roothide specific *************/

    const char *tweaksDisabledPathSuffixes[] = {
        // System binaries
        "/usr/libexec/xpcproxy",
    };
    for (size_t i = 0; i < sizeof(tweaksDisabledPathSuffixes) / sizeof(const char *); i++) {
        if (string_has_suffix(gExecutablePath, tweaksDisabledPathSuffixes[i]))
            return false;
    }

    // Jailbreak detection bypass tweaks can break either Relaxin app.
    if (is_relaxin_executable_path(gExecutablePath))
        return false;

    if (__builtin_available(iOS 16.0, *)) {
        // These seem to be problematic on iOS 16+ (dyld gets stuck in a weird way when opening TweakLoader)
        const char *iOS16TweaksDisabledPaths[] = {
            "/usr/libexec/logd",
            "/usr/sbin/notifyd",
            "/usr/libexec/usermanagerd",
        };
        for (size_t i = 0; i < sizeof(iOS16TweaksDisabledPaths) / sizeof(const char *); i++) {
            if (!strcmp(gExecutablePath, iOS16TweaksDisabledPaths[i]))
                return false;
        }
    }

    return true;
}

int __posix_spawn_hook(pid_t *restrict pid,
                       const char *restrict path,
                       struct _posix_spawn_args_desc *desc,
                       char *const argv[restrict],
                       char *const envp[restrict]) {
    return roothide_systemhook___posix_spawn_prehook(pid,
                                                     path,
                                                     desc,
                                                     argv,
                                                     envp,
                                                     (void *)roothide_systemhook___posix_spawn_posthook,
                                                     jbclient_trust_file_by_path,
                                                     jbclient_platform_set_process_debugged,
                                                     jbclient_jbsettings_get_double("jetsamMultiplier"));
}

int __posix_spawn_hook_with_filter(pid_t *restrict pid,
                                   const char *restrict path,
                                   char *const argv[restrict],
                                   char *const envp[restrict],
                                   struct _posix_spawn_args_desc *desc,
                                   int *ret) {
    *ret = roothide_systemhook___posix_spawn_prehook(pid,
                                                     path,
                                                     desc,
                                                     argv,
                                                     envp,
                                                     (void *)roothide_systemhook___posix_spawn_posthook,
                                                     jbclient_trust_file_by_path,
                                                     jbclient_platform_set_process_debugged,
                                                     jbclient_jbsettings_get_double("jetsamMultiplier"));
    return 1;
}

int __execve_hook(const char *path, char *const argv[], char *const envp[]) {
    return roothide_systemhook___execve_prehook(path,
                                                argv,
                                                envp,
                                                (void *)roothide_systemhook___execve_posthook,
                                                jbclient_trust_file_by_path);
}

const struct mach_header_64 *get_dyld_mach_header(void) {
    static const struct mach_header_64 *dyldMachHeader = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        task_dyld_info_data_t dyldInfo;
        uint32_t count = TASK_DYLD_INFO_COUNT;
        kern_return_t kr = task_info(mach_task_self_, TASK_DYLD_INFO, (task_info_t)&dyldInfo, &count);
        if (kr == KERN_SUCCESS) {
            struct dyld_all_image_infos *infos = (struct dyld_all_image_infos *)dyldInfo.all_image_info_addr;
            dyldMachHeader = (const struct mach_header_64 *)infos->dyldImageLoadAddress;
        }
    });
    return dyldMachHeader;
}

int parse_dyldhook_jbinfo(char **jbRootPathOut,
                          char **bootUUIDOut,
                          char **sandboxExtensionsOut,
                          bool *fullyDebuggedOut) {
    // Get dyld header
    const struct mach_header_64 *dyldHeader = get_dyld_mach_header();
    if (!dyldHeader)
        return -1;

    // Check if dyld LC_UUID contains dopamine magic
    uuid_t dyldUUID;
    if (!_dyld_get_image_uuid((const struct mach_header *)dyldHeader, dyldUUID))
        return -2;
    if (!string_has_prefix((char *)dyldUUID, "DOPA"))
        return -3;

    // If so, get __jbinfo section
    size_t jbInfoSize = 0;
    struct dyld_jbinfo *jbInfo = (struct dyld_jbinfo *)getsectiondata(dyldHeader, "__DATA", "__jbinfo", &jbInfoSize);
    if (!jbInfo)
        return -4;

    // Check if dyld already performed check-in
    if (jbInfo->state != DYLD_STATE_CHECKED_IN)
        return -5;

    // If so, parse jbinfo
    if (jbRootPathOut)
        *jbRootPathOut = jbInfo->jbRootPath;
    if (bootUUIDOut)
        *bootUUIDOut = jbInfo->bootUUID;
    if (sandboxExtensionsOut)
        *sandboxExtensionsOut = jbInfo->sandboxExtensions;
    if (fullyDebuggedOut)
        *fullyDebuggedOut = jbInfo->fullyDebugged;

    return 0;
}

__attribute__((constructor)) static void initializer(void) {
    setid_donor_run_if_requested();

    /***** roothide specific ****/
    roothide_init();
    /***** roothide specific ****/

    // Under normal circumstances, dyldhook will have already handled the check-in, so get the check-in information from the __jbinfo section
    // For more information on the check-in process, check the comments in dyldhook
    if (parse_dyldhook_jbinfo(&JB_RootPath, &JB_BootUUID, &JB_SandboxExtensions, &gFullyDebugged) != 0) {
        // If under any circumstances dyldhook has *not* performed a check-in, do it now
        // This code path is taken inside xpcproxy on iOS 16, because launchd apparently no longer passes it a bootstrap port
        int checkinStatus = perform_process_checkin();
        if (checkinStatus == 0) {
            consume_tokenized_sandbox_extensions(JB_SandboxExtensions);
        } else {
            // launchd may already have published a donor credential before a
            // later validation or reply step failed. Never let a setid or mixed
            // BSD-identity target enter main after a failed check-in.
            if (setid_should_fail_closed_after_checkin_error()) {
                _exit(126);
            }

            // Ordinary processes retain the historical behavior when neither
            // dyldhook nor SystemHook can check in.
            return;
        }
    }

    int executablePathStatus = load_executable_path();

    // Unset DYLD_INSERT_LIBRARIES, but only if systemhook itself is the only thing contained in it
    // Feeable attempt at making jailbreak detection harder
    const char *dyldInsertLibraries = getenv("DYLD_INSERT_LIBRARIES");
    if (dyldInsertLibraries) {
        if (!strcmp(dyldInsertLibraries, HOOK_DYLIB_PATH)) {
            unsetenv("DYLD_INSERT_LIBRARIES");
        }
    }

    // Apply posix_spawn / execve hooks
    if (__builtin_available(iOS 16.0, *)) {
        litehook_hook_function(__posix_spawn, __posix_spawn_hook);
        litehook_hook_function(__execve, __execve_hook);
    } else {
        // On iOS 15 there is a way to hook posix_spawn and execve without doing instruction replacements
        // Unfortunately Apple decided to remove these in iOS 16 :(

        void **posix_spawn_with_filter = litehook_find_dsc_symbol("/usr/lib/system/libsystem_kernel.dylib",
                                                                  "_posix_spawn_with_filter");
        void **execve_with_filter = litehook_find_dsc_symbol("/usr/lib/system/libsystem_kernel.dylib",
                                                             "_execve_with_filter");

        *posix_spawn_with_filter = __posix_spawn_hook_with_filter;
        *execve_with_filter = __execve_hook;
    }

    // Hook the dyld_shared_cache __fcntl to jump to the dyld __fcntl instead
    // This makes it so that library validation is also bypassed if someone calls fcntl in userspace to attach a signature manually
    void *dyld___fcntl = litehook_find_symbol(get_dyld_mach_header(), "___fcntl");
    extern int __fcntl(int fd, int op, ... /* arg */);
    litehook_hook_function(__fcntl, dyld___fcntl);

    // Initialize stuff neccessary for sandbox_apply hook
    gLibSandboxHandle = dlopen("/usr/lib/libsandbox.1.dylib", RTLD_FIRST | RTLD_LOCAL | RTLD_LAZY);
    sandbox_apply_orig = dlsym(gLibSandboxHandle, "sandbox_apply");

    // Apply dyld hooks
    void ***gDyldPtr = litehook_find_dsc_symbol("/usr/lib/system/libdyld.dylib", "__ZN5dyld45gDyldE");
    if (gDyldPtr) {
        // TODO: Maybe we can just rebind sandbox_apply instead?
        dyld_hook_routine(*gDyldPtr, 17, (void *)&dyld_dlsym_hook, (void **)&dyld_dlsym_orig, 0x839D);
    }

    /*************************** roothide *************************/
    /* after unsandboxing jbroot and applying library-trust-hook */
    roothide_init_with_checkin(JB_RootPath); // will hook dlopen* if necessary
    /*************************** roothide ************************/

#ifdef __arm64e__
    // Since pages have been modified in this process, we need to load forkfix to ensure forking will work
    // Optimization: If the process cannot fork at all due to sandbox, we don't need to do anything
    if (sandbox_check(getpid(), "process-fork", SANDBOX_CHECK_NO_REPORT, NULL) == 0) {
        dlopen(JBROOT_PATH("/basebin/forkfix.dylib"), RTLD_NOW);
    }
#endif

    if (executablePathStatus == 0) {
        // Load rootlesshooks / watchdoghook when neccessary
        if (!strcmp(gExecutablePath, "/usr/sbin/cfprefsd")
            || !strcmp(gExecutablePath, "/System/Library/CoreServices/SpringBoard.app/SpringBoard")
            || !strcmp(gExecutablePath, "/usr/libexec/lsd") || !strcmp(gExecutablePath, "/usr/libexec/runningboardd")) {
            dlopen(JBROOT_PATH("/basebin/roothidehooks.dylib"), RTLD_NOW);
        } else if (!strcmp(gExecutablePath, "/usr/libexec/watchdogd")) {
            dlopen(JBROOT_PATH("/basebin/watchdoghook.dylib"), RTLD_NOW);
        }

        // ptrace hook to allow attaching a debugger to processes that systemhook did not inject into
        // e.g. allows attaching debugserver to an app where tweak injection has been disabled via choicy
        // since we want to keep hooks minimal and debugserver is the only thing I can think of that would
        // call ptrace and expect it to allow invalid pages, we only hook it in debugserver
        // this check is a bit shit since we rely on the name of the binary, but who cares ¯\_(ツ)_/¯
        if (string_has_suffix(gExecutablePath, "/debugserver")) {
            litehook_hook_function(ptrace, ptrace_hook);
        }

#ifndef __arm64e__
        // On arm64, writing to executable pages removes CS_VALID from the csflags of the process
        // These hooks are neccessary to get the system to behave with this (since multiple system APIs check for CS_VALID and produce failures if it's not set)
        // They are ugly but needed
        litehook_hook_function(csops, csops_hook);
        litehook_hook_function(csops_audittoken, csops_audittoken_hook);
        if (__builtin_available(iOS 16.0, *)) {
            litehook_hook_function(necp_match_policy, necp_match_policy_hook);
            litehook_hook_function(necp_open, necp_open_hook);
            litehook_hook_function(necp_client_action, necp_client_action_hook);
            litehook_hook_function(necp_session_open, necp_session_open_hook);
            litehook_hook_function(necp_session_action, necp_session_action_hook);
        }
#endif

        /******************* roothide *****************/
        roothide_init_with_executable(gExecutablePath);
        /******************* roothide ****************/

        // Load tweaks if desired
        // We can hardcode /var/jb here since if it doesn't exist, loading TweakLoader.dylib is not going to work anyways
        if (should_enable_tweaks()) {
            const char *tweakLoaderPath = JBROOT_PATH("/usr/lib/TweakLoader.dylib");
            if (access(tweakLoaderPath, F_OK) == 0) {
                void *tweakLoaderHandle = dlopen(tweakLoaderPath, RTLD_NOW);
                if (tweakLoaderHandle != NULL) {
                    dlclose(tweakLoaderHandle);
                }
            }
        }

#ifndef __arm64e__
        // Feeable attempt at adding back CS_VALID
        jbclient_cs_revalidate();
#endif
    }
}
