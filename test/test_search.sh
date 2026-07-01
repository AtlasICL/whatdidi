#!/usr/bin/env bash
# Category: Basic history search

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_simple_match() {
    local hist
    hist="$(printf '%s\n' "ls -la" "curl https://example.com" "echo hello")"
    run_hi "$hist" "curl"
    assert_contains "$HI_STDOUT" "curl https://example.com"
}

test_no_match_empty_output() {
    local hist
    hist="$(printf '%s\n' "ls -la" "echo hello")"
    run_hi "$hist" "nonexistent"
    assert_eq "" "$HI_STDOUT" "no output for no match"
}

test_default_returns_one_result() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb" "curl ccc")"
    run_hi "$hist" "curl"
    assert_line_count 1 "$HI_STDOUT" "default count is 1"
}

test_explicit_count_returns_n() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb" "curl ccc" "curl ddd")"
    run_hi "$hist" "curl 3"
    assert_line_count 3 "$HI_STDOUT" "count=3 returns 3"
}

test_count_exceeds_matches() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb" "echo other")"
    run_hi "$hist" "curl 10"
    assert_line_count 2 "$HI_STDOUT" "only 2 matches exist"
}

test_most_recent_first() {
    local hist
    hist="$(printf '%s\n' "curl first" "curl second" "curl third")"
    run_hi "$hist" "curl 3"
    local first_line
    first_line="$(printf '%s\n' "$HI_STDOUT" | head -1)"
    assert_eq "curl third" "$first_line" "most recent entry first"
}

test_order_preserved_across_all() {
    local hist
    hist="$(printf '%s\n' "curl first" "curl second" "curl third")"
    run_hi "$hist" "curl 3"
    local last_line
    last_line="$(printf '%s\n' "$HI_STDOUT" | tail -1)"
    assert_eq "curl first" "$last_line" "oldest entry last"
}

test_duplicate_entries_all_returned() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl aaa" "curl aaa")"
    run_hi "$hist" "curl 10"
    assert_line_count 3 "$HI_STDOUT" "all 3 duplicates returned"
}

test_newest_first_over_many_entries() {
    # Guards the history reversal (awk newest-first, replacing GNU `tac`):
    # seed 20 matches and require the full result in strict most-recent-first
    # order, not just the first line.
    local hist expected i
    local lines=() exp=()
    for i in $(seq 1 20); do lines+=("curl req$i"); done
    hist="$(printf '%s\n' "${lines[@]}")"
    for i in $(seq 20 -1 1); do exp+=("curl req$i"); done
    expected="$(printf '%s\n' "${exp[@]}")"
    run_hi "$hist" "curl 20"
    assert_eq "$expected" "$HI_STDOUT" "20 matches returned newest-first"
}

test_search_exit_code_on_match() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "echo hello")"
    run_hi "$hist" "curl"
    assert_eq 0 "$HI_EXIT" "exit code 0 on match"
}

test_search_exit_code_on_no_match() {
    local hist
    hist="$(printf '%s\n' "ls -la" "echo hello")"
    run_hi "$hist" "nonexistent"
    assert_eq 0 "$HI_EXIT" "exit code 0 even with no match"
}

test_search_exit_code_when_count_unmet() {
    # whatdidi must report 0 even when the match is the oldest line processed
    # and the requested count is never reached (guards the explicit return 0).
    local hist
    hist="$(printf '%s\n' "curl target" "echo a" "echo b")"
    run_hi "$hist" "curl 5"
    assert_eq 0 "$HI_EXIT" "exit 0 regardless of where the match falls"
}

run_search_tests() {
    printf '\033[1mHistory search\033[0m\n'
    run_test test_simple_match
    run_test test_no_match_empty_output
    run_test test_default_returns_one_result
    run_test test_explicit_count_returns_n
    run_test test_count_exceeds_matches
    run_test test_most_recent_first
    run_test test_order_preserved_across_all
    run_test test_duplicate_entries_all_returned
    run_test test_newest_first_over_many_entries
    run_test test_search_exit_code_on_match
    run_test test_search_exit_code_on_no_match
    run_test test_search_exit_code_when_count_unmet
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_search_tests
    print_summary
fi
