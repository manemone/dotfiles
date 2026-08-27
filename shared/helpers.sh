#!/bin/sh
#
# shared/helpers.sh — Unified helpers sourced by every deploy script.
# Keep functions self-contained and side-effect free where possible.
# This file uses POSIX sh (no bashisms).

# ── Linked-worktree guard ─────────────────────────────────────────────
#
# This file's source-time guard (bottom of this file) fires whenever a
# script sources it from inside a linked git worktree (created by
# `git worktree add`, e.g. by `ocw`) — that covers deploy-all.sh and every
# standalone `<tool>/deploy.sh`. uninstall.sh pre-suppresses it (it never
# deploys, so the notice would never be accurate there — see uninstall.sh).
#
# The wording below must stay true regardless of which of those two entry
# points fired it: deploy-all.sh may be building a brand-new generation
# right now, while a standalone `<tool>/deploy.sh` never creates one (it
# only symlinks against whatever generation `current` already points at —
# see AGENTS.md's "単体 <tool>/deploy.sh 実行時の規約"). What both share,
# and what the wording says, is only that $HOME resolves through `current`
# rather than through this worktree — not which of them is creating what.
# The one exception is dev mode (`--dev`), which points `current` directly
# at a worktree; cmd_dev in deploy-all.sh prints its own, more specific
# warning for that case.
#
# Set DOTFILES_QUIET_WORKTREE_WARNING=1 to silence.

# is_linked_worktree <dir>
# Returns 0 if dir is inside a *linked* git worktree (not the main one).
# Returns 1 if it is the main worktree, not a repo, or git is unavailable.
is_linked_worktree() {
  _ilw_dir="${1:-.}"

  command -v git >/dev/null 2>&1 || return 1

  _ilw_gitdir=$(git -C "$_ilw_dir" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  _ilw_common=$(git -C "$_ilw_dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1

  [ "$_ilw_gitdir" != "$_ilw_common" ]
}

# warn_if_linked_worktree <dir>
# Print a one-time warning when deploying from a linked worktree.
# Warns at most once per process tree (the flag is exported so that
# deploy-all.sh and the per-tool deploy scripts do not repeat it).
warn_if_linked_worktree() {
  [ -z "${DOTFILES_WORKTREE_WARNED:-}" ] || return 0
  [ -z "${DOTFILES_QUIET_WORKTREE_WARNING:-}" ] || return 0

  is_linked_worktree "${1:-.}" || return 0

  DOTFILES_WORKTREE_WARNED=1
  export DOTFILES_WORKTREE_WARNED

  # show-toplevel resolves to the worktree's own root, unlike plain `cd
  # "${1:-.}" && pwd`, which is whatever subdirectory dirname -- "$0"
  # happened to pass in (e.g. a per-tool deploy.sh passes its own tool
  # directory, not the checkout root).
  _wilw_root=$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null)
  [ -n "$_wilw_root" ] || _wilw_root=$(cd "${1:-.}" && pwd)

  log_warn "Deploying from a linked git worktree:"
  log_warn "  $_wilw_root"
  log_warn "\$HOME symlinks resolve through the distributed generation (via"
  log_warn "\`current\`), not through this worktree directly, so removing the"
  log_warn "worktree afterward will NOT break them. (The exception is dev"
  log_warn "mode: '--dev' points \$HOME directly at whichever tree is"
  log_warn "current, and prints its own warning for that.)"

  # The main worktree is the parent of the common git dir. Named here for
  # reference only (e.g. to know where to deploy from once this worktree is
  # gone), not as a required follow-up step.
  _wilw_main=$(
    git -C "${1:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null
  )
  if [ -n "$_wilw_main" ]; then
    _wilw_main=$(cd "$_wilw_main/.." 2>/dev/null && pwd)
  fi
  if [ -n "$_wilw_main" ]; then
    log_warn "Main worktree: $_wilw_main"
  fi

  log_warn "Silence this with DOTFILES_QUIET_WORKTREE_WARNING=1."
}

# ── Platform detection ────────────────────────────────────────────────

case "$(uname -s)" in
  Darwin)
    CURRENT_PLATFORM='macos'
    ;;
  Linux*)
    CURRENT_PLATFORM='linux'
    ;;
  MINGW32_NT*)
    CURRENT_PLATFORM='cygwin'
    ;;
  *)
    CURRENT_PLATFORM='unknown'
    ;;
esac

is_macos() { [ "$CURRENT_PLATFORM" = "macos" ]; }
is_linux() { [ "$CURRENT_PLATFORM" = "linux" ]; }

# is_wsl
# Returns 0 if running under Windows Subsystem for Linux, 1 otherwise.
is_wsl() {
  [ -n "${WSL_DISTRO_NAME:-}" ] && return 0
  grep -qi microsoft /proc/version 2>/dev/null
}

# Canonical list of available tools.  deploy-all.sh and uninstall.sh
# both source this file, so the list is defined once.
#
# `skills` is listed after `claude` so the tool that owns ~/.claude gets to
# create it first. That ordering is presentational, not load-bearing:
# skills/deploy.sh creates a repo-owned agent home itself when it is missing
# (agent_home_mode), precisely so that `--only skills` and every --dry-run
# behave the same as a full deploy.
AVAILABLE_TOOLS="zsh nvim tmux bin claude skills"

# resolve_tools <only_tools> <var_name>
# Resolves a comma-separated tool filter against AVAILABLE_TOOLS.
# Sets the caller's variable named <var_name> to the space-separated
# list of validated, deduplicated tools.  Exits with an error message
# if any requested tool is unknown.
#
# Usage (caller must eval the output):
#   eval "$(resolve_tools "$ONLY_TOOLS" "TOOLS")"
resolve_tools() {
  _rt_only="${1:-}"
  _rt_var="${2:-TOOLS}"

  if [ -z "$_rt_only" ]; then
    printf '%s="%s"\n' "$_rt_var" "$AVAILABLE_TOOLS"
    return 0
  fi

  _rt_result=""
  _rt_oldifs="$IFS"
  IFS=','
  for _rt_t in $_rt_only; do
    IFS="$_rt_oldifs"
    _rt_t=$(printf '%s' "$_rt_t" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    _rt_found=0
    for _rt_a in $AVAILABLE_TOOLS; do
      if [ "$_rt_t" = "$_rt_a" ]; then
        case " $_rt_result " in
          *" $_rt_t "*) _rt_found=1 ;;
          *)
            _rt_result="$_rt_result $_rt_t"
            _rt_found=1
            ;;
        esac
        break
      fi
    done
    if [ "$_rt_found" -eq 0 ]; then
      printf 'log_error "Unknown tool: '\''%s'\''. Available: %s"\n' "$_rt_t" "$AVAILABLE_TOOLS" >&2
      printf 'exit 1\n'
      return 1
    fi
    IFS=','
  done
  IFS="$_rt_oldifs"

  _rt_result=$(printf '%s' "$_rt_result" | sed 's/^[[:space:]]*//')
  printf '%s="%s"\n' "$_rt_var" "$_rt_result"
  return 0
}

