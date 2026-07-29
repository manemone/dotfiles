# CLI Tools (bin)

## Overview

自作 CLI ツール集。`~/bin/` に symlink して使う。

| Tool | Purpose |
|---|---|
| `ocw` | Git worktree 作成・管理。Herdr 連携で commander/implementer/reviewer の三面体制を自動セットアップ |
| `claude-ds` | Claude Code を DeepSeek API 経由で実行するラッパー |

## 1. Requirements

| Tool | Why | Install |
|---|---|---|
| **Git** | worktree 操作 (`ocw`) | Built-in on most systems |
| **Python 3** | JSON パース (`ocw` Herdr モード) | `mise use python@latest` |
| **claude** (CLI) | `claude-ds` の実体 | `npm install -g @anthropic-ai/claude-code` |
| **DeepSeek API key** | `claude-ds` の認証 | `~/.config/deepseek/api_key` に保存 |
| **VS Code** `code` CLI (optional) | `ocw` のデフォルトモードで worktree を開く | `code` コマンドを PATH に通す（macOS: Cmd+Shift+P → "Shell Command: Install 'code' command in PATH"） |
| **Herdr** (optional) | `ocw --herdr` のマルチペイン管理 | Herdr プロジェクトのインストール手順に従う（スタティックリンクされたバイナリとして配布） |

## 2. Quick Start

```bash
# 1. Run deploy script
cd ~/.dotfiles/bin
./deploy.sh

# 2. Restart your shell (or source ~/.zshrc) so ~/bin is on PATH
exec $SHELL -l

# 3. Verify
which ocw
which claude-ds
```

> **Note**: `~/bin` の PATH 追加は `zsh/.zshrc` が担っています。bash 等他のシェルを使う場合は、各自で `~/bin` を PATH に通してください。

The deploy script:
- Creates `~/bin/` directory if missing
- Symlinks `ocw` and `claude-ds` into `~/bin/`

## 3. What's Included

### 3.1 ocw — Opinionated Claude Worktree

Git worktree を作成し、オプションで Herdr マルチペイン環境をセットアップする。

```bash
# 基本的な worktree 作成（VS Code で開く）
ocw my-feature

# Herdr 連携（commander/implementer/reviewer の3ペイン）
ocw --herdr my-feature

# ベースブランチを指定
ocw new --herdr my-feature origin/main

# worktree 削除
ocw rm my-feature
ocw rm -f my-feature  # 強制削除

# worktree 一覧
ocw ls
```

**Herdr モードのペイン構成:**
- **commander**: 司令塔（デフォルト: `claude`）
- **implementer**: 実装担当（デフォルト: `claude`）
- **reviewer**: レビュー担当（デフォルト: `claude`）

### 3.2 claude-ds — Claude Code via DeepSeek API

Claude Code CLI を DeepSeek API に繋ぎ替えて実行する。`exec env` で以下の環境変数を**すべて上書き固定**する。`claude "$@"` で CLI 引数は素通しされるため `--model` 等のオプションは通常通り指定可能だが、デフォルトモデルは以下の値に固定される:

```bash
claude-ds
# 実体:
#   ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
#   ANTHROPIC_AUTH_TOKEN="<キーファイルの中身>"
#   ANTHROPIC_MODEL="deepseek-v4-pro[1m]"
#   ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-pro[1m]"
#   ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-pro[1m]"
#   ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek-v4-flash"
#   CLAUDE_CODE_SUBAGENT_MODEL="deepseek-v4-flash"
#   claude "$@"
```

| モデル種別 | 固定値 |
|---|---|
| メイン / Opus / Sonnet | `deepseek-v4-pro[1m]` |
| Haiku / subagent | `deepseek-v4-flash` |

API キーは `DEEPSEEK_API_KEY_FILE` 環境変数で指定可能（デフォルト: `~/.config/deepseek/api_key`）。

## 4. Customization

### ocw のコマンド差し替え

環境変数で commander / implementer / reviewer の実行コマンドを上書きできる:

```bash
# DeepSeek を使う場合（旧デフォルト）
export OCW_COMMANDER_COMMAND=claude-ds
export OCW_IMPLEMENTER_COMMAND=claude-ds

# 別のツールを指定
export OCW_REVIEWER_COMMAND=claude
```

| Variable | Default | Purpose |
|---|---|---|
| `OCW_COMMANDER_COMMAND` | `claude` | commander ペインで実行するコマンド |
| `OCW_IMPLEMENTER_COMMAND` | `claude` | implementer ペインで実行するコマンド |
| `OCW_REVIEWER_COMMAND` | `claude` | reviewer ペインで実行するコマンド |

### claude-ds の API キー設定

```bash
# デフォルトのキーファイル
mkdir -p ~/.config/deepseek
echo "sk-your-api-key" > ~/.config/deepseek/api_key
chmod 600 ~/.config/deepseek/api_key

# 別の場所に置く場合
export DEEPSEEK_API_KEY_FILE=/path/to/your/api_key
```

## 5. Troubleshooting

### `which ocw` returns nothing

`~/bin` の PATH 追加は `zsh/.zshrc` のシェル起動時チェックに依存しています。`deploy.sh` で `~/bin` を新規作成した直後は、シェルを再起動してください:

```bash
exec $SHELL -l
```

bash 等他のシェルを使う場合は、各自で `~/bin` を PATH に通してください。

### `error: Herdr server is not running. Start or attach first with: herdr`

`ocw --herdr` は Herdr サーバーが起動している必要があります。先に `herdr` を実行してサーバーを起動するか、アタッチしてください。

### `Error: DeepSeek API key file not found: ~/.config/deepseek/api_key`

`claude-ds` の API キーが未設定です。以下を実行してください:

```bash
mkdir -p ~/.config/deepseek
echo "sk-your-api-key" > ~/.config/deepseek/api_key
chmod 600 ~/.config/deepseek/api_key
```

別のパスにキーを置く場合は `DEEPSEEK_API_KEY_FILE` 環境変数で指定してください。

### `error: run ocw from inside a Git worktree`

`ocw` は Git リポジトリの worktree 内で実行する必要があります。カレントディレクトリが Git worktree であることを確認してください。

### `warning: VS Code CLI 'code' was not found`

`ocw` のデフォルトモード（`--herdr` なし）では worktree 作成後に VS Code を開こうとします。`code` CLI がインストールされていない場合、この警告が出ますが worktree 作成自体は成功しています。VS Code をインストールするか、`--herdr` モードを使用してください。
