//
//  RLXKernelLayout.h
//  RelaxinEngine
//
//  Stable runtime kernel layout published with kernel access.
//

#ifndef RLX_KERNEL_LAYOUT_H
#define RLX_KERNEL_LAYOUT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RLX_KERNEL_LAYOUT_VERSION 1U

typedef struct rlx_kernel_layout {
    uint32_t version;
    uint32_t size;
    uint32_t page_size;
    uint32_t reserved;

    uint64_t kernel_base;
    uint64_t kernel_slide;
    uint64_t cpu_ttep;
    uint64_t virtual_base;
    uint64_t physical_base;
    uint64_t physical_size;
} rlx_kernel_layout;

#ifdef __cplusplus
}
#endif

#endif /* RLX_KERNEL_LAYOUT_H */
