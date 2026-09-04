//
//  RLXXPFSession.m
//  RelaxinEngine
//

#import "RLXXPFSession.h"

#import "../../Diagnostic/RLXEngineDiagnostic.h"
#import "../../Log/RLXEngineLog.h"
#import "../Access/RLXKernelAccessFailure.h"
#import "RLXKernelInfo.h"
#import "RLXKernelOffsetTable.h"
#import "../Exploit/Rocket/Rocket.h"

#import <libjailbreak/info.h>
#import <xpf/xpf.h>

#include <dlfcn.h>
#include <stdio.h>

extern uint64_t kernel_slide;

/*
 * Every patchfinder failure reports the same stage; `details` appends what this
 * one knows, through the builder rather than as pre-rendered text.
 *
 * The session says nothing about whether the kernel is dirty. On its own it is
 * not — it opens a file and reads it — and whether the run around it left the
 * kernel modified is the caller's fact, folded in on receipt.
 */
static RLXKernelAccessFailure *rlx_xpf_failure(NSString *description,
                                               NSString *reason,
                                               RLXKernelAccessDiagnosticDetails details) {
    RLXEngineDiagnostic *built = [RLXEngineDiagnostic diagnosticWithStage:@"analyze_kernelcache"];
    details(built);
    // clang-format off
    return [RLXKernelAccessFailure
        failureWithKind:RLXKernelAccessFailureKindAccessUnavailable
                 status:0
            description:description
          failureReason:reason
     recoverySuggestion:@"Verify the bundled libchoma/libxpf pair and the acquired kernelcache."
             diagnostic:built];
    // clang-format on
}

@interface RLXXPFSession ()

- (NSString *)currentXPFError;
- (void)stopAndClose;
- (void)closeLibraries;

@end

@implementation RLXXPFSession {
    void *_chomaHandle;
    void *_xpfHandle;
    BOOL _started;
}

- (nullable instancetype)initWithKernelcachePath:(NSString *)kernelcachePath
                                  resourceBundle:(NSBundle *)resourceBundle
                                         failure:(RLXKernelAccessFailure *_Nullable *_Nullable)failure {
    self = [super init];
    if (!self) {
        return nil;
    }

    NSString *chomaPath = [resourceBundle pathForResource:@"libchoma" ofType:@"dylib"];
    NSString *xpfPath = [resourceBundle pathForResource:@"libxpf" ofType:@"dylib"];
    if (!chomaPath || !xpfPath) {
        if (failure) {
            *failure = rlx_xpf_failure(@"The bundled patchfinder libraries are unavailable.",
                                       @"libchoma.dylib or libxpf.dylib is missing from the resource bundle.",
                                       ^(RLXEngineDiagnostic *diagnostic) {
                                           [diagnostic appendKey:@"bundle" value:resourceBundle.bundlePath];
                                           [diagnostic appendKey:@"libchoma" value:chomaPath fallback:@"missing"];
                                           [diagnostic appendKey:@"libxpf" value:xpfPath fallback:@"missing"];
                                       });
        }
        return nil;
    }

    _chomaHandle = dlopen(chomaPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!_chomaHandle) {
        NSString *reason = [NSString stringWithUTF8String:dlerror() ?: "unknown dlopen error"];
        if (failure) {
            *failure = rlx_xpf_failure(@"The bundled ChOma library could not be loaded.",
                                       reason,
                                       ^(RLXEngineDiagnostic *diagnostic) {
                                           [diagnostic appendKey:@"library" value:@"libchoma"];
                                           [diagnostic appendKey:@"path" value:chomaPath];
                                       });
        }
        return nil;
    }

    _xpfHandle = dlopen(xpfPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!_xpfHandle) {
        NSString *reason = [NSString stringWithUTF8String:dlerror() ?: "unknown dlopen error"];
        if (failure) {
            *failure = rlx_xpf_failure(@"The bundled XPF library could not be loaded.",
                                       reason,
                                       ^(RLXEngineDiagnostic *diagnostic) {
                                           [diagnostic appendKey:@"library" value:@"libxpf"];
                                           [diagnostic appendKey:@"path" value:xpfPath];
                                       });
        }
        [self closeLibraries];
        return nil;
    }

    _started = YES;
    if (xpf_start_with_kernel_path(kernelcachePath.fileSystemRepresentation) != 0) {
        NSString *reason = [self currentXPFError];
        if (failure) {
            *failure = rlx_xpf_failure(@"The kernelcache could not be opened by XPF.",
                                       reason,
                                       ^(RLXEngineDiagnostic *diagnostic) {
                                           [diagnostic appendKey:@"kernelcache" value:kernelcachePath];
                                           [diagnostic appendKey:@"xpf_start" boolValue:NO];
                                       });
        }
        [self stopAndClose];
        return nil;
    }

    _staticKernelBase = gXPF.kernelBase;
    _arm64eKernel = gXPF.kernelIsArm64e;
    _SPTMDevice = gXPF.isSPTMDevice;
    _xnuBuild = gXPF.xnuBuild ? [NSString stringWithUTF8String:gXPF.xnuBuild] : @"";
    _osVersion = gXPF.osVersion ? [NSString stringWithUTF8String:gXPF.osVersion] : @"";
    return self;
}

