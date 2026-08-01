# 計画書: LLM費用・Claude利用枠の観測基盤（ocw-meter）

傘ブランチ: `ai/llm-cost-observability`
ターゲット: `master`
作成日: 2026-08-01
依頼書: `tmp/DOC-202608011608-claude-code-llm-cost-observability-planning-prompt.md`

---

## 1. Executive summary

**結論: 大がかりなgatewayもDBも不要。必要なデータの大半は既にローカルに存在している。**

調査の結果、以下が実測で確認できた。

- Claude Code は全セッションの全アシスタントメッセージを `~/.claude/projects/<slug>/<session-id>.jsonl` に追記しており、
  各メッセージに `model` と `usage`（`input_tokens` / `cache_read_input_tokens` / `cache_creation_input_tokens` / `output_tokens`）が入っている。
- これは **DeepSeek 経由（`claude-ds`）でも全く同じ形式で記録されている**。DeepSeek の Anthropic互換エンドポイントは
  `cache_read_input_tokens` を正しく返しており、キャッシュhit/missを分離した費用換算が既存ログだけで可能。
- Claude の 5時間枠・週間枠は **statusLine コマンドの stdin JSON に `rate_limits.five_hour.used_percentage` /
  `resets_at` / `seven_day` として機械可読で渡ってくる**。`/usage` の TUI をパースする必要はない。
- Herdr の `herdr pane list` は `label`（= commander/implementer/reviewer）と `agent_session.value`（= Claude の session_id）と
  `cwd` / `workspace_id` を同時に返す。役割とセッションの結合キーが既に存在する。
- transcript には `type: "pr-link"` エントリ（`prNumber` / `prUrl` / `prRepository`）があり、
  セッション → PR の紐付けも既に記録されている。

したがって第一段階の設計は次の一点に集約される。

> **観測はAPI経路に一切割り込まず、既存ログの「事後読み取り」で行う。
> ワークフローに追加するのは、ログに書かれない情報（工程・ラウンド・役割の境界）を刻む軽量イベントだけ。**

これにより「観測が本番フローを止める」リスクが構造的にゼロに近づく（読み取り側が壊れてもレビューループは無傷）。

### 全transcript（330ファイル / 39,805メッセージ）からの実測サマリ

| model | msgs | cache miss入力 | cache read入力 | cache create入力 | 出力 |
|---|---|---|---|---|---|
| `deepseek-v4-pro` | 29,676 | 38,336,862 | 5,428,087,040 | 0 | 11,983,028 |
| `claude-opus-4-8` | 7,298 | 362,517 | 1,295,799,788 | 33,506,182 | 7,246,760 |
| `claude-opus-5` | 2,448 | 4,611 | 357,823,943 | 9,235,398 | 2,428,983 |
| `claude-fable-5` | 282 | 30,019 | 21,338,804 | 893,461 | 273,868 |

現行価格表（後述）でDeepSeek分を換算すると **概算 $46.8**（全期間）。7月請求 $58.80 と同オーダーで整合する。

**最重要の示唆**: DeepSeekのトークンの **99.3%はキャッシュhit**（5.43B / 5.47B）で、単価は120分の1。
費用ドライバーは総トークン数ではなく **cache missトークン（= プロンプト先頭の変化によるキャッシュ破棄）と出力トークン** である。
「compactでコンテキストを削る」は費用対策として的外れである可能性が高く、依頼書の「compactを安易に採用しない」方針を数字が支持している。

---

## 2. Problem statement

### 元の目的

1. 月間LLM費用を抑える
2. Claudeの5時間枠に引っかかって作業が止まる頻度を下げる

ただしレビュー品質・自動運転性を落とさない。

### 現状の問題

7月実績 $108.80（ChatGPT Plus $20 / Claude Pro $20 / OpenCode Go $10 / DeepSeek API $58.80）のうち、
変動費であるDeepSeek $58.80 の内訳が **PR別・工程別・役割別に一切分からない**。

- 初回実装 / 自己レビュー / 修正往復 のどれが金を食っているのか不明
- Claude 5時間枠を初回レビューで使い切っているのか、別作業で使っているのか不明
- 1PRを同一5時間枠で完走できているのかも計測されていない

**最適化案を評価する物差しが無いまま最適化を実装するのは、賭けであって改善ではない。**
よって第一段階は最適化を実装せず、スコアブックだけを作る。

---

## 3. Current architecture（実装確認済み）

### 3.1 `bin/ocw`（704行）

- `ocw [-H|--herdr] <worktree-name> [base-ref]` で `git worktree add -b ai/<slug>` を実行
- `-H` 時は Herdr に workspace を作り、`commander` / `implementer` / `reviewer` の3ペインを
  **同一worktree cwd** で作成し、それぞれ `$OCW_{COMMANDER,IMPLEMENTER,REVIEWER}_COMMAND`（既定 `claude`）を起動
- ペイン名は `herdr pane rename` で `commander` / `implementer` / `reviewer` に固定される
- 標準出力に `workspace:` / `commander:` / `implementer:` / `reviewer:` の各IDを出力
- Herdrセットアップ失敗時は worktree ごとロールバックする

### 3.2 `bin/claude-ds`（35行）

`~/.config/deepseek/api_key` を読み、`exec env` で以下を固定して `claude "$@"` を起動する。

| 変数 | 値 |
|---|---|
| `ANTHROPIC_BASE_URL` | `https://api.deepseek.com/anthropic` |
| `ANTHROPIC_MODEL` / `ANTHROPIC_DEFAULT_OPUS_MODEL` / `ANTHROPIC_DEFAULT_SONNET_MODEL` | `deepseek-v4-pro[1m]` |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` / `CLAUDE_CODE_SUBAGENT_MODEL` | `deepseek-v4-flash` |

**確認事項**: transcript 上のモデル名は `[1m]` サフィックスが落ちた `deepseek-v4-pro` として記録される。
またAPIキーは環境変数にのみ載り、ログには出ない。

### 3.3 `claude/skills/pr-review-loop/SKILL.md`（539行）

implementerが起動し、Phase 0（reviewerペイン特定）〜Phase 7（完了報告）を自律実行する。
Phase 1.5（自己レビュー）、Phase 2（レビュー依頼）、Phase 3（待機）、Phase 4（判定）、Phase 5（修正）、Phase 6（返信・再依頼）。
「譲れないレビュー基準」8項目（小出し禁止 / 伏せない / オプション段階なし / 1レビュー1判定 / 再レビュー免除は権限外 等）が
過去の失敗（重大問題を「参考まで」に押し込み、implementerが「承認」だけ拾う）への対策として明文化されている。

**この規約は本傘ブランチで一切変更しない。** 追加するのは工程境界でのイベント発火行のみ。

### 3.4 `claude/skills/umbrella-orchestrator/SKILL.md`（467行）

傘ブランチのcommanderが計画書を読み、`/spawn <N>` で `ocw -H <孫ブランチ> <傘ブランチ>` を叩いて孫workspaceを作り、
implementerにプロンプトを送る。`/check` でマージ検出・検証・計画書更新。`/finalize` で傘→mainのPR。
計画書には **孫ブランチ進捗テーブル** と `## 孫N用プロンプト:` セクションが必須。本計画書はこの形式に従う。

### 3.5 デプロイ・テスト・ドキュメント

- `deploy-all.sh` → 各ツールの `deploy.sh`（`shared/helpers.sh` の `AVAILABLE_TOOLS` に列挙）
- `bin/deploy.sh` は `~/bin/` へ `ocw` / `claude-ds` を symlink するだけ
- `claude/deploy.sh` は `~/.claude/settings.json` を **ベース + `settings.machine.json` のマージで生成**（symlink不可）し、
  skills を個別symlinkする
- **このリポジトリにはテストフレームワークもlint設定も存在しない。** よって `/check` も `pr-review-loop` も
  言語検出に失敗し検証をスキップしている（`unknown` → スキップ）。本傘で最小のテスト基盤を導入する（第13章）
- `.gitignore` は `/.claude/` を無視している → プロジェクト設定 `.claude/pr-review.yml` を置くには除外指定が必要

---

## 4. Goals and non-goals

### Goals（第一段階）

- G1. PR単位・工程単位・役割単位で、DeepSeek変動費を**推定**できる
- G2. PR単位で Claude 5時間枠 / 週間枠の消費を**サンプリング**できる
- G3. レビュープロセスの所要時間・ラウンド数・人間介入回数を集計できる
- G4. 1PRが同一5時間窓で完走できたかを判定できる
- G5. 上記を、既存フローの挙動を1ミリも変えずに達成する
- G6. 5〜10本の実PRでベースラインを取る手順が確立している

### Non-goals（第一段階で作らない — 依頼書12章に準拠）

レビュー規約の緩和 / 承認条件の変更 / finding ledger / controller状態機械 / ペイン構成変更 / 役割の責務変更 /
自動compact / コンテキスト閾値によるセッション切替 / Opus・Sonnetの自動ルーティング / fixer自動昇格 /
Claude Max自動移行 / branch protection変更 / commit statusによるreview gate / 外部SaaSダッシュボード /
大規模LLM gateway / 複数provider対応の一般化。

さらに本計画では以下も明示的に作らない。

- リアルタイム集計・常駐プロセス・デーモン
- SQLite等のDB（第9章で不要と結論）
- 指摘内容そのものの構造化（依頼書302行に準拠）

---

## 5. Verified technical findings（実測済みの事実）

以下はすべて 2026-08-01 に本マシン上で実際に確認した。推測ではない。

### 5.1 環境バージョン

| 対象 | 値 |
|---|---|
| Claude Code | `2.1.220`（`~/.local/share/claude/versions/2.1.220`、ELF実行ファイル） |
| Herdr | `0.7.3` |
| python3 | mise pin `3.12`（`ocw` が既に依存） |

### 5.2 Claude Code transcript が単独で費用計測に足りる ✅

`~/.claude/projects/<cwd-slug>/<session-id>.jsonl` に追記される。実測した行の型:

```
mode / permission-mode / file-history-snapshot / user / attachment / assistant /
last-prompt / ai-title / file-history-delta / pr-link / system
```

`type: "assistant"` 行の実データ（DeepSeek経由・実物）:

```json
{"type":"assistant","timestamp":"2026-07-29T10:28:31.395Z","sessionId":"00b2ac54-...",
 "version":"2.1.220","gitBranch":"ai/ai-ph-04-docs","cwd":"/home/manemone/projects/dotfiles/ai-ph-04-docs",
 "effort":"high","isSidechain":false,
 "message":{"id":"...","model":"deepseek-v4-pro","stop_reason":...,
   "usage":{"input_tokens":4617,"cache_creation_input_tokens":0,"cache_read_input_tokens":27264,
            "output_tokens":329,"service_tier":"standard",
            "cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},
            "server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},
            "iterations":[],"speed":"standard"}}}
```

Anthropic本家（`claude-opus-5`）でも**完全に同一スキーマ**。`iterations` 配列と `cache_creation` の内訳が埋まる点だけ異なる。

取得できる項目: `sessionId` / `timestamp` / `model` / `usage`一式 / `gitBranch` / `cwd` / `version` / `effort` / `isSidechain`。

### 5.3 ⚠️ 同一 `message.id` が複数行に重複出力される（**重複排除が必須**）

実測: 1ファイル中 `assistant` 行 **179行** に対し distinct `message.id` は **57**。
1レスポンスが content block ごとに分割追記されるため、素朴に合計すると**最大3倍以上の過大計上**になる。

> **設計上の必須要件: `message.id` を idempotency key として重複排除する。**

`requestId` フィールドは存在しない。`message.id` が唯一の一意キー。

### 5.4 DeepSeek Anthropic互換エンドポイントの usage は信頼できる ✅

- `cache_read_input_tokens` が実際に返る（= DeepSeekの自動prefix cacheのhit分）
- `cache_creation_input_tokens` は**常に0**。公式docの「Cache control annotations は非サポート」と整合する
  （DeepSeekは明示cache writeを課金せず自動キャッシュする）
- よって **cache miss入力 = `input_tokens`、cache hit入力 = `cache_read_input_tokens`** と対応付けられる
- streamingの中断・retryは transcript には「usage付きの完成メッセージ」としてしか現れない。
  つまり **課金されたが記録されない中断リクエストが存在しうる**（第6章 U3、第17章 R2）