# ── Known $HOME-side link destinations per tool ─────────────────────────
#
# links_for_tool <tool>
# Print (one per line) the known $HOME symlink destinations for <tool>
# (empty if <tool> has none). Single source of truth for "which paths under
# $HOME does this repo's deploy create": uninstall.sh needs it to know what
# to remove, deploy-all.sh --status needs it to check for broken symlinks.
# Keeping one copy (instead of duplicating the list in both scripts) is
# what prevents the drift that let ocw-meter go unlisted from
# KNOWN_LINKS_bin in the first place (see ADR DOC-2608040229 §2.6 /
# AGENTS.md 実装時の注意).
#
# A forgotten arm here surfaces as "No link list defined for '<tool>'.
# Skipping." in uninstall.sh's per-tool loop ONLY when <tool> is in $TOOLS
# AND has no KNOWN_GENERATED_* / KNOWN_SKILLS_SRC_* entry either (that loop
# only warns when all three come back empty). claude is the one tool where this
# doesn't save you: it has a KNOWN_GENERATED_claude entry
# (~/.claude/settings.json), so a forgotten claude arm here still leaves
# _generated non-empty, the warning never fires, and ~/.claude/CLAUDE.md
# quietly stops being touched while the generation it points into gets
# deleted out from under it. deploy-all.sh --status's link-health scan
# (a third consumer, added alongside this comment) has no warning path at
# all for a forgotten arm: the tool's entries are just silently absent from
# the report, so a broken symlink for that tool goes undetected too — the
# same blind spot skill_links() below exists to close for skills.
#
# Values are inlined into the case arms (not module-level KNOWN_LINKS_*
# variables) on purpose: this file is sourced by every interactive zsh
# startup (zsh/.zshrc), and module-level `VAR=$(printf ...)` assignments
# both leak into that shell's namespace (zsh/.zshrc already has to unset
# AVAILABLE_TOOLS for the same reason — see its "helpers.sh exports
# AVAILABLE_TOOLS which we don't need in an interactive shell" comment) and
# fork one subshell per tool at source time. Inlining also means $HOME /
# $XDG_CONFIG_HOME are read at call time instead of source time, which is
# what lets tests override them via `env HOME=...` after helpers.sh is
# already sourced.
links_for_tool() {
  case "$1" in
    zsh)
      printf '%s\n' \
        "$HOME/.zshrc" \
        "$HOME/.zsh_plugins.txt"
      ;;
    nvim)
      printf '%s\n' \
        "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/init.lua" \
        "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/lua" \
        "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/lazy-lock.json"
      ;;
    tmux)
      printf '%s\n' \
        "$HOME/.tmux.conf"
      ;;
    bin)
      printf '%s\n' \
        "$HOME/bin/ocw" \
        "$HOME/bin/claude-ds" \
        "$HOME/bin/ocw-meter"
      ;;
    claude)
      printf '%s\n' \
        "$HOME/.claude/CLAUDE.md"
      ;;
      # skills deliberately has no arm: its $HOME-side links are one per
      # skill directory auto-detected under skills/, across every agent in
      # skill_agents() — a set that changes whenever a skill is added or
      # removed, so it cannot be a fixed list here. skill_links() below is
      # its single source of truth instead, and both consumers of this
      # function (uninstall.sh, deploy-all.sh --status) call that too.
      # uninstall.sh's "No link list defined" warning must therefore not
      # fire for skills — see the note at its per-tool loop.
  esac
}

# ── State files ($HOME-side writeback into the running generation) ─────
#
# state_files_for_tool <tool>
# Print (one per line) the tool-relative paths of files that a running
# tool writes back through its $HOME symlink into the generation directory
# it resolves through (e.g. lazy.nvim's `:Lazy update` rewrites
# nvim/lazy-lock.json in place). Because $HOME symlinks always resolve
# through `current` (never the generation directly — see
# dotfiles_current_link), such a write lands inside the *generation*
# directory, not the source tree, and is silently lost the next time a new
# generation is created (create_generation copies from the source tree,
# not from the outgoing generation). detect_state_writeback (below) is
# what catches this before it happens.
#
# Same "one arm per tool, single source of truth" shape as links_for_tool
# (see its comment for why: avoiding the drift that let uninstall.sh's
# KNOWN_LINKS_bin go stale). Paths are relative to the tool's own
# directory (e.g. "lazy-lock.json", not "nvim/lazy-lock.json") because
# callers already know which tool they're checking and need to join it
# against two different roots (a generation directory and the source
# tree), not just $HOME.
#
# zsh/.zsh_plugins.txt is deliberately absent: it's antidote's *input*
# file (human-edited), never written by the tool itself. claude/settings.json
# is a generated real file (ADR §4.8), not a $HOME-side writeback into the
# generation, and is out of scope here (see AGENTS.md / the task that added
# this function).
state_files_for_tool() {
  case "$1" in
    nvim)
      printf '%s\n' \
        "lazy-lock.json"
      ;;
  esac
}

