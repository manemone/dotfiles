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
log_info "Deploying: opencode (OpenCode global instructions)"

FAIL=0

# --- Only deploy if OpenCode is actually installed on this machine ---
# See codex/deploy.sh for the full reasoning — same ADR DOC-2608272128 §2.3
# judgment call (agent_home_mode() returns empty for opencode), reused via
# skill_agent_home() rather than reading $XDG_CONFIG_HOME directly.
OPENCODE_HOME_DIR="$(skill_agent_home opencode)"

if [ ! -d "$OPENCODE_HOME_DIR" ]; then
  log_info "Skipping opencode — not installed on this machine ($OPENCODE_HOME_DIR does not exist)."
  log_ok "opencode deployment complete (nothing to do)."
  exit 0
fi

# --- Symlink AGENTS.md to the same source claude/CLAUDE.md uses ---
# OpenCode reads ${XDG_CONFIG_HOME:-$HOME/.config}/opencode/AGENTS.md as its
# own global instructions, falling back to ~/.claude/CLAUDE.md only when
# that file is absent (https://opencode.ai/docs/rules/). Deploying this
# symlink means OpenCode always has its own copy rather than depending on
# that fallback. See codex/deploy.sh and ADR DOC-2609072334 for why this
# points at claude/CLAUDE.md instead of a content file of its own.
symlink_backup "$DOTFILES_DEPLOY_SRC/claude/CLAUDE.md" "$OPENCODE_HOME_DIR/AGENTS.md" || FAIL=1

# --- Steer OpenCode's own settings-UI writes away from the opencode.json
# symlink (ADR DOC-2609162327 §5.3.1) ---
# OpenCode's own Config.updateGlobal() (desktop/web settings UI: shell
# choice, disabled_providers, custom-provider baseURL/headers — which can
# include an auth token) writes to whichever of opencode.jsonc / opencode.json
# / config.json globalConfigFile() finds first, in that order. Whether
# updateGlobal() ends up targeting OUR opencode.json symlink below depends
# only on whether opencode.jsonc exists — it is first in that order, so its
# mere presence always wins the write-target race regardless of what else
# exists. Gating this on "none of the three exist" (an earlier revision of
# this file did) is therefore both too narrow and wrong: a machine with a
# pre-existing real opencode.json (about to be moved to .backup by
# symlink_backup below, leaving only our symlink as a candidate) or with
# only a config.json (legacy TOML-migration output; opencode.json — our
# symlink — still sorts before it) would both still end up with
# updateGlobal() writing through the symlink into the running *generation*
# — the same writeback pattern as nvim/lazy-lock.json, EXCEPT what's
# written here can be machine-local settings or secrets, not something that
# belongs in the tracked, all-machines-shared opencode/opencode.json.
# Treating it as a state file (an earlier revision of this file did — see
# git history) would make `--adopt-state` copy that machine-local/secret
# content into the tracked file and, from there, out to every other
# machine. So instead of capturing the writeback, we prevent it
# unconditionally: create a real, machine-local opencode.jsonc *before*
# symlinking opencode.json below, whenever opencode.jsonc itself doesn't
# already exist — independent of opencode.json / config.json. Content
# matches what loadGlobal() itself would generate on a machine with no
# candidate file at all (schema only, no `instructions` key — mergeDeep
# only overwrites keys jsonc actually has, so it never overwrites keys from
# an existing opencode.json or config.json, and opencode.json's
# `instructions` below still survives the merge untouched). Never overwrite
# an existing opencode.jsonc — that would clobber genuine machine settings
# or fight with content someone put there on purpose (see the
# opencode.jsonc warning further below).
if [ ! -e "$OPENCODE_HOME_DIR/opencode.jsonc" ]; then
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    log_info "[DRY-RUN] Would create $OPENCODE_HOME_DIR/opencode.jsonc (machine-local; steers OpenCode's own settings writes away from the opencode.json symlink below)"
  else
    # Quoted heredoc delimiter: the $ in $schema is a literal JSON key, not
    # a shell expansion (avoids shellcheck SC2016, which single-quoting the
    # same literal in a printf argument would trigger instead).
    if cat >"$OPENCODE_HOME_DIR/opencode.jsonc" <<'JSONC_EOF'; then
{"$schema": "https://opencode.ai/config.json"}
JSONC_EOF
      :
    else
      log_error "Failed to create $OPENCODE_HOME_DIR/opencode.jsonc"
      FAIL=1
    fi
    [ "$FAIL" -eq 0 ] && log_ok "Created $OPENCODE_HOME_DIR/opencode.jsonc (machine-local; not tracked by this repo)"
  fi
