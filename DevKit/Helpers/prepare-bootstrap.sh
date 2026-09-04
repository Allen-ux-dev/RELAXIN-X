#!/bin/zsh
# Derived from Dopamine-lbr77 tooling; see DevKit/Bootstrap/LICENSE.md.

set -euo pipefail

source "${0:A:h:h:h}/.env.sh"

if (( $# != 4 )); then
	print -u2 "usage: $0 <input.tar.zst> <output.tar.zst> <signature-verifier> <uicache-policy>"
	exit 64
fi

"${0:A:h}/check-tools.sh" zstd gtar

input_archive="$1"
output_archive="$2"
signature_verifier="$3"
uicache_policy_path="$4"
work_directory="$(mktemp -d "${TMPDIR:-/tmp}/relaxin-bootstrap.XXXXXX")"
temporary_archive="$output_archive.tmp.$$"
trap 'rm -rf -- "$work_directory"; rm -f -- "$temporary_archive"' EXIT

bootstrap_progress()
{
	print -r -- "note: [Bootstrap] $*"
}

plutil -lint "$uicache_policy_path" >/dev/null
uicache_policy="$(
	plutil -extract 'com\.apple\.CommCenter\.fine-grained' \
		json -o - "$uicache_policy_path"
)"

mkdir -p "$work_directory/root" "$work_directory/reference" "${output_archive:h}"
bootstrap_progress "extracting source archive"
zstd -q -d -c "$input_archive" \
	| gtar --same-permissions -xf - -C "$work_directory/root"
zstd -q -d -c "$input_archive" \
	| gtar --same-permissions -xf - -C "$work_directory/reference"

bootstrap_progress "scanning Mach-O files"
macho_manifest="$work_directory/macho-files.list"
typeset -i macho_count=0
while IFS= read -r -d '' binary_path; do
	binary_type="$(file -b "$binary_path")"
	if [[ "$binary_type" == *Mach-O* ]]; then
		printf '%s\0%s\0' "$binary_path" "$binary_type" >> "$macho_manifest"
		(( macho_count += 1 ))
	fi
done < <(find "$work_directory/root" -type f -print0)

if (( macho_count == 0 )); then
	print -u2 "bootstrap contains no Mach-O files: $input_archive"
	exit 65
fi
bootstrap_progress "found $macho_count Mach-O files"

typeset -i signed_count=0
while IFS= read -r -d '' binary_path && IFS= read -r -d '' binary_type; do
	(( signed_count += 1 ))
	relative_path="${binary_path#$work_directory/root/}"
	if (( signed_count == 1 || signed_count == macho_count || signed_count % 10 == 0 )); then
		bootstrap_progress "signing $signed_count / $macho_count: $relative_path"
	fi

	"$signature_verifier" "$binary_path"

	entitlements_path="$work_directory/current.entitlements"
	/usr/bin/codesign -d --entitlements :- -- "$binary_path" \
		> "$entitlements_path" 2>/dev/null

	use_explicit_entitlements=false
	if [[ "$binary_type" == *executable* \
			&& -s "$entitlements_path" \
			&& "$(plutil -extract 'platform-application' \
				raw -o - "$entitlements_path" 2>/dev/null)" == "true" ]]; then
		if plutil -extract 'com\.apple\.private\.set-exception-port' \
				raw -o /dev/null "$entitlements_path" 2>/dev/null; then
			plutil -replace 'com\.apple\.private\.set-exception-port' \
				-bool true "$entitlements_path"
		else
			plutil -insert 'com\.apple\.private\.set-exception-port' \
				-bool true "$entitlements_path"
		fi
		use_explicit_entitlements=true
	fi

	if [[ "$relative_path" == "usr/bin/uicache" ]]; then
		if plutil -extract 'com\.apple\.CommCenter\.fine-grained' \
				raw -o /dev/null "$entitlements_path" 2>/dev/null; then
			plutil -replace 'com\.apple\.CommCenter\.fine-grained' \
				-json "$uicache_policy" "$entitlements_path"
		else
			plutil -insert 'com\.apple\.CommCenter\.fine-grained' \
				-json "$uicache_policy" "$entitlements_path"
		fi
		use_explicit_entitlements=true
	fi

	if [[ "$use_explicit_entitlements" == "true" ]]; then
		signing_output="$(/usr/bin/codesign \
			--force \
			--sign - \
			--timestamp=none \
			--preserve-metadata=identifier,flags,runtime \
			--entitlements "$entitlements_path" \
			-- "$binary_path" 2>&1)" || {
			print -u2 "$signing_output"
			exit 65
		}
	else
		if ! signing_output="$(/usr/bin/codesign \
				--force \
				--sign - \
				--timestamp=none \
				--preserve-metadata=identifier,entitlements,flags,runtime \
				-- "$binary_path" 2>&1)"; then
			print -u2 "$signing_output"
			exit 65
		fi
	fi
	"$signature_verifier" "$binary_path"
	/usr/bin/codesign --verify --strict --all-architectures -- "$binary_path"
done < "$macho_manifest"

bootstrap_progress "restoring archive metadata"
while IFS= read -r -d '' reference_path; do
	relative_path="${reference_path#$work_directory/reference/}"
	chmod "$(stat -f '%Mp%Lp' "$reference_path")" "$work_directory/root/$relative_path"
	touch -r "$reference_path" "$work_directory/root/$relative_path"
done < <(find "$work_directory/reference" -type f -print0)
while IFS= read -r -d '' reference_path; do
	relative_path="${reference_path#$work_directory/reference/}"
	chmod "$(stat -f '%Mp%Lp' "$reference_path")" "$work_directory/root/$relative_path"
	touch -r "$reference_path" "$work_directory/root/$relative_path"
done < <(
	find "$work_directory/reference" \
		-type d ! -path "$work_directory/reference" -print0 \
		| sort -zr
)
chmod "$(stat -f '%Mp%Lp' "$work_directory/reference")" "$work_directory/root"
touch -r "$work_directory/reference" "$work_directory/root"

if [[ ! -d "$work_directory/root/var/mobile" \
		|| -L "$work_directory/root/var/mobile" ]]; then
	print -u2 "bootstrap var/mobile is not a directory: $input_archive"
	exit 65
fi

bootstrap_progress "rebuilding archive"
uncompressed_archive="$work_directory/bootstrap.tar"
root_entries="$work_directory/root-entries.list"
mobile_entry="$work_directory/mobile-entry.list"
mobile_descendants="$work_directory/mobile-descendants.list"
(
	cd "$work_directory/root"
	find . \
		! -path './var/mobile' \
		! -path './var/mobile/*' \
		-print0 \
		| sort -z > "$root_entries"
	printf './var/mobile\0' > "$mobile_entry"
	find ./var/mobile -mindepth 1 -print0 \
		| sort -z > "$mobile_descendants"

	COPYFILE_DISABLE=1 gtar \
		--format=ustar \
		--no-xattrs \
		--no-recursion \
		--null \
		--owner=0 \
		--group=0 \
		-cf "$uncompressed_archive" \
		-T "$root_entries"
	COPYFILE_DISABLE=1 gtar \
		--format=ustar \
		--no-xattrs \
		--no-recursion \
		--null \
		--owner=501 \
		--group=501 \
		-rf "$uncompressed_archive" \
		-T "$mobile_entry"
	COPYFILE_DISABLE=1 gtar \
		--format=ustar \
		--no-xattrs \
		--no-recursion \
		--null \
		--owner=0 \
		--group=0 \
		-rf "$uncompressed_archive" \
		-T "$mobile_descendants"
)
bootstrap_progress "compressing archive with zstd"
zstd -q -19 -T0 "$uncompressed_archive" -o "$temporary_archive"

normalize_archive_metadata()
{
	local archive_path="$1"
	local manifest_path="$2"
	gtar --numeric-owner --full-time -tvf "$archive_path" \
		| awk '{
			mode = $1
			owner = $2
			date = $4
			time = $5
			$1 = $2 = $3 = $4 = $5 = ""
			sub(/^[[:space:]]+/, "")
			print mode "\t" owner "\t" date " " time "\t" $0
		}' \
		| LC_ALL=C sort > "$manifest_path"
}

