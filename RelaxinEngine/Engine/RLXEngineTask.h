//
//  RLXEngineTask.h
//  RelaxinEngine
//

#import <Foundation/Foundation.h>

#import "RLXEngine.h"

@class RLXEngineRunContext;

NS_ASSUME_NONNULL_BEGIN

/// One synchronous unit of work executed by RLXEngineTaskQueue.
@interface RLXEngineTask : NSObject

@property(nonatomic, readonly) RLXEngineStage stage;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, strong, readonly) RLXEngineRunContext *context;

- (instancetype)initWithStage:(RLXEngineStage)stage context:(RLXEngineRunContext *)context NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Returns nil on success. Subclasses must override.
- (nullable NSError *)execute;

/// Standard failure for a task whose implementation has not landed.
- (NSError *)unavailableError;

@end

NS_ASSUME_NONNULL_END