- (NSString *)currentXPFError {
    const char *message = xpf_get_error();
    return message ? [NSString stringWithUTF8String:message] : @"XPF did not provide an error message.";
}

- (uint64_t)resolveRequiredItem:(NSString *)name failure:(RLXKernelAccessFailure *_Nullable *_Nullable)failure {
    uint64_t value = xpf_item_resolve(name.UTF8String);
    if (value != 0) {
        return value;
    }

    if (failure) {
        *failure = rlx_xpf_failure(@"A required kernelcache value could not be resolved.",
                                   [self currentXPFError],
                                   ^(RLXEngineDiagnostic *diagnostic) {
                                       [diagnostic appendKey:@"item" value:name];
                                       [diagnostic appendKey:@"value" hex64Value:0];
                                   });
    }
    return 0;
}

typedef struct {
    const char *name;
    uint64_t value;
    uint32_t alignment;
} RLXRequiredKernelOffset;

static NSString *rlx_xpf_invalid_post_exploitation_field(uint64_t *valueOut) {
    const RLXRequiredKernelOffset requiredOffsets[] = {
        {"proc.struct_size", ksizeof(proc), 8},
        {"proc.proc_ro", koffsetof(proc, proc_ro), 8},
        {"proc.pid", koffsetof(proc, pid), 4},
        {"proc.flag", koffsetof(proc, flag), 4},
        {"proc_ro.ucred", koffsetof(proc_ro, ucred), 8},
        {"proc_ro.csflags", koffsetof(proc_ro, csflags), 4},
        {"proc_ro.t_flags_ro", koffsetof(proc_ro, t_flags_ro), 4},
        {"ucred.uid", koffsetof(ucred, uid), 4},
        {"ucred.ruid", koffsetof(ucred, ruid), 4},
        {"ucred.svuid", koffsetof(ucred, svuid), 4},
        {"ucred.groups", koffsetof(ucred, groups), 8},
        {"ucred.rgid", koffsetof(ucred, rgid), 4},
        {"ucred.svgid", koffsetof(ucred, svgid), 4},
        {"ucred.label", koffsetof(ucred, label), 8},
        {"label.sandbox", koffsetof(label, sandbox), 8},
        {"task.map", koffsetof(task, map), 8},
        {"task.itk_space", koffsetof(task, itk_space), 8},
        {"task.task_can_transfer_memory_ownership", koffsetof(task, task_can_transfer_memory_ownership), 8},
        {"ipc_space.table", koffsetof(ipc_space, table), 8},
        {"ipc_entry.struct_size", ksizeof(ipc_entry), 8},
        {"ipc_port.kobject", koffsetof(ipc_port, kobject), 8},
        {"vm_map.hdr", koffsetof(vm_map, hdr), 8},
        {"vm_map.pmap", koffsetof(vm_map, pmap), 8},
        {"vm_map.flags", koffsetof(vm_map, flags), 4},
        {"vm_map_header.nentries", koffsetof(vm_map_header, nentries), 4},
        {"vm_map_links.next", koffsetof(vm_map_links, next), 8},
        {"vm_map_links.min", koffsetof(vm_map_links, min), 8},
        {"vm_map_links.max", koffsetof(vm_map_links, max), 8},
        {"pmap.ttep", koffsetof(pmap, ttep), 8},
        {"trustcache.prevptr", koffsetof(trustcache, prevptr), 8},
        {"trustcache.size", koffsetof(trustcache, size), 8},
        {"trustcache.fileptr", koffsetof(trustcache, fileptr), 8},
        {"trustcache.struct_size", ksizeof(trustcache), 8},
    };
    NSString *invalidField = nil;
    *valueOut = 0;
    for (size_t index = 0; index < sizeof(requiredOffsets) / sizeof(requiredOffsets[0]); index++) {
        RLXRequiredKernelOffset offset = requiredOffsets[index];
        if (offset.value == 0 || offset.value >= 0x2000 || offset.value % offset.alignment != 0) {
            invalidField = @(offset.name);
            *valueOut = offset.value;
            break;
        }
    }
    uint64_t trustcacheSize = ksizeof(trustcache);
    if (!invalidField
        && (koffsetof(trustcache, prevptr) + sizeof(uint64_t) > trustcacheSize
            || koffsetof(trustcache, size) + sizeof(uint64_t) > trustcacheSize
            || koffsetof(trustcache, fileptr) + sizeof(uint64_t) > trustcacheSize)) {
        invalidField = @"trustcache.bounds";
        *valueOut = trustcacheSize;
    }
    if (!invalidField && koffsetof(label, sandbox) + sizeof(uint64_t) > 0x20) {
        invalidField = @"label.sandbox_bounds";
        *valueOut = koffsetof(label, sandbox);
    }
    if (!invalidField
        && (!gSystemInfo.kernelStruct.proc_ro.exists || !kconstant(pointer_mask) || !ksymbol(ppl_trust_cache_rt))) {
        invalidField = @"post_exploitation_prerequisites";
    }
    return invalidField;
}

