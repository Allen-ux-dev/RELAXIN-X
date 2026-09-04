from pathlib import Path
root = Path(__file__).resolve().parents[3]
engine = (root / 'Relaxin/Backend/EngineSession/EngineSession.swift').read_text()
home = (root / 'Relaxin/Interface/Home/HomeView.swift').read_text()

assert '@Published private(set) var environmentSnapshot' in engine
assert '@Published private(set) var environmentState' in engine
assert 'func refreshEnvironment() async' in engine
assert 'EnvironmentInspector(' in engine
assert 'environmentState = .inspecting' in engine

refresh = engine.split('func refreshEnvironment() async',1)[1].split('\n    }',1)[0]
for forbidden in ['engine.run(', 'removeItem', 'reinstallSileo', 'performAction']:
    assert forbidden not in refresh, f'refreshEnvironment must stay read-only: {forbidden}'

assert 'engineSession.environmentState' in home
assert 'EnvironmentStatusView(' in home
assert 'await engineSession.refreshEnvironment()' in home
assert 'postJailbreakSession.isAvailable' not in home.split('@ViewBuilder private var productContent',1)[1].split('var body:',1)[0], \
    'full Home product routing must not be solely based on PostJailbreakSession.isAvailable'

print('ok home-environment-integration-contract')
