#import <Foundation/Foundation.h>
#import <substrate.h>
#include <roothide.h>
#include "common.h"

CFURLRef (*orig__CFCopyHomeDirURLForUser)(const char *username, bool fallBackToHome) = NULL;
CFURLRef new__CFCopyHomeDirURLForUser(const char *username, bool fallBackToHome) {
    CFURLRef url = orig__CFCopyHomeDirURLForUser(username, fallBackToHome);

    char path[PATH_MAX] = {0};
    if (CFURLGetFileSystemRepresentation(url, 0, (UInt8 *)path, sizeof(path))) {
        const char *jbpath = rootfs(path);
        if (strncmp(jbpath, "/rootfs/", sizeof("/rootfs/") - 1) == 0) {
            CFRelease(url);

            const char *newpath = jbroot(path);
            url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault,
                                                          (const UInt8 *)newpath,
                                                          strlen(newpath),
                                                          true);
        }
    }

    return url;
}

__attribute__((visibility("default"))) void pathhook() {
    MSImageRef coreFoundationImage = MSGetImageByName(
        "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation");
    void *_CFCopyHomeDirURLForUser_ptr = MSFindSymbol(coreFoundationImage, "__CFCopyHomeDirURLForUser");
    if (_CFCopyHomeDirURLForUser_ptr) {
        MSHookFunction(_CFCopyHomeDirURLForUser_ptr,
                       (void *)&new__CFCopyHomeDirURLForUser,
                       (void **)&orig__CFCopyHomeDirURLForUser);
        RHLogDebug(@"path hooks initialized");
    }
}
