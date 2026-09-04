#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-}"
if [[ -z "$ROOT_DIR" || ! -d "$ROOT_DIR" ]]; then
    echo "error: [Prebuild] expected workspace root argument" >&2
    exit 64
fi

required=(
    "build/BootstrapResources/bootstrap_1900.tar.zst"
    "build/BaseBinResources/basebin.tar"
    "build/BaseBinResources/basebin.tc"
    "build/BaseBinResources/libroot.deb"
    "build/BaseBinResources/libkrw-dopamine.deb"
    "build/BaseBinResources/basebin-link.deb"
    "build/BaseBinResources/libjailbreak.dylib"
    "build/BaseBinResources/libxpf.dylib"
    "build/BaseBinResources/libchoma.dylib"
)

for relative in "${required[@]}"; do
    if [[ ! -s "$ROOT_DIR/$relative" ]]; then
        echo "error: [Prebuild] missing $relative" >&2
        exit 1
    fi
done

header_tree="$ROOT_DIR/build/BaseBinWork/Vendor/Dopamine/BaseBin/.include"
if [[ ! -d "$header_tree" ]]; then
    echo "error: [Prebuild] missing build/BaseBinWork/Vendor/Dopamine/BaseBin/.include" >&2
    exit 1
fi

echo "note: [Prebuild] all required resources are ready"
