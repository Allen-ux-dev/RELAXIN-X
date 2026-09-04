#import <Foundation/Foundation.h>

#import "RLXBootstrapFinalizer.h"
#import "RLXEngine.h"

#include <errno.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdio.h>
#include <sys/types.h>

NSErrorDomain const RLXEngineErrorDomain = @"com.aapl.relaxin.engine";
RLXEngineErrorUserInfoKey const RLXEngineDiagnosticKey = @"RLXEngineDiagnostic";

static int gFailures;
static uid_t gRealUserID = 501;
static int gHelperInstallStatus;
static int gDirectInstallStatus;
static NSString *gTestRoot;
static NSMutableArray<NSString *> *gOperations;
static NSMutableArray<NSString *> *gInstalledPackagePaths;
static NSString *gDpkgDebInputPath;
static NSString *gDpkgDebOutputPath;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "not ok %s\n", what);
        gFailures++;
    }
}

uid_t rlx_test_getuid(void) {
    return gRealUserID;
}

char *get_jbroot(void) {
    return (char *)gTestRoot.fileSystemRepresentation;
}

int jbclient_trust_file_by_path(const char *path) {
    (void)path;
    return 0;
}

bool jbclient_palehide_present(void) {
    return false;
}

void rlx_engine_log(int32_t level, const char *category, const char *message) {
    (void)level;
    (void)category;
    (void)message;
}

static NSString *hostPathForRootfsPath(NSString *path) {
    static NSString *const prefix = @"/rootfs";
    return [path hasPrefix:prefix] ? [path substringFromIndex:prefix.length] : path;
}

static int recordPackageInstall(NSString *path, int status) {
    [gInstalledPackagePaths addObject:path];
    [gOperations addObject:[@"package:" stringByAppendingString:path.lastPathComponent.stringByDeletingPathExtension]];
    return status;
}

int exec_cmd(const char *binary, ...) {
    NSMutableArray<NSString *> *arguments = [NSMutableArray array];
    va_list list;
    va_start(list, binary);
    const char *argument;
    while ((argument = va_arg(list, const char *))) {
        [arguments addObject:@(argument)];
    }
    va_end(list);

    NSString *binaryPath = @(binary);
    if ([binaryPath hasSuffix:@"/basebin/jbctl"] && arguments.count == 3 && [arguments[0] isEqualToString:@"internal"]
        && [arguments[1] isEqualToString:@"install_pkg"]) {
        return recordPackageInstall(arguments[2], gHelperInstallStatus);
    }

    if ([binaryPath hasSuffix:@"/usr/bin/dpkg-deb"] && arguments.count == 3 && [arguments[0] isEqualToString:@"-R"]) {
        gDpkgDebInputPath = arguments[1];
        gDpkgDebOutputPath = arguments[2];
        [gOperations addObject:@"libroot"];

        NSString *hostOutput = hostPathForRootfsPath(gDpkgDebOutputPath);
        NSString *libraryDirectory = [hostOutput stringByAppendingPathComponent:@"var/jb/usr/lib"];
        [NSFileManager.defaultManager createDirectoryAtPath:libraryDirectory withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil];
        [@"fixture-libroot" writeToFile:[libraryDirectory stringByAppendingPathComponent:@"libroot.dylib"]
                             atomically:YES
                               encoding:NSUTF8StringEncoding
                                  error:nil];
        return 0;
    }

    return 0;
}

int exec_cmd_roothide_spawn(pid_t *pid,
                            const char *path,
                            const posix_spawn_file_actions_t *fileActions,
                            const posix_spawnattr_t *attributes,
                            char *const arguments[],
                            char *const environment[]) {
    (void)path;
    (void)fileActions;
    (void)attributes;
    (void)environment;
    if (pid) {
        *pid = 100;
    }
    recordPackageInstall(@(arguments[2]), gDirectInstallStatus);
    return 0;
}

int cmd_wait_for_exit(pid_t pid) {
    (void)pid;
    return gDirectInstallStatus;
}

