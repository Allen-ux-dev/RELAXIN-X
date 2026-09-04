//
//  RLXActionRunner.m
//  RelaxinEngine
//

#import "RLXActionRunner.h"

#import "../Diagnostic/RLXEngineDiagnostic.h"
#import "../Engine/RLXEngineError.h"
#import "../Log/RLXEngineLog.h"

#include <TargetConditionals.h>
#include <errno.h>
#include <string.h>

NSString *_Nullable RLXEngineActionName(RLXEngineAction action) {
    switch (action) {
        case RLXEngineActionRestartSpringBoard:
            return @"Restart SpringBoard";
        case RLXEngineActionRestartUserspace:
            return @"Restart Userspace";
        case RLXEngineActionRefreshJailbreakApps:
            return @"Refresh Jailbreak Apps";
        case RLXEngineActionResetJailbreakPassword:
            return @"Reset Mobile Password";
        case RLXEngineActionRemoveJailbreak:
            return @"Remove Jailbreak";
        case RLXEngineActionReinstallSileo:
            return @"Reinstall Sileo";
        case RLXEngineActionReinstallZebra:
            return @"Reinstall Zebra";
        case RLXEngineActionRepairPackageSources:
            return @"Repair Package Sources";
    }
    return nil;
}

NSString *_Nullable RLXEngineActionIdentifier(RLXEngineAction action) {
    switch (action) {
        case RLXEngineActionRestartSpringBoard:
            return @"restart_springboard";
        case RLXEngineActionRestartUserspace:
            return @"restart_userspace";
        case RLXEngineActionRefreshJailbreakApps:
            return @"refresh_jailbreak_apps";
        case RLXEngineActionResetJailbreakPassword:
            return @"reset_mobile_password";
        case RLXEngineActionRemoveJailbreak:
            return @"remove_jailbreak";
        case RLXEngineActionReinstallSileo:
            return @"reinstall_sileo";
        case RLXEngineActionReinstallZebra:
            return @"reinstall_zebra";
        case RLXEngineActionRepairPackageSources:
            return @"repair_package_sources";
    }
    return nil;
}

NSError *RLXInvalidActionError(void) {
    return [RLXEngineError errorWithCode:RLXEngineErrorCodeInvalidAction
                             description:@"The requested engine action is invalid."
                           failureReason:nil
                      recoverySuggestion:nil
                              diagnostic:nil];
}

NSError *RLXUnavailableActionError(RLXEngineAction action, NSString *reason) {
    NSString *name = RLXEngineActionName(action) ?: @"The requested action";
    NSString *identifier = RLXEngineActionIdentifier(action) ?: @"unknown";
    RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnostic];
    [diagnostic appendKey:@"action" value:identifier];
    [diagnostic appendPhase:@"runtime_preflight"];
    return [RLXEngineError errorWithCode:RLXEngineErrorCodeStageUnavailable
                             description:[NSString stringWithFormat:@"%@ is unavailable.", name]
                           failureReason:reason
                      recoverySuggestion:@"Activate the RootHide jailbreak runtime and try again."
                              diagnostic:diagnostic];
}

#if !TARGET_OS_SIMULATOR

NSError *RLXActionExecutionError(RLXEngineAction action,
                                 NSString *phase,
                                 int status,
                                 NSError *_Nullable underlyingError) {
    int errorCode = status > 0 && status <= ELAST ? status : EIO;
    NSString *statusDescription = [NSString stringWithUTF8String:strerror(errorCode)] ?: @"Unknown error";
    NSString *name = RLXEngineActionName(action) ?: @"The requested action";
    NSString *identifier = RLXEngineActionIdentifier(action) ?: @"unknown";
    NSString *failureReason = underlyingError.localizedDescription
        ?: [NSString
               stringWithFormat:@"The operation failed during %@ with status %d: %@", phase, status, statusDescription];
    RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnostic];
    [diagnostic appendKey:@"action" value:identifier];
    [diagnostic appendPhase:phase];
    [diagnostic appendStatus:status];
    [diagnostic appendKey:@"status_description" value:statusDescription];
    NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo = [@{
        NSLocalizedDescriptionKey : [NSString stringWithFormat:@"%@ failed.", name],
        NSLocalizedFailureReasonErrorKey : failureReason,
        NSLocalizedRecoverySuggestionErrorKey : @"Verify the jailbreak runtime is active, then try again.",
        RLXEngineDiagnosticKey : diagnostic.renderedValue,
    } mutableCopy];
    if (underlyingError) {
        userInfo[NSUnderlyingErrorKey] = underlyingError;
    }
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:errorCode userInfo:userInfo];
}

void RLXPublishActionOutput(NSString *message, RLXEngineOutputHandler outputHandler) {
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

#endif

void RLXCompleteAction(NSError *_Nullable error, RLXEngineCompletionHandler completion) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) {
            completion(error);
        }
    });
}

void RLXLogActionResult(RLXEngineAction action, NSError *_Nullable error) {
    NSString *identifier = RLXEngineActionIdentifier(action) ?: @"unknown";
    if (error) {
        NSString *diagnostic = error.userInfo[RLXEngineDiagnosticKey] ?: @"";
        NSString *message = [NSString stringWithFormat:@"action=%@ failed error=%@%@%@",
                                                       identifier,
                                                       error.localizedDescription,
                                                       diagnostic.length > 0 ? @"\n" : @"",
                                                       diagnostic];
        rlx_engine_log(RLX_ENGINE_LOG_ERROR, "RLXEngineAction", message.UTF8String);
        return;
    }

    NSString *message = [NSString stringWithFormat:@"action=%@ dispatched", identifier];
    rlx_engine_log(RLX_ENGINE_LOG_INFO, "RLXEngineAction", message.UTF8String);
}
