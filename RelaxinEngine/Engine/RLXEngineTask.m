//
//  RLXEngineTask.m
//  RelaxinEngine
//

#import "RLXEngineTask.h"

#import "../Diagnostic/RLXEngineDiagnostic.h"
#import "RLXEngineError.h"
#import "RLXEngineRunContext.h"

@implementation RLXEngineTask

- (instancetype)initWithStage:(RLXEngineStage)stage context:(RLXEngineRunContext *)context {
    self = [super init];
    if (self) {
        _stage = stage;
        switch (stage) {
            case RLXEngineStageTargetConfirmation:
                _name = @"target confirmation";
                break;
            case RLXEngineStageKernelCacheAcquisition:
                _name = @"kernelcache acquisition";
                break;
            case RLXEngineStageKernelCacheLayoutAnalysis:
                _name = @"kernelcache layout analysis";
                break;
            case RLXEngineStageKernelAccessAcquisition:
                _name = @"kernel access acquisition";
                break;
            case RLXEngineStagePrivilegeEscalation:
                _name = @"privilege escalation";
                break;
            case RLXEngineStageBootstrapPreparation:
                _name = @"bootstrap preparation";
                break;
            case RLXEngineStageBaseBinTrust:
                _name = @"BaseBin trust";
                break;
            case RLXEngineStageLaunchdHandoff:
                _name = @"launchd handoff";
                break;
            case RLXEngineStageJailbreakdCheckin:
                _name = @"jailbreakd check-in";
                break;
            case RLXEngineStageSystemHookActivation:
                _name = @"SystemHook activation";
                break;
            case RLXEngineStageBootstrapFinalization:
                _name = @"bootstrap finalization";
                break;
            case RLXEngineStageUserspaceReboot:
                _name = @"userspace reboot";
                break;
            case RLXEngineStageBootstrapRemoval:
                _name = @"bootstrap removal";
                break;
            case RLXEngineStagePostRemovalCleanup:
                _name = @"post-removal cleanup";
                break;
        }
        _context = context;
    }
    return self;
}

- (nullable NSError *)execute {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (NSError *)unavailableError {
    RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnosticWithStage:@"unavailable"];
    [diagnostic appendKey:@"stage_id" integerValue:self.stage];
    [diagnostic appendKey:@"name" value:self.name];
    return [RLXEngineError
             errorWithCode:RLXEngineErrorCodeStageUnavailable
               description:[NSString stringWithFormat:@"%@ is not implemented.", self.name]
             failureReason:@"The stage is present in the engine task plan but has no implementation."
        recoverySuggestion:@"Implement and validate this stage before running the complete jailbreak sequence."
                diagnostic:diagnostic];
}

@end
