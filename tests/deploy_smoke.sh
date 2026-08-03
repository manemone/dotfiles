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

# EXTRA_ENV
# run_deploy / run_deploy_from に渡す追加の環境変数。シナリオ関数が呼び出し
# 前にセットし、呼び出し後に空へ戻す運用とする（例: 世代のGCを検証するため
# DOTFILES_KEEP_GENERATIONS を上書きするシナリオ）。
EXTRA_ENV=()

# run_deploy_from <deploy_all.sh のパス> <sbx> [引数...]
# REPO_ROOT の deploy-all.sh 以外（使い捨てのコピーツリーなど）から
# サンドボックスへ deploy するためのバリエーション。
run_deploy_from() {
  local deploy_all="$1" sbx="$2"
  shift 2
  sandbox_env "$sbx"
  env "${SANDBOX_ENV[@]}" "${EXTRA_ENV[@]}" "$deploy_all" "$@"
}

run_deploy() {
  local sbx="$1"
  shift
  run_deploy_from "$REPO_ROOT/deploy-all.sh" "$sbx" "$@"
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

# dotfiles_prefix_for <sbx>
# shared/helpers.sh の dotfiles_prefix() と同じ計算をテスト側で再現する
# （XDG_DATA_HOME は sandbox_env が $sbx/.local/share に差し替える）。
dotfiles_prefix_for() {
  printf '%s/.local/share/dotfiles' "$1"
}

# current_target_for <sbx>
# サンドボックス内の current シンボリックリンクの読み取り先を返す。
current_target_for() {
  readlink "$(dotfiles_prefix_for "$1")/current" 2>/dev/null
}

# wait_for_next_second
# 世代IDは秒精度（<date +%Y%m%dT%H%M%S>-<sha>）なので、意図的に世代を
# 増やしたい再デプロイの間には最低1秒空ける必要がある。固定の `sleep 1`
# は「1回目の date 呼び出し直後」ではなく「テストコードがこの行に来た
# 時点」から数えるため、1回目のdeploy内の処理時間や実行環境の負荷次第
# では計算上ぎりぎり足りず、まれに同一秒に収まって世代ID衝突を起こす
# （衝突自体は仕様通り正しく拒否されるが、テストの意図は「増える」側の
# 検証なので偽陽性の失敗になる）。秒の値が実際に変わるまで待つことで、
# タイミングに依存せず確実に次の秒へ進める。
wait_for_next_second() {
  local start
  start="$(date +%s)"
  while [ "$(date +%s)" = "$start" ]; do
    sleep 0.1
  done
}

# copy_repo_snapshot <dest_dir>
# deploy-all.sh が世代へコピーする対象一式（全ツールディレクトリ + shared/）
# と deploy-all.sh 自身を dest_dir へコピーする。「ソースツリー消失耐性」
# 「編集分離」シナリオで、REPO_ROOT とは別の使い捨てツリーから deploy し、
# そのツリーを消す・書き換えるために使う。
copy_repo_snapshot() {
  local dest="$1" name
  mkdir -p "$dest"
  for name in zsh nvim tmux bin claude shared; do
    cp -a "$REPO_ROOT/$name" "$dest/$name"
  done
  cp -a "$REPO_ROOT/deploy-all.sh" "$dest/deploy-all.sh"
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
  local sbx out rc existing_skill prefix
  new_sandbox
  sbx="$SANDBOX_DIR"
  prefix="$(dotfiles_prefix_for "$sbx")"

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
    local gen_target

    # $HOME 側の symlink は current を経由する固定パスを指す（世代ディレク
    # トリを直接指さない）。current の付け替えだけで全リンクの向き先が
    # 一斉に切り替わる、という世代方式の要になっている（ADR §4.1）。
    assert_symlink "$sbx/bin/ocw" "$prefix/current/bin/ocw"
    assert_symlink "$sbx/bin/claude-ds" "$prefix/current/bin/claude-ds"
    assert_exists "$sbx/bin/ocw.backup"
    if [ "$(cat "$sbx/bin/ocw.backup" 2>/dev/null)" = "dummy-ocw" ]; then
      pass "既存ファイルの中身が退避先に保存されている: $sbx/bin/ocw.backup"
    else
      fail "既存ファイルの中身が退避先に保存されている: $sbx/bin/ocw.backup"
    fi

    if [ -L "$prefix/current" ]; then
      pass "current が symlink として存在する: $prefix/current"
    else
      fail "current が symlink として存在する: $prefix/current"
    fi
    gen_target="$(current_target_for "$sbx")"
    case "$gen_target" in
      "$prefix/generations/"*)
        pass "current が generations/ 配下を指している: $gen_target"
        ;;
      *)
        fail "current が generations/ 配下を指している (実際: $gen_target)"
        ;;
    esac
    assert_exists "$gen_target/.dotfiles-manifest"
    if grep -q '^mode: generation$' "$gen_target/.dotfiles-manifest" 2>/dev/null; then
      pass "manifest の mode が generation になっている"
    else
      fail "manifest の mode が generation になっている"
    fi
  fi

  if has_tool claude; then
    # $HOME 側の symlink は current を経由する固定パスを指す(作業ツリーを
    # 直接指さない)。孫2で claude も他ツールと同じ配布実体経由へ揃えた
    # (ADR §4.8 / DOC-2608040229)。
    assert_symlink "$sbx/.claude/CLAUDE.md" "$prefix/current/claude/CLAUDE.md"
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
      assert_symlink "$sbx/.claude/skills/$skill" "$prefix/current/claude/skills/$skill"
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
  # 世代IDは秒精度（<date>-<sha>）なので、同一秒内の再デプロイは同じ内容
  # でも世代IDが衝突しうる（衝突時は上書きせずエラーにする仕様。指摘3）。
  # 秒が変わるまで待ってから2回目を実行する。
  wait_for_next_second
  out="$(run_deploy "$sbx" --force --only "$TOOLS" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "2回目の deploy-all.sh が失敗 (exit=$rc、冪等性なし)"
  else
    pass "2回目の deploy-all.sh も成功（冪等）"
  fi
  if has_tool bin; then
    assert_symlink "$sbx/bin/ocw" "$(dotfiles_prefix_for "$sbx")/current/bin/ocw"
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
      # 孫3で uninstall.sh の由来判定が両対応になり、current 経由で張られた
      # 新方式の skill symlink も認識・撤去できるようになった(ADR §4.8/§4.9
      # / DOC-2608040229)。撤去後は deploy 時に skills-backup へ退避して
      # おいた元のスキルが復元される。
      if [ -d "$sbx/.claude/skills/$existing_skill" ] && [ ! -L "$sbx/.claude/skills/$existing_skill" ] && [ -f "$sbx/.claude/skills/$existing_skill/DUMMY_MARKER" ]; then
        pass "uninstallで新方式skillのsymlinkが撤去され、元skillが復元された: $sbx/.claude/skills/$existing_skill"
      else
        fail "uninstallで新方式skillのsymlinkが撤去され、元skillが復元された: $sbx/.claude/skills/$existing_skill"
      fi

      # 復元は「移動」であって「コピー」ではないので、skills-backup 配下に
      # 退避データが残っていないことも確認する(残っていれば復元処理の
      # 実装が mv ではなく cp 相当に退化している証拠になる)。
      local backup_match_after_uninstall=""
      for cand in "$sbx/.claude/skills-backup/$existing_skill".*; do
        [ -e "$cand" ] && backup_match_after_uninstall="$cand" && break
      done
      if [ -z "$backup_match_after_uninstall" ]; then
        pass "復元後、skills-backup配下の退避データは残っていない(復元先へ移動済み)"
      else
        fail "復元後、skills-backup配下の退避データは残っていない(復元先へ移動済み): $backup_match_after_uninstall が残存"
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
  assert_symlink "$sbx/bin/ocw" "$(dotfiles_prefix_for "$sbx")/current/bin/ocw"
  assert_not_exists "$sbx/bin/ocw.backup"
}

