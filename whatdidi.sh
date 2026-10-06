# Install: 1) add this file to $HOME/.local/share/whatdidi/whatdidi
#          2) add `source $HOME/.local/share/whatdidi/whatdidi` to ~/.bashrc and/or ~/.zshrc


whatdidi() {
  local needle count line default_count default_unique _wdi_conf _wdi_line stripped desudo
  local unique seen sep _wdi_arg _wdi_i _wdi_n _wdi_unique_seen
  # Single source of truth for the version string. The test suite extracts this
  # same line from the script (see EXPECTED_VERSION in test/helpers.sh) so the
  # value only ever needs bumping here.
  local version="1.5.0"
  _wdi_conf="${HOME}/.config/whatdidi/config"
  default_count=1
  # Track whether a default_unique= line was seen with a boolean, kept separate
  # from its value: an empty-string value alone can't tell apart "key absent"
  # (normal, no warning) from "key present but empty" (garbage, warn), so we can't
  # use the value itself as the sentinel the way an empty string would suggest.
  default_unique=""
  _wdi_unique_seen=0
  if [[ -f "$_wdi_conf" ]]; then
    while IFS= read -r _wdi_line || [[ -n "$_wdi_line" ]]; do
      # Trim a single trailing carriage return so hand-edited / Windows (CRLF)
      # configs aren't rejected: without this a "default_count=3\r" line fails
      # the digit regex and "default_unique=true\r" fails the true/false check,
      # spuriously warning "invalid ... using ...". `$'\r'` is understood by
      # both bash 3.2+ and zsh.
      _wdi_line="${_wdi_line%$'\r'}"
      [[ "$_wdi_line" == default_count=* ]] && default_count="${_wdi_line#default_count=}"
      [[ "$_wdi_line" == default_unique=* ]] && { default_unique="${_wdi_line#default_unique=}"; _wdi_unique_seen=1; }
    done < "$_wdi_conf"
  fi
  # A corrupt/hand-edited config shouldn't make the tool unusable: fall back to
  # the built-in default and warn rather than erroring out.
  # Force base-10 once the value is known to be all digits: a stray leading zero
  # (e.g. 08) is otherwise read as octal by bash arithmetic and errors, while
  # zsh treats it as decimal — normalizing here keeps both shells in agreement.
  [[ "$default_count" =~ ^[0-9]+$ ]] && default_count=$((10#$default_count))
  if ! [[ "$default_count" =~ ^[0-9]+$ ]] || [[ "$default_count" -lt 1 ]]; then
    echo "whatdidi: invalid default_count in $_wdi_conf; using 1" >&2
    default_count=1
  fi
  # Mirror the default_count handling for default_unique. Absence is normal (the
  # key simply wasn't set) so it silently becomes "false"; a present-but-invalid
  # value is a corrupt config, so warn and fall back to "false" — exactly like
  # the invalid default_count case above. A present-but-EMPTY line (default_unique=)
  # counts as present-but-invalid and warns too, since _wdi_unique_seen distinguishes
  # it from true absence. Only the literal lowercase spellings "true"/"false" are
  # accepted, matching what the --set-default-unique setter writes and keeping
  # bash 3.2 and zsh in agreement.
  if [[ "$_wdi_unique_seen" -eq 0 ]]; then
    default_unique="false"
  elif [[ "$default_unique" != "true" && "$default_unique" != "false" ]]; then
    echo "whatdidi: invalid default_unique in $_wdi_conf; using false" >&2
    default_unique="false"
  fi
  # Seed the runtime unique flag from the persisted default before parsing args,
  # so the config value takes effect when no flag is given and the flags below can
  # still override it either way.
  if [[ "$default_unique" == "true" ]]; then
    unique=1
  else
    unique=0
  fi
  # Parse optional -u/--unique / --no-unique flags out of the argument list before
  # reading positional args, so they can appear anywhere: `whatdidi -u curl 3`,
  # `whatdidi curl 3 -u`, and `whatdidi curl -u 2` are all equivalent. Rotate the
  # positional params — shift each arg off the front and, unless it's a flag,
  # re-append it to the end — so after $# passes the non-flag args are back in
  # their original order with the flags removed. This is a fully portable rebuild
  # (no arrays, which bash 3.2 lacks and zsh spells differently) that preserves
  # arg boundaries, so multi-word needles like "git push" survive intact.
  # --no-unique forces dedup off (e.g. to override a `true` default); because each
  # case sets `unique` as the flag is encountered and we process args in order,
  # when both -u and --no-unique are given the LAST one on the line wins.
  _wdi_n=$#
  _wdi_i=0
  while [[ "$_wdi_i" -lt "$_wdi_n" ]]; do
    _wdi_arg="$1"
    shift
    case "$_wdi_arg" in
      -u|--unique) unique=1 ;;
      --no-unique) unique=0 ;;
      *) set -- "$@" "$_wdi_arg" ;;
    esac
    _wdi_i=$((_wdi_i+1))
  done

  needle="${1:-}"
  count="${2:-$default_count}"

  if [[ "$needle" == "--version" || "$needle" == "-v" ]]; then
    echo "whatdidi $version"
    echo "Author: Emre Acarsoy"
    return 0
  fi

  if [[ "$needle" == "--help" || "$needle" == "-h" ]]; then
    cat <<'HELP'
