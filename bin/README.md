# CLI Tools (bin)

## Overview

自作 CLI ツール集。`~/bin/` に symlink して使う。

| Tool | Purpose |
|---|---|
| `ocw` | Git worktree 作成・管理。Herdr 連携で commander/implementer/reviewer の三面体制を自動セットアップ |
| `claude-ds` | Claude Code を DeepSeek API 経由で実行するラッパー |
| `ocw-meter` | LLM費用・Claude利用枠の観測基盤。既存ログの事後読み取り専用。fail-open |

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
- Symlinks `ocw`, `claude-ds`, and `ocw-meter` into `~/bin/`

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

**工程計測（`ocw-meter` 連携。fail-open）:**

worktree作成のたびに `run_id` を採番し、標準出力に `run:` 行として表示する。
`run_id` は worktree の git管理領域（`git -C <worktree> rev-parse --absolute-git-dir` が指す
`.git/worktrees/<slug>/ocw-run-id`。git worktreeの削除時に自動で掃除される、リポジトリには一切入らない場所）
に保存され、`ocw rm` 実行時にそこから読み戻されて `run.end` イベントの記録に使われる。

Herdrモードでは、commander/implementer/reviewer の各ペイン起動時に環境変数
`OCW_ROLE`（`commander`/`implementer`/`reviewer`）と `OCW_RUN_ID` が `herdr workspace create --env` /
`herdr pane split --env` 経由で自動的に渡される。`ocw-meter event` はこれらの環境変数を
自動的に読み取り役割・runを紐付けるため、呼び出し側で明示的に指定する必要はない。

**非Herdrモード（`ocw <name>`、VS Codeを開く既定モード）では `OCW_RUN_ID` は自動では渡らない。**
`run_id` は `run:` 行と `ocw-run-id` ファイルには保存されるが、それを読んで環境変数へ載せる主体が
Herdrのペイン起動以外に存在しないため、そのworktree内で動く `ocw-meter event`（`pr-review-loop` の
工程イベント等）は明示的にexportしない限り `run_id: null` として記録される。紐付けたい場合は
worktree内で以下を実行してから作業を始めること:

```bash
export OCW_RUN_ID="$(cat "$(git rev-parse --absolute-git-dir)/ocw-run-id" 2>/dev/null)"
```

`ocw-meter` が PATH に無い場合、`run:` 行と `ocw-run-id` の保存は変わらず行われる
（純粋なgit/bashロジックのため）が、`ocw-meter event` 呼び出しは `command -v` ガードにより静かにスキップされ、
`ocw` 自体の動作・終了コードには一切影響しない。`ocw-meter` はあるがそのイベントの書き込みだけが失敗する場合
（例: `OCW_METER_HOME` が読み取り専用）も、`run_id` の採番・`run:` 出力・`ocw-run-id` の保存・`ocw` 自体の
終了コードは影響を受けない（fail-open）。ただし `ocw-meter` 自身は書き込み失敗を stderr に1行warnとして出す
設計（`bin/ocw-meter` 自身の既知の限界。誤りを隠さない方針のため）であり、これは `ocw` の出力への追加として
現れうる。

**`run.end` が記録されない run が存在しうる**（best-effort の限界）: `ocw rm` は「未マージ」「未コミット
変更あり」等で `die` して停止する経路が複数あり、そこに到達する前に停止した場合は `run.end` が一切
記録されない。`ocw rm -f` は完了時に必ず記録するが、その `outcome` は `failure`（`-f` は「未マージ・未コミット
のまま強制的に捨てる」経路であり、通常の `rm` の `success` と区別する）になる。

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

### 3.3 ocw-meter — LLM費用・Claude利用枠の観測基盤

`ocw` / `claude-ds` / `pr-review-loop` の**本番経路には一切割り込まない**、事後読み取り専用の観測ツール。
詳細設計は `docs/planning/DOC-003_ai-llm-cost-observability_計画.md` を参照。

