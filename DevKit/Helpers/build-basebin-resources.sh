#!/usr/bin/env bash

set -Eeuo pipefail

CURRENT_STAGE="starting"

log_stage() {
    CURRENT_STAGE="$1"
    printf 'note: [BaseBin] %s\n' "$CURRENT_STAGE"
}

report_failure() {
    local status=$?
    printf 'error: [BaseBin] failed while %s (exit %d)\n' \
        "$CURRENT_STAGE" "$status" >&2
    exit "$status"
}

trap report_failure ERR

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT_DIR/.env.sh"
TOOL_CHECKER="$ROOT_DIR/DevKit/Helpers/check-tools.sh"
BASE_CONFIGURATION="$ROOT_DIR/Configuration/Base.xcconfig"
SIGNATURE_VERIFIER_SOURCE="$ROOT_DIR/DevKit/Bootstrap/VerifyAdHocSignature.c"
VENDOR_DIRECTORY="$ROOT_DIR/Vendor"
VENDOR_DOPAMINE="$VENDOR_DIRECTORY/Dopamine"
VENDOR_CAPTAINHOOK="$VENDOR_DIRECTORY/CaptainHook"
VENDOR_ELLEKIT="$VENDOR_DIRECTORY/ElleKit"
WORK_DIRECTORY="$ROOT_DIR/build/BaseBinWork"
CACHE_DIRECTORY="${RELAXIN_BASEBIN_CACHE_DIRECTORY:-$ROOT_DIR/build/BaseBinCaches}"
OUTPUT_DIRECTORY="$ROOT_DIR/build/BaseBinResources"
LOCK_DIRECTORY="${RELAXIN_BASEBIN_LOCK_DIRECTORY:-$ROOT_DIR/build/.BaseBinResources.lock}"
STAMP_PATH="$OUTPUT_DIRECTORY/.input-sha256"
MANIFEST_PATH="$OUTPUT_DIRECTORY/.artifact-sha256"

EXPECTED_OUTPUTS=(
    basebin.tar
    basebin.tc
    libchoma.dylib
    libjailbreak.dylib
    libxpf.dylib
    libroot.deb
    libkrw-dopamine.deb
    basebin-link.deb
    libchoma-sim.dylib
    libjailbreak-sim.dylib
    libxpf-sim.dylib
)

export LC_ALL=C
export SOURCE_DATE_EPOCH=0
export ZERO_AR_DATE=1

log_stage "checking required build tools"
"$TOOL_CHECKER" xcode make gtar trustcache dpkg-deb ldid git rsync shasum

if command -v gmake >/dev/null 2>&1; then
    GNU_MAKE="$(command -v gmake)"
else
    GNU_MAKE="$(command -v make)"
fi
if ! "$GNU_MAKE" --version | grep -Fq "GNU Make"; then
    echo "error: $GNU_MAKE is not GNU Make" >&2
    exit 69
fi
echo "note: [BaseBin] using $("$GNU_MAKE" --version | sed -n '1p')"

log_stage "preparing isolated build caches"
mkdir -p "$CACHE_DIRECTORY"
CACHE_DIRECTORY="$(cd "$CACHE_DIRECTORY" && pwd -P)"
relaxin_prepare_build_environment "$CACHE_DIRECTORY"

LOCK_ACQUIRED=0

release_lock() {
    if [[ "$LOCK_ACQUIRED" -eq 1 ]]; then
        rm -rf "$LOCK_DIRECTORY"
        LOCK_ACQUIRED=0
    fi
}

acquire_lock() {
    local attempts=0
    local owner_pid

    while ! mkdir "$LOCK_DIRECTORY" 2>/dev/null; do
        owner_pid=""
        if [[ -f "$LOCK_DIRECTORY/pid" ]]; then
            owner_pid="$(cat "$LOCK_DIRECTORY/pid" 2>/dev/null || true)"
        fi
        if [[ "$owner_pid" =~ ^[0-9]+$ ]] &&
            ! kill -0 "$owner_pid" 2>/dev/null; then
            rm -rf "$LOCK_DIRECTORY"
            continue
        fi
        if (( attempts == 0 )); then
            echo "Waiting for the active BaseBin resource build"
        fi
        if (( attempts >= 300 )); then
            echo "error: timed out waiting for $LOCK_DIRECTORY" >&2
            exit 75
        fi
        attempts=$((attempts + 1))
        sleep 1
    done

    LOCK_ACQUIRED=1
    printf '%s\n' "$$" >"$LOCK_DIRECTORY/pid"
}

