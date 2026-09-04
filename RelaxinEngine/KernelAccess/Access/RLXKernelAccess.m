//
//  RLXKernelAccess.m
//  RelaxinEngine
//

#import "../RLXKernelAccess.h"
#import "RLXKernelAccessInternal.h"

#import "../../Diagnostic/RLXEngineDiagnostic.h"
#import "../../Log/RLXEngineLog.h"
#import "RLXKernelAccessFailure.h"
#import "RLXKernelcacheStaging.h"
#import "../Analysis/RLXKernelInfo.h"
#import "../Analysis/RLXKernelOffsetTable.h"
#import "RLXRocketRuntime.h"
#import "../Analysis/RLXXPFSession.h"
#import "../Exploit/Rocket/Rocket.h"

#include <copyfile.h>
#include <errno.h>
#include <libjailbreak/info.h>
#include <libjailbreak/primitives_external.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

extern int exploit_init(const char *flavor);
extern uint64_t kernel_base;
extern uint64_t kernel_slide;

// clang-format off
static BOOL rlx_kernel_access_is_valid(const rlx_kernel_access *access) {
    return access->version == RLX_KERNEL_ACCESS_VERSION
        && access->size >= sizeof(*access)
        && access->token != 0
        && access->layout.version == RLX_KERNEL_LAYOUT_VERSION
        && access->layout.size >= sizeof(access->layout)
        && access->layout.reserved == 0
        && access->layout.page_size != 0
        && access->kernel_read
        && access->kernel_write
        && access->physical_read
        && access->physical_write
        && access->finalize;
}
// clang-format on

@interface RLXKernelAccess ()

- (int)buildAccess:(rlx_kernel_access *)access;

@end

typedef struct {
    __unsafe_unretained RLXKernelAccess *owner;
    semaphore_t completion;
    rlx_kernel_access access;
    int status;
} rlx_exploit_thread_context;

static void *rlx_run_exploit_on_worker_thread(void *opaqueContext) {
    rlx_exploit_thread_context *context = opaqueContext;
    @autoreleasepool {
        context->status = [context->owner buildAccess:&context->access];
    }
    if (semaphore_signal(context->completion) != KERN_SUCCESS) {
        abort();
    }
    return NULL;
}

@implementation RLXKernelAccess {
    rlx_kernel_access _accessStorage;
    RLXKernelInfo *_kernelInfo;
    RLXKernelOffsetProfile *_offsetProfile;
    RLXKernelAccessFailure *_buildFailure;
    NSBundle *_resourceBundle;
    NSURL *_dataDirectoryURL;
    /// This instance's claim on the process-wide Rocket runtime, or zero.
    ///
    /// Held from the moment `-buildAccess:` acquires the runtime until teardown
    /// releases it, including across a failed build: the acquisition that
    /// started Rocket is the one that has to finish with it.
    rlx_rocket_runtime_token _runtimeToken;
}

- (instancetype)initWithKernelcachePath:(NSString *)kernelcachePath
                         resourceBundle:(NSBundle *)resourceBundle
                       dataDirectoryURL:(NSURL *)dataDirectoryURL {
    self = [super init];
    if (self) {
        _kernelcachePath = [kernelcachePath copy];
        _resourceBundle = resourceBundle;
        _dataDirectoryURL = [dataDirectoryURL copy];
    }
    return self;
}

- (instancetype)initWithKernelcachePath:(NSString *)kernelcachePath
                          offsetProfile:(RLXKernelOffsetProfile *)offsetProfile
                         resourceBundle:(NSBundle *)resourceBundle
                       dataDirectoryURL:(NSURL *)dataDirectoryURL {
    self = [self initWithKernelcachePath:kernelcachePath resourceBundle:resourceBundle
                        dataDirectoryURL:dataDirectoryURL];
    if (self) {
        _offsetProfile = offsetProfile;
    }
    return self;
}

