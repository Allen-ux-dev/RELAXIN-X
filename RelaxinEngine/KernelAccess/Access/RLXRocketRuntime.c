//
//  RLXRocketRuntime.c
//  RelaxinEngine
//

#include "RLXRocketRuntime.h"

#include "../Exploit/Rocket/Rocket.h"

#include <assert.h>
#include <errno.h>
#include <libjailbreak/primitives_external.h>
#include <stdatomic.h>
#include <unistd.h>

extern int exploit_deinit(void);

/*
 * Owner, gate, and callbacks are one fact recorded once.
 *
 * `g_owner` is the acquisition allowed to drive the runtime. `g_gateOpen` is
 * whether the published callbacks are being honoured; `g_inFlight` counts the
 * callers currently past them. A callback consults both, together with the
 * caller's token, as one entry — checking ownership and then entering would
 * leave a moment in which the answer stops being true, and that moment is
 * exactly what a concurrent teardown needs. Teardown shuts the gate first and
 * waits for the count to reach zero, so the window where a caller is inside a
 * callback while the backend under it is being destroyed does not exist.
 *
 * `g_kernelRead` and `g_kernelWrite` are plain pointers on purpose: they are
 * installed before the gate opens and cleared after it has shut and drained, so
 * every read of them happens between those two points.
 */
static _Atomic(RLXRocketRuntimeState) g_state = RLXRocketRuntimeStateInactive;
static _Atomic(rlx_rocket_runtime_token) g_owner;
static _Atomic(uint64_t) g_issuedTokens;
static _Atomic(bool) g_gateOpen;
static _Atomic(uint32_t) g_inFlight;
static int g_error;
static rlx_rocket_buffer_operation g_kernelRead;
static rlx_rocket_const_buffer_operation g_kernelWrite;

/*
 * The engine drives Rocket from one queue, so the drain normally reads zero on
 * its first look. The deadline is for when it does not: tearing the backend
 * down under a live caller is the thing this gate exists to prevent, so a
 * drain that will not finish refuses the teardown rather than performing it
 * late.
 */
#define RLX_ROCKET_RUNTIME_DRAIN_INTERVAL_US 1000U
#define RLX_ROCKET_RUNTIME_DRAIN_ATTEMPTS 2000U

static bool rlx_rocket_runtime_owns(rlx_rocket_runtime_token token) {
    return token != 0 && atomic_load_explicit(&g_owner, memory_order_acquire) == token;
}

/*
 * Announce first, then check.
 *
 * This half and rlx_rocket_runtime_shut_gate() are the two sides of a
 * store-then-load pair: a caller publishes its arrival before reading the gate,
 * and teardown shuts the gate before reading the count. Acquire/release would
 * let both loads miss the other's store and admit a caller into a runtime
 * already being destroyed, so all four operations are sequentially consistent —
 * that single total order is what guarantees at least one of them sees the
 * other.
 */
static bool rlx_rocket_runtime_enter_gate(rlx_rocket_runtime_token token) {
    atomic_fetch_add_explicit(&g_inFlight, 1U, memory_order_seq_cst);
    if (atomic_load_explicit(&g_gateOpen, memory_order_seq_cst) && rlx_rocket_runtime_owns(token)) {
        return true;
    }
    atomic_fetch_sub_explicit(&g_inFlight, 1U, memory_order_release);
    return false;
}

static void rlx_rocket_runtime_leave_gate(void) {
    atomic_fetch_sub_explicit(&g_inFlight, 1U, memory_order_release);
}

RLXRocketRuntimeState rlx_rocket_runtime_current_state(void) {
    return atomic_load_explicit(&g_state, memory_order_acquire);
}

bool rlx_rocket_runtime_is_active(rlx_rocket_runtime_token token) {
    return rlx_rocket_runtime_owns(token) && atomic_load_explicit(&g_gateOpen, memory_order_acquire);
}

int rlx_rocket_runtime_acquire(rlx_rocket_runtime_token *tokenOut) {
    if (!tokenOut) {
        return EINVAL;
    }
    *tokenOut = 0;

    if (atomic_load_explicit(&g_state, memory_order_acquire) == RLXRocketRuntimeStateDirty) {
        return g_error ?: EIO;
    }

    rlx_rocket_runtime_token token = atomic_fetch_add_explicit(&g_issuedTokens, 1U, memory_order_relaxed) + 1U;
    rlx_rocket_runtime_token unowned = 0;
    if (!atomic_compare_exchange_strong_explicit(&g_owner,
                                                 &unowned,
                                                 token,
                                                 memory_order_acq_rel,
                                                 memory_order_acquire)) {
        return EBUSY;
    }
    *tokenOut = token;
    return 0;
}

void rlx_rocket_runtime_enter_darksword(rlx_rocket_runtime_token token) {
    assert(rlx_rocket_runtime_owns(token));
    if (!rlx_rocket_runtime_owns(token)) {
        return;
    }
    g_error = 0;
    atomic_store_explicit(&g_state, RLXRocketRuntimeStateDarkSwordActive, memory_order_release);
}

void rlx_rocket_runtime_enter_rocket_published(rlx_rocket_runtime_token token) {
    assert(rlx_rocket_runtime_owns(token));
    if (!rlx_rocket_runtime_owns(token)) {
        return;
    }
    atomic_store_explicit(&g_state, RLXRocketRuntimeStateRocketPublished, memory_order_release);
}