# ── シナリオ3: --only フィルタで指定ツールのみがデプロイされる ───────────

scenario_only_filter() {
  log "=== シナリオ3: --only フィルタで指定ツール以外は触られない ==="
  local sbx gen_target tool
  new_sandbox
  sbx="$SANDBOX_DIR"
  run_deploy "$sbx" --force --only bin >/dev/null 2>&1

  if [ -L "$sbx/bin/ocw" ]; then
    pass "--only bin では bin/ocw がデプロイされる"
  else
    fail "--only bin では bin/ocw がデプロイされる"
  fi
  assert_not_exists "$sbx/.claude"

  # --only は $HOME 側のリンク対象を絞るだけで、世代の中身には影響しない
  # （ADR §4.3 / DOC-2608040229）。--only bin でも世代には全ツール分の
  # ディレクトリが入っていることを確認する。
  gen_target="$(current_target_for "$sbx")"
  for tool in zsh nvim tmux bin claude shared; do
    assert_exists "$gen_target/$tool"
  done
}

# ── シナリオ4: ソースツリー消失耐性 ────────────────────────────────────

scenario_source_tree_disappears() {
  if ! has_tool bin; then
    return
  fi
  log "=== シナリオ4: ソースツリー消失耐性 ==="
  local sbx copy_dir out rc content
  new_sandbox
  sbx="$SANDBOX_DIR"
  copy_dir="$(mktemp -d)"
  CREATED_DIRS+=("$copy_dir")
  copy_repo_snapshot "$copy_dir"

  out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "コピーからの deploy-all.sh --only bin が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  content="$(cat "$sbx/bin/ocw" 2>/dev/null)"
  if [ -z "$content" ]; then
    fail "deploy 直後に $sbx/bin/ocw が読めること"
    return
  fi
  pass "deploy 直後に $sbx/bin/ocw が読める"

  # ソースツリー（コピー）を削除する。世代は cp -a による実体コピーなので、
  # 消えたソースツリーに依存していなければ $HOME 側は引き続き読めるはず
  # （ADR 問題2の回帰テスト）。
  rm -rf "$copy_dir"

  if [ "$(cat "$sbx/bin/ocw" 2>/dev/null)" = "$content" ]; then
    pass "ソースツリー削除後も $sbx/bin/ocw が同じ内容で読める（消失耐性）"
  else
    fail "ソースツリー削除後も $sbx/bin/ocw が同じ内容で読める（消失耐性）"
  fi
}

# ── シナリオ5: 編集分離（deploy後のソースツリー編集は即反映されない） ────

scenario_edit_isolation() {
  if ! has_tool bin; then
    return
  fi
  log "=== シナリオ5: 編集分離 + 再デプロイでの反映 ==="
  local sbx copy_dir out rc original marker

  new_sandbox
  sbx="$SANDBOX_DIR"
  copy_dir="$(mktemp -d)"
  CREATED_DIRS+=("$copy_dir")
  copy_repo_snapshot "$copy_dir"

  out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "コピーからの deploy-all.sh --only bin が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  original="$(cat "$sbx/bin/ocw" 2>/dev/null)"

  marker="# smoke-test marker $$"
  printf '%s\n' "$marker" >>"$copy_dir/bin/ocw"

  if [ "$(cat "$sbx/bin/ocw" 2>/dev/null)" = "$original" ]; then
    pass "deploy 後にソースツリーを書き換えても \$HOME 側の内容は変わらない（編集分離）"
  else
    fail "deploy 後にソースツリーを書き換えても \$HOME 側の内容は変わらない（編集分離）"
  fi

  # 世代IDは秒精度（<date>-<sha>）なので、同一秒内の再デプロイは世代が
  # 衝突しうる。秒が変わるまで待ってから再デプロイし、編集が反映される
  # ことを確認する。
  wait_for_next_second
  out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "2回目のコピーからの deploy-all.sh --only bin が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  if cat "$sbx/bin/ocw" 2>/dev/null | grep -qF "$marker"; then
    pass "再デプロイでソースツリーの編集が反映される"
  else
    fail "再デプロイでソースツリーの編集が反映される"
  fi
}

# ── シナリオ6: 世代の増加とGC ──────────────────────────────────────────

scenario_generation_gc() {
  if ! has_tool bin; then
    return
  fi
  log "=== シナリオ6: 世代の増加とGC ==="
  local sbx copy_dir prefix gen_count keep i out rc first_target cur_target

  new_sandbox
  sbx="$SANDBOX_DIR"
  copy_dir="$(mktemp -d)"
  CREATED_DIRS+=("$copy_dir")
  copy_repo_snapshot "$copy_dir"
  prefix="$(dotfiles_prefix_for "$sbx")"

  out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "1回目の deploy-all.sh --only bin が失敗 (exit=$rc)"
    log "$out"
    return
  fi
  first_target="$(current_target_for "$sbx")"

  wait_for_next_second
  out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "2回目の deploy-all.sh --only bin が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  gen_count="$(find "$prefix/generations" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  if [ "$gen_count" -eq 2 ]; then
    pass "再デプロイで世代が増える（既定の保持数では削除されない）: $gen_count 件"
  else
    fail "再デプロイで世代が増える（既定の保持数では削除されない）: 期待2件、実際 $gen_count 件"
  fi

  if [ -d "$first_target" ]; then
    pass "保持数を超えていない古い世代は削除されない: $first_target"
  else
    fail "保持数を超えていない古い世代は削除されない: $first_target"
  fi

  # --- 保持数を超えるとGCされ、current が指す世代は消えないこと ---
  keep=2
  EXTRA_ENV=("DOTFILES_KEEP_GENERATIONS=$keep")
  i=0
  while [ "$i" -lt 3 ]; do
    i=$((i + 1))
    wait_for_next_second
    out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --force --only bin 2>&1)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      fail "GC検証用の再デプロイが失敗 (exit=$rc)"
      log "$out"
      EXTRA_ENV=()
      return
    fi
  done
  EXTRA_ENV=()

  gen_count="$(find "$prefix/generations" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  if [ "$gen_count" -eq "$keep" ]; then
    pass "DOTFILES_KEEP_GENERATIONS=$keep を超えた古い世代がGCされる: $gen_count 件"
  else
    fail "DOTFILES_KEEP_GENERATIONS=$keep を超えた古い世代がGCされる: 期待${keep}件、実際 $gen_count 件"
  fi

  cur_target="$(current_target_for "$sbx")"
  if [ -d "$cur_target" ]; then
    pass "current が指す世代はGCされずに残っている: $cur_target"
  else
    fail "current が指す世代はGCされずに残っている: $cur_target"
  fi
}