- (BOOL)isActive {
    /*
     * Derived from the runtime, not tracked beside it. A published callback
     * table whose runtime has been torn down — or latched Dirty by a teardown
     * that failed — is not access, and answering from the struct alone is what
     * used to report `active` while every call returned ENOTSUP.
     *
     * It is a report, not a permission: by the time a caller acts on it the
     * answer can already be stale, so the accessors above re-establish it as
     * part of entering rather than trusting this.
     */
    return rlx_rocket_runtime_is_active(_runtimeToken) && rlx_kernel_access_is_valid(&_accessStorage);
}

- (rlx_kernel_layout)layout {
    return _accessStorage.layout;
}

/*
 * Straight to the runtime, not through the published table.
 *
 * Reading `active` and then calling what the struct holds are two moments, and
 * a teardown between them finds the ivar cleared and the call jumping through a
 * null pointer. The runtime entry establishes ownership as part of admitting
 * the call, so there is nothing to observe in between; a call that arrives too
 * late gets ENOTSUP instead of a crash.
 */
- (int)readKernelAtAddress:(uint64_t)address output:(void *)output size:(size_t)size {
    return rlx_rocket_runtime_kernel_read(_runtimeToken, address, output, size);
}

- (int)writeKernelAtAddress:(uint64_t)address input:(const void *)input size:(size_t)size {
    return rlx_rocket_runtime_kernel_write(_runtimeToken, address, input, size);
}

- (nullable RLXKernelInfo *)kernelInfo {
    return _kernelInfo;
}

- (nullable RLXKernelAccessFailure *)buildFailure {
    return _buildFailure;
}

- (nullable RLXKernelOffsetProfile *)offsetProfile {
    return _offsetProfile;
}

- (int)build {
    _buildFailure = nil;
    if (self.active) {
        _buildFailure = rlx_kernel_access_failure(@"precondition",
                                                  EALREADY,
                                                  @"Kernel access was already built.",
                                                  NO,
                                                  ^(RLXEngineDiagnostic *diagnostic) {
                                                      [diagnostic appendKey:@"access" boolValue:YES];
                                                  });
        return EALREADY;
    }

    rlx_exploit_thread_context *context = calloc(1, sizeof(*context));
    if (!context) {
        _buildFailure = rlx_kernel_access_failure(@"worker_allocation",
                                                  ENOMEM,
                                                  @"The Rocket worker context could not be allocated.",
                                                  NO,
                                                  ^(RLXEngineDiagnostic *diagnostic) {
                                                      [diagnostic appendKey:@"worker_context" boolValue:NO];
                                                  });
        return ENOMEM;
    }
    context->owner = self;
    if (semaphore_create(mach_task_self_, &context->completion, SYNC_POLICY_FIFO, 0) != KERN_SUCCESS) {
        free(context);
        _buildFailure = rlx_kernel_access_failure(@"worker_semaphore",
                                                  EIO,
                                                  @"The Rocket completion semaphore could not be created.",
                                                  NO,
                                                  ^(RLXEngineDiagnostic *diagnostic) {
                                                      [diagnostic appendKey:@"completion_semaphore" boolValue:NO];
                                                  });
        return EIO;
    }

    pthread_attr_t attributes;
    int status = pthread_attr_init(&attributes);
    if (status == 0) {
        status = pthread_attr_setdetachstate(&attributes, PTHREAD_CREATE_DETACHED);
        if (status == 0) {
            pthread_t thread;
            status = pthread_create(&thread, &attributes, rlx_run_exploit_on_worker_thread, context);
        }
        pthread_attr_destroy(&attributes);
    }
    if (status != 0) {
        semaphore_destroy(mach_task_self_, context->completion);
        free(context);
        _buildFailure = rlx_kernel_access_failure(@"worker_thread",
                                                  status,
                                                  @"The dedicated Rocket worker thread could not be created.",
                                                  NO,
                                                  ^(RLXEngineDiagnostic *diagnostic) {
                                                      [diagnostic appendKey:@"worker_thread" boolValue:NO];
                                                  });
        return status;
    }

    if (semaphore_wait(context->completion) != KERN_SUCCESS) {
        abort();
    }
    status = context->status;
    rlx_kernel_access candidate = context->access;
    semaphore_destroy(mach_task_self_, context->completion);
    free(context);
    if (status != 0) {
        return status;
    }
    if (!rlx_kernel_access_is_valid(&candidate)) {
        _buildFailure = rlx_kernel_access_failure(@"access_publication",
                                                  EPROTO,
                                                  @"Rocket returned an incomplete kernel access handoff.",
                                                  YES,
                                                  ^(RLXEngineDiagnostic *diagnostic) {
                                                      [diagnostic appendKey:@"access" boolValue:NO];
                                                  });
        return EPROTO;
    }

    _accessStorage = candidate;
    rlx_engine_log(
        RLX_ENGINE_LOG_INFO,
        "RLXKernelAccess",
        "primitive availability phase=kernel_access_commit " "libjailbreak_post_exploitation=true engine_access=true");
    return 0;
}