/*
 * Hands one offset dictionary to libjailbreak and establishes the slide from
 * it. Shared by both sources, because a dictionary read from the table and one
 * built from a kernelcache are the same dictionary and must land the same way.
 *
 * Borrows `dictionary`; each caller owns the reference it passes in.
 */
static BOOL rlx_xpf_apply_offset_dictionary(xpc_object_t dictionary,
                                            uint64_t staticKernelBase,
                                            uint64_t liveKernelBase,
                                            NSString *source,
                                            RLXKernelAccessFailure *_Nullable *_Nullable failure) {
    jbinfo_initialize_dynamic_offsets(dictionary);
    if (staticKernelBase == 0 || gSystemInfo.kernelConstant.staticBase != staticKernelBase
        || liveKernelBase < staticKernelBase) {
        if (failure) {
            *failure = rlx_xpf_failure(@"The kernel information produced an inconsistent kernel base.",
                                       @"The live and static kernel bases could not reconstruct a valid slide.",
                                       ^(RLXEngineDiagnostic *diagnostic) {
                                           [diagnostic appendKey:@"source" value:source];
                                           [diagnostic appendKey:@"live_base" hex64Value:liveKernelBase];
                                           [diagnostic appendKey:@"static_base" hex64Value:staticKernelBase];
                                           [diagnostic appendKey:@"decoded_static_base"
                                                      hex64Value:gSystemInfo.kernelConstant.staticBase];
                                       });
        }
        return NO;
    }
    gSystemInfo.kernelConstant.slide = liveKernelBase - staticKernelBase;
    jbinfo_initialize_hardcoded_offsets();

    uint64_t invalidValue = 0;
    NSString *invalidField = rlx_xpf_invalid_post_exploitation_field(&invalidValue);
    if (invalidField) {
        if (failure) {
            *failure = rlx_xpf_failure(@"The post-exploitation kernel layout is incomplete.",
                                       @"A privilege, trust-cache, or launchd field failed validation.",
                                       ^(RLXEngineDiagnostic *diagnostic) {
                                           [diagnostic appendKey:@"source" value:source];
                                           [diagnostic appendKey:@"field" value:invalidField];
                                           [diagnostic appendKey:@"value" hex64Value:invalidValue];
                                       });
        }
        return NO;
    }
    return YES;
}