### 5.5 DeepSeek 価格表（2026-08-01 時点、公式doc実取得）

出典: `https://api-docs.deepseek.com/quick_start/pricing`（USD / 1Mトークン）

| model | cache hit入力 | cache miss入力 | 出力 |
|---|---|---|---|
| `deepseek-v4-flash` | $0.0028 | $0.14 | $0.28 |
| `deepseek-v4-pro` | $0.003625 | $0.435 | $0.87 |

- 両モデルとも context 1M / 最大出力 384K
- **予告**: ピーク/オフピーク料金（ピーク時2倍、北京時間 9:00–12:00 と 14:00–18:00）が「近日」適用。**適用日未定**
- Responses API は現在 `deepseek-v4-flash` のみ対応（本件には無関係）

→ **価格表はコードにベタ書きせず、`price_table_version` と `effective_date` を持つデータとして持つ。
過去イベントは記録時に適用した version を保持し、再計算しない。**
ピーク料金が始まったら、リクエスト時刻を Asia/Shanghai に変換して判定するフィールドを追加できる形にしておく。

### 5.6 Claude 利用枠は statusLine 経由で機械可読に取れる ✅（最大の発見）

Claude Code 2.1.220 の statusLine コマンドは stdin に JSON を渡す。公式スキーマ（バイナリ内蔵ドキュメントより実取得）:

```json
{
  "session_id": "string",
  "session_name": "string",
  "prompt_id": "string",
  "transcript_path": "string",
  "cwd": "string",
  "model": { "id": "string", "display_name": "string" },
  "workspace": { "current_dir": "...", "project_dir": "...", "git_worktree": "...",
                 "repo": { "host": "...", "owner": "...", "name": "..." } },
  "version": "string",
  "context_window": { "total_input_tokens": n, "total_output_tokens": n,
                      "context_window_size": n, "current_usage": {...}|null,
                      "used_percentage": n|null, "remaining_percentage": n|null },
  "effort": { "level": "low|medium|high|xhigh|max" },
  "thinking": { "enabled": bool },
  "rate_limits": {
    "five_hour": { "used_percentage": 0-100, "resets_at": <unix epoch sec> },
    "seven_day": { "used_percentage": 0-100, "resets_at": <unix epoch sec> }
  },
  "pr": { "number": n, "url": "...", "review_state": "approved|pending|changes_requested|draft" },
  "worktree": { "name": "...", "path": "...", "branch": "..." }
}
```

`rate_limits` のコメントに **「Optional: Claude.ai subscription usage limits. Only present for subscribers after first API response.」**
と明記されている。つまり:

- Claude Pro セッションでは初回API応答後に取得可能（**孫0 P1で実証済み ✅**。ADR-001 §2.1参照）
- `claude-ds`（DeepSeek）セッションでは**存在しない**（**孫0 P1で実証済み ✅**。38/38サンプルで不在）
- **`resets_at` が窓の識別子**になるため、5時間窓のreset跨ぎを単純減算せずに扱える（**孫0 P1で安定性確認済み ✅**）
- ⚠️ **孫0 P1の新発見**: `context_window.used_percentage` は非nullが多数（59/66）だがnullのケースもある（7/66）。
  `total_input_tokens` / `total_output_tokens` / `context_window_size` は常に取得可能。
  null-safe処理が必要（ADR-001 §2.1）
- ⚠️ **孫0 P1の新発見**: statusLine に `cost.total_cost_usd`（セッション累積コスト、USD）が全サンプル（66/66）で出現。
  Claude本家・DeepSeek両セッションで取得可能。費用推定の補完・検証に使える（ADR-001 §2.1）
- ⚠️ **孫0 P1の新発見**: `resets_at` は安定しているが、一部セッションで過去窓のstale値を返す（8件中3件）。
  `window_id` として使うには現在時刻との比較による鮮度判定が必要（ADR-001 §2.1）

`/usage` はバイナリ内に2実装ある。`{type:"local-jsx", name:"usage", aliases:["cost","stats"], requires:{ink:true}}`（TUI）と、
`{type:"local", name:"usage", supportsNonInteractive:true, ...}`（条件付き有効）。
いずれも出力は散文であり、**statusLine JSON より機械可読性で劣る**。TUIパース案は採用しない。

### 5.7 Herdr が「役割 ↔ セッション」の結合キーを既に持っている ✅

`herdr pane list`（実出力）:

```json
{"pane_id":"w6:p2","workspace_id":"w6","tab_id":"w6:t1","label":"reviewer",
 "agent":"claude","agent_status":"idle",
 "agent_session":{"agent":"claude","kind":"id","source":"herdr:claude",
                  "value":"292fbb18-a548-404a-aa3c-bfd1197602f3"},
 "cwd":"/home/manemone/projects/lora-dataset-forge/main", ...}
```

- `label` = `commander` / `implementer` / `reviewer`（`ocw` が rename 済み）
- `agent_session.value` = **Claude Code の session_id**（= transcript ファイル名）
- `cwd` = worktree パス、`workspace_id` = Herdr workspace ID
- `agent_status` = `idle` / `working` / `blocked` / `unknown`

この対応は Herdr 同梱の `~/.claude/hooks/herdr-agent-state.sh`（SessionStart hook）が
`pane.report_agent_session` を socket に送ることで成立している。**Herdr本体の改修は不要。**

Herdrが各ペインに渡す環境変数: `HERDR_ENV=1` / `HERDR_PANE_ID` / `HERDR_SOCKET_PATH` / `HERDR_WORKSPACE_ID`。

### 5.8 transcript に PR紐付けが既にある ✅

```json
{"type":"pr-link","sessionId":"00b2ac54-...","prNumber":22,
 "prUrl":"https://github.com/manemone/dotfiles/pull/22",
 "prRepository":"manemone/dotfiles","timestamp":"2026-07-29T10:36:35.966Z"}
```

→ 「PR作成前はrun IDで開始し、後からPR番号へbind」という要件は、
自前bindに加えてこの行を**フォールバック情報源**として使える。

### 5.9 その他の周辺情報

| 情報源 | 内容 | 用途 |
|---|---|---|
| `~/.claude/sessions/<pid>.json` | `sessionId` / `cwd` / `pid` / `startedAt` / `kind:"interactive"` / `name` / `status` | セッション生存確認、pid紐付け |
| `~/.claude/stats-cache.json` | 日次 messageCount / sessionCount / toolCallCount | 参考のみ（費用情報なし） |
| hook events | `SessionStart` `SessionEnd` `Stop` `SubagentStop` `PreToolUse` `PostToolUse` `UserPromptSubmit` `Notification` `PreCompact` `PostCompact` | **usage は渡ってこない**。session_id と transcript_path のみ |
| OTel | `claude_code.token.usage` / `claude_code.cost.usage` / `claude_code.llm_request` 等のメトリクスが実装済み（`CLAUDE_CODE_ENABLE_TELEMETRY`） | 収集器が必要。console exporter はTUIを汚す → **不採用** |
| `claude -p --output-format json` | `usage` / `total_cost_usd` / `modelUsage` / `num_turns` を返す | 本フローは対話ペイン運用のため経路が違う。参考のみ |

### 5.10 カバレッジのギャップ（重要な限界）

DeepSeek管理画面の7月実績 v4-flash **2,793 requests / 107M tokens** に対し、
全transcript中の `deepseek-v4-flash` メッセージは **0件**。

→ Claude Code の背景ユーティリティ呼び出し（タイトル生成・要約等、Haiku枠 = flash）は
**transcriptに記録されない**。またサブエージェント（`CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash`）分も
本マシンのtranscriptからは検出できていない。

- v4-pro: console 6.177B tokens vs transcript 5.478B → **約89%をカバー**（残りは他マシン・別期間・非記録分）
- v4-flash: **カバー率ほぼ0%**（ただし金額寄与は小さい: 107M tokens ≒ 最大 $15、大半がhitなら $1未満）

> **設計上の必須要件: 集計レポートには常に `coverage`（transcript由来 / provider総計）を併記し、
> 「完全な記録」と誤認させない。** 孫3 で実測して比率を確定する。

---

## 6. Unknowns and probes（未確定事項と実証方法）

「取れないものを取れることにしない」ため、以下は孫0で実証してから孫3・孫4の設計を確定する。

| ID | 未確定事項 | probe | 課金 | 秘密情報 | 生成物 |
|---|---|---|---|---|---|
| U1 | Claude Pro 契約で statusLine の `rate_limits` が実際に来るか。来るタイミング・更新頻度 | P1 ✅ 実証済み | なし | なし | `/tmp` にJSONダンプ → ADR-001 §2.1 |
| U2 | `resets_at` が5時間窓の識別子として安定か（窓跨ぎで値が変わるか） | P1 ⚠️ epoch秒としての安定性は確認。ただし8件中3件でstale値（過去窓のresets_at）を観測。鮮度判定が必要 | なし | なし | 同上 |
| U3 | streaming中断・retry・APIエラー時に課金されたリクエストがtranscriptから漏れる量 | P2（人間実行待ち） | 微小 | APIキー（非出力） | 生SSEのヘッダ/最終usageのみ |
| U4 | `deepseek-v4-pro[1m]` 指定時の実課金モデル名・レスポンスヘッダ（request-id / rate limit） | P2（人間実行待ち） | 微小 | 同上 | 同上 |
| U5 | reasoning（thinking）トークンが出力トークンに含まれるか、別項目か | P2（人間実行待ち） + transcript精査 | 微小 | なし | 集計結果 |
| U6 | transcript由来集計 vs DeepSeek管理画面の乖離率（カバレッジ） | P3 ⚠️ 集計完了、管理画面値は人間確認待ち | なし | なし | 突合レポート → ADR-001 §2.2 |
| U7 | `claude -p "/usage"` が機械可読な出力を返すか | P4（人間確認待ち） | 1ターン分 + Claude枠消費 | なし | 出力テキスト |
| U8 | 5時間枠に到達して待機した際、transcript / statusLine に何が現れるか | P5 ⚠️ 未観測（期間中に到達せず） | なし | なし | 観測メモ → ADR-001 §2.5 |

### probe 詳細（**すべて承認後に実施**）

**P1: statusLine rate_limits 実証**（課金ゼロ）
一時的な statusLine スクリプトを `~/.claude/statusline-probe.sh` に置き、stdin JSON をそのまま
`/tmp/claude-statusline-probe.jsonl` に追記して固定文字列を返すだけにする。
`claude/settings.machine.json`（gitignore済み）に `statusLine` を書いてClaudeセッションを1つ再起動し、数時間放置して収集。
**本番設定 `claude/settings.json` は触らない。** 収集後に設定を戻す。

**P2: DeepSeek 生リクエストprobe**（課金 < $0.01）
`curl` で `https://api.deepseek.com/anthropic/v1/messages` に `max_tokens: 16` の最小リクエストを1回、
非streamingとstreamingで各1回。取得する対象:
- レスポンスヘッダ全一覧（`request-id`、rate limit系）→ **値はキー名のみ記録し、Authorizationは記録しない**
- streamingの `message_start` / `message_delta` に載る usage
- 途中で `curl` を中断した場合の挙動（課金の有無は管理画面で翌日確認）
APIキーは `DEEPSEEK_API_KEY_FILE` から読み、`set +x` 下で環境変数経由でのみ渡す。**probeスクリプトはキーを一切出力しない。**
`~/.config/deepseek/**` は `claude/settings.json` の `permissions.deny` に入っているため、
**probeは人間が手で実行するか、明示的に許可を得てから実行する。**

**P3: 突合**（課金ゼロ）
transcript集計結果と DeepSeek管理画面の月次値を人間が並べて比較。乖離率を記録。

**P4: `/usage` 非対話実証**（Claude枠を1ターン分消費）
`claude -p "/usage" --output-format json` を1回だけ実行し、機械可読性を判定。
散文なら「不安定」と結論して statusLine 案を確定する。

