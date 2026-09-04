//
//  RLXEngineMockTask.m
//  RelaxinEngine
//

#import "RLXEngineMockTask.h"

#import "../../Log/RLXEngineLog.h"

@implementation RLXEngineMockTask

- (nullable NSError *)execute {
    // Keep the stage visible long enough for progress UI to be observable.
    [NSThread sleepForTimeInterval:0.8];

    NSString *message = [NSString stringWithFormat:@"mock stage succeeded: %@", self.name];
    rlx_engine_log(RLX_ENGINE_LOG_INFO, "RLXEngineMock", message.UTF8String);
    return nil;
}

@end
