#!/bin/sh

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
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
      # Backup existing settings.json if it is a real file (not a symlink)
      # and differs from what we're about to generate.
      if [ -f "$SETTINGS_DST" ] && [ ! -L "$SETTINGS_DST" ]; then
        _backup_path="$(_backup_dst "$SETTINGS_DST")"
        log_warn "Backing up existing settings.json → $_backup_path"
        cp "$SETTINGS_DST" "$_backup_path" || {
          log_error "Failed to back up existing settings.json"
          FAIL=1
        }
      fi

      # Merge: base settings + machine overrides (top-level shallow merge)
      python3 -c "
import json, sys

with open('$SETTINGS_SRC') as f:
    base = json.load(f)
with open('$MACHINE_SRC') as f:
    machine = json.load(f)

# Shallow merge: machine top-level keys override base
for key in machine:
    if key in base and isinstance(base[key], dict) and isinstance(machine[key], dict):
        base[key].update(machine[key])
    else:
        base[key] = machine[key]

with open('$SETTINGS_DST', 'w') as f:
    json.dump(base, f, indent=2)
    f.write('\n')
" || {
        log_error "Failed to merge settings. Check settings.machine.json is valid JSON."
        FAIL=1
      }
      if [ "$FAIL" -eq 0 ]; then
        log_ok "Generated merged settings.json → $SETTINGS_DST"
      fi
    fi
  fi
else
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    log_info "[DRY-RUN] Would copy settings.json → $SETTINGS_DST"
  else
    # Warn if existing settings.json has local modifications
    if [ -f "$SETTINGS_DST" ] && [ ! -L "$SETTINGS_DST" ]; then
      if ! cmp -s "$SETTINGS_SRC" "$SETTINGS_DST" 2>/dev/null; then
        _backup_path="$(_backup_dst "$SETTINGS_DST")"
        log_warn "Existing settings.json has local modifications."
        log_warn "Backing up → $_backup_path"
        cp "$SETTINGS_DST" "$_backup_path" || {
          log_error "Failed to back up existing settings.json"
          FAIL=1
        }
        log_warn "To preserve custom settings, create claude/settings.machine.json"
        log_warn "from claude/settings.machine.json.example before next deploy."
      fi
    fi
    cp "$SETTINGS_SRC" "$SETTINGS_DST" || {
      log_error "Failed to copy settings.json"
      FAIL=1
    }
    log_ok "Copied settings.json → $SETTINGS_DST"
  fi
fi

if [ "$FAIL" -ne 0 ]; then
  log_error "claude deployment completed with errors."
  exit 1
fi

log_ok "claude deployment complete."
log_info "Tip: Copy claude/settings.machine.json.example → claude/settings.machine.json"
log_info "     and customize it for this machine. It's gitignored — never committed."