void rlx_rocket_runtime_activate(rlx_rocket_runtime_token token,
                                 rlx_rocket_buffer_operation kernelRead,
                                 rlx_rocket_const_buffer_operation kernelWrite) {
    assert(rlx_rocket_runtime_owns(token));
    if (!rlx_rocket_runtime_owns(token)) {
        return;
    }
    g_kernelRead = kernelRead;
    g_kernelWrite = kernelWrite;
    atomic_store_explicit(&g_state, RLXRocketRuntimeStateActive, memory_order_release);
    /* Opened last: everything a caller admitted through it reaches is now in
     * place. */
    atomic_store_explicit(&g_gateOpen, true, memory_order_release);
}

int rlx_rocket_runtime_kernel_read(rlx_rocket_runtime_token token, uint64_t kernelAddress, void *output, size_t size) {
    if (!rlx_rocket_runtime_enter_gate(token)) {
        return ENOTSUP;
    }
    int status = g_kernelRead ? g_kernelRead(kernelAddress, output, size) : ENOTSUP;
    rlx_rocket_runtime_leave_gate();
    return status;
}

int rlx_rocket_runtime_kernel_write(rlx_rocket_runtime_token token,
                                    uint64_t kernelAddress,
                                    const void *input,
                                    size_t size) {
    if (!rlx_rocket_runtime_enter_gate(token)) {
        return ENOTSUP;
    }
    int status = g_kernelWrite ? g_kernelWrite(kernelAddress, input, size) : ENOTSUP;
    rlx_rocket_runtime_leave_gate();
    return status;
}

int rlx_rocket_runtime_physical_read(rlx_rocket_runtime_token token,
                                     uint64_t physicalAddress,
                                     void *output,
                                     size_t size) {
    if (!rlx_rocket_runtime_enter_gate(token)) {
        return ENOTSUP;
    }
    int status = gPrimitives.physreadbuf ? gPrimitives.physreadbuf(physicalAddress, output, size) : ENOTSUP;
    rlx_rocket_runtime_leave_gate();
    return status;
}

int rlx_rocket_runtime_physical_write(rlx_rocket_runtime_token token,
                                      uint64_t physicalAddress,
                                      const void *input,
                                      size_t size) {
    if (!rlx_rocket_runtime_enter_gate(token)) {
        return ENOTSUP;
    }
    int status = gPrimitives.physwritebuf ? gPrimitives.physwritebuf(physicalAddress, input, size) : ENOTSUP;
    rlx_rocket_runtime_leave_gate();
    return status;
}

/// Shuts the gate and waits out the callers already past it. The other half of
/// the pair described above rlx_rocket_runtime_enter_gate().
static int rlx_rocket_runtime_shut_gate(void) {
    atomic_store_explicit(&g_gateOpen, false, memory_order_seq_cst);
    for (uint32_t attempt = 0;; attempt++) {
        if (atomic_load_explicit(&g_inFlight, memory_order_seq_cst) == 0) {
            return 0;
        }
        if (attempt == RLX_ROCKET_RUNTIME_DRAIN_ATTEMPTS) {
            return EBUSY;
        }
        usleep(RLX_ROCKET_RUNTIME_DRAIN_INTERVAL_US);
    }
}

/**
 * Records where teardown ended.
 *
 * The callbacks are cleared on every terminal path, Dirty included: the gate is
 * already shut, so leaving the table populated would be a second and staler
 * answer to a question the gate has answered. A failed teardown keeps the token
 * with its owner — Dirty is terminal, so a later call from that owner reports
 * the latched status rather than EPERM, and no new acquisition can claim a
 * runtime this process can no longer retract.
 */
static int rlx_rocket_runtime_settle(int status) {
    g_kernelRead = NULL;
    g_kernelWrite = NULL;
    g_error = status;
    if (status != 0) {
        atomic_store_explicit(&g_state, RLXRocketRuntimeStateDirty, memory_order_release);
        return status;
    }
    atomic_store_explicit(&g_state, RLXRocketRuntimeStateInactive, memory_order_release);
    atomic_store_explicit(&g_owner, 0, memory_order_release);
    return 0;
}

int rlx_rocket_runtime_finalize(rlx_rocket_runtime_token token) {
    if (token == 0) {
        /* Never acquired, or acquired and already released. Nothing of this
         * caller's is outstanding, which is what EALREADY says. */
        return EALREADY;
    }
    if (!rlx_rocket_runtime_owns(token)) {
        /* A token that was issued and is no longer the live one. Somebody is
         * holding a claim across a teardown, and honouring it would retire an
         * acquisition that is not theirs. */
        return EPERM;
    }

    RLXRocketRuntimeState state = atomic_load_explicit(&g_state, memory_order_acquire);
    if (state == RLXRocketRuntimeStateDirty) {
        return g_error ?: EIO;
    }

    int drained = rlx_rocket_runtime_shut_gate();
    if (drained != 0) {
        return drained;
    }

    switch (state) {
        case RLXRocketRuntimeStateInactive:
            /* Claimed but never started. Release the claim so the process can
             * try again, and say there was nothing to retract. */
            (void)rlx_rocket_runtime_settle(0);
            return EALREADY;
        case RLXRocketRuntimeStateDarkSwordActive:
            return rlx_rocket_runtime_settle(exploit_deinit());
        case RLXRocketRuntimeStateRocketPublished:
        case RLXRocketRuntimeStateActive: {
            /* A handoff that cannot be retired is the one failure that must not
             * be followed by exploit_deinit: the kernel still refers to state
             * this process is about to drop. */
            int status = kernel_exploit_finalize_handoff();
            if (status == 0) {
                status = exploit_deinit();
            }
            return rlx_rocket_runtime_settle(status);
        }
        case RLXRocketRuntimeStateDirty:
            break;
    }
    return g_error ?: EIO;
}
