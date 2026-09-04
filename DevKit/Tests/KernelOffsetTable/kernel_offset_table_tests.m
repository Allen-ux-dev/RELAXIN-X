/*
 * Contract tests for the bundled kernelcache offset table.
 *
 * The reader is the only thing standing between a plist on disk and the
 * offsets Rocket walks the kernel with, so what is checked here is that it
 * reproduces the generator's values exactly, and that it refuses anything it
 * cannot reproduce rather than handing back a partly filled profile.
 *
 * Every reader is bound to an explicit resource bundle. Tests therefore stage
 * isolated bundles instead of depending on the command-line tool's main
 * bundle, including a same-process case that proves readers cannot contaminate
 * one another.
 */

#import <Foundation/Foundation.h>

#import <mach/machine.h>

#import "RLXKernelOffsetTable.h"

#include <stdio.h>
#include <string.h>

static int gFailures;
static RLXKernelOffsetTable *gTable;
static NSURL *gBundleURL;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "not ok %s\n", what);
        gFailures++;
    }
}

static void expect_u64(uint64_t observed, uint64_t expected, const char *what) {
    if (observed != expected) {
        fprintf(stderr, "not ok %s: observed 0x%llx expected 0x%llx\n", what, observed, expected);
        gFailures++;
    }
}

/* The generator's encoding: values above Int64 max travel as their two's
 * complement, because that is all a plist integer can carry. */
static NSNumber *encoded(uint64_t value) {
    return @((long long)value);
}

static RLXKernelOffsetTable *tableForFixture(NSDictionary *_Nullable table, NSURL **bundleURL) {
    NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"KernelOffsets-%@.bundle", NSUUID.UUID.UUIDString]
                        isDirectory:YES];
    NSError *error = nil;
    BOOL created = [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:&error];
    NSDictionary *info = @{
        @"CFBundleIdentifier" : [NSString stringWithFormat:@"com.aapl.relaxin.tests.%@", NSUUID.UUID.UUIDString],
        @"CFBundlePackageType" : @"BNDL",
    };
    BOOL wroteInfo = [info writeToURL:[directory URLByAppendingPathComponent:@"Info.plist"] atomically:YES];
    BOOL wroteTable = YES;
    if (table) {
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:table format:NSPropertyListBinaryFormat_v1_0
                                                                 options:0
                                                                   error:&error];
        wroteTable = data &&
            [data writeToURL:[directory URLByAppendingPathComponent:@"KernelOffsets.plist"] atomically:YES];
    }
    NSBundle *bundle = [NSBundle bundleWithURL:directory];
    if (!created || !wroteInfo || !wroteTable || !bundle) {
        fprintf(stderr, "not ok stage: %s\n", error.localizedDescription.UTF8String ?: "write failed");
        exit(1);
    }
    if (bundleURL) {
        *bundleURL = directory;
    }
    return [[RLXKernelOffsetTable alloc] initWithResourceBundle:bundle];
}

static void stageTable(NSDictionary *table) {
    if (gBundleURL) {
        [NSFileManager.defaultManager removeItemAtURL:gBundleURL error:nil];
    }
    NSURL *bundleURL = nil;
    gTable = tableForFixture(table, &bundleURL);
    gBundleURL = bundleURL;
}

static NSDictionary *symbolsFixture(void) {
    return @{
        @"cpu_ttep" : encoded(0xFFFFFFF027899B98ULL),
        @"gVirtBase" : encoded(0xFFFFFFF0278BCCA0ULL),
        @"gPhysBase" : encoded(0xFFFFFFF0278EA428ULL),
        @"gPhysSize" : encoded(0xFFFFFFF0278EA430ULL),
        @"ptov_table" : encoded(0xFFFFFFF02792C9C8ULL),
        @"allproc" : encoded(0xFFFFFFF02A36D300ULL),
        @"vm_map_pmap" : encoded(0x40ULL),
        @"arm_tt_l1_index_mask" : encoded(0x7000000000ULL),
        @"t1sz_boot" : encoded(0x19ULL),
        @"kernel_el" : encoded(0x1ULL),
    };
}

