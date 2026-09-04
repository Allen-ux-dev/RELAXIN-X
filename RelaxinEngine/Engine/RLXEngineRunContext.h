//
//  RLXEngineRunContext.h
//  RelaxinEngine
//

#import <Foundation/Foundation.h>

#import "RLXEngine.h"

@class RLXKernelAccess;
@class RLXKernelInfo;
@class RLXKernelOffsetProfile;

NS_ASSUME_NONNULL_BEGIN

/// Queue-confined values produced and consumed by one engine run.
@interface RLXEngineRunContext : NSObject

@property(nonatomic, copy, readonly) NSDictionary<RLXEngineManifestKey, NSString *> *manifest;
@property(nonatomic, strong, readonly) RLXRuntimeEnvironment *runtimeEnvironment;
@property(nonatomic, copy, readonly) NSArray<NSString *> *additionalBootstrapPackageResourceNames;
@property(nonatomic, copy, nullable) NSDictionary<RLXEngineManifestKey, NSString *> *confirmedTarget;
@property(nonatomic, copy, nullable) NSString *kernelcachePath;
/// Precomputed kernelcache offsets for this target, when the app ships them.
///
/// Set by stage 02 in place of `kernelcachePath`: the two are alternatives, and
/// exactly one of them is what the later stages read the kernel layout from.
/// Stages must prefer this and treat a missing kernelcache as an error only
/// when it is nil as well.
@property(nonatomic, strong, nullable) RLXKernelOffsetProfile *kernelOffsetProfile;
@property(nonatomic, strong, nullable) RLXKernelAccess *kernelAccess;
/// Kernel information published by stage 04, for the stages that follow it.
///
/// Carrying it here is what keeps later stages off libjailbreak's `gSystemInfo`
/// and `gPrimitives` globals, which sit two layers below them.
@property(nonatomic, strong, nullable) RLXKernelInfo *kernelInfo;

/**
 * Retires the run's kernel access and writes the finalization status to
 * `status`. Returns NO when the run holds no access, leaving `status` untouched.
 *
 * Finalizing and forgetting are separate on purpose. The task queue clears the
 * reference whatever the status, because it is already reporting a failure;
 * the userspace-reboot and post-removal stages keep theirs on failure so the
 * queue can finalize again and record the cleanup status in the diagnostic.
 * Ordering is the caller's too: the userspace-reboot stage must call this
 * while its carrier is still suspended, and that ordering is the point, so
 * this does not hide it.
 */
- (BOOL)finalizeKernelAccessReturningStatus:(int *)status;

/// Forgets the kernel access and the kernel information published with it.
- (void)discardKernelAccess;

- (instancetype)initWithManifest:(NSDictionary<RLXEngineManifestKey, NSString *> *)manifest
                         runtimeEnvironment:(RLXRuntimeEnvironment *)runtimeEnvironment
    additionalBootstrapPackageResourceNames:(NSArray<NSString *> *)packageResourceNames NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithManifest:(NSDictionary<RLXEngineManifestKey, NSString *> *)manifest
              runtimeEnvironment:(RLXRuntimeEnvironment *)runtimeEnvironment;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
