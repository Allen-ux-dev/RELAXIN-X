#!/usr/bin/env bash
#
# Enforce that RelaxinEngine stays unlocalized.
#
# Framework diagnostics, stage names, and NSError payloads must remain fixed
# English literals. Localization belongs in the app target only — never via
# NSLocalizedString, localizedStringWithFormat, or a framework string catalog.
# NSLocalizedDescriptionKey and related NSError user-info keys remain allowed.

set -u -o pipefail

ROOT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENGINE_DIRECTORY="$ROOT_DIRECTORY/RelaxinEngine"

if ! command -v rg >/dev/null 2>&1; then
    echo "error: engine localization check requires rg" >&2
    exit 69
fi

if [ ! -d "$ENGINE_DIRECTORY" ]; then
    echo "error: engine localization check could not find $ENGINE_DIRECTORY" >&2
    exit 1
fi

FOUND=0

while IFS= read -r catalog; do
    echo "error: RelaxinEngine must stay unlocalized: remove string catalog $catalog" >&2
    FOUND=1
done < <(find "$ENGINE_DIRECTORY" \( -name 'Localizable.xcstrings' -o -name 'Localizable.strings' -o -name 'Localizable.stringsdict' \) -print)

if rg -n --glob '!**/DarkSword/**' --glob '!**/Rocket/**' \
    'NSLocalizedString|localizedStringWithFormat:|String\(localized:|LocalizedStringKey' \
    "$ENGINE_DIRECTORY"; then
    echo "error: RelaxinEngine must stay unlocalized: remove localization lookups from RelaxinEngine sources" >&2
    FOUND=1
fi

if [ "$FOUND" -ne 0 ]; then
    exit 1
fi
