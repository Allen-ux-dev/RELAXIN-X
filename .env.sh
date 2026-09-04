#!/bin/sh

# Shared host environment for interactive shells, Make, and Xcode shell phases.
# Source .env.sh; it intentionally does not change HOME until a build asks for
# an isolated cache with relaxin_prepare_build_environment.

_relaxin_prepend_path() {
    [ -d "$1" ] || return 0
    case ":${PATH-}:" in
        *":$1:"*) ;;
        *) PATH="$1${PATH:+:$PATH}" ;;
    esac
}

_relaxin_login_home="$(
    /usr/bin/dscacheutil -q user -a uid "$(/usr/bin/id -u)" |
        /usr/bin/awk '$1 == "dir:" { print $2; exit }'
)"

_relaxin_prepend_path /sbin
_relaxin_prepend_path /usr/sbin
_relaxin_prepend_path /bin
_relaxin_prepend_path /usr/bin
_relaxin_prepend_path "${_relaxin_login_home:+$_relaxin_login_home/.local/bin}"
_relaxin_prepend_path /usr/local/bin
_relaxin_prepend_path /opt/homebrew/bin
if [ -n "${ROOT_DIR-}" ] && [ -d "$ROOT_DIR/DevKit" ]; then
    _relaxin_root_dir="$ROOT_DIR"
elif [ -n "${SRCROOT-}" ] && [ -d "$SRCROOT/DevKit" ]; then
    _relaxin_root_dir="$SRCROOT"
else
    _relaxin_root_dir="$(pwd -P)"
fi
_relaxin_prepend_path "$_relaxin_root_dir/build/HostTools/bin"
export PATH

# Respect an explicit DEVELOPER_DIR. If xcode-select only points at Command Line
# Tools, select the sole installed Xcode without baking a version into scripts.
if [ -z "${DEVELOPER_DIR-}" ] &&
    ! /usr/bin/xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
    _relaxin_xcode_count=0
    _relaxin_xcode_candidate=
    for _relaxin_candidate in /Applications/Xcode*.app/Contents/Developer; do
        [ -d "$_relaxin_candidate" ] || continue
        _relaxin_xcode_count=$((_relaxin_xcode_count + 1))
        _relaxin_xcode_candidate="$_relaxin_candidate"
    done
    if [ "$_relaxin_xcode_count" -eq 1 ]; then
        DEVELOPER_DIR="$_relaxin_xcode_candidate"
        export DEVELOPER_DIR
    fi
fi

relaxin_prepare_build_environment() {
    if [ "$#" -ne 1 ] || [ -z "$1" ]; then
        echo "usage: relaxin_prepare_build_environment <cache-root>" >&2
        return 64
    fi

    local cache_root="$1"
    HOME="$cache_root/home"
    XDG_CACHE_HOME="$cache_root/xdg-cache"
    CLANG_MODULE_CACHE_PATH="$cache_root/ModuleCache.noindex"
    SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
    export HOME XDG_CACHE_HOME
    export CLANG_MODULE_CACHE_PATH SWIFTPM_MODULECACHE_OVERRIDE

    /bin/mkdir -p "$HOME" "$XDG_CACHE_HOME" "$CLANG_MODULE_CACHE_PATH"
}

unset _relaxin_login_home
unset _relaxin_xcode_count _relaxin_xcode_candidate _relaxin_candidate
unset _relaxin_root_dir
unset -f _relaxin_prepend_path
