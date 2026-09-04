#!/usr/bin/env python3
import hashlib
import json
import plistlib
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")

baseline = read("Relaxin/Backend/RuntimeAbstraction/UpstreamBaselineRegistry.swift")
generation = read("Relaxin/Backend/EnvironmentRecovery/EnvironmentGeneration.swift")
resolver = read("Relaxin/Backend/RuntimeAbstraction/RuntimeProfileResolver.swift")
backend = read("Relaxin/Backend/RuntimeAbstraction/LegacyRelaxinRuntimeBackend.swift")
hardware = read("Relaxin/Backend/RuntimeAbstraction/HardwareSupportRegistry.swift")
inspector = read("DevKit/Helpers/UpstreamBaseline/inspect-upstream-release.py")
makefile = read("Makefile")

assert 'id: "relaxin.upstream.v0.5.0.20260826"' in baseline
assert 'static let currentRuntimeAbstractionSchema = 2' in generation
assert 'static let currentRuntimeResolutionGeneration = 2' in generation
assert 'static let currentBaseBinGeneration = "public-snapshot-f44e0acf-fix12"' in generation
assert 'baseBinGeneration: "3716385fe8"' in baseline
assert re.search(r'backendGeneration:\s*2', backend)
assert 'static let resolutionGeneration = 2' in resolver
assert '.userspaceRebootV2' not in backend
assert '.missingTargetPathRepair' not in backend

plist = plistlib.loads((ROOT / "Relaxin/Resources/KernelOffsets.plist").read_bytes())
assert plist["generatedAt"] == "2026-08-26T07:38:29+00:00"
assert len(plist["profiles"]) == 339
assert len(plist["index"]) == 971
metadata_profiles = [p for p in plist["profiles"] if "sptmSHA256" in p or "txmSHA256" in p]
assert len(metadata_profiles) == 74
for profile in metadata_profiles:
    assert re.fullmatch(r"[0-9a-f]{64}", profile["sptmSHA256"])
    assert re.fullmatch(r"[0-9a-f]{64}", profile["txmSHA256"])

# Production registry is intentionally closed to the verified A12-A17 set.
assert hardware.count('status: .supported') == 6
assert 'future' not in hardware.lower()
assert 'A18' not in hardware and 'A19' not in hardware

expected_ui = json.loads((HERE / "fix13_10_ui_hashes.json").read_text())
for rel, expected in expected_ui.items():
    actual = hashlib.sha256((ROOT / rel).read_bytes()).hexdigest()
    assert actual == expected, f"Fix13.10 UI changed: {rel}"

for forbidden in [
    ROOT / "Relaxin/Resources/RelaxinEngine.framework",
    ROOT / "Vendor/RelaxinEngine.framework",
]:
    assert not forbidden.exists(), f"vendored engine framework is forbidden: {forbidden}"

assert (ROOT / "DevKit/Helpers/UpstreamBaseline/inspect-upstream-release.py").is_file()
for forbidden_token in ["urllib", "requests", "socket", "http://", "https://"]:
    assert forbidden_token not in inspector, f"upstream inspector must remain network-free: {forbidden_token}"
assert "zipfile" in inspector and "plistlib" in inspector and "hashlib" in inspector
assert "autoPromote" in inspector and "False" in inspector

fix14_pos = makefile.find('DevKit/Tests/Fix14Acceptance')
root_hide_pos = makefile.find('DevKit/Tests/RootHideSignaturePolicy')
assert fix14_pos >= 0, "Fix14Acceptance is not wired into test-host"
assert root_hide_pos >= 0 and fix14_pos < root_hide_pos, "Fix14Acceptance must run before macOS-only RootHide gate"

print("PASS Fix14 acceptance contract")
