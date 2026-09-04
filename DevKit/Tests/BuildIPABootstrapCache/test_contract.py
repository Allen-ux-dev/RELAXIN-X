#!/usr/bin/env python3
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[3]
BUILD=(ROOT/'BuildIPA.command').read_text()
MAKE=(ROOT/'Makefile').read_text()
PREP=(ROOT/'DevKit/Helpers/prepare-bootstrap.sh').read_text()
fail=[]
def req(c,m):
    if not c: fail.append(m)
for token in [
    'PERSISTENT_BOOTSTRAP_SOURCES="$RELAXIN_BUILD_HOME/Bootstrap/Sources"',
    'PERSISTENT_BOOTSTRAP_RESOURCES="$RELAXIN_BUILD_HOME/Bootstrap/Resources"',
    'PERSISTENT_BOOTSTRAP_TOOLS="$RELAXIN_BUILD_HOME/Bootstrap/Tools"',
    'ln -s "$PERSISTENT_BOOTSTRAP_SOURCES" "$BUILD_ROOT_DIR/build/BootstrapSources"',
    'ln -s "$PERSISTENT_BOOTSTRAP_RESOURCES" "$BUILD_ROOT_DIR/build/BootstrapResources"',
    'ln -s "$PERSISTENT_BOOTSTRAP_TOOLS" "$BUILD_ROOT_DIR/build/Tools"',
]: req(token in BUILD, f'missing Fix11 Bootstrap token: {token}')
req('step "Preparing Bootstrap"' in BUILD, 'Bootstrap must be explicit prebuild stage')
req('find "$persistent_path" -mindepth 1 -maxdepth 1 -print -quit' in BUILD, 'legacy Bootstrap migration must only populate an empty build-home cache')
req('note: [Bootstrap] resources are up to date' in MAKE, 'Makefile must report Bootstrap cache hit')
for marker in [
    'bootstrap_progress "extracting source archive"',
    'bootstrap_progress "scanning Mach-O files"',
    'bootstrap_progress "rebuilding archive"',
    'bootstrap_progress "compressing archive with zstd"',
    'bootstrap_progress "verifying archive metadata"',
]: req(marker in PREP, f'missing Bootstrap progress marker: {marker}')
if fail:
    print('BuildIPA bootstrap-cache/progress contract: FAIL', file=sys.stderr)
    for x in fail: print('- '+x, file=sys.stderr)
    raise SystemExit(1)
print('BuildIPA bootstrap-cache/progress contract: PASS')
