#!/usr/bin/env bash
#
# bench.sh — empirical performance harness for the `whatdidi` history search.
#
# WHY: whatdidi has two shell-specific search paths (see the script, ~L207-244).
# The zsh path streams history newest-first via `fc -rl` and early-exits once it
# has collected `count` matches. The bash path pipes `history` through an awk
# program that buffers the ENTIRE history into an array before emitting anything
# (to reverse it without GNU `tac`), so the awk stage can never early-exit and
# always pays a full-history cost. This harness measures both paths against a
# large, deterministic fixture with a KNOWN match distribution so that cost
# difference is observable rather than asserted.
#
# USAGE:
#   bash test/perf/bench.sh
#
# ENV KNOBS (all optional):
#   SIZE    history fixture size in lines            (default 50000)
#   ITERS   batch size K: calls timed per stamp pair  (default 20)
#   REPS    repetitions R: timing samples per cell    (default 10)
#   SHELLS  space-separated shells to test            (default "bash zsh")
#           A requested shell whose binary is absent is skipped with a note.
#   WDI_HIST_SEED  PRNG seed forwarded to gen_history.sh (default 1)
#
# OUTPUT: an environment banner followed by a table of per-call timings
# (min/median/mean/max, in milliseconds) for each scenario x shell:
#   absent  — absent needle, count=1   (full scan, 0 matches)
#   recent  — recent needle, count=1   (best case: newest-first hit)
#   oldest  — oldest-only needle, count=5 (near-full scan to collect 5)
#   spread  — spread needle, count=100 (many matches across the history)
#
# The fixture is generated once into a temp file and removed on exit.

set -euo pipefail

# Pin the C locale process-wide. The runners already emit timing samples under
# LC_ALL=C (dot decimals), but `perf_stats` (sort -n | awk) runs here in bench's
# ambient locale. Under a comma-decimal locale (e.g. de_DE.UTF-8) awk would parse
# "0.005" as 0 and collapse the WHOLE table to zeros — and the raw samples are
# still valid, so the "no samples" dash-guard would not catch it. Exporting it
# once here keeps sample generation and aggregation on the same decimal point.
export LC_ALL=C

# Resolve our own directory so the harness runs from any CWD (mirrors run_all.sh).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# perf_helpers.sh provides the timing primitives and the seeded-shell runners.
# shellcheck source=/dev/null
source "$SCRIPT_DIR/perf_helpers.sh"

# --- Configuration (env-overridable) ---------------------------------------
SIZE="${SIZE:-50000}"
ITERS="${ITERS:-20}"
REPS="${REPS:-10}"
SHELLS="${SHELLS:-bash zsh}"

# Validate the numeric knobs up front: a non-numeric value would otherwise blow
# up deep inside the runners with a cryptic arithmetic error.
for _kv in "SIZE=$SIZE" "ITERS=$ITERS" "REPS=$REPS"; do
  _k="${_kv%%=*}"; _v="${_kv#*=}"
  if ! [[ "$_v" =~ ^[0-9]+$ ]] || [[ "$_v" -lt 1 ]]; then
    echo "bench.sh: $_k must be a positive integer (got: $_v)" >&2
    exit 2
  fi
done

# The seeded shells cap their in-memory history at PERF_HISTSIZE (defined in
# perf_helpers.sh). If SIZE leaves no room for the handful of commands the
# session itself adds (the seeding lines, warmup, etc.), the shell silently
# TRUNCATES the OLDEST entries on load — dropping wdi_oldest_needle and making
# the `oldest`/`absent` scans under-measure while still looking valid. Reject
# such a SIZE loudly rather than reporting mislabeled numbers. We reserve a small
# fixed headroom for those session commands. (Chosen a static guard over
# auto-growing PERF_HISTSIZE so the history cap stays an explicit, reviewed knob.)
PERF_SESSION_HEADROOM=500
_max_size=$((PERF_HISTSIZE - PERF_SESSION_HEADROOM))
if [[ "$SIZE" -gt "$_max_size" ]]; then
  echo "bench.sh: SIZE ($SIZE) exceeds seeded-history capacity ($_max_size)." >&2
  echo "bench.sh: that is PERF_HISTSIZE ($PERF_HISTSIZE) minus ${PERF_SESSION_HEADROOM}-line session headroom." >&2
  echo "bench.sh: lower SIZE or raise PERF_HISTSIZE in perf_helpers.sh." >&2
  exit 2
fi

# --- Temp fixtures + cleanup -------------------------------------------------
# Fixture and an empty PERF_HOME (so the caller's real ~/.config/whatdidi config
# can't perturb the default count, and thus the amount of scanning) both live in
# the system temp dir and are removed on ANY exit via the trap.
FIXTURE="$(mktemp "${TMPDIR:-/tmp}/wdi_perf_hist.XXXXXX")"
PERF_HOME="$(mktemp -d "${TMPDIR:-/tmp}/wdi_perf_home.XXXXXX")"
export PERF_HOME
cleanup() { rm -rf "$FIXTURE" "$PERF_HOME"; }
trap cleanup EXIT

