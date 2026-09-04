from pathlib import Path
root = Path(__file__).resolve().parents[3]
inspector = (root/'Relaxin/Backend/EnvironmentRecovery/EnvironmentInspector.swift').read_text()
generation = (root/'Relaxin/Backend/EnvironmentRecovery/EnvironmentGeneration.swift').read_text()

assert 'func fingerprintEvidence() async -> EnvironmentFingerprint' in inspector
assert 'JailbreakTarget.current.deviceIdentifier' in inspector
assert 'JailbreakTarget.current.osVersion' in inspector
assert 'JailbreakTarget.current.osBuild' in inspector
assert 'func generationEvidence() async -> EnvironmentGeneration' in inspector
assert 'AppInfo.build(in: runtime.resourceBundle)' in inspector
assert 'currentBootstrapGeneration' in generation
assert 'currentBaseBinGeneration' in generation
assert 'currentEnvironmentSchema' in generation
assert 'currentProfileRulesVersion' in generation
assert 'currentProfileRulesVersion = 2' in generation, 'Fix12 Stealth rule contract requires generation 2'
print('ok production-environment-identity-contract')
