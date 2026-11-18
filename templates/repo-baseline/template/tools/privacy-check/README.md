# privacy-check

人間の発言の逐語を載せる節の見出しと、非公開の名前を、コミットの時点で止める点検。
言語ランタイムを要求しない（POSIX sh と awk だけ）。`templates/repo-baseline` で他のリポジトリへも配る。

## 使い方

```sh
tools/privacy-check/privacy-check [<file> ...]   # 引数が無ければ git 管理下の全ファイル
tools/privacy-check/privacy-check --stdin        # 標準入力（PR の本文など、ファイルにならないもの）
tools/privacy-check/privacy-check --commit-msg <file>   # コミットメッセージのファイル（commit-msg 段）
```

`--commit-msg` は git が捨てる行を読まない。はさみ線（`git commit -v` の差分の手前）より下は常に読まない。
行頭がコメント文字（`core.commentChar`、既定 `#`）の行は、エディタを開いたときの案内
（`Please enter the commit message` の行）がファイルにあるときだけ読まない。`-m` / `-F` のコミットでは
`#` で始まる行もメッセージに残るので、そのまま点検する。

ヒットは `<path>:<行番号>: <heading|name>` の形で出し、ヒットがあれば終了コード 1、無ければ 0。
**名前の一覧に当たった語そのものは出力しない**（CI のログや PR のコメントへ写らないように。行番号で見に行く）。

## 2つの点検

| 点検 | 対象 | 止めるもの |
|---|---|---|
| `heading` | Markdown（`*.md` / `*.markdown` と標準入力）の見出し行 | 発言をそのまま載せる節であることを示す語（スクリプトの中の一覧）を含む見出し。「書かない」「写さない」など書かないことを述べる見出しは止めない |
| `name` | すべてのテキストファイルと標準入力 | 名前の一覧に載った語（大文字小文字を区別しない部分一致） |

地の文は見ない。文中の引用と手順の例として書いた文は、語や記号の並びでは区別できないため。
コードブロックの中の見出しも点検する（計画書に入れた孫のプロンプトはコードブロックの中にあるため）。

## 非公開の名前の一覧

一覧はリポジトリの中に置かない。置き場は次のどちらか。

- 環境変数 `PRIVACY_CHECK_NAMES_FILE` が指すファイル
- `${XDG_CONFIG_HOME:-$HOME/.config}/privacy-check/private-names.txt`

1行1語。`#` から行末はコメント、空行は無視する。ファイルが無ければ名前の点検は黙って飛ばし、
見出しの点検だけを行う。CI にはこの一覧が無いので、名前の点検が効くのは手元のコミットだけである。

```sh
mkdir -p ~/.config/privacy-check
$EDITOR ~/.config/privacy-check/private-names.txt
```

## 許可

- 行: 行に `privacy-check:allow-line` があれば、その行は両方の点検で飛ばす
- ファイル: このディレクトリの `allowlist.txt` に、リポジトリのルートからの相対パスを1行1つ書く。
  ディレクトリ丸ごとの除外はできない。足すのは最小限にし、理由を PR に書く

## pre-commit への登録

`pre-commit` 段（ファイル）と `commit-msg` 段（コミットメッセージのファイル）の両方に登録する。
`commit-msg` 段は次を一度実行しないと効かない。

```sh
pre-commit install --hook-type commit-msg
```

## テスト

```sh
tools/privacy-check/test/privacy_check_test.sh
```

実際のリポジトリにも `$HOME` にも触れず、`mktemp -d` の中の架空の一覧だけを使う。
