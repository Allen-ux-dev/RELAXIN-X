#include "util.h"
#include "primitives.h"
#include "info.h"
#include "kernel.h"
#include "setid_donor.h"
#include "translation.h"
#include <spawn.h>
#include <errno.h>
#include <bsm/audit.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <dlfcn.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <archive.h>
#include <archive_entry.h>
#include <math.h>
#include <mach-o/dyld.h>
#include <dirent.h>
#include <IOKit/IOKitLib.h>
#include <mach-o/dyld_images.h>
#include <mach-o/getsect.h>
#include <dyld_cache_format.h>
extern char **environ;

#include "roothider.h"

#define FAKE_PHYSPAGE_TO_MAP 0x13370000

int posix_spawnattr_set_registered_ports_np(posix_spawnattr_t *__restrict attr,
                                            mach_port_t portarray[],
                                            uint32_t count);
int posix_spawnattr_setauditsessionport_np(posix_spawnattr_t *__restrict attr, mach_port_t auditSessionPort);

const struct mach_header *get_mach_header(const char *name) {
    const struct mach_header *mh = NULL;
    for (int i = 0; i < _dyld_image_count(); i++) {
        if (!strcmp(_dyld_get_image_name(i), name)) {
            mh = _dyld_get_image_header(i);
            break;
        }
    }
    return mh;
}

void proc_iterate(void (^itBlock)(uint64_t, bool *)) {
    uint64_t proc = ksymbol(allproc);
    while ((proc = kread_ptr(proc + koffsetof(proc, list_next)))) {
        bool stop = false;
        itBlock(proc, &stop);
        if (stop)
            return;
    }
}

uint64_t proc_self(void) {
    static uint64_t gSelfProc = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSelfProc = proc_find(getpid());
        // decrement ref count again, we assume proc_self will exist for the whole lifetime of this process
        proc_rele(gSelfProc);
    });
    return gSelfProc;
}

uint64_t task_self(void) {
    static uint64_t gSelfTask = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSelfTask = proc_task(proc_self());
    });
    return gSelfTask;
}

uint64_t vm_map_self(void) {
    static uint64_t gSelfMap = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSelfMap = kread_ptr(task_self() + koffsetof(task, map));
    });
    return gSelfMap;
}

uint64_t pmap_self(void) {
    static uint64_t gSelfPmap = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSelfPmap = kread_ptr(vm_map_self() + koffsetof(vm_map, pmap));
    });
    return gSelfPmap;
}

uint64_t ttep_self(void) {
    static uint64_t gSelfTTEP = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSelfTTEP = kread_ptr(pmap_self() + koffsetof(pmap, ttep));
    });
    return gSelfTTEP;
}

uint64_t tte_self(void) {
    static uint64_t gSelfTTE = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSelfTTE = kread_ptr(pmap_self() + koffsetof(pmap, tte));
    });
    return gSelfTTE;
}

uint64_t task_get_ipc_port_table_entry(uint64_t task, mach_port_t port) {
    uint64_t itk_space = kread_ptr(task + koffsetof(task, itk_space));
    return ipc_entry_lookup(itk_space, port);
}

uint64_t task_get_ipc_port_object(uint64_t task, mach_port_t port) {
    return kread_ptr(task_get_ipc_port_table_entry(task, port) + koffsetof(ipc_entry, object));
}

uint64_t task_get_ipc_port_kobject(uint64_t task, mach_port_t port) {
    return kread_ptr(task_get_ipc_port_object(task, port) + koffsetof(ipc_port, kobject));
}

uint64_t alloc_page_table_unassigned(void) {
    uint64_t pmap = pmap_self();
    uint64_t ttep = kread64(pmap + koffsetof(pmap, ttep));

    vm_address_t free_lvl2 = 0;
    uint64_t tte_lvl2 = 0;
    uint64_t allocatedPT = 0;
    uint64_t pinfo_pa = 0;
    while (true) {
        /*
		 * launchd's malloc zone traps on the 32 MiB aligned allocation used
		 * by the 16 KiB PPL geometry. A VM alignment mask reserves the same
		 * L2 span and keeps process allocator metadata untouched.
		 */
        kern_return_t kr = vm_map(mach_task_self(),
                                  &free_lvl2,
                                  L2_BLOCK_SIZE,
                                  L2_BLOCK_MASK,
                                  VM_FLAGS_ANYWHERE,
                                  MEMORY_OBJECT_NULL,
                                  0,
                                  FALSE,
                                  VM_PROT_READ | VM_PROT_WRITE,
                                  VM_PROT_READ | VM_PROT_WRITE,
                                  VM_INHERIT_NONE);
        if (kr != KERN_SUCCESS) {
            JBLogError("L2 page-table address allocation failed status=%d", kr);
            return 0;
        }
        // Now, fault in one page to make the kernel allocate the page table for it
        *(volatile uint64_t *)(uintptr_t)free_lvl2;

        // Find the newly allocated page table
        uint64_t lvl = PMAP_TT_L2_LEVEL;
        allocatedPT = vtophys_lvl(ttep, free_lvl2, &lvl, &tte_lvl2);

        uint64_t pvh = pai_to_pvh(pa_index(allocatedPT));
        uint64_t ptdp = pvh_ptd(pvh);
        uint64_t pinfo = kread64(ptdp + koffsetof(pt_desc, ptd_info));
        pinfo_pa = kvtophys(pinfo);

        uint16_t refCount = physread16(pinfo_pa);
        if (refCount != 1) {
            // Something is off, retry
            vm_deallocate(mach_task_self(), free_lvl2, L2_BLOCK_SIZE);
            free_lvl2 = 0;
            continue;
        }
        break;
    }

    // Bump reference count of our allocated page table
    physwrite16(pinfo_pa, 0x1337);

    // Deallocate address range (our allocated page table will stay because we bumped it's reference count)
    vm_deallocate(mach_task_self(), free_lvl2, L2_BLOCK_SIZE);

    // Remove our allocated page table from it's original location (leak it)
    physwrite64(tte_lvl2, 0);

    // Reference count of new page table must be 0!
    // original ref count is 1 because the table holds one PTE
    // Our new PTEs are not part of the pmap layer though so refcount needs to be 0
    physwrite16(pinfo_pa, 0);

    return allocatedPT;
}

uint64_t pmap_alloc_page_table(uint64_t pmap, uint64_t va) {
    if (!pmap) {
        pmap = pmap_self();
    }

    uint64_t tt_p = alloc_page_table_unassigned();
    if (!tt_p)
        return 0;

    uint64_t pvh = pai_to_pvh(pa_index(tt_p));
    uint64_t ptdp = pvh_ptd(pvh);

    uint64_t ptdp_pa = kvtophys(ptdp);

    // At this point the allocated page table is associated
    // to the pmap of this process alongside the address it was allocated on
    // We now need to replace the association with the context in which it will be used
    physwrite64(ptdp_pa + koffsetof(pt_desc, pmap), pmap);

    // On A14+ PT_INDEX_MAX is 4, for whatever reason
    // However in practice, only the first slot is used...
    for (uint64_t po = 0; po < vm_page_size; po += vm_real_kernel_page_size) {
        physwrite64(ptdp_pa + koffsetof(pt_desc, va) + (po / vm_page_size), va + po);
    }

    return tt_p;
}

