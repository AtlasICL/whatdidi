#!/usr/bin/env bash
# Category: HISTTIMEFORMAT robustness (bash)
#
# Regression guard: when HISTTIMEFORMAT is set (common in dotfiles), bash's
# `history` prepends a timestamp column. whatdidi must clear it for its internal
# read so the timestamp doesn't leak past the sed and defeat matching. Before
# the fix, every search silently returned nothing.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# Common HISTTIMEFORMAT values seen in the wild.
_HTF_STANDARD='export HISTTIMEFORMAT="%F %T "'
_HTF_BRACKET='export HISTTIMEFORMAT="[%Y-%m-%d %H:%M:%S] "'
_HTF_EPOCH='export HISTTIMEFORMAT="%s "'

test_htf_standard_search_still_matches() {
    local hist
    hist="$(printf '%s\n' "ls -la" "curl https://example.com" "echo hello")"
    run_hi "$hist" "curl" "" "$_HTF_STANDARD"
    assert_contains "$HI_STDOUT" "curl https://example.com" "match found despite timestamp column"
}

test_htf_bracketed_format_matches() {
    local hist
    hist="$(printf '%s\n' "git status" "git push origin main")"
    run_hi "$hist" "git 10" "" "$_HTF_BRACKET"
    assert_contains "$HI_STDOUT" "git status" "bracketed timestamp format handled"
}

test_htf_epoch_format_matches() {
    local hist
    hist="$(printf '%s\n' "make build" "make test")"
    run_hi "$hist" "make 5" "" "$_HTF_EPOCH"
    assert_contains "$HI_STDOUT" "make build" "epoch timestamp format handled" &&
    assert_contains "$HI_STDOUT" "make test" "both make lines returned"
}

test_htf_count_still_respected() {
    local hist
    hist="$(printf '%s\n' "curl a" "curl b" "curl c" "curl d")"
    run_hi "$hist" "curl 2" "" "$_HTF_STANDARD"
    assert_line_count 2 "$HI_STDOUT" "count honored under HISTTIMEFORMAT"
}

test_htf_no_timestamp_leaks_into_output() {
    # The printed command must be the raw command, with no timestamp prefix.
    local hist
    hist="$(printf '%s\n' "curl target")"
    run_hi "$hist" "curl" "" "$_HTF_STANDARD"
    assert_eq "curl target" "$HI_STDOUT" "output is the bare command, no timestamp"
}

test_htf_order_preserved_newest_first() {
    # Reversal (awk) + timestamp-clearing must compose: results still come back
    # most-recent-first when HISTTIMEFORMAT is set.
    local hist
    hist="$(printf '%s\n' "curl first" "curl second" "curl third")"
    run_hi "$hist" "curl 3" "" "$_HTF_STANDARD"
    local expected
    expected="$(printf '%s\n' "curl third" "curl second" "curl first")"
    assert_eq "$expected" "$HI_STDOUT" "newest-first order preserved under HISTTIMEFORMAT"
}

test_htf_sudo_still_matches() {
    local hist
    hist="$(printf '%s\n' "echo hi" "sudo apt update")"
    run_hi "$hist" "apt" "" "$_HTF_STANDARD"
    assert_contains "$HI_STDOUT" "sudo apt update" "sudo match works under HISTTIMEFORMAT"
}

run_histtimeformat_tests() {
    printf '\033[1mHISTTIMEFORMAT robustness\033[0m\n'
    run_test test_htf_standard_search_still_matches
    run_test test_htf_bracketed_format_matches
    run_test test_htf_epoch_format_matches
    run_test test_htf_count_still_respected
    run_test test_htf_no_timestamp_leaks_into_output
    run_test test_htf_order_preserved_newest_first
    run_test test_htf_sudo_still_matches
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_histtimeformat_tests
    print_summary
fi
