#include <Foundation/Foundation.h>

#include <spawn.h>
#include <roothide.h>

#include "common.h"
#include "Hooking.h"

extern char **environ;

typedef void (^LSOpenCompletionHandler)(BOOL success, NSError *error);
#pragma GCC diagnostic ignored "-Wobjc-method-access"
#pragma GCC diagnostic ignored "-Wunused-variable"

/*lsd can only get path for normal app via proc_pidpath, or we can use
  xpc_connection_get_audit_token([connection _xpcConnection], &token) //_LSCopyExecutableURLForXPCConnection
  proc_pidpath_audittoken(tokenarg, buffer, size) //_LSCopyExecutableURLForAuditToken
  */

@interface LSApplicationProxy : NSObject
+ (id)applicationProxyForIdentifier:(id)arg1;
- (NSURL *)bundleURL;
@end

@interface LSApplicationWorkspace : NSObject
+ (LSApplicationWorkspace *)defaultWorkspace;
- (NSArray *)applicationsAvailableForHandlingURLScheme:(NSString *)scheme;
- (NSArray *)applicationsAvailableForOpeningURL:(NSURL *)url legacySPI:(BOOL)legacySPI;
- (NSArray *)applicationsAvailableForOpeningURL:(NSURL *)url;
@end

BOOL isJailbreakURLScheme(NSString *scheme) {
    NSArray *apps = [[NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace]
        applicationsAvailableForHandlingURLScheme:scheme];
    for (id app in apps) //LSApplicationProxy
    {
        NSURL *bundleURL = [app performSelector:@selector(bundleURL)];
        if (!bundleURL)
            continue;

        if (isJailbreakBundlePath(bundleURL.path.fileSystemRepresentation)) {
            return YES;
        }
    }
    return NO;
}

static const void *kBlockSchemeTagKey = &kBlockSchemeTagKey;

CHDeclareClass(_LSURLOverride);

CHMethod1(id, _LSURLOverride, initWithOriginalURL, NSURL *, url) {
    NSNumber *tag = objc_getAssociatedObject(url, kBlockSchemeTagKey);
    if (tag && tag.boolValue) {
        return nil;
    }
    return CHSuper1(_LSURLOverride, initWithOriginalURL, url);
}

CHDeclareClass(_LSCanOpenURLManager);

CHMethod3(void *,
          _LSCanOpenURLManager,
          getIsURL,
          NSURL *,
          url,
          alwaysCheckable,
          BOOL *,
          pCheckable,
          hasHandler,
          BOOL *,
          pHasHandler) {
    BOOL _checkable = NO;
    BOOL _hasHandler = NO;
    void
        *result = CHSuper3(_LSCanOpenURLManager, getIsURL, url, alwaysCheckable, &_checkable, hasHandler, &_hasHandler);
    if (_checkable || _hasHandler) {
        NSNumber *tag = objc_getAssociatedObject(url, kBlockSchemeTagKey);
        if (tag && tag.boolValue) {
            _hasHandler = NO;
            _checkable = NO;
        }
    }

    if (pCheckable)
        *pCheckable = _checkable;
    if (pHasHandler)
        *pHasHandler = _hasHandler;
    return result;
}

