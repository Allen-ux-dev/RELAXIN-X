#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

def read(rel):
    return (ROOT / rel).read_text()

home_files = [
    'Relaxin/Interface/Home/HomeView+TerminalContent+Layout.swift',
    'Relaxin/Interface/Home/EnvironmentStatusView.swift',
    'Relaxin/Interface/Home/HomeView+Screen.swift',
    'Relaxin/Interface/Home/HomeView+Menu.swift',
    'Relaxin/Interface/Home/HomeView.swift',
]
home = '\n'.join(read(p) for p in home_files)
gate = read('Relaxin/Backend/EnvironmentRecovery/CompatibilityGate.swift')
inspector = read('Relaxin/Backend/EnvironmentRecovery/EnvironmentInspector.swift')
pbx = read('Relaxin.xcodeproj/project.pbxproj')

# Product/UI layers must not own a version support envelope.
assert 'For iOS 16.5.1-17.3.1 devices' not in home
assert '16.5.1' not in gate and '17.3.1' not in gate

# Runtime status must be capability/resolution driven.
status = read('Relaxin/Interface/Home/EnvironmentStatusView.swift')
for token in ['profileDisplayName', 'backendDisplayName', 'supportLevel', 'capabilities']:
    assert token in status, f'missing resolution-driven status token: {token}'

# Developer policy must be persisted and read by production evidence.
policy_store = ROOT / 'Relaxin/Backend/RuntimeAbstraction/RuntimeBackendPolicyStore.swift'
assert policy_store.is_file(), 'missing RuntimeBackendPolicyStore.swift'
policy = policy_store.read_text()
for token in ['experimentalEnabled', 'preferredBackendID', 'UserDefaults']:
    assert token in policy, f'missing policy-store token: {token}'
assert 'RuntimeBackendPolicyStore' in inspector
assert 'experimentalEnabled: false, preferredBackendID: nil' not in inspector.split('#if canImport')[1]

# UI offers explicit experimental opt-in and a recommended automatic selection.
settings = ROOT / 'Relaxin/Interface/Settings/RuntimeBackendSettingsView.swift'
assert settings.is_file(), 'missing RuntimeBackendSettingsView.swift'
settings_text = settings.read_text()
for token in ['Enable Experimental Backends', 'Recommended', 'preferredBackendID', 'RuntimeBackendRegistry.production']:
    assert token in settings_text, f'missing backend settings token: {token}'
assert 'runtimeBackendSettings' in home
assert 'runtimeSupportsPrimaryAction' in home, 'primary actions must be capability-gated in Home'

# Fix13 full-only runtime files must not leak into RelaxinLite's synchronized target.
for rel in [
    'Backend/RuntimeAbstraction/HardwareExecutionClass.swift',
    'Backend/RuntimeAbstraction/RuntimeEnvironment.swift',
    'Backend/RuntimeAbstraction/RuntimeCapability.swift',
    'Backend/RuntimeAbstraction/RuntimeProfile.swift',
    'Backend/RuntimeAbstraction/RuntimeBackendDescriptor.swift',
    'Backend/RuntimeAbstraction/RuntimeBackendPolicy.swift',
    'Backend/RuntimeAbstraction/RuntimeBackendPolicyStore.swift',
    'Backend/RuntimeAbstraction/RuntimeResolution.swift',
    'Backend/RuntimeAbstraction/RuntimeResolutionIdentity.swift',
    'Backend/RuntimeAbstraction/RuntimeProfileResolver.swift',
    'Backend/RuntimeAbstraction/RuntimeOperationRequirements.swift',
    'Backend/RuntimeAbstraction/RuntimeExecutionAdmission.swift',
    'Backend/RuntimeAbstraction/RuntimeBackendExecutionAdapter.swift',
    'Backend/RuntimeAbstraction/RuntimeProfileRegistry.swift',
    'Backend/RuntimeAbstraction/RuntimeBackend.swift',
    'Backend/RuntimeAbstraction/LegacyRelaxinRuntimeBackend.swift',
    'Backend/RuntimeAbstraction/RuntimeBackendRegistry.swift',
    'Interface/Settings/RuntimeBackendSettingsView.swift',
]:
    assert rel in pbx, f'RelaxinLite exclusion missing: {rel}'

print('PASS RuntimeResolution UI contract')
