#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "primitives_external.h"
#include "trustcache_nokcall_word32.h"

#define TEST_PAGE_SIZE UINT64_C(0x4000)
#define TEST_ADDRESS UINT64_C(0x1000)
#define TEST_PHYSICAL_ADDRESS UINT64_C(0x2000)
#define TEST_SECOND_PHYSICAL_ADDRESS UINT64_C(0x6000)
#define TEST_PAGE_LAST_ADDRESS (TEST_PAGE_SIZE - sizeof(uint32_t))
#define TEST_PAGE_LAST_PHYSICAL_ADDRESS \
	(TEST_PAGE_SIZE * 2 - sizeof(uint32_t))
#define TEST_FOREIGN_WORD UINT32_C(0xdecafbad)

#define CHECK(condition) \
	do { \
		if (!(condition)) { \
			fprintf(stderr, "check failed at line %d: %s\n", \
			        __LINE__, #condition); \
			return 1; \
		} \
	} while (0)

struct kernel_primitives gPrimitives;

typedef enum {
    FAKE_WRITE_DESIRED,
    FAKE_WRITE_NONE,
    FAKE_WRITE_FOREIGN,
} fake_write_effect;

static uint64_t gVirtualAddress;
static uint64_t gInitialPhysicalAddress;
static uint64_t gFinalPhysicalAddress;
static uint32_t gInitialPhysicalWord;
static uint32_t gFinalPhysicalWord;
static uint32_t gFailPhysicalReadCall;
static int gProtectedWriteStatus;
static fake_write_effect gProtectedWriteEffect;
static bool gTranslationDrifts;
static unsigned gPhysicalReadCount;
static unsigned gProtectedWriteCount;
static unsigned gMappedAccessCount;
static unsigned gTranslationCount;

uint64_t get_vm_real_kernel_page_size(void) {
    return TEST_PAGE_SIZE;
}

static uint64_t fake_translate(uint64_t address) {
    if (address != gVirtualAddress)
        return 0;
    gTranslationCount++;
    if (gTranslationDrifts && gTranslationCount > 1) {
        return gFinalPhysicalAddress;
    }
    return gInitialPhysicalAddress;
}

uint64_t kvtophys(uint64_t address) {
    return fake_translate(address);
}

static uint32_t *fake_physical_word(uint64_t physicalAddress) {
    if (physicalAddress == gInitialPhysicalAddress) {
        return &gInitialPhysicalWord;
    }
    if (gFinalPhysicalAddress != gInitialPhysicalAddress && physicalAddress == gFinalPhysicalAddress) {
        return &gFinalPhysicalWord;
    }
    return NULL;
}

static int fake_physread(uint64_t physicalAddress, void *output, size_t size) {
    uint32_t *word = fake_physical_word(physicalAddress);
    if (!word || !output || size != sizeof(*word)) {
        return EFAULT;
    }
    gPhysicalReadCount++;
    if (gFailPhysicalReadCall != 0 && gPhysicalReadCount == gFailPhysicalReadCall) {
        return EIO;
    }
    memcpy(output, word, sizeof(*word));
    return 0;
}

static int fake_protected_write(uint64_t address, uint32_t value) {
    if (address != gVirtualAddress)
        return EFAULT;
    switch (gProtectedWriteEffect) {
        case FAKE_WRITE_DESIRED:
            gInitialPhysicalWord = value;
            break;
        case FAKE_WRITE_NONE:
            break;
        case FAKE_WRITE_FOREIGN:
            gInitialPhysicalWord = TEST_FOREIGN_WORD;
            break;
    }
    gProtectedWriteCount++;
    return gProtectedWriteStatus;
}

static int fake_mapped_access(uint64_t physicalAddress, uint64_t size, kernel_map_accessor accessor) {
    uint32_t *word = fake_physical_word(physicalAddress);
    if (!word || size != sizeof(*word) || !accessor) {
        return EFAULT;
    }
    gMappedAccessCount++;
    accessor(word);
    return 0;
}

static void reset_primitives_at(uint64_t virtualAddress, uint64_t physicalAddress, uint32_t word) {
    memset(&gPrimitives, 0, sizeof(gPrimitives));
    gPrimitives.physreadbuf = fake_physread;
    gPrimitives.kvtophys = fake_translate;
    gVirtualAddress = virtualAddress;
    gInitialPhysicalAddress = physicalAddress;
    gFinalPhysicalAddress = physicalAddress;
    gInitialPhysicalWord = word;
    gFinalPhysicalWord = word;
    gFailPhysicalReadCall = 0;
    gProtectedWriteStatus = 0;
    gProtectedWriteEffect = FAKE_WRITE_DESIRED;
    gTranslationDrifts = false;
    gPhysicalReadCount = 0;
    gProtectedWriteCount = 0;
    gMappedAccessCount = 0;
    gTranslationCount = 0;
}

static void reset_primitives(uint32_t word) {
    reset_primitives_at(TEST_ADDRESS, TEST_PHYSICAL_ADDRESS, word);
}

static int test_protected_writer_without_mapped_access(void) {
    const uint32_t expected = UINT32_C(0x11223344);
    const uint32_t desired = UINT32_C(0x55667788);
    reset_primitives(expected);
    gPrimitives.protectedKwrite32 = fake_protected_write;

    CHECK(tcn_word32_environment_status() == 0);
    uint32_t observed = 0;
    CHECK(tcn_word32_replace(TEST_ADDRESS, expected, desired, &observed) == 0);
    CHECK(observed == desired);
    CHECK(gInitialPhysicalWord == desired);
    CHECK(gPhysicalReadCount == 2);
    CHECK(gProtectedWriteCount == 1);
    CHECK(gMappedAccessCount == 0);
    return 0;
}

static int test_mapped_single_store_fallback(void) {
    const uint32_t expected = UINT32_C(0xaabbccdd);
    const uint32_t desired = UINT32_C(0x01020304);
    reset_primitives(expected);
    gPrimitives.physaccess_mapped = fake_mapped_access;

    CHECK(tcn_word32_environment_status() == 0);
    uint32_t observed = 0;
    CHECK(tcn_word32_replace(TEST_ADDRESS, expected, desired, &observed) == 0);
    CHECK(observed == desired);
    CHECK(gInitialPhysicalWord == desired);
    CHECK(gPhysicalReadCount == 2);
    CHECK(gProtectedWriteCount == 0);
    CHECK(gMappedAccessCount == 1);
    return 0;
}

static int test_missing_both_writers_fails_closed(void) {
    reset_primitives(UINT32_C(0x12345678));

    CHECK(tcn_word32_environment_status() == ENOTSUP);
    uint32_t observed = UINT32_MAX;
    CHECK(tcn_word32_replace(TEST_ADDRESS, gInitialPhysicalWord, UINT32_C(0x87654321), &observed) == ENOTSUP);
    CHECK(observed == 0);
    CHECK(gPhysicalReadCount == 0);
    CHECK(gProtectedWriteCount == 0);
    CHECK(gMappedAccessCount == 0);
    return 0;
}

static int test_read_and_translation_are_required(void) {
    reset_primitives(UINT32_C(0x12345678));
    gPrimitives.protectedKwrite32 = fake_protected_write;
    gPrimitives.physreadbuf = NULL;
    CHECK(tcn_word32_environment_status() == ENOTSUP);

    reset_primitives(UINT32_C(0x12345678));
    gPrimitives.protectedKwrite32 = fake_protected_write;
    gPrimitives.kvtophys = NULL;
    CHECK(tcn_word32_environment_status() == ENOTSUP);
    return 0;
}

static int test_writer_error_before_store_preserves_old(void) {
    const uint32_t expected = UINT32_C(0x11223344);
    const uint32_t desired = UINT32_C(0x55667788);
    reset_primitives(expected);
    gPrimitives.protectedKwrite32 = fake_protected_write;
    gProtectedWriteEffect = FAKE_WRITE_NONE;
    gProtectedWriteStatus = EIO;

    uint32_t observed = 0;
    CHECK(tcn_word32_replace(TEST_ADDRESS, expected, desired, &observed) == EINPROGRESS);
    CHECK(observed == expected);
    CHECK(gInitialPhysicalWord == expected);
    CHECK(gPhysicalReadCount == 2);
    CHECK(gProtectedWriteCount == 1);
    return 0;
}

static int test_writer_error_after_store_commits_desired(void) {
    const uint32_t expected = UINT32_C(0xaabbccdd);
    const uint32_t desired = UINT32_C(0x01020304);
    reset_primitives(expected);
    gPrimitives.protectedKwrite32 = fake_protected_write;
    gProtectedWriteEffect = FAKE_WRITE_DESIRED;
    gProtectedWriteStatus = EIO;

    uint32_t observed = 0;
    CHECK(tcn_word32_replace(TEST_ADDRESS, expected, desired, &observed) == EINPROGRESS);
    CHECK(observed == desired);
    CHECK(gInitialPhysicalWord == desired);
    CHECK(gPhysicalReadCount == 2);
    CHECK(gProtectedWriteCount == 1);
    return 0;
}

static int test_store_then_readback_failure_leaves_desired(void) {
    const uint32_t expected = UINT32_C(0x13572468);
    const uint32_t desired = UINT32_C(0x24681357);
    reset_primitives(expected);
    gPrimitives.protectedKwrite32 = fake_protected_write;
    gFailPhysicalReadCall = 2;

    uint32_t observed = 0;
    CHECK(tcn_word32_replace(TEST_ADDRESS, expected, desired, &observed) == EIO);
    /*
	 * The caller only has the pre-store observation, but durable memory already
	 * contains the complete desired word. Recovery must reobserve it.
	 */
    CHECK(observed == expected);
    CHECK(gInitialPhysicalWord == desired);
    CHECK(gPhysicalReadCount == 2);
    CHECK(gProtectedWriteCount == 1);
    return 0;
}

static int test_second_translation_drift_fails_closed(void) {
    const uint32_t expected = UINT32_C(0x0badcafe);
    const uint32_t desired = UINT32_C(0x600df00d);
    reset_primitives(expected);
    gPrimitives.protectedKwrite32 = fake_protected_write;
    gTranslationDrifts = true;
    gFinalPhysicalAddress = TEST_SECOND_PHYSICAL_ADDRESS;
    gFinalPhysicalWord = expected;

    uint32_t observed = 0;
    CHECK(tcn_word32_replace(TEST_ADDRESS, expected, desired, &observed) == ESTALE);
    CHECK(gTranslationCount == 2);
    CHECK(observed == expected);
    CHECK(gInitialPhysicalWord == desired);
    CHECK(gFinalPhysicalWord == expected);
    CHECK(gProtectedWriteCount == 1);
    return 0;
}

static int test_foreign_observed_word_fails_closed(void) {
    const uint32_t expected = UINT32_C(0x10203040);
    const uint32_t desired = UINT32_C(0x50607080);
    reset_primitives(expected);
    gPrimitives.protectedKwrite32 = fake_protected_write;
    gProtectedWriteEffect = FAKE_WRITE_FOREIGN;

    uint32_t observed = 0;
    CHECK(tcn_word32_replace(TEST_ADDRESS, expected, desired, &observed) == EIO);
    CHECK(observed == TEST_FOREIGN_WORD);
    CHECK(gInitialPhysicalWord == TEST_FOREIGN_WORD);
    CHECK(gProtectedWriteCount == 1);
    return 0;
}

static int test_last_word_of_page_and_boundary(void) {
    const uint32_t expected = UINT32_C(0x89abcdef);
    const uint32_t desired = UINT32_C(0x76543210);
    reset_primitives_at(TEST_PAGE_LAST_ADDRESS, TEST_PAGE_LAST_PHYSICAL_ADDRESS, expected);
    gPrimitives.protectedKwrite32 = fake_protected_write;

    uint32_t observed = 0;
    CHECK(tcn_word32_replace(TEST_PAGE_LAST_ADDRESS, expected, desired, &observed) == 0);
    CHECK(observed == desired);
    CHECK(gInitialPhysicalWord == desired);
    CHECK(gTranslationCount == 2);

    /* A word starting inside the final word would cross the page unaligned. */
    reset_primitives_at(TEST_PAGE_LAST_ADDRESS, TEST_PAGE_LAST_PHYSICAL_ADDRESS, expected);
    gPrimitives.protectedKwrite32 = fake_protected_write;
    observed = UINT32_MAX;
    CHECK(tcn_word32_replace(TEST_PAGE_LAST_ADDRESS + 2, expected, desired, &observed) == EINVAL);
    CHECK(observed == UINT32_MAX);
    CHECK(gTranslationCount == 0);
    CHECK(gPhysicalReadCount == 0);
    CHECK(gProtectedWriteCount == 0);
    return 0;
}

int main(void) {
    if (test_protected_writer_without_mapped_access() != 0)
        return 1;
    if (test_mapped_single_store_fallback() != 0)
        return 1;
    if (test_missing_both_writers_fails_closed() != 0)
        return 1;
    if (test_read_and_translation_are_required() != 0)
        return 1;
    if (test_writer_error_before_store_preserves_old() != 0)
        return 1;
    if (test_writer_error_after_store_commits_desired() != 0)
        return 1;
    if (test_store_then_readback_failure_leaves_desired() != 0)
        return 1;
    if (test_second_translation_drift_fails_closed() != 0)
        return 1;
    if (test_foreign_observed_word_fails_closed() != 0)
        return 1;
    if (test_last_word_of_page_and_boundary() != 0)
        return 1;
    puts("trustcache_nokcall_word32: primitive contracts passed");
    return 0;
}
