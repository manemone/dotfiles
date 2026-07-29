# 計画書: 自作ツールの dotfiles への移行

傘ブランチ: `ai/dotfiles-add-tools`
ターゲット: `master`

## 概要

マシン上に散在する自作ツール（ocw, claude-ds, Claude Code スキル）を dotfiles リポジトリに統合する。
新しいツールディレクトリ `bin/` と `claude/` を追加し、既存の deploy-all.sh フレームワークに乗せる。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 0 | `ai/ph-00-bin` | `bin/` ディレクトリ追加。ocw（デフォルトコマンドを claude に修正）、claude-ds、deploy.sh、README.md | ✅ PR #18 マージ済 |
| 1 | `ai/ph-01-claude-config` | `claude/` ディレクトリ追加。CLAUDE.md、settings.json（汎用設定のみ）、deploy.sh、README.md | ✅ PR #19 マージ済 |
| 2 | `ai/ph-02-claude-skills` | `claude/skills/` に pr-review-loop と umbrella-orchestrator を移行（**孫1マージ後に着手**） | ✅ PR #20 マージ済 |
| 3 | `ai/ph-03-shared-update` | `shared/helpers.sh` の AVAILABLE_TOOLS に `bin claude` を追加 | ✅ PR #21 マージ済 |
| 4 | `ai/ph-04-docs` | README.md 更新、deploy-all.sh での統合確認、実マシンデプロイテスト | ⬜ 待機中（全孫マージ待ち） |

## 依存関係と実行順序

```
フェーズ1（並列可）:
  孫0 (bin/)     ← 独立。~/bin/ の ocw, claude-ds をコピー
  孫1 (claude/)  ← 独立。~/.claude/ の CLAUDE.md, settings.json をコピー

フェーズ2（孫1マージ後に着手）:
  孫2 (skills)   ← 孫1 の claude/deploy.sh を拡張するため、孫1マージ必須

フェーズ3（孫0,1,2 全マージ後に着手）:
  孫3 (shared)   ← AVAILABLE_TOOLS に bin claude 追加

フェーズ4（全孫マージ後に着手）:
  孫4 (docs+test) ← ドキュメント更新 + 実マシンデプロイテスト
```

## 除外するもの

- herdr スキル (`~/.agents/skills/herdr/`): Herdr が管理
- herdr-agent-state.sh (`~/.claude/hooks/`): Herdr が管理
- `permissions.allow`: マシン固有パス多数のため（ユーザーは `settings.local.json` で追加する）
- `permissions.additionalDirectories`: 同上
- hooks: herdr-agent-state.sh のみで Herdr 管理下のため（ユーザーは `settings.local.json` で追加する）

## ローカル拡張の基本方針

各ツールはユーザーがマシン固有の設定を追加できるよう、以下の拡張ポイントを確保する:

| ツール | 拡張メカニズム | ドキュメント |
|--------|--------------|------------|
| bin (ocw) | 環境変数 `OCW_COMMANDER_COMMAND`, `OCW_IMPLEMENTER_COMMAND`, `OCW_REVIEWER_COMMAND` | README に記載 |
| claude (CLAUDE.md) | symlink 先を直接編集すれば即反映 | README に記載 |
| claude (settings.json) | `claude/settings.machine.json` にマシン固有設定を記述。deploy.sh がベース設定とマージして `~/.claude/settings.json` を生成（実ファイル）。`~/.claude/settings.local.json` はユーザーレベルでは読まれないため非推奨 | README に記載 |
| claude/skills | スキルは**個別 symlink**。`~/.claude/skills/` に手動で置いた独自スキルと共存可能。deploy.sh は `claude/skills/` 内の全ディレクトリを自動検出 | README に記載 |
| shared/helpers.sh | AVAILABLE_TOOLS 編集はファイル1行変更で済む。必要に応じてユーザーが直接編集 | README に記載 |

## 孫0用プロンプト:

```
## タスク: bin/ ディレクトリを追加し自作ツールを移行する

### やること

#### 1. bin/ ディレクトリ構造を作成
```
bin/
├── ocw
├── claude-ds
├── deploy.sh
└── README.md
```

#### 2. ocw スクリプト
- `~/bin/ocw` からコピー
- **デフォルトの `OCW_COMMANDER_COMMAND` と `OCW_IMPLEMENTER_COMMAND` を `claude` に変更する**
  - 現在の `claude-ds` を `claude` に修正
- それ以外の機能は現状維持
- 環境変数による上書き設計は維持（ユーザーは `export OCW_COMMANDER_COMMAND=claude-ds` で戻せる）

#### 3. claude-ds スクリプト
- `~/bin/claude-ds` からコピー
- 現状維持でOK
- `DEEPSEEK_API_KEY_FILE` 環境変数で API キー設定可（デフォルト `~/.config/deepseek/api_key`）

#### 4. deploy.sh
- `~/bin/` に symlink を作成
- `~/bin/` ディレクトリがなければ作成
- `shared/helpers.sh` を source して使う
- 既存の deploy.sh（zsh/, nvim/, tmux/）のパターンに従う
- **AVAILABLE_TOOLS にはまだ追加しない**（孫3で対応）

#### 5. README.md
- ocw と claude-ds の説明
- セットアップ手順
- 他のツールディレクトリのREADMEフォーマットに合わせる

### 重要なファイル（新規作成）
- `bin/ocw`
- `bin/claude-ds`
- `bin/deploy.sh`
- `bin/README.md`
```