int pmap_expand_range(uint64_t pmap, uint64_t vaStart, uint64_t size) {
    uint64_t ttep = kread_ptr(pmap + koffsetof(pmap, ttep));

    if (is_kcall_available()) {
        uint64_t unmappedStart = 0, unmappedSize = 0;

        uint64_t l2Start = vaStart & ~L2_BLOCK_MASK;
        uint64_t l2End = (vaStart + (size - 1)) & ~L2_BLOCK_MASK;
        uint64_t l2Count = ((l2End - l2Start) / L2_BLOCK_SIZE) + 1;

        for (uint64_t i = 0; i <= l2Count; i++) {
            uint64_t curL2 = l2Start + (i * L2_BLOCK_SIZE);

            uint64_t leafLevel = PMAP_TT_L3_LEVEL;
            uint64_t pt3 = 0;
            vtophys_lvl(ttep, curL2, &leafLevel, &pt3);
            if (leafLevel == PMAP_TT_L3_LEVEL || i == l2Count) {
                // i == l2Count: one extra cycle that this for loop takes
                // We hit this block either if there was a mapping or at the end
                // Alloc page tables for the current area (unmappedStart, unmappedSize) by running pmap_enter_options on every page
                // And then running pmap_remove on the entire area while nested is true

                for (uint64_t l2Off = 0; l2Off < unmappedSize; l2Off += L2_BLOCK_SIZE) {
                    kern_return_t kr = pmap_enter_options_addr(pmap, FAKE_PHYSPAGE_TO_MAP, unmappedStart + l2Off);
                    if (kr != KERN_SUCCESS) {
                        return -7;
                    }
                }

                // Set type to nested
                physwrite8(kvtophys(pmap + koffsetof(pmap, type)), 3);

                // Remove mapping (table will stay cause nested is set)
                pmap_remove(pmap, unmappedStart, unmappedStart + unmappedSize);

                // Change type back
                physwrite8(kvtophys(pmap + koffsetof(pmap, type)), 0);

                unmappedStart = 0;
                unmappedSize = 0;
                continue;
            } else {
                if (unmappedStart == 0) {
                    unmappedStart = curL2;
                }
                unmappedSize += L2_BLOCK_SIZE;
            }
        }
    } else {
        uint64_t l2Start = (vaStart & ~L2_BLOCK_MASK);
        uint64_t l2End = (((vaStart + size) + (L2_BLOCK_SIZE - 1)) & ~L2_BLOCK_MASK);
        for (uint64_t va = l2Start; va < l2End; va += L2_BLOCK_SIZE) {
            uint64_t leafLevel;
            do {
                leafLevel = PMAP_TT_L3_LEVEL;
                uint64_t pte = 0;
                vtophys_lvl(ttep, va, &leafLevel, &pte);
                if (leafLevel != PMAP_TT_L3_LEVEL) {
                    uint64_t pt_va = 0;
                    switch (leafLevel) {
                        case PMAP_TT_L1_LEVEL: {
                            pt_va = va & ~L1_BLOCK_MASK;
                            break;
                        }
                        case PMAP_TT_L2_LEVEL: {
                            pt_va = va & ~L2_BLOCK_MASK;
                            break;
                        }
                    }
                    leafLevel++;
                    uint64_t newTable = pmap_alloc_page_table(pmap, pt_va);
                    if (newTable) {
                        physwrite64(pte, newTable | ARM_TTE_VALID | ARM_TTE_TYPE_TABLE);
                    } else {
                        return -2;
                    }
                }
            } while (leafLevel < PMAP_TT_L3_LEVEL);
        }
    }
    return 0;
}

int pmap_map_in(uint64_t pmap, uint64_t uaStart, uint64_t paStart, uint64_t size) {
    uint64_t ttep = kread64(pmap + koffsetof(pmap, ttep));

    uint64_t paEnd = paStart + size;
    uint64_t uaEnd = uaStart + size;

    uint64_t uaL2Start = uaStart & ~L2_BLOCK_MASK;
    uint64_t uaL2End = ((uaStart + size - 1) + L2_BLOCK_SIZE) & ~L2_BLOCK_MASK;

    uint64_t paL2Start = paStart & ~L2_BLOCK_MASK;
    uint64_t l2Count = (((uaL2End - uaL2Start) - 1) / L2_BLOCK_SIZE) + 1;

    // Sanity check: Ensure the entire area to be mapped in is not mapped to anything yet
    for (uint64_t ua = uaStart; ua < uaEnd; ua += vm_real_kernel_page_size) {
        uint64_t leafLevel = PMAP_TT_L3_LEVEL;
        if (vtophys_lvl(ttep, ua, &leafLevel, NULL) != 0) {
            return -1;
        } else {
            // Performance improvement
            // If there is no L1 / L2 mapping we can skip a whole bunch of addresses
            if (leafLevel == PMAP_TT_L1_LEVEL) {
                ua = (((ua + L1_BLOCK_SIZE) & ~L1_BLOCK_MASK) - vm_real_kernel_page_size);
            } else if (leafLevel == PMAP_TT_L2_LEVEL) {
                ua = (((ua + L2_BLOCK_SIZE) & ~L2_BLOCK_MASK) - vm_real_kernel_page_size);
            }
        }

        if (vtophys(ttep, ua))
            return -1;
        // TODO: If all mappings match 1:1, maybe return 0 instead of -1?
    }

    // Allocate all page tables that need to be allocated
    if (pmap_expand_range(pmap, uaStart, size) != 0)
        return -1;

    // Insert entries into L3 pages
    uint64_t curPA = paStart;
    for (uint64_t i = 0; i < l2Count; i++) {
        uint64_t uaL2Cur = uaL2Start + (i * L2_BLOCK_SIZE);

        // Current L2 range
        uint64_t uaL2CurStart = uaL2Cur;
        uint64_t uaL2CurEnd = uaL2Cur + L2_BLOCK_SIZE;

        // Round to passed boundary if neccessary
        if (uaStart > uaL2CurStart)
            uaL2CurStart = uaStart;
        if (uaEnd < uaL2CurEnd)
            uaL2CurEnd = uaEnd;

        // Create full table for this mapping
        uint64_t tableToWrite[L2_BLOCK_COUNT];
        memset(tableToWrite, 0, sizeof(tableToWrite));
        for (uint64_t curUA = uaL2CurStart; curUA < uaL2CurEnd;
             curUA += vm_real_kernel_page_size, curPA += vm_real_kernel_page_size) {
            int idx = (curUA - uaL2Cur) / vm_real_kernel_page_size;
            tableToWrite[idx] = curPA | PERM_TO_PTE(PERM_KRW_URW) | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE
                | PTE_LEVEL3_ENTRY;
        }

        // Replace table with the entries we generated
        uint64_t leafLevel = PMAP_TT_L2_LEVEL;
        uint64_t level2Table = vtophys_lvl(ttep, uaL2Cur, &leafLevel, NULL);
        if (!level2Table)
            return -2;
        physwritebuf(level2Table, tableToWrite, vm_real_kernel_page_size);
    }

    return 0;
}

#ifdef __arm64e__

#define PMAP_CS_IDENTIFIER_MAX 256

static bool pmap_cs_read_identifier(uint64_t codeDir,
                                    uint32_t identifierOffset,
                                    char identifier[PMAP_CS_IDENTIFIER_MAX]) {
    uint64_t identifierPtr = kread_ptr(codeDir + identifierOffset);
    if (!identifierPtr)
        return false;

    memset(identifier, 0, PMAP_CS_IDENTIFIER_MAX);
    return kreadbuf(identifierPtr, identifier, PMAP_CS_IDENTIFIER_MAX - 1) == 0;
}

static uint64_t pmap_find_main_binary_code_dir_tree(uint64_t region, unsigned depth) {
    if (!region || depth >= 64)
        return 0;

    uint64_t codeDir = kread_ptr(region + koffsetof(pmap_cs_region, cd_entry));
    if (codeDir && kread8(codeDir + koffsetof(pmap_cs_code_directory, main_binary))) {
        return codeDir;
    }

    uint64_t codeDirResult = pmap_find_main_binary_code_dir_tree(kread_ptr(
                                                                     region
                                                                     + koffsetof(pmap_cs_region, pmap_cs_region_next)),
                                                                 depth + 1);
    if (codeDirResult)
        return codeDirResult;

    return pmap_find_main_binary_code_dir_tree(kread_ptr(region + koffsetof(pmap_cs_region, pmap_cs_region_right)),
                                               depth + 1);
}

static void pmap_set_custom_trust_for_identifier(uint64_t region,
                                                 unsigned depth,
                                                 const char *mainIdentifier,
                                                 uint64_t mainCodeDir,
                                                 uint32_t trust) {
    if (!region || depth >= 64)
        return;

    pmap_set_custom_trust_for_identifier(kread_ptr(region + koffsetof(pmap_cs_region, pmap_cs_region_next)),
                                         depth + 1,
                                         mainIdentifier,
                                         mainCodeDir,
                                         trust);

    uint64_t codeDir = kread_ptr(region + koffsetof(pmap_cs_region, cd_entry));
    if (codeDir && codeDir != mainCodeDir
        && kread32(codeDir + koffsetof(pmap_cs_code_directory, trust))
            == pmap_cs_trust_string_to_int("PMAP_CS_IN_LOADED_TRUST_CACHE")) {
        char identifier[PMAP_CS_IDENTIFIER_MAX];
        if (pmap_cs_read_identifier(codeDir, koffsetof(pmap_cs_code_directory, signing_identifier), identifier)
            && strcmp(identifier, mainIdentifier) == 0) {
            uint64_t identifierPtr = kread_ptr(codeDir + koffsetof(pmap_cs_code_directory, signing_identifier));
            if (!kread_ptr(codeDir + koffsetof(pmap_cs_code_directory, team_identifier))) {
                kwrite64(codeDir + koffsetof(pmap_cs_code_directory, team_identifier), identifierPtr);
            }
            kwrite32(codeDir + koffsetof(pmap_cs_code_directory, trust), trust);
        }
    }

    pmap_set_custom_trust_for_identifier(kread_ptr(region + koffsetof(pmap_cs_region, pmap_cs_region_right)),
                                         depth + 1,
                                         mainIdentifier,
                                         mainCodeDir,
                                         trust);
}