- (int)buildAccess:(rlx_kernel_access *)access {
    RLXKernelOffsetProfile *offsetProfile = self.offsetProfile;
    if (!offsetProfile && self.kernelcachePath.length == 0) {
        _buildFailure = rlx_kernel_access_failure(@"kernel_layout_source",
                                                  EINVAL,
                                                  @"The run has neither a kernelcache nor a bundled offset profile.",
                                                  NO,
                                                  ^(RLXEngineDiagnostic *diagnostic) {
                                                      [diagnostic appendKey:@"kernelcache" boolValue:NO];
                                                      [diagnostic appendKey:@"offset_table" boolValue:NO];
                                                  });
        return EINVAL;
    }

    if (!kernel_exploit_runtime_is_supported()) {
        _buildFailure = rlx_kernel_access_failure(@"rocket_runtime_preflight",
                                                  ENOTSUP,
                                                  @"Rocket does not support this iOS version.",
                                                  NO,
                                                  ^(RLXEngineDiagnostic *diagnostic) {
                                                      [diagnostic appendKey:@"runtime_supported" boolValue:NO];
                                                  });
        return ENOTSUP;
    }

    /*
     * Claiming the runtime is the first thing this build does, and holding the
     * token is what later makes it this instance's runtime to tear down. A
     * second RLXKernelAccess gets EBUSY here and never receives a token, so it
     * cannot finalize the first one's access on its way out.
     */
    int acquireStatus = rlx_rocket_runtime_acquire(&_runtimeToken);
    if (acquireStatus != 0) {
        _buildFailure = rlx_kernel_access_failure(@"runtime_acquisition",
                                                  acquireStatus,
                                                  acquireStatus == EBUSY
                                                      ? @"Another kernel access already owns the Rocket runtime."
                                                      : @"The Rocket runtime cannot be acquired again.",
                                                  acquireStatus != EBUSY,
                                                  ^(RLXEngineDiagnostic *diagnostic) {
                                                      [diagnostic appendKey:@"runtime_owner" boolValue:NO];
                                                      [diagnostic appendKey:@"runtime_state"
                                                               integerValue:rlx_rocket_runtime_current_state()];
                                                  });
        return acquireStatus;
    }

    /*
     * With a profile there is nothing to stage: Rocket is handed the offsets
     * directly and never opens a kernelcache, so the copy into Documents that
     * exists only to give it a readable path is skipped along with the file.
     */
    NSString *rocketKernelcachePath = nil;
    int status = 0;
    if (offsetProfile) {
        RocketStaticKernelProfile rocketProfile = offsetProfile.rocketProfile;
        rocket_static_profile_publish(&rocketProfile);
    } else {
        rocket_static_profile_publish(NULL);
        NSString *stagingFailureOperation = nil;
        RLXKernelcacheStaging *staging = [[RLXKernelcacheStaging alloc] initWithDataDirectoryURL:_dataDirectoryURL];
        rocketKernelcachePath = staging.rocketKernelcachePath;
        status = [staging stageKernelcacheAtPath:self.kernelcachePath failureOperation:&stagingFailureOperation];
        if (status != 0) {
            _buildFailure = rlx_kernel_access_failure(@"kernelcache_staging",
                                                      status,
                                                      @"The kernelcache could not be staged for Rocket.",
                                                      NO,
                                                      ^(RLXEngineDiagnostic *diagnostic) {
                                                          [diagnostic appendKey:@"operation"
                                                                          value:stagingFailureOperation
                                                                       fallback:@"unknown"];
                                                          [diagnostic appendKey:@"source" value:self.kernelcachePath];
                                                          [diagnostic appendKey:@"target" value:rocketKernelcachePath];
                                                      });
            return status;
        }
    }

    /* M-series may retain a Coruna voucher anchor for post-KRW task lookup. */
    (void)kernel_exploit_prepare_task_anchor();

    status = exploit_init(NULL);
    if (status != 0) {
        _buildFailure = rlx_kernel_access_failure(@"darksword",
                                                  status,
                                                  @"DarkSword did not publish its initial kernel primitives.",
                                                  YES,
                                                  ^(RLXEngineDiagnostic *diagnostic) {
                                                      [diagnostic appendKey:@"exploit_init" boolValue:NO];
                                                  });
        return status;
    }
    rlx_rocket_runtime_enter_darksword(_runtimeToken);
    rlx_engine_log(
        RLX_ENGINE_LOG_INFO,
        "RLXKernelAccess",
        "primitive availability phase=darksword kernel_read=temporary " "kernel_write=temporary physical_read=false physical_write=false " "libjailbreak_post_exploitation=false engine_access=false");

    status = pthread_set_qos_class_self_np(QOS_CLASS_DEFAULT, 0);
    if (status != 0) {
        _buildFailure = rlx_kernel_access_failure(@"worker_qos_restore",
                                                  status,
                                                  @"The Rocket worker QoS could not be restored.",
                                                  YES,
                                                  ^(RLXEngineDiagnostic *diagnostic) {
                                                      [diagnostic appendKey:@"qos" value:@"not_restored"];
                                                  });
        return status;
    }

    status = kernel_exploit_initialize(rocketKernelcachePath.fileSystemRepresentation);
    if (status != 0) {
        _buildFailure = rlx_kernel_access_failure(@"rocket_initialize",
                                                  status,
                                                  @"Rocket could not construct stable kernel access.",
                                                  YES,
                                                  ^(RLXEngineDiagnostic *diagnostic) {
                                                      [diagnostic appendKey:@"stable_access" boolValue:NO];
                                                  });
        return status;
    }
    rlx_rocket_runtime_enter_rocket_published(_runtimeToken);

    if (!kernel_exploit_requires_deferred_exploit_cleanup() || !gPrimitives.kreadbuf || !gPrimitives.kwritebuf
        || !gPrimitives.physreadbuf || !gPrimitives.physwritebuf || !gPrimitives.protectedKwrite32
        || !gPrimitives.kvtophys) {
        _buildFailure = rlx_kernel_access_failure(@"primitive_publication",
                                                  ENOTSUP,
                                                  @"Rocket did not publish the complete kcall-less data provider.",
                                                  YES,
                                                  ^(RLXEngineDiagnostic *diagnostic) {
                                                      [diagnostic
                                                          appendKey:@"direct_access"
                                                          boolValue:kernel_exploit_requires_deferred_exploit_cleanup()];
                                                      [diagnostic appendKey:@"kread"
                                                                  boolValue:gPrimitives.kreadbuf != NULL];
                                                      [diagnostic appendKey:@"kwrite"
                                                                  boolValue:gPrimitives.kwritebuf != NULL];
                                                      [diagnostic appendKey:@"pread"
                                                                  boolValue:gPrimitives.physreadbuf != NULL];
                                                      [diagnostic appendKey:@"pwrite"
                                                                  boolValue:gPrimitives.physwritebuf != NULL];
                                                      [diagnostic appendKey:@"protected_write32"
                                                                  boolValue:gPrimitives.protectedKwrite32 != NULL];
                                                      [diagnostic appendKey:@"kvtophys"
                                                                  boolValue:gPrimitives.kvtophys != NULL];
                                                  });
        return ENOTSUP;
    }
    rlx_rocket_runtime_activate(_runtimeToken, gPrimitives.kreadbuf, gPrimitives.kwritebuf);
    rlx_engine_log(
        RLX_ENGINE_LOG_INFO,
        "RLXKernelAccess",
        "primitive availability phase=rocket_stable kernel_read=true " "kernel_write=true physical_read=true physical_write=true " "protected_write32=true kvtophys=true " "libjailbreak_post_exploitation=true engine_access=false");

    RLXKernelAccessFailure *patchfinderFailure = nil;
    RLXKernelInfo *patchfinderInfo = offsetProfile
        ? [RLXXPFSession analyzeOffsetProfile:offsetProfile liveKernelBase:kernel_base failure:&patchfinderFailure]
        : [RLXXPFSession analyzeKernelcacheAtPath:rocketKernelcachePath resourceBundle:_resourceBundle
                                   liveKernelBase:kernel_base
                                          failure:&patchfinderFailure];
    if (!patchfinderInfo) {
        if (patchfinderFailure) {
            /* The patchfinder does not know the exploit already ran; this
             * build does, and it is the one caller its failures reach. */
            _buildFailure = [patchfinderFailure failureByFoldingIntoKernelAccessBuild];
        } else {
            _buildFailure = rlx_kernel_access_failure(@"xpf_analysis",
                                                      EPROTO,
                                                      @"XPF did not produce usable kernel information.",
                                                      YES,
                                                      ^(RLXEngineDiagnostic *diagnostic) {
                                                          [diagnostic appendKey:@"kernelcache"
                                                                          value:rocketKernelcachePath];
                                                      });
        }
        return EPROTO;
    }

    jbinfo_initialize_boot_constants();
    uint64_t pageSize = get_vm_real_kernel_page_size();
    if (pageSize == 0 || pageSize > UINT32_MAX || kernel_base == 0
        || kernel_slide != kernel_base - gSystemInfo.kernelConstant.staticBase
        || gSystemInfo.kernelConstant.cpuTTEP == 0 || gSystemInfo.kernelConstant.virtBase == 0
        || gSystemInfo.kernelConstant.physBase == 0 || gSystemInfo.kernelConstant.physSize == 0) {
        _buildFailure = rlx_kernel_access_failure(@"boot_constants",
                                                  EPROTO,
                                                  @"libjailbreak could not resolve the live kernel layout.",
                                                  YES,
                                                  ^(RLXEngineDiagnostic *diagnostic) {
                                                      [diagnostic appendKey:@"kernel_base" hex64Value:kernel_base];
                                                      [diagnostic appendKey:@"static_base"
                                                                 hex64Value:gSystemInfo.kernelConstant.staticBase];
                                                      [diagnostic appendKey:@"kernel_slide" hex64Value:kernel_slide];
                                                      [diagnostic appendKey:@"cpu_ttep"
                                                                 hex64Value:gSystemInfo.kernelConstant.cpuTTEP];
                                                      [diagnostic appendKey:@"virt_base"
                                                                 hex64Value:gSystemInfo.kernelConstant.virtBase];
                                                      [diagnostic appendKey:@"phys_base"
                                                                 hex64Value:gSystemInfo.kernelConstant.physBase];
                                                      [diagnostic appendKey:@"phys_size"
                                                                 hex64Value:gSystemInfo.kernelConstant.physSize];
                                                  });
        return EPROTO;
    }

    uint64_t kernelPhysical = gPrimitives.kvtophys(kernel_base);
    uint32_t kernelMagic = 0;
    status = kernelPhysical ? gPrimitives.physreadbuf(kernelPhysical, &kernelMagic, sizeof(kernelMagic)) : EFAULT;
    if (status != 0 || kernelMagic != MH_MAGIC_64) {
        _buildFailure = rlx_kernel_access_failure(@"kernel_translation",
                                                  status != 0 ? status : EPROTO,
                                                  @"Rocket's kernel-to-physical translation failed validation.",
                                                  YES,
                                                  ^(RLXEngineDiagnostic *diagnostic) {
                                                      [diagnostic appendKey:@"kernel_base" hex64Value:kernel_base];
                                                      [diagnostic appendKey:@"kernel_physical"
                                                                 hex64Value:kernelPhysical];
                                                      [diagnostic appendKey:@"kernel_magic" hexValue:kernelMagic];
                                                  });
        return status != 0 ? status : EPROTO;
    }

    access->version = RLX_KERNEL_ACCESS_VERSION;
    access->size = sizeof(*access);
    access->token = _runtimeToken;
    access->layout = (rlx_kernel_layout){
        .version = RLX_KERNEL_LAYOUT_VERSION,
        .size = sizeof(access->layout),
        .page_size = (uint32_t)pageSize,
        .kernel_base = kernel_base,
        .kernel_slide = kernel_slide,
        .cpu_ttep = gSystemInfo.kernelConstant.cpuTTEP,
        .virtual_base = gSystemInfo.kernelConstant.virtBase,
        .physical_base = gSystemInfo.kernelConstant.physBase,
        .physical_size = gSystemInfo.kernelConstant.physSize,
    };
    access->kernel_read = rlx_rocket_runtime_kernel_read;
    access->kernel_write = rlx_rocket_runtime_kernel_write;
    access->physical_read = rlx_rocket_runtime_physical_read;
    access->physical_write = rlx_rocket_runtime_physical_write;
    access->finalize = rlx_rocket_runtime_finalize;
    _kernelInfo = [patchfinderInfo infoByAddingRuntimeLayout:access->layout];
    if (!_kernelInfo) {
        memset(access, 0, sizeof(*access));
        _buildFailure = rlx_kernel_access_failure(@"runtime_layout",
                                                  EPROTO,
                                                  @"The resolved runtime layout failed validation.",
                                                  YES,
                                                  ^(RLXEngineDiagnostic *diagnostic) {
                                                      [diagnostic appendKey:@"runtime_layout" boolValue:NO];
                                                  });
        return EPROTO;
    }
    return 0;
}

