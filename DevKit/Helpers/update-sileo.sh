#!/usr/bin/env bash

set -euo pipefail

ROOT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VENDOR_DIRECTORY="$ROOT_DIRECTORY/Vendor/Sileo"
VENDOR_DEB="$VENDOR_DIRECTORY/sileo.deb"
VENDOR_LICENSES="$VENDOR_DIRECTORY/BundledLicenses.plist"
ORIGIN_FILE="$VENDOR_DIRECTORY/ORIGIN.md"
LICENSE_SCANNER="$ROOT_DIRECTORY/DevKit/Helpers/scan-licenses.sh"
TOOL_CHECKER="$ROOT_DIRECTORY/DevKit/Helpers/check-tools.sh"

PACKAGE_IDENTIFIER="org.coolstar.sileo"
PACKAGE_ARCHITECTURE="iphoneos-arm64e"
REPOSITORY_URL="${SILEO_REPOSITORY_URL:-https://roothide.github.io}"
REFERENCE_DEB="${SILEO_REFERENCE_DEB:-}"
REQUESTED_VERSION=""

usage() {
    cat <<EOF
Usage: ${0##*/} [--reference PATH] [VERSION]

Download and validate Sileo from the RootHide APT repository, then update
Vendor/Sileo. Without VERSION, the latest iphoneos-arm64e Debian version in
the repository index is selected.

Options:
  --reference PATH  Require the current vendored deb to match PATH byte-for-byte
  -h, --help        Show this help

Environment:
  SILEO_REFERENCE_DEB    Same as --reference
  SILEO_REPOSITORY_URL   Override the repository URL for testing
EOF
}

fail() {
    echo "error: $*" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --reference)
            [ "$#" -ge 2 ] || fail "--reference requires a path"
            REFERENCE_DEB="$2"
            shift 2
            ;;
        --reference=*)
            REFERENCE_DEB="${1#*=}"
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        -*)
            fail "unknown option: $1"
            ;;
        *)
            [ -z "$REQUESTED_VERSION" ] || fail "only one VERSION may be supplied"
            REQUESTED_VERSION="$1"
            shift
            ;;
    esac
done

if [ -n "$REQUESTED_VERSION" ] \
    && [[ ! "$REQUESTED_VERSION" =~ ^[0-9A-Za-z.+:~_-]+$ ]]
then
    fail "invalid Debian version: $REQUESTED_VERSION"
fi

REPOSITORY_URL="${REPOSITORY_URL%/}"
case "$REPOSITORY_URL" in
    https://*) ;;
    *) fail "repository URL must use HTTPS: $REPOSITORY_URL" ;;
esac

for required_file in \
    "$VENDOR_DEB" \
    "$VENDOR_LICENSES" \
    "$ORIGIN_FILE" \
    "$LICENSE_SCANNER"; do
    [ -f "$required_file" ] || fail "missing ${required_file#"$ROOT_DIRECTORY/"}"
done

"$TOOL_CHECKER" curl dpkg dpkg-deb file lipo plutil shasum tar

if [ -n "$REFERENCE_DEB" ]; then
    [ -f "$REFERENCE_DEB" ] || fail "reference deb not found: $REFERENCE_DEB"
    if ! cmp -s "$VENDOR_DEB" "$REFERENCE_DEB"; then
        echo "current vendored deb differs from the requested reference:" >&2
        shasum -a 256 "$VENDOR_DEB" "$REFERENCE_DEB" >&2
        fail "refusing to overwrite a potentially customized Sileo package"
    fi
    echo "Verified current sileo.deb matches $REFERENCE_DEB"
fi

WORK_DIRECTORY="$(mktemp -d -t relaxin-sileo-update)"
trap 'rm -rf "$WORK_DIRECTORY"' EXIT

PACKAGES_INDEX="$WORK_DIRECTORY/Packages"
PACKAGE_CANDIDATES="$WORK_DIRECTORY/candidates.tsv"
DOWNLOADED_DEB="$WORK_DIRECTORY/sileo.deb"
EXTRACTED_ROOT="$WORK_DIRECTORY/root"
ORIGIN_TAIL="$WORK_DIRECTORY/origin-tail.md"
STAGED_ORIGIN="$WORK_DIRECTORY/ORIGIN.md"

INDEX_URL="$REPOSITORY_URL/Packages"
echo "Fetching $INDEX_URL"
curl \
    --fail \
    --location \
    --proto '=https' \
    --retry 3 \
    --show-error \
    --silent \
    --tlsv1.2 \
    --output "$PACKAGES_INDEX" \
    "$INDEX_URL"

awk -v package_identifier="$PACKAGE_IDENTIFIER" '
    BEGIN {
        RS = ""
        FS = "\n"
        OFS = "\t"
    }
    {
        package = ""
        version = ""
        architecture = ""
        filename = ""
        size = ""
        sha256 = ""

        for (line_number = 1; line_number <= NF; line_number++) {
            separator = index($line_number, ":")
            if (separator == 0) {
                continue
            }
            key = substr($line_number, 1, separator - 1)
            value = substr($line_number, separator + 1)
            sub(/^[[:space:]]+/, "", value)

            if (key == "Package") package = value
            else if (key == "Version") version = value
            else if (key == "Architecture") architecture = value
            else if (key == "Filename") filename = value
            else if (key == "Size") size = value
            else if (key == "SHA256") sha256 = value
        }

        if (package == package_identifier) {
            print version, architecture, filename, size, sha256
        }
    }
