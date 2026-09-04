#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
forbidden = [
    ROOT / "Relaxin" / "Resources" / "RelaxinEngine.framework",
    ROOT / "Vendor" / "RelaxinEngine.framework",
]
violations = [str(path.relative_to(ROOT)) for path in forbidden if path.exists()]
assert not violations, f"black-box engine framework must not be vendored: {violations}"

print("PASS RuntimeBaseline resource contract")
