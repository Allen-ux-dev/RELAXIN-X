#import "RLXEngine+Actions.h"

#import "RLXActionRunner.h"
#import "RLXActions.h"
#import "../../RelaxinPostJailbreak/Actions/RLXPostJailbreakActionRunner.h"

#include <TargetConditionals.h>

static BOOL rlx_post_jailbreak_action(RLXEngineAction action, RLXPostJailbreakAction *postJailbreakAction) {
    switch (action) {
        case RLXEngineActionRestartSpringBoard:
            *postJailbreakAction = RLXPostJailbreakActionRestartSpringBoard;
            return YES;
        case RLXEngineActionRestartUserspace:
            *postJailbreakAction = RLXPostJailbreakActionRestartUserspace;
            return YES;
        case RLXEngineActionRefreshJailbreakApps:
            *postJailbreakAction = RLXPostJailbreakActionRefreshJailbreakApps;
            return YES;
        case RLXEngineActionResetJailbreakPassword:
            *postJailbreakAction = RLXPostJailbreakActionResetMobilePassword;
            return YES;
        case RLXEngineActionRemoveJailbreak:
            *postJailbreakAction = RLXPostJailbreakActionRemoveJailbreak;
            return YES;
        case RLXEngineActionReinstallSileo:
        case RLXEngineActionReinstallZebra:
        case RLXEngineActionRepairPackageSources:
            return NO;
    }
    return NO;
}

@implementation RLXEngine (Actions)

RLXEngineActionArgumentKey const RLXEngineActionArgumentPasswordKey = @"password";
RLXEngineActionArgumentKey const RLXEngineActionArgumentBootLogoDarkAppearanceKey = @"bootLogoDarkAppearance";
RLXEngineActionArgumentKey const RLXEngineActionArgumentPackagePathKey = @"packagePath";
RLXEngineActionArgumentKey const RLXEngineActionArgumentPackageManagerKey = @"packageManager";

- (BOOL)tweakInjectionEnabled {
    return self.postJailbreakController.tweakInjectionEnabled;
}

- (void)setTweakInjectionEnabled:(BOOL)enabled {
    [self.postJailbreakController setTweakInjectionEnabled:enabled];
}

- (BOOL)appJITEnabled {
    return self.postJailbreakController.appJITEnabled;
}

- (void)setAppJITEnabled:(BOOL)enabled {
    [self.postJailbreakController setAppJITEnabled:enabled];
}

- (void)performAction:(RLXEngineAction)action
         outputHandler:(RLXEngineOutputHandler)outputHandler
    completionCallback:(RLXEngineCompletionHandler)completionCallback {
    [self performAction:action arguments:nil outputHandler:outputHandler completionCallback:completionCallback];
}

- (void)performAction:(RLXEngineAction)action
             arguments:(NSDictionary<RLXEngineActionArgumentKey, NSString *> *)arguments
         outputHandler:(RLXEngineOutputHandler)outputHandler
    completionCallback:(RLXEngineCompletionHandler)completionCallback {
    NSString *name = RLXEngineActionName(action);
    if (!name) {
        NSError *error = RLXInvalidActionError();
        RLXLogActionResult(action, error);
        RLXCompleteAction(error, completionCallback);
        return;
    }

    RLXPostJailbreakAction postJailbreakAction;
    if (rlx_post_jailbreak_action(action, &postJailbreakAction)) {
        NSDictionary<RLXPostJailbreakActionArgumentKey, NSString *>
            *postArguments = arguments[RLXEngineActionArgumentBootLogoDarkAppearanceKey] ? @{
                RLXPostJailbreakActionArgumentBootLogoDarkAppearanceKey :
                    arguments[RLXEngineActionArgumentBootLogoDarkAppearanceKey]
            }
                                                                                         : nil;
        [self.postJailbreakController performAction:postJailbreakAction arguments:postArguments
                                      outputHandler:outputHandler
                                         completion:completionCallback];
        return;
    }

    dispatch_async(RLXPostJailbreakActionQueue(), ^{
        @autoreleasepool {
            NSError *error = nil;
#if TARGET_OS_SIMULATOR
            error = RLXUnavailableActionError(action, @"Manual jailbreak actions are unavailable in the simulator.");
#else
            if (![self.postJailbreakController isAvailable]) {
                error = RLXUnavailableActionError(
                    action,
                    @"The App is not running inside an active RootHide jailbreak.");
            }
            else {
                NSString *failurePhase = nil;
                int rootStatus = RLXPostJailbreakLoadRoot(&failurePhase);
                if (rootStatus != 0) {
                    error = RLXActionExecutionError(
                        action,
                        failurePhase ?: @"jailbreak_root",
                        rootStatus,
                        nil);
                }
                else {
                    RLXPublishActionOutput(name, outputHandler);
                    switch (action) {
                        case RLXEngineActionReinstallSileo:
                            error = RLXReinstallSileo(
                                self.runtimeEnvironment.resourceBundle,
                                &failurePhase);
                            break;
                        case RLXEngineActionReinstallZebra: {
                            NSString *packagePath = arguments[RLXEngineActionArgumentPackagePathKey];
                            error = packagePath.length > 0
                                ? RLXReinstallZebra(packagePath, &failurePhase)
                                : RLXActionExecutionError(action, @"validate_package_path", EINVAL, nil);
                            break;
                        }
                        case RLXEngineActionRepairPackageSources: {
                            NSString *packageManager = arguments[RLXEngineActionArgumentPackageManagerKey];
                            error = packageManager.length > 0
                                ? RLXRepairPackageSources(packageManager, &failurePhase)
                                : RLXActionExecutionError(action, @"validate_package_manager", EINVAL, nil);
                            break;
                        }
                        default:
                            error = RLXInvalidActionError();
                            break;
                    }
                }
            }
#endif
            RLXLogActionResult(action, error);
            RLXCompleteAction(error, completionCallback);
        }
    });
}

@end
