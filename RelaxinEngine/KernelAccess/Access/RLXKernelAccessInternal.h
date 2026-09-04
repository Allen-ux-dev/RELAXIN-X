//
//  RLXKernelAccessInternal.h
//  RelaxinEngine
//

#import "../RLXKernelAccess.h"

@class RLXKernelInfo;
@class RLXKernelAccessFailure;
@class RLXKernelOffsetProfile;

NS_ASSUME_NONNULL_BEGIN

@interface RLXKernelAccess (Internal)

/**
 * Builds a run from offsets the app already ships, skipping the kernelcache.
 *
 * Both arguments are optional and the profile wins when both are given. It is
 * declared here rather than beside the public initializer because the profile
 * type belongs to KernelAccess, and the kernel stage that constructs the access
 * is the only caller.
 */
- (instancetype)initWithKernelcachePath:(nullable NSString *)kernelcachePath
                          offsetProfile:(nullable RLXKernelOffsetProfile *)offsetProfile
                         resourceBundle:(NSBundle *)resourceBundle
                       dataDirectoryURL:(NSURL *)dataDirectoryURL;

/// Precomputed offsets for this device and build, when the run was given them.
@property(nonatomic, strong, readonly, nullable) RLXKernelOffsetProfile *offsetProfile;

@property(nonatomic, strong, readonly, nullable) RLXKernelInfo *kernelInfo;
/// Why the last `-build` failed, in KernelAccess terms. The kernel stage is
/// what turns it into an engine error.
@property(nonatomic, strong, readonly, nullable) RLXKernelAccessFailure *buildFailure;

/// Retires the Rocket runtime and invalidates every published callback.
- (int)finalizeAccess;

/// Performs checked access without exposing the callback table or its storage.
- (int)readKernelAtAddress:(uint64_t)address output:(void *)output size:(size_t)size;
- (int)writeKernelAtAddress:(uint64_t)address input:(const void *)input size:(size_t)size;

@end

NS_ASSUME_NONNULL_END
