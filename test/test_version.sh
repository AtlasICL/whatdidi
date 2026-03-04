#!/usr/bin/env bash
# Category: --version / -v

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_version_exits_zero() {
    run_ni --version
    assert_eq 0 "$NI_EXIT" "exit code"
}

test_version_prints_version_number() {
    run_ni --version
    assert_contains "$NI_STDOUT" "whatdidi" "has program name" &&
    assert_contains "$NI_STDOUT" "1.0.1" "has version number"
}

test_version_prints_author() {
    run_ni --version
    assert_contains "$NI_STDOUT" "Author:" "has author label" &&
    assert_contains "$NI_STDOUT" "Emre Acarsoy" "has author name"
}

test_v_flag_exits_zero() {
    run_ni -v
    assert_eq 0 "$NI_EXIT" "exit code"
}

test_v_flag_same_as_version() {
    run_ni --version
    local version_out="$NI_STDOUT"
    run_ni -v
    assert_eq "$version_out" "$NI_STDOUT" "-v and --version output identical"
}

test_version_with_trailing_args_ignored() {
    run_ni --version extra
    assert_eq 0 "$NI_EXIT" "exit code" &&
    assert_contains "$NI_STDOUT" "1.0.1" "still shows version"
}

test_v_with_trailing_args_ignored() {
    run_ni -v extra
    assert_eq 0 "$NI_EXIT" "exit code" &&
    assert_contains "$NI_STDOUT" "1.0.1" "still shows version"
}

test_help_mentions_version() {
    run_ni --help
    assert_contains "$NI_STDOUT" "--version" "help documents --version"
}

run_version_tests() {
    printf '\033[1mVersion\033[0m\n'
    run_test test_version_exits_zero
    run_test test_version_prints_version_number
    run_test test_version_prints_author
    run_test test_v_flag_exits_zero
    run_test test_v_flag_same_as_version
    run_test test_version_with_trailing_args_ignored
    run_test test_v_with_trailing_args_ignored
    run_test test_help_mentions_version
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_version_tests
    print_summary
fi
