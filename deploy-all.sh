#!/bin/sh
#
# deploy-all.sh — Unified deployment orchestrator for all dotfile tools.
#
# Usage:
#   ./deploy-all.sh                Interactive mode (asks before each tool)
#   ./deploy-all.sh --dry-run      Print what would be done, don't do it
#   ./deploy-all.sh --force        Skip all confirmations
#   ./deploy-all.sh --only zsh,nvim   Deploy specific tools only
#   ./deploy-all.sh --backup       Always back up existing files (on by default)
#   ./deploy-all.sh --no-backup    Skip backing up existing files
#   ./deploy-all.sh --status       Show current generation, manifest, GC state
#   ./deploy-all.sh --rollback [id]  Switch current to the previous (or given) generation
#   ./deploy-all.sh --dev          Point current at this working tree (no generation)
#   ./deploy-all.sh --adopt-state  Copy back state file writeback into the source tree
#
# Options can be combined:
#   ./deploy-all.sh --dry-run --only tmux
#   ./deploy-all.sh --force --only zsh,nvim
#
# --status/--rollback/--dev/--adopt-state are operations that bypass the
# normal generation-build/deploy flow (see ADR DOC-2608040229) and cannot be
# combined with each other or with --only/--force/--backup — --dry-run is
# the only modifier they honour.

set -u

SCRIPT_DIR=$(
  cd "$(dirname "$0")" || exit 1
  pwd
)

# shared/helpers.sh fires a one-shot "Deploying from a linked git worktree"
# notice the moment it's sourced (its source-time guard runs before this
# script has parsed any arguments). It is suppressed for four of our modes,
# for reasons independent of the notice's wording: --status is documented as
# read-only/safe against a real $HOME and shouldn't print anything unrelated
# to the status report, --rollback only ever points current at an existing
# generation directory (never at $SCRIPT_DIR) so the worktree it's invoked
# from is irrelevant to what it does, --dev prints its own dev-flavored
# warning below instead (cmd_dev), and --adopt-state only copies files from
# the running generation into $SCRIPT_DIR — it never touches $HOME symlinks,
# so the notice's "removing this worktree won't break $HOME" wording doesn't
# apply to what it does either. Pre-set the "already warned" flag the guard
# checks (shared/helpers.sh's DOTFILES_WORKTREE_WARNED, not
# DOTFILES_QUIET_WORKTREE_WARNING — that one is the user's own explicit
# silence switch and must stay untouched here) so it never fires for these
# four, before we even know MODE (argument parsing hasn't happened yet).
for _dsa_arg in "$@"; do
  case "$_dsa_arg" in
    --status | --rollback | --dev | --adopt-state)
      DOTFILES_WORKTREE_WARNED=1
      export DOTFILES_WORKTREE_WARNED
      break
      ;;
  esac
done
unset _dsa_arg

# shellcheck source=SCRIPTDIR/shared/helpers.sh
. "$SCRIPT_DIR/shared/helpers.sh"

# ── Defaults ──────────────────────────────────────────────────────────

DRY_RUN=0
FORCE=0
BACKUP=1
ONLY_TOOLS=""
MODE="deploy"
ROLLBACK_TARGET=""
ONLY_SEEN=0
FORCE_SEEN=0
BACKUP_SEEN=0

# ── Usage ─────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Unified deployment orchestrator for all dotfile tools.

