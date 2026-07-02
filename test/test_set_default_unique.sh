#!/usr/bin/env bash
# Category: --set-default-unique

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_set_default_unique_true_exits_zero() {
    run_ni --set-default-unique true
    assert_eq 0 "$NI_EXIT" "exit code"
}

test_set_default_unique_true_prints_confirmation() {
    run_ni --set-default-unique true
    assert_contains "$NI_STDOUT" "default unique set to true"
}

test_set_default_unique_false_prints_confirmation() {
    run_ni --set-default-unique false
    assert_contains "$NI_STDOUT" "default unique set to false"
}

test_set_default_unique_creates_dir() {
    run_ni --set-default-unique true
    [[ -d "$TEST_HOME/.config/whatdidi" ]] || {
        printf '    directory not created\n'; return 1
    }
}

test_set_default_unique_writes_true() {
    run_ni --set-default-unique true
    local n
    n="$(count_lines_matching "$TEST_HOME/.config/whatdidi/config" "default_unique=true")"
    assert_eq 0 "$NI_EXIT" "exit code" &&
    assert_eq 1 "$n" "config holds exactly one default_unique=true line"
}

test_set_default_unique_writes_false() {
    run_ni --set-default-unique false
    local n
    n="$(count_lines_matching "$TEST_HOME/.config/whatdidi/config" "default_unique=false")"
    assert_eq 0 "$NI_EXIT" "exit code" &&
    assert_eq 1 "$n" "config holds exactly one default_unique=false line"
}

test_set_default_unique_missing_value_returns_2() {
    run_ni --set-default-unique
    assert_eq 2 "$NI_EXIT" "exit code" &&
    assert_contains "$NI_STDERR" "true" "error mentions valid values" &&
    assert_contains "$NI_STDERR" "false" "error mentions valid values"
}

test_set_default_unique_invalid_value_returns_2() {
    run_ni --set-default-unique bogus
    assert_eq 2 "$NI_EXIT" "exit code" &&
    assert_contains "$NI_STDERR" "true" "error mentions valid values"
}

test_set_default_unique_capitalized_true_returns_2() {
    # Only the lowercase spellings are valid, so an uppercased True is rejected —
    # this keeps the persisted value round-tripping cleanly with the loader,
    # which likewise accepts lowercase only.
    run_ni --set-default-unique True
    assert_eq 2 "$NI_EXIT" "exit code"
}

test_set_default_unique_numeric_one_returns_2() {
    # 1 is a common truthy spelling elsewhere but is NOT accepted here; only
    # literal true/false round-trip with the loader.
    run_ni --set-default-unique 1
    assert_eq 2 "$NI_EXIT" "exit code"
}

test_set_default_unique_no_duplicate() {
    # Setting the default twice must not accumulate duplicate default_unique=
    # lines — the previous one is dropped and only the latest value remains.
    run_ni --set-default-unique true
    run_ni --set-default-unique false
    local kept dropped
    kept="$(count_lines_matching "$TEST_HOME/.config/whatdidi/config" "default_unique=false")"
    dropped="$(count_lines_matching "$TEST_HOME/.config/whatdidi/config" "default_unique=true")"
    assert_eq 1 "$kept" "exactly one default_unique line remains (latest value)" &&
    assert_eq 0 "$dropped" "old value dropped"
}

test_set_default_unique_preserves_default_count() {
    # KEY-ISOLATION: the two setters must never clobber each other's key. Seed a
    # config that already holds default_count=5, then --set-default-unique true
    # and confirm default_count=5 SURVIVES verbatim while default_unique=true is
    # added alongside it.
    mkdir -p "$TEST_HOME/.config/whatdidi"
    printf 'default_count=5\n' > "$TEST_HOME/.config/whatdidi/config"
    run_ni --set-default-unique true
    local content
    content="$(cat "$TEST_HOME/.config/whatdidi/config")"
    assert_eq 0 "$NI_EXIT" "exit code" &&
    assert_contains "$content" "default_count=5" "default_count preserved" &&
    assert_contains "$content" "default_unique=true" "default_unique added"
}

