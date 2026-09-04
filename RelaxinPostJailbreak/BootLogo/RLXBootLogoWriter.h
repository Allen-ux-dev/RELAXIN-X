//
//  RLXBootLogoWriter.h
//  RelaxinPostJailbreak
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorUserInfoKey const RLXBootLogoWriterFailurePhaseErrorKey;

/// Selects the light or dark mark asset, renders it for the main screen's
/// native pixel geometry, and writes it to the active jailbreak root.
@interface RLXBootLogoWriter : NSObject

+ (nullable NSError *)writeBootLogoForDarkAppearance:(BOOL)darkAppearance resourceBundle:(NSBundle *)resourceBundle;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