**P5: 制限到達の受動観測**（課金ゼロ）
通常運用中に5時間枠へ到達したら、その時点の statusLine ダンプと transcript の該当時刻を保存する。
到達しなければ「未観測」と正直に記録し、孫4では `blocked` を best-effort 扱いにする。

---

## 7. Proposed architecture

### 7.1 採用案: 「事後読み取り + 軽量イベント刻み」

```
                 ┌─────────────────────────────────────────────┐
   本番フロー →   │  ocw / claude / claude-ds / pr-review-loop   │  ← 一切割り込まない
                 └───────────────┬─────────────────────────────┘
                                 │ (副作用として既に書かれている)
        ┌────────────────────────┼──────────────────────────┐
        ▼                        ▼                          ▼
 ~/.claude/projects/*.jsonl   herdr pane list        statusLine stdin JSON
 (model / usage / pr-link)    (label↔session_id)     (rate_limits / pr / model)
        │                        │                          │
        └────────────┬───────────┴──────────────┬───────────┘
                     ▼                          ▼
             ocw-meter ingest            ocw-meter snapshot-quota
             (バッチ・冪等・読み取り専用)   (statusLineから1行append)
                     │                          │
                     └──────────┬───────────────┘
                                ▼
                ~/.local/state/ocw-meter/events/*.jsonl   ← append-only
                                ▲
                                │ ocw-meter event  (fail-open, 常に exit 0)
                 ┌──────────────┴──────────────┐
                 │ ocw / pr-review-loop の工程境界  │  ← 追加する唯一の割り込み
                 └─────────────────────────────┘
                                │
                                ▼
                         ocw-meter report
                    (PR別 / 工程別 / model別 / 5h窓別 / 月次)
```

### 7.2 なぜこれが最小で最も安全か

| 観点 | 事後読み取り方式 |
|---|---|
| 本番経路への割り込み | ゼロ（ingest は完全に読み取り専用・後追い） |
| meter障害時の影響 | 集計が古くなるだけ。レビューループは無傷 |
| 秘密情報 | APIキー・認証ヘッダに一切触れない |
| retry/中断の捕捉 | ✗（transcriptに現れない分は取れない）→ coverage で明示 |
| 実装量 | 小（JSONL読み取り + 集計） |

### 7.3 不採用案とその理由

| 案 | 内容 | 不採用の理由 |
|---|---|---|
| **A. ローカル透過gateway** | `claude-ds` と DeepSeek の間にHTTPプロキシを立て、request/responseを全捕捉 | 忠実度は最高（retry / 中断 / ヘッダ / request-id まで取れる）。しかし**本番経路に単一障害点を追加**し、TLS・認証ヘッダ・ストリーム転送・プロセス寿命管理が必要。依頼書16章「何でも取れる巨大gateway」を避ける方針にも反する。**U6の乖離率が許容できない場合の将来オプションとして保留** |
| **B. OpenTelemetry** | `CLAUDE_CODE_ENABLE_TELEMETRY=1` + OTLP | `claude_code.token.usage` 等は実装済みだが、collector常駐が必要。console exporterはTUIを汚す。第一段階には過剰 |
| **C. Claude Code hooks で usage 収集** | `Stop` / `PostToolUse` hook でusageを拾う | **hook入力にusageは含まれない**（session_id / transcript_path のみ）。さらに `~/.claude/settings.json` は Herdr が自動書き込みし、`claude/deploy.sh` が生成し直す競合地帯。触るリスクが高い |
| **D. `/usage` のTUIパース** | ペインから `/usage` を送って画面を読む | 表示形式変更で壊れる。statusLine JSONという公式の機械可読経路がある以上、選ぶ理由がない |
| **E. SQLite** | イベントをDBに | 全期間で40k messages / 数MB。JSONL + python集計で秒オーダー。第一段階では不要。将来必要になったらJSONLからimportできる |
| **F. providerの請求API** | DeepSeekの利用履歴APIを叩いて突合 | 月次総額しか取れず、PR別内訳にならない。**人間による突合（P3）で代替** |

### 7.4 コンポーネント

すべて `bin/ocw-meter` 単一実行ファイル（bash薄皮 + python3本体、既存依存のみ）。

| サブコマンド | 用途 | 呼び出し元 |
|---|---|---|
| `ocw-meter event <type> [--key val ...]` | 任意イベントを1行append | `ocw`, `pr-review-loop` |
| `ocw-meter bind-pr --run <id> --pr <n>` | run_id → PR番号を後から結合 | `pr-review-loop` Phase 1 |
| `ocw-meter ingest [--since <ts>]` | transcript + herdr pane list を走査し `usage.message` イベントを生成（冪等） | 手動 / `report` が自動実行 |
| `ocw-meter snapshot-quota` | statusLine の stdin JSON を読み `quota.sample` を1行append、statusLine文字列を stdout に返す | `statusLine` |
| `ocw-meter report [--pr N] [--phase] [--model] [--window] [--month]` | 集計出力（表 / JSON） | 人間 |
| `ocw-meter validate` | 保存済みイベントのschema検証・破損行の隔離 | テスト / 手動 |

**役割の帰属ロジック（優先順）**

1. イベントに明示された `role`（`ocw` が各ペインに `OCW_ROLE` を渡す — 孫2）
2. `herdr pane list` の `label` ↔ `agent_session.value` == transcript の `sessionId`
3. 不明なら `role: "unknown"`（捏造しない）

**PR帰属ロジック（優先順）**

1. `ocw-meter bind-pr` による明示bind（run_id 経由）
2. transcript の `pr-link` 行
3. `gitBranch` → `gh pr list --head` の後追い解決（`ingest` 時、失敗しても続行）
4. 不明なら `pr_number: null`

---

## 8. Event schema

`schema_version: 1`。全イベント共通のエンベロープ + 型ごとのペイロード。

### 8.1 共通エンベロープ

| フィールド | 型 | 説明 |
|---|---|---|
| `schema_version` | int | 現在 `1` |
| `event_id` | string(uuid4) | イベント一意ID |
| `idempotency_key` | string | 重複排除キー。`usage.message` は `msg:<message.id>`、`phase.*` は `<run_id>:<phase>:<round>:<boundary>` |
| `event_type` | string | 下表参照 |
| `ts` | string | RFC3339 UTC（例 `2026-08-01T07:28:31.395Z`） |
| `ts_local_offset` | string | 記録マシンのローカルoffset（例 `+09:00`） |
| `source` | string | `ocw` / `pr-review-loop` / `transcript` / `statusline` |
| `parser_version` | int | 生データ解釈ロジックのversion（transcript / statusline 用） |
| `completeness` | string | `complete` / `partial` / `unknown` |
| `run_id` | string | 実行系列ID（PR作成前から採番。ULID風 `<epoch>-<rand>`） |
| `repo` | string | `owner/name` |
| `worktree` | string | worktree絶対パス |
| `branch` | string \| null | git branch |
| `head_sha` | string \| null | 記録時点のHEAD |
| `workspace_id` | string \| null | Herdr workspace |
| `pane_id` | string \| null | Herdr pane |
| `role` | string | `commander` / `implementer` / `reviewer` / `unknown`（将来 `controller` 等を追加可） |
| `session_id` | string \| null | Claude Code session |
| `provider` | string \| null | `anthropic` / `deepseek` / `unknown` |
| `model` | string \| null | 実モデル名 |
| `phase` | string \| null | 第8.3節 |
| `round` | int \| null | レビューラウンド（1始まり） |
| `pr_number` | int \| null | 後から bind 可 |
| `pr_url` | string \| null | |

### 8.2 イベント型

| `event_type` | 発生源 | 主要ペイロード |
|---|---|---|
| `run.start` | `ocw` | `base_ref`, `command` |
| `run.end` | `ocw`（rm時） | `outcome` |
| `phase.start` / `phase.end` | `pr-review-loop` | `phase`, `round`, `duration_ms`(end), `outcome`: `success`/`failure`/`blocked`, `error_category` |
| `pr.bind` | `pr-review-loop` | `pr_number`, `pr_url` |
| `review.round` | `pr-review-loop` | `round`, `findings_count`, `verdict`: `approved`/`changes_requested`/`ambiguous`, `reviewed_head_sha` |
| `human.intervention` | `pr-review-loop` 停止条件 | `reason`（第539行の停止条件に対応する列挙） |
| `usage.message` | `ingest`（transcript） | 第8.4節 |
| `quota.sample` | `snapshot-quota` | 第8.5節 |
| `block.start` / `block.end` | best-effort | `cause`: `rate_limit`/`api_error`/`unknown`, `wait_ms` |
| `meter.error` | 自己診断 | `stage`, `message`（**内容本文は載せない**） |

### 8.3 phase 列挙（`pr-review-loop` の実フェーズに対応）

`implement` / `self_review`（Phase 1.5）/ `lint_test` / `pr_create`（Phase 2 前段）/ `review_request`（Phase 2）/
`review_wait`（Phase 3）/ `review_collect`（Phase 3b）/ `verdict`（Phase 4）/ `fix`（Phase 5）/
`reply`（Phase 6）/ `rereview_request`（Phase 6-4）/ `done`（Phase 7）

### 8.4 `usage.message` ペイロード

| フィールド | 由来 |
|---|---|
| `message_id` | `message.id`（重複排除キー） |
| `input_tokens` | `usage.input_tokens` = **cache missトークン** |
| `cache_read_input_tokens` | = **cache hitトークン** |
| `cache_creation_input_tokens` | Anthropicのみ非0 |
| `output_tokens` | |
| `reasoning_tokens` | 取得可能なら。**現状フィールドなし → `null`**（U5） |
| `is_sidechain` | `isSidechain`（サブエージェント判定） |
| `effort` | `high` 等 |
| `stop_reason` | |
| `cost_estimate_usd` | 下式 |
| `price_table_version` | 例 `deepseek-2026-08-01` |
| `price_effective_date` | 例 `2026-08-01` |
| `cost_basis` | `estimated`（**常にestimated。実請求ではない**） |
| `currency` | `USD` |

**費用計算式**

```
cost = ( cache_read_input_tokens        * price.cache_hit_in
       + (input_tokens + cache_creation_input_tokens) * price.cache_miss_in
       + output_tokens                  * price.out ) / 1_000_000
```

Anthropic（Claude Pro）分は **`cost_estimate_usd: null` / `cost_basis: "subscription"`** とする。
定額契約をAPI単価へ換算しない（依頼書180行）。分析上どうしても配賦する場合はレポート側で
`allocation`（分析上の按分であることを明示）として別カラムに出す。

### 8.5 `quota.sample` ペイロード

| フィールド | 説明 |
|---|---|
| `five_hour_used_pct` / `five_hour_resets_at` | `rate_limits.five_hour`。無ければ `null` |
| `seven_day_used_pct` / `seven_day_resets_at` | 同上 |
| `window_id` | `five_hour_resets_at` の値そのもの（**窓の同一性判定に使う**） |
| `context_used_pct` | `context_window.used_percentage` |
| `plan_source` | `statusline` |
| `raw_ref` | 生スナップショットのファイル参照（opt-in時のみ）。既定 `null` |

**窓跨ぎの扱い**: 消費量は **同一 `window_id` 内のサンプル同士でのみ差分を取る**。
`window_id` が変わったら新しい窓として開始し、跨いだ減算は行わない。`used_percentage` が
前サンプルより減少しかつ `window_id` が同じ場合は異常として `completeness: "partial"` を立てて警告する。

---

## 9. Storage and privacy

### 9.1 保存先とレイアウト

```
~/.local/state/ocw-meter/            (mode 700)
├── events/
│   └── YYYY-MM-DD.jsonl             (mode 600, append-only)
├── state/
│   ├── ingest-cursor.json           最終ingest位置（ファイル別 offset + mtime + inode）
│   └── seen-keys/YYYY-MM.txt        idempotency key の既知集合（月別）
├── prices/
│   └── deepseek-2026-08-01.json     価格表（version付き。上書き禁止・追加のみ）
├── raw/                             opt-in時のみ（既定では空）
│   └── YYYY-MM-DD/*.json            statusLine 生スナップショット等
└── quarantine/
    └── YYYY-MM-DD.jsonl             schema不正・破損行の隔離先（黙って捨てない）
```

