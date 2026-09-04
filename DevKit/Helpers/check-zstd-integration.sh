#!/usr/bin/env bash
#
# Keep both sides of the deliberate zstd integration: vendored engine sources
# and the host tool used to prepare bootstrap resources.

set -u -o pipefail

ROOT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
    echo "error: zstd integration is incomplete: $1" >&2
    exit 1
}

[ -f "$ROOT_DIRECTORY/Vendor/zstd/LICENSE" ] \
    || fail "Vendor/zstd/LICENSE is missing"
[ -f "$ROOT_DIRECTORY/Vendor/zstd/lib/zstd.h" ] \
    || fail "the vendored public header is missing"

PROJECT="$ROOT_DIRECTORY/Relaxin.xcodeproj/project.pbxproj"
ENGINE_CONFIGURATION="$ROOT_DIRECTORY/Configuration/Targets/RelaxinEngine.xcconfig"
PREPARE_BOOTSTRAP="$ROOT_DIRECTORY/DevKit/Helpers/prepare-bootstrap.sh"
MAKEFILE="$ROOT_DIRECTORY/Makefile"
LICENSE_OUTPUT="$ROOT_DIRECTORY/Relaxin/Resources/Licenses.txt"

rg -q 'path = zstd;' "$PROJECT" \
    || fail "the Xcode synchronized zstd group is missing"
rg -q 'Vendor/zstd/lib' "$ENGINE_CONFIGURATION" \
    || fail "the engine header search path is missing"
rg -q 'check-tools\.sh" zstd gtar' "$PREPARE_BOOTSTRAP" \
    || fail "bootstrap preparation no longer checks the host archive tools"
rg -q 'zstd -q -d -c' "$PREPARE_BOOTSTRAP" \
    || fail "bootstrap preparation no longer decompresses with zstd"
rg -q 'gtar --same-permissions -xf' "$PREPARE_BOOTSTRAP" \
    || fail "bootstrap preparation no longer preserves source permissions"
rg -q 'normalize_archive_metadata' "$PREPARE_BOOTSTRAP" \
    || fail "bootstrap preparation no longer compares archive metadata"
rg -q 'require_archive_metadata' "$PREPARE_BOOTSTRAP" \
    || fail "bootstrap preparation no longer validates critical permissions"
rg -q '\| zstd .* -19' "$PREPARE_BOOTSTRAP" \
    || rg -q '^zstd -q -19 ' "$PREPARE_BOOTSTRAP" \
    || fail "bootstrap preparation no longer compresses with zstd"
rg -q 'TOOL_CHECKER.*zstd gtar' "$MAKEFILE" \
    || fail "the Makefile no longer validates the host archive tools"
rg -q '^## zstd$' "$LICENSE_OUTPUT" \
    || fail "the generated license bundle no longer contains zstd"
