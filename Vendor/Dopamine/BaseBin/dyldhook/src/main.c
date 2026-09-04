#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sandbox.h>
#include <libjailbreak/jbclient_mach.h>

#include "dyld.h"
#include "dyld_jbinfo.h"

#ifndef DEBUG
#define DEBUG 0
#endif

#if DEBUG
#define DYLDHookDebug(...) _simple_dprintf(STDERR_FILENO, __VA_ARGS__)
#else
#define DYLDHookDebug(...) do { } while (0)
#endif

#define DYLDHookError(...) _simple_dprintf(STDERR_FILENO, __VA_ARGS__)

__attribute__((section("__DATA,__jbinfo"))) static char jbinfoSection[0x4000];
#define jbInfo ((struct dyld_jbinfo *)&jbinfoSection[0])

bool gDyldhookInitDone = false;

bool jbinfo_is_checked_in(void) {
    return jbInfo->state == DYLD_STATE_CHECKED_IN;
}

char *jbinfo_get_jbroot(void) {
    return jbInfo->jbRootPath;
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

void dyldhook_perform_checkin(void) {
    struct jbserver_mach_msg_checkin_reply *replyPtr; // Only for sizeof macro

    char *jbRootPathPtr = &jbInfo->data[0];
    char *bootUUIDPtr = &jbInfo->data[sizeof(replyPtr->jbRootPath)];
    char *sandboxExtensionsPtr = &jbInfo->data[sizeof(replyPtr->jbRootPath) + sizeof(replyPtr->bootUUID)];

    // Tell jbserver (in launchd) that this process exists
    // This will, amongst other things, disable page validation, which allows instruction hooks to be applied later
    if (jbclient_mach_process_checkin(jbRootPathPtr, bootUUIDPtr, sandboxExtensionsPtr, &jbInfo->fullyDebugged) == 0) {
        DYLDHookDebug("dyldhook: checkin complete\n");
        consume_tokenized_sandbox_extensions(sandboxExtensionsPtr);
        jbInfo->jbRootPath = jbRootPathPtr;
        jbInfo->bootUUID = bootUUIDPtr;
        jbInfo->sandboxExtensions = sandboxExtensionsPtr;
        jbInfo->state = DYLD_STATE_CHECKED_IN;
    } else {
        DYLDHookError("dyldhook: checkin failed\n");
    }
}

mach_port_t mach_task_self_ = MACH_PORT_NULL;
void mach_init_4real(void) {
    // Because mach_init has a "call once" mechanism, we can just call it ourselves without breaking anything in the later dyld flow
    // This allows us to have a proper pthread descriptor which fixes a whole bunch of stuff
    extern void mach_init(void);
    mach_init(); // This sets up mach_task_self_ in dyld but we can't get it since getting a global from dyld is not implemented in MachOMerger

    mach_task_self_ = task_self_trap();
    // Apparently task_self_trap increases the refcount of the task so we call deallocate again to decrease it
    mach_port_deallocate(mach_task_self_, mach_task_self_);
}

void dyldhook_init(uintptr_t kernelParams) {
    extern void dyldhook_init_roothide(uintptr_t);
    dyldhook_init_roothide(kernelParams);

    mach_init_4real();

    // If we are in launchd, bail out
    if (getpid() == 1) {
        return;
    }

    // Walk kernelParams to get envp
    uintptr_t argc = *(uintptr_t *)(kernelParams + sizeof(void *));
    char **envp = (char **)(kernelParams + sizeof(void *) + sizeof(argc) + (sizeof(const char *) * argc)
                            + sizeof(void *));

    // If DYLD_INSERT_LIBRARIES is not set or does not contain systemhook, bail out
    const char *insertLibrariesVar = _simple_getenv(envp, "DYLD_INSERT_LIBRARIES");
    if (!insertLibrariesVar) {
        DYLDHookDebug("dyldhook: checkin skipped reason=missing-insert-libraries\n");
        return;
    }
    if (!strstr(insertLibrariesVar, "/systemhook")) {
        DYLDHookDebug("dyldhook: checkin skipped reason=missing-systemhook\n");
        return;
    }

    // If all is well, do check-in right here before dyld_start!
    dyldhook_perform_checkin();
}