- リポジトリには一切書かない。`.gitignore` にも `ocw-meter` 関連の保険パターンを追加する
- 書き込みは `flock` で排他し、1イベント = 1行を `O_APPEND` で書く（並行writer対応）
- **JSONLで十分**な根拠: 全期間で 39,805 メッセージ。1イベント約600B → 年間でも数十MB。
  python での全走査集計は1秒未満。SQLiteの運用コスト（スキーマ移行・ロック・破損復旧）に見合わない

### 9.2 既定で保存しないもの（依頼書7章準拠）

プロンプト全文 / モデル応答全文 / ソースコード本文 / `.env` / APIキー / 認証ヘッダ /
GitHub token / DeepSeek token / Claude credential / ターミナル全文。

**transcript は読むが、`message.content` には一切触れない**（`usage` / `model` / `id` / `stop_reason` / メタのみ抽出）。
`meter.error` の `message` も例外文字列のみで、入力データを含めない。

### 9.3 opt-in の raw 保存

`OCW_METER_RAW=1` のときのみ `raw/` に statusLine JSON等を保存する。既定OFF。

- redaction: 保存前に `authorization` / `api[-_]?key` / `token` / `sk-[A-Za-z0-9]+` にマッチする値を `[REDACTED]` に置換
- 保存期間: 既定 14日。`ocw-meter prune` で削除（cronは組まない。手動 or 将来）
- パーミッション: ディレクトリ700 / ファイル600

### 9.4 誤commit防止

- 保存先はリポジトリ外（`~/.local/state/`）が第一防衛線
- `.gitignore` に `*.ocw-meter.jsonl` / `/ocw-meter-state/` を保険で追加
- `ocw-meter` は **リポジトリ配下への書き込みを拒否する**（保存先が git worktree 内なら起動時にエラー）

---

## 10. Failure behavior

### 10.1 原則: 書き込み側は fail-open、読み取り側は fail-loud

| 経路 | 失敗時の挙動 |
|---|---|
| `ocw-meter event` / `bind-pr` / `snapshot-quota` | **常に exit 0**。stderr に1行warnのみ。本番フローを止めない |
| 呼び出し側の書き方 | `command -v ocw-meter >/dev/null && ocw-meter event ... \|\| true`（**meter不在が正常系**） |
| `snapshot-quota` | 例外時も statusLine 文字列は必ず stdout に出す（statusLineが壊れて見えない事態を防ぐ） |
| `ocw-meter ingest` / `report` / `validate` | **失敗したら非ゼロで落ちる**。壊れたデータを黙って集計しない |
| schema不正・破損行 | `quarantine/` へ移し、`report` の出力先頭に「隔離N件」を警告表示 |

### 10.2 provider障害と meter障害の区別

- `usage.message` が「取れなかった」= meter側の問題 → `completeness: "unknown"` で `meter.error` を残す
- APIエラー・rate limit = provider側 → `block.*` / `error_category` で記録
- レポートは両者を別カラムで出す。混ぜない

### 10.3 冪等性・再実行・クラッシュ耐性

- `ingest` は `state/ingest-cursor.json`（file → offset/inode/mtime）から再開。**何度実行しても同じ結果**
- 重複排除は `idempotency_key`。`usage.message` は `msg:<message.id>`（第5.3節の重複行問題への直接対策）
- ローテート・inode変化を検出したら当該ファイルを頭から読み直す（重複はキーで吸収）
- プロセスがクラッシュしても append-only なので破損は最終行の切れのみ。読み込み時に
  「最終行がJSONとして不完全」なら**警告して読み飛ばし、quarantineに退避**（前段の完全な行は生かす）
- 並行writer: `flock` + 単一 `write()`。ロック取得に100ms以上かかったら諦めて exit 0（fail-open）

### 10.4 「部分的な記録」を完全と誤認しない

すべての集計出力に必ず次を併記する。

```
coverage: transcript-derived 5.478B tokens / provider-reported 6.284B tokens (87.2%)
completeness: complete 96.1% / partial 3.4% / unknown 0.5%
quarantined: 0 lines
price_table: deepseek-2026-08-01 (effective 2026-08-01)
cost_basis: estimated — not an invoice
```

---

## 11. Child PR plan

### 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 0 | `ai/ph-00-feasibility-probes` | feasibility probe実施 + ADR作成（本番コードなし・docsのみ） | 🔄 実装中 |
| 1 | `ai/ph-01-meter-core` | `bin/ocw-meter` コア（schema / storage / event / bind-pr / validate / report骨格）+ テスト基盤 | ⬜ 待機中 |
| 2 | `ai/ph-02-instrumentation` | `ocw` と `pr-review-loop` への工程イベント埋め込み（挙動不変・fail-open） | ⬜ 待機中 |
| 3 | `ai/ph-03-deepseek-usage` | transcript ingest + 価格表 + 費用推定 + 突合レポート | ⬜ 待機中 |
| 4 | `ai/ph-04-claude-quota` | statusLine 経由の quota スナップショット収集（孫0 P1 の実証範囲のみ） | ⬜ 待機中 |
| 5 | `ai/ph-05-reports-baseline` | 集計レポート（PR別/工程別/model別/5h窓別/月次）+ ベースライン計測手順 | ⬜ 待機中 |

各孫の詳細（目的 / 変更対象 / 変更しない対象 / 依存 / 完了条件 / テスト / ロールバック / レビュー重点）は
後半の「孫N用プロンプト」に implementer 向けの形で完全記述する。ここでは要点のみ。

| 孫 | 変更対象 | 変更しない対象 | 依存 |
|---|---|---|---|
| 0 | `docs/adr/`, `docs/planning/` | 本番コード全部 | なし |
| 1 | `bin/ocw-meter`, `bin/tests/`, `bin/deploy.sh`, `bin/README.md`, `.gitignore`, `.claude/pr-review.yml` | `ocw`, `claude-ds`, skills | 孫0（ADRのschema決定） |
| 2 | `bin/ocw`, `claude/skills/pr-review-loop/SKILL.md`, `claude/skills/umbrella-orchestrator/SKILL.md`(任意) | レビュー規約・承認判定・ペイン構成 | 孫1 |
| 3 | `bin/ocw-meter`（ingest追加）, `bin/prices/` | `claude-ds` の接続先・引数 | 孫1 + 孫0 P2/P3 |
| 4 | `bin/ocw-meter`（snapshot-quota追加）, `claude/settings.json`(statusLine), `claude/README.md` | hooks全般 | 孫1 + 孫0 P1 |
| 5 | `bin/ocw-meter`（report拡充）, `docs/` | 収集ロジック | 孫1〜4 |

---

## 12. Dependency graph

```
孫0 (probes/ADR)
  │   ★ 人間が結果を確認してから先へ進む（自動進行しない）
  ▼
孫1 (meter core)  ────────┬──────────────┬───────────────┐
  │                       │              │               │
  ▼                       ▼              ▼               │
孫2 (instrumentation)   孫3 (deepseek)  孫4 (quota)       │
  │                       │              │               │
  └───────────┬───────────┴──────────────┘               │
              ▼                                          │
            孫5 (reports + baseline)  ←────────────────────┘
```

- **孫0 → 孫1 の間に人間の承認ゲートを置く。** 孫0の結果次第で孫3・孫4の設計が変わるため
- 孫2 / 孫3 / 孫4 は孫1マージ後に**並列可**。ただし全部同時spawnはレビュー負荷が高いので逐次を推奨
- **`/autopilot` は使わない。** `/spawn <N>` → 人間がPRを確認 → マージ → `/check` の逐次進行とする
  （依頼書591行「後続PRを最初から固定しすぎない」に準拠）

### spawn時のペイン構成（孫1以降・必須）

孫0は implementer が `claude-ds`（DeepSeek）で実行された。**孫1以降は implementer を
Anthropic本家の `claude` で、Sonnet + auto permission mode で起動する。**

```bash
OCW_IMPLEMENTER_COMMAND='claude --model sonnet --permission-mode auto' \
  ocw -H <孫ブランチのslug> ai/llm-cost-observability
```

- commander / reviewer は現行のまま（reviewerは `claude` = 既定モデル Opus）
- 環境に `OCW_IMPLEMENTER_COMMAND=claude-ds` が export されているため、
  **上記のように毎回明示的に上書きしないと DeepSeek に戻る**
- 注意: 孫0と孫1以降で implementer のモデル構成が異なる。
  これは基盤構築フェーズの話であり、**第15章のベースライン計測（実PR 5〜10本）の期間中は
  構成を固定すること**。計測開始時点の構成をベースラインレポートに記録する

---

## 13. Test strategy

### 13.1 テスト基盤の新設（孫1）

**このリポジトリには現在テストもlintも存在しない。** そのため `pr-review-loop` Phase 0.5 も
`umbrella-orchestrator /check` も検証をスキップしている。孫1で最小構成を導入する。

- テスト: **python3 標準ライブラリの `unittest`**（mise で python 3.12 が既に固定済み。新規依存ゼロ）
  - 配置: `bin/tests/test_ocw_meter.py`
  - 実行: `python3 -m unittest discover -s bin/tests -v`
- lint: **`python3 -m py_compile` + `bash -n` によるシンタックスチェック**（外部依存を増やさない）
  - 実行: `bin/tests/lint.sh`
- `.claude/pr-review.yml` を追加し `lint_cmd` / `test_cmd` を明示
  - **`.gitignore` の `/.claude/` が効くため `!/.claude/` と `!/.claude/pr-review.yml` の除外指定が必須**

### 13.2 必須テストケース（依頼書14章の全項目を網羅）

| # | ケース | 種別 | 実装方法 |
|---|---|---|---|
| T01 | schema validation（必須フィールド欠落・型不一致） | fixture | 正常/異常イベントを直接投入 |
| T02 | malformed event（壊れたJSON行） | fixture | quarantineへ隔離されること |
| T03 | duplicate event（同一 idempotency_key 2回） | fixture | 1件として集計されること |
| T04 | **同一 message.id の複数行**（第5.3節の実問題） | fixture | 実transcript由来の縮小fixtureで検証 |
| T05 | process crash（最終行が途中で切れている） | fixture | 前段は生き、最終行はquarantine |
| T06 | concurrent writers（20プロセス同時append） | 実行 | 全イベントが欠落なく行崩れなし |
| T07 | PR未作成 → 後から bind-pr | fixture | run_id配下の全イベントにPRが解決される |
| T08 | workspace再起動 / Herdr resume（pane_id変化） | fixture | session_id基準で継続追跡できる |
| T09 | 5時間window reset跨ぎ | fixture | window_id違いで減算しないこと |
| T10 | unknown usage（rate_limits欠落 / usage欠落） | fixture | `null` + `completeness: unknown` |
| T11 | UI出力形式変更（statusLine JSONに未知キー追加 / 既知キー消失） | fixture | 落ちずに `parser_version` 付きで partial 記録 |
| T12 | DeepSeek stream正常終了 | fixture | 孫0 P2 で採取した実レスポンスを固定化 |
| T13 | DeepSeek stream中断 | fixture | usage欠落を `unknown` として扱う |
| T14 | retry | fixture | 同一 message.id なら1件、別idなら2件 |
| T15 | API error | fixture | `block.*` / `error_category` に分類される |
| T16 | provider料金version変更 | fixture | 過去イベントが再計算されないこと |
| T17 | secrets redaction | fixture | `sk-xxx` / `Authorization:` を含む入力が保存物に残らない |
| T18 | meter executable不在 | 実行 | `ocw` / スキル手順が正常完走する |
| T19 | meter書込失敗（保存先を読み取り専用にする） | 実行 | 呼び出し側は exit 0 のまま継続 |
| T20 | report部分データ（イベント0件 / 片側だけ） | fixture | 空でも落ちず coverage を明示 |
| T21 | timezone（UTC / JST / 北京時間の境界） | fixture | 日次・月次集計の境界が意図通り |
| T22 | リポジトリ配下への書き込み拒否 | 実行 | git worktree内を保存先に指定するとエラー |

### 13.3 実ネットワークテストの分離

