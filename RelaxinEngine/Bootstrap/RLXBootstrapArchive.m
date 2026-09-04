//
//  RLXBootstrapArchive.m
//  RelaxinEngine
//

#import "RLXBootstrapArchive.h"

#import "RLXBootstrapPreparationError.h"
#import "../Log/RLXEngineLog.h"

#include <errno.h>
#include <libjailbreak/util.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <zstd.h>

static NSString *const RLXBootstrapArchiveName = @"bootstrap_1900.tar.zst";

@interface RLXBootstrapArchive ()
- (int)decompressZstandardFile:(NSString *)sourcePath
                        toFile:(NSString *)destinationPath
                        detail:(NSString *_Nullable *_Nullable)detail;
@end

@implementation RLXBootstrapArchive {
    NSBundle *_resourceBundle;
    NSURL *_temporaryDirectoryURL;
}

- (instancetype)initWithResourceBundle:(NSBundle *)resourceBundle temporaryDirectoryURL:(NSURL *)temporaryDirectoryURL {
    self = [super init];
    if (self) {
        _resourceBundle = resourceBundle;
        _temporaryDirectoryURL = [temporaryDirectoryURL copy];
    }
    return self;
}

- (int)extractBootstrapArchiveAtRoot:(NSString *)root detail:(NSString *_Nullable *_Nullable)detail {
    NSString *archive = [_resourceBundle.bundlePath stringByAppendingPathComponent:RLXBootstrapArchiveName];
    if (![NSFileManager.defaultManager fileExistsAtPath:archive]) {
        if (detail) {
            *detail = [NSString stringWithFormat:@"archive=%@\narchive_present=false", archive];
        }
        return ENOENT;
    }

    NSError *directoryError = nil;
    if (![NSFileManager.defaultManager createDirectoryAtURL:_temporaryDirectoryURL withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:&directoryError]) {
        if (detail) {
            *detail = [NSString stringWithFormat:@"temporary_directory=%@", _temporaryDirectoryURL.path];
        }
        return rlx_status_for_error(directoryError);
    }

    NSString *temporaryTar = [_temporaryDirectoryURL.path stringByAppendingPathComponent:@"bootstrap.tar"];
    if ([NSFileManager.defaultManager fileExistsAtPath:temporaryTar]) {
        NSError *removeError = nil;
        if (![NSFileManager.defaultManager removeItemAtPath:temporaryTar error:&removeError]) {
            if (detail) {
                *detail = [NSString stringWithFormat:@"temporary_tar=%@\nremove=false", temporaryTar];
            }
            return rlx_status_for_error(removeError);
        }
    }

    int status = [self decompressZstandardFile:archive toFile:temporaryTar detail:detail];
    if (status == 0) {
        int archiveStatus = libarchive_unarchive(temporaryTar.fileSystemRepresentation, root.fileSystemRepresentation);
        if (archiveStatus != 0) {
            status = EBADEXEC;
            if (detail) {
                *detail = [NSString stringWithFormat:@"archive=%@\ntemporary_tar=%@\n" "libarchive_status=%d",
                                                     archive,
                                                     temporaryTar,
                                                     archiveStatus];
            }
        }
    }
    return status;
}

- (int)decompressZstandardFile:(NSString *)sourcePath
                        toFile:(NSString *)destinationPath
                        detail:(NSString *_Nullable *_Nullable)detail {
    static const size_t bufferSize = 8192;

    FILE *input = fopen(sourcePath.fileSystemRepresentation, "rb");
    if (!input) {
        if (detail) {
            *detail = [NSString stringWithFormat:@"source=%@", sourcePath];
        }
        return errno ?: EIO;
    }

    FILE *output = fopen(destinationPath.fileSystemRepresentation, "wb");
    if (!output) {
        int status = errno ?: EIO;
        fclose(input);
        if (detail) {
            *detail = [NSString stringWithFormat:@"destination=%@", destinationPath];
        }
        return status;
    }

    void *inputBuffer = malloc(bufferSize);
    if (!inputBuffer) {
        fclose(output);
        fclose(input);
        return ENOMEM;
    }

    void *outputBuffer = malloc(bufferSize);
    if (!outputBuffer) {
        free(inputBuffer);
        fclose(output);
        fclose(input);
        return ENOMEM;
    }

    ZSTD_DStream *stream = ZSTD_createDStream();
    if (!stream) {
        free(outputBuffer);
        free(inputBuffer);
        fclose(output);
        fclose(input);
        return ENOMEM;
    }
    size_t result = ZSTD_initDStream(stream);
    if (ZSTD_isError(result)) {
        if (detail) {
            *detail = [NSString stringWithFormat:@"zstd_error=%s", ZSTD_getErrorName(result)];
        }
        ZSTD_freeDStream(stream);
        free(outputBuffer);
        free(inputBuffer);
        fclose(output);
        fclose(input);
        return EBADEXEC;
    }

    int status = 0;
    while (status == 0) {
        size_t bytesRead = fread(inputBuffer, 1, bufferSize, input);
        if (bytesRead == 0) {
            if (!feof(input)) {
                status = errno ?: EIO;
            }
            break;
        }
        ZSTD_inBuffer inputState = {
            .src = inputBuffer,
            .size = bytesRead,
            .pos = 0,
        };
        BOOL flushPendingOutput = NO;
        do {
            ZSTD_outBuffer outputState = {
                .dst = outputBuffer,
                .size = bufferSize,
                .pos = 0,
            };
            result = ZSTD_decompressStream(stream, &outputState, &inputState);
            if (ZSTD_isError(result)) {
                status = EBADEXEC;
                if (detail) {
                    *detail = [NSString stringWithFormat:@"zstd_error=%s", ZSTD_getErrorName(result)];
                }
                break;
            }
            if (fwrite(outputBuffer, 1, outputState.pos, output) != outputState.pos) {
                status = errno ?: EIO;
                break;
            }
            flushPendingOutput = result > 0 && outputState.pos == outputState.size;
        } while (status == 0 && (inputState.pos < inputState.size || flushPendingOutput));
    }
    if (status == 0 && result != 0) {
        status = EBADEXEC;
        if (detail) {
            *detail = @"zstd_error=incomplete_frame";
        }
    }

    free(outputBuffer);
    free(inputBuffer);
    ZSTD_freeDStream(stream);
    fclose(output);
    fclose(input);
    if (status != 0 && detail && !*detail) {
        *detail = [NSString stringWithFormat:@"source=%@\ndestination=%@", sourcePath, destinationPath];
    }
    return status;
}

@end
