#!/usr/bin/env bash
# Category: multi-line (lithist) history entries (bash)
#
# Regression guard for L3: with `shopt -s lithist` a multi-line command is
# stored in history with embedded newlines, so `history` prints it across
# several physical lines where only the FIRST carries the leading event number.
# whatdidi reverses history to newest-first before matching; a naive per-line
# reversal scrambles such events (it flips the order of the physical lines
# WITHIN an event). The fix reverses by event/record instead, keeping each
# event's lines together and in their original order. These tests seed real
# multi-line events via `history -s $'...\n...'` and assert the intra-event
# line order survives the search.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# Preamble that clears the seeded history and stuffs three events, the middle
# one being a genuine two-line command whose BOTH lines match "git". `\n` inside
# $'...' becomes a real embedded newline, reproducing a lithist multi-line event.
_ML_TWO_GIT_LINES=$'shopt -s lithist cmdhist\nhistory -c\nhistory -s \'echo z\'\nhistory -s $\'git first\\ngit second\'\nhistory -s \'echo y\''

# A multi-line event sandwiched between single-line git matches. Continuation
# line ("git mid") matches too, so newest-first order across events is checked.
_ML_INTERLEAVED=$'shopt -s lithist cmdhist\nhistory -c\nhistory -s \'git one\'\nhistory -s $\'echo pre\\ngit mid\'\nhistory -s \'git three\''

# History that contains only non-matching events — an "effectively empty" search
# for the "git" needle. The record-reversal awk still builds records; the search
# simply finds nothing.
_ML_NO_MATCH=$'history -c\nhistory -s \'echo alpha\'\nhistory -s \'echo beta\''

# A multi-line (lithist) event as the very FIRST event in history. This is the
# closest the real `history` builtin lets us get to the `n > 0` guard's target
# scenario (reversal output that BEGINS with an unnumbered continuation line):
# the builtin always numbers the first physical line of every event, so a
# genuine leading continuation line can't be forced through it. Instead we
# verify the first record is assembled correctly (its continuation line attaches
# to the numbered first line) and that no stray leading blank record is emitted.
_ML_LEADING_EVENT=$'shopt -s lithist cmdhist\nhistory -c\nhistory -s $\'git alpha\\ngit beta\'\nhistory -s \'echo tail\''

test_multiline_intra_event_order_preserved() {
    # The two-line event's lines must be returned in their ORIGINAL order
    # ("git first" then "git second"). The buggy per-line reversal flipped them
    # to "git second" then "git first".
    run_hi "echo seed" "git 5" "" "$_ML_TWO_GIT_LINES"
    local expected
    expected="$(printf '%s\n' "git first" "git second")"
    assert_eq "$expected" "$HI_STDOUT" "multi-line event lines kept in original order"
}

test_multiline_event_not_dropped() {
    # Both lines of the multi-line event are present (nothing scrambled away).
    run_hi "echo seed" "git 5" "" "$_ML_TWO_GIT_LINES"
    assert_contains "$HI_STDOUT" "git first" "first line of multi-line event present" &&
    assert_contains "$HI_STDOUT" "git second" "second line of multi-line event present"
}

test_multiline_interleaved_newest_first() {
    # Across events, git matches come back newest-first with the multi-line
    # event's continuation line ("git mid") in its correct middle position:
    #   git three (newest) -> git mid (continuation of middle event) -> git one.
    run_hi "echo seed" "git 5" "" "$_ML_INTERLEAVED"
    local expected
    expected="$(printf '%s\n' "git three" "git mid" "git one")"
    assert_eq "$expected" "$HI_STDOUT" "matches newest-first, multi-line event placed correctly"
}

test_multiline_empty_history_no_match() {
    # L3 edge: an effectively empty history (only non-matching events) for a
    # needle that matches nothing must return cleanly — empty stdout, exit 0,
    # and no crash or stray garbage from the record-reversal awk.
    run_hi "echo seed" "git 5" "" "$_ML_NO_MATCH"
    assert_eq "" "$HI_STDOUT" "no matches yields empty stdout" &&
    assert_eq 0 "$HI_EXIT" "clean exit when nothing matches"
}

test_multiline_leading_event_no_stray_blank() {
    # L3 edge: a multi-line event first in history exercises the first-record
    # build path adjacent to the `n > 0` continuation guard. Its two lines must
    # come back in order with NO stray leading blank record (a leading empty
    # line would make HI_STDOUT start with a newline, which this exact-match
    # assertion would catch). See _ML_LEADING_EVENT for why a genuine leading
    # continuation line can't be forced through the real `history` builtin.
    run_hi "echo seed" "git 5" "" "$_ML_LEADING_EVENT"
    local expected
    expected="$(printf '%s\n' "git alpha" "git beta")"
    assert_eq "$expected" "$HI_STDOUT" "leading multi-line event kept in order, no stray leading blank" &&
    assert_eq 0 "$HI_EXIT" "clean exit"
}

run_multiline_tests() {
    printf '\033[1mMulti-line (lithist) history\033[0m\n'
    run_test test_multiline_intra_event_order_preserved
    run_test test_multiline_event_not_dropped
    run_test test_multiline_interleaved_newest_first
    run_test test_multiline_empty_history_no_match
    run_test test_multiline_leading_event_no_stray_blank
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_multiline_tests
    print_summary
fi
