#import <Foundation/Foundation.h>
#import <substrate.h>
#include <roothide.h>
#include "common.h"

// The iPhoneOS 27.0 SDK marks xpc_connection_get_pid() unavailable on iOS,
// but the symbol still exists at runtime. Alias it under a different C name
// to bypass the SDK availability check.
pid_t xpc_connection_get_pid_alias(xpc_connection_t connection) __asm("_xpc_connection_get_pid");
#define xpc_connection_get_pid xpc_connection_get_pid_alias

#define PROC_PIDPATHINFO_MAXSIZE        (4*MAXPATHLEN)

pid_t __thread gCurrentClientPid = 0;

BOOL preferencePlistNeedsRedirection(NSString *plistPath) {
    NSString *pattern = @"^(/private)?/var/(\\w+)/Library/Preferences/";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:plistPath options:0 range:NSMakeRange(0, plistPath.length)];
    if (!match)
        return NO;

    NSString *plistName = plistPath.lastPathComponent;

    NSString *identifier = [plistName hasSuffix:@".plist"] ? plistName.stringByDeletingPathExtension : plistName;
    if (is_apple_internal_identifier(identifier.UTF8String))
        return YES;

    if ([plistName hasPrefix:@"com.apple."] || [plistName hasPrefix:@"group.com.apple."] ||
        [plistName hasPrefix:@"systemgroup.com.apple."])
        return NO;

    NSArray *additionalSystemPlistNames = @[
        @".GlobalPreferences.plist",
        @".GlobalPreferences_m.plist",
        @"bluetoothaudiod.plist",
        @"NetworkInterfaces.plist",
        @"OSThermalStatus.plist",
        @"preferences.plist",
        @"osanalyticshelper.plist",
        @"UserEventAgent.plist",
        @"wifid.plist",
        @"dprivacyd.plist",
        @"silhouette.plist",
        @"nfcd.plist",
        @"kNPProgressTrackerDomain.plist",
        @"siriknowledged.plist",
        @"UITextInputContextIdentifiers.plist",
        @"mobile_storage_proxy.plist",
        @"splashboardd.plist",
        @"mobile_installation_proxy.plist",
        @"languageassetd.plist",
        @"ptpcamerad.plist",
        @"com.google.gmp.measurement.monitor.plist",
        @"com.google.gmp.measurement.plist",
    ];

    return ![additionalSystemPlistNames containsObject:plistName];
}

BOOL (*orig_CFPrefsGetPathForTriplet)(CFStringRef, CFStringRef, BOOL, CFStringRef, UInt8 *);
BOOL new_CFPrefsGetPathForTriplet(CFStringRef identifier,
                                  CFStringRef user,
                                  BOOL byHost,
                                  CFStringRef container,
                                  UInt8 *buffer) {
    BOOL orig = orig_CFPrefsGetPathForTriplet(identifier, user, byHost, container, buffer);

    if (orig && buffer) {
        NSString *origPath = [NSString stringWithUTF8String:(char *)buffer];
        BOOL needsRedirection = preferencePlistNeedsRedirection(origPath);

        if (needsRedirection) {
            if (gCurrentClientPid > 0 && jbclient_blacklist_check_pid(gCurrentClientPid) == true) {
                needsRedirection = NO;
            }
        }

        if (needsRedirection) {
            const char *newpath = jbroot(origPath.UTF8String);
            //buffer size=1024 in CFXPreferences_fileProtectionClassForIdentifier_user_host_container___block_invoke
            if (strlen(newpath) < 1024) {
                strcpy((char *)buffer, newpath);
            } else {
                return NO;
            }
        }
    }

    return orig;
}

void *(*orig__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__)(id self,
                                                                   xpc_object_t message,
                                                                   xpc_connection_t connection,
                                                                   void *replyHandler);
void *(*LEGACY_orig__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__)(id self,
                                                                          SEL selector,
                                                                          xpc_object_t message,
                                                                          xpc_connection_t connection,
                                                                          void *replyHandler);
void *DISPATCH_orig__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__(id self,
                                                                         xpc_object_t message,
                                                                         xpc_connection_t connection,
                                                                         void *replyHandler) {
    if (@available(iOS 17.0, *)) {
        return orig__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__(self, message, connection, replyHandler);
    } else {
        return LEGACY_orig__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__(self,
                                                                                nil,
                                                                                message,
                                                                                connection,
                                                                                replyHandler);
    }
}
void *new__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__(id self,
                                                               xpc_object_t message,
                                                               xpc_connection_t connection,
                                                               void *replyHandler) {
    pid_t clientPid = xpc_connection_get_pid(connection);

    gCurrentClientPid = clientPid;

    return DISPATCH_orig__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__(self, message, connection, replyHandler);
}
void *LEGACY_new__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__(id self,
                                                                      SEL selector,
                                                                      xpc_object_t message,
                                                                      xpc_connection_t connection,
                                                                      void *replyHandler) {
    return new__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__(self, message, connection, replyHandler);
}

void cfprefsdInit(void) {
    MSImageRef coreFoundationImage = MSGetImageByName(
        "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation");

    void *CFPrefsGetPathForTriplet_ptr = MSFindSymbol(coreFoundationImage, "__CFPrefsGetPathForTriplet");
    if (CFPrefsGetPathForTriplet_ptr) {
        MSHookFunction(CFPrefsGetPathForTriplet_ptr,
                       (void *)&new_CFPrefsGetPathForTriplet,
                       (void **)&orig_CFPrefsGetPathForTriplet);
    }

    // clang-format off
    void *__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__ =
        MSFindSymbol(coreFoundationImage, "-[CFPrefsDaemon handleMessage:fromPeer:replyHandler:]");
    // clang-format on
    if (__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__) {
        if (@available(iOS 17.0, *)) {
            MSHookFunction(__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__,
                           (void *)new__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__,
                           (void **)&orig__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__);
        } else {
            MSHookFunction(__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__,
                           (void *)LEGACY_new__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__,
                           (void **)&LEGACY_orig__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__);
        }
    }

    RHLogDebug(@"cfprefsd hooks initialized");
}
