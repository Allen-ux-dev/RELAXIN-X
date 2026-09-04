//
//  RLXEngine.m
//  RelaxinEngine
//

#import "RLXEngine.h"

#import "RLXEngineRunContext.h"
#import "RLXEngineStageRegistry.h"
#import "RLXEngineTaskQueue.h"

NSErrorDomain const RLXEngineErrorDomain = @"com.aapl.relaxin.engine";
RLXEngineErrorUserInfoKey const RLXEngineFailureStageKey = @"RLXEngineFailureStage";
RLXEngineErrorUserInfoKey const RLXEngineFailureTaskPositionKey = @"RLXEngineFailureTaskPosition";
RLXEngineErrorUserInfoKey const RLXEngineFailureTaskCountKey = @"RLXEngineFailureTaskCount";
RLXEngineErrorUserInfoKey const RLXEngineDiagnosticKey = @"RLXEngineDiagnostic";
RLXEngineManifestKey const RLXEngineManifestTargetDeviceIdentifierKey = @"targetDeviceIdentifier";
RLXEngineManifestKey const RLXEngineManifestTargetSoCKey = @"targetSoC";
RLXEngineManifestKey const RLXEngineManifestTargetCPUFamilyKey = @"targetCPUFamily";
RLXEngineManifestKey const RLXEngineManifestTargetOSVersionKey = @"targetOSVersion";
RLXEngineManifestKey const RLXEngineManifestTargetOSBuildKey = @"targetOSBuild";
RLXEngineManifestKey const RLXEngineManifestRuntimeProfileKey = @"runtimeProfile";
RLXEngineManifestKey const RLXEngineManifestRuntimeProfileIDKey = @"runtimeProfileID";
RLXEngineManifestKey const RLXEngineManifestRuntimeBackendIDKey = @"runtimeBackendID";
RLXEngineManifestKey const RLXEngineManifestRuntimeBackendGenerationKey = @"runtimeBackendGeneration";
RLXEngineManifestKey const RLXEngineManifestRuntimeResolutionGenerationKey = @"runtimeResolutionGeneration";
RLXEngineManifestKey const RLXEngineManifestHardwareExecutionClassKey = @"hardwareExecutionClass";
RLXEngineManifestKey const RLXEngineManifestRuntimeSupportLevelKey = @"runtimeSupportLevel";
RLXEngineManifestKey const RLXEngineManifestTweakInjectionEnabledKey = @"tweakInjectionEnabled";
RLXEngineManifestKey const RLXEngineManifestAppJITEnabledKey = @"appJITEnabled";
RLXEngineManifestKey const RLXEngineManifestJetsamMultiplierKey = @"jetsamMultiplier";
RLXEngineManifestKey const RLXEngineManifestRemoveJailbreakEnabledKey = @"removeJailbreakEnabled";
RLXEngineManifestKey const RLXEngineManifestBootLogoDarkAppearanceKey = @"bootLogoDarkAppearance";
RLXEngineManifestKey const RLXEngineManifestInstallSileoEnabledKey = @"installSileoEnabled";
RLXEngineManifestKey const RLXEngineManifestInstallZebraEnabledKey = @"installZebraEnabled";
RLXEngineManifestKey const RLXEngineManifestZebraPackagePathKey = @"zebraPackagePath";
RLXEngineManifestKey const RLXEngineManifestBootstrapRestoreModeKey = @"bootstrapRestoreMode";

@implementation RLXEngine {
    RLXEngineTaskQueue *_taskQueue;
}

- (instancetype)init {
    return [self initWithRuntimeEnvironment:RLXRuntimeEnvironment.defaultEnvironment];
}

- (instancetype)initWithRuntimeEnvironment:(RLXRuntimeEnvironment *)runtimeEnvironment {
    return [self initWithRuntimeEnvironment:runtimeEnvironment additionalBootstrapPackageResourceNames:@[]];
}

- (instancetype)initWithRuntimeEnvironment:(RLXRuntimeEnvironment *)runtimeEnvironment
    additionalBootstrapPackageResourceNames:(NSArray<NSString *> *)packageResourceNames {
    self = [super init];
    if (self) {
        _runtimeEnvironment = runtimeEnvironment;
        _additionalBootstrapPackageResourceNames = [packageResourceNames copy];
        _postJailbreakController = [[RLXPostJailbreakController alloc]
            initWithResourceBundle:runtimeEnvironment.resourceBundle];
        _taskQueue = [[RLXEngineTaskQueue alloc] init];
    }
    return self;
}

- (BOOL)detectJailbroken {
    return [self.postJailbreakController isAvailable];
}

- (void)runWithManifest:(NSDictionary<RLXEngineManifestKey, NSString *> *)manifest
          updateHandler:(RLXEngineTaskUpdateHandler)updateHandler
             completion:(RLXEngineCompletionHandler)completion {
    RLXEngineRunContext *context = [[RLXEngineRunContext alloc]
                               initWithManifest:manifest
                             runtimeEnvironment:self.runtimeEnvironment
        additionalBootstrapPackageResourceNames:self.additionalBootstrapPackageResourceNames];
    NSArray<RLXEngineTask *> *tasks = [RLXEngineStageRegistry tasksForContext:context];

    [_taskQueue enqueueTasks:tasks updateHandler:updateHandler completion:completion];
}

@end
