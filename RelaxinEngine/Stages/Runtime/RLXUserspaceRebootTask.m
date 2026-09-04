//
//  RLXUserspaceRebootTask.m
//  RelaxinEngine
//

#import "RLXUserspaceRebootTask.h"

#import "../../../RelaxinPostJailbreak/BootLogo/RLXBootLogoWriter.h"
#import "../../Engine/RLXEngine.h"
#import "../../Diagnostic/RLXEngineDiagnostic.h"
#import "../../Engine/RLXEngineError.h"
#import "../../Log/RLXEngineLog.h"
#import "../../Engine/RLXEngineRunContext.h"

#include <errno.h>
#include <signal.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include <libjailbreak/jbroot.h>
#include <libjailbreak/util.h>

static const char *const RLXUserspaceRebootLogCategory = "UserspaceReboot";

static NSError *rlx_userspace_reboot_error(NSString *phase, int status, NSString *reason) {
    NSString *message = [NSString stringWithFormat:@"failed phase=%@ status=%d reason=%@", phase, status, reason];
    rlx_engine_log(RLX_ENGINE_LOG_ERROR, RLXUserspaceRebootLogCategory, message.UTF8String);
    RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnostic];
    [diagnostic appendPhase:phase];
    [diagnostic appendStatus:status];
    return [RLXEngineError errorWithCode:RLXEngineErrorCodeUserspaceRebootFailed
                             description:@"The userspace reboot could not be started."
                           failureReason:reason
                      recoverySuggestion:@"Reboot the device before retrying the jailbreak."
                              diagnostic:diagnostic];
}

static void rlx_discard_suspended_process(pid_t pid) {
    if (pid <= 0) {
        return;
    }
    if (kill(pid, SIGKILL) != 0 && errno != ESRCH) {
        return;
    }
    while (waitpid(pid, NULL, 0) == -1 && errno == EINTR) {
    }
}

@implementation RLXUserspaceRebootTask

- (instancetype)initWithContext:(RLXEngineRunContext *)context {
    return [super initWithStage:RLXEngineStageUserspaceReboot context:context];
}

- (nullable NSError *)execute {
    BOOL darkAppearance = self.context.manifest[RLXEngineManifestBootLogoDarkAppearanceKey].boolValue;
    NSError *bootLogoError = [RLXBootLogoWriter
        writeBootLogoForDarkAppearance:darkAppearance
                        resourceBundle:self.context.runtimeEnvironment.resourceBundle];
    if (bootLogoError) {
        NSString *phase = bootLogoError.userInfo[RLXBootLogoWriterFailurePhaseErrorKey] ?: @"update";
        return rlx_userspace_reboot_error([@"boot_logo_" stringByAppendingString:phase],
                                          (int)(bootLogoError.code ?: EIO),
                                          bootLogoError.localizedDescription);
    }

    const char *jbctlPath = JBROOT_PATH("/basebin/jbctl");
    if (!jbctlPath) {
        return rlx_userspace_reboot_error(@"reboot_path", ENOENT, @"The live jbroot path is unavailable.");
    }

    rlx_engine_log(RLX_ENGINE_LOG_INFO, RLXUserspaceRebootLogCategory, "phase=reboot_spawn begin");
    pid_t pid = -1;
    int status = exec_cmd_suspended(&pid, jbctlPath, "reboot_userspace", NULL);
    if (status != 0) {
        return rlx_userspace_reboot_error(@"reboot_spawn",
                                          status,
                                          [NSString
                                              stringWithFormat:@"jbctl could not be spawned with status %d.", status]);
    }

    rlx_engine_log(RLX_ENGINE_LOG_INFO,
                   RLXUserspaceRebootLogCategory,
                   "phase=kernel_access_finalize begin; reboot carrier is suspended");
    /*
     * Ordering is the point: the reboot carrier stays suspended across this
     * call, so every backend restores or safely retires its process-local
     * access before anything can run in the new userspace. The backend owns
     * any device-specific process-exit retention policy.
     */
    if (![self.context finalizeKernelAccessReturningStatus:&status]) {
        rlx_discard_suspended_process(pid);
        return rlx_userspace_reboot_error(
            @"kernel_access_finalize",
            ENXIO,
            @"The run no longer owns the kernel access required for the " "userspace reboot handoff.");
    }
    if (status != 0 && status != EALREADY) {
        rlx_discard_suspended_process(pid);
        return rlx_userspace_reboot_error(
            @"kernel_access_finalize",
            status,
            @"Rocket could not retire its process-local kernel access after " "launchd accepted the handoff.");
    }
    [self.context discardKernelAccess];
    NSString *finalizeMessage = [NSString
        stringWithFormat:@"phase=kernel_access_finalize status=%d; access retired", status];
    rlx_engine_log(RLX_ENGINE_LOG_INFO, RLXUserspaceRebootLogCategory, finalizeMessage.UTF8String);

    if (kill(pid, SIGCONT) != 0) {
        int signalError = errno ?: EIO;
        return rlx_userspace_reboot_error(@"reboot_resume",
                                          signalError,
                                          [NSString
                                              stringWithFormat:@"The suspended jbctl process could not be resumed: %s.",
                                                               strerror(signalError)]);
    }

    NSString *message = [NSString stringWithFormat:@"phase=reboot_resume status=0 pid=%d; request submitted", pid];
    rlx_engine_log(RLX_ENGINE_LOG_INFO, RLXUserspaceRebootLogCategory, message.UTF8String);
    return nil;
}

@end
