#include "translation.h"
#include "primitives.h"
#include "kernel.h"
#include "info.h"
#include "log.h"
#include <errno.h>
#include <stdio.h>
#include <string.h>

struct tt_level {
    uint64_t offMask;
    uint64_t shift;
    uint64_t indexMask;
    uint64_t validMask;
    uint64_t typeMask;
    uint64_t typeBlock;
};
struct tt_level arm_tt_level[4];

// Address translation physical <-> virtual

#define PTOV_TABLE_SIZE 32
#define PPL_PTOV_TABLE_SIZE 8

struct ptov_table_entry {
    uint64_t pa;
    uint64_t va;
    uint64_t len;
};

static struct {
    bool usesSptmContext;
    uint32_t count;
    uint64_t kernelRootPa;
    struct ptov_table_entry entries[PTOV_TABLE_SIZE];
} gTranslationContext;

static bool translation_kernel_address_valid(uint64_t address) {
    return SIGN(address) && UNSIGN_PTR(address) >= 0xffff000000000000ULL;
}

static bool translation_init_ppl_context(void) {
    uint64_t ptovSlot = ksymbol(ptov_table);
    struct ptov_table_entry entries[PPL_PTOV_TABLE_SIZE] = {0};
    if (!ptovSlot || kreadbuf(ptovSlot, entries, sizeof(entries)) != 0) {
        return false;
    }

    uint32_t count = 0;
    while (count < PPL_PTOV_TABLE_SIZE && entries[count].len != 0) {
        struct ptov_table_entry *entry = &entries[count];
        if (entry->pa + entry->len < entry->pa || !translation_kernel_address_valid(entry->va)) {
            return false;
        }
        count++;
    }
    if (count == 0)
        return false;

    memcpy(gTranslationContext.entries, entries, count * sizeof(entries[0]));
    gTranslationContext.count = count;
    return true;
}

static void translation_init_sptm_context(void) {
    uint64_t ptovSlot = ksymbol(ptov_table);
    uint64_t countKva = UNSIGN_PTR(kread64(ptovSlot));
    uint64_t tableKva = UNSIGN_PTR(kread64(ptovSlot + sizeof(uint64_t)));
    if (!translation_kernel_address_valid(countKva) || !translation_kernel_address_valid(tableKva)) {
        return;
    }

    uint32_t count = 0;
    if (kreadbuf(countKva, &count, sizeof(count)) != 0 || count == 0 || count > PTOV_TABLE_SIZE
        || kreadbuf(tableKva, gTranslationContext.entries, count * sizeof(gTranslationContext.entries[0])) != 0) {
        memset(&gTranslationContext, 0, sizeof(gTranslationContext));
        return;
    }

    for (uint32_t index = 0; index < count; index++) {
        struct ptov_table_entry *entry = &gTranslationContext.entries[index];
        if (entry->len > (UINT64_MAX >> ARM_16K_TT_L3_SHIFT)) {
            memset(&gTranslationContext, 0, sizeof(gTranslationContext));
            return;
        }
        entry->len <<= ARM_16K_TT_L3_SHIFT;
        if (!entry->len || entry->pa + entry->len < entry->pa || !translation_kernel_address_valid(entry->va)) {
            memset(&gTranslationContext, 0, sizeof(gTranslationContext));
            return;
        }
    }

    uint64_t kernProc = proc_find(0);
    uint64_t kernTask = kernProc ? proc_task(kernProc) : 0;
    uint64_t kernMap = kernTask ? kread_ptr(kernTask + koffsetof(task, map)) : 0;
    uint64_t kernPmap = kernMap ? kread_ptr(kernMap + koffsetof(vm_map, pmap)) : 0;
    uint64_t rootKva = kernPmap ? kread_ptr(kernPmap + koffsetof(pmap, tte)) : 0;
    uint64_t rootPa = kernPmap ? kread64(kernPmap + koffsetof(pmap, ttep)) : 0;
    if (kernProc)
        proc_rele(kernProc);

    if (!translation_kernel_address_valid(rootKva) || !rootPa || (rootPa & vm_real_kernel_page_mask) != 0) {
        memset(&gTranslationContext, 0, sizeof(gTranslationContext));
        return;
    }

    gTranslationContext.usesSptmContext = true;
    gTranslationContext.count = count;
    gTranslationContext.kernelRootPa = rootPa;
}

uint64_t phystokv(uint64_t pa) {
    for (uint32_t index = 0; index < gTranslationContext.count; index++) {
        struct ptov_table_entry *entry = &gTranslationContext.entries[index];
        if (pa >= entry->pa && pa - entry->pa < entry->len) {
            return pa - entry->pa + entry->va;
        }
    }

    if (kconstant(physSize) && pa >= kconstant(physBase) && pa - kconstant(physBase) < kconstant(physSize)) {
        return pa - kconstant(physBase) + kconstant(virtBase);
    }
    return 0;
}

