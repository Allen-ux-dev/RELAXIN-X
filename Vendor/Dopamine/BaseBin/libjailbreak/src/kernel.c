#include "kernel.h"
#include <stdbool.h>
#include "primitives.h"
#include "info.h"
#include "util.h"
#include "translation.h"
#include "codesign.h"
#include <dispatch/dispatch.h>
#include <errno.h>
#include <libkern/OSCacheControl.h>
#include <stdatomic.h>

uint64_t proc_find(pid_t pidToFind) {
    __block uint64_t foundProc = 0;
    // This sucks a bit due to us not being able to take locks
    // If we don't find anything, just repeat 5 times
    // Attempts to avoids conditions where we got thrown off by modifications
    for (int i = 0; i < 5 && !foundProc; i++) {
        proc_iterate(^(uint64_t proc, bool *stop) {
            pid_t pid = kread32(proc + koffsetof(proc, pid));
            if (pid == pidToFind) {
                foundProc = proc;
                *stop = true;
            }
        });
    }
    return foundProc;
}

int proc_rele(uint64_t proc) {
    // If proc_find doesn't increment the ref count, there is also no need to decrement it again
    return -1;
}

uint64_t proc_task(uint64_t proc) {
    if (koffsetof(proc, task)) {
        // iOS <= 15: proc has task attribute
        return kread_ptr(proc + koffsetof(proc, task));
    } else {
        // iOS >= 16: task is always at "proc + sizeof(proc)"
        return proc + ksizeof(proc);
    }
}

uint64_t proc_ucred(uint64_t proc) {
    if (!proc) {
        errno = EINVAL;
        return 0;
    }
    if (gSystemInfo.kernelStruct.proc_ro.exists) {
        uint64_t proc_ro = kread_ptr(proc + koffsetof(proc, proc_ro));
        if (!proc_ro) {
            errno = EFAULT;
            return 0;
        }
        uint64_t rawUcred = 0;
        int status = kreadbuf_protected(proc_ro + koffsetof(proc_ro, ucred), &rawUcred, sizeof(rawUcred));
        if (status != 0) {
            errno = status;
            return 0;
        }
        return UNSIGN_PTR(rawUcred);
    } else {
        return kread_ptr(proc + koffsetof(proc, ucred));
    }
}

static int proc_getcsflags_checked(uint64_t proc, uint32_t *flagsOut) {
    if (!proc || !flagsOut)
        return EINVAL;
    if (gSystemInfo.kernelStruct.proc_ro.exists) {
        uint64_t proc_ro = kread_ptr(proc + koffsetof(proc, proc_ro));
        if (!proc_ro)
            return EFAULT;
        return kreadbuf_protected(proc_ro + koffsetof(proc_ro, csflags), flagsOut, sizeof(*flagsOut));
    }
    return kreadbuf(proc + koffsetof(proc, csflags), flagsOut, sizeof(*flagsOut));
}

uint32_t proc_getcsflags(uint64_t proc) {
    uint32_t flags = 0;
    int status = proc_getcsflags_checked(proc, &flags);
    if (status != 0)
        errno = status;
    return flags;
}

int proc_csflags_update(uint64_t proc, uint32_t flags) {
    if (!proc)
        return EINVAL;
    if (gSystemInfo.kernelStruct.proc_ro.exists) {
        uint64_t proc_ro = kread_ptr(proc + koffsetof(proc, proc_ro));
        if (!proc_ro)
            return EFAULT;
        uint64_t address = proc_ro + koffsetof(proc_ro, csflags);
        int status = kwritebuf_protected(address, &flags, sizeof(flags));
        if (status != 0)
            return status;

        uint32_t observed = 0;
        status = kreadbuf_protected(address, &observed, sizeof(observed));
        if (status != 0)
            return status;
        return observed == flags ? 0 : EIO;
    }
    return kwrite32(proc + koffsetof(proc, csflags), flags);
}

int proc_csflags_set(uint64_t proc, uint32_t flags) {
    uint32_t currentFlags = 0;
    int status = proc_getcsflags_checked(proc, &currentFlags);
    if (status != 0)
        return status;
    return proc_csflags_update(proc, currentFlags | flags);
}

int proc_csflags_clear(uint64_t proc, uint32_t flags) {
    uint32_t currentFlags = 0;
    int status = proc_getcsflags_checked(proc, &currentFlags);
    if (status != 0)
        return status;
    return proc_csflags_update(proc, currentFlags & ~flags);
}