uint64_t pmap_find_main_binary_code_dir(uint64_t pmap) {
    uint64_t mainCodeDir = 0;
    uint64_t pmap_cs_region = kread_ptr(pmap + koffsetof(pmap, pmap_cs_main));
    while (pmap_cs_region && !mainCodeDir) {
        uint64_t pmap_cs_code_dir = kread_ptr(pmap_cs_region + koffsetof(pmap_cs_region, cd_entry));
        while (pmap_cs_code_dir) {
            _Bool mainBinary = kread64(pmap_cs_code_dir + koffsetof(pmap_cs_code_directory, main_binary));
            if (mainBinary) {
                mainCodeDir = pmap_cs_code_dir;
                break;
            }
            pmap_cs_code_dir = kread_ptr(pmap_cs_code_dir
                                         + koffsetof(pmap_cs_code_directory, pmap_cs_code_directory_next));
        }
        pmap_cs_region = kread_ptr(pmap_cs_region + koffsetof(pmap_cs_region, pmap_cs_region_next));
    }
    return mainCodeDir;
}

uint64_t proc_find_main_binary_code_dir(uint64_t proc) {
    uint64_t task = proc_task(proc);
    uint64_t map = kread_ptr(task + koffsetof(task, map));
    uint64_t pmap = kread_ptr(map + koffsetof(vm_map, pmap));
    return pmap_find_main_binary_code_dir(pmap);
}

void proc_set_pmap_cs_custom_trust(uint64_t proc, uint32_t trust) {
    uint64_t task = proc_task(proc);
    uint64_t map = kread_ptr(task + koffsetof(task, map));
    uint64_t pmap = kread_ptr(map + koffsetof(vm_map, pmap));
    uint64_t regionRoot = kread_ptr(pmap + koffsetof(pmap, pmap_cs_main));
    uint64_t mainCodeDir = pmap_find_main_binary_code_dir_tree(regionRoot, 0);
    if (!mainCodeDir)
        return;

    char mainIdentifier[PMAP_CS_IDENTIFIER_MAX];
    if (!pmap_cs_read_identifier(mainCodeDir, koffsetof(pmap_cs_code_directory, signing_identifier), mainIdentifier))
        return;

    uint64_t mainIdentifierPtr = kread_ptr(mainCodeDir + koffsetof(pmap_cs_code_directory, signing_identifier));
    if (!kread_ptr(mainCodeDir + koffsetof(pmap_cs_code_directory, team_identifier))) {
        kwrite64(mainCodeDir + koffsetof(pmap_cs_code_directory, team_identifier), mainIdentifierPtr);
    }
    kwrite32(mainCodeDir + koffsetof(pmap_cs_code_directory, trust), trust);

    pmap_set_custom_trust_for_identifier(regionRoot, 0, mainIdentifier, mainCodeDir, trust);
}

uint32_t pmap_cs_trust_string_to_int(const char *trustString) {
    int trustInt = 0;
    if (__builtin_available(iOS 16.0, *)) {
        if (!strcmp(trustString, "PMAP_CS_UNTRUSTED"))
            trustInt = 0;
        else if (!strcmp(trustString, "PMAP_CS_RETIRED"))
            trustInt = 1;
        else if (!strcmp(trustString, "PMAP_CS_PROFILE_PREFLIGHT"))
            trustInt = 2;
        else if (!strcmp(trustString, "PMAP_CS_COMPILATION_SERVICE"))
            trustInt = 3;
        else if (!strcmp(trustString, "PMAP_CS_OOP_JIT"))
            trustInt = 4;
        else if (!strcmp(trustString, "PMAP_CS_LOCAL_SIGNING"))
            trustInt = 5;
        else if (!strcmp(trustString, "PMAP_CS_PROFILE_VALIDATED"))
            trustInt = 6;
        else if (!strcmp(trustString, "PMAP_CS_APP_STORE"))
            trustInt = 7;
        else if (!strcmp(trustString, "PMAP_CS_IN_LOADED_TRUST_CACHE"))
            trustInt = 8;
        else if (!strcmp(trustString, "PMAP_CS_IN_STATIC_TRUST_CACHE"))
            trustInt = 9;
    } else {
        if (!strcmp(trustString, "PMAP_CS_UNTRUSTED"))
            trustInt = 0;
        else if (!strcmp(trustString, "PMAP_CS_RETIRED"))
            trustInt = 1;
        else if (!strcmp(trustString, "PMAP_CS_PROFILE_PREFLIGHT"))
            trustInt = 2;
        else if (!strcmp(trustString, "PMAP_CS_COMPILATION_SERVICE"))
            trustInt = 3;
        else if (!strcmp(trustString, "PMAP_CS_LOCAL_SIGNING"))
            trustInt = 4;
        else if (!strcmp(trustString, "PMAP_CS_PROFILE_VALIDATED"))
            trustInt = 5;
        else if (!strcmp(trustString, "PMAP_CS_APP_STORE"))
            trustInt = 6;
        else if (!strcmp(trustString, "PMAP_CS_IN_LOADED_TRUST_CACHE"))
            trustInt = 7;
        else if (!strcmp(trustString, "PMAP_CS_IN_STATIC_TRUST_CACHE"))
            trustInt = 8;
    }
    return trustInt;
}

#endif

int sign_kernel_thread(uint64_t proc, mach_port_t threadPort) {
    uint64_t threadKobj = task_get_ipc_port_kobject(proc_task(proc), threadPort);
    uint64_t threadContext = kread_ptr(threadKobj + koffsetof(thread, machine_contextData));

    uint64_t pc = kread64(threadContext + offsetof(kRegisterState, pc));
    uint64_t cpsr = kread64(threadContext + offsetof(kRegisterState, cpsr));
    uint64_t lr = kread64(threadContext + offsetof(kRegisterState, lr));
    uint64_t x16 = kread64(threadContext + offsetof(kRegisterState, x[16]));
    uint64_t x17 = kread64(threadContext + offsetof(kRegisterState, x[17]));

    return kcall(NULL, ksymbol(ml_sign_thread_state), 6, (uint64_t[]){threadContext, pc, cpsr, lr, x16, x17});
}

uint64_t kpacda(uint64_t pointer, uint64_t modifier) {
    if (gPrimitives.kexec && kgadget(pacda)) {
        // |------- GADGET -------|
        // | cmp x1, #0		      |
        // | pacda x1, x9         |
        // | str x9, [x8]         |
        // | csel x9, xzr, x1, eq |
        // | ret                  |
        // |----------------------|
        uint64_t output = 0;
        uint64_t output_kernelVA = phystokv(vtophys(kread_ptr(pmap_self() + koffsetof(pmap, ttep)), (uint64_t)&output));
        kRegisterState threadState = {0};
        threadState.pc = kgadget(pacda);
        threadState.x[1] = pointer;
        threadState.x[9] = modifier;
        threadState.x[8] = output_kernelVA;
        kexec(&threadState);
        return output;
    }
    return 0;
}

uint64_t kptr_sign(uint64_t kaddr, uint64_t pointer, uint16_t salt) {
    uint64_t modifier = (kaddr & 0xffffffffffff) | ((uint64_t)salt << 48);
    return kpacda(UNSIGN_PTR(pointer), modifier);
}

int kwrite1_bits(uint64_t startPtr, uint32_t bitCount) {
    if (bitCount == 0)
        return 0;
    size_t byteSize = ((size_t)bitCount + 7) / 8;
    uint8_t *buf = calloc(byteSize, sizeof(*buf));
    if (!buf)
        return ENOMEM;
    memset(buf, 0xff, byteSize);
    uint32_t trailingBits = bitCount & 7;
    if (trailingBits != 0) {
        buf[byteSize - 1] = (uint8_t)((1U << trailingBits) - 1U);
    }
    int status = kwritebuf(startPtr, buf, byteSize);
    free(buf);
    return status;
}

static int kwrite1_bits_protected(uint64_t startPtr, uint32_t bitCount) {
    if (bitCount == 0)
        return 0;
    size_t byteSize = ((size_t)bitCount + 7) / 8;
    uint8_t *buf = calloc(byteSize, sizeof(*buf));
    if (!buf)
        return ENOMEM;
    memset(buf, 0xff, byteSize);
    uint32_t trailingBits = bitCount & 7;
    if (trailingBits != 0) {
        buf[byteSize - 1] = (uint8_t)((1U << trailingBits) - 1U);
    }
    int status = kwritebuf_protected(startPtr, buf, byteSize);
    free(buf);
    return status;
}

static int read_protected_pointer(uint64_t address, uint64_t *pointerOut) {
    if (!address || !pointerOut)
        return EINVAL;
    uint64_t rawPointer = 0;
    int status = kreadbuf_protected(address, &rawPointer, sizeof(rawPointer));
    if (status != 0)
        return status;
    *pointerOut = UNSIGN_PTR(rawPointer);
    return 0;
}

