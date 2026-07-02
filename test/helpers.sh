#!/usr/bin/env bash
# Shared test infrastructure — sourced by each test file.

[[ -n "${_HELPERS_LOADED:-}" ]] && return
_HELPERS_LOADED=1

set -euo pipefail

# Constants
WHATDIDI_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/whatdidi"
INSTALL_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install"
# The exact line install adds to rc files and uninstall removes. It is a
# $HOME-derived absolute path, and both install and whatdidi expand $HOME at
# runtime — so under the sandbox (HOME=$TEST_HOME) it must expand to $TEST_HOME.
# Because TEST_HOME is freshly minted per test in setup(), SOURCE_LINE is
# (re)computed there rather than pinned to a static string here.
SOURCE_LINE=""
PASS=0
FAIL=0
ERRORS=()

# Test infrastructure

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    TEST_HOME="$TEST_TMPDIR/home"
    mkdir -p "$TEST_HOME"
    # Recompute against this test's TEST_HOME so it matches the expanded path the
    # install script / whatdidi write when run with HOME=$TEST_HOME.
    SOURCE_LINE="source $TEST_HOME/.local/share/whatdidi/whatdidi"
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

# Assertion helpers

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

# Tier 1: non-interactive runner
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

# Tier 2: interactive runner with controlled history
# For testing the history search pipeline

run_hi() {
    # $1 = newline-separated history lines to seed
    # $2 = full whatdidi invocation args (as a single string)
    # $3 = (optional) config file contents
    # $4 = (optional) extra shell preamble injected before whatdidi is invoked
    #      (e.g. 'export HISTTIMEFORMAT="%F %T "')
    # Sets: HI_STDOUT, HI_STDERR, HI_EXIT
    local hist_lines="$1"
    local wdi_args="$2"
    local config_contents="${3:-}"
    local hi_preamble="${4:-}"
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
# Seed with 'history -n' (not '-r'): on bash 3.2 '-r' doesn't advance the '-n'
# read cursor, so whatdidi's internal 'history -n' would re-read the seeded file
# and double every entry. '-n' seeding advances the cursor, matching bash 5.
# Precondition: this relies on HISTFILE NOT having been read at interactive
# startup (in the sandbox it defaults to the nonexistent $TEST_HOME/.bash_history,
# so the '-n' cursor starts at 0). If a future test pre-exports HISTFILE or
# creates $TEST_HOME/.bash_history, 'history -c' + 'history -n' would silently
# seed zero lines instead.
history -n "\$HISTFILE"
$hi_preamble
source "$WHATDIDI_SRC"
whatdidi $wdi_args
HEREDOC
    HI_EXIT=$?
    set -e
    HI_STDOUT="$(cat "$stdout_f")"
    HI_STDERR="$(grep -v -E 'bash.*cannot set terminal|no job control' "$stderr_f" || true)"
}

# zsh variants of the runners above. They reuse the same NI_*/HI_* result vars
# so zsh test functions read identically to the bash ones. zsh is launched with
# -f (skip rc files, like bash's --norc --noprofile); seeded history is loaded
# with `fc -R` instead of bash's `history -n`.

run_ni_zsh() {
    # Usage: run_ni_zsh [whatdidi args...]
    # Sets: NI_STDOUT, NI_STDERR, NI_EXIT
    local stdout_f="$TEST_TMPDIR/stdout" stderr_f="$TEST_TMPDIR/stderr"

    set +e
    HOME="$TEST_HOME" zsh -f -c '
        source "'"$WHATDIDI_SRC"'"
        whatdidi "$@"
    ' _ "$@" >"$stdout_f" 2>"$stderr_f"
    NI_EXIT=$?
    set -e
    NI_STDOUT="$(cat "$stdout_f")"
    NI_STDERR="$(cat "$stderr_f")"
}

run_hi_zsh() {
    # $1 = newline-separated history lines to seed
    # $2 = full whatdidi invocation args (as a single string)
    # $3 = (optional) config file contents
    # $4 = (optional) extra shell preamble injected before whatdidi is invoked
    # Sets: HI_STDOUT, HI_STDERR, HI_EXIT
    local hist_lines="$1"
    local wdi_args="$2"
    local config_contents="${3:-}"
    local hi_preamble="${4:-}"
    local histfile="$TEST_TMPDIR/histfile"
    local stdout_f="$TEST_TMPDIR/stdout"
    local stderr_f="$TEST_TMPDIR/stderr"

    printf '%s\n' "$hist_lines" > "$histfile"

    if [[ -n "$config_contents" ]]; then
        mkdir -p "$TEST_HOME/.config/whatdidi"
        printf '%s\n' "$config_contents" > "$TEST_HOME/.config/whatdidi/config"
    fi

    set +e
    HOME="$TEST_HOME" zsh -f -i <<HEREDOC >"$stdout_f" 2>"$stderr_f"
export HISTFILE="$histfile"
HISTSIZE=10000
SAVEHIST=10000
fc -R "\$HISTFILE"
$hi_preamble
source "$WHATDIDI_SRC"
whatdidi $wdi_args
HEREDOC
    HI_EXIT=$?
    set -e
    HI_STDOUT="$(cat "$stdout_f")"
    HI_STDERR="$(grep -v -E 'cannot set terminal|no job control|can.t find terminal' "$stderr_f" || true)"
}

