//
//  RLXBootstrapRootScanner.h
//  RelaxinEngine
//
//  Finding an installed jailbreak root, and the brand that names it.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Owns the `.jbroot-<brand>` naming scheme.
 *
 * The brand is persisted state: it is the directory name of an installed
 * bootstrap, so the generation and recovery rules here must not change or
 * existing installs become unreachable. A brand is a 64-bit value whose low
 * byte is an XOR checksum of the upper seven, which is how a jbroot directory
 * is told apart from anything else with a similar name.
 */
@interface RLXBootstrapRootScanner : NSObject

/// Scans both container directories for an installed root. Returns NO only on
/// error; a successful scan that finds nothing leaves `installedRoot` nil.
- (BOOL)scanJailbreakRootsWithInstalledRoot:(NSString *_Nullable *_Nonnull)installedRoot
                                      error:(NSError *_Nullable *_Nullable)error;

/// Whether `name` is a well-formed `.jbroot-` name, and its brand if so.
- (BOOL)rootName:(NSString *)name containsBrand:(uint64_t *)brand;

/// A fresh brand with a valid checksum.
- (uint64_t)generateBrand;

- (NSString *)primaryRootForBrand:(uint64_t)brand;
- (NSString *)secondaryRootForBrand:(uint64_t)brand;

@end

NS_ASSUME_NONNULL_END
