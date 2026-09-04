//
//  RLXJailbreakdCheckinTask.m
//  RelaxinEngine
//

#import "RLXJailbreakdCheckinTask.h"

#import "../../Engine/RLXEngine.h"
#import "../../Diagnostic/RLXEngineDiagnostic.h"
#import "../../Engine/RLXEngineError.h"
#import "../../Log/RLXEngineLog.h"
#import "../../Engine/RLXEngineRunContext.h"

#include <errno.h>
#include <string.h>
#include <unistd.h>

#include <libjailbreak/jbclient_xpc.h>

static const char *const RLXJailbreakdCheckinLogCategory = "JailbreakdCheckin";
// todo: test these consts.
static const NSUInteger RLXJailbreakdCheckinAttemptCount = 100;
static const useconds_t RLXJailbreakdCheckinPollInterval = 100000;

static NSError *rlx_jailbreakd_checkin_error(int status, NSUInteger attempts) {
    int displayStatus = status > 0 ? status : EIO;
    NSString *statusDescription = @(strerror(displayStatus));
    RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnostic];
    [diagnostic appendPhase:@"checkin"];
    [diagnostic appendStatus:status];
    [diagnostic appendKey:@"status_description" value:statusDescription];
    [diagnostic appendKey:@"attempts" integerValue:(NSInteger)attempts];
    [diagnostic appendKey:@"poll_interval_us" integerValue:RLXJailbreakdCheckinPollInterval];
    NSString *message = [NSString
        stringWithFormat:@"jailbreakd did not check in after %lu attempts " "(last status=%d)",
                         (unsigned long)attempts,
                         status];
    rlx_engine_log(RLX_ENGINE_LOG_ERROR, RLXJailbreakdCheckinLogCategory, message.UTF8String);
    return [RLXEngineError errorWithCode:RLXEngineErrorCodeJailbreakdCheckinFailed
                             description:@"jailbreakd did not complete its launchd check-in."
                           failureReason:@"The launchd hook did not observe jailbreakd taking " "over its server port."
                      recoverySuggestion:@"Inspect the jailbreakd startup log before retrying."
                              diagnostic:diagnostic];
}

@implementation RLXJailbreakdCheckinTask

- (instancetype)initWithContext:(RLXEngineRunContext *)context {
    return [super initWithStage:RLXEngineStageJailbreakdCheckin context:context];
}

- (nullable NSError *)execute {
    rlx_engine_log(RLX_ENGINE_LOG_INFO, RLXJailbreakdCheckinLogCategory, "waiting for jailbreakd check-in");

    int lastStatus = 0;
    for (NSUInteger attempt = 1; attempt <= RLXJailbreakdCheckinAttemptCount; ++attempt) {
        bool checkedIn = false;
        int status = jbclient_jailbreakd_checkin_status(&checkedIn);
        if (attempt == 1 || status != lastStatus) {
            NSString *message = [NSString
                stringWithFormat:@"jailbreakd check-in pending attempt=%lu status=%d", (unsigned long)attempt, status];
            rlx_engine_log(RLX_ENGINE_LOG_INFO, RLXJailbreakdCheckinLogCategory, message.UTF8String);
        }
        lastStatus = status;
        if (lastStatus == 0 && checkedIn) {
            NSString *message = [NSString
                stringWithFormat:@"jailbreakd check-in completed attempt=%lu", (unsigned long)attempt];
            rlx_engine_log(RLX_ENGINE_LOG_INFO, RLXJailbreakdCheckinLogCategory, message.UTF8String);
            return nil;
        }

        if (attempt < RLXJailbreakdCheckinAttemptCount) {
            usleep(RLXJailbreakdCheckinPollInterval);
        }
    }

    return rlx_jailbreakd_checkin_error(lastStatus == 0 ? ETIMEDOUT : lastStatus, RLXJailbreakdCheckinAttemptCount);
}

@end
