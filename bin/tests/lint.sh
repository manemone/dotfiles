#!/usr/bin/env bash
set -euo pipefail

# Minimal, dependency-free lint: `bash -n` for every shell script in the
# repo, `python3 -m py_compile` for every python file. No external
# linters — this repo has none installed, and this phase deliberately
# doesn't add any (docs/planning/DOC-2608021229-a_..._計画.md §13.1).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
status=0

# Single source of truth for "every shell script in the repo" — used by
# both the bash -n block below and the /bin/bash -n compatibility block.
# Duplicating this find in two places is exactly the failure shape
# AGENTS.md warns about for links_for_tool(): a future standalone CLI
# added to bin/ only gets appended to one of the two copies, and the
# other silently checks one file fewer with no error or warning.
list_shell_scripts() {
  find "$repo_root" \
    \( -path "$repo_root/.git" -o -path "$repo_root/*/.git" \) -prune -o \
    -type f \( -name '*.sh' -o -name 'ocw' -o -name 'claude-ds' -o -name 'ocw-meter' \) -print0
}

echo "== bash -n =="
while IFS= read -r -d '' file; do
  echo "  bash -n $file"
  bash -n "$file" || status=1
done < <(list_shell_scripts)

echo "== /bin/bash -n (macOS bash 3.2 compatibility) =="
# `bash -n` above resolves via PATH, which on a dev machine with
# Homebrew bash installed is bash 5 — so a syntax construct bash 3.2
# alone rejects (e.g. a heredoc nested inside a process substitution)
# passes silently. macOS still ships bash 3.2 at /bin/bash, so re-run
# the same check there whenever that's a 3.x build.
if [ -x /bin/bash ] && /bin/bash --version | head -1 | grep -q 'version 3\.'; then
  while IFS= read -r -d '' file; do
    echo "  /bin/bash -n $file"
    /bin/bash -n "$file" || status=1
  done < <(list_shell_scripts)
else
  echo "  skipped (no bash 3.x at /bin/bash)"
fi

echo "== python3 -m py_compile =="
while IFS= read -r -d '' file; do
  echo "  py_compile $file"
  python3 -m py_compile "$file" || status=1
done < <(
  find "$repo_root" \
    \( -path "$repo_root/.git" -o -path "$repo_root/*/.git" \) -prune -o \
    -type f -name '*.py' -print0
)

echo "== embedded python3 heredoc in bin/ocw-meter =="
meter_script="$repo_root/bin/ocw-meter"
if [ -f "$meter_script" ]; then
  # A template ending in a suffix after the X's (e.g. "...-XXXXXX.py") is
  # a GNU coreutils extension (see GNU mktemp(1): "This option [--suffix]
  # is implied if TEMPLATE does not end in X"). BSD/macOS mktemp has no
  # such extension — the template is passed straight to mkstemp(3), which
  # requires it to *end* in the X's. Under `set -euo pipefail`, mktemp
  # failing there would fail this whole script, not just misname a file.
  # A directory whose template ends in X, with the suffix added to a
  # filename inside it, works identically on GNU and BSD.
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/ocw-meter-heredoc-XXXXXX")"
  trap 'rm -rf "$tmp_dir"' EXIT
  tmp_py="$tmp_dir/heredoc.py"
  # Match only the actual heredoc opener line (`cat >"$_ocw_meter_py"
  # <<'PY' || die ...`, possibly indented), not prose that merely
  # mentions `<<'PY'` in a comment — a loose `/<<'PY'/` pattern would
  # start extraction at the first such mention (e.g. a comment
  # explaining the heredoc) and pull in non-Python lines ahead of the
  # real opener. No trailing `$` on the opener pattern: the line ends
  # with `|| die "..."`, not right after `<<'PY'`.
  awk "/^[[:space:]]*cat >\"\\\$_ocw_meter_py\" <<'PY'/{flag=1; next} /^PY\$/{flag=0} flag" "$meter_script" >"$tmp_py"
  if [ -s "$tmp_py" ]; then
    echo "  py_compile (extracted heredoc)"
    python3 -m py_compile "$tmp_py" || status=1
  else
    echo "  warning: no python3 heredoc found in $meter_script" >&2
    status=1
  fi
fi

if [ "$status" -ne 0 ]; then
  echo "lint: FAILED" >&2
  exit 1
fi

echo "lint: OK"