- **通常のCI・`pr-review-loop` のテストは fixture のみ。外部APIを一切叩かない**（課金ゼロを保証）
- 実ネットワークを使うのは孫0のprobeのみで、`bin/tests/network/` に隔離し
  `OCW_METER_NETWORK_TESTS=1` が無い限りスキップする
- fixture は孫0 P2 で採取した実レスポンスを **秘密情報を除去した上で** 固定化する

---

## 14. Rollback strategy

| 孫 | ロールバック手順 | 副作用の残骸 |
|---|---|---|
| 0 | `git revert`（docsのみ） | なし。probeで作った一時statusLine設定は probe 手順内で必ず戻す |
| 1 | `git revert` → `bin/deploy.sh` 再実行 → `~/bin/ocw-meter` symlink を手動削除 | `~/.local/state/ocw-meter/` は残る（手動削除可、データ保全のため自動削除しない） |
| 2 | `git revert` | なし（追加行はすべて `\|\| true` 付きの独立行。既存ロジックに絡めない設計を必須とする） |
| 3 | `git revert` | 生成済み `usage.message` イベントは残る。`ocw-meter validate` は旧schemaも読める |
| 4 | `git revert` → `claude/deploy.sh` 再実行 → `~/.claude/settings.json` の `statusLine` を確認 | **要注意**: `~/.claude/settings.json` は Herdr も書き込む。revert後に Herdr の `hooks` が消えていないか目視確認する |
| 5 | `git revert` | なし |

**全体ロールバック**: 傘ブランチごと revert すれば本番フローは完全に元通り。
`ocw-meter` が消えても `command -v` ガードにより `ocw` / `pr-review-loop` は正常動作する（T18で保証）。

---

## 15. Baseline measurement protocol（導入後のベースライン計測手順）

孫5で `docs/DOC-xxx_ベースライン計測手順.md` として成果物化する。骨子:

### 15.1 前提

- 孫1〜5がすべてマージ済み
- **この期間中、フロー・規約・モデル構成を一切変更しない**（観測が挙動を変えないことが前提）
- 実PR **5〜10本**（できれば規模がばらけたもの）を通常どおり回す

### 15.2 手順

1. 計測開始前に `ocw-meter report --month` を実行し、開始時点のスナップショットを保存
2. 各PRについて通常どおり `ocw -H` → 実装 → `/pr-review-loop` を回す（**特別な操作は一切しない**）
3. PR承認・マージのたびに `ocw-meter ingest && ocw-meter report --pr <N>` を実行して保存
4. 5〜10本完了したら以下を集計
   - PR別: 承認までの所要時間 / レビューラウンド数 / 人間介入回数 / 推定API費 / 5h枠消費
   - 工程別: `implement` / `self_review` / `fix` / `review_*` の時間とトークン内訳
   - model別 / role別のトークンと費用
   - 5時間窓別: 同一窓完走率、blocked時間
5. 月末に DeepSeek管理画面の実績と `ocw-meter report --month` を突合し **coverage比率を確定**
6. 結果を `docs/` にベースラインレポートとして記録し、**この時点で初めて最適化候補を評価する**

### 15.3 ベースラインとして必ず答える5つの問い（依頼書16章）

1. DeepSeek代の何割が初回実装 / 自己レビュー / 修正往復か
2. Claude 5時間枠の何割が初回レビュー / 再レビュー / 別設計作業か
3. 1PRを同一5時間枠で完走できているか（完走率）
4. Maxへ上げてDSを切った場合、総額はどう変わるか（推定シナリオ計算）
5. どの最適化候補を最初に試すべきか

---

## 16. Future experiments（次の傘ブランチ）

ベースライン取得後、**別の傘ブランチ**で以下を比較する。本傘では一切実装しない。

| 案 | 内容 |
|---|---|
| A. 現行 | DeepSeek実装・修正 / Opus初回レビュー / 現行の厳格な `pr-review-loop` |
| B. ハイブリッド | DeepSeek実装 / Opus初回フルレビュー / DeepSeek修正は原則1回 / Sonnetによる指摘限定再レビュー / 構造変更時のみOpusフルレビューへ回帰 / 同一指摘残存で強いfixerへ昇格 |
| C. Claude Max集中 | Max 5x / Opus中心 / DeepSeek最小化 / interactive quota と Agent SDK credit を分けて評価 |

比較指標: API費/承認済みPR、5h枠消費/承認済みPR、同一窓完走率、週間枠消費、blocked時間、
レビューラウンド数、人間介入、所要時間、品質guardrail。

**事前基準（実験前に確定し、結果を見てから変更しない）**

- API変動費 30%以上減
- Claude利用枠消費 20%以上減
- 人間介入が増えない
- blocking defectの見逃しが増えない
- 完了時間が悪化しない

> **基準の固定方法**: この5条件を孫5のベースライン文書に記載し、実験傘ブランチ開始時に
> commit hash を引用して参照する。実験結果を見てから閾値を編集するPRは、
> 「基準変更」であることを明示した独立PRとしてのみ許可する（結果と同一PRで変えない）。

### 品質guardrailの拡張余地

第一段階では収集しないが、schemaは以下を後付けできる形にしておく（`event_type` 追加だけで済む）。

`defect.escaped`（マージ後に発覚した重大問題）/ `revert.occurred` / `followup_fix.pr` / `ci.failed` / `human.found_issue`

---

## 17. Risks and open questions

| ID | リスク / 未解決 | 影響 | 緩和策 |
|---|---|---|---|
| R1 | transcriptのカバレッジが約89%（背景flash呼び出しが不可視。孫0 P3実測値、管理画面分母は人間確認待ち） | 費用の一部が見えない | coverage を全レポートに常時併記。孫3で比率を実測。許容できなければ将来gateway案（不採用案A）を再検討 |
| R2 | streaming中断・retryで課金されたが記録されないリクエスト | 過少計上 | 孫0 P2 で発生条件を確認。突合の乖離として吸収し、`cost_basis: estimated` を明示 |
| R3 | `~/.claude/settings.json` は Herdr も `claude/deploy.sh` も書き込む競合地帯 | statusLine追加でHerdrのhooksが飛ぶ / deployで統計設定が消える | **孫0 P1でhooks消失を実体験済み。** `claude/deploy.sh` は `settings.machine.json` が無い場合、または `hooks` を含まない `settings.machine.json` を使った場合に Herdr の `SessionStart` を消し飛ばす。対策: `settings.machine.json` に `hooks` を明記する。孫4は `claude/settings.json`（追跡ファイル）に `statusLine` を追加してdeploy経路に乗せる。デプロイ前後で `~/.claude/settings.json` の `hooks` を目視確認する手順をPRに含める |
| R4 | statusLine の `rate_limits` が Pro契約で来ない可能性 | 孫4が成立しない | 孫0 P1 で先に実証。来なければ孫4は「取得不可」と結論し、`blocked` の受動観測のみに縮小する（捏造しない） |
| R5 | DeepSeekのピーク/オフピーク2倍料金が計測期間中に開始 | 費用推定が外れる | 価格表をversion管理し `effective_date` を持つ。開始を検知したら新version追加。**過去データは再計算しない** |
| R6 | statusLine コマンドは描画のたびに実行される（高頻度） | I/O負荷・ログ肥大 | `snapshot-quota` は最短サンプリング間隔（既定60秒）を state ファイルで自制。超高速パス（前回から60秒未満なら即return） |
| R7 | 観測イベント追加により `pr-review-loop` の手順が長くなり、LLMが手順を取りこぼす | レビュー品質低下（最も避けたい） | 追加は各Phase冒頭/末尾の**1行コマンド**のみ。規約テキスト・判定基準・禁止事項は一切変更しない。孫2のレビューではこの点を最重点で確認する |
| R8 | 実測した7月の DeepSeek 実効単価と価格表の整合 | 費用推定の絶対値がずれる | 全期間transcriptからの推定 $46.8 と7月請求 $58.80 は同オーダーで矛盾しない。孫3で月境界を揃えて再突合し、乖離が2倍を超えるなら価格表の前提を疑う |
| Q1 | reasoning（thinking）トークンの課金上の扱い | 費用推定の精度 | U5（孫0 P2）。判明するまで `reasoning_tokens: null` |
| Q2 | Agent SDK credit と interactive quota の関係 | 将来Cの評価に影響 | 本傘では `claude -p` を使わないため未解決のままで問題ない。**混同しないことだけをschemaで担保**（`entrypoint` を記録） |
| Q3 | 固定費（Pro $20等）のPR配賦方法 | レポート解釈 | 第一段階では配賦しない。`cost_basis: subscription` で分離表示のみ |

---

## 18. Explicit approval checkpoint

### ✋ 承認ゲート1（**現在ここ**）

本計画書の承認。承認まで以下を行わない。

実装 / commit / push / PR作成 / 孫worktree作成 / `/umbrella-orchestrator autopilot` / `/spawn` /
`pr-review-loop` の編集 / `ocw` の挙動変更 / `claude-ds` の接続先変更 / probeの実行。

**probeについての事前説明（承認をお願いしたい項目）**

| probe | 課金 | 秘密情報への影響 | 生成ファイル |
|---|---|---|---|
| P1 statusLine | **なし** | なし | `~/.claude/statusline-probe.sh`（一時）、`claude/settings.machine.json` への一時追記（gitignore済）、`/tmp/claude-statusline-probe.jsonl` |
| P2 DeepSeek raw | **$0.01未満** | APIキーを読むが出力しない。`permissions.deny` 対象のため人間実行または明示許可が必要 | `/tmp/ds-probe-*.txt`（ヘッダはキー名のみ） |
| P3 突合 | なし | なし | なし（人間が管理画面を目視） |
| P4 `/usage` 非対話 | **Claude枠1ターン分** | なし | `/tmp/usage-probe.txt` |
| P5 制限到達の受動観測 | なし | なし | 観測メモ |

### ✋ 承認ゲート2（孫0マージ後）

孫0のADRを人間が確認し、孫3・孫4の設計を確定してから孫1へ進む。
**孫0の結果によっては孫3・孫4のプロンプトを書き換える。**

### ✋ 承認ゲート3（孫2マージ後）

instrumentationが実際のPR1本を通しても
「レビュー品質・ラウンド数・承認判定が変わっていない」ことを人間が確認してから孫3以降へ進む。

### 進行方法

`/umbrella-orchestrator /spawn 0` → 人間がPR確認 → マージ → `/check` → ゲート確認 → `/spawn 1` → …
**`/autopilot` は使用しない。**

---

## 孫0用プロンプト:

````
## タスク: feasibility probe の実施と ADR の作成

**このPRでは本番コードを1行も変更しない。docsのみ。**

### 背景

計画書 `docs/planning/DOC-003_ai-llm-cost-observability_計画.md` の第5章に、
既に実測確認済みの事実がまとめてある。まず第5章と第6章を熟読すること。

このタスクは、第6章の未確定事項 U1〜U8 を実際のprobeで潰し、
孫3（DeepSeek usage収集）と孫4（Claude quota収集）の設計を確定するADRを書くことである。

### やること

#### 1. probe の実施（P1, P3, P4, P5。P2は人間に依頼する）

**P1: statusLine の rate_limits 実証（課金ゼロ）**

1. `~/.claude/statusline-probe.sh` を作成する:
   - stdin の JSON をそのまま `/tmp/claude-statusline-probe.jsonl` に1行append
   - stdout には固定文字列（例 `probe`）だけ返す
   - どんな例外でも exit 0
2. `claude/settings.machine.json`（gitignore済み。無ければ `.example` からコピー）に
   `"statusLine": {"type": "command", "command": "bash ~/.claude/statusline-probe.sh"}` を追記
3. `claude/deploy.sh` を実行して `~/.claude/settings.json` に反映
   - **反映後、`~/.claude/settings.json` の `hooks` に Herdr の SessionStart が残っているか必ず確認する。
     消えていたら復元してから続行する**
4. Claude Code セッション（Anthropic本家、`claude` コマンド）を1つ起動し、何かプロンプトを1回投げる
5. 数分〜数時間放置して `/tmp/claude-statusline-probe.jsonl` を観察し、以下を記録する:
   - `rate_limits` キーが実際に出現するか（出現するまでの条件）
   - `five_hour.used_percentage` と `resets_at` の実値
   - `seven_day` が来るか
   - `resets_at` が5時間窓を跨いだときどう変わるか（可能な範囲で）
   - `claude-ds`（DeepSeek）セッションでは `rate_limits` が来ないことの確認
   - statusLine コマンドが1セッションあたり何回/分呼ばれるか（append行数から算出）
