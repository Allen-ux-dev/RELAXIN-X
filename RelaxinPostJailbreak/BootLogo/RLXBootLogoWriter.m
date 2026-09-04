//
//  RLXBootLogoWriter.m
//  RelaxinPostJailbreak
//

#import "RLXBootLogoWriter.h"

#import <UIKit/UIKit.h>

#import "RLXBootLogoRenderer.h"
#import "../Controller/RLXPostJailbreakLog.h"

#include <errno.h>
#include <math.h>
#include <stdint.h>
#include <unistd.h>

#include <libjailbreak/jbroot.h>

NSErrorUserInfoKey const RLXBootLogoWriterFailurePhaseErrorKey = @"RLXBootLogoWriterFailurePhase";

static NSString *const kBootLogoMarkImageName = @"BootLogoMark";
static NSString *const kBootLogoDestinationPath = @"/basebin/bootlogo.jp2";
static const CGFloat kBootLogoMarkSideLengthInPoints = 128.0;
static const char *const RLXBootLogoLogCategory = "BootLogo";

static NSError *rlx_boot_logo_writer_error(NSString *phase,
                                           int status,
                                           NSString *reason,
                                           NSError *_Nullable underlyingError) {
    NSString *message = [NSString stringWithFormat:@"failed phase=%@ status=%d reason=%@", phase, status, reason];
    rlx_post_jailbreak_log(RLX_POST_JAILBREAK_LOG_ERROR, RLXBootLogoLogCategory, message.UTF8String);

    NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo = [@{
        NSLocalizedDescriptionKey : reason,
        RLXBootLogoWriterFailurePhaseErrorKey : phase,
    } mutableCopy];
    if (underlyingError) {
        userInfo[NSUnderlyingErrorKey] = underlyingError;
    }
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:status userInfo:userInfo];
}

@implementation RLXBootLogoWriter

+ (nullable NSError *)writeBootLogoForDarkAppearance:(BOOL)darkAppearance resourceBundle:(NSBundle *)resourceBundle {
    NSString *appearance = darkAppearance ? @"dark" : @"light";
    NSString *beginMessage = [NSString stringWithFormat:@"phase=render begin appearance=%@", appearance];
    rlx_post_jailbreak_log(RLX_POST_JAILBREAK_LOG_INFO, RLXBootLogoLogCategory, beginMessage.UTF8String);

    UIUserInterfaceStyle interfaceStyle = darkAppearance ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    UITraitCollection *traits = [UITraitCollection traitCollectionWithUserInterfaceStyle:interfaceStyle];
    UIImage *markImage = [UIImage imageNamed:kBootLogoMarkImageName inBundle:resourceBundle
               compatibleWithTraitCollection:traits];
    CGImageRef mark = markImage.CGImage;
    if (!mark) {
        return rlx_boot_logo_writer_error(@"asset", ENOENT, @"The BootLogoMark asset is unavailable.", nil);
    }

    __block CGSize screenSize = CGSizeZero;
    __block CGFloat nativeScale = 0;
    void (^captureMainScreenGeometry)(void) = ^{
        UIScreen *screen = UIScreen.mainScreen;
        screenSize = screen.nativeBounds.size;
        nativeScale = screen.nativeScale;
    };
    if (NSThread.isMainThread) {
        captureMainScreenGeometry();
    } else {
        dispatch_sync(dispatch_get_main_queue(), captureMainScreenGeometry);
    }

    CGFloat markMaximumSideLengthInPixels = round(kBootLogoMarkSideLengthInPoints * nativeScale);
    if (!isfinite(screenSize.width) || !isfinite(screenSize.height) || !isfinite(nativeScale)
        || !isfinite(markMaximumSideLengthInPixels) || screenSize.width <= 0 || screenSize.height <= 0
        || nativeScale <= 0 || markMaximumSideLengthInPixels <= 0 || screenSize.width > (CGFloat)SIZE_MAX
        || screenSize.height > (CGFloat)SIZE_MAX) {
        return rlx_boot_logo_writer_error(@"dimensions",
                                          EINVAL,
                                          @"The main screen pixel dimensions or native scale are unavailable.",
                                          nil);
    }

    size_t width = (size_t)screenSize.width;
    size_t height = (size_t)screenSize.height;
    NSError *renderError = nil;
    NSData *imageData = [RLXBootLogoRenderer jpeg2000DataWithMark:mark width:width height:height
                                    markMaximumSideLengthInPixels:markMaximumSideLengthInPixels
                                                   darkAppearance:darkAppearance
                                                            error:&renderError];
    if (!imageData) {
        return rlx_boot_logo_writer_error(@"render",
                                          EIO,
                                          renderError.localizedDescription ?: @"The boot logo could not be rendered.",
                                          renderError);
    }

    NSString *destinationPath = JBROOT_PATH(kBootLogoDestinationPath);
    if (!destinationPath) {
        return rlx_boot_logo_writer_error(@"path", ENOENT, @"The live jbroot path is unavailable.", nil);
    }

    unlink(destinationPath.fileSystemRepresentation);
    NSError *writeError = nil;
    BOOL written = [imageData writeToFile:destinationPath options:0 error:&writeError];
    if (!written) {
        int status = [writeError.domain isEqualToString:NSPOSIXErrorDomain] ? (int)writeError.code : EIO;
        return rlx_boot_logo_writer_error(@"write",
                                          status,
                                          writeError.localizedDescription ?: @"The boot logo could not be written.",
                                          writeError);
    }

    NSString *message = [NSString
        stringWithFormat:@"phase=write status=0 appearance=%@ " "size=%zux%zu mark=%.0fx%.0fpx bytes=%lu path=%@",
                         appearance,
                         width,
                         height,
                         markMaximumSideLengthInPixels,
                         markMaximumSideLengthInPixels,
                         (unsigned long)imageData.length,
                         destinationPath];
    rlx_post_jailbreak_log(RLX_POST_JAILBREAK_LOG_INFO, RLXBootLogoLogCategory, message.UTF8String);
    return nil;
}

@end
