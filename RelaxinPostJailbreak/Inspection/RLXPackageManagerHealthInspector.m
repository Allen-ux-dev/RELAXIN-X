#import "RLXPackageManagerHealthInspector.h"

@interface RLXPackageManagerHealthEvidence ()
@property(nonatomic, readwrite) BOOL sileoInstalled;
@property(nonatomic, readwrite) BOOL sileoHealthy;
@property(nonatomic, readwrite) BOOL zebraInstalled;
@property(nonatomic, readwrite) BOOL zebraHealthy;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *findings;
@end

@implementation RLXPackageManagerHealthEvidence
@end

@implementation RLXPackageManagerHealthInspector

+ (RLXPackageManagerHealthEvidence *)inspectJailbreakRoot:(NSString *)jailbreakRoot {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *findings = [NSMutableArray array];

    NSString *sileoApp = [jailbreakRoot stringByAppendingPathComponent:@"Applications/Sileo.app"];
    NSString *sileoSources =
        [jailbreakRoot stringByAppendingPathComponent:@"etc/apt/sources.list.d/sileo.sources"];
    NSString *zebraApp = [jailbreakRoot stringByAppendingPathComponent:@"Applications/Zebra.app"];
    NSString *zebraSources = [jailbreakRoot
        stringByAppendingPathComponent:@"var/mobile/Library/Application Support/xyz.willy.Zebra/sources.list"];

    BOOL sileoInstalled = [fileManager fileExistsAtPath:sileoApp];
    BOOL sileoSourcesPresent = [fileManager fileExistsAtPath:sileoSources];
    BOOL zebraInstalled = [fileManager fileExistsAtPath:zebraApp];
    BOOL zebraSourcesPresent = [fileManager fileExistsAtPath:zebraSources];

    if (sileoInstalled && !sileoSourcesPresent) {
        [findings addObject:@"sileo_sources_missing"];
    }
    if (zebraInstalled && !zebraSourcesPresent) {
        [findings addObject:@"zebra_sources_missing"];
    }

    RLXPackageManagerHealthEvidence *evidence = [[RLXPackageManagerHealthEvidence alloc] init];
    evidence.sileoInstalled = sileoInstalled;
    evidence.sileoHealthy = sileoInstalled && sileoSourcesPresent;
    evidence.zebraInstalled = zebraInstalled;
    evidence.zebraHealthy = zebraInstalled && zebraSourcesPresent;
    evidence.findings = findings.copy;
    return evidence;
}

@end
