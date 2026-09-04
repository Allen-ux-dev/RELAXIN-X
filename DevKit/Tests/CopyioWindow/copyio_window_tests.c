/*
 * Contract tests for the window copy_validate() will accept.
 *
 * The cost of getting this predicate wrong is asymmetric: too wide and the
 * device panics, too narrow and the exploit fails soft. It has already been
 * wrong once — the guard in DarkSword tested a band with its bounds crossed, so
 * it accepted everything for a fortnight — which is why the boundaries are
 * asserted here rather than trusted to a reading of the constants.
 */

#include "CopyioWindow.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

/// Both halves of the window, at their first and last accepted address.
static void test_window_edges(void) {
    assert(rocket_copyio_window_contains(ROCKET_COPYIO_MSERIES_MIN, false));
    assert(rocket_copyio_window_contains(ROCKET_COPYIO_MSERIES_MAX - 1, false));
    assert(!rocket_copyio_window_contains(ROCKET_COPYIO_MSERIES_MIN - 1, false));
    assert(!rocket_copyio_window_contains(ROCKET_COPYIO_MSERIES_MAX, false));

    assert(rocket_copyio_window_contains(ROCKET_COPYIO_MOBILE_MIN, false));
    assert(rocket_copyio_window_contains(ROCKET_COPYIO_MOBILE_MAX - 1, false));
    assert(!rocket_copyio_window_contains(ROCKET_COPYIO_MOBILE_MIN - 1, false));
    assert(!rocket_copyio_window_contains(ROCKET_COPYIO_MOBILE_MAX, false));

    /* The two ranges are disjoint, and the gap between them is not the window. */
    assert(ROCKET_COPYIO_MSERIES_MAX < ROCKET_COPYIO_MOBILE_MIN);
    assert(!rocket_copyio_window_contains(ROCKET_COPYIO_MSERIES_MAX, false));
    assert(!rocket_copyio_window_contains(ROCKET_COPYIO_MOBILE_MIN - 1, false));
}

/**
 * The predicate is satisfiable, and not by everything.
 *
 * Both halves of the bug this replaced: bounds that no address could satisfy,
 * and — had they been written the other way round — bounds that every address
 * satisfies.
 */
static void test_predicate_is_not_degenerate(void) {
    static const uint64_t probes[] = {
        0,
        UINT64_C(0x0000000100000000),
        UINT64_C(0xFFFFF00000000000),
        ROCKET_COPYIO_MSERIES_MIN,
        ROCKET_COPYIO_MSERIES_MIN + UINT64_C(0x8000000000),
        ROCKET_COPYIO_MSERIES_MAX,
        UINT64_C(0xFFFFFF8000000000),
        ROCKET_COPYIO_MOBILE_MIN,
        ROCKET_COPYIO_MOBILE_MIN + UINT64_C(0x1000000000),
        ROCKET_COPYIO_MOBILE_MAX,
        UINT64_C(0xFFFFFFFFFFFFFFF8),
    };

    unsigned accepted = 0;
    unsigned rejected = 0;
    for (size_t index = 0; index < sizeof(probes) / sizeof(probes[0]); index++) {
        if (rocket_copyio_window_contains(probes[index], false)) {
            accepted++;
        } else {
            rejected++;
        }
    }
    assert(accepted > 0);
    assert(rejected > 0);
}

/**
 * The KRW band is wider than the window.
 *
 * rocket_is_kaddr_valid() accepts the whole top 2^44, which is why the accessors
 * above it had to stop using it as their precondition: an address it accepts can
 * be one the primitive refuses, and a refused read used to come back as zero.
 */
static void test_krw_band_is_not_the_window(void) {
    const uint64_t krwBand = UINT64_C(0xFFFFF00000000000);
    assert((krwBand & UINT64_C(0xfffff00000000000)) == UINT64_C(0xfffff00000000000));
    assert(!rocket_copyio_window_contains(krwBand, false));
}

/**
 * The primitive reads in 32-byte units, so an address inside the window can
 * still have its access leave it.
 *
 * This is the residue the scalar accessors carry: eight bytes at the top of the
 * window pass their own check, and the fixed-width access underneath does not.
 * Asserting it here is what keeps it a known edge rather than a surprise.
 */
static void test_fixed_width_access_can_leave_the_window(void) {
    const uint64_t last = ROCKET_COPYIO_MOBILE_MAX - 8;
    assert(rocket_copyio_window_contains(last, false));
    assert(rocket_copyio_window_contains(last + 7, false));
    assert(!rocket_copyio_window_contains(last + 31, false));
}

/// The M-series exception widens the window, and only where it is enabled.
static void test_signed_pointer_exception(void) {
    const uint64_t signedField = UINT64_C(0xFFFF123456789000);
    assert(!rocket_copyio_window_contains(signedField, false));
    assert(rocket_copyio_window_contains(signedField, true));

    const uint64_t secondHalf = UINT64_C(0xFFFE000000000008);
    assert(!rocket_copyio_window_contains(secondHalf, false));
    assert(rocket_copyio_window_contains(secondHalf, true));

    /* Null is never in the window, exception or not. */
    assert(!rocket_copyio_window_contains(0, true));
    assert(!rocket_copyio_window_contains(0, false));

    /* And the exception is the top two halves only, not everything. */
    assert(!rocket_copyio_window_contains(UINT64_C(0xFFFD000000000008), true));
    assert(!rocket_copyio_window_contains(UINT64_C(0x0000000100000000), true));
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <case>\n", argv[0]);
        return 2;
    }

    const char *name = argv[1];
    if (strcmp(name, "edges") == 0) {
        test_window_edges();
    } else if (strcmp(name, "not-degenerate") == 0) {
        test_predicate_is_not_degenerate();
    } else if (strcmp(name, "krw-band") == 0) {
        test_krw_band_is_not_the_window();
    } else if (strcmp(name, "fixed-width") == 0) {
        test_fixed_width_access_can_leave_the_window();
    } else if (strcmp(name, "signed-pointers") == 0) {
        test_signed_pointer_exception();
    } else {
        fprintf(stderr, "unknown case: %s\n", name);
        return 2;
    }

    printf("ok %s\n", name);
    return 0;
}
