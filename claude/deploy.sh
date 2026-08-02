#!/bin/sh

SCRIPT_DIR=$(
  cd "$(dirname "$0")" || exit 1
  pwd
)
# shellcheck source=SCRIPTDIR/../shared/helpers.sh
. "$SCRIPT_DIR/../shared/helpers.sh"

log_hr
log_info "Deploying: claude (Claude Code config)"

FAIL=0

# --- Ensure ~/.claude exists with correct permissions ---
CLAUDE_DIR="$HOME/.claude"

if [ ! -d "$CLAUDE_DIR" ]; then
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    log_info "[DRY-RUN] Would create directory: $CLAUDE_DIR with mode 700"
  else
    log_info "Creating directory: $CLAUDE_DIR"
    mkdir -p "$CLAUDE_DIR" || {
      log_error "Failed to create directory: $CLAUDE_DIR"
      exit 1
    }
    log_ok "Created: $CLAUDE_DIR"
  fi
fi

# Enforce 700 permissions (~/.claude may contain credentials)
if [ "${DRY_RUN:-0}" -eq 1 ]; then
  log_info "[DRY-RUN] Would chmod 700 $CLAUDE_DIR"
else
  chmod 700 "$CLAUDE_DIR" || log_warn "Failed to chmod 700 $CLAUDE_DIR"
fi

# --- Symlink CLAUDE.md ---
symlink_backup "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" || FAIL=1

# --- Generate settings.json (NOT a symlink) ---
# Claude Code does NOT read ~/.claude/settings.local.json at the user level
# (only project-level .claude/settings.local.json is supported).
# Instead, machine-specific overrides go in claude/settings.machine.json
# (not tracked in git — copy from settings.machine.json.example).
# deploy.sh merges base + machine overrides into ~/.claude/settings.json.

SETTINGS_SRC="$SCRIPT_DIR/settings.json"
MACHINE_SRC="$SCRIPT_DIR/settings.machine.json"
SETTINGS_DST="$CLAUDE_DIR/settings.json"

if [ -f "$MACHINE_SRC" ]; then
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    log_info "[DRY-RUN] Would merge settings.json + settings.machine.json → $SETTINGS_DST"
  else
    log_info "Found settings.machine.json — merging with base settings..."

    if ! command -v python3 >/dev/null 2>&1; then
      log_error "python3 is required to merge settings.machine.json."
      log_error "Install python3, or remove claude/settings.machine.json to deploy base settings only."
      FAIL=1
    else
      MERGE_TMP="$SETTINGS_DST.tmp.$$"

      # Merge: base settings + machine overrides.
      # List-valued keys within "permissions" (allow, deny, ask) are concatenated;
      # all other keys use shallow .update() semantics (machine wins).
      python3 - "$SETTINGS_SRC" "$MACHINE_SRC" "$MERGE_TMP" <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    base = json.load(f)
with open(sys.argv[2]) as f:
    machine = json.load(f)

LIST_KEYS = {'allow', 'deny', 'ask'}

for key in machine:
    if key == 'permissions' and isinstance(base.get(key), dict) and isinstance(machine[key], dict):
        for subkey in machine[key]:
            if subkey in LIST_KEYS and isinstance(base[key].get(subkey), list) and isinstance(machine[key][subkey], list):
                # Concatenate lists (deduplicate preserving order)
                seen = set(base[key][subkey])
                for item in machine[key][subkey]:
                    if item not in seen:
                        base[key][subkey].append(item)
                        seen.add(item)
            else:
                base[key][subkey] = machine[key][subkey]
    elif key in base and isinstance(base[key], dict) and isinstance(machine[key], dict):
        base[key].update(machine[key])
    else:
        base[key] = machine[key]

with open(sys.argv[3], 'w') as f:
    json.dump(base, f, indent=2)
    f.write('\n')
PYEOF
      _merge_rc=$?

      if [ $_merge_rc -ne 0 ]; then
        log_error "Failed to merge settings. Check settings.machine.json is valid JSON."
        rm -f "$MERGE_TMP"
        FAIL=1
      else
        # Compare with existing file — skip if identical
        if [ -f "$SETTINGS_DST" ] && cmp -s "$MERGE_TMP" "$SETTINGS_DST" 2>/dev/null; then
          log_info "settings.json is already up to date (unchanged)."
          rm -f "$MERGE_TMP"
        else
          # Back up existing if present
          if [ -f "$SETTINGS_DST" ]; then
            _backup_path="$(backup_dst "$SETTINGS_DST")"
            log_warn "Backing up existing settings.json → $_backup_path"
            mv "$SETTINGS_DST" "$_backup_path" || {
              log_error "Failed to back up existing settings.json"
              rm -f "$MERGE_TMP"
              FAIL=1
            }
          fi
          if [ "$FAIL" -eq 0 ]; then
            mv "$MERGE_TMP" "$SETTINGS_DST" || {
              log_error "Failed to write settings.json"
              FAIL=1
            }
            if [ "$FAIL" -eq 0 ]; then
              log_ok "Generated merged settings.json → $SETTINGS_DST"
            fi
          fi
        fi
      fi
    fi
  fi
