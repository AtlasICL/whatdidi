#!/usr/bin/env bash
# Category: Unique flag (-u/--unique)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_dedup_collapses_identical() {
    # Seed the SAME matching command repeated plus an unrelated line. With -u,
    # byte-identical matches collapse to a single printed line. This case is
    # robust to the sandbox history-doubling artifact: even if the 3 seeded
    # lines become 6, they're all byte-identical so dedup still yields exactly 1.
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl aaa" "echo hello" "curl aaa")"
    run_hi "$hist" "-u curl 10"
    assert_line_count 1 "$HI_STDOUT" "identical matches collapse to 1"
}

test_distinct_matches_preserved() {
    # Distinct matches are kept; only byte-identical duplicates are dropped.
    # Newest-first, the FIRST occurrence of each distinct line is what survives:
    # history newest->oldest is (curl aaa, curl bbb, curl aaa), so we keep
    # `curl aaa` (newest) then `curl bbb`, and skip the older `curl aaa`.
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb" "curl aaa")"
    run_hi "$hist" "-u curl 10"
    assert_line_count 2 "$HI_STDOUT" "two distinct matches" &&
    assert_eq "curl aaa" "$(printf '%s\n' "$HI_STDOUT" | head -1)" "newest distinct first" &&
    assert_eq "curl bbb" "$(printf '%s\n' "$HI_STDOUT" | tail -1)" "older distinct last"
}

test_count_means_n_unique() {
    # With -u, count means "up to N UNIQUE matches": the decrement happens only
    # on an actual (deduped) print. Seed distinct matches with a duplicate
    # interleaved; `-u curl 2` returns the 2 most-recent DISTINCT lines.
    # History newest->oldest: curl d, curl a, curl c, curl b, curl a  =>  d, a.
    local hist
    hist="$(printf '%s\n' "curl a" "curl b" "curl c" "curl a" "curl d")"
    run_hi "$hist" "-u curl 2"
    assert_line_count 2 "$HI_STDOUT" "count caps at 2 unique" &&
    assert_eq "curl d" "$(printf '%s\n' "$HI_STDOUT" | head -1)" "most recent unique first" &&
    assert_eq "curl a" "$(printf '%s\n' "$HI_STDOUT" | tail -1)" "second most recent unique"
}

test_flag_position_variants_equivalent() {
    # -u may appear ANYWHERE in the args: leading, trailing, or between the
    # needle and count. All three invocations must produce identical output.
    local hist a b c
    hist="$(printf '%s\n' "curl aaa" "curl bbb" "curl aaa" "curl ccc")"
    run_hi "$hist" "-u curl 10"; a="$HI_STDOUT"
    run_hi "$hist" "curl 10 -u"; b="$HI_STDOUT"
    run_hi "$hist" "curl -u 10"; c="$HI_STDOUT"
    assert_eq "$a" "$b" "'-u curl 10' == 'curl 10 -u'" &&
    assert_eq "$a" "$c" "'-u curl 10' == 'curl -u 10'" &&
    assert_line_count 3 "$a" "three distinct matches after dedup"
}

test_long_flag_equivalent() {
    # The long form --unique is a documented alias for -u; exercise it so a
    # regression in the long-form spelling can't slip through unnoticed.
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb" "curl aaa")"
    run_hi "$hist" "--unique curl 10"
    assert_line_count 2 "$HI_STDOUT" "--unique behaves like -u"
}

test_byte_identical_only_sudo_stays_distinct() {
    # Dedup is by byte-identical PRINTED line. `sudo rm foo` and `rm foo` both
    # match the needle `rm` (sudo is transparent to matching) but print as
    # different lines, so -u must keep BOTH.
    local hist
    hist="$(printf '%s\n' "rm foo" "sudo rm foo")"
    run_hi "$hist" "-u rm 10"
    assert_line_count 2 "$HI_STDOUT" "sudo variant is a distinct line" &&
    assert_contains "$HI_STDOUT" "rm foo" "plain rm kept" &&
    assert_contains "$HI_STDOUT" "sudo rm foo" "sudo rm kept"
}

test_no_flag_path_unchanged() {
    # Regression guard: without -u the default behavior is untouched — all
    # duplicates are returned. Mirrors test_duplicate_entries_all_returned in
    # test_search.sh (asserts exactly 3) to stay consistent with the existing
    # default-behavior test.
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl aaa" "curl aaa")"
    run_hi "$hist" "curl 10"
    assert_line_count 3 "$HI_STDOUT" "all 3 duplicates returned without -u"
}

test_multiword_needle_with_unique() {
    # Multi-word needles survive the flag-stripping rebuild (arg boundaries are
    # preserved). `git push` duplicates collapse while the distinct `git push -f`
    # is kept.
    local hist
    hist="$(printf '%s\n' "git push" "git push -f" "git push")"
    run_hi "$hist" '-u "git push" 10'
    assert_line_count 2 "$HI_STDOUT" "git push deduped, git push -f distinct" &&
    assert_contains "$HI_STDOUT" "git push" "plain git push kept" &&
    assert_contains "$HI_STDOUT" "git push -f" "git push -f kept"
}

test_unique_exit_code_on_match() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl aaa" "echo hello")"
    run_hi "$hist" "-u curl"
    assert_eq 0 "$HI_EXIT" "exit code 0 on match with -u"
}

# --- --no-unique (override a unique default) -------------------------------

