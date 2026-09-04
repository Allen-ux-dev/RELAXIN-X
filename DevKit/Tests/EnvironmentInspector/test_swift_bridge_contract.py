from pathlib import Path
import re

root = Path(__file__).resolve().parents[3]
bootstrap_header = root / "RelaxinEngine/Inspection/RLXBootstrapEnvironmentInspector.h"
environment_swift = root / "Relaxin/Backend/EnvironmentRecovery/EnvironmentInspector.swift"

header = bootstrap_header.read_text()
swift = environment_swift.read_text()

# This method is intended to import as `inspectSystemContainerRoots() throws`.
# For Clang to treat the trailing NSError** as Swift error handling while using
# a zero-argument swift_name, the object result must be nullable on failure.
pattern = re.compile(
    r"\+\s*\(RLXBootstrapEnvironmentEvidence\s*\*_Nullable\)"
    r"\s*inspectSystemContainerRootsWithError:\s*"
    r"\(NSError\s*\*_Nullable\s*\*_Nullable\)error\s*"
    r"NS_SWIFT_NAME\(inspectSystemContainerRoots\(\)\);",
    re.MULTILINE,
)
assert pattern.search(header), (
    "system bootstrap inspector must expose a nullable NSError** result so "
    "NS_SWIFT_NAME(inspectSystemContainerRoots()) imports as a throwing Swift API"
)

# BOOL fields inside a C struct import to Swift as ObjCBool, unlike Objective-C
# object properties. Convert them explicitly before building Swift Bool models.
for field in [
    "rootHideReportedJailbroken",
    "processRuntimeActive",
    "processIsPlatform",
]:
    assert f"evidence.{field}.boolValue" in swift, f"missing ObjCBool conversion for {field}"

# NSUInteger imports to Swift as UInt. Keep the internal recovery model signed
# (`BootstrapEvidence.ambiguous(count: Int)`) and convert explicitly at the bridge.
assert "ambiguous(count: Int(evidence.candidateCount))" in swift, (
    "candidateCount must be converted from imported UInt to the recovery model Int"
)

print("ok environment-inspector-swift-bridge-contract")
