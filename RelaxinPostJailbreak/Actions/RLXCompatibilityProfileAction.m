#import "RLXPostJailbreakActions.h"

#import "RLXPostJailbreakActionRunner.h"

#include <errno.h>

#include <libjailbreak/jbroot.h>

#if !TARGET_OS_SIMULATOR

static BOOL rlx_valid_bundle_identifier(NSString *bundleIdentifier) {
    if (bundleIdentifier.length == 0 || bundleIdentifier.length > 255) {
        return NO;
    }
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];
    return [bundleIdentifier rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

static BOOL rlx_protected_management_bundle(NSString *bundleIdentifier) {
    static NSSet<NSString *> *protectedBundles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        protectedBundles = [NSSet setWithArray:@[
            @"com.aapl.relaxin",
            @"org.coolstar.SileoStore",
            @"xyz.willy.Zebra",
            @"com.roothide.manager",
        ]];
    });
    return [protectedBundles containsObject:bundleIdentifier];
}

int RLXPostJailbreakSetCompatibilityProfile(NSString *bundleIdentifier,
                                            BOOL enabled,
                                            NSString *_Nullable __strong *_Nullable failurePhase) {
    if (!rlx_valid_bundle_identifier(bundleIdentifier)) {
        RLXPostJailbreakSetFailurePhase(failurePhase, @"validate_bundle_identifier");
        return EINVAL;
    }
    if (enabled && rlx_protected_management_bundle(bundleIdentifier)) {
        RLXPostJailbreakSetFailurePhase(failurePhase, @"protected_management_bundle");
        return EPERM;
    }

    return RLXPostJailbreakRunAsEffectiveRoot(
        ^int {
            return RLXPostJailbreakRunUnsandboxed(
                ^int {
                    NSString *directory = JBROOT_PATH(@"/var/mobile/Library/RootHide");
                    NSString *configPath = [directory stringByAppendingPathComponent:@"RootHideConfig.plist"];
                    NSFileManager *fileManager = NSFileManager.defaultManager;
                    NSError *directoryError = nil;
                    if (![fileManager fileExistsAtPath:directory]) {
                        NSDictionary *attributes = @{
                            NSFilePosixPermissions : @(0755),
                            NSFileOwnerAccountID : @(501),
                            NSFileGroupOwnerAccountID : @(501),
                        };
                        if (![fileManager createDirectoryAtPath:directory
                                   withIntermediateDirectories:YES
                                                    attributes:attributes
                                                         error:&directoryError]) {
                            RLXPostJailbreakSetFailurePhase(failurePhase, @"create_compatibility_directory");
                            return directoryError.code ?: EIO;
                        }
                    }

                    BOOL configExists = [fileManager fileExistsAtPath:configPath];
                    NSMutableDictionary *config = [NSMutableDictionary dictionaryWithContentsOfFile:configPath];
                    if (configExists && !config) {
                        RLXPostJailbreakSetFailurePhase(failurePhase, @"read_compatibility_config");
                        return EILSEQ;
                    }
                    if (!config) {
                        config = [NSMutableDictionary dictionary];
                    }

                    id existingAppConfig = config[@"appconfig"];
                    if (existingAppConfig && ![existingAppConfig isKindOfClass:NSDictionary.class]) {
                        RLXPostJailbreakSetFailurePhase(failurePhase, @"validate_compatibility_config");
                        return EILSEQ;
                    }
                    NSMutableDictionary *appConfig = existingAppConfig
                        ? [existingAppConfig mutableCopy]
                        : [NSMutableDictionary dictionary];
                    appConfig[bundleIdentifier] = @(enabled);
                    config[@"appconfig"] = appConfig;
                    if (![config writeToFile:configPath atomically:YES]) {
                        RLXPostJailbreakSetFailurePhase(failurePhase, @"write_compatibility_config");
                        return EIO;
                    }

                    NSDictionary *readBack = [NSDictionary dictionaryWithContentsOfFile:configPath];
                    NSNumber *readBackValue = readBack[@"appconfig"][bundleIdentifier];
                    if (!readBackValue || readBackValue.boolValue != enabled) {
                        RLXPostJailbreakSetFailurePhase(failurePhase, @"verify_compatibility_config");
                        return EIO;
                    }
                    return 0;
                },
                failurePhase);
        },
        failurePhase);
}

#endif /* !TARGET_OS_SIMULATOR */
