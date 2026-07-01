#!/usr/bin/env bash
# Category: Literal matching depth
#
# The needle is matched literally (never compiled to a regex). These tests pin
# that real command names containing regex metacharacters are found, that
# metacharacters are inert, and that word-boundary/sudo behavior holds — none of
# which should regress if the matching internals are touched again.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# --- Real commands with metacharacters are found ---

test_lit_gpp_found() {
    local hist
    hist="$(printf '%s\n' "g++ -O2 main.cpp" "gcc x.c" "echo done")"
    run_hi "$hist" '"g++"'
    assert_contains "$HI_STDOUT" "g++ -O2 main.cpp" "g++ found literally"
}

test_lit_cpp_found_and_distinct_from_gpp() {
    local hist
    hist="$(printf '%s\n' "g++ a.cpp" "c++ b.cpp" "clang c.cpp")"
    run_hi "$hist" '"c++" 10'
    assert_contains "$HI_STDOUT" "c++ b.cpp" "c++ found" &&
    assert_not_contains "$HI_STDOUT" "g++" "c++ needle does not match g++"
}

test_lit_dotslash_configure_found() {
    local hist
    hist="$(printf '%s\n' "./configure --prefix=/usr" "make" "echo hi")"
    run_hi "$hist" '"./configure"'
    assert_contains "$HI_STDOUT" "./configure --prefix=/usr" "./configure found literally"
}

test_lit_versioned_binary_found() {
    local hist
    hist="$(printf '%s\n' "python3.11 script.py" "python2 old.py")"
    run_hi "$hist" '"python3.11"'
    assert_contains "$HI_STDOUT" "python3.11 script.py" "dotted version matched" &&
    assert_not_contains "$HI_STDOUT" "python2" "python3.11 needle does not match python2"
}

test_lit_bracket_needle_no_crash() {
    # "[" is an unbalanced bracket as a regex and previously errored on every
    # line. As a literal it must simply match the `[` test command.
    local hist
    hist="$(printf '%s\n' "[ -f /etc/hosts ]" "echo hi")"
    run_hi "$hist" '"[" 10'
    assert_contains "$HI_STDOUT" "[ -f /etc/hosts ]" "'[' matched literally" &&
    assert_not_contains "$HI_STDERR" "error" "no regex/syntax error on stderr"
}

# --- Metacharacters are inert (do not act as regex) ---

test_lit_dot_not_wildcard() {
    local hist
    hist="$(printf '%s\n' "cat file" "car go" "cut x")"
    run_hi "$hist" '"c.t" 10'
    assert_eq "" "$HI_STDOUT" "'c.t' does not match cat/cut"
}

test_lit_star_inert() {
    local hist
    hist="$(printf '%s\n' "curl a" "curl b" "echo c")"
    run_hi "$hist" '"cur*" 10'
    assert_eq "" "$HI_STDOUT" "'cur*' is not a glob/regex, matches nothing"
}

test_lit_alternation_inert() {
    local hist
    hist="$(printf '%s\n' "curl a" "ls -l" "echo c")"
    run_hi "$hist" '"curl|ls" 10'
    assert_eq "" "$HI_STDOUT" "alternation is inert"
}

test_lit_anchors_inert() {
    local hist
    hist="$(printf '%s\n' "curl a" "echo c")"
    run_hi "$hist" '"^curl" 10'
    assert_eq "" "$HI_STDOUT" "leading caret is literal, matches nothing"
}

# --- Word boundary holds with literal matching ---

test_lit_no_substring_prefix_match() {
    local hist
    hist="$(printf '%s\n' "git status" "github-cli auth" "git-lfs pull")"
    run_hi "$hist" '"git" 10'
    assert_contains "$HI_STDOUT" "git status" "git matched" &&
    assert_not_contains "$HI_STDOUT" "github-cli" "github not matched by git" &&
    assert_not_contains "$HI_STDOUT" "git-lfs" "git-lfs not matched by git"
}

test_lit_bare_command_matches() {
    local hist
    hist="$(printf '%s\n' "make" "makefile-thing run")"
    run_hi "$hist" '"make" 10'
    assert_contains "$HI_STDOUT" "make" "bare make matched" &&
    assert_not_contains "$HI_STDOUT" "makefile-thing" "make does not match makefile-thing"
}

# --- sudo transparency + literal ---

test_lit_sudo_metachar_command() {
    local hist
    hist="$(printf '%s\n' "echo hi" "sudo g++ -shared x.cpp")"
    run_hi "$hist" '"g++"'
    assert_contains "$HI_STDOUT" "sudo g++ -shared x.cpp" "sudo g++ matched literally"
}

test_lit_search_for_sudo_itself() {
    local hist
    hist="$(printf '%s\n' "sudo rm x" "rm y" "echo z")"
    run_hi "$hist" '"sudo" 10'
    assert_contains "$HI_STDOUT" "sudo rm x" "searching 'sudo' finds sudo commands" &&
    assert_not_contains "$HI_STDOUT" "rm y" "plain rm not matched by sudo needle"
}

test_lit_sudo_extra_whitespace() {
    # Multiple spaces between sudo and the command must still be transparent.
    local hist
    hist="$(printf '%s\n' "echo hi" "sudo    rm -rf /tmp/j")"
    run_hi "$hist" "rm"
    assert_contains "$HI_STDOUT" "sudo    rm -rf /tmp/j" "extra whitespace after sudo handled"
}

# --- Compound (multi-word) needle with metacharacters ---

test_lit_compound_with_flags() {
    local hist
    hist="$(printf '%s\n' "git log --oneline" "git log -p" "git status")"
    run_hi "$hist" '"git log --oneline" 10'
    assert_contains "$HI_STDOUT" "git log --oneline" "exact compound found" &&
    assert_not_contains "$HI_STDOUT" "git log -p" "different compound excluded"
}

run_literal_tests() {
    printf '\033[1mLiteral matching depth\033[0m\n'
    run_test test_lit_gpp_found
    run_test test_lit_cpp_found_and_distinct_from_gpp
    run_test test_lit_dotslash_configure_found
    run_test test_lit_versioned_binary_found
    run_test test_lit_bracket_needle_no_crash
    run_test test_lit_dot_not_wildcard
    run_test test_lit_star_inert
    run_test test_lit_alternation_inert
    run_test test_lit_anchors_inert
    run_test test_lit_no_substring_prefix_match
    run_test test_lit_bare_command_matches
    run_test test_lit_sudo_metachar_command
    run_test test_lit_search_for_sudo_itself
    run_test test_lit_sudo_extra_whitespace
    run_test test_lit_compound_with_flags
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_literal_tests
    print_summary
fi
