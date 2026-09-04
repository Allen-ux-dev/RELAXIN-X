//
//  RLXKernelOffsetTable.m
//  RelaxinEngine
//

#import "RLXKernelOffsetTable.h"

#import "../../Log/RLXEngineLog.h"

#include <stdio.h>

/*
 * Layout of KernelOffsets.plist. DevKit/Helpers/KernelOffsets/build-offset-table.py
 * writes it; the two constants below and the flag bits are the whole contract
 * between the generator and this reader.
 */
static const NSInteger RLXKernelOffsetTableSchema = 1;
static NSString *const RLXKernelOffsetTableResource = @"KernelOffsets";

typedef NS_OPTIONS(NSUInteger, RLXKernelOffsetProfileFlag) {
    RLXKernelOffsetProfileFlagArm64e = 1 << 0,
    RLXKernelOffsetProfileFlagSPTM = 1 << 1,
    RLXKernelOffsetProfileFlagFileset = 1 << 2,
    RLXKernelOffsetProfileFlagPPLText = 1 << 3,
    RLXKernelOffsetProfileFlagGFXOffsets = 1 << 4,
};

/*
 * Kernel addresses do not fit in the signed integers a plist stores, so the
 * generator writes their two's complement and this reads the bits back. Going
 * through NSNumber rather than the raw object keeps a stray string or array in
 * the resource from being reinterpreted as an address.
 */
static uint64_t rlx_offset_value(NSDictionary *container, NSString *key) {
    id value = container[key];
    return [value isKindOfClass:NSNumber.class] ? [(NSNumber *)value unsignedLongLongValue] : 0;
}

static uint32_t rlx_offset_value32(NSDictionary *container, NSString *key) {
    return (uint32_t)rlx_offset_value(container, key);
}

@interface RLXKernelOffsetProfile ()

- (nullable instancetype)initWithRecord:(NSDictionary *)record
                       deviceIdentifier:(NSString *)deviceIdentifier
                                osBuild:(NSString *)osBuild;

@end

@implementation RLXKernelOffsetProfile {
    NSDictionary<NSString *, NSNumber *> *_offsets;
}

