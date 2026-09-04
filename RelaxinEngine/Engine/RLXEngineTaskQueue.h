//
//  RLXEngineTaskQueue.h
//  RelaxinEngine
//

#import <Foundation/Foundation.h>

#import "RLXEngine.h"

@class RLXEngineTask;

NS_ASSUME_NONNULL_BEGIN

@interface RLXEngineTaskQueue : NSObject

- (void)enqueueTasks:(NSArray<RLXEngineTask *> *)tasks
       updateHandler:(nullable RLXEngineTaskUpdateHandler)updateHandler
          completion:(nullable RLXEngineCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END
