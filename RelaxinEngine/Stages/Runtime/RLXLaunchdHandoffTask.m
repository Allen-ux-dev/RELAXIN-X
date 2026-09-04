//
//  RLXLaunchdHandoffTask.m
//  RelaxinEngine
//

#import "RLXLaunchdHandoffTask.h"

#import "../../Engine/RLXEngine.h"
#import "../../Diagnostic/RLXEngineDiagnostic.h"
#import "../../Engine/RLXEngineError.h"
#import "../../Log/RLXEngineLog.h"
#import "../../Engine/RLXEngineRunContext.h"
#import "../../KernelAccess/RLXKernelAccess.h"
#import "../../KernelAccess/Analysis/RLXKernelInfo.h"

#include <errno.h>
#include <pthread.h>
#include <spawn.h>
#include <stdatomic.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include <mach/mach.h>
#include <xpc/xpc.h>

#include <libjailbreak/info.h>
#include <libjailbreak/jbserver_boomerang.h>
#include <libjailbreak/primitives.h>
#include <libjailbreak/roothider/common.h>
#include <libjailbreak/translation.h>
#include <libjailbreak/util.h>

extern int posix_spawnattr_set_registered_ports_np(posix_spawnattr_t *__restrict attr,
                                                   mach_port_t portarray[],
                                                   uint32_t count);

static const char *const RLXLaunchdHandoffLogCategory = "LaunchdHandoff";

typedef struct {
    mach_port_t serverPort;
    dispatch_semaphore_t done;
    atomic_bool stop;
} RLXBoomerangServerContext;

static NSError *rlx_launchd_handoff_error(NSString *phase, int status, NSString *detail) {
    int displayStatus = status != 0 ? status : EIO;
    NSString *statusDescription = displayStatus > 0 ? @(strerror(displayStatus)) : @"unknown error";
    RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnostic];
    [diagnostic appendPhase:phase];
    [diagnostic appendStatus:status];
    [diagnostic appendKey:@"status_description" value:statusDescription];
    [diagnostic appendRenderedDiagnostic:detail ?: @""];

    NSString *message = [NSString
        stringWithFormat:@"failed phase=%@ status=%d (%@)%@",
                         phase,
                         status,
                         statusDescription,
                         detail.length ? [NSString stringWithFormat:@" detail={%@}", detail] : @""];
    rlx_engine_log(RLX_ENGINE_LOG_ERROR, RLXLaunchdHandoffLogCategory, message.UTF8String);
    return [RLXEngineError
             errorWithCode:RLXEngineErrorCodeLaunchdHandoffFailed
               description:@"The launchd primitive handoff could not be completed."
             failureReason:[NSString
                               stringWithFormat:@"%@ failed with status %d (%@).", phase, status, statusDescription]
        recoverySuggestion:@"Reboot the device before retrying the jailbreak."
                diagnostic:diagnostic];
}

static void *rlx_boomerang_server(void *opaqueContext) {
    RLXBoomerangServerContext *context = opaqueContext;
    while (!atomic_load_explicit(&context->stop, memory_order_acquire)) {
        xpc_object_t message = NULL;
        int receiveStatus = xpc_pipe_receive(context->serverPort, &message);
        if (receiveStatus != 0) {
            continue;
        }

        int action = jbserver_received_boomerang_xpc_message(&gBoomerangServer, message);
        if (action == JBS_BOOMERANG_DONE) {
            dispatch_semaphore_signal(context->done);
            break;
        }
    }
    return NULL;
}

static void rlx_stop_boomerang_server(RLXBoomerangServerContext *context, pthread_t thread, bool threadStarted) {
    atomic_store_explicit(&context->stop, true, memory_order_release);
    if (context->serverPort != MACH_PORT_NULL) {
        mach_port_mod_refs(mach_task_self(), context->serverPort, MACH_PORT_RIGHT_RECEIVE, -1);
        mach_port_deallocate(mach_task_self(), context->serverPort);
        context->serverPort = MACH_PORT_NULL;
    }
    if (threadStarted) {
        pthread_join(thread, NULL);
    }
}

static int rlx_wait_for_process(pid_t pid, int *exitStatusOut) {
    int waitStatus = 0;
    while (waitpid(pid, &waitStatus, 0) == -1) {
        if (errno == EINTR)
            continue;
        return errno ?: ECHILD;
    }

    if (WIFEXITED(waitStatus)) {
        *exitStatusOut = WEXITSTATUS(waitStatus);
    } else if (WIFSIGNALED(waitStatus)) {
        *exitStatusOut = 128 + WTERMSIG(waitStatus);
    } else {
        *exitStatusOut = ECHILD;
    }
    return 0;
}