else
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    log_info "[DRY-RUN] Would copy settings.json → $SETTINGS_DST"
  else
    # Compare with existing — skip if identical
    if [ -f "$SETTINGS_DST" ] && cmp -s "$SETTINGS_SRC" "$SETTINGS_DST" 2>/dev/null; then
      log_info "settings.json is already up to date (unchanged)."
    else
      # Guard: ~/.claude/settings.json must NOT be a symlink.
      # deploy.sh generates a real file (either by copying base settings or
      # merging with settings.machine.json).  A symlink would be overwritten
      # silently by cp below — warn and remove it first.
      if [ -L "$SETTINGS_DST" ]; then
        log_warn "settings.json is a symlink — removing to replace with generated file."
        log_warn "  Symlink target was: $(readlink "$SETTINGS_DST")"
        rm -f "$SETTINGS_DST" || {
          log_error "Failed to remove symlink: $SETTINGS_DST"
          FAIL=1
        }
      fi

      # Back up existing if it differs from base
      if [ -f "$SETTINGS_DST" ]; then
        if ! cmp -s "$SETTINGS_SRC" "$SETTINGS_DST" 2>/dev/null; then
          _backup_path="$(backup_dst "$SETTINGS_DST")"
          log_warn "Existing settings.json has local modifications — backing up → $_backup_path"
          mv "$SETTINGS_DST" "$_backup_path" || {
            log_error "Failed to back up existing settings.json"
            FAIL=1
          }
          log_warn "To preserve custom settings across deploys, create claude/settings.machine.json"
          log_warn "from claude/settings.machine.json.example and add your overrides there."
        fi
      fi
      if [ "$FAIL" -eq 0 ]; then
        cp "$SETTINGS_SRC" "$SETTINGS_DST" || {
          log_error "Failed to copy settings.json"
          FAIL=1
        }
        if [ "$FAIL" -eq 0 ]; then
          log_ok "Copied settings.json → $SETTINGS_DST"
        fi
      fi
    fi
  fi
fi

# --- Deploy skills (individual symlinks per skill) ---
# Directory-wide symlink (~/.claude/skills → repo/claude/skills) is forbidden
# because it would wipe out Herdr-managed and user-owned skills.
# Instead, each skill directory is symlinked individually so they coexist.
#
# Uses an independent _skills_fail flag so that a prior failure in CLAUDE.md
# or settings.json does not silently skip skill deployment.
SKILLS_SRC_DIR="$SCRIPT_DIR/skills"
SKILLS_DST_DIR="$CLAUDE_DIR/skills"
SKILLS_BACKUP_DIR="$CLAUDE_DIR/skills-backup"
_skills_fail=0

# Guard: ~/.claude/skills must NOT be a directory-wide symlink.
# If it is, the per-skill symlink logic below would mv files out of the
# repo (since $_skill_dst and $_skill_src resolve to the same path) and
# the stale-cleanup pass would delete the repo-side SKILL.md files.
if [ -L "$SKILLS_DST_DIR" ]; then
  log_error "$SKILLS_DST_DIR is a symlink — directory-wide skill symlinks are not supported."
  log_error "Remove it first: rm \"$SKILLS_DST_DIR\""
  log_error "Then re-run deploy.  Herdr-managed and user-owned skills will be untouched."
  _skills_fail=1
fi