# ── シナリオ7: 旧方式（直リンク）symlink の移行は退避されない ────────────

scenario_migration_no_backup_for_repo_owned_symlink() {
  if ! has_tool bin; then
    return
  fi
  log "=== シナリオ7: 旧方式(直リンク)symlinkの移行は退避されない ==="
  local sbx out rc

  new_sandbox
  sbx="$SANDBOX_DIR"
  mkdir -p "$sbx/bin"
  ln -s "$REPO_ROOT/bin/ocw" "$sbx/bin/ocw"

  out="$(run_deploy "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "旧方式リンクが存在する状態での deploy-all.sh --only bin が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  assert_symlink "$sbx/bin/ocw" "$(dotfiles_prefix_for "$sbx")/current/bin/ocw"
  assert_not_exists "$sbx/bin/ocw.backup"
}

# ── シナリオ8: 由来判定の偽陽性防止 + 単体実行時のcurrent不在エラー ─────

scenario_symlink_ownership_and_standalone_deploy() {
  if ! has_tool bin; then
    return
  fi
  log "=== シナリオ8: 由来判定の偽陽性防止 + 単体実行時のcurrent不在エラー ==="
  local sbx out rc prefix

  # --- 偽陽性防止: リポジトリ外を指す symlink は退避される ---
  new_sandbox
  sbx="$SANDBOX_DIR"
  mkdir -p "$sbx/bin"
  printf 'my-own-ocw\n' >"$sbx/my-own-ocw"
  ln -s "$sbx/my-own-ocw" "$sbx/bin/ocw"

  out="$(run_deploy "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "ユーザー所有symlinkが存在する状態での deploy-all.sh --only bin が失敗 (exit=$rc)"
    log "$out"
  else
    assert_exists "$sbx/bin/ocw.backup"
    if [ -L "$sbx/bin/ocw.backup" ] && [ "$(readlink "$sbx/bin/ocw.backup")" = "$sbx/my-own-ocw" ]; then
      pass "リポジトリ外を指すユーザー所有symlinkは退避される（偽陽性なし）: $sbx/bin/ocw.backup -> $sbx/my-own-ocw"
    else
      fail "リポジトリ外を指すユーザー所有symlinkは退避される（偽陽性なし）: $sbx/bin/ocw.backup -> $(readlink "$sbx/bin/ocw.backup" 2>/dev/null || echo '(symlinkでない)')"
    fi
    assert_symlink "$sbx/bin/ocw" "$(dotfiles_prefix_for "$sbx")/current/bin/ocw"
  fi

  # --- 単体実行: current が存在しない状態で bin/deploy.sh を直接実行するとエラー終了する ---
  new_sandbox
  sbx="$SANDBOX_DIR"
  sandbox_env "$sbx"
  out="$(env "${SANDBOX_ENV[@]}" DRY_RUN=1 sh "$REPO_ROOT/bin/deploy.sh" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "current が無い状態での bin/deploy.sh 単体実行はエラー終了する (exit=$rc)"
  else
    fail "current が無い状態での bin/deploy.sh 単体実行はエラー終了する (exit=0 になってしまった)"
  fi
  if printf '%s' "$out" | grep -q "does not exist yet"; then
    pass "current 不在時のエラーメッセージが表示される"
  else
    fail "current 不在時のエラーメッセージが表示される"
  fi

  # --- 単体実行: current がリンク切れのときは別のメッセージになる ---
  prefix="$(dotfiles_prefix_for "$sbx")"
  mkdir -p "$prefix"
  ln -s "$prefix/generations/does-not-exist" "$prefix/current"
  out="$(env "${SANDBOX_ENV[@]}" DRY_RUN=1 sh "$REPO_ROOT/bin/deploy.sh" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "current がリンク切れの状態での bin/deploy.sh 単体実行はエラー終了する (exit=$rc)"
  else
    fail "current がリンク切れの状態での bin/deploy.sh 単体実行はエラー終了する (exit=0 になってしまった)"
  fi
  if printf '%s' "$out" | grep -q "broken symlink"; then
    pass "current がリンク切れのときは『存在しない』ではなく『リンク切れ』のメッセージになる"
  else
    fail "current がリンク切れのときは『存在しない』ではなく『リンク切れ』のメッセージになる"
  fi
}

# ── シナリオ9: ソースツリー消失耐性(claude版) ──────────────────────────

scenario_claude_source_tree_disappears() {
  if ! has_tool claude; then
    return
  fi
  log "=== シナリオ9: ソースツリー消失耐性(claude版) ==="
  local sbx copy_dir out rc claude_md_content skill

  new_sandbox
  sbx="$SANDBOX_DIR"
  copy_dir="$(mktemp -d)"
  CREATED_DIRS+=("$copy_dir")
  copy_repo_snapshot "$copy_dir"

  out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --force --only claude 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "コピーからの deploy-all.sh --only claude が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  claude_md_content="$(cat "$sbx/.claude/CLAUDE.md" 2>/dev/null)"
  if [ -z "$claude_md_content" ]; then
    fail "deploy 直後に $sbx/.claude/CLAUDE.md が読めること"
    return
  fi
  pass "deploy 直後に $sbx/.claude/CLAUDE.md が読める"

  # ソースツリー(コピー)を削除する。世代は cp -a による実体コピーなので、
  # 消えたソースツリーに依存していなければ $HOME 側は引き続き読めるはず
  # (ADR 問題2の回帰テスト。claude 側は孫1では未対応だったため孫2で追加)。
  rm -rf "$copy_dir"

  if [ "$(cat "$sbx/.claude/CLAUDE.md" 2>/dev/null)" = "$claude_md_content" ]; then
    pass "ソースツリー削除後も \$HOME/.claude/CLAUDE.md が同じ内容で読める(消失耐性)"
  else
    fail "ソースツリー削除後も \$HOME/.claude/CLAUDE.md が同じ内容で読める(消失耐性)"
  fi

  while IFS= read -r skill; do
    [ -n "$skill" ] || continue
    if [ -d "$sbx/.claude/skills/$skill" ]; then
      pass "ソースツリー削除後も skill が読める: $skill"
    else
      fail "ソースツリー削除後も skill が読める: $skill"
    fi
  done <<EOF
$(list_repo_skills)
EOF
}