trap release_lock EXIT
trap 'release_lock; exit 129' HUP
trap 'release_lock; exit 130' INT
trap 'release_lock; exit 143' TERM

read_xcconfig_value() {
    local key="$1"

    awk -F= -v key="$key" '
        $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
            value = $2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            print value
            exit
        }
    ' "$BASE_CONFIGURATION"
}

MIN_IOS_VERSION="$(
    read_xcconfig_value RELAXIN_BASEBIN_DEPLOYMENT_TARGET
)"
if [[ ! "$MIN_IOS_VERSION" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "error: invalid RELAXIN_BASEBIN_DEPLOYMENT_TARGET in $BASE_CONFIGURATION" >&2
    exit 65
fi

APP_BUNDLE_IDENTIFIER="$(read_xcconfig_value PRODUCT_BUNDLE_IDENTIFIER)"
if [[ ! "$APP_BUNDLE_IDENTIFIER" =~ ^[A-Za-z0-9-]+([.][A-Za-z0-9-]+)+$ ]]; then
    echo "error: invalid PRODUCT_BUNDLE_IDENTIFIER in $BASE_CONFIGURATION" >&2
    exit 65
fi
STARTUP_PLIST_NAME="$APP_BUNDLE_IDENTIFIER.startup.plist"
BASEBIN_DEBUG=0
if [[ "${CONFIGURATION:-Release}" == "Debug" ]]; then
    BASEBIN_DEBUG=1
fi

calculate_input_fingerprint() {
    {
        printf 'minimum-ios=%s\n' "$MIN_IOS_VERSION"
        printf 'app-bundle-identifier=%s\n' "$APP_BUNDLE_IDENTIFIER"
        printf 'architectures=arm64 arm64e\n'
        printf 'basebin-debug=%s\n' "$BASEBIN_DEBUG"

        find \
            "$VENDOR_DOPAMINE" \
            "$VENDOR_CAPTAINHOOK" \
            "$VENDOR_ELLEKIT" \
            \( -type f -o -type l \) -print |
            LC_ALL=C sort |
            while IFS= read -r path; do
                if [[ -L "$path" ]]; then
                    printf 'symlink:%s  %s\n' \
                        "$(readlink "$path")" \
                        "${path#"$ROOT_DIR/"}"
                else
                    hash="$(shasum -a 256 "$path" | awk '{ print $1 }')"
                    printf '%s  %s\n' "$hash" "${path#"$ROOT_DIR/"}"
                fi
            done

        for path in \
            "$BASE_CONFIGURATION" \
            "$SIGNATURE_VERIFIER_SOURCE" \
            "$ROOT_DIR/.env.sh" \
            "$ROOT_DIR/DevKit/Helpers/build-basebin-resources.sh"; do
            hash="$(shasum -a 256 "$path" | awk '{ print $1 }')"
            printf '%s  %s\n' "$hash" "${path#"$ROOT_DIR/"}"
        done

        xcodebuild -version
        xcrun --sdk iphoneos --show-sdk-version
        env -u SDKROOT "$(xcrun --find clang)" --version 2>&1 | sed -n '1p'
        env -u SDKROOT "$(xcrun --find swiftc)" --version 2>&1 | sed -n '1p'
        "$GNU_MAKE" --version | sed -n '1p'
        gtar --version | sed -n '1p'
        dpkg-deb --version | sed -n '1p'
        ldid 2>&1 | sed -n '1p'
        shasum -a 256 "$(command -v trustcache)"
    } | shasum -a 256 | awk '{ print $1 }'
}

cache_is_valid() {
    local fingerprint="$1"

    [[ -f "$STAMP_PATH" && -f "$MANIFEST_PATH" ]] || return 1
    [[ "$(cat "$STAMP_PATH")" == "$fingerprint" ]] || return 1
    (
        cd "$OUTPUT_DIRECTORY"
        shasum -a 256 -c "$(basename "$MANIFEST_PATH")" >/dev/null
    )
}

require_architectures() {
    local path="$1"
    local expected="$2"
    local actual

    actual="$(lipo -archs "$path")"
    if [[ "$actual" != "$expected" ]]; then
        echo "error: unexpected architectures for $path" >&2
        echo "expected: $expected" >&2
        echo "actual:   $actual" >&2
        exit 65
    fi
}

require_minimum_ios() {
    local path="$1"
    shift

    local architecture
    for architecture in "$@"; do
        if ! vtool -arch "$architecture" -show-build "$path" |
            grep -Eq "minos[[:space:]]+${MIN_IOS_VERSION}([.]0)?$"; then
            echo "error: $path ($architecture) does not target iOS $MIN_IOS_VERSION" >&2
            vtool -arch "$architecture" -show-build "$path" >&2
            exit 65
        fi
    done
}

require_simulator_platform() {
    local path="$1"

    if ! vtool -show-build "$path" |
        grep -Eq "platform[[:space:]]+IOSSIMULATOR$"; then
        echo "error: $path is not built for the iOS simulator platform" >&2
        vtool -show-build "$path" >&2
        exit 65
    fi
}

verify_signed_binary() {
    local verifier="$1"
    local path="$2"

    "$verifier" "$path"
    /usr/bin/codesign --verify --strict --all-architectures -- "$path"
}

require_dylib_contract() {
    local path="$1"
    local expected_install_name="$2"
    local expected_rpaths="$3"
    local actual_install_name
    local actual_rpaths

    actual_install_name="$(otool -D "$path" | sed -n '2p')"
    if [[ "$actual_install_name" != "$expected_install_name" ]]; then
        echo "error: unexpected LC_ID_DYLIB for $path" >&2
        echo "expected: $expected_install_name" >&2
        echo "actual:   $actual_install_name" >&2
        exit 65
    fi
    if ! otool -L "$path" |
        sed -n '2p' |
        grep -Fq \
            '(compatibility version 0.0.0, current version 0.0.0)'; then
        echo "error: unexpected dylib version fields for $path" >&2
        otool -L "$path" | sed -n '2p' >&2
        exit 65
    fi

    actual_rpaths="$(
        otool -l "$path" |
            awk '
                /cmd LC_RPATH/ {
                    capture = 1
                    next
                }
                capture && /path / {
                    print $2
                    capture = 0
                }
            ' |
            LC_ALL=C sort |
            paste -sd, -
    )"
    [[ "$expected_rpaths" == "-" ]] && expected_rpaths=""
    if [[ "$actual_rpaths" != "$expected_rpaths" ]]; then
        echo "error: LC_RPATH set drifted for $path" >&2
        echo "expected: ${expected_rpaths:-(none)}" >&2
        echo "actual:   ${actual_rpaths:-(none)}" >&2
        exit 65
    fi
}

require_export() {
    local path="$1"
    local symbol="$2"

    nm -gjU "$path" | grep -Fx "$symbol" >/dev/null || {
        echo "error: required export $symbol is missing from $path" >&2
        exit 65
    }
}

require_dependency() {
    local path="$1"
    local dependency="$2"

    otool -L "$path" |
        tail -n +2 |
        sed -E 's/^[[:space:]]+([^[:space:]]+).*/\1/' |
        grep -Fx "$dependency" >/dev/null || {
        echo "error: required dependency $dependency is missing from $path" >&2
        exit 65
    }
}

require_entitlements() {
    local path="$1"
    local expected_plist="$2"
    local actual_digest
    local expected_digest

    actual_digest="$(
        /usr/bin/codesign -d --entitlements :- "$path" 2>/dev/null |
            plutil -p - |
            shasum -a 256 |
            awk '{print $1}'
    )"
    expected_digest="$(
        plutil -p "$expected_plist" |
            shasum -a 256 |
            awk '{print $1}'
    )"
    if [[ "$actual_digest" != "$expected_digest" ]]; then
        echo "error: entitlement dictionary drifted for $path" >&2
        echo "expected source: $expected_plist" >&2
        exit 65
    fi
}

