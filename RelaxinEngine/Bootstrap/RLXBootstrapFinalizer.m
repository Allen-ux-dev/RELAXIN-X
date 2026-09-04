//
//  RLXBootstrapFinalizer.m
//  RelaxinEngine
//

#import "RLXBootstrapFinalizer.h"

#import "../Engine/RLXEngine.h"
#import "../Diagnostic/RLXEngineDiagnostic.h"
#import "../Engine/RLXEngineError.h"
#import "../Log/RLXEngineLog.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <spawn.h>
#include <sys/stat.h>
#include <unistd.h>

#include <libjailbreak/jbclient_xpc.h>
#include <libjailbreak/jbroot.h>
#include <libjailbreak/util.h>

static const char *const RLXBootstrapFinalizationLogCategory = "BootstrapFinalization";
static const NSInteger RLXBootstrapInstallVersion = 2;

static NSDictionary<NSString *, NSString *> *rlx_bundled_package_versions(void) {
    return @{
        @"libkrw0-dopamine" : @"2.0.4",
        @"dopamine-basebin-link" : @"1.0.0",
    };
}

static int rlx_status_for_error(NSError *error) {
    if ([error.domain isEqualToString:NSPOSIXErrorDomain] && error.code > 0 && error.code <= INT_MAX) {
        return (int)error.code;
    }
    return EIO;
}

static NSString *rlx_rootfs_path(NSString *path) {
    return [@"/rootfs" stringByAppendingPathComponent:path];
}

static NSInteger rlx_numerical_version(NSString *version) {
    NSArray<NSString *> *components = [version
        componentsSeparatedByCharactersInSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet];
    NSMutableArray<NSString *> *numbers = [NSMutableArray arrayWithCapacity:3];
    for (NSString *component in components) {
        if (component.length != 0) {
            [numbers addObject:component];
            if (numbers.count == 3) {
                break;
            }
        }
    }
    while (numbers.count < 3) {
        [numbers addObject:@"0"];
    }
    return (numbers[0].integerValue << 16) | (numbers[1].integerValue << 8) | numbers[2].integerValue;
}

static void rlx_log_finalization(NSString *message) {
    rlx_engine_log(RLX_ENGINE_LOG_INFO, RLXBootstrapFinalizationLogCategory, message.UTF8String);
}

extern char **environ;
extern int exec_cmd_roothide_spawn(pid_t *pid,
                                   const char *path,
                                   const posix_spawn_file_actions_t *fileActions,
                                   const posix_spawnattr_t *attributes,
                                   char *const arguments[],
                                   char *const environment[]);

