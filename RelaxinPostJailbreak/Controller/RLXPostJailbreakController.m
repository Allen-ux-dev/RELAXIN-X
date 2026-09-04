#import "RLXPostJailbreakController.h"

#import "RLXPostJailbreakLog.h"
#import "../Actions/RLXPostJailbreakActionRunner.h"
#import "../Actions/RLXPostJailbreakActions.h"

#include <TargetConditionals.h>
#include <dlfcn.h>
#include <errno.h>
#include <unistd.h>

#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR
#include <libjailbreak/codesign.h>
#include <libjailbreak/jbclient_xpc.h>
#include <libjailbreak/jbroot.h>
#endif

NSErrorDomain const RLXPostJailbreakErrorDomain = @"com.aapl.relaxin.post-jailbreak";
NSErrorUserInfoKey const RLXPostJailbreakDiagnosticKey = @"RLXPostJailbreakDiagnostic";
RLXPostJailbreakActionArgumentKey const
    RLXPostJailbreakActionArgumentBootLogoDarkAppearanceKey = @"bootLogoDarkAppearance";
RLXPostJailbreakActionArgumentKey const RLXPostJailbreakActionArgumentBundleIdentifierKey = @"bundleIdentifier";
RLXPostJailbreakActionArgumentKey const RLXPostJailbreakActionArgumentCompatibilityEnabledKey = @"compatibilityEnabled";

#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR

typedef char *(*RLXSystemHookGetJailbreakRoot)(void);

static BOOL rlx_process_has_active_roothide_runtime(void) {
    void *systemHook = dlopen("systemhook.dylib", RTLD_NOLOAD);
    if (!systemHook) {
        return NO;
    }

    RLXSystemHookGetJailbreakRoot getJailbreakRoot = (RLXSystemHookGetJailbreakRoot)dlsym(systemHook, "get_jbroot");
    const char *rootPath = getJailbreakRoot ? getJailbreakRoot() : NULL;
    BOOL checkedIn = rootPath && rootPath[0] != '\0';
    dlclose(systemHook);
    if (!checkedIn) {
        return NO;
    }

    uint32_t csflags = 0;
    return csops(getpid(), CS_OPS_STATUS, &csflags, sizeof(csflags)) == 0 && (csflags & CS_PLATFORM_BINARY) != 0;
}

static NSError *_Nullable rlx_execute_post_jailbreak_action(
    RLXPostJailbreakAction action,
    NSBundle *resourceBundle,
    NSDictionary<RLXPostJailbreakActionArgumentKey, NSString *> *_Nullable arguments) {
    NSString *failurePhase = nil;
    int status = 0;

    switch (action) {
        case RLXPostJailbreakActionRestartSpringBoard:
            status = RLXPostJailbreakRestartSpringBoard(&failurePhase);
            break;
        case RLXPostJailbreakActionRestartUserspace:
            return RLXPostJailbreakRestartUserspace(resourceBundle,
                                                    arguments[RLXPostJailbreakActionArgumentBootLogoDarkAppearanceKey]
                                                        .boolValue);
        case RLXPostJailbreakActionRefreshJailbreakApps:
            status = RLXPostJailbreakRefreshApps(&failurePhase);
            break;
        case RLXPostJailbreakActionResetMobilePassword:
            status = RLXPostJailbreakResetMobilePassword(&failurePhase);
            break;
        case RLXPostJailbreakActionRemoveJailbreak:
            return RLXPostJailbreakRemove(&failurePhase);
        case RLXPostJailbreakActionSetCompatibilityProfile: {
            NSString *bundleIdentifier = arguments[RLXPostJailbreakActionArgumentBundleIdentifierKey];
            NSString *enabled = arguments[RLXPostJailbreakActionArgumentCompatibilityEnabledKey];
            if (bundleIdentifier.length == 0 || enabled.length == 0) {
                return RLXPostJailbreakActionExecutionError(
                    action, @"validate_compatibility_profile", EINVAL, nil);
            }
            status = RLXPostJailbreakSetCompatibilityProfile(
                bundleIdentifier, enabled.boolValue, &failurePhase);
            break;
        }
    }

    return status == 0 ? nil : RLXPostJailbreakActionExecutionError(action, failurePhase ?: @"unknown", status, nil);
}

#endif /* TARGET_OS_IOS && !TARGET_OS_SIMULATOR */

@implementation RLXPostJailbreakController

- (instancetype)initWithResourceBundle:(NSBundle *)resourceBundle {
    self = [super init];
    if (self) {
        _resourceBundle = resourceBundle;
    }
    return self;
}

- (RLXPostJailbreakRuntimeEvidence)runtimeEvidence {
    RLXPostJailbreakRuntimeEvidence evidence = {0};
#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR
    evidence.rootHideReportedJailbroken = jbclient_roothide_jailbroken();
    evidence.processRuntimeActive = rlx_process_has_active_roothide_runtime();

    uint32_t csflags = 0;
    int csopsStatus = csops(getpid(), CS_OPS_STATUS, &csflags, sizeof(csflags));
    evidence.processIsPlatform = csopsStatus == 0 && (csflags & CS_PLATFORM_BINARY) != 0;
#endif
    return evidence;
}

