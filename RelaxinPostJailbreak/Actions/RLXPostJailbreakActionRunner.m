#import "RLXPostJailbreakActionRunner.h"

#import "../Controller/RLXPostJailbreakLog.h"

#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <TargetConditionals.h>
#include <unistd.h>

#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR
#include <libjailbreak/info.h>
#include <libjailbreak/jbclient_xpc.h>
#include <libjailbreak/util.h>
#endif

NSString *_Nullable RLXPostJailbreakActionName(RLXPostJailbreakAction action) {
    switch (action) {
        case RLXPostJailbreakActionRestartSpringBoard:
            return @"Restart SpringBoard";
        case RLXPostJailbreakActionRestartUserspace:
            return @"Restart Userspace";
        case RLXPostJailbreakActionRefreshJailbreakApps:
            return @"Refresh Jailbreak Apps";
        case RLXPostJailbreakActionResetMobilePassword:
            return @"Reset Mobile Password";
        case RLXPostJailbreakActionRemoveJailbreak:
            return @"Remove Jailbreak";
        case RLXPostJailbreakActionSetCompatibilityProfile:
            return @"Update Compatibility Profile";
    }
    return nil;
}

NSString *_Nullable RLXPostJailbreakActionIdentifier(RLXPostJailbreakAction action) {
    switch (action) {
        case RLXPostJailbreakActionRestartSpringBoard:
            return @"restart_springboard";
        case RLXPostJailbreakActionRestartUserspace:
            return @"restart_userspace";
        case RLXPostJailbreakActionRefreshJailbreakApps:
            return @"refresh_jailbreak_apps";
        case RLXPostJailbreakActionResetMobilePassword:
            return @"reset_mobile_password";
        case RLXPostJailbreakActionRemoveJailbreak:
            return @"remove_jailbreak";
        case RLXPostJailbreakActionSetCompatibilityProfile:
            return @"set_compatibility_profile";
    }
    return nil;
}

dispatch_queue_t RLXPostJailbreakActionQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_queue_attr_t
            attributes = dispatch_queue_attr_make_with_autorelease_frequency(DISPATCH_QUEUE_SERIAL,
                                                                             DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM);
        queue = dispatch_queue_create("com.aapl.relaxin.post-jailbreak.actions", attributes);
    });
    return queue;
}

static NSString *rlx_post_jailbreak_diagnostic(RLXPostJailbreakAction action,
                                               NSString *phase,
                                               NSNumber *_Nullable status) {
    NSString *identifier = RLXPostJailbreakActionIdentifier(action) ?: @"unknown";
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithArray:@[
        [@"action=" stringByAppendingString:identifier],
        [@"phase=" stringByAppendingString:phase],
    ]];
    if (status) {
        [lines addObject:[NSString stringWithFormat:@"status=%d", status.intValue]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

NSError *RLXPostJailbreakInvalidActionError(void) {
    return [NSError errorWithDomain:RLXPostJailbreakErrorDomain code:EINVAL userInfo:@{
        NSLocalizedDescriptionKey : @"The requested post-jailbreak action is invalid.",
        RLXPostJailbreakDiagnosticKey : @"action=unknown\nphase=action_validation\nstatus=22",
    }];
}

NSError *RLXPostJailbreakUnavailableActionError(RLXPostJailbreakAction action, NSString *reason) {
    NSString *name = RLXPostJailbreakActionName(action) ?: @"The requested action";
    return [NSError errorWithDomain:RLXPostJailbreakErrorDomain code:ENXIO userInfo:@{
        NSLocalizedDescriptionKey : [NSString stringWithFormat:@"%@ is unavailable.", name],
        NSLocalizedFailureReasonErrorKey : reason,
        NSLocalizedRecoverySuggestionErrorKey : @"Activate the RootHide jailbreak runtime and try again.",
        RLXPostJailbreakDiagnosticKey : rlx_post_jailbreak_diagnostic(action, @"runtime_preflight", @(ENXIO)),
    }];
}

NSError *RLXPostJailbreakActionExecutionError(RLXPostJailbreakAction action,
                                              NSString *phase,
                                              int status,
                                              NSError *_Nullable underlyingError) {
    int errorCode = status > 0 && status <= ELAST ? status : EIO;
    NSString *statusDescription = [NSString stringWithUTF8String:strerror(errorCode)] ?: @"Unknown error";
    NSString *name = RLXPostJailbreakActionName(action) ?: @"The requested action";
    NSString *failureReason = underlyingError.localizedDescription
        ?: [NSString
               stringWithFormat:@"The operation failed during %@ with status %d: %@", phase, status, statusDescription];
    NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo = [@{
        NSLocalizedDescriptionKey : [NSString stringWithFormat:@"%@ failed.", name],
        NSLocalizedFailureReasonErrorKey : failureReason,
        NSLocalizedRecoverySuggestionErrorKey : @"Verify the jailbreak runtime is active, then try again.",
        RLXPostJailbreakDiagnosticKey : rlx_post_jailbreak_diagnostic(action, phase, @(status)),
    } mutableCopy];
    if (underlyingError) {
        userInfo[NSUnderlyingErrorKey] = underlyingError;
    }
    return [NSError errorWithDomain:RLXPostJailbreakErrorDomain code:errorCode userInfo:userInfo];
}

void RLXPostJailbreakCompleteAction(NSError *_Nullable error, RLXPostJailbreakCompletionHandler completion) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) {
            completion(error);
        }
    });
}

