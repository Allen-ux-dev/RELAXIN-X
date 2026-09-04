#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
read = lambda rel: (ROOT / rel).read_text(errors="replace")

home_paths = [
    "Relaxin/Interface/Home/HomeView.swift",
    "Relaxin/Interface/Home/HomeView+Screen.swift",
    "Relaxin/Interface/Home/HomeView+Menu.swift",
    "Relaxin/Interface/Home/HomeView+TerminalContent+Layout.swift",
    "Relaxin/Interface/Home/EnvironmentStatusView.swift",
]
home = "\n".join(read(p) for p in home_paths)
gate = read("Relaxin/Backend/EnvironmentRecovery/CompatibilityGate.swift")
target = read("Relaxin/Backend/JailbreakConfiguration/JailbreakTarget.swift")
preflight = read("RelaxinEngine/Stages/Preflight/RLXTargetConfirmationTask.m")
resolver = read("Relaxin/Backend/RuntimeAbstraction/RuntimeProfileResolver.swift")
capability = read("Relaxin/Backend/RuntimeAbstraction/RuntimeCapability.swift")
checkpoint = read("Relaxin/Backend/EnvironmentRecovery/EnvironmentCheckpointStore.swift")
diagnostics = read("Relaxin/Backend/EnvironmentRecovery/EnvironmentDiagnostics.swift")
engine_session = read("Relaxin/Backend/EngineSession/EngineSession.swift")
coordinator = read("Relaxin/Backend/EnvironmentRecovery/EnvironmentRecoveryCoordinator.swift")
pbx = read("Relaxin.xcodeproj/project.pbxproj")
makefile = read("Makefile")

# 1-4: product/shared layers do not own the support range.
for body, name in [(home, "Home"), (gate, "CompatibilityGate"), (target, "JailbreakTarget"), (preflight, "shared preflight")]:
    assert not ("16.5.1" in body or "17.3.1" in body), f"{name} still owns the fixed support range"
assert "isSupportedOSVersion" not in target

# 5: live target confirmation remains immediately before execution.
for token in ["currentTarget", "hw.cpufamily", "kern.osproductversion", "TargetDeviceIdentifier", "TargetOSBuild", "RuntimeProfileID", "RuntimeBackendID"]:
    assert token in preflight, f"preflight lost live-target confirmation token: {token}"

# 6/13: profile/backend are separate concepts and full support vocabulary exists.
assert (ROOT / "Relaxin/Backend/RuntimeAbstraction/RuntimeProfile.swift").is_file()
assert (ROOT / "Relaxin/Backend/RuntimeAbstraction/RuntimeBackend.swift").is_file()
for token in ["supported", "experimental", "partial", "recoveryOnly", "unsupported"]:
    assert re.search(rf"case\s+{token}\b", capability), f"missing support level: {token}"

# 7-11: deterministic selection, no synthetic fallback, stable preference, experimental opt-in.
for token in ["candidateSort", "sorted", "runtimeBackendMissing", "backendCapabilityMissing", "experimentalBackendDisabled"]:
    assert token in resolver, f"resolver contract missing: {token}"
assert "automaticRank" in resolver
assert "policy.experimentalEnabled" in resolver
assert "runtimeProfileMissing" in resolver
assert "backendMaturityIncompatible" in resolver

# Executable backend dispatch must follow the resolved backend ID rather than hard-wire RLXEngine in EngineSession.
dispatch = read("Relaxin/Backend/RuntimeAbstraction/RuntimeBackendExecutionAdapter.swift")
assert "RuntimeBackendExecutionRegistry" in dispatch and "LegacyRelaxinRuntimeExecutionAdapter" in dispatch
execute_section = engine_session.split("private func executeEngineRun(", 1)[1].split("private func revalidateStealth", 1)[0]
assert "RuntimeBackendExecutionRegistry.adapter" in execute_section
assert "engine.run(manifest: manifest)" not in execute_section

# 12: immutable selected identity + fresh re-resolution; no mid-stage fallback API.
for token in ["RuntimeExecutionAdmission.validate", "freshSnapshot.runtimeResolution", "runtimeResolutionIdentity(from: manifest)"]:
    assert token in engine_session, f"execution admission missing: {token}"
assert "fallbackBackend" not in engine_session and "switchBackend" not in engine_session

# 14/15: restore and operations are capability specific.
assert "RuntimeOperationRequirements.restore" in coordinator
assert "RuntimeOperationRequirements.repair" in coordinator
assert "RuntimeOperationRequirements.freshInstall" in coordinator

# 16/17: checkpoint carries runtime identity; mismatch only invalidates metadata.
assert "runtimeResolutionIdentity" in checkpoint
for token in ["runtime_profile_changed", "runtime_backend_changed", "runtime_backend_generation_changed", "runtime_resolution_generation_changed"]:
    assert token in read("Relaxin/Backend/RuntimeAbstraction/RuntimeResolutionIdentity.swift")
for forbidden in ["removeItem", "deleteBootstrap", "deleteTrustCache"]:
    assert forbidden not in checkpoint, f"checkpoint stale path must not delete installed environment: {forbidden}"

# 18: privacy-safe structured resolution diagnostics.
for token in ["runtimeResolution", "profileID", "backendID", "supportLevel", "capabilities", "missingCapabilities", "rejectedCandidateReasonCodes"]:
    assert token in diagnostics, f"runtime diagnostics missing: {token}"
for forbidden in ["jbroot", "environmentIdentity"]:
    assert forbidden not in diagnostics, f"diagnostics exports forbidden detail: {forbidden}"

# 19-21: capability-driven Fix12 integration + current adapter + synthetic extensibility proof.
assert "RuntimeResolution" in gate and "resolution.supports" in gate
assert "RuntimeProfileRegistry.currentPublicSnapshotID" in read("Relaxin/Backend/RuntimeAbstraction/LegacyRelaxinRuntimeBackend.swift")
assert (ROOT / "DevKit/Tests/RuntimeExtensibility/main.swift").is_file()
assert (ROOT / "DevKit/Tests/RuntimeExtensibility/test_source_contract.py").is_file()

# 23: full-only Fix13 files are excluded from RelaxinLite.
for rel in [
    "Backend/RuntimeAbstraction/RuntimeProfileResolver.swift",
    "Backend/RuntimeAbstraction/RuntimeBackendPolicyStore.swift",
    "Interface/Settings/RuntimeBackendSettingsView.swift",
]:
    assert rel in pbx, f"RelaxinLite exclusion missing: {rel}"

# 24: host regression entrypoint includes Fix13 portable gates before platform-specific tests.
for token in [
    "DevKit/Tests/RuntimeAbstraction",
    "DevKit/Tests/RuntimeBackendPolicy",
    "DevKit/Tests/RuntimeExtensibility",
    "DevKit/Tests/RuntimeManifestContract/test_contract.py",
    "DevKit/Tests/RuntimeResolutionIntegration/test_contract.py",
    "DevKit/Tests/RuntimeResolutionIntegration/test_ui_contract.py",
    "DevKit/Tests/RuntimeBackendDispatch/test_contract.py",
    "DevKit/Tests/Fix13Acceptance/test_contract.py",
]:
    assert token in makefile, f"test-host missing Fix13 gate: {token}"

print("PASS Fix13Acceptance source contract")