int proc_allow_all_syscalls(uint64_t proc) {
    if (!gSystemInfo.kernelStruct.proc_ro.exists)
        return 0;
    if (!proc)
        return EINVAL;
    uint64_t proc_ro = kread_ptr(proc + koffsetof(proc, proc_ro));
    if (!proc_ro)
        return EFAULT;

    uint64_t bsdFilter = 0;
    uint64_t machFilter = 0;
    uint64_t machKobjFilter = 0;
    int status = read_protected_pointer(proc_ro + koffsetof(proc_ro, syscall_filter_mask), &bsdFilter);
    if (status != 0)
        return status;
    status = read_protected_pointer(proc_ro + koffsetof(proc_ro, mach_trap_filter_mask), &machFilter);
    if (status != 0)
        return status;
    status = read_protected_pointer(proc_ro + koffsetof(proc_ro, mach_kobj_filter_mask), &machKobjFilter);
    if (status != 0)
        return status;

    if (bsdFilter) {
        status = kwrite1_bits_protected(bsdFilter, kconstant(nsysent));
        if (status != 0)
            return status;
    }
    if (machFilter) {
        status = kwrite1_bits_protected(machFilter, kconstant(mach_trap_count));
        if (status != 0)
            return status;
    }
    if (machKobjFilter) {
        uint64_t machKobjCount = 0;
        status = kreadbuf_protected(ksymbol(mach_kobj_count), &machKobjCount, sizeof(machKobjCount));
        if (status != 0)
            return status;
        if (machKobjCount > UINT32_MAX)
            return EOVERFLOW;
        status = kwrite1_bits_protected(machKobjFilter, (uint32_t)machKobjCount);
        if (status != 0)
            return status;
    }
    return 0;
}

int proc_remove_msg_filter(uint64_t proc) {
    if (!proc)
        return EINVAL;
    if (__builtin_available(iOS 16.0, *)) {
#define TFRO_FILTER_MSG                 0x00004000

        if (koffsetof(proc_ro, t_flags_ro)) {
            // iOS 16.1+
            uint64_t proc_ro = kread_ptr(proc + koffsetof(proc, proc_ro));
            if (!proc_ro)
                return EFAULT;
            uint64_t address = proc_ro + koffsetof(proc_ro, t_flags_ro);
            uint32_t t_flags = 0;
            int status = kreadbuf_protected(address, &t_flags, sizeof(t_flags));
            if (status != 0)
                return status;
            t_flags &= ~TFRO_FILTER_MSG;
            return kwritebuf_protected(address, &t_flags, sizeof(t_flags));
        } else if (koffsetof(task, flags)) {
            // iOS 16.0.x
            uint64_t task = proc_task(proc);
            if (!task)
                return EFAULT;
            uint32_t t_flags = kread32(task + koffsetof(task, flags));
            return kwrite32(task + koffsetof(task, flags), t_flags & ~TFRO_FILTER_MSG);
        }
    }
    return 0;
}

int cmd_wait_for_exit(pid_t pid) {
    int status = 0;
    do {
        if (waitpid(pid, &status, 0) == -1) {
            return -1;
        }
    } while (!WIFEXITED(status) && !WIFSIGNALED(status));
    return status;
}

int __exec_cmd_internal_va(bool suspended,
                           bool root,
                           bool waitForExit,
                           pid_t *pidOut,
                           const char *binary,
                           int argc,
                           va_list va_args,
                           char **envp) {
    const char *argv[argc + 1];
    argv[0] = binary;
    for (int i = 1; i < argc; i++) {
        argv[i] = va_arg(va_args, const char *);
    }
    argv[argc] = NULL;

    posix_spawnattr_t attr = NULL;
    posix_spawnattr_init(&attr);
    if (suspended) {
        posix_spawnattr_setflags(&attr, POSIX_SPAWN_START_SUSPENDED);
    }
    if (root) {
        posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
        posix_spawnattr_set_persona_uid_np(&attr, 0);
        posix_spawnattr_set_persona_gid_np(&attr, 0);
    }

    char **envToUse = envp;
    if (!envToUse && getpid() != 1) {
        // We NEVER want to pass launchd's environment to any process whatsoever
        // This is because, amongst other things, it has DYLD_INSERT_LIBRARIES set to launchdhook which is NO good
        envToUse = environ;
    }

    pid_t spawnedPid = 0;
    int spawnError = exec_cmd_roothide_spawn(&spawnedPid, binary, NULL, &attr, (char *const *)argv, envToUse);
    if (attr)
        posix_spawnattr_destroy(&attr);
    if (spawnError != 0)
        return spawnError;

    if (waitForExit && !suspended) {
        return cmd_wait_for_exit(spawnedPid);
    } else if (pidOut) {
        *pidOut = spawnedPid;
    }
    return 0;
}

int exec_cmd(const char *binary, ...) {
    int argc = 1;
    va_list args;
    va_start(args, binary);
    while (va_arg(args, const char *))
        argc++;
    va_end(args);

    va_start(args, binary);
    int r = __exec_cmd_internal_va(false, false, true, NULL, binary, argc, args, NULL);
    va_end(args);
    return r;
}

int exec_cmd_nowait(pid_t *pidOut, const char *binary, ...) {
    int argc = 1;
    va_list args;
    va_start(args, binary);
    while (va_arg(args, const char *))
        argc++;
    va_end(args);

    va_start(args, binary);
    int r = __exec_cmd_internal_va(false, false, false, pidOut, binary, argc, args, NULL);
    va_end(args);
    return r;
}

int exec_cmd_suspended(pid_t *pidOut, const char *binary, ...) {
    int argc = 1;
    va_list args;
    va_start(args, binary);
    while (va_arg(args, const char *))
        argc++;
    va_end(args);

    va_start(args, binary);
    int r = __exec_cmd_internal_va(true, false, false, pidOut, binary, argc, args, NULL);
    va_end(args);
    return r;
}

int exec_cmd_root(const char *binary, ...) {
    int argc = 1;
    va_list args;
    va_start(args, binary);
    while (va_arg(args, const char *))
        argc++;
    va_end(args);

    va_start(args, binary);
    int r = __exec_cmd_internal_va(false, true, true, NULL, binary, argc, args, NULL);
    va_end(args);
    return r;
}

int exec_cmd_env(char **envp, const char *binary, ...) {
    int argc = 1;
    va_list args;
    va_start(args, binary);
    while (va_arg(args, const char *))
        argc++;
    va_end(args);

    va_start(args, binary);
    int r = __exec_cmd_internal_va(false, false, true, NULL, binary, argc, args, envp);
    va_end(args);
    return r;
}

int jbctl_earlyboot(mach_port_t earlyBootServer, ...) {
    int argc = 2;
    va_list args;
    va_start(args, earlyBootServer);
    while (va_arg(args, const char *))
        argc++;
    va_end(args);

    const char *jbctlPath = JBROOT_PATH("/basebin/jbctl");
    const char *argsArr[argc + 1];
    argsArr[0] = jbctlPath;
    va_start(args, earlyBootServer);
    for (int i = 1; i < argc - 1; i++) {
        argsArr[i] = va_arg(args, const char *);
    }
    argsArr[argc - 1] = "earlyboot";
    argsArr[argc] = NULL;

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_set_registered_ports_np(&attr, (mach_port_t[]){earlyBootServer, MACH_PORT_NULL, MACH_PORT_NULL}, 3);
    pid_t spawnedPid = 0;
    int r = posix_spawn(&spawnedPid, jbctlPath, NULL, &attr, (char *const *)argsArr, NULL);
    posix_spawnattr_destroy(&attr);
    if (r != 0)
        return r;
    return cmd_wait_for_exit(spawnedPid);
}

int proc_ucred_update(uint64_t proc, uint64_t newUcred) {
    if (!proc || !newUcred)
        return EINVAL;
    if (gSystemInfo.kernelStruct.proc_ro.exists) {
        uint64_t proc_ro = kread_ptr(proc + koffsetof(proc, proc_ro));
        if (!proc_ro)
            return EFAULT;
        uint64_t address = proc_ro + koffsetof(proc_ro, ucred);
        int status = kwritebuf_protected(address, &newUcred, sizeof(newUcred));
        if (status != 0)
            return status;

        uint64_t observedUcred = 0;
        status = kreadbuf_protected(address, &observedUcred, sizeof(observedUcred));
        if (status != 0)
            return status;
        return UNSIGN_PTR(observedUcred) == UNSIGN_PTR(newUcred) ? 0 : EIO;
    }
    return kwrite_ptr(proc + koffsetof(proc, ucred), newUcred, 0x84E8);
}

struct setid_proc_snapshot {
    pid_t pid;
    uint64_t proc;
    uint64_t ucred;
};

static int setid_validate_copy_state(const char *phase,
                                     const struct setid_proc_snapshot *source,
                                     const struct setid_proc_snapshot *target) {
    uint64_t sourceProc = proc_find(source->pid);
    uint64_t targetProc = proc_find(target->pid);
    uint64_t sourceUcred = sourceProc ? proc_ucred(sourceProc) : 0;
    uint64_t targetUcred = targetProc ? proc_ucred(targetProc) : 0;
    if (sourceProc == source->proc && sourceUcred == source->ucred && targetProc == target->proc
        && targetUcred == target->ucred) {
        return 0;
    }

    JBLogError(
        "libjailbreak: setid ucred-copy failed phase=%s status=%d " "source-pid=%d source-proc=0x%llx/0x%llx " "source-ucred=0x%llx/0x%llx " "target-pid=%d target-proc=0x%llx/0x%llx " "target-ucred=0x%llx/0x%llx",
        phase,
        ESRCH,
        source->pid,
        source->proc,
        sourceProc,
        source->ucred,
        sourceUcred,
        target->pid,
        target->proc,
        targetProc,
        target->ucred,
        targetUcred);
    return ESRCH;
}