fi

# --- Symlink opencode.json (design 3, plan DOC-2609162320 / ADR
# DOC-2609162327 §5) ---
# Unlike AGENTS.md above (which carries the base personal-instructions text,
# same as Claude Code/Codex), opencode.json is a config file specific to
# this tool: its `instructions` array is OpenCode's own mechanism for
# layering in extra files, and this repo's copy points a single entry at
# ~/.claude/CLAUDE.machine.md — the fixed-path machine-local personality
# personalization entity claude/deploy.sh already symlinks there
# (dotfiles_machine_md_path, shared/helpers.sh). That path is deliberately
# NOT under this agent's own (XDG_CONFIG_HOME-relative) home: OpenCode
# expands a leading "~/" in an instructions entry against $HOME only, never
# against XDG_CONFIG_HOME, so a literal path assuming the default
# ~/.config/opencode location would silently stop resolving on any machine
# with a customized XDG_CONFIG_HOME. ~/.claude is not XDG-configurable
# (skill_agent_home claude is always $HOME/.claude), so this reference stays
# correct regardless. The trade-off: on a machine that deploys `--only
# opencode` without ever deploying `claude`, ~/.claude/CLAUDE.machine.md
# doesn't exist yet, and OpenCode's instructions resolution just finds no
# match for that entry (see instruction.ts's systemPaths(), which silently
# drops entries whose glob doesn't match) — the same graceful
# no-personalization default as an empty CLAUDE.machine.md, not an error.
symlink_backup "$DOTFILES_DEPLOY_SRC/opencode/opencode.json" "$OPENCODE_HOME_DIR/opencode.json" || FAIL=1

# --- Warn if an existing opencode.jsonc declares its own `instructions`
# (ADR DOC-2609162327 §5.3.2) ---
# OpenCode's loadGlobal() merges config.json -> opencode.json -> opencode.jsonc
# with mergeDeep (remeda), last-loaded wins per key and arrays are NOT
# concatenated. If opencode.jsonc has its own `instructions` array, it
# silently replaces the `instructions` this symlink just deployed and
# ~/.claude/CLAUDE.machine.md stops reaching OpenCode — no error, no log
# from OpenCode itself. Only warn when opencode.jsonc both exists AND
# actually declares "instructions": the block above now creates a
# schema-only opencode.jsonc whenever one doesn't already exist, and that
# always-exists-afterward file must not turn this into a warning on every
# single deploy. A plain grep (not a JSONC parser) is
# enough — a false-positive match inside a comment or string only causes an
# extra (harmless) warning, never a missed one.
if [ -f "$OPENCODE_HOME_DIR/opencode.jsonc" ] && grep -q '"instructions"' "$OPENCODE_HOME_DIR/opencode.jsonc" 2>/dev/null; then
  log_warn "opencode.jsonc declares its own 'instructions' at $OPENCODE_HOME_DIR/opencode.jsonc."
  log_warn "OpenCode merges opencode.json -> opencode.jsonc (jsonc wins per key, arrays are replaced, not concatenated)."
  log_warn "So ~/.claude/CLAUDE.machine.md (added via opencode.json) is being silently dropped."
  log_warn "Add ~/.claude/CLAUDE.machine.md to opencode.jsonc's own 'instructions' too — see opencode/README.md §4."
fi

if [ "$FAIL" -ne 0 ]; then
  log_error "opencode deployment completed with errors."
  exit 1
fi

log_ok "opencode deployment complete."
