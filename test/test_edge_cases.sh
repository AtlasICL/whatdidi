#!/usr/bin/env bash
# Category J: Edge cases

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_empty_history() {
    run_hi "" "curl"
    assert_eq "" "$HI_STDOUT" "empty history gives empty output"
}

test_single_match_in_history() {
    local hist="curl https://example.com"
    run_hi "$hist" "curl"
    assert_eq "curl https://example.com" "$HI_STDOUT"
}

test_special_chars_in_command() {
    local hist
    hist="$(printf '%s\n' "echo hello | grep h" "ls > /tmp/out" "echo done")"
    run_hi "$hist" "echo 10"
    assert_contains "$HI_STDOUT" "echo hello | grep h" "pipe preserved"
}

test_command_with_dollar_sign() {
    local hist
    hist="$(printf '%s\n' 'echo $HOME' "ls")"
    run_hi "$hist" "echo"
    assert_contains "$HI_STDOUT" 'echo $HOME' "dollar sign preserved"
}

test_regex_dot_star_needle_matches_everything() {
    # Needle is interpolated into a regex, so ".*" matches all commands —
    # including internal session setup lines, not just seeded history.
    local hist
    hist="$(printf '%s\n' "curl aaa" "ls -la" "echo hello")"
    run_hi "$hist" '".*" 100'
    assert_contains "$HI_STDOUT" "curl aaa" "curl matched" &&
    assert_contains "$HI_STDOUT" "ls -la" "ls matched" &&
    assert_contains "$HI_STDOUT" "echo hello" "echo matched"
    # Count will exceed 3 because .* also matches session setup commands
    local count
    count="$(printf '%s\n' "$HI_STDOUT" | wc -l | tr -d ' ')"
    [[ "$count" -gt 3 ]] || {
        printf '    expected more than 3 matches (got %s) due to regex injection\n' "$count"
        return 1
    }
}

test_regex_pipe_needle_matches_multiple() {
    # "curl|ls" as needle matches both curl and ls commands
    local hist
    hist="$(printf '%s\n' "curl aaa" "ls -la" "echo hello")"
    run_hi "$hist" '"curl|ls" 10'
    assert_contains "$HI_STDOUT" "curl aaa" "curl matched" &&
    assert_contains "$HI_STDOUT" "ls -la" "ls matched" &&
    assert_not_contains "$HI_STDOUT" "echo" "echo not matched"
}

test_regex_bracket_needle() {
    # "[cC]url" as needle matches curl and Curl
    local hist
    hist="$(printf '%s\n' "curl aaa" "Curl bbb" "echo hello")"
    run_hi "$hist" '"[cC]url" 10'
    assert_contains "$HI_STDOUT" "curl aaa" "lowercase matched" &&
    assert_contains "$HI_STDOUT" "Curl bbb" "uppercase matched"
}

test_history_with_tab_characters() {
    local hist
    hist="$(printf '%s\n' "echo	hello" "ls")"
    run_hi "$hist" "echo"
    assert_contains "$HI_STDOUT" "echo" "tab-containing line matched"
}

test_needle_with_leading_whitespace() {
    # A needle with a leading space won't match because the regex anchors
    # to start-of-line then optional whitespace then the needle
    local hist
    hist="$(printf '%s\n' "curl aaa" "echo hello")"
    run_hi "$hist" '" curl"'
    assert_eq "" "$HI_STDOUT" "leading-space needle matches nothing"
}

run_edge_cases_tests() {
    printf '\033[1mEdge cases\033[0m\n'
    run_test test_empty_history
    run_test test_single_match_in_history
    run_test test_special_chars_in_command
    run_test test_command_with_dollar_sign
    run_test test_regex_dot_star_needle_matches_everything
    run_test test_regex_pipe_needle_matches_multiple
    run_test test_regex_bracket_needle
    run_test test_history_with_tab_characters
    run_test test_needle_with_leading_whitespace
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_edge_cases_tests
    print_summary
fi
