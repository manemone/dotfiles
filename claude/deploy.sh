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

# --- Symlink git-guard.sh (PreToolUse hook) ---
# ~/.claude/hooks/ には dotfiles 由来でないフック（herdr-agent-state.sh）が
# 既に居るため、ディレクトリごとではなくファイル単位で symlink する。
# symlink_backup は親ディレクトリが無ければ作成するため、~/.claude/hooks
# が未作成でも問題ない。
symlink_backup "$DOTFILES_DEPLOY_SRC/claude/hooks/git-guard.sh" "$CLAUDE_DIR/hooks/git-guard.sh" || FAIL=1

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
# deploy.sh merges three inputs into ~/.claude/settings.json: base settings
# → machine overrides (if any) → permissions.allow already present in the
# generated file being replaced. The third input is how allow entries
# Claude Code learns interactively survive the next deploy (design 3,
# DOC-2609121700). Only permissions.allow is carried forward this way —
# ask/deny/hooks/etc. always come from base+machine, so a stray manual `ask`
# entry can never outlive a deploy and calcify (see 背景3-A in the same doc).

SETTINGS_SRC="$CLAUDE_SRC_DIR/settings.json"
MACHINE_SRC="$CLAUDE_SRC_DIR/settings.machine.json"
SETTINGS_DST="$CLAUDE_DIR/settings.json"

# merge_claude_settings <output> <base> <machine-or-empty> <existing-or-empty>
# Writes the merged JSON to <output> and prints the number of
# permissions.allow entries carried over from <existing> to stdout.
# List-valued keys within "permissions" (allow, deny, ask) from <machine>
# are concatenated onto <base>; every other key uses shallow .update()
# semantics (machine wins). <existing>'s permissions.allow is then merged in
# on top of that (deduplicated, order-preserving) — this is the only thing
# read from <existing>.
merge_claude_settings() {
  python3 - "$@" <<'PYEOF'
import json, sys

output_path, base_path, machine_path, existing_path = sys.argv[1:5]

with open(base_path) as f:
    merged = json.load(f)

if machine_path:
    with open(machine_path) as f:
        machine = json.load(f)

    LIST_KEYS = {'allow', 'deny', 'ask'}

    for key in machine:
        if key == 'permissions' and isinstance(merged.get(key), dict) and isinstance(machine[key], dict):
            for subkey in machine[key]:
                if subkey in LIST_KEYS and isinstance(merged[key].get(subkey), list) and isinstance(machine[key][subkey], list):
                    # Concatenate lists (deduplicate preserving order)
                    seen = set(merged[key][subkey])
                    for item in machine[key][subkey]:
                        if item not in seen:
                            merged[key][subkey].append(item)
                            seen.add(item)
                else:
                    merged[key][subkey] = machine[key][subkey]
        elif key in merged and isinstance(merged[key], dict) and isinstance(machine[key], dict):
            merged[key].update(machine[key])
        else:
            merged[key] = machine[key]

preserved = 0
if existing_path:
    # Best-effort: a missing/corrupt/unexpected-shape existing file must
    # never fail the deploy, it just means nothing gets preserved.
    try:
        with open(existing_path) as f:
            existing = json.load(f)
        existing_allow = existing.get('permissions', {}).get('allow')
        if isinstance(existing_allow, list):
            merged.setdefault('permissions', {})
            current_allow = merged['permissions'].setdefault('allow', [])
            seen = set(current_allow)
            for item in existing_allow:
                if isinstance(item, str) and item not in seen:
                    current_allow.append(item)
                    seen.add(item)
                    preserved += 1
    except Exception:
        pass

with open(output_path, 'w') as f:
    json.dump(merged, f, indent=2)
    f.write('\n')

print(preserved)
PYEOF
}

HAVE_PYTHON3=1
command -v python3 >/dev/null 2>&1 || HAVE_PYTHON3=0

if [ -f "$MACHINE_SRC" ] && [ "$HAVE_PYTHON3" -eq 0 ]; then
  log_error "python3 is required to merge settings.machine.json."
  log_error "Install python3, or remove claude/settings.machine.json to deploy base settings only."
  FAIL=1