// Both processes are stopped at protocol boundaries: the target is waiting for
// its launchd check-in reply and the donor is waiting for launchd's ACK. They
// can still be killed, so revalidate the naked proc addresses at every phase.
int proc_copy_ucred(uint64_t procCopyFrom, uint64_t procCopyTo) {
    if (!procCopyFrom || !procCopyTo)
        return EINVAL;
    struct setid_proc_snapshot source = {
        .pid = kread32(procCopyFrom + koffsetof(proc, pid)),
        .proc = procCopyFrom,
        .ucred = proc_ucred(procCopyFrom),
    };
    struct setid_proc_snapshot target = {
        .pid = kread32(procCopyTo + koffsetof(proc, pid)),
        .proc = procCopyTo,
        .ucred = proc_ucred(procCopyTo),
    };
    uint64_t ucredToCopy = source.ucred;
    uint64_t origUcred = target.ucred;
    if (!ucredToCopy || !origUcred)
        return errno ? errno : EFAULT;
    int status = setid_validate_copy_state("copy-new-weak-ref", &source, &target);
    if (status != 0)
        return status;
    if (ucredToCopy == origUcred)
        return 0;

    status = kauth_cred_ref(ucredToCopy);
    if (status != 0) {
        JBLogError("libjailbreak: setid ucred-copy failed " "phase=new-weak-ref ucred=0x%llx status=%d",
                  ucredToCopy,
                  status);
        return status;
    }
    status = kauth_cred_hold(ucredToCopy);
    if (status != 0) {
        (void)kauth_cred_unref(ucredToCopy);
        JBLogError("libjailbreak: setid ucred-copy failed " "phase=new-long-ref ucred=0x%llx status=%d",
                  ucredToCopy,
                  status);
        return status;
    }
    status = setid_validate_copy_state("copy-publish", &source, &target);
    if (status != 0) {
        (void)kauth_cred_drop(ucredToCopy);
        (void)kauth_cred_unref(ucredToCopy);
        return status;
    }

    status = proc_ucred_update(procCopyTo, ucredToCopy);
    if (status != 0) {
        (void)kauth_cred_drop(ucredToCopy);
        (void)kauth_cred_unref(ucredToCopy);
        JBLogError("libjailbreak: setid ucred-copy failed " "phase=publish target-proc=0x%llx " "ucred=0x%llx status=%d",
                  procCopyTo,
                  ucredToCopy,
                  status);
        return status;
    }
    target.ucred = ucredToCopy;
    status = setid_validate_copy_state("copy-drop-old", &source, &target);
    if (status != 0) {
        JBLogError("libjailbreak: setid ucred-copy phase=old-retained " "ucred=0x%llx drop-status=%d unref-status=%d",
                  origUcred,
                  status,
                  status);
        return status;
    }

    int dropStatus = kauth_cred_drop(origUcred);
    int unrefStatus = kauth_cred_unref(origUcred);
    if (dropStatus != 0 || unrefStatus != 0) {
        // The new credential is already published and fully referenced.
        // Retaining an old reference is safer than attempting a rollback.
        JBLogError("libjailbreak: setid ucred-copy phase=old-retained " "ucred=0x%llx drop-status=%d unref-status=%d",
                  origUcred,
                  dropStatus,
                  unrefStatus);
    }

    return 0;
}

static int ucred_read(uint64_t ucred, uint64_t offset, void *buffer, size_t size) {
    if (!ucred || !buffer || size == 0)
        return EINVAL;
    return gSystemInfo.kernelStruct.proc_ro.exists ? kreadbuf_protected(ucred + offset, buffer, size)
                                                   : kreadbuf(ucred + offset, buffer, size);
}

static int ucred_write(uint64_t ucred, uint64_t offset, const void *buffer, size_t size) {
    if (!ucred || !buffer || size == 0)
        return EINVAL;
    return gSystemInfo.kernelStruct.proc_ro.exists ? kwritebuf_protected(ucred + offset, buffer, size)
                                                   : kwritebuf(ucred + offset, buffer, size);
}

int proc_read_ucred_identity(uint64_t proc, struct proc_ucred_identity *identityOut) {
    if (!proc || !identityOut)
        return EINVAL;
    uint64_t ucred = proc_ucred(proc);
    if (!ucred)
        return errno ? errno : EFAULT;

    struct proc_ucred_identity identity = {0};
    int status = ucred_read(ucred, koffsetof(ucred, uid), &identity.euid, sizeof(identity.euid));
    if (status == 0) {
        status = ucred_read(ucred, koffsetof(ucred, ruid), &identity.ruid, sizeof(identity.ruid));
    }
    if (status == 0) {
        status = ucred_read(ucred, koffsetof(ucred, svuid), &identity.svuid, sizeof(identity.svuid));
    }
    if (status == 0) {
        status = ucred_read(ucred,
                            koffsetof(ucred, groups) - sizeof(uint32_t),
                            &identity.ngroups,
                            sizeof(identity.ngroups));
    }
    if (status != 0)
        return status;
    if (identity.ngroups == 0 || identity.ngroups > NGROUPS_MAX) {
        return EIO;
    }

    status = ucred_read(ucred,
                        koffsetof(ucred, groups),
                        identity.groups,
                        identity.ngroups * sizeof(identity.groups[0]));
    if (status == 0)
        identity.egid = identity.groups[0];
    if (status == 0) {
        status = ucred_read(ucred, koffsetof(ucred, rgid), &identity.rgid, sizeof(identity.rgid));
    }
    if (status == 0) {
        status = ucred_read(ucred, koffsetof(ucred, svgid), &identity.svgid, sizeof(identity.svgid));
    }
    if (status == 0) {
        status = ucred_read(ucred, koffsetof(ucred, svgid) + sizeof(gid_t), &identity.gmuid, sizeof(identity.gmuid));
    }
    if (status == 0) {
        status = ucred_read(ucred,
                            koffsetof(ucred, svgid) + sizeof(gid_t) + sizeof(uid_t),
                            &identity.flags,
                            sizeof(identity.flags));
    }
    if (status != 0)
        return status;

    *identityOut = identity;
    return 0;
}

static bool setid_identity_matches(const struct proc_ucred_identity *observed,
                                   const struct proc_ucred_identity *expected) {
    if (!observed || !expected)
        return false;
    return observed->euid == expected->euid && observed->ruid == expected->ruid && observed->svuid == expected->svuid
        && observed->egid == expected->egid && observed->rgid == expected->rgid && observed->svgid == expected->svgid
        && observed->gmuid == expected->gmuid && observed->flags == expected->flags
        && observed->ngroups == expected->ngroups
        && memcmp(observed->groups, expected->groups, expected->ngroups * sizeof(expected->groups[0])) == 0;
}

static int setid_write_all(int fd, const void *buffer, size_t size) {
    const uint8_t *cursor = buffer;
    while (size > 0) {
        ssize_t written = write(fd, cursor, size);
        if (written < 0) {
            if (errno == EINTR)
                continue;
            return errno;
        }
        if (written == 0)
            return EIO;
        cursor += written;
        size -= (size_t)written;
    }
    return 0;
}

static int setid_read_all(int fd, void *buffer, size_t size) {
    uint8_t *cursor = buffer;
    while (size > 0) {
        ssize_t received = read(fd, cursor, size);
        if (received < 0) {
            if (errno == EINTR)
                continue;
            return errno;
        }
        if (received == 0)
            return EPIPE;
        cursor += received;
        size -= (size_t)received;
    }
    return 0;
}

enum {
    SETID_DONOR_READY_TIMEOUT_MS = 10000,
    SETID_DONOR_EXIT_TIMEOUT_MS = 2000,
    SETID_DONOR_REAP_INTERVAL_MS = 10,
};

static int setid_wait_for_exit(pid_t pid, bool requireSuccess, int *waitStatusOut) {
    int waitStatus = 0;
    int attempts = SETID_DONOR_EXIT_TIMEOUT_MS / SETID_DONOR_REAP_INTERVAL_MS;
    for (int attempt = 0; attempt <= attempts; attempt++) {
        pid_t waited = waitpid(pid, &waitStatus, WNOHANG);
        if (waited == pid) {
            if (waitStatusOut)
                *waitStatusOut = waitStatus;
            if (!requireSuccess)
                return 0;
            return WIFEXITED(waitStatus) && WEXITSTATUS(waitStatus) == 0 ? 0 : ECHILD;
        }
        if (waited < 0 && errno != EINTR) {
            return errno ? errno : ECHILD;
        }
        if (attempt < attempts) {
            (void)poll(NULL, 0, SETID_DONOR_REAP_INTERVAL_MS);
        }
    }
    return ETIMEDOUT;
}

