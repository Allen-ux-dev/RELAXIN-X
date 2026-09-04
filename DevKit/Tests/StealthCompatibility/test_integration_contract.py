from pathlib import Path
root = Path(__file__).resolve().parents[3]
controller_h = (root/'RelaxinPostJailbreak/Controller/RLXPostJailbreakController.h').read_text()
profile_action_m = (root/'RelaxinPostJailbreak/Actions/RLXCompatibilityProfileAction.m').read_text()
engine = (root/'Relaxin/Backend/EngineSession/EngineSession.swift').read_text()
runtime = (root/'Relaxin/Application/RelaxinRuntime.swift').read_text()
view = root/'Relaxin/Interface/Settings/StealthCompatibilityView.swift'

assert 'RLXPostJailbreakActionSetCompatibilityProfile' in controller_h
assert 'RLXPostJailbreakActionArgumentBundleIdentifierKey' in controller_h
assert 'RLXPostJailbreakActionArgumentCompatibilityEnabledKey' in controller_h
assert 'RootHideConfig.plist' in profile_action_m
assert '@"appconfig"' in profile_action_m
assert 'com.aapl.relaxin' in profile_action_m, 'device-side hard rule must protect Relaxin itself'
assert 'environmentRecovery' not in profile_action_m.lower(), 'compatibility profile mutation must not invoke jailbreak recovery'
assert 'stealthProfileURL' in runtime
assert '@Published private(set) var stealthHealth' in engine
assert 'StealthProfileStore' in engine
assert 'StealthHealthInspector' in engine
assert 'setStealthProfileMode' in engine
assert 'stealthRevalidation:' in engine
assert view.exists(), 'native Stealth Compatibility settings view must exist'
text = view.read_text()
assert 'Stealth Compatibility' in text
assert 'Needs Review' in text
print('ok stealth-integration-contract')
