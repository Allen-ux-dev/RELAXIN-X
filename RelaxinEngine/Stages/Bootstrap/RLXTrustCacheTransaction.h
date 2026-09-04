#ifndef RLXTrustCacheTransaction_h
#define RLXTrustCacheTransaction_h

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int (*RLXTrustCacheTransactionStep)(void *context);

typedef struct {
    void *context;
    RLXTrustCacheTransactionStep inspect;
    RLXTrustCacheTransactionStep prepareCandidate;
    RLXTrustCacheTransactionStep validateCandidate;
    RLXTrustCacheTransactionStep publish;
    RLXTrustCacheTransactionStep readBack;
    RLXTrustCacheTransactionStep verifyPublished;
    RLXTrustCacheTransactionStep commit;
    RLXTrustCacheTransactionStep rollbackIfSupported;
} RLXTrustCacheTransactionCallbacks;

typedef struct {
    int status;
    const char *failedPhase;
    bool publicationAttempted;
    bool rollbackAttempted;
    int rollbackStatus;
} RLXTrustCacheTransactionResult;

RLXTrustCacheTransactionResult
RLXRunTrustCacheTransaction(RLXTrustCacheTransactionCallbacks callbacks);

#ifdef __cplusplus
}
#endif

#endif /* RLXTrustCacheTransaction_h */
