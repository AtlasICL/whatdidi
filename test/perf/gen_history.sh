#!/usr/bin/env bash
#
# gen_history.sh — deterministic synthetic shell-history generator for the
# whatdidi performance harness.
#
# WHY: bench.sh needs a large, *reproducible* history file with a KNOWN
# match distribution so it can drive specific search scenarios (best case,
# near-full scan, no matches, many matches) and compare shells fairly. Real
# ~/.bash_history is neither reproducible nor controllable, so we synthesise
# one with a seeded PRNG.
#
# USAGE:
#   gen_history.sh [SIZE] [OUTFILE]
#     SIZE     number of history lines to emit  (default: 50000)
#              may also be set via the SIZE env var; the positional arg wins.
#     OUTFILE  path to write to; if omitted the history is printed to stdout.
#
#   Env knobs:
#     SIZE            default line count when $1 is absent (default 50000)
#     WDI_HIST_SEED   PRNG seed, integer 1..2147483646 (default 1). Changing
#                     it reshuffles the filler while preserving all guarantees.
#
# OUTPUT FORMAT: one command per line, NO leading history numbers — this
# matches how a HISTFILE stores raw entries on disk (bash/zsh add the numbers
# only when *listing* via `history` / `fc -l`). The lines are therefore
# directly loadable with `history -n` (bash) or `fc -R` (zsh).
#
# DETERMINISM: filler is produced by a Park–Miller minimal-standard LCG
# (multiplier 16807, modulus 2^31-1). Its products stay < 2^53 so awk's
# double-precision integer math is EXACT, giving byte-identical output across
# runs and across awk implementations for a given SIZE+seed. (We deliberately
# avoid awk's built-in rand()/srand(), whose sequence is implementation-defined.)
#
# PLANTED MATCH DISTRIBUTION (all needles are `wdi_*` so they can never collide
# with the real-command filler vocabulary). History is stored oldest-first, so
# line 1 is the OLDEST entry and line SIZE is the NEWEST; whatdidi scans
# newest-first (from line SIZE downward):
#
#   wdi_recent_needle  — planted on the NEWEST 5 lines (SIZE-4 .. SIZE).
#                        Best case: a newest-first scan finds it immediately,
#                        so count=1 early-exits after a handful of iterations.
#
#   wdi_oldest_needle  — planted on the OLDEST 8 lines (1 .. 8) and NOWHERE
#                        else. Collecting count=5 matches forces the scan to
#                        walk from the newest entry down to within ~4 lines of
#                        the very oldest — i.e. a near-full history sweep.
#
#   wdi_spread_needle  — planted on every 50th line (i % 50 == 0) that does not
#                        fall inside a reserved band above. Frequency is thus
#                        ~SIZE/50 occurrences (e.g. ~1000 at SIZE=50000), giving
#                        a count=100 run enough matches within the newest ~5000
#                        entries. If SIZE is small enough that fewer than the
#                        requested count exist, whatdidi simply returns them all.
#
#   wdi_absent_needle  — NEVER emitted anywhere. A search for it scans the whole
#                        history and returns 0 matches (worst case for work-done,
#                        zero matches to collect).
#
# Reserved bands take precedence over the spread rule, so the guaranteed counts
# above are exact. SIZE should be >= ~50 for the bands not to overlap; the
# harness uses thousands, so this is never a concern in practice.

set -euo pipefail

# Resolve args: positional SIZE wins over the SIZE env var, which falls back to
# the built-in default. OUTFILE is optional (empty => stdout).
SIZE="${1:-${SIZE:-50000}}"
OUTFILE="${2:-}"
SEED="${WDI_HIST_SEED:-1}"

# Validate SIZE up front: a bad value should fail loudly rather than silently
# producing a garbage fixture the benchmark would then mis-measure.
if ! [[ "$SIZE" =~ ^[0-9]+$ ]] || [[ "$SIZE" -lt 1 ]]; then
  echo "gen_history.sh: SIZE must be a positive integer (got: $SIZE)" >&2
  exit 2