static int rlx_install_package(NSString *package, NSString *_Nullable *_Nullable output) {
    if (output) {
        *output = nil;
    }

    const char *binary = JBROOT_PATH("/usr/bin/dpkg");
    int status = jbclient_trust_file_by_path(binary);
    if (status != 0) {
        return status;
    }

    int outputDescriptors[2];
    if (pipe(outputDescriptors) != 0) {
        return errno ?: EIO;
    }
    int readDescriptor = fcntl(outputDescriptors[0], F_DUPFD, STDERR_FILENO + 1);
    int writeDescriptor = fcntl(outputDescriptors[1], F_DUPFD, STDERR_FILENO + 1);
    if (readDescriptor < 0 || writeDescriptor < 0) {
        int duplicationStatus = errno ?: EIO;
        if (readDescriptor >= 0) {
            close(readDescriptor);
        }
        if (writeDescriptor >= 0) {
            close(writeDescriptor);
        }
        close(outputDescriptors[0]);
        close(outputDescriptors[1]);
        return duplicationStatus;
    }
    close(outputDescriptors[0]);
    close(outputDescriptors[1]);
    outputDescriptors[0] = readDescriptor;
    outputDescriptors[1] = writeDescriptor;

    posix_spawn_file_actions_t fileActions;
    status = posix_spawn_file_actions_init(&fileActions);
    if (status != 0) {
        close(outputDescriptors[0]);
        close(outputDescriptors[1]);
        return status;
    }
    status = posix_spawn_file_actions_addclose(&fileActions, outputDescriptors[0]);
    if (status == 0) {
        status = posix_spawn_file_actions_adddup2(&fileActions, outputDescriptors[1], STDOUT_FILENO);
    }
    if (status == 0) {
        status = posix_spawn_file_actions_adddup2(&fileActions, outputDescriptors[1], STDERR_FILENO);
    }
    if (status == 0) {
        status = posix_spawn_file_actions_addclose(&fileActions, outputDescriptors[1]);
    }

    posix_spawnattr_t attributes;
    if (status == 0) {
        status = posix_spawnattr_init(&attributes);
    }
    if (status == 0) {
        char *const arguments[] = {
            (char *)binary,
            (char *)"-i",
            (char *)package.fileSystemRepresentation,
            NULL,
        };
        pid_t pid = -1;
        status = exec_cmd_roothide_spawn(&pid, binary, &fileActions, &attributes, arguments, environ);

        close(outputDescriptors[1]);
        outputDescriptors[1] = -1;

        if (status == 0) {
            NSMutableData *capturedOutput = [NSMutableData data];
            uint8_t buffer[4096];
            ssize_t count;
            while ((count = read(outputDescriptors[0], buffer, sizeof(buffer))) > 0) {
                [capturedOutput appendBytes:buffer length:(NSUInteger)count];
            }

            status = cmd_wait_for_exit(pid);

            NSString *renderedOutput = [[NSString alloc] initWithData:capturedOutput encoding:NSUTF8StringEncoding];
            if (output && renderedOutput.length != 0) {
                *output = [renderedOutput
                    stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            }
        }
        posix_spawnattr_destroy(&attributes);
    }
    if (outputDescriptors[1] >= 0) {
        close(outputDescriptors[1]);
    }
    close(outputDescriptors[0]);
    posix_spawn_file_actions_destroy(&fileActions);
    return status;
}

static NSError *rlx_finalization_error(NSString *phase,
                                       int status,
                                       NSString *_Nullable detail,
                                       NSError *_Nullable underlying) {
    RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnostic];
    [diagnostic appendPhase:phase];
    [diagnostic appendStatus:status];
    if (detail.length) {
        [diagnostic appendRenderedDiagnostic:detail];
    }
    NSString *message = [NSString stringWithFormat:@"failed phase=%@ status=%d%@",
                                                   phase,
                                                   status,
                                                   detail.length ? [NSString stringWithFormat:@" %@", detail] : @""];
    rlx_engine_log(RLX_ENGINE_LOG_ERROR, RLXBootstrapFinalizationLogCategory, message.UTF8String);

    return [RLXEngineError errorWithCode:RLXEngineErrorCodeBootstrapFinalizationFailed
                             description:@"The bootstrap could not be finalized."
                           failureReason:[NSString stringWithFormat:@"%@ failed with status %d.", phase, status]
                      recoverySuggestion:@"Inspect the bootstrap finalization log before retrying."
                              diagnostic:diagnostic
                         underlyingError:underlying];
}

@interface RLXBootstrapFinalizer ()

@property(nonatomic, copy) NSString *root;

- (nullable NSError *)installAdditionalPackages;

@end

@implementation RLXBootstrapFinalizer {
    NSBundle *_resourceBundle;
    NSURL *_temporaryDirectoryURL;
    NSArray<NSString *> *_additionalPackageResourceNames;
    BOOL _installSileo;
    NSString *_zebraPackagePath;
}

- (instancetype)initWithResourceBundle:(NSBundle *)resourceBundle temporaryDirectoryURL:(NSURL *)temporaryDirectoryURL {
    return [self initWithResourceBundle:resourceBundle temporaryDirectoryURL:temporaryDirectoryURL
         additionalPackageResourceNames:@[]];
}

- (instancetype)initWithResourceBundle:(NSBundle *)resourceBundle
                 temporaryDirectoryURL:(NSURL *)temporaryDirectoryURL
        additionalPackageResourceNames:(NSArray<NSString *> *)packageResourceNames {
    return [self initWithResourceBundle:resourceBundle
                 temporaryDirectoryURL:temporaryDirectoryURL
        additionalPackageResourceNames:packageResourceNames
                         installSileo:YES
                     zebraPackagePath:nil];
}

- (instancetype)initWithResourceBundle:(NSBundle *)resourceBundle
                 temporaryDirectoryURL:(NSURL *)temporaryDirectoryURL
        additionalPackageResourceNames:(NSArray<NSString *> *)packageResourceNames
                         installSileo:(BOOL)installSileo
                     zebraPackagePath:(NSString *)zebraPackagePath {
    self = [super init];
    if (self) {
        _resourceBundle = resourceBundle;
        _temporaryDirectoryURL = [temporaryDirectoryURL copy];
        _additionalPackageResourceNames = [packageResourceNames copy];
        _installSileo = installSileo;
        _zebraPackagePath = [zebraPackagePath copy];
    }
    return self;
}

