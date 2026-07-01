#!/usr/bin/env bash
# Category: install script — rc-file wiring
#
# Exercises the install script against a sandboxed HOME with a no-op sudo shim,
# so the rc-file logic runs for real while the privileged /usr/local/bin copy is
# skipped. Pins: only append to rc files that already exist, never create a
# ~/.zshrc for a non-zsh user, fall back to creating ~/.bashrc if neither
# exists, and stay idempotent.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_install_creates_bashrc_when_neither_exists() {
    run_install
    assert_eq 0 "$INST_EXIT" "install succeeds" &&
    assert_eq 1 "$(count_lines_matching "$TEST_HOME/.bashrc" "$SOURCE_LINE")" "bashrc wired" &&
    [[ ! -e "$TEST_HOME/.zshrc" ]] || {
        printf '    ~/.zshrc should NOT be created when it did not exist\n'; return 1
    }
}

test_install_warns_when_creating_bashrc_fallback() {
    run_install
    assert_contains "$INST_STDOUT$INST_STDERR" "creating ~/.bashrc" "fallback is announced"
}

test_install_appends_to_existing_bashrc_only() {
    printf '%s\n' "# my bashrc" "alias ll='ls -l'" > "$TEST_HOME/.bashrc"
    run_install
    assert_eq 1 "$(count_lines_matching "$TEST_HOME/.bashrc" "$SOURCE_LINE")" "source line added" &&
    assert_contains "$(cat "$TEST_HOME/.bashrc")" "alias ll='ls -l'" "existing content preserved" &&
    [[ ! -e "$TEST_HOME/.zshrc" ]] || {
        printf '    ~/.zshrc should NOT be created for a bash-only user\n'; return 1
    }
}

test_install_appends_to_existing_zshrc_no_bashrc_created() {
    printf '%s\n' "# my zshrc" > "$TEST_HOME/.zshrc"
    run_install
    assert_eq 1 "$(count_lines_matching "$TEST_HOME/.zshrc" "$SOURCE_LINE")" "zshrc wired" &&
    [[ ! -e "$TEST_HOME/.bashrc" ]] || {
        printf '    ~/.bashrc should NOT be created when ~/.zshrc already exists\n'; return 1
    }
}

test_install_wires_both_when_both_exist() {
    printf '%s\n' "# bashrc" > "$TEST_HOME/.bashrc"
    printf '%s\n' "# zshrc" > "$TEST_HOME/.zshrc"
    run_install
    assert_eq 1 "$(count_lines_matching "$TEST_HOME/.bashrc" "$SOURCE_LINE")" "bashrc wired" &&
    assert_eq 1 "$(count_lines_matching "$TEST_HOME/.zshrc" "$SOURCE_LINE")" "zshrc wired"
}

test_install_idempotent_no_duplicate() {
    printf '%s\n' "# bashrc" > "$TEST_HOME/.bashrc"
    run_install
    run_install
    assert_eq 1 "$(count_lines_matching "$TEST_HOME/.bashrc" "$SOURCE_LINE")" \
        "running install twice does not duplicate the source line"
}

test_install_idempotent_reports_skip() {
    printf '%s\n' "# bashrc" > "$TEST_HOME/.bashrc"
    run_install
    run_install
    assert_contains "$INST_STDOUT$INST_STDERR" "already sources whatdidi" "second run reports skip"
}

run_install_tests() {
    printf '\033[1mInstall (rc wiring)\033[0m\n'
    run_test test_install_creates_bashrc_when_neither_exists
    run_test test_install_warns_when_creating_bashrc_fallback
    run_test test_install_appends_to_existing_bashrc_only
    run_test test_install_appends_to_existing_zshrc_no_bashrc_created
    run_test test_install_wires_both_when_both_exist
    run_test test_install_idempotent_no_duplicate
    run_test test_install_idempotent_reports_skip
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_install_tests
    print_summary
fi
