#import "RLXBootstrapEnvironmentInspector.h"

#include <errno.h>
#include <stdint.h>
#include <stdlib.h>

static NSString *const RLXPrimaryRootDirectory = @"/var/containers/Bundle/Application";
static NSString *const RLXSecondaryRootDirectory = @"/var/mobile/Containers/Shared/AppGroup";
static NSString *const RLXInstalledMarker = @".installed_relaxin";

static BOOL rlx_environment_root_name_is_valid(NSString *name) {
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

    uint8_t checksum = (uint8_t)(value >> 8) ^ (uint8_t)(value >> 16) ^ (uint8_t)(value >> 24)
        ^ (uint8_t)(value >> 32) ^ (uint8_t)(value >> 40) ^ (uint8_t)(value >> 48)
        ^ (uint8_t)(value >> 56);
    return checksum == (uint8_t)value;
}

@interface RLXBootstrapEnvironmentEvidence ()
@property(nonatomic, readwrite) NSUInteger candidateCount;
@property(nonatomic, readwrite) BOOL hasInstalledRelaxinMarker;
@property(nonatomic, copy, readwrite, nullable) NSString *installedRootPath;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *candidateRootPaths;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *findings;
@end

@implementation RLXBootstrapEnvironmentEvidence
@end

@implementation RLXBootstrapEnvironmentInspector

+ (RLXBootstrapEnvironmentEvidence *)inspectContainerRoots:(NSArray<NSString *> *)roots
                                                     error:(NSError *_Nullable *_Nullable)error {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSMutableOrderedSet<NSString *> *candidateNames = [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet<NSString *> *candidatePaths = [NSMutableOrderedSet orderedSet];
    NSMutableDictionary<NSString *, NSString *> *installedRootsByName = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *findings = [NSMutableArray array];

    NSArray<NSString *> *incompatibleMarkers = @[
        @".bootstrapped",
        @".thebootstrapped",
    ];

    for (NSString *containerRoot in roots) {
        NSError *listingError = nil;
        NSArray<NSString *> *items = [fileManager contentsOfDirectoryAtPath:containerRoot error:&listingError];
        if (!items) {
            if (listingError.code != NSFileReadNoSuchFileError
                && listingError.code != NSFileNoSuchFileError) {
                if (error) {
                    *error = listingError;
                }
                return [[RLXBootstrapEnvironmentEvidence alloc] init];
            }
            [findings addObject:[NSString stringWithFormat:@"container_missing:%@", containerRoot]];
            continue;
        }

        for (NSString *item in items) {
            if (!rlx_environment_root_name_is_valid(item)) {
                continue;
            }

            NSString *candidate = [containerRoot stringByAppendingPathComponent:item];
            [candidateNames addObject:item];
            [candidatePaths addObject:candidate];
            for (NSString *incompatibleMarker in incompatibleMarkers) {
                NSString *incompatiblePath = [candidate stringByAppendingPathComponent:incompatibleMarker];
                if ([fileManager fileExistsAtPath:incompatiblePath]) {
                    [findings addObject:[NSString
                        stringWithFormat:@"conflicting_marker:%@:%@", incompatibleMarker, candidate]];
                }
            }

            NSString *marker = [candidate stringByAppendingPathComponent:RLXInstalledMarker];
            if ([fileManager fileExistsAtPath:marker] && !installedRootsByName[item]) {
                installedRootsByName[item] = candidate;
            }
        }
    }

    for (NSString *candidateName in candidateNames) {
        if (!installedRootsByName[candidateName]) {
            [findings addObject:[NSString stringWithFormat:@"candidate_without_marker:%@", candidateName]];
        }
    }

    RLXBootstrapEnvironmentEvidence *evidence = [[RLXBootstrapEnvironmentEvidence alloc] init];
    evidence.candidateCount = candidateNames.count;
    evidence.candidateRootPaths = candidatePaths.array;
    evidence.hasInstalledRelaxinMarker = installedRootsByName.count > 0;
    if (installedRootsByName.count == 1) {
        evidence.installedRootPath = installedRootsByName.allValues.firstObject;
    } else if (installedRootsByName.count > 1) {
        [findings addObject:[NSString stringWithFormat:@"multiple_installed_roots:%lu",
                                                       (unsigned long)installedRootsByName.count]];
    }
    evidence.findings = findings.copy;
    return evidence;
}

+ (RLXBootstrapEnvironmentEvidence *_Nullable)inspectSystemContainerRootsWithError:
    (NSError *_Nullable *_Nullable)error {
    NSError *inspectionError = nil;
    RLXBootstrapEnvironmentEvidence *evidence = [self
        inspectContainerRoots:@[RLXPrimaryRootDirectory, RLXSecondaryRootDirectory]
                       error:&inspectionError];
    if (inspectionError) {
        if (error) {
            *error = inspectionError;
        }
        return nil;
    }
    return evidence;
}

@end
