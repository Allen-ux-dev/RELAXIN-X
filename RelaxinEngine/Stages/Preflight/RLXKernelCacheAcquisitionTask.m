//
//  RLXKernelCacheAcquisitionTask.m
//  RelaxinEngine
//

#import "RLXKernelCacheAcquisitionTask.h"

#import <errno.h>
#import <fcntl.h>
#import <IOKit/IOKitLib.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <unistd.h>

#import <libgrabkernel2/libgrabkernel2.h>

#import "../../Engine/RLXEngine.h"
#import "../../Engine/RLXEngineEnvironment.h"
#import "../../Diagnostic/RLXEngineDiagnostic.h"
#import "../../Engine/RLXEngineError.h"
#import "../../KernelAccess/Analysis/RLXKernelOffsetTable.h"
#import "../../Log/RLXEngineLog.h"
#import "../../Engine/RLXEngineRunContext.h"

static NSString *const RLXKernelcacheName = @"kernelcache";

@interface RLXKernelCacheAcquisitionTask ()

- (BOOL)isUsableKernelcacheAtPath:(NSString *)path;
- (nullable NSString *)kernelcachePathInDirectory:(NSString *)directoryPath;
- (nullable NSString *)systemKernelcachePath;
- (nullable NSString *)stringForSysctlName:(const char *)name;
- (nullable NSString *)osNameForDeviceIdentifier:(NSString *)deviceIdentifier;
- (nullable NSString *)downloadedKernelcacheForTarget:(NSDictionary<RLXEngineManifestKey, NSString *> *)target
                                          offsetTable:(RLXKernelOffsetTable *)offsetTable
                                                error:(NSError *_Nullable *_Nullable)error;

@end

@implementation RLXKernelCacheAcquisitionTask

- (instancetype)initWithContext:(RLXEngineRunContext *)context {
    return [super initWithStage:RLXEngineStageKernelCacheAcquisition context:context];
}

- (nullable NSError *)execute {
    NSDictionary<RLXEngineManifestKey, NSString *> *target = self.context.confirmedTarget;
    if (!target) {
        RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnosticWithStage:@"obtain_kernelcache"];
        [diagnostic appendKey:@"confirmed_target" boolValue:NO];
        return [RLXEngineError errorWithCode:RLXEngineErrorCodeInvalidAction
                                 description:@"The kernelcache task has no confirmed target."
                               failureReason:nil
                          recoverySuggestion:@"Run target confirmation before obtaining the kernelcache."
                                  diagnostic:diagnostic];
    }

    RLXRuntimeEnvironment *runtimeEnvironment = self.context.runtimeEnvironment;
    NSBundle *resourceBundle = runtimeEnvironment.resourceBundle;
    RLXKernelOffsetTable *offsetTable = [[RLXKernelOffsetTable alloc] initWithResourceBundle:resourceBundle];

    NSString *kernelcachePath = [self systemKernelcachePath];
    if (!kernelcachePath) {
        kernelcachePath = [self kernelcachePathInDirectory:resourceBundle.bundlePath];
    }
    if (!kernelcachePath) {
        kernelcachePath = [self kernelcachePathInDirectory:runtimeEnvironment.dataDirectoryURL.path];
    }

    /*
     * Prefer every usable kernelcache already on the device. Only after those
     * sources miss, use a shipped profile to avoid the otherwise necessary
     * network transfer. The profile contains the offsets that would have been
     * read from the kernelcache for exactly this device and build, so nothing
     * downstream needs the downloaded file itself.
     *
     * It has to fit this chip, though. A12's DMA backend does not need GFX
     * offsets; every direct-GFX backend does. Rejecting an incomplete profile
     * here lets the real download and analysis remain the fallback.
     */
    if (!kernelcachePath) {
        NSString *deviceIdentifier = target[RLXEngineManifestTargetDeviceIdentifierKey];
        NSString *osBuild = target[RLXEngineManifestTargetOSBuildKey];
        uint32_t cpuFamily = (uint32_t)strtoul(target[RLXEngineManifestTargetCPUFamilyKey].UTF8String ?: "0", NULL, 0);
        RLXKernelOffsetProfile *profile = [offsetTable profileForDeviceIdentifier:deviceIdentifier osBuild:osBuild];
        if (profile && ![profile supportsCPUFamily:cpuFamily]) {
            NSString *message = [NSString
                stringWithFormat:
                    @"kernelcache offsets rejected device=%@ build=%@ " "cpu_family=0x%08X gfx_offsets=%d kernelcache=%@",
                    deviceIdentifier,
                    osBuild,
                    cpuFamily,
                    profile.hasGFXOffsets,
                    profile.kernelcacheDigest];
            rlx_engine_log(RLX_ENGINE_LOG_INFO, "RLXEngine", message.UTF8String);
            profile = nil;
        }
        if (profile) {
            self.context.kernelOffsetProfile = profile;
            NSString *message = [NSString
                stringWithFormat:
                    @"kernelcache offsets from table device=%@ build=%@ " "xnu=%@ static_base=0x%llx sptm=%d kernelcache=%@",
                    profile.deviceIdentifier,
                    profile.osBuild,
                    profile.xnuBuild,
                    profile.staticKernelBase,
                    profile.isSPTMDevice,
                    profile.kernelcacheDigest];
            rlx_engine_log(RLX_ENGINE_LOG_INFO, "RLXEngine", message.UTF8String);
            return nil;
        }
    }

    NSError *error = nil;
    if (!kernelcachePath) {
        kernelcachePath = [self downloadedKernelcacheForTarget:target offsetTable:offsetTable error:&error];
    }
    if (!kernelcachePath) {
        return error;
    }

    self.context.kernelcachePath = kernelcachePath;
    NSString *message = [NSString stringWithFormat:@"kernelcache ready path=%@", kernelcachePath];
    rlx_engine_log(RLX_ENGINE_LOG_INFO, "RLXEngine", message.UTF8String);
    return nil;
}

