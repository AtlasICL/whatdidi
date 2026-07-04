#!/usr/bin/env bash
#
# perf_helpers.sh — timing/stats primitives and seeded-shell runners for the
# whatdidi performance harness. Sourced by bench.sh; not meant to be run alone.
#
# It provides:
#   * _perf_now_snippet   — emits shell code defining a portable hi-res clock
#                           (`_wdi_now`) INSIDE a seeded interactive shell.
#   * perf_stats          — min/median/mean/max of float samples (in ms).
#   * perf_run_bash       — seed 50k history under bash, time batched calls.
#   * perf_run_zsh        — same, under zsh.
#
# The runners mirror run_hi / run_hi_zsh from ../helpers.sh as faithfully as
# possible (the `history -c; history -n` ordering, the -f / -i flags, the
# job-control stderr filtering) so the numbers reflect the REAL tool behaviour.

# Guard against double-sourcing (bench.sh sources us exactly once, but be safe).
[[ -n "${_PERF_HELPERS_LOADED:-}" ]] && return
_PERF_HELPERS_LOADED=1

# Absolute path to the whatdidi script under test. Resolved relative to THIS
# file so the harness works regardless of the caller's CWD (perf_helpers.sh
# lives in test/perf/, whatdidi lives two levels up at the repo root).
WDI_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/whatdidi.sh"

# History-list sizes for the seeded shells. The existing harness uses 10000,
# which would TRUNCATE a 50k fixture and leave the scan covering only the newest
# 10k entries — defeating the near-full-scan scenarios. 60000 comfortably holds
# the default 50k with headroom for the handful of session commands.
PERF_HISTSIZE=60000

# An interactive bash echoes every command it reads back to stderr, each line
# prefixed by the prompt (PS1 for a command, PS2 for a continuation). We set both
# prompts to this distinctive sentinel so _perf_scrub can drop those echo lines
# wholesale while leaving genuine sub-process errors (which carry no sentinel)
# intact. The token is deliberately unlike anything a real error would print.
PERF_PS_SENTINEL='__WDI_PERF_ECHO__'

# ---------------------------------------------------------------------------
# _perf_now_snippet
#
# Prints shell code (to stdout) that, when executed inside the seeded shell,
# defines `_wdi_now` — "seconds since the epoch as a float". WHY a snippet
# rather than a helper on the outside: the timing must happen *inside* the same
# interactive shell that hosts the seeded history, with no extra process
# boundary per call.
#
# Clock selection, fastest first (note: `$(_wdi_now)` ALWAYS forks a subshell for
# the command substitution — the difference below is only the EXTRA cost inside
# that subshell):
#   1. $EPOCHREALTIME — a builtin float clock read with no additional process.
#      bash >= 5 exposes it natively; zsh exposes it after `zmodload
#      zsh/datetime`. Preferred for the zsh best case, where a call is sub-ms.
#   2. perl Time::HiRes — portable fallback for bash 3.2 (stock macOS), which
#      has no $EPOCHREALTIME. This adds a second fork (the perl process) on top of
#      the subshell. We only stamp twice per repetition, so that cost is amortised
#      over K calls and dominates the per-call figure only at very small ITERS.
#
# We deliberately do NOT use `date +%s.%N`: BSD/macOS `date` has no %N and would
# emit a literal "N", silently corrupting the arithmetic.
#
# The emitted code is captured into a shell variable by the runners and injected
# into the heredoc by a single top-level expansion, so `$EPOCHREALTIME` etc.
# inside it stay literal (no `\$` escaping needed).
# ---------------------------------------------------------------------------
#
# NOTE ON COMMENT-FREE OUTPUT: the emitted code carries NO inline comments. An
# interactive zsh (zsh -i) leaves the `interactive_comments` option OFF by
# default, so a leading `#` is parsed as a command and — worse — an apostrophe
# inside a comment (e.g. "isn't") flips zsh into quote-continuation mode and
# silently swallows the real timing calls that follow, yielding zero samples.
# Rather than depend on toggling a shell option inside the measured shell, we
# keep every explanation out here as ordinary source comments and emit only bare
# executable lines. Line-by-line meaning of the snippet below:
#   * `zmodload zsh/datetime` — zsh: expose $EPOCHREALTIME (no-op under bash,
#     error swallowed).
#   * `_wdi_now` — prints "seconds since epoch" as a float. Prefers the builtin
#     $EPOCHREALTIME (bash>=5 / zsh, no extra process beyond the subshell); falls
#     back to perl Time::HiRes on bash 3.2 (stock macOS), which lacks it.
_perf_now_snippet() {
  cat <<'SNIPPET'
zmodload zsh/datetime 2>/dev/null || true
_wdi_now() {
  if [ -n "${EPOCHREALTIME:-}" ]; then
    printf '%s\n' "$EPOCHREALTIME"
  else
    perl -MTime::HiRes=time -e 'printf "%.6f\n", time'
  fi
}
SNIPPET
}

