#!/bin/sh
# privacy-check のテスト。実際のリポジトリにも $HOME にも触れず、mktemp -d の中の
# 架空の名前の一覧だけを使う。POSIX sh のみ（配る先で言語ランタイムを要求しないため）。
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

printf '# 架空の一覧\nexample-private-repo  # コメント\n\nexample-host.internal\n' >"$_work/names.txt"
export PRIVACY_CHECK_NAMES_FILE="$_work/names.txt"

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

# 1. 名前の一覧に載った語が、ファイル・標準入力・コミットメッセージ（.md でないファイル）で止まり、
#    出力に語そのものが出ない。大文字小文字は区別しない
printf 'ok\nsee Example-Private-Repo here\n' >notes.txt
printf 'fix: example-host.internal を直す\n' >msg
run notes.txt
expect 1 "ファイルの名前のヒットが止まる"
if grep -q 'notes.txt:2: name' "$_work/out" && ! grep -qi example "$_work/out"; then
  ok "出力に行番号が出て、当たった語は出ない"
else
  ng "出力に行番号が出て、当たった語は出ない"
fi
run msg
expect 1 "コミットメッセージのファイルの名前のヒットが止まる"
printf 'body example-private-repo\n' | "$_pc" --stdin >"$_work/out" 2>&1
_rc=$?
expect 1 "標準入力の名前のヒットが止まる"
check "標準入力の出力は <stdin>:行:name" grep -q '^<stdin>:1: name$' "$_work/out"

# 1b. --commit-msg: git が捨てるコメント行とはさみ線より下は読まず、本文は読む
printf 'remove the name\n# Please enter the commit message for your changes.\n# example-private-repo in a comment\n# ------------------------ >8 ------------------------\n-example-private-repo removed line\n' >msg2
run --commit-msg msg2
expect 0 "--commit-msg はコメント行とはさみ線より下の名前で止めない"
printf 'fix example-private-repo\n# comment\n' >msg3
run --commit-msg msg3
expect 1 "--commit-msg でも本文の名前は止まる"
printf 'fix\n\n#2 example-private-repo の設定を直す\n' >msg4
run --commit-msg msg4
expect 1 "案内のコメントが無い（-m / -F）メッセージの # 行の名前は止まる"

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
printf '## 逐語 <!-- privacy-check:allow-line -->\nexample-private-repo # privacy-check:allow-line\n' >allowed.md
run allowed.md
expect 0 "allow-line の行は両方の点検で飛ばされる"
run bad.md notes.txt
expect 1 "許可リストが空なら止まる"
printf 'bad.md\n./notes.txt\n' >tools/privacy-check/allowlist.txt
run bad.md notes.txt
expect 0 "許可リストのファイルは飛ばされる"
: >tools/privacy-check/allowlist.txt

# 4. 名前の一覧が無ければ名前の点検だけが黙って飛ばされ、見出しの点検は走る
PRIVACY_CHECK_NAMES_FILE="$_work/none.txt" run notes.txt
expect 0 "一覧が無いとき、名前は飛ばされて通る"
PRIVACY_CHECK_NAMES_FILE="$_work/none.txt" run bad.md
expect 1 "一覧が無くても見出しの点検は走る"
# 既定の置き場: PRIVACY_CHECK_NAMES_FILE を使わず XDG_CONFIG_HOME から読む
mkdir -p "$_work/xdg/privacy-check"
cp "$_work/names.txt" "$_work/xdg/privacy-check/private-names.txt"
(
  unset PRIVACY_CHECK_NAMES_FILE
  XDG_CONFIG_HOME="$_work/xdg" "$_pc" notes.txt >"$_work/out" 2>&1
)
_rc=$?
expect 1 "既定の置き場（XDG_CONFIG_HOME 配下）の一覧を読む"

# 5. 引数なしは git 管理下の全ファイルを点検する。バイナリは読まない
printf '## 逐語\n' >日本語の計画.md
git init -q . && git add notes.txt good.md bad.md 日本語の計画.md
printf 'example-private-repo\000\001' >bin.dat
git add bin.dat
run
expect 1 "引数なしで git 管理下のファイルを点検する"
check "日本語を含むパスのファイルも点検される" grep -q '日本語の計画.md:1: heading' "$_work/out"
check "バイナリは点検しない" test "$(grep -c 'bin.dat' "$_work/out")" -eq 0

# 6. 使い方の誤り
run --stdin notes.txt
expect 2 "--stdin とファイルの併用は使い方の誤り"

if [ "$_fail" -eq 0 ]; then echo "[OK] privacy_check_test"; else echo "[NG] privacy_check_test" >&2; fi
exit "$_fail"
