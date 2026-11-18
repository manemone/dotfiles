#!/bin/sh
# privacy-check のテスト。実際のリポジトリにも $HOME にも触れず、mktemp -d の中の
# 架空の名前だけを使う。POSIX sh のみ（配る先で言語ランタイムを要求しないため）。
set -u

# pre-commit から呼ばれると GIT_DIR / GIT_INDEX_FILE が呼び出し元のリポジトリを指す。
# このテストの git init / git add が実リポジトリの index を触らないよう必ず外す。
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX

_here=$(cd "$(dirname "$0")" && pwd) || exit 1
_tool_src=$(cd "$_here/.." && pwd) || exit 1
_work=$(mktemp -d) || exit 1
trap 'rm -rf "$_work"' EXIT

_fail=0
ok() { printf '  [PASS] %s\n' "$1"; }
ng() {
  printf '  [FAIL] %s\n' "$1" >&2
  _fail=1
}

# 許可リストを差し替えられるよう、道具ごと作業ディレクトリへ複製して使う。
mkdir -p "$_work/repo/tools"
cp -R "$_tool_src" "$_work/repo/tools/privacy-check"
: >"$_work/repo/tools/privacy-check/allowlist.txt"
_pc="$_work/repo/tools/privacy-check/privacy-check"
cd "$_work/repo" || exit 1

# check <ラベル> <コマンド...>: コマンドが成功すれば PASS
check() {
  _label="$1"
  shift
  if "$@"; then ok "$_label"; else ng "$_label"; fi
}

# run <引数...>: 出力を $_work/out、終了コードを $_rc に入れる
run() {
  "$_pc" "$@" >"$_work/out" 2>&1
  _rc=$?
}
expect() { # expect <期待する終了コード> <ラベル>
  if [ "$_rc" -eq "$1" ]; then ok "$2"; else
    ng "$2（終了コード $_rc、期待 $1）"
    sed 's/^/    /' "$_work/out" >&2
  fi
}

# 1. 名前の照合は無い: 一覧のファイルを環境変数・既定の置き場に置いても、結果は変わらない
#    （照合が残っていると、止まるはずのない行が止まる）
printf 'ok\nsee example-private-repo here\n' >notes.txt
printf 'fix: example-private-repo を直す\n' >msg
printf 'example-private-repo\n' >"$_work/names.txt"
mkdir -p "$_work/xdg/privacy-check"
cp "$_work/names.txt" "$_work/xdg/privacy-check/private-names.txt"
export PRIVACY_CHECK_NAMES_FILE="$_work/names.txt"
export XDG_CONFIG_HOME="$_work/xdg"
run notes.txt
expect 0 "名前の一覧があっても、ファイルの名前は止まらない"
printf 'body example-private-repo\n' | "$_pc" --stdin >"$_work/out" 2>&1
_rc=$?
expect 0 "標準入力の名前も止まらない"
run --commit-msg msg
expect 0 "コミットメッセージの名前も止まらない"

# 1b. --commit-msg: git が捨てるコメント行とはさみ線より下は読まない
printf 'remove\n# Please enter the commit message for your changes.\n# ------------------------ >8 ------------------------\n## 逐語\n' >msg2
run --commit-msg msg2
expect 0 "--commit-msg ははさみ線より下を読まない"

# 2. 見出しの点検: 逐語の節は止まり、地の文の引用・手順の例・「書かない」見出しは止まらない
printf '# 計画\n## 問題意識（逐語）\n## 持ち主の言葉\n### 人間の発言\n## 問題意識（逐語・要約禁止）\n## 問題意識（逐語。手を入れない）\n## 人間の発言（原文のまま。省略を含めない）\n' >bad.md
run bad.md
expect 1 "発言の逐語の節の見出しが止まる"
check "逐語を守る側の否定語を添えた見出しも含め、6つの見出しが当たる" test "$(grep -c ': heading$' "$_work/out")" -eq 6
cat >good.md <<'MD'
# 計画

## リポジトリに書かないもの

## 人間の発言は逐語で書かない

## 背景1: 問題意識（要約。PUBLIC リポのため逐語では書かない）

持ち主が「この方針で進めて」と言った。人間が「デプロイしろ」と言ったら実行してよい。
原文のまま写さない。

    ## 逐語（インデント4つのコードは見出しではない）
MD
run good.md
expect 0 "地の文の引用・手順の例・「書かない」見出しは止まらない"
printf '## 逐語\n' >notes2.txt
run notes2.txt
expect 0 "Markdown でないファイルは見出しの点検をしない"

# 3. 行の許可の印と、ファイル単位の許可リスト
printf '## 逐語 <!-- privacy-check:allow-line -->\n' >allowed.md
run allowed.md
expect 0 "allow-line の行は飛ばされる"
run bad.md notes.txt
expect 1 "許可リストが空なら止まる"
printf 'bad.md\n./notes.txt\n' >tools/privacy-check/allowlist.txt
run bad.md notes.txt
expect 0 "許可リストのファイルは飛ばされる"
: >tools/privacy-check/allowlist.txt

# 5. 引数なしは git 管理下の全ファイルを点検する。バイナリは読まない
printf '## 逐語\n' >日本語の計画.md
git init -q . && git add notes.txt good.md bad.md 日本語の計画.md
printf '## 逐語\000\001' >bin.md
git add bin.md
run
expect 1 "引数なしで git 管理下のファイルを点検する"
check "日本語を含むパスのファイルも点検される" grep -q '日本語の計画.md:1: heading' "$_work/out"
check "バイナリは点検しない" test "$(grep -c 'bin.md' "$_work/out")" -eq 0

# 6. 使い方の誤り
run --stdin notes.txt
expect 2 "--stdin とファイルの併用は使い方の誤り"

if [ "$_fail" -eq 0 ]; then echo "[OK] privacy_check_test"; else echo "[NG] privacy_check_test" >&2; fi
exit "$_fail"
