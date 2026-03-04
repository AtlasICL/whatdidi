#!/usr/bin/env bash
# Category: Argument validation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_no_args_returns_2() {
    run_ni
    assert_eq 2 "$NI_EXIT" "exit code"
}

test_no_args_shows_usage_hint() {
    run_ni
    assert_contains "$NI_STDERR" "Usage:" "usage on stderr" &&
    assert_contains "$NI_STDERR" "--help" "hints at --help"
}

test_three_args_returns_2() {
    run_ni curl 3 extra
    assert_eq 2 "$NI_EXIT" "exit code"
}

test_count_zero_returns_2() {
    run_ni curl 0
    assert_eq 2 "$NI_EXIT" "exit code"
}

test_count_non_integer_returns_2() {
    run_ni curl abc
    assert_eq 2 "$NI_EXIT" "exit code" &&
    assert_contains "$NI_STDERR" "nonzero positive int" "error message"
}

test_count_float_returns_2() {
    run_ni curl 1.5
    assert_eq 2 "$NI_EXIT" "exit code"
}

test_count_negative_returns_2() {
    run_ni curl -1
    assert_eq 2 "$NI_EXIT" "exit code"
}

run_args_tests() {
    printf '\033[1mArgument validation\033[0m\n'
    run_test test_no_args_returns_2
    run_test test_no_args_shows_usage_hint
    run_test test_three_args_returns_2
    run_test test_count_zero_returns_2
    run_test test_count_non_integer_returns_2
    run_test test_count_float_returns_2
    run_test test_count_negative_returns_2
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_args_tests
    print_summary
fi
