//
//  RLXEngineMockTask.h
//  RelaxinEngine
//

#import "../../Engine/RLXEngineTask.h"

NS_ASSUME_NONNULL_BEGIN

/// Simulator stand-in for a concrete engine task. Reports success after a
/// short delay so the engine run flow (progress updates, UI surface) can be
/// exercised without a real target. Never enqueued on device builds.
@interface RLXEngineMockTask : RLXEngineTask
@end

NS_ASSUME_NONNULL_END