static int setid_kill_and_reap(pid_t pid) {
    errno = 0;
    int killStatus = kill(pid, SIGKILL) == 0 ? 0 : (errno != 0 ? errno : EIO);
    int reapStatus = setid_wait_for_exit(pid, false, NULL);
    return killStatus != 0 && killStatus != ESRCH ? killStatus : reapStatus;
}

struct setid_donor {
    pid_t pid;
    int controlFd;
};

static void setid_abort_donor(const char *procPath, const char *phase, struct setid_donor *donor) {
    if (!donor)
        return;
    JBLogError("libjailbreak: setid donor phase=abort path=%s " "reason=%s pid=%d fd=%d",
              procPath ?: "(null)",
              phase ?: "(unknown)",
              donor->pid,
              donor->controlFd);
    if (donor->controlFd >= 0) {
        close(donor->controlFd);
        donor->controlFd = -1;
    }
    if (donor->pid > 0) {
        int cleanupStatus = setid_kill_and_reap(donor->pid);
        if (cleanupStatus != 0) {
            JBLogError("libjailbreak: setid donor failed " "phase=abort-reap path=%s pid=%d status=%d",
                      procPath ?: "(null)",
                      donor->pid,
                      cleanupStatus);
        }
        donor->pid = 0;
    }
}

static int setid_finish_donor(const char *procPath, struct setid_donor *donor, int operationStatus) {
    if (!donor || donor->pid <= 0 || donor->controlFd < 0) {
        return EINVAL;
    }

    struct jb_setid_donor_ack ack = {
        .magic = JB_SETID_DONOR_MAGIC,
        .status = operationStatus,
    };
    int status = setid_write_all(donor->controlFd, &ack, sizeof(ack));
    close(donor->controlFd);
    donor->controlFd = -1;
    if (status != 0) {
        JBLogError("libjailbreak: setid donor failed phase=ack-send " "path=%s pid=%d status=%d",
                  procPath,
                  donor->pid,
                  status);
        int cleanupStatus = setid_kill_and_reap(donor->pid);
        if (cleanupStatus != 0) {
            JBLogError("libjailbreak: setid donor failed " "phase=ack-failure-reap path=%s pid=%d status=%d",
                      procPath,
                      donor->pid,
                      cleanupStatus);
        }
        donor->pid = 0;
        return status;
    }

    pid_t donorPid = donor->pid;
    status = setid_wait_for_exit(donorPid, operationStatus == 0, NULL);
    if (status == ETIMEDOUT) {
        int cleanupStatus = setid_kill_and_reap(donorPid);
        JBLogError(
            "libjailbreak: setid donor failed phase=reap-timeout " "path=%s pid=%d timeout-ms=%d cleanup-status=%d",
            procPath,
            donorPid,
            SETID_DONOR_EXIT_TIMEOUT_MS,
            cleanupStatus);
    } else if (status != 0) {
        JBLogError("libjailbreak: setid donor failed phase=reap " "path=%s pid=%d status=%d",
                  procPath,
                  donorPid,
                  status);
    }
    donor->pid = 0;
    return status;
}

static int setid_start_donor(const char *procPath,
                             const struct proc_ucred_identity *identity,
                             mach_port_t auditSessionPort,
                             struct setid_donor *donorOut) {
    if (!procPath || procPath[0] != '/' || !identity || !donorOut) {
        return EINVAL;
    }
    if (identity->ngroups == 0 || identity->ngroups > NGROUPS_MAX) {
        return EINVAL;
    }
    if (identity->egid != identity->groups[0])
        return EINVAL;
    if (auditSessionPort != MACH_PORT_NULL && !MACH_PORT_VALID(auditSessionPort)) {
        return EINVAL;
    }

    int controlSockets[2] = {-1, -1};
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, controlSockets) != 0) {
        return errno;
    }
    int noSigPipe = 1;
    if (setsockopt(controlSockets[0], SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe)) != 0
        || setsockopt(controlSockets[1], SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe)) != 0) {
        int socketError = errno;
        close(controlSockets[0]);
        close(controlSockets[1]);
        return socketError;
    }
    posix_spawn_file_actions_t actions = NULL;
    posix_spawnattr_t attr = NULL;
    int status = posix_spawn_file_actions_init(&actions);
    if (status == 0) {
        status = posix_spawn_file_actions_addinherit_np(&actions, controlSockets[1]);
    }
    if (status == 0) {
        status = posix_spawn_file_actions_addclose(&actions, controlSockets[0]);
    }
    if (status == 0)
        status = posix_spawnattr_init(&attr);
    if (status == 0 && MACH_PORT_VALID(auditSessionPort)) {
        status = posix_spawnattr_setauditsessionport_np(&attr, auditSessionPort);
    }

    char controlFdString[12];
    char ruidString[12];
    char euidString[12];
    char svuidString[12];
    char rgidString[12];
    char egidString[12];
    char svgidString[12];
    char ngroupsString[12];
    char groupStrings[NGROUPS_MAX][12];
    snprintf(controlFdString, sizeof(controlFdString), "%d", controlSockets[1]);
    snprintf(ruidString, sizeof(ruidString), "%u", identity->ruid);
    snprintf(euidString, sizeof(euidString), "%u", identity->euid);
    snprintf(svuidString, sizeof(svuidString), "%u", identity->svuid);
    snprintf(rgidString, sizeof(rgidString), "%u", identity->rgid);
    snprintf(egidString, sizeof(egidString), "%u", identity->egid);
    snprintf(svgidString, sizeof(svgidString), "%u", identity->svgid);
    snprintf(ngroupsString, sizeof(ngroupsString), "%u", identity->ngroups);

    char *argv[JB_SETID_DONOR_FIXED_ARGC + NGROUPS_MAX + 1] = {0};
    argv[0] = (char *)procPath;
    argv[JB_SETID_DONOR_ARG_MARKER] = JB_SETID_DONOR_ARGUMENT;
    argv[JB_SETID_DONOR_ARG_CONTROL_FD] = controlFdString;
    argv[JB_SETID_DONOR_ARG_RUID] = ruidString;
    argv[JB_SETID_DONOR_ARG_EUID] = euidString;
    argv[JB_SETID_DONOR_ARG_SVUID] = svuidString;
    argv[JB_SETID_DONOR_ARG_RGID] = rgidString;
    argv[JB_SETID_DONOR_ARG_EGID] = egidString;
    argv[JB_SETID_DONOR_ARG_SVGID] = svgidString;
    argv[JB_SETID_DONOR_ARG_NGROUPS] = ngroupsString;
    for (uint16_t index = 0; index < identity->ngroups; index++) {
        snprintf(groupStrings[index], sizeof(groupStrings[index]), "%u", identity->groups[index]);
        argv[JB_SETID_DONOR_FIXED_ARGC + index] = groupStrings[index];
    }

    // The empty environment is intentional. launchd's ordinary spawn hook
    // adds SystemHook; no SafeMode or patched-dyld trigger is involved.
    char *const donorEnvironment[] = {NULL};
    pid_t donorPid = 0;
    if (status == 0) {
        status = posix_spawn(&donorPid, procPath, &actions, &attr, argv, donorEnvironment);
    }
    if (attr)
        posix_spawnattr_destroy(&attr);
    if (actions)
        posix_spawn_file_actions_destroy(&actions);
    close(controlSockets[1]);
    if (status != 0 || donorPid <= 0) {
        close(controlSockets[0]);
        int spawnStatus = status != 0 ? status : EIO;
        JBLogError("libjailbreak: setid donor failed phase=spawn " "path=%s pid=%d status=%d",
                  procPath,
                  donorPid,
                  spawnStatus);
        return spawnStatus;
    }

    struct setid_donor donor = {
        .pid = donorPid,
        .controlFd = controlSockets[0],
    };

    struct pollfd pollFd = {
        .fd = donor.controlFd,
        .events = POLLIN,
    };
    int pollStatus;
    do {
        pollStatus = poll(&pollFd, 1, SETID_DONOR_READY_TIMEOUT_MS);
    } while (pollStatus < 0 && errno == EINTR);
    if (pollStatus <= 0) {
        status = pollStatus == 0 ? ETIMEDOUT : errno;
        setid_abort_donor(procPath, "ready-poll", &donor);
        return status;
    }
    if ((pollFd.revents & (POLLIN | POLLHUP)) == 0) {
        setid_abort_donor(procPath, "ready-events", &donor);
        return EPROTO;
    }

    struct jb_setid_donor_reply reply = {0};
    status = setid_read_all(donor.controlFd, &reply, sizeof(reply));
    if (status == 0 && (reply.magic != JB_SETID_DONOR_MAGIC || reply.status != 0 || reply.donorPid != donor.pid)) {
        status = reply.status != 0 ? reply.status : EPROTO;
    }
    if (status != 0) {
        setid_abort_donor(procPath, "ready-reply", &donor);
        return status;
    }
    *donorOut = donor;
    return 0;
}

struct proc_audit_token_snapshot {
    uint64_t address;
    pid_t pid;
    audit_token_t token;
};