@implementation RLXLaunchdHandoffTask

- (instancetype)initWithContext:(RLXEngineRunContext *)context {
    return [super initWithStage:RLXEngineStageLaunchdHandoff context:context];
}

- (nullable NSError *)execute {
    RLXKernelAccess *kernelAccess = self.context.kernelAccess;
    if (!kernelAccess.isActive || !kernelAccess.isBootstrapIdentityActive) {
        return rlx_launchd_handoff_error(@"precondition",
                                         ENXIO,
                                         [NSString stringWithFormat:
                                                       @"kernel_access_active=%@\n" "bootstrap_identity_active=%@",
                                                       kernelAccess.isActive ? @"true" : @"false",
                                                       kernelAccess.isBootstrapIdentityActive ? @"true" : @"false"]);
    }
    if (!gSystemInfo.jailbreakInfo.rootPath || !gSystemInfo.jailbreakInfo.rootPath[0]
        || !gSystemInfo.jailbreakInfo.jbrand || !gPrimitives.kreadbuf || !gPrimitives.kwritebuf
        || !gPrimitives.physreadbuf || !gPrimitives.physwritebuf || !gPrimitives.protectedKwrite32
        || !gPrimitives.kvtophys) {
        return rlx_launchd_handoff_error(
            @"precondition",
            ENOTSUP,
            [NSString
                stringWithFormat:
                    @"protection=%s\nkernel_el=%llu\nroot_path=%s\njbrand=0x%llx\n" "kread=%d\nkwrite=%d\nphysread=%d\nphyswrite=%d\n" "protected_kwrite32=%d\nkvtophys=%d",
                    self.context.kernelInfo.isSPTMKernel ? "sptm" : "ppl",
                    self.context.kernelInfo.kernelExceptionLevel,
                    gSystemInfo.jailbreakInfo.rootPath ?: "(null)",
                    gSystemInfo.jailbreakInfo.jbrand,
                    gPrimitives.kreadbuf != NULL,
                    gPrimitives.kwritebuf != NULL,
                    gPrimitives.physreadbuf != NULL,
                    gPrimitives.physwritebuf != NULL,
                    gPrimitives.protectedKwrite32 != NULL,
                    gPrimitives.kvtophys != NULL]);
    }

    NSString *appJIT = self.context.manifest[RLXEngineManifestAppJITEnabledKey];
    NSString *jetsamMultiplier = self.context.manifest[RLXEngineManifestJetsamMultiplierKey];
    gSystemInfo.jailbreakSettings.markAppsAsDebugged = appJIT.length == 0 || appJIT.boolValue;
    gSystemInfo.jailbreakSettings.jetsamMultiplier = jetsamMultiplier.length == 0 ? 0 : jetsamMultiplier.doubleValue;
    NSString *settingsMessage = [NSString
        stringWithFormat:@"publishing runtime settings app_jit=%@ jetsam_multiplier=%g",
                         gSystemInfo.jailbreakSettings.markAppsAsDebugged ? @"enabled" : @"disabled",
                         gSystemInfo.jailbreakSettings.jetsamMultiplier];
    rlx_engine_log(RLX_ENGINE_LOG_INFO, RLXLaunchdHandoffLogCategory, settingsMessage.UTF8String);

    NSString *baseBinPath = [@(gSystemInfo.jailbreakInfo.rootPath) stringByAppendingPathComponent:@"basebin"];
    NSString *jbctlPath = [baseBinPath stringByAppendingPathComponent:@"jbctl"];
    NSString *opainjectPath = [baseBinPath stringByAppendingPathComponent:@"opainject"];
    NSString *launchdHookPath = [baseBinPath stringByAppendingPathComponent:@"launchdhook.dylib"];
    NSFileManager *fileManager = NSFileManager.defaultManager;
    if (![fileManager isExecutableFileAtPath:jbctlPath] || ![fileManager isExecutableFileAtPath:opainjectPath]
        || ![fileManager fileExistsAtPath:launchdHookPath]) {
        return rlx_launchd_handoff_error(@"locate_basebin",
                                         ENOENT,
                                         [NSString stringWithFormat:@"jbctl=%@\nopainject=%@\nlaunchdhook=%@",
                                                                    jbctlPath,
                                                                    opainjectPath,
                                                                    launchdHookPath]);
    }

    rlx_engine_log(RLX_ENGINE_LOG_INFO, RLXLaunchdHandoffLogCategory, "initializing translation context");
    if (!libjailbreak_translation_init()) {
        return rlx_launchd_handoff_error(@"translation", ENOTSUP, @"ptov context was not resolved");
    }

    RLXBoomerangServerContext serverContext = {
        .serverPort = MACH_PORT_NULL,
        .done = dispatch_semaphore_create(0),
    };
    atomic_init(&serverContext.stop, false);
    kern_return_t kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &serverContext.serverPort);
    if (kr != KERN_SUCCESS) {
        return rlx_launchd_handoff_error(@"boomerang_port_allocate",
                                         kr,
                                         [NSString stringWithFormat:@"mach_status=%d", kr]);
    }
    kr = mach_port_insert_right(mach_task_self(),
                                serverContext.serverPort,
                                serverContext.serverPort,
                                MACH_MSG_TYPE_MAKE_SEND);
    if (kr != KERN_SUCCESS) {
        rlx_stop_boomerang_server(&serverContext, (pthread_t){0}, false);
        return rlx_launchd_handoff_error(@"boomerang_port_insert",
                                         kr,
                                         [NSString stringWithFormat:@"mach_status=%d", kr]);
    }

    pthread_t serverThread;
    bool serverThreadStarted = false;
    int status = pthread_create(&serverThread, NULL, rlx_boomerang_server, &serverContext);
    if (status != 0) {
        rlx_stop_boomerang_server(&serverContext, (pthread_t){0}, false);
        return rlx_launchd_handoff_error(@"boomerang_thread", status, @"pthread_create failed");
    }
    serverThreadStarted = true;

    posix_spawnattr_t spawnAttributes = NULL;
    status = posix_spawnattr_init(&spawnAttributes);
    if (status == 0) {
        mach_port_t registeredPorts[] = {
            MACH_PORT_NULL,
            MACH_PORT_NULL,
            serverContext.serverPort,
        };
        status = posix_spawnattr_set_registered_ports_np(&spawnAttributes, registeredPorts, 3);
    }
    if (status != 0) {
        if (spawnAttributes) {
            posix_spawnattr_destroy(&spawnAttributes);
        }
        rlx_stop_boomerang_server(&serverContext, serverThread, serverThreadStarted);
        return rlx_launchd_handoff_error(@"stash_port_attributes", status, @"posix spawn attributes");
    }

    rlx_engine_log(RLX_ENGINE_LOG_INFO, RLXLaunchdHandoffLogCategory, "stashing boomerang server port in launchd");
    pid_t jbctlPid = 0;
    const char *jbctl = jbctlPath.fileSystemRepresentation;
    char *const jbctlArguments[] = {
        (char *)jbctl,
        "internal",
        "launchd_stash_port",
        NULL,
    };
    status = posix_spawn(&jbctlPid, jbctl, NULL, &spawnAttributes, jbctlArguments, NULL);
    posix_spawnattr_destroy(&spawnAttributes);
    if (status != 0) {
        rlx_stop_boomerang_server(&serverContext, serverThread, serverThreadStarted);
        return rlx_launchd_handoff_error(@"stash_port_spawn",
                                         status,
                                         [NSString stringWithFormat:@"jbctl=%@", jbctlPath]);
    }

    int jbctlExitStatus = 0;
    status = rlx_wait_for_process(jbctlPid, &jbctlExitStatus);
    if (status != 0 || jbctlExitStatus != 0) {
        rlx_stop_boomerang_server(&serverContext, serverThread, serverThreadStarted);
        return rlx_launchd_handoff_error(@"stash_port",
                                         status ?: jbctlExitStatus,
                                         [NSString
                                             stringWithFormat:@"jbctl=%@\nexit_status=%d", jbctlPath, jbctlExitStatus]);
    }

    rlx_engine_log(RLX_ENGINE_LOG_INFO, RLXLaunchdHandoffLogCategory, "injecting launchdhook into PID 1");
    exec_set_patch(false);
    status = exec_cmd(opainjectPath.fileSystemRepresentation, "1", launchdHookPath.fileSystemRepresentation, NULL);
    if (status != 0) {
        rlx_stop_boomerang_server(&serverContext, serverThread, serverThreadStarted);
        return rlx_launchd_handoff_error(@"opainject",
                                         status,
                                         [NSString stringWithFormat:@"opainject=%@\nlaunchdhook=%@",
                                                                    opainjectPath,
                                                                    launchdHookPath]);
    }

    rlx_engine_log(RLX_ENGINE_LOG_INFO, RLXLaunchdHandoffLogCategory, "waiting for launchd boomerang completion");
    dispatch_semaphore_wait(serverContext.done, DISPATCH_TIME_FOREVER);
    rlx_stop_boomerang_server(&serverContext, serverThread, serverThreadStarted);
    rlx_engine_log(RLX_ENGINE_LOG_INFO, RLXLaunchdHandoffLogCategory, "launchd primitive handoff completed");
    return nil;
}

@end
