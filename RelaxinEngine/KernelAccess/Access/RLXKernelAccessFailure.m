//
//  RLXKernelAccessFailure.m
//  RelaxinEngine
//

#import "RLXKernelAccessFailure.h"

#import "../../Diagnostic/RLXEngineDiagnostic.h"

@interface RLXKernelAccessFailure ()

/// `init` is unavailable to callers; the factory still needs a designated one.
- (instancetype)initInternal;

@end

@implementation RLXKernelAccessFailure

+ (instancetype)failureWithKind:(RLXKernelAccessFailureKind)kind
                         status:(int)status
                    description:(NSString *)description
                  failureReason:(nullable NSString *)failureReason
             recoverySuggestion:(NSString *)recoverySuggestion
                     diagnostic:(RLXEngineDiagnostic *)diagnostic {
    RLXKernelAccessFailure *failure = [[self alloc] initInternal];
    failure->_kind = kind;
    failure->_status = status;
    failure->_failureDescription = [description copy];
    failure->_failureReason = [failureReason copy];
    failure->_recoverySuggestion = [recoverySuggestion copy];
    failure->_diagnostic = diagnostic;
    return failure;
}

- (instancetype)initInternal {
    return [super init];
}

- (RLXKernelAccessFailure *)failureByFoldingIntoKernelAccessBuild {
    RLXEngineDiagnostic *diagnostic = self.diagnostic;
    if ([diagnostic containsKey:@"kernel_state_may_be_dirty"]) {
        [diagnostic setBoolValue:YES forEveryKey:@"kernel_state_may_be_dirty"];
    } else {
        [diagnostic appendKernelStateMayBeDirty:YES];
    }
    return [RLXKernelAccessFailure failureWithKind:RLXKernelAccessFailureKindAccessUnavailable status:self.status
                                       description:self.failureDescription
                                     failureReason:self.failureReason
                                recoverySuggestion:rlx_kernel_access_recovery_suggestion(YES)
                                        diagnostic:diagnostic];
}

@end

NSString *rlx_kernel_access_recovery_suggestion(BOOL kernelStateMayBeDirty) {
    return kernelStateMayBeDirty
        ? @"Reboot the device before retrying with a supported device, OS " @"build, kernelcache, and Rocket runtime."
        : @"Use a supported device, OS build, kernelcache, and Rocket runtime.";
}

RLXKernelAccessFailure *rlx_kernel_access_failure(NSString *phase,
                                                  int status,
                                                  NSString *reason,
                                                  BOOL kernelStateMayBeDirty,
                                                  RLXKernelAccessDiagnosticDetails _Nullable details) {
    RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnosticWithStage:@"acquire_kernel_access"];
    [diagnostic appendPhase:phase];
    [diagnostic appendStatus:status];
    [diagnostic appendKernelStateMayBeDirty:kernelStateMayBeDirty];
    if (details) {
        details(diagnostic);
    }
    return [RLXKernelAccessFailure failureWithKind:RLXKernelAccessFailureKindAccessUnavailable status:status
                                       description:@"Kernel access could not be built."
                                     failureReason:reason
                                recoverySuggestion:rlx_kernel_access_recovery_suggestion(kernelStateMayBeDirty)
                                        diagnostic:diagnostic];
}
