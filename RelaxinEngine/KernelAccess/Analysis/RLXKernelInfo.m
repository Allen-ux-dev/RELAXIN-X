//
//  RLXKernelInfo.m
//  RelaxinEngine
//

#import "RLXKernelInfo.h"

#include <stdbool.h>
#include <string.h>

static bool rlx_kernel_patchfinder_info_is_valid(const rlx_kernel_patchfinder_info *info) {
    return info->static_base != 0 && info->cpu_ttep_symbol != 0 && info->virtual_base_symbol != 0
        && info->physical_base_symbol != 0 && info->physical_size_symbol != 0 && info->ptov_table_symbol != 0
        && info->vm_map_pmap_offset != 0 && info->arm_tt_l1_index_mask != 0 && info->t1sz_boot != 0
        && info->kernel_el != 0 && info->xnu_major != 0 && info->is_sptm <= 1 && info->reserved == 0;
}

static bool rlx_kernel_layout_is_valid(const rlx_kernel_layout *layout, uint64_t staticBase) {
    if (layout->version != RLX_KERNEL_LAYOUT_VERSION || layout->size < sizeof(*layout) || layout->reserved != 0
        || layout->page_size == 0 || (layout->page_size & (layout->page_size - 1)) != 0
        || layout->kernel_base < staticBase || layout->kernel_slide != layout->kernel_base - staticBase
        || layout->cpu_ttep == 0 || layout->virtual_base == 0 || layout->physical_base == 0
        || layout->physical_size == 0) {
        return false;
    }

    return layout->physical_base <= UINT64_MAX - layout->physical_size;
}

@implementation RLXKernelInfo {
    rlx_kernel_info _infoStorage;
}

- (nullable instancetype)initWithPatchfinderInfo:(rlx_kernel_patchfinder_info)patchfinderInfo {
    if (!rlx_kernel_patchfinder_info_is_valid(&patchfinderInfo)) {
        return nil;
    }

    self = [super init];
    if (self) {
        _infoStorage.version = RLX_KERNEL_INFO_VERSION;
        _infoStorage.size = sizeof(_infoStorage);
        _infoStorage.phase = RLX_KERNEL_INFO_PHASE_PATCHFINDER_RESOLVED;
        _infoStorage.patchfinder = patchfinderInfo;
    }
    return self;
}

- (const rlx_kernel_info *)info {
    return &_infoStorage;
}

- (rlx_kernel_info_phase)phase {
    return (rlx_kernel_info_phase)_infoStorage.phase;
}

- (nullable RLXKernelInfo *)infoByAddingRuntimeLayout:(rlx_kernel_layout)layout {
    if (_infoStorage.phase != RLX_KERNEL_INFO_PHASE_PATCHFINDER_RESOLVED
        || !rlx_kernel_layout_is_valid(&layout, _infoStorage.patchfinder.static_base)) {
        return nil;
    }

    RLXKernelInfo *snapshot = [[RLXKernelInfo alloc] initWithPatchfinderInfo:_infoStorage.patchfinder];
    if (!snapshot) {
        return nil;
    }
    snapshot->_infoStorage.phase = RLX_KERNEL_INFO_PHASE_RUNTIME_RESOLVED;
    snapshot->_infoStorage.layout = layout;
    return snapshot;
}

- (uint64_t)kernelExceptionLevel {
    return _infoStorage.patchfinder.kernel_el;
}

- (BOOL)isSPTMKernel {
    return _infoStorage.patchfinder.is_sptm != 0;
}

@end