- (nullable instancetype)initWithRecord:(NSDictionary *)record
                       deviceIdentifier:(NSString *)deviceIdentifier
                                osBuild:(NSString *)osBuild {
    self = [super init];
    if (!self) {
        return nil;
    }

    if (![record isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    NSDictionary *symbols = record[@"symbols"];
    NSDictionary *offsets = record[@"offsets"];
    if (![symbols isKindOfClass:NSDictionary.class] || ![offsets isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    _deviceIdentifier = [deviceIdentifier copy];
    _osBuild = [osBuild copy];
    _kernelcacheDigest = [record[@"kernelcacheSHA256"] isKindOfClass:NSString.class]
        ? [record[@"kernelcacheSHA256"] copy]
        : @"";
    _xnuBuild = [record[@"xnuBuild"] isKindOfClass:NSString.class] ? [record[@"xnuBuild"] copy] : @"";
    _osVersion = [record[@"osVersion"] isKindOfClass:NSString.class] ? [record[@"osVersion"] copy] : @"";
    _offsets = [offsets copy];

    NSUInteger flags = [record[@"flags"] isKindOfClass:NSNumber.class]
        ? [(NSNumber *)record[@"flags"] unsignedIntegerValue]
        : 0;

    RocketStaticKernelProfile profile = {0};
    profile.version = ROCKET_STATIC_PROFILE_VERSION;
    profile.isArm64e = (flags & RLXKernelOffsetProfileFlagArm64e) != 0;
    profile.isSPTMDevice = (flags & RLXKernelOffsetProfileFlagSPTM) != 0;
    profile.isFileset = (flags & RLXKernelOffsetProfileFlagFileset) != 0;
    profile.hasPPLTextSection = (flags & RLXKernelOffsetProfileFlagPPLText) != 0;
    profile.hasGFXOffsets = (flags & RLXKernelOffsetProfileFlagGFXOffsets) != 0;
    profile.staticKernelBase = rlx_offset_value(record, @"staticKernelBase");
    profile.sptmArgs = rlx_offset_value(record, @"sptmArgs");
    profile.xnuVersionPacked = rlx_offset_value(record, @"xnuVersionPacked");

    profile.symbols.cpu_ttep = rlx_offset_value(symbols, @"cpu_ttep");
    profile.symbols.gVirtBase = rlx_offset_value(symbols, @"gVirtBase");
    profile.symbols.gPhysBase = rlx_offset_value(symbols, @"gPhysBase");
    profile.symbols.gPhysSize = rlx_offset_value(symbols, @"gPhysSize");
    profile.symbols.ptov_table = rlx_offset_value(symbols, @"ptov_table");
    profile.symbols.allproc = rlx_offset_value(symbols, @"allproc");
    profile.symbols.vm_map_pmap = rlx_offset_value(symbols, @"vm_map_pmap");
    profile.symbols.arm_tt_l1_index_mask = rlx_offset_value(symbols, @"arm_tt_l1_index_mask");
    profile.symbols.t1sz_boot = rlx_offset_value(symbols, @"t1sz_boot");
    profile.symbols.kernel_el = rlx_offset_value(symbols, @"kernel_el");

    NSDictionary *gfx = record[@"gfx"];
    if (profile.hasGFXOffsets && [gfx isKindOfClass:NSDictionary.class]) {
        PhysrwGfxResolvedOffsets *out = &profile.gfxOffsets;
        out->userClientToOwnerOffset = rlx_offset_value32(gfx, @"userClientToOwnerOffset");
        out->submitObjectAddressOffset = rlx_offset_value32(gfx, @"submitObjectAddressOffset");
        out->ownerToStateOffset = rlx_offset_value32(gfx, @"ownerToStateOffset");
        out->stateControlOffset = rlx_offset_value32(gfx, @"stateControlOffset");
        out->ownerPatchedPointerOffset = rlx_offset_value32(gfx, @"ownerPatchedPointerOffset");
        out->stateSubmitObjectOffset = rlx_offset_value32(gfx, @"stateSubmitObjectOffset");
        out->stateAddressBiasOffset = rlx_offset_value32(gfx, @"stateAddressBiasOffset");
        out->stateLengthOffset = rlx_offset_value32(gfx, @"stateLengthOffset");
        out->ownerResourceTableOffset = rlx_offset_value32(gfx, @"ownerResourceTableOffset");
        out->resourceTableEntriesOffset = rlx_offset_value32(gfx, @"resourceTableEntriesOffset");
        out->resourceObjectMemoryOffset = rlx_offset_value32(gfx, @"resourceObjectMemoryOffset");
        out->resourceMemoryAddressOffset = rlx_offset_value32(gfx, @"resourceMemoryAddressOffset");
        out->ioGpuUserClientTypeStaticAddress = rlx_offset_value(gfx, @"ioGpuUserClientTypeStaticAddress");
        // clang-format off
        out->mobileFramebufferUserClientTypeStaticAddress =
            rlx_offset_value(gfx, @"mobileFramebufferUserClientTypeStaticAddress");
        // clang-format on
        out->agxSubmitHandlerVtableAddress = rlx_offset_value(gfx, @"agxSubmitHandlerVtableAddress");
    } else if (profile.hasGFXOffsets) {
        return nil;
    }
    if (profile.hasGFXOffsets && !physrw_gfx_resolved_offsets_are_valid(&profile.gfxOffsets)) {
        return nil;
    }

    strlcpy(profile.xnuBuild, _xnuBuild.UTF8String ?: "", sizeof(profile.xnuBuild));
    strlcpy(profile.osVersion, _osVersion.UTF8String ?: "", sizeof(profile.osVersion));

    /*
     * The same shape the collector enforces after reading a kernelcache. A
     * table entry that would not have passed there must not pass here either.
     */
    if (!profile.staticKernelBase || !profile.xnuVersionPacked || !profile.symbols.cpu_ttep
        || !profile.symbols.gVirtBase || !profile.symbols.gPhysBase || !profile.symbols.gPhysSize
        || !profile.symbols.ptov_table || !profile.symbols.allproc || !profile.symbols.vm_map_pmap
        || !profile.symbols.arm_tt_l1_index_mask || !profile.symbols.t1sz_boot || !profile.symbols.kernel_el
        || (profile.isSPTMDevice && !profile.sptmArgs) || (!profile.isSPTMDevice && !profile.hasPPLTextSection)) {
        return nil;
    }
    profile.valid = true;
    _rocketProfile = profile;
    return self;
}

- (uint64_t)staticKernelBase {
    return _rocketProfile.staticKernelBase;
}

- (uint64_t)SPTMArgumentsAddress {
    return _rocketProfile.sptmArgs;
}

- (BOOL)isArm64eKernel {
    return _rocketProfile.isArm64e;
}

- (BOOL)isSPTMDevice {
    return _rocketProfile.isSPTMDevice;
}

- (BOOL)hasGFXOffsets {
    return _rocketProfile.hasGFXOffsets;
}

- (BOOL)supportsCPUFamily:(uint32_t)cpuFamily {
    PhysrwGfxChip chip = physrw_gfx_chip_for_cpu_family(cpuFamily);
    if (chip == PHYSRW_GFX_CHIP_UNKNOWN) {
        return NO;
    }
    return _rocketProfile.hasGFXOffsets || !physrw_gfx_chip_requires_recovered_offsets(chip);
}

- (rlx_kernel_patchfinder_info)patchfinderInfo {
    rlx_kernel_patchfinder_info patchfinder = {0};
    patchfinder.static_base = _rocketProfile.staticKernelBase;
    patchfinder.cpu_ttep_symbol = _rocketProfile.symbols.cpu_ttep;
    patchfinder.virtual_base_symbol = _rocketProfile.symbols.gVirtBase;
    patchfinder.physical_base_symbol = _rocketProfile.symbols.gPhysBase;
    patchfinder.physical_size_symbol = _rocketProfile.symbols.gPhysSize;
    patchfinder.ptov_table_symbol = _rocketProfile.symbols.ptov_table;
    patchfinder.vm_map_pmap_offset = _rocketProfile.symbols.vm_map_pmap;
    patchfinder.arm_tt_l1_index_mask = _rocketProfile.symbols.arm_tt_l1_index_mask;
    patchfinder.t1sz_boot = _rocketProfile.symbols.t1sz_boot;
    patchfinder.kernel_el = _rocketProfile.symbols.kernel_el;
    patchfinder.is_sptm = _rocketProfile.isSPTMDevice;

    /*
     * Same two spellings the XPF path parses, in the same order: modern builds
     * carry five dotted components, older ones three.
     */
    if (sscanf(_rocketProfile.xnuBuild,
               "%u.%u.%u.%*u.%*u~%u",
               &patchfinder.xnu_major,
               &patchfinder.xnu_minor,
               &patchfinder.xnu_patch,
               &patchfinder.xnu_revision)
        != 4) {
        (void)sscanf(_rocketProfile.xnuBuild,
                     "%u.%u.%u~%u",
                     &patchfinder.xnu_major,
                     &patchfinder.xnu_minor,
                     &patchfinder.xnu_patch,
                     &patchfinder.xnu_revision);
    }
    return patchfinder;
}

- (xpc_object_t)offsetDictionary {
    xpc_object_t dictionary = xpc_dictionary_create(NULL, NULL, 0);
    [_offsets enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *value, BOOL *stop) {
        (void)stop;
        if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSNumber.class]) {
            xpc_dictionary_set_uint64(dictionary, key.UTF8String, value.unsignedLongLongValue);
        }
    }];
    xpc_dictionary_set_uint64(dictionary, "kernelConstant.staticBase", _rocketProfile.staticKernelBase);
    /*
     * No manual balancing here, unlike the XPF path: xpc_dictionary_create
     * carries XPC_RETURNS_RETAINED, so ARC already owns the reference and the
     * +0 return is its autorelease.
     */
    return dictionary;
}

@end

@implementation RLXKernelOffsetTable {
    NSDictionary *_table;
}

- (instancetype)initWithResourceBundle:(NSBundle *)resourceBundle {
    self = [super init];
    if (!self) {
        return nil;
    }

    NSString *path = [resourceBundle pathForResource:RLXKernelOffsetTableResource ofType:@"plist"];
    if (path.length == 0) {
        rlx_engine_log(RLX_ENGINE_LOG_INFO, "RLXKernelOffsets", "offset table absent; kernelcache analysis stays live");
        return self;
    }

    NSDictionary *loaded = [NSDictionary dictionaryWithContentsOfFile:path];
    NSNumber *schema = loaded[@"schema"];
    NSNumber *profileVersion = loaded[@"profileVersion"];
    if (![loaded[@"profiles"] isKindOfClass:NSArray.class] || ![loaded[@"index"] isKindOfClass:NSDictionary.class]
        || ![schema isKindOfClass:NSNumber.class] || schema.integerValue != RLXKernelOffsetTableSchema
        || ![profileVersion isKindOfClass:NSNumber.class]
        || profileVersion.unsignedIntValue != ROCKET_STATIC_PROFILE_VERSION) {
        NSString *message = [NSString
            stringWithFormat:
                @"offset table rejected path=%@ schema=%@ " "profile_version=%@ expected_schema=%ld " "expected_profile_version=%u",
                path,
                schema ?: @"missing",
                profileVersion ?: @"missing",
                (long)RLXKernelOffsetTableSchema,
                ROCKET_STATIC_PROFILE_VERSION];
        rlx_engine_log(RLX_ENGINE_LOG_ERROR, "RLXKernelOffsets", message.UTF8String);
        return self;
    }

    _table = loaded;
    NSString *message = [NSString stringWithFormat:@"offset table loaded entries=%lu profiles=%lu " "generated=%@",
                                                   (unsigned long)[loaded[@"index"] count],
                                                   (unsigned long)[loaded[@"profiles"] count],
                                                   loaded[@"generatedAt"] ?: @"unknown"];
    rlx_engine_log(RLX_ENGINE_LOG_INFO, "RLXKernelOffsets", message.UTF8String);
    return self;
}

- (nullable RLXKernelOffsetProfile *)profileForDeviceIdentifier:(NSString *)deviceIdentifier
                                                        osBuild:(NSString *)osBuild {
    if (deviceIdentifier.length == 0 || osBuild.length == 0) {
        return nil;
    }

    NSDictionary *table = _table;
    if (!table) {
        return nil;
    }

    NSString *key = [NSString stringWithFormat:@"%@|%@", deviceIdentifier, osBuild];
    NSNumber *position = table[@"index"][key];
    NSArray *profiles = table[@"profiles"];
    if (![position isKindOfClass:NSNumber.class] || position.integerValue < 0
        || (NSUInteger)position.integerValue >= profiles.count) {
        return nil;
    }

    return [[RLXKernelOffsetProfile alloc] initWithRecord:profiles[(NSUInteger)position.integerValue]
                                         deviceIdentifier:deviceIdentifier
                                                  osBuild:osBuild];
}

- (NSUInteger)coverageCount {
    return [_table[@"index"] count];
}

- (nullable NSString *)generatedAt {
    id value = _table[@"generatedAt"];
    return [value isKindOfClass:NSString.class] ? value : nil;
}

@end
