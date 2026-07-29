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
| **Herdr** (optional) | `ocw --herdr` のマルチペイン管理 | Herdr 管理下で提供 |

## 2. Quick Start

```bash
# 1. Run deploy script
cd ~/.dotfiles/bin
./deploy.sh

# 2. Verify
which ocw
which claude-ds
```

The deploy script:
- Creates `~/bin/` directory if missing
- Symlinks `ocw` and `claude-ds` into `~/bin/`

## 3. Tools

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

Claude Code CLI を DeepSeek API に繋ぎ替えて実行する。

```bash
claude-ds
# 実体: ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic claude
```

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
