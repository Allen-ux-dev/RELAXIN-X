//
//  RLXBootstrapRootPublisher.m
//  RelaxinEngine
//

#import "RLXBootstrapRootPublisher.h"

#import "RLXBootstrapPreparationError.h"
#import "../Log/RLXEngineLog.h"

#include <errno.h>
#include <libjailbreak/info.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

@interface RLXBootstrapRootPublisher ()
@end

@implementation RLXBootstrapRootPublisher

- (int)publishJailbreakRoot:(NSString *)root brand:(uint64_t)brand detail:(NSString *_Nullable *_Nullable)detail {
    char *rootCopy = strdup(root.fileSystemRepresentation);
    if (!rootCopy) {
        if (detail) {
            *detail = @"root_path_allocation=false";
        }
        return ENOMEM;
    }

    free(gSystemInfo.jailbreakInfo.rootPath);
    gSystemInfo.jailbreakInfo.rootPath = rootCopy;
    gSystemInfo.jailbreakInfo.jbrand = brand;
    return 0;
}

- (BOOL)deleteSymlinkAtPath:(NSString *)path error:(NSError *_Nullable *_Nullable)error {
    NSDictionary<NSFileAttributeKey, id> *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path
                                                                                                      error:error];
    if (!attributes) {
        return YES;
    }
    if (attributes[NSFileType] == NSFileTypeSymbolicLink) {
        return [NSFileManager.defaultManager removeItemAtPath:path error:error];
    }
    return NO;
}

- (int)createSymlinkAtPath:(NSString *)path target:(NSString *)target {
    return symlink(target.fileSystemRepresentation, path.fileSystemRepresentation) == 0 ? 0 : (errno ?: EIO);
}

- (int)replaceExistingSymlinkAtPath:(NSString *)path
                             target:(NSString *)target
                         underlying:(NSError *_Nullable *_Nullable)underlying {
    NSError *error = nil;
    if (![NSFileManager.defaultManager removeItemAtPath:path error:&error]) {
        if (underlying) {
            *underlying = error;
        }
        return rlx_status_for_error(error);
    }
    return [self createSymlinkAtPath:path target:target];
}

@end
