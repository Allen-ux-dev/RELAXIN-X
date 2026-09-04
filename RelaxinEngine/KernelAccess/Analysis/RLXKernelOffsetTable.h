//
//  RLXKernelOffsetTable.h
//  RelaxinEngine
//
//  The kernelcache offsets Relaxin ships instead of computing.
//

#import <Foundation/Foundation.h>

#import <xpc/xpc.h>

#import "RLXKernelInfo.h"
#import "../Exploit/Rocket/Profile/Platform.h"
#import "../Exploit/Rocket/Profile/StaticProfile.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * One kernelcache's worth of precomputed offsets.
 *
 * Everything here was produced by `DevKit/Helpers/KernelOffsets` running the
 * engine's own recovery code over the matching kernelcache, so a profile is
 * interchangeable with the result of opening that file on the device. What it
 * cannot supply is anything the running kernel decides — the slide, the live
 * ptov table, the kernel roots — and it does not pretend to.
 */
@interface RLXKernelOffsetProfile : NSObject

@property(nonatomic, copy, readonly) NSString *deviceIdentifier;
@property(nonatomic, copy, readonly) NSString *osBuild;
/// Digest of the kernelcache the offsets were read from, for diagnostics.
@property(nonatomic, copy, readonly) NSString *kernelcacheDigest;
@property(nonatomic, copy, readonly) NSString *xnuBuild;
@property(nonatomic, copy, readonly) NSString *osVersion;

@property(nonatomic, readonly) uint64_t staticKernelBase;
@property(nonatomic, readonly) uint64_t SPTMArgumentsAddress;
@property(nonatomic, readonly, getter=isArm64eKernel) BOOL arm64eKernel;
@property(nonatomic, readonly, getter=isSPTMDevice) BOOL SPTMDevice;

/// The profile in the shape Rocket publishes and reads back.
@property(nonatomic, readonly) RocketStaticKernelProfile rocketProfile;

/// The patchfinder snapshot stage 04 would otherwise have built from XPF.
@property(nonatomic, readonly) rlx_kernel_patchfinder_info patchfinderInfo;

/// Whether the GFX offsets were recovered from this profile's kernelcache.
@property(nonatomic, readonly, getter=hasGFXOffsets) BOOL GFXOffsets;

/**
 * Whether this profile carries everything `cpuFamily`'s exploit backend reads.
 *
 * A profile can parse cleanly and still be useless on a given chip. A12's DMA
 * backend does not need GFX offsets; every direct-GFX backend does. The caller
 * asks before committing, so the answer is a fallback to reading the
 * kernelcache rather than a failed run.
 */
- (BOOL)supportsCPUFamily:(uint32_t)cpuFamily;

/**
 * An offset dictionary in the shape `jbinfo_initialize_dynamic_offsets`
 * expects, including `kernelConstant.staticBase`.
 *
 * Returned at +0: the name is deliberately outside ARC's `copy` and `new`
 * families so ownership is ARC's alone, and no caller has to know that XPC's
 * constructors hand back a reference ARC did not create.
 */
- (xpc_object_t)offsetDictionary;

- (instancetype)init NS_UNAVAILABLE;

@end

/**
 * A kernel offset table loaded from one host-owned resource bundle.
 *
 * A missing resource, an unreadable one, or a schema the engine does not know
 * are all the same answer — no profile — because every caller's fallback is
 * the same: read the kernelcache the way it always did.
 */
@interface RLXKernelOffsetTable : NSObject

- (instancetype)initWithResourceBundle:(NSBundle *)resourceBundle NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/**
 * The profile for this device and build, or nil when the table cannot serve it.
 *
 * "Cannot serve it" covers a missing entry and a structurally incomplete one.
 * It does not cover chip fitness: ask the returned profile `-supportsCPUFamily:`
 * for that, because this class has no business deciding which device is running.
 */
- (nullable RLXKernelOffsetProfile *)profileForDeviceIdentifier:(NSString *)deviceIdentifier
                                                        osBuild:(NSString *)osBuild;

/// Number of device/build pairs the bundled table covers. Zero when absent.
@property(nonatomic, readonly) NSUInteger coverageCount;

/// When the bundled table was generated, or nil when there is no table.
@property(nonatomic, readonly, nullable) NSString *generatedAt;

@end

NS_ASSUME_NONNULL_END
