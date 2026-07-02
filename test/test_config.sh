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

test_config_invalid_non_integer_falls_back() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb")"
    run_hi "$hist" "curl" "default_count=abc"
    assert_contains "$HI_STDERR" "invalid default_count" "bad config warned" &&
    assert_line_count 1 "$HI_STDOUT" "falls back to default 1"
}

test_config_invalid_zero_falls_back() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb")"
    run_hi "$hist" "curl" "default_count=0"
    assert_contains "$HI_STDERR" "invalid default_count" "zero config warned" &&
    assert_line_count 1 "$HI_STDOUT" "falls back to default 1"
}

test_config_invalid_negative_falls_back() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb")"
    run_hi "$hist" "curl" "default_count=-5"
    assert_contains "$HI_STDERR" "invalid default_count" "negative config warned" &&
    assert_line_count 1 "$HI_STDOUT" "falls back to default 1"
}

test_config_explicit_count_bypasses_bad_config() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb" "curl ccc")"
    run_hi "$hist" "curl 2" "default_count=abc"
    assert_line_count 2 "$HI_STDOUT" "explicit count overrides bad config"
}

test_config_empty_value_falls_back() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb")"
    run_hi "$hist" "curl" "default_count="
    assert_contains "$HI_STDERR" "invalid default_count" "empty value warned" &&
    assert_line_count 1 "$HI_STDOUT" "empty value falls back to 1"
}

test_config_float_value_falls_back() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb")"
    run_hi "$hist" "curl" "default_count=2.5"
    assert_contains "$HI_STDERR" "invalid default_count" "float value warned" &&
    assert_line_count 1 "$HI_STDOUT" "float value falls back to 1"
}

test_config_large_valid_value_used() {
    local hist
    hist="$(printf '%s\n' "curl a" "curl b" "curl c" "curl d" "curl e")"
    run_hi "$hist" "curl" "default_count=100"
    assert_line_count 5 "$HI_STDOUT" "large default returns all available matches" &&
    assert_not_contains "$HI_STDERR" "invalid default_count" "valid config produces no warning"
}

test_config_last_default_count_line_wins() {
    # The config reader overwrites on each matching line, so the last one wins.
    local hist config
    hist="$(printf '%s\n' "curl a" "curl b" "curl c" "curl d")"
    config="$(printf '%s\n' "default_count=1" "default_count=3")"
    run_hi "$hist" "curl" "$config"
    assert_line_count 3 "$HI_STDOUT" "last default_count line takes effect"
}

test_config_unrelated_lines_ignored() {
    local hist config
    hist="$(printf '%s\n' "curl a" "curl b" "curl c")"
    config="$(printf '%s\n' "# a comment" "some_other_key=99" "default_count=2")"
    run_hi "$hist" "curl" "$config"
    assert_line_count 2 "$HI_STDOUT" "only default_count is read; other lines ignored" &&
    assert_not_contains "$HI_STDERR" "invalid default_count" "no warning for well-formed config with extra lines"
}

test_config_leading_zero_value_honored() {
    # M1: a config value with a leading zero (default_count=08) must be read as
    # decimal 8, not rejected as octal by bash arithmetic. Assert on stderr
    # (no arithmetic error, no invalid warning) rather than an exact match count
    # so the test is robust to the sandbox's history-doubling artifact.
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb")"
    run_hi "$hist" "curl" "default_count=08"
    assert_not_contains "$HI_STDERR" "value too great" "08 not parsed as octal" &&
    assert_not_contains "$HI_STDERR" "invalid default_count" "08 honored, not rejected"
}

test_config_default_unique_true_dedups() {
    # A plain search (no -u) must dedup when default_unique=true. Seed byte-
    # identical matches: they collapse to exactly 1 under dedup regardless of the
    # sandbox history-doubling artifact, so the count is deterministic.
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl aaa" "echo hello" "curl aaa")"
    run_hi "$hist" "curl 10" "default_unique=true"
    assert_line_count 1 "$HI_STDOUT" "default_unique=true dedups without -u" &&
    assert_not_contains "$HI_STDERR" "invalid default_unique" "valid value produces no warning"
}

