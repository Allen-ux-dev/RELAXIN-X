//
//  RLXActions.h
//  RelaxinEngine
//
//  Full-engine actions that are not part of RelaxinPostJailbreak.
//

#import <Foundation/Foundation.h>

#import "RLXEngine+Actions.h"

#include <TargetConditionals.h>

NS_ASSUME_NONNULL_BEGIN

#if !TARGET_OS_SIMULATOR

#pragma GCC visibility push(hidden)

NSError *_Nullable RLXReinstallSileo(NSBundle *resourceBundle, NSString *_Nullable __strong *_Nullable failurePhase);
NSError *_Nullable RLXReinstallZebra(NSString *packagePath, NSString *_Nullable __strong *_Nullable failurePhase);
NSError *_Nullable RLXRepairPackageSources(NSString *packageManager, NSString *_Nullable __strong *_Nullable failurePhase);

#pragma GCC visibility pop

#endif /* !TARGET_OS_SIMULATOR */

NS_ASSUME_NONNULL_END
