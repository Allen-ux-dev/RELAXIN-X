//
//  RLXBaseBinTrustTask.m
//  RelaxinEngine
//

#import "RLXBaseBinTrustTask.h"
#import "RLXTrustCacheTransaction.h"

#import "../../Engine/RLXEngine.h"
#import "../../Diagnostic/RLXEngineDiagnostic.h"
#import "../../Engine/RLXEngineError.h"
#import "../../Log/RLXEngineLog.h"
#import "../../Engine/RLXEngineRunContext.h"
#import "../../KernelAccess/RLXKernelAccess.h"
#import "../../KernelAccess/Analysis/RLXKernelInfo.h"

#include <errno.h>
#include <string.h>

#include <libjailbreak/info.h>
#include <libjailbreak/roothider/common.h>
#include <libjailbreak/trustcache.h>
#include <libjailbreak/trustcache_nokcall.h>

static const char *const RLXBaseBinTrustLogCategory = "BaseBinTrust";

static NSError *rlx_basebin_trust_error(NSString *phase, int status, NSString *detail) {
    NSString *statusDescription = status > 0 ? @(strerror(status)) : @"unknown error";
    NSString *logMessage = [NSString
        stringWithFormat:@"failed phase=%@ status=%d (%@)%@",
                         phase,
                         status,
                         statusDescription,
                         detail.length ? [NSString stringWithFormat:@" detail={%@}", detail] : @""];
    rlx_engine_log(RLX_ENGINE_LOG_ERROR, RLXBaseBinTrustLogCategory, logMessage.UTF8String);
    RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnostic];
    [diagnostic appendPhase:phase];
    [diagnostic appendStatus:status];
    [diagnostic appendKey:@"status_description" value:statusDescription];
    [diagnostic appendRenderedDiagnostic:detail ?: @""];
    return [RLXEngineError
             errorWithCode:RLXEngineErrorCodeBaseBinTrustFailed
               description:@"BaseBin could not be published to the trust cache."
             failureReason:[NSString
                               stringWithFormat:@"%@ failed with status %d (%@).", phase, status, statusDescription]
        recoverySuggestion:@"Reboot the device before retrying the jailbreak."
                diagnostic:diagnostic];
}


typedef struct {
    __unsafe_unretained NSString *baseBinPath;
    __unsafe_unretained NSArray<NSString *> *artifacts;
    __unsafe_unretained NSString *failedArtifact;
    cdhash_t cdhashes[3];
} RLXBaseBinTrustTransactionContext;

static int rlx_basebin_trust_inspect(void *opaque) {
    RLXBaseBinTrustTransactionContext *context = opaque;
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:context->baseBinPath isDirectory:&isDirectory] || !isDirectory) {
        return ENOENT;
    }
    return 0;
}

static int rlx_basebin_trust_prepare_candidate(void *opaque) {
    RLXBaseBinTrustTransactionContext *context = opaque;
    for (NSString *artifact in context->artifacts) {
        NSString *path = [context->baseBinPath stringByAppendingPathComponent:artifact];
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
            context->failedArtifact = artifact;
            return ENOENT;
        }
    }
    return 0;
}

static int rlx_basebin_trust_validate_candidate(void *opaque) {
    RLXBaseBinTrustTransactionContext *context = opaque;
    for (NSString *artifact in context->artifacts) {
        NSString *path = [context->baseBinPath stringByAppendingPathComponent:artifact];
        BOOL isDirectory = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) {
            context->failedArtifact = artifact;
            return ENOEXEC;
        }
    }
    return 0;
}

static int rlx_basebin_trust_publish(void *opaque) {
    RLXBaseBinTrustTransactionContext *context = opaque;
    return randomizeAndBootstrapBasebinTrustcache(context->baseBinPath.fileSystemRepresentation);
}

static int rlx_basebin_trust_read_back(void *opaque) {
    RLXBaseBinTrustTransactionContext *context = opaque;
    NSUInteger index = 0;
    for (NSString *artifact in context->artifacts) {
        if (index >= 3) {
            return EOVERFLOW;
        }
        NSString *path = [context->baseBinPath stringByAppendingPathComponent:artifact];
        if (ensure_randomized_cdhash(path.fileSystemRepresentation, context->cdhashes[index]) != 0) {
            context->failedArtifact = artifact;
            return ENOEXEC;
        }
        index += 1;
    }
    return 0;
}

