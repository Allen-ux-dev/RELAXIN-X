//
//  RLXKernelInfo.h
//  RelaxinEngine
//
//  Immutable kernel information passed between engine tasks.
//

#ifndef RLX_KERNEL_INFO_H
#define RLX_KERNEL_INFO_H

#include <RelaxinEngine/RLXKernelLayout.h>

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RLX_KERNEL_INFO_VERSION 1U

typedef enum rlx_kernel_info_phase {
    RLX_KERNEL_INFO_PHASE_PATCHFINDER_RESOLVED = 1,
    RLX_KERNEL_INFO_PHASE_RUNTIME_RESOLVED = 2,
} rlx_kernel_info_phase;

/// Scalar results copied out of XPF before its session is stopped.
///
/// Every address in this structure is unslid unless its name says otherwise.
/// XPF-owned Mach-O and PFSection pointers must never be stored here.
typedef struct rlx_kernel_patchfinder_info {
    uint64_t static_base;
    uint64_t cpu_ttep_symbol;
    uint64_t virtual_base_symbol;
    uint64_t physical_base_symbol;
    uint64_t physical_size_symbol;
    uint64_t ptov_table_symbol;

    uint64_t vm_map_pmap_offset;
    uint64_t arm_tt_l1_index_mask;
    uint64_t t1sz_boot;
    uint64_t kernel_el;

    uint32_t xnu_major;
    uint32_t xnu_minor;
    uint32_t xnu_patch;
    uint32_t xnu_revision;
    uint32_t is_sptm;
    uint32_t reserved;
} rlx_kernel_patchfinder_info;

/// Versioned snapshot carried by RLXEngineRunContext.
typedef struct rlx_kernel_info {
    uint32_t version;
    uint32_t size;
    uint32_t phase;
    uint32_t reserved;

    rlx_kernel_patchfinder_info patchfinder;
    rlx_kernel_layout layout;
} rlx_kernel_info;

#ifdef __cplusplus
}
#endif

#ifdef __OBJC__

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Immutable Objective-C owner for one kernel-information snapshot.
@interface RLXKernelInfo : NSObject

@property(nonatomic, readonly) const rlx_kernel_info *info;
@property(nonatomic, readonly) rlx_kernel_info_phase phase;

/// Exception level the kernel runs at, from XPF's `kernelConstant.kernel_el`.
@property(nonatomic, readonly) uint64_t kernelExceptionLevel;

/// Whether this kernel is SPTM-protected, from XPF's own determination.
///
/// Equivalent to libjailbreak's `system_info_uses_sptm()` once kernel access is
/// built — that function reports `sptm_args != 0`, and the XPF pass publishes a
/// non-zero `sptm_args` exactly when this flag is set, failing the build if it
/// cannot. Reading it here keeps engine stages off libjailbreak's globals.
@property(nonatomic, readonly, getter=isSPTMKernel) BOOL SPTMKernel;

- (nullable instancetype)initWithPatchfinderInfo:(rlx_kernel_patchfinder_info)patchfinderInfo NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Returns a runtime-resolved snapshot without mutating the receiver.
- (nullable RLXKernelInfo *)infoByAddingRuntimeLayout:(rlx_kernel_layout)layout;

@end

NS_ASSUME_NONNULL_END

#endif /* __OBJC__ */

#endif /* RLX_KERNEL_INFO_H */
