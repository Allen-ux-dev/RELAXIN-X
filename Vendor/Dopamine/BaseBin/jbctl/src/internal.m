#import "internal.h"
#import <Foundation/Foundation.h>
#import <CoreServices/LSApplicationProxy.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/log.h>
#import <errno.h>
#import <limits.h>
#import <stdint.h>
#import <stdlib.h>
#import <string.h>
#import <sys/mount.h>
#import <unistd.h>
#import <libjailbreak/stock_fixes.h>

int reboot3(uint64_t flags, ...);

#define RB2_FULLREBOOT (0x8000000000000000llu)

static NSString *const jailbreak_root_prefix = @".jbroot-";
static const unsigned int application_unregistration_settle_seconds = 5;

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allApplications;
- (BOOL)unregisterApplication:(NSURL *)url;
@end

SInt32 CFUserNotificationDisplayAlert(CFTimeInterval timeout,
                                      CFOptionFlags flags,
                                      CFURLRef iconURL,
                                      CFURLRef soundURL,
                                      CFURLRef localizationURL,
                                      CFStringRef alertHeader,
                                      CFStringRef alertMessage,
                                      CFStringRef defaultButtonTitle,
                                      CFStringRef alternateButtonTitle,
                                      CFStringRef otherButtonTitle,
                                      CFOptionFlags *responseFlags) API_AVAILABLE(ios(3.0));

FOUNDATION_EXTERN CFTypeRef _CTServerConnectionCreate(CFAllocatorRef, void *, void *);
FOUNDATION_EXTERN int64_t _CTServerConnectionSetCellularUsagePolicy(CFTypeRef connection,
                                                                    CFStringRef bundleIdentifier,
                                                                    CFDictionaryRef policies);

static int fix_app_network(const char *bundleIdentifierArgument) {
    NSString *bundleIdentifier = [NSString stringWithUTF8String:bundleIdentifierArgument];
    if (bundleIdentifier.length == 0) {
        fprintf(stderr, "ERROR: Bundle identifier must be a non-empty UTF-8 string.\n");
        return EINVAL;
    }

    CFTypeRef connection = _CTServerConnectionCreate(kCFAllocatorDefault, NULL, NULL);
    if (!connection) {
        fprintf(stderr, "ERROR: Unable to connect to CoreTelephony.\n");
        return EIO;
    }

    NSDictionary *policies = @{
        @"kCTCellularDataUsagePolicy" : @"kCTCellularDataUsagePolicyAlwaysAllow",
        @"kCTWiFiDataUsagePolicy" : @"kCTCellularDataUsagePolicyAlwaysAllow",
    };
    int64_t status = _CTServerConnectionSetCellularUsagePolicy(connection,
                                                               (__bridge CFStringRef)bundleIdentifier,
                                                               (__bridge CFDictionaryRef)policies);
    CFRelease(connection);

    if (status != 0) {
        fprintf(stderr,
                "ERROR: Failed to repair network access for %s (CoreTelephony status: %lld).\n",
                bundleIdentifier.UTF8String,
                status);
        return EIO;
    }

    printf("Successfully repaired Wi-Fi and cellular access for %s.\n", bundleIdentifier.UTF8String);
    return 0;
}

static NSString *normalized_application_path(NSString *path) {
    path = path.stringByStandardizingPath;
    if ([path hasPrefix:@"/private/var/"]) {
        path = [path substringFromIndex:@"/private".length];
    }
    return path;
}

