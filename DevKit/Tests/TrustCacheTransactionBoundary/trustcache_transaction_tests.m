#include <stdio.h>
#include <string.h>

#include "../../../RelaxinEngine/Stages/Bootstrap/RLXTrustCacheTransaction.h"

typedef struct {
    char events[512];
    int failVerify;
    int rollbackCalls;
} TestContext;

static void append_event(TestContext *ctx, const char *event) {
    if (ctx->events[0] != '\0') {
        strncat(ctx->events, ",", sizeof(ctx->events) - strlen(ctx->events) - 1);
    }
    strncat(ctx->events, event, sizeof(ctx->events) - strlen(ctx->events) - 1);
}

#define STEP(name) \
    static int name(void *opaque) { \
        TestContext *ctx = opaque; \
        append_event(ctx, #name); \
        return 0; \
    }

STEP(inspect)
STEP(prepare)
STEP(validate_candidate)
STEP(publish)
STEP(read_back)
STEP(commit)

static int verify_published(void *opaque) {
    TestContext *ctx = opaque;
    append_event(ctx, "verify_published");
    return ctx->failVerify ? 71 : 0;
}

static int rollback(void *opaque) {
    TestContext *ctx = opaque;
    append_event(ctx, "rollback");
    ctx->rollbackCalls += 1;
    return 0;
}

static int expect(int condition, const char *message) {
    if (condition) return 0;
    fprintf(stderr, "not ok %s\n", message);
    return 1;
}

static RLXTrustCacheTransactionCallbacks callbacks(TestContext *ctx, int supportsRollback) {
    RLXTrustCacheTransactionCallbacks cb = {0};
    cb.context = ctx;
    cb.inspect = inspect;
    cb.prepareCandidate = prepare;
    cb.validateCandidate = validate_candidate;
    cb.publish = publish;
    cb.readBack = read_back;
    cb.verifyPublished = verify_published;
    cb.commit = commit;
    cb.rollbackIfSupported = supportsRollback ? rollback : NULL;
    return cb;
}

int main(void) {
    int failures = 0;

    TestContext success = {0};
    RLXTrustCacheTransactionResult successResult =
        RLXRunTrustCacheTransaction(callbacks(&success, 1));
    failures += expect(successResult.status == 0, "success transaction returns zero");
    failures += expect(
        strcmp(success.events,
               "inspect,prepare,validate_candidate,publish,read_back,verify_published,commit") == 0,
        "transaction order includes read-back verification before commit");
    failures += expect(success.rollbackCalls == 0, "success does not rollback");

    TestContext failure = {0};
    failure.failVerify = 1;
    RLXTrustCacheTransactionResult failureResult =
        RLXRunTrustCacheTransaction(callbacks(&failure, 1));
    failures += expect(failureResult.status == 71, "verify failure is returned");
    failures += expect(failureResult.rollbackAttempted, "published verify failure attempts supported rollback");
    failures += expect(failure.rollbackCalls == 1, "rollback callback runs once");
    failures += expect(strstr(failure.events, "verify_published,rollback") != NULL,
                       "rollback happens after verify failure");

    TestContext noRollback = {0};
    noRollback.failVerify = 1;
    RLXTrustCacheTransactionResult noRollbackResult =
        RLXRunTrustCacheTransaction(callbacks(&noRollback, 0));
    failures += expect(noRollbackResult.status == 71, "failure remains failure without rollback support");
    failures += expect(!noRollbackResult.rollbackAttempted, "unsupported rollback is not pretended");

    if (failures == 0) puts("ok trustcache-transaction-boundary");
    return failures == 0 ? 0 : 1;
}
