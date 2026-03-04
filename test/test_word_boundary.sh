#!/usr/bin/env bash
# Category I: Word boundary / regex behavior

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_word_boundary_no_prefix_match() {
    local hist
    hist="$(printf '%s\n' "git status" "gitk --all")"
    run_hi "$hist" "git 10"
    assert_contains "$HI_STDOUT" "git status" "git matches" &&
    assert_not_contains "$HI_STDOUT" "gitk" "gitk is not matched by git"
}

test_bare_command_at_line_end() {
    local hist
    hist="$(printf '%s\n' "git" "echo hello")"
    run_hi "$hist" "git"
    assert_contains "$HI_STDOUT" "git" "bare command matched"
}

test_command_with_flags() {
    local hist
    hist="$(printf '%s\n' "ls -la /tmp" "echo hello")"
    run_hi "$hist" "ls"
    assert_contains "$HI_STDOUT" "ls -la /tmp"
}

run_word_boundary_tests() {
    printf '\033[1mWord boundary\033[0m\n'
    run_test test_word_boundary_no_prefix_match
    run_test test_bare_command_at_line_end
    run_test test_command_with_flags
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_word_boundary_tests
    print_summary
fi