# ---------------------------------------------------------------------------
# perf_stats
#
# Reads whitespace/newline-separated float samples (seconds) on stdin and
# prints "min median mean max" as space-separated milliseconds with 3 decimals.
#
# Implemented via `sort -n | awk` for portability: macOS's BWK awk has no
# asort(), so we pre-sort externally and let awk pick order statistics by index.
# awk gives the floating-point precision that a pure-shell implementation cannot.
#
# Both stages are pinned to LC_ALL=C so the '.' decimal separator in the samples
# is honoured regardless of the caller's locale. bench.sh also exports LC_ALL=C
# globally; this local pin makes perf_stats correct even if sourced elsewhere.
# ---------------------------------------------------------------------------
perf_stats() {
  LC_ALL=C sort -n | LC_ALL=C awk '
    { v[NR] = $1; sum += $1 }
    END {
      n = NR
      if (n == 0) { print "0.000 0.000 0.000 0.000"; exit }
      min = v[1]; max = v[n]; mean = sum / n
      if (n % 2 == 1) med = v[(n + 1) / 2]
      else            med = (v[n / 2] + v[n / 2 + 1]) / 2
      # Convert seconds -> milliseconds for a human-readable table.
      printf "%.3f %.3f %.3f %.3f\n", min * 1000, med * 1000, mean * 1000, max * 1000
    }'
}

# ---------------------------------------------------------------------------
# _perf_timing_body ARGS K R
#
# Prints the shared timing routine (to stdout) that both runners inject after
# sourcing whatdidi. It:
#   * does one warmup call (output discarded) to page in the history scan and
#     stabilise the first-call cost, then
#   * runs R repetitions; each repetition stamps the clock once, fires K
#     consecutive `whatdidi ARGS` calls (stdout+stderr to /dev/null), stamps
#     again, and prints the PER-CALL time = (t1 - t0) / K.
#
# WHY batch by K: a single zsh best-case call can be well under a millisecond —
# smaller than the fork overhead of even one clock read. Timing K calls between
# a single pair of stamps amortises that overhead so the per-call figure is
# meaningful. R gives us a distribution (min/median/mean/max) over batches.
#
# ARGS is injected verbatim (e.g. `wdi_recent_needle 1`); K and R are integers.
# C-style `for ((...))` loops are supported by both bash 3.2 and zsh 5.
#
# As with _perf_now_snippet, the emitted body is COMMENT-FREE (see the note there
# for why zsh -i mangles injected comments). Line-by-line meaning:
#   * first `whatdidi` call — warmup, output discarded; primes the history scan
#     so the first timed batch isn't skewed by one-off setup (awk buffering on
#     the bash path, filesystem caches, etc.).
#   * outer loop (R times) — stamps `_wdi_now` before/after a batch of K calls.
#   * inner loop (K times) — the calls actually being timed, output to /dev/null.
#   * awk — prints per-call seconds = (t1 - t0) / K to stdout for the caller;
#     awk does the float subtraction/division portably and precisely. It runs
#     ONLY when both stamps are non-empty: if the clock is broken (no
#     $EPOCHREALTIME AND no perl/Time::HiRes) _wdi_now emits nothing, and we must
#     emit NO sample rather than a fake "0.000000" that (b-a)/k would produce —
#     otherwise bench.sh's `^[0-9]` guard would accept it and print a misleading
#     0.000 row instead of dashes.
# ---------------------------------------------------------------------------
_perf_timing_body() {
  local args="$1" k="$2" r="$3"
  cat <<BODY
whatdidi $args >/dev/null 2>&1
for ((__r = 0; __r < $r; __r++)); do
  __t0=\$(_wdi_now)
  for ((__k = 0; __k < $k; __k++)); do
    whatdidi $args >/dev/null 2>&1
  done
  __t1=\$(_wdi_now)
  if [ -n "\$__t0" ] && [ -n "\$__t1" ]; then
    awk -v a="\$__t0" -v b="\$__t1" -v k="$k" 'BEGIN { printf "%.6f\n", (b - a) / k }'
  fi
done
BODY
}

