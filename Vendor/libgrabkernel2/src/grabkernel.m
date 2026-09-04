//
//  grabkernel.c
//  libgrabkernel2
//
//  Created by Alfie on 14/02/2024.
//

#include <Foundation/Foundation.h>
#include <CommonCrypto/CommonDigest.h>
#include <libgrabkernel2/libgrabkernel2.h>
#include <partial/partial.h>
#include <unistd.h>
#include "appledb.h"
#include "utils.h"

static NSError *grabKernelError(NSString *description,
                                NSError *underlyingError) {
    NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo =
        [@{NSLocalizedDescriptionKey: description} mutableCopy];
    if (underlyingError) {
        userInfo[NSLocalizedFailureReasonErrorKey] =
            underlyingError.localizedDescription;
        userInfo[NSUnderlyingErrorKey] = underlyingError;
    }
    return [NSError errorWithDomain:@"libgrabkernel2"
                              code:1
                          userInfo:userInfo];
}

static void setGrabKernelError(NSError **outputError, NSError *error) {
    if (outputError) {
        *outputError = error;
    }
}

static void deleteCachedHSTS(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    if (!bundleID) {
        return;
    }

    NSString *hstsPath = [NSHomeDirectory()
        stringByAppendingPathComponent:[NSString
                                           stringWithFormat:
                                               @"Library/Caches/%@/HSTS.plist",
                                               bundleID]];
    if ([NSFileManager.defaultManager fileExistsAtPath:hstsPath]
        && [NSFileManager.defaultManager removeItemAtPath:hstsPath
                                                    error:nil]) {
        LOG("Removed cached HSTS.plist\n");
    }
}

static NSDictionary<NSString *, id> *
kernelcacheIdentityFromManifest(NSData *buildManifestData,
                                NSString *boardconfig,
                                NSString *pathPrefix,
                                NSString *expectedBuild,
                                NSString *expectedModelIdentifier,
                                NSError **error) {
    NSDictionary *buildManifest =
        [NSPropertyListSerialization propertyListWithData:buildManifestData
                                                  options:0
                                                   format:NULL
                                                    error:error];
    if (!buildManifest) {
        return nil;
    }
    if (expectedBuild.length > 0
        && ![buildManifest[@"ProductBuildVersion"]
            isEqual:expectedBuild]) {
        setGrabKernelError(
            error,
            grabKernelError(
                @"The firmware manifest build does not match the requested target.",
                nil));
        return nil;
    }
    NSArray *supportedProductTypes =
        buildManifest[@"SupportedProductTypes"];
    if (expectedModelIdentifier.length > 0
        && (![supportedProductTypes isKindOfClass:NSArray.class]
            || ![supportedProductTypes
                containsObject:expectedModelIdentifier])) {
        setGrabKernelError(
            error,
            grabKernelError(
                @"The firmware manifest does not support the requested device.",
                nil));
        return nil;
    }

    for (NSDictionary<NSString *, id> *identity
         in buildManifest[@"BuildIdentities"]) {
        if ([identity[@"Info"][@"Variant"] hasPrefix:@"Research"]) {
            continue;
        }
        if ([identity[@"Info"][@"DeviceClass"]
                isEqualToString:boardconfig.lowercaseString]) {
            NSDictionary<NSString *, id> *kernelcache =
                identity[@"Manifest"][@"KernelCache"];
            NSString *manifestPath = kernelcache[@"Info"][@"Path"];
            NSString *path =
                [manifestPath isKindOfClass:NSString.class]
                ? [pathPrefix stringByAppendingPathComponent:manifestPath]
                : nil;
            NSData *digest = kernelcache[@"Digest"];
            if (path.length > 0 && [digest isKindOfClass:NSData.class]) {
                return @{
                    @"path": path,
                    @"digest": digest,
                };
            }
        }
    }
    return nil;
}

