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

SCRIPT_DIR=$(
  cd "$(dirname "$0")" || exit 1
  pwd
)
# shellcheck source=SCRIPTDIR/shared/helpers.sh
. "$SCRIPT_DIR/shared/helpers.sh"

# ── Distribution layer paths ─────────────────────────────────────────
# Computed once: dotfiles_prefix()/dotfiles_current_link() only depend on
# $HOME / $XDG_DATA_HOME, which are stable for the life of this process.
DOTFILES_PREFIX="$(dotfiles_prefix)"
DOTFILES_CURRENT_LINK="$(dotfiles_current_link)"
DOTFILES_GENERATIONS_DIR="$DOTFILES_PREFIX/generations"

# ── Defaults ──────────────────────────────────────────────────────────

DRY_RUN=0
FORCE=0
ONLY_TOOLS=""

# ── Known symlinks per tool (dst only) ────────────────────────────────
# Each tool entry lists one symlink destination per line.
# Use printf so the trailing-newline line-continuation works portably.
KNOWN_LINKS_zsh=$(
  printf '%s\n' \
    "$HOME/.zshrc" \
    "$HOME/.zsh_plugins.txt"
)

KNOWN_LINKS_nvim=$(
  printf '%s\n' \
    "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/init.lua" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/lua" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/lazy-lock.json"
)

KNOWN_LINKS_tmux=$(
  printf '%s\n' \
    "$HOME/.tmux.conf"
)

KNOWN_LINKS_bin=$(
  printf '%s\n' \
    "$HOME/bin/ocw" \
    "$HOME/bin/claude-ds" \
    "$HOME/bin/ocw-meter"
)

KNOWN_LINKS_claude=$(
  printf '%s\n' \
    "$HOME/.claude/CLAUDE.md"
)

# Skills are symlinked individually by deploy.sh (auto-detected from
# claude/skills/).  We walk ~/.claude/skills/ at uninstall time and
# restore any symlink whose target is repo-owned. A symlink counts as
# repo-owned under either scheme: the current distribution scheme
# (target under DOTFILES_PREFIX — via `current` or a generations/ dir
# directly, see resolve_deploy_src) or the pre-migration direct-to-worktree
# scheme (target under the checkout itself). Both must be recognized so
# that machines with leftover pre-migration links can still be cleaned up
# after adopting the new scheme (ADR DOC-2608040229 §4.8/§4.9).
KNOWN_SKILLS_SRC_claude="$SCRIPT_DIR/claude/skills"

# settings.json is a generated file (not a symlink) — handled separately.
# symlink_restore would skip it because it's a real file.
KNOWN_GENERATED_claude=$(
  printf '%s\n' \
    "$HOME/.claude/settings.json"
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
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    --only)
      if [ $# -lt 2 ]; then
        log_error "--only requires a comma-separated list of tools."
        exit 1
      fi
      ONLY_TOOLS="$2"
      shift
      ;;
    --help | -h)
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
    [Yy] | [Yy][Ee][Ss]) ;;
    *)
      log_warn "Aborted."
      exit 0
      ;;
  esac
  printf '\n'
fi

# ── Process each tool ─────────────────────────────────────────────────

export DRY_RUN
OVERALL_OK=0

for _tool in $TOOLS; do
  log_hr
  log_info "Uninstalling: $_tool"

  # Get the list of known links for this tool. A case statement (rather
  # than eval-based indirection through a "KNOWN_LINKS_$_tool" variable
  # name) keeps each KNOWN_LINKS_* / KNOWN_GENERATED_* variable directly
  # referenced, so shellcheck can see the use and avoids eval entirely.
  _links=""
  case "$_tool" in
    zsh) _links="$KNOWN_LINKS_zsh" ;;
    nvim) _links="$KNOWN_LINKS_nvim" ;;
    tmux) _links="$KNOWN_LINKS_tmux" ;;
    bin) _links="$KNOWN_LINKS_bin" ;;
    claude) _links="$KNOWN_LINKS_claude" ;;
  esac
  _generated=""
  case "$_tool" in
    claude) _generated="$KNOWN_GENERATED_claude" ;;
  esac

  if [ -z "$_links" ] && [ -z "$_generated" ]; then
    log_warn "No link list defined for '$_tool'. Skipping."
    continue
  fi

  # Iterate over links, one per line (IFS=newline to handle whitespace paths)
  _OLDIFS="$IFS"
  if [ -n "$_links" ]; then
    IFS='
'
    for _dst in $_links; do
      IFS="$_OLDIFS"
      [ -z "$_dst" ] && continue # skip blank lines
      symlink_restore "$_dst" || OVERALL_OK=1
      IFS='