' "$PACKAGES_INDEX" >"$PACKAGE_CANDIDATES"

[ -s "$PACKAGE_CANDIDATES" ] \
    || fail "$PACKAGE_IDENTIFIER is absent from $INDEX_URL"

SELECTED_VERSION=""
SELECTED_FILENAME=""
SELECTED_SIZE=""
SELECTED_SHA256=""
SELECTED_COUNT=0

while IFS=$'\t' read -r candidate_version candidate_architecture \
    candidate_filename candidate_size candidate_sha256; do
    [ "$candidate_architecture" = "$PACKAGE_ARCHITECTURE" ] || continue

    if [ -n "$REQUESTED_VERSION" ]; then
        [ "$candidate_version" = "$REQUESTED_VERSION" ] || continue
        SELECTED_COUNT=$((SELECTED_COUNT + 1))
    elif [ -z "$SELECTED_VERSION" ] \
        || dpkg --compare-versions "$candidate_version" gt "$SELECTED_VERSION"
    then
        SELECTED_COUNT=1
    elif dpkg --compare-versions "$candidate_version" eq "$SELECTED_VERSION"; then
        SELECTED_COUNT=$((SELECTED_COUNT + 1))
    else
        continue
    fi

    SELECTED_VERSION="$candidate_version"
    SELECTED_FILENAME="$candidate_filename"
    SELECTED_SIZE="$candidate_size"
    SELECTED_SHA256="$candidate_sha256"
done <"$PACKAGE_CANDIDATES"

if [ -n "$REQUESTED_VERSION" ] && [ -z "$SELECTED_VERSION" ]; then
    fail "$PACKAGE_IDENTIFIER $REQUESTED_VERSION ($PACKAGE_ARCHITECTURE) is absent from $INDEX_URL"
fi
[ -n "$SELECTED_VERSION" ] || fail "no $PACKAGE_ARCHITECTURE package was found"
[ "$SELECTED_COUNT" -eq 1 ] \
    || fail "repository index contains $SELECTED_COUNT matching entries for $SELECTED_VERSION"
[[ "$SELECTED_VERSION" =~ ^[0-9A-Za-z.+:~_-]+$ ]] \
    || fail "repository returned an invalid Debian version: $SELECTED_VERSION"

