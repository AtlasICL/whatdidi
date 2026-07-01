#!/usr/bin/env bash
# Category: zsh compatibility
#
# This file runs under bash (like the rest of the suite) but exercises the
# whatdidi function under zsh via run_ni_zsh / run_hi_zsh. It mirrors the core
# scenarios from the bash categories so the zsh code path gets equivalent
# coverage. If zsh is not installed, the whole category is skipped (not failed)
# so bash-only dev machines stay green.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# --- History search (run_hi_zsh) ---

test_zsh_simple_match() {
    local hist
    hist="$(printf '%s\n' "ls -la" "curl https://example.com" "echo hello")"
    run_hi_zsh "$hist" "curl"
    assert_contains "$HI_STDOUT" "curl https://example.com"
}

test_zsh_no_match_empty_output() {
    local hist
    hist="$(printf '%s\n' "ls -la" "echo hello")"
    run_hi_zsh "$hist" "nonexistent"
    assert_eq "" "$HI_STDOUT" "no output for no match"
}

test_zsh_default_returns_one_result() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb" "curl ccc")"
    run_hi_zsh "$hist" "curl"
    assert_line_count 1 "$HI_STDOUT" "default count is 1"
}

test_zsh_explicit_count_returns_n() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb" "curl ccc" "curl ddd")"
    run_hi_zsh "$hist" "curl 3"
    assert_line_count 3 "$HI_STDOUT" "count=3 returns 3"
}

test_zsh_count_exceeds_matches() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb" "echo other")"
    run_hi_zsh "$hist" "curl 10"
    assert_line_count 2 "$HI_STDOUT" "only 2 matches exist"
}

test_zsh_most_recent_first() {
    local hist
    hist="$(printf '%s\n' "curl first" "curl second" "curl third")"
    run_hi_zsh "$hist" "curl 3"
    local first_line
    first_line="$(printf '%s\n' "$HI_STDOUT" | head -1)"
    assert_eq "curl third" "$first_line" "most recent entry first"
}

test_zsh_duplicate_entries_all_returned() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl aaa" "curl aaa")"
    run_hi_zsh "$hist" "curl 10"
    assert_line_count 3 "$HI_STDOUT" "all 3 duplicates returned"
}

test_zsh_finds_command_older_than_16() {
    # The whole reason zsh needs `fc -rl 1`: bare `history`/`fc -l` defaults to
    # the last 16 events, so a match further back would be invisible. Seed 30+
    # commands with the only match at the very start and confirm it is found.
    local hist lines=() i
    lines+=("curl ancient-match")
    for i in $(seq 1 30); do lines+=("echo pad$i"); done
    hist="$(printf '%s\n' "${lines[@]}")"
    run_hi_zsh "$hist" "curl"
    assert_contains "$HI_STDOUT" "curl ancient-match" "match older than 16 events found"
}

test_zsh_compound_needle_match() {
    local hist
    hist="$(printf '%s\n' "git status" "git push origin main" "git pull")"
    run_hi_zsh "$hist" '"git push"'
    assert_contains "$HI_STDOUT" "git push origin main"
}

test_zsh_compound_excludes_partial() {
    local hist
    hist="$(printf '%s\n' "git push origin main" "git pull" "git status")"
    run_hi_zsh "$hist" '"git push" 10'
    assert_not_contains "$HI_STDOUT" "git pull" "git pull is not git push" &&
    assert_not_contains "$HI_STDOUT" "git status" "git status is not git push"
}

test_zsh_sudo_prefix_matched() {
    local hist
    hist="$(printf '%s\n' "echo hello" "sudo rm -rf /tmp/junk")"
    run_hi_zsh "$hist" "rm"
    assert_contains "$HI_STDOUT" "sudo rm -rf /tmp/junk"
}

test_zsh_sudo_and_plain_both_matched() {
    local hist
    hist="$(printf '%s\n' "rm foo.txt" "sudo rm bar.txt" "echo other")"
    run_hi_zsh "$hist" "rm 5"
    assert_contains "$HI_STDOUT" "rm foo.txt" &&
    assert_contains "$HI_STDOUT" "sudo rm bar.txt"
}

test_zsh_word_boundary_no_prefix_match() {
    local hist
    hist="$(printf '%s\n' "git status" "gitk --all")"
    run_hi_zsh "$hist" "git 10"
    assert_contains "$HI_STDOUT" "git status" "git matches" &&
    assert_not_contains "$HI_STDOUT" "gitk" "gitk is not matched by git"
}

test_zsh_skips_whatdidi_invocations() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "whatdidi curl" "curl bbb")"
    run_hi_zsh "$hist" "curl 10"
    assert_not_contains "$HI_STDOUT" "whatdidi" "whatdidi lines excluded" &&
    assert_line_count 2 "$HI_STDOUT" "only real curl commands"
}

test_zsh_searching_for_whatdidi_returns_matches() {
    local hist
    hist="$(printf '%s\n' "whatdidi curl" "whatdidi git 5" "echo hello")"
    run_hi_zsh "$hist" "whatdidi 10"
    assert_contains "$HI_STDOUT" "whatdidi curl" "whatdidi invocation found" &&
    assert_contains "$HI_STDOUT" "whatdidi git 5" "whatdidi invocation found"
}

test_zsh_special_chars_in_command() {
    local hist
    hist="$(printf '%s\n' "echo hello | grep h" "ls > /tmp/out" "echo done")"
    run_hi_zsh "$hist" "echo 10"
    assert_contains "$HI_STDOUT" "echo hello | grep h" "pipe preserved"
}

