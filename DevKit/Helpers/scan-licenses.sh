#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor"
KERNEL_ACCESS_DIR="$ROOT_DIR/RelaxinEngine/KernelAccess"
OUTPUT="$ROOT_DIR/Relaxin/Resources/Licenses.txt"

DARKSWORD_LICENSE="$KERNEL_ACCESS_DIR/Exploit/DarkSword/LICENSE.md"
ROCKET_LICENSE="$KERNEL_ACCESS_DIR/Exploit/Rocket/LICENSE.md"
ROCKET_LICENSE_TITLE='OwnGoal Studio(GitHub@Lakr233, GitHub@lbr77)'
ROOT_HIDE_HEADERS_LICENSE="$VENDOR_DIR/Dopamine/BaseBin/_external/include/LICENSE.md"
ROOT_HIDE_LIB_LICENSE="$VENDOR_DIR/Dopamine/BaseBin/_external/lib/LICENSE.md"
ROOT_HIDE_EXTERNAL_NOTICE="$VENDOR_DIR/Dopamine/BaseBin/_external/NOTICE.md"

[ -d "$VENDOR_DIR" ] || {
    echo "error: Vendor directory not found at $VENDOR_DIR" >&2
    exit 1
}

WORK_DIR="$(mktemp -d -t relaxin-license-scan)"
trap 'rm -rf "$WORK_DIR"' EXIT

LICENSE_LIST="$WORK_DIR/licenses"
ALL_LICENSES="$WORK_DIR/all-licenses"
LICENSE_MANIFEST="$WORK_DIR/license-manifest"
EMITTED_HASHES="$WORK_DIR/emitted-hashes"
GENERATED_OUTPUT="$WORK_DIR/Licenses.txt"

if [ -e "$ROOT_DIR/.git" ] && \
    git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "license discovery: git-index"
    git -C "$ROOT_DIR" ls-files -- Vendor |
        while IFS= read -r relative_path; do
            filename="${relative_path##*/}"
            lowercase_filename="$(
                printf '%s' "$filename" | tr '[:upper:]' '[:lower:]'
            )"
            case "$lowercase_filename" in
                license* | *.license | copying* | notice*)
                    printf '%s/%s\n' "$ROOT_DIR" "$relative_path"
                    ;;
            esac
        done |
        LC_ALL=C sort >"$ALL_LICENSES"
else
    echo "license discovery: source-archive"
    find "$VENDOR_DIR" \
        -type f \
        \( \
            -iname "LICENSE*" -o \
            -iname "*.LICENSE" -o \
            -iname "COPYING*" -o \
            -iname "NOTICE*" \
        \) \
        -print |
        LC_ALL=C sort >"$ALL_LICENSES"
fi

while IFS= read -r license_file; do
    case "$license_file" in
        "$ROOT_HIDE_HEADERS_LICENSE" | "$ROOT_HIDE_LIB_LICENSE")
            # These upstream manifests describe their entire repositories.
            # Snapshot-specific notices beside them cover only vendored inputs.
            continue
            ;;
    esac

    printf '%s\n' "$license_file"
done <"$ALL_LICENSES" >"$LICENSE_LIST"

[ -s "$LICENSE_LIST" ] || {
    echo "error: no license files found in Vendor" >&2
    exit 1
}

for required_license in \
    "$DARKSWORD_LICENSE" \
    "$ROCKET_LICENSE" \
    "$ROOT_HIDE_HEADERS_LICENSE" \
    "$ROOT_HIDE_LIB_LICENSE" \
    "$ROOT_HIDE_EXTERNAL_NOTICE"; do
    if [ ! -f "$required_license" ]; then
        echo "error: missing license file in ${required_license#"$ROOT_DIR/"}" >&2
        exit 1
    fi
done

while IFS= read -r component; do
    component_license="$(find "$component" \
        -mindepth 1 \
        -maxdepth 1 \
        -type f \
        \( \
            -iname "LICENSE*" -o \
            -iname "*.LICENSE" -o \
            -iname "COPYING*" -o \
            -iname "NOTICE*" \
        \) \
        -print \
        -quit)"
    if [ -z "$component_license" ]; then
        echo "error: missing license file in ${component#"$ROOT_DIR/"}" >&2
        exit 1
    fi
done < <(find "$VENDOR_DIR" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)

emit_license_section() {
    local title="$1"
    local license_file="$2"
    printf '\n## %s\n\n' "$title"
    cat "$license_file"
}

append_license_manifest_entry() {
    local title="$1"
    local license_file="$2"
    local content_hash

    content_hash="$(shasum -a 256 "$license_file" | awk '{ print $1 }')"
    printf '%s\t%s\t%s\n' "$content_hash" "$title" "$license_file" >>"$LICENSE_MANIFEST"
}

: >"$LICENSE_MANIFEST"

while IFS= read -r license_file; do
    component_name="$(dirname "${license_file#"$VENDOR_DIR/"}")"
    component_name="${component_name//\// / }"
    component_name="${component_name//_external/External}"
    component_name="${component_name%.xcframework}"

    append_license_manifest_entry "$component_name" "$license_file"
done <"$LICENSE_LIST"

append_license_manifest_entry "DarkSword" "$DARKSWORD_LICENSE"
append_license_manifest_entry "$ROCKET_LICENSE_TITLE" "$ROCKET_LICENSE"

: >"$EMITTED_HASHES"

{
    printf '# Open Source License\n'

    while IFS=$'\t' read -r content_hash component_name license_file; do
        if grep -Fqx "$content_hash" "$EMITTED_HASHES"; then
            continue
        fi

        component_names="$(
            awk -F '\t' -v content_hash="$content_hash" '
                $1 == content_hash {
                    component_names[count++] = $2
                }
                END {
                    for (i = 0; i < count; i++) {
                        component_name = component_names[i]
                        if (count > 1) {
                            sub(/^.* \/ /, "", component_name)
                        }
                        if (title != "") {
                            title = title " + "
                        }
                        title = title component_name
                    }
                    if (title != "") {
                        print title
                    }
                }
            ' "$LICENSE_MANIFEST"
        )"

        emit_license_section "$component_names" "$license_file"
        printf '%s\n' "$content_hash" >>"$EMITTED_HASHES"
    done <"$LICENSE_MANIFEST"
} >"$GENERATED_OUTPUT"

INCOMPATIBLE_LICENSE_PATTERNS=(
    "GNU (Affero |Lesser )?General Public License"
    "GNU (AGPL|LGPL|GPL)"
)

for pattern in "${INCOMPATIBLE_LICENSE_PATTERNS[@]}"; do
    if grep -Eiq "$pattern" "$GENERATED_OUTPUT"; then
        echo "error: found incompatible license matching: $pattern" >&2
        exit 1
    fi
done

if [ -f "$OUTPUT" ] && cmp -s "$GENERATED_OUTPUT" "$OUTPUT"; then
    echo "Open source licenses are up to date"
    exit 0
fi

mv "$GENERATED_OUTPUT" "$OUTPUT"
echo "Generated ${OUTPUT#"$ROOT_DIR/"}"
