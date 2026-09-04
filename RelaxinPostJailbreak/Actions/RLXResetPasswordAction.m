#import "RLXPostJailbreakActions.h"

#import "RLXPostJailbreakActionRunner.h"

#include <errno.h>
#include <signal.h>
#include <unistd.h>

#include <libjailbreak/jbroot.h>
#include <libjailbreak/util.h>

#if !TARGET_OS_SIMULATOR

int RLXPostJailbreakResetMobilePassword(NSString *_Nullable __strong *_Nullable failurePhase) {
    __block pid_t pid = -1;
    __block int spawnStatus = 0;
    __block int resumeStatus = 0;
    int scopeStatus = RLXPostJailbreakRunAsEffectiveRoot(
        ^int {
            return RLXPostJailbreakRunUnsandboxed(
                ^int {
                    const char *dashPath = JBROOT_PATH("/usr/bin/dash");
                    const char *uialertPath = JBROOT_PATH("/usr/bin/uialert");
                    const char *sedPath = JBROOT_PATH("/usr/bin/sed");
                    const char *pwPath = JBROOT_PATH("/usr/sbin/pw");
                    if (!dashPath || !uialertPath || !sedPath || !pwPath) {
                        RLXPostJailbreakSetFailurePhase(failurePhase, @"password_tool_path");
                        spawnStatus = ENOENT;
                        return spawnStatus;
                    }
                    if (access(dashPath, X_OK) != 0 || access(uialertPath, X_OK) != 0 || access(sedPath, X_OK) != 0
                        || access(pwPath, X_OK) != 0) {
                        RLXPostJailbreakSetFailurePhase(failurePhase, @"password_tool_path");
                        spawnStatus = errno ?: EACCES;
                        return spawnStatus;
                    }

                    NSString
                        *
                            command = [NSString
                                stringWithFormat:
                                    @"PASSWORDS=\"\"\n" "PASSWORD1=\"\"\n" "PASSWORD2=\"\"\n" "while [ -z \"$PASSWORD1\" ]" " || [ ! \"$PASSWORD1\" = \"$PASSWORD2\" ]; do\n" "    PASSWORDS=\"$(\"%s\"" " -b \"In order to use command line tools like" " \\\"sudo\\\" after jailbreaking, you will need to set" " a terminal passcode. (This cannot be empty)\"" " --secure \"Password\"" " --secure \"Repeat Password\"" " -p \"Set\" \"Set Password\")\"\n" "    PASSWORD1=\"$(printf \"%%s\\n\" \"$PASSWORDS\"" " | \"%s\" -n '1 p')\"\n" "    PASSWORD2=\"$(printf \"%%s\\n\" \"$PASSWORDS\"" " | \"%s\" -n '2 p')\"\n" "done\n" "printf \"%%s\\n\" \"$PASSWORD1\"" " | \"%s\" usermod mobile -h 0",
                                    uialertPath,
                                    sedPath,
                                    sedPath,
                                    pwPath];
                    errno = 0;
                    spawnStatus = RLXPostJailbreakSpawnStatus(
                        exec_cmd_suspended(&pid, dashPath, "-c", command.UTF8String, NULL));
                    if (spawnStatus != 0) {
                        RLXPostJailbreakSetFailurePhase(failurePhase, @"password_change_spawn");
                        return spawnStatus;
                    }

                    if (kill(pid, SIGCONT) != 0) {
                        resumeStatus = errno ?: EIO;
                        RLXPostJailbreakSetFailurePhase(failurePhase, @"password_change_resume");
                        (void)kill(pid, SIGKILL);
                        (void)cmd_wait_for_exit(pid);
                        return resumeStatus;
                    }
                    return 0;
                },
                failurePhase);
        },
        failurePhase);
    if (spawnStatus != 0) {
        return scopeStatus ?: spawnStatus;
    }
    if (resumeStatus != 0) {
        return scopeStatus ?: resumeStatus;
    }
    if (scopeStatus != 0) {
        (void)cmd_wait_for_exit(pid);
        return scopeStatus;
    }

    errno = 0;
    int status = RLXPostJailbreakWaitStatus(cmd_wait_for_exit(pid));
    if (status != 0) {
        RLXPostJailbreakSetFailurePhase(failurePhase, @"password_change");
    }
    return status;
}

#endif /* !TARGET_OS_SIMULATOR */
