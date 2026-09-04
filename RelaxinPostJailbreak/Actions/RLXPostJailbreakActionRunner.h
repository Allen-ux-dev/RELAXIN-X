#import <Foundation/Foundation.h>

#import "../Controller/RLXPostJailbreakController.h"

#include <TargetConditionals.h>

NS_ASSUME_NONNULL_BEGIN

#pragma GCC visibility push(hidden)

NSString *_Nullable RLXPostJailbreakActionName(RLXPostJailbreakAction action);
NSString *_Nullable RLXPostJailbreakActionIdentifier(RLXPostJailbreakAction action);
dispatch_queue_t RLXPostJailbreakActionQueue(void);

NSError *RLXPostJailbreakInvalidActionError(void);
NSError *RLXPostJailbreakUnavailableActionError(RLXPostJailbreakAction action, NSString *reason);
NSError *RLXPostJailbreakActionExecutionError(RLXPostJailbreakAction action,
                                              NSString *phase,
                                              int status,
                                              NSError *_Nullable underlyingError);
void RLXPostJailbreakCompleteAction(NSError *_Nullable error, RLXPostJailbreakCompletionHandler _Nullable completion);
void RLXPostJailbreakLogActionResult(RLXPostJailbreakAction action, NSError *_Nullable error);
void RLXPostJailbreakPublishActionOutput(NSString *message, RLXPostJailbreakOutputHandler _Nullable outputHandler);

#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR

typedef int (^RLXPostJailbreakOperation)(void);

void RLXPostJailbreakSetFailurePhase(NSString *_Nullable __strong *_Nullable failurePhase, NSString *phase);
int RLXPostJailbreakSpawnStatus(int status);
int RLXPostJailbreakWaitStatus(int status);
BOOL RLXPostJailbreakInstalledThroughTrollStore(void);
int RLXPostJailbreakLoadRoot(NSString *_Nullable __strong *_Nullable failurePhase);
int RLXPostJailbreakRunUnsandboxed(RLXPostJailbreakOperation operation,
                                   NSString *_Nullable __strong *_Nullable failurePhase);
int RLXPostJailbreakRunAsEffectiveRoot(RLXPostJailbreakOperation operation,
                                       NSString *_Nullable __strong *_Nullable failurePhase);

#endif /* TARGET_OS_IOS && !TARGET_OS_SIMULATOR */

#pragma GCC visibility pop

NS_ASSUME_NONNULL_END