static NSString *makeTestDirectory(void) {
    NSString *path = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[NSString
                                           stringWithFormat:@"RelaxinBootstrapFinalizer-%@", NSUUID.UUID.UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

static void writeFixture(NSString *contents, NSString *path) {
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    [contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static NSBundle *makeResourceBundle(NSString *directory, NSArray<NSString *> *packageResourceNames) {
    NSString *bundlePath = [directory stringByAppendingPathComponent:@"Fixture.bundle"];
    writeFixture(
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>" "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" " "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">" "<plist version=\"1.0\"><dict>" "<key>CFBundleIdentifier</key><string>com.aapl.relaxin.tests.bootstrap</string>" "</dict></plist>",
        [bundlePath stringByAppendingPathComponent:@"Info.plist"]);
    for (NSString *name in packageResourceNames) {
        writeFixture([@"fixture-" stringByAppendingString:name],
                     [bundlePath stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"deb"]]);
    }
    return [NSBundle bundleWithPath:bundlePath];
}

static void prepareJailbreakRoot(NSString *directory, BOOL corePackagesAreCurrent) {
    gTestRoot = [directory stringByAppendingPathComponent:@"jbroot"];
    writeFixture(@"shell", [gTestRoot stringByAppendingPathComponent:@"bin/sh"]);
    writeFixture(@"shell", [gTestRoot stringByAppendingPathComponent:@"usr/bin/sh"]);
    [NSFileManager.defaultManager createDirectoryAtPath:[gTestRoot stringByAppendingPathComponent:@"usr/lib"]
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    NSString *status = corePackagesAreCurrent
        ? @"Package: libkrw0-dopamine\nVersion: 2.0.4\n\n" "Package: dopamine-basebin-link\nVersion: 1.0.0\n"
        : @"";
    writeFixture(status, [gTestRoot stringByAppendingPathComponent:@"var/lib/dpkg/status"]);
}

static void resetCapture(void) {
    gRealUserID = 501;
    gHelperInstallStatus = 0;
    gDirectInstallStatus = 0;
    gOperations = [NSMutableArray array];
    gInstalledPackagePaths = [NSMutableArray array];
    gDpkgDebInputPath = nil;
    gDpkgDebOutputPath = nil;
}

static NSError *finalizeWithPackages(NSBundle *bundle, NSString *directory, NSArray<NSString *> *packageResourceNames) {
    RLXBootstrapFinalizer *finalizer = [[RLXBootstrapFinalizer alloc]
                initWithResourceBundle:bundle
                 temporaryDirectoryURL:[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"staging"]
                                                  isDirectory:YES]
        additionalPackageResourceNames:packageResourceNames];
    return [finalizer finalizeBootstrap];
}

static void removeTestDirectory(NSString *directory) {
    [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
}

static BOOL allInstalledPathsUseRootfs(void) {
    for (NSString *path in gInstalledPackagePaths) {
        if (![path hasPrefix:@"/rootfs/"]) {
            return NO;
        }
    }
    return YES;
}

static void test_unlisted_resource_is_ignored(void) {
    NSString *directory = makeTestDirectory();
    resetCapture();
    prepareJailbreakRoot(directory, YES);
    NSBundle *bundle = makeResourceBundle(directory, @[
        @"libroot",
        @"fixture-extra",
    ]);

    NSError *error = finalizeWithPackages(bundle, directory, @[]);

    expect(error == nil, "unlisted: finalization succeeds");
    expect(gInstalledPackagePaths.count == 0, "unlisted: an available extra package is not installed");
    expect([gDpkgDebInputPath hasPrefix:@"/rootfs/"], "unlisted: libroot input uses the rootfs view");
    expect([gDpkgDebOutputPath hasPrefix:@"/rootfs/"], "unlisted: libroot staging uses the rootfs view");
    expect([NSFileManager.defaultManager
               fileExistsAtPath:[gTestRoot stringByAppendingPathComponent:@"usr/lib/libroot.dylib"]],
           "unlisted: Foundation installs libroot through the host view");
    removeTestDirectory(directory);
}

static void test_declared_resources_preserve_order(void) {
    NSString *directory = makeTestDirectory();
    resetCapture();
    prepareJailbreakRoot(directory, YES);
    NSBundle *bundle = makeResourceBundle(directory, @[
        @"libroot",
        @"first-extra",
        @"second-extra",
    ]);

    NSError *error = finalizeWithPackages(bundle, directory, @[ @"first-extra", @"second-extra" ]);

    expect(error == nil, "declared: finalization succeeds");
    expect([gOperations isEqualToArray:@[
               @"package:first-extra",
               @"package:second-extra",
               @"libroot",
           ]],
           "declared: package order is preserved and libroot is last");
    expect(allInstalledPathsUseRootfs(), "declared: helper package paths use the rootfs view");
    removeTestDirectory(directory);
}

static void test_initial_packages_precede_additional_packages(void) {
    NSString *directory = makeTestDirectory();
    resetCapture();
    prepareJailbreakRoot(directory, YES);
    writeFixture(@"prep", [gTestRoot stringByAppendingPathComponent:@"prep_bootstrap.sh"]);
    NSBundle *bundle = makeResourceBundle(directory, @[
        @"sileo",
        @"roothideapp",
        @"fixture-extra",
        @"libroot",
    ]);

    NSError *error = finalizeWithPackages(bundle, directory, @[ @"fixture-extra" ]);

    expect(error == nil, "initial order: finalization succeeds");
    expect([gOperations isEqualToArray:@[
               @"package:sileo",
               @"package:roothideapp",
               @"package:fixture-extra",
               @"libroot",
           ]],
           "initial order: fixed packages precede additional packages and libroot");
    removeTestDirectory(directory);
}

static void test_core_packages_precede_additional_packages(void) {
    NSString *directory = makeTestDirectory();
    resetCapture();
    prepareJailbreakRoot(directory, NO);
    NSBundle *bundle = makeResourceBundle(directory, @[
        @"libkrw-dopamine",
        @"basebin-link",
        @"fixture-extra",
        @"libroot",
    ]);

    NSError *error = finalizeWithPackages(bundle, directory, @[ @"fixture-extra" ]);

    expect(error == nil, "order: finalization succeeds");
    expect([gOperations isEqualToArray:@[
               @"package:libkrw-dopamine",
               @"package:basebin-link",
               @"package:fixture-extra",
               @"libroot",
           ]],
           "order: core packages precede additional packages and libroot");
    removeTestDirectory(directory);
}

static void test_missing_declared_resource_fails(void) {
    NSString *directory = makeTestDirectory();
    resetCapture();
    prepareJailbreakRoot(directory, YES);
    NSBundle *bundle = makeResourceBundle(directory, @[ @"libroot" ]);

    NSError *error = finalizeWithPackages(bundle, directory, @[ @"missing-extra" ]);
    NSString *diagnostic = error.userInfo[RLXEngineDiagnosticKey];

    expect(error != nil, "missing: a declared package is required");
    expect([diagnostic containsString:@"phase=locate_package"], "missing: failure identifies package resolution");
    expect([diagnostic containsString:@"package=missing-extra"], "missing: failure identifies the declared resource");
    removeTestDirectory(directory);
}

static void test_helper_status_is_propagated(void) {
    NSString *directory = makeTestDirectory();
    resetCapture();
    gHelperInstallStatus = 512;
    prepareJailbreakRoot(directory, YES);
    NSBundle *bundle = makeResourceBundle(directory, @[
        @"fixture-extra",
        @"libroot",
    ]);

    NSError *error = finalizeWithPackages(bundle, directory, @[ @"fixture-extra" ]);
    NSString *diagnostic = error.userInfo[RLXEngineDiagnosticKey];

    expect(error != nil, "helper status: install failure is returned");
    expect([diagnostic containsString:@"phase=install_package"],
           "helper status: failure identifies package installation");
    expect([diagnostic containsString:@"status=512"], "helper status: real helper status is preserved");
    expect(allInstalledPathsUseRootfs(), "helper status: failed helper receives the rootfs path");
    removeTestDirectory(directory);
}

static void test_direct_dpkg_status_is_propagated(void) {
    NSString *directory = makeTestDirectory();
    resetCapture();
    gRealUserID = 0;
    gDirectInstallStatus = 512;
    prepareJailbreakRoot(directory, YES);
    NSBundle *bundle = makeResourceBundle(directory, @[
        @"fixture-extra",
        @"libroot",
    ]);

    NSError *error = finalizeWithPackages(bundle, directory, @[ @"fixture-extra" ]);
    NSString *diagnostic = error.userInfo[RLXEngineDiagnosticKey];

    expect(error != nil, "direct status: dpkg failure is returned");
    expect([diagnostic containsString:@"status=512"], "direct status: real dpkg status is preserved");
    expect(allInstalledPathsUseRootfs(), "direct status: direct dpkg receives the rootfs path");
    removeTestDirectory(directory);
}

int main(void) {
    @autoreleasepool {
        test_unlisted_resource_is_ignored();
        test_declared_resources_preserve_order();
        test_initial_packages_precede_additional_packages();
        test_core_packages_precede_additional_packages();
        test_missing_declared_resource_fails();
        test_helper_status_is_propagated();
        test_direct_dpkg_status_is_propagated();
    }
    if (gFailures == 0) {
        fprintf(stdout, "ok bootstrap-finalizer\n");
    }
    return gFailures == 0 ? 0 : 1;
}
