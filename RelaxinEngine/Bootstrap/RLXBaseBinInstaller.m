//
//  RLXBaseBinInstaller.m
//  RelaxinEngine
//

#import "RLXBaseBinInstaller.h"

#import "RLXBootstrapPreparationError.h"
#import "../Log/RLXEngineLog.h"

#include <errno.h>
#include <libjailbreak/util.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static NSString *const RLXBaseBinArchiveName = @"basebin.tar";

@interface RLXBaseBinInstaller ()
- (void)patchBaseBinDaemonPlistsAtRoot:(NSString *)root;
@end

@implementation RLXBaseBinInstaller {
    NSBundle *_resourceBundle;
}

- (instancetype)initWithResourceBundle:(NSBundle *)resourceBundle {
    self = [super init];
    if (self) {
        _resourceBundle = resourceBundle;
    }
    return self;
}

- (int)installBaseBinAtRoot:(NSString *)root
                     detail:(NSString *_Nullable *_Nullable)detail
                 underlying:(NSError *_Nullable *_Nullable)underlying {
    NSString *baseBin = [root stringByAppendingPathComponent:@"basebin"];
    NSError *error = nil;
    int status = 0;
    if ([NSFileManager.defaultManager fileExistsAtPath:baseBin]
        && ![NSFileManager.defaultManager removeItemAtPath:baseBin error:&error]) {
        status = rlx_status_for_error(error);
    }
    if (status != 0) {
        if (detail) {
            *detail = [NSString stringWithFormat:@"existing_basebin=%@", baseBin];
        }
        if (underlying) {
            *underlying = error;
        }
        return status;
    }

    NSString *archive = [_resourceBundle.bundlePath stringByAppendingPathComponent:RLXBaseBinArchiveName];

    int archiveStatus = libarchive_unarchive(archive.fileSystemRepresentation, root.fileSystemRepresentation);
    if (archiveStatus != 0) {
        if (detail) {
            *detail = [NSString stringWithFormat:@"archive=%@\nlibarchive_status=%d", archive, archiveStatus];
        }
        return EBADEXEC;
    }

    [self patchBaseBinDaemonPlistsAtRoot:root];

    NSString *embeddedTrustCache = [baseBin stringByAppendingPathComponent:@"basebin.tc"];
    [NSFileManager.defaultManager removeItemAtPath:embeddedTrustCache error:nil];

    NSString *bundleIdentifier = _resourceBundle.bundleIdentifier;
    NSString *identifierPath = [baseBin stringByAppendingPathComponent:@".AppIdentifier"];
    [bundleIdentifier writeToFile:identifierPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return 0;
}

- (void)patchBaseBinDaemonPlistsAtRoot:(NSString *)root {
    NSString *directory = [root stringByAppendingPathComponent:@"basebin/LaunchDaemons"];
    NSArray<NSString *> *items = [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil];

    for (NSString *item in items) {
        NSString *path = [directory stringByAppendingPathComponent:item];
        NSMutableDictionary *plist = [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy];
        if (!plist) {
            continue;
        }

        NSMutableArray *arguments = [plist[@"ProgramArguments"] mutableCopy];
        if (!arguments) {
            continue;
        }

        BOOL changed = NO;
        for (NSString *argument in [arguments reverseObjectEnumerator]) {
            if ([argument containsString:@"@JBROOT@"]) {
                NSString *patched = [argument stringByReplacingOccurrencesOfString:@"@JBROOT@" withString:root];
                NSUInteger index = [arguments indexOfObject:argument];
                if (index != NSNotFound) {
                    arguments[index] = patched;
                    changed = YES;
                }
            }
        }
        if (changed) {
            plist[@"ProgramArguments"] = arguments;
            [plist writeToFile:path atomically:NO];
        }
    }
}

@end
