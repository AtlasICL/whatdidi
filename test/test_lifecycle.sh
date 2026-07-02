#!/usr/bin/env bash
# Category: --update / --uninstall confirmation + cleanup
#
# These drive the confirmation prompts via stdin under a sandboxed HOME. The
# tool installs/uninstalls under a user-owned $HOME path with no sudo. The
# "proceed" path of --update is deliberately NOT exercised
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

# --- rc rewrite edge cases (M2 / M3 regressions) ---

test_uninstall_rc_with_only_source_line() {
    # M2: an rc file whose ENTIRE contents is the source line. `grep -v` then
    # matches nothing and exits 1, but the (empty) filtered output must still be
    # written back and the temp file must not be orphaned.
    printf '%s\n' "$SOURCE_LINE" > "$TEST_HOME/.bashrc"
    run_wdi_stdin "Y" "--uninstall"
    assert_eq 0 "$SI_EXIT" "clean exit" &&
    assert_eq 0 "$(count_lines_matching "$TEST_HOME/.bashrc" "$SOURCE_LINE")" \
        "source line removed even when it was the only line" &&
    [[ ! -e "$TEST_HOME/.bashrc.wdi_tmp" ]] || {
        printf '    temp file .bashrc.wdi_tmp should not be orphaned\n'; return 1
    }
}

test_uninstall_reports_error_on_unwritable_rc() {
    # A rewrite failure must not be masked by the trailing success message +
    # `return 0`. Make the rc read-only (chmod 400) AFTER seeding: the grep
    # guard can still READ it (so the block is entered) and the temp file is
    # written fine, but `cat > "$rc"` fails to open the read-only file for
    # writing — exactly the mid-write failure the else branch guards against.
    printf '%s\n' "$SOURCE_LINE" > "$TEST_HOME/.bashrc"
    chmod 400 "$TEST_HOME/.bashrc"
    run_wdi_stdin "Y" "--uninstall"
    # chmod back so teardown's rm -rf is never at the mercy of odd umask/root
    # edge cases (rm relies on the parent dir, but restoring perms is cheap
    # insurance and keeps the temp file removable too).
    chmod 600 "$TEST_HOME/.bashrc" 2>/dev/null || true
    assert_eq 1 "$SI_EXIT" "non-zero exit when an rc rewrite fails" &&
    assert_contains "$SI_STDERR" "failed to rewrite" "reports the rewrite failure" &&
    assert_not_contains "$SI_STDOUT" "uninstalled" \
        "does not print the success message on partial failure"
}

test_uninstall_empty_home_never_targets_system_paths() {
    # BUG-5 (defense-in-depth guard, NOT a strict red-green regression lock):
    # when HOME is empty, conf_dir resolves to "/.config/whatdidi" and the rc
    # paths to "/.bashrc" / "/.zshrc" — all bare-`/`-rooted system paths. The
    # `[[ -n "$HOME" && -d "$conf_dir" ]]` guard adds a belt-and-suspenders
    # `-n "$HOME"` check so uninstall never issues a destructive op against one.
    #
    # Why this is NOT a strict lock against the pre-fix (unguarded) code: the
    # deletion is ALSO gated by the pre-existing `-d "$conf_dir"` precheck, and
    # "/.config/whatdidi" cannot be created inside the hermetic sandbox (it is a
    # real system path). So even without the `-n "$HOME"` guard the `rm -rf`
    # would be skipped here — a red-against-pre-fix assertion is unachievable
    # without touching the real filesystem. Instead we assert the honest,
    # verifiable property: under empty HOME, uninstall exits cleanly and `rm` is
    # never invoked on any bare-`/`-rooted $HOME-derived path. The mock `rm`
    # logger records every invocation's args, so a future regression that DID
    # fire `rm` on such a path (e.g. by dropping the `-d` precheck too) would be
    # caught here.
    local rm_log="$TEST_TMPDIR/rm_calls"
    : > "$rm_log"
    local shadow="rm() { printf '%s\n' \"\$*\" >> '$rm_log'; }"
    run_wdi_stdin_emptyhome "Y" "--uninstall" "$shadow"
    local rm_calls
    rm_calls="$(cat "$rm_log")"
    assert_eq 0 "$SI_EXIT" "uninstall exits cleanly with empty HOME" &&
    assert_not_contains "$SI_STDOUT" "removed config directory" \
        "config-removal branch is skipped when HOME is empty" &&
    assert_not_contains "$rm_calls" "/.config/whatdidi" \
        "rm is never invoked on the exact \$HOME-derived config path" &&
    assert_not_contains "$rm_calls" "/.config/" \
        "rm is never invoked on any bare-/-rooted .config path" &&
    assert_not_contains "$rm_calls" "/.bashrc" \
        "rm is never invoked on the bare-/-rooted .bashrc path" &&
    assert_not_contains "$rm_calls" "/.zshrc" \
        "rm is never invoked on the bare-/-rooted .zshrc path"
}

