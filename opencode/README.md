# OpenCode Global Instructions (opencode)

## Overview

[OpenCode](https://opencode.ai) のグローバル指示ファイル
（`${XDG_CONFIG_HOME:-$HOME/.config}/opencode/AGENTS.md`）を配布する。このディレクトリの
`AGENTS.md` 自体には内容ファイルが無く、`deploy.sh` が [`claude/CLAUDE.md`](../claude/README.md) を
symlink で指す。内容はエージェント名を問わない個人指示（人格のパーソナライズ・傘ブランチ
引き継ぎの発動条件）であり、1ファイルを複数エージェントへ配る構造にした理由は
[ADR DOC-2609072334](../docs/adr/DOC-2609072334_codex-opencode-global-instructions-distribution.md)
を参照。

OpenCode は自身の `AGENTS.md` が無い場合に `~/.claude/CLAUDE.md` をフォールバックとして
読む（[公式ドキュメント](https://opencode.ai/docs/rules/)）。このツールを配ることで、
その暗黙のフォールバックに頼らず明示的に配布された指示を読ませる。

`opencode.json` はこのディレクトリが持つ唯一の内容ファイルで、OpenCode の `instructions`
機構を使い、マシンローカルな人格のパーソナライズ（`~/.claude/CLAUDE.machine.md`。
[claude/README.md](../claude/README.md) 参照）を OpenCode にも効かせる（設計は
[ADR DOC-2609162327](../docs/adr/DOC-2609162327_claude-md-machine-local-tone.md) §5）。
詳細は下記「4. Machine-local personalization」を参照。

| File | Purpose | Deploy Method |
|---|---|---|
| （なし。`../claude/CLAUDE.md` を参照） | OpenCode の個人指示（プロジェクト横断のグローバル指示） | symlink |
| `opencode.json` | OpenCode の `instructions` に `~/.claude/CLAUDE.machine.md` を列挙し、マシンローカルな人格のパーソナライズを効かせる | symlink |

## 1. Requirements

| Tool | Why | Install |
|---|---|---|
| **OpenCode** | 設定ファイルの読み取り元 | 各自インストール |

`${XDG_CONFIG_HOME:-$HOME/.config}/opencode/` が存在しないマシンでは、このツールは何も
しない（OpenCode 未導入とみなし、ディレクトリを新規作成しない。
[ADR DOC-2608272128](../docs/adr/DOC-2608272128_skills-multi-agent-distribution.md)
§2.3 と同じ判断基準）。

## 2. Quick Start

初回（新規マシン、まだ何もデプロイしていない状態）は、単体の `opencode/deploy.sh` ではなく
必ずリポジトリルートの `deploy-all.sh` を実行してください。単体実行は配布実体
（`current`）経由でしか読まないため、`current` がまだ無い新規マシンではエラーで終了します
（詳細はルート `AGENTS.md`「デプロイの仕組み」節を参照）。

```bash
# 1. リポジトリルートから実行（初回は必ずこちら）
cd ~/.dotfiles
./deploy-all.sh --only opencode

# 2. Verify
ls -la ~/.config/opencode/AGENTS.md       # symlink（current 経由。claude/CLAUDE.md と同じ実体）
ls -la ~/.config/opencode/opencode.json   # symlink（current 経由。opencode/opencode.json と同じ実体）
```

すでに一度 `deploy-all.sh` を実行済みで `current` が存在する状態であれば、
`opencode/` ディレクトリから単体の `./deploy.sh` を実行しても構いません。

> **⚠️ 重要**: `${XDG_CONFIG_HOME:-$HOME/.config}/opencode/AGENTS.md` や
> `${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json` が既に実ファイルとして
> 存在する場合、deploy 実行時にバックアップ（`.backup` 付きで退避）されます。
> 既存の `opencode.json` を他の用途（MCP サーバー設定など）で使っている環境では、
> deploy 後にその内容が `.backup` へ退避されている点に注意してください
> （マージは行わない。理由は ADR DOC-2609162327 §5 を参照）。

## 3. What's Included

`AGENTS.md` は OpenCode が起動時に読み込むグローバルな個人指示。中身は
[`claude/README.md`](../claude/README.md) の CLAUDE.md の節を参照（同一ファイルの symlink
のため内容は完全に一致する）。編集する場合は `claude/CLAUDE.md` を編集すること。

`opencode.json` は本ディレクトリの `opencode/opencode.json` を symlink で配ったもの。
編集する場合はそちら（トラッキング対象）を編集すること。

## 4. Machine-local personalization

人格のパーソナライズ（口調・一人称/二人称・キャラクター付けなど）をマシンローカルに
カスタマイズする方法は [claude/README.md](../claude/README.md) と同じ:
`~/.claude/CLAUDE.machine.md`（実体は `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/CLAUDE.machine.md`
という固定パス）を直接編集する。**deploy は不要。**

`opencode/opencode.json` の `instructions` 配列が `~/.claude/CLAUDE.machine.md` を直接
指しているため、Claude Code 向けに書き換えた内容がそのまま OpenCode にも反映される
（両エージェントが同じ実体ファイルを読む）。

**この参照先が `~/.claude/CLAUDE.machine.md`（Claude Code 側の symlink）である理由**:
OpenCode の `instructions` 内の `~/` は `$HOME` からの展開であり、
`$XDG_CONFIG_HOME`（既定は `$HOME/.config` だがマシンごとに変更され得る）からの展開では
ない。もし本ディレクトリ自身の配下（`~/.config/opencode/...` のような既定値決め打ちの
パス）を指していたら、`XDG_CONFIG_HOME` をカスタマイズしているマシンで静かに解決しなく
なる。`~/.claude` は `XDG_CONFIG_HOME` に依存しない固定パスのため、この参照はどのマシン
でも崩れない。

**トレードオフ**: `--only opencode` のように `claude` を一度もデプロイしていないマシンでは
`~/.claude/CLAUDE.machine.md` がまだ存在しないため、この `instructions` エントリは
（OpenCode 側で）単に何も解決しない。エラーにはならず、`CLAUDE.machine.md` が空の場合と
同じ「パーソナライズ指定なし」がデフォルトになる。詳細と検証根拠は
[ADR DOC-2609162327](../docs/adr/DOC-2609162327_claude-md-machine-local-tone.md) §5 を参照。

**`~/.config/opencode/opencode.jsonc` について**: OpenCode 自身の設定UI（デスクトップ/Web
アプリの provider 設定など）は、`opencode.jsonc` / `opencode.json` / `config.json` のうち
存在する最初のファイルへ書き込みます。このディレクトリが配る `opencode.json` は symlink
（配布物）なので、そこへ書き込ませるとマシン固有の設定・場合によっては認証情報が
配布物へ紛れ込みます。それを避けるため、deploy はこれら3ファイルがどれも無いマシンでは
`opencode.jsonc`（`{"$schema": "https://opencode.ai/config.json"}` のみの空の実ファイル）を
先に作ります。これは**このリポジトリの追跡対象ではない、マシンローカルなファイル**です
（`opencode/deploy.sh`）。**設定UIでの変更はこの `opencode.jsonc` へ書かれ、`opencode.json`
（配布物）には触れません。**

**⚠️ `opencode.jsonc` に独自の `instructions` がある場合の注意**: OpenCode はグローバル設定を
`config.json` → `opencode.json` → `opencode.jsonc` の順に重ね合わせて読み込み、
後から読んだ側（`opencode.jsonc`）が優先されます。オブジェクトのキー単位で上書きされ、
配列（`instructions` を含む）は連結されず丸ごと置き換わります。そのため、
`opencode.jsonc` に独自の `instructions` を書いている環境（deploy が作った上記の
schema-only な `opencode.jsonc` を手で書き換えた場合や、deploy より前から別の目的で
`opencode.jsonc` を使っていた場合）では、このディレクトリが配る `opencode.json` の
`instructions`（`~/.claude/CLAUDE.machine.md`）が**エラーも警告も出さずに無視されます**。
deploy 時に `opencode.jsonc` に `instructions` キーがあるかどうかを検出して警告します
（`opencode/deploy.sh`。中身は `"instructions"` という文字列の有無を見るだけで、JSONC の
構文解析はしません）。警告が出た場合は、`opencode.jsonc` 側の `instructions` にも
`~/.claude/CLAUDE.machine.md` を追記してください。決着の詳細は
[ADR DOC-2609162327](../docs/adr/DOC-2609162327_claude-md-machine-local-tone.md) §5.3 を参照。
