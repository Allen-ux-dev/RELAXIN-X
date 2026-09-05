from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
engine_session = (ROOT/'Relaxin/Backend/EngineSession/EngineSession.swift').read_text()
actions = (ROOT/'Relaxin/Interface/Home/HomeView+Actions.swift').read_text()
home = (ROOT/'Relaxin/Interface/Home/HomeView.swift').read_text()
view_path = ROOT/'Relaxin/Interface/Home/PackageManagerInstallConfirmationView.swift'
assert 'packageManagerConfirmationDraft' in engine_session, 'EngineSession must publish a confirmation draft'
assert 'requestPackageManagerConfirmation' in engine_session, 'EngineSession must suspend for UI confirmation'
assert 'confirmPendingPackageManagers' in engine_session
assert 'cancelPendingPackageManagers' in engine_session
assert 'togglePendingPackageManager' in engine_session
assert 'engine.packageManagerConfirmationHandler' in engine_session
assert 'ZebraPackagePreflight' in engine_session, 'Zebra must be prepared after final confirmation'
assert 'ZebraPackagePreflight' not in actions, 'Zebra preflight must not happen before engine reaches install boundary'
assert view_path.exists(), 'final manager confirmation view missing'
view = view_path.read_text()
assert 'Confirm and Continue' in view
assert 'Cancel Jailbreak' in view
assert 'interactiveDismissDisabled' in view or 'interactiveDismissDisabled' in home
assert 'packageManagerConfirmationDraft' in home, 'HomeView must present the boundary confirmation'
print('PASS: package manager confirmation bridge contract')
