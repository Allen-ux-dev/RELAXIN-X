//
//  RLXRuntimeEnvironment.h
//  RelaxinEngine
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Immutable resources and writable directories owned by one Relaxin host.
@interface RLXRuntimeEnvironment : NSObject <NSCopying>

@property(nonatomic, strong, readonly) NSBundle *resourceBundle;
@property(nonatomic, copy, readonly) NSURL *dataDirectoryURL;
@property(nonatomic, copy, readonly) NSURL *cacheDirectoryURL;
@property(nonatomic, copy, readonly) NSURL *temporaryDirectoryURL;

/// The standalone app's main bundle, Documents, Caches, and temporary directory.
@property(class, nonatomic, readonly) RLXRuntimeEnvironment *defaultEnvironment;

- (nullable instancetype)initWithResourceBundle:(NSBundle *)resourceBundle
                               dataDirectoryURL:(NSURL *)dataDirectoryURL
                              cacheDirectoryURL:(NSURL *)cacheDirectoryURL
                          temporaryDirectoryURL:(NSURL *)temporaryDirectoryURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