require_archive_metadata()
{
	local archive_path="$1"
	local entry_path="$2"
	local expected_mode="$3"
	local expected_owner="$4"
	local actual_metadata
	actual_metadata="$(
		gtar --numeric-owner -tvf "$archive_path" \
			| awk -v entry="$entry_path" '
				$6 == entry {
					print $1 "\t" $2
					count += 1
				}
				END {
					if (count != 1) exit 1
				}
			'
	)" || {
		print -u2 "bootstrap metadata entry missing or duplicated: $entry_path"
		exit 65
	}
	if [[ "$actual_metadata" != "$expected_mode"$'\t'"$expected_owner" ]]; then
		print -u2 \
			"bootstrap metadata mismatch: $entry_path expected=$expected_mode,$expected_owner actual=${actual_metadata//$'\t'/,}"
		exit 65
	fi
}

bootstrap_progress "verifying archive metadata"
source_manifest="$work_directory/source-metadata"
prepared_manifest="$work_directory/prepared-metadata"
normalize_archive_metadata "$input_archive" "$source_manifest"
normalize_archive_metadata "$temporary_archive" "$prepared_manifest"
if ! cmp -s "$source_manifest" "$prepared_manifest"; then
	print -u2 "prepared bootstrap metadata differs from its source"
	diff -u "$source_manifest" "$prepared_manifest" >&2 || true
	exit 65
fi

for setuid_path in \
	./usr/bin/chpass \
	./usr/bin/su \
	./usr/bin/quota \
	./usr/bin/sudo \
	./usr/bin/login \
	./usr/bin/passwd \
	./usr/sbin/shshd; do
	require_archive_metadata \
		"$temporary_archive" "$setuid_path" "-rwsr-xr-x" "0/0"
done
require_archive_metadata \
	"$temporary_archive" "./tmp/" "drwxrwxrwt" "0/0"
require_archive_metadata \
	"$temporary_archive" "./var/lib/ex/" "drwxrwxrwt" "0/0"
require_archive_metadata \
	"$temporary_archive" "./var/mobile/" "drwxr-xr-x" "501/501"

mv -f -- "$temporary_archive" "$output_archive"
bootstrap_progress "finished: prepared $signed_count explicitly ad-hoc signed Mach-O files"
print "prepared $signed_count explicitly ad-hoc signed Mach-O files: $output_archive"
