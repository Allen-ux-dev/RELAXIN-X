#import "RLXPostJailbreakActions.h"

#import "RLXPostJailbreakActionRunner.h"

#include <errno.h>

#if !TARGET_OS_SIMULATOR

#include <libjailbreak/jbroot.h>
#include <libjailbreak/util.h>

NSError *_Nullable RLXPostJailbreakRemove(NSString *_Nullable __strong *_Nullable failurePhase) {
    int rootStatus = RLXPostJailbreakLoadRoot(failurePhase);
    if (rootStatus != 0) {
        return RLXPostJailbreakActionExecutionError(RLXPostJailbreakActionRemoveJailbreak,
                                                    failurePhase && *failurePhase ? *failurePhase : @"jailbreak_root",
                                                    rootStatus,
                                                    nil);
    }

    const char *jbctlPath = JBROOT_PATH("/basebin/jbctl");
    if (!jbctlPath) {
        RLXPostJailbreakSetFailurePhase(failurePhase, @"removal_helper_path");
        return RLXPostJailbreakActionExecutionError(RLXPostJailbreakActionRemoveJailbreak,
                                                    @"removal_helper_path",
                                                    ENOENT,
                                                    nil);
    }

    __block pid_t helperPID = -1;
    int status = RLXPostJailbreakRunAsEffectiveRoot(
        ^int {
            return RLXPostJailbreakRunUnsandboxed(
                ^int {
                    int spawnStatus = exec_cmd_nowait(&helperPID, jbctlPath, "internal", "remove_jailbreak", NULL);
                    if (spawnStatus != 0) {
                        RLXPostJailbreakSetFailurePhase(failurePhase, @"removal_helper_spawn");
                        return RLXPostJailbreakSpawnStatus(spawnStatus);
                    }

                    int waitStatus = RLXPostJailbreakWaitStatus(cmd_wait_for_exit(helperPID));
                    if (waitStatus != 0) {
                        RLXPostJailbreakSetFailurePhase(failurePhase, @"removal_helper_exit");
                    }
                    return waitStatus;
                },
                failurePhase);
        },
        failurePhase);
    if (status != 0) {
        NSString *phase = failurePhase && *failurePhase ? *failurePhase : @"removal_helper";
        return RLXPostJailbreakActionExecutionError(RLXPostJailbreakActionRemoveJailbreak, phase, status, nil);
    }
    return nil;
}

#endif /* !TARGET_OS_SIMULATOR */
