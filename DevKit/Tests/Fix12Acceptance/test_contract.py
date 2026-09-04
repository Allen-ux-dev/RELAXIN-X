import json
from pathlib import Path

root = Path(__file__).resolve().parents[3]

def read(path: str) -> str:
    return (root / path).read_text(errors="replace")

state_source = read("Relaxin/Backend/EnvironmentRecovery/JailbreakEnvironmentState.swift")
inspector_swift = read("Relaxin/Backend/EnvironmentRecovery/EnvironmentInspector.swift")
inspector_objc = read("RelaxinEngine/Inspection/RLXBootstrapEnvironmentInspector.m")
coordinator = read("Relaxin/Backend/EnvironmentRecovery/EnvironmentRecoveryCoordinator.swift")
checkpoint = read("Relaxin/Backend/EnvironmentRecovery/EnvironmentCheckpointStore.swift")
generation = read("Relaxin/Backend/EnvironmentRecovery/EnvironmentGeneration.swift")
stale = read("Relaxin/Backend/EnvironmentRecovery/StaleStateInvalidator.swift")
repair = read("Relaxin/Backend/EnvironmentRecovery/RepairPlan.swift")
trust = read("RelaxinEngine/Stages/Bootstrap/RLXTrustCacheTransaction.m")
basebin_trust = read("RelaxinEngine/Stages/Bootstrap/RLXBaseBinTrustTask.m")
engine = read("Relaxin/Backend/EngineSession/EngineSession.swift")
home = read("Relaxin/Interface/Home/HomeView.swift")
home_menu = read("Relaxin/Interface/Home/HomeView+Menu.swift")
home_screen = read("Relaxin/Interface/Home/HomeView+Screen.swift")
menu_action = read("Relaxin/Interface/Home/HomeView+MenuAction.swift")
stealth = "\n".join(
    path.read_text(errors="replace")
    for path in sorted((root / "Relaxin/Backend/StealthCompatibility").glob("*.swift"))
)
makefile = read("Makefile")
localizations_path = root / "Relaxin/Resources/Localizable.xcstrings"
localizations = json.loads(localizations_path.read_text())
strings = localizations["strings"]

required_localized_strings = [
    "Restore Jailbreak Environment",
    "Repair Current Environment",
    "Environment Check",
    "Runtime Inactive",
    "Environment Healthy",
    "Environment Requires Repair",
    "Compatibility Profiles Need Revalidation",
    "Stealth Compatibility Suspended",
]
required_locales = {"ar", "de", "en", "es", "fr", "ja", "ru", "vi", "zh-Hans"}
for key in required_localized_strings:
    assert key in strings, f"missing localized UI key: {key}"
    locales = set(strings[key].get("localizations", {}))
    assert required_locales <= locales, f"{key} missing locales: {sorted(required_locales - locales)}"

# 1-3: state is evidence-driven; history cannot synthesize live health.
assert "installedInactive" in state_source
assert "snapshot.runtime.active" in state_source
assert "snapshot.bootstrap.isValidRelaxin" in state_source
assert "historicalHint" not in state_source, "historical hint must not resolve environment state"
assert "engineSession.environmentState" in home
routing = home.split("private var showsVerifiedPostJailbreakContent", 1)[1].split("@ViewBuilder private var productContent", 1)[0]
full_branch = routing.split("case .full:", 1)[1].split("case .lite:", 1)[0]
assert "engineSession.environmentState" in full_branch
assert "postJailbreakSession.isAvailable" not in full_branch

# 4-5: inspection is read-only and ambiguity/incompleteness are first-class evidence.
for forbidden in [
    "removeItemAtPath", "createDirectoryAtPath", "moveItemAtPath", "writeToFile",
    "unlink(", "rmdir(", "rename(", "chmod(", "chown(",
]:
    assert forbidden not in inspector_objc, f"read-only inspector mutates state via {forbidden}"
assert "candidate_without_marker" in inspector_objc
assert "multiple_installed_roots" in inspector_objc
assert "return .incomplete" in inspector_swift
assert "return .ambiguous" in inspector_swift

# 6-10: restore gets a fresh gate; checkpoint is history; final success is fresh verification.
assert "CompatibilityGate.evaluate(initialSnapshot, requirements: requirements)" in coordinator
assert "runtimeRequirements(for: operation, snapshot: initialSnapshot)" in coordinator
assert "persisted checkpoint is progress history" in coordinator
assert "finalSnapshot = await inspector.inspect()" in coordinator
assert "RecoveryStage.execute" in coordinator and ".verify" in coordinator
assert "loadValidated" in checkpoint and "checkpoint_decode_failed" in checkpoint

# 11-15: targeted repair and validation stay narrow and non-destructive.
assert "repairSileo" in repair and "repairZebra" in repair
assert "freshInstall" not in repair
assert "sileo" in repair and "zebra" in repair
assert "blockingFindings" in repair
assert "startTargetedRepair" in engine
repair_section = engine.split("func startTargetedRepair", 1)[1].split("func startRecovery", 1)[0]
assert "engine.run(" not in repair_section, "targeted repair must not call full jailbreak engine"

# 17: identity/rules changes invalidate verification without deleting the environment.
assert "profile_rules_changed" in stale
assert "deleteEnvironment: false" in stale
assert "preserveExplicitProfilePreferences: true" in stale
assert "currentProfileRulesVersion = 2" in generation

# 18: trust-cache wrapper verifies published state without inventing a new primitive.
for phase in ["inspect", "prepareCandidate", "validateCandidate", "publish", "readBack", "verifyPublished", "commit"]:
    assert phase in trust
assert "RLXRunTrustCacheTransaction" in basebin_trust
assert "randomizeAndBootstrapBasebinTrustcache" in basebin_trust

# 19-24: Stealth uses profile rules, revalidation, independent repair, and non-evasion gate.
assert "StealthProfileResolver" in stealth
assert "StealthProfileRevalidator" in stealth
assert "managementBundleIdentifiers" in stealth
assert "case automatic" in stealth and "case developer" in stealth
assert "case revalidateProfile" in stealth
assert "stealthRevalidation:" in engine
assert "StealthProfileStore.invalidatingVerification" in engine
assert "test_non_evasion_contract.py" in makefile
assert "StealthCompatibility" in makefile

# Final product wiring: environment check + native Stealth settings + diagnostics.
assert "environmentCheck" in menu_action
assert "stealthCompatibility" in menu_action
home_menu_wiring = home_menu + "\n" + home_screen
assert "Environment Check" in home_menu_wiring
assert "Stealth Compatibility" in home_menu_wiring
assert (root / "Relaxin/Interface/Settings/StealthCompatibilityView.swift").exists()
diagnostics = root / "Relaxin/Backend/EnvironmentRecovery/EnvironmentDiagnostics.swift"
assert diagnostics.exists(), "structured environment diagnostics are required"
diagnostic_text = diagnostics.read_text(errors="replace")
for required in ["stage", "state", "generation", "checkpoint", "findings"]:
    assert required in diagnostic_text.lower(), f"diagnostics missing {required}"
assert "environmentDiagnosticReport" in engine

# Build/host regression registration.
assert "TrustCacheTransactionBoundary" in makefile
assert "EnvironmentDiagnostics" in makefile
assert "EnvironmentDiagnostics/test_export_contract.py" in makefile
assert "XcodeFix12TargetMembership/test_contract.py" in makefile
assert "StealthCompatibility/test_localization_contract.py" in makefile
assert "Fix12Acceptance/test_contract.py" in makefile

print("ok fix12-acceptance-contract")
