//
//  RLXBaseBinInstaller.h
//  RelaxinEngine
//
//  Installing BaseBin into a prepared jailbreak root.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Unpacks basebin.tar into the root and patches its daemon plists.
@interface RLXBaseBinInstaller : NSObject

- (instancetype)initWithResourceBundle:(NSBundle *)resourceBundle NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (int)installBaseBinAtRoot:(NSString *)root
                     detail:(NSString *_Nullable *_Nullable)detail
                 underlying:(NSError *_Nullable *_Nullable)underlying;

@end

NS_ASSUME_NONNULL_END