**観測は fail-open。`ocw-meter` が無くても、PATH から消えても、書き込みに失敗しても、
本スキル・`ocw` は完全に動作し続ける。** 呼び出し側は必ず次の形で呼ぶ:

```bash
command -v ocw-meter >/dev/null && ocw-meter event ... || true
```

```bash
# 任意のイベントを1行append（--key value で任意フィールドを上書き・追加可能）
ocw-meter event <event_type> [--key value ...]

# PRの後付けbind（run_id → PR番号）
ocw-meter bind-pr --run <run_id> --pr <n> [--url <url>]

# 保存済みイベントのschema検証。壊れた行はquarantineへ隔離
ocw-meter validate [--file <path>]

# イベント件数・completeness・coverageの要約（骨格。費用集計は後続フェーズ）
ocw-meter report [--pr <n>] [--json]
```

| サブコマンド | 失敗時の挙動 |
|---|---|
| `event` / `bind-pr` | **常に exit 0**。stderrに1行warnのみ。本番フローを止めない |
| `validate` / `report` | 失敗したら非ゼロで落ちる（壊れたデータを黙って集計しない） |

**保存先と環境変数:**

| Variable | Default | Purpose |
|---|---|---|
| `OCW_METER_HOME` | `~/.local/state/ocw-meter` | 保存先ルート。**git worktree内を指すと拒否される**（誤commit防止）。`event`/`bind-pr`は書き込みをスキップして exit 0（設定ミスが誰にも気づかれないままにならないよう、既定の保存先へ `meter.error` を1件/日で記録し、fallbackした旨をstderrに警告する）、`validate`/`report`は非ゼロで停止する |
| `OCW_METER_RAW` | `0` | 予約済み（将来フェーズのopt-in raw保存用）。現時点のサブコマンドでは未使用 |

保存レイアウト: `events/YYYY-MM-DD.jsonl`（基本はappend-only, mode 600。**例外**: 同一`idempotency_key`を再送すると
後勝ち(last-write-wins)でその日のファイル内の該当行をmkstemp+os.replaceで原子的に置き換える）/
`state/seen-keys/YYYY-MM.txt`（`idempotency_key`による重複排除）/
`quarantine/YYYY-MM-DD.jsonl`（schema不正・破損行の隔離先）/ `state/meter-errors.jsonl`（`meter.error`自己診断専用。
`events/`とは別ファイルにすることで、後勝ちdedupによるイベントファイル書き換えと競合せずlock無しで追記できる）。
ディレクトリは mode 700。`ocw-meter report` はこのファイルの件数も表示する。

**プライバシー方針**: プロンプト全文・モデル応答全文・ソースコード本文・APIキー・認証ヘッダ・トークン類は
一切保存しない。`--key value` で渡された値のうち `sk-...`（任意長）/ `Bearer ...` / `Authorization: ...` /
GitHub token形式（`ghp_...` 等 / `github_pat_...`）に一致する値、キー名が
`api_key` / `token` / `secret` / `password` / `authorization` に一致するものは保存前に `[REDACTED]` へ置換される。
この置換は保存物だけでなく、meterが出す例外・警告メッセージにも適用される。

**このフェーズでの既知の限界**:
- `ingest`（DeepSeek transcript取り込み）と `snapshot-quota`（Claude利用枠取得）はまだ実装されていない。
  `report` の費用・coverage列はプレースホルダで、実データは後続フェーズで入る
- `event`/`bind-pr` は1呼び出しごとに git メタ情報の解決（subprocess呼び出し数回）と
  月次seen-keysファイルの全読み込みを行う（実測 約75ms/回）。`ocw`/`pr-review-loop` の工程境界イベント
  （1runあたり数十件）には十分だが、**大量イベントをループでこのCLI経由で書き込む用途（将来のbulk ingest等）には
  向かない**。そのような用途は同一プロセス内でgitメタとseen-key集合を1度だけ解決するバッチ経路を別途持つこと

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
