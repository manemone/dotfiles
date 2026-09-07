# Codex CLI Global Instructions (codex)

## Overview

[OpenAI Codex CLI](https://developers.openai.com/codex/cli) のグローバル指示ファイル
（`~/.codex/AGENTS.md`）を配布する。このディレクトリ自体には内容ファイルが無く、
`deploy.sh` が [`claude/CLAUDE.md`](../claude/README.md) を symlink で指す。内容は
エージェント名を問わない個人指示（口調設定・傘ブランチ引き継ぎの発動条件）であり、
1ファイルを複数エージェントへ配る構造にした理由は
[ADR DOC-2609072334](../docs/adr/DOC-2609072334_codex-opencode-global-instructions-distribution.md)
を参照。

| File | Purpose | Deploy Method |
|---|---|---|
| （なし。`../claude/CLAUDE.md` を参照） | Codex の個人指示（プロジェクト横断のグローバル指示） | symlink |

## 1. Requirements

| Tool | Why | Install |
|---|---|---|
| **Codex CLI** | 設定ファイルの読み取り元 | 各自インストール |

`~/.codex/` が存在しないマシンでは、このツールは何もしない（Codex 未導入とみなし、
ディレクトリを新規作成しない。[ADR DOC-2608272128](../docs/adr/DOC-2608272128_skills-multi-agent-distribution.md)
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
ls -la ~/.codex/AGENTS.md         # symlink（current 経由。claude/CLAUDE.md と同じ実体）
```

すでに一度 `deploy-all.sh` を実行済みで `current` が存在する状態であれば、
`codex/` ディレクトリから単体の `./deploy.sh` を実行しても構いません。

> **⚠️ 重要**: `~/.codex/AGENTS.md` が既に実ファイルとして存在する場合、deploy 実行時に
> バックアップ（`.backup` 付きで退避）されます。dotfiles 導入前に手作業で書いた内容が
> あれば、退避先から内容を確認したうえで `claude/CLAUDE.md` へ統合してください。

## 3. What's Included

`~/.codex/AGENTS.md` は Codex が起動時に読み込むグローバルな個人指示。中身は
[`claude/README.md`](../claude/README.md) の CLAUDE.md の節を参照（同一ファイルの symlink
のため内容は完全に一致する）。編集する場合は `claude/CLAUDE.md` を編集すること
（`codex/` 配下には編集対象のファイルが無い）。
