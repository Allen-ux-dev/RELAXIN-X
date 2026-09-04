#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: package-deb.sh <RelaxinLite.app> <output.deb>" >&2
    exit 64
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_directory/../../.." && pwd)"
source_app="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
output_directory="$(cd "$(dirname "$2")" && pwd)"
output_deb="$output_directory/$(basename "$2")"
entitlements="$project_root/RelaxinLite/Resources/RelaxinLite.entitlements"
version_configuration="$project_root/Configuration/Version.xcconfig"

for tool in dpkg-deb install_name_tool ldid lipo nm otool plutil; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Required tool is unavailable: $tool" >&2
        exit 1
    fi
done

executable="$source_app/RelaxinLite"
if [[ ! -d "$source_app" || ! -f "$source_app/Info.plist" || ! -f "$executable" ]]; then
    echo "RelaxinLite.app is incomplete: $source_app" >&2
    exit 1
fi
if [[ ! -f "$entitlements" || ! -f "$version_configuration" ]]; then
    echo "Relaxin Lite packaging inputs are incomplete" >&2
    exit 1
fi

bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Info.plist")"
bundle_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$source_app/Info.plist")"
if [[ "$bundle_identifier" != "com.aapl.relaxin.lite" || "$bundle_executable" != "RelaxinLite" ]]; then
    echo "Unexpected Relaxin Lite bundle metadata: $bundle_identifier / $bundle_executable" >&2
    exit 1
fi

architectures="$(lipo -archs "$executable")"
if [[ "$architectures" != "arm64e" ]]; then
    echo "Relaxin Lite must contain only arm64e, found: $architectures" >&2
    exit 1
fi

marketing_version="$(awk -F= '/^[[:space:]]*MARKETING_VERSION[[:space:]]*=/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }' "$version_configuration")"
build_version="$(awk -F= '/^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }' "$version_configuration")"
if [[ -z "$marketing_version" || -z "$build_version" ]]; then
    echo "Version.xcconfig does not define both product versions" >&2
    exit 1
fi
package_version="${marketing_version}-${build_version}"

mkdir -p "$project_root/build"
staging_directory="$(mktemp -d "$project_root/build/.RelaxinLiteDeb.XXXXXX")"
trap 'rm -rf "$staging_directory"' EXIT
package_root="$staging_directory/root"
staged_app="$package_root/Applications/RelaxinLite.app"
control_directory="$package_root/DEBIAN"
mkdir -p "$package_root/Applications" "$control_directory"
/usr/bin/ditto "$source_app" "$staged_app"

staged_executable="$staged_app/RelaxinLite"
/usr/bin/install_name_tool \
    -change "@loader_path/libjailbreak.dylib" \
    "@loader_path/.jbroot/usr/lib/libjailbreak.dylib" \
    "$staged_executable"
ldid -S"$entitlements" -Cadhoc "$staged_executable"
chmod 4755 "$staged_executable"

printf '%s\n' \
    'Package: com.aapl.relaxin.lite' \
    'Name: Relaxin Lite' \
    "Version: $package_version" \
    'Architecture: iphoneos-arm64e' \
    'Depends: dopamine-basebin-link (>= 1.0.0)' \
    'Section: Utilities' \
    'Priority: optional' \
    'Maintainer: OWNGOAL STUDIO' \
    'Description: Post-jailbreak controls for the Relaxin Web jailbreak.' \
    >"$control_directory/control"
/usr/bin/install -m 0755 "$script_directory/postinst" "$control_directory/postinst"
/usr/bin/install -m 0755 "$script_directory/prerm" "$control_directory/prerm"

actual_entitlements="$staging_directory/actual-entitlements.plist"
ldid -e "$staged_executable" >"$actual_entitlements"
if ! diff -u \
    <(plutil -convert json -o - "$entitlements") \
    <(plutil -convert json -o - "$actual_entitlements"); then
    echo "Relaxin Lite entitlements do not match the allow-list" >&2
    exit 1
fi

if ! otool -L "$staged_executable" \
    | grep -F '@loader_path/.jbroot/usr/lib/libjailbreak.dylib' >/dev/null; then
    echo "Relaxin Lite is not linked to the installed RootHide runtime" >&2
    exit 1
fi
if otool -L "$staged_executable" \
    | grep -Ei 'RelaxinEngine|libxpf|libchoma|@loader_path/libjailbreak' >/dev/null; then
    echo "Relaxin Lite contains a forbidden jailbreak runtime dependency" >&2
    exit 1
fi
if nm -m "$staged_executable" \
    | grep -E 'DarkSword|Rocket|KernelAccess|XPF' >/dev/null; then
    echo "Relaxin Lite contains an exploit or kernel-access symbol" >&2
    exit 1
fi
if find "$staged_app" -type f \
    | grep -Ei '/(bootstrap|basebin|sileo|roothideapp|kerneloffsets)([./]|$)' >/dev/null; then
    echo "Relaxin Lite contains a forbidden bootstrap resource" >&2
    exit 1
fi

dpkg-deb --root-owner-group --build "$package_root" "$output_deb"

for field in \
    'Package=com.aapl.relaxin.lite' \
    'Name=Relaxin Lite' \
    'Architecture=iphoneos-arm64e' \
    'Depends=dopamine-basebin-link (>= 1.0.0)'; do
    key="${field%%=*}"
    expected="${field#*=}"
    actual="$(dpkg-deb -f "$output_deb" "$key")"
    if [[ "$actual" != "$expected" ]]; then
        echo "Unexpected deb field $key: $actual" >&2
        exit 1
    fi
done
if ! dpkg-deb --contents "$output_deb" \
    | grep -F './Applications/RelaxinLite.app/RelaxinLite' >/dev/null; then
    echo "Relaxin Lite deb does not contain its executable" >&2
    exit 1
fi

echo "Built Relaxin Lite RootHide package: $output_deb"
