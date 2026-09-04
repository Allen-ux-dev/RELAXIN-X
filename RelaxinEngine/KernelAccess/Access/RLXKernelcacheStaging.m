//
//  RLXKernelcacheStaging.m
//  RelaxinEngine
//

#import "RLXKernelcacheStaging.h"

#include <copyfile.h>
#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>

@implementation RLXKernelcacheStaging {
    NSURL *_dataDirectoryURL;
}

- (instancetype)initWithDataDirectoryURL:(NSURL *)dataDirectoryURL {
    self = [super init];
    if (self) {
        _dataDirectoryURL = [dataDirectoryURL copy];
    }
    return self;
}

- (NSString *)rocketKernelcachePath {
    return [_dataDirectoryURL.path stringByAppendingPathComponent:@"kernelcache"];
}

- (int)stageKernelcacheAtPath:(NSString *)sourcePath failureOperation:(NSString *_Nullable *_Nullable)failureOperation {
    NSString *dataDirectoryPath = _dataDirectoryURL.path;
    if (mkdir(dataDirectoryPath.fileSystemRepresentation, 0755) != 0 && errno != EEXIST) {
        if (failureOperation) {
            *failureOperation = @"create_data_directory";
        }
        return errno ?: EIO;
    }

    struct stat dataDirectoryAttributes = {0};
    if (stat(dataDirectoryPath.fileSystemRepresentation, &dataDirectoryAttributes) != 0) {
        if (failureOperation) {
            *failureOperation = @"inspect_data_directory";
        }
        return errno ?: EIO;
    }
    if (!S_ISDIR(dataDirectoryAttributes.st_mode)) {
        if (failureOperation) {
            *failureOperation = @"inspect_data_directory";
        }
        return ENOTDIR;
    }

    NSString *rocketPath = self.rocketKernelcachePath;
    if ([sourcePath isEqualToString:rocketPath]) {
        return 0;
    }

    NSString *nextPath = [rocketPath stringByAppendingFormat:@".next-%@", NSUUID.UUID.UUIDString];
    if (copyfile(sourcePath.fileSystemRepresentation,
                 nextPath.fileSystemRepresentation,
                 NULL,
                 COPYFILE_DATA | COPYFILE_EXCL)
        != 0) {
        int status = errno ?: EIO;
        unlink(nextPath.fileSystemRepresentation);
        if (failureOperation) {
            *failureOperation = @"copy_kernelcache_data";
        }
        return status;
    }
    if (rename(nextPath.fileSystemRepresentation, rocketPath.fileSystemRepresentation) != 0) {
        int status = errno ?: EIO;
        unlink(nextPath.fileSystemRepresentation);
        if (failureOperation) {
            *failureOperation = @"publish_kernelcache";
        }
        return status;
    }
    return 0;
}

@end
