# AGENTS.md

## 概要

クロスプラットフォーム（macOS / Linux / WSL2）対応の dotfiles。mise でランタイムを固定し、
各ツールディレクトリ（`zsh/` `nvim/` `tmux/` `bin/` `claude/`）の `deploy.sh` が
ユーザーの `$HOME` に symlink を張ることで設定を配布する。

## 最重要ルール

- **人間の明示的指示がない限り、`git merge` / `git pull` / `git reset --hard` /
  `git push --force` / `gh pr merge` を実行しない。例外はない。**
  すべての不可逆操作の前にこのルールを照合すること。
- **deploy スクリプト（`deploy-all.sh` / `uninstall.sh` / `*/deploy.sh`）を実オペレーションで
  実行しない。** symlink 先はユーザーの実 `$HOME` であり、`~/.zshrc` `~/.tmux.conf`
  `~/.claude/settings.json` `~/bin/*` を実際に置き換える。動作確認は `deploy-all.sh --dry-run`
  （全ツール対象）で行うのを基本とする。`HOME` を一時ディレクトリに差し替えるサンドボックス実行が
  許されるツールの範囲は無条件ではない。副作用が `$HOME` の外（システムパッケージのインストール）や
  外部ネットワークに及ぶツール（`tmux` `zsh` `nvim`）は対象外であり、詳細と対象ツールの分類は
  `docs/design/` の「テスト方針（DOC-2608020715-b）」に従うこと。
  **個別の `<tool>/deploy.sh` は `--dry-run` 引数を解釈しない**（環境変数 `DRY_RUN=1` のみ見る）。
  `sh zsh/deploy.sh --dry-run` のように直接引数を渡しても無視され実際に書き換えが起きるため、
  個別スクリプトを dry-run するときは `DRY_RUN=1 sh zsh/deploy.sh` のように環境変数で渡すこと。
- 指示された範囲外の機能を先回りして実装しない。
- **linter の抑制ディレクティブ（`# shellcheck disable=...` 等）や linter 設定の除外・閾値緩和を、
  AI の判断で追加しない。** 違反が設計上不合理だと判断した場合は、抑制せず違反内容・対象ファイル・
  判断理由を人間に報告する。

## ディレクトリ構成

| ディレクトリ | 役割 |
|---|---|
| `zsh/` | Zsh 設定（Antidote でプラグイン管理） |
| `nvim/` | NeoVim 設定（lazy.nvim でプラグイン管理） |
| `tmux/` | tmux 設定 |
| `bin/` | スタンドアロンの CLI ツール（`ocw`, `claude-ds`） |
| `claude/` | Claude Code 向け配布物（設定・スキル） |
| `shared/` | 全 deploy スクリプトが共有するヘルパー（`helpers.sh`） |
| `docs/` | このリポジトリ自体の設計文書・計画書 |
| `tools/` | このリポジトリ自体の開発を支援するツール（`doc-id` など）。`bin/` と異なり `$HOME` へは配布しない |

各ツールディレクトリは「設定ファイル本体 + `deploy.sh` + `README.md`」という共通構造を持つ。

## 3つの領域（混同しないこと）

| 対象 | 正体 | 誰が読むか |
|---|---|---|
| `claude/CLAUDE.md`, `claude/settings.json`, `claude/skills/` | **配布される成果物。** `claude/deploy.sh` がユーザーの `~/.claude/` 配下へ配置する（`CLAUDE.md` と `skills/` は symlink、`settings.json` は生成。詳細は「デプロイの仕組み」参照） | このリポジトリを使う人間のマシンの Claude Code |
| ルート `AGENTS.md` / `CLAUDE.md`（このファイル） | **このリポジトリを開発するためのルール** | このリポジトリで作業する AI |
| `.claude/settings.json` | リポジトリで作業する AI 向けの permissions を置く場所 | このリポジトリで作業する Claude Code |

**`claude/CLAUDE.md`（配布物。個人の口調設定などが入っている。ルート `CLAUDE.md` とは別物）は、
指示が無い限り編集しない。**

## デプロイの仕組み

- `deploy-all.sh` が `shared/helpers.sh` を source し、`AVAILABLE_TOOLS` を解決した上で
  各 `<tool>/deploy.sh` を呼び出す。
- オプション: `--dry-run` / `--force` / `--only <tools>` / `--backup` / `--no-backup`。
- symlink は `shared/helpers.sh` の `symlink_backup` 経由で張る。既存ファイルは `.backup`
  （既に存在する場合はタイムスタンプ+PID 付きの別名）に退避される。`symlink_restore` が
  uninstall 側の対応関数。ただし退避の前提は次の2点で崩れる:
  - `--no-backup`（`BACKUP=0`）指定時は退避されず `rm -f` される
  - `claude/skills/` は `symlink_backup` を通らない。`claude/deploy.sh` がスキルごとに
    個別に symlink を張り、退避先も `~/.claude/skills-backup/<名前>.<日時>.<PID>` になる
- `claude/settings.json` だけは symlink ではなく、ベース設定と `settings.machine.json`
  （マシン固有・非追跡）をマージした**実ファイル**として生成される。マシンごとの上書き設定を
  git 管理下に置かずに反映するため。

