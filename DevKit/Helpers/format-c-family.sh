#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="${1:-}"

case "$MODE" in
    write)
        FORMAT_ARGUMENTS=(-i)
        ;;
    lint)
        FORMAT_ARGUMENTS=(--dry-run --Werror)
        ;;
    *)
        echo "usage: $0 <write|lint>" >&2
        exit 64
        ;;
esac

cd "$ROOT_DIR"

SOURCE_FILES=()
while IFS= read -r -d '' source_file; do
    [ -f "$source_file" ] || continue

    case "$source_file" in
        build/*|.build/*|DerivedData/*)
            continue
            ;;
        Vendor/Dopamine/BaseBin/_external/*|\
        Vendor/Dopamine/BaseBin/*/external/*|\
        Vendor/Dopamine/BaseBin/*/Dependencies/*|\
        Vendor/Dopamine/BaseBin/*/generated/*)
            continue
            ;;
        Vendor/Dopamine/BaseBin/*)
            ;;
        Vendor/*)
            continue
            ;;
    esac

    SOURCE_FILES+=("$source_file")
done < <(git ls-files --cached --others --exclude-standard -z -- \
    '*.c' '*.cc' '*.cpp' '*.cxx' \
    '*.h' '*.hh' '*.hpp' '*.hxx' \
    '*.m' '*.mm')

if [ "${#SOURCE_FILES[@]}" -eq 0 ]; then
    exit 0
fi

clang-format "${FORMAT_ARGUMENTS[@]}" \
    --style=file \
    --fallback-style=none \
    "${SOURCE_FILES[@]}"
