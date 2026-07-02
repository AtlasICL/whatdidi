#!/usr/bin/env bash
# Category: --set-default

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_set_default_count_exits_zero() {
    run_ni --set-default 5
    assert_eq 0 "$NI_EXIT" "exit code"
}

test_set_default_count_prints_confirmation() {
    run_ni --set-default 5
    assert_contains "$NI_STDOUT" "default count set to 5"
}

test_set_default_count_creates_dir() {
    run_ni --set-default 3
    [[ -d "$TEST_HOME/.config/whatdidi" ]] || {
        printf '    directory not created\n'; return 1
    }
}

test_set_default_count_writes_config() {
    run_ni --set-default 7
    local content
    content="$(cat "$TEST_HOME/.config/whatdidi/config")"
    assert_eq "default_count=7" "$content"
}

test_set_default_count_overwrites() {
    run_ni --set-default 3
    run_ni --set-default 9
    local content
    content="$(cat "$TEST_HOME/.config/whatdidi/config")"
    assert_eq "default_count=9" "$content" "second write overwrites"
}

test_set_default_count_missing_value_returns_2() {
    run_ni --set-default
    assert_eq 2 "$NI_EXIT" "exit code" &&
    assert_contains "$NI_STDERR" "nonzero positive int" "error message"
}

test_set_default_count_zero_returns_2() {
    run_ni --set-default 0
    assert_eq 2 "$NI_EXIT" "exit code"
}

test_set_default_count_non_integer_returns_2() {
    run_ni --set-default abc
    assert_eq 2 "$NI_EXIT" "exit code"
}

test_set_default_count_large_value() {
    run_ni --set-default 999
    local content
    content="$(cat "$TEST_HOME/.config/whatdidi/config")"
    assert_eq 0 "$NI_EXIT" "exit code" &&
    assert_eq "default_count=999" "$content"
}

test_set_default_count_extra_args_ignored() {
    run_ni --set-default 5 extra
    local content
    content="$(cat "$TEST_HOME/.config/whatdidi/config")"
    assert_eq 0 "$NI_EXIT" "exit code" &&
    assert_eq "default_count=5" "$content" "extra arg silently ignored"
}

test_set_default_leading_zero_persisted_as_decimal() {
    # M1: --set-default 08 must be normalized to base-10 before it is written,
    # so the config reads default_count=8 (not 08, which bash would later choke
    # on as octal).
    run_ni --set-default 08
    local content
    content="$(cat "$TEST_HOME/.config/whatdidi/config")"
    assert_eq 0 "$NI_EXIT" "exit code" &&
    assert_eq "default_count=8" "$content" "08 persisted as decimal 8"
}

test_set_default_double_zero_returns_2() {
    # 00 normalizes to 0, which is below the minimum of 1, so it must be
    # rejected just like a plain 0.
    run_ni --set-default 00
    assert_eq 2 "$NI_EXIT" "exit code" &&
    assert_contains "$NI_STDERR" "nonzero positive int" "error message"
}

test_set_default_preserves_unrelated_key() {
    # BUG-6: writing default_count must not clobber other config keys. Seed the
    # config with an unrelated key, then --set-default and confirm BOTH the
    # unrelated key survives verbatim AND default_count is added.
    mkdir -p "$TEST_HOME/.config/whatdidi"
    printf 'some_other_key=42\n' > "$TEST_HOME/.config/whatdidi/config"
    run_ni --set-default 5
    local content
    content="$(cat "$TEST_HOME/.config/whatdidi/config")"
    assert_eq 0 "$NI_EXIT" "exit code" &&
    assert_contains "$content" "some_other_key=42" "unrelated key preserved" &&
    assert_contains "$content" "default_count=5" "default_count added"
}

test_set_default_no_duplicate_default_count() {
    # BUG-6: setting the default twice must not accumulate duplicate
    # default_count= lines — the previous one is dropped and only the latest
    # value remains.
    run_ni --set-default 3
    run_ni --set-default 9
    local total content
    content="$(cat "$TEST_HOME/.config/whatdidi/config")"
    # grep -c exits 1 when the count is 0, so tolerate a nonzero exit.
    total="$(grep -c '^default_count=' "$TEST_HOME/.config/whatdidi/config" 2>/dev/null || true)"
    assert_eq 1 "${total:-0}" "exactly one default_count line remains" &&
    assert_contains "$content" "default_count=9" "latest value kept" &&
    assert_not_contains "$content" "default_count=3" "old value dropped"
}

test_set_default_preserves_symlinked_config() {
    # BUG-6: when the config file is a symlink (common with dotfile managers) the
    # rewrite must happen in place via `cat >` so the symlink survives and the
    # real target is updated — `mv` would replace the symlink with a regular file
    # and orphan the real target. Mirrors test_uninstall_preserves_symlinked_rc.
    # Keep both the symlink and its target under TEST_HOME so the test stays
    # hermetic (run_ni sets HOME="$TEST_HOME").
    mkdir -p "$TEST_HOME/.config/whatdidi"
    printf 'some_other_key=42\n' > "$TEST_HOME/real_config"
    ln -s "$TEST_HOME/real_config" "$TEST_HOME/.config/whatdidi/config"
    run_ni --set-default 5
    local target
    target="$(cat "$TEST_HOME/real_config")"
    assert_eq 0 "$NI_EXIT" "exit code" &&
    { [[ -L "$TEST_HOME/.config/whatdidi/config" ]] || {
        printf '    config should still be a symlink after --set-default\n'; return 1
    }; } &&
    assert_contains "$target" "default_count=5" "default_count written to the real target" &&
    assert_contains "$target" "some_other_key=42" "unrelated key preserved in the real target"
}

run_set_default_tests() {
    printf '\033[1m--set-default\033[0m\n'
    run_test test_set_default_count_exits_zero
    run_test test_set_default_count_prints_confirmation
    run_test test_set_default_count_creates_dir
    run_test test_set_default_count_writes_config
    run_test test_set_default_count_overwrites
    run_test test_set_default_count_missing_value_returns_2
    run_test test_set_default_count_zero_returns_2
    run_test test_set_default_count_non_integer_returns_2
    run_test test_set_default_count_large_value
    run_test test_set_default_count_extra_args_ignored
    run_test test_set_default_leading_zero_persisted_as_decimal
    run_test test_set_default_double_zero_returns_2
    run_test test_set_default_preserves_unrelated_key
    run_test test_set_default_no_duplicate_default_count
    run_test test_set_default_preserves_symlinked_config
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_set_default_tests
    print_summary
fi
