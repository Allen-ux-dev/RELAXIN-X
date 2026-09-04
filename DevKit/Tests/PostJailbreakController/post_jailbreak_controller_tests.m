#import <Foundation/Foundation.h>

#import "RLXPostJailbreakController.h"
#import "RLXPostJailbreakLog.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>

static int gFailures;
static int32_t gLogLevel;
static NSString *gLogCategory;
static NSString *gLogMessage;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "not ok %s\n", what);
        gFailures++;
    }
}

static BOOL waitForFlag(BOOL (^flag)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while (!flag() && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return flag();
}

static void captureLog(int32_t level, const char *category, const char *message) {
    gLogLevel = level;
    gLogCategory = category ? [NSString stringWithUTF8String:category] : nil;
    gLogMessage = message ? [NSString stringWithUTF8String:message] : nil;
}

static void test_explicit_bundle_ownership(void) {
    NSBundle *firstBundle = NSBundle.mainBundle;
    NSBundle *secondBundle = [NSBundle bundleForClass:NSObject.class];
    RLXPostJailbreakController *first = [[RLXPostJailbreakController alloc] initWithResourceBundle:firstBundle];
    RLXPostJailbreakController *second = [[RLXPostJailbreakController alloc] initWithResourceBundle:secondBundle];

    expect(first.resourceBundle == firstBundle, "controller: first instance retains its explicit bundle");
    expect(second.resourceBundle == secondBundle, "controller: second instance retains its explicit bundle");
    expect(first.resourceBundle != second.resourceBundle, "controller: instances do not share resource configuration");
    expect(!first.hasActiveRootHideRuntime, "controller: host platform has no active RootHide runtime");
    expect(!first.isAvailable, "controller: host platform reports post-jailbreak runtime unavailable");
}

static void test_invalid_action(void) {
    RLXPostJailbreakController *controller = [[RLXPostJailbreakController alloc]
        initWithResourceBundle:NSBundle.mainBundle];
    __block BOOL completed = NO;
    __block BOOL completedOnMainThread = NO;
    __block NSError *result;

    [controller performAction:(RLXPostJailbreakAction)NSIntegerMax arguments:nil outputHandler:nil
                   completion:^(NSError *error) {
                       result = error;
                       completedOnMainThread = NSThread.isMainThread;
                       completed = YES;
                   }];

    expect(waitForFlag(^BOOL {
               return completed;
           }), "invalid action: completion returns");
    expect(completedOnMainThread, "invalid action: completion is delivered on the main thread");
    expect([result.domain isEqualToString:RLXPostJailbreakErrorDomain], "invalid action: error uses the module domain");
    expect(result.code == EINVAL, "invalid action: error preserves EINVAL");
    expect([result.userInfo[RLXPostJailbreakDiagnosticKey] containsString:@"phase=action_validation"],
           "invalid action: diagnostic identifies validation");
}

static void test_unavailable_action(void) {
    RLXPostJailbreakController *controller = [[RLXPostJailbreakController alloc]
        initWithResourceBundle:NSBundle.mainBundle];
    __block BOOL emittedOutput = NO;
    __block BOOL completed = NO;
    __block BOOL completedOnMainThread = NO;
    __block NSError *result;

    [controller performAction:RLXPostJailbreakActionRestartSpringBoard arguments:nil
        outputHandler:^(NSString *message) {
            (void)message;
            emittedOutput = YES;
        } completion:^(NSError *error) {
            result = error;
            completedOnMainThread = NSThread.isMainThread;
            completed = YES;
        }];

    expect(waitForFlag(^BOOL {
               return completed;
           }), "unavailable action: completion returns");
    expect(completedOnMainThread, "unavailable action: completion is delivered on the main thread");
    expect(!emittedOutput, "unavailable action: execution output is not published");
    expect([result.domain isEqualToString:RLXPostJailbreakErrorDomain],
           "unavailable action: error uses the module domain");
    expect(result.code == ENXIO, "unavailable action: error preserves ENXIO");
    expect([result.userInfo[RLXPostJailbreakDiagnosticKey] containsString:@"phase=runtime_preflight"],
           "unavailable action: diagnostic identifies preflight");
}

static void test_log_sink(void) {
    rlx_post_jailbreak_set_log_handler(captureLog);
    rlx_post_jailbreak_log(RLX_POST_JAILBREAK_LOG_WARNING, "PostJailbreakTest", "message");
    rlx_post_jailbreak_set_log_handler(NULL);

    expect(gLogLevel == RLX_POST_JAILBREAK_LOG_WARNING, "logging: level reaches the configured sink");
    expect([gLogCategory isEqualToString:@"PostJailbreakTest"], "logging: category reaches the configured sink");
    expect([gLogMessage isEqualToString:@"message"], "logging: message reaches the configured sink");
}

int main(void) {
    @autoreleasepool {
        test_explicit_bundle_ownership();
        test_invalid_action();
        test_unavailable_action();
        test_log_sink();
    }
    if (gFailures == 0) {
        fprintf(stdout, "ok post-jailbreak-controller\n");
    }
    return gFailures == 0 ? 0 : 1;
}
