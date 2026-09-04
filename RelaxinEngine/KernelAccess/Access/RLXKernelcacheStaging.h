//
//  RLXKernelcacheStaging.h
//  RelaxinEngine
//
//  Publishing the kernelcache at the fixed path Rocket reads.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RLXKernelcacheStaging : NSObject

- (instancetype)initWithDataDirectoryURL:(NSURL *)dataDirectoryURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/**
 * The one place the Rocket kernelcache location is defined. Staging writes the
 * file here and Rocket is handed this exact path, so the staged file and the
 * analysed file cannot drift apart.
 */
@property(nonatomic, readonly) NSString *rocketKernelcachePath;

/**
 * Copies `sourcePath` into place through a uniquely named temporary and an
 * atomic rename, so a torn copy is never visible at the published path. A
 * no-op when the source already is the published path.
 *
 * Returns 0 on success, otherwise an errno value, and on failure writes the
 * operation that failed to `failureOperation` for the diagnostic.
 */
- (int)stageKernelcacheAtPath:(NSString *)sourcePath failureOperation:(NSString *_Nullable *_Nullable)failureOperation;

@end

NS_ASSUME_NONNULL_END