static NSDictionary *gfxFixture(void) {
    return @{
        @"userClientToOwnerOffset" : @288,
        @"submitObjectAddressOffset" : @40,
        @"ownerToStateOffset" : @72,
        @"stateControlOffset" : @7276,
        @"ownerPatchedPointerOffset" : @344,
        @"stateSubmitObjectOffset" : @34624,
        @"stateAddressBiasOffset" : @1144,
        @"stateLengthOffset" : @34128,
        @"ownerResourceTableOffset" : @120,
        @"resourceTableEntriesOffset" : @16,
        @"resourceObjectMemoryOffset" : @48,
        @"resourceMemoryAddressOffset" : @40,
        @"ioGpuUserClientTypeStaticAddress" : encoded(0xFFFFFFF02794EAC8ULL),
        @"mobileFramebufferUserClientTypeStaticAddress" : encoded(0xFFFFFFF027C55DD0ULL),
        @"agxSubmitHandlerVtableAddress" : encoded(0xFFFFFFF02794E790ULL),
    };
}

/* Flags 0b10111: arm64e | SPTM | fileset | GFX offsets, no PPL __TEXT. */
static NSMutableDictionary *sptmProfileFixture(void) {
    return [@{
        @"kernelcacheSHA256" : @"db8c68bfa8b5",
        @"xnuBuild" : @"10002.82.4~3",
        @"osVersion" : @"17.3",
        @"flags" : @(0x17),
        @"staticKernelBase" : encoded(0xFFFFFFF027004000ULL),
        @"sptmArgs" : encoded(0xFFFFFFF02792B958ULL),
        @"xnuVersionPacked" : encoded(10997403352042496ULL),
        @"symbols" : symbolsFixture(),
        @"gfx" : gfxFixture(),
        @"offsetSets" : @[ @"translation", @"struct" ],
        @"offsets" : @{
            @"kernelSymbol.cpu_ttep" : encoded(0xFFFFFFF027899B98ULL),
            @"kernelConstant.T1SZ_BOOT" : @25,
            @"kernelStruct.vm_map.pmap" : @64,
        },
    } mutableCopy];
}

static NSDictionary *tableWithProfiles(NSArray *profiles, NSDictionary *index) {
    return @{
        @"schema" : @1,
        @"profileVersion" : @(ROCKET_STATIC_PROFILE_VERSION),
        @"generatedAt" : @"2026-08-07T00:00:00+00:00",
        @"source" : @"fixture",
        @"profiles" : profiles,
        @"index" : index,
    };
}

/*
 * The values the generator wrote come back bit for bit, including the kernel
 * addresses that do not fit in the signed integer a plist stores.
 */
