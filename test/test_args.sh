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

test_count_leading_zero_not_octal_bash() {
    # M1: a leading-zero count (08) must be normalized to base-10, not parsed as
    # octal by bash arithmetic (which would error "value too great for base").
    # We assert on stderr/exit rather than exact match counts so the test is
    # robust to the sandbox's history-doubling artifact.
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb")"
    run_hi "$hist" "curl 08"
    assert_eq 0 "$HI_EXIT" "leading-zero count is a clean exit" &&
    assert_not_contains "$HI_STDERR" "value too great" "no octal arithmetic error" &&
    assert_not_contains "$HI_STDERR" "nonzero positive int" "08 is a valid count, not rejected"
}

test_count_leading_zero_not_octal_zsh() {
    # Cross-shell agreement: zsh already treats 08 as decimal; assert the same
    # clean behavior so bash and zsh stay in lockstep. Guarded on zsh.
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb")"
    run_hi_zsh "$hist" "curl 08"
    assert_eq 0 "$HI_EXIT" "leading-zero count is a clean exit under zsh" &&
    assert_not_contains "$HI_STDERR" "value too great" "no arithmetic error under zsh" &&
    assert_not_contains "$HI_STDERR" "nonzero positive int" "08 is a valid count under zsh"
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
    run_test test_count_leading_zero_not_octal_bash
    if command -v zsh >/dev/null 2>&1; then
        run_test test_count_leading_zero_not_octal_zsh
    else
        printf '  \033[33mSKIP\033[0m  test_count_leading_zero_not_octal_zsh (zsh not installed)\n'
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_args_tests
    print_summary
fi