test_no_unique_overrides_default_true() {
    # With default_unique=true in config, --no-unique forces dedup OFF. Prove the
    # override by comparing against the SAME search without --no-unique, which
    # dedups: identical dups collapse to 1 by default but all 3 return with the
    # override. The deduped count (1) is robust to history-doubling; the
    # all-duplicates count (3) relies on the no-doubling seeding invariant,
    # matching test_no_flag_path_unchanged.
    local hist all deduped
    hist="$(printf '%s\n' "curl aaa" "curl aaa" "curl aaa")"
    run_hi "$hist" "--no-unique curl 10" "default_unique=true"; all="$HI_STDOUT"
    run_hi "$hist" "curl 10" "default_unique=true"; deduped="$HI_STDOUT"
    assert_line_count 3 "$all" "--no-unique returns all duplicates" &&
    assert_line_count 1 "$deduped" "default_unique=true dedups without the override"
}

test_no_unique_trailing_position() {
    # --no-unique is parseable from ANY position (same rotation as -u): a trailing
    # occurrence overrides the true default just like a leading one.
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl aaa" "curl aaa")"
    run_hi "$hist" "curl 10 --no-unique" "default_unique=true"
    assert_line_count 3 "$HI_STDOUT" "trailing --no-unique overrides unique default"
}

test_no_unique_noop_when_default_false() {
    # When the default is already non-unique (no config), --no-unique is a no-op:
    # it must behave identically to passing no flag at all.
    local hist with without
    hist="$(printf '%s\n' "curl aaa" "curl aaa" "curl aaa")"
    run_hi "$hist" "--no-unique curl 10"; with="$HI_STDOUT"
    run_hi "$hist" "curl 10"; without="$HI_STDOUT"
    assert_eq "$without" "$with" "--no-unique is a no-op when default is false" &&
    assert_line_count 3 "$with" "all duplicates returned"
}

test_no_unique_last_flag_wins() {
    # -u and --no-unique are processed in order, so the LAST one on the line wins.
    # '-u ... --no-unique' ends non-unique (all dups); '--no-unique ... -u' ends
    # unique (collapsed to 1). The deduped count (1) is robust to history-doubling;
    # the all-duplicates count (3) relies on the no-doubling seeding invariant,
    # matching test_no_flag_path_unchanged.
    local hist no_wins u_wins
    hist="$(printf '%s\n' "curl aaa" "curl aaa" "curl aaa")"
    run_hi "$hist" "-u curl 10 --no-unique"; no_wins="$HI_STDOUT"
    run_hi "$hist" "--no-unique curl 10 -u"; u_wins="$HI_STDOUT"
    assert_line_count 3 "$no_wins" "trailing --no-unique wins over leading -u" &&
    assert_line_count 1 "$u_wins" "trailing -u wins over leading --no-unique"
}

# --- zsh parity ------------------------------------------------------------
# Replicate the two core behaviors under zsh so bash and zsh stay in lockstep.

test_dedup_collapses_identical_zsh() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl aaa" "echo hello" "curl aaa")"
    run_hi_zsh "$hist" "-u curl 10"
    assert_line_count 1 "$HI_STDOUT" "identical matches collapse to 1 under zsh"
}

test_distinct_matches_preserved_zsh() {
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl bbb" "curl aaa")"
    run_hi_zsh "$hist" "-u curl 10"
    assert_line_count 2 "$HI_STDOUT" "two distinct matches under zsh" &&
    assert_eq "curl aaa" "$(printf '%s\n' "$HI_STDOUT" | head -1)" "newest distinct first under zsh" &&
    assert_eq "curl bbb" "$(printf '%s\n' "$HI_STDOUT" | tail -1)" "older distinct last under zsh"
}

test_no_unique_overrides_default_true_zsh() {
    # zsh parity for the core override: default_unique=true + --no-unique returns
    # all duplicates, while the same search without the override dedups to 1.
    local hist all deduped
    hist="$(printf '%s\n' "curl aaa" "curl aaa" "curl aaa")"
    run_hi_zsh "$hist" "--no-unique curl 10" "default_unique=true"; all="$HI_STDOUT"
    run_hi_zsh "$hist" "curl 10" "default_unique=true"; deduped="$HI_STDOUT"
    assert_line_count 3 "$all" "--no-unique returns all duplicates under zsh" &&
    assert_line_count 1 "$deduped" "default_unique=true dedups without the override under zsh"
}

run_unique_tests() {
    printf '\033[1mUnique flag\033[0m\n'
    run_test test_dedup_collapses_identical
    run_test test_distinct_matches_preserved
    run_test test_count_means_n_unique
    run_test test_flag_position_variants_equivalent
    run_test test_long_flag_equivalent
    run_test test_byte_identical_only_sudo_stays_distinct
    run_test test_no_flag_path_unchanged
    run_test test_multiword_needle_with_unique
    run_test test_unique_exit_code_on_match
    run_test test_no_unique_overrides_default_true
    run_test test_no_unique_trailing_position
    run_test test_no_unique_noop_when_default_false
    run_test test_no_unique_last_flag_wins
    if command -v zsh >/dev/null 2>&1; then
        run_test test_dedup_collapses_identical_zsh
        run_test test_distinct_matches_preserved_zsh
        run_test test_no_unique_overrides_default_true_zsh
    else
        printf '  \033[33mSKIP\033[0m  test_dedup_collapses_identical_zsh (zsh not installed)\n'
        printf '  \033[33mSKIP\033[0m  test_distinct_matches_preserved_zsh (zsh not installed)\n'
        printf '  \033[33mSKIP\033[0m  test_no_unique_overrides_default_true_zsh (zsh not installed)\n'
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_unique_tests
    print_summary
fi
