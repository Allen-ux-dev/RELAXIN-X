#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
SCAN_ROOTS = [ROOT / "RelaxinEngine", ROOT / "RelaxinPostJailbreak"]
USE_RE = re.compile(r"\bJBROOT_PATH\s*\(")
INCLUDE_RE = re.compile(r"^\s*#\s*include\s*<libjailbreak/jbroot\.h>\s*$", re.MULTILINE)

missing = []
checked = []
for scan_root in SCAN_ROOTS:
    for path in sorted(scan_root.rglob("*")):
        if not path.is_file() or path.suffix not in {".m", ".mm"}:
            continue
        text = path.read_text(encoding="utf-8")
        if not USE_RE.search(text):
            continue
        checked.append(path.relative_to(ROOT))
        if not INCLUDE_RE.search(text):
            missing.append(path.relative_to(ROOT))

assert checked, "contract did not find any Objective-C JBROOT_PATH consumers"
assert not missing, (
    "files using JBROOT_PATH must explicitly include <libjailbreak/jbroot.h>:\n  - "
    + "\n  - ".join(map(str, missing))
)

print(f"JBROOT explicit-include contract: PASS ({len(checked)} consumers)")