require_debian_field() {
    local package_path="$1"
    local field="$2"
    local expected="$3"
    local actual

    actual="$(dpkg-deb -f "$package_path" "$field")"
    if [[ "$actual" != "$expected" ]]; then
        echo "error: invalid $field in $(basename "$package_path")" >&2
        echo "expected: $expected" >&2
        echo "actual:   $actual" >&2
        exit 65
    fi
}

require_symlink_target() {
    local path="$1"
    local expected="$2"
    local actual

    [[ -L "$path" ]] || {
        echo "error: expected package symlink is missing: $path" >&2
        exit 65
    }
    actual="$(readlink "$path")"
    if [[ "$actual" != "$expected" ]]; then
        echo "error: invalid symlink target for $path" >&2
        echo "expected: $expected" >&2
        echo "actual:   $actual" >&2
        exit 65
    fi
}

validate_build() {
    local dopamine_root="$WORK_DIRECTORY/Vendor/Dopamine"
    local basebin_root="$dopamine_root/BaseBin"
    local staged_root="$basebin_root/.build"
    local verifier="$dopamine_root/build/Tools/VerifyAdHocSignature"

    local fat_binaries=(
        "$staged_root/fallback/CydiaSubstrate.framework/CydiaSubstrate"
        "$staged_root/launchdhook.dylib"
        "$staged_root/libchoma.dylib"
        "$staged_root/libjailbreak.dylib"
        "$staged_root/libxpf.dylib"
        "$staged_root/roothidehooks.dylib"
        "$staged_root/systemhook.dylib"
        "$staged_root/watchdoghook.dylib"
        "$staged_root/boomerang"
        "$staged_root/bootstrapper"
        "$staged_root/jailbreakd"
        "$staged_root/jbctl"
        "$staged_root/opainject"
    )
    local compiled_fat_binaries=("${fat_binaries[@]:1}")
    local dyld_binaries=(
        "$staged_root/dyldhook_merge.arm64.iOS16-17.dylib"
        "$staged_root/dyldhook_merge.arm64e.iOS16-17.dylib"
        "$staged_root/dyldhook_merge.arm64.iOS18+.dylib"
        "$staged_root/dyldhook_merge.arm64e.iOS18+.dylib"
    )

    local binary
    for binary in "${fat_binaries[@]}"; do
        require_architectures "$binary" "arm64 arm64e"
        verify_signed_binary "$verifier" "$binary"
    done
    for binary in "${compiled_fat_binaries[@]}"; do
        require_minimum_ios "$binary" arm64 arm64e
    done

    require_architectures "$staged_root/forkfix.dylib" arm64e
    require_minimum_ios "$staged_root/forkfix.dylib" arm64e
    verify_signed_binary "$verifier" "$staged_root/forkfix.dylib"

    require_architectures "$staged_root/MachOMerger" arm64
    require_minimum_ios "$staged_root/MachOMerger" arm64
    verify_signed_binary "$verifier" "$staged_root/MachOMerger"

    for binary in "${dyld_binaries[@]}"; do
        if [[ "$binary" == *".arm64e."* ]]; then
            require_architectures "$binary" arm64e
            require_minimum_ios "$binary" arm64e
        else
            require_architectures "$binary" arm64
            require_minimum_ios "$binary" arm64
        fi
        verify_signed_binary "$verifier" "$binary"
    done

    if ! otool -L "$staged_root/opainject" |
        grep -Fq "/System/Library/PrivateFrameworks/CoreSymbolication.framework/CoreSymbolication"; then
        echo "error: opainject lost its CoreSymbolication dependency" >&2
        exit 65
    fi
    while IFS='|' read -r relative_path install_name rpaths; do
        require_dylib_contract \
            "$staged_root/$relative_path" \
            "$install_name" \
            "$rpaths"
    done <<'DYLIB_CONTRACTS'
libchoma.dylib|@loader_path/libchoma.dylib|-
libxpf.dylib|@loader_path/libxpf.dylib|-
libjailbreak.dylib|@loader_path/libjailbreak.dylib|-
systemhook.dylib|systemhook.dylib|-
launchdhook.dylib|launchdhook.dylib|@loader_path/fallback
watchdoghook.dylib|watchdoghook.dylib|@loader_path/.jbroot/Library/Frameworks,@loader_path/fallback
roothidehooks.dylib|/basebin/roothidehooks.dylib|@loader_path/.jbroot/Library/Frameworks,@loader_path/fallback
forkfix.dylib|forkfix.dylib|-
DYLIB_CONTRACTS

    while IFS='|' read -r relative_path symbol; do
        require_export "$staged_root/$relative_path" "$symbol"
    done <<'REQUIRED_EXPORTS'
libchoma.dylib|_macho_init
libchoma.dylib|_pfmetric_string_init
libxpf.dylib|_gXPF
libxpf.dylib|_xpf_construct_offset_dictionary
libxpf.dylib|_xpf_start_with_kernel_path
libxpf.dylib|_xpf_stop
libjailbreak.dylib|_gPrimitives
libjailbreak.dylib|_gSystemInfo
libjailbreak.dylib|_jbinfo_get_serialized
systemhook.dylib|___posix_spawn_hook
launchdhook.dylib|_boomerang_recoverPrimitives
launchdhook.dylib|_jbserver_local_start
watchdoghook.dylib|_IOServiceOpen_hook
roothidehooks.dylib|_cfprefsdInit
roothidehooks.dylib|_lsdInit
roothidehooks.dylib|_sbInit
forkfix.dylib|_apply_fork_hook
REQUIRED_EXPORTS

    while IFS='|' read -r relative_path dependency; do
        require_dependency "$staged_root/$relative_path" "$dependency"
    done <<'REQUIRED_DEPENDENCIES'
libxpf.dylib|@loader_path/libchoma.dylib
libjailbreak.dylib|@loader_path/libchoma.dylib
launchdhook.dylib|@loader_path/libjailbreak.dylib
launchdhook.dylib|@rpath/CydiaSubstrate.framework/CydiaSubstrate
watchdoghook.dylib|@rpath/CydiaSubstrate.framework/CydiaSubstrate
roothidehooks.dylib|@loader_path/libjailbreak.dylib
roothidehooks.dylib|@loader_path/.jbroot/usr/lib/libroothide.dylib
roothidehooks.dylib|@rpath/CydiaSubstrate.framework/CydiaSubstrate
REQUIRED_DEPENDENCIES

    require_entitlements \
        "$staged_root/boomerang" \
        "$basebin_root/boomerang/entitlements.plist"
    require_entitlements \
        "$staged_root/bootstrapper" \
        "$basebin_root/bootstrapper/entitlements.plist"
    require_entitlements \
        "$staged_root/jailbreakd" \
        "$basebin_root/jailbreakd/entitlements.plist"
    require_entitlements \
        "$staged_root/jbctl" \
        "$basebin_root/jbctl/entitlements.plist"
    require_entitlements \
        "$staged_root/opainject" \
        "$basebin_root/opainject/entitlements.plist"
    require_entitlements \
        "$staged_root/MachOMerger" \
        "$basebin_root/MachOMerger/MachOMerger.entitlements"

    local trustcache_info
    trustcache_info="$(trustcache info "$basebin_root/basebin.tc")"
    if ! grep -Eq 'entry count = 28$' <<<"$trustcache_info"; then
        echo "error: unexpected BaseBin trust cache entry count" >&2
        echo "$trustcache_info" >&2
        exit 65
    fi

    local tar_listing
    tar_listing="$(gtar -tf "$basebin_root/basebin.tar")"
    local expected_tar_listing
    expected_tar_listing="$(
        printf '%s\n' \
            basebin/ \
            basebin/.AppIdentifier \
            basebin/.version \
            basebin/LaunchDaemons/ \
            "basebin/LaunchDaemons/$STARTUP_PLIST_NAME" \
            basebin/MachOMerger \
            basebin/basebin.tc \
            basebin/boomerang \
            basebin/bootstrapper \
            basebin/dyldhook_merge.arm64.iOS16-17.dylib \
            basebin/dyldhook_merge.arm64.iOS18+.dylib \
            basebin/dyldhook_merge.arm64e.iOS16-17.dylib \
            basebin/dyldhook_merge.arm64e.iOS18+.dylib \
            basebin/fallback/ \
            basebin/fallback/CydiaSubstrate.framework/ \
            basebin/fallback/CydiaSubstrate.framework/.this_is_ellekit_not_substrate \
            basebin/fallback/CydiaSubstrate.framework/CydiaSubstrate \
            basebin/forkfix.dylib \
            basebin/jailbreakd \
            basebin/jbctl \
            basebin/launchdhook.dylib \
            basebin/libchoma.dylib \
            basebin/libjailbreak.dylib \
            basebin/libxpf.dylib \
            basebin/opainject \
            basebin/roothidehooks.dylib \
            basebin/systemhook.dylib \
            basebin/watchdoghook.dylib |
            LC_ALL=C sort
    )"
    if [[ "$(LC_ALL=C sort <<<"$tar_listing")" != "$expected_tar_listing" ]]; then
        echo "error: unexpected BaseBin archive member set" >&2
        diff -u \
            <(printf '%s\n' "$expected_tar_listing") \
            <(LC_ALL=C sort <<<"$tar_listing") >&2 || true
        exit 65
    fi

    local startup_plist="$staged_root/LaunchDaemons/$STARTUP_PLIST_NAME"
    local startup_label
    startup_label="$(plutil -extract Label raw -o - "$startup_plist")"
    if [[ "$startup_label" != "$APP_BUNDLE_IDENTIFIER.startup" ]]; then
        echo "error: invalid Relaxin startup label: $startup_label" >&2
        exit 65
    fi
    local staged_identifier
    staged_identifier="$(cat "$staged_root/.AppIdentifier")"
    if [[ "$staged_identifier" != "$APP_BUNDLE_IDENTIFIER" ]]; then
        echo "error: BaseBin app identifier does not match $BASE_CONFIGURATION" >&2
        exit 65
    fi

    local legacy_identity_pattern
    legacy_identity_pattern='com[.]opa334[.]Dopamine|Dopamine[.]app/Dopamine|DOPAMINE_|[.]installed_dopamine|dopamine-worker|/private/var/db/Dopamine|DopamineInjectionBreadcrumb'
    if grep -aEq "$legacy_identity_pattern" "$basebin_root/basebin.tar"; then
        echo "error: basebin.tar contains a legacy Dopamine runtime identity" >&2
        grep -aEo "$legacy_identity_pattern" "$basebin_root/basebin.tar" |
            LC_ALL=C sort -u >&2
        exit 65
    fi

    require_architectures \
        "$dopamine_root/Packages/libroot/libroot.dylib" \
        "arm64 arm64e"
    require_minimum_ios \
        "$dopamine_root/Packages/libroot/libroot.dylib" \
        arm64 arm64e
    require_architectures \
        "$dopamine_root/Packages/libkrw-provider/libkrw-dopamine.dylib" \
        "arm64 arm64e"
    require_minimum_ios \
        "$dopamine_root/Packages/libkrw-provider/libkrw-dopamine.dylib" \
        arm64 arm64e
    verify_signed_binary \
        "$verifier" \
        "$dopamine_root/Packages/libroot/libroot.dylib"
    verify_signed_binary \
        "$verifier" \
        "$dopamine_root/Packages/libkrw-provider/libkrw-dopamine.dylib"

    local package_path
    for package_path in \
        "$dopamine_root/Packages/libroot/libroot.deb" \
        "$dopamine_root/Packages/libkrw-provider/libkrw-dopamine.deb" \
        "$dopamine_root/Packages/basebin-link/basebin-link.deb"; do
        dpkg-deb --info "$package_path" >/dev/null
        if dpkg-deb --contents "$package_path" | grep -Eqi 'idownload|zebra'; then
            echo "error: $(basename "$package_path") contains an excluded resource" >&2
            exit 65
        fi
    done

    local libroot_deb="$dopamine_root/Packages/libroot/libroot.deb"
    local libkrw_deb="$dopamine_root/Packages/libkrw-provider/libkrw-dopamine.deb"
    local basebin_link_deb="$dopamine_root/Packages/basebin-link/basebin-link.deb"
    require_debian_field "$libroot_deb" Package libroot-dopamine
    require_debian_field "$libroot_deb" Architecture iphoneos-arm64
    require_debian_field "$libkrw_deb" Package libkrw0-dopamine
    require_debian_field "$libkrw_deb" Architecture iphoneos-arm64e
    require_debian_field "$basebin_link_deb" Package dopamine-basebin-link
    require_debian_field "$basebin_link_deb" Architecture iphoneos-arm64e

    local validation_root="$WORK_DIRECTORY/PackageValidation"
    rm -rf "$validation_root"
    mkdir -p \
        "$validation_root/libroot" \
        "$validation_root/libkrw" \
        "$validation_root/basebin-link"
    dpkg-deb -x "$libroot_deb" "$validation_root/libroot"
    dpkg-deb -x "$libkrw_deb" "$validation_root/libkrw"
    dpkg-deb -x "$basebin_link_deb" "$validation_root/basebin-link"

    local extracted_libroot="$validation_root/libroot/var/jb/usr/lib/libroot.dylib"
    local extracted_libkrw="$validation_root/libkrw/usr/lib/libkrw/libkrw-dopamine.dylib"
    cmp -s \
        "$dopamine_root/Packages/libroot/libroot.dylib" \
        "$extracted_libroot" || {
        echo "error: libroot.deb does not contain the validated libroot.dylib" >&2
        exit 65
    }
    cmp -s \
        "$dopamine_root/Packages/libkrw-provider/libkrw-dopamine.dylib" \
        "$extracted_libkrw" || {
        echo "error: libkrw-dopamine.deb does not contain the validated dylib" >&2
        exit 65
    }

    local payload_count
    payload_count="$(
        find "$validation_root/libroot" \( -type f -o -type l \) -print |
            wc -l |
            tr -d ' '
    )"
    [[ "$payload_count" == 1 ]] || {
        echo "error: libroot.deb has unexpected payload members" >&2
        exit 65
    }
    payload_count="$(
        find "$validation_root/libkrw" \( -type f -o -type l \) -print |
            wc -l |
            tr -d ' '
    )"
    [[ "$payload_count" == 1 ]] || {
        echo "error: libkrw-dopamine.deb has unexpected payload members" >&2
        exit 65
    }
    payload_count="$(
        find "$validation_root/basebin-link" \( -type f -o -type l \) -print |
            wc -l |
            tr -d ' '
    )"
    [[ "$payload_count" == 3 ]] || {
        echo "error: basebin-link.deb has unexpected payload members" >&2
        exit 65
    }
    require_symlink_target \
        "$validation_root/basebin-link/usr/bin/jbctl" \
        ../../basebin/jbctl
    require_symlink_target \
        "$validation_root/basebin-link/usr/bin/opainject" \
        ../../basebin/opainject
    require_symlink_target \
        "$validation_root/basebin-link/usr/lib/libjailbreak.dylib" \
        ../../basebin/libjailbreak.dylib

    local simulator_library
    for simulator_library in \
        libchoma-sim.dylib \
        libjailbreak-sim.dylib \
        libxpf-sim.dylib; do
        local simulator_path="$basebin_root/.build-simulator/$simulator_library"
        require_architectures "$simulator_path" arm64
        require_simulator_platform "$simulator_path"
    done
}

