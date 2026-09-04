//
//  RLXBootLogoRenderer.m
//  RelaxinPostJailbreak
//

#import "RLXBootLogoRenderer.h"

#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>

#include <math.h>
#include <stdint.h>

NSErrorDomain const RLXBootLogoRendererErrorDomain = @"com.aapl.relaxin.post-jailbreak.boot-logo-renderer";

static NSError *rlx_boot_logo_renderer_error(RLXBootLogoRendererErrorCode code, NSString *description) {
    return [NSError errorWithDomain:RLXBootLogoRendererErrorDomain code:code userInfo:@{
        NSLocalizedDescriptionKey : description,
    }];
}

@implementation RLXBootLogoRenderer

+ (nullable NSData *)jpeg2000DataWithMark:(CGImageRef)mark
                                    width:(size_t)width
                                   height:(size_t)height
            markMaximumSideLengthInPixels:(CGFloat)markMaximumSideLengthInPixels
                           darkAppearance:(BOOL)darkAppearance
                                    error:(NSError *_Nullable *_Nullable)error {
    CGImageRef bootLogo = [self renderBootLogoWithMark:mark width:width height:height
                             maximumSideLengthInPixels:markMaximumSideLengthInPixels
                                        darkAppearance:darkAppearance];
    if (!bootLogo) {
        if (error) {
            *error = rlx_boot_logo_renderer_error(RLXBootLogoRendererErrorRenderFailed,
                                                  [NSString stringWithFormat:
                                                                @"CoreGraphics could not render the %zux%zu boot logo.",
                                                                width,
                                                                height]);
        }
        return nil;
    }

    NSData *jpegData = [self encodeJPEG2000:bootLogo];
    CGImageRelease(bootLogo);
    if (!jpegData && error) {
        *error = rlx_boot_logo_renderer_error(RLXBootLogoRendererErrorEncodeFailed,
                                              @"ImageIO could not encode the boot logo as JPEG 2000.");
    }
    return jpegData;
}

+ (CGImageRef _Nullable)renderBootLogoWithMark:(CGImageRef)mark
                                         width:(size_t)width
                                        height:(size_t)height
                     maximumSideLengthInPixels:(CGFloat)maximumSideLengthInPixels
                                darkAppearance:(BOOL)darkAppearance {
    if (!mark || width == 0 || height == 0 || width > SIZE_MAX / 4 || !isfinite(maximumSideLengthInPixels)
        || maximumSideLengthInPixels <= 0) {
        return NULL;
    }

    size_t bytesPerRow = width * 4;
    size_t markWidth = CGImageGetWidth(mark);
    size_t markHeight = CGImageGetHeight(mark);
    if (height > SIZE_MAX / bytesPerRow || markWidth == 0 || markHeight == 0) {
        return NULL;
    }

    CGFloat maximumWidth = MIN(maximumSideLengthInPixels, (CGFloat)width);
    CGFloat maximumHeight = MIN(maximumSideLengthInPixels, (CGFloat)height);
    CGFloat scale = MIN(maximumWidth / (CGFloat)markWidth, maximumHeight / (CGFloat)markHeight);
    CGFloat fittedWidth = floor(MIN(maximumWidth, (CGFloat)markWidth * scale));
    CGFloat fittedHeight = floor(MIN(maximumHeight, (CGFloat)markHeight * scale));
    if (!isfinite(scale) || fittedWidth < 1 || fittedHeight < 1) {
        return NULL;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (!colorSpace) {
        return NULL;
    }
    CGContextRef context = CGBitmapContextCreate(NULL,
                                                 width,
                                                 height,
                                                 8,
                                                 bytesPerRow,
                                                 colorSpace,
                                                 (CGBitmapInfo)kCGImageAlphaNoneSkipFirst);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        return NULL;
    }

    CGFloat backgroundComponent = darkAppearance ? 0.0 : 1.0;
    CGContextSetRGBFillColor(context, backgroundComponent, backgroundComponent, backgroundComponent, 1.0);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));

    // Preserve the hard edges of the block mark at screen resolution.
    CGContextSetInterpolationQuality(context, kCGInterpolationNone);
    CGRect markRect = CGRectMake(floor(((CGFloat)width - fittedWidth) * 0.5),
                                 floor(((CGFloat)height - fittedHeight) * 0.5),
                                 fittedWidth,
                                 fittedHeight);
    CGContextDrawImage(context, markRect, mark);

    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return image;
}

+ (NSData *_Nullable)encodeJPEG2000:(CGImageRef)image {
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,
                                                                         CFSTR("public.jpeg-2000"),
                                                                         1,
                                                                         NULL);
    if (!destination) {
        return nil;
    }
    CGImageDestinationAddImage(destination, image, (__bridge CFDictionaryRef) @{
        (__bridge NSString *)kCGImageDestinationLossyCompressionQuality : @1.0,
    });
    BOOL finalized = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    return finalized ? data.copy : nil;
}

@end
