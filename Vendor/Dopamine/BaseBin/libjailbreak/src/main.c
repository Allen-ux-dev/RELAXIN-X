#include "jbclient_xpc.h"
#include <stdlib.h>
#include "physrw.h"
#include "physrw_pte.h"
#include "kalloc_pt.h"
#include "primitives_IOSurface.h"
#include "info.h"
#include "machine_info.h"
#include "translation.h"
#include "kcall_Fugu14.h"
#include "kcall_arm64.h"
#include "log.h"
#include <errno.h>
#include <stdio.h>
#include <sys/sysctl.h>
#include <xpc/xpc.h>

typedef enum {
    JBCLIENT_PRIMITIVE_MODE_FULL,
    JBCLIENT_PRIMITIVE_MODE_PTE,
    JBCLIENT_PRIMITIVE_MODE_PTE_ONLY,
} jbclient_primitive_mode;

static bool jbclient_supports_pte_only_mode(void) {
    if (system_info_uses_sptm())
        return true;

    uint32_t cpuFamily = 0;
    size_t cpuFamilySize = sizeof(cpuFamily);
    return sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0) == 0
        && cpuFamily == CPUFAMILY_ARM_FIRESTORM_ICESTORM;
}

static int jbclient_initialize_primitives_for_mode(jbclient_primitive_mode mode) {
    if (getuid() != 0)
        return -1;

    xpc_object_t xSystemInfo = NULL;
    int status = jbclient_root_get_sysinfo(&xSystemInfo);
    if (status != 0 || !xSystemInfo) {
        if (xSystemInfo)
            xpc_release(xSystemInfo);
        return status != 0 ? status : -1;
    }

    SYSTEM_INFO_DESERIALIZE(xSystemInfo);
    xpc_release(xSystemInfo);

    bool usesSPTM = system_info_uses_sptm();
    bool pteOnly = mode == JBCLIENT_PRIMITIVE_MODE_PTE_ONLY;
    if (usesSPTM && !pteOnly)
        return ENOTSUP;
    if (pteOnly && !jbclient_supports_pte_only_mode())
        return ENOTSUP;

    bool physrwPTE = mode == JBCLIENT_PRIMITIVE_MODE_PTE || pteOnly;
    uint64_t pageTableVirtualAddress = 0;
    if (physrwPTE) {
        status = physrw_pte_preseed(&pageTableVirtualAddress);
        if (status != 0)
            return status;
    }

    uint64_t asidPtr = 0;
    status = jbclient_root_get_physrw(physrwPTE, pageTableVirtualAddress, &asidPtr);
    if (status != 0)
        return status;

    status = physrwPTE ? libjailbreak_physrw_pte_init(true, asidPtr) : libjailbreak_physrw_init(true);
    if (status != 0)
        return status;

    if (!libjailbreak_translation_init())
        return -1;
    if (physrwPTE) {
        /* Standby handoff needs the completed SPTM translation context. */
        status = physrw_pte_prepare_standby_generation();
        if (status != 0)
            return status;
    }
    if (pteOnly) {
        if (!gPrimitives.physreadbuf || !gPrimitives.physwritebuf || !gPrimitives.physaccess_mapped
            || !gPrimitives.kaccess_mapped || !gPrimitives.vtophys || !gPrimitives.phystokv || gPrimitives.kreadbuf
            || gPrimitives.kwritebuf || gPrimitives.kcall || gPrimitives.kexec || gPrimitives.kalloc_global
            || gPrimitives.kalloc_local || gPrimitives.kfree_global || gPrimitives.kmap
            || gPrimitives.protectedKwrite32) {
            return EPROTO;
        }
        JBLogDebug("primitive initialization status=complete mode=pte-only asid=0x%llx", asidPtr);
        return 0;
    }

    libjailbreak_IOSurface_primitives_init();
    if (__builtin_available(iOS 16.0, *)) {
        libjailbreak_kalloc_pt_init();
    }
    if (gPrimitives.kalloc_local) {
#ifdef __arm64e__
        if (jbinfo(usesPACBypass)) {
            jbclient_get_fugu14_kcall();
        }
#else
        arm64_kcall_init();
#endif
    }

    return 0;
}

int jbclient_initialize_primitives_internal(bool physrwPTE) {
    return jbclient_initialize_primitives_for_mode(physrwPTE ? JBCLIENT_PRIMITIVE_MODE_PTE
                                                             : JBCLIENT_PRIMITIVE_MODE_FULL);
}

int jbclient_initialize_primitives_pte_only(void) {
    return jbclient_initialize_primitives_for_mode(JBCLIENT_PRIMITIVE_MODE_PTE_ONLY);
}

int jbclient_initialize_jailbreakd_primitives(void) {
    int status = jbclient_initialize_primitives_pte_only();
    if (status == ENOTSUP) {
        return jbclient_initialize_primitives_for_mode(JBCLIENT_PRIMITIVE_MODE_FULL);
    }
    return status;
}

int jbclient_initialize_primitives(void) {
    int status = jbclient_initialize_primitives_pte_only();
    if (status == ENOTSUP) {
        return jbclient_initialize_primitives_internal(false);
    }
    return status;
}

// Used for supporting third party legacy software that still calls this function
int jbdInitPPLRW(void) {
    return jbclient_initialize_primitives();
}
