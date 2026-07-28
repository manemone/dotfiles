#!/bin/sh
#
# deploy-all.sh — Unified deployment orchestrator for all dotfile tools.
#
# Usage:
#   ./deploy-all.sh                Interactive mode (asks before each tool)
#   ./deploy-all.sh --dry-run      Print what would be done, don't do it
#   ./deploy-all.sh --force        Skip all confirmations
#   ./deploy-all.sh --only zsh,nvim   Deploy specific tools only
#   ./deploy-all.sh --backup       Always back up existing files (on by default)
#   ./deploy-all.sh --no-backup    Skip backing up existing files
#
# Options can be combined:
#   ./deploy-all.sh --dry-run --only tmux
#   ./deploy-all.sh --force --only zsh,nvim

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
. "$SCRIPT_DIR/shared/helpers.sh"

# ── Defaults ──────────────────────────────────────────────────────────

DRY_RUN=0
FORCE=0
BACKUP=1
ONLY_TOOLS=""

# ── Usage ─────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Unified deployment orchestrator for all dotfile tools.

Options:
  --dry-run         Print what would be done, make no changes.
  --force           Skip all confirmation prompts.
  --only <tools>    Comma-separated list of tools to deploy.
                    Available: $AVAILABLE_TOOLS
  --backup          Back up existing config files (default).
  --no-backup       Do NOT back up existing files before overwriting.
  --help, -h        Show this help message.

Examples:
  $0                           # Interactive, all tools
  $0 --dry-run                 # Preview everything
  $0 --only zsh,nvim           # Deploy only zsh and nvim
  $0 --force --only tmux       # Deploy tmux without prompts
EOF
}

# ── Parse arguments ───────────────────────────────────────────────────

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --force)
      FORCE=1
      ;;
    --backup)
      BACKUP=1
      ;;
    --no-backup)
      BACKUP=0
      ;;
    --only)
      if [ $# -lt 2 ]; then
        log_error "--only requires a comma-separated list of tools."
        exit 1
      fi
      ONLY_TOOLS="$2"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      usage >&2
      exit 1
      ;;
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
log_info "Platform: $(uname -s) ($(uname -m))"
if is_wsl; then
  log_info "WSL:      detected"
fi
log_info "Tools:   $TOOLS"
printf '\n'

# ── Confirmation (only in interactive mode, never in dry-run) ─────────

if [ "$FORCE" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  # Refuse to proceed when stdin is not a terminal (pipe / cron / CI).
  if [ ! -t 0 ]; then
    log_error "stdin is not a terminal. Use --force to deploy non-interactively."
    exit 1
  fi
  printf 'Proceed with deployment? [Y/n] '
  read -r _answer || {
    printf '\n'
    log_warn "Aborted (EOF on stdin)."
    exit 1
  }
  case "$_answer" in
    [Nn]|[Nn][Oo])
      log_warn "Aborted."
      exit 0
      ;;
  esac
  printf '\n'
fi

# ── Run each tool's deploy script ─────────────────────────────────────

export DRY_RUN
export BACKUP

OVERALL_OK=0

for _tool in $TOOLS; do
  _deploy_script="$SCRIPT_DIR/$_tool/deploy.sh"
  if [ ! -x "$_deploy_script" ]; then
    log_error "Deploy script not found or not executable: $_deploy_script"
    OVERALL_OK=1
    continue
  fi

  # Per-tool confirmation in interactive mode (never in dry-run)
  if [ "$FORCE" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    printf 'Deploy %s? [Y/n/s/q] ' "$_tool"
    read -r _answer || {
      printf '\n'
      log_warn "Aborted (EOF on stdin)."
      exit 1
    }
    case "$_answer" in
      [Ss]|[Ss][Kk][Ii][Pp]*)
        log_info "Skipping remaining tools."
        break
        ;;
      [Qq])
        log_warn "Aborted."
        exit 0
        ;;
      [Nn]|[Nn][Oo])
        log_info "Skipping: $_tool"
        continue
        ;;
    esac
  fi

  "$_deploy_script" || {
    log_error "Deploy script for '$_tool' exited with code $?."
    OVERALL_OK=1
  }
done

# ── Summary ───────────────────────────────────────────────────────────

printf '\n'
log_hr
if [ "$OVERALL_OK" -eq 0 ]; then
  log_ok "All deployments finished successfully. 🎉"
else
  log_warn "Deployment finished with some errors. Check the output above."
fi

exit "$OVERALL_OK"