uint64_t ipc_entry_lookup(uint64_t space, mach_port_name_t name) {
    uint64_t table = 0;
    // New format in iOS 16.1
    if (gSystemInfo.kernelStruct.ipc_space.table_uses_smr) {
        table = kread_smrptr(space + koffsetof(ipc_space, table));
    } else {
        table = kread_ptr(space + koffsetof(ipc_space, table));
    }

    return (table + (ksizeof(ipc_entry) * (name >> 8)));
}

uint64_t pa_index(uint64_t pa) {
    return atop(pa - kread64(ksymbol(vm_first_phys)));
}

uint64_t pai_to_pvh(uint64_t pai) {
    return kread64(ksymbol(pv_head_table)) + (pai * 8);
}

uint64_t pvh_ptd(uint64_t pvh) {
    return ((kread64(pvh) & PVH_LIST_MASK) | kconstant(PVH_HIGH_FLAGS));
}

int task_set_memory_ownership_transfer(uint64_t task, bool value) {
    return kwrite8(task + koffsetof(task, task_can_transfer_memory_ownership), !!value);
}

uint64_t mac_label_get(uint64_t label, int slot) {
    // On 15.0 - 15.1.1, 0 is the equivalent of -1 on 15.2+
    // So, treat 0 as -1 there
    uint64_t address = label + ((slot + 1) * sizeof(uint64_t));
    uint64_t value = 0;
    if (gSystemInfo.kernelStruct.proc_ro.exists) {
        uint64_t rawValue = 0;
        int status = kreadbuf_protected(address, &rawValue, sizeof(rawValue));
        if (status != 0) {
            errno = status;
            return 0;
        }
        value = UNSIGN_PTR(rawValue);
    } else {
        value = kread_ptr(address);
    }
    if (!gSystemInfo.kernelStruct.proc_ro.exists && value == 0)
        value = -1;
    return value;
}

void mac_label_set(uint64_t label, int slot, uint64_t value) {
    // THe inverse of the condition above, treat -1 as 0 on 15.0 - 15.1.1
    if (!gSystemInfo.kernelStruct.proc_ro.exists && value == -1)
        value = 0;
#ifdef __arm64e__
    if (jbinfo(usesPACBypass) && !gSystemInfo.kernelStruct.proc_ro.exists) {
        kcall(NULL, ksymbol(mac_label_set), 3, (uint64_t[]){label, slot, value});
        return;
    }
#endif
    uint64_t address = label + ((slot + 1) * sizeof(uint64_t));
    errno = gSystemInfo.kernelStruct.proc_ro.exists ? kwritebuf_protected(address, &value, sizeof(value))
                                                    : kwrite64(address, value);
}

uint64_t kauth_cred_rw(uint64_t cred) {
    if (gSystemInfo.kernelStruct.ucred_rw.exists) {
        uint64_t rawUcredRw = 0;
        int status = kreadbuf_protected(cred + koffsetof(ucred, rw), &rawUcredRw, sizeof(rawUcredRw));
        if (status != 0) {
            errno = status;
            return 0;
        }
        return UNSIGN_PTR(rawUcredRw);
    }
    return 0;
}

#define KAUTH_CRED_REF_MAX 0x0fffffffU

static int kauth_cred_adjust32(uint64_t address, int delta, bool allowZero) {
    if (!address || (delta != 1 && delta != -1))
        return EINVAL;
    __block int status = 0;
    int mapStatus = kaccess_mapped(address, sizeof(uint32_t), ^(void *ptr) {
        _Atomic(uint32_t) *counter = ptr;
        uint32_t current = atomic_load_explicit(counter, memory_order_relaxed);
        for (;;) {
            if ((delta > 0 && (current == 0 || current >= KAUTH_CRED_REF_MAX))
                || (delta < 0 && (current == 0 || (!allowZero && current == 1)))) {
                status = delta > 0 ? EOVERFLOW : ERANGE;
                break;
            }
            uint32_t desired = delta > 0 ? current + 1 : current - 1;
            if (atomic_compare_exchange_weak_explicit(counter,
                                                      &current,
                                                      desired,
                                                      memory_order_relaxed,
                                                      memory_order_relaxed)) {
                break;
            }
        }
    });
    if (mapStatus != 0)
        return mapStatus > 0 ? mapStatus : EIO;
    return status;
}