if [ -d "$SKILLS_SRC_DIR" ]; then
  log_hr
  log_info "Deploying: claude/skills"

  if [ ! -d "$SKILLS_DST_DIR" ]; then
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
      log_info "[DRY-RUN] Would create directory: $SKILLS_DST_DIR"
    else
      log_info "Creating skills directory: $SKILLS_DST_DIR"
      mkdir -p "$SKILLS_DST_DIR" || {
        log_error "Failed to create skills directory: $SKILLS_DST_DIR"
        _skills_fail=1
      }
    fi
  fi

  if [ "$_skills_fail" -eq 0 ]; then
    _skill_count=0
    for _skill_dir in "$SKILLS_SRC_DIR"/*/; do
      [ -d "$_skill_dir" ] || continue
      _skill_name=$(basename "$_skill_dir")
      # Use $SKILLS_SRC_DIR/$_skill_name (no trailing slash) so the symlink
      # target is clean and consistent with other links (e.g. CLAUDE.md).
      _skill_src="$SKILLS_SRC_DIR/$_skill_name"
      _skill_dst="$SKILLS_DST_DIR/$_skill_name"

      # Safety: if dst and src resolve to the same path, skip to avoid
      # moving repo-side files or creating self-referential symlinks.
      if [ "$_skill_dst" = "$_skill_src" ]; then
        log_warn "Skipping $_skill_name — destination equals source (possible directory-wide symlink?)."
        log_warn "  Remove the symlink at $SKILLS_DST_DIR first, then re-run deploy."
        continue
      fi

      # Already correct symlink?
      if [ -L "$_skill_dst" ] && [ "$(readlink "$_skill_dst")" = "$_skill_src" ]; then
        log_info "Already linked: $_skill_dst → $_skill_src"
        _skill_count=$((_skill_count + 1))
        continue
      fi

      # If an existing file / directory / different symlink is in the way,
      # back it up OUTSIDE skills/ so it isn't picked up as a duplicate skill.
      if [ -e "$_skill_dst" ] || [ -L "$_skill_dst" ]; then
        if [ "${DRY_RUN:-0}" -eq 1 ]; then
          log_info "[DRY-RUN] Would back up existing: $_skill_dst → $SKILLS_BACKUP_DIR/"
        else
          mkdir -p "$SKILLS_BACKUP_DIR" || {
            log_error "Failed to create backup directory: $SKILLS_BACKUP_DIR"
            _skills_fail=1
            continue
          }
          _backup_name="${_skill_name}.$(date +%Y%m%d%H%M%S).$$"
          log_warn "Backing up existing skill: $_skill_dst → $SKILLS_BACKUP_DIR/$_backup_name"
          mv "$_skill_dst" "$SKILLS_BACKUP_DIR/$_backup_name" || {
            log_error "Failed to back up: $_skill_dst"
            _skills_fail=1
            continue
          }
          log_info "  To restore: mv $SKILLS_BACKUP_DIR/$_backup_name $_skill_dst"
        fi
      fi

      # Create symlink
      if [ "${DRY_RUN:-0}" -eq 1 ]; then
        log_info "[DRY-RUN] Would symlink: $_skill_dst → $_skill_src"
        _skill_count=$((_skill_count + 1))
      else
        ln -fs "$_skill_src" "$_skill_dst" || {
          log_error "Failed to symlink: $_skill_src → $_skill_dst"
          _skills_fail=1
          continue
        }
        log_ok "Linked: $_skill_dst → $_skill_src"
        _skill_count=$((_skill_count + 1))
      fi
    done

    if [ "$_skill_count" -eq 0 ]; then
      log_warn "No skill directories found in $SKILLS_SRC_DIR"
    else
      log_ok "Deployed $_skill_count skill(s)"
    fi

    # Clean up stale symlinks inside ~/.claude/skills/ that point into
    # SKILLS_SRC_DIR but whose targets no longer exist (renamed / removed).
    # Only touches symlinks whose target starts with SKILLS_SRC_DIR, leaving
    # user-owned and Herdr-managed symlinks alone.
    for _dst_link in "$SKILLS_DST_DIR"/*; do
      [ -L "$_dst_link" ] || continue
      _target=$(readlink "$_dst_link")
      case "$_target" in
        "$SKILLS_SRC_DIR"/*)
          if [ ! -d "$_target" ]; then
            if [ "${DRY_RUN:-0}" -eq 1 ]; then
              log_info "[DRY-RUN] Would remove stale skill symlink: $_dst_link → $_target"
            else
              log_warn "Removing stale skill symlink: $_dst_link → $_target"
              rm -f "$_dst_link" || {
                log_error "Failed to remove stale symlink: $_dst_link"
                _skills_fail=1
              }
            fi
          fi
          ;;
      esac
    done
  fi
else
  log_info "No skills directory — skipping skill deployment."
fi

# Merge skills failure into main FAIL flag (do NOT exit early — settings.json
# may have succeeded even if skills had an issue, and vice versa).
if [ "$_skills_fail" -ne 0 ]; then
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  log_error "claude deployment completed with errors."
  exit 1
fi

log_ok "claude deployment complete."
log_info "Tip: Copy claude/settings.machine.json.example → claude/settings.machine.json"
log_info "     and customize it for this machine. It's gitignored — never committed."
