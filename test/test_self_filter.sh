#!/usr/bin/env bash
# Category: Self-filter (skip whatdidi invocations)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_skips_whatdidi_invocations() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "whatdidi curl" "curl bbb")"
    run_hi "$hist" "curl 10"
    assert_not_contains "$HI_STDOUT" "whatdidi" "whatdidi lines excluded" &&
    assert_line_count 2 "$HI_STDOUT" "only real curl commands"
}

test_whatdidi_with_args_skipped() {
    local hist
    hist="$(printf '%s\n' "whatdidi git 5" "git status")"
    run_hi "$hist" "git 10"
    assert_not_contains "$HI_STDOUT" "whatdidi" "whatdidi invocation excluded"
}

test_searching_for_whatdidi_returns_matches() {
    # When the needle itself is "whatdidi", the self-filter is disabled so
    # past whatdidi invocations are searchable like any other command.
    local hist
    hist="$(printf '%s\n' "whatdidi curl" "whatdidi git 5" "echo hello")"
    run_hi "$hist" "whatdidi 10"
    assert_contains "$HI_STDOUT" "whatdidi curl" "whatdidi invocation found" &&
    assert_contains "$HI_STDOUT" "whatdidi git 5" "whatdidi invocation found"
}

test_bare_whatdidi_not_filtered() {
    # The self-filter checks for "whatdidi " (with trailing space).
    # A bare "whatdidi" line (no space) is NOT filtered by the self-filter,
    # but won't match the needle regex for other commands either.
    local hist
    hist="$(printf '%s\n' "whatdidi" "curl aaa")"
    run_hi "$hist" "curl 10"
    assert_not_contains "$HI_STDOUT" "whatdidi" "bare whatdidi not in curl results"
}

run_self_filter_tests() {
    printf '\033[1mSelf-filter\033[0m\n'
    run_test test_skips_whatdidi_invocations
    run_test test_whatdidi_with_args_skipped
    run_test test_searching_for_whatdidi_returns_matches
    run_test test_bare_whatdidi_not_filtered
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_self_filter_tests
    print_summary
fi
