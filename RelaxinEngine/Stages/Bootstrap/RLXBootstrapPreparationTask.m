//
//  RLXBootstrapPreparationTask.m
//  RelaxinEngine
//

#import "RLXBootstrapPreparationTask.h"

#import "../../Bootstrap/RLXBootstrapPreparer.h"
#import "../../Engine/RLXEngine.h"
#import "../../Log/RLXEngineLog.h"
#import "../../Engine/RLXEngineRunContext.h"

@implementation RLXBootstrapPreparationTask

- (instancetype)initWithContext:(RLXEngineRunContext *)context {
    return [super initWithStage:RLXEngineStageBootstrapPreparation context:context];
}

- (nullable NSError *)execute {
    NSString *tweakInjection = self.context.manifest[RLXEngineManifestTweakInjectionEnabledKey];
    BOOL tweakInjectionEnabled = tweakInjection.length == 0 || tweakInjection.boolValue;
    NSString *restoreMode = self.context.manifest[RLXEngineManifestBootstrapRestoreModeKey];
    BOOL requiresExistingBootstrap = [restoreMode isEqualToString:@"existing-required"];
    RLXBootstrapPreparer *preparer = [[RLXBootstrapPreparer alloc]
         initWithKernelAccess:self.context.kernelAccess
        tweakInjectionEnabled:tweakInjectionEnabled
    requiresExistingBootstrap:requiresExistingBootstrap
               resourceBundle:self.context.runtimeEnvironment.resourceBundle
        temporaryDirectoryURL:self.context.runtimeEnvironment.temporaryDirectoryURL];
    NSError *error = [preparer prepare];
    if (!error) {
        rlx_engine_log(RLX_ENGINE_LOG_INFO, "RLXEngine", "bootstrap preparation complete");
    }
    return error;
}

@end