static NSData *kernelcacheDigest(NSData *data, NSUInteger digestLength) {
    if (data.length == 0 || data.length > UINT32_MAX) {
        return nil;
    }

    unsigned char digest[CC_SHA512_DIGEST_LENGTH] = {0};
    switch (digestLength) {
        case CC_SHA1_DIGEST_LENGTH:
            CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
            break;
        case CC_SHA256_DIGEST_LENGTH:
            CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
            break;
        case CC_SHA384_DIGEST_LENGTH:
            CC_SHA384(data.bytes, (CC_LONG)data.length, digest);
            break;
        default:
            return nil;
    }
    return [NSData dataWithBytes:digest length:digestLength];
}

bool verify_kernelcache_digest(NSString *path,
                               NSData *expectedDigest,
                               NSError **error) {
    NSError *attributeError = nil;
    NSDictionary<NSFileAttributeKey, id> *attributes =
        [NSFileManager.defaultManager attributesOfItemAtPath:path
                                                       error:&attributeError];
    unsigned long long fileSize =
        [attributes[NSFileSize] unsignedLongLongValue];
    if (attributeError
        || ![attributes[NSFileType] isEqualToString:NSFileTypeRegular]
        || fileSize == 0
        || fileSize > UINT32_MAX) {
        setGrabKernelError(
            error,
            grabKernelError(
                @"The kernelcache is not a supported nonempty regular file.",
                attributeError));
        return false;
    }

    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile:path
                                         options:NSDataReadingMappedIfSafe
                                           error:&readError];
    NSData *actualDigest =
        kernelcacheDigest(data, expectedDigest.length);
    if (actualDigest
        && [actualDigest isEqualToData:expectedDigest]) {
        return true;
    }

    NSString *description = readError
        ? @"The kernelcache could not be read for digest verification."
        : @"The kernelcache does not match its firmware manifest digest.";
    setGrabKernelError(error, grabKernelError(description, readError));
    return false;
}

static bool downloadKernelcacheRange(NSString *boardconfig,
                                     NSString *zipURL,
                                     bool isOTA,
                                     NSString *outPath,
                                     NSString *expectedBuild,
                                     NSString *expectedModelIdentifier,
                                     NSData **outputDigest,
                                     NSError **outputError) {
    NSError *error = nil;
    NSString *pathPrefix = isOTA ? @"AssetData/boot" : @"";

    Partial *zip =
        [Partial partialZipWithURL:[NSURL URLWithString:zipURL] error:&error];
    if (!zip) {
        WARNLOG("Range download could not open zip file: %s\n",
                error.localizedDescription.UTF8String);
        setGrabKernelError(
            outputError,
            grabKernelError(@"Failed to open the firmware archive.", error));
        return false;
    }

    LOG("Downloading BuildManifest.plist...\n");

    NSData *buildManifestData =
        [zip getFileForPath:[pathPrefix
                                stringByAppendingPathComponent:
                                    @"BuildManifest.plist"]
                      error:&error];
    if (!buildManifestData) {
        WARNLOG("Range download could not fetch BuildManifest.plist: %s\n",
                error.localizedDescription.UTF8String);
        setGrabKernelError(
            outputError,
            grabKernelError(@"Failed to download BuildManifest.plist.",
                            error));
        return false;
    }

    NSDictionary<NSString *, id> *kernelcacheIdentity =
        kernelcacheIdentityFromManifest(buildManifestData,
                                        boardconfig,
                                        pathPrefix,
                                        expectedBuild,
                                        expectedModelIdentifier,
                                        &error);
    NSString *kernelCachePath = kernelcacheIdentity[@"path"];
    NSData *expectedDigest = kernelcacheIdentity[@"digest"];
    if (!kernelcacheIdentity) {
        WARNLOG(
            "Range download found no verifiable matching kernelcache in "
            "BuildManifest.plist.\n");
        setGrabKernelError(
            outputError,
            grabKernelError(
                @"The firmware manifest does not contain a matching kernelcache and digest.",
                error));
        return false;
    }

    LOG("Downloading %s to %s...\n",
        kernelCachePath.UTF8String,
        outPath.UTF8String);

    NSData *kernelCacheData =
        [zip getFileForPath:kernelCachePath error:&error];
    if (!kernelCacheData) {
        WARNLOG("Range download could not fetch kernelcache: %s\n",
                error.localizedDescription.UTF8String);
        setGrabKernelError(
            outputError,
            grabKernelError(@"Failed to download the kernelcache.", error));
        return false;
    }

    NSData *actualDigest =
        kernelcacheDigest(kernelCacheData, expectedDigest.length);
    if (!actualDigest
        || ![actualDigest isEqualToData:expectedDigest]) {
        WARNLOG("Downloaded kernelcache failed manifest digest verification.\n");
        setGrabKernelError(
            outputError,
            grabKernelError(
                @"The downloaded kernelcache does not match its firmware manifest digest.",
                nil));
        return false;
    }

    if (![kernelCacheData writeToFile:outPath
                              options:NSDataWritingAtomic
                                error:&error]) {
        WARNLOG("Range download could not write kernelcache to %s: %s\n",
                outPath.UTF8String,
                error.localizedDescription.UTF8String);
        setGrabKernelError(
            outputError,
            grabKernelError(@"Failed to write the downloaded kernelcache.",
                            error));
        return false;
    }

    if (outputDigest) {
        *outputDigest = expectedDigest;
    }
    LOG("Downloaded kernelcache!\n");
    return true;
}

