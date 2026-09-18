# dfxfer-lib.sh — shared plumbing for the dfup / dfdown file-handoff commands.
#
# Sourced (never executed) by bin/dfup and bin/dfdown, both of which are bash
# with `set -euo pipefail`. Everything both directions need — destination
# resolution, rsync discovery, the --iconv decision, the common option list,
# local directory layout — lives here so the two commands differ only in the
# src/dst order they hand to rsync.
#
# No shebang on purpose: this file is never run directly. With no shebang
# there is nothing for the linter to infer the dialect from — it falls back
# to POSIX sh and rejects every `local` — hence the `shell=bash` directive
# below, which states which shell this is rather than suppressing anything.
# bin/tests/lint.sh picks the file up for `bash -n` because it matches *.sh.
#
# Design decisions and their rationale: docs/planning/DOC-2609172237_file-handoff_計画.md
# 設計1 (1.2 through 1.8).

# shellcheck shell=bash

# ── shared/helpers.sh ─────────────────────────────────────────────────
#
# Platform detection has to go through is_macos / is_linux rather than a bare
# `uname` (AGENTS.md "クロスプラットフォーム制約"), and those live in
# shared/helpers.sh. ${BASH_SOURCE[0]} is this file's real path — bin/dfup
# already resolved its own symlink before sourcing us — so ../shared is the
# checkout (or the deployed generation, which also carries shared/).
#
# helpers.sh has a source-time guard that warns when it is sourced from a
# linked git worktree. That warning is written for the deploy scripts ("$HOME
# symlinks resolve through the distributed generation..."), which is nonsense
# coming out of a file-transfer command, so silence it through the environment
# variable helpers.sh documents for exactly this purpose.
_dfxfer_lib_dir=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_dfxfer_helpers="$_dfxfer_lib_dir/../shared/helpers.sh"

if [ ! -f "$_dfxfer_helpers" ]; then
  printf '[ERROR] dfxfer: shared/helpers.sh not found at %s\n' "$_dfxfer_helpers" >&2
  exit 1
fi

DOTFILES_QUIET_WORKTREE_WARNING=1
# shellcheck source=SCRIPTDIR/../shared/helpers.sh
. "$_dfxfer_helpers"

# ── Errors ────────────────────────────────────────────────────────────

# dfxfer_die <message>...
# Print each argument as its own error line, then exit 1.
dfxfer_die() {
  local line
  for line in "$@"; do
    log_error "$line"
  done
  exit 1
}

# ── Destination host ──────────────────────────────────────────────────

# dfxfer_host
# Print the destination host alias, applying the five rules in 計画書 1.3.
# Dies with setup guidance when the destination cannot be determined —
# "which host?" is exactly the question a human has to answer once, in
# ~/.zshrc.local, and never again.
dfxfer_host() {
  local configured="${DFXFER_HOST:-}"
  local listed="${DFXFER_HOSTS:-}"
  local candidate
  local count=0
  local first=""
  local matched=0
  local names=""
  local restore_glob=1

  # DFXFER_HOSTS is a space-separated list, so it has to be split. Globbing
  # is switched off around the split so that an alias containing * or ?
  # cannot expand against the current directory (a host alias is unlikely to
  # contain one, but silently sending to a cwd-derived name is not a failure
  # mode worth leaving open).
  #
  # A bash array would read better than this counter, but this file runs
  # under `set -u` on macOS's stock /bin/bash, which is 3.2: there, merely
  # expanding a *zero-element* array — including "${arr[@]}" — raises
  # "unbound variable". Zero destinations is not an exotic case here, it is
  # what every unconfigured machine looks like, so the command would die
  # before it could print the setup instructions below. bin/ocw's
  # resolve_removal_target() carries the same workaround for the same
  # reason (see its comment, and PR #49).
  case "$-" in *f*) restore_glob=0 ;; esac
  set -f
  for candidate in $listed; do
    count=$((count + 1))
    if [ -z "$first" ]; then
      first="$candidate"
      names="$candidate"
    else
      names="$names $candidate"
    fi
    if [ "$candidate" = "$configured" ]; then
      matched=1
    fi
  done
  [ "$restore_glob" -eq 0 ] || set +f

  if [ -n "$configured" ]; then
    # Rule 5: cross-check against the list, but only when a list exists.
    # Running with just DFXFER_HOST and no DFXFER_HOSTS is a supported
    # single-destination setup, not a misconfiguration.
    if [ "$count" -gt 0 ] && [ "$matched" -eq 0 ]; then
      dfxfer_die \
        "DFXFER_HOST='$configured' is not listed in DFXFER_HOSTS." \
        "Known destinations: $names" \
        "Fix one or the other in ~/.zshrc.local (remember 'export')."
    fi
    printf '%s\n' "$configured"
    return 0
  fi

  # Rule 2: an unambiguous list needs no DFXFER_HOST.
  if [ "$count" -eq 1 ]; then
    printf '%s\n' "$first"
    return 0
  fi

  if [ "$count" -eq 0 ]; then
    dfxfer_die \
      "No destination configured." \
      "Add this to ~/.zshrc.local (it is sourced by zsh, so 'export' is required" \
      "for dfup / dfdown to see it — they run as separate processes):" \
      "" \
      "  export DFXFER_HOSTS=\"toybox\"   # ssh Host aliases, space separated" \
      "  export DFXFER_HOST=\"toybox\"    # the default one" \
      "" \
      "The names are ~/.ssh/config Host aliases, not hostnames."
  fi

  dfxfer_die \
    "DFXFER_HOSTS lists more than one destination, and no default is set." \
    "Known destinations: $names" \
    "Name the default in ~/.zshrc.local (export is required):" \
    "" \
    "  export DFXFER_HOST=\"$first\""
}