test_zsh_command_with_dollar_sign() {
    local hist
    hist="$(printf '%s\n' 'echo $HOME' "ls")"
    run_hi_zsh "$hist" "echo"
    assert_contains "$HI_STDOUT" 'echo $HOME' "dollar sign preserved"
}

test_zsh_metachar_command_matched_literally() {
    # The needle is matched literally under zsh too, so g++ is found and does
    # not accidentally match c++.
    local hist
    hist="$(printf '%s\n' "g++ main.cpp -o main" "c++ other.cpp" "echo hello")"
    run_hi_zsh "$hist" '"g++"'
    assert_contains "$HI_STDOUT" "g++ main.cpp -o main" "g++ matched literally" &&
    assert_not_contains "$HI_STDOUT" "c++" "g++ needle does not match c++"
}

test_zsh_default_count_from_config() {
    local hist
    hist="$(printf '%s\n' "curl a" "curl b" "curl c" "curl d")"
    run_hi_zsh "$hist" "curl" "default_count=3"
    assert_line_count 3 "$HI_STDOUT" "config default_count=3 honored"
}

test_zsh_exit_code_on_match() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "echo hello")"
    run_hi_zsh "$hist" "curl"
    assert_eq 0 "$HI_EXIT" "exit code 0 on match"
}

test_zsh_exit_code_zero_when_count_unmet() {
    # Exposes a bash/zsh exit-code divergence: when the match is the oldest
    # (last-processed) line and the requested count is never exhausted, the
    # loop's leaked status is nonzero under zsh. whatdidi must still report 0.
    local hist
    hist="$(printf '%s\n' "curl target" "echo a" "echo b")"
    run_hi_zsh "$hist" "curl 5"
    assert_eq 0 "$HI_EXIT" "exit 0 regardless of where the match falls"
}

# --- Early-return paths (run_ni_zsh) ---

test_zsh_version() {
    run_ni_zsh --version
    assert_eq 0 "$NI_EXIT" "exit code" &&
    assert_contains "$NI_STDOUT" "whatdidi" "has program name" &&
    assert_contains "$NI_STDOUT" "1.1.0" "has version number"
}

test_zsh_v_flag_same_as_version() {
    run_ni_zsh --version
    local version_out="$NI_STDOUT"
    run_ni_zsh -v
    assert_eq "$version_out" "$NI_STDOUT" "-v and --version output identical"
}

test_zsh_help() {
    run_ni_zsh --help
    assert_eq 0 "$NI_EXIT" "exit code" &&
    assert_contains "$NI_STDOUT" "Usage:" "has Usage section" &&
    assert_contains "$NI_STDOUT" "whatdidi <command> [count]" "shows syntax"
}

test_zsh_no_args_returns_2() {
    run_ni_zsh
    assert_eq 2 "$NI_EXIT" "exit code" &&
    assert_contains "$NI_STDERR" "Usage:" "usage on stderr"
}

test_zsh_count_zero_returns_2() {
    run_ni_zsh curl 0
    assert_eq 2 "$NI_EXIT" "exit code"
}

test_zsh_count_non_integer_returns_2() {
    run_ni_zsh curl abc
    assert_eq 2 "$NI_EXIT" "exit code" &&
    assert_contains "$NI_STDERR" "nonzero positive int" "error message"
}

test_zsh_set_default_persists() {
    run_ni_zsh --set-default 7
    assert_eq 0 "$NI_EXIT" "exit code" &&
    local content
    content="$(cat "$TEST_HOME/.config/whatdidi/config")"
    assert_eq "default_count=7" "$content"
}

test_zsh_set_default_bad_value_returns_2() {
    run_ni_zsh --set-default 0
    assert_eq 2 "$NI_EXIT" "exit code"
}

run_zsh_tests() {
    printf '\033[1mzsh compatibility\033[0m\n'
    if ! command -v zsh >/dev/null 2>&1; then
        printf '  \033[33mSKIP\033[0m  zsh not installed\n'
        return 0
    fi

    run_test test_zsh_simple_match
    run_test test_zsh_no_match_empty_output
    run_test test_zsh_default_returns_one_result
    run_test test_zsh_explicit_count_returns_n
    run_test test_zsh_count_exceeds_matches
    run_test test_zsh_most_recent_first
    run_test test_zsh_duplicate_entries_all_returned
    run_test test_zsh_finds_command_older_than_16
    run_test test_zsh_compound_needle_match
    run_test test_zsh_compound_excludes_partial
    run_test test_zsh_sudo_prefix_matched
    run_test test_zsh_sudo_and_plain_both_matched
    run_test test_zsh_word_boundary_no_prefix_match
    run_test test_zsh_skips_whatdidi_invocations
    run_test test_zsh_searching_for_whatdidi_returns_matches
    run_test test_zsh_special_chars_in_command
    run_test test_zsh_command_with_dollar_sign
    run_test test_zsh_metachar_command_matched_literally
    run_test test_zsh_default_count_from_config
    run_test test_zsh_exit_code_on_match
    run_test test_zsh_exit_code_zero_when_count_unmet
    run_test test_zsh_version
    run_test test_zsh_v_flag_same_as_version
    run_test test_zsh_help
    run_test test_zsh_no_args_returns_2
    run_test test_zsh_count_zero_returns_2
    run_test test_zsh_count_non_integer_returns_2
    run_test test_zsh_set_default_persists
    run_test test_zsh_set_default_bad_value_returns_2
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_zsh_tests
    print_summary
fi
