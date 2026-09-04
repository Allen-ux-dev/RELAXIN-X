//
//  RLXKernelCacheLayoutAnalysisTask.m
//  RelaxinEngine
//

#import "RLXKernelCacheLayoutAnalysisTask.h"

#import "../../Engine/RLXEngine.h"
#import "../../Diagnostic/RLXEngineDiagnostic.h"
#import "../../Engine/RLXEngineError.h"
#import "../../KernelAccess/Analysis/RLXKernelOffsetTable.h"
#import "../../Log/RLXEngineLog.h"
#import "../../Engine/RLXEngineRunContext.h"

#import <libjailbreak/info.h>

@implementation RLXKernelCacheLayoutAnalysisTask

- (instancetype)initWithContext:(RLXEngineRunContext *)context {
    return [super initWithStage:RLXEngineStageKernelCacheLayoutAnalysis context:context];
}

- (nullable NSError *)execute {
    NSString *kernelcachePath = self.context.kernelcachePath;
    RLXKernelOffsetProfile *offsetProfile = self.context.kernelOffsetProfile;
    NSDictionary<RLXEngineManifestKey, NSString *> *target = self.context.confirmedTarget;

    /*
     * Stage 02 leaves one of the two: a shipped profile, or a kernelcache on
     * disk. The file is only inspected when there is no profile, because a
     * profile means the file was never fetched.
     */
    NSError *fileError = nil;
    NSDictionary<NSFileAttributeKey, id> *attributes = (!offsetProfile && kernelcachePath)
        ? [NSFileManager.defaultManager attributesOfItemAtPath:kernelcachePath error:&fileError]
        : nil;
    BOOL usableKernelcache = [attributes[NSFileType] isEqualToString:NSFileTypeRegular] &&
        [attributes[NSFileSize] unsignedLongLongValue] > 0;
    if (!target || !(offsetProfile || usableKernelcache)) {
        RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnosticWithStage:@"analyze_kernelcache"];
        [diagnostic appendKey:@"confirmed_target" boolValue:target != nil];
        [diagnostic appendKey:@"offset_table" boolValue:offsetProfile != nil];
        [diagnostic appendKey:@"kernelcache" value:kernelcachePath fallback:@"missing"];
        [diagnostic appendKey:@"usable" boolValue:usableKernelcache];
        return [RLXEngineError errorWithCode:RLXEngineErrorCodeInvalidAction
                                 description:@"Kernelcache analysis prerequisites are missing."
                               failureReason:fileError.localizedDescription
                                   ?: @"Neither a bundled offset profile nor a nonempty kernelcache is available."
                          recoverySuggestion:@"Run target confirmation and kernelcache acquisition first."
                                  diagnostic:diagnostic];
    }

    /*
     * Match Dopamine's coupled runtime: DarkSword needs only the live OS
     * structure layout. Rocket must own this process's first full XPF session
     * because its pattern recovery and GFX bootstrap share one timing boundary.
     * Task 04 performs the complete post-exploitation dictionary pass — from
     * the shipped profile when there is one, and from an XPF session over the
     * kernelcache when there is not.
     */
    jbinfo_initialize_hardcoded_offsets();
    NSString *message = [NSString
        stringWithFormat:@"kernelcache layout preflight ready source=%@; " "full analysis is coupled to Rocket",
                         offsetProfile ? @"table" : @"kernelcache"];
    rlx_engine_log(RLX_ENGINE_LOG_INFO, "RLXEngine", message.UTF8String);
    return nil;
}

@end
