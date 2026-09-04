/*
 * Contract tests for the Rocket runtime state machine.
 *
 * RLXRocketRuntime.c is compiled as-is against the stubs below: exploit_deinit,
 * kernel_exploit_finalize_handoff, and gPrimitives are the only things it
 * reaches outside itself, and each is scriptable here. Every interleaving the
 * runtime claims to survive is a case, because the claims are about states no
 * successful run ever visits — a second acquisition, a teardown that latches
 * Dirty, a token that outlived its run.
 */

#include "RLXRocketRuntime.h"

#include <libjailbreak/primitives_external.h>

#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* ---------------------------------------------------------------- */
/* Stubs standing in for the exploit backend                          */
/* ---------------------------------------------------------------- */

struct kernel_primitives gPrimitives;

static int g_deinitStatus;
static int g_finalizeHandoffStatus;
static unsigned g_deinitCalls;
static unsigned g_finalizeHandoffCalls;

int exploit_deinit(void) {
    g_deinitCalls++;
    return g_deinitStatus;
}

int kernel_exploit_finalize_handoff(void) {
    g_finalizeHandoffCalls++;
    return g_finalizeHandoffStatus;
}

/* ---------------------------------------------------------------- */
/* Scripted kernel read/write                                         */
/* ---------------------------------------------------------------- */

static atomic_uint g_readCalls;
static atomic_uint g_readsInFlight;
static atomic_uint g_readHold;
static uint64_t g_lastReadAddress;

static int fake_kread(uint64_t address, void *buffer, size_t size) {
    (void)buffer;
    (void)size;
    g_lastReadAddress = address;
    atomic_fetch_add(&g_readCalls, 1U);
    atomic_fetch_add(&g_readsInFlight, 1U);
    while (atomic_load(&g_readHold)) {
        usleep(1000);
    }
    atomic_fetch_sub(&g_readsInFlight, 1U);
    return 0;
}

static int fake_kwrite(uint64_t address, const void *buffer, size_t size) {
    (void)address;
    (void)buffer;
    (void)size;
    return 0;
}

/*
 * The runtime's state is process-global by design, so each case runs in its own
 * process. That is also the only way to test the Dirty latch, which is terminal
 * on purpose and has no reset.
 */
static void reset_stubs(void) {
    memset(&gPrimitives, 0, sizeof(gPrimitives));
    g_deinitStatus = 0;
    g_finalizeHandoffStatus = 0;
    g_deinitCalls = 0;
    g_finalizeHandoffCalls = 0;
    atomic_store(&g_readCalls, 0U);
    atomic_store(&g_readsInFlight, 0U);
    atomic_store(&g_readHold, 0U);
}

static rlx_rocket_runtime_token acquire_and_activate(void) {
    rlx_rocket_runtime_token token = 0;
    assert(rlx_rocket_runtime_acquire(&token) == 0);
    assert(token != 0);
    rlx_rocket_runtime_enter_darksword(token);
    rlx_rocket_runtime_enter_rocket_published(token);
    rlx_rocket_runtime_activate(token, fake_kread, fake_kwrite);
    assert(rlx_rocket_runtime_is_active(token));
    return token;
}

/* ---------------------------------------------------------------- */
/* Cases                                                              */
/* ---------------------------------------------------------------- */

/// One owner at a time, and the loser never receives a token.
static void test_owner_race(void) {
    rlx_rocket_runtime_token first = acquire_and_activate();

    rlx_rocket_runtime_token second = 0xAAAA;
    assert(rlx_rocket_runtime_acquire(&second) == EBUSY);
    assert(second == 0);
    assert(!rlx_rocket_runtime_is_active(second));

    /* The loser cannot retire the winner's runtime. */
    assert(rlx_rocket_runtime_finalize(second) == EALREADY);
    assert(rlx_rocket_runtime_is_active(first));
    assert(g_finalizeHandoffCalls == 0);
    assert(g_deinitCalls == 0);

    assert(rlx_rocket_runtime_finalize(first) == 0);
    assert(!rlx_rocket_runtime_is_active(first));
}

