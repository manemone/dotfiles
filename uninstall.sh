#!/bin/sh
#
# uninstall.sh — Remove symlinks created by deploy scripts and restore backups.
#
# Usage:
#   ./uninstall.sh                 Interactive mode
#   ./uninstall.sh --dry-run       Print what would be done
#   ./uninstall.sh --force         Skip all confirmations
#   ./uninstall.sh --only zsh,nvim  Uninstall specific tools

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
. "$SCRIPT_DIR/shared/helpers.sh"

# ── Defaults ──────────────────────────────────────────────────────────

DRY_RUN=0
FORCE=0
ONLY_TOOLS=""

# ── Known symlinks per tool (dst only) ────────────────────────────────
# Each tool entry lists one symlink destination per line.
# Use printf so the trailing-newline line-continuation works portably.
KNOWN_LINKS_zsh=$(printf '%s\n' \
  "$HOME/.zshrc" \
  "$HOME/.zsh_plugins.txt" \
)

KNOWN_LINKS_nvim=$(printf '%s\n' \
  "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/init.lua" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/lua" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/lazy-lock.json" \
)

KNOWN_LINKS_tmux=$(printf '%s\n' \
  "$HOME/.tmux.conf" \
)

# ── Usage ─────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Remove dotfile symlinks and restore any .backup files.

Options:
  --dry-run         Print what would be done, make no changes.
  --force           Skip all confirmation prompts.
  --only <tools>    Comma-separated list of tools to uninstall.
                    Available: $AVAILABLE_TOOLS
  --help, -h        Show this help message.
EOF
}

# ── Parse arguments ───────────────────────────────────────────────────

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)    DRY_RUN=1 ;;
    --force)      FORCE=1 ;;
    --only)
      if [ $# -lt 2 ]; then
        log_error "--only requires a comma-separated list of tools."
        exit 1
      fi
      ONLY_TOOLS="$2"; shift ;;
    --help|-h)    usage; exit 0 ;;
    *)
      log_error "Unknown option: $1"
      usage >&2; exit 1 ;;
  esac
  shift
done

# ── Resolve tool list (with dedup) ────────────────────────────────────

eval "$(resolve_tools "$ONLY_TOOLS" "TOOLS")"

# ── Banner ────────────────────────────────────────────────────────────

printf '\n'
log_hr
if [ "$DRY_RUN" -eq 1 ]; then
  log_warn "DRY RUN MODE — no changes will be made."
fi
log_info "Uninstalling tools:$TOOLS"
printf '\n'

# ── Confirmation (only in interactive mode, never in dry-run) ─────────

if [ "$FORCE" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  if [ ! -t 0 ]; then
    log_error "stdin is not a terminal. Use --force to uninstall non-interactively."
    exit 1
  fi
  printf 'Proceed with uninstall? [y/N] '
  read -r _answer || {
    printf '\n'
    log_warn "Aborted (EOF on stdin)."
    exit 1
  }
  case "$_answer" in
    [Yy]|[Yy][Ee][Ss]) ;;
    *) log_warn "Aborted."; exit 0 ;;
  esac
  printf '\n'
fi

# ── Process each tool ─────────────────────────────────────────────────

export DRY_RUN
OVERALL_OK=0

for _tool in $TOOLS; do
  log_hr
  log_info "Uninstalling: $_tool"

  # Get the list of known links for this tool.
  # Guard: $_tool is validated by resolve_tools() above but we
  # double-check it contains only alphanumeric characters before
  # using it in a dynamic variable name to prevent injection.
  case "$_tool" in
    *[!a-zA-Z0-9_]*) log_error "Invalid tool name: '$_tool'"; continue ;;
  esac
  _links_var="KNOWN_LINKS_$_tool"
  eval "_links=\${$_links_var:-}"
  if [ -z "$_links" ]; then
    log_warn "No link list defined for '$_tool'. Skipping."
    continue
  fi

  # Iterate over links, one per line (IFS=newline to handle whitespace paths)
  _OLDIFS="$IFS"
  IFS='
'
  for _dst in $_links; do
    IFS="$_OLDIFS"
    [ -z "$_dst" ] && continue  # skip blank lines
    symlink_restore "$_dst" || OVERALL_OK=1
    IFS='
'
  done
  IFS="$_OLDIFS"
done

# ── Summary ───────────────────────────────────────────────────────────

printf '\n'
log_hr
if [ "$OVERALL_OK" -eq 0 ]; then
  log_ok "Uninstall complete."
else
  log_warn "Uninstall finished with some errors. Check the output above."
fi
log_warn "Note: Installed packages (zsh, tmux, etc.) were not removed."
log_warn "Note: Plugin managers (Antidote, lazy.nvim) were not removed."

exit "$OVERALL_OK"
