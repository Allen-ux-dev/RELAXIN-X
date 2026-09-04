#import <Foundation/Foundation.h>

#import "RLXEngine.h"

#include <errno.h>
#include <stdio.h>

/* RLXEngine creates these collaborators, but runtime ownership does not need
 * their production implementations. Supplying the class symbols keeps this a
 * focused host test of the real RLXEngine initializer. */
static NSArray<NSString *> *gRunContextPackageResourceNames;

@interface RLXEngineTaskQueue : NSObject

- (void)enqueueTasks:(NSArray *)tasks
       updateHandler:(nullable RLXEngineTaskUpdateHandler)updateHandler
          completion:(nullable RLXEngineCompletionHandler)completion;

@end
@implementation RLXEngineTaskQueue

- (void)enqueueTasks:(NSArray *)tasks
       updateHandler:(nullable RLXEngineTaskUpdateHandler)updateHandler
          completion:(nullable RLXEngineCompletionHandler)completion {
    (void)tasks;
    (void)updateHandler;
    if (completion) {
        completion(nil);
    }
}

@end

@class RLXEngineRunContext;

@interface RLXEngineStageRegistry : NSObject

+ (NSArray *)tasksForContext:(RLXEngineRunContext *)context;

@end
@implementation RLXEngineStageRegistry

+ (NSArray *)tasksForContext:(RLXEngineRunContext *)context {
    (void)context;
    return @[];
}

@end

@interface RLXEngineRunContext : NSObject

- (instancetype)initWithManifest:(NSDictionary<RLXEngineManifestKey, NSString *> *)manifest
                         runtimeEnvironment:(RLXRuntimeEnvironment *)runtimeEnvironment
    additionalBootstrapPackageResourceNames:(NSArray<NSString *> *)packageResourceNames;

@end
@implementation RLXEngineRunContext

- (instancetype)initWithManifest:(NSDictionary<RLXEngineManifestKey, NSString *> *)manifest
                         runtimeEnvironment:(RLXRuntimeEnvironment *)runtimeEnvironment
    additionalBootstrapPackageResourceNames:(NSArray<NSString *> *)packageResourceNames {
    (void)manifest;
    (void)runtimeEnvironment;
    self = [super init];
    if (self) {
        gRunContextPackageResourceNames = [packageResourceNames copy];
    }
    return self;
}

@end

@interface RLXPostJailbreakController ()
@property(nonatomic, strong, readwrite) NSBundle *resourceBundle;
@end
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation RLXPostJailbreakController
- (instancetype)initWithResourceBundle:(NSBundle *)resourceBundle {
    self = [super init];
    if (self) {
        _resourceBundle = resourceBundle;
    }
    return self;
}
@end
#pragma clang diagnostic pop

void rlx_engine_log(int32_t level, const char *category, const char *message) {
    (void)level;
    (void)category;
    (void)message;
}

int jbclient_process_checkin(char **rootPath, char **bootUUID, char **sandboxExtensions, bool *fullyDebugged) {
    (void)rootPath;
    (void)bootUUID;
    (void)sandboxExtensions;
    (void)fullyDebugged;
    return -1;
}

bool jbclient_roothide_jailbroken(void) {
    return false;
}

int csops(pid_t pid, unsigned int operation, void *address, size_t size) {
    (void)pid;
    (void)operation;
    (void)address;
    (void)size;
    errno = ENOTSUP;
    return -1;
}

static int gFailures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "not ok %s\n", what);
        gFailures++;
    }
}

static NSURL *standardizedDirectory(NSString *path) {
    return [NSURL fileURLWithPath:path isDirectory:YES].URLByStandardizingPath;
}

static void test_default_environment(void) {
    RLXRuntimeEnvironment *environment = RLXRuntimeEnvironment.defaultEnvironment;
    NSURL *documents = [NSFileManager.defaultManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask
                                                   appropriateForURL:nil
                                                              create:NO
                                                               error:nil];
    NSURL *caches = [NSFileManager.defaultManager URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask
                                                appropriateForURL:nil
                                                           create:NO
                                                            error:nil];

    expect(environment.resourceBundle == NSBundle.mainBundle, "default: resource bundle is the process main bundle");
    expect([environment.dataDirectoryURL isEqual:documents.URLByStandardizingPath],
           "default: data directory remains Documents");
    expect([environment.cacheDirectoryURL isEqual:caches.URLByStandardizingPath],
           "default: cache directory remains Caches");
    expect([environment.temporaryDirectoryURL isEqual:standardizedDirectory(NSTemporaryDirectory())],
           "default: temporary directory remains the system temporary directory");
}

static RLXRuntimeEnvironment *customEnvironment(NSString *name) {
    NSURL *root = standardizedDirectory([NSTemporaryDirectory() stringByAppendingPathComponent:name]);
    return [[RLXRuntimeEnvironment alloc]
        initWithResourceBundle:NSBundle.mainBundle
              dataDirectoryURL:[root URLByAppendingPathComponent:@"one/../data" isDirectory:YES]
             cacheDirectoryURL:[root URLByAppendingPathComponent:@"cache/." isDirectory:YES]
         temporaryDirectoryURL:[root URLByAppendingPathComponent:@"temp/../temporary" isDirectory:YES]];
}