6. **probe終了後、`claude/settings.machine.json` の statusLine を必ず削除して deploy し直す**

**P3: 突合（課金ゼロ）**

`~/.claude/projects/*/*.jsonl` の全 `assistant` 行から `message.id` で重複排除して
model別に `input_tokens` / `cache_read_input_tokens` / `cache_creation_input_tokens` / `output_tokens` を合計し、
**2026年7月分だけ**に絞った値を出す（`timestamp` でフィルタ）。
その結果を、人間が DeepSeek 管理画面で確認した7月実績（requests / tokens / 金額）と並べて乖離率を出す。
管理画面の値は人間に聞くこと。**推測で埋めない。**

**P4: `/usage` 非対話（Claude枠を1ターン消費。実行前に人間に確認を取る）**

`claude -p "/usage" --output-format json` を1回だけ実行し、出力が機械可読か判定する。
散文なら「不安定・不採用」と結論する。

**P5: 制限到達の受動観測（課金ゼロ）**

probe期間中に5時間枠へ到達したら、その時刻の statusLine ダンプと transcript を保存する。
到達しなければ「未観測」と正直に記録し、孫4では `blocked` を best-effort 扱いとする結論を書く。

**P2: DeepSeek 生リクエスト（課金あり。自分で実行しない）**

以下の内容の probe スクリプト `docs/adr/probes/deepseek-raw-probe.sh` を**作成だけ**して、
人間に手動実行を依頼する。実行結果を人間から受け取ってADRに反映する。

- `curl` で `https://api.deepseek.com/anthropic/v1/messages` へ `max_tokens: 16` の最小リクエスト
- 非streaming 1回、streaming（`"stream": true`）1回
- APIキーは `${DEEPSEEK_API_KEY_FILE:-$HOME/.config/deepseek/api_key}` から読み、
  **変数経由でのみ渡す。`set -x` を使わない。スクリプトはキーを一切出力しない**
- 記録対象: レスポンスヘッダの**キー名一覧**（`request-id` 系や rate limit 系の有無）、
  非streamingの `usage`、streamingの `message_start` と `message_delta` に載る usage、
  `model` フィールドの実値（`deepseek-v4-pro[1m]` を指定したときに何が返るか）
- **`Authorization` ヘッダの値、APIキー、レスポンス本文のテキストは保存しない**

#### 2. ADR の作成

`docs/adr/ADR-001_llm-cost-observability-collection-method.md` を作成する。
（`docs/adr/` は新規ディレクトリ。既存に ADR 形式がなければこの形式を採用する）

必須セクション:

1. **Status**: Accepted / 日付
2. **Context**: なぜ観測が必要か（計画書2章の要約）
3. **実証できたこと**: probe の**実際の出力例**を貼る（秘密情報は除去）
   - 取得できる項目の一覧
   - **取得できない項目の一覧**（ここを曖昧にしない）
4. **壊れやすい箇所**: 形式変更で壊れる箇所と検知方法
5. **秘密情報の扱い**: 何を保存し、何を保存しないか
6. **採用案**: 事後読み取り方式（計画書7.1）を採用する根拠を、probe結果で裏付ける
7. **代替案と不採用理由**: 計画書7.3 の A〜F を probe 結果で更新する
8. **孫3・孫4への設計指示**: probe結果を踏まえ、変更が必要なら明記する
9. **見積もり**: 孫1〜5 の実装規模（ファイル数・行数の目安）

#### 3. 計画書の更新

probe結果によって計画書の記述（特に第5章・第6章・第17章）が事実と異なることが判明したら、
`docs/planning/DOC-003_ai-llm-cost-observability_計画.md` を修正する。
**都合よく書き換えない。取れなかったものは「取得不可」と書く。**

### 変更してよいファイル

- `docs/adr/ADR-001_llm-cost-observability-collection-method.md`（新規）
- `docs/adr/probes/*.sh`（新規。実行はしない/人間に依頼）
- `docs/planning/DOC-003_ai-llm-cost-observability_計画.md`（事実修正のみ）

### 絶対に変更しないファイル

`bin/ocw`, `bin/claude-ds`, `bin/deploy.sh`, `claude/settings.json`,
`claude/skills/**`, `deploy-all.sh`, `shared/helpers.sh`

（`claude/settings.machine.json` はgitignore済みのローカルファイルなのでprobe中の一時変更は可。
ただしprobe終了後に必ず元へ戻すこと）

### 完了条件

- P1/P3/P5 を実施し、実際の出力例がADRに貼られている
- P2 のスクリプトが作成され、人間に実行依頼済み（結果が得られたら反映）
- P4 の実行可否を人間に確認済み
- 「取得できない項目」が明示されている
- 孫3・孫4の設計に対する指示が書かれている
- probe用の一時設定がすべて元に戻っている（`~/.claude/settings.json` の `hooks` 健在を確認済み）

### テスト

このPRはdocsのみのため自動テストは不要。ただし以下を目視確認すること:

- ADR内のコマンドがすべて実在し、実際に実行できる
- 貼った出力例に秘密情報（APIキー、トークン、認証ヘッダ値、コード本文）が混入していない
- `deploy-all.sh --dry-run` が従来どおり動作する

### ロールバック

`git revert` のみ。副作用なし（probe用一時設定は本タスク内で戻す）。

### レビュー時に重点確認してほしい点

- **「取れないもの」を「取れる」と書いていないか**
- probe の出力例に秘密情報が混入していないか
- statusLine probe の後始末（設定復元、Herdr hooks健在）が完了しているか
- 本番コードに1行も変更が入っていないか
````

---

## 孫1用プロンプト:

````
## タスク: `bin/ocw-meter` コアとテスト基盤の実装

### 前提

計画書 `docs/planning/DOC-003_ai-llm-cost-observability_計画.md` の第8章（Event schema）、
第9章（Storage and privacy）、第10章（Failure behavior）、第13章（Test strategy）を熟読すること。
**孫0のADR `docs/adr/ADR-001_*.md` があれば、そちらの決定を計画書より優先する。**

### やること

#### 1. `bin/ocw-meter` を新規作成

単一実行ファイル。既存依存（bash + python3）のみを使う。新しいパッケージを入れない。
`bin/ocw` の実装スタイル（`set -euo pipefail`、`die`/`warn` ヘルパ、ヒアドキュメントでpython呼び出し）に合わせること。

実装するサブコマンド:

| サブコマンド | 内容 |
|---|---|
| `event <type> [--key value ...]` | 共通エンベロープを埋めてイベント1行をappend |
| `bind-pr --run <run_id> --pr <n> [--url <url>]` | `pr.bind` イベントを記録 |
| `validate [--file <path>]` | 保存済みイベントのschema検証。破損行をquarantineへ |
| `report [--pr N] [--json]` | **骨格のみ**。イベント件数と coverage/completeness の要約を出す（本格集計は孫5） |
| `help` | usage表示 |

`ingest` と `snapshot-quota` は**このPRでは実装しない**（孫3・孫4）。
ただしサブコマンドのディスパッチ構造は拡張しやすい形にしておく。

#### 2. schema の実装

計画書8.1のエンベロープ全フィールドと、8.2のイベント型のうち
`run.start` / `run.end` / `phase.start` / `phase.end` / `pr.bind` / `review.round` /
`human.intervention` / `block.start` / `block.end` / `meter.error` を扱えるようにする。
（`usage.message` と `quota.sample` はschema定義だけ入れて、生成は孫3・孫4）

- `schema_version: 1`
- 未知フィールドは保持する（前方互換）
- 必須フィールド欠落は検証エラー

#### 3. ストレージの実装（計画書9.1）

- 保存先: `${OCW_METER_HOME:-$HOME/.local/state/ocw-meter}`
- ディレクトリ 700 / ファイル 600 で作成
- `events/YYYY-MM-DD.jsonl` に append-only
- `flock` で排他。ロック取得が 100ms 超なら諦めて exit 0
- **保存先が git worktree 内だった場合は起動時にエラーで停止**（リポジトリ誤commit防止）
- `quarantine/` に破損行を退避（黙って捨てない）
- `state/seen-keys/YYYY-MM.txt` で `idempotency_key` の重複排除

#### 4. fail-open の徹底（計画書10.1）

- `event` / `bind-pr` は**どんな失敗でも exit 0**。stderr に1行warnのみ
- `validate` / `report` は失敗時に非ゼロで落ちる
- 例外時に入力データの中身をログへ出さない（`meter.error` は例外種別と段階のみ）

#### 5. テスト基盤の新設

- `bin/tests/test_ocw_meter.py`（python3 標準 `unittest`）
- `bin/tests/lint.sh`（`bash -n` で全shスクリプト、`python3 -m py_compile` でpythonをチェック）
- `bin/tests/fixtures/` にfixtureを配置
- 計画書13.2 の T01〜T11, T16〜T22 のうち、このPRの範囲で実施可能なものを実装する
  （T12〜T15 は孫3、T09/T10のquota部分は孫4で追加）
  - **T04（同一 message.id の複数行）と T06（並行writer20プロセス）は必ず含めること**
- **外部APIを一切叩かないこと。** ネットワークテストは書かない

#### 6. `.claude/pr-review.yml` の追加

```yaml
lint_cmd: "bin/tests/lint.sh"
test_cmd: "python3 -m unittest discover -s bin/tests -v"
```

**`.gitignore` に `/.claude/` があるため、除外指定を追加しないとcommitできない:**

```
# AI tools
/.claude/
!/.claude/
/.claude/*
!/.claude/pr-review.yml
```

（動作する形にすること。`git check-ignore -v .claude/pr-review.yml` で確認する）

#### 7. デプロイとドキュメント

- `bin/deploy.sh` に `ocw-meter` の symlink を追加（`symlink_backup` を使う。既存2行と同じ形）
- `bin/README.md` に `ocw-meter` の節を追加:
  - 目的、サブコマンド一覧、保存先、環境変数（`OCW_METER_HOME`, `OCW_METER_RAW`）
  - **「観測は fail-open。meterが無くても壊れない」ことを明記**
  - プライバシー方針（何を保存しないか）
- ルート `README.md` の Supported Tools 表の bin 行の説明に `ocw-meter` を追記

### 変更してよいファイル

`bin/ocw-meter`（新規）、`bin/tests/**`（新規）、`bin/deploy.sh`、`bin/README.md`、
`README.md`、`.gitignore`、`.claude/pr-review.yml`（新規）

### 絶対に変更しないファイル

`bin/ocw`, `bin/claude-ds`, `claude/skills/**`, `claude/settings.json`, `deploy-all.sh`, `shared/helpers.sh`

### 完了条件

- 上記サブコマンドが動作する
- `python3 -m unittest discover -s bin/tests -v` が緑
- `bin/tests/lint.sh` が緑
- `git check-ignore -v .claude/pr-review.yml` が「無視されない」ことを示す
- `bin/deploy.sh` を実行して `~/bin/ocw-meter` が張られ、`ocw-meter help` が動く
- 保存先がリポジトリ外であることを実機で確認
- **`ocw-meter` を PATH から外した状態で `ocw ls` が従来どおり動く**（T18の先取り確認）

### テスト

計画書13.2の該当ケース。特に:
- T03/T04: 重複排除（同一 idempotency_key、同一 message.id）
- T06: 20プロセス同時append で行崩れ・欠落なし
- T17: `sk-` で始まる文字列や `Authorization:` を含む入力が保存物に残らない
- T19: 保存先を読み取り専用にしても `event` が exit 0
- T22: git worktree内を `OCW_METER_HOME` に指定するとエラー

### ロールバック

`git revert` → `bin/deploy.sh` 再実行 → `~/bin/ocw-meter` symlink を手動削除。
`~/.local/state/ocw-meter/` は残す（データ保全）。

### レビュー時に重点確認してほしい点

