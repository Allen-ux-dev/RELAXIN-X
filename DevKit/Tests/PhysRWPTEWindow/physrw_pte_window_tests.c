#include "physrw_pte_window.h"

#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>

static const uint64_t pageSize = UINT64_C(0x4000);
static const size_t pageCapacity = PHYSRW_PTE_WINDOW_PAGE_CAPACITY;

static physrw_pte_window_range make_range(uint64_t address, uint64_t size) {
    physrw_pte_window_range range = {0};
    assert(physrw_pte_window_range_make(address, size, pageSize, pageCapacity, &range) == 0);
    return range;
}

static void test_single_page_ranges(void) {
    physrw_pte_window_range range = make_range(0x8123, 0);
    assert(range.firstPageAddress == 0x8000);
    assert(range.firstPageOffset == 0x123);
    assert(range.pageCount == 1);

    range = make_range(0x8001, pageSize - 1);
    assert(range.pageCount == 1);
}

static void test_cross_page_ranges(void) {
    physrw_pte_window_range range = make_range(0x8001, pageSize);
    assert(range.firstPageAddress == 0x8000);
    assert(range.firstPageOffset == 1);
    assert(range.pageCount == 2);

    range = make_range(0xBFFF, 2);
    assert(range.pageCount == 2);

    range = make_range(0x8123, (3 * pageSize) + 0x200);
    assert(range.pageCount == 4);
}

static void test_capacity(void) {
    physrw_pte_window_range range = {0};
    assert(physrw_pte_window_range_make(0, pageCapacity * pageSize, pageSize, pageCapacity, &range) == 0);
    assert(range.pageCount == pageCapacity);

    assert(physrw_pte_window_range_make(1, pageCapacity * pageSize, pageSize, pageCapacity, &range) == E2BIG);
}

static void test_invalid_ranges(void) {
    physrw_pte_window_range range = {0};
    assert(physrw_pte_window_range_make(UINT64_MAX - 7, 9, pageSize, pageCapacity, &range) == EOVERFLOW);
    assert(physrw_pte_window_range_make(0, 1, 0, pageCapacity, &range) == EINVAL);
    assert(physrw_pte_window_range_make(0, 1, 0x3000, pageCapacity, &range) == EINVAL);
    assert(physrw_pte_window_range_make(0, 1, pageSize, pageCapacity, NULL) == EINVAL);
}

int main(void) {
    test_single_page_ranges();
    test_cross_page_ranges();
    test_capacity();
    test_invalid_ranges();
    puts("physrw_pte_window: range contracts verified");
    return 0;
}
