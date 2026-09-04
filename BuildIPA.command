#!/bin/bash

set -Eeuo pipefail

SOURCE_ROOT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
ROOT_DIR="$SOURCE_ROOT_DIR"
BUILD_ROOT_DIR="$SOURCE_ROOT_DIR"
BUILD_WORKSPACE_DIR=""
cd "$SOURCE_ROOT_DIR"

OUTPUT_DIR="$SOURCE_ROOT_DIR/Output"
OUTPUT_IPA="$OUTPUT_DIR/RELAXIN-X.ipa"
OUTPUT_SHA256="$OUTPUT_IPA.sha256.txt"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/relaxin-x-ipa.XXXXXX")"
STAGING_IPA="$STAGING_DIR/RELAXIN-X.ipa"

TRUSTCACHE_REPOSITORY="https://github.com/CRKatri/trustcache.git"
TRUSTCACHE_COMMIT="aa0e8847529cf76576fce8d2dbc9e088c8f1a0df"
REQUIRED_BUILD_TOOLS=(rg zstd gtar dpkg-deb ldid trustcache)
CLEAN_BUILD=0

cleanup() {
    rm -rf "$STAGING_DIR"
    if [[ "${BUILD_LOCK_ACQUIRED:-0}" -eq 1 && -n "${RELAXIN_BUILD_LOCK_DIRECTORY:-}" ]]; then
        rm -rf "$RELAXIN_BUILD_LOCK_DIRECTORY"
        BUILD_LOCK_ACQUIRED=0
    fi
}
trap cleanup EXIT

fail() {
    printf '\n[ERROR] %s\n' "$*" >&2
    exit 1
}

step() {
    printf '\n== %s ==\n' "$*"
}

for argument in "$@"; do
    case "$argument" in
        --clean) CLEAN_BUILD=1 ;;
        *) fail "Unknown argument: $argument (supported: --clean)" ;;
    esac
done

step "RELAXIN-X IPA Build"
printf 'Source: %s\n' "$ROOT_DIR"

[[ "$(uname -s)" == "Darwin" ]] || fail "This build command must run on macOS with Xcode installed."
command -v xcode-select >/dev/null 2>&1 || fail "xcode-select is unavailable. Install Xcode first."
command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild is unavailable. Install the full Xcode app."
command -v xcrun >/dev/null 2>&1 || fail "xcrun is unavailable. Install Xcode command-line tools."
command -v make >/dev/null 2>&1 || fail "make is unavailable."
command -v unzip >/dev/null 2>&1 || fail "unzip is unavailable."
command -v shasum >/dev/null 2>&1 || fail "shasum is unavailable."
[[ -x /usr/libexec/PlistBuddy ]] || fail "/usr/libexec/PlistBuddy is unavailable."

BUILD_HOME_HELPER="$SOURCE_ROOT_DIR/DevKit/Helpers/build-home.sh"
[[ -r "$BUILD_HOME_HELPER" ]] || fail "Missing build-home helper: $BUILD_HOME_HELPER"
. "$BUILD_HOME_HELPER"

XCODE_BUILD_VERSION="$(xcodebuild -version 2>/dev/null | awk '/Build version/ { print $3; exit }')"
[[ -n "$XCODE_BUILD_VERSION" ]] || fail "Could not determine the active Xcode build version."
IPHONEOS_SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null)"
[[ -n "$IPHONEOS_SDK_VERSION" ]] || fail "Could not determine the active iPhoneOS SDK version."
RELAXIN_CACHE_KEY="$(relaxin_cache_key "$SOURCE_ROOT_DIR" "$XCODE_BUILD_VERSION" "$IPHONEOS_SDK_VERSION")"
[[ -n "$RELAXIN_CACHE_KEY" ]] || fail "Could not derive the RELAXIN-X build cache key."