Options:
  --dry-run         Print what would be done, make no changes.
  --force           Skip all confirmation prompts.
  --only <tools>    Comma-separated list of tools to deploy.
                    Available: $AVAILABLE_TOOLS
  --backup          Back up existing config files (default).
  --no-backup       Do NOT back up existing files before overwriting.
  --status          Show what current points at, its manifest, the kept
                    generations, and whether any \$HOME symlink is broken.
                    Read-only; safe to run against a real \$HOME. Exits 0
                    if current and every \$HOME symlink are healthy, or if
                    nothing has been deployed yet. Exits 1 if current is
                    broken (points at something that no longer exists or
                    isn't a symlink) or any \$HOME symlink is broken.
  --rollback [id]   Switch current to the generation before it, or to
                    <id> if given. \$HOME symlinks are not re-created —
                    they already resolve through current. Combine with
                    --dry-run to preview.
  --dev             Point current directly at this working tree instead
                    of a generation (no generation is created; edits to
                    this checkout take effect immediately). Combine with
                    --dry-run to preview.
  --adopt-state     Copy state files that a running tool wrote back into
                    the current generation (e.g. lazy.nvim's \`:Lazy update\`
                    rewriting nvim/lazy-lock.json through its \$HOME symlink)
                    into this source tree, so a normal deploy afterwards
                    won't silently discard them. Copies only — it does not
                    create a generation or touch \$HOME symlinks; run a
                    normal deploy afterwards (after reviewing/committing
                    the adopted changes) to continue. A no-op if nothing
                    differs. Combine with --dry-run to preview.
  --help, -h        Show this help message.

A normal deploy (no mode flag) refuses to create a new generation if the
generation \`current\` points at has state file changes not yet adopted into
this source tree (they would otherwise be silently discarded — see
--adopt-state above). Run --adopt-state first, or re-run with --force to
discard them. This check is skipped while \`current\` is in dev mode (there
is nothing to lose — dev mode's \`current\` already IS the source tree) and
still runs (report-only) under --dry-run.

Examples:
  $0                           # Interactive, all tools
  $0 --dry-run                 # Preview everything
  $0 --only zsh,nvim           # Deploy only zsh and nvim
  $0 --force --only tmux       # Deploy tmux without prompts
  $0 --status                  # Inspect what's currently deployed
  $0 --rollback                # Roll back to the previous generation
  $0 --dev                     # Switch to live-edit (dev) mode
  $0 --adopt-state             # Copy back unadopted state file writeback
EOF
}

# ── current-symlink operations (--status / --rollback / --dev) ────────
#
# These act on the `current` symlink itself rather than deploying files,
# so they are dispatched right after argument parsing and skip the
# generation-build / per-tool-deploy / GC flow entirely (see ADR
# DOC-2608040229 §4.4/§4.5).

# cmd_status
# Read-only. Prints what current points at (a generation, dev-mode source
# tree, or nothing yet), that generation's manifest (or, in dev mode, the
# same fields read live from the source tree's own git state — dev mode
# never writes a manifest, see cmd_dev), the list of kept generations,
# any state file writeback (detect_state_writeback, shared/helpers.sh) not
# yet adopted into this source tree, and a $HOME symlink health scan (via
# links_for_tool() + skill_links(), shared/helpers.sh) that flags
# broken symlinks. Returns 1 if current is broken (points at something that
# no longer exists or isn't a symlink) or any $HOME symlink is broken.
# Returns 0 otherwise, including when nothing has been deployed yet
# (current does not exist — that is not an error state) or when unadopted
# state file writeback exists (that's a thing to know, not itself a broken
# state — --adopt-state is the actionable follow-up, not a failing
# --status) — callers that want a machine-readable health check can rely on
# the exit code.
cmd_status() {
  _cs_prefix="$(dotfiles_prefix)"
  _cs_link="$(dotfiles_current_link)"
  _cs_gens_dir="$_cs_prefix/generations"
  _cs_target=""
  _cs_rc=0

  log_hr
  log_info "Distribution prefix: $_cs_prefix"
  printf '\n'

  if [ -L "$_cs_link" ]; then
    _cs_target="$(readlink "$_cs_link")"
  elif [ -e "$_cs_link" ]; then
    log_error "current exists but is not a symlink: $_cs_link"
    _cs_rc=1
  else
    log_warn "current does not exist yet — nothing has been deployed."
  fi

  case "$_cs_target" in
    "$_cs_gens_dir"/*)
      log_info "Mode: generation"
      log_info "current -> $_cs_target"
      if [ -d "$_cs_target" ]; then
        if [ -f "$_cs_target/.dotfiles-manifest" ]; then
          printf '\n'
          log_info "Manifest:"
          sed 's/^/  /' "$_cs_target/.dotfiles-manifest"
        else
          log_warn "No .dotfiles-manifest found in current generation."
        fi
      else
        log_error "current points at a generation directory that no longer exists: $_cs_target"
        _cs_rc=1
      fi
      ;;
    "") ;;
    *)
      log_warn "Mode: DEV — current points directly at a source tree (not a generation)."
      log_info "current -> $_cs_target"
      if [ -d "$_cs_target" ]; then
        if is_linked_worktree "$_cs_target"; then
          log_warn "The dev source tree is a linked git worktree. Removing it will break every symlink under \$HOME."
        fi
        # Dev mode never writes a .dotfiles-manifest (it would dirty the
        # source tree — see cmd_dev), so the provenance a generation gets
        # from its manifest has to be read live instead. Without this,
        # dev mode was the one mode where "which commit/branch is
        # currently live in $HOME" (ADR problem 3) stayed unanswerable —
        # arguably the mode that needs it most, since dev mode is exactly
        # where an uncommitted, mid-edit state is what's live.
        if command -v git >/dev/null 2>&1 && git -C "$_cs_target" rev-parse --git-dir >/dev/null 2>&1; then
          printf '\n'
          log_info "Live source tree state (no manifest in dev mode):"
          printf '  commit_sha: %s\n' "$(git -C "$_cs_target" rev-parse HEAD 2>/dev/null || printf unknown)"
          printf '  branch: %s\n' "$(git -C "$_cs_target" rev-parse --abbrev-ref HEAD 2>/dev/null || printf unknown)"
          if [ -z "$(git -C "$_cs_target" status --porcelain 2>/dev/null)" ]; then
            printf '  dirty: 0\n'
          else
            printf '  dirty: 1\n'
          fi
        fi
      else
        log_error "current points at a dev source tree that no longer exists: $_cs_target"
        _cs_rc=1
      fi
      ;;
  esac
  printf '\n'

  if [ -d "$_cs_gens_dir" ]; then
    _cs_cur_name=""
    case "$_cs_target" in
      "$_cs_gens_dir"/*) _cs_cur_name="$(basename "$_cs_target")" ;;
    esac
    log_info "Generations (kept: $(dotfiles_keep_generations)):"
    for _cs_name in $(find "$_cs_gens_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort); do
      if [ "$_cs_name" = "$_cs_cur_name" ]; then
        printf '  * %s  (current)\n' "$_cs_name"
      else
        printf '    %s\n' "$_cs_name"
      fi
    done
  else
    log_info "No generations directory yet."
  fi
  printf '\n'

  # State file writeback: only meaningful in generation mode. In dev mode
  # `current` already IS the source tree (SCRIPT_DIR), so the diff would
  # always be zero — same reasoning as the pre-generation check below.
  case "$_cs_target" in
    "$_cs_gens_dir"/*)
      if [ -d "$_cs_target" ]; then
        _cs_state_diff="$(detect_state_writeback "$_cs_target" "$SCRIPT_DIR")"
        if [ -n "$_cs_state_diff" ]; then
          log_warn "Unadopted state file writeback (written into the running"
          log_warn "generation, not yet copied back into this source tree):"
          printf '%s\n' "$_cs_state_diff" | sed 's/^/  /'
          log_info "Run '$0 --adopt-state' to bring these into the repo."
          printf '\n'
        fi
      fi
      ;;
  esac

  log_info "Link health (\$HOME):"
  _cs_broken=0
  for _cs_tool in $AVAILABLE_TOOLS; do
    _cs_oldifs="$IFS"
    IFS='
'
    for _cs_dst in $(links_for_tool "$_cs_tool"); do
      IFS="$_cs_oldifs"
      [ -z "$_cs_dst" ] && continue
      if [ -L "$_cs_dst" ]; then
        if [ -e "$_cs_dst" ]; then
          printf '  [OK]      %s\n' "$_cs_dst"
        else
          printf '  [BROKEN]  %s -> %s\n' "$_cs_dst" "$(readlink "$_cs_dst")"
          _cs_broken=$((_cs_broken + 1))
        fi
      elif [ -e "$_cs_dst" ]; then
        printf '  [SKIP]    %s (exists, not a symlink)\n' "$_cs_dst"
      else
        printf '  [MISSING] %s (not deployed)\n' "$_cs_dst"
      fi
      IFS='
'
    done
    IFS="$_cs_oldifs"
  done

  # Skill symlinks aren't in links_for_tool() — skills/deploy.sh symlinks
  # them individually, one per skill directory it auto-detects, into every
  # agent's own skills directory (ADR DOC-2608272128), not as a fixed list
  # — so they need their own pass via skill_links() (shared/helpers.sh) or
  # they'd be a silent blind spot in exactly the tool with the most $HOME
  # symlinks of any of them (ADR DOC-2608040229 §1.1).
  _cs_oldifs="$IFS"
  IFS='
'
  for _cs_dst in $(skill_links "$SCRIPT_DIR"); do
    IFS="$_cs_oldifs"
    [ -z "$_cs_dst" ] && continue
    if [ -e "$_cs_dst" ]; then
      printf '  [OK]      %s\n' "$_cs_dst"
    else
      printf '  [BROKEN]  %s -> %s\n' "$_cs_dst" "$(readlink "$_cs_dst")"
      _cs_broken=$((_cs_broken + 1))
    fi
    IFS='
'
  done
  IFS="$_cs_oldifs"

  if [ "$_cs_broken" -gt 0 ]; then
    printf '\n'
    log_warn "$_cs_broken broken symlink(s) found under \$HOME."
    _cs_rc=1
  fi

  return "$_cs_rc"
}

# cmd_rollback <target_id_or_empty>
# Switches current to <target_id_or_empty> if given (validated against the
# generations actually on disk — rejected if it contains a "/" to rule out
# path traversal), otherwise to the generation immediately before the one
# current points at. $HOME symlinks are never re-created here: they already
# resolve through the literal `current` path (see ADR §4.1), so swapping
# what current points at is the entire operation. Warns (but does not
# block) if the generation being left has state file writeback not yet
# adopted into the source tree — see the comment above the
# detect_state_writeback call below and ADR DOC-2608040229 §4.9.
cmd_rollback() {
  _rb_target_arg="$1"
  _rb_prefix="$(dotfiles_prefix)"
  _rb_link="$(dotfiles_current_link)"
  _rb_gens_dir="$_rb_prefix/generations"

  if [ ! -d "$_rb_gens_dir" ]; then
    log_error "No generations directory found. Nothing to roll back to."
    return 1
  fi

  _rb_names="$(find "$_rb_gens_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)"
  if [ -z "$_rb_names" ]; then
    log_error "No generations available to roll back to."
    return 1
  fi

  _rb_cur_target=""
  [ -L "$_rb_link" ] && _rb_cur_target="$(readlink "$_rb_link")"
  _rb_cur_name=""
  case "$_rb_cur_target" in
    "$_rb_gens_dir"/*) _rb_cur_name="$(basename "$_rb_cur_target")" ;;
  esac

  if [ -z "$_rb_cur_name" ]; then
    log_warn "current is in dev mode (or unset) — there is no 'current generation' to roll back from."
    log_warn "Rolling back means leaving dev mode and switching to a generation instead."
  fi

  if [ -n "$_rb_target_arg" ]; then
    case "$_rb_target_arg" in
      */* | . | ..)
        log_error "Invalid generation id: $_rb_target_arg"
        return 1
        ;;
    esac
    _rb_found=0
    for _rb_n in $_rb_names; do
      [ "$_rb_n" = "$_rb_target_arg" ] && _rb_found=1 && break
    done
    if [ "$_rb_found" -eq 0 ]; then
      log_error "Unknown generation: $_rb_target_arg"
      log_info "Available generations:"
      printf '%s\n' "$_rb_names" | sed 's/^/  /'
      return 1
    fi
    _rb_target_name="$_rb_target_arg"
  elif [ -n "$_rb_cur_name" ]; then
    _rb_cur_listed=0
    for _rb_n in $_rb_names; do
      [ "$_rb_n" = "$_rb_cur_name" ] && _rb_cur_listed=1 && break
    done
    if [ "$_rb_cur_listed" -eq 0 ]; then
      log_error "current points at a generation that no longer exists: $_rb_cur_name"
      log_info "Pass a generation id explicitly, e.g.: $0 --rollback <id>"
      log_info "Available generations:"
      printf '%s\n' "$_rb_names" | sed 's/^/  /'
      return 1
    fi

    _rb_target_name=""
    _rb_prev=""
    for _rb_n in $_rb_names; do
      if [ "$_rb_n" = "$_rb_cur_name" ]; then
        _rb_target_name="$_rb_prev"
        break
      fi
      _rb_prev="$_rb_n"
    done
    if [ -z "$_rb_target_name" ]; then
      log_error "No older generation to roll back to (current is already the oldest)."
      return 1
    fi
  else
    _rb_target_name="$(printf '%s\n' "$_rb_names" | tail -n1)"
    log_info "No generation id given — switching to the most recent generation: $_rb_target_name"
  fi

  _rb_target_dir="$_rb_gens_dir/$_rb_target_name"

  # Once we switch away from it, the generation we're leaving stops being
  # `current` and loses gc_generations' "never remove the generation
  # current points at" protection — a later deploy's GC can delete it like
  # any other old generation. Any state file writeback it holds (e.g. a
  # `:Lazy update` that rewrote nvim/lazy-lock.json through the $HOME
  # symlink) would be lost with it if it was never adopted into the source
  # tree. Warn here, before switching, while --adopt-state on the
  # generation we're about to leave is still possible (see ADR
  # DOC-2608040229 §4.9 — this is a documented, not auto-protected, gap).
  if [ -n "$_rb_cur_target" ] && [ -d "$_rb_cur_target" ]; then
    _rb_state_diff="$(detect_state_writeback "$_rb_cur_target" "$SCRIPT_DIR")"
    if [ -n "$_rb_state_diff" ]; then
      log_warn "The generation you're leaving has unadopted state file writeback:"
      printf '%s\n' "$_rb_state_diff" | sed 's/^/  /'
      log_warn "Once it's no longer current, it can be GC'd on a later deploy."
      log_warn "Ctrl-C now and run '$0 --adopt-state' first if you want to keep it."
    fi
  fi

  log_info "Rolling back current -> $_rb_target_dir"
  switch_current "$_rb_target_dir" || {
    log_error "Failed to switch current -> $_rb_target_dir"
    return 1
  }

  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    log_info "[DRY-RUN] \$HOME symlinks are unaffected by rollback — they already resolve through current."
  else
    log_ok "Rollback complete. \$HOME symlinks now resolve through: $_rb_target_dir"
  fi

  # Two things a plain "current now points here" message doesn't cover, and
  # both are exactly the kind of thing that should show up in a --dry-run
  # preview too (that's the whole point of previewing a rollback before
  # committing to it), so this isn't gated on DRY_RUN:
  #   - the target generation may not have every symlink the one we just
  #     left had (e.g. a claude skill added since), which leaves a
  #     dangling $HOME symlink that this command has no way to detect
  #     without walking every tool's links here too — --status already
  #     does exactly that, so point at it instead of duplicating the scan
  #   - ~/.claude/settings.json is a generated real file, not a symlink
  #     (ADR §4.8), so switching current never touches it; without this
  #     line a rollback silently leaves stale settings.json content in
  #     place while claiming the rollback is "complete"
  log_info "Run '$0 --status' to check for symlinks the target generation doesn't have."
  log_info "Note: ~/.claude/settings.json is a generated file, not a symlink — rollback"
  log_info "does not revert it. Re-run claude/deploy.sh from the target generation if"
  log_info "its content also needs to go back."
  return 0
}

# cmd_dev
# Points current directly at $SCRIPT_DIR (this working tree) instead of a
# generation. No generation is created or GC'd. Because every $HOME symlink
# already resolves through the literal `current` path rather than a
# generation directory (ADR §4.1), this alone is enough to make edits to
# the working tree take effect immediately — the same immediacy the
# pre-migration direct-link scheme had (ADR §4.5). It does not create any
# $HOME symlinks itself: run deploy-all.sh normally at least once first if
# nothing has been deployed yet.
cmd_dev() {
  log_hr
  log_warn "Switching to DEV mode: current will point directly at this working tree."
  log_warn "No generation is created; edits to this checkout take effect immediately."
  printf '\n'

  # Not warn_if_linked_worktree: its one-shot flag was pre-set before
  # shared/helpers.sh was even sourced (see the top of this script) so its
  # generic notice never fires here — dev mode needs its own wording. The
  # generic notice says removing the worktree does NOT break $HOME (true for
  # generation mode); dev mode is the opposite case, where removing the
  # worktree DOES break $HOME because current points directly at it. Still
  # honours the user's own DOTFILES_QUIET_WORKTREE_WARNING, unlike the
  # pre-set flag above which is this script's own internal suppression and
  # not a user-facing switch.
  if [ -z "${DOTFILES_QUIET_WORKTREE_WARNING:-}" ] && is_linked_worktree "$SCRIPT_DIR"; then
    log_warn "This working tree is a linked git worktree:"
    log_warn "  $SCRIPT_DIR"
    log_warn "Dev mode makes \$HOME resolve directly into it via current. Removing this"
    log_warn "worktree (e.g. 'ocw rm') will break every \$HOME symlink until you switch"
    log_warn "back to generation mode."
    log_warn "Silence this with DOTFILES_QUIET_WORKTREE_WARNING=1."
    printf '\n'
  fi

  switch_current "$SCRIPT_DIR" || {
    log_error "Failed to switch current -> $SCRIPT_DIR"
    return 1
  }

  printf '\n'
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    log_info "[DRY-RUN] Dev mode would be active. Generation GC would be skipped while active."
  else
    log_ok "Dev mode is active. Generation GC is skipped while current points outside generations/."
  fi
  log_info "To return to generation mode, run: $SCRIPT_DIR/deploy-all.sh"
  return 0
}

# cmd_adopt_state
# Copies every state file that differs between the generation `current`
# points at and this source tree (detect_state_writeback, shared/helpers.sh)
# back into the source tree — the opposite direction of a normal deploy.
# This is what makes a $HOME-side rewrite (e.g. lazy.nvim's `:Lazy update`
# writing through the nvim/lazy-lock.json symlink into the generation
# directory, invisible to `git status` because the generation directory
# isn't part of the repo) show up in the repo again.
#
# Copies only: it does not create a generation, switch current, or touch
# any $HOME symlink. Run a normal deploy afterwards (after reviewing/
# committing what got adopted, so a half-reviewed change doesn't
# immediately become the next generation) to continue — see usage().
#
# A no-op (not an error) if nothing differs, or if current isn't in
# generation mode: dev mode's current already IS the source tree (nothing
# to adopt from a place that already is here), and "nothing deployed yet"
# has no generation to adopt from either.
cmd_adopt_state() {
  _as_prefix="$(dotfiles_prefix)"
  _as_link="$(dotfiles_current_link)"
  _as_gens_dir="$_as_prefix/generations"
  _as_target=""

  [ -L "$_as_link" ] && _as_target="$(readlink "$_as_link")"

  case "$_as_target" in
    "$_as_gens_dir"/*) ;;
    "")
      log_warn "current does not exist yet — nothing has been deployed, so there is nothing to adopt."
      return 0
      ;;
    *)
      log_warn "current is in dev mode — it already points at a source tree, so there is nothing to adopt."
      return 0
      ;;
  esac

  if [ ! -d "$_as_target" ]; then
    log_error "current points at a generation directory that no longer exists: $_as_target"
    return 1
  fi

  _as_diff="$(detect_state_writeback "$_as_target" "$SCRIPT_DIR")"
  if [ -z "$_as_diff" ]; then
    log_info "No state file differs from the source tree. Nothing to adopt."
    return 0
  fi

  log_hr
  log_info "Adopting state file writeback from: $_as_target"
  printf '\n'

  _as_fail=0
  _as_oldifs="$IFS"
  IFS='
'
  for _as_rel in $_as_diff; do
    IFS="$_as_oldifs"
    [ -n "$_as_rel" ] || continue
    _as_gen_file="$_as_target/$_as_rel"
    _as_src_file="$SCRIPT_DIR/$_as_rel"

    if [ "${DRY_RUN:-0}" -eq 1 ]; then
      printf '[DRY-RUN] cp %s %s\n' "$_as_gen_file" "$_as_src_file"
    elif cp "$_as_gen_file" "$_as_src_file"; then
      log_ok "Adopted: $_as_rel"
    else
      log_error "Failed to adopt: $_as_rel"
      _as_fail=1
    fi
    IFS='
'
  done
  IFS="$_as_oldifs"

  [ "$_as_fail" -eq 0 ] || return 1

  printf '\n'
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    log_info "[DRY-RUN] Would adopt the file(s) above. Nothing was written."
  else
    log_ok "Adopted state file writeback into the source tree."
    log_info "Review with 'git diff', commit, then run './deploy-all.sh' to deploy normally."
  fi
  return 0
}

# ── Parse arguments ───────────────────────────────────────────────────

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --force)
      FORCE=1
      FORCE_SEEN=1
      ;;
    --backup)
      BACKUP=1
      BACKUP_SEEN=1
      ;;
    --no-backup)
      BACKUP=0
      BACKUP_SEEN=1
      ;;
    --only)
      if [ $# -lt 2 ]; then
        log_error "--only requires a comma-separated list of tools."
        exit 1
      fi
      ONLY_TOOLS="$2"
      ONLY_SEEN=1
      shift
      ;;
    --status)
      if [ "$MODE" != "deploy" ]; then
        log_error "Cannot combine --status with --rollback/--dev/--adopt-state."
        exit 1
      fi
      MODE="status"
      ;;
    --rollback)
      if [ "$MODE" != "deploy" ]; then
        log_error "Cannot combine --rollback with --status/--dev/--adopt-state."
        exit 1
      fi
      MODE="rollback"
      # Optional generation id: only consume $2 if it doesn't look like
      # another option, so `--rollback --dry-run` (or `--rollback -h`)
      # still parses the flag as a flag rather than as a (bogus)
      # generation id. Generation ids are `<date>-<sha>` and never start
      # with "-", so excluding anything dash-prefixed (not just "--"
      # long options) is safe and also catches short options like -h.
      if [ $# -ge 2 ]; then
        case "$2" in
          -*) ;;
          *)
            ROLLBACK_TARGET="$2"
            shift
            ;;
        esac
      fi
      ;;
    --dev)
      if [ "$MODE" != "deploy" ]; then
        log_error "Cannot combine --dev with --status/--rollback/--adopt-state."
        exit 1
      fi
      MODE="dev"
      ;;
    --adopt-state)
      if [ "$MODE" != "deploy" ]; then
        log_error "Cannot combine --adopt-state with --status/--rollback/--dev."
        exit 1
      fi
      MODE="adopt-state"
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      usage >&2
      exit 1
      ;;
  esac
  shift
done

# ── Dispatch current-symlink operations ─────────────────────────────────
# These bypass the generation-build / per-tool-deploy / GC flow below
# entirely (see the cmd_status/cmd_rollback/cmd_dev/cmd_adopt_state
# definitions above).

if [ "$MODE" != "deploy" ]; then
  if [ "$ONLY_SEEN" -eq 1 ] || [ "$FORCE_SEEN" -eq 1 ] || [ "$BACKUP_SEEN" -eq 1 ]; then
    log_error "--status/--rollback/--dev/--adopt-state cannot be combined with --only/--force/--backup/--no-backup."
    exit 1
  fi
fi

case "$MODE" in
  status)
    cmd_status
    exit $?
    ;;
  rollback)
    cmd_rollback "$ROLLBACK_TARGET"
    exit $?
    ;;
  dev)
    cmd_dev
    exit $?
    ;;
  adopt-state)
    cmd_adopt_state
    exit $?
    ;;
esac

# ── Resolve tool list (with dedup) ────────────────────────────────────

eval "$(resolve_tools "$ONLY_TOOLS" "TOOLS")"

# ── Banner ────────────────────────────────────────────────────────────

printf '\n'
log_hr
if [ "$DRY_RUN" -eq 1 ]; then
  log_warn "DRY RUN MODE — no changes will be made."
fi
log_info "Platform: $(uname -s) ($(uname -m))"
if is_wsl; then
  log_info "WSL:      detected"
fi
log_info "Tools:   $TOOLS"
printf '\n'

# ── Detect unadopted state file writeback before building a new generation ──
#
# A running tool (e.g. lazy.nvim's `:Lazy update`) writes back through its
# $HOME symlink into the *generation* directory, not the source tree —
# every $HOME symlink resolves through `current`, never through the source
# tree directly (ADR §4.1). create_generation (below) copies from the
# source tree, so without this check that writeback is silently discarded
# the moment a new generation replaces the one that holds it — exactly the
# regression this check exists to close (ADR §4.9).
#
# Runs before the confirmation prompt below (not just before
# create_generation) on purpose: there is no point asking "proceed?" when
# the answer is about to be "no, not until you deal with this", and a
# non-interactive run (--force or otherwise) shouldn't have to get past a
# stdin check first to hit this. Skipped while `current` is in dev mode:
# there, `current` already IS the source tree, so the diff would always be
# zero and this would just spin its wheels. Runs under --dry-run too
# (report-only there — skipping it would make a --dry-run preview miss the
# one thing a real run would actually stop over).
_deploy_cur_link="$(dotfiles_current_link)"
_deploy_cur_target=""
[ -L "$_deploy_cur_link" ] && _deploy_cur_target="$(readlink "$_deploy_cur_link")"
case "$_deploy_cur_target" in
  "$(dotfiles_prefix)/generations"/*)
    if [ -d "$_deploy_cur_target" ]; then
      _deploy_state_diff="$(detect_state_writeback "$_deploy_cur_target" "$SCRIPT_DIR")"
      if [ -n "$_deploy_state_diff" ]; then
        if [ "$FORCE" -eq 1 ]; then
          log_warn "State file writeback not in the source tree (discarding via --force):"
          printf '%s\n' "$_deploy_state_diff" | sed 's/^/  /'
        elif [ "$DRY_RUN" -eq 1 ]; then
          log_warn "[DRY-RUN] State file writeback not in the source tree (a real run would stop here):"
          printf '%s\n' "$_deploy_state_diff" | sed 's/^/  /'
          log_warn "       Adopt with: $0 --adopt-state"
          log_warn "       or discard with --force."
        else
          log_error "Plugin/state lockfile changed since last deploy:"
          printf '%s\n' "$_deploy_state_diff" | sed 's/^/         /'
          log_error "       The running generation has updates that are not in your"
          log_error "       source tree (e.g. a :Lazy update wrote through the symlink)."
          log_error "       Adopt them into the repo first:"
          log_error "         $0 --adopt-state"
          log_error "       or discard with --force."
          exit 1
        fi
      fi
    fi
    ;;
esac

# ── Confirmation (only in interactive mode, never in dry-run) ─────────

if [ "$FORCE" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  # Refuse to proceed when stdin is not a terminal (pipe / cron / CI).
  if [ ! -t 0 ]; then
    log_error "stdin is not a terminal. Use --force to deploy non-interactively."
    exit 1
  fi
  printf 'Proceed with deployment? [Y/n] '
  read -r _answer || {
    printf '\n'
    log_warn "Aborted (EOF on stdin)."
    exit 1
  }
  case "$_answer" in
    [Nn] | [Nn][Oo])
      log_warn "Aborted."
      exit 0
      ;;
  esac
  printf '\n'
fi

# ── Build a new generation and switch `current` ────────────────────────
#
# A generation always holds the full tool set regardless of --only (see
# ADR §4.3 / DOC-2608040229) — --only only controls which $HOME symlinks
# get (re)created below. Every tool's deploy.sh links $HOME through the
# `current` symlink itself, never through the generation directory, so a
# later rollback is a single `current` swap (ADR §4.1).

export DRY_RUN
export BACKUP

DOTFILES_DEPLOY_SRC="$(dotfiles_current_link)"
export DOTFILES_DEPLOY_SRC

GENERATION_DIR=""
eval "$(create_generation "$SCRIPT_DIR" "GENERATION_DIR")" || {
  log_error "Failed to create generation from: $SCRIPT_DIR"
  exit 1
}
log_info "Generation: $GENERATION_DIR"

write_manifest "$GENERATION_DIR" "$SCRIPT_DIR" "generation" || {
  log_warn "Failed to write .dotfiles-manifest (continuing)."
}

switch_current "$GENERATION_DIR" || {
  log_error "Failed to switch current -> $GENERATION_DIR"
  exit 1
}

printf '\n'

# ── Run each tool's deploy script ─────────────────────────────────────

OVERALL_OK=0

for _tool in $TOOLS; do
  _deploy_script="$SCRIPT_DIR/$_tool/deploy.sh"
  if [ ! -x "$_deploy_script" ]; then
    log_error "Deploy script not found or not executable: $_deploy_script"
    OVERALL_OK=1
    continue
  fi

  # Per-tool confirmation in interactive mode (never in dry-run)
  if [ "$FORCE" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    printf 'Deploy %s? [Y/n/s/q] ' "$_tool"
    read -r _answer || {
      printf '\n'
      log_warn "Aborted (EOF on stdin)."
      exit 1
    }
    case "$_answer" in
      [Ss] | [Ss][Kk][Ii][Pp]*)
        log_info "Skipping remaining tools."
        break
        ;;
      [Qq])
        log_warn "Aborted."
        exit 0
        ;;
      [Nn] | [Nn][Oo])
        log_info "Skipping: $_tool"
        continue
        ;;
    esac
  fi

  "$_deploy_script" || {
    log_error "Deploy script for '$_tool' exited with code $?."
    OVERALL_OK=1
  }
done

# ── Garbage-collect old generations ────────────────────────────────────

gc_generations

# ── Summary ───────────────────────────────────────────────────────────

printf '\n'
log_hr
if [ "$OVERALL_OK" -eq 0 ]; then
  log_ok "All deployments finished successfully. 🎉"
else
  log_warn "Deployment finished with some errors. Check the output above."
fi

exit "$OVERALL_OK"
