# シェルスクリプトコーディング方針

この文書は `dotfiles` に参加する人間と AI の両方が持つべき、シェルスクリプトの書き方の基準をまとめたものです。

shellcheck / shfmt が機械的に検出できるものはそちらに委ねます。ここでは linter では判定できない
「書き方の思想」と、このリポジトリの既存慣行を説明します。

## 1. 方言の使い分け（最重要）

このリポジトリは POSIX sh と bash を意図的に使い分けています。実際のファイルの shebang と一致させること。

| 対象 | 方言 | 理由 |
|---|---|---|
| `shared/helpers.sh` | POSIX sh（`#!/bin/sh`） | 全 deploy スクリプトから source される。最大公約数の方言でなければ動かない環境がある |
| `deploy-all.sh` / `uninstall.sh` / `*/deploy.sh` | POSIX sh（`#!/bin/sh`） | ブートストラップ時点で bash が入っているとは限らない |
| `bin/ocw` / `bin/claude-ds` | bash（`#!/usr/bin/env bash`） | デプロイ後にユーザーの PATH 経由で実行されるツール。bash 前提でよい |

新しいスクリプトを追加するときは、置き場所からではなく「誰が・いつ実行するか」から方言を決めること。
`deploy-all.sh` から source/呼び出しされうるものは POSIX sh、デプロイ後にユーザーが単体で使うツールは bash、という基準で判断する。

## 2. POSIX sh で避けるべき bashism

`shared/helpers.sh` `deploy-all.sh` `uninstall.sh` `*/deploy.sh` では以下を書かない。

- 配列（`arr=(a b c)`）
- `[[ ... ]]`（`[ ... ]` を使う）
- `local`（POSIX sh に存在しない。関数内変数は次節のプレフィクス命名で衝突を避ける）
- `${var,,}` / `${var^^}`（大小文字変換）
- `function` キーワード（`name() { ... }` の形で定義する）
- `$'...'`（ANSI-C クォート）
- `<<<`（herestring）
- `source`（`.` を使う。既存コードは `. "$SCRIPT_DIR/../shared/helpers.sh"` の形）
- `==`（`[ ]` の中では `=` を使う）

`bin/ocw` `bin/claude-ds` はこの制約を受けない。bash の機能を使ってよい。

## 3. エラーハンドリング

- `bin/ocw` `bin/claude-ds`（bash）は `set -euo pipefail` を使う。
- `deploy-all.sh` `uninstall.sh`（POSIX sh）は `set -u` のみを使う。`pipefail` は POSIX sh に無いため使えない。
- 各 `<tool>/deploy.sh` は現状 `set` ディレクティブを一切持たず、代わりに各コマンドの終了コードを
  `|| FAIL=1` で個別に拾い、最後に `[ "$FAIL" -ne 0 ]` で集約して終了コードを決める方針を取っている
  （`tmux/deploy.sh` などを参照）。これは1つの外部コマンドの失敗（例: `brew install` の失敗）で
  スクリプト全体を即座に止めず、他のツールのデプロイを試行させるための意図的な設計であり、
  `set -e` を書き足して置き換えないこと。

新しい `<tool>/deploy.sh` を書くときも、この「個別に拾って集約する」既存方針に合わせること。
`set -e` を追加したい場合は、それが既存の集約方針と矛盾しないか確認し、矛盾するなら
`set -e` を追加せず既存方針を踏襲する。

## 4. クォート

- 変数展開は原則 `"$var"` とする。
- 意図的に単語分割させる箇所は例外とし、コメントで意図を明示する。既存コードでは
  `resolve_tools` 内の `for _rt_t in $_rt_only`（カンマ区切りをスペース区切りに変換した後の走査）や
  `deploy-all.sh` の `for _tool in $TOOLS`（スペース区切りツール名リストの走査）がこれにあたる。

## 5. 未定義変数