CHMethod5(BOOL,
          _LSCanOpenURLManager,
          canOpenURL,
          NSURL *,
          url,
          publicSchemes,
          BOOL,
          ispublic,
          privateSchemes,
          BOOL,
          isprivate,
          XPCConnection,
          NSXPCConnection *,
          connection,
          error,
          NSError *__autoreleasing *,
          perror) {
    BOOL blocked = NO;

    if (connection) //connection=nil if comes from lsd server
    {
        pid_t pid = connection.processIdentifier;

        if (jbclient_blacklist_check_pid(pid) == true) {
            if (isJailbreakURLScheme(url.scheme)) {
                objc_setAssociatedObject(url, kBlockSchemeTagKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                blocked = YES;
            }
        }
    }

    BOOL ret = CHSuper5(_LSCanOpenURLManager,
                        canOpenURL,
                        url,
                        publicSchemes,
                        ispublic,
                        privateSchemes,
                        isprivate,
                        XPCConnection,
                        connection,
                        error,
                        perror);
    if (blocked) {
        assert(ret == NO);
    }
    return ret;
}

@interface _LSDOpenClient : NSObject
@property(retain, readonly) NSXPCConnection *XPCConnection;
@end

CHDeclareClass(_LSDOpenClient);

CHMethod4(void,
          _LSDOpenClient,
          openApplicationWithIdentifier,
          NSString *,
          identifier,
          options,
          id,
          options,
          useClientProcessHandle,
          BOOL,
          useClientProcessHandle,
          completionHandler,
          LSOpenCompletionHandler,
          completionHandler) {
    BOOL blocked = NO;

    if (self.XPCConnection) {
        pid_t pid = self.XPCConnection.processIdentifier;

        if (jbclient_blacklist_check_pid(pid) == true) {
            LSApplicationProxy *appProxy = [NSClassFromString(@"LSApplicationProxy")
                applicationProxyForIdentifier:identifier];
            if (appProxy && isJailbreakBundlePath(appProxy.bundleURL.path.fileSystemRepresentation)) {
                useClientProcessHandle = YES;

                blocked = YES;
            }
        }
    }

    id newcallback = ^(BOOL success, NSError *error) {
        if (blocked) {
            assert(success == NO);
        }

        return completionHandler(success, error);
    };

    CHSuper4(_LSDOpenClient,
             openApplicationWithIdentifier,
             identifier,
             options,
             options,
             useClientProcessHandle,
             useClientProcessHandle,
             completionHandler,
             newcallback);
}

//16.2(?)+
CHMethod4(void,
          _LSDOpenClient,
          openURL,
          NSURL *,
          url,
          fileHandle,
          id,
          fileHandle,
          options,
          id,
          options,
          completionHandler,
          LSOpenCompletionHandler,
          completionHandler) {
    BOOL blocked = NO;

    if (self.XPCConnection) {
        pid_t pid = self.XPCConnection.processIdentifier;

        if (jbclient_blacklist_check_pid(pid) == true) {
            if (isJailbreakURLScheme(url.scheme)) {
                objc_setAssociatedObject(url, kBlockSchemeTagKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                blocked = YES;
            }
        }
    }

    id newcallback = ^(BOOL success, NSError *error) {
        if (blocked) {
            assert(success == NO);
        }

        return completionHandler(success, error);
    };

    CHSuper4(_LSDOpenClient, openURL, url, fileHandle, fileHandle, options, options, completionHandler, newcallback);
}

//15.0~16.0(?)
CHMethod3(void,
          _LSDOpenClient,
          openURL,
          NSURL *,
          url,
          options,
          id,
          options,
          completionHandler,
          LSOpenCompletionHandler,
          completionHandler) {
    BOOL blocked = NO;

    if (self.XPCConnection) {
        pid_t pid = self.XPCConnection.processIdentifier;

        if (jbclient_blacklist_check_pid(pid) == true) {
            if (isJailbreakURLScheme(url.scheme)) {
                objc_setAssociatedObject(url, kBlockSchemeTagKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                blocked = YES;
            }
        }
    }

    id newcallback = ^(BOOL success, NSError *error) {
        if (blocked) {
            assert(success == NO);
        }

        return completionHandler(success, error);
    };

    CHSuper3(_LSDOpenClient, openURL, url, options, options, completionHandler, newcallback);
}

@interface LSPlugInQueryWithUnits : NSObject
- (id)initWithPlugInUnits:(id)units forDatabaseWithUUID:(id)dbUUID;
@end

@interface _LSQueryContext : NSObject
- (NSMutableDictionary *)_resolveQueries:(NSSet *)queries
                           XPCConnection:(NSXPCConnection *)connection
                                   error:(NSError *)error;
@end

CHDeclareClass(_LSQueryContext);

CHMethod3(NSMutableDictionary *,
          _LSQueryContext,
          _resolveQueries,
          NSSet *,
          queries,
          XPCConnection,
          NSXPCConnection *,
          connection,
          error,
          NSError *,
          error) {
    NSMutableDictionary
        *result = CHSuper3(_LSQueryContext, _resolveQueries, queries, XPCConnection, connection, error, error);
    /*
	result: @{
		queries[0]: @[data1, data2, ...],
		queries[1]: @[data1, data2, ...],
	}
	*/

    if (!result || !connection) {
        return result;
    }

    pid_t pid = connection.processIdentifier;

    if (jbclient_blacklist_check_pid(pid) == false) {
        return result;
    }

    for (id key in result) {
        if ([key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithUnits")] ||
            [key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithIdentifier")] ||
            [key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithQueryDictionary")]) {
            NSMutableArray *plugins = result[key];

            NSMutableIndexSet *removed = [[NSMutableIndexSet alloc] init];
            for (int i = 0; i < [plugins count]; i++) {
                id plugin = plugins[i]; //LSPlugInKitProxy
                id appbundle = [plugin performSelector:@selector(containingBundle)];
                if (!appbundle)
                    continue;

                NSURL *bundleURL = [appbundle performSelector:@selector(bundleURL)];
                if (isJailbreakBundlePath(bundleURL.path.fileSystemRepresentation)) {
                    [removed addIndex:i];
                }
            }

            [plugins removeObjectsAtIndexes:removed];

            if ([key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithUnits")]) {
                NSMutableArray *units = [[key valueForKey:@"_pluginUnits"] mutableCopy];
                [units removeObjectsAtIndexes:removed];
                [key setValue:[units copy] forKey:@"_pluginUnits"];
            }
        } else if ([key isKindOfClass:NSClassFromString(@"LSPlugInQueryAllUnits")]) {
            NSMutableArray *unitsArray = result[key];
            for (int i = 0; i < [unitsArray count]; i++) {
                id unitsResult = unitsArray[i]; //LSPlugInQueryAllUnitsResult

                NSUUID *_dbUUID = [unitsResult valueForKey:@"_dbUUID"];
                NSArray *_pluginUnits = [unitsResult valueForKey:@"_pluginUnits"];
                id unitQuery = [[NSClassFromString(@"LSPlugInQueryWithUnits") alloc] initWithPlugInUnits:_pluginUnits
                                                                                     forDatabaseWithUUID:_dbUUID];
                NSMutableDictionary *queriesResult = [self _resolveQueries:[NSSet setWithObject:unitQuery]
                                                             XPCConnection:connection
                                                                     error:error];
                if (queriesResult) {
                    for (id queryKey in queriesResult) {
                        NSArray *new_pluginUnits = [queryKey valueForKey:@"_pluginUnits"];
                        [unitsResult setValue:new_pluginUnits forKey:@"_pluginUnits"];
                    }
                }
            }
        }
    }

    return result;
}

//or -[Copier initWithSourceURL:uniqueIdentifier:destURL:callbackTarget:selector:options:] in transitd
NSURL *(*orig_LSGetInboxURLForBundleIdentifier)(NSString *bundleIdentifier) = NULL;
NSURL *new_LSGetInboxURLForBundleIdentifier(NSString *bundleIdentifier) {
    NSURL *pathURL = orig_LSGetInboxURLForBundleIdentifier(bundleIdentifier);

    if (![bundleIdentifier hasPrefix:@"com.apple."] &&
        [pathURL.path hasPrefix:@"/var/mobile/Library/Application Support/Containers/"]) {
        pathURL = [NSURL fileURLWithPath:jbroot(pathURL.path)]; //require unsandboxing file-write-read for jbroot:/var/
    }

    return pathURL;
}

int (*orig_LSServer_RebuildApplicationDatabases)() = NULL;
int new_LSServer_RebuildApplicationDatabases() {
    int r = orig_LSServer_RebuildApplicationDatabases();

    if (access(jbroot("/.disable_auto_uicache"), F_OK) == 0)
        return r;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Ensure jailbreak apps are readded to icon cache after the system reloads it
        // A bit hacky, but works
        char *const args[] = {"/usr/bin/uicache", "-a", NULL};
        const char *uicachePath = jbroot(args[0]);
        if (access(uicachePath, F_OK) == 0) {
            pid_t pid = 0;
            int spawnerr = posix_spawn(&pid, uicachePath, NULL, NULL, args, environ);
            if (spawnerr == 0) {
                wait_for_exit(pid);
            }
        }
    });

    return r;
}

void lsdInit(void) {
    MSImageRef coreServicesImage = MSGetImageByName("/System/Library/Frameworks/CoreServices.framework/CoreServices");

    void *_LSGetInboxURLForBundleIdentifier = MSFindSymbol(coreServicesImage, "__LSGetInboxURLForBundleIdentifier");
    if (_LSGetInboxURLForBundleIdentifier) {
        MSHookFunction(_LSGetInboxURLForBundleIdentifier,
                       (void *)&new_LSGetInboxURLForBundleIdentifier,
                       (void **)&orig_LSGetInboxURLForBundleIdentifier);
    }

    void *_LSServer_RebuildApplicationDatabases = MSFindSymbol(coreServicesImage,
                                                               "__LSServer_RebuildApplicationDatabases");
    if (_LSServer_RebuildApplicationDatabases) {
        MSHookFunction(_LSServer_RebuildApplicationDatabases,
                       (void *)&new_LSServer_RebuildApplicationDatabases,
                       (void **)&orig_LSServer_RebuildApplicationDatabases);
    }

    CHLoadLateClass(_LSURLOverride);
    CHLoadLateClass(_LSCanOpenURLManager);
    CHLoadLateClass(_LSDOpenClient);
    CHLoadLateClass(_LSQueryContext);

    CHHook1(_LSURLOverride, initWithOriginalURL);
    CHHook3(_LSCanOpenURLManager, getIsURL, alwaysCheckable, hasHandler);
    CHHook5(_LSCanOpenURLManager, canOpenURL, publicSchemes, privateSchemes, XPCConnection, error);
    CHHook4(_LSDOpenClient, openApplicationWithIdentifier, options, useClientProcessHandle, completionHandler);
    CHHook4(_LSDOpenClient, openURL, fileHandle, options, completionHandler);
    CHHook3(_LSDOpenClient, openURL, options, completionHandler);
    CHHook3(_LSQueryContext, _resolveQueries, XPCConnection, error);

    RHLogDebug(@"lsd hooks initialized");
}
