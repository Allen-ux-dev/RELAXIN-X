//
//  RLXBootstrapPreparationError.m
//  RelaxinEngine
//

#import "RLXBootstrapPreparationError.h"

#import "../Engine/RLXEngine.h"
#import "../Diagnostic/RLXEngineDiagnostic.h"
#import "../Engine/RLXEngineError.h"

#include <errno.h>
#include <string.h>

int rlx_status_for_error(NSError *error) {
    if ([error.domain isEqualToString:NSPOSIXErrorDomain]) {
        return (int)error.code;
    }
    return EIO;
}

NSError *rlx_bootstrap_preparation_error(NSString *phase,
                                         int status,
                                         NSString *_Nullable detail,
                                         NSError *_Nullable underlying) {
    const char *statusCString = status > 0 ? strerror(status) : NULL;
    NSString *statusDescription = statusCString ? [NSString stringWithUTF8String:statusCString] : @"unknown status";
    BOOL filesystemStateMayBePartial = !([phase isEqualToString:@"validate_runtime"] ||
                                         [phase isEqualToString:@"detect_active_jailbreak"] ||
                                         [phase isEqualToString:@"enable_developer_mode"]);
    RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnosticWithStage:@"bootstrap_preparation"];
    [diagnostic appendPhase:phase];
    [diagnostic appendStatus:status];
    [diagnostic appendKey:@"status_description" value:statusDescription];
    [diagnostic appendKey:@"filesystem_state_may_be_partial" boolValue:filesystemStateMayBePartial];
    [diagnostic appendKernelStateMayBeDirty:YES];
    if (detail.length > 0) {
        [diagnostic appendRenderedDiagnostic:detail];
    }
    NSString *logMessage = [NSString stringWithFormat:@"failed phase=%@ status=%d description=%@%@%@",
                                                      phase,
                                                      status,
                                                      statusDescription,
                                                      detail.length > 0 ? @" " : @"",
                                                      detail ?: @""];
    rlx_engine_log(RLX_ENGINE_LOG_ERROR, "RLXBootstrapPreparation", logMessage.UTF8String);

    BOOL existingBootstrapRequiresReinstallation = [phase isEqualToString:@"validate_existing_jbroot_topology"];
    NSString *recoverySuggestion = existingBootstrapRequiresReinstallation
        ? @"Use Remove Jailbreak to delete the existing bootstrap, then " "install it again with this version of Relaxin."
        : @"Reboot the device before retrying. Relaxin will discard an " "uncommitted bootstrap on the next run.";
    return [RLXEngineError
             errorWithCode:RLXEngineErrorCodeBootstrapPreparationFailed
               description:@"The RootHide bootstrap could not be prepared."
             failureReason:[NSString
                               stringWithFormat:@"%@ failed with status %d (%@).", phase, status, statusDescription]
        recoverySuggestion:recoverySuggestion
                diagnostic:diagnostic
           underlyingError:underlying];
}
