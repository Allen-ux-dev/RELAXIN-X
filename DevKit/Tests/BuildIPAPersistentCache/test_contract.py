#!/usr/bin/env python3
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[3]
BUILD=(ROOT/'BuildIPA.command').read_text()
BASEBIN=(ROOT/'DevKit/Helpers/build-basebin-resources.sh').read_text()
MAKE=(ROOT/'Makefile').read_text()
fail=[]
def req(c,m):
    if not c: fail.append(m)
for token in [
    'PERSISTENT_CACHE_ROOT="$RELAXIN_BUILD_HOME"',
    'PERSISTENT_BASEBIN_CACHE="$RELAXIN_BUILD_HOME/BaseBin/CompilerCache"',
    'PERSISTENT_BASEBIN_RESOURCES="$RELAXIN_BUILD_HOME/BaseBin/Resources"',
    'prepare_persistent_build_cache',
    'ln -s "$PERSISTENT_BASEBIN_CACHE" "$BUILD_ROOT_DIR/build/BaseBinCaches"',
    'ln -s "$PERSISTENT_BASEBIN_RESOURCES" "$BUILD_ROOT_DIR/build/BaseBinResources"',
    'RELAXIN_BASEBIN_LOCK_DIRECTORY="$RELAXIN_BUILD_HOME/Locks/BaseBinResources.lock"',
]: req(token in BUILD, f'missing Fix11 persistent cache token: {token}')
cache=BUILD.find('\nprepare_persistent_build_cache\n')
boot=BUILD.find('step "Preparing Bootstrap"')
base=BUILD.find('step "Preparing BaseBin"')
xcode=BUILD.find('step "Building unsigned IPA"')
req(0 <= cache < boot < base < xcode, 'cache/prebuild/xcode ordering is wrong')
req('make -C "$BUILD_ROOT_DIR" clean' not in BUILD, 'normal flow must not call make clean')
req('LOCK_DIRECTORY="${RELAXIN_BASEBIN_LOCK_DIRECTORY:-$ROOT_DIR/build/.BaseBinResources.lock}"' in BASEBIN,
    'BaseBin helper must allow persistent lock override')
req('BuildIPAPersistentCache/test_contract.py' in MAKE, 'persistent cache regression missing from test-host')
if fail:
    print('BuildIPA persistent-cache contract: FAIL', file=sys.stderr)
    for x in fail: print('- '+x, file=sys.stderr)
    raise SystemExit(1)
print('BuildIPA persistent-cache contract: PASS')