# Tier 3: install / lifecycle runners
#
# These exercise the install script and the --update / --uninstall paths. Both
# now install to a user-owned XDG data path under $HOME (=$TEST_HOME in the
# sandbox) and use no sudo at all, so the copy/remove and rc-file wiring all run
# for real inside the sandbox without any privilege shim.

run_install() {
    # Run the install script with HOME=TEST_HOME.
    # Sets: INST_STDOUT, INST_STDERR, INST_EXIT
    local stdout_f stderr_f
    stdout_f="$TEST_TMPDIR/inst_out"
    stderr_f="$TEST_TMPDIR/inst_err"

    set +e
    HOME="$TEST_HOME" sh "$INSTALL_SRC" >"$stdout_f" 2>"$stderr_f"
    INST_EXIT=$?
    set -e
    INST_STDOUT="$(cat "$stdout_f")"
    INST_STDERR="$(cat "$stderr_f")"
}

run_wdi_stdin() {
    # Source whatdidi under bash with HOME=TEST_HOME, feed $1 to stdin (for the
    # --update/--uninstall confirmation prompt) and run $2.
    # $3 = (optional) shell preamble injected after sourcing, before the call
    #      (e.g. to shadow `command -v curl` and simulate curl being absent).
    # Sets: SI_STDOUT, SI_STDERR, SI_EXIT
    local stdin_data="$1" args="$2" preamble="${3:-}"
    local stdout_f stderr_f
    stdout_f="$TEST_TMPDIR/si_out"
    stderr_f="$TEST_TMPDIR/si_err"

    set +e
    printf '%s\n' "$stdin_data" | \
        HOME="$TEST_HOME" bash --norc --noprofile -c '
            source "'"$WHATDIDI_SRC"'"
            '"$preamble"'
            whatdidi '"$args"'
        ' >"$stdout_f" 2>"$stderr_f"
    SI_EXIT=$?
    set -e
    SI_STDOUT="$(cat "$stdout_f")"
    SI_STDERR="$(cat "$stderr_f")"
}

run_wdi_stdin_emptyhome() {
    # Like run_wdi_stdin but exports an EMPTY HOME, to exercise the
    # $HOME-derived `rm -rf "$conf_dir"` guard in --uninstall (BUG-5). With an
    # empty HOME, conf_dir resolves to "/.config/whatdidi" (a system path) and
    # must never be removed. Same result vars as run_wdi_stdin: SI_STDOUT,
    # SI_STDERR, SI_EXIT.
    local stdin_data="$1" args="$2" preamble="${3:-}"
    local stdout_f stderr_f
    stdout_f="$TEST_TMPDIR/si_out"
    stderr_f="$TEST_TMPDIR/si_err"

    set +e
    printf '%s\n' "$stdin_data" | \
        HOME="" bash --norc --noprofile -c '
            source "'"$WHATDIDI_SRC"'"
            '"$preamble"'
            whatdidi '"$args"'
        ' >"$stdout_f" 2>"$stderr_f"
    SI_EXIT=$?
    set -e
    SI_STDOUT="$(cat "$stdout_f")"
    SI_STDERR="$(cat "$stderr_f")"
}

run_wdi_stdin_zsh() {
    # zsh counterpart of run_wdi_stdin: exercises the --update/--uninstall
    # confirmation prompts under zsh, which is where the H1 `read -p` bug hid
    # (zsh treats `-p` as "read from coprocess", so the bash-only prompt was
    # silently skipped). Sources whatdidi under zsh -f with HOME=TEST_HOME,
    # feeds $1 to stdin (the confirmation reply) and runs $2.
    # $3 = (optional) shell preamble injected after sourcing, before the call.
    # Sets the SAME result vars as the bash version so zsh test bodies read
    # identically: SI_STDOUT, SI_STDERR, SI_EXIT.
    local stdin_data="$1" args="$2" preamble="${3:-}"
    local stdout_f stderr_f
    stdout_f="$TEST_TMPDIR/si_out"
    stderr_f="$TEST_TMPDIR/si_err"

    set +e
    printf '%s\n' "$stdin_data" | \
        HOME="$TEST_HOME" zsh -f -c '
            source "'"$WHATDIDI_SRC"'"
            '"$preamble"'
            whatdidi '"$args"'
        ' >"$stdout_f" 2>"$stderr_f"
    SI_EXIT=$?
    set -e
    SI_STDOUT="$(cat "$stdout_f")"
    # `zsh -f -c` is non-interactive, so the "cannot set terminal" job-control
    # noise `run_hi_zsh` filters does not appear here — keep stderr raw like the
    # bash run_wdi_stdin so error-message assertions match verbatim.
    SI_STDERR="$(cat "$stderr_f")"
}

# Count exact (whole-line) occurrences of a string in a file (0 if absent).
# grep -c prints the count on stdout but exits 1 when the count is 0, so we
# capture stdout and ignore the exit status.
count_lines_matching() {
    local file="$1" needle="$2" n
    [[ -f "$file" ]] || { printf '0'; return; }
    n="$(grep -cxF "$needle" "$file" 2>/dev/null)"
    printf '%s' "${n:-0}"
}

# Summary
print_summary() {
    printf '\n\033[1m=== Results: %d passed, %d failed ===\033[0m\n\n' "$PASS" "$FAIL"
    if (( FAIL > 0 )); then
        printf 'Failed tests:\n'
        for t in "${ERRORS[@]}"; do printf '  - %s\n' "$t"; done
        exit 1
    fi
}
