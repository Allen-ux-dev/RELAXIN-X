from pathlib import Path
root = Path(__file__).resolve().parents[3]
h = (root/'RelaxinEngine/Engine/RLXEngine.h').read_text()
m = (root/'RelaxinEngine/Engine/RLXEngine.m').read_text()
pre = (root/'RelaxinEngine/Stages/Preflight/RLXTargetConfirmationTask.m').read_text()
jt = (root/'Relaxin/Backend/JailbreakConfiguration/JailbreakTarget.swift').read_text()
config = (root/'Relaxin/Backend/JailbreakConfiguration/JailbreakConfiguration.swift').read_text()
required = [
    'RuntimeProfileID', 'RuntimeBackendID', 'RuntimeBackendGeneration',
    'RuntimeResolutionGeneration', 'HardwareExecutionClass', 'RuntimeSupportLevel'
]
for name in required:
    assert f'RLXEngineManifest{name}Key' in h, f'missing header manifest key {name}'
    assert f'RLXEngineManifest{name}Key' in m, f'missing implementation manifest key {name}'
for literal in ['16.5.1', '17.3.1', 'isSupportedVersion']:
    assert literal not in pre, f'shared preflight still owns generic version policy: {literal}'
for live_fact in ['hw.cpufamily', 'kern.osversion', 'kern.osproductversion', 'uname(&systemInfo)']:
    assert live_fact in pre, f'live target reread missing: {live_fact}'
for key in ['TargetDeviceIdentifierKey','TargetCPUFamilyKey','TargetOSVersionKey','TargetOSBuildKey']:
    assert key in pre, f'exact target comparison missing {key}'
assert 'manifest(resolution:' in jt, 'JailbreakTarget must build manifest from selected RuntimeResolution'
assert 'resolution: RuntimeResolution' in config, 'JailbreakConfiguration manifest must require RuntimeResolution'
print('PASS RuntimeManifestContract')
