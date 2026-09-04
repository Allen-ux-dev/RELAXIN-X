#import <Foundation/Foundation.h>

#include <TargetConditionals.h>

NS_ASSUME_NONNULL_BEGIN

#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR

#pragma GCC visibility push(hidden)

int RLXPostJailbreakRestartSpringBoard(NSString *_Nullable __strong *_Nullable failurePhase);
NSError *_Nullable RLXPostJailbreakRestartUserspace(NSBundle *resourceBundle, BOOL darkAppearance);
int RLXPostJailbreakRefreshApps(NSString *_Nullable __strong *_Nullable failurePhase);
int RLXPostJailbreakResetMobilePassword(NSString *_Nullable __strong *_Nullable failurePhase);
NSError *_Nullable RLXPostJailbreakRemove(NSString *_Nullable __strong *_Nullable failurePhase);
int RLXPostJailbreakSetCompatibilityProfile(NSString *bundleIdentifier,
                                            BOOL enabled,
                                            NSString *_Nullable __strong *_Nullable failurePhase);

#pragma GCC visibility pop

#endif /* TARGET_OS_IOS && !TARGET_OS_SIMULATOR */

NS_ASSUME_NONNULL_END
