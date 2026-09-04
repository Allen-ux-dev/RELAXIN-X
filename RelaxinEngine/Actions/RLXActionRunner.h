//
//  RLXActionRunner.h
//  RelaxinEngine
//
//  Shared plumbing behind the engine actions.
//

#import <Foundation/Foundation.h>

#import "RLXEngine+Actions.h"

#include <TargetConditionals.h>

NS_ASSUME_NONNULL_BEGIN

/* Internal to the framework's compatibility façade and Sileo reinstall. */
#pragma GCC visibility push(hidden)

NSString *_Nullable RLXEngineActionName(RLXEngineAction action);
NSString *_Nullable RLXEngineActionIdentifier(RLXEngineAction action);

NSError *RLXInvalidActionError(void);
NSError *RLXUnavailableActionError(RLXEngineAction action, NSString *reason);
void RLXCompleteAction(NSError *_Nullable error, RLXEngineCompletionHandler completion);
void RLXLogActionResult(RLXEngineAction action, NSError *_Nullable error);

#if !TARGET_OS_SIMULATOR

NSError *RLXActionExecutionError(RLXEngineAction action,
                                 NSString *phase,
                                 int status,
                                 NSError *_Nullable underlyingError);
void RLXPublishActionOutput(NSString *message, RLXEngineOutputHandler outputHandler);

#endif /* !TARGET_OS_SIMULATOR */

#pragma GCC visibility pop

NS_ASSUME_NONNULL_END
