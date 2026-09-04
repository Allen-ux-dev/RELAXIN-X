//
//  RLXEngineTaskUpdate.h
//  RelaxinEngine
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Engine stages.
 *
 * Declaration order is NOT execution order — BootstrapRemoval and
 * PostRemovalCleanup sit between LaunchdHandoff and JailbreakdCheckin here, but
 * they belong to the removal branch and never run alongside those stages.
 *
 * These raw values are ABI: the Swift app persists and compares them, so cases
 * may only be appended, never reordered. Execution order lives in
 * RLXEngineStageRegistry's table, which is the thing to edit when a stage moves.
 */
typedef NS_ENUM(NSInteger, RLXEngineStage) {
    RLXEngineStageTargetConfirmation,
    RLXEngineStageKernelCacheAcquisition,
    RLXEngineStageKernelCacheLayoutAnalysis,
    RLXEngineStageKernelAccessAcquisition,
    RLXEngineStagePrivilegeEscalation,
    RLXEngineStageBootstrapPreparation,
    RLXEngineStageBaseBinTrust,
    RLXEngineStageLaunchdHandoff,
    RLXEngineStageBootstrapRemoval,
    RLXEngineStagePostRemovalCleanup,
    RLXEngineStageJailbreakdCheckin,
    RLXEngineStageSystemHookActivation,
    RLXEngineStageBootstrapFinalization,
    RLXEngineStageUserspaceReboot,
};

typedef NS_ENUM(NSInteger, RLXEngineTaskStatus) {
    RLXEngineTaskStatusRunning,
    RLXEngineTaskStatusSucceeded,
    RLXEngineTaskStatusFailed,
};

@interface RLXEngineTaskUpdate : NSObject

@property(nonatomic, readonly) RLXEngineStage stage;
@property(nonatomic, copy, readonly) NSString *message;
@property(nonatomic, readonly) NSUInteger position;
@property(nonatomic, readonly) NSUInteger count;
@property(nonatomic, readonly) RLXEngineTaskStatus status;

- (instancetype)initWithStage:(RLXEngineStage)stage
                      message:(NSString *)message
                     position:(NSUInteger)position
                        count:(NSUInteger)count
                       status:(RLXEngineTaskStatus)status NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

typedef void (^RLXEngineTaskUpdateHandler)(RLXEngineTaskUpdate *update);

NS_ASSUME_NONNULL_END
