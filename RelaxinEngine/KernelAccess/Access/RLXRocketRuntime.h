//
//  RLXRocketRuntime.h
//  RelaxinEngine
//
//  The Rocket runtime state machine and the callbacks it publishes.
//

#ifndef RLX_ROCKET_RUNTIME_H
#define RLX_ROCKET_RUNTIME_H

#include "../RLXKernelAccess.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/**
 * Rocket's lifecycle, in the order a successful run walks it.
 *
 * `Dirty` is terminal and latching: once teardown has failed, the kernel may
 * hold state this process can no longer retract, so every later attempt
 * reports the latched error rather than trying again.
 */
typedef enum {
    RLXRocketRuntimeStateInactive,
    RLXRocketRuntimeStateDarkSwordActive,
    RLXRocketRuntimeStateRocketPublished,
    RLXRocketRuntimeStateActive,
    RLXRocketRuntimeStateDirty,
} RLXRocketRuntimeState;

/**
 * Names one acquisition of the process-wide runtime.
 *
 * Rocket's state lives in process globals — libjailbreak's primitives, the GFX
 * backend, the transaction generation — so there is exactly one runtime and at
 * most one owner of it. The token is what an RLXKernelAccess holds to prove it
 * is that owner: every transition, every access, and the teardown take it, and
 * a caller that does not hold the live one is refused instead of being allowed
 * to drive somebody else's runtime. Zero means "owns nothing" and is never
 * issued.
 *
 * It is the same value the published `rlx_kernel_access` carries, so a callback
 * table kept across a finalize refuses rather than reaching whatever acquired
 * the runtime next.
 */
typedef rlx_kernel_access_token rlx_rocket_runtime_token;

typedef int (*rlx_rocket_buffer_operation)(uint64_t address, void *buffer, size_t size);
typedef int (*rlx_rocket_const_buffer_operation)(uint64_t address, const void *buffer, size_t size);

/*
 * Internal to the framework: RLXKernelAccess drives the state machine and
 * publishes the callbacks through rlx_kernel_access. Nothing outside links
 * against these names, and keeping them out of the export table is what stops
 * generic names like these from colliding with a loaded dylib.
 */
#pragma GCC visibility push(hidden)

/**
 * Claims the runtime for one acquisition.
 *
 * Returns 0 and writes a fresh token on success, EBUSY when another acquisition
 * still holds it, EINVAL without an output, and the latched status once Dirty —
 * a runtime whose teardown could not retract kernel state is never handed to a
 * second acquisition.
 */
int rlx_rocket_runtime_acquire(rlx_rocket_runtime_token *tokenOut);

RLXRocketRuntimeState rlx_rocket_runtime_current_state(void);

/**
 * Whether `token` owns the runtime and the gate is open.
 *
 * Advisory only. It samples two facts that a concurrent teardown can change the
 * instant after it returns, so it answers "was this live" and must never be the
 * check a caller then acts on — the callbacks below re-establish the same fact
 * as part of entering, which is the only place it can be relied on.
 */
bool rlx_rocket_runtime_is_active(rlx_rocket_runtime_token token);

/**
 * Transitions, in lifecycle order.
 *
 * Each is the single writer of the state and does nothing unless `token` owns
 * the runtime; being called by anything else is a programming error and
 * asserts.
 */
void rlx_rocket_runtime_enter_darksword(rlx_rocket_runtime_token token);
void rlx_rocket_runtime_enter_rocket_published(rlx_rocket_runtime_token token);
void rlx_rocket_runtime_activate(rlx_rocket_runtime_token token,
                                 rlx_rocket_buffer_operation kernelRead,
                                 rlx_rocket_const_buffer_operation kernelWrite);

/**
 * Shuts the gate, waits for in-flight callbacks to leave, then walks the state
 * machine back to Inactive and releases the token.
 *
 * Returns 0 on success, EALREADY when the caller holds no claim or the owner
 * had nothing to retract, EPERM when `token` was issued but is no longer the
 * live one, EBUSY when callers were still inside a callback at the drain
 * deadline, and otherwise the errno-style teardown status — the latched one
 * once Dirty.
 *
 * The gate shuts before any teardown runs, so a concurrent read or write either
 * finished before it or is refused; nothing can be inside a callback while the
 * backend that callback reaches is being destroyed. A drain that times out
 * leaves the gate shut and the runtime intact: no new caller can get in, and
 * the next call finalizes for real once the stragglers have left.
 */
int rlx_rocket_runtime_finalize(rlx_rocket_runtime_token token);

/**
 * The four callbacks handed to the engine.
 *
 * Ownership and admission are one operation: the token check, the gate check,
 * and the in-flight count all happen inside a single entry, so there is no
 * moment between deciding a call may proceed and it proceeding. A call from a
 * spent token, or one that arrives after the gate shut, returns ENOTSUP; it
 * never reaches a backend being torn down, and never reaches the backend of a
 * later acquisition.
 */
int rlx_rocket_runtime_kernel_read(rlx_rocket_runtime_token token, uint64_t kernelAddress, void *output, size_t size);
int rlx_rocket_runtime_kernel_write(rlx_rocket_runtime_token token,
                                    uint64_t kernelAddress,
                                    const void *input,
                                    size_t size);
int rlx_rocket_runtime_physical_read(rlx_rocket_runtime_token token,
                                     uint64_t physicalAddress,
                                     void *output,
                                     size_t size);
int rlx_rocket_runtime_physical_write(rlx_rocket_runtime_token token,
                                      uint64_t physicalAddress,
                                      const void *input,
                                      size_t size);

#pragma GCC visibility pop

#endif /* RLX_ROCKET_RUNTIME_H */