void RLXPostJailbreakLogActionResult(RLXPostJailbreakAction action, NSError *_Nullable error) {
    NSString *identifier = RLXPostJailbreakActionIdentifier(action) ?: @"unknown";
    if (error) {
        NSString *diagnostic = error.userInfo[RLXPostJailbreakDiagnosticKey] ?: @"";
        NSString *message = [NSString stringWithFormat:@"action=%@ failed error=%@%@%@",
                                                       identifier,
                                                       error.localizedDescription,
                                                       diagnostic.length ? @"\n" : @"",
                                                       diagnostic];
        rlx_post_jailbreak_log(RLX_POST_JAILBREAK_LOG_ERROR, "RLXPostJailbreakAction", message.UTF8String);
        return;
    }

    NSString *message = [NSString stringWithFormat:@"action=%@ dispatched", identifier];
    rlx_post_jailbreak_log(RLX_POST_JAILBREAK_LOG_INFO, "RLXPostJailbreakAction", message.UTF8String);
}

void RLXPostJailbreakPublishActionOutput(NSString *message, RLXPostJailbreakOutputHandler outputHandler) {
    if (!outputHandler) {
        return;
    }
    if (NSThread.isMainThread) {
        outputHandler(message);
        return;
    }
    dispatch_sync(dispatch_get_main_queue(), ^{
        outputHandler(message);
    });
}

#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR

void RLXPostJailbreakSetFailurePhase(NSString *_Nullable __strong *_Nullable failurePhase, NSString *phase) {
    if (failurePhase && !*failurePhase) {
        *failurePhase = phase;
    }
}

int RLXPostJailbreakSpawnStatus(int status) {
    return status == -1 ? (errno ?: EIO) : status;
}

int RLXPostJailbreakWaitStatus(int status) {
    if (status == -1) {
        return errno ?: EIO;
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : EIO;
}

BOOL RLXPostJailbreakInstalledThroughTrollStore(void) {
    static BOOL installedThroughTrollStore;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *marker = [[NSBundle.mainBundle.bundlePath stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:@"_TrollStore"];
        installedThroughTrollStore = [NSFileManager.defaultManager fileExistsAtPath:marker];
    });
    return installedThroughTrollStore;
}

int RLXPostJailbreakLoadRoot(NSString *_Nullable __strong *_Nullable failurePhase) {
    const char *rootPath = jbclient_get_jbroot();
    if (!rootPath || !rootPath[0]) {
        RLXPostJailbreakSetFailurePhase(failurePhase, @"jailbreak_root");
        return ENOENT;
    }
    if (jbinfo(rootPath) && strcmp(jbinfo(rootPath), rootPath) == 0) {
        return 0;
    }

    char *rootPathCopy = strdup(rootPath);
    if (!rootPathCopy) {
        RLXPostJailbreakSetFailurePhase(failurePhase, @"jailbreak_root");
        return ENOMEM;
    }
    gSystemInfo.jailbreakInfo.rootPath = rootPathCopy;
    return 0;
}

int RLXPostJailbreakRunUnsandboxed(RLXPostJailbreakOperation operation,
                                   NSString *_Nullable __strong *_Nullable failurePhase) {
    if (RLXPostJailbreakInstalledThroughTrollStore() || !jbclient_roothide_jailbroken()) {
        return operation();
    }

    uint64_t originalLabel = 0;
    int enterStatus = jbclient_root_set_mac_label(1, UINT64_MAX, &originalLabel);
    if (enterStatus != 0) {
        RLXPostJailbreakSetFailurePhase(failurePhase, @"unsandbox_enter");
    }

    int operationStatus = operation();
    int restoreStatus = jbclient_root_set_mac_label(1, originalLabel, NULL);
    if (restoreStatus != 0 && enterStatus == 0 && operationStatus == 0) {
        RLXPostJailbreakSetFailurePhase(failurePhase, @"unsandbox_restore");
    }

    if (enterStatus != 0) {
        return enterStatus;
    }
    if (operationStatus != 0) {
        return operationStatus;
    }
    return restoreStatus;
}

int RLXPostJailbreakRunAsEffectiveRoot(RLXPostJailbreakOperation operation,
                                       NSString *_Nullable __strong *_Nullable failurePhase) {
    uid_t originalUser = geteuid();
    gid_t originalGroup = getegid();
    if (originalUser == 0 && originalGroup == 0) {
        return operation();
    }

    if (originalUser != 0 && seteuid(0) != 0) {
        RLXPostJailbreakSetFailurePhase(failurePhase, @"root_enter_user");
        return errno ?: EPERM;
    }
    if (originalGroup != 0 && setegid(0) != 0) {
        int status = errno ?: EPERM;
        RLXPostJailbreakSetFailurePhase(failurePhase, @"root_enter_group");
        if (originalUser != 0) {
            (void)seteuid(originalUser);
        }
        return status;
    }

    int operationStatus = operation();
    int groupRestoreStatus = 0;
    int userRestoreStatus = 0;
    if (originalGroup != 0 && setegid(originalGroup) != 0) {
        groupRestoreStatus = errno ?: EPERM;
    }
    if (originalUser != 0 && seteuid(originalUser) != 0) {
        userRestoreStatus = errno ?: EPERM;
    }

    if (operationStatus != 0) {
        return operationStatus;
    }
    if (groupRestoreStatus != 0) {
        RLXPostJailbreakSetFailurePhase(failurePhase, @"root_restore_group");
        return groupRestoreStatus;
    }
    if (userRestoreStatus != 0) {
        RLXPostJailbreakSetFailurePhase(failurePhase, @"root_restore_user");
        return userRestoreStatus;
    }
    return 0;
}

#endif /* TARGET_OS_IOS && !TARGET_OS_SIMULATOR */
