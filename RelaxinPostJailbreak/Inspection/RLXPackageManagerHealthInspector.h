#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RLXPackageManagerHealthEvidence : NSObject
@property(nonatomic, readonly) BOOL sileoInstalled;
@property(nonatomic, readonly) BOOL sileoHealthy;
@property(nonatomic, readonly) BOOL zebraInstalled;
@property(nonatomic, readonly) BOOL zebraHealthy;
@property(nonatomic, copy, readonly) NSArray<NSString *> *findings;
@end

@interface RLXPackageManagerHealthInspector : NSObject
+ (RLXPackageManagerHealthEvidence *)inspectJailbreakRoot:(NSString *)jailbreakRoot
    NS_SWIFT_NAME(inspect(jailbreakRoot:));
@end

NS_ASSUME_NONNULL_END
