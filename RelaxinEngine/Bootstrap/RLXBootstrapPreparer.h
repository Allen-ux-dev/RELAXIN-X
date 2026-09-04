//
//  RLXBootstrapPreparer.h
//  RelaxinEngine
//

#import <Foundation/Foundation.h>

@class RLXKernelAccess;

NS_ASSUME_NONNULL_BEGIN

/// Prepares one RootHide bootstrap up to, but not including, BaseBin trust.
@interface RLXBootstrapPreparer : NSObject

- (instancetype)initWithKernelAccess:(nullable RLXKernelAccess *)kernelAccess
               tweakInjectionEnabled:(BOOL)tweakInjectionEnabled
           requiresExistingBootstrap:(BOOL)requiresExistingBootstrap
                      resourceBundle:(NSBundle *)resourceBundle
               temporaryDirectoryURL:(NSURL *)temporaryDirectoryURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (nullable NSError *)prepare;

@end

NS_ASSUME_NONNULL_END