- (nullable NSError *)finalizeBootstrap {
    const char *root = get_jbroot();
    if (!root || root[0] != '/') {
        return rlx_finalization_error(@"resolve_jbroot", ENOENT, nil, nil);
    }
    self.root = @(root);

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *prepBootstrap = [self pathInRoot:@"/prep_bootstrap.sh"];
    BOOL firstFinalization = [fileManager fileExistsAtPath:prepBootstrap];
    rlx_log_finalization(
        [NSString stringWithFormat:@"begin route=%@ root=%@", firstFinalization ? @"initial" : @"update", self.root]);

    NSError *error = firstFinalization ? [self performInitialFinalization] : [self updateBootstrapLinks];
    if (error) {
        return error;
    }

    error = [self updateBundledPackages];
    if (error) {
        return error;
    }

    error = [self installAdditionalPackages];
    if (error) {
        return error;
    }

    error = [self refreshLibroot];
    if (error) {
        return error;
    }

    NSString *installedMarker = [self pathInRoot:@"/.installed_relaxin"];
    [[NSString stringWithFormat:@"%ld", (long)RLXBootstrapInstallVersion] writeToFile:installedMarker atomically:YES
                                                                             encoding:NSUTF8StringEncoding
                                                                                error:nil];

    NSString *palera1nMarker = [self pathInRoot:@"/.installed_palera1n"];
    if (jbclient_palehide_present()) {
        [@"" writeToFile:palera1nMarker atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fileManager removeItemAtPath:palera1nMarker error:nil];
    }

    rlx_log_finalization(@"bootstrap finalization completed");
    return nil;
}

