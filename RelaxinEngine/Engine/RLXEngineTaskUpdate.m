//
//  RLXEngineTaskUpdate.m
//  RelaxinEngine
//

#import "RLXEngineTaskUpdate.h"

@implementation RLXEngineTaskUpdate

- (instancetype)initWithStage:(RLXEngineStage)stage
                      message:(NSString *)message
                     position:(NSUInteger)position
                        count:(NSUInteger)count
                       status:(RLXEngineTaskStatus)status {
    self = [super init];
    if (self) {
        _stage = stage;
        _message = [message copy];
        _position = position;
        _count = count;
        _status = status;
    }
    return self;
}

@end
