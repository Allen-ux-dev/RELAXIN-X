//
//  RLXXPFSession.h
//  RelaxinEngine
//
//  Scoped access to the libxpf dylib embedded in the app bundle.
//

#import <Foundation/Foundation.h>

@class RLXKernelInfo;
@class RLXKernelAccessFailure;
@class RLXKernelOffsetProfile;

NS_ASSUME_NONNULL_BEGIN

/// Owns exactly one XPF global session and stops it during deallocation.
@interface RLXXPFSession : NSObject

@property(nonatomic, readonly) uint64_t staticKernelBase;
@property(nonatomic, readonly, getter=isArm64eKernel) BOOL arm64eKernel;
@property(nonatomic, readonly, getter=isSPTMDevice) BOOL SPTMDevice;
@property(nonatomic, copy, readonly) NSString *xnuBuild;
@property(nonatomic, copy, readonly) NSString *osVersion;

- (nullable instancetype)initWithKernelcachePath:(NSString *)kernelcachePath
                                  resourceBundle:(NSBundle *)resourceBundle
                                         failure:(RLXKernelAccessFailure *_Nullable *_Nullable)failure
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Resolves one required XPF item. A zero result is reported as a failure.
- (uint64_t)resolveRequiredItem:(NSString *)name failure:(RLXKernelAccessFailure *_Nullable *_Nullable)failure;

/// Applies Dopamine's supported XPF sets to libjailbreak's system information.
- (BOOL)initializeSystemInformationForLiveKernelBase:(uint64_t)liveKernelBase
                                             failure:(RLXKernelAccessFailure *_Nullable *_Nullable)failure;

/**
 * Runs the complete post-exploitation XPF pass over `path` and returns the
 * patchfinder snapshot, opening and closing its own session.
 *
 * This publishes runtime state as a side effect, which is why it belongs to the
 * session rather than to its caller: it sets Rocket's `kernel_slide`,
 * libjailbreak's `gSystemInfo.kernelConstant.slide`, and on SPTM devices
 * `gSystemInfo.relaxinKernelSymbol.sptm_args`.
 *
 * Must run after Rocket has published stable access — `liveKernelBase` is the
 * live base the slide is derived from, and the SPTM arguments slot is read back
 * from Rocket.
 */
+ (nullable RLXKernelInfo *)analyzeKernelcacheAtPath:(NSString *)path
                                      resourceBundle:(NSBundle *)resourceBundle
                                      liveKernelBase:(uint64_t)liveKernelBase
                                             failure:(RLXKernelAccessFailure *_Nullable *_Nullable)failure;

/**
 * The same pass, from offsets the app already ships, with no XPF session and no
 * kernelcache on disk.
 *
 * Identical in effect to `+analyzeKernelcacheAtPath:` for the kernelcache the
 * profile was generated from: it publishes the same slide, the same libjailbreak
 * offsets, and the same SPTM arguments slot, and returns the same snapshot.
 */
+ (nullable RLXKernelInfo *)analyzeOffsetProfile:(RLXKernelOffsetProfile *)profile
                                  liveKernelBase:(uint64_t)liveKernelBase
                                         failure:(RLXKernelAccessFailure *_Nullable *_Nullable)failure;

@end

NS_ASSUME_NONNULL_END
