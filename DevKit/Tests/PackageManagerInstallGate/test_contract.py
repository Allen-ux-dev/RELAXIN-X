from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
engine_h = (ROOT / 'RelaxinEngine/Engine/RLXEngine.h').read_text()
engine_m = (ROOT / 'RelaxinEngine/Engine/RLXEngine.m').read_text()
context_h = (ROOT / 'RelaxinEngine/Engine/RLXEngineRunContext.h').read_text()
context_m = (ROOT / 'RelaxinEngine/Engine/RLXEngineRunContext.m').read_text()
task = (ROOT / 'RelaxinEngine/Stages/Bootstrap/RLXBootstrapFinalizationTask.m').read_text()
finalizer_h = (ROOT / 'RelaxinEngine/Bootstrap/RLXBootstrapFinalizer.h').read_text()
finalizer_m = (ROOT / 'RelaxinEngine/Bootstrap/RLXBootstrapFinalizer.m').read_text()

required_engine = [
    'RLXPackageManagerInstallSelection',
    'RLXPackageManagerConfirmationReply',
    'RLXPackageManagerConfirmationHandler',
    'packageManagerConfirmationHandler',
]
for token in required_engine:
    assert token in engine_h, f'missing engine confirmation API: {token}'

assert 'RLXEngineManifestInstallPrism' not in engine_h
assert 'RLXEngineManifestInstallPrism' not in engine_m
assert 'packageManagerConfirmationHandler:self.packageManagerConfirmationHandler' in engine_m
assert 'packageManagerConfirmationHandler' in context_h
assert '_packageManagerConfirmationHandler = [packageManagerConfirmationHandler copy];' in context_m

assert 'packageManagerConfirmationHandler' in task
assert 'dispatch_semaphore_wait' in task
assert 'installPrism:confirmedSelection.installPrism' in task
assert 'zebraPackagePath:confirmedSelection.zebraPackagePath' in task
assert '@"prismstore"' in finalizer_m
assert 'installPrism:(BOOL)installPrism' in finalizer_h

# Manager confirmation must happen before the finalizer begins installing managers.
confirm_index = task.index('packageManagerConfirmationHandler')
finalizer_index = task.index('RLXBootstrapFinalizer *finalizer')
assert confirm_index < finalizer_index

print('PASS: package manager install gate contract')
