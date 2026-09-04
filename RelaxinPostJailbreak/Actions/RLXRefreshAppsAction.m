#import "RLXPostJailbreakActions.h"

#import "RLXPostJailbreakActionRunner.h"

#include <errno.h>

#include <libjailbreak/jbroot.h>
#include <libjailbreak/util.h>

#if !TARGET_OS_SIMULATOR

int RLXPostJailbreakRefreshApps(NSString *_Nullable __strong *_Nullable failurePhase) {
    return RLXPostJailbreakRunAsEffectiveRoot(
        ^int {
            return RLXPostJailbreakRunUnsandboxed(
                ^int {
                    const char *uicachePath = JBROOT_PATH("/usr/bin/uicache");
                    if (!uicachePath) {
                        RLXPostJailbreakSetFailurePhase(failurePhase, @"uicache_path");
                        return ENOENT;
                    }

                    errno = 0;
                    int status = RLXPostJailbreakWaitStatus(exec_cmd(uicachePath, "-a", NULL));
                    if (status != 0) {
                        RLXPostJailbreakSetFailurePhase(failurePhase, @"uicache");
                    }
                    return status;
                },
                failurePhase);
        },
        failurePhase);
}

#endif /* !TARGET_OS_SIMULATOR */