# ── rsync discovery ───────────────────────────────────────────────────

# dfxfer_rsync_major <path>
# Print the major version of the rsync at <path>, or nothing when the binary
# does not identify itself as "rsync version N.M". openrsync (what recent
# macOS ships in place of rsync) reports only a protocol version and so comes
# back empty, which is the correct answer: it is not rsync 3.x either.
# The `|| true` is not cosmetic: callers run under `set -euo pipefail`, where a
# probe of something that turns out not to be runnable would otherwise abort the
# whole command through the assignment that captures this output — with no
# message, because the failing command never got to say anything.
dfxfer_rsync_major() {
  { "$1" --version 2>/dev/null || true; } | awk 'NR == 1 {
    for (i = 1; i < NF; i++) {
      if ($i == "version" && $(i + 1) ~ /^[0-9]+\./) {
        split($(i + 1), parts, ".")
        print parts[1]
        exit
      }
    }
  }'
}

# dfxfer_resolve_rsync
# Set DFXFER_RSYNC_CMD to the rsync to run and DFXFER_RSYNC_MAJOR to its major
# version (empty when unknown). Search order is 計画書 1.4: an explicit
# DFXFER_RSYNC wins outright, otherwise the first 3.x found on PATH or in a
# Homebrew prefix wins, otherwise whatever rsync exists at all.
#
# macOS matters here: its bundled rsync is 2.6.9 (or openrsync), neither of
# which has --iconv, while `brew install rsync` puts a 3.x alongside it.
dfxfer_resolve_rsync() {
  local explicit="${DFXFER_RSYNC:-}"
  local fallback=""
  local brew_prefix
  local candidate

  if [ -n "$explicit" ]; then
    # A typo here would otherwise surface much later, as a bare exec failure
    # from a command the human never typed. They set this once in
    # ~/.zshrc.local and then forget it exists, so name it in the message.
    if ! command -v "$explicit" >/dev/null 2>&1; then
      dfxfer_die \
        "DFXFER_RSYNC is set to '$explicit', which is not an executable command." \
        "Fix it in ~/.zshrc.local, or unset it to let dfup find rsync by itself."
    fi
    DFXFER_RSYNC_CMD="$explicit"
    DFXFER_RSYNC_MAJOR=$(dfxfer_rsync_major "$explicit")
    return 0
  fi

  local candidates=()
  if command -v rsync >/dev/null 2>&1; then
    candidates+=("$(command -v rsync)")
  fi
  brew_prefix=$(get_brew_prefix)
  if [ -n "$brew_prefix" ]; then
    candidates+=("$brew_prefix/bin/rsync")
  fi
  # Unconditional, and load-bearing: it is what keeps `candidates` non-empty
  # at the expansion below. An empty array there would raise "unbound
  # variable" on macOS's bash 3.2 under `set -u` — the same trap that
  # dfxfer_host() above is written around.
  candidates+=(/opt/homebrew/bin/rsync /usr/local/bin/rsync)

  for candidate in "${candidates[@]}"; do
    [ -x "$candidate" ] || continue
    [ -n "$fallback" ] || fallback="$candidate"
    if [ "$(dfxfer_rsync_major "$candidate")" = "3" ]; then
      DFXFER_RSYNC_CMD="$candidate"
      DFXFER_RSYNC_MAJOR="3"
      return 0
    fi
  done

  if [ -z "$fallback" ]; then
    dfxfer_die \
      "rsync not found." \
      "Install it with your package manager (macOS: 'brew install rsync')."
  fi

  DFXFER_RSYNC_CMD="$fallback"
  DFXFER_RSYNC_MAJOR=$(dfxfer_rsync_major "$fallback")
}