- (BOOL)initializeSystemInformationForLiveKernelBase:(uint64_t)liveKernelBase
                                             failure:(RLXKernelAccessFailure *_Nullable *_Nullable)failure {
    const char *sets[ROCKET_STATIC_PROFILE_OFFSET_SET_MAX] = {0};
    (void)rocket_static_profile_offset_sets(sets, ROCKET_STATIC_PROFILE_OFFSET_SET_MAX);

    xpc_object_t dictionary = xpf_construct_offset_dictionary(sets);
    if (!dictionary) {
        if (failure) {
            *failure = rlx_xpf_failure(@"XPF could not construct the kernel information dictionary.",
                                       [self currentXPFError],
                                       ^(RLXEngineDiagnostic *diagnostic) {
                                           [diagnostic appendKey:@"xpf_dictionary" boolValue:NO];
                                       });
        }
        return NO;
    }

    xpc_dictionary_set_uint64(dictionary, "kernelConstant.staticBase", gXPF.kernelBase);

    uint64_t staticKernelBase = gXPF.kernelBase;
    xpf_stop();
    _started = NO;

    // XPF returns this at +1 without a retained-result annotation, on top of
    // the reference ARC took on assignment. Balancing it here leaves ARC's,
    // which is the one the helper borrows and this scope releases.
    (void)CFBridgingRelease((__bridge CFTypeRef)dictionary);
    return rlx_xpf_apply_offset_dictionary(dictionary, staticKernelBase, liveKernelBase, @"kernelcache", failure);
}

- (void)stopAndClose {
    if (_started) {
        xpf_stop();
        _started = NO;
    }
    [self closeLibraries];
}

- (void)closeLibraries {
    if (_xpfHandle) {
        dlclose(_xpfHandle);
        _xpfHandle = NULL;
    }
    if (_chomaHandle) {
        dlclose(_chomaHandle);
        _chomaHandle = NULL;
    }
}

- (void)dealloc {
    [self stopAndClose];
}

/*
 * The last stretch of the analysis, which belongs to neither source: the slide
 * comes from the running kernel and the SPTM arguments slot comes back from
 * Rocket, whichever way the static half arrived.
 */
