//
//  RLXEngineStageRegistry.h
//  RelaxinEngine
//
//  The single source of stage -> task mapping.
//

#import <Foundation/Foundation.h>

#import "RLXEngineTaskUpdate.h"

@class RLXEngineRunContext;
@class RLXEngineTask;

NS_ASSUME_NONNULL_BEGIN

/// Which run branches a stage belongs to.
typedef NS_OPTIONS(NSUInteger, RLXEngineStageBranch) {
    RLXEngineStageBranchJailbreak = 1 << 0,
    RLXEngineStageBranchRemoval = 1 << 1,
    RLXEngineStageBranchAll = RLXEngineStageBranchJailbreak | RLXEngineStageBranchRemoval,
};

/**
 * Owns the ordered stage table.
 *
 * Execution order used to be encoded three times over — in the file name, in
 * the class name, and in the array literal that built the run. It lives here
 * once, as data, and the task classes are named after what they do.
 */
@interface RLXEngineStageRegistry : NSObject

/**
 * The stages a run executes, in execution order.
 *
 * `simulator` selects whether stages without a simulator implementation are
 * still listed; they are, because the simulator substitutes a mock rather than
 * skipping them.
 */
+ (NSArray<NSNumber *> *)stagesForRemoval:(BOOL)removeJailbreak;

/// Whether the simulator substitutes RLXEngineMockTask for this stage.
+ (BOOL)isSimulatorMockedStage:(RLXEngineStage)stage;

/// Builds the run's task list, mocking where the platform requires it.
+ (NSArray<RLXEngineTask *> *)tasksForContext:(RLXEngineRunContext *)context;

@end

NS_ASSUME_NONNULL_END