static int kauth_cred_adjust64(uint64_t address, int delta, bool allowZero) {
    if (!address || (delta != 1 && delta != -1))
        return EINVAL;
    __block int status = 0;
    int mapStatus = kaccess_mapped(address, sizeof(uint64_t), ^(void *ptr) {
        _Atomic(uint64_t) *counter = ptr;
        uint64_t current = atomic_load_explicit(counter, memory_order_relaxed);
        for (;;) {
            if ((delta > 0 && (current == 0 || current >= KAUTH_CRED_REF_MAX))
                || (delta < 0 && (current == 0 || (!allowZero && current == 1)))) {
                status = delta > 0 ? EOVERFLOW : ERANGE;
                break;
            }
            uint64_t desired = delta > 0 ? current + 1 : current - 1;
            if (atomic_compare_exchange_weak_explicit(counter,
                                                      &current,
                                                      desired,
                                                      memory_order_relaxed,
                                                      memory_order_relaxed)) {
                break;
            }
        }
    });
    if (mapStatus != 0)
        return mapStatus > 0 ? mapStatus : EIO;
    return status;
}

static int kauth_cred_reference_adjust(uint64_t ucred, int delta) {
    if (!ucred)
        return EINVAL;
    if (gSystemInfo.kernelStruct.ucred_rw.exists) {
        uint64_t ucred_rw = kauth_cred_rw(ucred);
        if (!ucred_rw)
            return errno ? errno : EFAULT;
        // A raw 1 -> 0 weak release would bypass kauth_cred_retire().
        return kauth_cred_adjust32(ucred_rw + koffsetof(ucred_rw, weak_ref), delta, false);
    }
    return kauth_cred_adjust64(ucred + koffsetof(ucred, ref), delta, false);
}

int kauth_cred_ref(uint64_t ucred) {
    return kauth_cred_reference_adjust(ucred, 1);
}

int kauth_cred_unref(uint64_t ucred) {
    return kauth_cred_reference_adjust(ucred, -1);
}

int kauth_cred_hold(uint64_t ucred) {
    if (!ucred)
        return EINVAL;
    if (!gSystemInfo.kernelStruct.ucred_rw.exists)
        return 0;
    return kauth_cred_adjust64(ucred + koffsetof(ucred, ref), 1, true);
}

int kauth_cred_drop(uint64_t ucred) {
    if (!ucred)
        return EINVAL;
    if (!gSystemInfo.kernelStruct.ucred_rw.exists)
        return 0;
    // cr_ref is the 64-bit long-term reference count. Unlike the weak
    // count, its final 1 -> 0 transition does not retire the credential.
    return kauth_cred_adjust64(ucred + koffsetof(ucred, ref), -1, true);
}

#ifdef __arm64e__
static bool txm_pointer_is_valid(uint64_t pointer) {
    uint64_t pointerMask = kconstant(pointer_mask);
    return pointer != 0 && pointerMask != 0 && (pointer & pointerMask) == pointerMask;
}

static int txm_read_pointer(uint64_t address, uint64_t *pointerOut) {
    if (!pointerOut)
        return EINVAL;
    uint64_t rawPointer = 0;
    int status = kreadbuf_protected(address, &rawPointer, sizeof(rawPointer));
    if (status != 0)
        return status;

    uint64_t pointer = UNSIGN_PTR(rawPointer);
    if (!txm_pointer_is_valid(pointer))
        return EFAULT;
    *pointerOut = pointer;
    return 0;
}

static int txm_write_protected(uint64_t address, const void *value, size_t size) {
    if (!address || !value || size == 0)
        return EINVAL;
    if (vm_real_kernel_page_size == 0 || (address & vm_real_kernel_page_mask) + size > vm_real_kernel_page_size) {
        return EOVERFLOW;
    }

    int status = kwritebuf_protected(address, value, size);
    if (status != 0)
        return status;

    errno = 0;
    uint64_t physicalAddress = kvtophys(address);
    if (!physicalAddress)
        return errno ?: ENXIO;
    uint64_t pagePhysicalAddress = physicalAddress & ~vm_real_kernel_page_mask;
    status = physaccess_mapped(pagePhysicalAddress, vm_real_kernel_page_size, ^(void *mappedAddress) {
        sys_dcache_flush(mappedAddress, vm_real_kernel_page_size);
        __asm__ volatile("dsb sy" ::: "memory");
    });
    return status == 0 ? 0 : EIO;
}

