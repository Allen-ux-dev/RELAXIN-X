#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
EXPECTED = json.loads((HERE / "fix13_10_ui_hashes.json").read_text())

for relative, expected_hash in EXPECTED.items():
    path = ROOT / relative
    assert path.is_file(), relative
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    assert actual == expected_hash, f"Fix13.10 UI changed: {relative}"

pbx = (ROOT / "Relaxin.xcodeproj/project.pbxproj").read_text()
required_sources = [
    "BaselineIntegrityRequirement.swift",
    "UpstreamBaselineManifest.swift",
    "UpstreamBaselineRegistry.swift",
    "HardwareSupportDescriptor.swift",
    "HardwareSupportRegistry.swift",
    "KernelProfileIntegrityMetadata.swift",
    "BaselineIntegrityEvaluator.swift",
]
for source in required_sources:
    relative = f"Backend/RuntimeAbstraction/{source}"
    assert relative in pbx, f"missing RelaxinLite exclusion/project wiring: {source}"

print("ok fix14-integration-contract")