static void test_round_trip(void) {
    stageTable(tableWithProfiles(@[ sptmProfileFixture() ], @{@"iPhone14,6|21D61" : @0}));

    RLXKernelOffsetProfile *profile = [gTable profileForDeviceIdentifier:@"iPhone14,6" osBuild:@"21D61"];
    expect(profile != nil, "round-trip: profile resolves");
    if (!profile) {
        return;
    }

    expect_u64(profile.staticKernelBase, 0xFFFFFFF027004000ULL, "round-trip: staticKernelBase");
    expect_u64(profile.SPTMArgumentsAddress, 0xFFFFFFF02792B958ULL, "round-trip: sptmArgs");
    expect(profile.isSPTMDevice, "round-trip: SPTM");
    expect(profile.isArm64eKernel, "round-trip: arm64e");
    expect([profile.xnuBuild isEqualToString:@"10002.82.4~3"], "round-trip: xnuBuild");

    RocketStaticKernelProfile rocket = profile.rocketProfile;
    expect(rocket.valid, "round-trip: rocket profile valid");
    expect(rocket.version == ROCKET_STATIC_PROFILE_VERSION, "round-trip: rocket profile version");
    expect_u64(rocket.symbols.cpu_ttep, 0xFFFFFFF027899B98ULL, "round-trip: cpu_ttep");
    expect_u64(rocket.symbols.arm_tt_l1_index_mask, 0x7000000000ULL, "round-trip: ARM_TT_L1_INDEX_MASK");
    expect_u64(rocket.symbols.t1sz_boot, 0x19ULL, "round-trip: T1SZ_BOOT");
    expect(rocket.hasGFXOffsets, "round-trip: GFX offsets present");
    expect_u64(rocket.gfxOffsets.stateSubmitObjectOffset, 34624, "round-trip: stateSubmitObjectOffset");
    expect_u64(rocket.gfxOffsets.agxSubmitHandlerVtableAddress,
               0xFFFFFFF02794E790ULL,
               "round-trip: agxSubmitHandlerVtableAddress");

    /* The XNU build parses into the same four components the XPF path parses. */
    rlx_kernel_patchfinder_info patchfinder = profile.patchfinderInfo;
    expect(patchfinder.xnu_major == 10002 && patchfinder.xnu_minor == 82 && patchfinder.xnu_patch == 4
               && patchfinder.xnu_revision == 3,
           "round-trip: xnu version components");
    expect_u64(patchfinder.static_base, 0xFFFFFFF027004000ULL, "round-trip: patchfinder static_base");
    expect(patchfinder.is_sptm == 1, "round-trip: patchfinder is_sptm");

    xpc_object_t dictionary = profile.offsetDictionary;
    expect(dictionary != NULL, "round-trip: offset dictionary");
    if (dictionary) {
        expect_u64(xpc_dictionary_get_uint64(dictionary, "kernelSymbol.cpu_ttep"),
                   0xFFFFFFF027899B98ULL,
                   "round-trip: dictionary cpu_ttep");
        /*
         * The static base is not one of XPF's items; the engine adds it before
         * handing the dictionary over, so the table has to as well.
         */
        expect_u64(xpc_dictionary_get_uint64(dictionary, "kernelConstant.staticBase"),
                   0xFFFFFFF027004000ULL,
                   "round-trip: dictionary staticBase");
    }
}

/* A12 uses DMAFail, so its PPL profile is complete without GFX offsets. */
static void test_ppl_profile_without_gfx(void) {
    NSMutableDictionary *profileRecord = sptmProfileFixture();
    profileRecord[@"flags"] = @(0x0D); /* arm64e | fileset | PPL __TEXT */
    profileRecord[@"sptmArgs"] = @0;
    [profileRecord removeObjectForKey:@"gfx"];
    stageTable(tableWithProfiles(@[ profileRecord ], @{@"iPhone11,8|21D61" : @0}));

    RLXKernelOffsetProfile *profile = [gTable profileForDeviceIdentifier:@"iPhone11,8" osBuild:@"21D61"];
    expect(profile != nil, "ppl: profile resolves");
    if (!profile) {
        return;
    }
    expect(!profile.isSPTMDevice, "ppl: not SPTM");
    expect(profile.SPTMArgumentsAddress == 0, "ppl: no SPTM arguments");
    expect(!profile.rocketProfile.hasGFXOffsets, "ppl: no GFX offsets");
    expect(profile.rocketProfile.hasPPLTextSection, "ppl: PPL __TEXT present");
    expect(profile.rocketProfile.valid, "ppl: profile valid");
}

/*
 * 一份没有 GFX 偏移的 profile 对 A12 是完整的，对其余任何一条后端都不是。查表
 * 本身照常返回它，判定归调用方。
 */
