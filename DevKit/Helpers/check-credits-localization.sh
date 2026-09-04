#!/usr/bin/env bash
#
# Enforce that the credits page stays unlocalized.
#
# The credits sequence (HomeView+Credits.swift) is a fixed attribution roll:
# its title and role strings must remain the original English literals and
# must never route through localization lookups.

set -u -o pipefail

ROOT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CREDITS_FILE="$ROOT_DIRECTORY/Relaxin/Interface/Home/HomeView+Credits.swift"

if ! command -v rg >/dev/null 2>&1; then
    echo "error: credits localization check requires rg" >&2
    exit 69
fi

if [ ! -f "$CREDITS_FILE" ]; then
    echo "error: credits localization check could not find $CREDITS_FILE" >&2
    exit 1
fi

if rg -n 'String\(localized:|NSLocalizedString|LocalizedStringKey' "$CREDITS_FILE"; then
    echo "error: credits page must stay unlocalized: remove localization lookups from $CREDITS_FILE" >&2
    exit 1
fi
