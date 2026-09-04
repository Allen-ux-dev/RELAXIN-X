//
//  RLXKernelAccessFailureError.m
//  RelaxinEngine
//

#import "RLXKernelAccessFailureError.h"

#import "../../Engine/RLXEngine.h"
#import "../../Engine/RLXEngineError.h"
#import "../../KernelAccess/Access/RLXKernelAccessFailure.h"

static RLXEngineErrorCode rlx_engine_code_for_failure_kind(RLXKernelAccessFailureKind kind) {
    switch (kind) {
        case RLXKernelAccessFailureKindAccessUnavailable:
            return RLXEngineErrorCodeKernelAccessUnavailable;
        case RLXKernelAccessFailureKindPrivilegeEscalation:
            return RLXEngineErrorCodePrivilegeEscalationFailed;
    }
    return RLXEngineErrorCodeKernelAccessUnavailable;
}

NSError *rlx_engine_error_from_kernel_access_failure(RLXKernelAccessFailure *failure) {
    return [RLXEngineError errorWithCode:rlx_engine_code_for_failure_kind(failure.kind)
                             description:failure.failureDescription
                           failureReason:failure.failureReason
                      recoverySuggestion:failure.recoverySuggestion
                              diagnostic:failure.diagnostic];
}
