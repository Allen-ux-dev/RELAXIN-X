//
//  RLXPrivilegeEscalationTask.m
//  RelaxinEngine
//

#import "RLXPrivilegeEscalationTask.h"

#import "../../Engine/RLXEngine.h"
#import "../../Diagnostic/RLXEngineDiagnostic.h"
#import "../../Engine/RLXEngineError.h"
#import "../../Log/RLXEngineLog.h"
#import "../../Engine/RLXEngineRunContext.h"
#import "../../KernelAccess/Access/RLXKernelAccessFailure.h"
#import "../../KernelAccess/PostExploitation/RLXKernelAccess+PrivilegeEscalation.h"
#import "RLXKernelAccessFailureError.h"

@implementation RLXPrivilegeEscalationTask

- (instancetype)initWithContext:(RLXEngineRunContext *)context {
    return [super initWithStage:RLXEngineStagePrivilegeEscalation context:context];
}

- (nullable NSError *)execute {
    RLXKernelAccess *kernelAccess = self.context.kernelAccess;
    if (!kernelAccess.active) {
        RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnosticWithStage:@"privilege_escalation"];
        [diagnostic appendKey:@"kernel_access" boolValue:NO];
        return [RLXEngineError errorWithCode:RLXEngineErrorCodeInvalidAction
                                 description:@"Privilege escalation requires kernel access."
                               failureReason:nil
                          recoverySuggestion:@"Build and validate kernel access before running this checkpoint."
                                  diagnostic:diagnostic];
    }

    // Task 04 owns backend selection; downstream tasks use only its context
    // handoff and never import Rocket-specific APIs.
    RLXKernelAccessFailure *failure = [kernelAccess escalatePrivileges];
    if (failure) {
        return rlx_engine_error_from_kernel_access_failure(failure);
    }

    rlx_engine_log(RLX_ENGINE_LOG_INFO, "RLXEngine", "privilege escalation complete");
    return nil;
}

@end