test_set_default_count_preserves_default_unique() {
    # KEY-ISOLATION (symmetric direction): seed default_unique=true, then run the
    # count setter and confirm default_unique=true SURVIVES while default_count=5
    # is added — neither setter clobbers the other's key.
    mkdir -p "$TEST_HOME/.config/whatdidi"
    printf 'default_unique=true\n' > "$TEST_HOME/.config/whatdidi/config"
    run_ni --set-default-count 5
    local content
    content="$(cat "$TEST_HOME/.config/whatdidi/config")"
    assert_eq 0 "$NI_EXIT" "exit code" &&
    assert_contains "$content" "default_unique=true" "default_unique preserved" &&
    assert_contains "$content" "default_count=5" "default_count added"
}

test_set_default_unique_preserves_unrelated_key() {
    # An unrelated hand-added key must survive a default_unique write verbatim.
    mkdir -p "$TEST_HOME/.config/whatdidi"
    printf 'some_other_key=99\n' > "$TEST_HOME/.config/whatdidi/config"
    run_ni --set-default-unique true
    local content
    content="$(cat "$TEST_HOME/.config/whatdidi/config")"
    assert_eq 0 "$NI_EXIT" "exit code" &&
    assert_contains "$content" "some_other_key=99" "unrelated key preserved" &&
    assert_contains "$content" "default_unique=true" "default_unique added"
}

test_set_default_unique_preserves_symlinked_config() {
    # When the config file is a symlink (common with dotfile managers) the rewrite
    # must happen in place via `cat >` so the symlink survives and the real target
    # is updated — `mv` would replace the symlink with a regular file and orphan
    # the real target. Mirrors test_set_default_preserves_symlinked_config. Keep
    # both the symlink and its target under TEST_HOME so the test stays hermetic.
    mkdir -p "$TEST_HOME/.config/whatdidi"
    printf 'some_other_key=42\n' > "$TEST_HOME/real_config"
    ln -s "$TEST_HOME/real_config" "$TEST_HOME/.config/whatdidi/config"
    run_ni --set-default-unique true
    local target
    target="$(cat "$TEST_HOME/real_config")"
    assert_eq 0 "$NI_EXIT" "exit code" &&
    { [[ -L "$TEST_HOME/.config/whatdidi/config" ]] || {
        printf '    config should still be a symlink after --set-default-unique\n'; return 1
    }; } &&
    assert_contains "$target" "default_unique=true" "default_unique written to the real target" &&
    assert_contains "$target" "some_other_key=42" "unrelated key preserved in the real target"
}

# --- zsh parity ------------------------------------------------------------

test_zsh_set_default_unique_persists() {
    run_ni_zsh --set-default-unique true
    local n
    n="$(count_lines_matching "$TEST_HOME/.config/whatdidi/config" "default_unique=true")"
    assert_eq 0 "$NI_EXIT" "exit code" &&
    assert_eq 1 "$n" "config holds default_unique=true under zsh"
}

run_set_default_unique_tests() {
    printf '\033[1m--set-default-unique\033[0m\n'
    run_test test_set_default_unique_true_exits_zero
    run_test test_set_default_unique_true_prints_confirmation
    run_test test_set_default_unique_false_prints_confirmation
    run_test test_set_default_unique_creates_dir
    run_test test_set_default_unique_writes_true
    run_test test_set_default_unique_writes_false
    run_test test_set_default_unique_missing_value_returns_2
    run_test test_set_default_unique_invalid_value_returns_2
    run_test test_set_default_unique_capitalized_true_returns_2
    run_test test_set_default_unique_numeric_one_returns_2
    run_test test_set_default_unique_no_duplicate
    run_test test_set_default_unique_preserves_default_count
    run_test test_set_default_count_preserves_default_unique
    run_test test_set_default_unique_preserves_unrelated_key
    run_test test_set_default_unique_preserves_symlinked_config
    if command -v zsh >/dev/null 2>&1; then
        run_test test_zsh_set_default_unique_persists
    else
        printf '  \033[33mSKIP\033[0m  test_zsh_set_default_unique_persists (zsh not installed)\n'
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_set_default_unique_tests
    print_summary
fi
