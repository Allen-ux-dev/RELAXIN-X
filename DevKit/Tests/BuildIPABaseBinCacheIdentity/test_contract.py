#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[3]
build = (root / 'BuildIPA.command').read_text()
helper = (root / 'DevKit/Helpers/build-basebin-resources.sh').read_text()
makefile = (root / 'Makefile').read_text()
errors=[]
def require(c,m):
    if not c: errors.append(m)

require('RELAXIN_CACHE_KEY="$(relaxin_cache_key "$SOURCE_ROOT_DIR" "$XCODE_BUILD_VERSION" "$IPHONEOS_SDK_VERSION")"' in build,
        'BuildIPA must derive a stable project/toolchain cache key')
require('RELAXIN_BASEBIN_CACHE_DIRECTORY="$PERSISTENT_BASEBIN_CACHE"' in build,
        'BaseBin compiler cache must use the stable build-home physical directory')
require('PERSISTENT_BASEBIN_CACHE="$RELAXIN_BUILD_HOME/BaseBin/CompilerCache"' in build,
        'BaseBin compiler cache must live in the build home')
require('export RELAXIN_BASEBIN_CACHE_DIRECTORY' in build,
        'BaseBin cache override must reach Xcode/prebuild helpers')
require('CACHE_DIRECTORY="${RELAXIN_BASEBIN_CACHE_DIRECTORY:-$ROOT_DIR/build/BaseBinCaches}"' in helper,
        'BaseBin helper must consume RELAXIN_BASEBIN_CACHE_DIRECTORY')
require('CACHE_DIRECTORY="$(cd "$CACHE_DIRECTORY" && pwd -P)"' in helper,
        'BaseBin helper must canonicalize compiler cache to a physical path')
require('relaxin_prepare_build_environment "$CACHE_DIRECTORY"' in helper,
        'BaseBin helper must prepare selected compiler cache')
require('HEADER_TREE="$WORK_DIRECTORY/Vendor/Dopamine/BaseBin/.include"' in helper,
        'BaseBin cache hit must verify staged headers are available')
require('BuildIPABaseBinCacheIdentity/test_contract.py' in makefile,
        'BaseBin cache regression must be included in make test-host')
if errors:
    print('BuildIPABaseBinCacheIdentity contract: FAIL')
    for e in errors: print(f'- {e}')
    raise SystemExit(1)
print('BuildIPABaseBinCacheIdentity contract: PASS')
