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

# shared/helpers.sh fires a one-shot "Deploying from a linked git worktree"
# notice the moment it's sourced (its source-time guard). uninstall.sh never
# deploys anything — it only removes $HOME symlinks and cleans up the
# distribution artifacts — so that notice would never be accurate here.
# Pre-set the "already warned" flag the guard checks (not
# DOTFILES_QUIET_WORKTREE_WARNING — that one is the user's own explicit
# silence switch and must stay untouched here) before sourcing.
DOTFILES_WORKTREE_WARNED=1

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
# KNOWN_LINKS_<tool> and links_for_tool() now live in shared/helpers.sh —
# deploy-all.sh --status needs the same list to check for broken symlinks,
# and keeping one copy is what prevents the drift that let ocw-meter go
# unlisted here in the first place (see ADR DOC-2608040229 §2.6).

# Skills are symlinked individually by skills/deploy.sh (auto-detected from
# skills/), into every agent's own skills directory (ADR DOC-2608272128).
# We walk each of those directories at uninstall time and restore any
# symlink whose target is repo-owned. A symlink counts as repo-owned under
# either scheme: the current distribution scheme (target under
# DOTFILES_PREFIX — via `current` or a generations/ dir directly, see
# resolve_deploy_src) or the pre-migration direct-to-worktree scheme (target
# under the checkout itself), each in both its post-split (skills/) and
# pre-split (claude/skills/) spelling. All of them must be recognized so
# that machines with leftover links from an older scheme can still be
# cleaned up after adopting the current one (ADR DOC-2608040229 §4.8/§4.10,
# ADR DOC-2608272128 §4.2).
#
# This flag is a plain boolean (only its non-emptiness is checked below),
# not a path — the actual repo-owned-symlink resolution for every scheme
# and every agent lives entirely in skill_links() (shared/helpers.sh). A
# tool that needs the same "walk the agents' skills directories for
# repo-owned symlinks" logic should get its own arm here.
KNOWN_SKILLS_SRC_skills=1

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

  # Get the list of known links for this tool via links_for_tool (defined
  # in shared/helpers.sh). KNOWN_GENERATED_* / KNOWN_SKILLS_SRC_* have only
  # one case arm each, so they aren't worth routing through a helper the
  # way KNOWN_LINKS_* is.
  _links="$(links_for_tool "$_tool")"
  _generated=""
  case "$_tool" in
    claude) _generated="$KNOWN_GENERATED_claude" ;;
  esac

  # Resolved before the "nothing to do" guard below, not after: skills is a
  # tool with no links_for_tool() arm and no generated files by design (its
  # $HOME-side links are per-skill and per-agent, so skill_links() is their
  # source of truth — see links_for_tool()'s comment). Leaving it out of the
  # guard would make the guard's `continue` skip skill removal entirely,
  # under a "No link list defined" warning that reads like a forgotten arm.
  _skills_src=""
  case "$_tool" in
    skills) _skills_src="$KNOWN_SKILLS_SRC_skills" ;;
  esac

  if [ -z "$_links" ] && [ -z "$_generated" ] && [ -z "$_skills_src" ]; then
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

  # --- skills: walk every agent's skills directory for repo-owned links ---
  if [ -n "$_skills_src" ]; then
    _OLDIFS="$IFS"
    IFS='
'
    for _skill_link in $(skill_links "$SCRIPT_DIR"); do
      IFS="$_OLDIFS"
      [ -z "$_skill_link" ] && continue
      _skill_name=$(basename "$_skill_link")
      symlink_restore "$_skill_link" || OVERALL_OK=1

      # After removing the symlink, try to restore the original skill that
      # skills/deploy.sh backed up into that agent's skills-backup/.
      # Resolved per link rather than per run: skill_links() returns a flat
      # list spanning every agent, and each agent has its own backup
      # directory. Pick the oldest backup (first in glob order) — same
      # policy as symlink_restore for .backup files.
      _skill_backup_dir="$(skill_backup_dir_for_link "$_skill_link")"
      if [ -n "$_skill_backup_dir" ]; then
        for _cand in "$_skill_backup_dir/$_skill_name".*; do
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
      fi
      IFS='
'
    done
    IFS="$_OLDIFS"

    # skills-backup/ is where skills/deploy.sh set aside pre-existing skills
    # before symlinking over them (see its backup step). Once every
    # restorable skill above has been moved back out of it, an empty
    # directory is the only thing left — clean it up as part of the same
    # "undo what deploy did" pass, the same way the distribution artifact
    # cleanup below cleans up what deploy-all.sh created. One per agent: an
    # agent that never had a name collision never gets a backup directory,
    # and rmdir on a missing or non-empty one is a no-op either way.
    IFS='
'
    for _skill_agent in $(skill_agents); do
      IFS="$_OLDIFS"
      _skill_backup_dir="$(skill_backup_dir_for_agent "$_skill_agent")"
      if [ -n "$_skill_backup_dir" ] && [ -d "$_skill_backup_dir" ]; then
        if [ "${DRY_RUN:-0}" -eq 1 ]; then
          printf '[DRY-RUN] rmdir %s (only if empty)\n' "$_skill_backup_dir"
        elif rmdir "$_skill_backup_dir" 2>/dev/null; then
          log_ok "Removed empty skills-backup directory: $_skill_backup_dir"
        fi
      fi
      IFS='
