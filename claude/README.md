# Claude Code Config (claude)

## Overview

Claude Code の設定ファイル群。`~/.claude/` にデプロイして使う。

| File | Purpose | Deploy Method |
|---|---|---|
| `CLAUDE.md` | Claude Code の個人指示（プロジェクト横断で適用されるグローバル指示） | symlink |
| `settings.json` | Claude Code の汎用設定（モデル、権限ポリシー、テーマ等）。マシン固有設定は**含まない** | 生成（マージ） |
| `settings.machine.json.example` | マシン固有設定のテンプレート。コピーして使う | （手動コピー） |

## 1. Requirements

| Tool | Why | Install |
|---|---|---|
| **Claude Code** CLI | 設定ファイルの読み取り元 | `npm install -g @anthropic-ai/claude-code` |
| **Python 3** | `settings.machine.json` とのマージ用（任意） | `mise use python@latest` |

## 2. Quick Start

```bash
# 1. Run deploy script
cd ~/.dotfiles/claude
./deploy.sh

# 2. Verify
ls -la ~/.claude/CLAUDE.md         # symlink
ls -la ~/.claude/settings.json     # 実ファイル（deploy.sh が生成）
```

The deploy script:
- Creates `~/.claude/` directory with mode `700`（認証情報を置く可能性があるため）
- Symlinks `CLAUDE.md` → `~/.claude/CLAUDE.md`
- Generates `~/.claude/settings.json` as a real file（※symlink ではない）:
  - 通常時: `claude/settings.json` をそのままコピー
  - `claude/settings.machine.json` が存在する場合: ベース設定にマシン固有設定をマージして出力

> **⚠️ 重要**: deploy 実行時に既存の `~/.claude/settings.json` はバックアップ（`.backup` 付きで退避）されます。
> `permissions.allow`（33件）、Herdr の `SessionStart` hook、`additionalDirectories` など
> マシン固有の設定が失われるのを防ぐには、**deploy 前に `settings.machine.json` を作成**してください。

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
| `permissions.ask` | 危険コマンドパターン（20件） | `git push --force`, `rm -rf`, `sudo` 等の実行前に確認 |

## 4. Customization — マシン固有設定の追加

`settings.json` にはマシン固有の設定（`permissions.allow`、`additionalDirectories`、`hooks`）が含まれていません。

**Claude Code はユーザーレベルの `~/.claude/settings.local.json` を読み取りません。**
（`--setting-sources` の `local` はプロジェクトレベルの `.claude/settings.local.json` を指します。）

代わりに `claude/settings.machine.json` を使います。deploy.sh がベース設定とマージして
`~/.claude/settings.json` を生成します。

### 4.1 初回セットアップ

```bash
cd ~/.dotfiles/claude

# テンプレートから settings.machine.json を作成
cp settings.machine.json.example settings.machine.json

# 自分の環境に合わせて編集
vim settings.machine.json

# デプロイ実行（ベース + machine をマージして ~/.claude/settings.json を生成）
./deploy.sh
```

`settings.machine.json` は `.gitignore` で除外されているため、commit されません。

### 4.2 `permissions.allow` の追加

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

マージの仕組み:
- `settings.json`（ベース）の上に `settings.machine.json` を shallow merge
- `permissions` 内のリストキー（`allow`, `deny`, `ask`）は**結合**（重複除去、machine 側の項目が末尾に追加）
- それ以外のキーは machine 側の値で上書き

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

> **注意**: Herdr の `herdr-agent-state.sh` hook が必要な場合は、これを含めてください。

### 4.4 `model` / `theme` の上書き

```json
{
  "model": "sonnet",
  "theme": "light"
}
```

### 4.5 `additionalDirectories` の追加

```json
{
  "permissions": {
    "additionalDirectories": [
      "/home/manemone/projects/my-other-project/config"
    ]
  }
}
```

### 4.6 `defaultMode` の上書き

```json
{
  "permissions": {
    "defaultMode": "acceptEdits"
  }
}
```

### 4.7 設定の反映確認

`settings.machine.json` を編集した後は、再デプロイで反映されます:

```bash
cd ~/.dotfiles/claude
./deploy.sh
```

Claude Code は起動時に設定を読み込むため、設定変更後は Claude Code を再起動してください。

### 4.8 CLAUDE.md の直接編集

CLAUDE.md は個人設定のため、symlink 先を直接編集して問題ありません。リポジトリ側のファイルに即反映されます。

```bash
# 直接編集
vim ~/.claude/CLAUDE.md

# またはリポジトリ側を編集（同じファイル）
vim ~/.dotfiles/claude/CLAUDE.md
```

## 5. Troubleshooting

### `~/.claude/settings.json` の変更を反映したい

Claude Code は起動時に設定を読み込みます。

- **マシン固有の設定を追加・変更する** → `claude/settings.machine.json` を編集して再デプロイ:
  ```bash
  cd ~/.dotfiles/claude && ./deploy.sh
  ```
- **`~/.claude/settings.json` を何らかの理由で直接編集した** → Claude Code を再起動。
  ただし次回 `deploy.sh` 実行時に上書きされるため、恒久的な変更は `settings.machine.json` に転記してください。

### `settings.machine.json` の変更が反映されない

`settings.machine.json` を編集した後は、**必ず再デプロイ**してください。
deploy.sh がその時点の `settings.machine.json` を読み取って `~/.claude/settings.json` を再生成します。

```bash
cd ~/.dotfiles/claude && ./deploy.sh
```

### デプロイで既存設定が消えた

deploy.sh は既存の `~/.claude/settings.json` を `.backup` 付きで退避します。
退避されたファイルから設定を確認し、`settings.machine.json` に転記してください:

```bash
# バックアップを確認
ls -la ~/.claude/settings.json.backup*

# バックアップから復元（必要に応じて）
cp ~/.claude/settings.json.backup ~/.claude/settings.json
```

### `python3` がないと言われる

`settings.machine.json` を使わない場合は python3 不要です（ベース設定がそのままコピーされます）。
`settings.machine.json` によるマージを使う場合は python3 をインストールしてください:

```bash
mise use python@latest
# または
sudo apt install python3
```

### `settings.machine.json` が JSON として invalid

```bash
python3 -m json.tool claude/settings.machine.json
```

エラーが出たら JSON の構文を修正してください。

### symlink が壊れている

```bash
# 確認
ls -la ~/.claude/CLAUDE.md

# 修復
cd ~/.dotfiles/claude
./deploy.sh
```