int pmap_cs_allow_invalid(uint64_t pmap) {
    // idk but, seems it works?
    if (__builtin_available(iOS 17.0, *) && system_info_uses_sptm()) {
        uint32_t txmAddressSpaceOffset = koffsetof(pmap, txm_addr_space);
        uint32_t allowsInvalidCodeOffset = koffsetof(txm_address_space, allows_invalid_code);
        if (!pmap || !txmAddressSpaceOffset || !allowsInvalidCodeOffset) {
            return ENOTSUP;
        }

        uint64_t rawAddressSpace = 0;
        int status = kreadbuf_protected(pmap + txmAddressSpaceOffset, &rawAddressSpace, sizeof(rawAddressSpace));
        if (status != 0)
            return status;

        uint64_t txmAddressSpace = UNSIGN_PTR(rawAddressSpace);
        if (!txm_pointer_is_valid(txmAddressSpace)) {
            return EFAULT;
        }

        uint64_t allowsInvalidCodeAddress = txmAddressSpace + allowsInvalidCodeOffset;
        uint8_t currentValue = 0;
        status = kreadbuf_protected(allowsInvalidCodeAddress, &currentValue, sizeof(currentValue));
        if (status != 0)
            return status;
        if (currentValue & 1)
            return 0;

        uint8_t enabled = 1;
        status = txm_write_protected(allowsInvalidCodeAddress, &enabled, sizeof(enabled));
        if (status != 0)
            return status;

        uint8_t observedValue = 0;
        status = kreadbuf_protected(allowsInvalidCodeAddress, &observedValue, sizeof(observedValue));
        if (status != 0)
            return status;
        return (observedValue & 1) ? 0 : EIO;
    }
    return kwrite8(pmap + koffsetof(pmap, wx_allowed), true);
}

#define TXM_FORK_TRUST_LEVEL 5

static uint16_t cs_fork_trust_pair(void) {
    return TXM_FORK_TRUST_LEVEL | (TXM_FORK_TRUST_LEVEL << 8);
}

static int cs_fork_write_trust_pair(uint64_t address, uint16_t expected, uint16_t replacement) {
    uint16_t current = 0;
    int status = kreadbuf_protected(address, &current, sizeof(current));
    if (status != 0)
        return status;
    if (current != expected)
        return EPROTO;
    if (current == replacement)
        return 0;

    status = txm_write_protected(address, &replacement, sizeof(replacement));
    if (status != 0)
        return status;

    uint16_t observed = 0;
    status = kreadbuf_protected(address, &observed, sizeof(observed));
    if (status != 0)
        return status;
    return observed == replacement ? 0 : EIO;
}

int cs_fork_trust_prepare(uint64_t proc, struct cs_fork_trust_state *state) {
    if (!state)
        return EINVAL;
    *state = (struct cs_fork_trust_state){0};
    if (!system_info_uses_sptm())
        return 0;
    if (!proc)
        return ESRCH;

    uint32_t txmAddressSpaceOffset = koffsetof(pmap, txm_addr_space);
    uint32_t pmapTrustOffset = koffsetof(pmap, txm_trust_level);
    uint32_t allowsInvalidCodeOffset = koffsetof(txm_address_space, allows_invalid_code);
    uint32_t mainRegionOffset = koffsetof(txm_address_space, main_region);
    uint32_t codeSignatureOffset = koffsetof(txm_region, code_signature);
    uint32_t trustPairOffset = koffsetof(txm_code_signature, fork_trust_pair);
    if (!txmAddressSpaceOffset || !pmapTrustOffset || !allowsInvalidCodeOffset || !mainRegionOffset
        || !codeSignatureOffset || !trustPairOffset) {
        return ENOTSUP;
    }

    uint64_t task = proc_task(proc);
    if (!task)
        return EFAULT;
    uint64_t map = kread_ptr(task + koffsetof(task, map));
    if (!map)
        return EFAULT;
    uint64_t pmap = kread_ptr(map + koffsetof(vm_map, pmap));
    if (!pmap)
        return EFAULT;

    uint8_t pmapTrust = 0;
    int status = kreadbuf(pmap + pmapTrustOffset, &pmapTrust, sizeof(pmapTrust));
    if (status != 0)
        return status;
    if (pmapTrust == 0)
        return EACCES;

    uint64_t txmAddressSpace = 0;
    status = txm_read_pointer(pmap + txmAddressSpaceOffset, &txmAddressSpace);
    if (status != 0)
        return status;

    uint8_t allowsInvalidCode = 0;
    status = kreadbuf_protected(txmAddressSpace + allowsInvalidCodeOffset,
                                &allowsInvalidCode,
                                sizeof(allowsInvalidCode));
    if (status != 0)
        return status;
    if (allowsInvalidCode > 1)
        return EFAULT;

    uint64_t mainRegion = 0;
    status = txm_read_pointer(txmAddressSpace + mainRegionOffset, &mainRegion);
    if (status != 0)
        return status;

    uint64_t codeSignature = 0;
    status = txm_read_pointer(mainRegion + codeSignatureOffset, &codeSignature);
    if (status != 0)
        return status;

    uint64_t trustPairAddress = codeSignature + trustPairOffset;
    uint16_t currentTrustPair = 0;
    status = kreadbuf_protected(trustPairAddress, &currentTrustPair, sizeof(currentTrustPair));
    if (status != 0)
        return status;
    if (currentTrustPair == 0)
        return EACCES;

    state->trust_pair_address = trustPairAddress;
    state->original_trust_pair = currentTrustPair;
    status = cs_fork_write_trust_pair(trustPairAddress, currentTrustPair, cs_fork_trust_pair());
    if (status != 0) {
        *state = (struct cs_fork_trust_state){0};
    }
    return status;
}

