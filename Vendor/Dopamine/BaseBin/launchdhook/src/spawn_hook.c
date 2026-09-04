#include <spawn.h>
#include "../systemhook/src/common.h"
#include "boomerang.h"
#include <libjailbreak/roothider/crashreporter.h>
#include <libjailbreak/util.h>
#include <libjailbreak/log.h>
#include <substrate.h>
#include <mach-o/dyld.h>
#include <sys/param.h>
#include <sys/mount.h>
extern char **environ;

extern int roothide_launchd_trust_executable(const char *path);
extern int roothide_launchd___posix_spawn_prehook(pid_t *restrict pidp,
                                                  const char *restrict path,
                                                  struct _posix_spawn_args_desc *desc,
                                                  char *const argv[restrict],
                                                  char *const envp[restrict]);
extern int roothide_launchd___posix_spawn_posthook(pid_t *restrict pidp,
                                                   const char *restrict path,
                                                   struct _posix_spawn_args_desc *desc,
                                                   char *const argv[restrict],
                                                   char *const envp[restrict]);

extern int platform_set_process_debugged(uint64_t pid, bool fullyDebugged);

extern bool gInEarlyBoot;

void early_boot_done(void) {
    gInEarlyBoot = false;
}

int __posix_spawn_orig_wrapper(pid_t *restrict pid,
                               const char *restrict path,
                               struct _posix_spawn_args_desc *desc,
                               char *const argv[restrict],
                               char *const envp[restrict]) {
    pid_t pidval = 0;
    if (!pid)
        pid = &pidval;

    // launchd's task exception port must not be inherited by the child.
    int crashReporterKey = crashreporter_pause();
    int r = __posix_spawn_orig(pid, path, desc, argv, envp);
    crashreporter_resume(crashReporterKey);

    return r;
}

int __posix_spawn_hook(pid_t *restrict pid,
                       const char *restrict path,
                       struct _posix_spawn_args_desc *desc,
                       char *const argv[restrict],
                       char *const envp[restrict]) {
    if (path) {
        char executablePath[1024];
        uint32_t bufsize = sizeof(executablePath);
        _NSGetExecutablePath(&executablePath[0], &bufsize);
        if (!strcmp(path, executablePath)) {
            // This spawn will perform a userspace reboot...
            // Instead of the ordinary hook, we want to reinsert this dylib
            // This has already been done in envp so we only need to call the original posix_spawn

            // We are back in "early boot" for the remainder of this launchd instance
            // Mainly so we don't lock up while spawning boomerang
            gInEarlyBoot = true;

            JBLogDebug("userspace reboot phase=prepare status=begin");

            // Before the userspace reboot, we want to stash the primitives into boomerang
            boomerang_stashPrimitives();
            JBLogDebug("userspace reboot phase=stash-primitives status=complete");

            // Fix Xcode debugging being broken after the userspace reboot
            unmount("/Developer", MNT_FORCE);

            // Always use environ instead of envp, as boomerang_stashPrimitives calls setenv
            // setenv / unsetenv can sometimes cause environ to get reallocated
            // In that case envp may point to garbage or be empty
            // Say goodbye to this process
            return __posix_spawn_orig_wrapper(pid, path, desc, argv, environ);
        }
    }

    // We can't support injection into processes that get spawned before the launchd XPC server is up
    // (Technically we could but there is little reason to, since it requires additional work)
    if (gInEarlyBoot) {
        if (!strcmp(path, "/usr/libexec/xpcproxy")) {
            // The spawned process being xpcproxy indicates that the launchd XPC server is up
            // All processes spawned including this one should be injected into
            early_boot_done();
        } else {
            return __posix_spawn_orig_wrapper(pid, path, desc, argv, envp);
        }
    }

    return posix_spawn_hook_shared(pid,
                                   path,
                                   desc,
                                   argv,
                                   envp,
                                   roothide_launchd___posix_spawn_posthook,
                                   roothide_launchd_trust_executable,
                                   platform_set_process_debugged,
                                   jbsetting(jetsamMultiplier));
}

void initSpawnHooks(void) {
    MSHookFunction(&__posix_spawn, (void *)roothide_launchd___posix_spawn_prehook, NULL);
}