Usage:
  whatdidi [-u] <command> [count]

Arguments:
  command   The command name to search for in your shell history.
            Use quotes for multi-word commands (e.g. "git push").
  count     Number of recent matches to show (default: 1).

Options:
  --set-default-count <n>         Set the default number of results to show
                                  when count is not specified. Persists across
                                  sessions (~/.config/whatdidi/config).
  --set-default-unique <true|false>
                                  Set whether results are deduplicated by
                                  default. Persists across sessions.
  --update                        Reinstall whatdidi with the latest version.
  --uninstall                     Uninstall whatdidi from your system.
  -u, --unique                    Only return unique (deduplicated) results.
  --no-unique                     Override a 'true' default and return all results.
  -v, --version                   Show version and author information.
  -h, --help                      Show this help message.

Examples:
  whatdidi curl                # last curl command you ran
  whatdidi mvn 3               # last 3 mvn commands
  whatdidi "git switch" 2      # last 2 git switch commands
  whatdidi -u git 5            # last 5 distinct git commands
  whatdidi --no-unique git 5   # last 5 git commands even if unique is the default

Commands prefixed with sudo are also matched.
HELP
    return 0
  fi

  if [[ "$needle" == "--update" ]]; then
    if ! command -v curl >/dev/null 2>&1; then
      echo "whatdidi: curl is required to update but was not found" >&2
      return 1
    fi
    local reply
    # `read -p` is bash-only; in zsh -p reads from the coprocess, so prompt
    # via printf and read the reply separately to stay portable.
    printf 'Update whatdidi to the latest version? [Y/n] ' >&2
    read -r reply
    reply="${reply:-Y}"
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
      echo "whatdidi: update cancelled"
      return 0
    fi
    echo "whatdidi: fetching the latest version ..."
    curl -fsSL https://raw.githubusercontent.com/AtlasICL/whatdidi/main/install | sh
    return $?
  fi

  if [[ "$needle" == "--uninstall" ]]; then
    local reply
    # `read -p` is bash-only; in zsh -p reads from the coprocess, so prompt
    # via printf and read the reply separately to stay portable.
    printf 'Uninstall whatdidi? This will remove the tool and your config. [Y/n] ' >&2
    read -r reply
    reply="${reply:-Y}"
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
      echo "whatdidi: uninstall cancelled"
      return 0
    fi
    local install_path="${HOME}/.local/share/whatdidi/whatdidi"
    local source_line="source ${HOME}/.local/share/whatdidi/whatdidi"
    local conf_dir="${HOME}/.config/whatdidi"
    # Track whether any rc rewrite failed so a partial failure isn't masked by
    # the success message + `return 0` at the end of the block.
    local uninstall_failed=0
    # Declare the rc loop variable local: whatdidi is *sourced* into the user's
    # interactive shell, so an undeclared `rc` would leak the last rc path into
    # their environment after `whatdidi --uninstall`.
    local rc rc_tmp
    if [[ -f "$install_path" ]]; then
      rm -f "$install_path"
      echo "whatdidi: removed $install_path"
      # Clean up the now-empty install dir too. `rmdir` only removes an empty
      # directory, so it fails harmlessly (and silently) if the user kept other
      # files there or the dir is already gone.
      rmdir "$(dirname "$install_path")" 2>/dev/null || true
    fi
    for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
      if [[ -f "$rc" ]] && grep -qxF "$source_line" "$rc" 2>/dev/null; then
        # Create the scratch file with mktemp (unpredictable name — no clobbering
        # an attacker-planted symlink at a guessable path) in the SAME directory
        # as the rc file so it inherits the target's filesystem and permission
        # context. Mirrors the installer's mktemp usage. On mktemp failure, warn
        # and flag the failure rather than pressing on with an empty path.
        if ! rc_tmp="$(mktemp "${rc}.XXXXXXXX")"; then
          echo "whatdidi: failed to create a temp file to rewrite $rc" >&2
          uninstall_failed=1
          continue
        fi
        # Don't gate on grep's exit status: when the source line is the ONLY
        # line, grep -v matches nothing and exits 1, which would otherwise skip
        # the write and orphan the temp file. We want the (possibly empty)
        # filtered output either way.
        grep -vxF "$source_line" "$rc" > "$rc_tmp"
        # Copy back with `cat >` rather than `mv` so a symlinked rc file (common
        # with dotfile managers) is edited in place — mv would replace the
        # symlink with a regular file and leave the real repo-managed file stale.
        # Only drop the temp file and claim success if the write actually
        # completed: if `cat >` fails mid-write (e.g. disk full) the temp copy is
        # the only intact version, so keep it and report the failure to stderr.
        if cat "$rc_tmp" > "$rc"; then
          rm -f "$rc_tmp"
          echo "whatdidi: removed source line from $rc"
        else
          echo "whatdidi: failed to rewrite $rc; left $rc_tmp in place" >&2
          uninstall_failed=1
        fi
      fi
    done
    # The config dir is independent of the rc files, so clean it up even if an
    # rc rewrite failed above — but still surface the failure below.
    # Guard on a non-empty $HOME: if HOME were empty/unset, conf_dir would be
    # "/.config/whatdidi" (a system path), and `rm -rf` must never target that.
    if [[ -n "$HOME" && -d "$conf_dir" ]]; then
      rm -rf "$conf_dir"
      echo "whatdidi: removed config directory $conf_dir"
    fi
    if [[ "$uninstall_failed" -ne 0 ]]; then
      echo "whatdidi: uninstall completed with errors; see messages above" >&2
      return 1
    fi
    echo "whatdidi: uninstalled. You may restart your terminal to complete removal."
    return 0
  fi

  if [[ "$needle" == "--set-default-count" ]]; then
    local new_count="${2:-}"
    if [[ -z "$new_count" ]] || ! [[ "$new_count" =~ ^[0-9]+$ ]]; then
      echo "whatdidi: --set-default-count requires a nonzero positive int" >&2
      return 2
    fi
    # Force base-10 before the range check and before persisting, so an input
    # like 08 becomes 8 rather than a config bash later chokes on as octal.
    new_count=$((10#$new_count))
    if [[ "$new_count" -lt 1 ]]; then
      echo "whatdidi: --set-default-count requires a nonzero positive int" >&2
      return 2
    fi
    mkdir -p "${HOME}/.config/whatdidi"
    # Preserve any unrelated config keys: read the existing file, drop every
    # existing default_count= line, keep everything else verbatim (including any
    # default_unique= line the unique setter wrote), then append the new
    # default_count line. A plain `> "$_wdi_conf"` would truncate the whole file
    # and silently discard other keys. Build the new content in a temp file, then
    # copy it back with `cat >` rather than `mv` so a symlinked config (common
    # with dotfile managers) is edited in place — `mv` would replace the symlink
    # with a regular file and leave the real repo-managed target stale. This
    # mirrors the write-through the uninstall rc-rewrite deliberately uses. The
    # read loop mirrors the portable `read` pattern used to load the config near
    # the top of this function (works identically in bash 3.2 and zsh).
    # Create the scratch file with mktemp (unpredictable name, no clobbering a
    # guessable path) in the config dir just `mkdir -p`'d above so it shares the
    # target's filesystem and permissions; mirrors the installer's mktemp usage.
    local _wdi_tmp
    if ! _wdi_tmp="$(mktemp "${HOME}/.config/whatdidi/config.XXXXXXXX")"; then
      echo "whatdidi: failed to write $_wdi_conf" >&2
      return 1
    fi
    if [[ -f "$_wdi_conf" ]]; then
      while IFS= read -r _wdi_line || [[ -n "$_wdi_line" ]]; do
        [[ "$_wdi_line" == default_count=* ]] && continue
        printf '%s\n' "$_wdi_line" >> "$_wdi_tmp"
      done < "$_wdi_conf"
    fi
    printf 'default_count=%s\n' "$new_count" >> "$_wdi_tmp"
    # Only drop the temp file and claim success if the write-through actually
    # completed: if `cat >` fails mid-write (e.g. disk full) the temp copy is the
    # only intact version, so keep it and report the failure to stderr.
    if cat "$_wdi_tmp" > "$_wdi_conf"; then
      rm -f "$_wdi_tmp"
    else
      echo "whatdidi: failed to write $_wdi_conf" >&2
      return 1
    fi
    echo "whatdidi: default count set to $new_count"
    return 0
  fi

  if [[ "$needle" == "--set-default-unique" ]]; then
    local new_unique="${2:-}"
    # Only the literal lowercase spellings "true"/"false" are valid — the same
    # spellings the config stores and the loader reads — so the persisted value
    # round-trips cleanly. Anything else (or a missing value) is a user error.
    if [[ "$new_unique" != "true" && "$new_unique" != "false" ]]; then
      echo "whatdidi: --set-default-unique requires 'true' or 'false'" >&2
      return 2
    fi
    mkdir -p "${HOME}/.config/whatdidi"
    # Symmetric to the count setter above: preserve any unrelated config keys by
    # reading the existing file, dropping ONLY existing default_unique= lines, and
    # keeping everything else verbatim (crucially the default_count= line, so the
    # two setters never clobber each other's key), then append the new
    # default_unique line. Copy back with `cat >` rather than `mv` so a symlinked
    # config is edited in place, and keep the temp file + report failure if the
    # write-through doesn't complete. The read loop is the same portable pattern
    # used everywhere else in this function (bash 3.2 and zsh agree).
    # Create the scratch file with mktemp (unpredictable name, no clobbering a
    # guessable path) in the config dir just `mkdir -p`'d above so it shares the
    # target's filesystem and permissions; mirrors the installer's mktemp usage.
    local _wdi_tmp
    if ! _wdi_tmp="$(mktemp "${HOME}/.config/whatdidi/config.XXXXXXXX")"; then
      echo "whatdidi: failed to write $_wdi_conf" >&2
      return 1
    fi
    if [[ -f "$_wdi_conf" ]]; then
      while IFS= read -r _wdi_line || [[ -n "$_wdi_line" ]]; do
        [[ "$_wdi_line" == default_unique=* ]] && continue
        printf '%s\n' "$_wdi_line" >> "$_wdi_tmp"
      done < "$_wdi_conf"
    fi
    printf 'default_unique=%s\n' "$new_unique" >> "$_wdi_tmp"
    # Only drop the temp file and claim success if the write-through actually
    # completed: if `cat >` fails mid-write (e.g. disk full) the temp copy is the
    # only intact version, so keep it and report the failure to stderr.
    if cat "$_wdi_tmp" > "$_wdi_conf"; then
      rm -f "$_wdi_tmp"
    else
      echo "whatdidi: failed to write $_wdi_conf" >&2
      return 1
    fi
    echo "whatdidi: default unique set to $new_unique"
    return 0
  fi

  if [[ -z "$needle" || $# -gt 2 ]]; then
    echo "Usage: whatdidi <command> [count]  (try --help)" >&2
    return 2
  fi
  # Force base-10 before the range check and the later decrement so a leading
  # zero (e.g. 08) doesn't trip bash's octal arithmetic.
  [[ "$count" =~ ^[0-9]+$ ]] && count=$((10#$count))
  if ! [[ "$count" =~ ^[0-9]+$ ]] || [[ "$count" -lt 1 ]]; then
    echo "whatdidi: count must be a nonzero positive int" >&2
    echo "For searching for a compound command (e.g. whatdidi \"git clone\") please use double quotes" >&2
    return 2
  fi

  # Refresh session history so the search sees the latest commands (bash only;
  # zsh keeps the interactive history in memory already).
  if [ -z "${ZSH_VERSION:-}" ]; then
    builtin history -a 2>/dev/null || true
    builtin history -n 2>/dev/null || true
  fi

  # All matching happens in ONE awk process that reads history newest-first and
  # exits as soon as it has printed `count` lines. A shell `while read` loop
  # costs ~6us/line just for `read` (one syscall per byte on a pipe) plus the
  # glob tests, i.e. ~1s per 50k lines; awk does the same work in <1us/line and
  # its early exit SIGPIPEs the producer so the best case never lists the
  # whole history.
  #
  # The needle goes through ENVIRON, not `-v`: `-v` interprets backslash
  # escapes, which would mangle a needle like 'printf \n'.
  #
  # Producers (both emit newest event first, lines within an event in order):
  #   bash: `fc -lnr 1` prefixes each event's first line with "\t " (or "\t*"
  #         for an edited entry); lithist continuation lines are raw. fc also
  #         omits the current command line (the whatdidi call itself).
  #   zsh:  `fc -rln 1` prints each event on one line, no prefix.
  #
  # mawk (default awk on Debian/Ubuntu) blocks until its input buffer is full
  # before running any rule, which defeats the early exit: the producer has to
  # emit ~100s of KB first. `-W interactive` makes it read line by line. BWK awk
  # (macOS) and gawk read what is available and need no flag. Detect once per
  # shell session and cache the answer in a global.
  if [ -z "${_WDI_AWK_IS_MAWK:-}" ]; then
    case "$(awk -W version 2>&1 </dev/null)" in
      mawk*) _WDI_AWK_IS_MAWK=1 ;;
      *)     _WDI_AWK_IS_MAWK=0 ;;
    esac
  fi
  # needle/count are already captured, so the positional params are free to
  # carry the optional awk flags (bash 3.2 has no arrays to spare for this).
  if [ "$_WDI_AWK_IS_MAWK" = 1 ]; then set -- -W interactive; else set --; fi

  {
    if [ -n "${ZSH_VERSION:-}" ]; then
      builtin fc -rln 1
    else
      builtin fc -lnr 1
    fi
  } 2>/dev/null | WDI_NEEDLE="$needle" WDI_COUNT="$count" WDI_UNIQUE="$unique" WDI_ZSH="${ZSH_VERSION:+1}" awk "$@" '
    function hit(s) {
      return substr(s, 1, nl) == needle && (length(s) == nl || substr(s, nl + 1, 1) ~ /[ \t\r\f\v]/)
    }
    BEGIN {
      needle = ENVIRON["WDI_NEEDLE"]; nl = length(needle)
      count = ENVIRON["WDI_COUNT"] + 0; uniq = (ENVIRON["WDI_UNIQUE"] == "1")
      selff = (substr(needle, 1, 8) != "whatdidi"); zsh = (ENVIRON["WDI_ZSH"] == "1")
    }
    {
      if (!index($0, needle)) next
      line = $0
      if (zsh) sub(/^[ \t]+/, "", line); else sub(/^\t[ *][ \t]*/, "", line)
      if (line == "") next
      if (selff && substr(line, 1, 9) == "whatdidi ") next
      s = line; sub(/^[ \t\r\f\v]+/, "", s)
      if (!hit(s)) {
        if (substr(s, 1, 4) != "sudo" || substr(s, 5, 1) !~ /[ \t\r\f\v]/) next
        s = substr(s, 5); sub(/^[ \t\r\f\v]+/, "", s)
        if (!hit(s)) next
      }
      if (uniq) { if (line in seen) next; seen[line] = 1 }
      print line
      if (--count <= 0) exit
    }
  '

  return 0
}