/// A token that outlived its run reaches nothing, including the run after it.
static void test_stale_generation(void) {
    rlx_rocket_runtime_token first = acquire_and_activate();
    uint64_t buffer = 0;
    assert(rlx_rocket_runtime_kernel_read(first, 0x100, &buffer, 8) == 0);
    assert(atomic_load(&g_readCalls) == 1U);

    assert(rlx_rocket_runtime_finalize(first) == 0);
    assert(rlx_rocket_runtime_kernel_read(first, 0x100, &buffer, 8) == ENOTSUP);

    rlx_rocket_runtime_token second = acquire_and_activate();
    assert(second != first);

    /* The reopened gate must not admit the previous run's token. */
    assert(rlx_rocket_runtime_kernel_read(first, 0x200, &buffer, 8) == ENOTSUP);
    assert(rlx_rocket_runtime_kernel_write(first, 0x200, &buffer, 8) == ENOTSUP);
    assert(rlx_rocket_runtime_physical_read(first, 0x200, &buffer, 8) == ENOTSUP);
    assert(rlx_rocket_runtime_physical_write(first, 0x200, &buffer, 8) == ENOTSUP);
    assert(atomic_load(&g_readCalls) == 1U);

    /* And must not let it retire the run that owns the runtime now. */
    assert(rlx_rocket_runtime_finalize(first) == EPERM);
    assert(rlx_rocket_runtime_is_active(second));

    assert(rlx_rocket_runtime_kernel_read(second, 0x300, &buffer, 8) == 0);
    assert(g_lastReadAddress == 0x300);
    assert(rlx_rocket_runtime_finalize(second) == 0);
}

/// Repeating the teardown reports that there is nothing left, not a second one.
static void test_repeated_finalize(void) {
    rlx_rocket_runtime_token token = acquire_and_activate();

    assert(rlx_rocket_runtime_finalize(token) == 0);
    assert(g_finalizeHandoffCalls == 1);
    assert(g_deinitCalls == 1);

    assert(rlx_rocket_runtime_finalize(token) == EPERM);
    assert(g_finalizeHandoffCalls == 1);
    assert(g_deinitCalls == 1);

    /* Never acquired at all. */
    assert(rlx_rocket_runtime_finalize(0) == EALREADY);
    assert(g_finalizeHandoffCalls == 1);
}

/// Claimed but never started: the claim is released, nothing is retracted.
static void test_acquire_without_start(void) {
    rlx_rocket_runtime_token token = 0;
    assert(rlx_rocket_runtime_acquire(&token) == 0);
    assert(rlx_rocket_runtime_finalize(token) == EALREADY);
    assert(g_finalizeHandoffCalls == 0);
    assert(g_deinitCalls == 0);

    /* Released, so the runtime can be claimed again. */
    rlx_rocket_runtime_token second = 0;
    assert(rlx_rocket_runtime_acquire(&second) == 0);
    assert(second != 0 && second != token);
}

/// A teardown that cannot retract kernel state latches, and stays latched.
static void test_dirty_latch(void) {
    rlx_rocket_runtime_token token = acquire_and_activate();

    g_finalizeHandoffStatus = EIO;
    assert(rlx_rocket_runtime_finalize(token) == EIO);
    assert(rlx_rocket_runtime_current_state() == RLXRocketRuntimeStateDirty);

    /* exploit_deinit must not run behind a handoff that would not retire. */
    assert(g_deinitCalls == 0);

    /* The callbacks are gone even though teardown failed. */
    uint64_t buffer = 0;
    assert(rlx_rocket_runtime_kernel_read(token, 0x100, &buffer, 8) == ENOTSUP);
    assert(!rlx_rocket_runtime_is_active(token));

    /* Latched: repeating reports the same status and does not retry. */
    g_finalizeHandoffStatus = 0;
    assert(rlx_rocket_runtime_finalize(token) == EIO);
    assert(g_finalizeHandoffCalls == 1);

    /* And the runtime is never handed to a second acquisition. */
    rlx_rocket_runtime_token second = 0xBBBB;
    assert(rlx_rocket_runtime_acquire(&second) == EIO);
    assert(second == 0);
}

/* ---------------------------------------------------------------- */
/* Drain                                                              */
/* ---------------------------------------------------------------- */

