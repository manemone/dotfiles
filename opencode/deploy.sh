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

# --- Warn if opencode.jsonc coexists (ADR DOC-2609162327 §5.3) ---
# OpenCode's loadGlobal() merges config.json -> opencode.json -> opencode.jsonc
# with mergeDeep (remeda), last-loaded wins per key and arrays are NOT
# concatenated. If opencode.jsonc has its own `instructions` array, it
# silently replaces the `instructions` this symlink just deployed and
# ~/.claude/CLAUDE.machine.md stops reaching OpenCode — no error, no log
# from OpenCode itself. loadGlobal() also auto-creates opencode.jsonc on an
# agent's very first run when none of the three candidate files exist yet,
# so this is a normal (not just hypothetical) state on any machine that has
# used OpenCode before deploying this. Detecting the *content* of
# opencode.jsonc (does it actually declare `instructions`?) would require a
# JSONC parser in POSIX sh; warning on mere coexistence is simpler and
# matches what plan/ADR §5.3 documents as the mitigation.
if [ -f "$OPENCODE_HOME_DIR/opencode.jsonc" ]; then
  log_warn "opencode.jsonc also exists at $OPENCODE_HOME_DIR/opencode.jsonc."
  log_warn "OpenCode merges opencode.json -> opencode.jsonc (jsonc wins per key, arrays are replaced, not concatenated)."
  log_warn "If opencode.jsonc has its own 'instructions', add ~/.claude/CLAUDE.machine.md there too — see opencode/README.md §4."
fi

if [ "$FAIL" -ne 0 ]; then
  log_error "opencode deployment completed with errors."
  exit 1
fi

log_ok "opencode deployment complete."
