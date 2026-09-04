#!/usr/bin/env bash

set -Eeuo pipefail

if [[ "$#" -ne 2 ]]; then
    echo "usage: $0 <app-bundle> <output-ipa>" >&2
    exit 64
fi

APP_BUNDLE="$1"
OUTPUT_IPA="$2"
APP_NAME="$(basename "$APP_BUNDLE")"
APP_EXECUTABLE="${APP_NAME%.app}"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "error: app bundle does not exist: $APP_BUNDLE" >&2
    exit 66
fi
if [[ ! -f "$APP_BUNDLE/Info.plist" || ! -x "$APP_BUNDLE/$APP_EXECUTABLE" ]]; then
    echo "error: app bundle is incomplete: $APP_BUNDLE" >&2
    exit 65
fi
if [[ -e "$APP_BUNDLE/_CodeSignature" || -e "$APP_BUNDLE/embedded.mobileprovision" ]]; then
    echo "error: app bundle contains distribution signing material" >&2
    exit 65
fi

OUTPUT_NAME="$(basename "$OUTPUT_IPA")"
OUTPUT_DIRECTORY="$(dirname "$OUTPUT_IPA")"
mkdir -p "$OUTPUT_DIRECTORY"
OUTPUT_DIRECTORY="$(cd "$OUTPUT_DIRECTORY" && pwd -P)"
OUTPUT_IPA="$OUTPUT_DIRECTORY/$OUTPUT_NAME"
WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/relaxin-ipa.XXXXXX")"
TEMPORARY_IPA="$OUTPUT_DIRECTORY/.$OUTPUT_NAME.tmp.$$"
trap 'rm -rf "$WORK_DIRECTORY"; rm -f "$TEMPORARY_IPA"' EXIT

mkdir -p "$WORK_DIRECTORY/Payload"
/usr/bin/ditto "$APP_BUNDLE" "$WORK_DIRECTORY/Payload/$APP_NAME"
(
    cd "$WORK_DIRECTORY"
    COPYFILE_DISABLE=1 /usr/bin/ditto -c -k \
        --norsrc --noextattr --noqtn --noacl \
        --keepParent Payload "$TEMPORARY_IPA"
)

/usr/bin/unzip -tq "$TEMPORARY_IPA"
ARCHIVE_MEMBERS="$(/usr/bin/unzip -Z1 "$TEMPORARY_IPA")"
for member in \
    "Payload/$APP_NAME/Info.plist" \
    "Payload/$APP_NAME/$APP_EXECUTABLE"; do
    if ! grep -Fxq "$member" <<<"$ARCHIVE_MEMBERS"; then
        echo "error: IPA is missing $member" >&2
        exit 65
    fi
done
if grep -Eq "^Payload/$APP_NAME/(_CodeSignature/|embedded[.]mobileprovision$)" \
    <<<"$ARCHIVE_MEMBERS"; then
    echo "error: IPA contains distribution signing material" >&2
    exit 65
fi
if grep -Eq "(^|/)(__MACOSX|[.]DS_Store)(/|$)" <<<"$ARCHIVE_MEMBERS"; then
    echo "error: IPA contains macOS metadata" >&2
    exit 65
fi

mv -f "$TEMPORARY_IPA" "$OUTPUT_IPA"
echo "Packaged unsigned IPA: $OUTPUT_IPA"
shasum -a 256 "$OUTPUT_IPA"
