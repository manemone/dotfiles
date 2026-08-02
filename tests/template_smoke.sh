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
# ci.yml を YAML パースに通す。
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

log() { printf '%s\n' "$*"; }
pass() { printf '  [PASS] %s\n' "$1"; }
fail() {
  printf '  [FAIL] %s\n' "$1" >&2
  FAIL=1
}

cleanup() {
  local d
  for d in "${CREATED_DIRS[@]:-}"; do
    [ -n "$d" ] && rm -rf "$d"
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

check_combo() {
  local name="$1"
  shift
  local sbx log_file
  new_sandbox
  sbx="$SANDBOX_DIR"
  log_file="$sbx.copier.log"

  log "=== $name ==="

  if uvx copier copy "$TEMPLATE_DIR" "$sbx" --defaults "$@" >"$log_file" 2>&1; then
    pass "copier copy が成功"
  else
    fail "copier copy が成功"
    cat "$log_file" >&2
    return
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
    if python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$sbx/.github/workflows/ci.yml"; then
      pass "ci.yml が有効な YAML である"
    else
      fail "ci.yml が有効な YAML である"
    fi
  fi
}

check_combo "全部盛り(use_doc_id/use_ci/has_long_running_commands/use_adr/use_reference すべて true, lint/test に特殊文字あり)" \
  --data default_branch=main \
  --data 'lint_cmd=pytest -k "not slow"' \
  --data 'test_cmd=npm run lint -- --max-warnings: 0' \
  --data use_doc_id=true \
  --data use_ci=true \
  --data has_long_running_commands=true \
  --data use_adr=true \
  --data use_reference=true

check_combo "最小構成(use_doc_id/use_ci/has_long_running_commands すべて false, lint/test 空欄)" \
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
