#import <Foundation/Foundation.h>
#import "../../../RelaxinEngine/Inspection/RLXBootstrapEnvironmentInspector.h"
#import "../../../RelaxinPostJailbreak/Inspection/RLXPackageManagerHealthInspector.h"

static int failures = 0;
#define EXPECT(condition, message) do { \
    if (!(condition)) { fprintf(stderr, "not ok %s\n", message); failures++; } \
} while (0)

static void touch(NSString *path) {
    [[NSData data] writeToFile:path atomically:YES];
}

int main(void) {
    @autoreleasepool {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *primary = [base stringByAppendingPathComponent:@"primary"];
        [fm createDirectoryAtPath:primary withIntermediateDirectories:YES attributes:nil error:nil];

        // Valid checksum brand: upper seven bytes are zero, low checksum byte is zero.
        NSString *installed = [primary stringByAppendingPathComponent:@".jbroot-0000000000000000"];
        NSString *incomplete = [primary stringByAppendingPathComponent:@".jbroot-0100000000000001"];
        [fm createDirectoryAtPath:installed withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:incomplete withIntermediateDirectories:YES attributes:nil error:nil];
        touch([installed stringByAppendingPathComponent:@".installed_relaxin"]);

        NSError *error = nil;
        RLXBootstrapEnvironmentEvidence *evidence =
            [RLXBootstrapEnvironmentInspector inspectContainerRoots:@[primary] error:&error];
        EXPECT(error == nil, "inspection returns evidence without mutation");
        EXPECT(evidence.candidateCount == 2, "two candidate roots are observed");
        EXPECT(evidence.hasInstalledRelaxinMarker, "installed marker is observed");
        EXPECT([fm fileExistsAtPath:installed], "inspection leaves installed root in place");
        EXPECT([fm fileExistsAtPath:incomplete], "inspection leaves incomplete root in place");

        NSString *jbroot = [base stringByAppendingPathComponent:@"jb"];
        [fm createDirectoryAtPath:[jbroot stringByAppendingPathComponent:@"Applications/Sileo.app"]
      withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:[jbroot stringByAppendingPathComponent:@"etc/apt/sources.list.d"]
      withIntermediateDirectories:YES attributes:nil error:nil];
        touch([jbroot stringByAppendingPathComponent:@"etc/apt/sources.list.d/sileo.sources"]);
        RLXPackageManagerHealthEvidence *packages =
            [RLXPackageManagerHealthInspector inspectJailbreakRoot:jbroot];
        EXPECT(packages.sileoInstalled, "Sileo installation is observed");
        EXPECT(packages.sileoHealthy, "Sileo files plus sources are healthy");
        EXPECT(!packages.zebraInstalled, "Zebra absence is independent from Sileo");
        EXPECT(!packages.zebraHealthy, "Zebra absence is not healthy");

        [fm removeItemAtPath:base error:nil];
    }
    if (failures == 0) puts("ok environment-inspector");
    return failures == 0 ? 0 : 1;
}
