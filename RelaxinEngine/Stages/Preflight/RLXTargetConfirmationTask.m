//
//  RLXTargetConfirmationTask.m
//  RelaxinEngine
//

#import "RLXTargetConfirmationTask.h"

#import <stdlib.h>
#import <string.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>

#import "../../Engine/RLXEngine.h"
#import "../../Diagnostic/RLXEngineDiagnostic.h"
#import "../../Engine/RLXEngineError.h"
#import "../../Log/RLXEngineLog.h"
#import "../../Engine/RLXEngineRunContext.h"

@interface RLXTargetConfirmationTask ()

- (nullable NSString *)stringForSysctlName:(const char *)name;
- (NSString *)currentOSVersion;
- (NSDictionary<RLXEngineManifestKey, NSString *> *)currentTarget;
- (nullable NSDictionary<RLXEngineManifestKey, NSString *> *)
    confirmedTargetForManifest:(NSDictionary<RLXEngineManifestKey, NSString *> *)manifest
                         error:(NSError *_Nullable *_Nullable)error;

@end

@implementation RLXTargetConfirmationTask

- (instancetype)initWithContext:(RLXEngineRunContext *)context {
    return [super initWithStage:RLXEngineStageTargetConfirmation context:context];
}

- (nullable NSError *)execute {
#if !defined(__arm64e__)
    RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnosticWithStage:@"confirm_target"];
    [diagnostic appendKey:@"expected_arch" value:@"arm64e"];
    return [RLXEngineError errorWithCode:RLXEngineErrorCodeInvalidTarget
                             description:@"The engine is not running as arm64e."
                           failureReason:nil
                      recoverySuggestion:@"Rebuild the app and framework for arm64e."
                              diagnostic:diagnostic];
#endif

    NSError *error = nil;
    NSDictionary<RLXEngineManifestKey, NSString *> *target = [self confirmedTargetForManifest:self.context.manifest
                                                                                        error:&error];
    if (!target) {
        return error;
    }

    self.context.confirmedTarget = target;
    NSString *message = [NSString
        stringWithFormat:@"target confirmed device=%@ soc=%@ cpu_family=%@ ios=%@ build=%@ hardware_class=%@ profile_id=%@ backend_id=%@",
                         target[RLXEngineManifestTargetDeviceIdentifierKey],
                         target[RLXEngineManifestTargetSoCKey],
                         target[RLXEngineManifestTargetCPUFamilyKey],
                         target[RLXEngineManifestTargetOSVersionKey],
                         target[RLXEngineManifestTargetOSBuildKey],
                         target[RLXEngineManifestHardwareExecutionClassKey],
                         self.context.manifest[RLXEngineManifestRuntimeProfileIDKey],
                         self.context.manifest[RLXEngineManifestRuntimeBackendIDKey]];
    rlx_engine_log(RLX_ENGINE_LOG_INFO, "RLXEngine", message.UTF8String);
    return nil;
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

- (NSString *)currentOSVersion {
    NSString *version = [self stringForSysctlName:"kern.osproductversion"];
    if (version.length > 0) {
        return version;
    }

    NSOperatingSystemVersion components = NSProcessInfo.processInfo.operatingSystemVersion;
    if (components.patchVersion > 0) {
        return [NSString stringWithFormat:@"%ld.%ld.%ld",
                                          (long)components.majorVersion,
                                          (long)components.minorVersion,
                                          (long)components.patchVersion];
    }
    return [NSString stringWithFormat:@"%ld.%ld", (long)components.majorVersion, (long)components.minorVersion];
}

- (NSDictionary<RLXEngineManifestKey, NSString *> *)currentTarget {
    struct utsname systemInfo = {0};
    uname(&systemInfo);

    uint32_t cpuFamily = 0;
    size_t cpuFamilySize = sizeof(cpuFamily);
    BOOL hasCPUFamily = sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0) == 0
        && cpuFamilySize == sizeof(cpuFamily);

    NSString *soc = @"";
    NSString *profile = @"";
    // This profile confirms CPU-family compatibility only. Rocket derives
    // PPL/SPTM from the exact kernelcache instead of the profile name.
    if (hasCPUFamily) {
        switch (cpuFamily) {
            case 0x07D34B9F:
                soc = @"A12";
                profile = @"ppl-dma-a12";
                break;
            case 0x462504D2:
                soc = @"A13";
                profile = @"ppl-gfx-a13";
                break;
            case 0x1B588BB3:
                soc = @"A14/M1";
                profile = @"ppl-gfx-a14-m1";
                break;
            case 0xDA33D83D:
                soc = @"A15/M2";
                profile = @"gfx-a15-m2";
                break;
            case 0x8765EDEA:
                soc = @"A16";
                profile = @"gfx-a16";
                break;
            case 0x2876F5B5:
                soc = @"A17";
                profile = @"sptm-gfx-a17";
                break;
            default:
                break;
        }
    }

    return @{
        RLXEngineManifestTargetDeviceIdentifierKey : [NSString stringWithUTF8String:systemInfo.machine] ?: @"",
        RLXEngineManifestTargetSoCKey : soc,
        RLXEngineManifestTargetCPUFamilyKey : hasCPUFamily ? [NSString stringWithFormat:@"0x%08X", cpuFamily] : @"",
        RLXEngineManifestTargetOSVersionKey : [self currentOSVersion],
        RLXEngineManifestTargetOSBuildKey : [self stringForSysctlName:"kern.osversion"] ?: @"",
        RLXEngineManifestRuntimeProfileKey : profile,
        RLXEngineManifestHardwareExecutionClassKey : profile,
    };
}