static int unregister_applications(NSString *applicationsDirectory) {
    NSError *directoryError = nil;
    NSArray<NSString *> *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:applicationsDirectory
                                                                                     error:&directoryError];
    if (!items) {
        if ([directoryError.domain isEqualToString:NSCocoaErrorDomain]
            && (directoryError.code == NSFileNoSuchFileError || directoryError.code == NSFileReadNoSuchFileError)) {
            return 0;
        }
        printf("Failed to enumerate applications: %s\n", directoryError.localizedDescription.UTF8String);
        return EIO;
    }
    if (items.count == 0)
        return 0;

    NSMutableSet<NSString *> *applicationPaths = [NSMutableSet setWithCapacity:items.count];
    for (NSString *item in items) {
        NSString *path = [applicationsDirectory stringByAppendingPathComponent:item];
        [applicationPaths addObject:normalized_application_path(path)];
    }

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass || ![workspaceClass respondsToSelector:@selector(defaultWorkspace)]) {
        return ENOSYS;
    }

    @try {
        LSApplicationWorkspace *workspace = [workspaceClass defaultWorkspace];
        if (![workspace respondsToSelector:@selector(allApplications)]
            || ![workspace respondsToSelector:@selector(unregisterApplication:)]) {
            return ENOSYS;
        }

        NSArray<LSApplicationProxy *> *applications = workspace.allApplications;
        if (![applications isKindOfClass:NSArray.class])
            return EIO;

        for (LSApplicationProxy *application in applications) {
            NSURL *applicationURL = application.bundleURL;
            NSString *applicationPath = normalized_application_path(applicationURL.path);
            if (!applicationPath || ![applicationPaths containsObject:applicationPath]) {
                continue;
            }
            if (![workspace unregisterApplication:applicationURL]) {
                printf("Failed to unregister application: %s\n", applicationURL.path.fileSystemRepresentation);
                return EIO;
            }
        }
        return 0;
    } @catch (NSException *exception) {
        printf("Failed to unregister applications: %s: %s\n", exception.name.UTF8String, exception.reason.UTF8String);
        return EIO;
    }
}

static void wait_after_application_unregistration(void) {
    sleep(application_unregistration_settle_seconds);
}

static BOOL is_jailbreak_brand(uint64_t value) {
    uint8_t checksum = (uint8_t)(value >> 8) ^ (uint8_t)(value >> 16) ^ (uint8_t)(value >> 24) ^ (uint8_t)(value >> 32)
        ^ (uint8_t)(value >> 40) ^ (uint8_t)(value >> 48) ^ (uint8_t)(value >> 56);
    return checksum == (uint8_t)value;
}

static BOOL is_jailbreak_root_name(NSString *name) {
    if (![name hasPrefix:jailbreak_root_prefix] || name.length != jailbreak_root_prefix.length + 16) {
        return NO;
    }

    const char *brand = [name substringFromIndex:jailbreak_root_prefix.length].UTF8String;
    if (!brand)
        return NO;

    char *end = NULL;
    errno = 0;
    uint64_t value = strtoull(brand, &end, 16);
    return errno == 0 && end && *end == '\0' && is_jailbreak_brand(value);
}

static int unregister_jailbreak_root_applications(NSString *directory) {
    NSArray<NSString *> *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil];
    for (NSString *item in items) {
        if (!is_jailbreak_root_name(item))
            continue;

        NSString *root = [directory stringByAppendingPathComponent:item];
        int status = unregister_applications([root stringByAppendingPathComponent:@"Applications"]);
        if (status != 0)
            return status;
    }
    return 0;
}

static int remove_jailbreak_roots(NSString *directory) {
    NSArray<NSString *> *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil];
    for (NSString *item in items) {
        if (!is_jailbreak_root_name(item))
            continue;

        NSString *root = [directory stringByAppendingPathComponent:item];
        NSError *error = nil;
        if (![[NSFileManager defaultManager] removeItemAtPath:root error:&error]) {
            fprintf(stderr,
                    "Failed to remove jailbreak root: %s: %s\n",
                    root.fileSystemRepresentation,
                    error.localizedDescription.UTF8String);
            return error.code > 0 && error.code <= INT_MAX ? (int)error.code : EIO;
        }
    }
    return 0;
}