# Generate the fixture once. gen_history.sh is deterministic for a given
# SIZE + WDI_HIST_SEED, so repeated runs benchmark identical input.
bash "$SCRIPT_DIR/gen_history.sh" "$SIZE" "$FIXTURE"
FIXTURE_LINES="$(wc -l < "$FIXTURE" | tr -d ' ')"

# --- Select available shells -------------------------------------------------
# Honour the requested SHELLS but silently skip any whose binary is missing so
# the harness still runs on a box without, say, zsh installed.
AVAIL_SHELLS=()
for sh in $SHELLS; do
  if command -v "$sh" >/dev/null 2>&1; then
    AVAIL_SHELLS+=("$sh")
  else
    printf 'bench.sh: %s not found on PATH; skipping\n' "$sh" >&2
  fi
done
if [[ "${#AVAIL_SHELLS[@]}" -eq 0 ]]; then
  echo "bench.sh: none of the requested shells ($SHELLS) are available" >&2
  exit 1
fi

# --- Environment banner ------------------------------------------------------
BOLD=$'\033[1m'; RESET=$'\033[0m'
printf '%s=== whatdidi performance benchmark ===%s\n\n' "$BOLD" "$RESET"
if command -v bash >/dev/null 2>&1; then
  printf '  bash:    %s\n' "$(bash --version 2>/dev/null | head -1)"
fi
if command -v zsh >/dev/null 2>&1; then
  printf '  zsh:     %s\n' "$(zsh --version 2>/dev/null | head -1)"
fi
printf '  fixture: %s lines (SIZE=%s, seed=%s)\n' \
  "$FIXTURE_LINES" "$SIZE" "${WDI_HIST_SEED:-1}"
printf '  batch:   ITERS(K)=%s  REPS(R)=%s\n' "$ITERS" "$REPS"
printf '  shells:  %s\n\n' "${AVAIL_SHELLS[*]}"

# --- Scenarios ---------------------------------------------------------------
# Parallel arrays (bash 3.2 has no associative arrays): a display name and the
# exact `whatdidi <needle> <count>` args each scenario drives. The needles are
# the fixed tokens planted by gen_history.sh.
SCEN_NAMES=(absent recent oldest spread)
SCEN_ARGS=(
  "wdi_absent_needle 1"
  "wdi_recent_needle 1"
  "wdi_oldest_needle 5"
  "wdi_spread_needle 100"
)

# --- Table header ------------------------------------------------------------
COL_FMT='%-9s %-6s %10s %10s %10s %10s\n'
printf "${BOLD}${COL_FMT}${RESET}" scenario shell "min(ms)" "median" "mean" "max"
printf -- '%.0s-' $(seq 1 56); printf '\n'

# Dispatch to the shell-specific runner. Kept as a helper so the scenario loop
# below reads uniformly regardless of which shell is being measured.
run_for_shell() {
  local shell="$1" args="$2"
  case "$shell" in
    bash) perf_run_bash "$FIXTURE" "$args" "$ITERS" "$REPS" ;;
    zsh)  perf_run_zsh  "$FIXTURE" "$args" "$ITERS" "$REPS" ;;
    *)    echo "bench.sh: no runner for shell '$shell'" >&2; return 1 ;;
  esac
}

# --- Run every scenario on every available shell -----------------------------
i=0
while [[ $i -lt ${#SCEN_NAMES[@]} ]]; do
  name="${SCEN_NAMES[$i]}"
  args="${SCEN_ARGS[$i]}"
  for shell in "${AVAIL_SHELLS[@]}"; do
    # Collect R per-call samples, then reduce them to order statistics (ms).
    samples="$(run_for_shell "$shell" "$args")"
    # Guard: a broken measurement (e.g. missing perl clock) yields no numeric
    # samples. Surface it as dashes rather than printing a misleading 0.000.
    got="$(printf '%s\n' "$samples" | grep -c -E '^[0-9]' || true)"
    if [[ "$got" -eq 0 ]]; then
      printf "$COL_FMT" "$name" "$shell" "-" "-" "-" "-"
      printf 'bench.sh: no samples for %s/%s (measurement failed)\n' \
        "$name" "$shell" >&2
    else
      stats="$(printf '%s\n' "$samples" | perf_stats)"
      # stats == "min median mean max"; splat into positional args for printf.
      # shellcheck disable=SC2086
      set -- $stats
      printf "$COL_FMT" "$name" "$shell" "$1" "$2" "$3" "$4"
    fi
  done
  i=$((i + 1))
done

printf '\n'
