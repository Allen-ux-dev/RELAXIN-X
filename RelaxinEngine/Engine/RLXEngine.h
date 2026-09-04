//
//  RLXEngine.h
//  RelaxinEngine
//  Objective-C engine used by the jailbreak setup flow.
//

#import <Foundation/Foundation.h>

#import <RelaxinEngine/RLXEngineTaskUpdate.h>
#import <RelaxinEngine/RLXRuntimeEnvironment.h>
#import <RelaxinPostJailbreak/RLXPostJailbreakController.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const RLXEngineErrorDomain;

typedef NSString *RLXEngineErrorUserInfoKey NS_TYPED_EXTENSIBLE_ENUM;

FOUNDATION_EXPORT RLXEngineErrorUserInfoKey const RLXEngineFailureStageKey;
FOUNDATION_EXPORT RLXEngineErrorUserInfoKey const RLXEngineFailureTaskPositionKey;
FOUNDATION_EXPORT RLXEngineErrorUserInfoKey const RLXEngineFailureTaskCountKey;
FOUNDATION_EXPORT RLXEngineErrorUserInfoKey const RLXEngineDiagnosticKey;

typedef NSString *RLXEngineManifestKey NS_TYPED_EXTENSIBLE_ENUM;

FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestTargetDeviceIdentifierKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestTargetSoCKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestTargetCPUFamilyKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestTargetOSVersionKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestTargetOSBuildKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestRuntimeProfileKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestRuntimeProfileIDKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestRuntimeBackendIDKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestRuntimeBackendGenerationKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestRuntimeResolutionGenerationKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestHardwareExecutionClassKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestRuntimeSupportLevelKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestTweakInjectionEnabledKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestAppJITEnabledKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestJetsamMultiplierKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestRemoveJailbreakEnabledKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestBootLogoDarkAppearanceKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestInstallSileoEnabledKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestInstallZebraEnabledKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestZebraPackagePathKey;
FOUNDATION_EXPORT RLXEngineManifestKey const RLXEngineManifestBootstrapRestoreModeKey;

typedef NS_ERROR_ENUM(RLXEngineErrorDomain, RLXEngineErrorCode){
    RLXEngineErrorCodeInvalidAction = 1,
    RLXEngineErrorCodeInvalidTarget,
    RLXEngineErrorCodeKernelcacheUnavailable,
    RLXEngineErrorCodeKernelAccessUnavailable,
    RLXEngineErrorCodePrivilegeEscalationFailed,
    RLXEngineErrorCodeStageUnavailable,
    RLXEngineErrorCodeBootstrapPreparationFailed,
    RLXEngineErrorCodeBaseBinTrustFailed,
    RLXEngineErrorCodeLaunchdHandoffFailed,
    RLXEngineErrorCodeJailbreakdCheckinFailed,
    RLXEngineErrorCodeSystemHookActivationFailed,
    RLXEngineErrorCodeBootstrapFinalizationFailed,
    RLXEngineErrorCodeUserspaceRebootFailed,
};

typedef void (^RLXEngineCompletionHandler)(NSError *_Nullable error);

@interface RLXEngine : NSObject

@property(nonatomic, strong, readonly) RLXRuntimeEnvironment *runtimeEnvironment;
@property(nonatomic, copy, readonly) NSArray<NSString *> *additionalBootstrapPackageResourceNames;
@property(nonatomic, strong, readonly) RLXPostJailbreakController *postJailbreakController;

- (instancetype)initWithRuntimeEnvironment:(RLXRuntimeEnvironment *)runtimeEnvironment
    additionalBootstrapPackageResourceNames:(NSArray<NSString *> *)packageResourceNames NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithRuntimeEnvironment:(RLXRuntimeEnvironment *)runtimeEnvironment
    NS_SWIFT_NAME(init(runtimeEnvironment:));
- (instancetype)init;

- (BOOL)detectJailbroken NS_SWIFT_NAME(detectJailbroken());

- (void)runWithManifest:(NSDictionary<RLXEngineManifestKey, NSString *> *)manifest
          updateHandler:(nullable RLXEngineTaskUpdateHandler)updateHandler
             completion:(nullable RLXEngineCompletionHandler)completion NS_SWIFT_NAME(run(manifest:update:completion:));

@end

NS_ASSUME_NONNULL_END
