#!/usr/bin/env bash
#
# tests/template_smoke.sh — templates/repo-baseline copier テンプレートの
# レンダリング結果を検証するスモークテスト。
#
# .pre-commit-config.yaml.jinja / ci.yml.jinja は拡張子が .jinja のため、
# 本体リポジトリの check-yaml フックの対象外になる（Jinja の構文エラーや
# 壊れた YAML を生む変更が無検出でマージされうる）。それを検出できるのは
# このテストだけなので、templates/ 配下を変更した場合は必ず実行すること
# （AGENTS.md 参照）。
#
# 代表的な回答の組み合わせ（全部盛り / 最小構成）で copier copy を実行し、
# 生成された .pre-commit-config.yaml を `pre-commit validate-config` に、
# ci.yml を YAML パースに通す。あわせて生成された全 .md（AGENTS.md と
# docs/ 配下の全ファイル）の Jinja 空白制御ミス（行ゼロの表・見出し直前の
# 空行欠落・空行の二重化・Jinja 構文の残骸）と、use_doc_id=false 時に
# docs/ tools/ .github/ が生成されないことも検証する。
#
# set -e は使わない。1件のアサーション失敗で残りのチェックが埋もれるのを
# 避け、全チェックを走らせた上で最後にまとめて合否を報告するため
# （tests/deploy_smoke.sh と同じ既存方針を踏襲）。
set -uo pipefail

SCRIPT_DIR=$(
  cd "$(dirname "$0")" || exit 1
  pwd
)
REPO_ROOT=$(
  cd "$SCRIPT_DIR/.." || exit 1
  pwd
)
TEMPLATE_DIR="$REPO_ROOT/templates/repo-baseline"

FAIL=0
CREATED_DIRS=()
CREATED_FILES=()

log() { printf '%s\n' "$*"; }
pass() { printf '  [PASS] %s\n' "$1"; }
fail() {
  printf '  [FAIL] %s\n' "$1" >&2
  FAIL=1
}

cleanup() {
  local d f
  for d in "${CREATED_DIRS[@]:-}"; do
    [ -n "$d" ] && rm -rf "$d"
  done
  for f in "${CREATED_FILES[@]:-}"; do
    [ -n "$f" ] && rm -f "$f"
  done
}
trap cleanup EXIT

new_sandbox() {
  local dir
  dir="$(mktemp -d)" || {
    echo "エラー: mktemp -d に失敗しました" >&2
    exit 1
  }
  CREATED_DIRS+=("$dir")
  SANDBOX_DIR="$dir"
}

new_log_file() {
  local file
  file="$(mktemp)" || {
    echo "エラー: mktemp に失敗しました" >&2
    exit 1
  }
  CREATED_FILES+=("$file")
  LOG_FILE="$file"
}

# assert_markdown_hygiene <file> <label>
# Jinja の空白制御ミスが生む3系統の崩れを検出する:
#  1. 未展開の Jinja 構文（{% %} {{ }}）の残骸
#  2. 見出し（## ...）の直前に空行が無い（段落結合・二重見出し隣接）
#  3. 表の区切り行（|---|）の直後にデータ行が無い（行ゼロの壊れた表）
assert_markdown_hygiene() {
  local file="$1" label="$2"
  if python3 - "$file" <<'PYEOF'; then
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    lines = f.read().split("\n")

problems = []
for i, line in enumerate(lines):
    if any(tok in line for tok in ("{%", "%}", "{{", "}}")):
        problems.append(f"{i + 1}行目: Jinja構文の残骸: {line!r}")
    if line.startswith("## ") and i > 0 and lines[i - 1] != "":
        problems.append(f"{i + 1}行目: 見出しの直前が空行でない: {lines[i - 1]!r} -> {line!r}")
    if line.startswith("|---") and i + 1 < len(lines):
        nxt = lines[i + 1]
        if nxt == "" or nxt.startswith("#"):
            problems.append(f"{i + 1}行目: 表の区切り行の直後にデータ行が無い（行ゼロの表）: {line!r}")
    if line == "" and i > 0 and lines[i - 1] == "":
        problems.append(f"{i + 1}行目: 空行が2行連続している（{i}行目と{i + 1}行目）")

if problems:
    for p in problems:
        print(p, file=sys.stderr)
    sys.exit(1)
PYEOF
    pass "$label: Jinja残骸・見出し前空行・行ゼロの表が無い"
  else
    fail "$label: Jinja残骸・見出し前空行・行ゼロの表が無い"
  fi
}

