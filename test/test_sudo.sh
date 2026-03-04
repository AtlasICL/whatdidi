#!/usr/bin/env bash
# Category F: Sudo matching

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_sudo_prefix_matched() {
    local hist
    hist="$(printf '%s\n' "echo hello" "sudo rm -rf /tmp/junk")"
    run_hi "$hist" "rm"
    assert_contains "$HI_STDOUT" "sudo rm -rf /tmp/junk"
}

test_sudo_and_plain_both_matched() {
    local hist
    hist="$(printf '%s\n' "rm foo.txt" "sudo rm bar.txt" "echo other")"
    run_hi "$hist" "rm 5"
    assert_contains "$HI_STDOUT" "rm foo.txt" &&
    assert_contains "$HI_STDOUT" "sudo rm bar.txt"
}

test_sudo_order_preserved() {
    local hist
    hist="$(printf '%s\n' "rm old" "sudo rm middle" "rm recent")"
    run_hi "$hist" "rm 3"
    local first_line
    first_line="$(printf '%s\n' "$HI_STDOUT" | head -1)"
    assert_eq "rm recent" "$first_line" "most recent rm first"
}

run_sudo_tests() {
    printf '\033[1mSudo matching\033[0m\n'
    run_test test_sudo_prefix_matched
    run_test test_sudo_and_plain_both_matched
    run_test test_sudo_order_preserved
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_sudo_tests
    print_summary
fi