`set -u` 環境（`deploy-all.sh` `uninstall.sh`、および `set -u` の有無に関わらず source される
`shared/helpers.sh` の関数群）で裸の `$VAR` を書かない。既存コードは `${DRY_RUN:-0}` `${BACKUP:-1}`
`${NO_COLOR:-}` のように必ずデフォルト値付きの展開を使っている。この慣行をすべての新規変数に適用する。

## 6. 関数の命名と副作用

`shared/helpers.sh` は POSIX sh のため `local` が使えず、関数内で使う一時変数はすべてスクリプト全体の
グローバル変数になる。名前空間衝突を避けるため、以下の既存慣行に従う。

- 単純な一時変数にはアンダースコア始まりの名前を使う（`_src` `_dst` `_parent` `_fail` など）。
- 呼び出し元に `eval` させて値を返す関数（`resolve_tools` など、戻り値を変数代入として出力するもの）は、
  関数固有のプレフィクスを付けて名前空間を切る（`resolve_tools` の `_rt_only` `_rt_result` `_rt_found` など）。
  他の関数のローカル変数と衝突する可能性がある場合に、このプレフィクス命名を検討すること。

## 7. 移植性（macOS BSD 版 / Linux GNU 版の差異）

現状のコードは `date +FORMAT`（オプション無し）のみを使っており、これは BSD/GNU 共通で安全である。
今後 `sed -i`、`date -d`、`readlink -f`、`mktemp`、`stat` を使う場合は、BSD 版と GNU 版でオプションの
意味や対応状況が異なることに注意する。

- `sed -i`: GNU は `sed -i 's/a/b/' file`、BSD は `sed -i '' 's/a/b/' file`（バックアップ拡張子の引数が必須）
- `date -d`: GNU 専用。BSD/macOS には無く `date -j -f` が必要
- `readlink -f`: GNU 専用。BSD/macOS には無い（`greadlink` か、`cd "$(dirname "$f")" && pwd` 相当の代替が必要）
- `mktemp`: `mktemp -d` はどちらでも動くが、テンプレート引数の扱いが異なる場合がある
- `stat`: GNU は `stat -c`、BSD/macOS は `stat -f`

`echo` より `printf` を優先する（既存コードは一貫して `printf` を使っている。エスケープシーケンスや
末尾改行の扱いがシェル間で一貫しないため）。

## 8. ユーザーの HOME を壊さない

- 破壊的操作（シンボリックリンクの張り替え、既存ファイルの上書き）の前には必ずバックアップを取る。
  自前で `mv` / `rm` を書かず `shared/helpers.sh` の `symlink_backup` を使う。
- `rm -rf` を変数展開込みで書かない。変数が空文字列や意図しない値になった場合に
  取り返しのつかない削除が起きる。削除対象は必ず存在確認・型確認（`-e` / `-L` など）をしてから扱う。
- `deploy-all.sh` `uninstall.sh` を含む全 deploy スクリプトの動作確認は、実 `$HOME` に対してではなく
  `--dry-run` または `HOME` を一時ディレクトリに差し替えたサンドボックスで行う。詳細は
  「テスト方針」を参照。

## 9. linter 抑制を AI の判断で追加しない

`# shellcheck disable=...` などの抑制ディレクティブや、`.shellcheckrc` / shfmt 設定の除外・閾値緩和を、
AI の判断で追加しない。shellcheck / shfmt の指摘が設計上不合理だと判断した場合は、抑制せず
違反内容・対象ファイル・判断理由を人間に報告する。

## 10. linter とこの文書の関係

shellcheck / shfmt は「機械的に判定できること」を守る。この文書は「機械的に判定できない思想」を守る。
両方を満たして初めて、このリポジトリらしいシェルスクリプトと言える。

AI がシェルスクリプトを書く・直すときは、必ずこの文書を参照し、shellcheck / shfmt が黙っていても
思想に反する書き方をしていないかを確認すること。
