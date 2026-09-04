#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT_DIR/.env.sh"

if [ "$#" -eq 0 ]; then
    echo "usage: $0 <tool>..." >&2
    exit 64
fi

FAILURES=()
MISSING_TOOLS=()
XCODE_FAILED=0

check_command() {
    local tool="$1"

    if ! command -v "$tool" >/dev/null 2>&1; then
        FAILURES+=("$tool: command not found in PATH")
        MISSING_TOOLS+=("$tool")
    fi
}

check_xcode() {
    local has_xcrun=1

    if ! command -v xcodebuild >/dev/null 2>&1; then
        FAILURES+=("Xcode: xcodebuild was not found in PATH")
        XCODE_FAILED=1
    elif ! xcodebuild -version >/dev/null 2>&1; then
        FAILURES+=("Xcode: \`xcodebuild -version\` failed")
        XCODE_FAILED=1
    fi

    if ! command -v xcrun >/dev/null 2>&1; then
        FAILURES+=("Xcode: xcrun was not found in PATH")
        XCODE_FAILED=1
        has_xcrun=0
    fi

    if [ "$has_xcrun" -eq 1 ]; then
        if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
            FAILURES+=("Xcode: the iPhoneOS SDK is unavailable")
            XCODE_FAILED=1
        fi

        if ! xcrun --find clang >/dev/null 2>&1; then
            FAILURES+=("Xcode: clang is unavailable through xcrun")
            XCODE_FAILED=1
        fi
    fi
}

print_install_hint() {
    case "$1" in
        ldid)
            echo "note: ldid: brew install ldid" >&2
            ;;
        dpkg-deb)
            echo "note: dpkg-deb: brew install dpkg" >&2
            ;;
        trustcache)
            echo "note: trustcache: run ./BuildIPA.command; it prepares a pinned project-local build" >&2
            ;;
        zstd)
            echo "note: zstd: brew install zstd" >&2
            ;;
        gtar)
            echo "note: gtar: brew install gnu-tar" >&2
            ;;
        swiftformat)
            echo "note: swiftformat: brew install swiftformat" >&2
            ;;
        clang-format)
            echo "note: clang-format: brew install clang-format" >&2
            ;;
        rg)
            echo "note: rg: brew install ripgrep" >&2
            ;;
        *)
            echo "note: $1: install it and ensure it is available in PATH" >&2
            ;;
    esac
}

for tool in "$@"; do
    if [ "$tool" = "xcode" ]; then
        check_xcode
    else
        check_command "$tool"
    fi
done

if [ "${#FAILURES[@]}" -eq 0 ]; then
    exit 0
fi

echo "required build tools are unavailable:" >&2
for failure in "${FAILURES[@]}"; do
    echo "error: $failure" >&2
done

echo "install or configure the missing tools, then retry:" >&2
for tool in "${MISSING_TOOLS[@]-}"; do
    [ -n "$tool" ] || continue
    print_install_hint "$tool"
done
if [ "$XCODE_FAILED" -eq 1 ]; then
    echo "note: Xcode: install and open Xcode, then select its Developer directory with DEVELOPER_DIR or xcode-select" >&2
fi

exit 69
