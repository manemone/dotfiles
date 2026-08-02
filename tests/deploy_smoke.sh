#!/usr/bin/env bash
#
# tests/deploy_smoke.sh — deploy-all.sh のサンドボックス実行スモークテスト。
# docs/design/DOC-2608020715-b_テスト方針.md の「サンドボックス実行」層を実装する。
#
# 対象は既定で bin,claude のみ。副作用が $HOME 配下に閉じ、かつネットワーク
# 不要なツールに限定している（AGENTS.md 最重要ルール・テスト方針を参照）。
# tmux はシステムへのパッケージインストール（apt/brew）を、zsh は Antidote
# の、nvim は lazy.nvim の git clone を伴うため既定から外している。
# 引数で対象を上書きできるが、その場合ネットワークアクセスやシステムへの
# パッケージインストールが実際に発生しうることを呼び出し側が理解すること。
#
# Usage:
#   tests/deploy_smoke.sh              # 既定: bin,claude
#   tests/deploy_smoke.sh bin          # bin のみ
#
# set -e は使わない。1件のアサーション失敗で残りのチェックが埋もれるのを
# 避け、全チェックを走らせた上で最後にまとめて合否を報告するため
# （個別コマンドの終了コードを拾って集約する既存方針を踏襲）。
set -uo pipefail

SCRIPT_DIR=$(
  cd "$(dirname "$0")" || exit 1
  pwd
)
REPO_ROOT=$(
  cd "$SCRIPT_DIR/.." || exit 1
  pwd
)

TOOLS="${1:-bin,claude}"

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

