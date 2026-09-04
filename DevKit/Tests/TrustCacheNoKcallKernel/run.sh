#!/bin/sh
set -eu

SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIRECTORY="$(CDPATH= cd -- "$SCRIPT_DIRECTORY/../../.." && pwd)"
SOURCE_DIRECTORY="$ROOT_DIRECTORY/Vendor/Dopamine/BaseBin/libjailbreak/src"
SOURCE_FILE="$SOURCE_DIRECTORY/trustcache_nokcall_kernel.c"

TEMPORARY_DIRECTORY="$(
	mktemp -d "${TMPDIR:-/tmp}/relaxin-tcnk-kernel.XXXXXX"
)"
trap 'rm -rf -- "$TEMPORARY_DIRECTORY"' EXIT HUP INT TERM

SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"

compile_object() {
	architecture="$1"
	output="$TEMPORARY_DIRECTORY/kernel.$architecture.o"
	xcrun --sdk iphoneos clang \
		-arch "$architecture" \
		-isysroot "$SDK_PATH" \
		-miphoneos-version-min=15.0 \
		-std=gnu11 \
		-fblocks \
		-O2 \
		-Wall \
		-Wextra \
		-Werror \
		-I"$SOURCE_DIRECTORY" \
		-c "$SOURCE_FILE" \
		-o "$output"
	xcrun llvm-nm "$output" |
		grep -Eq '[[:space:]]_tcnk_kernel_create$'
	xcrun llvm-nm "$output" |
		grep -Eq '[[:space:]]_tcnk_kernel_prepare$'
	xcrun llvm-nm "$output" |
		grep -Eq '[[:space:]]_tcnk_kernel_destroy$'
	xcrun llvm-nm "$output" |
		grep -Eq '[[:space:]]_tcnk_kernel_destroy_context$'
	xcrun llvm-nm -u "$output" |
		grep -Eq '(^|[[:space:]])_tcn_word32_environment_status$'
	if xcrun llvm-nm -u "$output" |
		grep -Eq '(_kwritebuf_protected|_physwritebuf)$'; then
		echo "error: kernel adapter retained a bulk protected-write dependency" >&2
		exit 1
	fi
}

compile_object arm64
compile_object arm64e

echo "trustcache_nokcall_kernel: arm64 and arm64e syntax verified"