static int proc_read_audit_token_snapshot(uint64_t proc,
                                          const char *procPath,
                                          struct proc_audit_token_snapshot *snapshotOut) {
    if (!proc || !procPath || !snapshotOut)
        return EINVAL;

    uint32_t taskTokensOffset = koffsetof(proc_ro, task_tokens);
    uint32_t auditTokenOffset = koffsetof(task_token_ro_data, audit_token);
    if (!gSystemInfo.kernelStruct.proc_ro.exists || taskTokensOffset == 0 || auditTokenOffset == 0) {
        JBLogError(
            "libjailbreak: setid audit-read failed path=%s " "status=%d task-tokens-offset=0x%x " "audit-token-offset=0x%x",
            procPath,
            ENOTSUP,
            taskTokensOffset,
            auditTokenOffset);
        return ENOTSUP;
    }

    uint64_t procRo = kread_ptr(proc + koffsetof(proc, proc_ro));
    if (!procRo) {
        int status = errno ? errno : EFAULT;
        JBLogError("libjailbreak: setid audit-read failed path=%s " "status=%d proc-ro=0x%llx",
                  procPath,
                  status,
                  procRo);
        return status;
    }

    pid_t targetPid = 0;
    int status = kreadbuf(proc + koffsetof(proc, pid), &targetPid, sizeof(targetPid));
    if (status != 0 || targetPid <= 0) {
        if (status == 0)
            status = EPROTO;
        JBLogError("libjailbreak: setid audit-read failed path=%s " "status=%d pid=%d", procPath, status, targetPid);
        return status;
    }

    uint64_t auditTokenAddress = procRo + taskTokensOffset + auditTokenOffset;
    audit_token_t token = {0};
    status = kreadbuf_protected(auditTokenAddress, &token, sizeof(token));
    if (status != 0) {
        JBLogError("libjailbreak: setid audit-read failed path=%s " "pid=%d address=0x%llx status=%d",
                  procPath,
                  targetPid,
                  auditTokenAddress,
                  status);
        return status;
    }
    if (token.val[5] != (uint32_t)targetPid) {
        JBLogError("libjailbreak: setid audit-read failed path=%s " "pid=%d token-pid=%u status=%d",
                  procPath,
                  targetPid,
                  token.val[5],
                  EPROTO);
        return EPROTO;
    }
    *snapshotOut = (struct proc_audit_token_snapshot){
        .address = auditTokenAddress,
        .pid = targetPid,
        .token = token,
    };
    return 0;
}

static int proc_finalize_audit_token(const char *procPath,
                                     const struct proc_ucred_identity *identity,
                                     enum proc_ucred_audit_policy auditPolicy,
                                     const struct proc_audit_token_snapshot *snapshot) {
    if (!procPath || !identity || !snapshot)
        return EINVAL;

    audit_token_t expectedToken = snapshot->token;
    switch (auditPolicy) {
        case PROC_UCRED_AUDIT_PRESERVE:
            break;
        case PROC_UCRED_AUDIT_SYNCHRONIZE: {
            uint32_t expectedIdentity[4] = {
                identity->euid,
                identity->egid,
                identity->ruid,
                identity->rgid,
            };
            memcpy(&expectedToken.val[1], expectedIdentity, sizeof(expectedIdentity));
            if (memcmp(&snapshot->token.val[1], expectedIdentity, sizeof(expectedIdentity)) != 0) {
                int status = kwritebuf_protected(snapshot->address + sizeof(snapshot->token.val[0]),
                                                 expectedIdentity,
                                                 sizeof(expectedIdentity));
                if (status != 0) {
                    JBLogError("libjailbreak: setid audit-write failed " "path=%s pid=%d address=0x%llx " "status=%d",
                              procPath,
                              snapshot->pid,
                              snapshot->address,
                              status);
                    return status;
                }
            }
            break;
        }
        default:
            return EINVAL;
    }

    audit_token_t observedToken = {0};
    int status = kreadbuf_protected(snapshot->address, &observedToken, sizeof(observedToken));
    if (status == 0 && memcmp(&observedToken, &expectedToken, sizeof(observedToken)) != 0) {
        status = EIO;
    }
    if (status != 0) {
        JBLogError("libjailbreak: setid audit-verify failed path=%s " "pid=%d address=0x%llx status=%d",
                  procPath,
                  snapshot->pid,
                  snapshot->address,
                  status);
        return status;
    }

    return 0;
}

int proc_ucred_update_content(uint64_t proc,
                              const char *procPath,
                              const struct proc_ucred_identity *identity,
                              mach_port_t auditSessionPort,
                              enum proc_ucred_audit_policy auditPolicy) {
    if (!proc || !procPath || !identity)
        return EINVAL;
    if (identity->ngroups == 0 || identity->ngroups > NGROUPS_MAX) {
        return EINVAL;
    }
    if (auditPolicy != PROC_UCRED_AUDIT_PRESERVE && auditPolicy != PROC_UCRED_AUDIT_SYNCHRONIZE) {
        return EINVAL;
    }

    struct proc_audit_token_snapshot auditSnapshot = {0};
    int status = proc_read_audit_token_snapshot(proc, procPath, &auditSnapshot);
    if (status != 0)
        return status;

    if (__builtin_available(iOS 17.0, *)) {
        struct proc_ucred_identity expectedIdentity = *identity;

        struct setid_donor donor = {
            .pid = 0,
            .controlFd = -1,
        };
        status = setid_start_donor(procPath, &expectedIdentity, auditSessionPort, &donor);
        if (status != 0) {
            JBLogError("libjailbreak: setid donor failed " "phase=start path=%s status=%d", procPath, status);
            return status;
        }

        uint64_t donorProc = proc_find(donor.pid);
        uint64_t donorUcred = donorProc ? proc_ucred(donorProc) : 0;
        struct proc_ucred_identity donorIdentity = {0};
        status = donorProc && donorUcred ? proc_read_ucred_identity(donorProc, &donorIdentity) : ESRCH;
        if (status == 0) {
            if (!setid_identity_matches(&donorIdentity, &expectedIdentity)) {
                status = EIO;
            }
        }
        if (status != 0) {
            JBLogError(
                "libjailbreak: setid donor failed " "phase=donor-readback path=%s pid=%d " "proc=0x%llx ucred=0x%llx status=%d",
                procPath,
                donor.pid,
                donorProc,
                donorUcred,
                status);
        }

        if (status == 0) {
            status = proc_copy_ucred(donorProc, proc);
        }
        if (donorProc)
            proc_rele(donorProc);

        struct proc_ucred_identity observedIdentity = {0};
        uint64_t observedUcred = 0;
        if (status == 0) {
            observedUcred = proc_ucred(proc);
            if (!observedUcred || UNSIGN_PTR(observedUcred) != UNSIGN_PTR(donorUcred)) {
                status = EIO;
            }
        }
        if (status == 0) {
            status = proc_read_ucred_identity(proc, &observedIdentity);
        }
        if (status == 0) {
            if (!setid_identity_matches(&observedIdentity, &donorIdentity)) {
                status = EIO;
            }
        }
        if (status != 0) {
            JBLogError(
                "libjailbreak: setid ucred-copy failed " "phase=target-readback path=%s pid=%d " "target-ucred=0x%llx donor-ucred=0x%llx " "status=%d",
                procPath,
                donor.pid,
                observedUcred,
                donorUcred,
                status);
        }
        if (status == 0) {
            status = proc_finalize_audit_token(procPath, &expectedIdentity, auditPolicy, &auditSnapshot);
        }

        int cleanupStatus = setid_finish_donor(procPath, &donor, status);
        if (status == 0 && cleanupStatus != 0)
            status = cleanupStatus;
        return status;
    } else {
        uint64_t ucred = proc_ucred(proc);
        if (!ucred)
            return errno ? errno : EFAULT;

        status = ucred_write(ucred, koffsetof(ucred, svuid), &identity->svuid, sizeof(identity->svuid));
        if (status != 0)
            return status;
        status = ucred_write(ucred, koffsetof(ucred, uid), &identity->euid, sizeof(identity->euid));
        if (status != 0)
            return status;
        status = ucred_write(ucred, koffsetof(ucred, ruid), &identity->ruid, sizeof(identity->ruid));
        if (status != 0)
            return status;
        status = ucred_write(ucred,
                             koffsetof(ucred, groups),
                             identity->groups,
                             identity->ngroups * sizeof(identity->groups[0]));
        if (status != 0)
            return status;
        status = ucred_write(ucred, koffsetof(ucred, rgid), &identity->rgid, sizeof(identity->rgid));
        if (status != 0)
            return status;
        status = ucred_write(ucred, koffsetof(ucred, svgid), &identity->svgid, sizeof(identity->svgid));
        if (status != 0)
            return status;
        status = ucred_write(ucred, koffsetof(ucred, svgid) + sizeof(gid_t), &identity->gmuid, sizeof(identity->gmuid));
        if (status != 0)
            return status;

        struct proc_ucred_identity observedIdentity = {0};
        status = proc_read_ucred_identity(proc, &observedIdentity);
        if (status == 0 && !setid_identity_matches(&observedIdentity, identity)) {
            status = EIO;
        }
        if (status != 0) {
            JBLogError("libjailbreak: setid ucred-copy failed " "phase=direct-write-verify path=%s status=%d",
                      procPath,
                      status);
            return status;
        }
        return proc_finalize_audit_token(procPath, identity, auditPolicy, &auditSnapshot);
    }
}