- (BOOL)isUsableKernelcacheAtPath:(NSString *)path {
    struct stat attributes = {0};
    const char *fileSystemPath = path.fileSystemRepresentation;
    if (stat(fileSystemPath, &attributes) != 0 || !S_ISREG(attributes.st_mode) || attributes.st_size == 0) {
        return NO;
    }

    int descriptor = open(fileSystemPath, O_RDONLY | O_CLOEXEC);
    if (descriptor < 0) {
        return NO;
    }
    uint8_t byte = 0;
    BOOL isReadable = read(descriptor, &byte, sizeof(byte)) == sizeof(byte);
    close(descriptor);
    return isReadable;
}

- (nullable NSString *)kernelcachePathInDirectory:(NSString *)directoryPath {
    NSString *exactPath = [directoryPath stringByAppendingPathComponent:RLXKernelcacheName];
    if ([self isUsableKernelcacheAtPath:exactPath]) {
        return exactPath;
    }

    NSArray<NSString *> *entries = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:directoryPath error:nil]
        sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *entry in entries) {
        if ([entry isEqualToString:RLXKernelcacheName] || ![entry hasPrefix:RLXKernelcacheName] ||
            [entry hasSuffix:@".identity.plist"] || [entry containsString:@".partial-"] ||
            [entry containsString:@".next"]) {
            continue;
        }

        NSString *candidate = [directoryPath stringByAppendingPathComponent:entry];
        if ([self isUsableKernelcacheAtPath:candidate]) {
            return candidate;
        }
    }
    return nil;
}

- (nullable NSString *)systemKernelcachePath {
    if (!RLXInstalledThroughTrollStore()) {
        return nil;
    }

    io_registry_entry_t chosen = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/chosen");
    if (chosen != IO_OBJECT_NULL) {
        CFTypeRef value = IORegistryEntryCreateCFProperty(chosen, CFSTR("boot-manifest-hash"), kCFAllocatorDefault, 0);
        IOObjectRelease(chosen);

        NSData *hash = CFBridgingRelease(value);
        if ([hash isKindOfClass:NSData.class] && hash.length > 0) {
            NSMutableString *hashString = [NSMutableString stringWithCapacity:hash.length * 2];
            const uint8_t *bytes = hash.bytes;
            for (NSUInteger index = 0; index < hash.length; index++) {
                [hashString appendFormat:@"%02X", bytes[index]];
            }

            NSString *prebootPath = [NSString
                stringWithFormat:@"/private/preboot/%@/System/Library/Caches/" "com.apple.kernelcaches/kernelcache",
                                 hashString];
            if ([self isUsableKernelcacheAtPath:prebootPath]) {
                return prebootPath;
            }
        }
    }

    NSString *systemPath = @"/System/Library/Caches/com.apple.kernelcaches/kernelcache";
    return [self isUsableKernelcacheAtPath:systemPath] ? systemPath : nil;
}