## 孫1用プロンプト:

> ※ この節は着手時のプロンプトの記録です。`settings.local.json` 方式は実装レビューで
> 「ユーザーレベルでは読まれない」ことが実測で判明したため、`claude/settings.machine.json`
> マージ方式に変更しました。現行仕様は `claude/README.md` を参照してください。

```
## タスク: claude/ ディレクトリを追加し Claude Code 設定を移行する

### やること

#### 1. claude/ ディレクトリ構造を作成
```
claude/
├── CLAUDE.md
├── settings.json
├── deploy.sh
└── README.md
```

#### 2. CLAUDE.md
- `~/.claude/CLAUDE.md` から内容をコピー（現在の個人設定をそのまま移行）
- デプロイ先: `~/.claude/CLAUDE.md` への symlink

#### 3. settings.json
- `~/.claude/settings.json` からコピーし、以下を**除去**（マシン固有のため）:
  - `permissions.allow`（33件、すべて特定パス）
  - `permissions.additionalDirectories`
  - `hooks`（herdr-agent-state.sh のみで Herdr 管理下）
- 以下の汎用設定は**保持**:
  - `permissions.deny`（.env, .ssh, .aws 等のセキュリティポリシー、全マシン共通）
  - `permissions.ask`（危険コマンドパターン、全マシン共通）
  - `permissions.defaultMode`
  - `model`
  - `language`
  - `effortLevel`
  - `theme`
  - `editorMode`
  - `autoCompactEnabled`
  - `switchModelsOnFlag`
  - `skipWorkflowUsageWarning`
- デプロイ先: `~/.claude/settings.json` への symlink

#### 4. deploy.sh
- `shared/helpers.sh` を source して使う
- 各ファイルを `~/.claude/` に symlink
- 既存の deploy.sh パターンに従う

#### 5. README.md
- CLAUDE.md と settings.json の説明
- セットアップ手順
- **「マシン固有設定の追加」セクションを必須で記載**:
  - `~/.claude/settings.local.json` を作成することで settings.json を上書き・拡張できること
  - `permissions.allow` の追加方法（具体例付き）
  - hooks の追加方法
  - model/theme の上書き方法
  - **既知の注意点**: `permissions` は deep merge されず replace される場合があるバグ。`permissions.deny` を settings.local.json に書く場合は `settings.json` 側の deny もコピーしてから追加すること
  - CLAUDE.md は直接編集してOK（個人設定のため）

### 重要なファイル（新規作成）
- `claude/CLAUDE.md`
- `claude/settings.json`
- `claude/deploy.sh`
- `claude/README.md`
```

## 孫2用プロンプト:

```
## タスク: Claude Code スキルを dotfiles に移行する

### やること

#### 1. claude/skills/ ディレクトリ構造を作成
```
claude/skills/
├── pr-review-loop/
│   └── SKILL.md
└── umbrella-orchestrator/
    └── SKILL.md
```

#### 2. pr-review-loop スキル
- `~/.claude/skills/pr-review-loop/SKILL.md` から内容をコピー
- 現状維持でOK

#### 3. umbrella-orchestrator スキル
- `~/.claude/skills/umbrella-orchestrator/SKILL.md` から内容をコピー
- 現状維持でOK

#### 4. デプロイ設計（重要）
- **ディレクトリ全体 symlink は禁止。** `~/.claude/skills → repo/claude/skills` にすると、Herdr 管理の herdr スキルやユーザー独自スキルが消える
- **スキルごとに個別 symlink する**:
  ```
  ~/.claude/skills/pr-review-loop → repo/claude/skills/pr-review-loop
  ~/.claude/skills/umbrella-orchestrator → repo/claude/skills/umbrella-orchestrator
  ~/.claude/skills/herdr → (そのまま、Herdr管理)
  ```
- **claude/deploy.sh を拡張**し、`claude/skills/` 内の全ディレクトリを自動検出して個別 symlink するロジックを追加する
- こうすることで将来スキルが増えても deploy.sh を修正する必要がなくなる

#### 5. 注意
- **herdr スキルは対象外**（Herdr 管理下のため。`~/.claude/skills/herdr/` は手付かずで残る）

#### 6. claude/README.md への追記
- 独自スキルの追加方法: `~/.claude/skills/my-skill/SKILL.md` を手動で作るだけ
- deploy.sh が上書きしないことを明記

### 重要なファイル
- `claude/skills/pr-review-loop/SKILL.md`（新規）
- `claude/skills/umbrella-orchestrator/SKILL.md`（新規）
- `claude/deploy.sh`（拡張: スキル自動検出 + 個別 symlink ロジック追加）
- `claude/README.md`（追記）
```

