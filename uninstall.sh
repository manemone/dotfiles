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
AVAILABLE_TOOLS="zsh nvim tmux"

# ── Known symlinks per tool (dst only — src is inferred from the link target) ──
# Each tool entry lists the symlink destinations that deploy creates.
KNOWN_LINKS_zsh="
$HOME/.zshrc
$HOME/.zsh_plugins.txt
"

KNOWN_LINKS_nvim="
${XDG_CONFIG_HOME:-$HOME/.config}/nvim/init.vim
${XDG_CONFIG_HOME:-$HOME/.config}/nvim/dein.toml
${XDG_CONFIG_HOME:-$HOME/.config}/nvim/dein_lazy.toml
"

KNOWN_LINKS_tmux="
$HOME/.tmux.conf
"

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
      ONLY_TOOLS="$2"; shift ;;
    --help|-h)    usage; exit 0 ;;
    *)
      log_error "Unknown option: $1"
      usage >&2; exit 1 ;;
  esac
  shift
done

# ── Resolve tool list ─────────────────────────────────────────────────

if [ -n "$ONLY_TOOLS" ]; then
  TOOLS=""
  _OLDIFS="$IFS"
  IFS=','
  for _t in $ONLY_TOOLS; do
    IFS="$_OLDIFS"
    _t=$(printf '%s' "$_t" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    _found=0
    for _a in $AVAILABLE_TOOLS; do
      if [ "$_t" = "$_a" ]; then
        TOOLS="$TOOLS $_t"
        _found=1; break
      fi
    done
    if [ "$_found" -eq 0 ]; then
      log_error "Unknown tool: '$_t'. Available: $AVAILABLE_TOOLS"
      exit 1
    fi
    IFS=','
  done
  IFS="$_OLDIFS"
else
  TOOLS="$AVAILABLE_TOOLS"
fi

# ── Banner ────────────────────────────────────────────────────────────

printf '\n'
log_hr
if [ "$DRY_RUN" -eq 1 ]; then
  log_warn "DRY RUN MODE — no changes will be made."
fi
log_info "Uninstalling tools: $TOOLS"
printf '\n'

# ── Confirmation ──────────────────────────────────────────────────────

if [ "$FORCE" -eq 0 ]; then
  printf 'Proceed with uninstall? [y/N] '
  read -r _answer
  case "$_answer" in
    [Yy]|[Yy][Ee][Ss]) ;;
    *) log_warn "Aborted."; exit 0 ;;
  esac
  printf '\n'
fi

# ── Process each tool ─────────────────────────────────────────────────

export DRY_RUN

for _tool in $TOOLS; do
  log_hr
  log_info "Uninstalling: $_tool"

  # Get the list of known links for this tool via eval
  _links_var="KNOWN_LINKS_$_tool"
  eval "_links=\$$_links_var"

  for _dst in $_links; do
    if [ -L "$_dst" ]; then
      symlink_restore "$_dst"
    elif [ -e "$_dst.backup" ]; then
      # Link gone but backup exists — restore anyway
      if [ "${DRY_RUN:-0}" -eq 1 ]; then
        printf '[DRY-RUN] mv %s.backup %s\n' "$_dst" "$_dst"
      else
        mv "$_dst.backup" "$_dst" && log_ok "Restored backup: $_dst"
      fi
    else
      log_info "Nothing to do for: $_dst"
    fi
  done
done

# ── Summary ───────────────────────────────────────────────────────────

printf '\n'
log_hr
log_ok "Uninstall complete."
log_warn "Note: Installed packages (zsh, tmux, etc.) were not removed."
log_warn "Note: Plugin managers (Antidote, dein.vim) were not removed."