# check_combo <name> <comma区切りの生成されないはずのパス、無ければ空文字> --data ...
# 「生成されないはずのパス」の検査は copier copy が成功した場合のみ行う。
# 呼び出し順や外側のグローバル変数に依存させず、この関数の中で完結させる
# （PR #38 ラウンド3レビュー: 末尾に check_combo を1つ足すと直前の
# SANDBOX_DIR を検査してしまう問題、および copier copy 失敗時に空の
# サンドボックスを見て false PASS が出る問題への対応）。
check_combo() {
  local name="$1" assert_absent_csv="$2"
  shift 2
  local sbx
  new_sandbox
  sbx="$SANDBOX_DIR"
  new_log_file
  local log_file="$LOG_FILE"

  log "=== $name ==="

  if uvx copier copy "$TEMPLATE_DIR" "$sbx" --defaults "$@" >"$log_file" 2>&1; then
    pass "copier copy が成功"
  else
    fail "copier copy が成功"
    cat "$log_file" >&2
    return
  fi

  if [ -n "$assert_absent_csv" ]; then
    local p
    local IFS=,
    for p in $assert_absent_csv; do
      if [ -e "$sbx/$p" ]; then
        fail "$name: $p が生成されていない"
      else
        pass "$name: $p が生成されていない"
      fi
    done
  fi

  if [ -f "$sbx/.copier-answers.yml" ]; then
    pass "$name: .copier-answers.yml が生成されている"
  else
    fail "$name: .copier-answers.yml が生成されている"
  fi

  if [ -f "$sbx/.pre-commit-config.yaml" ]; then
    if uvx pre-commit validate-config "$sbx/.pre-commit-config.yaml" >"$log_file" 2>&1; then
      pass ".pre-commit-config.yaml が pre-commit validate-config を通る"
    else
      fail ".pre-commit-config.yaml が pre-commit validate-config を通る"
      cat "$log_file" >&2
    fi
  else
    fail ".pre-commit-config.yaml が生成されている"
  fi

  if [ -f "$sbx/.github/workflows/ci.yml" ]; then
    # copier / pre-commit と同じく uvx 経由で依存を解決する。システムの
    # python3 に PyYAML が入っているかに依存すると、無い環境では
    # 「テンプレートは無事だが検証系が壊れている」だけなのに [FAIL] が出て
    # 原因も分かりにくい（詳細は PR #38 ラウンド2レビュー参照）。
    if uvx --with pyyaml python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$sbx/.github/workflows/ci.yml" >"$log_file" 2>&1; then
      pass "ci.yml が有効な YAML である"
    else
      fail "ci.yml が有効な YAML である"
      cat "$log_file" >&2
    fi
  fi

  if [ -f "$sbx/AGENTS.md" ]; then
    assert_markdown_hygiene "$sbx/AGENTS.md" "AGENTS.md"
  fi

  # AGENTS.md 以外にも Jinja の空白制御を使う .md.jinja が docs/ 配下にある
  # （docs/README.md.jinja / docs/design/README.md.jinja / コーディング方針.md.jinja 等）。
  # 生成された全 *.md を対象にする。
  if [ -d "$sbx/docs" ]; then
    local md_file
    while IFS= read -r md_file; do
      assert_markdown_hygiene "$md_file" "${md_file#"$sbx"/}"
    done < <(find "$sbx/docs" -name '*.md' -type f)
  fi
}

check_combo "全部盛り(use_doc_id/use_ci/has_long_running_commands/use_adr/use_reference すべて true, lint/test に特殊文字あり)" "" \
  --data default_branch=main \
  --data 'lint_cmd=pytest -k "not slow"' \
  --data 'test_cmd=npm run lint -- --max-warnings: 0' \
  --data use_doc_id=true \
  --data use_ci=true \
  --data has_long_running_commands=true \
  --data use_adr=true \
  --data use_reference=true

# _exclude による制御が効いていること（docs/ tools/ .github/ が生成され
# ないこと）を最小構成のケースで確認する。テンプレート README の受け入れ
# 条件の1つ。
check_combo "最小構成(use_doc_id/use_ci/has_long_running_commands すべて false, lint/test 空欄)" "docs,tools,.github" \
  --data default_branch=main \
  --data lint_cmd= \
  --data test_cmd= \
  --data use_doc_id=false \
  --data use_ci=false \
  --data has_long_running_commands=false

log
if [ "$FAIL" -eq 0 ]; then
  log "[OK] template_smoke: 全チェックに合格しました。"
else
  log "[NG] template_smoke: 一部のチェックに失敗しました。"
fi

# 明示的な exit は使わない（tests/deploy_smoke.sh と同じ理由。shellcheck
# SC2329 の既知の誤検知を避ける）。最後の式の終了コードをそのまま使う。
[ "$FAIL" -eq 0 ]
