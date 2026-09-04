#import "RLXPostJailbreakActions.h"

#import "RLXPostJailbreakActionRunner.h"

#include <errno.h>
#include <signal.h>
#include <unistd.h>

#include <libjailbreak/jbroot.h>
#include <libjailbreak/util.h>

#if !TARGET_OS_SIMULATOR

int RLXPostJailbreakRestartSpringBoard(NSString *_Nullable __strong *_Nullable failurePhase) {
    return RLXPostJailbreakRunAsEffectiveRoot(
        ^int {
            __block pid_t pid = 0;
            __block int spawnStatus = 0;
            __block int resumeStatus = 0;
            int scopeStatus = RLXPostJailbreakRunUnsandboxed(
                ^int {
                    const char *sbreloadPath = JBROOT_PATH("/usr/bin/sbreload");
                    if (!sbreloadPath) {
                        RLXPostJailbreakSetFailurePhase(failurePhase, @"sbreload_path");
                        spawnStatus = ENOENT;
                    } else {
                        errno = 0;
                        spawnStatus = RLXPostJailbreakSpawnStatus(exec_cmd_suspended(&pid, sbreloadPath, NULL));
                        if (spawnStatus != 0) {
                            RLXPostJailbreakSetFailurePhase(failurePhase, @"sbreload_spawn");
                        }
                    }

                    if (spawnStatus == 0 && kill(pid, SIGCONT) != 0) {
                        resumeStatus = errno ?: EIO;
                        RLXPostJailbreakSetFailurePhase(failurePhase, @"sbreload_resume");
                    }
                    return spawnStatus;
                },
                failurePhase);
            if (spawnStatus != 0) {
                return scopeStatus ?: spawnStatus;
            }

            errno = 0;
            int waitStatus = RLXPostJailbreakWaitStatus(cmd_wait_for_exit(pid));
            int fallbackStatus = 0;
            if (waitStatus != 0) {
                NSString *fallbackPhase = nil;
                fallbackStatus = RLXPostJailbreakRunUnsandboxed(
                    ^int {
                        killall("/usr/libexec/backboardd", SIGTERM);
                        return 0;
                    },
                    &fallbackPhase);
                if (fallbackStatus != 0 && failurePhase && !*failurePhase) {
                    *failurePhase = fallbackPhase;
                }
            }
            if (scopeStatus != 0) {
                return scopeStatus;
            }
            if (resumeStatus != 0) {
                return resumeStatus;
            }
            return fallbackStatus;
        },
        failurePhase);
}

#endif /* !TARGET_OS_SIMULATOR */