static void test_cpu_family_fitness(void) {
    NSMutableDictionary *withoutGFX = sptmProfileFixture();
    withoutGFX[@"flags"] = @(0x0D); /* arm64e | fileset | PPL __TEXT */
    withoutGFX[@"sptmArgs"] = @0;
    [withoutGFX removeObjectForKey:@"gfx"];
    stageTable(tableWithProfiles(
        @[ withoutGFX, sptmProfileFixture() ],
        @{@"iPhone11,8|20G81" : @0,
          @"iPhone14,6|21D61" : @1}));

    RLXKernelOffsetProfile *lean = [gTable profileForDeviceIdentifier:@"iPhone11,8" osBuild:@"20G81"];
    expect(lean != nil, "fitness: 无 GFX 的条目照常解析");
    if (lean) {
        expect(!lean.hasGFXOffsets, "fitness: 无 GFX 偏移");
        expect([lean supportsCPUFamily:CPUFAMILY_ARM_VORTEX_TEMPEST], "fitness: A12 可用");
        expect(![lean supportsCPUFamily:CPUFAMILY_ARM_LIGHTNING_THUNDER], "fitness: A13 不可用");
        expect(![lean supportsCPUFamily:CPUFAMILY_ARM_BLIZZARD_AVALANCHE], "fitness: A15 不可用");
        expect(![lean supportsCPUFamily:0], "fitness: 未知 CPU 族不可用");
    }

    RLXKernelOffsetProfile *full = [gTable profileForDeviceIdentifier:@"iPhone14,6" osBuild:@"21D61"];
    expect(full != nil, "fitness: 有 GFX 的条目解析");
    if (full) {
        expect(full.hasGFXOffsets, "fitness: 有 GFX 偏移");
        expect([full supportsCPUFamily:CPUFAMILY_ARM_BLIZZARD_AVALANCHE], "fitness: A15 可用");
        expect([full supportsCPUFamily:CPUFAMILY_ARM_VORTEX_TEMPEST], "fitness: A12 也可用（多带的偏移无害）");
        expect(![full supportsCPUFamily:0], "fitness: 未知 CPU 族仍不可用");
    }
}

/* A miss is the ordinary case for an uncovered build, and has to be silent. */
static void test_miss(void) {
    stageTable(tableWithProfiles(@[ sptmProfileFixture() ], @{@"iPhone14,6|21D61" : @0}));

    expect([gTable profileForDeviceIdentifier:@"iPhone14,6" osBuild:@"21E236"] == nil, "miss: unknown build");
    expect([gTable profileForDeviceIdentifier:@"iPhone17,1" osBuild:@"21D61"] == nil, "miss: unknown device");
    expect([gTable profileForDeviceIdentifier:@"" osBuild:@"21D61"] == nil, "miss: empty device");
    expect(gTable.coverageCount == 1, "miss: coverage counted");
}

/* A future generator writes a schema this reader cannot parse. Refusing the
 * whole table sends every caller down the kernelcache path, which still works. */
static void test_rejects_future_schema(void) {
    NSMutableDictionary *table = [tableWithProfiles(
        @[ sptmProfileFixture() ],
        @{@"iPhone14,6|21D61" : @0}) mutableCopy];
    table[@"schema"] = @99;
    stageTable(table);

    expect([gTable profileForDeviceIdentifier:@"iPhone14,6" osBuild:@"21D61"] == nil, "future-schema: table refused");
    expect(gTable.coverageCount == 0, "future-schema: no coverage reported");
}

/* Same for a profile shape the engine's struct no longer matches. */
static void test_rejects_future_profile_version(void) {
    NSMutableDictionary *table = [tableWithProfiles(
        @[ sptmProfileFixture() ],
        @{@"iPhone14,6|21D61" : @0}) mutableCopy];
    table[@"profileVersion"] = @(ROCKET_STATIC_PROFILE_VERSION + 1);
    stageTable(table);

    expect([gTable profileForDeviceIdentifier:@"iPhone14,6" osBuild:@"21D61"] == nil, "future-profile: table refused");
}

/*
 * A truncated entry must not resolve. Rocket cannot tell a zero symbol from an
 * absent one once it is walking page tables, so the refusal has to happen here.
 */
static void test_rejects_incomplete_profile(void) {
    NSMutableDictionary *profileRecord = sptmProfileFixture();
    NSMutableDictionary *symbols = [symbolsFixture() mutableCopy];
    [symbols removeObjectForKey:@"ptov_table"];
    profileRecord[@"symbols"] = symbols;
    stageTable(tableWithProfiles(@[ profileRecord ], @{@"iPhone14,6|21D61" : @0}));

    expect([gTable profileForDeviceIdentifier:@"iPhone14,6" osBuild:@"21D61"] == nil,
           "incomplete: missing symbol refused");
}

/* The GFX flag promises all offsets direct-gfx reads. A partial dictionary must
 * fall back before Rocket sees zero as a usable kernel offset. */
