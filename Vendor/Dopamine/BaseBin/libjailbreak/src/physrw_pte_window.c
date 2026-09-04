#include "physrw_pte_window.h"

#include <errno.h>
#include <limits.h>

int physrw_pte_window_range_make(uint64_t address,
                                 uint64_t size,
                                 uint64_t pageSize,
                                 size_t pageCapacity,
                                 physrw_pte_window_range *rangeOut) {
    if (!rangeOut || pageSize == 0 || (pageSize & (pageSize - 1)) != 0) {
        return EINVAL;
    }

    uint64_t lastAddress = address;
    if (size != 0) {
        if (size - 1 > UINT64_MAX - address)
            return EOVERFLOW;
        lastAddress = address + size - 1;
    }

    uint64_t pageMask = pageSize - 1;
    uint64_t firstPageAddress = address & ~pageMask;
    uint64_t lastPageAddress = lastAddress & ~pageMask;
    uint64_t pageCount = ((lastPageAddress - firstPageAddress) / pageSize) + 1;
    if (pageCount > SIZE_MAX || pageCount > pageCapacity)
        return E2BIG;

    *rangeOut = (physrw_pte_window_range){
        .firstPageAddress = firstPageAddress,
        .firstPageOffset = address & pageMask,
        .pageCount = (size_t)pageCount,
    };
    return 0;
}