- (BOOL)isAvailable {
#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR
    // Preserve the existing explicit check-in behavior for post-jailbreak actions.
    // Passive environment inspection uses -runtimeEvidence and does not perform this call.
    int checkinStatus = jbclient_process_checkin(NULL, NULL, NULL, NULL);
    RLXPostJailbreakRuntimeEvidence evidence = [self runtimeEvidence];
    BOOL available = evidence.rootHideReportedJailbroken && evidence.processIsPlatform;

    NSString *message = [NSString
        stringWithFormat:@"checkin=%d roothide=%d runtime=%d platform=%d available=%d",
                         checkinStatus,
                         evidence.rootHideReportedJailbroken,
                         evidence.processRuntimeActive,
                         evidence.processIsPlatform,
                         available];
    rlx_post_jailbreak_log(RLX_POST_JAILBREAK_LOG_INFO, "RLXPostJailbreakRuntime", message.UTF8String);
    return available;
#else
    return NO;
#endif
}

- (BOOL)hasActiveRootHideRuntime {
    return [self runtimeEvidence].processRuntimeActive;
}

- (BOOL)compatibilityProfileEnabledForBundleIdentifier:(NSString *)bundleIdentifier {
#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR
    if (bundleIdentifier.length == 0) {
        return NO;
    }
    return jbclient_blacklist_check_bundle(bundleIdentifier.UTF8String);
#else
    (void)bundleIdentifier;
    return NO;
#endif
}

- (BOOL)tweakInjectionEnabled {
#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR
    NSString *failurePhase = nil;
    if (RLXPostJailbreakLoadRoot(&failurePhase) != 0) {
        return NO;
    }
    return ![NSFileManager.defaultManager fileExistsAtPath:JBROOT_PATH(@"/basebin/.safe_mode")];
#else
    return NO;
#endif
}

- (void)setTweakInjectionEnabled:(BOOL)enabled {
#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR
    NSString *failurePhase = nil;
    if (RLXPostJailbreakLoadRoot(&failurePhase) != 0) {
        return;
    }

    NSString *safeModePath = JBROOT_PATH(@"/basebin/.safe_mode");
    if (!safeModePath) {
        return;
    }
    (void)RLXPostJailbreakRunAsEffectiveRoot(
        ^int {
            return RLXPostJailbreakRunUnsandboxed(
                ^int {
                    if (enabled) {
                        [NSFileManager.defaultManager removeItemAtPath:safeModePath error:nil];
                    } else {
                        [[NSData data] writeToFile:safeModePath atomically:YES];
                    }
                    return 0;
                },
                NULL);
        },
        NULL);
#else
    (void)enabled;
#endif
}

- (BOOL)appJITEnabled {
#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR
    return jbclient_jbsettings_get_bool("markAppsAsDebugged");
#else
    return NO;
#endif
}

- (void)setAppJITEnabled:(BOOL)enabled {
#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR
    (void)jbclient_platform_jbsettings_set_bool("markAppsAsDebugged", enabled);
#else
    (void)enabled;
#endif
}

- (void)performAction:(RLXPostJailbreakAction)action
        outputHandler:(RLXPostJailbreakOutputHandler)outputHandler
           completion:(RLXPostJailbreakCompletionHandler)completion {
    [self performAction:action arguments:nil outputHandler:outputHandler completion:completion];
}

- (void)performAction:(RLXPostJailbreakAction)action
            arguments:(NSDictionary<RLXPostJailbreakActionArgumentKey, NSString *> *)arguments
        outputHandler:(RLXPostJailbreakOutputHandler)outputHandler
           completion:(RLXPostJailbreakCompletionHandler)completion {
    if (!RLXPostJailbreakActionName(action)) {
        NSError *error = RLXPostJailbreakInvalidActionError();
        RLXPostJailbreakLogActionResult(action, error);
        RLXPostJailbreakCompleteAction(error, completion);
        return;
    }

    dispatch_async(RLXPostJailbreakActionQueue(), ^{
        @autoreleasepool {
            NSError *error = nil;
#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR
            if (![self isAvailable]) {
                error = RLXPostJailbreakUnavailableActionError(
                    action,
                    @"The App is not running inside an active RootHide jailbreak.");
            } else {
                NSString *failurePhase = nil;
                int rootStatus = RLXPostJailbreakLoadRoot(&failurePhase);
                if (rootStatus != 0) {
                    error = RLXPostJailbreakActionExecutionError(action,
                                                                 failurePhase ?: @"jailbreak_root",
                                                                 rootStatus,
                                                                 nil);
                } else {
                    RLXPostJailbreakPublishActionOutput(RLXPostJailbreakActionName(action), outputHandler);
                    error = rlx_execute_post_jailbreak_action(action, self.resourceBundle, arguments);
                }
            }
#else
            error = RLXPostJailbreakUnavailableActionError(
                action,
                @"Post-jailbreak actions are unavailable on this platform.");
#endif
            RLXPostJailbreakLogActionResult(action, error);
            RLXPostJailbreakCompleteAction(error, completion);
        }
    });
}

@end
