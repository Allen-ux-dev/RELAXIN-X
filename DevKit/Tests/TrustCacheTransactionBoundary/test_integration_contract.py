from pathlib import Path
root = Path(__file__).resolve().parents[3]
src = (root/'RelaxinEngine/Stages/Bootstrap/RLXBaseBinTrustTask.m').read_text()
assert '#import "RLXTrustCacheTransaction.h"' in src
assert 'RLXRunTrustCacheTransaction' in src
assert 'prepareCandidate' in src
assert 'validateCandidate' in src
assert 'verifyPublished' in src
assert 'rollbackIfSupported' in src
assert 'transaction.failedPhase' in src or 'transactionResult.failedPhase' in src
execute = src.split('- (nullable NSError *)execute',1)[1]
assert 'RLXRunTrustCacheTransaction' in execute
assert 'BaseBin trust cache transaction committed' in src
assert "if (trustcache_nokcall_is_required())" not in src, (
    "no-kcall trust cache must still use the existing query API for read-back verification"
)
print('ok trustcache-transaction-integration')