# ── rsync options ─────────────────────────────────────────────────────

# dfxfer_build_opts
# Fill DFXFER_OPTS with the option list both directions share (計画書 1.7),
# after resolving rsync. Call once, then splice "${DFXFER_OPTS[@]}" into the
# invocation.
#
# Deliberately absent, and load-bearing by their absence:
#   --delete              would propagate deletions; this is a one-way copy
#   --remove-source-files would delete the original after sending (計画書 5.4)
#   -X / -A               macOS xattrs and ACLs make rsync error out on Linux
dfxfer_build_opts() {
  dfxfer_resolve_rsync

  DFXFER_OPTS=(
    -a
    -v -h -P
    --exclude=.DS_Store
    '--exclude=._*'
  )

  # --iconv=LOCAL,REMOTE names the two *machines*, not the direction of the
  # transfer: man rsync says "This order ensures that the option will stay the
  # same whether you're pushing or pulling files." So dfup and dfdown pass the
  # identical spec — HFS+/APFS hands out NFD ("UTF-8-MAC"), Linux stores NFC.
  #
  # On Linux local there is nothing to convert; passing this would corrupt
  # names that are already NFC, so it must never be added there.
  if is_macos; then
    if [ "${DFXFER_RSYNC_MAJOR:-}" = "3" ]; then
      DFXFER_OPTS+=('--iconv=UTF-8-MAC,UTF-8')
    else
      log_warn "rsync at $DFXFER_RSYNC_CMD is not 3.x — transferring without --iconv."
      log_warn "Japanese (and other non-ASCII) filenames will arrive with their"
      log_warn "combining marks split apart. Install a 3.x rsync to fix this:"
      log_warn "  brew install rsync"
    fi
  fi
}

# ── Local directory layout ────────────────────────────────────────────

# dfxfer_local_dir <host> <out|in>
# Print $DFXFER_DIR/<host>/<leaf>, creating it when missing so the first run
# on a new machine needs no mkdir from the human (計画書 1.2).
dfxfer_local_dir() {
  local host="$1"
  local leaf="$2"
  local dir="${DFXFER_DIR:-$HOME/dfxfer}/$host/$leaf"

  mkdir -p "$dir" || dfxfer_die "Failed to create directory: $dir"
  printf '%s\n' "$dir"
}

# dfxfer_remote_dir <up|down>
# Print the handoff directory on the remote, relative to its home. up and
# down use separate directories: sharing one would mean a file dfup just sent
# reappears as "newly arrived" the next time dfdown runs against the same
# directory.
dfxfer_remote_dir() {
  # DFXFER_REMOTE_DIR predates the up/down split and is no longer read by
  # either direction. Silently falling back to the default here would send
  # or pull from the wrong place with no error — die instead so a
  # still-configured ~/.zshrc.local gets fixed instead of ignored.
  if [ -n "${DFXFER_REMOTE_DIR:-}" ]; then
    dfxfer_die \
      "DFXFER_REMOTE_DIR is no longer used." \
      "Remove it from ~/.zshrc.local — as long as it is set, this error keeps" \
      "firing even after you also export the variable below; it is not a" \
      "second knob alongside DFXFER_REMOTE_DIR, it replaces it." \
      "Set DFXFER_REMOTE_UP_DIR (for dfup) and/or DFXFER_REMOTE_DOWN_DIR (for dfdown) instead."
  fi

  case "$1" in
    up) printf '%s\n' "${DFXFER_REMOTE_UP_DIR:-uploads}" ;;
    down) printf '%s\n' "${DFXFER_REMOTE_DOWN_DIR:-downloads}" ;;
    *) dfxfer_die "dfxfer_remote_dir: invalid argument '$1' (expected up or down)" ;;
  esac
}

