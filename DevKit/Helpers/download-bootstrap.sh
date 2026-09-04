#!/bin/zsh
# Derived from Dopamine-lbr77 tooling; see DevKit/Bootstrap/LICENSE.md.

set -euo pipefail

if (( $# != 1 )); then
	print -u2 "usage: $0 <output.tar.zst>"
	exit 64
fi

bootstrap_version="1900"
output_archive="$1"
source_revision="c29323645b9c683a6bb7eab1c892fdeb1c47b6fd"
expected_sha256="420f72d1a62c9f884733cdefc596728469482a48858ec7ceca4d3ab2d3cba56c"

if [[ -f "$output_archive" ]]; then
	actual_sha256="$(shasum -a 256 "$output_archive" | awk '{ print $1 }')"
	if [[ "$actual_sha256" == "$expected_sha256" ]]; then
		print "RootHide bootstrap $bootstrap_version source is up to date"
		exit 0
	fi
fi

source_url="https://raw.githubusercontent.com/roothide/Dopamine2-roothide/$source_revision/Application/Dopamine/Resources/bootstrap_$bootstrap_version.tar.zst"
temporary_archive="$output_archive.tmp.$$"
trap 'rm -f -- "$temporary_archive"' EXIT

mkdir -p "${output_archive:h}"
print "downloading RootHide bootstrap $bootstrap_version"
curl \
	--fail \
	--location \
	--retry 3 \
	--retry-delay 2 \
	--output "$temporary_archive" \
	"$source_url"

actual_sha256="$(shasum -a 256 "$temporary_archive" | awk '{ print $1 }')"
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
	print -u2 "bootstrap $bootstrap_version SHA-256 mismatch"
	print -u2 "expected: $expected_sha256"
	print -u2 "actual:   $actual_sha256"
	exit 65
fi

mv -f -- "$temporary_archive" "$output_archive"
print "downloaded RootHide bootstrap $bootstrap_version: $output_archive"