elif [ "$HAVE_PYTHON3" -eq 1 ]; then
  MACHINE_ARG=""
  [ -f "$MACHINE_SRC" ] && MACHINE_ARG="$MACHINE_SRC"
  if [ -n "$MACHINE_ARG" ] && [ "${DRY_RUN:-0}" -eq 0 ]; then
    log_info "Found settings.machine.json — merging with base settings..."
  fi

  # Guard: ~/.claude/settings.json must NOT be a symlink. deploy.sh always
  # generates a real file. A leftover symlink (old scheme) would otherwise
  # either be silently overwritten below, or misread as "the previously
  # generated file" for allow-preservation purposes — remove it first.
  if [ -L "$SETTINGS_DST" ]; then
    log_warn "settings.json is a symlink — removing to replace with generated file."
    log_warn "  Symlink target was: $(readlink "$SETTINGS_DST")"
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
      log_info "[DRY-RUN] Would remove symlink: $SETTINGS_DST"
    else
      rm -f "$SETTINGS_DST" || {
        log_error "Failed to remove symlink: $SETTINGS_DST"
        FAIL=1
      }
    fi
  fi

  EXISTING_ARG=""
  if [ "$FAIL" -eq 0 ] && [ -f "$SETTINGS_DST" ] && [ ! -L "$SETTINGS_DST" ]; then
    EXISTING_ARG="$SETTINGS_DST"
  fi

  if [ "$FAIL" -eq 0 ]; then
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
      if [ -n "$MACHINE_ARG" ]; then
        log_info "[DRY-RUN] Would merge settings.json + settings.machine.json → $SETTINGS_DST"
      else
        log_info "[DRY-RUN] Would copy settings.json → $SETTINGS_DST"
      fi
      # Read-only preview: writes to a scratch temp file (never $SETTINGS_DST)
      # purely to compute the count, then discards it.
      _dry_tmp="$(mktemp "${TMPDIR:-/tmp}/claude-settings-preview.XXXXXX")" || {
        log_warn "Could not create a scratch file to preview allow preservation (mktemp failed) — skipping the count."
        _dry_tmp=""
      }
      if [ -n "$_dry_tmp" ]; then
        _preserved_count="$(merge_claude_settings "$_dry_tmp" "$SETTINGS_SRC" "$MACHINE_ARG" "$EXISTING_ARG")"
        _preview_rc=$?
        rm -f "$_dry_tmp"
        if [ $_preview_rc -ne 0 ]; then
          log_warn "Could not compute the allow-preservation preview (merge failed) — check settings.machine.json / the existing settings.json are valid JSON."
        else
          case "$_preserved_count" in
            '' | *[!0-9]*) _preserved_count=0 ;;
          esac
          log_info "[DRY-RUN] Would preserve $_preserved_count learned permissions.allow entries from the existing settings.json"
        fi
      fi
    else
      MERGE_TMP="$SETTINGS_DST.tmp.$$"
      _preserved_count="$(merge_claude_settings "$MERGE_TMP" "$SETTINGS_SRC" "$MACHINE_ARG" "$EXISTING_ARG")"
      _merge_rc=$?
      case "$_preserved_count" in
        '' | *[!0-9]*) _preserved_count=0 ;;
      esac

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
              log_ok "Generated settings.json → $SETTINGS_DST"
              if [ "$_preserved_count" -gt 0 ]; then
                log_info "Preserved $_preserved_count learned permissions.allow entries from the previous settings.json"
              fi
            fi
          fi
        fi
      fi
    fi
  fi
else
  # No python3 and no settings.machine.json to force the requirement: fall
  # back to a plain copy. Learned allow entries cannot be preserved on this
  # path (best-effort only — documented in claude/README.md).
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    log_info "[DRY-RUN] Would copy settings.json → $SETTINGS_DST"
    log_info "[DRY-RUN] python3 not found — allow preservation would be skipped"
  else
    if [ -f "$SETTINGS_DST" ] && cmp -s "$SETTINGS_SRC" "$SETTINGS_DST" 2>/dev/null; then
      log_info "settings.json is already up to date (unchanged)."
    else
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
          log_warn "python3 not found — could not preserve its permissions.allow entries."
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
# DOC-2608272128. ~/.claude/skills is therefore written by skills/deploy.sh.
#
# AVAILABLE_TOOLS lists `skills` after `claude` so the tool that owns
# ~/.claude gets to create it first, but that ordering is presentational,
# not load-bearing: skills/deploy.sh creates ~/.claude itself when it is
# missing, using the mode agent_home_mode() returns (the same one this
# script reads above). Do not read the ordering as a guarantee this script
# has already run — `--only skills` and every --dry-run depend on it not
# being one.

if [ "$FAIL" -ne 0 ]; then
  log_error "claude deployment completed with errors."
  exit 1
fi

log_ok "claude deployment complete."
log_info "Tip: Copy claude/settings.machine.json.example → claude/settings.machine.json"
log_info "     and customize it for this machine. It's gitignored — never committed."