# detect_state_writeback <generation_dir> <src_tree>
# Compares every known state file (state_files_for_tool, across
# AVAILABLE_TOOLS) between generation_dir (typically the generation
# `current` still points at) and src_tree (typically the source tree about
# to become the next generation). Prints, one per line, "<tool>/<relpath>"
# for every file that differs. Uses cmp -s rather than diff — the same
# reasoning as ADR DOC-2608040229 §4.7 avoiding rsync: a minimal Linux
# install may not have diff, but cmp is POSIX baseline.
#
# A file missing on either side is not a diff worth reporting: missing in
# the generation means nothing has been written back yet (e.g. a fresh
# generation), and missing in src_tree would be a repo-structure question
# unrelated to writeback, not something --adopt-state or --force should
# have an opinion on.
detect_state_writeback() {
  _dsw_gen="$1"
  _dsw_src="$2"

  for _dsw_tool in $AVAILABLE_TOOLS; do
    _dsw_oldifs="$IFS"
    IFS='
'
    for _dsw_rel in $(state_files_for_tool "$_dsw_tool"); do
      IFS="$_dsw_oldifs"
      [ -n "$_dsw_rel" ] || continue
      _dsw_gen_file="$_dsw_gen/$_dsw_tool/$_dsw_rel"
      _dsw_src_file="$_dsw_src/$_dsw_tool/$_dsw_rel"
      if [ -f "$_dsw_gen_file" ] && [ -f "$_dsw_src_file" ]; then
        cmp -s "$_dsw_gen_file" "$_dsw_src_file" || printf '%s/%s\n' "$_dsw_tool" "$_dsw_rel"
      fi
      IFS='
'
    done
    IFS="$_dsw_oldifs"
  done
}

# ── Skill distribution targets (one per AI coding agent) ───────────────
#
# skills/ is distributed to every supported agent, not just Claude Code:
# all three read the same SKILL.md format (YAML frontmatter with name /
# description + Markdown body), so one skill directory serves all of them
# and a symlink per agent is the whole of the "port". See ADR
# DOC-2608272128.
#
# skill_agents
# Print (one per line) the agents skills/ is distributed to. A function,
# not a module-level variable, on purpose: this file is sourced by every
# interactive zsh startup (zsh/.zshrc), and a module-level list would leak
# into that shell's namespace the way AVAILABLE_TOOLS does — .zshrc
# already has to `unset AVAILABLE_TOOLS` for exactly that reason, and
# adding a second name to that list is a drift trap.
skill_agents() {
  printf '%s\n' \
    claude \
    codex \
    opencode
}

# skill_agent_home <agent>
# Print the agent's own config directory — the one whose existence decides
# whether this machine uses that agent at all (empty for an unknown
# agent). skills/deploy.sh deploys into an agent only when this directory
# already exists, so an agent the user has never installed never gets a
# directory tree conjured up for it.
#
# Read at call time (not stored at source time) so tests can override
# $HOME / $XDG_CONFIG_HOME / $CODEX_HOME after helpers.sh is sourced —
# same reasoning as links_for_tool()'s inlined values.
skill_agent_home() {
  case "$1" in
    claude) printf '%s\n' "$HOME/.claude" ;;
    codex) printf '%s\n' "${CODEX_HOME:-$HOME/.codex}" ;;
    opencode) printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/opencode" ;;
  esac
}

# agent_home_mode <agent>
# Print the chmod mode this repo's deploy applies to the agent's config
# directory, or nothing if this repo must not create that directory at all.
# The two meanings are deliberately carried by one value: "this repo knows
# what mode that directory needs" and "this repo owns it enough to create
# it" are the same fact for every agent in the table.
#
# Only claude is creatable: this repo deploys Claude Code's own config
# (CLAUDE.md, settings.json) unconditionally, so ~/.claude is this repo's
# own territory rather than evidence that the user installed a particular
# agent. codex and opencode are the opposite — their config directories
# exist only because the user installed them, so a missing one means
# "this machine doesn't use that agent" and must be left alone (ADR
# DOC-2608272128 §2.3).
#
# Without this, `--only skills` and, worse, every --dry-run would silently
# plan nothing for Claude Code on a machine where ~/.claude does not exist
# yet: claude/deploy.sh creates it, but its DRY-RUN branch only *prints*
# that it would, so a dry-run's existence check finds nothing there and the
# plan under-reports what a real run does — the same dry-run/real
# divergence claude/deploy.sh's own CLAUDE_SRC_DIR comment guards against.
#
# The mode (not just a yes/no) lives here so the 0700 requirement — ~/.claude
# may contain credentials — has one home; claude/deploy.sh reads it from
# here too rather than repeating the literal.
agent_home_mode() {
  case "$1" in
    claude) printf '%s\n' 700 ;;
  esac
}

# skill_dir_for_agent <agent>
# Print the directory that agent reads user skills from (empty for an
# unknown agent). All three happen to use "<agent home>/skills", but they
# are spelled out per agent rather than derived, because that is a fact
# about each agent's own contract, not a shared convention we get to
# assume holds for the next one added here. (OpenCode accepts both
# `skill/` and `skills/`; `skills/` is used so all three agree.)
skill_dir_for_agent() {
  _sdfa_home="$(skill_agent_home "$1")"
  [ -n "$_sdfa_home" ] || return 0
  case "$1" in
    claude | codex | opencode) printf '%s\n' "$_sdfa_home/skills" ;;
  esac
}

# skill_backup_dir_for_agent <agent>
# Print where skills/deploy.sh sets aside a pre-existing, non-repo-owned
# skill before symlinking over its name. Deliberately a sibling of the
# skills directory rather than a subdirectory of it: a backup living
# inside skills/ would be picked up by the agent as a real (duplicate)
# skill.
skill_backup_dir_for_agent() {
  _sbdfa_home="$(skill_agent_home "$1")"
  [ -n "$_sbdfa_home" ] || return 0
  printf '%s\n' "$_sbdfa_home/skills-backup"
}

# skill_backup_dir_for_link <link_path>
# Print the backup directory skills/deploy.sh would have used for a skill
# symlink at <link_path> (empty if the link is not directly inside any known
# agent's skills directory). Exists so uninstall.sh can walk the flat list
# skill_links() returns and still find each link's own agent's backup
# directory, without re-deriving "<skills dir> minus 'skills' plus
# 'skills-backup'" itself — that convention stays owned by
# skill_backup_dir_for_agent alone.
skill_backup_dir_for_link() {
  _sbdfl_dir="$(dirname "$1")"

  _sbdfl_oldifs="$IFS"
  IFS='
'
  for _sbdfl_agent in $(skill_agents); do
    IFS="$_sbdfl_oldifs"
    if [ "$_sbdfl_dir" = "$(skill_dir_for_agent "$_sbdfl_agent")" ]; then
      IFS="$_sbdfl_oldifs"
      skill_backup_dir_for_agent "$_sbdfl_agent"
      return 0
    fi
    IFS='
'
  done
  IFS="$_sbdfl_oldifs"
}

