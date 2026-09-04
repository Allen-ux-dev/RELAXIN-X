//
//  RLXEngineTaskQueue.m
//  RelaxinEngine
//

#import "RLXEngineTaskQueue.h"

#import "../Diagnostic/RLXEngineDiagnostic.h"
#import "RLXEngineError.h"
#import "../Log/RLXEngineLog.h"
#import "RLXEngineRunContext.h"
#import "RLXEngineTask.h"

#include <errno.h>

/// Diagnostic fields the queue contributes after a stage fails.
static NSString *const kKernelAccessFinalizePhase = @"kernel_access_finalize";
static NSString *const kCleanupStatusKey = @"cleanup_status";
static NSString *const kKernelStateMayBeDirtyKey = @"kernel_state_may_be_dirty";

@interface RLXEngineTaskQueue ()

- (void)executeTasks:(NSArray<RLXEngineTask *> *)tasks
       updateHandler:(nullable RLXEngineTaskUpdateHandler)updateHandler
          completion:(nullable RLXEngineCompletionHandler)completion;
- (void)publishUpdate:(RLXEngineTaskUpdate *)update updateHandler:(nullable RLXEngineTaskUpdateHandler)updateHandler;
- (NSError *)errorBySettingFailureStage:(RLXEngineStage)stage
                               position:(NSUInteger)position
                                  count:(NSUInteger)count
                               forError:(NSError *)error;
- (NSError *)errorByFinalizingKernelAccessForTask:(RLXEngineTask *)task error:(NSError *)error;

@end

@implementation RLXEngineTaskQueue {
    dispatch_queue_t _queue;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        dispatch_queue_attr_t
            attributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL,
                                                                 QOS_CLASS_DEFAULT,
                                                                 0);
        _queue = dispatch_queue_create("com.aapl.relaxin.engine.tasks", attributes);
    }
    return self;
}

- (void)enqueueTasks:(NSArray<RLXEngineTask *> *)tasks
       updateHandler:(RLXEngineTaskUpdateHandler)updateHandler
          completion:(RLXEngineCompletionHandler)completion {
    NSArray<RLXEngineTask *> *taskSnapshot = [tasks copy];
    dispatch_async(_queue, ^{
        [self executeTasks:taskSnapshot updateHandler:updateHandler completion:completion];
    });
}

- (void)executeTasks:(NSArray<RLXEngineTask *> *)tasks
       updateHandler:(RLXEngineTaskUpdateHandler)updateHandler
          completion:(RLXEngineCompletionHandler)completion {
    NSUInteger taskCount = tasks.count;
    for (NSUInteger taskIndex = 0; taskIndex < taskCount; taskIndex++) {
        RLXEngineTask *task = tasks[taskIndex];
        NSUInteger position = taskIndex + 1;
        NSString *stageDescription = [NSString
            stringWithFormat:@"[%lu/%lu] %@", (unsigned long)position, (unsigned long)taskCount, task.name];
        RLXEngineTaskUpdate *runningUpdate = [[RLXEngineTaskUpdate alloc] initWithStage:task.stage message:task.name
                                                                               position:position
                                                                                  count:taskCount
                                                                                 status:RLXEngineTaskStatusRunning];
        [self publishUpdate:runningUpdate updateHandler:updateHandler];
        NSError *error = [task execute];
        if (error) {
            NSError *stagedError = [self errorBySettingFailureStage:task.stage position:position count:taskCount
                                                           forError:error];
            stagedError = [self errorByFinalizingKernelAccessForTask:task error:stagedError];
            rlx_engine_log(RLX_ENGINE_LOG_ERROR, "RLXEngine", stageDescription.UTF8String);
            rlx_engine_log(RLX_ENGINE_LOG_ERROR, "RLXEngine", stagedError.localizedDescription.UTF8String);
            NSString *diagnostic = stagedError.userInfo[RLXEngineDiagnosticKey];
            if (diagnostic) {
                rlx_engine_log(RLX_ENGINE_LOG_ERROR, "RLXEngine", diagnostic.UTF8String);
            }
            RLXEngineTaskUpdate *failedUpdate = [[RLXEngineTaskUpdate alloc] initWithStage:task.stage message:task.name
                                                                                  position:position
                                                                                     count:taskCount
                                                                                    status:RLXEngineTaskStatusFailed];
            [self publishUpdate:failedUpdate updateHandler:updateHandler];
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(stagedError);
                });
            }
            return;
        }

        rlx_engine_log(RLX_ENGINE_LOG_INFO, "RLXEngine", stageDescription.UTF8String);
        RLXEngineTaskUpdate *succeededUpdate = [[RLXEngineTaskUpdate alloc] initWithStage:task.stage message:task.name
                                                                                 position:position
                                                                                    count:taskCount
                                                                                   status:RLXEngineTaskStatusSucceeded];
        [self publishUpdate:succeededUpdate updateHandler:updateHandler];
    }

    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
    }
}

