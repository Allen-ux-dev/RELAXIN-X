#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
future_token = "99.4.7"
product_files = [
    "Relaxin/Interface/Home/HomeView.swift",
    "Relaxin/Interface/Home/HomeView+Screen.swift",
    "Relaxin/Interface/Home/HomeView+Menu.swift",
    "Relaxin/Interface/Home/HomeView+TerminalContent+Layout.swift",
    "Relaxin/Interface/Home/EnvironmentStatusView.swift",
    "Relaxin/Backend/EnvironmentRecovery/EnvironmentRecoveryCoordinator.swift",
    "Relaxin/Backend/EnvironmentRecovery/RepairPlan.swift",
    "Relaxin/Backend/EnvironmentRecovery/CompatibilityGate.swift",
]
text = "\n".join((ROOT / path).read_text(errors="replace") for path in product_files)

assert future_token not in text, "synthetic future OS leaked into product source"
assert "16.5.1" not in text and "17.3.1" not in text, "product layer still owns a support range"

# Product support/admission must be expressed through resolution/capabilities,
# not fresh OS-version branches hidden under a different spelling.
version_compare_patterns = [
    r"osVersion\s*[<>]=?",
    r"systemVersion\s*[<>]=?",
    r"operatingSystemVersion\s*[<>]=?",
]
for pattern in version_compare_patterns:
    assert re.search(pattern, text) is None, f"product support comparison remains: {pattern}"

required_tokens = {
    "Relaxin/Backend/EnvironmentRecovery/CompatibilityGate.swift": ["RuntimeResolution", "requirements", "resolution.supports"],
    "Relaxin/Backend/EnvironmentRecovery/EnvironmentRecoveryCoordinator.swift": ["RuntimeOperationRequirements", "CompatibilityGate.evaluate"],
    "Relaxin/Backend/EngineSession/EngineSession.swift": ["RuntimeExecutionAdmission.validate", "freshSnapshot.runtimeResolution"],
    "Relaxin/Interface/Home/EnvironmentStatusView.swift": ["runtimeResolution", "capabilities"],
}
for path, tokens in required_tokens.items():
    body = (ROOT / path).read_text(errors="replace")
    for token in tokens:
        assert token in body, f"{path} missing capability-driven token: {token}"

print("PASS RuntimeExtensibility source contract")

# Executable dispatch is isolated behind the backend registry; product execution contains no backend-specific ID.
engine_session = (ROOT / "Relaxin/Backend/EngineSession/EngineSession.swift").read_text(errors="replace")
assert "RuntimeBackendExecutionRegistry.adapter" in engine_session
assert "LegacyRelaxinRuntimeBackend.backendID" not in engine_session, "EngineSession must not branch on a concrete backend ID"
execution_registry = (ROOT / "Relaxin/Backend/RuntimeAbstraction/RuntimeBackendExecutionAdapter.swift").read_text(errors="replace")
assert "LegacyRelaxinRuntimeBackend.backendID" in execution_registry
