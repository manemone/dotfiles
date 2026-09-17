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
  local candidate
  # DFXFER_HOSTS is a space-separated list, so it has to be split — but
  # through `read -a` rather than an unquoted expansion, which would also
  # glob (a host alias is unlikely to contain * or ?, but silently expanding
  # one against the cwd is not a failure mode worth leaving open).
  local hosts=()
  if [ -n "${DFXFER_HOSTS:-}" ]; then
    read -r -a hosts <<<"${DFXFER_HOSTS}"
  fi

  if [ -n "$configured" ]; then
    # Rule 5: cross-check against the list, but only when a list exists.
    # Running with just DFXFER_HOST and no DFXFER_HOSTS is a supported
    # single-destination setup, not a misconfiguration.
    if [ "${#hosts[@]}" -gt 0 ]; then
      for candidate in "${hosts[@]}"; do
        if [ "$candidate" = "$configured" ]; then
          printf '%s\n' "$configured"
          return 0
        fi
      done
      dfxfer_die \
        "DFXFER_HOST='$configured' is not listed in DFXFER_HOSTS." \
        "Known destinations: ${hosts[*]}" \
        "Fix one or the other in ~/.zshrc.local (remember 'export')."
    fi
    printf '%s\n' "$configured"
    return 0
  fi

  # Rule 2: an unambiguous list needs no DFXFER_HOST.
  if [ "${#hosts[@]}" -eq 1 ]; then
    printf '%s\n' "${hosts[0]}"
    return 0
  fi

  if [ "${#hosts[@]}" -eq 0 ]; then
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
    "Known destinations: ${hosts[*]}" \
    "Name the default in ~/.zshrc.local (export is required):" \
    "" \
    "  export DFXFER_HOST=\"${hosts[0]}\""
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

# dfxfer_remote_dir
# Print the handoff directory on the remote, relative to its home.
dfxfer_remote_dir() {
  printf '%s\n' "${DFXFER_REMOTE_DIR:-uploads}"
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