# skill_links [repo_root]
# Print (one per line) the paths under every agent's skills directory that
# are symlinks owned by this repo's distribution. Recognizes, for each
# agent: current-scheme (target under <prefix>/current/skills/), a
# generation directly (target under <prefix>/generations/*/skills/, e.g.
# when DOTFILES_DEPLOY_SRC was pointed at one directly), and the
# pre-migration direct-to-worktree scheme (target under repo_root/skills/,
# if repo_root is given — see ADR DOC-2608040229 §4.8/§4.10). Each of the
# three is also matched in its pre-split .../claude/skills/ spelling, so a
# machine deployed before skills/ became its own tool still has its links
# recognized as repo-owned and cleaned up rather than stranded (ADR
# DOC-2608272128 §4.3).
#
# Deliberately narrower than _dotfiles_symlink_is_repo_owned's generic
# "anywhere under repo_root" check: a user's own symlink into some other
# part of the working tree (e.g. a scratch directory) is not a skill this
# repo distributed, and treating it as one would make uninstall.sh delete
# a link it doesn't own.
#
# Skills aren't in links_for_tool() because skills/deploy.sh symlinks them
# individually, one per skill directory auto-detected under skills/,
# rather than as a fixed list — but they are still $HOME symlinks this
# repo creates, and in practice the largest group of them (ADR
# DOC-2608040229 §1.1). Shared by uninstall.sh (needs the list to know
# what to restore) and deploy-all.sh --status (needs it so its $HOME
# link-health scan doesn't blind-spot the tool with the most symlinks of
# any of them). Prints nothing (not an error) for an agent whose skills
# directory doesn't exist.
skill_links() {
  _sl_repo_root="${1:-}"
  _sl_prefix="$(dotfiles_prefix)"

  _sl_oldifs="$IFS"
  IFS='
'
  for _sl_agent in $(skill_agents); do
    IFS="$_sl_oldifs"
    _sl_dir="$(skill_dir_for_agent "$_sl_agent")"
    if [ -n "$_sl_dir" ] && [ -d "$_sl_dir" ]; then
      for _sl_link in "$_sl_dir"/*; do
        [ -L "$_sl_link" ] || continue
        _sl_target=$(readlink "$_sl_link")
        case "$_sl_target" in
          "$_sl_prefix/current/skills"/* | "$_sl_prefix/generations"/*/skills/* | \
            "$_sl_prefix/current/claude/skills"/* | "$_sl_prefix/generations"/*/claude/skills/*)
            printf '%s\n' "$_sl_link"
            ;;
          *)
            if [ -n "$_sl_repo_root" ]; then
              case "$_sl_target" in
                "$_sl_repo_root/skills"/* | "$_sl_repo_root/claude/skills"/*)
                  printf '%s\n' "$_sl_link"
                  ;;
              esac
            fi
            ;;
        esac
      done
    fi
    IFS='
'
  done
  IFS="$_sl_oldifs"
}

# ── Logging (colourised when the output fd is a terminal) ─────────────

# _can_color <fd>
# Returns 0 if fd is a terminal and NO_COLOR is unset.
_can_color() {
  [ -t "$1" ] && [ -z "${NO_COLOR:-}" ]
}

log_info() {
  if _can_color 1; then
    printf '\033[36m[INFO]\033[m %s\n' "$*"
  else
    printf '[INFO] %s\n' "$*"
  fi
}

log_warn() {
  if _can_color 2; then
    printf '\033[33m[WARN]\033[m %s\n' "$*" >&2
  else
    printf '[WARN] %s\n' "$*" >&2
  fi
}

log_error() {
  if _can_color 2; then
    printf '\033[31m[ERROR]\033[m %s\n' "$*" >&2
  else
    printf '[ERROR] %s\n' "$*" >&2
  fi
}

log_ok() {
  if _can_color 1; then
    printf '\033[32m[OK]\033[m %s\n' "$*"
  else
    printf '[OK] %s\n' "$*"
  fi
}

# Print a horizontal rule (ASCII for portability, 50 chars wide).
log_hr() {
  printf '%s\n' '--------------------------------------------------'
}

# ── Command helpers ───────────────────────────────────────────────────

# ensure_command <cmd> [hint]
# Check if a command is available.  If not, print an error + optional
# install hint and return 1.
# In dry-run mode, missing commands are noted but do not cause a failure
# (so the full plan is visible).
ensure_command() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  fi
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    log_warn "[DRY-RUN] '$1' is not installed — would fail during real deploy."
    if [ -n "${2:-}" ]; then
      printf '        Install: %s\n' "$2" >&2
    fi
    return 0
  fi
  log_error "'$1' is not installed."
  if [ -n "${2:-}" ]; then
    printf '       Install: %s\n' "$2" >&2
  fi
  return 1
}

# ── Homebrew prefix ───────────────────────────────────────────────────

# get_brew_prefix
# Print the Homebrew prefix for the current architecture.
# macOS:  /opt/homebrew (Apple Silicon) or /usr/local (Intel)
# Linux:  /home/linuxbrew/.linuxbrew
get_brew_prefix() {
  if command -v brew >/dev/null 2>&1; then
    brew --prefix 2>/dev/null && return 0
  fi
  # Best guess when brew is not on PATH yet
  if is_macos; then
    if [ "$(uname -m)" = "arm64" ]; then
      printf '/opt/homebrew'
    else
      printf '/usr/local'
    fi
  elif is_linux; then
    printf '/home/linuxbrew/.linuxbrew'
  else
    printf '/usr/local'
  fi
}

# ── Distribution layer (generations + current) ─────────────────────────
#
# $HOME never links directly into the working tree. Instead, deploy-all.sh
# copies the working tree into a dated "generation" directory under the
# canonical prefix, points a `current` symlink at it, and every tool's
# deploy.sh links $HOME through `current` (never through the generation
# directory directly — that indirection is what lets a rollback be a single
# symlink swap). See ADR DOC-2608040229 for the full rationale.

# dotfiles_prefix
# Print the canonical prefix that holds generations/ and current.
dotfiles_prefix() {
  printf '%s' "${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles"
}

# dotfiles_current_link
# Print the path to the `current` symlink (not its resolved target).
# Tool deploy.sh scripts must link $HOME through this literal path so that
# a later `current` swap changes what every symlink resolves to without
# re-linking anything under $HOME.
dotfiles_current_link() {
  printf '%s' "$(dotfiles_prefix)/current"
}

# dotfiles_keep_generations
# Print the configured generation retention count
# (${DOTFILES_KEEP_GENERATIONS:-3} — 3 is the default ADR §4.6 settled on:
# enough to protect a running process's lazy-loaded files plus one
# rollback target). Single source for this default so gc_generations and
# deploy-all.sh --status can't drift apart and report different numbers.
dotfiles_keep_generations() {
  printf '%s' "${DOTFILES_KEEP_GENERATIONS:-3}"
}

# resolve_deploy_src
# Ensures DOTFILES_DEPLOY_SRC is set for a standalone `<tool>/deploy.sh` run
# (deploy-all.sh always sets it itself before calling any tool script). If
# unset, defaults to `current`; exits with an explanatory error if `current`
# doesn't resolve to a generation — distinguishing "nothing there yet" from
# "current is a broken symlink" (e.g. it still points at a generation that
# was since GC'd), since those call for different next steps.
resolve_deploy_src() {
  [ -n "${DOTFILES_DEPLOY_SRC:-}" ] && return 0

  DOTFILES_DEPLOY_SRC="$(dotfiles_current_link)"
  if [ ! -e "$DOTFILES_DEPLOY_SRC" ]; then
    if [ -L "$DOTFILES_DEPLOY_SRC" ]; then
      log_error "current is a broken symlink: $DOTFILES_DEPLOY_SRC -> $(readlink "$DOTFILES_DEPLOY_SRC")"
      log_error "The generation it pointed to is gone. Run ./deploy-all.sh from the repo root to create a new one."
    else
      log_error "No distributed generation found (current does not exist yet)."
      log_error "Run ./deploy-all.sh from the repo root first."
    fi
    exit 1
  fi
}

# _dotfiles_symlink_is_repo_owned <dst> [repo_root]
# Returns 0 if dst is a symlink whose target lives under the canonical
# prefix (current-scheme distribution) or under repo_root (pre-migration
# direct-link scheme). repo_root is an explicit argument rather than
# something this function infers from a global: what counts as "this
# repository's working tree" depends on the caller's own context (a
# tool-scoped deploy.sh vs. a future root-scoped caller), so each call site
# must state it. Pass "" (or omit it) to skip the working-tree check.
# Used by symlink_backup to decide whether an existing symlink is a leftover
# deploy artifact (safe to replace without backup) or user data.
_dotfiles_symlink_is_repo_owned() {
  _diro_dst="$1"
  _diro_repo_root="${2:-}"

  [ -L "$_diro_dst" ] || return 1
  _diro_target=$(readlink "$_diro_dst")
  _diro_prefix="$(dotfiles_prefix)"

  case "$_diro_target" in
    "$_diro_prefix"/*) return 0 ;;
  esac

  if [ -n "$_diro_repo_root" ]; then
    case "$_diro_target" in
      "$_diro_repo_root"/*) return 0 ;;
    esac
  fi

  return 1
}

# _dotfiles_safe_rmdir <path> <required_prefix>
# rm -rf path, but only after verifying it's not a symlink, exists, is a
# real directory, and lives under required_prefix (prefix match) — the
# three checks "全孫共通の注意" §2 requires before every `rm -rf` in this
# codebase. The symlink check runs before the existence check on purpose: a
# broken symlink is -L true but -e false (it follows the dangling target),
# so checking -e first would silently let a broken symlink slip past this
# guard entirely. Shared by create_generation (scratch cleanup),
# gc_generations (old-generation cleanup) and uninstall.sh (distribution
# artifact cleanup) so all three go through one path.
#
# DRY_RUN-aware: the three guard checks above always run (so a dry-run
# report matches what a real run would refuse), and only the final
# `rm -rf` itself is skipped, printed instead — the same "report what a
# real run would actually hit" policy create_generation's id-collision
# check follows for its own DRY_RUN branch.
_dotfiles_safe_rmdir() {
  _dsr_path="$1"
  _dsr_prefix="$2"

  if [ -L "$_dsr_path" ]; then
    log_warn "Refusing to remove a symlink: $_dsr_path"
    return 1
  fi
  [ -e "$_dsr_path" ] || return 0
  if [ ! -d "$_dsr_path" ]; then
    log_warn "Refusing to remove a non-directory: $_dsr_path"
    return 1
  fi
  case "$_dsr_path" in
    "$_dsr_prefix"/*) ;;
    *)
      log_error "Refusing to remove path outside canonical prefix: $_dsr_path"
      return 1
      ;;
  esac

  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    printf '[DRY-RUN] rm -rf %s\n' "$_dsr_path"
    return 0
  fi

  rm -rf "$_dsr_path"
}

# create_generation <src_tree> <var_name>
# Copies AVAILABLE_TOOLS dirs + shared/ from src_tree into a new dated
# generation directory under the canonical prefix (cp -a; ignores any
# --only filter — a generation always holds the full tool set, see
# ADR §4.3). Sets the caller's <var_name> to the generation directory path
# (via eval, same calling convention as resolve_tools).
# In DRY_RUN mode, nothing is copied; the would-be path is still emitted so
# callers can print a coherent plan.
#
# On failure, stdout carries a literal "exit 1" (mirroring resolve_tools),
# because the caller's `eval "$(create_generation ...)"` discards our
# function return code: a failed command substitution still yields success
# to eval once its (empty) output is evaluated as a no-op. Emitting "exit 1"
# is what actually stops the caller.
create_generation() {
  _cg_src_tree="$1"
  _cg_var="${2:-GENERATION_DIR}"

  _cg_prefix="$(dotfiles_prefix)"
  _cg_gens_dir="$_cg_prefix/generations"
  _cg_sha=$(git -C "$_cg_src_tree" rev-parse --short HEAD 2>/dev/null)
  [ -n "$_cg_sha" ] || _cg_sha="nogit"
  _cg_dir="$_cg_gens_dir/$(date +%Y%m%dT%H%M%S)-$_cg_sha"

  # Checked before the DRY_RUN branch so `--dry-run` reports the same
  # collision a real run would hit, instead of silently reporting a plan
  # that would actually fail.
  if [ -e "$_cg_dir" ]; then
    # Generation IDs are second-precision (<date>-<short sha>). Two deploys
    # within the same second from the same commit collide on this path;
    # `cp -a` into an *existing* directory nests instead of overwriting
    # (e.g. .../bin/ocw stays stale while the new content lands unseen at
    # .../bin/bin/ocw), silently distributing stale content while reporting
    # success. Refuse instead of nesting.
    log_error "Generation already exists (id collision): $_cg_dir"
    log_error "Generation IDs are second-precision; wait a second and re-run, or"
    log_error "use --dev if you want changes to take effect without creating a"
    log_error "new generation at all."
    printf 'exit 1\n'
    return 1
  fi

  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    # Caller evals our stdout to receive <var_name>=<path> (same convention
    # as resolve_tools), so the human-readable plan must go to stderr —
    # mixing it into stdout would feed "[DRY-RUN] ..." text to eval.
    # Mirrors the real build below: scratch dir under .tmp/, copy each tool
    # into it, then mv into place — not a direct mkdir+cp into $_cg_dir.
    printf '[DRY-RUN] mkdir -p %s/.tmp\n' "$_cg_prefix" >&2
    for _cg_stale in "$_cg_prefix/.tmp"/gen.*; do
      [ -e "$_cg_stale" ] || [ -L "$_cg_stale" ] || continue
      printf '[DRY-RUN] rm -rf %s (leftover scratch)\n' "$_cg_stale" >&2
    done
    printf '[DRY-RUN] mktemp -d %s/.tmp/gen.XXXXXX\n' "$_cg_prefix" >&2
    for _cg_t in $AVAILABLE_TOOLS; do
      printf '[DRY-RUN] cp -a %s/%s <scratch>/%s\n' "$_cg_src_tree" "$_cg_t" "$_cg_t" >&2
    done
    printf '[DRY-RUN] cp -a %s/shared <scratch>/shared\n' "$_cg_src_tree" >&2
    printf '[DRY-RUN] mv <scratch> %s\n' "$_cg_dir" >&2
    printf '%s="%s"\n' "$_cg_var" "$_cg_dir"
    return 0
  fi

  # Build in a scratch directory OUTSIDE generations/ (gc_generations only
  # ever lists generations/*, so a half-built attempt left there by a crash
  # would otherwise be counted as a real generation) and rename into place
  # once complete. This also keeps the id-collision case above from ever
  # observing a partially-copied directory.
  mkdir -p "$_cg_prefix/.tmp" || {
    log_error "Failed to create scratch directory: $_cg_prefix/.tmp"
    printf 'exit 1\n'
    return 1
  }

  # Sweep any scratch dirs left behind by a previous run that never reached
  # its own cleanup (e.g. killed mid-copy) — gc_generations only ever looks
  # at generations/, so .tmp/ is nobody else's job. This repo assumes a
  # single user running deploys sequentially, so by definition nothing here
  # from a prior invocation is still in use.
  for _cg_stale in "$_cg_prefix/.tmp"/gen.*; do
    [ -e "$_cg_stale" ] || [ -L "$_cg_stale" ] || continue
    # _dotfiles_safe_rmdir already logs its own warning/error when it
    # refuses to remove something, so only announce success here — logging
    # "sweeping" unconditionally before the check would print a contradictory
    # "sweeping" followed by "refusing" on every deploy for anything it
    # can't actually remove (e.g. a symlink someone dropped in .tmp/).
    if _dotfiles_safe_rmdir "$_cg_stale" "$_cg_prefix/.tmp"; then
      log_warn "Swept leftover scratch directory: $_cg_stale"
    fi
  done

  _cg_scratch=$(mktemp -d "$_cg_prefix/.tmp/gen.XXXXXX") || {
    log_error "Failed to create a scratch directory under $_cg_prefix/.tmp"
    printf 'exit 1\n'
    return 1
  }

  for _cg_t in $AVAILABLE_TOOLS; do
    cp -a "$_cg_src_tree/$_cg_t" "$_cg_scratch/$_cg_t" || {
      log_error "Failed to copy '$_cg_t' into generation: $_cg_scratch"
      _dotfiles_safe_rmdir "$_cg_scratch" "$_cg_prefix/.tmp"
      printf 'exit 1\n'
      return 1
    }
  done
  cp -a "$_cg_src_tree/shared" "$_cg_scratch/shared" || {
    log_error "Failed to copy 'shared' into generation: $_cg_scratch"
    _dotfiles_safe_rmdir "$_cg_scratch" "$_cg_prefix/.tmp"
    printf 'exit 1\n'
    return 1
  }

  # mktemp -d always creates the scratch dir 0700, ignoring the user's
  # umask. Before this scratch-dir mechanism existed, the generation
  # directory came from a plain `mkdir -p`, whose mode is umask-derived —
  # so match that instead of hardcoding a mode, or umask 077 (the user's
  # explicit "keep new things private to me" signal) would get silently
  # overridden to world-readable 0755.
  _cg_mode=$(printf '%03o' $((0777 & ~0$(umask))))
  chmod "$_cg_mode" "$_cg_scratch" || log_warn "Failed to set permissions on scratch directory: $_cg_scratch"

  mkdir -p "$_cg_gens_dir" || {
    log_error "Failed to create generations directory: $_cg_gens_dir"
    _dotfiles_safe_rmdir "$_cg_scratch" "$_cg_prefix/.tmp"
    printf 'exit 1\n'
    return 1
  }

  if [ -e "$_cg_dir" ]; then
    log_error "Generation already exists (id collision): $_cg_dir"
    log_error "Generation IDs are second-precision; wait a second and re-run, or"
    log_error "use --dev if you want changes to take effect without creating a"
    log_error "new generation at all."
    _dotfiles_safe_rmdir "$_cg_scratch" "$_cg_prefix/.tmp"
    printf 'exit 1\n'
    return 1
  fi

  mv "$_cg_scratch" "$_cg_dir" || {
    log_error "Failed to finalize generation: $_cg_dir"
    _dotfiles_safe_rmdir "$_cg_scratch" "$_cg_prefix/.tmp"
    printf 'exit 1\n'
    return 1
  }

  # stdout is eval'd by the caller (see the function comment above), so the
  # success message goes to stderr — mixing it into stdout would feed
  # "[OK] Created generation: ..." to eval as a command.
  log_ok "Created generation: $_cg_dir" >&2
  printf '%s="%s"\n' "$_cg_var" "$_cg_dir"
  return 0
}

# write_manifest <generation_dir> <src_tree> <mode>
# Writes a plain-text .dotfiles-manifest into generation_dir recording
# where this generation came from. <mode> is "generation" or "dev", but no
# caller currently passes "dev": cmd_dev (deploy-all.sh) never calls this
# function at all, since dev mode points current at a source tree rather
# than a generation directory, and writing a manifest into the user's own
# working tree would dirty it. deploy-all.sh --status instead reads dev
# mode's provenance live via git rev-parse/status against the source tree
# it points at, rather than through a written manifest.
write_manifest() {
  _wm_gen_dir="$1"
  _wm_src_tree="$2"
  _wm_mode="$3"

  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    printf '[DRY-RUN] write manifest -> %s/.dotfiles-manifest\n' "$_wm_gen_dir"
    return 0
  fi

  _wm_sha=$(git -C "$_wm_src_tree" rev-parse HEAD 2>/dev/null)
  [ -n "$_wm_sha" ] || _wm_sha="unknown"
  _wm_branch=$(git -C "$_wm_src_tree" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ -n "$_wm_branch" ] || _wm_branch="unknown"

  _wm_dirty="unknown"
  if git -C "$_wm_src_tree" rev-parse --git-dir >/dev/null 2>&1; then
    if [ -z "$(git -C "$_wm_src_tree" status --porcelain 2>/dev/null)" ]; then
      _wm_dirty="0"
    else
      _wm_dirty="1"
    fi
  fi

  _wm_linked_worktree="0"
  is_linked_worktree "$_wm_src_tree" && _wm_linked_worktree="1"

  _wm_host=$(uname -n 2>/dev/null)
  [ -n "$_wm_host" ] || _wm_host="unknown"

  {
    printf 'deployed_at: %s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)"
    printf 'source_tree: %s\n' "$_wm_src_tree"
    printf 'commit_sha: %s\n' "$_wm_sha"
    printf 'branch: %s\n' "$_wm_branch"
    printf 'dirty: %s\n' "$_wm_dirty"
    printf 'linked_worktree: %s\n' "$_wm_linked_worktree"
    printf 'mode: %s\n' "$_wm_mode"
    printf 'hostname: %s\n' "$_wm_host"
  } >"$_wm_gen_dir/.dotfiles-manifest" || {
    log_error "Failed to write manifest: $_wm_gen_dir/.dotfiles-manifest"
    return 1
  }
  return 0
}

# switch_current <target_dir>
# Point the `current` symlink at target_dir using `ln -sfn` (not atomic —
# see ADR §4.7 for why mv -T/-h was rejected).
switch_current() {
  _sc_target="$1"
  _sc_link="$(dotfiles_current_link)"
  _sc_parent="$(dirname "$_sc_link")"

  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    printf '[DRY-RUN] mkdir -p %s\n' "$_sc_parent"
    printf '[DRY-RUN] ln -sfn %s %s\n' "$_sc_target" "$_sc_link"
    return 0
  fi

  mkdir -p "$_sc_parent" || {
    log_error "Failed to create directory: $_sc_parent"
    return 1
  }
  ln -sfn "$_sc_target" "$_sc_link" || {
    log_error "Failed to switch current -> $_sc_target"
    return 1
  }
  log_ok "current -> $_sc_target"
  return 0
}

# gc_generations
# Removes generations beyond dotfiles_keep_generations(), oldest first.
# Invariants: the generation `current` points at is never removed, and if
# `current` points outside generations/ (dev mode — see ADR §4.5) nothing
# is removed at all. Deletion goes through _dotfiles_safe_rmdir, which
# re-verifies each candidate is not a symlink, is a real directory, and
# lives under the canonical prefix before touching rm -rf.
gc_generations() {
  _gc_prefix="$(dotfiles_prefix)"
  _gc_gens_dir="$_gc_prefix/generations"
  _gc_link="$(dotfiles_current_link)"

  [ -d "$_gc_gens_dir" ] || return 0

  _gc_current_target=""
  if [ -L "$_gc_link" ]; then
    _gc_current_target=$(readlink "$_gc_link")
  fi

  case "$_gc_current_target" in
    "$_gc_gens_dir"/*) ;;
    *)
      log_info "Dev mode (or no current yet) — skipping generation GC."
      return 0
      ;;
  esac
  _gc_current_name=$(basename "$_gc_current_target")

  _gc_keep="$(dotfiles_keep_generations)"

  # Two passes over generations/, deliberately kept separate:
  #   1. Enumerate every entry (no -type filter) so a stray symlink or file
  #      dropped in generations/ (e.g. macOS's .DS_Store) still gets a
  #      warning instead of being silently ignored.
  #   2. Only entries that pass the not-a-symlink / real-directory checks
  #      go into `_gc_names` and count toward `_gc_total`. Mixing stray
  #      entries into the retention count would make each one cost one
  #      extra *real* generation deleted (the count goes up, but only real
  #      generations are ever actually removable).
  # The symlink check runs before -e for the same reason as
  # _dotfiles_safe_rmdir: a broken symlink is -L true but -e false, so
  # checking -e first would let it through uncounted and unwarned.
  _gc_all_names=$(find "$_gc_gens_dir" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort)

  _gc_names=""
  _gc_total=0
  for _gc_n in $_gc_all_names; do
    _gc_candidate="$_gc_gens_dir/$_gc_n"
    if [ -L "$_gc_candidate" ]; then
      log_warn "Ignoring a symlink in generations/: $_gc_candidate"
      continue
    fi
    if [ ! -d "$_gc_candidate" ]; then
      log_warn "Ignoring a non-directory in generations/: $_gc_candidate"
      continue
    fi
    _gc_names="$_gc_names
$_gc_n"
    _gc_total=$((_gc_total + 1))
  done

  _gc_excess=$((_gc_total - _gc_keep))
  [ "$_gc_excess" -gt 0 ] || return 0

  _gc_removed=0
  for _gc_n in $_gc_names; do
    [ -n "$_gc_n" ] || continue
    [ "$_gc_removed" -lt "$_gc_excess" ] || break
    [ "$_gc_n" = "$_gc_current_name" ] && continue

    _gc_target_dir="$_gc_gens_dir/$_gc_n"

    if [ "${DRY_RUN:-0}" -eq 1 ]; then
      printf '[DRY-RUN] rm -rf %s\n' "$_gc_target_dir"
      _gc_removed=$((_gc_removed + 1))
    else
      if _dotfiles_safe_rmdir "$_gc_target_dir" "$_gc_prefix"; then
        log_info "Removed old generation: $_gc_target_dir"
        _gc_removed=$((_gc_removed + 1))
      else
        # Do not count a failed removal — counting it would let a later,
        # removable generation be skipped once `_gc_removed` reaches
        # `_gc_excess`, leaving more than the configured number kept.
        log_error "Failed to remove old generation: $_gc_target_dir"
      fi
    fi
  done

  return 0
}

# ── Filesystem helpers ────────────────────────────────────────────────

# backup_dst <dst>
# Print a safe backup path for dst.  If dst.backup doesn't exist, use it
# as-is; otherwise append a timestamp + PID to avoid overwriting a previous
# backup (PID included to prevent same-second collisions).
backup_dst() {
  _bd="$1.backup"
  if [ ! -e "$_bd" ] && [ ! -L "$_bd" ]; then
    printf '%s' "$_bd"
  else
    printf '%s.%s.%s' "$_bd" "$(date +%Y%m%d%H%M%S)" "$$"
  fi
}

# symlink_backup <src> <dst>
# Create a symlink dst → src.  If dst already exists (and is not already
# the correct symlink), move it to a backup path first.
# If DRY_RUN is set to 1, only print what would be done.
# If BACKUP is set to 0, existing files are removed instead of backed up.
symlink_backup() {
  _src="$1"
  _dst="$2"

  # Already correct?
  if [ -L "$_dst" ] && [ "$(readlink "$_dst")" = "$_src" ]; then
    log_info "Already linked: $_dst → $_src"
    return 0
  fi

  # Every current caller is a <tool>/deploy.sh with SCRIPT_DIR=<repo_root>/<tool>,
  # so its parent is the repo root. This is computed here (not inside
  # _dotfiles_symlink_is_repo_owned) so the assumption stays visible at the
  # one place today's callers share, instead of being buried in a shared
  # helper that a differently-scoped future caller could inherit by accident.
  _sb_repo_root=""
  [ -n "${SCRIPT_DIR:-}" ] && _sb_repo_root="$(dirname "$SCRIPT_DIR")"

  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    if [ -e "$_dst" ] || [ -L "$_dst" ]; then
      if [ "${BACKUP:-1}" -eq 0 ]; then
        printf '[DRY-RUN] rm -f %s\n' "$_dst"
      elif _dotfiles_symlink_is_repo_owned "$_dst" "$_sb_repo_root"; then
        printf '[DRY-RUN] rm -f %s (repo-owned symlink, no backup)\n' "$_dst"
      else
        printf '[DRY-RUN] mv %s %s\n' "$_dst" "$(backup_dst "$_dst")"
      fi
    fi
    printf '[DRY-RUN] ln -fs %s %s\n' "$_src" "$_dst"
    return 0
  fi

  # Ensure parent directory exists
  _parent="$(dirname "$_dst")"
  if [ ! -d "$_parent" ]; then
    mkdir -p "$_parent" || {
      log_error "Failed to create directory: $_parent"
      return 1
    }
  fi

  # Handle existing file / symlink
  if [ -e "$_dst" ] || [ -L "$_dst" ]; then
    if [ "${BACKUP:-1}" -eq 0 ]; then
      log_warn "Removing existing (backup disabled): $_dst"
      rm -f "$_dst" || {
        log_error "Failed to remove: $_dst"
        return 1
      }
    elif _dotfiles_symlink_is_repo_owned "$_dst" "$_sb_repo_root"; then
      # A leftover symlink from a previous deploy (either the old direct-
      # to-worktree scheme or a stale current-scheme link) is not user
      # data, so replacing it should not leave a .backup that uninstall.sh
      # would later "restore" as if it were the user's original file.
      log_info "Replacing repo-owned symlink (no backup needed): $_dst"
      rm -f "$_dst" || {
        log_error "Failed to remove: $_dst"
        return 1
      }
    else
      _backup_path="$(backup_dst "$_dst")"
      log_warn "Backing up existing: $_dst → $_backup_path"
      mv "$_dst" "$_backup_path" || {
        log_error "Failed to back up: $_dst"
        return 1
      }
    fi
  fi

  ln -fs "$_src" "$_dst" || {
    log_error "Failed to symlink: $_src → $_dst"
    return 1
  }
  log_ok "Linked: $_dst → $_src"
  return 0
}

# symlink_restore <dst>
# Remove the symlink at dst and restore from a .backup* file if one exists.
# If dst is a real file (not a symlink), skip to avoid overwriting user data.
# Restores the *original* backup (dst.backup without timestamp) if available;
# otherwise falls back to the oldest timestamped backup.
# Used by uninstall.sh.
symlink_restore() {
  _dst="$1"

  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    if [ -L "$_dst" ]; then
      printf '[DRY-RUN] rm %s\n' "$_dst"
    elif [ -e "$_dst" ]; then
      printf '[DRY-RUN] (skip — real file exists at %s)\n' "$_dst"
    fi
    if [ -e "$_dst.backup" ] || [ -L "$_dst.backup" ]; then
      printf '[DRY-RUN] mv %s.backup %s\n' "$_dst" "$_dst"
    fi
    return 0
  fi

  _fail=0

  if [ -L "$_dst" ]; then
    if rm "$_dst"; then
      log_info "Removed symlink: $_dst"
    else
      log_error "Failed to remove symlink: $_dst"
      _fail=1
    fi
  elif [ -e "$_dst" ]; then
    log_warn "Skipping restore — real file exists at $_dst (not a symlink)"
    return 0
  fi

  # Restore the *original* backup (dst.backup) first; if that doesn't exist,
  # pick the oldest timestamped backup (first in glob order = earliest).
  # Use -e || -L to also match backup files that are symlinks or broken symlinks.
  _restore=""
  if [ -e "$_dst.backup" ] || [ -L "$_dst.backup" ]; then
    _restore="$_dst.backup"
  else
    for _cand in "$_dst.backup."*; do
      [ -e "$_cand" ] || [ -L "$_cand" ] || continue
      _restore="$_cand"
      break
    done
  fi

  if [ -n "$_restore" ]; then
    if mv "$_restore" "$_dst"; then
      log_ok "Restored backup: $_dst (from $_restore)"
    else
      log_error "Failed to restore backup: $_restore → $_dst"
      _fail=1
    fi
  fi

  return "$_fail"
}

# ── Source-time guard ─────────────────────────────────────────────────
#
# Deliberate exception to the "side-effect free" rule at the top of this
# file: every entry point (deploy-all.sh and each tool's deploy.sh, which
# users also run directly) sources this file, so hooking here is the only
# way to cover them all without touching six scripts.  The warning fires
# at most once per process tree.
#
# "$0" is the sourcing script, which always lives inside the checkout.
warn_if_linked_worktree "$(dirname -- "$0")"
