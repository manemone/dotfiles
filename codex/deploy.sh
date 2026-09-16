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

# --- Generate the concatenated AGENTS.md at a fixed path outside any
# generation (design4, plan DOC-2609162320 / ADR DOC-2609162327 §6) ---
#
# Codex has no @include-equivalent that reads IN ADDITION to its own
# AGENTS.md: an AGENTS.override.md, if present, REPLACES the corresponding
# AGENTS.md rather than adding to it (confirmed against OpenAI's own docs
# — see the ADR). So unlike Claude Code (an `@` import, resolved live) and
# OpenCode (an `instructions` path, resolved live), Codex can only get
# machine-local personality personalization (CLAUDE.machine.md) by reading
# a real file whose content already has it baked in. That file
# (dotfiles_codex_agents_md_path(), shared/helpers.sh) lives at a fixed
# path — a sibling of generations/ and current, NOT inside a generation —
# for the same reason CLAUDE.machine.md/settings.machine.json do: it must
# not be tied to any one generation's lifecycle. Regenerating it is cheap
# (generate_codex_agents_md() just re-reads both source files), so this
# runs on every deploy rather than only when something looks stale.
GENERATED_AGENTS_MD="$(dotfiles_codex_agents_md_path)"
BASE_CLAUDE_MD="$DOTFILES_DEPLOY_SRC/claude/CLAUDE.md"
MACHINE_MD_PATH="$(dotfiles_machine_md_path)"

if [ "${DRY_RUN:-0}" -eq 1 ]; then
  log_info "[DRY-RUN] Would generate: $GENERATED_AGENTS_MD (claude/CLAUDE.md + $MACHINE_MD_PATH)"
else
  if generate_codex_agents_md "$BASE_CLAUDE_MD" "$MACHINE_MD_PATH" "$GENERATED_AGENTS_MD"; then
    log_ok "Generated: $GENERATED_AGENTS_MD"
  else
    log_error "Failed to generate: $GENERATED_AGENTS_MD"
    FAIL=1
  fi
fi

# --- Symlink AGENTS.md to the generated fixed-path file ---
# Not claude/CLAUDE.md directly any more (that was this deploy script's
# behavior before design4): AGENTS.md now needs the personalization baked
# in, which only the generated file above has.
symlink_backup "$GENERATED_AGENTS_MD" "$CODEX_HOME_DIR/AGENTS.md" || FAIL=1

if [ "$FAIL" -ne 0 ]; then
  log_error "codex deployment completed with errors."
  exit 1
fi

log_ok "codex deployment complete."
log_info "Tip: to change this machine's personality personalization for Codex, run 'persona'"
log_info "     (edits CLAUDE.machine.md, then regenerates AGENTS.md) or 'persona --regen'"
log_info "     (regenerates only). No redeploy needed either way."