publish_outputs() {
    local dopamine_root="$WORK_DIRECTORY/Vendor/Dopamine"
    local publish_directory="$OUTPUT_DIRECTORY/.publish.$$"
    local manifest_temporary="$OUTPUT_DIRECTORY/.artifact-sha256.tmp.$$"
    local stamp_temporary="$OUTPUT_DIRECTORY/.input-sha256.tmp.$$"

    rm -rf "$publish_directory"
    mkdir -p "$publish_directory" "$OUTPUT_DIRECTORY"
    trap 'rm -rf "$publish_directory"; rm -f "$manifest_temporary" "$stamp_temporary"' RETURN

    cp -p "$dopamine_root/BaseBin/basebin.tar" \
        "$publish_directory/basebin.tar"
    cp -p "$dopamine_root/BaseBin/basebin.tc" \
        "$publish_directory/basebin.tc"
    cp -p "$dopamine_root/BaseBin/.build/libchoma.dylib" \
        "$publish_directory/libchoma.dylib"
    cp -p "$dopamine_root/BaseBin/.build/libjailbreak.dylib" \
        "$publish_directory/libjailbreak.dylib"
    cp -p "$dopamine_root/BaseBin/.build/libxpf.dylib" \
        "$publish_directory/libxpf.dylib"
    cp -p "$dopamine_root/Packages/libroot/libroot.deb" \
        "$publish_directory/libroot.deb"
    cp -p "$dopamine_root/Packages/libkrw-provider/libkrw-dopamine.deb" \
        "$publish_directory/libkrw-dopamine.deb"
    cp -p "$dopamine_root/Packages/basebin-link/basebin-link.deb" \
        "$publish_directory/basebin-link.deb"

    local simulator_library
    for simulator_library in \
        libchoma-sim.dylib \
        libjailbreak-sim.dylib \
        libxpf-sim.dylib; do
        cp -p "$dopamine_root/BaseBin/.build-simulator/$simulator_library" \
            "$publish_directory/$simulator_library"
    done

    (
        cd "$publish_directory"
        shasum -a 256 "${EXPECTED_OUTPUTS[@]}"
    ) >"$manifest_temporary"
    printf '%s\n' "$INPUT_FINGERPRINT" >"$stamp_temporary"

    local output
    for output in "${EXPECTED_OUTPUTS[@]}"; do
        mv -f "$publish_directory/$output" "$OUTPUT_DIRECTORY/$output"
    done
    mv -f "$manifest_temporary" "$MANIFEST_PATH"
    mv -f "$stamp_temporary" "$STAMP_PATH"
    rm -rf "$publish_directory"
    trap - RETURN
}

