# Claude Code Config (claude)

## Overview

Claude Code の設定ファイル群。`~/.claude/` に symlink して使う。

| File | Purpose |
|---|---|
| `CLAUDE.md` | Claude Code の個人指示（プロジェクト横断で適用されるグローバル指示） |
| `settings.json` | Claude Code の汎用設定（モデル、権限ポリシー、テーマ等）。マシン固有設定は**含まない** |

## 1. Requirements

| Tool | Why | Install |
|---|---|---|
| **Claude Code** CLI | 設定ファイルの読み取り元 | `npm install -g @anthropic-ai/claude-code` |

## 2. Quick Start

```bash
# 1. Run deploy script
cd ~/.dotfiles/claude
./deploy.sh

# 2. Verify
ls -la ~/.claude/CLAUDE.md
ls -la ~/.claude/settings.json
```

The deploy script:
- Creates `~/.claude/` directory if missing
- Symlinks `CLAUDE.md` → `~/.claude/CLAUDE.md`
- Symlinks `settings.json` → `~/.claude/settings.json`

## 3. What's Included

### 3.1 CLAUDE.md

Claude Code がセッション開始時に読み込むグローバルな個人指示（project-level の CLAUDE.md より優先度は低い）。

現在の設定:
- 脳筋後輩キャラクターでの応答スタイル指定（語尾・一人称・二人称）

CLAUDE.md は個人設定のため、このファイルを直接編集することで即座に反映される。

### 3.2 settings.json

Claude Code の設定ファイル。以下の汎用設定を含む（マシン固有の `permissions.allow`、`additionalDirectories`、`hooks` は**意図的に除外**）。

| Setting | Value | Notes |
|---|---|---|
| `model` | `opus` | デフォルトモデル |
| `language` | `Japanese` | 応答言語 |
| `effortLevel` | `high` | 推論深度 |
| `theme` | `dark` | テーマ |
| `editorMode` | `normal` | エディタモード |
| `autoCompactEnabled` | `true` | 自動コンパクション |
| `switchModelsOnFlag` | `true` | フラグによるモデル切り替え |
| `skipWorkflowUsageWarning` | `true` | ワークフロー警告スキップ |
| `permissions.defaultMode` | `acceptEdits` | 権限のデフォルトモード |
| `permissions.deny` | セキュリティポリシー（24件） | `.env`, `.ssh`, `.aws`, API キー等へのアクセスをブロック |
| `permissions.ask` | 危険コマンドパターン（19件） | `git push --force`, `rm -rf`, `sudo` 等の実行前に確認 |

## 4. Customization — マシン固有設定の追加

`settings.json` にはマシン固有の設定（`permissions.allow`、`additionalDirectories`、`hooks`）が含まれていません。これらは各マシンで `~/.claude/settings.local.json` を作成することで追加します。

### 4.1 `settings.local.json` の基本

`settings.local.json` は `settings.json` とマージされて適用されます。同じキーがある場合は local 側が優先されます。

```bash
# ファイルが存在しない場合は作成
touch ~/.claude/settings.local.json
```

### 4.2 `permissions.allow` の追加

プロジェクト固有のディレクトリに対する読み取り/実行権限を許可する例:

```json
{
  "permissions": {
    "allow": [
      "Bash",
      "Read",
      "Edit",
      "WebFetch",
      "Read(//home/manemone/projects/my-project/**)",
      "Bash(git checkout *)",
      "Bash(git fetch *)",
      "Bash(git branch *)"
    ]
  }
}
```

### 4.3 `hooks` の追加

セッション開始時のフックを追加する例:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash '/path/to/your/hook.sh' session",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

### 4.4 `model` / `theme` の上書き

```json
{
  "model": "sonnet",
  "theme": "light"
}
```

### 4.5 ⚠️ 既知の注意点: `permissions` のマージバグ

Claude Code には `permissions` キーが deep merge されず、**local 側の値で完全に replace される**バグが報告されています。

**`permissions.deny` を `settings.local.json` に書く場合の対策:**

`settings.json` 側の `deny` リストも含めて**すべてコピーしてから追加**してください。つまり:

```json
{
  "permissions": {
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)",
      "... (settings.json の deny をすべてコピー) ...",
      "Edit(~/.netrc)",
      "Read(./my-additional-secret/**)",
      "Edit(./my-additional-secret/**)"
    ],
    "ask": [
      "... (settings.json の ask をすべてコピー) ..."
    ],
    "allow": [
      "... (必要な allow を列挙) ..."
    ]
  }
}
```

`permissions` 全体を local に書く場合は、**3つのキー（allow, deny, ask）をすべて明示的に記述する**必要があります。1つでも欠けると、そのキーは空として扱われます。

> **推奨**: できるだけ `permissions.allow` のみを local に書くことで、deny/ask は settings.json の値が維持されます。deny/ask のカスタマイズが必要な場合のみ、上記の全コピー戦略を使ってください。

### 4.6 `additionalDirectories` の追加

```json
{
  "permissions": {
    "additionalDirectories": [
      "/home/manemone/projects/my-other-project/config"
    ]
  }
}
```

### 4.7 CLAUDE.md の直接編集

CLAUDE.md は個人設定のため、symlink 先を直接編集して問題ありません。リポジトリ側のファイルに即反映されます。

```bash
# 直接編集
vim ~/.claude/CLAUDE.md

# またはリポジトリ側を編集（同じファイル）
vim ~/.dotfiles/claude/CLAUDE.md
```

## 5. Troubleshooting

### `settings.json` の変更が反映されない

Claude Code は起動時に設定を読み込みます。`settings.json` を編集したら Claude Code を再起動してください。

### `settings.local.json` が読み込まれない

以下を確認してください:
1. ファイルが `~/.claude/settings.local.json` に存在するか
2. JSON として valid か（`python3 -m json.tool ~/.claude/settings.local.json` で確認）
3. 権限が適切か（`ls -la ~/.claude/settings.local.json`）

### `permissions.deny` が効かない / 上書きされてしまう

セクション 4.5 の既知のバグを参照してください。`permissions` を `settings.local.json` に書く場合は、3つのキー（allow, deny, ask）すべてを明示的に記述する必要があります。

### symlink が壊れている

```bash
# 確認
ls -la ~/.claude/CLAUDE.md
ls -la ~/.claude/settings.json

# 修復
cd ~/.dotfiles/claude
./deploy.sh
```
