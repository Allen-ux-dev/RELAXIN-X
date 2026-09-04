#!/usr/bin/env bash

set -Eeuo pipefail

if [[ "$#" -ne 3 ]]; then
    echo "usage: $0 <app-bundle> <entitlements> <output-tipa>" >&2
    exit 64
fi

APP_BUNDLE="$1"
ENTITLEMENTS="$2"
OUTPUT_TIPA="$3"
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
if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "error: entitlements do not exist: $ENTITLEMENTS" >&2
    exit 66
fi
if [[ "$OUTPUT_TIPA" != *.tipa ]]; then
    echo "error: TIPA output must use the .tipa extension: $OUTPUT_TIPA" >&2
    exit 64
fi
if ! command -v ldid >/dev/null 2>&1; then
    echo "error: ldid is required to package the TIPA" >&2
    exit 69
fi

OUTPUT_NAME="$(basename "$OUTPUT_TIPA")"
OUTPUT_DIRECTORY="$(dirname "$OUTPUT_TIPA")"
mkdir -p "$OUTPUT_DIRECTORY"
OUTPUT_DIRECTORY="$(cd "$OUTPUT_DIRECTORY" && pwd -P)"
OUTPUT_TIPA="$OUTPUT_DIRECTORY/$OUTPUT_NAME"
WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/relaxin-tipa.XXXXXX")"
TEMPORARY_TIPA="$OUTPUT_DIRECTORY/.$OUTPUT_NAME.tmp.$$"
trap 'rm -rf "$WORK_DIRECTORY"; rm -f "$TEMPORARY_TIPA"' EXIT

mkdir -p "$WORK_DIRECTORY/Payload"
/usr/bin/ditto "$APP_BUNDLE" "$WORK_DIRECTORY/Payload/$APP_NAME"

PACKAGED_EXECUTABLE="$WORK_DIRECTORY/Payload/$APP_NAME/$APP_EXECUTABLE"
ldid -S"$ENTITLEMENTS" -Cadhoc "$PACKAGED_EXECUTABLE"

PACKAGED_ENTITLEMENTS="$WORK_DIRECTORY/packaged-entitlements.plist"
ldid -e "$PACKAGED_EXECUTABLE" >"$PACKAGED_ENTITLEMENTS"
for entitlement in \
    "platform-application" \
    "proc_info-allow" \
    "com.apple.private.persona-mgmt" \
    "com.apple.private.security.storage-exempt.heritable" \
    "com.apple.private.security.storage.AppBundles" \
    "com.apple.private.security.no-sandbox" \
    "com.apple.springboard.CFUserNotification" \
    "com.apple.springboard.launchapplications" \
    "com.apple.security.network.client" \
    "com.apple.developer.kernel.extended-virtual-addressing" \
    "com.apple.developer.kernel.increased-memory-limit"; do
    if [[ "$(/usr/libexec/PlistBuddy \
        -c "Print :$entitlement" \
        "$PACKAGED_ENTITLEMENTS" 2>/dev/null)" != "true" ]]; then
        echo "error: packaged executable is missing entitlement: $entitlement" >&2
        exit 65
    fi
done

(
    cd "$WORK_DIRECTORY"
    COPYFILE_DISABLE=1 /usr/bin/ditto -c -k \
        --norsrc --noextattr --noqtn --noacl \
        --keepParent Payload "$TEMPORARY_TIPA"
)

/usr/bin/unzip -tq "$TEMPORARY_TIPA"
ARCHIVE_MEMBERS="$(/usr/bin/unzip -Z1 "$TEMPORARY_TIPA")"
for member in \
    "Payload/$APP_NAME/Info.plist" \
    "Payload/$APP_NAME/$APP_EXECUTABLE"; do
    if ! grep -Fxq "$member" <<<"$ARCHIVE_MEMBERS"; then
        echo "error: TIPA is missing $member" >&2
        exit 65
    fi
done
if grep -Eq "^Payload/$APP_NAME/(_CodeSignature/|embedded[.]mobileprovision$)" \
    <<<"$ARCHIVE_MEMBERS"; then
    echo "error: TIPA contains distribution signing material" >&2
    exit 65
fi
if grep -Eq "(^|/)(__MACOSX|[.]DS_Store)(/|$)" <<<"$ARCHIVE_MEMBERS"; then
    echo "error: TIPA contains macOS metadata" >&2
    exit 65
fi

mv -f "$TEMPORARY_TIPA" "$OUTPUT_TIPA"
echo "Packaged no-sandbox TIPA: $OUTPUT_TIPA"
shasum -a 256 "$OUTPUT_TIPA"
