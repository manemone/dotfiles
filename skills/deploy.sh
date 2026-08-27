#!/bin/sh

SCRIPT_DIR=$(
  cd "$(dirname "$0")" || exit 1
  pwd
)
# shellcheck source=SCRIPTDIR/../shared/helpers.sh
. "$SCRIPT_DIR/../shared/helpers.sh"

# --- Resolve distribution source (current generation) ---
# See AGENTS.md "デプロイの仕組み": standalone runs default to `current`;
# deploy-all.sh overrides this with the generation it just created.
resolve_deploy_src

log_hr
log_info "Deploying: skills (AI coding agent skills)"

FAIL=0

# --- Resolve where to enumerate skills from for THIS run ---
# symlink targets always point through DOTFILES_DEPLOY_SRC regardless of
# DRY_RUN, but the *enumeration* below branches on which directories exist,
# and in DRY_RUN mode DOTFILES_DEPLOY_SRC/skills may not exist yet (current
# not switched, or create_generation's own DRY-RUN branch never actually
# copies anything) — so the check would silently see "no skills" even when
# the real run will deploy several. A generation is a cp -a snapshot of the
# working tree (see create_generation), so the working tree is what the
# plan should describe. Same split claude/deploy.sh makes for settings.json.
if [ "${DRY_RUN:-0}" -eq 1 ]; then
  SKILLS_SRC_DIR="$SCRIPT_DIR"
else
  SKILLS_SRC_DIR="$DOTFILES_DEPLOY_SRC/skills"
fi

# Distinct from SKILLS_SRC_DIR on purpose: SKILLS_SRC_DIR is only the
# enumeration input (which skills exist, per the DRY_RUN branching above).
# SKILLS_DEPLOY_DIR is what symlinks actually get pointed at, and that must
# always be the real distribution source regardless of DRY_RUN — otherwise a
# dry-run plan would propose linking through the working tree, which is
# exactly the scheme ADR DOC-2608040229 retired.
SKILLS_DEPLOY_DIR="$DOTFILES_DEPLOY_SRC/skills"

# The pre-split distribution path (claude/skills/, before skills/ became its
# own tool — ADR DOC-2608272128 §4.3). Only used to recognize leftover
# symlinks from a machine deployed before the split, never as a link target.
LEGACY_DEPLOY_DIR="$DOTFILES_DEPLOY_SRC/claude/skills"
LEGACY_WORKTREE_DIR="$(dirname "$SCRIPT_DIR")/claude/skills"

if [ ! -d "$SKILLS_SRC_DIR" ]; then
  log_info "No skills directory — nothing to deploy."
  exit 0
fi

# --- Deploy to every agent whose config directory exists ---
# Skills are distributed to each agent as individual per-skill symlinks.
# A directory-wide symlink (<agent skills dir> -> repo/skills) is forbidden
# because it would wipe out the agent's own bundled skills plus any
# Herdr-managed and user-owned ones. Linking each skill directory
# individually lets all of them coexist.
_deployed_agents=0

