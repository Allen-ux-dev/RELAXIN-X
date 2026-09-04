#ifndef PHYSRW_PTE_WINDOW_H
#define PHYSRW_PTE_WINDOW_H

#include <stddef.h>
#include <stdint.h>

#define PHYSRW_PTE_WINDOW_PAGE_CAPACITY 63U

typedef struct {
    uint64_t firstPageAddress;
    uint64_t firstPageOffset;
    size_t pageCount;
} physrw_pte_window_range;

int physrw_pte_window_range_make(uint64_t address,
                                 uint64_t size,
                                 uint64_t pageSize,
                                 size_t pageCapacity,
                                 physrw_pte_window_range *rangeOut);

#endif
