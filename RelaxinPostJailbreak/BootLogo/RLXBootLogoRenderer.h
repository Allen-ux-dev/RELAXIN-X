//
//  RLXBootLogoRenderer.h
//  RelaxinPostJailbreak
//

#import <Foundation/Foundation.h>

#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const RLXBootLogoRendererErrorDomain;

typedef NS_ERROR_ENUM(RLXBootLogoRendererErrorDomain, RLXBootLogoRendererErrorCode){
    RLXBootLogoRendererErrorRenderFailed = 1,
    RLXBootLogoRendererErrorEncodeFailed,
};

/// Renders the supplied boot logo mark onto a screen-sized light or dark
/// canvas and returns JPEG 2000 data. The caller owns asset selection,
/// native-screen geometry, point-to-pixel conversion, and publication.
@interface RLXBootLogoRenderer : NSObject

+ (nullable NSData *)jpeg2000DataWithMark:(CGImageRef)mark
                                    width:(size_t)width
                                   height:(size_t)height
            markMaximumSideLengthInPixels:(CGFloat)markMaximumSideLengthInPixels
                           darkAppearance:(BOOL)darkAppearance
                                    error:(NSError *_Nullable *_Nullable)error;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