log_stage "waiting for the resource-build lock"
acquire_lock

log_stage "calculating the input fingerprint"
INPUT_FINGERPRINT="$(calculate_input_fingerprint)"

log_stage "checking the published artifact cache"
HEADER_TREE="$WORK_DIRECTORY/Vendor/Dopamine/BaseBin/.include"
if cache_is_valid "$INPUT_FINGERPRINT" && [[ -d "$HEADER_TREE" ]]; then
    echo "note: [BaseBin] resources are up to date"
    exit 0
fi
if cache_is_valid "$INPUT_FINGERPRINT"; then
    echo "note: [BaseBin] artifact cache is valid but the staged header tree is missing; rebuilding working state"
else
    echo "note: [BaseBin] cache miss for input $INPUT_FINGERPRINT"
fi

log_stage "staging vendor sources for iOS $MIN_IOS_VERSION"
rm -rf "$WORK_DIRECTORY"
mkdir -p "$WORK_DIRECTORY/Vendor"
rsync -a --exclude .DS_Store "$VENDOR_DOPAMINE/" \
    "$WORK_DIRECTORY/Vendor/Dopamine/"
rsync -a --exclude .DS_Store "$VENDOR_CAPTAINHOOK/" \
    "$WORK_DIRECTORY/Vendor/CaptainHook/"

