#!/usr/bin/env bash
# Shared test infrastructure — sourced by each test file.

[[ -n "${_HELPERS_LOADED:-}" ]] && return
_HELPERS_LOADED=1

set -euo pipefail

# ── Constants ────────────────────────────────────────────
WHATDIDI_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/whatdidi"
PASS=0
FAIL=0
ERRORS=()

# ── Test infrastructure ──────────────────────────────────

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    TEST_HOME="$TEST_TMPDIR/home"
    mkdir -p "$TEST_HOME"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

run_test() {
    local name="$1"
    setup
    if "$name"; then
        PASS=$((PASS + 1))
        printf '  \033[32mPASS\033[0m  %s\n' "$name"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("$name")
        printf '  \033[31mFAIL\033[0m  %s\n' "$name"
    fi
    teardown
}

# ── Assertion helpers ────────────────────────────────────

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [[ "$expected" != "$actual" ]]; then
        printf '    expected: %s\n    actual:   %s\n' "$expected" "$actual"
        [[ -n "$msg" ]] && printf '    (%s)\n' "$msg"
        return 1
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "$haystack" != *"$needle"* ]]; then
        printf '    looking for: %s\n' "$needle"
        [[ -n "$msg" ]] && printf '    (%s)\n' "$msg"
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf '    should not contain: %s\n' "$needle"
        [[ -n "$msg" ]] && printf '    (%s)\n' "$msg"
        return 1
    fi
}

assert_line_count() {
    local expected="$1" text="$2" msg="${3:-}"
    local actual
    if [[ -z "$text" ]]; then
        actual=0
    else
        actual="$(printf '%s\n' "$text" | wc -l | tr -d ' ')"
    fi
    assert_eq "$expected" "$actual" "line count: $msg"
}

# ── Tier 1: non-interactive runner ───────────────────────
# For code paths that return before reaching `builtin history`

run_ni() {
    # Usage: run_ni [whatdidi args...]
    # Sets: NI_STDOUT, NI_STDERR, NI_EXIT
    local stdout_f="$TEST_TMPDIR/stdout" stderr_f="$TEST_TMPDIR/stderr"

    set +e
    HOME="$TEST_HOME" bash --norc --noprofile -c '
        source "'"$WHATDIDI_SRC"'"
        whatdidi "$@"
    ' _ "$@" >"$stdout_f" 2>"$stderr_f"
    NI_EXIT=$?
    set -e
    NI_STDOUT="$(cat "$stdout_f")"
    NI_STDERR="$(cat "$stderr_f")"
}

# ── Tier 2: interactive runner with controlled history ───
# For testing the history search pipeline

run_hi() {
    # $1 = newline-separated history lines to seed
    # $2 = full whatdidi invocation args (as a single string)
    # $3 = (optional) config file contents
    # Sets: HI_STDOUT, HI_STDERR, HI_EXIT
    local hist_lines="$1"
    local wdi_args="$2"
    local config_contents="${3:-}"
    local histfile="$TEST_TMPDIR/histfile"
    local stdout_f="$TEST_TMPDIR/stdout"
    local stderr_f="$TEST_TMPDIR/stderr"

    printf '%s\n' "$hist_lines" > "$histfile"

    if [[ -n "$config_contents" ]]; then
        mkdir -p "$TEST_HOME/.config/whatdidi"
        printf '%s\n' "$config_contents" > "$TEST_HOME/.config/whatdidi/config"
    fi

    set +e
    HOME="$TEST_HOME" bash --norc --noprofile -i <<HEREDOC >"$stdout_f" 2>"$stderr_f"
export HISTFILE="$histfile"
HISTSIZE=10000
HISTFILESIZE=10000
history -c
history -r "\$HISTFILE"
source "$WHATDIDI_SRC"
whatdidi $wdi_args
HEREDOC
    HI_EXIT=$?
    set -e
    HI_STDOUT="$(cat "$stdout_f")"
    HI_STDERR="$(grep -v -E 'bash.*cannot set terminal|no job control' "$stderr_f" || true)"
}

# ── Summary ──────────────────────────────────────────────

print_summary() {
    printf '\n\033[1m=== Results: %d passed, %d failed ===\033[0m\n\n' "$PASS" "$FAIL"
    if (( FAIL > 0 )); then
        printf 'Failed tests:\n'
        for t in "${ERRORS[@]}"; do printf '  - %s\n' "$t"; done
        exit 1
    fi
}