test_uninstall_preserves_symlinked_rc() {
    # M3: when the rc file is a symlink (common with dotfile managers) the edit
    # must happen in place via `cat >` so the symlink survives and the real
    # target is updated — `mv` would replace the symlink with a regular file.
    printf '%s\n' "# managed by dotfiles" "$SOURCE_LINE" > "$TEST_HOME/real_bashrc"
    ln -s "$TEST_HOME/real_bashrc" "$TEST_HOME/.bashrc"
    run_wdi_stdin "Y" "--uninstall"
    assert_eq 0 "$SI_EXIT" "clean exit" &&
    { [[ -L "$TEST_HOME/.bashrc" ]] || {
        printf '    .bashrc should still be a symlink after uninstall\n'; return 1
    }; } &&
    assert_eq 0 "$(count_lines_matching "$TEST_HOME/real_bashrc" "$SOURCE_LINE")" \
        "source line removed from the real target" &&
    assert_eq 1 "$(count_lines_matching "$TEST_HOME/real_bashrc" "# managed by dotfiles")" \
        "unrelated line in the real target preserved"
}

# --- zsh confirmation-path counterparts (H1 regression) ---
#
# These would have FAILED before the H1 fix: zsh's `read -p` reads from the
# coprocess rather than printing a prompt, so the confirmation reply was never
# consumed. Guarded on zsh availability so bash-only machines stay green.

test_update_cancelled_on_n_zsh() {
    run_wdi_stdin_zsh "n" "--update"
    assert_eq 0 "$SI_EXIT" "cancel is a clean exit" &&
    assert_contains "$SI_STDOUT" "cancelled" "reports cancellation" &&
    assert_not_contains "$SI_STDOUT" "fetching" "does not proceed to fetch"
}

test_uninstall_cancelled_on_n_leaves_everything_zsh() {
    _seed_installed_state
    run_wdi_stdin_zsh "n" "--uninstall"
    assert_eq 0 "$SI_EXIT" "clean exit on cancel" &&
    assert_contains "$SI_STDOUT" "cancelled" "reports cancellation" &&
    assert_eq 1 "$(count_lines_matching "$TEST_HOME/.bashrc" "$SOURCE_LINE")" "bashrc untouched" &&
    assert_eq 1 "$(count_lines_matching "$TEST_HOME/.zshrc" "$SOURCE_LINE")" "zshrc untouched" &&
    [[ -d "$TEST_HOME/.config/whatdidi" ]] || {
        printf '    config dir should remain after cancel\n'; return 1
    }
}

test_uninstall_removes_source_line_from_both_rc_zsh() {
    _seed_installed_state
    run_wdi_stdin_zsh "Y" "--uninstall"
    assert_eq 0 "$SI_EXIT" "clean exit" &&
    assert_eq 0 "$(count_lines_matching "$TEST_HOME/.bashrc" "$SOURCE_LINE")" "removed from bashrc" &&
    assert_eq 0 "$(count_lines_matching "$TEST_HOME/.zshrc" "$SOURCE_LINE")" "removed from zshrc"
}

test_uninstall_default_yes_on_empty_reply_zsh() {
    # Empty reply defaults to "Y" (uninstall proceeds) under zsh too.
    _seed_installed_state
    run_wdi_stdin_zsh "" "--uninstall"
    assert_eq 0 "$(count_lines_matching "$TEST_HOME/.bashrc" "$SOURCE_LINE")" \
        "empty reply defaults to yes and uninstalls"
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
    run_test test_uninstall_rc_with_only_source_line
    run_test test_uninstall_reports_error_on_unwritable_rc
    run_test test_uninstall_empty_home_never_targets_system_paths
    run_test test_uninstall_preserves_symlinked_rc

    # zsh confirmation-path counterparts — skip gracefully without zsh.
    if command -v zsh >/dev/null 2>&1; then
        run_test test_update_cancelled_on_n_zsh
        run_test test_uninstall_cancelled_on_n_leaves_everything_zsh
        run_test test_uninstall_removes_source_line_from_both_rc_zsh
        run_test test_uninstall_default_yes_on_empty_reply_zsh
    else
        printf '  \033[33mSKIP\033[0m  zsh lifecycle tests (zsh not installed)\n'
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_lifecycle_tests
    print_summary
fi
