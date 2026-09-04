#include "RLXTrustCacheTransaction.h"

#include <errno.h>
#include <stddef.h>

static int rlx_run_required_step(RLXTrustCacheTransactionStep step, void *context) {
    return step ? step(context) : EINVAL;
}

RLXTrustCacheTransactionResult
RLXRunTrustCacheTransaction(RLXTrustCacheTransactionCallbacks callbacks) {
    RLXTrustCacheTransactionResult result = {0};

#define RLX_RUN_PHASE(field, phaseName) \
    do { \
        int status = rlx_run_required_step(callbacks.field, callbacks.context); \
        if (status != 0) { \
            result.status = status; \
            result.failedPhase = phaseName; \
            goto failed; \
        } \
    } while (0)

    RLX_RUN_PHASE(inspect, "inspect");
    RLX_RUN_PHASE(prepareCandidate, "prepare");
    RLX_RUN_PHASE(validateCandidate, "validate_candidate");
    result.publicationAttempted = true;
    RLX_RUN_PHASE(publish, "publish");
    RLX_RUN_PHASE(readBack, "read_back");
    RLX_RUN_PHASE(verifyPublished, "verify_published");
    RLX_RUN_PHASE(commit, "commit");
    return result;

failed:
    if (result.publicationAttempted && callbacks.rollbackIfSupported) {
        result.rollbackAttempted = true;
        result.rollbackStatus = callbacks.rollbackIfSupported(callbacks.context);
    }
    return result;

#undef RLX_RUN_PHASE
}
