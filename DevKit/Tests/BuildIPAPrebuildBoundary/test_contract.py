#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
BUILD = (ROOT / 'BuildIPA.command').read_text()
MAKE = (ROOT / 'Makefile').read_text()
VERIFIER = ROOT / 'DevKit/Helpers/verify-prebuilt-resources.sh'

failures=[]
def require(cond,msg):
    if not cond: failures.append(msg)

markers = [
    'step "Preparing Bootstrap"',
    'step "Preparing BaseBin"',
    'step "Verifying prebuilt resources"',
    'step "Building unsigned IPA"',
]
for token in markers:
    require(token in BUILD, f'missing prebuild stage marker: {token}')
if all(t in BUILD for t in markers):
    indexes=[BUILD.index(t) for t in markers]
    require(indexes == sorted(indexes), f'prebuild stages are out of order: {indexes}')

require('HOST_TOOLS_ROOT="$RELAXIN_BUILD_HOME/HostTools"' in BUILD,
        'HostTools must live under RELAXIN_BUILD_HOME')
require('DERIVED_DATA="$RELAXIN_DERIVED_DATA"' in BUILD,
        'make ipa must receive persistent DERIVED_DATA')
require('make -C "$BUILD_ROOT_DIR" clean' not in BUILD,
        'normal BuildIPA flow must not call make clean')
require('if [[ "$CLEAN_BUILD" -eq 1 ]]' in BUILD,
        'explicit clean mode branch is missing')
require('rm -rf "$RELAXIN_DERIVED_DATA"' in BUILD,
        'clean mode must remove current cache-key DerivedData')
require('Unknown argument:' in BUILD,
        'BuildIPA must reject unknown command-line arguments')
require(VERIFIER.exists(), 'missing verify-prebuilt-resources.sh')
require('DERIVED_DATA    ?=' in MAKE, 'Makefile must keep DERIVED_DATA overridable')

if failures:
    print('BuildIPA prebuild-boundary contract: FAIL', file=sys.stderr)
    for f in failures: print(f'- {f}', file=sys.stderr)
    sys.exit(1)
print('BuildIPA prebuild-boundary contract: PASS')