static int rlx_basebin_trust_verify_published(void *opaque) {
    RLXBaseBinTrustTransactionContext *context = opaque;
    NSUInteger index = 0;
    for (NSString *artifact in context->artifacts) {
        bool found = false;
        int status = trustcache_query_cdhash(context->cdhashes[index], &found);
        if (status != 0 || !found) {
            context->failedArtifact = artifact;
            return status ?: ENOENT;
        }
        index += 1;
    }
    return 0;
}

static int rlx_basebin_trust_commit(void *opaque) {
    (void)opaque;
    return 0;
}

@implementation RLXBaseBinTrustTask

- (instancetype)initWithContext:(RLXEngineRunContext *)context {
    return [super initWithStage:RLXEngineStageBaseBinTrust context:context];
}

- (nullable NSError *)execute {
    NSString *beginMessage = [NSString
        stringWithFormat:@"begin kernel_access_active=%@ " "bootstrap_identity_active=%@ kernel_el=%llu",
                         self.context.kernelAccess.isActive ? @"true" : @"false",
                         self.context.kernelAccess.isBootstrapIdentityActive ? @"true" : @"false",
                         self.context.kernelInfo.kernelExceptionLevel];
    rlx_engine_log(RLX_ENGINE_LOG_VERBOSE, RLXBaseBinTrustLogCategory, beginMessage.UTF8String);

    if (!self.context.kernelAccess.isActive || !self.context.kernelAccess.isBootstrapIdentityActive) {
        return rlx_basebin_trust_error(@"precondition",
                                       ENXIO,
                                       [NSString
                                           stringWithFormat:@"kernel_access_active=%@\n" "bootstrap_identity_active=%@",
                                                            self.context.kernelAccess.isActive ? @"true" : @"false",
                                                            self.context.kernelAccess.isBootstrapIdentityActive
                                                                ? @"true"
                                                                : @"false"]);
    }
    if (!gSystemInfo.jailbreakInfo.rootPath || !gSystemInfo.jailbreakInfo.rootPath[0]
        || !gSystemInfo.jailbreakInfo.jbrand) {
        return rlx_basebin_trust_error(@"precondition",
                                       EINVAL,
                                       [NSString stringWithFormat:@"root_path=%s\njbrand=0x%llx",
                                                                  gSystemInfo.jailbreakInfo.rootPath ?: "(null)",
                                                                  gSystemInfo.jailbreakInfo.jbrand]);
    }

    NSString *rootPath = @(gSystemInfo.jailbreakInfo.rootPath);
    NSString *baseBinPath = [rootPath stringByAppendingPathComponent:@"basebin"];
    NSArray<NSString *> *verificationArtifacts = @[
        @"jbctl",
        @"opainject",
        @"launchdhook.dylib",
    ];

    RLXBaseBinTrustTransactionContext transactionContext = {
        .baseBinPath = baseBinPath,
        .artifacts = verificationArtifacts,
        .failedArtifact = nil,
    };
    RLXTrustCacheTransactionCallbacks callbacks = {
        .context = &transactionContext,
        .inspect = rlx_basebin_trust_inspect,
        .prepareCandidate = rlx_basebin_trust_prepare_candidate,
        .validateCandidate = rlx_basebin_trust_validate_candidate,
        .publish = rlx_basebin_trust_publish,
        .readBack = rlx_basebin_trust_read_back,
        .verifyPublished = rlx_basebin_trust_verify_published,
        .commit = rlx_basebin_trust_commit,
        // The public snapshot has no proven safe inverse for this publication.
        // Stop on failed verification instead of pretending rollback succeeded.
        .rollbackIfSupported = NULL,
    };

    rlx_engine_log(RLX_ENGINE_LOG_INFO,
                   RLXBaseBinTrustLogCategory,
                   "starting BaseBin trust cache publication transaction");
    RLXTrustCacheTransactionResult transactionResult = RLXRunTrustCacheTransaction(callbacks);
    if (transactionResult.status != 0) {
        NSString *phase = transactionResult.failedPhase ? @(transactionResult.failedPhase) : @"transaction";
        NSString *detail = [NSString
            stringWithFormat:@"basebin=%@\nartifact=%@\npublication_attempted=%@\nrollback_supported=false",
                             baseBinPath,
                             transactionContext.failedArtifact ?: @"none",
                             transactionResult.publicationAttempted ? @"true" : @"false"];
        return rlx_basebin_trust_error(phase, transactionResult.status, detail);
    }

    rlx_engine_log(RLX_ENGINE_LOG_INFO,
                   RLXBaseBinTrustLogCategory,
                   "BaseBin trust cache transaction committed after readback verification");
    return nil;
}
@end