# ── シナリオ10: settings.machine.json が世代に入りマージが効く ───────────

scenario_claude_settings_machine_merge() {
  if ! has_tool claude; then
    return
  fi
  log "=== シナリオ10: settings.machine.json が世代に入りマージが効く ==="
  local sbx copy_dir out rc

  new_sandbox
  sbx="$SANDBOX_DIR"
  copy_dir="$(mktemp -d)"
  CREATED_DIRS+=("$copy_dir")
  copy_repo_snapshot "$copy_dir"

  # settings.machine.json は非追跡(.gitignore)だが、create_generation は
  # 作業ツリーのファイルコピー(cp -a)であって git archive ではないので、
  # このコピー側に置いたファイルも世代に入るはず(ADR §2.4)。
  cat >"$copy_dir/claude/settings.machine.json" <<'JSONEOF'
{
  "smokeTestMarker": "smoke-test-value"
}
JSONEOF

  out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --force --only claude 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "settings.machine.json 付きの deploy-all.sh --only claude が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  if grep -q "smokeTestMarker" "$sbx/.claude/settings.json" 2>/dev/null; then
    pass "非追跡の settings.machine.json が世代にコピーされ、マージ結果が settings.json に反映される"
  else
    fail "非追跡の settings.machine.json が世代にコピーされ、マージ結果が settings.json に反映される"
  fi

  # smokeTestMarker の有無だけでは、settings.machine.json を「マージ」でなく
  # 「丸ごとコピー」する実装に退化しても緑のままになってしまう。ベース設定
  # (claude/settings.json)側にしかないキーも一緒に残っていることを確認し、
  # 両方が合成された結果であることを検証する。
  if grep -q '"permissions"' "$sbx/.claude/settings.json" 2>/dev/null; then
    pass "ベース設定(claude/settings.json)側のキーもマージ後に残っている(丸ごと上書きされていない)"
  else
    fail "ベース設定(claude/settings.json)側のキーもマージ後に残っている(丸ごと上書きされていない)"
  fi
}

# ── シナリオ11: 旧方式(直リンク)skill symlinkの移行 + stale掃除(claude版) ──

scenario_claude_skill_migration() {
  if ! has_tool claude; then
    return
  fi
  log "=== シナリオ11: 旧方式(直リンク)skill symlinkの移行 + stale掃除(claude版) ==="
  local sbx out rc skill_name prefix

  new_sandbox
  sbx="$SANDBOX_DIR"
  mkdir -p "$sbx/.claude/skills"

  skill_name="$(list_repo_skills | head -n1)"
  if [ -z "$skill_name" ]; then
    log "  (claude/skills/ 配下にスキルが無いためスキップ)"
    return
  fi

  # 旧方式(作業ツリー直リンク)の skill symlink を再現する。current 経由へ
  # 配布元が変わったことで、claude/deploy.sh の「Already correct symlink?」
  # の判定に一致しなくなり、バックアップ処理へ落ちる経路を通る(ADR §4.9)。
  ln -s "$REPO_ROOT/claude/skills/$skill_name" "$sbx/.claude/skills/$skill_name"
  # 存在しないスキルを指す旧方式リンク(stale)も再現する。
  ln -s "$REPO_ROOT/claude/skills/smoke-test-gone-skill" "$sbx/.claude/skills/smoke-test-gone-skill"

  out="$(run_deploy "$sbx" --force --only claude 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "旧方式skillリンクが存在する状態での deploy-all.sh --only claude が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  prefix="$(dotfiles_prefix_for "$sbx")"
  assert_symlink "$sbx/.claude/skills/$skill_name" "$prefix/current/claude/skills/$skill_name"
  assert_not_exists "$sbx/.claude/skills-backup"

  if [ -L "$sbx/.claude/skills/smoke-test-gone-skill" ] || [ -e "$sbx/.claude/skills/smoke-test-gone-skill" ]; then
    fail "存在しないスキルを指す旧方式リンクが掃除される: $sbx/.claude/skills/smoke-test-gone-skill"
  else
    pass "存在しないスキルを指す旧方式リンクが掃除される"
  fi
}

# ── シナリオ12: デプロイ済み状態でのdry-runが作業ツリーへのリンクを提案しない ──

scenario_claude_dry_run_matches_deployed_state() {
  if ! has_tool claude; then
    return
  fi
  log "=== シナリオ12: デプロイ済み状態でのdry-runが作業ツリーへのリンクを提案しない ==="
  local sbx out rc

  new_sandbox
  sbx="$SANDBOX_DIR"

  out="$(run_deploy "$sbx" --force --only claude 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "claude の初回 deploy-all.sh --force が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  # 世代IDは秒精度なので、直後の --dry-run が同一秒に収まると世代ID衝突で
  # 意図と無関係に失敗する。秒が変わるまで待ってから実行する。
  wait_for_next_second

  # デプロイ済みの状態に対して --dry-run --only claude を実行する。既に
  # current 経由で正しくリンクされているはずなので、計画には何も変更が
  # 無いはず。出力に作業ツリー(REPO_ROOT)のパスが混ざっていたら、dry-run
  # が「作業ツリーへ張り替える」という誤った計画を出している証拠になる
  # (このPRが廃止しようとしている直リンク方式そのもの)。
  out="$(run_deploy "$sbx" --dry-run --only claude 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "デプロイ済み状態での deploy-all.sh --dry-run --only claude が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  # 出力全体には create_generation の DRY-RUN 計画(cp -a REPO_ROOT/<tool> ...)
  # が含まれ、これは作業ツリーのパスを含んでいて正常なので、出力全体に対して
  # grep すると必ず誤検知する。見るべきは symlink の向き先を報告する行だけ。
  if printf '%s' "$out" | grep -E "Would (symlink|replace)|Already linked" | grep -qF "$REPO_ROOT"; then
    fail "デプロイ済み状態でのdry-run計画のsymlink向き先に作業ツリーのパスが現れない"
    log "$out"
  else
    pass "デプロイ済み状態でのdry-run計画のsymlink向き先に作業ツリーのパスが現れない"
  fi

  if printf '%s' "$out" | grep -q "Already linked"; then
    pass "デプロイ済み状態でのdry-runは『既にリンク済み』と判定する(変更を提案しない)"
  else
    fail "デプロイ済み状態でのdry-runは『既にリンク済み』と判定する(変更を提案しない)"
  fi
}

# ── シナリオ13: current不在状態でのdry-runが配布実体の中身を計画できる ──