- (nullable NSDictionary<RLXEngineManifestKey, NSString *> *)
    confirmedTargetForManifest:(NSDictionary<RLXEngineManifestKey, NSString *> *)manifest
                         error:(NSError *_Nullable *_Nullable)error {
    NSArray<RLXEngineManifestKey> *exactTargetKeys = @[
        RLXEngineManifestTargetDeviceIdentifierKey,
        RLXEngineManifestTargetSoCKey,
        RLXEngineManifestTargetCPUFamilyKey,
        RLXEngineManifestTargetOSVersionKey,
        RLXEngineManifestTargetOSBuildKey,
        RLXEngineManifestRuntimeProfileKey,
        RLXEngineManifestHardwareExecutionClassKey,
    ];
    NSArray<RLXEngineManifestKey> *requiredContractKeys = @[
        RLXEngineManifestRuntimeProfileIDKey,
        RLXEngineManifestRuntimeBackendIDKey,
        RLXEngineManifestRuntimeBackendGenerationKey,
        RLXEngineManifestRuntimeResolutionGenerationKey,
        RLXEngineManifestRuntimeSupportLevelKey,
    ];
    NSDictionary<RLXEngineManifestKey, NSString *> *observed = [self currentTarget];
    NSMutableArray<NSString *> *problems = [NSMutableArray array];

    for (RLXEngineManifestKey key in exactTargetKeys) {
        NSString *expectedValue = manifest[key];
        NSString *observedValue = observed[key];
        if (![expectedValue isKindOfClass:NSString.class] || expectedValue.length == 0) {
            [problems addObject:[NSString stringWithFormat:@"%@ is missing", key]];
        } else if (![expectedValue isEqualToString:observedValue]) {
            [problems
                addObject:[NSString stringWithFormat:@"%@ expected=%@ observed=%@", key, expectedValue, observedValue]];
        }
    }

    for (RLXEngineManifestKey key in requiredContractKeys) {
        NSString *value = manifest[key];
        if (![value isKindOfClass:NSString.class] || value.length == 0) {
            [problems addObject:[NSString stringWithFormat:@"%@ is missing", key]];
        }
    }

    NSInteger backendGeneration = [manifest[RLXEngineManifestRuntimeBackendGenerationKey] integerValue];
    NSInteger resolutionGeneration = [manifest[RLXEngineManifestRuntimeResolutionGenerationKey] integerValue];
    if (backendGeneration <= 0) {
        [problems addObject:@"runtimeBackendGeneration must be positive"];
    }
    if (resolutionGeneration <= 0) {
        [problems addObject:@"runtimeResolutionGeneration must be positive"];
    }
    NSSet<NSString *> *supportLevels = [NSSet setWithArray:@[
        @"supported", @"experimental", @"partial", @"recoveryOnly"
    ]];
    if (![supportLevels containsObject:manifest[RLXEngineManifestRuntimeSupportLevelKey] ?: @""]) {
        [problems addObject:@"runtimeSupportLevel is not actionable"];
    }
    if (observed[RLXEngineManifestHardwareExecutionClassKey].length == 0) {
        [problems addObject:@"hardwareExecutionClass has no mapping for the live CPU family"];
    }

    if (problems.count == 0) {
        return observed;
    }

    if (error) {
        RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnosticWithStage:@"confirm_target"];
        [diagnostic appendKey:@"device" value:observed[RLXEngineManifestTargetDeviceIdentifierKey]];
        [diagnostic appendKey:@"soc" value:observed[RLXEngineManifestTargetSoCKey]];
        [diagnostic appendKey:@"cpu_family" value:observed[RLXEngineManifestTargetCPUFamilyKey]];
        [diagnostic appendKey:@"ios" value:observed[RLXEngineManifestTargetOSVersionKey]];
        [diagnostic appendKey:@"build" value:observed[RLXEngineManifestTargetOSBuildKey]];
        [diagnostic appendKey:@"hardware_class" value:observed[RLXEngineManifestHardwareExecutionClassKey]];
        [diagnostic appendKey:@"runtime_profile_id" value:manifest[RLXEngineManifestRuntimeProfileIDKey]];
        [diagnostic appendKey:@"runtime_backend_id" value:manifest[RLXEngineManifestRuntimeBackendIDKey]];
        [diagnostic appendKey:@"problems" value:[problems componentsJoinedByString:@"; "]];

        *error = [RLXEngineError
                 errorWithCode:RLXEngineErrorCodeInvalidTarget
                   description:@"The runtime target could not be confirmed."
                 failureReason:[problems componentsJoinedByString:@"; "]
            recoverySuggestion:@"Verify the device, SoC, iOS version, build, and runtime profile before trying again."
                    diagnostic:diagnostic];
    }
    return nil;
}

@end