# ---------------------------------------------------------------------------
# _perf_scrub ERRFILE [EXTRA_DROP_REGEX]
#
# Reads a captured stderr file and prints only GENUINE error lines (caller
# redirects the result to its own stderr). Interactive shells emit a lot of
# benign chatter we must suppress so the harness output stays readable:
#   * bash/zsh "no job control" / "cannot set terminal" job-control warnings,
#   * the stock-macOS "default interactive shell is now zsh" three-line notice,
#   * zsh prompt/line-editor escape sequences and carriage returns,
#   * bash's echo of every command it reads (prefixed with the PS sentinel).
#
# We STRIP ANSI escape sequences and CRs first (zsh prompt artifacts), then drop
# the known-benign patterns plus any blank / lone-'%' prompt leftovers. Anything
# else — e.g. "Can't locate Time/HiRes.pm" if perl lacks the module — survives
# and is surfaced, so a real failure is never hidden. EXTRA_DROP_REGEX lets a
# caller add shell-specific patterns (bash passes its PS sentinel here).
# ---------------------------------------------------------------------------
_perf_scrub() {
  local errf="$1" extra="${2:-}"
  local drop='no job control|cannot set terminal|can.t find terminal|interactive shell is now zsh|chsh -s|support\.apple\.com'
  [ -n "$extra" ] && drop="$drop|$extra"
  # $'\033' is ESC; the class matches a CSI sequence like ESC[?1034h or ESC[1m.
  # `tr -d` removes the CRs zsh uses to redraw a prompt line. The two greps drop
  # benign patterns and then any residual blank / prompt-only ('%') lines.
  LC_ALL=C sed $'s/\033\\[[0-9;?]*[a-zA-Z]//g' "$errf" \
    | tr -d '\r' \
    | grep -av -E "$drop" \
    | grep -av -E '^[[:space:]]*%?[[:space:]]*$' \
    || true
}

# ---------------------------------------------------------------------------
# perf_run_bash FIXTURE ARGS K R
# perf_run_zsh  FIXTURE ARGS K R
#
#   FIXTURE  path to a generated history file (see gen_history.sh)
#   ARGS     whatdidi needle+count, as one string (e.g. "wdi_oldest_needle 5")
#   K        batch size — calls timed per stamped interval
#   R        repetitions — number of per-call samples emitted
#
# Each seeds the fixture into a fresh interactive shell ONCE, sources whatdidi,
# then runs the batched timing body. R per-call timing samples (seconds, float)
# are written to stdout for the caller to aggregate; job-control stderr noise is
# filtered and any genuine error is forwarded to our stderr.
#
# HOME is pointed at ${PERF_HOME:-$HOME}; bench.sh sets PERF_HOME to an empty
# temp dir so the caller's real ~/.config/whatdidi/config can't perturb the
# default count (and thus the amount of scanning) mid-benchmark.
# LC_ALL=C pins the decimal separator to '.', so $EPOCHREALTIME and awk agree
# regardless of the ambient locale.
# ---------------------------------------------------------------------------
perf_run_bash() {
  local fixture="$1" args="$2" k="$3" r="$4"
  local now_snippet timing_body errf fixcopy
  now_snippet="$(_perf_now_snippet)"
  timing_body="$(_perf_timing_body "$args" "$k" "$r")"
  errf="$(mktemp)"

  # PRIVATE per-invocation copy of the fixture. whatdidi's bash path runs
  # `builtin history -a`, which APPENDS this seeded session's own commands to
  # $HISTFILE. Pointing HISTFILE at the shared fixture would (a) let bash mutate
  # the very file the later zsh run reads — breaking the identical-input
  # guarantee — and (b) append entries AFTER wdi_recent_needle, diluting the
  # `recent` best case. Copying isolates every invocation.
  fixcopy="$(mktemp)"
  cp "$fixture" "$fixcopy"
  # Guarantee both temp files are removed even if the seeded shell aborts under
  # the caller's set -e. RETURN fires on any function exit; the `trap - RETURN`
  # self-clear stops this handler leaking onto sibling functions (bash traps are
  # global, not function-local), which matters if perf_helpers is used directly
  # rather than via bench.sh's command-substitution subshell.
  trap 'rm -f "$errf" "$fixcopy"; trap - RETURN' RETURN

  # Seeding mirrors run_hi(): `history -c` then `history -n` (NOT `-r`). On bash
  # 3.2, `-r` leaves the `-n` read cursor at 0, so whatdidi's own internal
  # `history -n` would re-read the file and DOUBLE every entry. `-n` advances
  # the cursor, matching bash 5 and keeping the seeded count exact.
  #
  # PS1/PS2 are set to the echo sentinel (see PERF_PS_SENTINEL) so _perf_scrub can
  # strip bash's echo of the heredoc it reads. The timing samples go to STDOUT
  # (unaffected by this), so the sentinel only ever touches the noise on stderr.
  HOME="${PERF_HOME:-$HOME}" LC_ALL=C PS1="$PERF_PS_SENTINEL" PS2="$PERF_PS_SENTINEL" \
    bash --norc --noprofile -i <<HEREDOC 2>"$errf"
export HISTFILE="$fixcopy"
HISTSIZE=$PERF_HISTSIZE
HISTFILESIZE=$PERF_HISTSIZE
history -c
history -n "\$HISTFILE"
$now_snippet
source "$WDI_SRC"
$timing_body
HEREDOC

  # Forward only genuine errors; the sentinel-prefixed command echo is dropped.
  # Temp cleanup is handled by the RETURN trap above.
  _perf_scrub "$errf" "^${PERF_PS_SENTINEL}" >&2
}