'
    done
  fi
  IFS="$_OLDIFS"

  # --- claude skills: walk ~/.claude/skills/ for repo-owned symlinks ---
  _skills_src=""
  case "$_tool" in
    claude) _skills_src="$KNOWN_SKILLS_SRC_claude" ;;
  esac

  if [ -n "$_skills_src" ] && [ -d "$HOME/.claude/skills" ]; then
    for _skill_link in "$HOME/.claude/skills"/*; do
      [ -L "$_skill_link" ] || continue
      _target=$(readlink "$_skill_link")
      # Recognize both schemes: current-scheme links go through
      # DOTFILES_PREFIX/current/claude/skills/<name> (the normal case) or,
      # if DOTFILES_DEPLOY_SRC was pointed at a generation directly, through
      # DOTFILES_PREFIX/generations/<id>/claude/skills/<name>. $_skills_src
      # (the working tree) covers pre-migration direct-to-worktree links.
      case "$_target" in
        "$DOTFILES_PREFIX/current/claude/skills"/* | "$DOTFILES_GENERATIONS_DIR"/*/claude/skills/* | "$_skills_src"/*)
          _skill_name=$(basename "$_skill_link")
          symlink_restore "$_skill_link" || OVERALL_OK=1

          # After removing the symlink, try to restore the original skill
          # that deploy.sh backed up into ~/.claude/skills-backup/.
          # Pick the oldest backup (first in glob order) — same policy as
          # symlink_restore for .backup files.
          for _cand in "$HOME/.claude/skills-backup/$_skill_name".*; do
            [ -e "$_cand" ] || [ -L "$_cand" ] || continue
            if [ "${DRY_RUN:-0}" -eq 1 ]; then
              printf '[DRY-RUN] mv %s %s\n' "$_cand" "$_skill_link"
            else
              if mv "$_cand" "$_skill_link"; then
                log_ok "Restored skill from backup: $_skill_link (from $(basename "$_cand"))"
              else
                log_error "Failed to restore skill backup: $_cand → $_skill_link"
                OVERALL_OK=1
              fi
            fi
            break
          done
          ;;
      esac
    done
  fi

  # Handle generated files (real files, not symlinks — e.g. claude/settings.json)
  if [ -n "$_generated" ]; then
    IFS='
'
    for _dst in $_generated; do
      IFS="$_OLDIFS"
      [ -z "$_dst" ] && continue

      # Step 1: Find deploy-time backup BEFORE creating any new files
      # (the glob in the else branch would otherwise match the safety backup
      #  we're about to create).
      _restore=""
      if [ -e "$_dst.backup" ] || [ -L "$_dst.backup" ]; then
        _restore="$_dst.backup"
      else
        for _cand in "$_dst.backup."*; do
          [ -e "$_cand" ] || [ -L "$_cand" ] || continue
          _restore="$_cand"
          break
        done
      fi

      # Step 2: Always safety-backup the current file before touching it
      # (so user edits made after deploy are never lost, even on new machines
      #  where no deploy-time .backup exists).
      _safety_path="${_dst}.backup.$(date +%Y%m%d%H%M%S).$$"

      if [ -f "$_dst" ] || [ -L "$_dst" ]; then
        if [ "${DRY_RUN:-0}" -eq 1 ]; then
          printf '[DRY-RUN] mv %s %s (safety backup)\n' "$_dst" "$_safety_path"
        else
          if mv "$_dst" "$_safety_path"; then
            log_info "Safety backup: $_dst → $_safety_path"
          else
            log_error "Failed to back up: $_dst"
            OVERALL_OK=1
            IFS='
'
            continue
          fi
        fi
      fi

      # Step 3: Restore the deploy-time backup (if found in Step 1)

      if [ -n "$_restore" ]; then
        if [ "${DRY_RUN:-0}" -eq 1 ]; then
          printf '[DRY-RUN] mv %s %s\n' "$_restore" "$_dst"
        else
          if mv "$_restore" "$_dst"; then
            log_ok "Restored deploy-time backup: $_dst (from $_restore)"
          else
            log_error "Failed to restore backup: $_restore → $_dst"
            OVERALL_OK=1
          fi
        fi
      else
        log_info "No deploy-time backup for $_dst — safety backup preserved."
      fi
      IFS='
'
    done
  fi
  IFS="$_OLDIFS"
done

# ── Distribution artifact cleanup (generations/ + current) ─────────────
#
# The canonical prefix is shared across every tool, not owned by any single
# one — it is not something a per-tool KNOWN_LINKS_* loop can safely tear
# down. If this uninstall run only targeted some tools (--only), a symlink
# belonging to a tool NOT in $TOOLS is untouched by this run and may still
# resolve through `current`, so we must not delete the prefix out from
# under it.
#
# We check membership in $TOOLS rather than re-scanning the filesystem for
# every tool: under --dry-run nothing was actually removed above, so a
# post-loop filesystem scan of a tool that WAS in scope would wrongly see
# its still-intact symlink and report a false "still referenced". A tool
# in $TOOLS is trusted to have been (or, in dry-run, to be about to be)
# cleared; only tools NOT in $TOOLS are checked against the live
# filesystem, since those are untouched in both real and dry-run modes.
#
# Deletion never touches whatever `current` resolves to. In dev mode (see
# ADR §4.5 / DOC-2608040229) `current` points at the human's own source
# tree; the only thing removed there is the `current` symlink itself. The
# real, cp -a'd generation directories under generations/ are always safe
# to remove outright (rm -rf via _dotfiles_safe_rmdir), independent of what
# `current` happens to point at, because a dev-mode `current` never points
# inside generations/ in the first place — see "全孫共通の注意" §2.

_dfu_still_referenced=0
_dfu_scope=" $TOOLS "

for _dfu_check_tool in $AVAILABLE_TOOLS; do
  case "$_dfu_scope" in
    *" $_dfu_check_tool "*) continue ;; # in scope this run — trust it's handled
  esac

  _dfu_check_links=""
  case "$_dfu_check_tool" in
    zsh) _dfu_check_links="$KNOWN_LINKS_zsh" ;;
    nvim) _dfu_check_links="$KNOWN_LINKS_nvim" ;;
    tmux) _dfu_check_links="$KNOWN_LINKS_tmux" ;;
    bin) _dfu_check_links="$KNOWN_LINKS_bin" ;;
    claude) _dfu_check_links="$KNOWN_LINKS_claude" ;;
  esac

  _OLDIFS="$IFS"
  IFS='
'
  for _dfu_dst in $_dfu_check_links; do
    IFS="$_OLDIFS"
    [ -z "$_dfu_dst" ] && continue
    if [ -L "$_dfu_dst" ]; then
      case "$(readlink "$_dfu_dst")" in
        "$DOTFILES_PREFIX"/*) _dfu_still_referenced=1 ;;
      esac
    fi
    IFS='
'
  done
  IFS="$_OLDIFS"
done

case "$_dfu_scope" in
  *" claude "*) ;; # claude in scope this run — trust its skills are handled
  *)
    if [ "$_dfu_still_referenced" -eq 0 ] && [ -d "$HOME/.claude/skills" ]; then
      for _dfu_skill_link in "$HOME/.claude/skills"/*; do
        [ -L "$_dfu_skill_link" ] || continue
        case "$(readlink "$_dfu_skill_link")" in
          "$DOTFILES_PREFIX"/*) _dfu_still_referenced=1 ;;
        esac
      done
    fi
    ;;
esac

if [ "$_dfu_still_referenced" -ne 0 ]; then
  log_info "Another tool's symlink still points into the distribution prefix — skipping its cleanup."
elif [ -L "$DOTFILES_CURRENT_LINK" ] || [ -d "$DOTFILES_GENERATIONS_DIR" ]; then
  log_hr
  log_info "Cleaning up distribution artifacts"

  if [ -L "$DOTFILES_CURRENT_LINK" ]; then
    _dfu_current_target=$(readlink "$DOTFILES_CURRENT_LINK")
    case "$_dfu_current_target" in
      "$DOTFILES_GENERATIONS_DIR"/*) ;;
      *)
        log_info "current is in dev mode (points at a source tree, not a generation) — only the symlink itself will be removed: $_dfu_current_target"
        ;;
    esac
  fi

  if [ -d "$DOTFILES_GENERATIONS_DIR" ]; then
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
      printf '[DRY-RUN] rm -rf %s\n' "$DOTFILES_GENERATIONS_DIR"
    elif _dotfiles_safe_rmdir "$DOTFILES_GENERATIONS_DIR" "$DOTFILES_PREFIX"; then
      log_ok "Removed generations directory: $DOTFILES_GENERATIONS_DIR"
    else
      log_error "Failed to remove generations directory: $DOTFILES_GENERATIONS_DIR"
      OVERALL_OK=1
    fi
  fi

  if [ -L "$DOTFILES_CURRENT_LINK" ]; then
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
      printf '[DRY-RUN] rm %s\n' "$DOTFILES_CURRENT_LINK"
    elif rm "$DOTFILES_CURRENT_LINK"; then
      log_ok "Removed current symlink: $DOTFILES_CURRENT_LINK"
    else
      log_error "Failed to remove current symlink: $DOTFILES_CURRENT_LINK"
      OVERALL_OK=1
    fi
  fi

  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    printf '[DRY-RUN] rmdir %s (only if empty)\n' "$DOTFILES_PREFIX"
  elif [ -d "$DOTFILES_PREFIX" ] && rmdir "$DOTFILES_PREFIX" 2>/dev/null; then
    log_ok "Removed empty prefix directory: $DOTFILES_PREFIX"
  fi
fi

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
