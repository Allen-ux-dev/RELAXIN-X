#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#include "common.h"

NSString *safe_getExecutablePath() {
    char executablePathC[PATH_MAX];
    uint32_t executablePathCSize = sizeof(executablePathC);
    _NSGetExecutablePath(&executablePathC[0], &executablePathCSize);
    return [NSString stringWithUTF8String:executablePathC];
}

NSString *getProcessName() {
    return safe_getExecutablePath().lastPathComponent;
}

__attribute__((constructor)) static void roothideHooksInitialize(void) {
    RHLogDebug(@"roothidehooks initialization status=begin");
    NSString *processName = getProcessName();
    if ([processName isEqualToString:@"cfprefsd"]) {
        extern void cfprefsdInit(void);
        cfprefsdInit();
    } else if ([processName isEqualToString:@"lsd"]) {
        extern void lsdInit(void);
        lsdInit();
    } else if ([processName isEqualToString:@"SpringBoard"]) {
        extern void sbInit(void);
        sbInit();
    } else if ([processName isEqualToString:@"runningboardd"]) {
        extern void runningboarddInit(void);
        runningboarddInit();
    }
}
