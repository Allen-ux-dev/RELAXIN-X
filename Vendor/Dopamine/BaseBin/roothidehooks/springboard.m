#import <Foundation/Foundation.h>
#import <fcntl.h>
#include <roothide.h>

#include "common.h"
#include "Hooking.h"

static int (*originalFcntl)(int fileDescriptor, int command, ...);

static int replacementFcntl(int fileDescriptor, int command, ...) {
    if (command == F_SETPROTECTIONCLASS) {
        char filePath[PATH_MAX];
        if (originalFcntl(fileDescriptor, F_GETPATH, filePath) != -1
            && isSubPathOf(filePath, jbroot("/var/mobile/Library/SplashBoard/Snapshots/"))) {
            return 0;
        }
    }

    va_list arguments;
    va_start(arguments, command);
    const void *argument1 = va_arg(arguments, void *);
    const void *argument2 = va_arg(arguments, void *);
    const void *argument3 = va_arg(arguments, void *);
    const void *argument4 = va_arg(arguments, void *);
    const void *argument5 = va_arg(arguments, void *);
    const void *argument6 = va_arg(arguments, void *);
    const void *argument7 = va_arg(arguments, void *);
    const void *argument8 = va_arg(arguments, void *);
    const void *argument9 = va_arg(arguments, void *);
    const void *argument10 = va_arg(arguments, void *);
    va_end(arguments);

    return originalFcntl(fileDescriptor,
                         command,
                         argument1,
                         argument2,
                         argument3,
                         argument4,
                         argument5,
                         argument6,
                         argument7,
                         argument8,
                         argument9,
                         argument10);
}

@interface XBSnapshotContainerIdentity : NSObject
@property NSString *bundleIdentifier;
@end

CHDeclareClass(XBSnapshotContainerIdentity);

CHMethod0(NSString *, XBSnapshotContainerIdentity, snapshotContainerPath) {
    NSString *path = CHSuper0(XBSnapshotContainerIdentity, snapshotContainerPath);

    if ([path hasPrefix:@"/var/mobile/Library/SplashBoard/Snapshots/"]
        && (![self.bundleIdentifier hasPrefix:@"com.apple."]
            || is_apple_internal_identifier(self.bundleIdentifier.UTF8String))) {
        path = jbroot(path);
    }

    return path;
}

static const void *kDenyQueryTagKey = &kDenyQueryTagKey;

CHDeclareClass(FBSApplicationLibrary);

CHMethod1(id, FBSApplicationLibrary, applicationInfoForBundleIdentifier, NSString *, bundleIdentifier) {
    id result = CHSuper1(FBSApplicationLibrary, applicationInfoForBundleIdentifier, bundleIdentifier);
    NSURL *executableURL = [result performSelector:@selector(executableURL)];

    NSNumber *tag = objc_getAssociatedObject(bundleIdentifier, kDenyQueryTagKey);
    if (tag.boolValue) {
        if (is_sensitive_app_identifier(bundleIdentifier.UTF8String)) {
            return nil;
        }

        if (result && executableURL && isJailbreakBundlePath(executableURL.path.fileSystemRepresentation)) {
            return nil;
        }
    }

    return result;
}

CHDeclareClass(FBSystemService);

CHMethod5(void *,
          FBSystemService,
          openApplication,
          NSString *,
          bundleIdentifier,
          withOptions,
          id,
          options,
          originator,
          id,
          originator,
          requestID,
          void *,
          requestID,
          completion,
          void *,
          completion) {
    id currentContext = [NSClassFromString(@"BSServiceConnection") performSelector:@selector(currentContext)];
    id remoteProcess = [currentContext performSelector:@selector(remoteProcess)];
    NSNumber *processIdentifier = [remoteProcess valueForKey:@"_pid"];
    pid_t pid = processIdentifier.intValue;

    if (jbclient_blacklist_check_pid(pid)) {
        objc_setAssociatedObject(bundleIdentifier, kDenyQueryTagKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    return CHSuper5(FBSystemService,
                    openApplication,
                    bundleIdentifier,
                    withOptions,
                    options,
                    originator,
                    originator,
                    requestID,
                    requestID,
                    completion,
                    completion);
}

void sbInit(void) {
    CHLoadLateClass(XBSnapshotContainerIdentity);
    CHLoadLateClass(FBSApplicationLibrary);
    CHLoadLateClass(FBSystemService);

    CHHook0(XBSnapshotContainerIdentity, snapshotContainerPath);
    CHHook1(FBSApplicationLibrary, applicationInfoForBundleIdentifier);
    CHHook5(FBSystemService, openApplication, withOptions, originator, requestID, completion);

    MSHookFunction((void *)&fcntl, (void *)&replacementFcntl, (void **)&originalFcntl);

    RHLogDebug(@"SpringBoard hooks initialized");
}
