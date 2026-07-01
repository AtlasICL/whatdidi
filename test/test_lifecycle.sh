#!/usr/bin/env bash
# Category: --update / --uninstall confirmation + cleanup
#
# These drive the confirmation prompts via stdin and use a no-op sudo shim + a
# sandboxed HOME. The "proceed" path of --update is deliberately NOT exercised
# (it would run `curl | sh` against the network); only its guard rails are.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# --- --update guard rails ---

test_update_cancelled_on_n() {
    run_wdi_stdin "n" "--update"
    assert_eq 0 "$SI_EXIT" "cancel is a clean exit" &&
    assert_contains "$SI_STDOUT" "cancelled" "reports cancellation" &&
    assert_not_contains "$SI_STDOUT" "fetching" "does not proceed to fetch"
}

test_update_errors_without_curl() {
    # curl is checked (via `command -v curl`) before the prompt. Shadow the
    # `command` builtin so curl looks absent, without disturbing PATH (which
    # would also hide bash itself).
    local shadow='command() { case "$*" in *curl*) return 1;; esac; builtin command "$@"; }'
    run_wdi_stdin "" "--update" "$shadow"
    assert_eq 1 "$SI_EXIT" "exits non-zero when curl missing" &&
    assert_contains "$SI_STDERR" "curl is required" "explains curl requirement"
}

# --- --uninstall confirmation + cleanup ---

_seed_installed_state() {
    # Simulate a machine where whatdidi is wired into both rc files and has a
    # config directory.
    printf '%s\n' "# bashrc" "alias g=git" "$SOURCE_LINE" > "$TEST_HOME/.bashrc"
    printf '%s\n' "# zshrc" "$SOURCE_LINE" > "$TEST_HOME/.zshrc"
    mkdir -p "$TEST_HOME/.config/whatdidi"
    printf 'default_count=3\n' > "$TEST_HOME/.config/whatdidi/config"
}

test_uninstall_cancelled_on_n_leaves_everything() {
    _seed_installed_state
    run_wdi_stdin "n" "--uninstall"
    assert_eq 0 "$SI_EXIT" "clean exit on cancel" &&
    assert_contains "$SI_STDOUT" "cancelled" "reports cancellation" &&
    assert_eq 1 "$(count_lines_matching "$TEST_HOME/.bashrc" "$SOURCE_LINE")" "bashrc untouched" &&
    assert_eq 1 "$(count_lines_matching "$TEST_HOME/.zshrc" "$SOURCE_LINE")" "zshrc untouched" &&
    [[ -d "$TEST_HOME/.config/whatdidi" ]] || {
        printf '    config dir should remain after cancel\n'; return 1
    }
}

test_uninstall_removes_source_line_from_both_rc() {
    _seed_installed_state
    run_wdi_stdin "Y" "--uninstall"
    assert_eq 0 "$SI_EXIT" "clean exit" &&
    assert_eq 0 "$(count_lines_matching "$TEST_HOME/.bashrc" "$SOURCE_LINE")" "removed from bashrc" &&
    assert_eq 0 "$(count_lines_matching "$TEST_HOME/.zshrc" "$SOURCE_LINE")" "removed from zshrc"
}

test_uninstall_preserves_other_rc_content() {
    _seed_installed_state
    run_wdi_stdin "Y" "--uninstall"
    local bashrc
    bashrc="$(cat "$TEST_HOME/.bashrc")"
    assert_contains "$bashrc" "alias g=git" "unrelated bashrc lines preserved" &&
    assert_contains "$bashrc" "# bashrc" "comment preserved"
}

test_uninstall_removes_config_dir() {
    _seed_installed_state
    run_wdi_stdin "Y" "--uninstall"
    [[ ! -e "$TEST_HOME/.config/whatdidi" ]] || {
        printf '    config dir should be removed on uninstall\n'; return 1
    }
}

test_uninstall_default_yes_on_empty_reply() {
    # Empty reply defaults to "Y" (uninstall proceeds).
    _seed_installed_state
    run_wdi_stdin "" "--uninstall"
    assert_eq 0 "$(count_lines_matching "$TEST_HOME/.bashrc" "$SOURCE_LINE")" \
        "empty reply defaults to yes and uninstalls"
}

test_uninstall_no_rc_files_still_clean() {
    # No rc files present: uninstall should not error, just clean what exists.
    mkdir -p "$TEST_HOME/.config/whatdidi"
    run_wdi_stdin "Y" "--uninstall"
    assert_eq 0 "$SI_EXIT" "clean exit with no rc files" &&
    [[ ! -e "$TEST_HOME/.config/whatdidi" ]] || {
        printf '    config dir should still be removed\n'; return 1
    }
}

run_lifecycle_tests() {
    printf '\033[1mUpdate / uninstall\033[0m\n'
    run_test test_update_cancelled_on_n
    run_test test_update_errors_without_curl
    run_test test_uninstall_cancelled_on_n_leaves_everything
    run_test test_uninstall_removes_source_line_from_both_rc
    run_test test_uninstall_preserves_other_rc_content
    run_test test_uninstall_removes_config_dir
    run_test test_uninstall_default_yes_on_empty_reply
    run_test test_uninstall_no_rc_files_still_clean
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_lifecycle_tests
    print_summary
fi
