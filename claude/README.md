# Claude Code Config (claude)

## Overview

Claude Code の設定ファイル群。`~/.claude/` にデプロイして使う。

| File | Purpose | Deploy Method |
|---|---|---|
| `CLAUDE.md` | Claude Code の個人指示（プロジェクト横断で適用されるグローバル指示） | symlink |
| `settings.json` | Claude Code の汎用設定（モデル、権限ポリシー、テーマ等）。マシン固有設定は**含まない** | 生成（マージ） |
| `skills/` | Claude Code スキル（`pr-review-loop`, `umbrella-orchestrator`） | スキルごとに個別 symlink |
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
ls -la ~/.claude/skills/           # 各スキルが symlink（herdr など独自スキルは残る）
```

The deploy script:
- Creates `~/.claude/` directory with mode `700`（認証情報を置く可能性があるため）
- Symlinks `CLAUDE.md` → `~/.claude/CLAUDE.md`
- Generates `~/.claude/settings.json` as a real file（※symlink ではない）:
  - 通常時: `claude/settings.json` をそのままコピー
  - `claude/settings.machine.json` が存在する場合: ベース設定にマシン固有設定をマージして出力
- Auto-detects skill directories under `claude/skills/` and symlinks each individually → `~/.claude/skills/<name>/`

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
| `statusLine` | `{"type":"command","command":"ocw-meter snapshot-quota"}` | Claude 利用枠(5時間枠・週間枠)のステータスバー表示。§3.4参照 |

### 3.3 Skills

Claude Code のカスタムスキル。`claude/skills/` 配下の各スキルディレクトリが
`~/.claude/skills/<skill-name>/` に**個別 symlink** される。

| Skill | Purpose |
|---|---|
| `pr-review-loop` | PRレビューサイクルを自動化。Herdr の reviewer エージェントと連携し、レビュー→修正→再レビューを承認まで繰り返す |
| `umbrella-orchestrator` | 傘ブランチの孫ライフサイクル管理。計画書の読み取り、孫ブランチの spawn、マージ検出と検証、計画書更新を自動化 |

`pr-review-loop` は各Phaseの境界で `ocw-meter event`（工程計測。`docs/planning/DOC-2608021229-a_ai-llm-cost-observability_計画.md` 参照）を呼び出す。
すべて `command -v ocw-meter >/dev/null && ... || true` 形式の fail-open 呼び出しで、
レビュー規約・判定基準・停止条件には一切変更が無く、`ocw-meter` が存在しない環境でもスキルは完全に動作する。

**デプロイの仕組み:**

- **ディレクトリ全体 symlink は禁止。** `~/.claude/skills` をまとめて symlink すると、Herdr 管理の `herdr` スキルやユーザー独自スキルが消えるため。
- 代わりに **`claude/skills/` 内の全ディレクトリを自動検出**し、1スキルずつ個別 symlink する。
- これにより、Herdr 管理のスキルや手動追加した独自スキルと安全に共存できる（**`claude/skills/` 配下と同名でない限り**）。
- 将来スキルが増えても deploy.sh の修正は不要（自動検出のため）。スキルを削除・リネームした場合も、deploy.sh が自動的に古い symlink を掃除する。

**重要**: `claude/skills/` 配下と同名のファイル／ディレクトリが既に `~/.claude/skills/` にある場合、`~/.claude/skills-backup/` に退避されます。
退避からの復元は手動で行ってください:
```bash
mv ~/.claude/skills-backup/<name>.<timestamp>.<pid> ~/.claude/skills/<name>
```

**独自スキルの追加方法:**

`~/.claude/skills/` に手動でディレクトリを作り `SKILL.md` を置くだけでよい。
deploy.sh はリポジトリ管理下のスキルのみを symlink し、**同名衝突がない限り**手動追加したスキルには触れない。

```bash
# 独自スキルを追加
mkdir -p ~/.claude/skills/my-skill
cat > ~/.claude/skills/my-skill/SKILL.md << 'EOF'
---
name: my-skill
description: 自分のスキル
---
# My Skill
...
EOF
```

リポジトリ管理のスキルを増やす場合は、`claude/skills/` にディレクトリを追加するだけで
次回 deploy 時に自動検出される。

```bash
# リポジトリ側に新しいスキルを追加
mkdir -p claude/skills/new-skill
# ... SKILL.md を作成 ...
./deploy.sh  # 自動検出されて symlink が作られる
```

### 3.4 statusLine — Claude 利用枠スナップショット

`ocw-meter snapshot-quota`（`bin/README.md` §3.3 参照）を `statusLine` コマンドとして配線し、
Claude Code のステータスバーに 5時間枠 / 週間枠 / コンテキスト使用率を表示する。
詳細設計は `docs/planning/DOC-2608021229-a_ai-llm-cost-observability_計画.md` 第5.6章・第8.5章、
`docs/adr/DOC-2608021229_llm-cost-observability-collection-method.md` §2.1・§8 を参照。

**表示内容**（例）:

```
5h:37% 7d:12% ctx:24%
```

取得できない項目は表示しない（例: `claude-ds`（DeepSeek）セッションでは `rate_limits` が
一切来ないため `5h:`/`7d:` は出ず、`ctx:` のみになるか、コンテキスト情報も無ければ完全に空になる）。
`ctx` は `context_window.used_percentage` が生の値として取得できているときのみ表示する
（推定値からのフォールバック計算は記録用イベントにのみ使い、表示には使わない）。

**事前準備（必須）**: `ocw-meter` が PATH に無い環境では statusLine コマンド自体が
`command not found` になり、表示が壊れる。必ず先に `bin/deploy.sh` を実行して
`~/bin/ocw-meter` を配置し、`~/bin` が PATH に入っていることを確認すること
（`~/bin` の PATH 追加は `zsh/.zshrc` 依存。`bin/README.md` §5 参照）。

**観測は既存フローに一切割り込まない。** `snapshot-quota` は例外が起きても必ず表示文字列を
stdout に返し exit 0 する（statusLine が壊れて画面が崩れる事態を避けるための最優先事項）。
サンプリングは既定60秒に1回（`OCW_METER_QUOTA_INTERVAL` で変更可）に自制されており、
statusLine が描画のたびに呼ばれても書き込みが肥大しない。

**取得できない項目（実測に基づく既知の制約。詳細は DOC-2608021229 §2.1 参照）:**

- `claude-ds`（DeepSeek）セッションでは `rate_limits` が原理的に来ない
  （Claude.ai サブスクリプションの利用枠であり、DeepSeek API 経由のセッションには適用されない）。
  `five_hour_used_pct` 等は `null`、`completeness: "unknown"` として記録される（推測しない）
- 5時間枠に到達して待機した際の挙動は**未観測**（その状況が発生した際のログをまだ収集できていない）。
  `blocked` の検出は best-effort であり、`ocw-meter` は明示的な待機時間を計測しない
- `rate_limits.five_hour.resets_at` が過去時刻（stale値）を返すケースが実測されている
  （DOC-2608021229 §2.1: 8サンプル中3件）。stale と判定された場合は `window_id` を `null` にして
  `completeness: "partial"` で記録する（推測で新しい窓を開始しない）

**⚠️ 重大な注意 — `~/.claude/settings.json` の `hooks` 消失リスク（計画書17章 R3）:**

`~/.claude/settings.json` は **Herdr（`SessionStart` hook）と `claude/deploy.sh` の両方が書き込む
競合地帯**である。`claude/deploy.sh` は `claude/settings.machine.json` が存在しない、または
存在しても `hooks` を含まない場合、Herdr が実行時に書き足した `hooks` ごと上書きしてしまう
（実機検証中に実際にこの事故が発生している — 詳細は DOC-2608021229 Appendix A 参照）。

**`statusLine` を配線した本設定を deploy する前に、必ず以下を確認・実施すること:**

1. `~/.claude/settings.json` の現在の `hooks` を確認する:
   ```bash
   python3 -c "import json; print(json.dumps(json.load(open('$HOME/.claude/settings.json')).get('hooks'), indent=2))"
   ```
2. `claude/settings.machine.json`（無ければ `settings.machine.json.example` からコピー）に、
   確認した `hooks`（通常は Herdr の `herdr-agent-state.sh`）を明記する（§4.3参照）
3. `./deploy.sh` を実行する
4. deploy 後、再度 手順1 のコマンドを実行し、`hooks.SessionStart` が健在であることを確認する

**statusLine の無効化方法:**

`claude/settings.machine.json` に `"statusLine": null` は効かない（machine側の shallow merge は
`null` も値として上書きしてしまうだけで、キー自体を消せない）。無効化したい場合は
`~/.claude/settings.json` の `statusLine` キーを deploy 後に手動で削除する
（**次回 `./deploy.sh` 実行時に `claude/settings.json` の内容で再度上書きされる**ので、
恒久的に無効化したい場合はリポジトリ側の `claude/settings.json` から `statusLine` を削除すること）。

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