- (int)finalizeAccess {
    /*
     * Only this instance's own acquisition. An RLXKernelAccess whose build lost
     * the race for the runtime holds no token, so it reports EPERM here instead
     * of tearing down the access another instance is still using.
     */
    int status = rlx_rocket_runtime_finalize(_runtimeToken);
    if (status == 0 || status == EALREADY) {
        /*
         * The claim is spent. Stages 12 and 98 keep their reference on failure
         * so the queue can finalize a second time, and dropping the token here
         * is what makes that second call report "nothing outstanding" rather
         * than present a claim the runtime has already moved past. A latched
         * Dirty keeps its token, so repeating the call there still reports the
         * latched status.
         */
        _runtimeToken = 0;
    }
    if (!rlx_rocket_runtime_is_active(_runtimeToken)) {
        /*
         * The callbacks go once the gate is shut, whether teardown succeeded or
         * latched Dirty — they name a runtime that no longer answers. The
         * layout stays, because it is a value snapshot and the header promises
         * it outlives finalization.
         */
        rlx_kernel_layout layout = _accessStorage.layout;
        memset(&_accessStorage, 0, sizeof(_accessStorage));
        _accessStorage.layout = layout;
        _kernelInfo = nil;
        /*
         * The published profile named this run's kernel. It is process-global,
         * so leaving it behind would let a later build start from it without
         * having chosen it.
         */
        rocket_static_profile_publish(NULL);
    }
    return status;
}

@end