RELAXIN_BUILD_HOME="${HOME}/Library/Caches/RelaxinBuild/$RELAXIN_CACHE_KEY"
RELAXIN_WORKSPACE_SOURCE="$RELAXIN_BUILD_HOME/workspace/source"
RELAXIN_DERIVED_DATA="$RELAXIN_BUILD_HOME/DerivedData"
RELAXIN_LOG_DIRECTORY="$RELAXIN_BUILD_HOME/Logs"
HOST_TOOLS_ROOT="$RELAXIN_BUILD_HOME/HostTools"
HOST_TOOLS_BIN="$HOST_TOOLS_ROOT/bin"
TRUSTCACHE_SOURCE_DIR="$HOST_TOOLS_ROOT/src/trustcache"
PERSISTENT_CACHE_ROOT="$RELAXIN_BUILD_HOME"
PERSISTENT_BASEBIN_CACHE="$RELAXIN_BUILD_HOME/BaseBin/CompilerCache"
PERSISTENT_BASEBIN_RESOURCES="$RELAXIN_BUILD_HOME/BaseBin/Resources"
PERSISTENT_BOOTSTRAP_SOURCES="$RELAXIN_BUILD_HOME/Bootstrap/Sources"
PERSISTENT_BOOTSTRAP_RESOURCES="$RELAXIN_BUILD_HOME/Bootstrap/Resources"
PERSISTENT_BOOTSTRAP_TOOLS="$RELAXIN_BUILD_HOME/Bootstrap/Tools"
RELAXIN_BASEBIN_CACHE_DIRECTORY="$PERSISTENT_BASEBIN_CACHE"
RELAXIN_BASEBIN_LOCK_DIRECTORY="$RELAXIN_BUILD_HOME/Locks/BaseBinResources.lock"
RELAXIN_BUILD_LOCK_DIRECTORY="$RELAXIN_BUILD_HOME/Locks/Build.lock"
export RELAXIN_BASEBIN_CACHE_DIRECTORY RELAXIN_BASEBIN_LOCK_DIRECTORY

BUILD_LOCK_ACQUIRED=0
acquire_build_lock() {
    local attempts=0
    local owner_pid=""
    while ! mkdir "$RELAXIN_BUILD_LOCK_DIRECTORY" 2>/dev/null; do
        owner_pid=""
        if [[ -f "$RELAXIN_BUILD_LOCK_DIRECTORY/pid" ]]; then
            owner_pid="$(cat "$RELAXIN_BUILD_LOCK_DIRECTORY/pid" 2>/dev/null || true)"
        fi
        if [[ "$owner_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$owner_pid" 2>/dev/null; then
            rm -rf "$RELAXIN_BUILD_LOCK_DIRECTORY"
            continue
        fi
        if (( attempts == 0 )); then
            printf 'Waiting for active RELAXIN-X build for cache key %s\n' "$RELAXIN_CACHE_KEY"
        fi
        if (( attempts >= 300 )); then
            fail "Timed out waiting for build lock: $RELAXIN_BUILD_LOCK_DIRECTORY"
        fi
        attempts=$((attempts + 1))
        sleep 1
    done
    BUILD_LOCK_ACQUIRED=1
    printf '%s\n' "$$" >"$RELAXIN_BUILD_LOCK_DIRECTORY/pid"
}

mkdir -p "$HOST_TOOLS_BIN" "$RELAXIN_LOG_DIRECTORY" "$RELAXIN_BUILD_HOME/Locks"
acquire_build_lock
export PATH="$HOST_TOOLS_BIN:$PATH"

find_homebrew() {
    local brew_bin=""
    if command -v brew >/dev/null 2>&1; then
        brew_bin="$(command -v brew)"
    elif [[ -x /opt/homebrew/bin/brew ]]; then
        brew_bin="/opt/homebrew/bin/brew"
    elif [[ -x /usr/local/bin/brew ]]; then
        brew_bin="/usr/local/bin/brew"
    fi
    printf '%s' "$brew_bin"
}

brew_formula_for_tool() {
    case "$1" in
        rg) printf '%s' ripgrep ;;
        zstd) printf '%s' zstd ;;
        gtar) printf '%s' gnu-tar ;;
        dpkg-deb) printf '%s' dpkg ;;
        ldid) printf '%s' ldid ;;
        *) return 1 ;;
    esac
}

