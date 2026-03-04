#!/usr/bin/env bash
# Category: Config file sourcing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_config_default_count_used() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb" "curl ccc" "curl ddd" "curl eee")"
    run_hi "$hist" "curl" "default_count=3"
    assert_line_count 3 "$HI_STDOUT" "config default_count=3 yields 3"
}

test_config_overridden_by_explicit_count() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb" "curl ccc" "curl ddd")"
    run_hi "$hist" "curl 2" "default_count=10"
    assert_line_count 2 "$HI_STDOUT" "explicit count=2 overrides config"
}

test_no_config_defaults_to_one() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb" "curl ccc")"
    run_hi "$hist" "curl"
    assert_line_count 1 "$HI_STDOUT" "no config means default 1"
}

test_config_invalid_non_integer_rejected() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb")"
    run_hi "$hist" "curl" "default_count=abc"
    assert_contains "$HI_STDERR" "nonzero positive int" "bad config caught"
}

test_config_invalid_zero_rejected() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb")"
    run_hi "$hist" "curl" "default_count=0"
    assert_contains "$HI_STDERR" "nonzero positive int" "zero config caught"
}

test_config_invalid_negative_rejected() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb")"
    run_hi "$hist" "curl" "default_count=-5"
    assert_contains "$HI_STDERR" "nonzero positive int" "negative config caught"
}

test_config_explicit_count_bypasses_bad_config() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb" "curl ccc")"
    run_hi "$hist" "curl 2" "default_count=abc"
    assert_line_count 2 "$HI_STDOUT" "explicit count overrides bad config"
}

run_config_tests() {
    printf '\033[1mConfig sourcing\033[0m\n'
    run_test test_config_default_count_used
    run_test test_config_overridden_by_explicit_count
    run_test test_no_config_defaults_to_one
    run_test test_config_invalid_non_integer_rejected
    run_test test_config_invalid_zero_rejected
    run_test test_config_invalid_negative_rejected
    run_test test_config_explicit_count_bypasses_bad_config
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_config_tests
    print_summary
fi
