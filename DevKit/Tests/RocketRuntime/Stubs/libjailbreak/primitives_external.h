/*
 * Enough of libjailbreak's primitive table for the runtime to compile on the
 * host.
 *
 * The runtime reaches two of its members. Mirroring the whole thing would tie
 * this test to a vendored header it is not testing; what matters is that the
 * names and signatures the runtime uses are the real ones.
 */

#ifndef ROCKET_RUNTIME_TEST_PRIMITIVES_EXTERNAL_H
#define ROCKET_RUNTIME_TEST_PRIMITIVES_EXTERNAL_H

#include <stddef.h>
#include <stdint.h>

struct kernel_primitives {
    int (*kreadbuf)(uint64_t kaddr, void *output, size_t size);
    int (*kwritebuf)(uint64_t kaddr, const void *input, size_t size);
    int (*physreadbuf)(uint64_t physaddr, void *output, size_t size);
    int (*physwritebuf)(uint64_t physaddr, const void *input, size_t size);
};

extern struct kernel_primitives gPrimitives;

#endif
