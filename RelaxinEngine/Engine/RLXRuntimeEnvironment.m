//
//  RLXRuntimeEnvironment.m
//  RelaxinEngine
//

#import "RLXRuntimeEnvironment.h"

static NSURL *rlx_directory_url(NSSearchPathDirectory directory, NSString *fallbackComponent) {
    NSURL *url = [NSFileManager.defaultManager URLForDirectory:directory inDomain:NSUserDomainMask appropriateForURL:nil
                                                        create:NO
                                                         error:nil];
    if (url) {
        return url;
    }
    return [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:fallbackComponent] isDirectory:YES];
}

static NSURL *_Nullable rlx_standardized_file_url(NSURL *url) {
    return url.fileURL ? url.URLByStandardizingPath : nil;
}

@implementation RLXRuntimeEnvironment

+ (RLXRuntimeEnvironment *)defaultEnvironment {
    static RLXRuntimeEnvironment *environment;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        environment = [[RLXRuntimeEnvironment alloc]
            initWithResourceBundle:NSBundle.mainBundle
                  dataDirectoryURL:rlx_directory_url(NSDocumentDirectory, @"Documents")
                 cacheDirectoryURL:rlx_directory_url(NSCachesDirectory, @"Library/Caches")
             temporaryDirectoryURL:[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]];
    });
    return environment;
}

- (nullable instancetype)initWithResourceBundle:(NSBundle *)resourceBundle
                               dataDirectoryURL:(NSURL *)dataDirectoryURL
                              cacheDirectoryURL:(NSURL *)cacheDirectoryURL
                          temporaryDirectoryURL:(NSURL *)temporaryDirectoryURL {
    NSURL *dataURL = rlx_standardized_file_url(dataDirectoryURL);
    NSURL *cacheURL = rlx_standardized_file_url(cacheDirectoryURL);
    NSURL *temporaryURL = rlx_standardized_file_url(temporaryDirectoryURL);
    if (!resourceBundle.bundleURL.fileURL || !dataURL || !cacheURL || !temporaryURL) {
        return nil;
    }

    self = [super init];
    if (self) {
        _resourceBundle = resourceBundle;
        _dataDirectoryURL = [dataURL copy];
        _cacheDirectoryURL = [cacheURL copy];
        _temporaryDirectoryURL = [temporaryURL copy];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return self;
}

@end
