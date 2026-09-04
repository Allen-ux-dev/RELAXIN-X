//
//  appledb.m
//  libgrabkernel2
//
//  Created by Dhinak G on 3/4/24.
//

#import <Foundation/Foundation.h>
#import <sys/utsname.h>
#if !TARGET_OS_OSX
#import <UIKit/UIKit.h>
#endif
#import <sys/sysctl.h>
#import "utils.h"

#define BASE_URL @"https://api.appledb.dev/ios/"
#define ALL_VERSIONS BASE_URL @"main.json.xz"

static NSArray<NSString *> *hostsNeedingAuth(void) {
    static NSArray<NSString *> *hosts;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hosts = @[@"adcdownload.apple.com",
                  @"download.developer.apple.com",
                  @"developer.apple.com"];
    });
    return hosts;
}

static inline NSString *apiURLForBuild(NSString *osStr, NSString *build) {
    return [NSString stringWithFormat:@"https://api.appledb.dev/ios/%@;%@.json", osStr, build];
}

static NSData *makeSynchronousRequest(NSString *url, NSError **error) {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *data = nil;
    __block NSError *taskError = nil;
    // Ephemeral session: no HSTS/cookie/cache persistence
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    NSURLSessionDataTask *task = [session dataTaskWithURL:[NSURL URLWithString:url]
                                        completionHandler:^(NSData *taskData, NSURLResponse *response, NSError *error) {
                                            data = taskData;
                                            taskError = error;
                                            dispatch_semaphore_signal(semaphore);
                                        }];
    [task resume];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    [session invalidateAndCancel];

    if (error) {
        *error = taskError;
    }

    return data;
}

// Returns every usable firmware link, in source preference order, as
// @{@"url": NSString, @"ota": @(BOOL)}. Callers can then fall through
// candidates when a CDN edge or the network breaks one of them.
static NSArray<NSDictionary *> *linksFromSources(NSArray<NSDictionary<NSString *, id> *> *sources, NSString *modelIdentifier) {
    NSMutableArray<NSDictionary *> *links = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *source in sources) {
        if (![source[@"deviceMap"] containsObject:modelIdentifier]) {
            DBGLOG("Skipping source that does not include device: %s\n", [source[@"deviceMap"] componentsJoinedByString:@", "].UTF8String);
            continue;
        }

        if (![@[@"ota", @"ipsw"] containsObject:source[@"type"]]) {
            DBGLOG("Skipping source type: %s\n", [source[@"type"] UTF8String]);
            continue;
        }

        id prerequisiteBuild = source[@"prerequisiteBuild"];
        if ([source[@"type"] isEqualToString:@"ota"] && prerequisiteBuild) {
            // ignore deltas
            DBGLOG("Skipping OTA source with prerequisite build: %s\n", [prerequisiteBuild description].UTF8String);
            continue;
        }

        for (NSDictionary<NSString *, id> *link in source[@"links"]) {
            NSURL *url = [NSURL URLWithString:link[@"url"]];
            if ([hostsNeedingAuth() containsObject:url.host]) {
                DBGLOG("Skipping link that needs authentication: %s\n", url.absoluteString.UTF8String);
                continue;
            }

            if (![link[@"active"] boolValue]) {
                DBGLOG("Skipping inactive link: %s\n", url.absoluteString.UTF8String);
                continue;
            }

            bool isOTA = [source[@"type"] isEqualToString:@"ota"];
            [links addObject:@{@"url": link[@"url"], @"ota": @(isOTA)}];
        }

        if (!links.count) {
            DBGLOG("No suitable links found for source: %s\n", [source[@"name"] UTF8String]);
        }
    }

    return links;
}

