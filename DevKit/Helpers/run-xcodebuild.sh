#!/usr/bin/env bash
# Live, concise xcodebuild wrapper with persistent raw logs.

set -u -o pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIRECTORY/../../.env.sh"
"$SCRIPT_DIRECTORY/check-tools.sh" xcode || exit $?
"$SCRIPT_DIRECTORY/check-zstd-integration.sh" || exit $?
"$SCRIPT_DIRECTORY/check-credits-localization.sh" || exit $?
"$SCRIPT_DIRECTORY/check-engine-localization.sh" || exit $?

LABEL="${XCBUILD_LABEL:-xcodebuild}"
SAFE_LABEL="${LABEL//\//_}"
SAFE_LABEL="${SAFE_LABEL// /_}"
LOG_DIRECTORY="${XCBUILD_LOG_DIR:-${TMPDIR:-/tmp}/RelaxinBuildLogs}"
mkdir -p "$LOG_DIRECTORY"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
LOG_STEM="$LOG_DIRECTORY/${SAFE_LABEL}-${TIMESTAMP}-$$"
RAW_LOG="$LOG_STEM.raw.log"
LOG="$LOG_STEM.log"

should_print_concise_line() {
    local line="$1"
    [[ "${XCBUILD_VERBOSE:-0}" == "1" ]] && return 0

    case "$line" in
        CompileSwift*|SwiftCompile*|CompileC*|CompileAssetCatalog*|CompileStoryboard*|CompileXIB*|\
        PhaseScriptExecution*|ProcessInfoPlistFile*|CpResource\ *|Copy\ *|Ld\ *|Link\ *|CodeSign\ *|\
        "** BUILD SUCCEEDED **"|"** BUILD FAILED **"|"** TEST SUCCEEDED **"|"** TEST FAILED **"|\
        note:\ \[Stage\]*|note:\ \[Prebuild\]*|note:\ \[BaseBin\]*|note:\ \[Bootstrap\]*)
            return 0
            ;;
    esac

    [[ "$line" =~ (^|[[:space:]])warning: ]] && return 0
    [[ "$line" =~ (^|[[:space:]])error: ]] && return 0
    return 1
}

stream_concise() {
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if should_print_concise_line "$line"; then
            printf '%s\n' "$line"
        fi
    done
}

capture_xcodebuild() {
    : >"$RAW_LOG"

    # tee owns the raw transcript; the final shell filter consumes one line at
    # a time and never waits for EOF before printing matching progress. Keep
    # formatters such as xcbeautify out of this producer pipeline.
    xcodebuild "$@" 2>&1 | tee "$RAW_LOG" | stream_concise
    local pipeline_status=("${PIPESTATUS[@]}")
    XC_STATUS="${pipeline_status[0]}"
}

maybe_print_beautified_summary() {
    if [[ "${XCBUILD_BEAUTIFY_SUMMARY:-0}" != "1" ]]; then
        return 0
    fi
    if ! command -v xcbeautify >/dev/null 2>&1; then
        return 0
    fi

    echo ""
    echo "---- xcbeautify post-build view ----"
    xcbeautify --disable-colored-output --disable-logging <"$RAW_LOG" || true
    echo "------------------------------------"
}

normalize_log() {
    perl -ne '
        s/\r/\n/g;
        s/\x08//g;
        s/\x04//g;
        next if m{Metal\.xctoolchain/usr/lib/swift/maccatalyst};
        next if m{CoreData: error: Failed to create NSXPCConnection};
        next if m{connection to service named com\.apple\.linkd\.autoShortcut};
        print;
    ' "$RAW_LOG" >"$LOG"
}

capture_xcodebuild "$@"
normalize_log
maybe_print_beautified_summary

ERR_RE='(^|[[:space:]])error:|^\*\* (BUILD|TEST|ARCHIVE|CLEAN|ANALYZE) FAILED \*\*|^Testing failed:|^Failing tests:'
FOUND_ERRORS=0
if grep -En "$ERR_RE" "$LOG" >/dev/null 2>&1; then
    FOUND_ERRORS=1
fi

if [[ "$XC_STATUS" -ne 0 || "$FOUND_ERRORS" -ne 0 ]]; then
    echo "" >&2
    echo "❌ [$LABEL] xcodebuild failed (exit=$XC_STATUS, errors_in_log=$FOUND_ERRORS)" >&2
    if [[ "$FOUND_ERRORS" -ne 0 ]]; then
        echo "---- first 40 error lines from log ----" >&2
        grep -En "$ERR_RE" "$LOG" | head -40 >&2 || true
        echo "---------------------------------------" >&2
    fi
    echo "Raw log: $RAW_LOG" >&2
    echo "Normalized log: $LOG" >&2
    if [[ -n "${RELAXIN_BUILD_HOME:-}" ]]; then
        echo "Build home: $RELAXIN_BUILD_HOME" >&2
    fi
    if [[ -n "${RELAXIN_WORKSPACE_SOURCE:-}" ]]; then
        echo "Workspace: $RELAXIN_WORKSPACE_SOURCE" >&2
    fi
    if [[ "$XC_STATUS" -ne 0 ]]; then
        exit "$XC_STATUS"
    fi
    exit 1
fi

printf 'note: [Xcode] raw log: %s\n' "$RAW_LOG"