## 孫3用プロンプト:

```
## タスク: shared/helpers.sh の AVAILABLE_TOOLS を更新する

### やること

#### 1. shared/helpers.sh の AVAILABLE_TOOLS を拡張
現在:
```bash
AVAILABLE_TOOLS="zsh nvim tmux"
```
これを以下に変更:
```bash
AVAILABLE_TOOLS="zsh nvim tmux bin claude"
```

#### 2. 影響確認
- `deploy-all.sh` の `--only` フィルタで `bin` と `claude` が指定可能になることを確認
- 既存の挙動が壊れないことを確認（zsh, nvim, tmux が引き続き動作する）

### 重要なファイル（変更）
- `shared/helpers.sh` — AVAILABLE_TOOLS の1行変更のみ
```

## 孫4用プロンプト:

```
## タスク: README 更新、全体統合確認、実マシンデプロイテスト

### やること

#### 1. ルート README.md の Supported Tools テーブルに bin と claude を追加
現在のテーブルに以下を追加:
- bin（自作CLIツール: ocw, claude-ds）
- claude（Claude Code 設定とスキル）

#### 2. deploy-all.sh から全 deploy.sh が正しく呼ばれることを確認
- `bin/deploy.sh` が deploy-all.sh から呼ばれること
- `claude/deploy.sh` が deploy-all.sh から呼ばれること
- `--only bin`, `--only claude`, `--only bin,claude` が正しく動作すること
- 全ツール一括デプロイが正常に完了すること

#### 3. ドキュメントの整合性確認
- 全READMEのフォーマット統一
- リンク切れがないこと
- 手順の正確性

#### 4. 実マシンデプロイテスト（最重要）
**PRマージ前に、このマシンで実際にデプロイを試して動作確認する。**

a) **事前バックアップ**:
```bash
mkdir -p ~/dotfiles-backup-$(date +%Y%m%d)
cp ~/bin/ocw ~/dotfiles-backup-$(date +%Y%m%d)/ 2>/dev/null
cp ~/bin/claude-ds ~/dotfiles-backup-$(date +%Y%m%d)/ 2>/dev/null
cp ~/.claude/CLAUDE.md ~/dotfiles-backup-$(date +%Y%m%d)/ 2>/dev/null
cp ~/.claude/settings.json ~/dotfiles-backup-$(date +%Y%m%d)/ 2>/dev/null
cp -r ~/.claude/skills/ ~/dotfiles-backup-$(date +%Y%m%d)/skills/ 2>/dev/null
```

b) **デプロイ実行**:
```bash
./deploy-all.sh --only bin,claude --force
```

c) **動作確認チェックリスト**:
- [ ] `~/bin/ocw` が実行可能で `claude` がデフォルトコマンドになっている
- [ ] `~/bin/claude-ds` が実行可能
- [ ] `~/.claude/CLAUDE.md` が symlink で内容が正しい
- [ ] `~/.claude/settings.json` が deploy.sh で生成された実ファイルで汎用設定のみ含まれている（allowリストがない）
- [ ] `~/.claude/skills/pr-review-loop/SKILL.md` が symlink で存在
- [ ] `~/.claude/skills/umbrella-orchestrator/SKILL.md` が symlink で存在
- [ ] `~/.claude/skills/herdr/` が手付かずで残っている（削除されていない）
- [ ] `deploy-all.sh --only zsh,nvim,tmux` が従来通り動作（bin/claude追加で壊れてない）
- [ ] `deploy-all.sh` 全ツール一括が正常完了

d) **問題があれば修正**:
- 動作確認で問題が見つかったら、このブランチで修正する
- 修正後、再度デプロイテストを行う
- すべてのチェック項目がパスするまで繰り返す

e) **バックアップからの復元手順もREADMEに記載**（万一のため）

### 重要なファイル（変更）
- `README.md` — Supported Tools テーブル更新
- `deploy-all.sh` — 必要に応じて更新
```