# new_sandbox
# mktemp -d でサンドボックス HOME を作り、実 $HOME と一致していないこと・
# 一時ディレクトリ配下であることを確認してから返す。ここが壊れると人間の
# 実 $HOME に対して deploy が走ってしまうため、この関数だけは慎重に扱う。
new_sandbox() {
  local dir
  dir="$(mktemp -d)" || {
    echo "エラー: mktemp -d に失敗しました" >&2
    exit 1
  }
  case "$dir" in
    /tmp/* | /var/folders/* | "${TMPDIR:-/nonexistent-tmpdir}"/*) ;;
    *)
      echo "エラー: サンドボックスが一時ディレクトリらしくありません: $dir" >&2
      exit 1
      ;;
  esac
  if [ -z "$dir" ] || [ "$dir" = "$HOME" ] || [ "$dir" = "/" ]; then
    echo "エラー: サンドボックスが実 HOME または '/' と同一です。中止します。" >&2
    exit 1
  fi
  CREATED_DIRS+=("$dir")
  printf '%s' "$dir"
}

run_deploy() {
  local sbx="$1"
  shift
  HOME="$sbx" \
    XDG_CONFIG_HOME="$sbx/.config" \
    XDG_DATA_HOME="$sbx/.local/share" \
    XDG_CACHE_HOME="$sbx/.cache" \
    ANTIDOTE_HOME="$sbx/.antidote" \
    "$REPO_ROOT/deploy-all.sh" "$@"
}

run_uninstall() {
  local sbx="$1"
  shift
  HOME="$sbx" "$REPO_ROOT/uninstall.sh" "$@"
}

has_tool() {
  case ",$TOOLS," in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

assert_symlink() {
  local path="$1" expected="$2"
  if [ -L "$path" ] && [ "$(readlink "$path")" = "$expected" ]; then
    pass "symlink: $path -> $expected"
  else
    fail "symlink: $path (expected -> $expected, got: $(readlink "$path" 2>/dev/null || echo 'not a symlink'))"
  fi
}

assert_real_file() {
  if [ -f "$1" ] && [ ! -L "$1" ]; then
    pass "実ファイル（symlinkでない）: $1"
  else
    fail "実ファイル（symlinkでない）: $1"
  fi
}

assert_exists() {
  if [ -e "$1" ] || [ -L "$1" ]; then
    pass "存在する: $1"
  else
    fail "存在する: $1"
  fi
}

assert_not_exists() {
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then
    pass "存在しない: $1"
  else
    fail "存在しない（想定外に存在した）: $1"
  fi
}

# ── シナリオ1: 既存ファイルの退避 + symlink 生成 + 冪等性 + uninstall 復元 ──

scenario_backup_symlink_idempotent_uninstall() {
  log "=== シナリオ1: 退避 / symlink / 冪等性 / uninstall 復元 (対象: $TOOLS) ==="
  local sbx out rc
  sbx="$(new_sandbox)"

  if has_tool bin; then
    mkdir -p "$sbx/bin"
    printf 'dummy-ocw\n' >"$sbx/bin/ocw"
    printf 'dummy-claude-ds\n' >"$sbx/bin/claude-ds"
  fi
  if has_tool claude; then
    mkdir -p "$sbx/.claude"
    printf 'dummy-claude-md\n' >"$sbx/.claude/CLAUDE.md"
    printf '{"dummy": true}\n' >"$sbx/.claude/settings.json"
  fi

  out="$(run_deploy "$sbx" --force --only "$TOOLS" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "deploy-all.sh --force --only $TOOLS が失敗 (exit=$rc)"
    log "$out"
    return
  fi
  pass "deploy-all.sh --force --only $TOOLS が成功"

  if has_tool bin; then
    assert_symlink "$sbx/bin/ocw" "$REPO_ROOT/bin/ocw"
    assert_symlink "$sbx/bin/claude-ds" "$REPO_ROOT/bin/claude-ds"
    assert_exists "$sbx/bin/ocw.backup"
    if [ "$(cat "$sbx/bin/ocw.backup" 2>/dev/null)" = "dummy-ocw" ]; then
      pass "既存ファイルの中身が退避先に保存されている: $sbx/bin/ocw.backup"
    else
      fail "既存ファイルの中身が退避先に保存されている: $sbx/bin/ocw.backup"
    fi
  fi

  if has_tool claude; then
    assert_symlink "$sbx/.claude/CLAUDE.md" "$REPO_ROOT/claude/CLAUDE.md"
    assert_exists "$sbx/.claude/CLAUDE.md.backup"
    assert_real_file "$sbx/.claude/settings.json"
    if grep -q '"dummy"' "$sbx/.claude/settings.json" 2>/dev/null; then
      fail "settings.json が実際に生成し直されている（ダミー内容のままになっている）"
    else
      pass "settings.json が実際に生成し直されている"
    fi
    assert_symlink "$sbx/.claude/skills/pr-review-loop" "$REPO_ROOT/claude/skills/pr-review-loop"
    assert_symlink "$sbx/.claude/skills/umbrella-orchestrator" "$REPO_ROOT/claude/skills/umbrella-orchestrator"
  fi

  # --- 冪等性: 同じ内容で2回目を実行しても壊れない ---
  out="$(run_deploy "$sbx" --force --only "$TOOLS" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "2回目の deploy-all.sh が失敗 (exit=$rc、冪等性なし)"
  else
    pass "2回目の deploy-all.sh も成功（冪等）"
  fi
  if has_tool bin; then
    assert_symlink "$sbx/bin/ocw" "$REPO_ROOT/bin/ocw"
  fi
  if has_tool claude; then
    if printf '%s' "$out" | grep -q "already up to date"; then
      pass "settings.json は2回目で再生成されない（already up to date）"
    else
      fail "settings.json が2回目でも再生成されている（冪等性が壊れている）"
    fi
  fi

  # --- uninstall: symlink 削除 + 退避ファイルの復元 ---
  out="$(run_uninstall "$sbx" --force --only "$TOOLS" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "uninstall.sh --force --only $TOOLS が失敗 (exit=$rc)"
    log "$out"
  else
    pass "uninstall.sh --force --only $TOOLS が成功"
  fi
  if has_tool bin; then
    if [ -f "$sbx/bin/ocw" ] && [ ! -L "$sbx/bin/ocw" ] && [ "$(cat "$sbx/bin/ocw")" = "dummy-ocw" ]; then
      pass "uninstall で bin/ocw が元のファイルに復元された"
    else
      fail "uninstall で bin/ocw が元のファイルに復元された"
    fi
  fi
  if has_tool claude; then
    if [ -f "$sbx/.claude/CLAUDE.md" ] && [ ! -L "$sbx/.claude/CLAUDE.md" ] && [ "$(cat "$sbx/.claude/CLAUDE.md")" = "dummy-claude-md" ]; then
      pass "uninstall で claude/CLAUDE.md が元のファイルに復元された"
    else
      fail "uninstall で claude/CLAUDE.md が元のファイルに復元された"
    fi
  fi
}

# ── シナリオ2: --no-backup 指定時は退避されず削除される ──────────────────

scenario_no_backup() {
  if ! has_tool bin; then
    return
  fi
  log "=== シナリオ2: --no-backup で退避されず削除される ==="
  local sbx out rc
  sbx="$(new_sandbox)"
  mkdir -p "$sbx/bin"
  printf 'dummy-ocw\n' >"$sbx/bin/ocw"

  out="$(run_deploy "$sbx" --force --no-backup --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "--no-backup 付き deploy-all.sh が失敗 (exit=$rc)"
    log "$out"
    return
  fi
  assert_symlink "$sbx/bin/ocw" "$REPO_ROOT/bin/ocw"
  assert_not_exists "$sbx/bin/ocw.backup"
}

# ── シナリオ3: --only フィルタで指定ツールのみがデプロイされる ───────────

scenario_only_filter() {
  log "=== シナリオ3: --only フィルタで指定ツール以外は触られない ==="
  local sbx
  sbx="$(new_sandbox)"
  run_deploy "$sbx" --force --only bin >/dev/null 2>&1

  if [ -L "$sbx/bin/ocw" ]; then
    pass "--only bin では bin/ocw がデプロイされる"
  else
    fail "--only bin では bin/ocw がデプロイされる"
  fi
  assert_not_exists "$sbx/.claude"
}

log "REPO_ROOT: $REPO_ROOT"
log "対象ツール: $TOOLS"
log

scenario_backup_symlink_idempotent_uninstall
log
scenario_no_backup
log
scenario_only_filter
log

if [ "$FAIL" -eq 0 ]; then
  log "[OK] deploy_smoke: 全チェックに合格しました。"
else
  log "[NG] deploy_smoke: 一部のチェックに失敗しました。"
fi

# 明示的な exit は使わない。shellcheck は「trap で登録した関数の後に exit
# があると、その関数への呼び出しが無い（SC2329）」と誤検知する既知の癖が
# あるため（trap ... EXIT からの呼び出しを制御フロー解析が追えない）。
# 最後の式の終了コードをそのままスクリプトの終了コードにする。
[ "$FAIL" -eq 0 ]