install_missing_brew_dependencies() {
    local brew_bin="$1"
    shift
    local formulas=("$@")
    [[ "${#formulas[@]}" -gt 0 ]] || return 0

    step "Installing missing Homebrew build dependencies"
    printf 'Homebrew: %s\n' "$brew_bin"
    printf 'Formulae:'
    printf ' %s' "${formulas[@]}"
    printf '\n'

    local answer=""
    if [[ -t 0 ]]; then
        read -r -p "Install these build dependencies now? [Y/n] " answer
    else
        fail "Missing Homebrew dependencies: ${formulas[*]}. Run: $brew_bin install --no-ask ${formulas[*]}"
    fi

    case "${answer:-Y}" in
        Y|y|YES|Yes|yes)
            HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 \
                "$brew_bin" install --no-ask "${formulas[@]}" \
                || fail "Homebrew could not install all required build dependencies."
            ;;
        *)
            fail "Required build dependencies were not installed."
            ;;
    esac
}

trustcache_version_ok() {
    local tool="$1"
    [[ -x "$tool" ]] || return 1
    local version_output
    version_output="$({ "$tool" --version || true; } 2>&1)"
    grep -Fq 'v2.0' <<<"$version_output"
}

prepare_trustcache() {
    if command -v trustcache >/dev/null 2>&1 && trustcache_version_ok "$(command -v trustcache)"; then
        printf 'trustcache: %s\n' "$(command -v trustcache)"
        return 0
    fi

    local local_tool="$HOST_TOOLS_BIN/trustcache"
    if trustcache_version_ok "$local_tool"; then
        printf 'trustcache: %s (cached build-home tool)\n' "$local_tool"
        return 0
    fi

    local legacy_tool="$SOURCE_ROOT_DIR/build/HostTools/bin/trustcache"
    if [[ "$legacy_tool" != "$local_tool" ]] && trustcache_version_ok "$legacy_tool"; then
        mkdir -p "$HOST_TOOLS_BIN"
        /usr/bin/install -m 755 "$legacy_tool" "$local_tool"
        printf 'trustcache: %s (migrated from source-local cache)\n' "$local_tool"
        return 0
    fi

    local brew_bin
    brew_bin="$(find_homebrew)"
    [[ -n "$brew_bin" ]] || fail "Homebrew is required to provide libmd for the project-local trustcache build."
    export PATH="$(dirname "$brew_bin"):$PATH"

    if ! "$brew_bin" list --versions libmd >/dev/null 2>&1; then
        fail "libmd is required to build trustcache. Re-run BuildIPA.command and allow the dependency preflight to install it."
    fi

    command -v git >/dev/null 2>&1 || fail "git is required to fetch trustcache source."
    command -v make >/dev/null 2>&1 || fail "make is required to build trustcache."
    command -v xcrun >/dev/null 2>&1 || fail "xcrun is required to build trustcache."

    step "Preparing project-local trustcache"
    printf 'Source: %s\n' "$TRUSTCACHE_REPOSITORY"
    printf 'Pinned commit: %s\n' "$TRUSTCACHE_COMMIT"

    mkdir -p "$(dirname "$TRUSTCACHE_SOURCE_DIR")"
    rm -rf "$TRUSTCACHE_SOURCE_DIR.tmp"
    if [[ ! -d "$TRUSTCACHE_SOURCE_DIR/.git" ]]; then
        rm -rf "$TRUSTCACHE_SOURCE_DIR"
        git clone --quiet "$TRUSTCACHE_REPOSITORY" "$TRUSTCACHE_SOURCE_DIR.tmp" \
            || fail "Could not clone trustcache source."
        mv "$TRUSTCACHE_SOURCE_DIR.tmp" "$TRUSTCACHE_SOURCE_DIR"
    fi

    git -C "$TRUSTCACHE_SOURCE_DIR" fetch --quiet origin \
        || fail "Could not refresh trustcache source."
    git -C "$TRUSTCACHE_SOURCE_DIR" checkout --quiet --detach "$TRUSTCACHE_COMMIT" \
        || fail "Could not check out pinned trustcache commit."
    [[ "$(git -C "$TRUSTCACHE_SOURCE_DIR" rev-parse HEAD)" == "$TRUSTCACHE_COMMIT" ]] \
        || fail "trustcache source did not resolve to the pinned commit."

    local libmd_prefix macos_sdk clang_bin make_bin jobs
    libmd_prefix="$($brew_bin --prefix libmd)" \
        || fail "Could not resolve Homebrew libmd prefix."
    [[ -d "$libmd_prefix/include" && -d "$libmd_prefix/lib" ]] \
        || fail "Homebrew libmd installation is incomplete: $libmd_prefix"
    macos_sdk="$(xcrun --sdk macosx --show-sdk-path)" \
        || fail "The macOS SDK is unavailable for the trustcache host build."
    [[ -d "$macos_sdk" ]] \
        || fail "The reported macOS SDK path does not exist: $macos_sdk"
    clang_bin="$(xcrun --sdk macosx --find clang)" || fail "Xcode clang is unavailable."
    printf 'macOS SDK: %s\n' "$macos_sdk"
    printf 'Host clang: %s\n' "$clang_bin"
    printf 'libmd: %s\n' "$libmd_prefix"
    if command -v gmake >/dev/null 2>&1; then
        make_bin="$(command -v gmake)"
    else
        make_bin="$(command -v make)"
    fi
    jobs="$(/usr/sbin/sysctl -n hw.ncpu 2>/dev/null || printf '2')"

    "$make_bin" -C "$TRUSTCACHE_SOURCE_DIR" clean >/dev/null 2>&1 || true
    env \
        CC="$clang_bin" \
        CPPFLAGS="-isysroot $macos_sdk -I$libmd_prefix/include" \
        LDFLAGS="-isysroot $macos_sdk -L$libmd_prefix/lib" \
        "$make_bin" -C "$TRUSTCACHE_SOURCE_DIR" -j"$jobs" trustcache \
        || fail "Failed to build trustcache from the pinned source."

    [[ -x "$TRUSTCACHE_SOURCE_DIR/trustcache" ]] \
        || fail "trustcache build finished without an executable."

    local temp_tool="$HOST_TOOLS_BIN/.trustcache.tmp.$$"
    /usr/bin/install -m 755 "$TRUSTCACHE_SOURCE_DIR/trustcache" "$temp_tool"
    if ! trustcache_version_ok "$temp_tool"; then
        rm -f "$temp_tool"
        fail "The built trustcache executable did not report v2.0."
    fi
    mv -f "$temp_tool" "$local_tool"
    hash -r 2>/dev/null || true
    printf 'trustcache: %s\n' "$local_tool"
}

