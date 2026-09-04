//
//  RLXEngineRunContext.m
//  RelaxinEngine
//

#import "RLXEngineRunContext.h"

#import "../KernelAccess/Access/RLXKernelAccessInternal.h"

@implementation RLXEngineRunContext

- (instancetype)initWithManifest:(NSDictionary<RLXEngineManifestKey, NSString *> *)manifest
              runtimeEnvironment:(RLXRuntimeEnvironment *)runtimeEnvironment {
    return [self initWithManifest:manifest runtimeEnvironment:runtimeEnvironment
        additionalBootstrapPackageResourceNames:@[]];
}

- (instancetype)initWithManifest:(NSDictionary<RLXEngineManifestKey, NSString *> *)manifest
                         runtimeEnvironment:(RLXRuntimeEnvironment *)runtimeEnvironment
    additionalBootstrapPackageResourceNames:(NSArray<NSString *> *)packageResourceNames {
    self = [super init];
    if (self) {
        _manifest = [manifest copy];
        _runtimeEnvironment = runtimeEnvironment;
        _additionalBootstrapPackageResourceNames = [packageResourceNames copy];
    }
    return self;
}

- (BOOL)finalizeKernelAccessReturningStatus:(int *)status {
    RLXKernelAccess *kernelAccess = self.kernelAccess;
    if (!kernelAccess) {
        return NO;
    }
    int finalizeStatus = [kernelAccess finalizeAccess];
    if (status) {
        *status = finalizeStatus;
    }
    return YES;
}

- (void)discardKernelAccess {
    self.kernelAccess = nil;
    self.kernelInfo = nil;
}

@end
