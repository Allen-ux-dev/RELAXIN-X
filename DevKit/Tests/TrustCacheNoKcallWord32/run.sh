#!/bin/sh
set -eu

SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIRECTORY="$(CDPATH= cd -- "$SCRIPT_DIRECTORY/../../.." && pwd)"
SOURCE_DIRECTORY="$ROOT_DIRECTORY/Vendor/Dopamine/BaseBin/libjailbreak/src"
SOURCE_FILE="$SOURCE_DIRECTORY/trustcache_nokcall_word32.c"
CONTRACT_TEST_SOURCE="$SCRIPT_DIRECTORY/trustcache_nokcall_word32_contract_tests.c"

TEMPORARY_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/relaxin-word32.XXXXXX")"
trap 'rm -rf -- "$TEMPORARY_DIRECTORY"' EXIT HUP INT TERM

OBJECT_FILE="$TEMPORARY_DIRECTORY/trustcache_nokcall_word32.o"
ARM64E_OBJECT_FILE="$TEMPORARY_DIRECTORY/trustcache_nokcall_word32.arm64e.o"
DISASSEMBLY_FILE="$TEMPORARY_DIRECTORY/trustcache_nokcall_word32.disassembly"
LEAF_FILE="$TEMPORARY_DIRECTORY/trustcache_nokcall_word32.leaf"
CONTRACT_TEST_BINARY="$TEMPORARY_DIRECTORY/trustcache_nokcall_word32_contract_tests"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
MACOS_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

compile_object() {
	architecture="$1"
	output="$2"
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
}

compile_object arm64 "$OBJECT_FILE"
compile_object arm64e "$ARM64E_OBJECT_FILE"

xcrun llvm-nm "$OBJECT_FILE" |
	grep -Eq '[[:space:]]_tcn_word32_replace$'
xcrun llvm-nm "$OBJECT_FILE" |
	grep -Eq '[[:space:]]_tcn_word32_store_leaf$'
xcrun llvm-nm "$ARM64E_OBJECT_FILE" |
	grep -Eq '[[:space:]]_tcn_word32_replace$'
xcrun llvm-nm "$ARM64E_OBJECT_FILE" |
	grep -Eq '[[:space:]]_tcn_word32_store_leaf$'

xcrun otool -tvV "$OBJECT_FILE" >"$DISASSEMBLY_FILE"
awk '
	/^_tcn_word32_store_leaf:$/ {
		in_leaf = 1
		next
	}
	in_leaf && /^[^[:space:]][^:]*:$/ {
		exit
	}
	in_leaf {
		print
	}
' "$DISASSEMBLY_FILE" >"$LEAF_FILE"

if [ ! -s "$LEAF_FILE" ]; then
	echo "error: store leaf was not present in arm64 disassembly" >&2
	exit 1
fi

store_count="$(
	awk '
		$2 ~ /^(str|stur|stp|strb|strh|stlr|stlxr|stxr)$/ {
			count++
		}
		END {
			print count + 0
		}
	' "$LEAF_FILE"
)"
word_store_count="$(
	awk '
		$2 ~ /^(str|stur|stlr)$/ && $3 ~ /^w[0-9]+,$/ {
			count++
		}
		END {
			print count + 0
		}
	' "$LEAF_FILE"
)"

if [ "$store_count" -ne 1 ] || [ "$word_store_count" -ne 1 ]; then
	echo "error: store leaf must contain exactly one 32-bit store" >&2
	cat "$LEAF_FILE" >&2
	exit 1
fi

if grep -q '_memcpy' "$DISASSEMBLY_FILE"; then
	echo "error: word32 PTE helper must not call memcpy" >&2
	grep '_memcpy' "$DISASSEMBLY_FILE" >&2
	exit 1
fi

if ! awk '$2 ~ /^ret/ { found = 1 } END { exit found ? 0 : 1 }' \
	"$LEAF_FILE"; then
	echo "error: store leaf has no return instruction" >&2
	cat "$LEAF_FILE" >&2
	exit 1
fi

xcrun --sdk macosx clang \
	-isysroot "$MACOS_SDK_PATH" \
	-std=gnu11 \
	-fblocks \
	-O2 \
	-Wall \
	-Wextra \
	-Werror \
	-I"$SOURCE_DIRECTORY" \
	"$SOURCE_FILE" \
	"$CONTRACT_TEST_SOURCE" \
	-o "$CONTRACT_TEST_BINARY"
"$CONTRACT_TEST_BINARY"

echo "trustcache_nokcall_word32: contracts, arm64 store leaf, and arm64e build verified"
