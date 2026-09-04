//
//  RLXBootstrapRemovalTask.m
//  RelaxinEngine
//

#import "RLXBootstrapRemovalTask.h"

#import "../../../RelaxinPostJailbreak/Bootstrap/RLXBootstrapRemover.h"

@implementation RLXBootstrapRemovalTask

- (instancetype)initWithContext:(RLXEngineRunContext *)context {
    return [super initWithStage:RLXEngineStageBootstrapRemoval context:context];
}

- (nullable NSError *)execute {
    return [RLXBootstrapRemover removeBootstrap];
}

@end