static RLXKernelInfo *rlx_xpf_publish_kernel_info(rlx_kernel_patchfinder_info patchfinder,
                                                  uint64_t liveKernelBase,
                                                  RLXKernelAccessFailure *_Nullable *_Nullable failureOut) {
    if (liveKernelBase < patchfinder.static_base) {
        rlx_engine_log(RLX_ENGINE_LOG_ERROR, "RLXKernelAccess", "The live kernel base is below the static kernel base");
        if (failureOut) {
            *failureOut = rlx_kernel_access_failure(@"xpf_slide",
                                                    EPROTO,
                                                    @"The live kernel base is below the static base.",
                                                    YES,
                                                    ^(RLXEngineDiagnostic *diagnostic) {
                                                        [diagnostic appendKey:@"liveKernelBase"
                                                                   hex64Value:liveKernelBase];
                                                        [diagnostic appendKey:@"static_base"
                                                                   hex64Value:patchfinder.static_base];
                                                    });
        }
        return nil;
    }
    kernel_slide = liveKernelBase - patchfinder.static_base;
    gSystemInfo.kernelConstant.slide = kernel_slide;

    uint64_t sptmArgs = 0;
    if (patchfinder.is_sptm) {
        sptmArgs = kernel_exploit_sptm_args_static_address();
        if (!sptmArgs) {
            rlx_engine_log(RLX_ENGINE_LOG_ERROR,
                           "RLXKernelAccess",
                           "Rocket did not publish the recovered SPTM arguments slot");
            if (failureOut) {
                *failureOut = rlx_kernel_access_failure(@"sptm_arguments",
                                                        EPROTO,
                                                        @"Rocket did not publish the recovered SPTM arguments slot.",
                                                        YES,
                                                        ^(RLXEngineDiagnostic *diagnostic) {
                                                            [diagnostic appendKey:@"protection" value:@"sptm"];
                                                            [diagnostic appendKey:@"sptm_args" hex64Value:0];
                                                        });
            }
            return nil;
        }
    }
    gSystemInfo.relaxinKernelSymbol.sptm_args = sptmArgs;
    return [[RLXKernelInfo alloc] initWithPatchfinderInfo:patchfinder];
}

/*
 * The log category stays "RLXKernelAccess" even though the code moved here:
 * category strings cross into the Swift app's log and are part of the contract,
 * and these are the same messages from the same engine stage as before.
 */
+ (nullable RLXKernelInfo *)analyzeKernelcacheAtPath:(NSString *)path
                                      resourceBundle:(NSBundle *)resourceBundle
                                      liveKernelBase:(uint64_t)liveKernelBase
                                             failure:(RLXKernelAccessFailure *_Nullable *_Nullable)failureOut {
    RLXKernelAccessFailure *failure = nil;
    RLXXPFSession *session = [[RLXXPFSession alloc] initWithKernelcachePath:path resourceBundle:resourceBundle
                                                                    failure:&failure];
    if (!session) {
        rlx_engine_log(RLX_ENGINE_LOG_ERROR, "RLXKernelAccess", failure.failureDescription.UTF8String);
        if (failureOut) {
            *failureOut = failure;
        }
        return nil;
    }

    rlx_kernel_patchfinder_info patchfinder = {0};
    patchfinder.static_base = session.staticKernelBase;
    struct {
        __unsafe_unretained NSString *name;
        uint64_t *value;
    } requiredItems[] = {
        {@"kernelSymbol.cpu_ttep", &patchfinder.cpu_ttep_symbol},
        {@"kernelSymbol.gVirtBase", &patchfinder.virtual_base_symbol},
        {@"kernelSymbol.gPhysBase", &patchfinder.physical_base_symbol},
        {@"kernelSymbol.gPhysSize", &patchfinder.physical_size_symbol},
        {@"kernelSymbol.ptov_table", &patchfinder.ptov_table_symbol},
        {@"kernelStruct.vm_map.pmap", &patchfinder.vm_map_pmap_offset},
        {@"kernelConstant.ARM_TT_L1_INDEX_MASK", &patchfinder.arm_tt_l1_index_mask},
        {@"kernelConstant.T1SZ_BOOT", &patchfinder.t1sz_boot},
        {@"kernelConstant.kernel_el", &patchfinder.kernel_el},
    };
    for (size_t index = 0; index < sizeof(requiredItems) / sizeof(requiredItems[0]); index++) {
        *requiredItems[index].value = [session resolveRequiredItem:requiredItems[index].name failure:&failure];
        if (*requiredItems[index].value == 0) {
            rlx_engine_log(RLX_ENGINE_LOG_ERROR, "RLXKernelAccess", failure.failureDescription.UTF8String);
            if (failureOut) {
                *failureOut = failure;
            }
            return nil;
        }
    }

    if (!session.isArm64eKernel
        || (sscanf(session.xnuBuild.UTF8String,
                   "%u.%u.%u.%*u.%*u~%u",
                   &patchfinder.xnu_major,
                   &patchfinder.xnu_minor,
                   &patchfinder.xnu_patch,
                   &patchfinder.xnu_revision)
                != 4
            && sscanf(session.xnuBuild.UTF8String,
                      "%u.%u.%u~%u",
                      &patchfinder.xnu_major,
                      &patchfinder.xnu_minor,
                      &patchfinder.xnu_patch,
                      &patchfinder.xnu_revision)
                != 4)
        || ![session initializeSystemInformationForLiveKernelBase:liveKernelBase failure:&failure]) {
        if (!failure) {
            failure = rlx_kernel_access_failure(@"xpf_profile",
                                                EPROTO,
                                                @"XPF returned a kernel profile incompatible with Rocket.",
                                                YES,
                                                ^(RLXEngineDiagnostic *diagnostic) {
                                                    [diagnostic appendKey:@"arm64e" boolValue:session.isArm64eKernel];
                                                    [diagnostic appendKey:@"sptm" boolValue:session.isSPTMDevice];
                                                    [diagnostic appendKey:@"xnu" value:session.xnuBuild];
                                                });
        }
        rlx_engine_log(RLX_ENGINE_LOG_ERROR,
                       "RLXKernelAccess",
                       (failure.failureDescription ?: @"The post-exploitation XPF result is incompatible.").UTF8String);
        if (failureOut) {
            *failureOut = failure;
        }
        return nil;
    }
    patchfinder.is_sptm = session.isSPTMDevice;
    return rlx_xpf_publish_kernel_info(patchfinder, liveKernelBase, failureOut);
}

