/*
 * Contract tests for how a kernel-access failure is classified.
 *
 * The thing worth locking is not any one string: it is that everything reaching
 * the kernel-access build leaves it as one kind, with one recovery suggestion
 * and one statement about the kernel. That was not true before the fold — the
 * XPF session's failures came out as a different engine error code than the
 * failures the build raised itself, decided by which branch inside one call
 * happened to fail.
 */

#import "RLXKernelAccessFailure.h"

#import "RLXEngineDiagnostic.h"

#import <Foundation/Foundation.h>

#import <assert.h>
#import <stdio.h>
#import <string.h>

static NSString *diagnostic_value(RLXEngineDiagnostic *diagnostic, NSString *key) {
    NSString *prefix = [key stringByAppendingString:@"="];
    for (NSString *line in [diagnostic.renderedValue componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:prefix]) {
            return [line substringFromIndex:prefix.length];
        }
    }
    return nil;
}

static NSUInteger diagnostic_count(RLXEngineDiagnostic *diagnostic, NSString *key) {
    NSString *prefix = [key stringByAppendingString:@"="];
    NSUInteger count = 0;
    for (NSString *line in [diagnostic.renderedValue componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:prefix]) {
            count++;
        }
    }
    return count;
}

/// A failure the XPF session would build: facts only, and the kernel is clean.
static RLXKernelAccessFailure *patchfinder_failure(void) {
    RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnosticWithStage:@"analyze_kernelcache"];
    [diagnostic appendKey:@"library" value:@"libxpf"];
    return [RLXKernelAccessFailure failureWithKind:RLXKernelAccessFailureKindAccessUnavailable status:0
                                       description:@"The bundled XPF library could not be loaded."
                                     failureReason:@"dlopen failed"
                                recoverySuggestion:@"Verify the bundled libchoma/libxpf pair."
                                        diagnostic:diagnostic];
}

/// The build's own factory already states everything.
static void test_build_failure_states_its_own_facts(void) {
    RLXKernelAccessFailure *failure = rlx_kernel_access_failure(@"rocket_initialize",
                                                                EPROTO,
                                                                @"Rocket could not construct stable kernel access.",
                                                                YES,
                                                                ^(RLXEngineDiagnostic *diagnostic) {
                                                                    [diagnostic appendKey:@"stable_access"
                                                                                boolValue:NO];
                                                                });

    assert(failure.kind == RLXKernelAccessFailureKindAccessUnavailable);
    assert(failure.status == EPROTO);
    assert([diagnostic_value(failure.diagnostic, @"stage") isEqualToString:@"acquire_kernel_access"]);
    assert([diagnostic_value(failure.diagnostic, @"phase") isEqualToString:@"rocket_initialize"]);
    assert([diagnostic_value(failure.diagnostic, @"kernel_state_may_be_dirty") isEqualToString:@"true"]);
    assert([failure.recoverySuggestion isEqualToString:rlx_kernel_access_recovery_suggestion(YES)]);
}

/**
 * The fold is what makes one caller produce one classification.
 *
 * A patchfinder failure arrives saying nothing about the kernel, because on its
 * own it dirties nothing. The build knows the exploit already ran.
 */
static void test_fold_states_the_build_s_view(void) {
    RLXKernelAccessFailure *raw = patchfinder_failure();
    assert(diagnostic_value(raw.diagnostic, @"kernel_state_may_be_dirty") == nil);

    RLXKernelAccessFailure *folded = [raw failureByFoldingIntoKernelAccessBuild];

    assert(folded.kind == RLXKernelAccessFailureKindAccessUnavailable);
    assert([folded.recoverySuggestion isEqualToString:rlx_kernel_access_recovery_suggestion(YES)]);
    assert([diagnostic_value(folded.diagnostic, @"kernel_state_may_be_dirty") isEqualToString:@"true"]);

    /* The facts the session reported survive the fold. */
    assert([folded.failureDescription isEqualToString:@"The bundled XPF library could not be loaded."]);
    assert([folded.failureReason isEqualToString:@"dlopen failed"]);
    assert([diagnostic_value(folded.diagnostic, @"stage") isEqualToString:@"analyze_kernelcache"]);
    assert([diagnostic_value(folded.diagnostic, @"library") isEqualToString:@"libxpf"]);
}

/**
 * Folding a failure that already states the field corrects it rather than
 * adding a second one, so the task queue's later rewrite still has exactly one
 * field to correct once cleanup has run.
 */
static void test_fold_does_not_duplicate_the_dirty_field(void) {
    RLXKernelAccessFailure *clean = rlx_kernel_access_failure(@"kernelcache_staging",
                                                              EIO,
                                                              @"The kernelcache could not be staged for Rocket.",
                                                              NO,
                                                              nil);
    assert([diagnostic_value(clean.diagnostic, @"kernel_state_may_be_dirty") isEqualToString:@"false"]);

    RLXKernelAccessFailure *folded = [clean failureByFoldingIntoKernelAccessBuild];
    assert(diagnostic_count(folded.diagnostic, @"kernel_state_may_be_dirty") == 1);
    assert([diagnostic_value(folded.diagnostic, @"kernel_state_may_be_dirty") isEqualToString:@"true"]);
}

/**
 * Every failure the build can report carries one kind.
 *
 * Privilege escalation is the only other kind, and it is raised by a different
 * stage; nothing the kernel-access build produces should classify as anything
 * but access-unavailable.
 */
static void test_build_has_a_single_kind(void) {
    RLXKernelAccessFailure *failures[] = {
        rlx_kernel_access_failure(@"precondition", EALREADY, @"a", NO, nil),
        rlx_kernel_access_failure(@"darksword", EIO, @"b", YES, nil),
        [patchfinder_failure() failureByFoldingIntoKernelAccessBuild],
    };
    for (size_t index = 0; index < sizeof(failures) / sizeof(failures[0]); index++) {
        assert(failures[index].kind == RLXKernelAccessFailureKindAccessUnavailable);
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "usage: %s <case>\n", argv[0]);
            return 2;
        }

        const char *name = argv[1];
        if (strcmp(name, "build-facts") == 0) {
            test_build_failure_states_its_own_facts();
        } else if (strcmp(name, "fold") == 0) {
            test_fold_states_the_build_s_view();
        } else if (strcmp(name, "fold-no-duplicate") == 0) {
            test_fold_does_not_duplicate_the_dirty_field();
        } else if (strcmp(name, "single-kind") == 0) {
            test_build_has_a_single_kind();
        } else {
            fprintf(stderr, "unknown case: %s\n", name);
            return 2;
        }

        printf("ok %s\n", name);
    }
    return 0;
}
