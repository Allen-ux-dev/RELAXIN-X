//
//  RLXBootstrapArchive.h
//  RelaxinEngine
//
//  Unpacking the bundled bootstrap archive.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Zstandard decompression and tar extraction for the bootstrap payload.
@interface RLXBootstrapArchive : NSObject

- (instancetype)initWithResourceBundle:(NSBundle *)resourceBundle
                 temporaryDirectoryURL:(NSURL *)temporaryDirectoryURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Decompresses and extracts `bootstrap_1900.tar.zst` into `root`.
/// Returns 0, or an errno value with `detail` describing the failing step.
- (int)extractBootstrapArchiveAtRoot:(NSString *)root detail:(NSString *_Nullable *_Nullable)detail;

/// Streams one zstd file to disk. Separate from extraction so a decompression
/// failure is reported as itself rather than as a tar failure.
- (int)decompressZstandardFile:(NSString *)sourcePath
                        toFile:(NSString *)destinationPath
                        detail:(NSString *_Nullable *_Nullable)detail;

@end

NS_ASSUME_NONNULL_END
