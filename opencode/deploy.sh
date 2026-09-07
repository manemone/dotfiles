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

if [ "$FAIL" -ne 0 ]; then
  log_error "opencode deployment completed with errors."
  exit 1
fi

log_ok "opencode deployment complete."
