#import <Foundation/Foundation.h>
#import <substrate.h>
#include <roothide.h>
#include "common.h"

static NSSet<NSString *> *currentJailbreakRootPaths(void) {
    unsigned long long brand = jbrand();
    return [NSSet
        setWithObjects:[NSString stringWithFormat:@"/var/containers/Bundle/Application/.jbroot-%016llX", brand],
                       [NSString stringWithFormat:@"/var/mobile/Containers/Shared/AppGroup/.jbroot-%016llX", brand],
                       nil];
}

static NSSet<NSString *> *(*originalAllowedLockedFilePaths)(id process, SEL selector);

static NSSet<NSString *> *replacementAllowedLockedFilePaths(id process, SEL selector) {
    NSSet *originalPaths = originalAllowedLockedFilePaths(process, selector);
    NSMutableSet *allowedPaths = originalPaths ? [originalPaths mutableCopy] : [NSMutableSet set];
    [allowedPaths unionSet:currentJailbreakRootPaths()];
    return [allowedPaths copy];
}

void runningboarddInit(void) {
    MSImageRef runningBoardImage = MSGetImageByName(
        "/System/Library/PrivateFrameworks/RunningBoard.framework/RunningBoard");
    void *allowedLockedFilePaths = runningBoardImage
        ? MSFindSymbol(runningBoardImage, "-[RBProcess _allowedLockedFilePaths]")
        : NULL;
    if (!allowedLockedFilePaths) {
        RHLogError(@"roothidehooks: missing -[RBProcess _allowedLockedFilePaths]");
        return;
    }

    MSHookFunction(allowedLockedFilePaths,
                   (void *)&replacementAllowedLockedFilePaths,
                   (void **)&originalAllowedLockedFilePaths);
    RHLogDebug(@"RunningBoard hooks initialized");
}
