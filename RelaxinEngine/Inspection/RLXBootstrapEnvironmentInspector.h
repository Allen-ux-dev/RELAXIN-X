#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Immutable, read-only evidence about Relaxin bootstrap roots.
/// Inspection never deletes, renames, publishes, or repairs a root.
@interface RLXBootstrapEnvironmentEvidence : NSObject
@property(nonatomic, readonly) NSUInteger candidateCount;
@property(nonatomic, readonly) BOOL hasInstalledRelaxinMarker;
@property(nonatomic, copy, readonly, nullable) NSString *installedRootPath;
@property(nonatomic, copy, readonly) NSArray<NSString *> *candidateRootPaths;
@property(nonatomic, copy, readonly) NSArray<NSString *> *findings;
@end

@interface RLXBootstrapEnvironmentInspector : NSObject

/// Inspects one or more container directories for `.jbroot-*` entries.
/// This API is intentionally read-only and is also used by host tests.
+ (RLXBootstrapEnvironmentEvidence *)inspectContainerRoots:(NSArray<NSString *> *)roots
                                                     error:(NSError *_Nullable *_Nullable)error
    NS_SWIFT_NAME(inspect(containerRoots:));

/// Inspects the live system container locations without modifying them.
+ (RLXBootstrapEnvironmentEvidence *_Nullable)inspectSystemContainerRootsWithError:
    (NSError *_Nullable *_Nullable)error NS_SWIFT_NAME(inspectSystemContainerRoots());

@end

NS_ASSUME_NONNULL_END
