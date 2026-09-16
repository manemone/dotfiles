# Codex CLI Global Instructions (codex)

## Overview

[OpenAI Codex CLI](https://developers.openai.com/codex/cli) のグローバル指示ファイル
（`${CODEX_HOME:-$HOME/.codex}/AGENTS.md`）を配布する。このディレクトリ自体には内容
ファイルが無い。`deploy.sh` は [`claude/CLAUDE.md`](../claude/README.md) と
このマシンの人格のパーソナライズ実体（`CLAUDE.machine.md`）を**連結生成**した実ファイルを
世代を経由しない固定パスへ作り、`AGENTS.md` をそこへ symlink する。1ファイルを複数
エージェントへ配る基本構造にした理由は
[ADR DOC-2609072334](../docs/adr/DOC-2609072334_codex-opencode-global-instructions-distribution.md)、
Codex だけ連結生成が要る理由（Codex には `@include` 相当の追加読み込み手段が無く、
`AGENTS.override.md` は存在しても**置き換え**であって追加読み込みではないことを確認済み）は
[ADR DOC-2609162327](../docs/adr/DOC-2609162327_claude-md-machine-local-tone.md) §6 を参照。

| File | Purpose | Deploy Method |
|---|---|---|
| （なし。`../claude/CLAUDE.md` + `CLAUDE.machine.md` から生成） | Codex の個人指示（プロジェクト横断のグローバル指示 + 人格のパーソナライズ） | 生成 + symlink |

## 1. Requirements

| Tool | Why | Install |
|---|---|---|
| **Codex CLI** | 設定ファイルの読み取り元 | 各自インストール |

`${CODEX_HOME:-$HOME/.codex}` が存在しないマシンでは、このツールは何もしない（Codex
未導入とみなし、ディレクトリを新規作成しない。
[ADR DOC-2608272128](../docs/adr/DOC-2608272128_skills-multi-agent-distribution.md)
§2.3 と同じ判断基準）。

## 2. Quick Start

初回（新規マシン、まだ何もデプロイしていない状態）は、単体の `codex/deploy.sh` ではなく
必ずリポジトリルートの `deploy-all.sh` を実行してください。単体実行は配布実体
（`current`）経由でしか読まないため、`current` がまだ無い新規マシンではエラーで終了します
（詳細はルート `AGENTS.md`「デプロイの仕組み」節を参照）。

```bash
# 1. リポジトリルートから実行（初回は必ずこちら）
cd ~/.dotfiles
./deploy-all.sh --only codex

# 2. Verify
ls -la ${CODEX_HOME:-$HOME/.codex}/AGENTS.md   # symlink（current 経由ではなく、世代を経由しない固定パスの生成物へ）
```

すでに一度 `deploy-all.sh` を実行済みで `current` が存在する状態であれば、
`codex/` ディレクトリから単体の `./deploy.sh` を実行しても構いません。

> **⚠️ 重要**: `${CODEX_HOME:-$HOME/.codex}/AGENTS.md` が既に実ファイルとして存在する場合、
> deploy 実行時にバックアップ（`.backup` 付きで退避）されます。dotfiles 導入前に手作業で
> 書いた内容があれば、退避先から内容を確認したうえで `claude/CLAUDE.md` へ統合してください。

## 3. What's Included

`AGENTS.md` は Codex が起動時に読み込むグローバルな個人指示。中身は
[`claude/CLAUDE.md`](../claude/README.md) をベースに、このマシンの人格のパーソナライズ
（`~/.claude/CLAUDE.machine.md`。実体は世代を経由しない固定パス）を**連結生成**したもの。
`claude/CLAUDE.md` 側の `@~/.claude/CLAUDE.machine.md`（Claude Code の import 記法）は
Codex にとって意味を持たないため、生成時にその行を `CLAUDE.machine.md` の中身へ置き換える。

- **プロジェクト横断のグローバル指示そのもの**（傘ブランチ引き継ぎの発動条件等）を編集する場合は
  `claude/CLAUDE.md` を編集すること（`codex/` 配下には編集対象のファイルが無い）
- **人格のパーソナライズ**（口調など）を変える場合は `persona` コマンド（`bin/persona`）を使う。
  `persona` は `$EDITOR` で `CLAUDE.machine.md` を開き、閉じると自動でこの生成物を再生成する。
  編集せず再生成だけしたい場合は `persona --regen`
- どちらの場合も **redeploy は不要**（Claude Code / OpenCode は `CLAUDE.machine.md` を
  live に読むため即座に反映され、Codex は `persona` 自身が再生成する）
- 生成物は世代の外（`${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/codex/AGENTS.md`）に
  置かれる。dev モード中も含め、どの世代がデプロイされているかに関わらず同じ生成物を指す