verify_relaxin_toolchain() {
    local checker="$ROOT_DIR/DevKit/Helpers/check-tools.sh"
    [[ -x "$checker" ]] || fail "Missing RELAXIN-X tool checker: $checker"
    "$checker" xcode rg zstd gtar trustcache dpkg-deb ldid git rsync shasum \
        || fail "RELAXIN-X build-tool verification failed after dependency preparation."

    local make_bin
    if command -v gmake >/dev/null 2>&1; then
        make_bin="$(command -v gmake)"
    else
        make_bin="$(command -v make)"
    fi
    "$make_bin" --version | grep -Fq 'GNU Make' \
        || fail "RELAXIN-X BaseBin requires GNU Make; found: $make_bin"
}

prepare_build_dependencies() {
    local brew_bin
    brew_bin="$(find_homebrew)"

    local missing_tools=()
    local formulas=()
    local tool formula existing

    for tool in "${REQUIRED_BUILD_TOOLS[@]}"; do
        [[ "$tool" == "trustcache" ]] && continue
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
            formula="$(brew_formula_for_tool "$tool")" \
                || fail "No Homebrew formula mapping for required tool: $tool"
            existing=0
            local current
            for current in "${formulas[@]-}"; do
                [[ "$current" == "$formula" ]] && existing=1 && break
            done
            [[ "$existing" -eq 1 ]] || formulas+=("$formula")
        fi
    done

    local trustcache_ready=0
    if command -v trustcache >/dev/null 2>&1 && trustcache_version_ok "$(command -v trustcache)"; then
        trustcache_ready=1
    elif trustcache_version_ok "$HOST_TOOLS_BIN/trustcache"; then
        trustcache_ready=1
    fi

    if [[ "$trustcache_ready" -eq 0 ]]; then
        missing_tools+=("trustcache")
        if [[ -z "$brew_bin" ]] || ! "$brew_bin" list --versions libmd >/dev/null 2>&1; then
            formulas+=("libmd")
        fi
    fi

    if [[ "${#missing_tools[@]}" -gt 0 ]]; then
        step "Missing build dependencies"
        printf 'Missing commands:'
        printf ' %s' "${missing_tools[@]}"
        printf '\n'
    fi

    if [[ "${#formulas[@]}" -gt 0 ]]; then
        [[ -n "$brew_bin" ]] \
            || fail "Homebrew is required for missing build dependencies: ${formulas[*]}"
        export PATH="$(dirname "$brew_bin"):$PATH"
        install_missing_brew_dependencies "$brew_bin" "${formulas[@]}"
    fi

    # Homebrew links formula executables into its bin directory. Refresh PATH
    # and the shell command cache before preparing the one project-local tool.
    if [[ -n "$brew_bin" ]]; then
        export PATH="$(dirname "$brew_bin"):$PATH"
    fi
    hash -r 2>/dev/null || true

    prepare_trustcache
    verify_relaxin_toolchain
}


