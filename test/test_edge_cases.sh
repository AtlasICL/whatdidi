#!/usr/bin/env bash
# Category: Edge cases

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

test_metachar_command_matched_literally() {
    # Command names containing regex metacharacters must be found — the needle
    # is matched literally, not compiled into a regex.
    local hist
    hist="$(printf '%s\n' "g++ main.cpp -o main" "c++ other.cpp" "echo hello")"
    run_hi "$hist" '"g++"'
    assert_contains "$HI_STDOUT" "g++ main.cpp -o main" "g++ matched literally" &&
    assert_not_contains "$HI_STDOUT" "c++" "g++ needle does not match c++"
}

test_regex_metachars_are_inert() {
    # A needle with regex metacharacters is NOT interpreted as a regex:
    # ".*" / "curl|ls" / "[cC]url" match nothing because no literal command
    # is named that.
    local hist
    hist="$(printf '%s\n' "curl aaa" "ls -la" "echo hello")"
    run_hi "$hist" '".*" 100'
    assert_eq "" "$HI_STDOUT" "dot-star matches nothing literally"
    run_hi "$hist" '"curl|ls" 10'
    assert_eq "" "$HI_STDOUT" "alternation matches nothing literally"
    run_hi "$hist" '"[cC]url" 10'
    assert_eq "" "$HI_STDOUT" "bracket class matches nothing literally"
}

test_dot_needle_not_wildcard() {
    # "." is a regex "any char"; as a literal needle it must not match a
    # differently-named command like "cat".
    local hist
    hist="$(printf '%s\n' "cat file" "ls -la")"
    run_hi "$hist" '"." 10'
    assert_eq "" "$HI_STDOUT" "'.' does not wildcard-match cat"
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
    run_test test_metachar_command_matched_literally
    run_test test_regex_metachars_are_inert
    run_test test_dot_needle_not_wildcard
    run_test test_history_with_tab_characters
    run_test test_needle_with_leading_whitespace
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_edge_cases_tests
    print_summary
fi