scenario_claude_dry_run_before_first_deploy() {
  if ! has_tool claude; then
    return
  fi
  log "=== シナリオ13: current不在状態でのdry-runが配布実体の中身を計画できる ==="
  local sbx copy_dir out rc skill prefix

  new_sandbox
  sbx="$SANDBOX_DIR"
  copy_dir="$(mktemp -d)"
  CREATED_DIRS+=("$copy_dir")
  copy_repo_snapshot "$copy_dir"

  # settings.machine.json を置いた状態で、まだ一度も deploy していない
  # (current が存在しない)サンドボックスに対して --dry-run を実行する。
  # ここが指摘1・6のバグが実際に発現していた条件そのもの: current が
  # 無い状態では配布実体がまだ存在しないため、-f/-d による実在性判定を
  # 素朴に配布実体へ向けると「マージ対象なし」「スキルなし」に見えて
  # しまう(指摘1)。逆にその回避として列挙元を作業ツリーに振ったせいで
  # リンクの向き先まで作業ツリーになってしまったのが指摘6。シナリオ12
  # は「デプロイ済み」状態しか見ないためこの分岐を一度も通らず、この
  # シナリオを置き換えではなく追加する。
  cat >"$copy_dir/claude/settings.machine.json" <<'JSONEOF'
{
  "smokeTestMarker": "smoke-test-value"
}
JSONEOF

  out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --dry-run --only claude 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "current不在状態での deploy-all.sh --dry-run --only claude が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  if printf '%s' "$out" | grep -q "Would merge settings.json + settings.machine.json"; then
    pass "current不在でもsettings.machine.jsonありなら『マージ』の計画になる(コピーに退化しない)"
  else
    fail "current不在でもsettings.machine.jsonありなら『マージ』の計画になる(コピーに退化しない)"
  fi

  while IFS= read -r skill; do
    [ -n "$skill" ] || continue
    if printf '%s' "$out" | grep -qF "Would symlink: $sbx/.claude/skills/$skill"; then
      pass "current不在でも配布対象のskillが計画に列挙される: $skill"
    else
      fail "current不在でも配布対象のskillが計画に列挙される: $skill"
    fi
  done <<EOF
$(list_repo_skills)
EOF

  # リンクの向き先は常に配布実体(current経由)でなければならない(指摘6の
  # 回帰)。列挙元だけ直っていてリンク先が作業ツリーのままの退化を検知
  # するため、Would symlink の行を配布実体prefixで確認する。
  prefix="$(dotfiles_prefix_for "$sbx")"
  if printf '%s' "$out" | grep "Would symlink:" | grep -qF "$prefix/current/claude/skills/"; then
    pass "current不在でもskillのリンク先は配布実体(current経由)になる"
  else
    fail "current不在でもskillのリンク先は配布実体(current経由)になる"
  fi
}

# ── シナリオ14: 配布実体(generations/current)の後片付け ─────────────────

scenario_distribution_artifact_cleanup() {
  if ! has_tool bin; then
    return
  fi
  log "=== シナリオ14: uninstallで配布実体(generations/current)が片付く ==="
  local sbx prefix out rc

  new_sandbox
  sbx="$SANDBOX_DIR"
  prefix="$(dotfiles_prefix_for "$sbx")"

  out="$(run_deploy "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "deploy-all.sh --force --only bin が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  if [ -d "$prefix/generations" ] && [ -L "$prefix/current" ]; then
    pass "deploy 直後は generations/ と current が存在する"
  else
    fail "deploy 直後は generations/ と current が存在する"
    return
  fi

  out="$(run_uninstall "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "uninstall.sh --force --only bin が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  assert_not_exists "$prefix/generations"
  assert_not_exists "$prefix/current"
  # generations/ と current だけでなく、prefix自体(.tmp/を含む)も片付く
  # ことを確認する。create_generation はビルド用scratchを
  # <prefix>/.tmp/ に作り(shared/helpers.sh)、成功時にgenerations/へ
  # mvするが .tmp ディレクトリ自体は残り続けるため、これを消し忘れると
  # prefixがいつまでも空にならない(rmdirが常に失敗する)。
  assert_not_exists "$prefix"
}

# ── シナリオ15: devモード(currentがソースツリーを指す)でのソースツリー保護 ──

scenario_dev_mode_source_tree_protection() {
  if ! has_tool bin; then
    return
  fi
  log "=== シナリオ15: devモードでのuninstallはcurrentが指すソースツリーを削除しない ==="
  local sbx dev_src prefix marker out rc copy_dir

  new_sandbox
  sbx="$SANDBOX_DIR"
  prefix="$(dotfiles_prefix_for "$sbx")"

  # 先に世代モードで一度 deploy し、generations/ に実体を作っておく。
  # 実運用でありうる「世代モードで運用したあと dev モードへ切り替えて
  # uninstall する」経路を再現する。dev モードの current は実運用でも
  # generations/ を経由しないので、この generations/ は dev モードに
  # 切り替えたあとに uninstall で消えるべき「片付け対象」であり、
  # 「消してはいけないソースツリー」とは別物であることを検証する。
  copy_dir="$(mktemp -d)"
  CREATED_DIRS+=("$copy_dir")
  copy_repo_snapshot "$copy_dir"
  out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "事前準備(世代モードでのdeploy-all.sh --force --only bin)が失敗 (exit=$rc)"
    log "$out"
    return
  fi
  if [ ! -d "$prefix/generations" ]; then
    fail "事前準備: generations/ が作られている"
    return
  fi
  pass "事前準備: 世代モードでdeployし、generations/ が存在する"

  dev_src="$(mktemp -d)"
  CREATED_DIRS+=("$dev_src")
  marker="dev-source-tree-marker-$$"
  printf '%s\n' "$marker" >"$dev_src/MARKER"

  # 孫4の --dev はまだ無いので、current を手でソースツリーへ向けて dev
  # モードを再現する(計画書 DOC-2608040234 孫3「dev モードの検証はサンド
  # ボックス内で current を手でソースツリーへ向ければよい」を参照)。
  ln -sfn "$dev_src" "$prefix/current"

  out="$(run_uninstall "$sbx" --force 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "devモード状態での uninstall.sh --force が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  if [ -d "$dev_src" ] && [ -f "$dev_src/MARKER" ] && [ "$(cat "$dev_src/MARKER")" = "$marker" ]; then
    pass "devモードのソースツリーはuninstallで削除されない(実体は無傷)"
  else
    fail "devモードのソースツリーはuninstallで削除されない(実体は無傷)"
  fi

  # ソースツリー自体は無傷である一方、current というリンク自体と
  # generations/ (dev モードのcurrentが指す先ではない、別に存在していた
  # 実体)は片付けられることを確認する。
  assert_not_exists "$prefix/current"
  assert_not_exists "$prefix/generations"
}

# ── シナリオ16: uninstall で ~/bin/ocw-meter が撤去される ────────────────

