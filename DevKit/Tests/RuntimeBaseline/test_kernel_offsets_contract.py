#!/usr/bin/env python3
import plistlib
import re
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
path = ROOT / "Relaxin" / "Resources" / "KernelOffsets.plist"
with path.open("rb") as fh:
    table = plistlib.load(fh)

assert table["schema"] == 1
assert table["profileVersion"] == 1
assert table["generatedAt"] == "2026-08-26T07:38:29+00:00"
assert len(table["profiles"]) == 339
assert len(table["index"]) == 971

with_digest = [
    p for p in table["profiles"]
    if isinstance(p, dict) and ("sptmSHA256" in p or "txmSHA256" in p)
]
assert len(with_digest) == 74, len(with_digest)
for profile in with_digest:
    assert re.fullmatch(r"[0-9a-f]{64}", profile.get("sptmSHA256", ""))
    assert re.fullmatch(r"[0-9a-f]{64}", profile.get("txmSHA256", ""))

canonical = plistlib.dumps(table, fmt=plistlib.FMT_XML, sort_keys=True)
canonical_sha256 = hashlib.sha256(canonical).hexdigest()
assert canonical_sha256 == "bf3b29a5abd41dbc40b5b86bd8914cdf5c781783c54f494b5b066a2635f44bb0"

profiles = table["profiles"]
for key, value in table["index"].items():
    assert isinstance(key, str) and "|" in key
    assert isinstance(value, int) and 0 <= value < len(profiles)

print("PASS RuntimeBaseline KernelOffsets v0.5.0 contract")
