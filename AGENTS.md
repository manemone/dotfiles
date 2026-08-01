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
  `~/.claude/settings.json` `~/bin/*` を実際に置き換える。動作確認は `--dry-run`、または
  `HOME` を一時ディレクトリに差し替えたサンドボックスで行うこと。
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

各ツールディレクトリは「設定ファイル本体 + `deploy.sh` + `README.md`」という共通構造を持つ。

## 3つの領域（混同しないこと）

| 対象 | 正体 | 誰が読むか |
|---|---|---|
| `claude/CLAUDE.md`, `claude/settings.json`, `claude/skills/` | **配布される成果物。** `claude/deploy.sh` がユーザーの `~/.claude/` へ symlink する | このリポジトリを使う人間のマシンの Claude Code |
| ルート `AGENTS.md` / `CLAUDE.md`（このファイル） | **このリポジトリを開発するためのルール** | このリポジトリで作業する AI |
| `.claude/settings.json` | リポジトリで作業する AI 向けの permissions を置く場所 | このリポジトリで作業する Claude Code |

`claude/CLAUDE.md`（配布物。個人の口調設定などが入っている）は編集対象が別物であることに注意する。

## デプロイの仕組み

- `deploy-all.sh` が `shared/helpers.sh` を source し、`AVAILABLE_TOOLS` を解決した上で
  各 `<tool>/deploy.sh` を呼び出す。
- オプション: `--dry-run` / `--force` / `--only <tools>` / `--backup` / `--no-backup`。
- symlink は `shared/helpers.sh` の `symlink_backup` 経由で張る。既存ファイルは `.backup` に
  退避される。`symlink_restore` が uninstall 側の対応関数。
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

## コミット前の必須ステップ

現時点では以下でよい:

- 変更したシェルスクリプトが `sh -n` / `bash -n` で構文エラーにならないこと
- `--dry-run` で意図した動作になることを確認すること

※ 孫4 で pre-commit が導入された時点でこの節は実際のコマンドに更新される。

## PR 作成時の注意

PR を作る前に `docs/design/` の「プルリクエストの作法」を読むこと
（孫2 で作成される予定の文書。作成前はこの節の原則に従う）。

## 実装時の注意

- 新しいツールディレクトリを足すときは `shared/helpers.sh` の `AVAILABLE_TOOLS` にも追加する。
- README は「ルート `README.md`（全体）」と「各ツールの `README.md`（詳細）」の二層構造。
  片方だけ更新しない。
