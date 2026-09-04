from pathlib import Path
root=Path(__file__).resolve().parents[3]
engine=(root/'Relaxin/Backend/EngineSession/EngineSession.swift').read_text()
home=(root/'Relaxin/Interface/Home/HomeView+Actions.swift').read_text()
config=(root/'Relaxin/Backend/JailbreakConfiguration/JailbreakConfiguration.swift').read_text()
assert 'RuntimeExecutionAdmission.validate' in engine, 'EngineSession must validate selected resolution immediately before engine run'
assert 'environmentInspector.inspect()' in engine, 'EngineSession must fresh-inspect before privileged execution'
assert 'runtimeResolutionIdentity' in engine or 'selectedIdentity' in engine, 'EngineSession must compare resolution identity'
assert 'RuntimeOperationRequirements.restore' in engine, 'restore path must enforce restore capabilities'
assert 'RuntimeOperationRequirements.freshInstall' in engine, 'fresh path must enforce fresh capabilities'
assert 'configuration.manifest(for: .current, resolution:' in home, 'Home must build manifest from resolved runtime contract'
assert 'resolution: RuntimeResolution' in config
# No dynamic backend replacement inside engine execution loop.
assert 'fallbackBackend' not in engine and 'switchBackend' not in engine
print('PASS RuntimeBackendExecution integration contract')
