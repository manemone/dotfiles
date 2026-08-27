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
log_info "Deploying: claude (Claude Code config)"

FAIL=0

# --- Ensure ~/.claude exists with correct permissions ---
CLAUDE_DIR="$HOME/.claude"
# The mode comes from shared/helpers.sh rather than a literal here: skills/
# creates this same directory when it is missing (see agent_home_mode), and
# 0700 — ~/.claude may contain credentials — must not drift between the two.
CLAUDE_DIR_MODE="$(agent_home_mode claude)"

if [ ! -d "$CLAUDE_DIR" ]; then
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    log_info "[DRY-RUN] Would create directory: $CLAUDE_DIR with mode $CLAUDE_DIR_MODE"
  else
    log_info "Creating directory: $CLAUDE_DIR"
    mkdir -p "$CLAUDE_DIR" || {
      log_error "Failed to create directory: $CLAUDE_DIR"
      exit 1
    }
    log_ok "Created: $CLAUDE_DIR"
  fi
fi

# Enforce the mode on every run (~/.claude may contain credentials)
if [ "${DRY_RUN:-0}" -eq 1 ]; then
  log_info "[DRY-RUN] Would chmod $CLAUDE_DIR_MODE $CLAUDE_DIR"
else
  chmod "$CLAUDE_DIR_MODE" "$CLAUDE_DIR" || log_warn "Failed to chmod $CLAUDE_DIR_MODE $CLAUDE_DIR"
fi

# --- Symlink CLAUDE.md ---
symlink_backup "$DOTFILES_DEPLOY_SRC/claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" || FAIL=1

# --- Resolve where to read claude/'s own contents from for THIS run ---
# symlink_backup (used for CLAUDE.md above) always links through
# DOTFILES_DEPLOY_SRC regardless of DRY_RUN — its DRY-RUN branch only prints
# a planned `ln -fs`, so the source never needs to exist yet. But the code
# below branches on "-f $MACHINE_SRC" to decide what to do, and in DRY_RUN
# mode DOTFILES_DEPLOY_SRC/claude may not exist yet (current not switched,
# or create_generation's own DRY-RUN branch never actually copies anything)
# — so that existence check would silently see "nothing to merge" even when
# the real run will merge.
# A generation is a cp -a snapshot of the working tree (see
# create_generation), so the working tree is what the plan should describe.
if [ "${DRY_RUN:-0}" -eq 1 ]; then
  CLAUDE_SRC_DIR="$SCRIPT_DIR"
else
  CLAUDE_SRC_DIR="$DOTFILES_DEPLOY_SRC/claude"
fi

# --- Generate settings.json (NOT a symlink) ---
# Claude Code does NOT read ~/.claude/settings.local.json at the user level
# (only project-level .claude/settings.local.json is supported).
# Instead, machine-specific overrides go in claude/settings.machine.json
# (not tracked in git — copy from settings.machine.json.example).
# deploy.sh merges base + machine overrides into ~/.claude/settings.json.

SETTINGS_SRC="$CLAUDE_SRC_DIR/settings.json"
MACHINE_SRC="$CLAUDE_SRC_DIR/settings.machine.json"
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

# --- Skills ---
# Skills are NOT deployed here. They moved to the top-level skills/ tool,
# which distributes the same skill directories to every supported agent
# (Claude Code, Codex, OpenCode) rather than to ~/.claude alone — see ADR
# DOC-2608272128. ~/.claude/skills is therefore written by skills/deploy.sh,
# and AVAILABLE_TOOLS orders `skills` after `claude` so that this script has
# already created ~/.claude by the time it runs.

if [ "$FAIL" -ne 0 ]; then
  log_error "claude deployment completed with errors."
  exit 1
fi

log_ok "claude deployment complete."
log_info "Tip: Copy claude/settings.machine.json.example → claude/settings.machine.json"
log_info "     and customize it for this machine. It's gitignored — never committed."
