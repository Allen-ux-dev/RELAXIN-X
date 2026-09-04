from pathlib import Path
import re

root = Path(__file__).resolve().parents[3]
pbx = (root / "Relaxin.xcodeproj/project.pbxproj").read_text(errors="replace")

match = re.search(
    r'B1800000000000000000000D /\* Exceptions for "Relaxin" folder in "RelaxinLite" target \*/ = \{(.*?)\n\t\t\};',
    pbx,
    re.S,
)
assert match, "RelaxinLite membership exception block missing"
block = match.group(1)

required = [
    "Backend/EnvironmentRecovery/CompatibilityGate.swift",
    "Backend/EnvironmentRecovery/EnvironmentCheckpointStore.swift",
    "Backend/EnvironmentRecovery/EnvironmentDiagnostics.swift",
    "Backend/EnvironmentRecovery/EnvironmentGeneration.swift",
    "Backend/EnvironmentRecovery/EnvironmentInspector.swift",
    "Backend/EnvironmentRecovery/EnvironmentPrimaryAction.swift",
    "Backend/EnvironmentRecovery/EnvironmentRecoveryCoordinator.swift",
    "Backend/EnvironmentRecovery/EnvironmentSnapshot.swift",
    "Backend/EnvironmentRecovery/JailbreakEnvironmentState.swift",
    "Backend/EnvironmentRecovery/PostConditionVerifier.swift",
    "Backend/EnvironmentRecovery/RecoveryOperation.swift",
    "Backend/EnvironmentRecovery/RecoveryStage.swift",
    "Backend/EnvironmentRecovery/RepairPlan.swift",
    "Backend/EnvironmentRecovery/StaleStateInvalidator.swift",
    "Backend/StealthCompatibility/AppStealthProfile.swift",
    "Backend/StealthCompatibility/StealthHealthInspector.swift",
    "Backend/StealthCompatibility/StealthProfileResolver.swift",
    "Backend/StealthCompatibility/StealthProfileRevalidator.swift",
    "Backend/StealthCompatibility/StealthProfileStore.swift",
    "Interface/Home/EnvironmentStatusView.swift",
    "Interface/Settings/StealthCompatibilityView.swift",
]
for path in required:
    assert path in block, f"RelaxinLite must exclude Fix12 full-only source: {path}"

print("ok xcode-fix12-target-membership-contract")