'
    done
    IFS="$_OLDIFS"
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
# under it. The same is true of a tool that WAS in scope but whose
# symlink_restore call above failed (OVERALL_OK=1): the link may still be
# sitting there, live, pointing into the generation we're about to delete.
#
# So in real (non-DRY_RUN) mode we scan the live filesystem for every tool
# in AVAILABLE_TOOLS, regardless of $TOOLS — a tool's links only count as
# "cleared" if they're actually gone, not because this run merely
# attempted them. Only under --dry-run, where the loop above never touches
# the filesystem at all, do we instead trust that a tool in $TOOLS would be
# cleared by a real run and skip re-checking it (checking it would just
# see its still-intact symlink and wrongly report "still referenced").
#
# Deletion never touches whatever `current` resolves to. In dev mode (see
# ADR §4.5 / DOC-2608040229) `current` points at the human's own source
# tree; the only thing removed there is the `current` symlink itself. The
# real, cp -a'd generation directories under generations/ are always safe
# to remove outright (rm -rf via _dotfiles_safe_rmdir), independent of what
# `current` happens to point at, because a dev-mode `current` never points
# inside generations/ in the first place — see "全孫共通の注意" §2.

_dfu_still_referenced=0
_dfu_reason_path=""
_dfu_scope=" $TOOLS "

for _dfu_check_tool in $AVAILABLE_TOOLS; do
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    case "$_dfu_scope" in
      *" $_dfu_check_tool "*) continue ;; # dry-run: trust a real run would clear this
    esac
  fi

  _OLDIFS="$IFS"
  IFS='
'
  for _dfu_dst in $(links_for_tool "$_dfu_check_tool"); do
    IFS="$_OLDIFS"
    [ -z "$_dfu_dst" ] && continue
    if [ -L "$_dfu_dst" ]; then
      case "$(readlink "$_dfu_dst")" in
        "$DOTFILES_PREFIX"/*)
          _dfu_still_referenced=1
          [ -n "$_dfu_reason_path" ] || _dfu_reason_path="$_dfu_dst"
          ;;
      esac
    fi
    IFS='
'
  done
  IFS="$_OLDIFS"
done

if [ "${DRY_RUN:-0}" -eq 1 ]; then
  case "$_dfu_scope" in
    *" skills "*) _dfu_check_skills=0 ;; # dry-run: trust the skills would be cleared
    *) _dfu_check_skills=1 ;;
  esac
else
  _dfu_check_skills=1 # real run: always verify against the live filesystem
fi

# skill_links() called without a repo_root argument deliberately: this scan
# only asks "does anything still resolve through the distribution prefix we
# are about to delete", and a leftover direct-to-worktree link (which a
# repo_root argument would add) points at the source tree instead, so it is
# not a reason to keep the prefix alive.
if [ "$_dfu_still_referenced" -eq 0 ] && [ "$_dfu_check_skills" -eq 1 ]; then
  _OLDIFS="$IFS"
  IFS='
'
  for _dfu_skill_link in $(skill_links); do
    IFS="$_OLDIFS"
    [ -z "$_dfu_skill_link" ] && continue
    _dfu_still_referenced=1
    [ -n "$_dfu_reason_path" ] || _dfu_reason_path="$_dfu_skill_link"
    IFS='
'
  done
  IFS="$_OLDIFS"
fi

if [ "$_dfu_still_referenced" -ne 0 ]; then
  # Deliberately not "another tool's" — in real mode this can just as well
  # be a tool that WAS in scope but whose own removal above failed
  # (OVERALL_OK=1). Naming the actual offending path lets the operator
  # tell the two cases apart instead of guessing.
  log_info "Still referenced: $_dfu_reason_path points into the distribution prefix — skipping its cleanup (either a tool outside --only, or removal of this link failed above)."
elif [ -L "$DOTFILES_CURRENT_LINK" ] || [ -d "$DOTFILES_GENERATIONS_DIR" ] || [ -d "$DOTFILES_PREFIX/.tmp" ]; then
  log_hr
  log_info "Cleaning up distribution artifacts"

  if [ -L "$DOTFILES_CURRENT_LINK" ]; then
    _dfu_current_target=$(readlink "$DOTFILES_CURRENT_LINK")
    case "$_dfu_current_target" in
      "$DOTFILES_GENERATIONS_DIR"/*) ;;
      *)
        log_info "current is in dev mode: it points at a source tree ($_dfu_current_target), which will NOT be touched. Only the current symlink itself is removed here; any generations/ directory (from earlier generation-mode deploys) is still cleaned up separately below."
        ;;
    esac
  fi

  if [ -d "$DOTFILES_GENERATIONS_DIR" ]; then
    if _dotfiles_safe_rmdir "$DOTFILES_GENERATIONS_DIR" "$DOTFILES_PREFIX"; then
      [ "${DRY_RUN:-0}" -eq 1 ] || log_ok "Removed generations directory: $DOTFILES_GENERATIONS_DIR"
    else
      log_error "Failed to remove generations directory: $DOTFILES_GENERATIONS_DIR"
      OVERALL_OK=1
    fi
  fi

  # create_generation's scratch workspace (mktemp -d "$DOTFILES_PREFIX/.tmp/gen.XXXXXX",
  # then mv'd into generations/ on success — see shared/helpers.sh). The
  # .tmp/ directory itself is created with `mkdir -p` and outlives every
  # generation it ever scratch-built, so it's always present after at
  # least one successful deploy; a crashed deploy can also leave a
  # half-built gen.XXXXXX scratch dir under it that nothing else ever
  # sweeps. Removing it here is what actually lets the final rmdir below
  # succeed, and also clears any orphaned crash leftovers.
  if [ -d "$DOTFILES_PREFIX/.tmp" ]; then
    if _dotfiles_safe_rmdir "$DOTFILES_PREFIX/.tmp" "$DOTFILES_PREFIX"; then
      [ "${DRY_RUN:-0}" -eq 1 ] || log_ok "Removed scratch directory: $DOTFILES_PREFIX/.tmp"
    else
      log_error "Failed to remove scratch directory: $DOTFILES_PREFIX/.tmp"
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
