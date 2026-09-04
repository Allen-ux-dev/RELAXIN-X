//
//  RLXKernelAccess.h
//  RelaxinEngine
//
//  Minimal handoff from an exploit-owned KRW/PHYRW backend to the engine.
//

#ifndef RLX_KERNEL_ACCESS_H
#define RLX_KERNEL_ACCESS_H

#include <RelaxinEngine/RLXKernelLayout.h>

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RLX_KERNEL_ACCESS_VERSION 2U

/**
 * Names the exploit run that published this access.
 *
 * Every callback takes it, and every callback refuses a token that is not the
 * live one. The exploit backend is process-global, so the function pointers
 * cannot say which run they belong to on their own: a table kept across a
 * finalize would otherwise read and write through whatever run acquired the
 * backend next. Zero is never issued and is always refused.
 */
typedef uint64_t rlx_kernel_access_token;

typedef int (*_Nullable rlx_kernel_read)(rlx_kernel_access_token token,
                                         uint64_t kernel_address,
                                         void *_Nonnull output,
                                         size_t size);
typedef int (*_Nullable rlx_kernel_write)(rlx_kernel_access_token token,
                                          uint64_t kernel_address,
                                          const void *_Nonnull input,
                                          size_t size);
typedef int (*_Nullable rlx_physical_read)(rlx_kernel_access_token token,
                                           uint64_t physical_address,
                                           void *_Nonnull output,
                                           size_t size);
typedef int (*_Nullable rlx_physical_write)(rlx_kernel_access_token token,
                                            uint64_t physical_address,
                                            const void *_Nonnull input,
                                            size_t size);
typedef int (*_Nullable rlx_kernel_access_finalize)(rlx_kernel_access_token token);

/// Stable kernel access published by one exploit run.
///
/// Every access callback returns zero on success and a nonzero errno-style
/// status on failure. It owns unaligned, cross-page, and arbitrary-length
/// transfers, and returns ENOTSUP once `token` is no longer the live run —
/// including while finalization is in progress. `finalize` is called exactly
/// once, by the holder of `token`, and invalidates the callbacks; a second call
/// reports EALREADY rather than retiring somebody else's run.
typedef struct rlx_kernel_access {
    uint32_t version;
    uint32_t size;
    rlx_kernel_access_token token;
    rlx_kernel_layout layout;

    rlx_kernel_read kernel_read;
    rlx_kernel_write kernel_write;
    rlx_physical_read physical_read;
    rlx_physical_write physical_write;
    rlx_kernel_access_finalize finalize;
} rlx_kernel_access;

#ifdef __cplusplus
}
#endif

#ifdef __OBJC__

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Owns the stable kernel access produced by one exploit run.
@interface RLXKernelAccess : NSObject

/// The kernelcache the run reads its layout from, or nil when the run was
/// given a bundled offset profile instead. Exactly one of the two is set.
@property(nonatomic, copy, readonly, nullable) NSString *kernelcachePath;
/// Whether the validated callbacks are available for use.
@property(nonatomic, readonly, getter=isActive) BOOL active;
/// An owned, immutable-by-contract value snapshot. It remains valid after
/// `active` becomes false during finalization.
@property(nonatomic, readonly) rlx_kernel_layout layout;
/// Whether the process-wide bootstrap identity transaction has committed.
///
/// Read-only to everything outside the framework. The transaction is committed
/// by `-beginBootstrapIdentity` in the internal BootstrapIdentity category,
/// which only privilege escalation calls.
@property(nonatomic, readonly, getter=isBootstrapIdentityActive) BOOL bootstrapIdentityActive;

/**
 * Builds a run against a kernelcache on disk using host-owned resources.
 *
 * The path is nullable because a run may instead be given precomputed offsets
 * through the internal initializer; an instance with neither has no source for
 * the kernel layout and fails its `-build` rather than starting one.
 */
- (instancetype)initWithKernelcachePath:(nullable NSString *)kernelcachePath
                         resourceBundle:(NSBundle *)resourceBundle
                       dataDirectoryURL:(NSURL *)dataDirectoryURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Builds the access handoff. Returns zero on success or an errno-style status.
- (int)build;

@end

NS_ASSUME_NONNULL_END

#endif /* __OBJC__ */

#endif /* RLX_KERNEL_ACCESS_H */
