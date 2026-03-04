#!/usr/bin/env bash
# Category A: --help / -h

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_help_exits_zero() {
    run_ni --help
    assert_eq 0 "$NI_EXIT" "exit code"
}

test_help_prints_usage() {
    run_ni --help
    assert_contains "$NI_STDOUT" "Usage:" "has Usage section" &&
    assert_contains "$NI_STDOUT" "whatdidi <command> [count]" "shows syntax"
}

test_help_shows_examples() {
    run_ni --help
    assert_contains "$NI_STDOUT" "Examples:" "has Examples section"
}

test_help_mentions_sudo() {
    run_ni --help
    assert_contains "$NI_STDOUT" "sudo" "mentions sudo"
}

test_help_mentions_set_default_count() {
    run_ni --help
    assert_contains "$NI_STDOUT" "--set-default" "documents --set-default"
}

test_h_flag_exits_zero() {
    run_ni -h
    assert_eq 0 "$NI_EXIT" "exit code"
}

test_h_flag_same_as_help() {
    run_ni --help
    local help_out="$NI_STDOUT"
    run_ni -h
    assert_eq "$help_out" "$NI_STDOUT" "-h and --help output identical"
}

test_help_with_trailing_args_ignored() {
    run_ni --help extra
    assert_eq 0 "$NI_EXIT" "exit code" &&
    assert_contains "$NI_STDOUT" "Usage:" "still shows help"
}

test_h_with_trailing_args_ignored() {
    run_ni -h extra
    assert_eq 0 "$NI_EXIT" "exit code" &&
    assert_contains "$NI_STDOUT" "Usage:" "still shows help"
}

run_help_tests() {
    printf '\033[1mHelp & usage\033[0m\n'
    run_test test_help_exits_zero
    run_test test_help_prints_usage
    run_test test_help_shows_examples
    run_test test_help_mentions_sudo
    run_test test_help_mentions_set_default_count
    run_test test_h_flag_exits_zero
    run_test test_h_flag_same_as_help
    run_test test_help_with_trailing_args_ignored
    run_test test_h_with_trailing_args_ignored
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_help_tests
    print_summary
fi