static void test_rejects_incomplete_gfx_profile(void) {
    NSMutableDictionary *profileRecord = sptmProfileFixture();
    NSMutableDictionary *gfx = [gfxFixture() mutableCopy];
    [gfx removeObjectForKey:@"stateSubmitObjectOffset"];
    profileRecord[@"gfx"] = gfx;
    stageTable(tableWithProfiles(@[ profileRecord ], @{@"iPhone14,6|21D61" : @0}));

    expect([gTable profileForDeviceIdentifier:@"iPhone14,6" osBuild:@"21D61"] == nil,
           "incomplete-gfx: missing offset refused");
}

/* Validate the array member before keyed subscripting it. A malformed resource
 * is a table miss, not an Objective-C unrecognized-selector crash. */
static void test_rejects_non_dictionary_profile(void) {
    stageTable(tableWithProfiles(@[ @"not-a-profile" ], @{@"iPhone14,6|21D61" : @0}));

    expect([gTable profileForDeviceIdentifier:@"iPhone14,6" osBuild:@"21D61"] == nil,
           "profile-type: non-dictionary refused");
}

/* An SPTM entry whose arguments slot never resolved would fail the same check
 * the collector applies after reading a kernelcache. */
static void test_rejects_sptm_without_arguments(void) {
    NSMutableDictionary *profileRecord = sptmProfileFixture();
    profileRecord[@"sptmArgs"] = @0;
    stageTable(tableWithProfiles(@[ profileRecord ], @{@"iPhone14,6|21D61" : @0}));

    expect([gTable profileForDeviceIdentifier:@"iPhone14,6" osBuild:@"21D61"] == nil, "sptm-no-args: refused");
}

/* An index entry pointing past the profile array. */
static void test_rejects_out_of_range_index(void) {
    stageTable(tableWithProfiles(@[ sptmProfileFixture() ], @{@"iPhone14,6|21D61" : @7}));

    expect([gTable profileForDeviceIdentifier:@"iPhone14,6" osBuild:@"21D61"] == nil, "out-of-range: refused");
}

/* Two readers created in one process must remain bound to their own bundles.
 * A bundle without the resource is the ordinary kernelcache-fallback case. */
static void test_bundle_isolation(void) {
    NSURL *firstURL = nil;
    NSURL *secondURL = nil;
    NSURL *missingURL = nil;
    RLXKernelOffsetTable *first = tableForFixture(tableWithProfiles(
                                                      @[ sptmProfileFixture() ],
                                                      @{@"iPhone14,6|21D61" : @0}),
                                                  &firstURL);
    RLXKernelOffsetTable *second = tableForFixture(tableWithProfiles(
                                                       @[ sptmProfileFixture() ],
                                                       @{@"iPhone16,2|21B91" : @0}),
                                                   &secondURL);
    RLXKernelOffsetTable *missing = tableForFixture(nil, &missingURL);

    expect([first profileForDeviceIdentifier:@"iPhone14,6" osBuild:@"21D61"] != nil,
           "bundle-isolation: first bundle resolves its profile");
    expect([first profileForDeviceIdentifier:@"iPhone16,2" osBuild:@"21B91"] == nil,
           "bundle-isolation: first bundle does not see second profile");
    expect([second profileForDeviceIdentifier:@"iPhone16,2" osBuild:@"21B91"] != nil,
           "bundle-isolation: second bundle resolves its profile");
    expect([second profileForDeviceIdentifier:@"iPhone14,6" osBuild:@"21D61"] == nil,
           "bundle-isolation: second bundle does not see first profile");
    expect(missing.coverageCount == 0, "bundle-isolation: missing resource reports no coverage");
    expect([missing profileForDeviceIdentifier:@"iPhone14,6" osBuild:@"21D61"] == nil,
           "bundle-isolation: missing resource falls back");

    for (NSURL *url in @[ firstURL, secondURL, missingURL ]) {
        [NSFileManager.defaultManager removeItemAtURL:url error:nil];
    }
}

/*
 * The table the app actually ships, when it is present. Every entry the index
 * names has to produce a usable profile: an entry that does not would send that
 * device down the download path with no sign that the table meant to cover it.
 */