## クロスプラットフォーム制約

- `shared/helpers.sh` は POSIX sh。bashism を書かない。
- `deploy-all.sh` `uninstall.sh` `*/deploy.sh` も `#!/bin/sh`。
- `bin/ocw` `bin/claude-ds` は bash（`#!/usr/bin/env bash`）。
- プラットフォーム分岐は `is_macos` / `is_linux` / `is_wsl` / `get_brew_prefix` を使い、
  直接 `uname` を叩かない。
- macOS の BSD 版コマンドと GNU 版の差異（`sed -i`、`date`、`readlink -f` など）に注意する。

## コードの書き方

シェルスクリプトを書く・直すときは
[docs/design/DOC-2608020715-a_シェルスクリプトコーディング方針.md](docs/design/DOC-2608020715-a_シェルスクリプトコーディング方針.md)
を参照すること。POSIX sh / bash の使い分け、bashism の回避、エラーハンドリングの既存方針などを定めている。

## コミット前の必須ステップ

初回のみ、clone 後に以下を実行して pre-commit フックを有効化する。

```
uv tool install pre-commit
pre-commit install
```

以降はコミット時に `.pre-commit-config.yaml` のフックが自動で走る
（`trailing-whitespace` 等の基本チェック、`shellcheck` / `shfmt`、
`./tools/doc-id/doc-id check` / `verify`、`tools/doc-id/` 配下の変更時の
`ruby tools/doc-id/test/doc_id_test.rb`、シェルスクリプト変更時の
`./deploy-all.sh --dry-run`）。手元でまとめて確認したい場合は次を実行する。

```
pre-commit run --all-files
```

pre-commit のフックではデプロイの実動作までは検証しないため、
デプロイ関連のシェルスクリプトを変更した場合は追加で以下も実行する。

```
tests/deploy_smoke.sh
```

`HOME` を一時ディレクトリへ差し替えたサンドボックス上で実際に deploy /
uninstall を行い、symlink・既存ファイルの退避・冪等性・
`claude/settings.json` の実ファイル生成を検証する（既定の対象は
`bin,claude`。デプロイの検証は必ずこのサンドボックス経由で行い、
人間の実 `$HOME` に対して直接実行しない。詳細は
[docs/design/DOC-2608020715-b_テスト方針.md](docs/design/DOC-2608020715-b_テスト方針.md)
を参照）。

**AI はこれらのステップ（pre-commit のフック相当の確認と
`tests/deploy_smoke.sh`）を省略しない。省略するのは人間が明示的に指示した
場合に限る。**

shellcheck / shfmt の指摘に対して、抑制ディレクティブ（`# shellcheck disable=...`
等）や `.pre-commit-config.yaml` の `exclude` 追加・`shfmt` のオプション緩和を
AI の判断で加えない。指摘が設計上不合理だと判断した場合は、抑制せず
指摘内容・対象ファイル・判断理由を人間に報告する。コードの構造を変えて
指摘そのものを解消できる場合（例: 動的変数名参照を case 文に置き換える）は
それを優先する。

`docs/` 配下に新規ファイルを追加する場合は、まず `DOC-DOCID_PLACEHOLDER_<説明的ファイル名>.md`
という名前で作り、`./tools/doc-id/doc-id assign docs/path/to/new_file.md` で DOC-ID を採番する
（`doc-id check` / `doc-id verify` フックが検証する）。

## PR 作成時の注意

PR を作る前に
[docs/design/DOC-2608020715_プルリクエストの作法.md](docs/design/DOC-2608020715_プルリクエストの作法.md)
を読むこと。

## 実装時の注意

- 新しいツールディレクトリを足すときは `shared/helpers.sh` の `AVAILABLE_TOOLS` に加えて、
  `uninstall.sh` の `KNOWN_LINKS_<tool>`（生成ファイルがあれば `KNOWN_GENERATED_<tool>` も）にも
  追加する。これを忘れると `uninstall.sh` は該当ツールを静かにスキップし、張った symlink が
  ユーザーの `$HOME` に残り続ける。
- README は「ルート `README.md`（全体）」と「各ツールの `README.md`（詳細）」の二層構造。
  片方だけ更新しない。
- `docs/` の文書に地の文で言及するときは、説明的ファイル名だけで呼ばず、その文書の DOC-ID を明示する
  （例: 「テスト方針（DOC-YYMMDDHHMM）を参照」のように、実際に割り当てられた DOC-ID を書く）。
  相対パスへのリンクを併記してもよいが、DOC-ID の明示は省略しない。DOC-ID は不変なので、
  ファイルが移動・リネームされても文書を一意に特定できる。
  - **移行措置**: 対象の文書がまだ `DOC-DOCID_PLACEHOLDER` のまま採番されていない間は、
    DOC-ID を書きようがないため説明的名称のみで言及してよい。`./tools/doc-id/doc-id assign` で採番する際は、
    ファイル名だけでなくリポジトリ内の地の文の言及（`git grep` で説明的ファイル名を検索して見つかる
    箇所）にも DOC-ID を追記すること。採番ツールによるプレースホルダ文字列の自動置換は
    ファイル名・リンク先パスのみが対象で、地の文中の言及までは拾わない。
