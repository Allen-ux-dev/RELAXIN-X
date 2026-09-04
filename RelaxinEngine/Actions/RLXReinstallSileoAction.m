//
//  RLXReinstallSileoAction.m
//  RelaxinEngine
//

#import "RLXActions.h"

#import "RLXActionRunner.h"
#import "../../RelaxinPostJailbreak/Actions/RLXPostJailbreakActionRunner.h"
#import "../Bootstrap/RLXBootstrapFinalizer.h"

#include <TargetConditionals.h>
#include <errno.h>

#include <libjailbreak/jbroot.h>

#if !TARGET_OS_SIMULATOR

NSError *_Nullable RLXReinstallSileo(NSBundle *resourceBundle, NSString *_Nullable __strong *_Nullable failurePhase) {
    __block NSError *installationError = nil;
    int status = RLXPostJailbreakRunAsEffectiveRoot(
        ^int {
            return RLXPostJailbreakRunUnsandboxed(
                ^int {
                    installationError = [RLXBootstrapFinalizer installBundledPackageNamed:@"sileo"
                                                                           resourceBundle:resourceBundle];
                    if (installationError) {
                        RLXPostJailbreakSetFailurePhase(failurePhase, @"install_sileo");
                        return EIO;
                    }
                    return 0;
                },
                failurePhase);
        },
        failurePhase);
    if (status == 0) {
        return nil;
    }
    return RLXActionExecutionError(RLXEngineActionReinstallSileo,
                                   failurePhase && *failurePhase ? *failurePhase : @"install_sileo",
                                   status,
                                   installationError);
}


NSError *_Nullable RLXReinstallZebra(NSString *packagePath,
                                     NSString *_Nullable __strong *_Nullable failurePhase) {
    __block NSError *installationError = nil;
    int status = RLXPostJailbreakRunAsEffectiveRoot(
        ^int {
            return RLXPostJailbreakRunUnsandboxed(
                ^int {
                    installationError = [RLXBootstrapFinalizer installExternalPackageAtPath:packagePath];
                    if (installationError) {
                        RLXPostJailbreakSetFailurePhase(failurePhase, @"install_zebra");
                        return EIO;
                    }
                    return 0;
                },
                failurePhase);
        },
        failurePhase);
    if (status == 0) {
        return nil;
    }
    return RLXActionExecutionError(RLXEngineActionReinstallZebra,
                                   failurePhase && *failurePhase ? *failurePhase : @"install_zebra",
                                   status,
                                   installationError);
}

static NSString *rlx_repair_sources_contents(NSString *packageManager) {
    if ([packageManager isEqualToString:@"sileo"]) {
        // Keep this content aligned with RLXBootstrapPreparer's initial sources.
        return @"Types: deb\n"
               "URIs: https://apt.82flex.com/\n"
               "Suites: ./\n"
               "Components:\n\n"
               "Types: deb\n"
               "URIs: https://github.com/roothide/roothide.github.io/releases/download/1900/\n"
               "Suites: ./\n"
               "Components:\n";
    }
    if ([packageManager isEqualToString:@"zebra"]) {
        return @"# Zebra Sources List\n"
               "deb https://apt.82flex.com/ ./\n"
               "deb https://getzbra.com/repo/ ./\n"
               "deb https://repo.chariz.com/ ./\n"
               "deb https://yourepo.com/ ./\n"
               "deb https://havoc.app/ ./\n"
               "deb https://roothide.github.io/ ./\n"
               "deb https://roothide.github.io/procursus iphoneos-arm64e/1900 main\n"
               "deb https://github.com/roothide/roothide.github.io/releases/download/1900/ ./\n\n";
    }
    return nil;
}

NSError *_Nullable RLXRepairPackageSources(NSString *packageManager,
                                            NSString *_Nullable __strong *_Nullable failurePhase) {
    NSString *contents = rlx_repair_sources_contents(packageManager);
    if (!contents) {
        return RLXActionExecutionError(RLXEngineActionRepairPackageSources,
                                       @"validate_package_manager",
                                       EINVAL,
                                       nil);
    }

    __block NSError *writeError = nil;
    int status = RLXPostJailbreakRunAsEffectiveRoot(
        ^int {
            return RLXPostJailbreakRunUnsandboxed(
                ^int {
                    NSString *relativePath = [packageManager isEqualToString:@"sileo"]
                        ? @"/etc/apt/sources.list.d/sileo.sources"
                        : @"/var/mobile/Library/Application Support/xyz.willy.Zebra/sources.list";
                    NSString *path = JBROOT_PATH(relativePath);
                    NSString *directory = path.stringByDeletingLastPathComponent;
                    if (![NSFileManager.defaultManager createDirectoryAtPath:directory
                                                  withIntermediateDirectories:YES
                                                                   attributes:nil
                                                                        error:&writeError]) {
                        RLXPostJailbreakSetFailurePhase(failurePhase, @"create_sources_directory");
                        return EIO;
                    }
                    if (![contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
                        RLXPostJailbreakSetFailurePhase(failurePhase, @"write_package_sources");
                        return EIO;
                    }
                    return 0;
                },
                failurePhase);
        },
        failurePhase);
    if (status == 0) {
        return nil;
    }
    return RLXActionExecutionError(RLXEngineActionRepairPackageSources,
                                   failurePhase && *failurePhase ? *failurePhase : @"write_package_sources",
                                   status,
                                   writeError);
}

#endif /* !TARGET_OS_SIMULATOR */
