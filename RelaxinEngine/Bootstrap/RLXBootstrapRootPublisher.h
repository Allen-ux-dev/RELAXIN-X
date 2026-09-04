//
//  RLXBootstrapRootPublisher.h
//  RelaxinEngine
//
//  Publishing the /var/jb symlink that makes a root the live one.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Publishes a prepared root by replacing the well-known symlinks that point
/// at it. This is the step that makes an installed bootstrap the active one.
@interface RLXBootstrapRootPublisher : NSObject

- (int)publishJailbreakRoot:(NSString *)root brand:(uint64_t)brand detail:(NSString *_Nullable *_Nullable)detail;

/// Creates a symlink, or replaces one that already points elsewhere.
/// Bootstrap preparation wires up the root's internal links with these.
- (int)createSymlinkAtPath:(NSString *)path target:(NSString *)target;
- (int)replaceExistingSymlinkAtPath:(NSString *)path
                             target:(NSString *)target
                         underlying:(NSError *_Nullable *_Nullable)underlying;

/// Removes a symlink, reporting NO only when one was there and could not go.
/// Bootstrap preparation uses this to clear stale roots before publishing.
- (BOOL)deleteSymlinkAtPath:(NSString *)path error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
