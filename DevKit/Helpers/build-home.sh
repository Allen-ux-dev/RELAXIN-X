#!/usr/bin/env bash

relaxin_project_identity() {
    local source_root="$1"
    local source_base="$source_root/SOURCE_BASE.txt"
    local zebra_identity="$source_root/ZEBRA_INTEGRATION.md"

    [[ -f "$source_base" ]] || {
        printf 'error: [BuildHome] missing %s\n' "$source_base" >&2
        return 1
    }
    [[ -f "$zebra_identity" ]] || {
        printf 'error: [BuildHome] missing %s\n' "$zebra_identity" >&2
        return 1
    }

    cat "$source_base"
    shasum -a 256 "$zebra_identity" | awk '{print $1}'
}

relaxin_cache_key() {
    local source_root="$1"
    local xcode_build="$2"
    local sdk_version="$3"

    {
        relaxin_project_identity "$source_root"
        printf 'xcode=%s\n' "$xcode_build"
        printf 'sdk=%s\n' "$sdk_version"
    } | shasum -a 256 | awk '{print $1}'
}

relaxin_sync_workspace() {
    local source_root="$1"
    local workspace_source="$2"

    command -v rsync >/dev/null 2>&1 || {
        printf 'error: [BuildHome] rsync is required\n' >&2
        return 1
    }

    mkdir -p "$workspace_source"
    rsync -a --delete \
        --exclude '/build/' \
        --exclude '/Output/' \
        --exclude '/DerivedData/' \
        --exclude '/.git/' \
        --exclude '.DS_Store' \
        "$source_root/" "$workspace_source/"
}
