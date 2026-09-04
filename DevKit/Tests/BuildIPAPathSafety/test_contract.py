#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
BUILD = (ROOT / "BuildIPA.command").read_text(encoding="utf-8")
HELPER = (ROOT / "DevKit/Helpers/build-home.sh").read_text(encoding="utf-8")

failures = []

def require(condition: bool, message: str) -> None:
    if not condition:
        failures.append(message)

for token in [
    'SOURCE_ROOT_DIR=',
    'BUILD_ROOT_DIR=',
    'RELAXIN_BUILD_HOME=',
    'RELAXIN_WORKSPACE_SOURCE=',
    'prepare_stable_build_workspace',
    'relaxin_sync_workspace "$SOURCE_ROOT_DIR" "$RELAXIN_WORKSPACE_SOURCE"',
    'BUILD_ROOT_DIR="$RELAXIN_WORKSPACE_SOURCE"',
    'Build workspace: %s',
]:
    require(token in BUILD, f"missing stable whitespace-safe build contract token: {token}")

require("rsync -a --delete" in HELPER, "stable workspace synchronization must use rsync --delete")
require("--exclude '/build/'" in HELPER, "workspace sync must preserve generated build state")
require('relaxin-zebra-source.XXXXXX' not in BUILD,
        "random temporary source workspaces must not be used")
require('OUTPUT_DIR="$SOURCE_ROOT_DIR/Output"' in BUILD,
        "Output must remain under the original source directory")
require('rm -rf "$BUILD_WORKSPACE_DIR"' not in BUILD,
        "stable build workspace must survive successful and failed builds")

for invocation in [
    'make -C "$BUILD_ROOT_DIR" --no-print-directory print-version',
    'make -C "$BUILD_ROOT_DIR" ipa IPA_OUTPUT="$STAGING_IPA"',
]:
    require(invocation in BUILD, f"make invocation is not workspace-safe: {invocation}")

require('export PATH="$BUILD_ROOT_DIR/build/HostTools/bin:$PATH"' in BUILD,
        "workspace-local HostTools must be first in PATH before Make/Xcode")

if failures:
    print("BuildIPA path-safety contract: FAIL", file=sys.stderr)
    for failure in failures:
        print(f"- {failure}", file=sys.stderr)
    sys.exit(1)

print("BuildIPA path-safety contract: PASS")