static void test_custom_environment(void) {
    RLXRuntimeEnvironment *environment = customEnvironment(@"Runtime-A");
    NSURL *root = standardizedDirectory([NSTemporaryDirectory() stringByAppendingPathComponent:@"Runtime-A"]);

    expect(environment != nil, "custom: file URLs are accepted");
    expect([environment.dataDirectoryURL isEqual:[root URLByAppendingPathComponent:@"data" isDirectory:YES]],
           "custom: data path is standardized");
    expect([environment.cacheDirectoryURL isEqual:[root URLByAppendingPathComponent:@"cache" isDirectory:YES]],
           "custom: cache path is standardized");
    expect([environment.temporaryDirectoryURL isEqual:[root URLByAppendingPathComponent:@"temporary" isDirectory:YES]],
           "custom: temporary path is standardized");

    NSURL *remote = [NSURL URLWithString:@"https://example.invalid/runtime"];
    expect([[RLXRuntimeEnvironment alloc] initWithResourceBundle:NSBundle.mainBundle dataDirectoryURL:remote
                                               cacheDirectoryURL:environment.cacheDirectoryURL
                                           temporaryDirectoryURL:environment.temporaryDirectoryURL]
               == nil,
           "custom: non-file directory URL is rejected");
}

static void test_engine_ownership(void) {
    RLXRuntimeEnvironment *firstEnvironment = customEnvironment(@"Runtime-First");
    RLXRuntimeEnvironment *secondEnvironment = customEnvironment(@"Runtime-Second");
    NSMutableArray<NSString *> *firstPackageNames = [NSMutableArray arrayWithObject:@"first-package"];
    RLXEngine *firstEngine = [[RLXEngine alloc] initWithRuntimeEnvironment:firstEnvironment
                                   additionalBootstrapPackageResourceNames:firstPackageNames];
    RLXEngine *secondEngine = [[RLXEngine alloc] initWithRuntimeEnvironment:secondEnvironment
                                    additionalBootstrapPackageResourceNames:@[
                                        @"second-package",
                                        @"third-package",
                                    ]];
    RLXEngine *defaultEngine = [[RLXEngine alloc] init];
    RLXEngine *environmentOnlyEngine = [[RLXEngine alloc] initWithRuntimeEnvironment:firstEnvironment];
    [firstPackageNames addObject:@"mutated-after-init"];

    expect(firstEngine.runtimeEnvironment == firstEnvironment, "engine: first instance owns its environment");
    expect(secondEngine.runtimeEnvironment == secondEnvironment, "engine: second instance owns its environment");
    expect(firstEngine.runtimeEnvironment != secondEngine.runtimeEnvironment,
           "engine: instances do not share custom configuration");
    expect(firstEngine.postJailbreakController.resourceBundle == firstEnvironment.resourceBundle,
           "engine: first controller receives the first resource bundle");
    expect(secondEngine.postJailbreakController.resourceBundle == secondEnvironment.resourceBundle,
           "engine: second controller receives the second resource bundle");
    expect(firstEngine.postJailbreakController != secondEngine.postJailbreakController,
           "engine: instances own distinct post-jailbreak controllers");
    expect(defaultEngine.runtimeEnvironment == RLXRuntimeEnvironment.defaultEnvironment,
           "engine: init preserves the native default environment");
    expect([firstEngine.additionalBootstrapPackageResourceNames isEqualToArray:@[ @"first-package" ]],
           "engine: additional package names are copied");
    expect([secondEngine.additionalBootstrapPackageResourceNames isEqualToArray:@[
               @"second-package",
               @"third-package",
           ]],
           "engine: additional package order is preserved");
    expect(firstEngine.additionalBootstrapPackageResourceNames != secondEngine.additionalBootstrapPackageResourceNames,
           "engine: instances do not share additional package configuration");
    expect(defaultEngine.additionalBootstrapPackageResourceNames.count == 0,
           "engine: init has no additional bootstrap packages");
    expect(environmentOnlyEngine.additionalBootstrapPackageResourceNames.count == 0,
           "engine: environment-only init has no additional bootstrap packages");

    gRunContextPackageResourceNames = nil;
    [secondEngine runWithManifest:@{} updateHandler:nil completion:nil];
    expect([gRunContextPackageResourceNames isEqualToArray:secondEngine.additionalBootstrapPackageResourceNames],
           "engine: run context receives the engine package configuration");
}

int main(void) {
    @autoreleasepool {
        test_default_environment();
        test_custom_environment();
        test_engine_ownership();
    }
    if (gFailures == 0) {
        fprintf(stdout, "ok runtime-environment\n");
    }
    return gFailures == 0 ? 0 : 1;
}