void killall(const char *executablePath, int signal) {
    static int maxArgumentSize = 0;
    if (maxArgumentSize == 0) {
        size_t size = sizeof(maxArgumentSize);
        if (sysctl((int[]){CTL_KERN, KERN_ARGMAX}, 2, &maxArgumentSize, &size, NULL, 0) == -1) {
            JBLogError("libjailbreak: KERN_ARGMAX query failed errno=%d", errno);
            maxArgumentSize = 4096; // Default
        }
    }
    int mib[3] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL};
    struct kinfo_proc *info;
    size_t length;
    int count;

    if (sysctl(mib, 3, NULL, &length, NULL, 0) < 0)
        return;
    if (!(info = malloc(length)))
        return;
    if (sysctl(mib, 3, info, &length, NULL, 0) < 0) {
        free(info);
        return;
    }
    count = length / sizeof(struct kinfo_proc);
    for (int i = 0; i < count; i++) {
        pid_t pid = info[i].kp_proc.p_pid;
        if (pid == 0) {
            continue;
        }
        size_t size = maxArgumentSize;
        char *buffer = malloc((size_t)maxArgumentSize);
        if (!buffer) {
            continue;
        }
        if (sysctl((int[]){CTL_KERN, KERN_PROCARGS2, pid}, 3, buffer, &size, NULL, 0) == 0) {
            char *cExecutablePath = buffer + sizeof(int);
            if (strcmp(cExecutablePath, executablePath) == 0) {
                kill(pid, signal);
            }
        }
        free(buffer);
    }
    free(info);
}

static int copy_data(struct archive *ar, struct archive *aw) {
    int r;
    const void *buff;
    size_t size;
    la_int64_t offset;

    for (;;) {
        r = archive_read_data_block(ar, &buff, &size, &offset);
        if (r == ARCHIVE_EOF)
            return (ARCHIVE_OK);
        if (r < ARCHIVE_OK)
            return (r);
        r = archive_write_data_block(aw, buff, size, offset);
        if (r < ARCHIVE_OK) {
            JBLogError("libjailbreak: archive data write failed status=%d error=%s",
                       r,
                       archive_error_string(aw));
            return (r);
        }
    }
}

int libarchive_unarchive(const char *fileToExtract, const char *extractionPath) {
    struct archive *a;
    struct archive *ext;
    struct archive_entry *entry;
    int flags;
    int r;

    /* Select which attributes we want to restore. */
    flags = ARCHIVE_EXTRACT_TIME;
    flags |= ARCHIVE_EXTRACT_PERM;
    flags |= ARCHIVE_EXTRACT_ACL;
    flags |= ARCHIVE_EXTRACT_FFLAGS;
    flags |= ARCHIVE_EXTRACT_OWNER;

    a = archive_read_new();
    archive_read_support_format_all(a);
    archive_read_support_filter_all(a);
    ext = archive_write_disk_new();
    archive_write_disk_set_options(ext, flags);
    archive_write_disk_set_standard_lookup(ext);
    if ((r = archive_read_open_filename(a, fileToExtract, 10240)))
        return 1;
    for (;;) {
        r = archive_read_next_header(a, &entry);
        if (r == ARCHIVE_EOF)
            break;
        if (r < ARCHIVE_OK)
            JBLogError("libjailbreak: archive header read failed status=%d error=%s",
                       r,
                       archive_error_string(a));
        if (r < ARCHIVE_WARN)
            return 1;

        const char *currentFile = archive_entry_pathname(entry);
        char outputPath[PATH_MAX];
        strlcpy(outputPath, extractionPath, PATH_MAX);
        strlcat(outputPath, "/", PATH_MAX);
        strlcat(outputPath, currentFile, PATH_MAX);

        archive_entry_set_pathname(entry, outputPath);

        r = archive_write_header(ext, entry);
        if (r < ARCHIVE_OK)
            JBLogError("libjailbreak: archive header write failed status=%d error=%s",
                       r,
                       archive_error_string(ext));
        else if (archive_entry_size(entry) > 0) {
            r = copy_data(a, ext);
            if (r < ARCHIVE_OK)
                JBLogError("libjailbreak: archive entry write failed status=%d error=%s",
                           r,
                           archive_error_string(ext));
            if (r < ARCHIVE_WARN)
                return 1;
        }
        r = archive_write_finish_entry(ext);
        if (r < ARCHIVE_OK)
            JBLogError("libjailbreak: archive entry finish failed status=%d error=%s",
                       r,
                       archive_error_string(ext));
        if (r < ARCHIVE_WARN)
            return 1;
    }
    archive_read_close(a);
    archive_read_free(a);
    archive_write_close(ext);
    archive_write_free(ext);

    return 0;
}

// code from ktrw by Brandon Azad : https://github.com/googleprojectzero/ktrw
// A worker thread for activity_thread that just spins.
static void *worker_thread(void *arg) {
    uint64_t end = *(uint64_t *)arg;
    for (;;) {
        close(-1);
        uint64_t now = mach_absolute_time();
        if (now >= end) {
            break;
        }
    }
    return NULL;
}

// A thread to alternately spin and sleep.
#define ACTIVITY_WORKER_COUNT 10
static void *activity_thread(void *arg) {
    volatile uint64_t *runCount = arg;
    struct mach_timebase_info tb;
    mach_timebase_info(&tb);
    const unsigned milliseconds = 40;
    while (*runCount != 0) {
        // Spin for one period on multiple threads.
        uint64_t start = mach_absolute_time();
        uint64_t end = start + milliseconds * 1000 * 1000 * tb.denom / tb.numer;
        pthread_t worker[ACTIVITY_WORKER_COUNT];
        for (unsigned i = 0; i < ACTIVITY_WORKER_COUNT; i++) {
            pthread_create(&worker[i], NULL, worker_thread, &end);
        }
        worker_thread(&end);
        for (unsigned i = 0; i < ACTIVITY_WORKER_COUNT; i++) {
            pthread_join(worker[i], NULL);
        }
        // Sleep for one period.
        usleep(milliseconds * 1000);
    }
    return NULL;
}

static uint64_t gCaffeinateThreadRunCount = 0;
static pthread_t gCaffeinateThread = NULL;

void thread_caffeinate_start(void) {
    if (gCaffeinateThreadRunCount == UINT64_MAX)
        return;
    gCaffeinateThreadRunCount++;
    if (gCaffeinateThreadRunCount == 1) {
        pthread_create(&gCaffeinateThread, NULL, activity_thread, &gCaffeinateThreadRunCount);
    }
}

void thread_caffeinate_stop(void) {
    if (gCaffeinateThreadRunCount == 0)
        return;
    gCaffeinateThreadRunCount--;
    if (gCaffeinateThreadRunCount == 0) {
        pthread_join(gCaffeinateThread, NULL);
    }
}

void convert_data_to_hex_string(const void *data, size_t size, char *outBuf) {
    unsigned char *pin = (unsigned char *)data;
    const char *hex = "0123456789ABCDEF";
    char *pout = outBuf;
    for (; pin < ((unsigned char *)data) + size; pout += 2, pin++) {
        pout[0] = hex[(*pin >> 4) & 0xF];
        pout[1] = hex[*pin & 0xF];
    }
    pout[0] = 0;
}

int convert_hex_string_to_data(const char *string, void *outBuf) {
    size_t length = strlen(string);
    const char *pin = string;
    char *pout = outBuf;
    for (; pin < string + length; pin++) {
        char byte = *pin;
        if (byte >= '0' && byte <= '9')
            byte = byte - '0';
        else if (byte >= 'a' && byte <= 'f')
            byte = byte - 'a' + 10;
        else if (byte >= 'A' && byte <= 'F')
            byte = byte - 'A' + 10;
        else
            return -1;

        int shift = ((pin - (string + length)) % 2) ? 0 : 4;
        *pout = (*pout & ~(0xf << shift)) | (byte << shift);
        if (shift == 0)
            pout++;
    }
    return 0;
}

char *boot_manifest_hash(void) {
    static char *gBuf = NULL;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        io_registry_entry_t registryEntry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/chosen");
        if (registryEntry) {
            CFDataRef bootManifestHashData = IORegistryEntryCreateCFProperty(registryEntry,
                                                                             CFSTR("boot-manifest-hash"),
                                                                             NULL,
                                                                             0);
            CFIndex bootManifestHashLength = CFDataGetLength(bootManifestHashData);

            gBuf = malloc((bootManifestHashLength * 2 * sizeof(char)) + sizeof(char));
            unsigned char *buf = (unsigned char *)CFDataGetBytePtr(bootManifestHashData);
            convert_data_to_hex_string(buf, bootManifestHashLength, gBuf);

            CFRelease(bootManifestHashData);
        }
    });

    return gBuf;
}