prepare_stable_build_workspace() {
    command -v rsync >/dev/null 2>&1 || fail "rsync is required to synchronize the stable build workspace."

    step "Preparing stable build workspace"
    printf 'Original source: %s\n' "$SOURCE_ROOT_DIR"
    printf 'Build cache key: %s\n' "$RELAXIN_CACHE_KEY"
    printf 'Build home: %s\n' "$RELAXIN_BUILD_HOME"

    mkdir -p "$RELAXIN_BUILD_HOME/workspace"
    relaxin_sync_workspace "$SOURCE_ROOT_DIR" "$RELAXIN_WORKSPACE_SOURCE" \
        || fail "Could not synchronize the source into the stable build workspace."

    BUILD_WORKSPACE_DIR="$RELAXIN_WORKSPACE_SOURCE"
    BUILD_ROOT_DIR="$RELAXIN_WORKSPACE_SOURCE"
    mkdir -p "$BUILD_ROOT_DIR/build"
    rm -rf "$BUILD_ROOT_DIR/build/HostTools"
    ln -s "$HOST_TOOLS_ROOT" "$BUILD_ROOT_DIR/build/HostTools"

    [[ -f "$BUILD_ROOT_DIR/Makefile" ]] || fail "Build workspace is missing Makefile."
    [[ -x "$BUILD_ROOT_DIR/DevKit/Helpers/check-tools.sh" ]] \
        || fail "Build workspace is missing the RELAXIN-X tool checker."
    [[ -x "$BUILD_ROOT_DIR/build/HostTools/bin/trustcache" ]] \
        || fail "Build workspace is missing the prepared build-home trustcache."

    printf 'Build workspace: %s\n' "$BUILD_ROOT_DIR"
}

