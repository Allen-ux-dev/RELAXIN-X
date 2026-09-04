#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[3]
BUILD = (ROOT / "BuildIPA.command").read_text(encoding="utf-8")
GITIGNORE = (ROOT / ".gitignore").read_text(encoding="utf-8")
ENV_SH = (ROOT / ".env.sh").read_text(encoding="utf-8")
CHECK_TOOLS = (ROOT / "DevKit/Helpers/check-tools.sh").read_text(encoding="utf-8")

failures = []

def require(condition: bool, message: str) -> None:
    if not condition:
        failures.append(message)

# BuildIPA must preflight the exact host tools required by Make/Xcode/BaseBin,
# not just the first missing tool observed at runtime.
for token in [
    'REQUIRED_BUILD_TOOLS=(rg zstd gtar dpkg-deb ldid trustcache)',
    'TRUSTCACHE_REPOSITORY="https://github.com/CRKatri/trustcache.git"',
    'TRUSTCACHE_COMMIT="aa0e8847529cf76576fce8d2dbc9e088c8f1a0df"',
    'HOST_TOOLS_ROOT="$RELAXIN_BUILD_HOME/HostTools"',
    'export PATH="$HOST_TOOLS_BIN:$PATH"',
    'prepare_trustcache',
    'verify_relaxin_toolchain',
    '--no-ask',
]:
    require(token in BUILD, f"BuildIPA.command missing required contract token: {token}")

# Homebrew mapping must be explicit, so a missing executable cannot silently
# install the wrong formula.
for command, formula in {
    "rg": "ripgrep",
    "zstd": "zstd",
    "gtar": "gnu-tar",
    "dpkg-deb": "dpkg",
    "ldid": "ldid",
}.items():
    pattern = rf'{re.escape(command)}\)\s+printf [^\n]*{re.escape(formula)}'
    require(re.search(pattern, BUILD) is not None,
            f"missing Homebrew mapping {command} -> {formula}")

require('build/HostTools/bin' in ENV_SH and '_relaxin_prepend_path' in ENV_SH,
        ".env.sh must re-add project-local HostTools inside Xcode shell phases")
require('check-tools.sh' in BUILD and
        'xcode rg zstd gtar trustcache dpkg-deb ldid git rsync shasum' in BUILD,
        "BuildIPA must rerun Relaxin's full build-tool checker after preparation")

# A standalone Xcode clang invocation does not reliably infer the macOS SDK.
# The project-local trustcache build must resolve the SDK explicitly and pass
# its sysroot through both compile/preprocessor and linker flags.
require('xcrun --sdk macosx --show-sdk-path' in BUILD,
        "trustcache build must resolve the macOS SDK explicitly")
require('-isysroot $macos_sdk' in BUILD,
        "trustcache build must pass the macOS SDK sysroot to clang")
require('CPPFLAGS="-isysroot $macos_sdk -I$libmd_prefix/include"' in BUILD,
        "trustcache compile flags must include the macOS SDK sysroot")
require('LDFLAGS="-isysroot $macos_sdk -L$libmd_prefix/lib"' in BUILD,
        "trustcache linker flags must include the macOS SDK sysroot")

for diagnostic in [
    "macOS SDK: %s",
    "Host clang: %s",
    "libmd: %s",
]:
    require(diagnostic in BUILD,
            f"trustcache host build is missing diagnostic: {diagnostic}")


require('dpkg-deb)' in CHECK_TOOLS and 'brew install dpkg' in CHECK_TOOLS,
        "check-tools.sh must give the correct dpkg-deb Homebrew hint")
require('trustcache)' in CHECK_TOOLS and 'BuildIPA.command' in CHECK_TOOLS,
        "check-tools.sh must direct trustcache users to the project-local BuildIPA preparation")

# The existing atomic publish behavior must remain: the final Output IPA is
# only replaced after a staged IPA has passed archive validation.
require('STAGING_IPA="$STAGING_DIR/RELAXIN-X.ipa"' in BUILD,
        "staging IPA contract was removed")
require('mv -f "$STAGING_IPA" "$OUTPUT_IPA"' in BUILD,
        "atomic publish move was removed")
require(BUILD.find('step "Validating IPA archive"') < BUILD.find('mv -f "$STAGING_IPA" "$OUTPUT_IPA"'),
        "Output IPA is published before validation")

# The source archive should not contain a malformed ignore glob that causes rg
# to print parser errors during repository-wide diagnostics.
require("Icon[\n]" not in GITIGNORE, ".gitignore contains malformed Icon[ / ] glob")
require("Icon?" in GITIGNORE, ".gitignore should use the portable Icon? pattern")

if failures:
    for failure in failures:
        print(f"FAIL: {failure}", file=sys.stderr)
    sys.exit(1)

print("BuildIPA host-tools contract: PASS")