static void test_shipped_table(const char *path) {
    NSDictionary *shipped = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithUTF8String:path]];
    if (!shipped) {
        fprintf(stderr, "not ok shipped: %s is unreadable\n", path);
        gFailures++;
        return;
    }
    stageTable(shipped);

    NSDictionary *index = shipped[@"index"];
    expect(index.count > 0, "shipped: index is not empty");
    expect(gTable.coverageCount == index.count, "shipped: coverage matches index");

    NSUInteger checked = 0;
    NSUInteger unusable = 0;
    for (NSString *key in index) {
        NSArray<NSString *> *components = [key componentsSeparatedByString:@"|"];
        if (components.count != 2) {
            fprintf(stderr, "not ok shipped: malformed key %s\n", key.UTF8String);
            gFailures++;
            continue;
        }
        RLXKernelOffsetProfile *profile = [gTable profileForDeviceIdentifier:components[0] osBuild:components[1]];
        if (!profile || !profile.rocketProfile.valid) {
            fprintf(stderr, "not ok shipped: %s does not resolve\n", key.UTF8String);
            gFailures++;
            continue;
        }
        rlx_kernel_patchfinder_info patchfinder = profile.patchfinderInfo;
        if (patchfinder.xnu_major == 0 || !profile.isArm64eKernel) {
            fprintf(stderr, "not ok shipped: %s is not an arm64e XNU profile\n", key.UTF8String);
            gFailures++;
            continue;
        }
        /*
         * 表里可以有对 direct-GFX 机型不完整的旧条目，但每一条至少要能被 DMAFail
         * profile 解析；一条谁都用不了的条目只是白占体积。
         */
        if (![profile supportsCPUFamily:CPUFAMILY_ARM_VORTEX_TEMPEST]) {
            fprintf(stderr, "not ok shipped: %s 对任何后端都不可用\n", key.UTF8String);
            gFailures++;
            continue;
        }
        if (!profile.hasGFXOffsets) {
            unusable++;
        }
        checked++;
    }
    fprintf(stdout,
            "    shipped entries checked: %lu (%lu without GFX offsets, " "incomplete for direct-GFX backends)\n",
            (unsigned long)checked,
            (unsigned long)unusable);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: %s <case> [table]\n", argv[0]);
            return 2;
        }

        const char *name = argv[1];
        if (strcmp(name, "round-trip") == 0) {
            test_round_trip();
        } else if (strcmp(name, "ppl-without-gfx") == 0) {
            test_ppl_profile_without_gfx();
        } else if (strcmp(name, "cpu-family-fitness") == 0) {
            test_cpu_family_fitness();
        } else if (strcmp(name, "miss") == 0) {
            test_miss();
        } else if (strcmp(name, "future-schema") == 0) {
            test_rejects_future_schema();
        } else if (strcmp(name, "future-profile-version") == 0) {
            test_rejects_future_profile_version();
        } else if (strcmp(name, "incomplete-profile") == 0) {
            test_rejects_incomplete_profile();
        } else if (strcmp(name, "incomplete-gfx-profile") == 0) {
            test_rejects_incomplete_gfx_profile();
        } else if (strcmp(name, "non-dictionary-profile") == 0) {
            test_rejects_non_dictionary_profile();
        } else if (strcmp(name, "sptm-without-arguments") == 0) {
            test_rejects_sptm_without_arguments();
        } else if (strcmp(name, "out-of-range-index") == 0) {
            test_rejects_out_of_range_index();
        } else if (strcmp(name, "bundle-isolation") == 0) {
            test_bundle_isolation();
        } else if (strcmp(name, "shipped") == 0) {
            if (argc < 3) {
                fprintf(stderr, "usage: %s shipped <table>\n", argv[0]);
                return 2;
            }
            test_shipped_table(argv[2]);
        } else {
            fprintf(stderr, "unknown case %s\n", name);
            return 2;
        }

        if (gBundleURL) {
            [NSFileManager.defaultManager removeItemAtURL:gBundleURL error:nil];
        }
        if (gFailures == 0) {
            fprintf(stdout, "ok %s\n", name);
        }
        return gFailures == 0 ? 0 : 1;
    }
}