+ (nullable RLXKernelInfo *)analyzeOffsetProfile:(RLXKernelOffsetProfile *)profile
                                  liveKernelBase:(uint64_t)liveKernelBase
                                         failure:(RLXKernelAccessFailure *_Nullable *_Nullable)failureOut {
    rlx_kernel_patchfinder_info patchfinder = profile.patchfinderInfo;
    if (!profile.isArm64eKernel || patchfinder.xnu_major == 0) {
        RLXKernelAccessFailure
            *failure = rlx_kernel_access_failure(@"offset_profile",
                                                 EPROTO,
                                                 @"The bundled offset profile is incompatible with Rocket.",
                                                 YES,
                                                 ^(RLXEngineDiagnostic *diagnostic) {
                                                     [diagnostic appendKey:@"arm64e" boolValue:profile.isArm64eKernel];
                                                     [diagnostic appendKey:@"sptm" boolValue:profile.isSPTMDevice];
                                                     [diagnostic appendKey:@"xnu" value:profile.xnuBuild];
                                                     [diagnostic appendKey:@"kernelcache"
                                                                     value:profile.kernelcacheDigest];
                                                 });
        rlx_engine_log(RLX_ENGINE_LOG_ERROR, "RLXKernelAccess", failure.failureDescription.UTF8String);
        if (failureOut) {
            *failureOut = failure;
        }
        return nil;
    }

    RLXKernelAccessFailure *failure = nil;
    if (!rlx_xpf_apply_offset_dictionary(profile.offsetDictionary,
                                         profile.staticKernelBase,
                                         liveKernelBase,
                                         @"table",
                                         &failure)) {
        rlx_engine_log(RLX_ENGINE_LOG_ERROR, "RLXKernelAccess", failure.failureDescription.UTF8String);
        if (failureOut) {
            *failureOut = failure;
        }
        return nil;
    }

    return rlx_xpf_publish_kernel_info(patchfinder, liveKernelBase, failureOut);
}

@end