static bool downloadKernelcacheWithRetries(NSString *boardconfig,
                                           NSString *zipURL,
                                           bool isOTA,
                                           NSString *outPath,
                                           NSString *expectedBuild,
                                           NSString *expectedModelIdentifier,
                                           NSData **outputDigest,
                                           NSError **outputError) {
    if (!zipURL) {
        ERRLOG("Missing firmware URL!\n");
        setGrabKernelError(
            outputError,
            grabKernelError(@"No firmware download URL was available.", nil));
        return false;
    }

    if (!outPath) {
        ERRLOG("Missing output path!\n");
        setGrabKernelError(
            outputError,
            grabKernelError(@"No kernelcache output path was provided.", nil));
        return false;
    }

    if (![NSFileManager.defaultManager
            isWritableFileAtPath:outPath.stringByDeletingLastPathComponent]) {
        ERRLOG("Output directory is not writable!\n");
        setGrabKernelError(
            outputError,
            grabKernelError(
                @"The kernelcache output directory is not writable.",
                nil));
        return false;
    }

    for (int attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) {
            LOG("Retrying range download (attempt %d/3)...\n", attempt + 1);
            sleep(1);
        }
        if (downloadKernelcacheRange(boardconfig,
                                     zipURL,
                                     isOTA,
                                     outPath,
                                     expectedBuild,
                                     expectedModelIdentifier,
                                     outputDigest,
                                     outputError)) {
            return true;
        }
    }
    return false;
}

bool download_kernelcache_for(NSString *boardconfig,
                              NSString *zipURL,
                              bool isOTA,
                              NSString *outPath) {
    return downloadKernelcacheWithRetries(boardconfig,
                                          zipURL,
                                          isOTA,
                                          outPath,
                                          nil,
                                          nil,
                                          nil,
                                          nil);
}

bool download_kernelcache(NSString *zipURL,
                          bool isOTA,
                          NSString *outPath) {
    NSString *boardconfig = getBoardconfig();
    if (!boardconfig) {
        ERRLOG("Failed to get boardconfig!\n");
        return false;
    }

    return downloadKernelcacheWithRetries(boardconfig,
                                          zipURL,
                                          isOTA,
                                          outPath,
                                          getBuild(),
                                          getModelIdentifier(),
                                          nil,
                                          nil);
}