STARTUP_PLIST="$WORK_DIRECTORY/Vendor/Dopamine/BaseBin/_external/basebin/LaunchDaemons/$STARTUP_PLIST_NAME"
plutil -replace Label -string "$APP_BUNDLE_IDENTIFIER.startup" "$STARTUP_PLIST"
printf '%s\n' "$APP_BUNDLE_IDENTIFIER" \
    >"$WORK_DIRECTORY/Vendor/Dopamine/BaseBin/_external/basebin/.AppIdentifier"

FALLBACK_FRAMEWORK="$WORK_DIRECTORY/Vendor/Dopamine/BaseBin/_external/basebin/fallback/CydiaSubstrate.framework"
mkdir -p "$FALLBACK_FRAMEWORK"
cp -p \
    "$VENDOR_ELLEKIT/CydiaSubstrate.framework/CydiaSubstrate" \
    "$FALLBACK_FRAMEWORK/CydiaSubstrate"
cp -p \
    "$VENDOR_ELLEKIT/CydiaSubstrate.framework/.this_is_ellekit_not_substrate" \
    "$FALLBACK_FRAMEWORK/.this_is_ellekit_not_substrate"

CLANG_DIRECTORY="$(dirname "$(xcrun --find clang)")"
export PATH="$CLANG_DIRECTORY:$PATH"