- (NSError *)errorByFinalizingKernelAccessForTask:(RLXEngineTask *)task error:(NSError *)error {
    int status = 0;
    if (![task.context finalizeKernelAccessReturningStatus:&status]) {
        return error;
    }
    [task.context discardKernelAccess];
    if (status == 0 || status == EALREADY) {
        rlx_engine_log(
            RLX_ENGINE_LOG_INFO,
            "RLXEngine",
            status == 0
                ? "kernel access finalized after task failure; process " "privileges remain active until the App exits"
                : "kernel access was already inactive after task failure");
        if (status == EALREADY) {
            return error;
        }

        /*
         * The stage reported whether it might have left the kernel dirty. It
         * did not, because cleanup has just succeeded, so that field is
         * rewritten rather than contradicted by a second one. A stage that
         * never mentioned the field does not get it rewritten — it gets it
         * stated, which is what the text substitution did by falling through.
         */
        RLXEngineDiagnostic *diagnostic = [RLXEngineError diagnosticFromError:error];
        BOOL stageReportedKernelState = [diagnostic containsKey:kKernelStateMayBeDirtyKey];
        [diagnostic setBoolValue:NO forEveryKey:kKernelStateMayBeDirtyKey];
        [diagnostic appendPhase:kKernelAccessFinalizePhase];
        [diagnostic appendKey:kCleanupStatusKey integerValue:0];
        if (!stageReportedKernelState) {
            [diagnostic appendKernelStateMayBeDirty:NO];
        }
        return [RLXEngineError errorFromError:error
                             revisingUserInfo:^(NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo) {
                                 userInfo[RLXEngineDiagnosticKey] = diagnostic.renderedValue;
                             }];
    }

    NSString *message = [NSString
        stringWithFormat:@"kernel access finalization failed after task failure status=%d", status];
    rlx_engine_log(RLX_ENGINE_LOG_ERROR, "RLXEngine", message.UTF8String);

    /*
     * Cleanup failed, so whatever the stage reported about kernel state is now
     * superseded: the field is appended rather than rewritten, because both the
     * stage's claim and this outcome are part of the record.
     */
    RLXEngineDiagnostic *diagnostic = [RLXEngineError diagnosticFromError:error];
    [diagnostic appendPhase:kKernelAccessFinalizePhase];
    [diagnostic appendKey:kCleanupStatusKey integerValue:status];
    [diagnostic appendKernelStateMayBeDirty:YES];
    return [RLXEngineError errorFromError:error revisingUserInfo:^(
                                                    NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo) {
        userInfo[RLXEngineDiagnosticKey] = diagnostic.renderedValue;
        userInfo[NSLocalizedRecoverySuggestionErrorKey] = @"Reboot the device before starting another jailbreak run.";
    }];
}

- (void)publishUpdate:(RLXEngineTaskUpdate *)update updateHandler:(RLXEngineTaskUpdateHandler)updateHandler {
    if (!updateHandler) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        updateHandler(update);
    });
}

- (NSError *)errorBySettingFailureStage:(RLXEngineStage)stage
                               position:(NSUInteger)position
                                  count:(NSUInteger)count
                               forError:(NSError *)error {
    NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo = [error.userInfo mutableCopy]
        ?: [NSMutableDictionary dictionary];
    userInfo[RLXEngineFailureStageKey] = @(stage);
    userInfo[RLXEngineFailureTaskPositionKey] = @(position);
    userInfo[RLXEngineFailureTaskCountKey] = @(count);
    return [NSError errorWithDomain:error.domain code:error.code userInfo:userInfo];
}

@end