migrate_directory_cache() {
    local existing_path="$1"
    local persistent_path="$2"
    local label="$3"

    [[ -d "$existing_path" && ! -L "$existing_path" ]] || return 0
    mkdir -p "$persistent_path"
    if [[ -n "$(find "$persistent_path" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
        return 0
    fi
    rsync -a "$existing_path/" "$persistent_path/" \
        || fail "Could not migrate existing $label cache into the build home."
}

migrate_legacy_bootstrap_caches() {
    local source_path
    for source_path in \
        "$SOURCE_ROOT_DIR/build/BootstrapSources" \
        "$SOURCE_ROOT_DIR/build/PersistentCache/BootstrapSources"; do
        migrate_directory_cache "$source_path" "$PERSISTENT_BOOTSTRAP_SOURCES" "BootstrapSources"
    done
    for source_path in \
        "$SOURCE_ROOT_DIR/build/BootstrapResources" \
        "$SOURCE_ROOT_DIR/build/PersistentCache/BootstrapResources"; do
        migrate_directory_cache "$source_path" "$PERSISTENT_BOOTSTRAP_RESOURCES" "BootstrapResources"
    done
    for source_path in \
        "$SOURCE_ROOT_DIR/build/Tools" \
        "$SOURCE_ROOT_DIR/build/PersistentCache/BootstrapTools"; do
        migrate_directory_cache "$source_path" "$PERSISTENT_BOOTSTRAP_TOOLS" "BootstrapTools"
    done
}

prepare_persistent_build_cache() {
    step "Preparing persistent build caches"

    mkdir -p \
        "$PERSISTENT_BASEBIN_CACHE" \
        "$PERSISTENT_BASEBIN_RESOURCES" \
        "$PERSISTENT_BOOTSTRAP_SOURCES" \
        "$PERSISTENT_BOOTSTRAP_RESOURCES" \
        "$PERSISTENT_BOOTSTRAP_TOOLS" \
        "$RELAXIN_BUILD_HOME/Locks" \
        "$RELAXIN_LOG_DIRECTORY" \
        "$BUILD_ROOT_DIR/build"

    migrate_legacy_bootstrap_caches

    rm -rf \
        "$BUILD_ROOT_DIR/build/BaseBinCaches" \
        "$BUILD_ROOT_DIR/build/BaseBinResources" \
        "$BUILD_ROOT_DIR/build/BootstrapSources" \
        "$BUILD_ROOT_DIR/build/BootstrapResources" \
        "$BUILD_ROOT_DIR/build/Tools"
    ln -s "$PERSISTENT_BASEBIN_CACHE" "$BUILD_ROOT_DIR/build/BaseBinCaches"
    ln -s "$PERSISTENT_BASEBIN_RESOURCES" "$BUILD_ROOT_DIR/build/BaseBinResources"
    ln -s "$PERSISTENT_BOOTSTRAP_SOURCES" "$BUILD_ROOT_DIR/build/BootstrapSources"
    ln -s "$PERSISTENT_BOOTSTRAP_RESOURCES" "$BUILD_ROOT_DIR/build/BootstrapResources"
    ln -s "$PERSISTENT_BOOTSTRAP_TOOLS" "$BUILD_ROOT_DIR/build/Tools"

    printf 'BaseBin compiler cache: %s\n' "$PERSISTENT_BASEBIN_CACHE"
    printf 'BaseBin resources: %s\n' "$PERSISTENT_BASEBIN_RESOURCES"
    printf 'Bootstrap source cache: %s\n' "$PERSISTENT_BOOTSTRAP_SOURCES"
    printf 'Bootstrap resource cache: %s\n' "$PERSISTENT_BOOTSTRAP_RESOURCES"
    printf 'Bootstrap tool cache: %s\n' "$PERSISTENT_BOOTSTRAP_TOOLS"
    printf 'DerivedData: %s\n' "$RELAXIN_DERIVED_DATA"
    printf 'Logs: %s\n' "$RELAXIN_LOG_DIRECTORY"
}

step "Checking build dependencies"
prepare_build_dependencies

prepare_stable_build_workspace
export PATH="$BUILD_ROOT_DIR/build/HostTools/bin:$PATH"
hash -r 2>/dev/null || true

"$BUILD_ROOT_DIR/DevKit/Helpers/check-tools.sh" \
    xcode rg zstd gtar trustcache dpkg-deb ldid git rsync shasum \
    || fail "Stable build workspace failed tool verification."

step "Checking Xcode and iPhoneOS SDK"
DEVELOPER_PATH="$(xcode-select -p 2>/dev/null)" || fail "No active Xcode developer directory. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
printf 'Developer: %s\n' "$DEVELOPER_PATH"
xcodebuild -version || fail "Xcode is not usable. Open Xcode once and accept its license/components."
IPHONEOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)" || fail "The iPhoneOS SDK is unavailable. Select the full Xcode installation with xcode-select."
[[ -d "$IPHONEOS_SDK" ]] || fail "The reported iPhoneOS SDK path does not exist: $IPHONEOS_SDK"
printf 'iPhoneOS SDK: %s\n' "$IPHONEOS_SDK"
printf 'iPhoneOS SDK version: %s\n' "$IPHONEOS_SDK_VERSION"

APP_VERSION="$(make -C "$BUILD_ROOT_DIR" --no-print-directory print-version)" || fail "Could not read the RELAXIN-X version."
[[ -n "$APP_VERSION" ]] || fail "RELAXIN-X MARKETING_VERSION is empty."
printf 'RELAXIN-X version: %s\n' "$APP_VERSION"

mkdir -p "$OUTPUT_DIR"
prepare_persistent_build_cache

if [[ "$CLEAN_BUILD" -eq 1 ]]; then
    step "Cleaning current build-home state"
    rm -rf "$RELAXIN_DERIVED_DATA" "$BUILD_ROOT_DIR/build/BaseBinWork" "$PERSISTENT_BASEBIN_RESOURCES"
    mkdir -p "$RELAXIN_DERIVED_DATA" "$PERSISTENT_BASEBIN_RESOURCES"
fi

step "Preparing Bootstrap"
make -C "$BUILD_ROOT_DIR" bootstrap-resources DERIVED_DATA="$RELAXIN_DERIVED_DATA"

step "Preparing BaseBin"
"$BUILD_ROOT_DIR/DevKit/Helpers/build-basebin-resources.sh"

step "Verifying prebuilt resources"
"$BUILD_ROOT_DIR/DevKit/Helpers/verify-prebuilt-resources.sh" "$BUILD_ROOT_DIR"

step "Building unsigned IPA"
XCBUILD_LOG_DIR="$RELAXIN_LOG_DIRECTORY" \
RELAXIN_BUILD_HOME="$RELAXIN_BUILD_HOME" \
RELAXIN_WORKSPACE_SOURCE="$RELAXIN_WORKSPACE_SOURCE" \
make -C "$BUILD_ROOT_DIR" ipa IPA_OUTPUT="$STAGING_IPA" DERIVED_DATA="$RELAXIN_DERIVED_DATA"
[[ -s "$STAGING_IPA" ]] || fail "The build completed without producing an IPA."

step "Validating IPA archive"
unzip -tq "$STAGING_IPA" >/dev/null || fail "The generated IPA archive is corrupt."
ARCHIVE_MEMBERS="$(unzip -Z1 "$STAGING_IPA")" || fail "Could not read the IPA archive directory."

INFO_COUNT="$(printf '%s\n' "$ARCHIVE_MEMBERS" | awk -F/ 'NF == 3 && $1 == "Payload" && $2 ~ /[.]app$/ && $3 == "Info.plist" { count += 1 } END { print count + 0 }')"
[[ "$INFO_COUNT" == "1" ]] || fail "Expected exactly one top-level Payload/*.app/Info.plist, found $INFO_COUNT."

INFO_MEMBER="$(printf '%s\n' "$ARCHIVE_MEMBERS" | awk -F/ 'NF == 3 && $1 == "Payload" && $2 ~ /[.]app$/ && $3 == "Info.plist" { print; exit }')"
APP_MEMBER="${INFO_MEMBER%/Info.plist}"
INFO_PLIST="$STAGING_DIR/Info.plist"
unzip -p "$STAGING_IPA" "$INFO_MEMBER" > "$INFO_PLIST" || fail "Could not extract Info.plist for validation."
[[ -s "$INFO_PLIST" ]] || fail "The packaged Info.plist is empty."

CF_BUNDLE_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST" 2>/dev/null)" || fail "Info.plist is missing CFBundleExecutable."
[[ -n "$CF_BUNDLE_EXECUTABLE" ]] || fail "CFBundleExecutable is empty."
printf '%s\n' "$ARCHIVE_MEMBERS" | grep -Fxq "$APP_MEMBER/$CF_BUNDLE_EXECUTABLE" || fail "IPA is missing the main executable: $CF_BUNDLE_EXECUTABLE"

if printf '%s\n' "$ARCHIVE_MEMBERS" | grep -Fq "$APP_MEMBER/_CodeSignature/"; then
    fail "IPA unexpectedly contains _CodeSignature signing material."
fi
if printf '%s\n' "$ARCHIVE_MEMBERS" | grep -Fxq "$APP_MEMBER/embedded.mobileprovision"; then
    fail "IPA unexpectedly contains embedded.mobileprovision."
fi
if printf '%s\n' "$ARCHIVE_MEMBERS" | grep -Eq '(^|/)(__MACOSX|[.]DS_Store)(/|$)'; then
    fail "IPA contains macOS metadata."
fi

step "Publishing verified IPA"
TEMP_SHA256="$STAGING_DIR/RELAXIN-X.ipa.sha256.txt"
IPA_SHA256="$(shasum -a 256 "$STAGING_IPA" | awk '{ print $1 }')"
printf '%s  %s\n' "$IPA_SHA256" "$(basename "$OUTPUT_IPA")" > "$TEMP_SHA256"
mv -f "$STAGING_IPA" "$OUTPUT_IPA"
mv -f "$TEMP_SHA256" "$OUTPUT_SHA256"
cat "$OUTPUT_SHA256"

printf '\nSUCCESS\n'
printf 'IPA:    %s\n' "$OUTPUT_IPA"
printf 'SHA256: %s\n' "$OUTPUT_SHA256"
printf '\nThis IPA is intentionally unsigned. Sign/install it with the method appropriate for your device environment.\n'