log_stage "building the BaseBin archive"
"$GNU_MAKE" \
    -C "$WORK_DIRECTORY/Vendor/Dopamine/BaseBin" \
    ARCHS="arm64 arm64e" \
    MIN_IOS_VERSION="$MIN_IOS_VERSION" \
    RELAXIN_BASEBIN_DEBUG="$BASEBIN_DEBUG" \
    SIGNATURE_VERIFIER_SOURCE="$SIGNATURE_VERIFIER_SOURCE" \
    basebin.tar

log_stage "building BaseBin Debian packages"
"$GNU_MAKE" \
    -C "$WORK_DIRECTORY/Vendor/Dopamine/Packages" \
    ARCHS="arm64 arm64e" \
    MIN_IOS_VERSION="$MIN_IOS_VERSION" \
    RELAXIN_BASEBIN_DEBUG="$BASEBIN_DEBUG" \
    SIGNATURE_VERIFIER_SOURCE="$SIGNATURE_VERIFIER_SOURCE" \
    all

log_stage "building simulator runtime libraries"
"$GNU_MAKE" \
    -C "$WORK_DIRECTORY/Vendor/Dopamine/BaseBin" \
    MIN_IOS_VERSION="$MIN_IOS_VERSION" \
    RELAXIN_BASEBIN_DEBUG="$BASEBIN_DEBUG" \
    SIGNATURE_VERIFIER_SOURCE="$SIGNATURE_VERIFIER_SOURCE" \
    simulator-libs

log_stage "validating generated artifacts"
validate_build

log_stage "publishing generated artifacts"
publish_outputs
echo "note: [BaseBin] published resources to $OUTPUT_DIRECTORY"