static NSArray<NSDictionary *> *firmwareCandidatesFromAll(NSString *osStr,
                                                          NSString *build,
                                                          NSString *modelIdentifier,
                                                          NSError **error) {
    NSError *requestError = nil;
    NSData *compressed = makeSynchronousRequest(ALL_VERSIONS, &requestError);
    if (requestError) {
        ERRLOG("Failed to fetch API data: %s\n", requestError.localizedDescription.UTF8String);
        if (error) *error = requestError;
        return nil;
    }

    NSData *decompressed = [compressed decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZMA error:&requestError];
    if (requestError) {
        ERRLOG("Failed to decompress API data: %s\n", requestError.localizedDescription.UTF8String);
        if (error) *error = requestError;
        return nil;
    }

    NSArray *json = [NSJSONSerialization JSONObjectWithData:decompressed options:0 error:&requestError];
    if (requestError) {
        ERRLOG("Failed to parse API data: %s\n", requestError.localizedDescription.UTF8String);
        if (error) *error = requestError;
        return nil;
    }

    for (NSDictionary<NSString *, id> *firmware in json) {
        if ([firmware[@"osStr"] isEqualToString:osStr] && [firmware[@"build"] isEqualToString:build]) {
            NSArray<NSDictionary *> *links = linksFromSources(firmware[@"sources"], modelIdentifier);
            if (!links.count) {
                DBGLOG("No suitable links found for firmware: %s\n", [firmware[@"key"] UTF8String]);
            } else {
                return links;
            }
        }
    }

    return nil;
}

static NSArray<NSDictionary *> *firmwareCandidatesFromDirect(NSString *osStr,
                                                             NSString *build,
                                                             NSString *modelIdentifier,
                                                             NSError **error) {
    NSString *apiURL = apiURLForBuild(osStr, build);
    if (!apiURL) {
        ERRLOG("Failed to get API URL!\n");
        return nil;
    }

    NSError *requestError = nil;
    NSData *data = makeSynchronousRequest(apiURL, &requestError);
    if (requestError) {
        ERRLOG("Failed to fetch API data: %s\n", requestError.localizedDescription.UTF8String);
        if (error) *error = requestError;
        return nil;
    }

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&requestError];
    if (requestError) {
        ERRLOG("Failed to parse API data: %s\n", requestError.localizedDescription.UTF8String);
        if (error) *error = requestError;
        return nil;
    }

    NSArray<NSDictionary *> *links = linksFromSources(json[@"sources"], modelIdentifier);
    if (!links.count) {
        return nil;
    }

    return links;
}

NSArray<NSDictionary *> *getFirmwareURLCandidatesFor(NSString *osStr,
                                                      NSString *build,
                                                      NSString *modelIdentifier,
                                                      NSError **error) {
    NSError *directError = nil;
    NSArray<NSDictionary *> *candidates =
        firmwareCandidatesFromDirect(osStr, build, modelIdentifier, &directError);
    if (!candidates.count) {
        DBGLOG("Failed to get firmware URL from direct API, checking all versions...\n");
        NSError *fallbackError = nil;
        candidates =
            firmwareCandidatesFromAll(osStr, build, modelIdentifier, &fallbackError);
        if (!candidates.count && error) {
            *error = fallbackError ?: directError;
        }
    }

    if (!candidates.count) {
        ERRLOG("Failed to find a firmware URL!\n");
        return nil;
    }

    return candidates;
}

NSArray<NSDictionary *> *getFirmwareURLCandidates(NSError **error) {
    NSString *osStr = getOsStr();
    NSString *build = getBuild();
    NSString *modelIdentifier = getModelIdentifier();

    if (!osStr || !build || !modelIdentifier) {
        return nil;
    }

    return getFirmwareURLCandidatesFor(osStr, build, modelIdentifier, error);
}

NSString *getFirmwareURLFor(NSString *osStr, NSString *build, NSString *modelIdentifier, bool *isOTA) {
    NSArray<NSDictionary *> *candidates =
        getFirmwareURLCandidatesFor(osStr, build, modelIdentifier, nil);
    if (!candidates.count) {
        return nil;
    }

    if (isOTA) {
        *isOTA = [candidates.firstObject[@"ota"] boolValue];
    }
    LOG("Found firmware URL: %s (OTA: %s)\n", [candidates.firstObject[@"url"] UTF8String], (isOTA && *isOTA) ? "yes" : "no");
    return candidates.firstObject[@"url"];
}

NSString *getFirmwareURL(bool *isOTA) {
    NSString *osStr = getOsStr();
    NSString *build = getBuild();
    NSString *modelIdentifier = getModelIdentifier();

    if (!osStr || !build || !modelIdentifier) {
        return nil;
    }

    return getFirmwareURLFor(osStr, build, modelIdentifier, isOTA);
}
