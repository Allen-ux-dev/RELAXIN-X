//
//  RLXBootstrapFinalizer.h
//  RelaxinEngine
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RLXBootstrapFinalizer : NSObject

+ (nullable NSError *)installBundledPackageNamed:(NSString *)name resourceBundle:(NSBundle *)resourceBundle;
+ (nullable NSError *)installExternalPackageAtPath:(NSString *)packagePath;

- (instancetype)initWithResourceBundle:(NSBundle *)resourceBundle
                 temporaryDirectoryURL:(NSURL *)temporaryDirectoryURL
        additionalPackageResourceNames:(NSArray<NSString *> *)packageResourceNames;
- (instancetype)initWithResourceBundle:(NSBundle *)resourceBundle
                 temporaryDirectoryURL:(NSURL *)temporaryDirectoryURL
        additionalPackageResourceNames:(NSArray<NSString *> *)packageResourceNames
                         installSileo:(BOOL)installSileo
                     zebraPackagePath:(nullable NSString *)zebraPackagePath NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithResourceBundle:(NSBundle *)resourceBundle temporaryDirectoryURL:(NSURL *)temporaryDirectoryURL;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (nullable NSError *)finalizeBootstrap;

@end

NS_ASSUME_NONNULL_END
