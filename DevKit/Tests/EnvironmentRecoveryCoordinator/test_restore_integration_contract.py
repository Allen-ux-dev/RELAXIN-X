from pathlib import Path
root = Path(__file__).resolve().parents[3]
engine_h = (root/'RelaxinEngine/Engine/RLXEngine.h').read_text()
engine_m = (root/'RelaxinEngine/Engine/RLXEngine.m').read_text()
prep_h = (root/'RelaxinEngine/Bootstrap/RLXBootstrapPreparer.h').read_text()
prep_m = (root/'RelaxinEngine/Bootstrap/RLXBootstrapPreparer.m').read_text()
prep_task = (root/'RelaxinEngine/Stages/Bootstrap/RLXBootstrapPreparationTask.m').read_text()
engine_session = (root/'Relaxin/Backend/EngineSession/EngineSession.swift').read_text()
menu_action = (root/'Relaxin/Interface/Home/HomeView+MenuAction.swift').read_text()
menu = (root/'Relaxin/Interface/Home/HomeView+Menu.swift').read_text()
actions = (root/'Relaxin/Interface/Home/HomeView+Actions.swift').read_text()

assert 'RLXEngineManifestBootstrapRestoreModeKey' in engine_h
assert 'RLXEngineManifestBootstrapRestoreModeKey' in engine_m
assert 'requiresExistingBootstrap' in prep_h
assert 'requiresExistingBootstrap' in prep_task
assert 'restore_requires_existing_bootstrap' in prep_m
scan_to_install = prep_m.split('scanJailbreakRootsWithInstalledRoot',1)[1].split('uint64_t brand',1)[0]
assert '_requiresExistingBootstrap && !installedRoot' in scan_to_install

assert 'func startRecovery(' in engine_session
assert 'EnvironmentRecoveryCoordinator(' in engine_session
assert '.bootstrapRestoreModeKey' in engine_session
assert 'case restoreEnvironment' in menu_action
assert 'case repairEnvironment' in menu_action
assert 'EnvironmentPrimaryAction.resolve' in menu
assert 'startRecoveryEnvironment()' in actions

print('ok restore-integration-contract')
