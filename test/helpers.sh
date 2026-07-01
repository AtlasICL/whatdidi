#!/usr/bin/env bash
# Shared test infrastructure — sourced by each test file.

[[ -n "${_HELPERS_LOADED:-}" ]] && return
_HELPERS_LOADED=1

set -euo pipefail

# Constants
WHATDIDI_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/whatdidi"
INSTALL_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install"
# The exact line install adds to rc files and uninstall removes.
SOURCE_LINE="source /usr/local/bin/whatdidi"
PASS=0
FAIL=0
ERRORS=()

# Test infrastructure

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
history -r "\$HISTFILE"
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
# with `fc -R` instead of bash's `history -r`.

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
# These exercise the install script and the --update / --uninstall paths
# without root. A no-op `sudo` shim is placed on PATH so the privileged
# /usr/local/bin copy/remove is skipped while the rc-file wiring (which touches
# the sandboxed TEST_HOME) runs for real.

make_mock_sudo() {
    # Create a no-op `sudo` in a temp bin dir and echo the dir path.
    local dir="$TEST_TMPDIR/mockbin"
    mkdir -p "$dir"
    cat > "$dir/sudo" <<'EOF'
#!/bin/sh
# no-op sudo for tests: succeed without doing anything privileged
exit 0
EOF
    chmod +x "$dir/sudo"
    printf '%s' "$dir"
}

run_install() {
    # Run the install script with HOME=TEST_HOME and a no-op sudo.
    # Sets: INST_STDOUT, INST_STDERR, INST_EXIT
    local mockbin stdout_f stderr_f
    mockbin="$(make_mock_sudo)"
    stdout_f="$TEST_TMPDIR/inst_out"
    stderr_f="$TEST_TMPDIR/inst_err"

    set +e
    HOME="$TEST_HOME" PATH="$mockbin:$PATH" sh "$INSTALL_SRC" >"$stdout_f" 2>"$stderr_f"
    INST_EXIT=$?
    set -e
    INST_STDOUT="$(cat "$stdout_f")"
    INST_STDERR="$(cat "$stderr_f")"
}

run_wdi_stdin() {
    # Source whatdidi under bash with HOME=TEST_HOME + a no-op sudo, feed $1 to
    # stdin (for the --update/--uninstall confirmation prompt) and run $2.
    # $3 = (optional) shell preamble injected after sourcing, before the call
    #      (e.g. to shadow `command -v curl` and simulate curl being absent).
    # Sets: SI_STDOUT, SI_STDERR, SI_EXIT
    local stdin_data="$1" args="$2" preamble="${3:-}"
    local mockbin stdout_f stderr_f
    mockbin="$(make_mock_sudo)"
    stdout_f="$TEST_TMPDIR/si_out"
    stderr_f="$TEST_TMPDIR/si_err"

    set +e
    printf '%s\n' "$stdin_data" | \
        HOME="$TEST_HOME" PATH="$mockbin:$PATH" bash --norc --noprofile -c '
            source "'"$WHATDIDI_SRC"'"
            '"$preamble"'
            whatdidi '"$args"'
        ' >"$stdout_f" 2>"$stderr_f"
    SI_EXIT=$?
    set -e
    SI_STDOUT="$(cat "$stdout_f")"
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