scenario_ocw_meter_removed_on_uninstall() {
  if ! has_tool bin; then
    return
  fi
  log "=== シナリオ16: uninstall で ~/bin/ocw-meter が撤去される ==="
  local sbx out rc

  new_sandbox
  sbx="$SANDBOX_DIR"

  out="$(run_deploy "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "deploy-all.sh --force --only bin が失敗 (exit=$rc)"
    log "$out"
    return
  fi
  assert_symlink "$sbx/bin/ocw-meter" "$(dotfiles_prefix_for "$sbx")/current/bin/ocw-meter"

  out="$(run_uninstall "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "uninstall.sh --force --only bin が失敗 (exit=$rc)"
    log "$out"
    return
  fi
  assert_not_exists "$sbx/bin/ocw-meter"
}

# ── シナリオ17: 新方式skillの撤去とskills-backupからの復元 ───────────────

scenario_claude_new_scheme_skill_removed_and_restored() {
  if ! has_tool claude; then
    return
  fi
  log "=== シナリオ17: 新方式skillのsymlinkが撤去され、元skillがskills-backupから復元される ==="
  local sbx prefix skill_name out rc backup_match

  new_sandbox
  sbx="$SANDBOX_DIR"
  prefix="$(dotfiles_prefix_for "$sbx")"

  skill_name="$(list_repo_skills | head -n1)"
  if [ -z "$skill_name" ]; then
    log "  (claude/skills/ 配下にスキルが無いためスキップ)"
    return
  fi

  mkdir -p "$sbx/.claude/skills/$skill_name"
  printf 'dummy-existing-skill\n' >"$sbx/.claude/skills/$skill_name/DUMMY_MARKER"

  out="$(run_deploy "$sbx" --force --only claude 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "deploy-all.sh --force --only claude が失敗 (exit=$rc)"
    log "$out"
    return
  fi
  assert_symlink "$sbx/.claude/skills/$skill_name" "$prefix/current/claude/skills/$skill_name"

  out="$(run_uninstall "$sbx" --force --only claude 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "uninstall.sh --force --only claude が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  if [ -d "$sbx/.claude/skills/$skill_name" ] && [ ! -L "$sbx/.claude/skills/$skill_name" ] && [ -f "$sbx/.claude/skills/$skill_name/DUMMY_MARKER" ]; then
    pass "新方式skillのsymlinkが撤去され、元skillがskills-backupから復元された: $sbx/.claude/skills/$skill_name"
  else
    fail "新方式skillのsymlinkが撤去され、元skillがskills-backupから復元された: $sbx/.claude/skills/$skill_name"
  fi

  backup_match=""
  for cand in "$sbx/.claude/skills-backup/$skill_name".*; do
    [ -e "$cand" ] && backup_match="$cand" && break
  done
  if [ -z "$backup_match" ]; then
    pass "復元後、skills-backup配下の退避データは残っていない(復元先へ移動済み)"
  else
    fail "復元後、skills-backup配下の退避データは残っていない(復元先へ移動済み): $backup_match が残存"
  fi

  # 退避データそのものだけでなく、空になった skills-backup ディレクトリ
  # 自体も片付くことを確認する。
  assert_not_exists "$sbx/.claude/skills-backup"
}

# ── シナリオ18: deployを介さない旧方式skillリンクもuninstallが撤去する ────

scenario_claude_old_scheme_skill_removed_by_uninstall() {
  if ! has_tool claude; then
    return
  fi
  log "=== シナリオ18: deployを介さない旧方式skillリンクもuninstallが撤去する ==="
  local sbx skill_name out rc

  new_sandbox
  sbx="$SANDBOX_DIR"
  mkdir -p "$sbx/.claude/skills"

  skill_name="$(list_repo_skills | head -n1)"
  if [ -z "$skill_name" ]; then
    log "  (claude/skills/ 配下にスキルが無いためスキップ)"
    return
  fi

  # deploy.sh を一度も実行していない(=新方式へ移行する前の)状態を再現する。
  # 作業ツリーを直接指す旧方式のskillリンクを手で張る。
  ln -s "$REPO_ROOT/claude/skills/$skill_name" "$sbx/.claude/skills/$skill_name"

  out="$(run_uninstall "$sbx" --force --only claude 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "旧方式skillリンクのみが存在する状態での uninstall.sh --force --only claude が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  assert_not_exists "$sbx/.claude/skills/$skill_name"
}

# ── シナリオ19: スコープ外ツールが参照している間は配布実体の後片付けをスキップする ──

scenario_cleanup_skipped_while_other_tool_in_scope() {
  if ! has_tool bin || ! has_tool claude; then
    return
  fi
  log "=== シナリオ19: bin,claudeをdeployし、binだけuninstallしても配布実体は残る(claudeがまだ参照している) ==="
  local sbx prefix out rc skill_name

  new_sandbox
  sbx="$SANDBOX_DIR"
  prefix="$(dotfiles_prefix_for "$sbx")"

  skill_name="$(list_repo_skills | head -n1)"

  out="$(run_deploy "$sbx" --force --only bin,claude 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "deploy-all.sh --force --only bin,claude が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  out="$(run_uninstall "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "uninstall.sh --force --only bin が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  assert_not_exists "$sbx/bin/ocw"
  if [ -d "$prefix/generations" ] && [ -L "$prefix/current" ]; then
    pass "claudeがまだ配布実体を参照しているため、bin単独のuninstallでは配布実体が残る"
  else
    fail "claudeがまだ配布実体を参照しているため、bin単独のuninstallでは配布実体が残る"
  fi
  if [ -n "$skill_name" ]; then
    assert_symlink "$sbx/.claude/skills/$skill_name" "$prefix/current/claude/skills/$skill_name"
  fi

  # claude も uninstall してはじめて、どのツールも配布実体を参照しなくなり
  # 後片付けが実行される。
  out="$(run_uninstall "$sbx" --force --only claude 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "uninstall.sh --force --only claude が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  assert_not_exists "$prefix/generations"
  assert_not_exists "$prefix/current"
}

# ── シナリオ20: symlink撤去に失敗した場合は配布実体を残す ────────────────

scenario_cleanup_skipped_when_symlink_removal_fails() {
  if ! has_tool bin; then
    return
  fi
  log "=== シナリオ20: symlinkの撤去に失敗した場合、配布実体を消さず生き残ったリンクをリンク切れにしない ==="
  local sbx prefix out rc

  new_sandbox
  sbx="$SANDBOX_DIR"
  prefix="$(dotfiles_prefix_for "$sbx")"

  out="$(run_deploy "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "deploy-all.sh --force --only bin が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  # ~/bin を書き込み不可にして、symlinkの削除(rm)自体を失敗させる。
  chmod 555 "$sbx/bin"

  out="$(run_uninstall "$sbx" --force --only bin 2>&1)"
  rc=$?

  # trap cleanup がサンドボックスを削除できるよう、権限を元に戻す。
  chmod 755 "$sbx/bin"

  if [ "$rc" -eq 0 ]; then
    fail "symlink削除に失敗する状況でuninstall.shがエラー終了する (exit=0になってしまった)"
    log "$out"
    return
  fi
  pass "symlink削除に失敗する状況でuninstall.shがエラー終了する (exit=$rc)"

  if [ -L "$sbx/bin/ocw" ]; then
    pass "削除に失敗したsymlinkは(壊れずに)残っている"
  else
    fail "削除に失敗したsymlinkは(壊れずに)残っている"
  fi

  if [ -d "$prefix/generations" ] && [ -L "$prefix/current" ]; then
    pass "symlinkの撤去に失敗した場合、配布実体は消されずに残る(生き残ったリンクをリンク切れにしない)"
  else
    fail "symlinkの撤去に失敗した場合、配布実体は消されずに残る(生き残ったリンクをリンク切れにしない)"
  fi
}

