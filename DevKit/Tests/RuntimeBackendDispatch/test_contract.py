#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
engine_session = (ROOT / 'Relaxin/Backend/EngineSession/EngineSession.swift').read_text(errors='replace')
adapter_path = ROOT / 'Relaxin/Backend/RuntimeAbstraction/RuntimeBackendExecutionAdapter.swift'
assert adapter_path.is_file(), 'missing executable backend adapter boundary'
adapter = adapter_path.read_text(errors='replace')

for token in [
    'protocol RuntimeBackendExecutionAdapter',
    'LegacyRelaxinRuntimeExecutionAdapter',
    'RuntimeBackendExecutionRegistry',
    'func adapter(',
    'LegacyRelaxinRuntimeBackend.backendID',
    'engine.run(manifest: manifest',
]:
    assert token in adapter, f'missing backend execution dispatch token: {token}'

section = engine_session.split('private func executeEngineRun(', 1)[1].split('private func revalidateStealth', 1)[0]
for token in ['runtimeBackendIDKey', 'RuntimeBackendExecutionRegistry.adapter', 'backend.execute']:
    assert token in section, f'EngineSession execution does not dispatch through selected backend: {token}'
assert 'engine.run(manifest: manifest)' not in section, 'EngineSession must not hard-wire the current engine after backend resolution'

# Backend selection is immutable from manifest admission through execution.
assert 'validateRuntimeAdmission' in engine_session
assert 'runtimeResolutionIdentity(from: manifest)' in engine_session
assert 'fallbackBackend' not in section and 'switchBackend' not in section

print('PASS RuntimeBackendDispatch contract')
