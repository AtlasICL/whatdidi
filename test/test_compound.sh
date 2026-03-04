#!/usr/bin/env bash
# Category: Compound (multi-word) needle

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_compound_needle_match() {
    local hist
    hist="$(printf '%s\n' "git status" "git push origin main" "git pull")"
    run_hi "$hist" '"git push"'
    assert_contains "$HI_STDOUT" "git push origin main"
}

test_compound_excludes_partial() {
    local hist
    hist="$(printf '%s\n' "git push origin main" "git pull" "git status")"
    run_hi "$hist" '"git push" 10'
    assert_not_contains "$HI_STDOUT" "git pull" "git pull is not git push" &&
    assert_not_contains "$HI_STDOUT" "git status" "git status is not git push"
}

test_compound_with_count() {
    local hist
    hist="$(printf '%s\n' "git push origin main" "git push origin dev" "git push origin staging")"
    run_hi "$hist" '"git push" 2'
    assert_line_count 2 "$HI_STDOUT" "compound with count=2"
}

test_compound_sudo() {
    local hist
    hist="$(printf '%s\n' "sudo apt install vim" "apt update" "echo done")"
    run_hi "$hist" '"apt install"'
    assert_contains "$HI_STDOUT" "sudo apt install vim"
}

run_compound_tests() {
    printf '\033[1mCompound needle\033[0m\n'
    run_test test_compound_needle_match
    run_test test_compound_excludes_partial
    run_test test_compound_with_count
    run_test test_compound_sudo
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_compound_tests
    print_summary
fi