# ── シナリオ21: 配布実体後片付けのdry-run出力が実際の挙動と一致する ────────

scenario_cleanup_dry_run_matches_reality() {
  if ! has_tool bin; then
    return
  fi
  log "=== シナリオ21: 配布実体後片付けのdry-run出力が実際の挙動と一致する ==="
  local sbx prefix out rc

  new_sandbox
  sbx="$SANDBOX_DIR"
  prefix="$(dotfiles_prefix_for "$sbx")"

  out="$(run_deploy "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "deploy-all.sh --force --only bin が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  out="$(run_uninstall "$sbx" --dry-run --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "uninstall.sh --dry-run --only bin が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  if [ -d "$prefix/generations" ] && [ -L "$prefix/current" ]; then
    pass "--dry-runでは配布実体が実際には消えない"
  else
    fail "--dry-runでは配布実体が実際には消えない"
  fi

  if printf '%s' "$out" | grep -qF "[DRY-RUN] rm -rf $prefix/generations"; then
    pass "dry-run出力にgenerationsの削除計画が含まれる"
  else
    fail "dry-run出力にgenerationsの削除計画が含まれる"
    log "$out"
  fi

  # --- generations が(何らかの理由で)symlinkだった場合、dry-runでも
  #     実行時と同じ拒否になること(create_generationのid衝突チェックが
  #     dry-runでも実行時と同じ失敗を報告する方針に揃える) ---
  new_sandbox
  sbx="$SANDBOX_DIR"
  prefix="$(dotfiles_prefix_for "$sbx")"
  out="$(run_deploy "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "2回目のdeploy-all.sh --force --only bin が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  rm -rf "$prefix/generations"
  ln -s "$sbx" "$prefix/generations"

  out="$(run_uninstall "$sbx" --dry-run --only bin 2>&1)"
  if printf '%s' "$out" | grep -q "Refusing to remove a symlink"; then
    pass "generationsがsymlinkの場合、dry-runでも実行時と同じ拒否メッセージになる"
  else
    fail "generationsがsymlinkの場合、dry-runでも実行時と同じ拒否メッセージになる"
    log "$out"
  fi
  rm -f "$prefix/generations"
}

# ── シナリオ22: generations/もcurrentも無くscratchだけが残っていても片付く ──

scenario_cleanup_removes_orphaned_scratch_without_generation() {
  log "=== シナリオ22: generations/もcurrentも無く.tmp/のscratchだけが残っている状態でもuninstallで片付く ==="
  local sbx prefix out rc

  new_sandbox
  sbx="$SANDBOX_DIR"
  prefix="$(dotfiles_prefix_for "$sbx")"

  # 初回deployがコピー中に中断された状態を再現する: create_generation
  # (shared/helpers.sh)のscratch(.tmp/gen.XXXXXX)だけが残り、コピー完了後に
  # mvされるはずの generations/ も switch_current が作る current も
  # まだ存在しない。
  mkdir -p "$prefix/.tmp/gen.CRASH1/bin"
  printf 'dummy\n' >"$prefix/.tmp/gen.CRASH1/bin/ocw"

  out="$(run_uninstall "$sbx" --force 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "uninstall.sh --force が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  assert_not_exists "$prefix"
}

# ── シナリオ23: --status ────────────────────────────────────────────────

scenario_status() {
  if ! has_tool bin; then
    return
  fi
  log "=== シナリオ23: --status ==="
  local sbx prefix out rc

  new_sandbox
  sbx="$SANDBOX_DIR"
  prefix="$(dotfiles_prefix_for "$sbx")"

  out="$(run_deploy "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "deploy-all.sh --force --only bin が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  out="$(run_deploy "$sbx" --status 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "--status が成功終了する (exit=$rc)"
    log "$out"
  else
    pass "--status が成功終了する"
  fi

  if printf '%s' "$out" | grep -q "Mode: generation"; then
    pass "--status がgenerationモードを表示する"
  else
    fail "--status がgenerationモードを表示する"
  fi

  if printf '%s' "$out" | grep -q "^  commit_sha: "; then
    pass "--status がmanifestのcommit_shaを表示する"
  else
    fail "--status がmanifestのcommit_shaを表示する"
  fi

  if printf '%s' "$out" | grep -q "(current)"; then
    pass "--status が世代一覧でcurrentを明示する"
  else
    fail "--status が世代一覧でcurrentを明示する"
  fi

  if printf '%s' "$out" | grep -qE "\[OK\][[:space:]]+$sbx/bin/ocw$"; then
    pass "--status がリンク健全性をOKと報告する"
  else
    fail "--status がリンク健全性をOKと報告する"
  fi

  # --- リンク切れを作ると検出されること ---
  rm -f "$sbx/bin/ocw-meter"
  ln -s "$prefix/current/bin/does-not-exist" "$sbx/bin/ocw-meter"

  out="$(run_deploy "$sbx" --status 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "リンク切れがあると--statusが非0で終了する (exit=$rc)"
  else
    fail "リンク切れがあると--statusが非0で終了する (exit=0のままだった)"
  fi
  if printf '%s' "$out" | grep -qE "\[BROKEN\][[:space:]]+$sbx/bin/ocw-meter"; then
    pass "--status がリンク切れを検出する"
  else
    fail "--status がリンク切れを検出する"
  fi
}

# ── シナリオ24: --rollback ──────────────────────────────────────────────

scenario_rollback() {
  if ! has_tool bin; then
    return
  fi
  log "=== シナリオ24: --rollback ==="
  local sbx copy_dir prefix out rc gen1_content gen2_content gen2_target marker

  new_sandbox
  sbx="$SANDBOX_DIR"
  copy_dir="$(mktemp -d)"
  CREATED_DIRS+=("$copy_dir")
  copy_repo_snapshot "$copy_dir"
  prefix="$(dotfiles_prefix_for "$sbx")"

  out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "1回目の deploy-all.sh --only bin が失敗 (exit=$rc)"
    log "$out"
    return
  fi
  gen1_content="$(cat "$sbx/bin/ocw" 2>/dev/null)"

  marker="# smoke-test rollback marker $$"
  printf '%s\n' "$marker" >>"$copy_dir/bin/ocw"

  wait_for_next_second
  out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "2回目の deploy-all.sh --only bin が失敗 (exit=$rc)"
    log "$out"
    return
  fi
  gen2_content="$(cat "$sbx/bin/ocw" 2>/dev/null)"
  gen2_target="$(current_target_for "$sbx")"

  if printf '%s' "$gen2_content" | grep -qF "$marker"; then
    pass "2回目のdeployでソースツリーの編集内容が反映されている（rollback検証の前提）"
  else
    fail "2回目のdeployでソースツリーの編集内容が反映されている（rollback検証の前提）"
    return
  fi

  # --- --dry-run は current を実際には変更しない ---
  out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --rollback --dry-run 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "--rollback --dry-run が失敗 (exit=$rc)"
    log "$out"
  elif printf '%s' "$out" | grep -q '\[DRY-RUN\]'; then
    pass "--rollback --dry-run はDRY-RUN出力になる"
  else
    fail "--rollback --dry-run はDRY-RUN出力になる"
  fi
  if [ "$(current_target_for "$sbx")" = "$gen2_target" ]; then
    pass "--rollback --dry-run はcurrentを実際には変更しない"
  else
    fail "--rollback --dry-run はcurrentを実際には変更しない"
  fi

  # --- 実際にrollbackする ---
  out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --rollback 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "--rollback が失敗 (exit=$rc)"
    log "$out"
    return
  fi
  pass "--rollback が成功する"

  if [ "$(cat "$sbx/bin/ocw" 2>/dev/null)" = "$gen1_content" ]; then
    pass "rollbackで\$HOME側から読める内容が前の世代のものに戻る（symlinkは張り直さない）"
  else
    fail "rollbackで\$HOME側から読める内容が前の世代のものに戻る（symlinkは張り直さない）"
  fi

  # $HOME 側の symlink 自体は current という固定パスを指したまま変わらない
  # ことも確認する（current の付け替えだけで向き先が変わる、が世代方式の要）。
  assert_symlink "$sbx/bin/ocw" "$prefix/current/bin/ocw"

  # --- これ以上戻れない場合は明確なエラーになる ---
  out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --rollback 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "戻せる世代が無い場合はエラー終了する (exit=$rc)"
  else
    fail "戻せる世代が無い場合はエラー終了する (exit=0になってしまった)"
  fi
  if printf '%s' "$out" | grep -q "No older generation"; then
    pass "戻せる世代が無い場合のエラーメッセージが表示される"
  else
    fail "戻せる世代が無い場合のエラーメッセージが表示される"
  fi
}

# ── シナリオ25: --dev ───────────────────────────────────────────────────

scenario_dev_mode() {
  if ! has_tool bin; then
    return
  fi
  log "=== シナリオ25: --dev ==="
  local sbx copy_dir prefix out rc marker gen_count_before gen_count_after

  new_sandbox
  sbx="$SANDBOX_DIR"
  copy_dir="$(mktemp -d)"
  CREATED_DIRS+=("$copy_dir")
  copy_repo_snapshot "$copy_dir"
  prefix="$(dotfiles_prefix_for "$sbx")"

  out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "事前準備(1回目のdeploy-all.sh --only bin)が失敗 (exit=$rc)"
    log "$out"
    return
  fi

  wait_for_next_second
  out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --force --only bin 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "事前準備(2回目のdeploy-all.sh --only bin)が失敗 (exit=$rc)"
    log "$out"
    return
  fi
  gen_count_before="$(find "$prefix/generations" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"

  # --- --dry-run は current を実際には変更しない ---
  out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --dev --dry-run 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "--dev --dry-run が失敗 (exit=$rc)"
    log "$out"
  fi
  case "$(current_target_for "$sbx")" in
    "$prefix/generations"/*)
      pass "--dev --dry-run はcurrentを実際には変更しない"
      ;;
    *)
      fail "--dev --dry-run はcurrentを実際には変更しない"
      ;;
  esac

  # --- 実際に dev モードへ切り替える ---
  out="$(run_deploy_from "$copy_dir/deploy-all.sh" "$sbx" --dev 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "--dev が失敗 (exit=$rc)"
    log "$out"
    return
  fi
  pass "--dev が成功する"

  if [ "$(current_target_for "$sbx")" = "$copy_dir" ]; then
    pass "--dev でcurrentがソースツリーを指す"
  else
    fail "--dev でcurrentがソースツリーを指す (実際: $(current_target_for "$sbx"))"
  fi

  marker="# smoke-test dev marker $$"
  printf '%s\n' "$marker" >>"$copy_dir/bin/ocw"

  if cat "$sbx/bin/ocw" 2>/dev/null | grep -qF "$marker"; then
    pass "devモードではソースツリーの書き換えが\$HOME側へ即座に反映される"
  else
    fail "devモードではソースツリーの書き換えが\$HOME側へ即座に反映される"
  fi

  # --- devモード中はGCで世代が削除されないことを直接gc_generationsで検証する ---
  # deploy-all.sh の通常フロー（--dev/--status/--rollback以外）は
  # switch_current で必ずcurrentを新世代へ切り替えてからgc_generationsを
  # 呼ぶため、この不変条件（shared/helpers.shのgc_generations、孫1実装）を
  # 実際にdevモードのまま踏むには直接呼び出すしかない。
  sandbox_env "$sbx"
  env "${SANDBOX_ENV[@]}" DOTFILES_KEEP_GENERATIONS=1 sh -c '. "'"$REPO_ROOT"'/shared/helpers.sh" && gc_generations' >/dev/null 2>&1
  gen_count_after="$(find "$prefix/generations" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  if [ "$gen_count_after" = "$gen_count_before" ]; then
    pass "devモード中はDOTFILES_KEEP_GENERATIONSを絞ってもGCで世代が削除されない: $gen_count_after 件のまま"
  else
    fail "devモード中はDOTFILES_KEEP_GENERATIONSを絞ってもGCで世代が削除されない: 期待${gen_count_before}件、実際 $gen_count_after 件"
  fi
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
scenario_source_tree_disappears
log
scenario_edit_isolation
log
scenario_generation_gc
log
scenario_migration_no_backup_for_repo_owned_symlink
log
scenario_symlink_ownership_and_standalone_deploy
log
scenario_claude_source_tree_disappears
log
scenario_claude_settings_machine_merge
log
scenario_claude_skill_migration
log
scenario_claude_dry_run_matches_deployed_state
log
scenario_claude_dry_run_before_first_deploy
log
scenario_distribution_artifact_cleanup
log
scenario_dev_mode_source_tree_protection
log
scenario_ocw_meter_removed_on_uninstall
log
scenario_claude_new_scheme_skill_removed_and_restored
log
scenario_claude_old_scheme_skill_removed_by_uninstall
log
scenario_cleanup_skipped_while_other_tool_in_scope
log
scenario_cleanup_skipped_when_symlink_removal_fails
log
scenario_cleanup_dry_run_matches_reality
log
scenario_cleanup_removes_orphaned_scratch_without_generation
log
scenario_status
log
scenario_rollback
log
scenario_dev_mode
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