- (nullable NSError *)performInitialFinalization {
    rlx_log_finalization(@"phase=prep_bootstrap begin");
    int status = exec_cmd_trusted(JBROOT_PATH("/bin/sh"), "/prep_bootstrap.sh", NULL);
    if (status != 0) {
        return rlx_finalization_error(@"prep_bootstrap", status, nil, nil);
    }

    NSError *error = nil;
    if (_installSileo) {
        rlx_log_finalization(@"phase=install_sileo begin");
        error = [RLXBootstrapFinalizer installBundledPackageNamed:@"sileo" resourceBundle:_resourceBundle];
        if (error) {
            return error;
        }
    }

    if (_zebraPackagePath.length != 0) {
        rlx_log_finalization(@"phase=install_zebra begin");
        error = [RLXBootstrapFinalizer installExternalPackageAtPath:_zebraPackagePath];
        if (error) {
            return error;
        }
    }

    rlx_log_finalization(@"phase=install_roothide_manager begin");
    error = [RLXBootstrapFinalizer installBundledPackageNamed:@"roothideapp" resourceBundle:_resourceBundle];
    if (error) {
        return error;
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    for (NSString *path in @[
             @"/var/mobile/Library/SplashBoard/Snapshots/xyz.willy.Zebra",
             @"/var/mobile/Library/SplashBoard/Snapshots/com.roothide.manager",
             @"/var/mobile/Library/SplashBoard/Snapshots/org.coolstar.SileoStore",
         ]) {
        [fileManager removeItemAtPath:path error:nil];
    }
    return nil;
}

- (nullable NSError *)updateBootstrapLinks {
    rlx_log_finalization(@"phase=update_symlinks begin");
    for (NSString *path in @[ @"/bin/sh", @"/usr/bin/sh" ]) {
        int status = [self fixBootstrapSymlink:path];
        if (status != 0) {
            return rlx_finalization_error(@"fix_bootstrap_symlink",
                                          status,
                                          [NSString stringWithFormat:@"path=%@", path],
                                          nil);
        }
    }

    int status = exec_cmd_trusted(JBROOT_PATH("/bin/sh"), "/usr/libexec/updatelinks.sh", NULL);
    if (status != 0) {
        return rlx_finalization_error(@"updatelinks", status, nil, nil);
    }
    return nil;
}

- (nullable NSError *)updateBundledPackages {
    NSDictionary<NSString *, NSString *> *versions = rlx_bundled_package_versions();
    BOOL installLibkrw = [self shouldInstallPackage:@"libkrw0-dopamine" bundledVersion:versions[@"libkrw0-dopamine"]];
    BOOL installBasebinLink = [self shouldInstallPackage:@"dopamine-basebin-link"
                                          bundledVersion:versions[@"dopamine-basebin-link"]];

    rlx_log_finalization([NSString
        stringWithFormat:@"phase=bundled_packages libkrw=%d basebin_link=%d", installLibkrw, installBasebinLink]);

    if (installLibkrw) {
        NSError *error = [RLXBootstrapFinalizer installBundledPackageNamed:@"libkrw-dopamine"
                                                            resourceBundle:_resourceBundle];
        if (error) {
            return error;
        }
    }

    if (installBasebinLink) {
        NSFileManager *fileManager = NSFileManager.defaultManager;
        for (NSString *path in @[
                 @"/usr/bin/opainject",
                 @"/usr/bin/jbctl",
                 @"/usr/lib/libjailbreak.dylib",
                 @"/usr/bin/libjailbreak.dylib",
             ]) {
            NSString *rootPath = [self pathInRoot:path];
            if ([self fileOrSymlinkExistsAtPath:rootPath]) {
                [fileManager removeItemAtPath:rootPath error:nil];
            }
        }

        NSError *error = [RLXBootstrapFinalizer installBundledPackageNamed:@"basebin-link"
                                                            resourceBundle:_resourceBundle];
        if (error) {
            return error;
        }
    }
    return nil;
}

- (nullable NSError *)installAdditionalPackages {
    rlx_log_finalization([NSString
        stringWithFormat:@"phase=additional_packages count=%lu", (unsigned long)_additionalPackageResourceNames.count]);
    for (NSString *packageResourceName in _additionalPackageResourceNames) {
        rlx_log_finalization(
            [NSString stringWithFormat:@"phase=install_additional_package begin package=%@", packageResourceName]);
        NSError *error = [RLXBootstrapFinalizer installBundledPackageNamed:packageResourceName
                                                            resourceBundle:_resourceBundle];
        if (error) {
            return error;
        }
        rlx_log_finalization(
            [NSString stringWithFormat:@"phase=install_additional_package completed package=%@", packageResourceName]);
    }
    return nil;
}

- (nullable NSError *)refreshLibroot {
    rlx_log_finalization(@"phase=refresh_libroot begin");
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *destination = [self pathInRoot:@"/usr/lib/libroot.dylib"];
    if ([self fileOrSymlinkExistsAtPath:destination]) {
        [fileManager removeItemAtPath:destination error:nil];
    }

    NSString *package = [_resourceBundle pathForResource:@"libroot" ofType:@"deb"];
    if (!package) {
        return rlx_finalization_error(@"locate_libroot_package", ENOENT, nil, nil);
    }

    NSError *underlying = nil;
    if (![fileManager createDirectoryAtURL:_temporaryDirectoryURL withIntermediateDirectories:YES attributes:nil
                                     error:&underlying]) {
        return rlx_finalization_error(@"create_libroot_staging", rlx_status_for_error(underlying), nil, underlying);
    }

    NSString *unpackedPath = [_temporaryDirectoryURL.path stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    int status = exec_cmd_trusted(JBROOT_PATH("/usr/bin/dpkg-deb"),
                                  "-R",
                                  rlx_rootfs_path(package).fileSystemRepresentation,
                                  rlx_rootfs_path(unpackedPath).fileSystemRepresentation,
                                  NULL);
    if (status != 0) {
        return rlx_finalization_error(@"unpack_libroot", status, nil, nil);
    }

    NSString *source = [unpackedPath stringByAppendingPathComponent:@"/var/jb/usr/lib/libroot.dylib"];
    if (![fileManager copyItemAtPath:source toPath:destination error:&underlying]) {
        return rlx_finalization_error(@"install_libroot", rlx_status_for_error(underlying), nil, underlying);
    }
    if (![fileManager removeItemAtPath:unpackedPath error:&underlying]) {
        return rlx_finalization_error(@"remove_libroot_staging", rlx_status_for_error(underlying), nil, underlying);
    }
    return nil;
}

+ (nullable NSError *)installExternalPackageAtPath:(NSString *)packagePath {
    NSString *standardizedPackage = packagePath.stringByStandardizingPath;
    NSString *standardizedHome = NSHomeDirectory().stringByStandardizingPath;
    NSString *homePrefix = [standardizedHome stringByAppendingString:@"/"];
    BOOL insideAppContainer = [standardizedPackage hasPrefix:homePrefix];
    if (!insideAppContainer || ![standardizedPackage.pathExtension.lowercaseString isEqualToString:@"deb"]) {
        return rlx_finalization_error(@"validate_external_package",
                                      EINVAL,
                                      @"package path is outside the app container or is not a deb",
                                      nil);
    }
    if (![NSFileManager.defaultManager fileExistsAtPath:standardizedPackage]) {
        return rlx_finalization_error(@"validate_external_package", ENOENT, @"package file is missing", nil);
    }

    NSString *rootfsPackage = rlx_rootfs_path(standardizedPackage);
    NSString *commandOutput = nil;
    int status;
    if (getuid() == 0) {
        status = rlx_install_package(rootfsPackage, &commandOutput);
    } else {
        status = exec_cmd(JBROOT_PATH("/basebin/jbctl"),
                          "internal",
                          "install_pkg",
                          rootfsPackage.fileSystemRepresentation,
                          NULL);
    }
    if (status != 0) {
        return rlx_finalization_error(@"install_external_package", status, commandOutput, nil);
    }
    return nil;
}

+ (nullable NSError *)installBundledPackageNamed:(NSString *)name resourceBundle:(NSBundle *)resourceBundle {
    NSString *package = [resourceBundle pathForResource:name ofType:@"deb"];
    if (!package) {
        return rlx_finalization_error(@"locate_package", ENOENT, [NSString stringWithFormat:@"package=%@", name], nil);
    }
    NSString *rootfsPackage = rlx_rootfs_path(package);

    NSString *commandOutput = nil;
    int status;
    if (getuid() == 0) {
        status = rlx_install_package(rootfsPackage, &commandOutput);
    } else {
        status = exec_cmd(JBROOT_PATH("/basebin/jbctl"),
                          "internal",
                          "install_pkg",
                          rootfsPackage.fileSystemRepresentation,
                          NULL);
    }
    if (status != 0) {
        NSString *detail = commandOutput.length
            ? [NSString stringWithFormat:@"package=%@\ndpkg_output=%@", name, commandOutput]
            : [NSString stringWithFormat:@"package=%@", name];
        return rlx_finalization_error(@"install_package", status, detail, nil);
    }
    return nil;
}

- (BOOL)shouldInstallPackage:(NSString *)identifier bundledVersion:(NSString *)bundledVersion {
    NSString *statusPath = [self pathInRoot:@"/var/lib/dpkg/status"];
    NSString *status = [NSString stringWithContentsOfFile:statusPath encoding:NSUTF8StringEncoding error:nil];
    NSString *packagePrefix = [NSString stringWithFormat:@"Package: %@", identifier];
    for (NSString *packageInfo in [status componentsSeparatedByString:@"\n\n"]) {
        if (![packageInfo hasPrefix:packagePrefix]) {
            continue;
        }
        for (NSString *line in [packageInfo componentsSeparatedByString:@"\n"]) {
            if ([line hasPrefix:@"Version: "]) {
                NSString *installed = [line substringFromIndex:9];
                return rlx_numerical_version(installed) < rlx_numerical_version(bundledVersion);
            }
        }
        break;
    }
    return YES;
}

- (int)fixBootstrapSymlink:(NSString *)path {
    NSString *rootPath = [self pathInRoot:path];
    struct stat attributes = {0};
    if (lstat(rootPath.fileSystemRepresentation, &attributes) != 0) {
        return errno ?: EIO;
    }
    if (!S_ISLNK(attributes.st_mode)) {
        return 0;
    }

    char targetBuffer[PATH_MAX + 1] = {0};
    ssize_t targetLength = readlink(rootPath.fileSystemRepresentation, targetBuffer, sizeof(targetBuffer) - 1);
    if (targetLength <= 0) {
        return errno ?: EIO;
    }
    if (targetBuffer[0] != '/') {
        return 0;
    }

    NSString *target = [@(targetBuffer) stringByStandardizingPath].stringByResolvingSymlinksInPath;
    NSRegularExpression *pattern = [NSRegularExpression
        regularExpressionWithPattern:@"^(?:/private)?/var/containers/Bundle/Application/" "\\.jbroot-[0-9A-Z]{16}(/.+)$"
                             options:0
                               error:nil];
    NSTextCheckingResult *match = [pattern firstMatchInString:target options:0 range:NSMakeRange(0, target.length)];
    if (!match || [match rangeAtIndex:1].location == NSNotFound) {
        return EINVAL;
    }

    NSString *suffix = [target substringWithRange:[match rangeAtIndex:1]];
    NSString *newTarget = [@".jbroot" stringByAppendingPathComponent:suffix];
    if (unlink(rootPath.fileSystemRepresentation) != 0) {
        return errno ?: EIO;
    }
    if (symlink(newTarget.fileSystemRepresentation, rootPath.fileSystemRepresentation) != 0) {
        return errno ?: EIO;
    }
    if (access(rootPath.fileSystemRepresentation, F_OK) != 0) {
        return errno ?: EIO;
    }
    return 0;
}

- (BOOL)fileOrSymlinkExistsAtPath:(NSString *)path {
    struct stat attributes = {0};
    return lstat(path.fileSystemRepresentation, &attributes) == 0;
}

- (NSString *)pathInRoot:(NSString *)path {
    return [self.root stringByAppendingPathComponent:path];
}

@end
