from pathlib import Path
root = Path(__file__).resolve().parents[3]
engine_session = (root/'Relaxin/Backend/EngineSession/EngineSession.swift').read_text()
actions = (root/'Relaxin/Interface/Home/HomeView+Actions.swift').read_text()
engine_actions_h = (root/'RelaxinEngine/Actions/RLXEngine+Actions.h').read_text()
engine_actions_m = (root/'RelaxinEngine/Actions/RLXEngine+Actions.m').read_text()
finalizer_h = (root/'RelaxinEngine/Bootstrap/RLXBootstrapFinalizer.h').read_text()
finalizer_m = (root/'RelaxinEngine/Bootstrap/RLXBootstrapFinalizer.m').read_text()

assert 'func startTargetedRepair(' in engine_session
repair_body = engine_session.split('func startTargetedRepair(',1)[1].split('\n    }',1)[0]
assert 'engine.run(' not in repair_body, 'targeted repair must not run full jailbreak engine'
assert 'executeEngineRun' not in repair_body, 'targeted repair must not call full engine pipeline'
assert 'RepairPlan.derive' in engine_session
assert 'desiredPackageManagers:' in engine_session, 'engine repair must pass the user package-manager selection explicitly'
assert 'JailbreakConfiguration(defaults: runtime.defaults)' in engine_session, 'repair must read the persisted user package-manager preference'
assert 'verifyRepair(' in engine_session
assert '.reinstallSileo' in engine_session
assert '.reinstallZebra' in engine_session
assert '.repairPackageSources' in engine_session
assert 'startTargetedRepair' in actions
assert 'Task 7 replaces' not in actions

assert 'RLXEngineActionReinstallZebra' in engine_actions_h
assert 'RLXEngineActionRepairPackageSources' in engine_actions_h
assert 'RLXEngineActionArgumentPackagePathKey' in engine_actions_h
assert 'RLXEngineActionArgumentPackageManagerKey' in engine_actions_h
assert 'RLXEngineActionReinstallZebra' in engine_actions_m
assert 'RLXEngineActionRepairPackageSources' in engine_actions_m

assert 'installExternalPackageAtPath' in finalizer_h
external = finalizer_m.split('installExternalPackageAtPath',1)[1]
assert 'pathExtension.lowercaseString' in external
assert 'NSHomeDirectory' in external
assert 'install_pkg' in external
print('ok targeted-repair-contract')

inspector = (root/'Relaxin/Backend/EnvironmentRecovery/EnvironmentInspector.swift').read_text()
assert 'health.findings' in inspector, 'production health mapping must preserve specific package-manager findings'
assert 'sourceFinding = \"\\(manager)_sources_missing\"' in inspector
assert 'registrationFinding = \"\\(manager)_registration_missing\"' in inspector
