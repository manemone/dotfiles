#!/usr/bin/env bash
set -euo pipefail

# Minimal, dependency-free lint: `bash -n` for every shell script in the
# repo, `python3 -m py_compile` for every python file. No external
# linters — this repo has none installed, and this phase deliberately
# doesn't add any (docs/planning/DOC-003_..._計画.md §13.1).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
status=0

echo "== bash -n =="
while IFS= read -r -d '' file; do
  echo "  bash -n $file"
  bash -n "$file" || status=1
done < <(
  find "$repo_root" \
    \( -path "$repo_root/.git" -o -path "$repo_root/*/.git" \) -prune -o \
    -type f \( -name '*.sh' -o -name 'ocw' -o -name 'claude-ds' -o -name 'ocw-meter' \) -print0
)

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
  awk "/<<'PY'/{flag=1; next} /^PY\$/{flag=0} flag" "$meter_script" > "$tmp_py"
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
