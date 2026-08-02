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
#
# 呼び出し規約: 結果は戻り値ではなくグローバル変数 SANDBOX_DIR に入れる。
# `sbx="$(new_sandbox)"` のようにコマンド置換で呼ぶと、この関数はサブ
# シェルで実行される。その結果 (1) 下のガードの `exit 1` がサブシェルしか
# 終了させずスクリプト本体が空の $sbx のまま処理を続けてしまう、
# (2) CREATED_DIRS+=(...) がサブシェル内の配列しか更新せず親シェルの
# CREATED_DIRS が空のままになり trap cleanup が何も消せない、という2つの
# 事故が起きる。実測でどちらも再現したため、通常呼び出し + グローバル変数
# 経由に変更した。呼び出し側は `new_sandbox; sbx="$SANDBOX_DIR"` とする。
SANDBOX_DIR=""

new_sandbox() {
  local dir
  dir="$(mktemp -d)" || {
    echo "エラー: mktemp -d に失敗しました" >&2
    exit 1
  }
  # mktemp が返した時点でディレクトリは既にファイルシステム上に存在する。
  # 下のガードで exit する経路でも trap cleanup が回収できるよう、ガードの
  # 前に登録する（登録するのは常に mktemp が返したパスそのものなので、
  # 「rm -rf の対象は自分が作ったものだけ」という不変条件は崩れない）。
  CREATED_DIRS+=("$dir")
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
  SANDBOX_DIR="$dir"
}

# sandbox_env <sbx>
# サンドボックス配下を指す環境変数の一覧を SANDBOX_ENV 配列にセットする。
# run_deploy / run_uninstall の双方から使い、リストを1箇所に集約する
# （テスト方針 DOC-2608020715-b が要求する XDG_* / ANTIDOTE_HOME の差し替え
# が deploy 側にしか効いていないと、uninstall 側は実環境の値のままになり
# 実 $HOME 配下の設定を触りにいく経路が残ってしまう）。
sandbox_env() {
  local sbx="$1"
  SANDBOX_ENV=(
    "HOME=$sbx"
    "XDG_CONFIG_HOME=$sbx/.config"
    "XDG_DATA_HOME=$sbx/.local/share"
    "XDG_CACHE_HOME=$sbx/.cache"
    "ANTIDOTE_HOME=$sbx/.antidote"
  )
}

run_deploy() {
  local sbx="$1"
  shift
  sandbox_env "$sbx"
  env "${SANDBOX_ENV[@]}" "$REPO_ROOT/deploy-all.sh" "$@"
}

run_uninstall() {
  local sbx="$1"
  shift
  sandbox_env "$sbx"
  env "${SANDBOX_ENV[@]}" "$REPO_ROOT/uninstall.sh" "$@"
}

has_tool() {
  case ",$TOOLS," in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

# list_repo_skills
# claude/skills/ 配下の実ディレクトリ名を列挙する（1行1件）。ハードコード
# すると、孫7で claude/skills/repo-baseline/ 等が増えたときにテストが
# それを検証しないまま緑になり続けるため、claude/deploy.sh 自身と同じ
# 「ディレクトリを見て自動検出する」入力からテストの期待値を導く。
list_repo_skills() {
  local d
  for d in "$REPO_ROOT/claude/skills"/*/; do
    [ -d "$d" ] || continue
    basename "$d"
  done
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
  local sbx out rc existing_skill
  new_sandbox
  sbx="$SANDBOX_DIR"

  if has_tool bin; then
    mkdir -p "$sbx/bin"
    printf 'dummy-ocw\n' >"$sbx/bin/ocw"
    printf 'dummy-claude-ds\n' >"$sbx/bin/claude-ds"
  fi
  existing_skill=""
  if has_tool claude; then
    mkdir -p "$sbx/.claude"
    printf 'dummy-claude-md\n' >"$sbx/.claude/CLAUDE.md"
    printf '{"dummy": true}\n' >"$sbx/.claude/settings.json"

    # claude/skills/ の退避（symlink_backup を通らず ~/.claude/skills-backup/
    # に退避される例外パス）を通すため、実在するskill名の1つと衝突する
    # ディレクトリを事前に置いておく。
    existing_skill="$(list_repo_skills | head -n1)"
    if [ -n "$existing_skill" ]; then
      mkdir -p "$sbx/.claude/skills/$existing_skill"
      printf 'dummy-existing-skill\n' >"$sbx/.claude/skills/$existing_skill/DUMMY_MARKER"
    fi
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
    local skill
    while IFS= read -r skill; do
      [ -n "$skill" ] || continue
      assert_symlink "$sbx/.claude/skills/$skill" "$REPO_ROOT/claude/skills/$skill"
    done <<EOF
$(list_repo_skills)
EOF

    if [ -n "$existing_skill" ]; then
      local backup_match=""
      for cand in "$sbx/.claude/skills-backup/$existing_skill".*; do
        [ -e "$cand" ] && backup_match="$cand" && break
      done
      if [ -n "$backup_match" ] && [ -f "$backup_match/DUMMY_MARKER" ]; then
        pass "既存skillがsymlink_backupを通らずskills-backupへ退避された: $backup_match"
      else
        fail "既存skillがsymlink_backupを通らずskills-backupへ退避された: $sbx/.claude/skills-backup/$existing_skill.*"
      fi
    fi
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
    if [ -n "$existing_skill" ]; then
      if [ -d "$sbx/.claude/skills/$existing_skill" ] && [ ! -L "$sbx/.claude/skills/$existing_skill" ] && [ -f "$sbx/.claude/skills/$existing_skill/DUMMY_MARKER" ]; then
        pass "uninstall で既存skillがskills-backupから復元された"
      else
        fail "uninstall で既存skillがskills-backupから復元された"
      fi
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
  new_sandbox
  sbx="$SANDBOX_DIR"
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
  new_sandbox
  sbx="$SANDBOX_DIR"
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
