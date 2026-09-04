from pathlib import Path
root = Path(__file__).resolve().parents[3]
runtime = (root/'Relaxin/Application/RelaxinRuntime.swift').read_text()
session = (root/'Relaxin/Backend/EngineSession/EngineSession.swift').read_text()

assert 'environmentRecoveryCheckpointURL' in runtime
assert 'appendingPathComponent("EnvironmentRecovery"' in runtime
assert 'appendingPathComponent("checkpoint.json"' in runtime
assert 'EnvironmentCheckpointStore(' in session
assert 'fileURL: runtime.environmentRecoveryCheckpointURL' in session
assert 'checkpointStore: checkpointStore' in session
print('ok environment-checkpoint-runtime-contract')