- **fail-open が本当に徹底されているか**（`event` が exit 0 以外を返す経路が1つも無いか）
- 並行書き込みで行が混ざらないか（`flock` + 単一write）
- 保存物に秘密情報が入る経路が無いか
- `.gitignore` の除外指定が実際に効いているか（実コマンドで確認したか）
- schemaの必須/任意の区別が計画書8章と一致しているか
````

---

## 孫2用プロンプト:

````
## タスク: `ocw` と `pr-review-loop` への工程イベント埋め込み

### 前提

計画書 `docs/planning/DOC-003_ai-llm-cost-observability_計画.md` の第8.3章（phase列挙）と
第10章（Failure behavior）、第17章 R7 を熟読すること。孫1（`bin/ocw-meter`）がマージ済みであること。

### 最重要の制約

**このPRでレビュー規約・承認判定・停止条件・ペイン構成・役割の責務を一切変更しない。**

`claude/skills/pr-review-loop/SKILL.md` の以下は**1文字も変えてはいけない**:
- 「譲れないレビュー基準」8項目
- Phase 4 の判定基準
- 「安全制約」の禁止事項リスト
- 「停止してユーザーに報告する条件」

追加してよいのは、各Phaseの冒頭/末尾に置く**独立した1行のイベント記録コマンド**だけである。
既存の判断ロジックにイベント記録を絡めない（記録の成否が判定に影響してはならない）。

### やること

#### 1. `bin/ocw` への埋め込み

- worktree作成時に `run_id` を採番し、`run.start` イベントを記録する
  - `run_id` は `ocw` の標準出力にも `run:` 行として出す（既存の `workspace:` 等と同じ形式）
  - `run_id` を worktree 内の `.git/ocw-run-id`（gitに入らない場所）に保存し、後続が読めるようにする
- Herdrモードでは各ペイン起動時に環境変数 `OCW_ROLE`（`commander`/`implementer`/`reviewer`）と
  `OCW_RUN_ID` を渡す
  - `herdr pane run` で起動するコマンドに環境変数を渡す方法を調べて実装すること。
    渡せない場合は無理をせず、`herdr pane list` の `label` による役割解決（計画書7.4）に委ねて
    **その旨をREADMEに書く**（できないことをできるように見せない）
- `ocw rm` 時に `run.end` を記録
- **すべての呼び出しは `command -v ocw-meter >/dev/null && ocw-meter ... || true` の形にする**
- `ocw` の既存の終了コード・出力・ロールバック挙動を変えない

#### 2. `claude/skills/pr-review-loop/SKILL.md` への埋め込み