uint64_t vtophys_lvl(uint64_t tte_ttep, uint64_t va, uint64_t *leaf_level, uint64_t *leaf_tte_ttep) {
    errno = 0;
    const uint64_t ROOT_LEVEL = PMAP_TT_L1_LEVEL;
    const uint64_t LEAF_LEVEL = *leaf_level;

    bool physical = !(bool)(tte_ttep & 0xf000000000000000);

    for (uint64_t curLevel = ROOT_LEVEL; curLevel <= LEAF_LEVEL; curLevel++) {
        if (curLevel > PMAP_TT_L3_LEVEL) {
            errno = 1041;
            return 0;
        }

        struct tt_level *lvlp = &arm_tt_level[curLevel];
        uint64_t tteIndex = (va & lvlp->indexMask) >> lvlp->shift;
        uint64_t tteEntry = 0;
        if (physical) {
            uint64_t tte_pa = tte_ttep + (tteIndex * sizeof(uint64_t));
            tteEntry = physread64(tte_pa);
            if (leaf_tte_ttep)
                *leaf_tte_ttep = tte_pa;
            if (leaf_level)
                *leaf_level = curLevel;
        } else if (gPrimitives.kreadbuf && !physical) {
            uint64_t tte_va = tte_ttep + (tteIndex * sizeof(uint64_t));
            tteEntry = kread64(tte_va);
            if (leaf_tte_ttep)
                *leaf_tte_ttep = tte_va;
            if (leaf_level)
                *leaf_level = curLevel;
        } else {
            JBLogError("address translation unavailable direction=%s", physical ? "physical" : "virtual");
            errno = 1043;
            return 0;
        }

        if ((tteEntry & lvlp->validMask) != lvlp->validMask) {
            errno = 1042;
            return 0;
        }

        if ((tteEntry & lvlp->typeMask) == lvlp->typeBlock) {
            // Found block mapping, no matter what level we are in, this is the end
            return ((tteEntry & ARM_TTE_PA_MASK & ~lvlp->offMask) | (va & lvlp->offMask));
        }

        if (physical) {
            tte_ttep = tteEntry & ARM_TTE_TABLE_MASK & ~vm_real_kernel_page_mask;
        } else {
            uint64_t nextTablePa = tteEntry & ARM_TTE_TABLE_MASK & ~vm_real_kernel_page_mask;
            tte_ttep = phystokv(nextTablePa);
        }
    }

    // If we end up here, it means we did not find a block mapping
    // In this case, return the last page table address we traversed
    return tte_ttep;
}

uint64_t vtophys(uint64_t tte_ttep, uint64_t va) {
    uint64_t level = PMAP_TT_L3_LEVEL;
    return vtophys_lvl(tte_ttep, va, &level, NULL);
}

uint64_t kvtophys(uint64_t va) {
    if (gPrimitives.kvtophys) {
        errno = 0;
        uint64_t pa = gPrimitives.kvtophys(va);
        if (pa) {
            errno = 0;
            return pa;
        }
        if (gTranslationContext.usesSptmContext && gTranslationContext.kernelRootPa) {
            return vtophys(gTranslationContext.kernelRootPa, va);
        }
        return 0;
    }
    if (gTranslationContext.usesSptmContext && gTranslationContext.kernelRootPa) {
        return vtophys(gTranslationContext.kernelRootPa, va);
    }
    return vtophys(kconstant(cpuTTEP), va);
}

bool translation_uses_sptm_context(void) {
    return gTranslationContext.usesSptmContext;
}

bool libjailbreak_translation_init(void) {
    memset(&gTranslationContext, 0, sizeof(gTranslationContext));
    if (vm_real_kernel_page_size != ARM_16K_TT_L3_SIZE) {
        return false;
    }

    arm_tt_level[0] = (struct tt_level){
        .offMask = ARM_16K_TT_L0_OFFMASK,
        .shift = ARM_16K_TT_L0_SHIFT,
        .indexMask = ARM_16K_TT_L0_INDEX_MASK,
        .validMask = ARM_TTE_VALID,
        .typeMask = ARM_TTE_TYPE_MASK,
        .typeBlock = ARM_TTE_TYPE_BLOCK,
    };
    arm_tt_level[1] = (struct tt_level){
        .offMask = ARM_16K_TT_L1_OFFMASK,
        .shift = ARM_16K_TT_L1_SHIFT,
        .indexMask = kconstant(ARM_TT_L1_INDEX_MASK),
        .validMask = ARM_TTE_VALID,
        .typeMask = ARM_TTE_TYPE_MASK,
        .typeBlock = ARM_TTE_TYPE_BLOCK,
    };
    arm_tt_level[2] = (struct tt_level){
        .offMask = ARM_16K_TT_L2_OFFMASK,
        .shift = ARM_16K_TT_L2_SHIFT,
        .indexMask = ARM_16K_TT_L2_INDEX_MASK,
        .validMask = ARM_TTE_VALID,
        .typeMask = ARM_TTE_TYPE_MASK,
        .typeBlock = ARM_TTE_TYPE_BLOCK,
    };
    arm_tt_level[3] = (struct tt_level){
        .offMask = ARM_16K_TT_L3_OFFMASK,
        .shift = ARM_16K_TT_L3_SHIFT,
        .indexMask = ARM_16K_TT_L3_INDEX_MASK,
        .validMask = ARM_TTE_VALID,
        .typeMask = ARM_TTE_TYPE_MASK,
        .typeBlock = ARM_TTE_TYPE_L3BLOCK,
    };

    gPrimitives.phystokv = phystokv;
    gPrimitives.vtophys = vtophys;
    if (rlx_ksymbol(sptm_args)) {
        translation_init_sptm_context();
        return gTranslationContext.usesSptmContext;
    }
    return translation_init_ppl_context();
}
