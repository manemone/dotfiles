#!/bin/sh
#
# shared/helpers.sh — Unified helpers sourced by every deploy script.
# Keep functions self-contained and side-effect free where possible.
# This file uses POSIX sh (no bashisms).

# ── Linked-worktree guard ─────────────────────────────────────────────
#
# Every deploy script symlinks files from THIS checkout into $HOME.  If the
# checkout is a linked git worktree (created by `git worktree add`, e.g. by
# `ocw`), those symlinks point into a directory that disappears when the
# worktree is removed — silently breaking ~/.zshrc, ~/.claude/skills/*,
# ~/bin/* and friends long after the deploy succeeded.
#
# Deploying from a worktree is legitimate while testing a change, so this is
# a warning, not an error.  Set DOTFILES_QUIET_WORKTREE_WARNING=1 to silence.

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

  log_warn "Deploying from a linked git worktree:"
  log_warn "  $(cd "${1:-.}" && pwd)"
  log_warn "Symlinks will point INTO this worktree and will break when it is"
  log_warn "removed (e.g. by 'ocw rm')."

  # The main worktree is the parent of the common git dir.
  _wilw_main=$(
    git -C "${1:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null
  )
  if [ -n "$_wilw_main" ]; then
    _wilw_main=$(cd "$_wilw_main/.." 2>/dev/null && pwd)
  fi
  if [ -n "$_wilw_main" ]; then
    log_warn "After merging, re-run the deploy from the main worktree:"
    log_warn "  cd $_wilw_main && ./deploy-all.sh"
  else
    log_warn "After merging, re-run the deploy from the main worktree."
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
AVAILABLE_TOOLS="zsh nvim tmux bin claude"

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
# guard entirely. Shared by create_generation (scratch cleanup) and
# gc_generations (old-generation cleanup) so both go through one path.
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
# where this generation came from. <mode> is "generation" or "dev".
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
# Removes generations beyond ${DOTFILES_KEEP_GENERATIONS:-3}, oldest first.
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

  _gc_keep="${DOTFILES_KEEP_GENERATIONS:-3}"

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
