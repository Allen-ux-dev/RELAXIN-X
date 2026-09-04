//
//  RLXPostRemovalCleanupTask.m
//  RelaxinEngine
//

#import "RLXPostRemovalCleanupTask.h"

#import "../../Engine/RLXEngine.h"
#import "../../Diagnostic/RLXEngineDiagnostic.h"
#import "../../Engine/RLXEngineError.h"
#import "../../Log/RLXEngineLog.h"
#import "../../Engine/RLXEngineRunContext.h"

#include <errno.h>
#include <string.h>

static const char *const RLXPostRemovalCleanupLogCategory = "PostRemovalCleanup";

static NSError *rlx_post_removal_cleanup_error(int status) {
    int displayStatus = status > 0 ? status : EIO;
    NSString *statusDescription = [NSString stringWithUTF8String:strerror(displayStatus)] ?: @"unknown error";
    NSString *message = [NSString
        stringWithFormat:@"kernel access finalization failed status=%d (%@)", status, statusDescription];
    rlx_engine_log(RLX_ENGINE_LOG_ERROR, RLXPostRemovalCleanupLogCategory, message.UTF8String);
    RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnostic];
    [diagnostic appendPhase:@"kernel_access_finalize"];
    [diagnostic appendStatus:status];
    [diagnostic appendKey:@"status_description" value:statusDescription];
    [diagnostic appendKernelStateMayBeDirty:YES];
    return [RLXEngineError
             errorWithCode:RLXEngineErrorCodeKernelAccessUnavailable
               description:@"Post-removal cleanup could not be completed."
             failureReason:[NSString stringWithFormat:@"Kernel access finalization failed with status " @"%d (%@).",
                                                      status,
                                                      statusDescription]
        recoverySuggestion:@"Reboot the device before starting another jailbreak " "run."
                diagnostic:diagnostic];
}

@implementation RLXPostRemovalCleanupTask

- (instancetype)initWithContext:(RLXEngineRunContext *)context {
    return [super initWithStage:RLXEngineStagePostRemovalCleanup context:context];
}

- (nullable NSError *)execute {
    rlx_engine_log(RLX_ENGINE_LOG_INFO,
                   RLXPostRemovalCleanupLogCategory,
                   "finalizing kernel access after bootstrap removal");
    int status = 0;
    if (![self.context finalizeKernelAccessReturningStatus:&status]) {
        return rlx_post_removal_cleanup_error(ENXIO);
    }
    if (status != 0 && status != EALREADY) {
        return rlx_post_removal_cleanup_error(status);
    }

    [self.context discardKernelAccess];
    NSString *message = [NSString
        stringWithFormat:@"kernel access finalized status=%d; process privileges remain " "active until the App exits",
                         status];
    rlx_engine_log(RLX_ENGINE_LOG_INFO, RLXPostRemovalCleanupLogCategory, message.UTF8String);
    return nil;
}

@end