static int remove_jailbreak_and_reboot(void) {
    int status = unregister_jailbreak_root_applications(@"/var/containers/Bundle/Application/");
    if (status != 0)
        return status;

    wait_after_application_unregistration();

    status = remove_jailbreak_roots(@"/var/containers/Bundle/Application/");
    if (status != 0)
        return status;

    status = remove_jailbreak_roots(@"/var/mobile/Containers/Shared/AppGroup/");
    if (status != 0)
        return status;

    errno = 0;
    return reboot3(RB2_FULLREBOOT, 0) == 0 ? 0 : (errno ?: EIO);
}
int jbctl_handle_internal(const char *command, int argc, char *argv[]) {
    if (!strcmp(command, "fix_app_network")) {
        return argc == 2 ? fix_app_network(argv[1]) : EINVAL;
    } else if (!strcmp(command, "unregister_apps")) {
        if (argc != 2)
            return EINVAL;
        NSString *applicationsDirectory = [NSString stringWithUTF8String:argv[1]];
        if (!applicationsDirectory)
            return EINVAL;
        int status = unregister_applications(applicationsDirectory);
        if (status != 0)
            return status;
        wait_after_application_unregistration();
        return 0;
    } else if (!strcmp(command, "remove_jailbreak")) {
        return argc == 1 ? remove_jailbreak_and_reboot() : EINVAL;
    } else if (!strcmp(command, "launchd_stash_port")) {
        mach_port_t *selfInitPorts = NULL;
        mach_msg_type_number_t selfInitPortsCount = 0;
        if (mach_ports_lookup(mach_task_self(), &selfInitPorts, &selfInitPortsCount) != 0) {
            printf("ERROR: Failed port lookup on self\n");
            return -1;
        }
        if (selfInitPortsCount < 3) {
            printf("ERROR: Unexpected initports count on self\n");
            return -1;
        }
        if (selfInitPorts[2] == MACH_PORT_NULL) {
            printf("ERROR: Port to stash not set\n");
            return -1;
        }

        printf("Port to stash: %u\n", selfInitPorts[2]);

        mach_port_t launchdTaskPort;
        if (task_for_pid(mach_task_self(), 1, &launchdTaskPort) != 0) {
            printf("task_for_pid on launchd failed\n");
            return -1;
        }
        mach_port_t *launchdInitPorts = NULL;
        mach_msg_type_number_t launchdInitPortsCount = 0;
        if (mach_ports_lookup(launchdTaskPort, &launchdInitPorts, &launchdInitPortsCount) != 0) {
            printf("mach_ports_lookup on launchd failed\n");
            return -1;
        }
        if (launchdInitPortsCount < 3) {
            printf("ERROR: Unexpected initports count on launchd\n");
            return -1;
        }
        launchdInitPorts[2] = selfInitPorts[2]; // Transfer port to launchd
        if (mach_ports_register(launchdTaskPort, launchdInitPorts, launchdInitPortsCount) != 0) {
            printf("ERROR: Failed stashing port into launchd\n");
            return -1;
        }
        mach_port_deallocate(mach_task_self(), launchdTaskPort);
        return 0;
    } else if (!strcmp(command, "startup")) {
        JBLogDebug("jbctl startup: checking userspace panic ...");

        char *panicMessage = NULL;
        if (jbclient_watchdog_get_last_userspace_panic(&panicMessage) == 0) {
            NSString *printMessage = [NSString
                stringWithFormat:
                    @"Relaxin has protected you from a userspace panic by temporarily disabling tweak injection and triggering a userspace reboot instead. A log is available under Analytics in the Preferences app. You can reenable tweak injection in the Relaxin app.\n\nPanic message: \n%s",
                    panicMessage];
            CFUserNotificationDisplayAlert(0,
                                           2 /*kCFUserNotificationCautionAlertLevel*/,
                                           NULL,
                                           NULL,
                                           NULL,
                                           CFSTR("Watchdog Timeout"),
                                           (__bridge CFStringRef)printMessage,
                                           NULL,
                                           NULL,
                                           NULL,
                                           NULL);
            free(panicMessage);
        }

        /************************* roothide specific ***************************/
        //only bootstrap after launchdhook and systemhook available
        JBLogDebug("jbctl startup: bootstrapping launch daemons ...");
        exec_cmd(JBROOT_PATH("/usr/bin/launchctl"), "bootstrap", "system", "/Library/LaunchDaemons", NULL);

        JBLogDebug("jbctl startup: refreshing jailbroken apps ...");

        if (access(JBROOT_PATH("/.disable_auto_uicache"), F_OK) == 0) {
            return 0;
        }
        /************************* roothide specific ***************************/

        exec_cmd(JBROOT_PATH("/usr/bin/uicache"), "-a", NULL);
        fix_app_network("org.coolstar.SileoStore");
    } else if (!strcmp(command, "install_pkg")) {
        if (argc > 1) {
            extern char **environ;
            const char *dpkg = JBROOT_PATH("/usr/bin/dpkg");
            int r = execve(dpkg, (char *const *)(const char *[]){dpkg, "-i", argv[1], NULL}, environ);
            return r;
        }
        return -1;
    }
    return -1;
}
