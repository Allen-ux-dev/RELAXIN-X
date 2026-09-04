//
//  RLXBootstrapFinalizationTask.m
//  RelaxinEngine
//

#import "RLXBootstrapFinalizationTask.h"

#import "../../Bootstrap/RLXBootstrapFinalizer.h"
#import "../../Engine/RLXEngineRunContext.h"
#import "../../Log/RLXEngineLog.h"

@implementation RLXBootstrapFinalizationTask

- (instancetype)initWithContext:(RLXEngineRunContext *)context {
    return [super initWithStage:RLXEngineStageBootstrapFinalization context:context];
}

- (nullable NSError *)execute {
    NSString *installSileoValue = self.context.manifest[RLXEngineManifestInstallSileoEnabledKey];
    BOOL installSileo = installSileoValue ? installSileoValue.boolValue : YES;
    BOOL installZebra = self.context.manifest[RLXEngineManifestInstallZebraEnabledKey].boolValue;
    NSString *zebraPackagePath = installZebra ? self.context.manifest[RLXEngineManifestZebraPackagePathKey] : nil;

    RLXBootstrapFinalizer *finalizer = [[RLXBootstrapFinalizer alloc]
                initWithResourceBundle:self.context.runtimeEnvironment.resourceBundle
                 temporaryDirectoryURL:self.context.runtimeEnvironment.temporaryDirectoryURL
        additionalPackageResourceNames:self.context.additionalBootstrapPackageResourceNames
                         installSileo:installSileo
                     zebraPackagePath:zebraPackagePath];
    NSError *error = [finalizer finalizeBootstrap];

    if (!error) {
        rlx_engine_log(RLX_ENGINE_LOG_INFO, "RLXEngine", "bootstrap finalization complete");
    }
    return error;
}

@end
