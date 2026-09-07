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
log_info "Deploying: codex (Codex CLI global instructions)"

FAIL=0

# --- Only deploy if Codex is actually installed on this machine ---
# Codex's config directory (~/.codex by default) existing at all is the
# only signal we have that this machine uses Codex — a directory this repo
# does not own the way it owns ~/.claude (see claude/deploy.sh). Creating
# one just to drop a symlink in it would conjure up a tree for a tool that
# isn't installed, the same reasoning skills/deploy.sh already applies per
# agent (ADR DOC-2608272128 §2.3) via agent_home_mode() returning empty for
# codex. Reusing skill_agent_home() here (rather than reading $CODEX_HOME
# directly) keeps the env var resolution in one place.
CODEX_HOME_DIR="$(skill_agent_home codex)"

if [ ! -d "$CODEX_HOME_DIR" ]; then
  log_info "Skipping codex — not installed on this machine ($CODEX_HOME_DIR does not exist)."
  log_ok "codex deployment complete (nothing to do)."
  exit 0
fi

# --- Symlink AGENTS.md to the same source claude/CLAUDE.md uses ---
# There is deliberately no codex/AGENTS.md content file in this directory.
# The personal instructions in claude/CLAUDE.md (tone settings, umbrella-
# handoff trigger condition) are agent-agnostic text — Codex's own
# ~/.codex/AGENTS.md was already, by hand, an exact copy of that same
# content before this tool existed (ADR DOC-2609072334). Symlinking both
# ~/.claude/CLAUDE.md and ~/.codex/AGENTS.md to one repo file is what keeps
# that duplication from drifting, without moving claude/CLAUDE.md out of
# claude/ (see the ADR's rejected-alternatives section for why not).
symlink_backup "$DOTFILES_DEPLOY_SRC/claude/CLAUDE.md" "$CODEX_HOME_DIR/AGENTS.md" || FAIL=1

if [ "$FAIL" -ne 0 ]; then
  log_error "codex deployment completed with errors."
  exit 1
fi

log_ok "codex deployment complete."
