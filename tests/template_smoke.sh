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
# docs/ tools/ .github/ が生成されないことも検証する。.claude/pr-review.yml
# （回答に関わらず常に生成される）は lint_cmd/test_cmd の読み戻し・markers の
# 既定値・convention_docs の出し分けと参照先の実在を検証する。
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

# assert_agents_md_test_policy <file> <label>
# テスト方針節と linter 対応の作法は「どの回答の組み合わせでも出す」設計（設計判断 D5）。
# use_doc_id 等の if で将来誤って条件分岐させるリファクタや、抑制禁止ルールを緩める編集を
# 検知する（AGENTS.md 参照）。
assert_agents_md_test_policy() {
  local file="$1" label="$2"
  if grep -q '^## テスト方針$' "$file" &&
    grep -q 'このテストが存在しなかった場合、どんな現実的な regression を逃すのか' "$file" &&
    grep -q '受け入れ条件と test example は' "$file" &&
    grep -q '発生可能性 × 影響度 × 既存coverage' "$file" &&
    grep -q '壊れないことを確認するのと、専用テストを足すのは別の判断' "$file" &&
    grep -q '長さ系の指摘に対して機械的に' "$file" &&
    grep -q '対象ファイル単位の' "$file" &&
    grep -q '抑制ディレクティブや、設定ファイルの除外・閾値緩和を、AI の判断で' "$file"; then
    pass "$label: テスト方針節・linter 作法・抑制禁止ルールが揃っている"
  else
    fail "$label: テスト方針節・linter 作法・抑制禁止ルールが揃っている"
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

  # .claude/pr-review.yml は回答に関わらず常に生成される（skills/pr-review-loop/ が
  # Phase 0.5 で最優先に読む設定ファイル）。lint_cmd/test_cmd は特殊文字を含む回答が
  # クォート崩れで別の値にならず読み戻せること、空欄ならキーごと出ないことを検証する
  # （`null` にもしない。省略と `null` は意味が違うため）。convention_docs は
  # docs/ が生成されている（≒ use_doc_id=true）場合だけ存在し、参照先が実在すること、
  # markers は3つとも常に既定値であることを検証する。
  local expected_lint="" expected_test="" arg_i arg
  local args=("$@")
  for ((arg_i = 0; arg_i < ${#args[@]}; arg_i++)); do
    arg="${args[$arg_i]}"
    if [ "$arg" = "--data" ]; then
      case "${args[$arg_i + 1]}" in
        lint_cmd=*) expected_lint="${args[$arg_i + 1]#lint_cmd=}" ;;
        test_cmd=*) expected_test="${args[$arg_i + 1]#test_cmd=}" ;;
      esac
    fi
  done
  local has_docs=0
  [ -d "$sbx/docs" ] && has_docs=1

  if [ -f "$sbx/.claude/pr-review.yml" ]; then
    if uvx --with pyyaml python3 - "$sbx/.claude/pr-review.yml" "$expected_lint" "$expected_test" "$has_docs" "$sbx" <<'PYEOF' >"$log_file" 2>&1; then
import sys

path, expected_lint, expected_test, has_docs, sbx = sys.argv[1:6]
import os
import yaml

with open(path, encoding="utf-8") as f:
    raw = f.read()

# .claude/pr-review.yml は YAML パーサではなく pr-review-loop スキル（AI）が
# `cat` で生テキストのまま読む前提のファイルである。tojson の \uXXXX エスケープ
# （HTML向け。& ' < > を変換する）が紛れ込むと、YAML としては読み戻せても
# 生テキストを読む AI には壊れたコマンドに見える（PR #81 レビュー指摘）。
assert "\\u00" not in raw, f"生テキストに \\uXXXX エスケープが混入している（tojson 回帰の疑い）: {raw!r}"

doc = yaml.safe_load(raw)

assert isinstance(doc, dict), f"YAML のトップレベルが dict ではない: {doc!r}"

if expected_lint:
    assert doc.get("lint_cmd") == expected_lint, f"lint_cmd 不一致: {doc.get('lint_cmd')!r} != {expected_lint!r}"
else:
    assert "lint_cmd" not in doc, f"lint_cmd が空欄なのにキーが出ている: {doc.get('lint_cmd')!r}"

if expected_test:
    assert doc.get("test_cmd") == expected_test, f"test_cmd 不一致: {doc.get('test_cmd')!r} != {expected_test!r}"
else:
    assert "test_cmd" not in doc, f"test_cmd が空欄なのにキーが出ている: {doc.get('test_cmd')!r}"

markers = doc.get("markers") or {}
assert markers.get("approved") == "🤖✅ 承認", f"markers.approved 不一致: {markers.get('approved')!r}"
assert markers.get("changes_requested") == "🤖🔍 レビュー指摘", f"markers.changes_requested 不一致: {markers.get('changes_requested')!r}"
assert markers.get("reply") == "🤖💬 対応報告", f"markers.reply 不一致: {markers.get('reply')!r}"

if has_docs == "1":
    docs = doc.get("convention_docs")
    assert docs, "docs/ があるのに convention_docs が無い"
    for p in docs:
        assert os.path.exists(os.path.join(sbx, p)), f"convention_docs の参照先が実在しない: {p}"
else:
    assert "convention_docs" not in doc, "docs/ が無いのに convention_docs がある"
PYEOF
      pass "$name: .claude/pr-review.yml の内容が期待どおり"
    else
      fail "$name: .claude/pr-review.yml の内容が期待どおり"
      cat "$log_file" >&2
    fi
  else
    fail "$name: .claude/pr-review.yml が生成されている"
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
    assert_agents_md_test_policy "$sbx/AGENTS.md" "AGENTS.md"
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
  --data 'lint_cmd=pytest -k "not slow" && echo done' \
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

# 全質問をテンプレート既定値のまま（--data を1つも渡さない）で展開する。
# use_doc_id=true・lint_cmd/test_cmd 空欄という、最も多く踏まれる経路であり、
# かつ崩れ1・崩れ2（Jinja 空白制御ミスによる二重空行・空行欠落）が実際に
# 発生していた組み合わせ（PR #39 ラウンド2レビュー参照）。全部盛り/最小構成の
# どちらの combo にも入っていなかったため、再発防止としてここに追加する。
check_combo "既定値のみ(--defaults そのまま。use_doc_id/use_ci はテンプレ既定値 true、lint/test/adr/reference は既定値のまま)" ""

log
if [ "$FAIL" -eq 0 ]; then
  log "[OK] template_smoke: 全チェックに合格しました。"
else
  log "[NG] template_smoke: 一部のチェックに失敗しました。"
fi

# 明示的な exit は使わない（tests/deploy_smoke.sh と同じ理由。shellcheck
# SC2329 の既知の誤検知を避ける）。最後の式の終了コードをそのまま使う。
[ "$FAIL" -eq 0 ]