case "$SELECTED_FILENAME" in
    ./*) RELATIVE_FILENAME="${SELECTED_FILENAME#./}" ;;
    *) RELATIVE_FILENAME="$SELECTED_FILENAME" ;;
esac

if [[ ! "$RELATIVE_FILENAME" =~ ^[0-9A-Za-z._/+~-]+$ ]]; then
    fail "package filename contains unsupported characters: $SELECTED_FILENAME"
fi
case "/$RELATIVE_FILENAME/" in
    */../* | */./*) fail "unsafe package filename: $SELECTED_FILENAME" ;;
esac
[[ "$SELECTED_SIZE" =~ ^[0-9]+$ ]] \
    || fail "invalid package size in index: $SELECTED_SIZE"
[[ "$SELECTED_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] \
    || fail "invalid package SHA-256 in index: $SELECTED_SHA256"
SELECTED_SHA256="$(printf '%s' "$SELECTED_SHA256" | tr '[:upper:]' '[:lower:]')"

PACKAGE_URL="$REPOSITORY_URL/$RELATIVE_FILENAME"
echo "Downloading $PACKAGE_IDENTIFIER $SELECTED_VERSION"
curl \
    --fail \
    --location \
    --proto '=https' \
    --retry 3 \
    --show-error \
    --silent \
    --tlsv1.2 \
    --output "$DOWNLOADED_DEB" \
    "$PACKAGE_URL"

ACTUAL_SIZE="$(wc -c <"$DOWNLOADED_DEB" | tr -d '[:space:]')"
ACTUAL_SHA256="$(shasum -a 256 "$DOWNLOADED_DEB" | awk '{ print $1 }')"
[ "$ACTUAL_SIZE" = "$SELECTED_SIZE" ] \
    || fail "package size mismatch: expected $SELECTED_SIZE, got $ACTUAL_SIZE"
[ "$ACTUAL_SHA256" = "$SELECTED_SHA256" ] \
    || fail "package SHA-256 mismatch: expected $SELECTED_SHA256, got $ACTUAL_SHA256"

ACTUAL_PACKAGE="$(dpkg-deb -f "$DOWNLOADED_DEB" Package)"
ACTUAL_VERSION="$(dpkg-deb -f "$DOWNLOADED_DEB" Version)"
ACTUAL_ARCHITECTURE="$(dpkg-deb -f "$DOWNLOADED_DEB" Architecture)"
[ "$ACTUAL_PACKAGE" = "$PACKAGE_IDENTIFIER" ] \
    || fail "unexpected package identifier: $ACTUAL_PACKAGE"
[ "$ACTUAL_VERSION" = "$SELECTED_VERSION" ] \
    || fail "unexpected package version: $ACTUAL_VERSION"
[ "$ACTUAL_ARCHITECTURE" = "$PACKAGE_ARCHITECTURE" ] \
    || fail "unexpected package architecture: $ACTUAL_ARCHITECTURE"

dpkg-deb --fsys-tarfile "$DOWNLOADED_DEB" | tar -tf - \
    >"$WORK_DIRECTORY/payload-paths"
: >"$WORK_DIRECTORY/unexpected-payload-paths"
while IFS= read -r payload_path; do
    case "$payload_path" in
        ./ | ./Applications/ | ./Applications/Sileo.app/ \
            | ./Applications/Sileo.app/*) ;;
        *) printf '%s\n' "$payload_path" \
            >>"$WORK_DIRECTORY/unexpected-payload-paths" ;;
    esac
done <"$WORK_DIRECTORY/payload-paths"
if [ -s "$WORK_DIRECTORY/unexpected-payload-paths" ]; then
    echo "unexpected Sileo payload paths:" >&2
    sed -n '1,40p' "$WORK_DIRECTORY/unexpected-payload-paths" >&2
    fail "package payload extends outside Applications/Sileo.app"
fi

dpkg-deb -x "$DOWNLOADED_DEB" "$EXTRACTED_ROOT"
SILEO_APP="$EXTRACTED_ROOT/Applications/Sileo.app"
SILEO_EXECUTABLE="$SILEO_APP/Sileo"
ROOT_HELPER="$SILEO_APP/giveMeRoot"
EMBEDDED_LICENSES="$SILEO_APP/Licenses.plist"

for extracted_file in \
    "$SILEO_EXECUTABLE" \
    "$ROOT_HELPER" \
    "$SILEO_APP/Info.plist" \
    "$EMBEDDED_LICENSES"; do
    [ -f "$extracted_file" ] || fail "package is missing ${extracted_file#"$EXTRACTED_ROOT/"}"
done

plutil -lint "$SILEO_APP/Info.plist" "$EMBEDDED_LICENSES" >/dev/null
APP_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$SILEO_APP/Info.plist")"
[ "$APP_VERSION" = "$SELECTED_VERSION" ] \
    || fail "Sileo.app version mismatch: expected $SELECTED_VERSION, got $APP_VERSION"

for executable in "$SILEO_EXECUTABLE" "$ROOT_HELPER"; do
    [ "$(lipo -archs "$executable")" = "arm64" ] \
        || fail "${executable#"$EXTRACTED_ROOT/"} is not thin arm64"
    file "$executable" | grep -q 'Mach-O 64-bit executable arm64' \
        || fail "${executable#"$EXTRACTED_ROOT/"} is not an arm64 Mach-O executable"
done
[ -u "$ROOT_HELPER" ] || fail "giveMeRoot is missing its setuid mode"

if ! cmp -s "$EMBEDDED_LICENSES" "$VENDOR_LICENSES"; then
    echo "The embedded Sileo license catalog changed." >&2
    shasum -a 256 "$VENDOR_LICENSES" "$EMBEDDED_LICENSES" >&2
    fail "review and update Vendor/Sileo/Dependencies before replacing the package"
fi

awk '
    found || /^## Bundled third-party licenses/ {
        found = 1
        print
    }
' "$ORIGIN_FILE" >"$ORIGIN_TAIL"
[ -s "$ORIGIN_TAIL" ] || fail "could not preserve the license notes in ORIGIN.md"

cat >"$STAGED_ORIGIN" <<EOF
# Sileo

\`sileo.deb\` is downloaded byte-for-byte from the RootHide APT repository:

- Repository: <$REPOSITORY_URL/>
- Index: <$INDEX_URL>
- Package file: <$PACKAGE_URL>
- Package: \`$PACKAGE_IDENTIFIER\`
- Version: \`$SELECTED_VERSION\`
- Debian architecture: \`$PACKAGE_ARCHITECTURE\`
- Size: \`$ACTUAL_SIZE\` bytes
- SHA-256: \`$ACTUAL_SHA256\`

The package is vendored without local modifications. Its \`Sileo\` and
\`giveMeRoot\` Mach-O executables are thin \`arm64\`.

Update it manually with \`DevKit/Helpers/update-sileo.sh [VERSION]\`. Pass
\`--reference PATH\` when the current deb must first match another project.

EOF
cat "$ORIGIN_TAIL" >>"$STAGED_ORIGIN"

chmod 0644 "$DOWNLOADED_DEB" "$STAGED_ORIGIN"
mv "$DOWNLOADED_DEB" "$VENDOR_DEB"
mv "$STAGED_ORIGIN" "$ORIGIN_FILE"

"$LICENSE_SCANNER"

echo "Updated Vendor/Sileo/sileo.deb to $SELECTED_VERSION"
echo "SHA-256: $ACTUAL_SHA256"