static bool grabKernelcacheWithCandidates(NSString *boardconfig,
                                          NSArray<NSDictionary *> *candidates,
                                          NSString *outPath,
                                          NSString *expectedBuild,
                                          NSString *expectedModelIdentifier,
                                          NSData **outputDigest,
                                          NSError **outputError) {
    if (!candidates.count) {
        ERRLOG("Failed to get firmware URL!\n");
        setGrabKernelError(
            outputError,
            grabKernelError(@"No firmware download URL was available.", nil));
        return false;
    }

    NSError *lastError = nil;
    for (NSDictionary *candidate in candidates) {
        NSString *url = candidate[@"url"];
        bool isOTA = [candidate[@"ota"] boolValue];
        NSError *attemptError = nil;
        LOG("Trying firmware URL: %s (OTA: %s)\n",
            url.UTF8String,
            isOTA ? "yes" : "no");
        if (downloadKernelcacheWithRetries(boardconfig,
                                           url,
                                           isOTA,
                                           outPath,
                                           expectedBuild,
                                           expectedModelIdentifier,
                                           outputDigest,
                                           &attemptError)) {
            return true;
        }
        lastError = attemptError;
    }

    NSError *error = grabKernelError(
        @"The kernelcache could not be downloaded without fetching the full "
         "firmware archive.",
        lastError);
    setGrabKernelError(outputError, error);
    ERRLOG("All range-download candidates failed; full firmware downloads are "
           "disabled: %s\n",
           lastError.localizedDescription.UTF8String);
    return false;
}

// TODO: Only require one of model identifier/boardconfig and use API to get
// the other?
bool grab_kernelcache_for(NSString *osStr,
                          NSString *build,
                          NSString *modelIdentifier,
                          NSString *boardconfig,
                          NSString *outPath) {
    return grab_kernelcache_for_with_error(
        osStr, build, modelIdentifier, boardconfig, outPath, nil);
}

bool grab_kernelcache_for_with_error(NSString *osStr,
                                     NSString *build,
                                     NSString *modelIdentifier,
                                     NSString *boardconfig,
                                     NSString *outPath,
                                     NSError **error) {
    return grab_kernelcache_for_with_digest(osStr,
                                            build,
                                            modelIdentifier,
                                            boardconfig,
                                            outPath,
                                            nil,
                                            error);
}

bool grab_kernelcache_for_with_digest(NSString *osStr,
                                      NSString *build,
                                      NSString *modelIdentifier,
                                      NSString *boardconfig,
                                      NSString *outPath,
                                      NSData **expectedDigest,
                                      NSError **error) {
    deleteCachedHSTS();

    NSError *candidateError = nil;
    NSArray *candidates = getFirmwareURLCandidatesFor(
        osStr, build, modelIdentifier, &candidateError);
    if (!candidates.count && candidateError) {
        setGrabKernelError(
            error,
            grabKernelError(@"Failed to obtain firmware download information.",
                            candidateError));
        return false;
    }
    return grabKernelcacheWithCandidates(
        boardconfig,
        candidates,
        outPath,
        build,
        modelIdentifier,
        expectedDigest,
        error);
}

bool grab_kernelcache(NSString *outPath) {
    deleteCachedHSTS();

    NSString *boardconfig = getBoardconfig();
    if (!boardconfig) {
        ERRLOG("Failed to get boardconfig!\n");
        return false;
    }

    NSArray *candidates = getFirmwareURLCandidates(nil);
    return grabKernelcacheWithCandidates(boardconfig,
                                         candidates,
                                         outPath,
                                         getBuild(),
                                         getModelIdentifier(),
                                         nil,
                                         nil);
}

bool grab_kernelcache_for_build_number(NSString *build, NSString *outPath) {
    deleteCachedHSTS();

    NSString *boardconfig = getBoardconfig();
    if (!boardconfig) {
        ERRLOG("Failed to get boardconfig!\n");
        return false;
    }

    NSArray *candidates =
        getFirmwareURLCandidatesFor(getOsStr(),
                                    build,
                                    getModelIdentifier(),
                                    nil);
    return grabKernelcacheWithCandidates(boardconfig,
                                         candidates,
                                         outPath,
                                         build,
                                         getModelIdentifier(),
                                         nil,
                                         nil);
}

// libgrabkernel compatibility shim
// Note that research kernel grabbing is not currently supported
int grabkernel(char *downloadPath, int isResearchKernel __unused) {
    NSString *outPath =
        [NSString stringWithCString:downloadPath
                          encoding:NSUTF8StringEncoding];
    return grab_kernelcache(outPath) ? 0 : -1;
}
