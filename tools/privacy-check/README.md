# privacy-check

人間の発言の逐語を載せる節の見出しを、コミットの時点で止める点検。
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

ヒットは `<path>:<行番号>: heading` の形で出し、ヒットがあれば終了コード 1、無ければ 0。

## 点検するもの

| 点検 | 対象 | 止めるもの |
|---|---|---|
| `heading` | Markdown（`*.md` / `*.markdown` と標準入力）の見出し行 | 発言をそのまま載せる節であることを示す語（スクリプトの中の一覧）を含む見出し。「書かない」「写さない」など書かないことを述べる見出しは止めない |

地の文は見ない。文中の引用と手順の例として書いた文は、語や記号の並びでは区別できないため。
コードブロックの中の見出しも点検する（計画書に入れた孫のプロンプトはコードブロックの中にあるため）。

## 非公開の名前は照合しない

非公開のリポジトリ・ホストの名前は、機械では照合しない。名前の一覧を作って突き合わせる方法は、一覧が名前の
置き場になるうえ、載っていない名前を止められないので採らなかった。名前の流出は、書かないという決まりと、
レビューで差分・PR の本文・コミットメッセージを意味で読んで指摘することで止める（ADR DOC-2611181132）。

## 許可

- 行: 行に `privacy-check:allow-line` があれば、その行は飛ばす
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