# dfxfer_has_dry_run_flag <rsync-passthrough-args...>
# True if any of the arguments dfdown/dfup forward to rsync would make it a
# dry run: --dry-run, a bare -n, or -n bundled into another short option
# (-an, -vn, ...). Used to keep "-n means nothing is touched" true even for
# the remote mkdir dfdown does before its own rsync call — a long option
# other than --dry-run (say --exclude=foo*n*) must not false-positive here,
# hence the separate --* arm that consumes it before the -*n* check runs.
dfxfer_has_dry_run_flag() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --dry-run) return 0 ;;
      --*) ;;
      -*)
        # Only a token made up entirely of dashes and letters can be a
        # bundle of short options (-an, -vn, ...). Anything else starting
        # with "-" is a value, not an option — most notably an rsync filter
        # rule passed via -f/--include/--exclude, which conventionally
        # starts with "- " for an exclude and can contain an "n" anywhere
        # in the pattern (e.g. "-f '- *.png'"). Matching those as dry-run
        # would skip the remote mkdir during an ordinary transfer.
        case "$arg" in
          *[!a-zA-Z-]*) ;;
          *n*) return 0 ;;
        esac
        ;;
    esac
  done
  return 1
}

# dfxfer_ensure_remote_dir <host> <dir>
# Create <dir> on <host>'s home over ssh if it does not exist yet, and say so
# when it actually had to. Only dfdown needs this: pushing with rsync creates
# the destination automatically (what lets dfup use a brand-new
# DFXFER_REMOTE_UP_DIR without ever mkdir'ing it first), but pulling does not
# — rsync refuses a source directory that is not there, so the first dfdown
# against a fresh remote would otherwise die on a bare rsync error instead of
# just working.
#
# The existence check has to happen on the remote and be reported back,
# rather than just running `mkdir -p` and staying quiet: a plain `mkdir -p`
# is silent either way, which would turn a typo'd DFXFER_REMOTE_DOWN_DIR from
# a loud rsync "no such file" error (what happened before this function
# existed) into "conjure an empty directory and report success" — exactly
# the kind of silent breakage this test suite exists to catch.
dfxfer_ensure_remote_dir() {
  local host="$1"
  local dir="$2"
  local result

  # ssh(1): additional command-line arguments after <host> are "appended to
  # the command, separated by spaces" before the *remote* shell parses that
  # flattened string — argv boundaries do not survive the trip. Passing
  # $dir as a trailing argv element (an earlier version of this function
  # did `sh -c '...' _ "$dir"`) therefore does not arrive as a separate
  # token: it becomes part of the one string the remote re-parses, and
  # unless that happens to still be valid shell syntax, the remote fails
  # with a syntax error instead of running anything.
  #
  # Sending the script over stdin instead sidesteps this: the remote
  # command line is just "sh" (nothing for ssh to flatten), and $dir is
  # substituted here, locally, by this heredoc (its terminator is
  # deliberately unquoted) before the already-resolved text is sent — so
  # the remote receives a literal value baked into valid syntax, not
  # something it has to parse out of a reassembled command line.
  result=$(
    # shellcheck disable=SC2087 # deliberately client-side: $dir must resolve here, before the remote gets it
    ssh "$host" sh <<REMOTE_SCRIPT
if [ -d "$dir" ]; then
  printf existing
else
  mkdir -p -- "$dir" && printf created
fi
REMOTE_SCRIPT
  ) || dfxfer_die "Failed to create $host:$dir/ over ssh. Check connectivity and permissions."

  if [ "$result" = "created" ]; then
    log_info "$host:$dir/ did not exist yet — created it. Check DFXFER_REMOTE_UP_DIR / DFXFER_REMOTE_DOWN_DIR for a typo if that is unexpected."
  fi
}

# dfxfer_is_empty_dir <dir>
# Return 0 when <dir> holds nothing but . and .. — used to tell the human
# "there was nothing to move" instead of leaving them staring at silent output.
dfxfer_is_empty_dir() {
  local entry
  for entry in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    return 1
  done
  return 0
}