for _agent in $(skill_agents); do
  _agent_home="$(skill_agent_home "$_agent")"
  _skills_dst_dir="$(skill_dir_for_agent "$_agent")"
  _skills_backup_dir="$(skill_backup_dir_for_agent "$_agent")"

  # An agent whose config directory does not exist is one this machine does
  # not use. Deploying would conjure up a whole tree for a tool that isn't
  # installed (ADR DOC-2608272128 §2.3). The exception is an agent whose
  # config directory this repo owns outright — see
  # agent_home_mode, which also carries the mode to create it
  # with, and explains why treating it as "not installed" would make every
  # --dry-run under-report what a real run does.
  _agent_home_mode="$(agent_home_mode "$_agent")"
  if [ ! -d "$_agent_home" ]; then
    if [ -z "$_agent_home_mode" ]; then
      log_info "Skipping $_agent — not installed on this machine ($_agent_home does not exist)."
      continue
    fi
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
      log_info "[DRY-RUN] Would create directory: $_agent_home with mode $_agent_home_mode"
    else
      log_info "Creating directory: $_agent_home"
      mkdir -p "$_agent_home" || {
        log_error "Failed to create directory: $_agent_home"
        FAIL=1
        continue
      }
      chmod "$_agent_home_mode" "$_agent_home" || log_warn "Failed to chmod $_agent_home_mode $_agent_home"
    fi
  fi

  log_hr
  log_info "Deploying skills for: $_agent → $_skills_dst_dir"

  _agent_fail=0

  # Guard: the agent's skills directory must NOT be a directory-wide
  # symlink. If it were, the per-skill logic below would mv files out of
  # the distribution source (since $_skill_dst and $_skill_src would
  # resolve to the same path) and the stale-cleanup pass would delete the
  # source-side SKILL.md files.
  if [ -L "$_skills_dst_dir" ]; then
    log_error "$_skills_dst_dir is a symlink — directory-wide skill symlinks are not supported."
    log_error "Remove it first: rm \"$_skills_dst_dir\""
    log_error "Then re-run deploy.  The agent's own and user-owned skills will be untouched."
    FAIL=1
    continue
  fi

  if [ ! -d "$_skills_dst_dir" ]; then
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
      log_info "[DRY-RUN] Would create directory: $_skills_dst_dir"
    else
      log_info "Creating skills directory: $_skills_dst_dir"
      mkdir -p "$_skills_dst_dir" || {
        log_error "Failed to create skills directory: $_skills_dst_dir"
        FAIL=1
        continue
      }
    fi
  fi

  _skill_count=0
  for _skill_dir in "$SKILLS_SRC_DIR"/*/; do
    [ -d "$_skill_dir" ] || continue
    _skill_name=$(basename "$_skill_dir")
    # No trailing slash, so the symlink target stays clean and consistent
    # with the other links this repo creates (e.g. ~/.claude/CLAUDE.md).
    # Deliberately SKILLS_DEPLOY_DIR, not SKILLS_SRC_DIR — see its comment.
    _skill_src="$SKILLS_DEPLOY_DIR/$_skill_name"
    _skill_dst="$_skills_dst_dir/$_skill_name"

    # Safety: if dst and src resolve to the same path, skip to avoid moving
    # source-side files or creating self-referential symlinks.
    if [ "$_skill_dst" = "$_skill_src" ]; then
      log_warn "Skipping $_skill_name — destination equals source (possible directory-wide symlink?)."
      log_warn "  Remove the symlink at $_skills_dst_dir first, then re-run deploy."
      continue
    fi

    # Already correct symlink?
    if [ -L "$_skill_dst" ] && [ "$(readlink "$_skill_dst")" = "$_skill_src" ]; then
      log_info "Already linked: $_skill_dst → $_skill_src"
      _skill_count=$((_skill_count + 1))
      continue
    fi

    # If an existing file / directory / different symlink is in the way,
    # back it up OUTSIDE the skills directory so it isn't picked up as a
    # duplicate skill. Exception: a symlink left over from a previous deploy
    # (the pre-split claude/skills scheme, the old direct-to-worktree
    # scheme, or a stale current-scheme link) is not user data — replace it
    # without backup, the same treatment symlink_backup gives CLAUDE.md
    # (ADR DOC-2608040229 §4.10). Without this check, every pre-existing
    # repo-owned skill symlink would get "backed up" here as if it were the
    # user's original skill, and a later uninstall would restore that backup
    # as if it were real data.
    if [ -e "$_skill_dst" ] || [ -L "$_skill_dst" ]; then
      if _dotfiles_symlink_is_repo_owned "$_skill_dst" "$(dirname "$SCRIPT_DIR")"; then
        if [ "${DRY_RUN:-0}" -eq 1 ]; then
          log_info "[DRY-RUN] Would replace repo-owned skill symlink (no backup): $_skill_dst"
        else
          log_info "Replacing repo-owned skill symlink (no backup needed): $_skill_dst"
          rm -f "$_skill_dst" || {
            log_error "Failed to remove: $_skill_dst"
            _agent_fail=1
            continue
          }
        fi
      elif [ "${DRY_RUN:-0}" -eq 1 ]; then
        log_info "[DRY-RUN] Would back up existing: $_skill_dst → $_skills_backup_dir/"
      else
        mkdir -p "$_skills_backup_dir" || {
          log_error "Failed to create backup directory: $_skills_backup_dir"
          _agent_fail=1
          continue
        }
        _backup_name="${_skill_name}.$(date +%Y%m%d%H%M%S).$$"
        log_warn "Backing up existing skill: $_skill_dst → $_skills_backup_dir/$_backup_name"
        mv "$_skill_dst" "$_skills_backup_dir/$_backup_name" || {
          log_error "Failed to back up: $_skill_dst"
          _agent_fail=1
          continue
        }
        log_info "  To restore: mv $_skills_backup_dir/$_backup_name $_skill_dst"
      fi
    fi

    if [ "${DRY_RUN:-0}" -eq 1 ]; then
      log_info "[DRY-RUN] Would symlink: $_skill_dst → $_skill_src"
      _skill_count=$((_skill_count + 1))
    else
      ln -fs "$_skill_src" "$_skill_dst" || {
        log_error "Failed to symlink: $_skill_src → $_skill_dst"
        _agent_fail=1
        continue
      }
      log_ok "Linked: $_skill_dst → $_skill_src"
      _skill_count=$((_skill_count + 1))
    fi
  done

  if [ "$_skill_count" -eq 0 ]; then
    log_warn "No skill directories found in $SKILLS_SRC_DIR"
  else
    log_ok "Deployed $_skill_count skill(s) for $_agent"
    _deployed_agents=$((_deployed_agents + 1))
  fi

  # Clean up stale symlinks in this agent's skills directory that point into
  # a distribution source but whose targets no longer exist (renamed /
  # removed). Uses SKILLS_DEPLOY_DIR, not SKILLS_SRC_DIR, for the same
  # reason the symlink target above does: in DRY_RUN mode SKILLS_SRC_DIR is
  # the working tree, so matching against it would miss stale current-scheme
  # links (the ones this deploy actually created) and the plan would
  # silently propose nothing to sweep. The two LEGACY_* prefixes cover the
  # pre-split claude/skills spelling of both schemes, so skills removed or
  # renamed before this machine adopted the split still get swept (ADR
  # DOC-2608272128 §4.3). Only symlinks whose target starts with one of
  # these prefixes are touched, leaving the agent's own bundled skills plus
  # user-owned and Herdr-managed symlinks alone.
  for _dst_link in "$_skills_dst_dir"/*; do
    [ -L "$_dst_link" ] || continue
    _target=$(readlink "$_dst_link")
    case "$_target" in
      "$SKILLS_DEPLOY_DIR"/* | "$SCRIPT_DIR"/* | "$LEGACY_DEPLOY_DIR"/* | "$LEGACY_WORKTREE_DIR"/*)
        if [ ! -d "$_target" ]; then
          if [ "${DRY_RUN:-0}" -eq 1 ]; then
            log_info "[DRY-RUN] Would remove stale skill symlink: $_dst_link → $_target"
          else
            log_warn "Removing stale skill symlink: $_dst_link → $_target"
            rm -f "$_dst_link" || {
              log_error "Failed to remove stale symlink: $_dst_link"
              _agent_fail=1
            }
          fi
        fi
        ;;
    esac
  done

  if [ "$_agent_fail" -ne 0 ]; then
    FAIL=1
  fi
done

if [ "$_deployed_agents" -eq 0 ] && [ "${DRY_RUN:-0}" -eq 0 ]; then
  log_warn "No agent received skills. Install at least one supported agent, or check the paths above."
fi

if [ "$FAIL" -ne 0 ]; then
  log_error "skills deployment completed with errors."
  exit 1
fi

log_ok "skills deployment complete."
