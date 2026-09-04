//
//  RLXBootstrapRootScanner.m
//  RelaxinEngine
//

#import "RLXBootstrapRootScanner.h"

#import "RLXBootstrapPreparationError.h"
#import "../Log/RLXEngineLog.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static NSString *const RLXPrimaryRootDirectory = @"/var/containers/Bundle/Application";
static NSString *const RLXSecondaryRootDirectory = @"/var/mobile/Containers/Shared/AppGroup";
static NSString *const RLXInstalledMarker = @".installed_relaxin";

@implementation RLXBootstrapRootScanner

- (BOOL)scanJailbreakRootsWithInstalledRoot:(NSString *_Nullable *_Nonnull)installedRoot
                                      error:(NSError *_Nullable *_Nullable)error {
    NSArray<NSString *> *items = [NSFileManager.defaultManager contentsOfDirectoryAtPath:RLXPrimaryRootDirectory
                                                                                   error:nil];

    NSMutableArray<NSString *> *installedRoots = [NSMutableArray array];
    NSArray<NSString *> *incompatibleMarkers = @[
        @".bootstrapped",
        @".thebootstrapped",
    ];
    for (NSString *item in items) {
        uint64_t brand = 0;
        if (![self rootName:item containsBrand:&brand]) {
            continue;
        }

        NSString *root = [RLXPrimaryRootDirectory stringByAppendingPathComponent:item];
        for (NSString *marker in incompatibleMarkers) {
            NSString *markerPath = [root stringByAppendingPathComponent:marker];
            if ([NSFileManager.defaultManager fileExistsAtPath:markerPath]) {
                if (error) {
                    *error = rlx_bootstrap_preparation_error(@"reject_bootstrap_app_jbroot",
                                                             EEXIST,
                                                             [NSString
                                                                 stringWithFormat:@"root=%@\nmarker=%@", root, marker],
                                                             nil);
                }
                return NO;
            }
        }

        NSString *installedPath = [root stringByAppendingPathComponent:RLXInstalledMarker];
        if ([NSFileManager.defaultManager fileExistsAtPath:installedPath]) {
            [installedRoots addObject:root];
            continue;
        }

        NSString *secondary = [self secondaryRootForBrand:brand];
        NSError *removeError = nil;
        if ([NSFileManager.defaultManager fileExistsAtPath:secondary]
            && ![NSFileManager.defaultManager removeItemAtPath:secondary error:&removeError]) {
            if (error) {
                *error = rlx_bootstrap_preparation_error(@"discard_incomplete_jbroot",
                                                         rlx_status_for_error(removeError),
                                                         [NSString stringWithFormat:@"root=%@\n" "secondary_root=%@",
                                                                                    root,
                                                                                    secondary],
                                                         removeError);
            }
            return NO;
        }
        if (![NSFileManager.defaultManager removeItemAtPath:root error:&removeError]) {
            if (error) {
                *error = rlx_bootstrap_preparation_error(@"discard_incomplete_jbroot",
                                                         rlx_status_for_error(removeError),
                                                         [NSString stringWithFormat:@"root=%@\n" "secondary_root=%@",
                                                                                    root,
                                                                                    secondary],
                                                         removeError);
            }
            return NO;
        }
        NSString *message = [NSString stringWithFormat:@"discarded incomplete root=%@", root];
        rlx_engine_log(RLX_ENGINE_LOG_VERBOSE, "RLXBootstrapPreparation", message.UTF8String);
    }

    if (installedRoots.count > 1) {
        if (error) {
            *error = rlx_bootstrap_preparation_error(@"reject_multiple_jbroots",
                                                     EEXIST,
                                                     [NSString stringWithFormat:@"roots=%@",
                                                                                [installedRoots
                                                                                    componentsJoinedByString:@","]],
                                                     nil);
        }
        return NO;
    }

    *installedRoot = installedRoots.firstObject;
    return YES;
}

- (BOOL)rootName:(NSString *)name containsBrand:(uint64_t *)brand {
    static NSString *const prefix = @".jbroot-";
    if (name.length != prefix.length + 16 || ![name hasPrefix:prefix]) {
        return NO;
    }

    const char *text = [name substringFromIndex:prefix.length].UTF8String;
    errno = 0;
    char *end = NULL;
    uint64_t value = strtoull(text, &end, 16);
    if (errno != 0 || !end || *end != '\0') {
        return NO;
    }

    uint8_t checksum = (uint8_t)(value >> 8) ^ (uint8_t)(value >> 16) ^ (uint8_t)(value >> 24) ^ (uint8_t)(value >> 32)
        ^ (uint8_t)(value >> 40) ^ (uint8_t)(value >> 48) ^ (uint8_t)(value >> 56);
    if (checksum != (uint8_t)value) {
        return NO;
    }
    if (brand) {
        *brand = value;
    }
    return YES;
}

- (uint64_t)generateBrand {
    uint64_t value = (uint64_t)arc4random() | ((uint64_t)arc4random() << 32);
    uint8_t checksum = (uint8_t)(value >> 8) ^ (uint8_t)(value >> 16) ^ (uint8_t)(value >> 24) ^ (uint8_t)(value >> 32)
        ^ (uint8_t)(value >> 40) ^ (uint8_t)(value >> 48) ^ (uint8_t)(value >> 56);
    return (value & ~UINT64_C(0xFF)) | checksum;
}

- (NSString *)primaryRootForBrand:(uint64_t)brand {
    return [RLXPrimaryRootDirectory
        stringByAppendingPathComponent:[NSString stringWithFormat:@".jbroot-%016llX", (unsigned long long)brand]];
}

- (NSString *)secondaryRootForBrand:(uint64_t)brand {
    return [RLXSecondaryRootDirectory
        stringByAppendingPathComponent:[NSString stringWithFormat:@".jbroot-%016llX", (unsigned long long)brand]];
}

@end
