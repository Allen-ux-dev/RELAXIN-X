//
//  RLXSystemHookActivationTask.m
//  RelaxinEngine
//

#import "RLXSystemHookActivationTask.h"

#import "../../Engine/RLXEngine.h"
#import "../../Diagnostic/RLXEngineDiagnostic.h"
#import "../../Engine/RLXEngineError.h"
#import "../../Log/RLXEngineLog.h"
#import "../../Engine/RLXEngineRunContext.h"

#include <errno.h>
#include <stdlib.h>
#include <unistd.h>

#include <libjailbreak/jbroot.h>
#include <libjailbreak/roothider/common.h>
#include <libjailbreak/util.h>

static const char *const RLXSystemHookActivationLogCategory = "SystemHookActivation";

static NSError *rlx_systemhook_activation_error(NSString *phase, int status) {
    NSString *message = [NSString stringWithFormat:@"failed phase=%@ status=%d", phase, status];
    rlx_engine_log(RLX_ENGINE_LOG_ERROR, RLXSystemHookActivationLogCategory, message.UTF8String);
    RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnostic];
    [diagnostic appendPhase:phase];
    [diagnostic appendStatus:status];
    return [RLXEngineError errorWithCode:RLXEngineErrorCodeSystemHookActivationFailed
                             description:@"The SystemHook execution environment could not be " "activated."
                           failureReason:[NSString stringWithFormat:@"%@ failed with status %d.", phase, status]
                      recoverySuggestion:@"Reboot the device before retrying the jailbreak."
                              diagnostic:diagnostic];
}

@implementation RLXSystemHookActivationTask

- (instancetype)initWithContext:(RLXEngineRunContext *)context {
    return [super initWithStage:RLXEngineStageSystemHookActivation context:context];
}

- (nullable NSError *)execute {
    const char *systemHookPath = JBROOT_PATH("/basebin/systemhook.dylib");
    rlx_engine_log(RLX_ENGINE_LOG_INFO,
                   RLXSystemHookActivationLogCategory,
                   "activating SystemHook with stock dyld; patched-dyld generation and trust are disabled");

    if (access(systemHookPath, R_OK) != 0) {
        int status = errno ?: ENOENT;
        NSString *message = [NSString
            stringWithFormat:@"SystemHook is unavailable path=%s status=%d", systemHookPath, status];
        rlx_engine_log(RLX_ENGINE_LOG_ERROR, RLXSystemHookActivationLogCategory, message.UTF8String);
        return rlx_systemhook_activation_error(@"locate_systemhook", status);
    }

    NSString *systemHookMessage = [NSString stringWithFormat:@"SystemHook payload ready path=%s", systemHookPath];
    rlx_engine_log(RLX_ENGINE_LOG_INFO, RLXSystemHookActivationLogCategory, systemHookMessage.UTF8String);

    // This flag controls child preparation, not dyld replacement. In the
    // stock-dyld path it suspends children long enough to apply
    // CS_GET_TASK_ALLOW before SystemHook is loaded.
    exec_set_patch(true);
    rlx_engine_log(RLX_ENGINE_LOG_INFO,
                   RLXSystemHookActivationLogCategory,
                   "enabled stock-dyld child preparation via CS_GET_TASK_ALLOW");

    setenv("DYLD_IN_CACHE", "0", 1);
    setenv("DISABLE_TWEAKS", "1", 1);
    setenv("DYLD_INSERT_LIBRARIES", systemHookPath, 1);
    rlx_engine_log(RLX_ENGINE_LOG_INFO,
                   RLXSystemHookActivationLogCategory,
                   "configured stock-dyld SystemHook injection environment; restarting iconservicesagent");

    int status = exec_cmd_trusted(JBROOT_PATH("/usr/bin/killall"), "-9", "iconservicesagent", NULL);
    NSString *restartMessage = [NSString
        stringWithFormat:@"iconservicesagent restart request completed status=%d", status];
    rlx_engine_log(status == 0 ? RLX_ENGINE_LOG_INFO : RLX_ENGINE_LOG_WARNING,
                   RLXSystemHookActivationLogCategory,
                   restartMessage.UTF8String);

    rlx_engine_log(RLX_ENGINE_LOG_INFO,
                   RLXSystemHookActivationLogCategory,
                   "SystemHook activation completed policy=stock-dyld patched_dyld=disabled");
    return nil;
}

@end
