#!/usr/bin/env bash
# =============================================================================
# Terminal UI: numbered steps with spinner + live log tail, durations,
# full output only on failure (or with --verbose), status table, summary box.
#
#   steps_begin 3
#   run_step "Building image" compose build app || return 1
#
# The command runs in the CURRENT shell (exports survive) with output captured
# to a temp log; the spinner is a background process that only reads that log.
# =============================================================================

[[ -n "${_UI_LOADED:-}" ]] && return 0
_UI_LOADED=1

SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "${SCRIPT_LIB_DIR}/colors.sh"

STEP_N=0
STEP_TOTAL=0
_SPINNER_PID=""
_ESC=$'\033'

# Spinner only on an interactive terminal, never in quiet/verbose mode.
_ui_animated() { [[ -t 1 && "${TERM:-}" != "dumb" && "${QUIET:-false}" != "true" && "${VERBOSE:-false}" != "true" ]]; }

_ui_cols() {
    local c="${COLUMNS:-}"
    [[ -z "$c" ]] && c="$(tput cols 2>/dev/null)"
    echo "${c:-80}"
}

# fmt_duration <seconds> -> 7s | 1m 05s
fmt_duration() {
    local s="$1"
    if (( s < 60 )); then
        echo "${s}s"
    else
        printf '%dm %02ds\n' $((s / 60)) $((s % 60))
    fi
}

# Strip colors/CR from a log line so it can be shown in the spinner.
_ui_clean() { tr '\r' '\n' | sed -e "s/${_ESC}\[[0-9;?]*[A-Za-z]//g"; }

steps_begin() {
    STEP_N=0
    STEP_TOTAL="${1:-0}"
}

_step_prefix() {
    if (( STEP_TOTAL > 0 )); then
        printf '%b' "${DIM}[${STEP_N}/${STEP_TOTAL}]${NC} "
    fi
}

_spinner_loop() {
    local label="$1" log="$2" start="$3" i=0 cols line width elapsed prefix
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    prefix="$(_step_prefix)"
    cols="$(_ui_cols)"
    while :; do
        elapsed="$(fmt_duration $((SECONDS - start)))"
        line="$(tail -n 30 "$log" 2>/dev/null | _ui_clean | grep -v '^[[:space:]]*$' | tail -n 1 | tr -s ' \t' ' ')"
        line="${line# }"
        # visible: "⠋ [n/N] label  12s  › line"
        width=$(( cols - ${#label} - ${#elapsed} - 16 ))
        if (( width > 10 )) && [[ -n "$line" ]]; then
            (( ${#line} > width )) && line="${line:0:$((width - 1))}…"
            line="  ${DIM}› ${line}${NC}"
        else
            line=""
        fi
        printf '\r%s[K%b%s%b %b%s  %b%s%b%b' "$_ESC" "$CYAN" "${frames[$i]}" "$NC" "$prefix" "$label" "$DIM" "$elapsed" "$NC" "$line"
        i=$(( (i + 1) % 10 ))
        sleep 0.12
    done
}

_spinner_stop() {
    if [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null
        wait "$_SPINNER_PID" 2>/dev/null
        _SPINNER_PID=""
        printf '\r%s[K' "$_ESC"
    fi
}

ui_cursor_hide() { _ui_animated && printf '%s[?25l' "$_ESC"; return 0; }
ui_cursor_show() { [[ -t 1 ]] && printf '%s[?25h' "$_ESC"; return 0; }

# Print the useful tail of a failed step's log. BuildKit appends Go stack
# traces after its error: cut the log at "failed to solve", drop blank lines.
_step_show_log() {
    local log="$1" lines="${2:-25}" cut prefix
    prefix="$(printf '%b' "    ${DIM}│${NC} ")"
    cut="$(grep -n -m1 -E 'failed to solve|did not complete successfully' "$log" | cut -d: -f1)"
    { if [[ -n "$cut" ]]; then head -n "$cut" "$log"; else cat "$log"; fi; } \
        | _ui_clean | grep -v '^[[:space:]]*$' | tail -n "$lines" | sed "s/^/${prefix}/" >&2
}

# Lines a step wants under its ✓: step_note output, warnings, errors.
_step_surface_notes() {
    _ui_clean < "$1" | grep -F -e "↳" -e "$ICON_WARN" -e "$CROSSMARK" | sed "s/^/    /" >&2
    return 0
}

# step_note <text>: shown under the step's result line (dimmed).
step_note() { echo -e "${DIM}↳ $*${NC}"; }

# run_step <label> <command...>: returns the command's exit code.
run_step() {
    local label="$1" log start rc elapsed prefix
    shift
    STEP_N=$((STEP_N + 1))
    prefix="$(_step_prefix)"
    start=$SECONDS

    if [[ "${VERBOSE:-false}" == "true" ]]; then
        print_msg "${BOLD}${BLUE}▸${NC} ${prefix}${BOLD}${label}${NC}"
        "$@" </dev/null
        rc=$?
        elapsed="$(fmt_duration $((SECONDS - start)))"
        if [[ $rc -eq 0 ]]; then
            print_msg "${GREEN}${CHECKMARK}${NC} ${prefix}${label} ${DIM}${elapsed}${NC}"
        else
            print_error "${prefix}${label} ${DIM}${elapsed}${NC}"
        fi
        return $rc
    fi

    log="${TMPDIR:-/tmp}"
    log="$(mktemp "${log%/}/dock-step.XXXXXX")"
    if _ui_animated; then
        _spinner_loop "$label" "$log" "$start" 2>/dev/null &
        _SPINNER_PID=$!
        trap '_spinner_stop; ui_cursor_show; echo -e "${RED}${CROSSMARK}${NC} '"${prefix}${label}"' ${DIM}interrupted${NC}" >&2; exit 130' INT TERM
    fi

    "$@" >"$log" 2>&1 </dev/null
    rc=$?

    _spinner_stop
    trap - INT TERM
    elapsed="$(fmt_duration $((SECONDS - start)))"

    if [[ $rc -eq 0 ]]; then
        print_msg "${GREEN}${CHECKMARK}${NC} ${prefix}${label} ${DIM}${elapsed}${NC}"
        _is_quiet || _step_surface_notes "$log"
        rm -f "$log"
    else
        print_error "${prefix}${BOLD}${label}${NC} ${DIM}failed after ${elapsed}${NC}"
        _step_show_log "$log"
        echo -e "    ${DIM}Full log: ${log}  ·  rerun with -v to stream output${NC}" >&2
    fi
    return $rc
}

# step_skip <label> <reason>: counts the step without running anything.
step_skip() {
    STEP_N=$((STEP_N + 1))
    print_msg "${GRAY}–${NC} $(_step_prefix)${GRAY}$1${NC} ${DIM}($2)${NC}"
}

# print_box <color> <line...>: rounded box sized to the longest line.
print_box() {
    _is_quiet && return 0
    local color="$1" line width=0 plain pad
    shift
    for line in "$@"; do
        plain="$(printf '%b' "$line" | _ui_clean)"
        (( ${#plain} > width )) && width=${#plain}
    done
    width=$((width + 4))
    echo ""
    echo -e "${color}╭$(printf '─%.0s' $(seq 1 "$width"))╮${NC}"
    for line in "$@"; do
        plain="$(printf '%b' "$line" | _ui_clean)"
        pad=$((width - ${#plain} - 2))
        echo -e "${color}│${NC}  ${line}$(printf '%*s' "$pad" '')${color}│${NC}"
    done
    echo -e "${color}╰$(printf '─%.0s' $(seq 1 "$width"))╯${NC}"
}
