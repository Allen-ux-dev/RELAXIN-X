//
//  RLXKernelAccessAcquisitionTask.m
//  RelaxinEngine
//

#import "RLXKernelAccessAcquisitionTask.h"

#import "../../Engine/RLXEngine.h"
#import "../../Diagnostic/RLXEngineDiagnostic.h"
#import "../../Engine/RLXEngineError.h"
#import "../../Log/RLXEngineLog.h"
#import "../../Engine/RLXEngineRunContext.h"
#import "../../KernelAccess/RLXKernelAccess.h"
#import "../../KernelAccess/Access/RLXKernelAccessInternal.h"
#import "../../KernelAccess/Access/RLXKernelAccessFailure.h"
#import "../../KernelAccess/Analysis/RLXKernelInfo.h"
#import "../../KernelAccess/Analysis/RLXKernelOffsetTable.h"
#import "RLXKernelAccessFailureError.h"

@implementation RLXKernelAccessAcquisitionTask

- (instancetype)initWithContext:(RLXEngineRunContext *)context {
    return [super initWithStage:RLXEngineStageKernelAccessAcquisition context:context];
}

- (nullable NSError *)execute {
    NSString *kernelcachePath = self.context.kernelcachePath;
    RLXKernelOffsetProfile *offsetProfile = self.context.kernelOffsetProfile;
    if (!kernelcachePath && !offsetProfile) {
        RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnosticWithStage:@"acquire_kernel_access"];
        [diagnostic appendKey:@"kernelcache" boolValue:NO];
        [diagnostic appendKey:@"offset_table" boolValue:NO];
        return [RLXEngineError errorWithCode:RLXEngineErrorCodeInvalidAction
                                 description:@"Kernel access requires a kernelcache or a bundled offset profile."
                               failureReason:nil
                          recoverySuggestion:@"Run kernelcache acquisition before building kernel access."
                                  diagnostic:diagnostic];
    }

    RLXKernelAccess *kernelAccess = [[RLXKernelAccess alloc]
        initWithKernelcachePath:kernelcachePath
                  offsetProfile:offsetProfile
                 resourceBundle:self.context.runtimeEnvironment.resourceBundle
               dataDirectoryURL:self.context.runtimeEnvironment.dataDirectoryURL];
    self.context.kernelAccess = kernelAccess;
    int status = [kernelAccess build];
    if (status != 0 || !kernelAccess.active) {
        if (kernelAccess.buildFailure) {
            return rlx_engine_error_from_kernel_access_failure(kernelAccess.buildFailure);
        }
        RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnosticWithStage:@"acquire_kernel_access"];
        [diagnostic appendKey:@"kernelcache" value:kernelcachePath fallback:@"unused"];
        [diagnostic appendKey:@"offset_table" boolValue:offsetProfile != nil];
        [diagnostic appendStatus:status];
        [diagnostic appendKey:@"access" boolValue:kernelAccess.active];
        [diagnostic appendKernelStateMayBeDirty:YES];
        return [RLXEngineError errorWithCode:RLXEngineErrorCodeKernelAccessUnavailable
                                 description:@"Kernel access could not be built."
                               failureReason:@"The exploit backend did not publish complete KRW and PHYRW primitives."
                          recoverySuggestion:@"Reboot the device before retrying with a supported " "exploit backend."
                                  diagnostic:diagnostic];
    }

    RLXKernelInfo *runtimeKernelInfo = kernelAccess.kernelInfo;
    if (!runtimeKernelInfo) {
        RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnosticWithStage:@"acquire_kernel_access"];
        [diagnostic appendKey:@"runtime_layout" boolValue:NO];
        [diagnostic appendKernelStateMayBeDirty:YES];
        return [RLXEngineError
                 errorWithCode:RLXEngineErrorCodeKernelAccessUnavailable
                   description:@"Kernel access published an invalid runtime layout."
                 failureReason:nil
            recoverySuggestion:@"Reboot the device before retrying with a supported " "kernelcache and exploit runtime."
                    diagnostic:diagnostic];
    }
    self.context.kernelInfo = runtimeKernelInfo;
    NSString *kernelBaseMessage = [NSString
        stringWithFormat:@"kbase=0x%llx", (unsigned long long)kernelAccess.layout.kernel_base];
    rlx_engine_log(RLX_ENGINE_LOG_INFO, "RLXEngine", kernelBaseMessage.UTF8String);
    rlx_engine_log(RLX_ENGINE_LOG_INFO, "RLXEngine", "kernel access ready");
    return nil;
}

@end