test_config_default_unique_false_no_dedup() {
    # default_unique=false leaves the default behavior untouched: duplicates are
    # all returned. Mirrors test_no_flag_path_unchanged (asserts exactly 3).
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl aaa" "curl aaa")"
    run_hi "$hist" "curl 10" "default_unique=false"
    assert_line_count 3 "$HI_STDOUT" "default_unique=false returns all duplicates" &&
    assert_not_contains "$HI_STDERR" "invalid default_unique" "valid value produces no warning"
}

test_config_default_unique_absent_no_dedup() {
    # Absence of default_unique is normal (not corrupt): silently false, no
    # warning, duplicates all returned.
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl aaa" "curl aaa")"
    run_hi "$hist" "curl 10" "default_count=10"
    assert_line_count 3 "$HI_STDOUT" "absent default_unique behaves as false" &&
    assert_not_contains "$HI_STDERR" "invalid default_unique" "absent key produces no warning"
}

test_config_default_unique_empty_warns() {
    # A present-but-EMPTY line (default_unique=) is garbage, not absence, so it
    # warns and falls back to false — the _wdi_unique_seen sentinel is what lets
    # the loader tell "present but empty" apart from "absent".
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl aaa" "curl aaa")"
    run_hi "$hist" "curl 10" "default_unique="
    assert_contains "$HI_STDERR" "invalid default_unique" "empty value warned" &&
    assert_line_count 3 "$HI_STDOUT" "empty value falls back to false (no dedup)"
}

test_config_default_unique_bogus_warns() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl aaa" "curl aaa")"
    run_hi "$hist" "curl 10" "default_unique=bogus"
    assert_contains "$HI_STDERR" "invalid default_unique" "bogus value warned" &&
    assert_line_count 3 "$HI_STDOUT" "bogus value falls back to false (no dedup)"
}

test_config_default_unique_capitalized_warns() {
    # Only lowercase true/false are valid; True is invalid and must warn + fall
    # back to false.
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl aaa" "curl aaa")"
    run_hi "$hist" "curl 10" "default_unique=True"
    assert_contains "$HI_STDERR" "invalid default_unique" "capitalized True warned" &&
    assert_line_count 3 "$HI_STDOUT" "True falls back to false (no dedup)"
}

test_config_both_keys_coexist() {
    # Both keys together take effect at once. With default_count=3 AND
    # default_unique=true, a search with NO explicit count reads the count (3)
    # from config and dedups. The history has only 2 DISTINCT matches (with dups
    # interleaved), so the deduped result is 2 — a count that could ONLY happen if
    # BOTH keys were honored: default 1 would give 1, and no-dedup would give 3.
    # Byte-identical dups make this robust to history-doubling.
    local hist config
    hist="$(printf '%s\n' "curl aaa" "curl bbb" "curl aaa" "curl bbb" "curl aaa")"
    config="$(printf '%s\n' "default_count=3" "default_unique=true")"
    run_hi "$hist" "curl" "$config"
    assert_line_count 2 "$HI_STDOUT" "count=3 + unique=true yields the 2 distinct matches" &&
    assert_not_contains "$HI_STDERR" "invalid default_unique" "valid config produces no warning"
}

run_config_tests() {
    printf '\033[1mConfig sourcing\033[0m\n'
    run_test test_config_default_count_used
    run_test test_config_overridden_by_explicit_count
    run_test test_no_config_defaults_to_one
    run_test test_config_invalid_non_integer_falls_back
    run_test test_config_invalid_zero_falls_back
    run_test test_config_invalid_negative_falls_back
    run_test test_config_explicit_count_bypasses_bad_config
    run_test test_config_empty_value_falls_back
    run_test test_config_float_value_falls_back
    run_test test_config_large_valid_value_used
    run_test test_config_last_default_count_line_wins
    run_test test_config_unrelated_lines_ignored
    run_test test_config_leading_zero_value_honored
    run_test test_config_default_unique_true_dedups
    run_test test_config_default_unique_false_no_dedup
    run_test test_config_default_unique_absent_no_dedup
    run_test test_config_default_unique_empty_warns
    run_test test_config_default_unique_bogus_warns
    run_test test_config_default_unique_capitalized_warns
    run_test test_config_both_keys_coexist
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_config_tests
    print_summary
fi
