from pathlib import Path
root = Path(__file__).resolve().parents[3]
jt = (root/'Relaxin/Backend/JailbreakConfiguration/JailbreakTarget.swift').read_text()
profiles = root/'Relaxin/Backend/RuntimeAbstraction/RuntimeProfileRegistry.swift'
backends = root/'Relaxin/Backend/RuntimeAbstraction/RuntimeBackendRegistry.swift'
adapter = root/'Relaxin/Backend/RuntimeAbstraction/LegacyRelaxinRuntimeBackend.swift'
assert 'enum RuntimeProfile' not in jt, 'JailbreakTarget must not own product RuntimeProfile'
assert 'isSupportedOSVersion' not in jt, 'JailbreakTarget must not decide product OS support range'
assert 'HardwareExecutionClass' in jt, 'JailbreakTarget must expose hardware execution class'
for p in [profiles, backends, adapter]:
    assert p.exists(), f'missing {p.name}'
pt = profiles.read_text()
bt = backends.read_text()
at = adapter.read_text()
assert '16.5.1' in pt and '17.3.1' in pt, 'current public support envelope belongs in profile registry'
assert 'LegacyRelaxinRuntimeBackend' in bt, 'registry must register the current adapter'
assert '.stable' in at, 'current adapter must declare stable maturity'
print('PASS RuntimeResolutionIntegration contract')