各Phaseの境界に、以下の形の**1行**を追加する（例）:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.start --phase self_review --round "$ROUND" || true
```

埋め込む箇所（計画書8.3のphase列挙に対応）:

| 箇所 | イベント |
|---|---|
| Phase 1 開始 | `phase.start --phase pr_create` / PR特定後に `bind-pr` |
| Phase 1.5 開始/終了 | `phase.start/end --phase self_review` |
| Phase 1.5 のlint/test前後 | `phase.start/end --phase lint_test` |
| Phase 2 送信前後 | `phase.start/end --phase review_request` |
| Phase 3 待機前後 | `phase.start/end --phase review_wait` |
| Phase 3b | `phase.start/end --phase review_collect` |
| Phase 4 判定後 | `review.round --round N --verdict <approved\|changes_requested\|ambiguous> --findings-count N --reviewed-head-sha SHA` |
| Phase 5 開始/終了 | `phase.start/end --phase fix` |
| Phase 6 | `phase.start/end --phase reply` → `rereview_request` |
| Phase 7 | `phase.end --phase done --outcome success` |
| 「停止してユーザーに報告する条件」に該当したとき | `human.intervention --reason <条件名>` |

**注意:**
- `--round` はスキルが既に追跡しているサイクル数を使う。新しいカウンタの概念を導入しない
- `findings_count` は「レビューで提示された指摘の件数」。**指摘の内容は記録しない**
- イベント記録の失敗を理由にPhaseを中断してはならない。`|| true` を必ず付ける
- スキル文書の可読性を落とさないよう、追加行には短いコメントを添える

#### 3. スキル冒頭への注記追加

`pr-review-loop` の冒頭付近に、次の趣旨を1段落だけ追加する:

> 本スキルには工程計測用の `ocw-meter` 呼び出しが含まれる。すべて fail-open であり、
> `ocw-meter` が存在しない環境でも本スキルは完全に動作する。
> 計測はレビュー判定に一切影響しない。

#### 4. ドキュメント

- `bin/README.md` の `ocw` の節に `OCW_ROLE` / `OCW_RUN_ID` / `run_id` 出力を追記
- `claude/README.md` に「pr-review-loop は工程イベントを記録する（fail-open）」を追記

### 変更してよいファイル

`bin/ocw`, `claude/skills/pr-review-loop/SKILL.md`, `bin/README.md`, `claude/README.md`, `bin/tests/**`

### 絶対に変更しないファイル

`bin/claude-ds`, `claude/settings.json`, `claude/skills/umbrella-orchestrator/SKILL.md`（任意変更も今回は見送る）

### 完了条件

- `ocw-meter` が PATH に無い状態で `ocw <name>` / `ocw -H <name>` / `ocw rm <name>` / `ocw ls` が
  **従来と完全に同じ出力・終了コード**で動作する（`run:` 行の追加を除く）
- `ocw-meter` がある状態で `run.start` / `run.end` が記録される
- `pr-review-loop` の規約テキスト（譲れないレビュー基準8項目、Phase 4判定、安全制約、停止条件）に
  **diffが1行も無い**ことを `git diff` で証明する
- 実PR1本で `pr-review-loop` を通し、phase/roundイベントが記録され、
  かつレビュー挙動が従来と変わらないことを確認する

### テスト

- 計画書 T18（meter不在）/ T19（書込失敗）/ T07（PR未作成→bind）
- `ocw` のドライラン相当（worktree作成→削除）でイベントが期待どおり出ること
- **既存挙動の非回帰**: `ocw` の全サブコマンドの出力を変更前後で比較する手順をPR説明に書く

### ロールバック

`git revert` のみ。追加行はすべて独立行のため、revertで完全に元へ戻る。

### レビュー時に重点確認してほしい点

- **レビュー規約・判定基準・停止条件に一切の変更が無いこと**（最重点。1文字でも変わっていたら変更要求）
- イベント記録の失敗が本番フローに波及する経路が無いか（`|| true` の付け忘れ）
- `ocw` の既存の終了コード・ロールバック挙動が変わっていないか
- スキルが長くなりすぎてLLMが手順を取りこぼすリスクが増えていないか（追加は最小限か）
- 環境変数を渡せない場合に「渡せることにしていない」か
````

---

## 孫3用プロンプト:

````
## タスク: DeepSeek usage の transcript ingest と費用推定

### 前提

計画書 `docs/planning/DOC-003_ai-llm-cost-observability_計画.md` の
第5.2〜5.5章、第5.10章、第8.4章、第17章 R1/R2/R5/R8 を熟読すること。
**孫0のADRに設計変更の指示があれば、そちらを優先する。**

孫1（`bin/ocw-meter`）がマージ済みであること。

### やること

#### 1. `ocw-meter ingest` の実装

`~/.claude/projects/<slug>/<session-id>.jsonl` を走査し、`usage.message` イベントを生成する。

**必須要件:**

- **`message.id` で重複排除する。** 実測で「179 assistant行 → 57 distinct message.id」であり、
  素朴な合計は3倍以上の過大計上になる。`idempotency_key = "msg:<message.id>"`
- `state/ingest-cursor.json` に (ファイルパス, inode, size, mtime, offset) を保存し増分読み取り。
  **何度実行しても結果が変わらないこと（冪等）**
- inode変化やサイズ縮小を検出したら当該ファイルを頭から読み直す（重複はキーで吸収）
- 最終行が壊れている（JSON不完全）場合は quarantine へ退避し、それ以前の行は生かす
- **`message.content` には一切触れない。** 抽出するのは
  `id` / `model` / `usage` / `stop_reason` / `timestamp` / `sessionId` / `gitBranch` / `cwd` / `isSidechain` / `effort` のみ
- `isSidechain: true` はサブエージェント分として区別できるようフィールドに残す

**役割・PR・runの帰属（計画書7.4）:**

1. `herdr pane list` から `agent_session.value`（= session_id）→ `label`（= role）と `workspace_id` / `pane_id` を解決
   - Herdr未起動・コマンド不在でも ingest は続行し `role: "unknown"` にする
2. PR番号は ①既存の `pr.bind` イベント ②transcript の `type: "pr-link"` 行 ③`gitBranch` からの後追い解決
   （`gh pr list --head <branch>` を使う。失敗しても続行）の順に解決。不明なら `null`
3. `run_id` は同一 worktree の `run.start` イベントから時刻範囲で解決。不明なら `null`
4. **どの経路でも解決できなければ `unknown` を書く。推測で埋めない**

#### 2. 価格表の実装

`bin/prices/deepseek-2026-08-01.json` を作成する:

```json
{
  "price_table_version": "deepseek-2026-08-01",
  "effective_date": "2026-08-01",
  "source": "https://api-docs.deepseek.com/quick_start/pricing",
  "fetched_at": "2026-08-01",
  "currency": "USD",
  "unit": "per_1m_tokens",
  "models": {
    "deepseek-v4-pro":   { "cache_hit_in": 0.003625, "cache_miss_in": 0.435, "out": 0.87 },
    "deepseek-v4-flash": { "cache_hit_in": 0.0028,   "cache_miss_in": 0.14,  "out": 0.28 }
  },
  "notes": "peak/off-peak 2x pricing announced (Beijing 09:00-12:00, 14:00-18:00) — effective date TBD as of fetched_at"
}
```

**実装前に必ず現在の公式価格ページを確認し、変わっていたら新しいversionのファイルを追加する
（既存ファイルは書き換えない）。**

費用計算（計画書8.4）:

```
cost = ( cache_read_input_tokens * cache_hit_in
       + (input_tokens + cache_creation_input_tokens) * cache_miss_in
       + output_tokens * out ) / 1_000_000
```

- モデル名の正規化: `deepseek-v4-pro[1m]` → `deepseek-v4-pro`（transcript上は既にサフィックスが落ちている）
- 価格表に無いモデルは `cost_estimate_usd: null` / `completeness: "unknown"`
- **Anthropicモデル（`claude-*`）は `cost_estimate_usd: null` / `cost_basis: "subscription"`。
  定額契約をAPI単価に換算しない**
- イベントには適用した `price_table_version` と `price_effective_date` を必ず記録する
- **既存イベントを新価格で再計算する機能を実装しない**

#### 3. 突合レポート `ocw-meter report --reconcile`

- 指定期間（既定: 当月）の transcript由来トークン合計を model別に出す
- provider管理画面の値を `--provider-total <model>=<tokens>` 形式で人間が渡せるようにし、
  カバレッジ比率を計算して表示する
- **出力に必ず `cost_basis: estimated — not an invoice` と coverage を併記する**

#### 4. 既知のカバレッジギャップの文書化

計画書5.10 の実測（v4-flashのtranscript記録が0件、v4-proのカバー率約89%）を
`bin/README.md` に「既知の限界」として明記する。**「全部取れている」と読める書き方をしない。**

### 変更してよいファイル

`bin/ocw-meter`, `bin/prices/**`（新規）, `bin/tests/**`, `bin/README.md`

### 絶対に変更しないファイル

`bin/claude-ds`（**接続先・環境変数を一切変更しない**）, `bin/ocw`, `claude/skills/**`, `claude/settings.json`

### 完了条件

- `ocw-meter ingest` が既存の全transcriptを走査でき、2回実行しても結果が同一（冪等）
- `message.id` 重複排除が効いている（実データで distinct 件数と一致することを示す）
- `ocw-meter report --reconcile` が model別トークン・推定費用・coverage を出す
- 全期間集計が計画書1章の実測値（v4-pro: miss 38.3M / hit 5.43B / out 12.0M）と整合する
- 推定費用が7月実績 $58.80 と同オーダーであることを確認し、乖離が2倍を超える場合は
  原因を調査して報告する（価格表の前提を疑う）
- transcript の本文（`message.content`）が保存物に一切現れない

### テスト

計画書 T12〜T16 と、加えて:
- 同一 `message.id` が複数行あるfixtureで1件に集約されること（**実transcript由来の縮小fixture**）
- 増分ingest（追記後に再実行）で新規分だけが増えること
- ファイルローテート・inode変化での再読み込み
- 価格表version変更後も既存イベントの `cost_estimate_usd` が変わらないこと
- **外部APIを叩かないこと**（`gh` 呼び出しはモック可能にし、既定でオフにする）

### ロールバック

`git revert`。生成済みイベントは残るが `ocw-meter validate` が旧schemaも読めること。

### レビュー時に重点確認してほしい点

- **重複排除が本当に効いているか**（ここを外すと全数字が無意味になる）
- 冪等性（2回実行で二重計上しないか、cursorのクラッシュ耐性）
- `message.content` に触れる経路が1つも無いか
- 価格表がハードコードされていないか、versionとeffective_dateが記録されるか
- 過去データを新価格で再計算していないか
- coverage を併記せずに数字だけ出す出力経路が無いか
````

---

## 孫4用プロンプト:

````
## タスク: Claude 利用枠スナップショットの収集（statusLine経由）

### 前提

計画書 `docs/planning/DOC-003_ai-llm-cost-observability_計画.md` の
第5.6章（statusLine スキーマ）、第8.5章、第17章 R3/R4/R6 を熟読すること。

**孫0 P1 の実証結果（ADR）が本タスクの範囲を決める。
実証できなかった項目は実装しない。「取得不可」と結論して文書化する。**

孫1（`bin/ocw-meter`）がマージ済みであること。

### やること

#### 1. `ocw-meter snapshot-quota` の実装

statusLine コマンドから呼ばれ、stdin の JSON を読んで `quota.sample` イベントを1行appendし、
**statusLine として表示する文字列を stdout に返す**。

**必須要件:**

- **例外が起きても必ず stdout に表示文字列を出し、exit 0 する**
  （statusLineが壊れると画面が壊れる。ここは絶対にfail-openにする）
- **サンプリング間隔の自制**: statusLineは描画のたびに呼ばれる。
  `state/quota-last-sample.json` に前回時刻を持ち、既定60秒（`OCW_METER_QUOTA_INTERVAL`で変更可）
  未満なら即座に表示文字列だけ返して終了する
- 記録するフィールド（計画書8.5）:
  `five_hour_used_pct` / `five_hour_resets_at` / `seven_day_used_pct` / `seven_day_resets_at` /
  `window_id`(= five_hour_resets_at) / `context_used_pct` / `session_id` / `model` /
  `pr_number`（statusLineの `pr.number`）/ `branch` / `cwd`
- **`rate_limits` が無い場合（DeepSeekセッション等）は `null` + `completeness: "unknown"` で記録する。
  捏造・推定をしない**
- 未知のキーが増えても落ちない。既知キーが消えても落ちない（`parser_version` を付けて partial 記録）
- **生JSONは既定で保存しない。** `OCW_METER_RAW=1` のときのみ `raw/` へ redaction 済みで保存

#### 2. 5時間窓の扱い（計画書8.5）

- 消費量の算出は **同一 `window_id` 内のサンプル同士でのみ差分を取る**
- `window_id` が変わったら新しい窓の開始として扱い、**跨いだ減算はしない**
- 同一 `window_id` 内で `used_percentage` が減少したら異常として `completeness: "partial"` を立て、警告する
- `report` 側に「PRが同一5時間窓で完走できたか」を判定するロジックを入れる
  （PRの最初と最後のイベント時刻が同一 `window_id` に収まるか）

#### 3. statusLine の配線

`claude/settings.json` に `statusLine` を追加する:

```json
"statusLine": { "type": "command", "command": "ocw-meter snapshot-quota" }
```

**重大な注意（計画書 R3）:**

- `~/.claude/settings.json` は **Herdr も書き込み**（`hooks.SessionStart`）、
  **`claude/deploy.sh` も生成し直す** 競合地帯である
- `hooks` には一切触らないこと
- **PR説明文に、デプロイ前後で `~/.claude/settings.json` の `hooks` が健在であることを
  実際に確認した結果を貼ること**
- `ocw-meter` が PATH に無い環境では statusLine が失敗する。表示が壊れないよう
  `bin/README.md` と `claude/README.md` に「`bin/deploy.sh` を先に実行すること」を明記する
- statusLine が表示する内容は最小限にする（例: `5h:37% 7d:12% ctx:24%`）。
  取得できない項目は表示しない

#### 4. ドキュメント

- `claude/README.md` に statusLine の役割・表示内容・無効化方法を記載
- **孫0で「取得不可」と結論した項目を明記する**（例: 制限到達時の待機時間が取れないなら、
  `blocked` は best-effort であることを書く）

### 変更してよいファイル

`bin/ocw-meter`, `claude/settings.json`（**`statusLine` キーの追加のみ**）,
`claude/README.md`, `bin/README.md`, `bin/tests/**`

### 絶対に変更しないファイル

`claude/settings.json` の `permissions` / `hooks` / `model` / その他既存キー、
`bin/ocw`, `bin/claude-ds`, `claude/skills/**`

### 完了条件

- `echo '<statusLine JSON>' | ocw-meter snapshot-quota` が表示文字列を返し、イベントを記録する
- **不正なJSON・空入力・`rate_limits` 欠落のいずれでも exit 0 で表示文字列を返す**
- サンプリング間隔の自制が効いている（連続呼び出しで記録が増えない）
- `claude/deploy.sh` 実行後、`~/.claude/settings.json` に statusLine が入り、
  **かつ Herdr の `hooks.SessionStart` が健在**であることを確認済み
- 実セッションで数分動かし、`quota.sample` が記録されることを確認
- DeepSeekセッションでは `rate_limits` が `null` として記録されることを確認

### テスト

計画書 T09（窓reset跨ぎ）/ T10（unknown usage）/ T11（UI出力形式変更）/ T21（timezone）と、加えて:
- 空入力・不正JSON・巨大入力で落ちないこと
- 同一 `window_id` 内での差分、`window_id` 変化時に減算しないこと
- 同一窓完走判定のロジック
- `OCW_METER_RAW=1` 時に redaction が効くこと（T17）

### ロールバック

`git revert` → `claude/deploy.sh` 再実行 → `~/.claude/settings.json` から statusLine が消えたことと
`hooks` が健在なことを目視確認。

### レビュー時に重点確認してほしい点

- **statusLine が絶対に画面を壊さないか**（全例外経路で stdout に文字列 + exit 0）
- 高頻度呼び出しに対する自制が効いているか
- `~/.claude/settings.json` の `hooks` を壊していないか（実機確認の証跡があるか）
- 5時間窓の跨ぎで単純減算していないか
- 取得できないものを `null`/`unknown` として正直に扱っているか
````

---

## 孫5用プロンプト:

````
## タスク: 集計レポートとベースライン計測手順

### 前提

計画書 `docs/planning/DOC-003_ai-llm-cost-observability_計画.md` の
第10.4章（部分データの明示）、第15章（Baseline measurement protocol）、第16章（Future experiments）を熟読すること。
孫1〜孫4がすべてマージ済みであること。

### やること

#### 1. `ocw-meter report` の拡充

以下の切り口で集計できるようにする。出力は人間が読める表（既定）と `--json`。

| オプション | 出力 |
|---|---|
| `--pr <N>` | PR別: 承認までの所要時間 / レビューラウンド数 / 各ラウンドの指摘数 / 人間介入回数 / 推定API費 / 5h枠消費 / 同一窓完走可否 / 最終結果 |
| `--phase` | 工程別: 時間、トークン内訳（miss/hit/out）、推定費用 |
| `--model` | model/provider別 |
| `--role` | role別（commander/implementer/reviewer/unknown） |
| `--window` | 5時間窓別: 窓ID、消費率、その窓に含まれるPR、blocked時間 |
| `--month [YYYY-MM]` | 月次: cash cost（従量API）/ capacity cost（Claude枠）/ process efficiency を**分離して**表示 |
| `--reconcile` | provider総計との突合（孫3で実装済みのものを統合） |

**必須要件（計画書10.4）: すべての出力に必ず以下を併記する**

```
coverage:     transcript-derived X tokens / provider-reported Y tokens (Z%)
completeness: complete A% / partial B% / unknown C%
quarantined:  N lines
price_table:  <version> (effective <date>)
cost_basis:   estimated — not an invoice
```

**指標の分離（依頼書5章 / 計画書16章）:**

- **Cash cost**: DeepSeek等の従量API費、固定サブスク費（**別項目**）
  - 固定費をPRへ配賦する場合は `allocation (analysis only)` と明示し、実額と混ぜない
- **Capacity cost**: Claude 5時間枠消費、週間枠消費、blocked時間、同一窓完走率
- **Process efficiency**: 承認済みPRあたりのAPI費 / 5h枠消費 / レビューラウンド / 人間介入 / 所要時間
- **Quality guardrail**: 第一段階では収集項目が無いため「未計測」と明示する
  （`defect.escaped` 等のイベント型が将来追加可能なことだけ書く）

**データが無い場合も落ちない。** 空なら「該当データなし」と表示する（T20）。

#### 2. ベースライン計測手順書

`docs/DOC-004_LLM費用観測ベースライン計測手順.md`（既存docs命名規則に合わせること）を作成する。
計画書15章を実行可能な手順に落とし込む。

必須内容:

1. 前提条件（孫1〜5マージ済み、**計測期間中はフロー・規約・モデル構成を変更しない**）
2. 計測対象: 実PR 5〜10本
3. 各PRでの手順（**特別な操作をしない**こと、`ocw-meter ingest` と `report --pr` の実行タイミング）
4. 月末の突合手順（DeepSeek管理画面との照合、coverage確定）
5. 集計テンプレート（表のフォーマット）
6. **必ず答える5つの問い**（計画書15.3）
7. 比較実験の事前基準（計画書16章の5条件）を明記し、
   **「結果を見てから閾値を変更するPRは、結果と同一PRにしない」というルールを書く**

#### 3. `bin/README.md` の完成

`ocw-meter` の全サブコマンド・全環境変数・保存先・プライバシー方針・**既知の限界**を1箇所にまとめる。

### 変更してよいファイル

`bin/ocw-meter`, `bin/tests/**`, `bin/README.md`, `docs/DOC-004_*.md`（新規）,
`docs/planning/DOC-003_*.md`（進捗テーブルの更新のみ）

### 絶対に変更しないファイル

`bin/ocw`, `bin/claude-ds`, `claude/skills/**`, `claude/settings.json`

### 完了条件

- 上記すべての集計オプションが動作する
- 全出力に coverage / completeness / price_table / cost_basis が併記される
- Cash cost と Capacity cost が明確に分離表示される
- データ0件でも落ちない
- ベースライン手順書が、他人がそのまま実行できる粒度で書かれている
- **手順書に書いた全コマンドを実際に実行して動作確認済み**（pr-review-loop 規約5「生成物は実物を読む」）

### テスト

計画書 T20（部分データ）/ T21（timezone境界）と、加えて:
- 各集計オプションのfixtureベーステスト
- 同一5時間窓完走判定の境界ケース
- 月次集計の月境界（JSTとUTCで日付が変わるケース）

### ロールバック

`git revert`。収集済みデータは影響を受けない。

### レビュー時に重点確認してほしい点

- **coverage 併記が全出力経路で漏れていないか**（1箇所でも漏れると「完全な記録」と誤認される）
- Cash cost と Capacity cost を混ぜていないか、固定費を実額として扱っていないか
- 手順書のコマンドが実在し、実際に実行されたか
- 事前基準が「後から都合よく変えられない」形で書かれているか
- 第一段階で測れないもの（品質guardrail）を「測れる」と書いていないか
````

---

## 実装完了後の流れ（全孫共通・必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `ai/llm-cost-observability` にすること。`master` には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する

実装が終わったタイミングで止まらず、必ずここまでやりきってください。

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `ai/llm-cost-observability` から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:

```
git checkout ai/llm-cost-observability && git pull --rebase origin ai/llm-cost-observability
git checkout -b <新しいブランチ名>
```