int cs_fork_trust_restore(const struct cs_fork_trust_state *state) {
    if (!system_info_uses_sptm())
        return 0;
    if (!state || !state->trust_pair_address || state->original_trust_pair == 0) {
        return EINVAL;
    }
    return cs_fork_write_trust_pair(state->trust_pair_address, cs_fork_trust_pair(), state->original_trust_pair);
}
#endif

#ifndef __arm64e__
int cs_fork_trust_prepare(uint64_t proc, struct cs_fork_trust_state *state) {
    (void)proc;
    if (state)
        *state = (struct cs_fork_trust_state){0};
    return state ? 0 : EINVAL;
}

int cs_fork_trust_restore(const struct cs_fork_trust_state *state) {
    (void)state;
    return 0;
}
#endif

int cs_allow_invalid(uint64_t proc, bool emulateFully) {
    if (!proc)
        return ESRCH;
    uint64_t task = proc_task(proc);
    if (!task)
        return EFAULT;
    uint64_t vm_map = kread_ptr(task + koffsetof(task, map));
    if (!vm_map)
        return EFAULT;
    uint64_t pmap = kread_ptr(vm_map + koffsetof(vm_map, pmap));
    if (!pmap)
        return EFAULT;

    // For non-pmap_cs (arm64) devices, this should always be emulated.
#ifdef __arm64e__
    if (emulateFully) {
#endif
        // XNU
        int status = proc_csflags_clear(proc, CS_KILL | CS_HARD);
        if (status != 0)
            return status;
        status = proc_csflags_set(proc, CS_DEBUGGED);
        if (status != 0)
            return status;

        status = task_set_memory_ownership_transfer(task, true);
        if (status != 0)
            return status;
        vm_map_flags flags = {0};
        status = kreadbuf(vm_map + koffsetof(vm_map, flags), &flags, sizeof(flags));
        if (status != 0)
            return status;
        flags.switch_protect = false;
        flags.cs_debugged = true;
        status = kwritebuf(vm_map + koffsetof(vm_map, flags), &flags, sizeof(flags));
        if (status != 0)
            return status;
#ifdef __arm64e__
    }
    // For pmap_cs (arm64e) devices, this is enough to get unsigned code to run
    return pmap_cs_allow_invalid(pmap);
#endif
    return 0;
}

kern_return_t pmap_enter_options_addr(uint64_t pmap, uint64_t pa, uint64_t va) {
    uint64_t kr = -1;
    if (!is_kcall_available())
        return kr;
    while (1) {
        kcall(&kr,
              ksymbol(pmap_enter_options_addr),
              8,
              (uint64_t[]){pmap, va, pa, VM_PROT_READ | VM_PROT_WRITE, 0, 0, 1, 1});
        if (kr != KERN_RESOURCE_SHORTAGE) {
            return kr;
        }
    }
}

uint64_t pmap_remove_options(uint64_t pmap, uint64_t start, uint64_t end) {
    uint64_t r = -1;
    if (!is_kcall_available())
        return r;
    kcall(&r, ksymbol(pmap_remove_options), 4, (uint64_t[]){pmap, start, end, 0x100});
    return r;
}

void pmap_remove(uint64_t pmap, uint64_t start, uint64_t end) {
#ifdef __arm64e__
    pmap_remove_options(pmap, start, end);
#else
    uint64_t remove_count = 0;
    if (!pmap) {
        return;
    }
    uint64_t va = start;
    while (va < end) {
        uint64_t l;
        l = ((va + L2_BLOCK_SIZE) & ~L2_BLOCK_MASK);
        if (l > end) {
            l = end;
        }
        remove_count = pmap_remove_options(pmap, va, l);
        va = remove_count;
    }
#endif
}
