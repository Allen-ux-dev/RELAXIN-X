#import "RLXPostJailbreakActions.h"

#import "RLXPostJailbreakActionRunner.h"
#import "../BootLogo/RLXBootLogoWriter.h"

#include <errno.h>
#include <signal.h>
#include <unistd.h>

#include <libjailbreak/jbroot.h>
#include <libjailbreak/util.h>

#if !TARGET_OS_SIMULATOR

NSError *_Nullable RLXPostJailbreakRestartUserspace(NSBundle *resourceBundle, BOOL darkAppearance) {
    __block NSString *failurePhase = nil;
    __block NSError *underlyingError = nil;
    int status = RLXPostJailbreakRunAsEffectiveRoot(
        ^int {
            return RLXPostJailbreakRunUnsandboxed(
                ^int {
                    NSError *bootLogoError = [RLXBootLogoWriter writeBootLogoForDarkAppearance:darkAppearance
                                                                                resourceBundle:resourceBundle];
                    if (bootLogoError) {
                        underlyingError = bootLogoError;
                        NSString *phase = bootLogoError.userInfo[RLXBootLogoWriterFailurePhaseErrorKey] ?: @"update";
                        RLXPostJailbreakSetFailurePhase(&failurePhase, [@"boot_logo_" stringByAppendingString:phase]);
                        return (int)(bootLogoError.code ?: EIO);
                    }

                    const char *jbctlPath = JBROOT_PATH("/basebin/jbctl");
                    if (!jbctlPath) {
                        RLXPostJailbreakSetFailurePhase(&failurePhase, @"userspace_reboot_path");
                        return ENOENT;
                    }

                    pid_t pid = -1;
                    errno = 0;
                    int spawnStatus = RLXPostJailbreakSpawnStatus(
                        exec_cmd_suspended(&pid, jbctlPath, "reboot_userspace", NULL));
                    if (spawnStatus != 0) {
                        RLXPostJailbreakSetFailurePhase(&failurePhase, @"userspace_reboot_spawn");
                        return spawnStatus;
                    }
                    if (kill(pid, SIGCONT) != 0) {
                        RLXPostJailbreakSetFailurePhase(&failurePhase, @"userspace_reboot_resume");
                        return errno ?: EIO;
                    }
                    return 0;
                },
                &failurePhase);
        },
        &failurePhase);
    return status == 0 ? nil
                       : RLXPostJailbreakActionExecutionError(RLXPostJailbreakActionRestartUserspace,
                                                              failurePhase ?: @"unknown",
                                                              status,
                                                              underlyingError);
}

#endif /* !TARGET_OS_SIMULATOR */