perf_run_zsh() {
  local fixture="$1" args="$2" k="$3" r="$4"
  local now_snippet timing_body errf fixcopy
  now_snippet="$(_perf_now_snippet)"
  timing_body="$(_perf_timing_body "$args" "$k" "$r")"
  errf="$(mktemp)"

  # PRIVATE per-invocation copy of the fixture (same rationale as perf_run_bash).
  # zsh's `fc -R` only READS the file so it would not mutate a shared fixture,
  # but a bash run scheduled earlier could already have appended to a shared one;
  # copying keeps every invocation's input byte-identical and self-contained.
  fixcopy="$(mktemp)"
  cp "$fixture" "$fixcopy"
  # Guarantee cleanup on any function exit; self-clear so the handler doesn't
  # leak onto sibling functions (see perf_run_bash for the full rationale).
  trap 'rm -f "$errf" "$fixcopy"; trap - RETURN' RETURN

  # Seeding mirrors run_hi_zsh(): zsh -f -i (skip rc files, interactive), load
  # the seeded history with `fc -R`. zsh keeps interactive history in memory, so
  # whatdidi does not re-read the file and no doubling guard is needed.
  #
  # CRITICAL: the heredoc body below must stay comment-free. Every line between
  # <<HEREDOC and HEREDOC is fed to the interactive zsh, which leaves
  # `interactive_comments` OFF by default — a stray `#` line would be run as a
  # command and an apostrophe in it would flip zsh into quote-continuation mode,
  # swallowing the real timing calls. `setopt interactive_comments` is set first
  # as belt-and-suspenders (in case ARGS ever carries a '#'), but we still keep
  # the body bare so the option toggle is never load-bearing.
  #
  # Prompt suppression: empty PROMPT/PS1/PS2 plus `-o nopromptsp -o nopromptcr`
  # (set at startup, so they apply before the very first prompt) and an empty
  # PROMPT_EOL_MARK stop zsh's line editor from emitting its reverse-video "%"
  # partial-line marker and CR redraws to stderr. Without these, zsh scribbles a
  # prompt artifact onto the same line as any real error, defeating _perf_scrub.
  HOME="${PERF_HOME:-$HOME}" LC_ALL=C PROMPT='' PS1='' PS2='' PROMPT_EOL_MARK='' \
    zsh -f -i -o nopromptsp -o nopromptcr <<HEREDOC 2>"$errf"
export HISTFILE="$fixcopy"
HISTSIZE=$PERF_HISTSIZE
SAVEHIST=$PERF_HISTSIZE
fc -R "\$HISTFILE"
setopt interactive_comments 2>/dev/null || true
$now_snippet
source "$WDI_SRC"
$timing_body
HEREDOC

  # zsh does not echo the commands it reads, so no sentinel is needed here.
  # Temp cleanup is handled by the RETURN trap above.
  _perf_scrub "$errf" >&2
}