fi
# Park–Miller requires a seed in 1..(2^31-2); reject 0 / non-numeric early.
if ! [[ "$SEED" =~ ^[0-9]+$ ]] || [[ "$SEED" -lt 1 ]] || [[ "$SEED" -gt 2147483646 ]]; then
  echo "gen_history.sh: WDI_HIST_SEED must be an integer in 1..2147483646 (got: $SEED)" >&2
  exit 2
fi

# The whole fixture is produced by a single awk program: it is POSIX, already a
# dependency of this project, and orders of magnitude faster than a shell loop
# for 50k lines. Redirecting is handled by the caller-visible `emit` below.
emit() {
  awk -v n="$SIZE" -v seed="$SEED" '
    # --- Park–Miller minimal-standard PRNG (exact in IEEE doubles) ------------
    function rnd() { _s = (16807 * _s) % 2147483647; return _s }
    # Uniform integer in [0, m-1].
    function irand(m) { return rnd() % m }
    # Pick a 1-based element from an array of length len.
    function pick(arr, len) { return arr[irand(len) + 1] }

    BEGIN {
      _s = seed

      # Reserved-band sizes (see header). Kept small and fixed so the planted
      # counts are exact and independent of SIZE.
      OLD = 8      # oldest lines carrying wdi_oldest_needle
      REC = 5      # newest lines carrying wdi_recent_needle
      SPREAD_PERIOD = 50

      # --- Filler vocabulary -------------------------------------------------
      # A spread of everyday commands so matching is not trivially uniform.
      # Each verb draws from its own argument pool below to look realistic.
      nv = split("git ls cd curl vim cat grep make docker npm python echo mkdir rm cp mv ssh tar find sed awk brew node go kubectl systemctl ping", verbs, " ")

      ngit  = split("status|log --oneline -10|commit -m \"wip\"|push origin main|pull --rebase|checkout -b feature|diff --staged|rebase -i HEAD~3|stash pop|fetch --all", gitargs, "|")
      npath = split("src/|./build|~/projects|/tmp/out|../shared|dist/|node_modules|/var/log|assets/img|test/perf", paths, "|")
      nurl  = split("https://api.example.com/v1/users|http://localhost:8080/health|https://raw.githubusercontent.com/o/r/main|https://example.org/data.json", urls, "|")
      nhost = split("build-01|db.internal|10.0.0.5|staging.example.com|gateway", hosts, "|")
      npkg  = split("install|run build|test --watch|ci|update|run lint|start", pkgs, "|")
      nflag = split("-la|-rf|-p|--verbose|-v|--force|-h|-n 20|--dry-run|-x", flags, "|")

      for (i = 1; i <= n; i++) {
        # Reserved bands first so planted counts stay exact.
        if (i <= OLD) {
          # Oldest band: a real, matchable oldest-only needle command line.
          print "wdi_oldest_needle --run " (i)
          continue
        }
        if (i > n - REC) {
          print "wdi_recent_needle --run " (n - i + 1)
          continue
        }
        if (i % SPREAD_PERIOD == 0) {
          print "wdi_spread_needle --job " i
          continue
        }

        # --- Filler: build a plausible "<verb> <args>" line ------------------
        v = pick(verbs, nv)
        if (v == "git")            line = v " " pick(gitargs, ngit)
        else if (v == "curl")      line = v " " pick(flags, nflag) " " pick(urls, nurl)
        else if (v == "ssh")       line = v " " pick(hosts, nhost)
        else if (v == "npm")       line = v " " pick(pkgs, npkg)
        else if (v == "cd")        line = v " " pick(paths, npath)
        else if (v == "ls")        line = v " " pick(flags, nflag) " " pick(paths, npath)
        else if (v == "rm" || v == "cp" || v == "mv")
                                   line = v " " pick(flags, nflag) " " pick(paths, npath)
        else if (v == "grep")      line = v " " pick(flags, nflag) " needle " pick(paths, npath)
        else if (v == "docker")    line = v " ps " pick(flags, nflag)
        else if (v == "kubectl")   line = v " get pods " pick(flags, nflag)
        else if (v == "find")      line = v " " pick(paths, npath) " -name \"*.log\""
        else                       line = v " " pick(flags, nflag)

        print line
      }
    }
  '
}

if [[ -n "$OUTFILE" ]]; then
  emit > "$OUTFILE"
else
  emit
fi