- (nullable NSString *)stringForSysctlName:(const char *)name {
    size_t size = 0;
    if (sysctlbyname(name, NULL, &size, NULL, 0) != 0 || size == 0) {
        return nil;
    }

    char *buffer = calloc(size, sizeof(char));
    if (!buffer) {
        return nil;
    }
    if (sysctlbyname(name, buffer, &size, NULL, 0) != 0) {
        free(buffer);
        return nil;
    }

    NSString *value = [[NSString alloc] initWithBytes:buffer length:strnlen(buffer, size)
                                             encoding:NSUTF8StringEncoding];
    free(buffer);
    return value;
}

- (nullable NSString *)osNameForDeviceIdentifier:(NSString *)deviceIdentifier {
    if ([deviceIdentifier hasPrefix:@"iPhone"]) {
        return @"iOS";
    }
    if ([deviceIdentifier hasPrefix:@"iPad"]) {
        return @"iPadOS";
    }
    return nil;
}

- (nullable NSString *)downloadedKernelcacheForTarget:(NSDictionary<RLXEngineManifestKey, NSString *> *)target
                                          offsetTable:(RLXKernelOffsetTable *)offsetTable
                                                error:(NSError *_Nullable *_Nullable)error {
    NSError *directoryError = nil;
    NSURL *documentsURL = self.context.runtimeEnvironment.dataDirectoryURL;
    if (![NSFileManager.defaultManager createDirectoryAtURL:documentsURL withIntermediateDirectories:YES attributes:nil
                                                      error:&directoryError]) {
        documentsURL = nil;
    }
    NSString *deviceIdentifier = target[RLXEngineManifestTargetDeviceIdentifierKey];
    NSString *build = target[RLXEngineManifestTargetOSBuildKey];
    NSString *boardConfiguration = [self stringForSysctlName:"hw.target"];
    NSString *downloadPath = [documentsURL URLByAppendingPathComponent:RLXKernelcacheName isDirectory:NO].path;

    NSString *osName = [self osNameForDeviceIdentifier:deviceIdentifier];
    NSString *temporaryPath = downloadPath.length > 0
        ? [downloadPath stringByAppendingFormat:@".partial-%@", NSUUID.UUID.UUIDString]
        : nil;
    NSError *downloadError = nil;
    BOOL downloaded = temporaryPath.length > 0 && osName.length > 0 && build.length > 0 && boardConfiguration.length > 0
        && grab_kernelcache_for_with_error(osName,
                                           build,
                                           deviceIdentifier,
                                           boardConfiguration,
                                           temporaryPath,
                                           &downloadError);
    if (downloaded && [self isUsableKernelcacheAtPath:temporaryPath]) {
        if (rename(temporaryPath.fileSystemRepresentation, downloadPath.fileSystemRepresentation) == 0) {
            return downloadPath;
        } else {
            downloadError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        }
    }
    if (temporaryPath.length > 0) {
        [NSFileManager.defaultManager removeItemAtPath:temporaryPath error:nil];
    }

    if (error) {
        NSError *underlyingError = directoryError ?: downloadError;
        RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnosticWithStage:@"obtain_kernelcache"];
        RLXRuntimeEnvironment *runtimeEnvironment = self.context.runtimeEnvironment;
        [diagnostic appendKey:@"bundle" value:runtimeEnvironment.resourceBundle.bundlePath];
        [diagnostic appendKey:@"documents" value:documentsURL.path fallback:@"unavailable"];
        [diagnostic appendKey:@"device" value:deviceIdentifier fallback:@"unavailable"];
        [diagnostic appendKey:@"build" value:build fallback:@"unavailable"];
        [diagnostic appendKey:@"board" value:boardConfiguration fallback:@"unavailable"];
        [diagnostic appendKey:@"downloaded" boolValue:downloaded];
        /* The download is only reached on a table miss, so record the miss. */
        [diagnostic appendKey:@"offset_table_entries" integerValue:(NSInteger)offsetTable.coverageCount];
        [diagnostic appendKey:@"failure" value:underlyingError.localizedDescription fallback:@"unavailable"];
        *error = [RLXEngineError
             errorWithCode:RLXEngineErrorCodeKernelcacheUnavailable
               description:@"The kernelcache could not be obtained."
             failureReason:underlyingError.localizedFailureReason
                               ?: underlyingError.localizedDescription
                               ?: @"No local kernelcache was found and the download failed."
        recoverySuggestion:@"Check the network connection or include a matching kernelcache in the app bundle or Documents directory."
                diagnostic:diagnostic
           underlyingError:underlyingError];
    }
    return nil;
}

@end
