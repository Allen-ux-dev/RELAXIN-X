#import "RLXBootstrapRemover.h"

#import "../Controller/RLXPostJailbreakLog.h"

#include <libjailbreak/jbclient_xpc.h>
#include <libjailbreak/util.h>

#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>

static const char *const RLXJailbreakRootPrefix = ".jbroot-";
static const size_t RLXJailbreakRootBrandLength = sizeof(uint64_t) * sizeof(char) * 2;

static BOOL rlx_is_jailbreak_brand(uint64_t value) {
    uint8_t checksum = (uint8_t)(value >> 8) ^ (uint8_t)(value >> 16) ^ (uint8_t)(value >> 24) ^ (uint8_t)(value >> 32)
        ^ (uint8_t)(value >> 40) ^ (uint8_t)(value >> 48) ^ (uint8_t)(value >> 56);
    return checksum == (uint8_t)value;
}

static BOOL rlx_is_jailbreak_root_name(const char *name) {
    size_t prefixLength = strlen(RLXJailbreakRootPrefix);
    if (strlen(name) != prefixLength + RLXJailbreakRootBrandLength) {
        return NO;
    }
    if (strncmp(name, RLXJailbreakRootPrefix, prefixLength) != 0) {
        return NO;
    }

    char *end = NULL;
    uint64_t value = strtoull(name + prefixLength, &end, 16);
    if (!end || *end != '\0') {
        return NO;
    }
    return rlx_is_jailbreak_brand(value);
}

static NSError *_Nullable rlx_unregister_jailbreak_apps(NSString *root) {
    NSString *applicationsDirectory = [root stringByAppendingPathComponent:@"Applications"];
    NSArray<NSString *> *applications = [NSFileManager.defaultManager contentsOfDirectoryAtPath:applicationsDirectory
                                                                                          error:nil];
    if (applications.count == 0) {
        return nil;
    }

    NSString *jbctlPath = [root stringByAppendingPathComponent:@"basebin/jbctl"];
    pid_t pid = -1;
    errno = 0;
    int status = exec_cmd_nowait(&pid,
                                 jbctlPath.fileSystemRepresentation,
                                 "internal",
                                 "unregister_apps",
                                 applicationsDirectory.fileSystemRepresentation,
                                 NULL);
    if (status == 0) {
        int waitStatus = cmd_wait_for_exit(pid);
        if (waitStatus == -1) {
            status = errno ?: EIO;
        } else if (WIFEXITED(waitStatus)) {
            status = WEXITSTATUS(waitStatus);
        } else {
            status = EIO;
        }
    }
    if (status == 0) {
        return nil;
    }

    int errorCode = status > 0 ? status : EIO;
    NSString *message = [NSString
        stringWithFormat:@"application unregistration failed path=%@ status=%d", applicationsDirectory, status];
    rlx_post_jailbreak_log(RLX_POST_JAILBREAK_LOG_ERROR, "RLXBootstrapRemoval", message.UTF8String);
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:errorCode userInfo:@{
        NSLocalizedDescriptionKey : @"Jailbreak applications could not be " @"unregistered.",
        NSLocalizedFailureReasonErrorKey : message,
    }];
}

static NSError *_Nullable rlx_remove_jailbreak_roots(NSString *directory,
                                                     BOOL unregisterApps,
                                                     NSUInteger *removedCount) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSError *error = nil;

    for (NSString *item in [fileManager contentsOfDirectoryAtPath:directory error:nil]) {
        if (!rlx_is_jailbreak_root_name(item.UTF8String)) {
            continue;
        }

        NSString *path = [directory stringByAppendingPathComponent:item];
        if (unregisterApps) {
            error = rlx_unregister_jailbreak_apps(path);
            if (error) {
                return error;
            }
        }
        NSString *message = [NSString stringWithFormat:@"remove %@ @ %@", item, directory];
        rlx_post_jailbreak_log(RLX_POST_JAILBREAK_LOG_VERBOSE, "RLXBootstrapRemoval", message.UTF8String);
        if (![fileManager removeItemAtPath:path error:&error]) {
            NSString *failureMessage = [NSString
                stringWithFormat:@"remove failed path=%@ error=%@", path, error.localizedDescription];
            rlx_post_jailbreak_log(RLX_POST_JAILBREAK_LOG_ERROR, "RLXBootstrapRemoval", failureMessage.UTF8String);
            return error;
        }
        *removedCount += 1;
    }

    return nil;
}

@implementation RLXBootstrapRemover

+ (nullable NSError *)removeBootstrap {
    rlx_post_jailbreak_log(RLX_POST_JAILBREAK_LOG_INFO, "RLXBootstrapRemoval", "Removing Jailbreak");

    BOOL unregisterApps = jbclient_roothide_jailbroken();
    NSUInteger primaryRemovedCount = 0;
    NSError *error = rlx_remove_jailbreak_roots(@"/var/containers/Bundle/Application/",
                                                unregisterApps,
                                                &primaryRemovedCount);
    if (error) {
        return error;
    }

    NSUInteger secondaryRemovedCount = 0;
    error = rlx_remove_jailbreak_roots(@"/var/mobile/Containers/Shared/AppGroup/", NO, &secondaryRemovedCount);
    if (error) {
        return error;
    }

    NSString *completionMessage = [NSString stringWithFormat:@"Bootstrap Removal Complete (%lu primary, %lu secondary)",
                                                             (unsigned long)primaryRemovedCount,
                                                             (unsigned long)secondaryRemovedCount];
    rlx_post_jailbreak_log(RLX_POST_JAILBREAK_LOG_VERBOSE, "RLXBootstrapRemoval", completionMessage.UTF8String);
    return nil;
}

@end
