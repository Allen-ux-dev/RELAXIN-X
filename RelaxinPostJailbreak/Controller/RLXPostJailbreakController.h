#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const RLXPostJailbreakErrorDomain;
FOUNDATION_EXPORT NSErrorUserInfoKey const RLXPostJailbreakDiagnosticKey;

typedef NS_ENUM(NSInteger, RLXPostJailbreakAction) {
    RLXPostJailbreakActionRestartSpringBoard,
    RLXPostJailbreakActionRestartUserspace,
    RLXPostJailbreakActionRefreshJailbreakApps,
    RLXPostJailbreakActionResetMobilePassword,
    RLXPostJailbreakActionRemoveJailbreak,
    RLXPostJailbreakActionSetCompatibilityProfile,
};

typedef NSString *RLXPostJailbreakActionArgumentKey NS_TYPED_EXTENSIBLE_ENUM;

FOUNDATION_EXPORT RLXPostJailbreakActionArgumentKey const RLXPostJailbreakActionArgumentBootLogoDarkAppearanceKey;
FOUNDATION_EXPORT RLXPostJailbreakActionArgumentKey const RLXPostJailbreakActionArgumentBundleIdentifierKey;
FOUNDATION_EXPORT RLXPostJailbreakActionArgumentKey const RLXPostJailbreakActionArgumentCompatibilityEnabledKey;

typedef void (^RLXPostJailbreakOutputHandler)(NSString *message);
typedef void (^RLXPostJailbreakCompletionHandler)(NSError *_Nullable error);

typedef struct {
    BOOL rootHideReportedJailbroken;
    BOOL processRuntimeActive;
    BOOL processIsPlatform;
} RLXPostJailbreakRuntimeEvidence;

@interface RLXPostJailbreakController : NSObject

@property(nonatomic, strong, readonly) NSBundle *resourceBundle;

- (instancetype)initWithResourceBundle:(NSBundle *)resourceBundle NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (BOOL)isAvailable;
- (BOOL)hasActiveRootHideRuntime;
- (RLXPostJailbreakRuntimeEvidence)runtimeEvidence;
- (BOOL)compatibilityProfileEnabledForBundleIdentifier:(NSString *)bundleIdentifier
    NS_SWIFT_NAME(compatibilityProfileEnabled(bundleIdentifier:));

- (BOOL)tweakInjectionEnabled;
- (void)setTweakInjectionEnabled:(BOOL)enabled;

- (BOOL)appJITEnabled;
- (void)setAppJITEnabled:(BOOL)enabled;

- (void)performAction:(RLXPostJailbreakAction)action
        outputHandler:(nullable RLXPostJailbreakOutputHandler)outputHandler
           completion:(nullable RLXPostJailbreakCompletionHandler)completion
    NS_SWIFT_NAME(perform(action:output:completion:));

- (void)performAction:(RLXPostJailbreakAction)action
            arguments:(nullable NSDictionary<RLXPostJailbreakActionArgumentKey, NSString *> *)arguments
        outputHandler:(nullable RLXPostJailbreakOutputHandler)outputHandler
           completion:(nullable RLXPostJailbreakCompletionHandler)completion
    NS_SWIFT_NAME(perform(action:arguments:output:completion:));

@end

NS_ASSUME_NONNULL_END