typedef struct {
    rlx_rocket_runtime_token token;
    int status;
} finalize_arguments;

static void *finalize_thread(void *opaque) {
    finalize_arguments *arguments = opaque;
    arguments->status = rlx_rocket_runtime_finalize(arguments->token);
    return NULL;
}

static void *read_thread(void *opaque) {
    rlx_rocket_runtime_token token = *(rlx_rocket_runtime_token *)opaque;
    uint64_t buffer = 0;
    (void)rlx_rocket_runtime_kernel_read(token, 0x400, &buffer, 8);
    return NULL;
}

/**
 * A caller already past the gate holds teardown off until it leaves.
 *
 * This is the interleaving the gate exists for: the backend must not be torn
 * down under a call that is inside it. The reader parks in fake_kread until the
 * test releases it, and the finalize must not have completed before then.
 */
static void test_drain_waits_for_in_flight(void) {
    rlx_rocket_runtime_token token = acquire_and_activate();

    atomic_store(&g_readHold, 1U);
    pthread_t reader;
    assert(pthread_create(&reader, NULL, read_thread, &token) == 0);
    while (atomic_load(&g_readsInFlight) == 0U) {
        usleep(1000);
    }

    finalize_arguments arguments = {.token = token, .status = -1};
    pthread_t finalizer;
    assert(pthread_create(&finalizer, NULL, finalize_thread, &arguments) == 0);

    /* Teardown is blocked while the reader is inside. */
    usleep(50 * 1000);
    assert(g_finalizeHandoffCalls == 0);
    assert(arguments.status == -1);

    atomic_store(&g_readHold, 0U);
    assert(pthread_join(reader, NULL) == 0);
    assert(pthread_join(finalizer, NULL) == 0);
    assert(arguments.status == 0);
    assert(g_finalizeHandoffCalls == 1);
}

/**
 * A drain that never finishes refuses the teardown and leaves the gate shut.
 *
 * The deadline is two seconds, so this case parks a reader and lets it expire.
 * What matters afterwards is that nothing was destroyed and no new caller can
 * get in — the next finalize is the one that does the work.
 */
static void test_drain_timeout(void) {
    rlx_rocket_runtime_token token = acquire_and_activate();

    atomic_store(&g_readHold, 1U);
    pthread_t reader;
    assert(pthread_create(&reader, NULL, read_thread, &token) == 0);
    while (atomic_load(&g_readsInFlight) == 0U) {
        usleep(1000);
    }

    assert(rlx_rocket_runtime_finalize(token) == EBUSY);
    assert(g_finalizeHandoffCalls == 0);
    assert(g_deinitCalls == 0);

    /* Shut, so no new caller is admitted while the straggler is still inside. */
    uint64_t buffer = 0;
    assert(rlx_rocket_runtime_kernel_read(token, 0x500, &buffer, 8) == ENOTSUP);

    atomic_store(&g_readHold, 0U);
    assert(pthread_join(reader, NULL) == 0);

    assert(rlx_rocket_runtime_finalize(token) == 0);
    assert(g_finalizeHandoffCalls == 1);
    assert(g_deinitCalls == 1);
}

/* ---------------------------------------------------------------- */

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <case>\n", argv[0]);
        return 2;
    }

    reset_stubs();
    const char *name = argv[1];
    if (strcmp(name, "owner-race") == 0) {
        test_owner_race();
    } else if (strcmp(name, "stale-generation") == 0) {
        test_stale_generation();
    } else if (strcmp(name, "repeated-finalize") == 0) {
        test_repeated_finalize();
    } else if (strcmp(name, "acquire-without-start") == 0) {
        test_acquire_without_start();
    } else if (strcmp(name, "dirty-latch") == 0) {
        test_dirty_latch();
    } else if (strcmp(name, "drain-in-flight") == 0) {
        test_drain_waits_for_in_flight();
    } else if (strcmp(name, "drain-timeout") == 0) {
        test_drain_timeout();
    } else {
        fprintf(stderr, "unknown case: %s\n", name);
        return 2;
    }

    printf("ok %s\n", name);
    return 0;
}
