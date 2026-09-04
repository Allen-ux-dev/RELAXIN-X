#import <RelaxinEngine/RLXEngine.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RLXEngineAction) {
    RLXEngineActionRestartSpringBoard,
    RLXEngineActionRestartUserspace,
    RLXEngineActionRefreshJailbreakApps,
    RLXEngineActionResetJailbreakPassword,
    RLXEngineActionRemoveJailbreak,
    RLXEngineActionReinstallSileo,
    RLXEngineActionReinstallZebra,
    RLXEngineActionRepairPackageSources,
};

typedef void (^RLXEngineOutputHandler)(NSString *message);

typedef NSString *RLXEngineActionArgumentKey NS_TYPED_EXTENSIBLE_ENUM;

FOUNDATION_EXPORT RLXEngineActionArgumentKey const RLXEngineActionArgumentPasswordKey;
FOUNDATION_EXPORT RLXEngineActionArgumentKey const RLXEngineActionArgumentBootLogoDarkAppearanceKey;
FOUNDATION_EXPORT RLXEngineActionArgumentKey const RLXEngineActionArgumentPackagePathKey;
FOUNDATION_EXPORT RLXEngineActionArgumentKey const RLXEngineActionArgumentPackageManagerKey;

@interface RLXEngine (Actions)

- (BOOL)tweakInjectionEnabled NS_SWIFT_NAME(tweakInjectionEnabled());

- (void)setTweakInjectionEnabled:(BOOL)enabled NS_SWIFT_NAME(setTweakInjectionEnabled(_:));

- (BOOL)appJITEnabled NS_SWIFT_NAME(appJITEnabled());

- (void)setAppJITEnabled:(BOOL)enabled NS_SWIFT_NAME(setAppJITEnabled(_:));

- (void)performAction:(RLXEngineAction)action
         outputHandler:(nullable RLXEngineOutputHandler)outputHandler
    completionCallback:(nullable RLXEngineCompletionHandler)completionCallback
    NS_SWIFT_NAME(perform(action:output:completion:));

- (void)performAction:(RLXEngineAction)action
             arguments:(nullable NSDictionary<RLXEngineActionArgumentKey, NSString *> *)arguments
         outputHandler:(nullable RLXEngineOutputHandler)outputHandler
    completionCallback:(nullable RLXEngineCompletionHandler)completionCallback
    NS_SWIFT_NAME(perform(action:arguments:output:completion:));

@end

NS_ASSUME_NONNULL_END
