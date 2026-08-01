# ADR-001: LLM費用・利用枠の収集方式

**Status**: Accepted  
**Date**: 2026-08-01  
**Decision by**: feasibility probe (孫0) の実測結果に基づく

---

## 1. Context

計画書 `DOC-003_ai-llm-cost-observability_計画.md` 第2章に詳述したとおり、
7月のLLM変動費 $58.80（DeepSeek API）の内訳が PR別・工程別・役割別に一切わからない。
また Claude Pro の5時間枠をどの工程で消費しているかも不明である。

最適化案を評価する物差しを作るため、第一段階では最適化を実装せず、観測基盤だけを構築する。
本ADRは、その観測基盤の**収集方式をprobe結果に基づいて確定**するものである。

---

## 2. 実証できたこと（Probe結果）

### 2.1 P1: statusLine `rate_limits`（✅ 実証完了）

**方法**: `~/.claude/statusline-probe.sh` を設置し、stdin JSON を `/tmp/claude-statusline-probe.jsonl` に追記。
2026-08-01 に実セッションで約1時間観測。66サンプル / 13セッションを収集。

**結果**:

#### Claude（Anthropic本家）セッション — `rate_limits` 取得可 ✅

実データ（`claude-opus-5`、2026-08-01T17:04:36+09:00採取。セッション名・パスは秘匿のため代表値を記載）:

```json
{
  "session_id": "756f06ff-28b8-412d-92db-cbd9dcece939",
  "session_name": "AI LLMコスト可視化の実装とPR作成",
  "prompt_id": "42f6cd60-9b99-4ad2-8c04-db12cf255f12",
  "cwd": "/home/manemone/projects/lora-dataset-forge/sweep-throughput",
  "transcript_path": "/home/manemone/.claude/projects/<slug>/756f06ff-....jsonl",
  "version": "2.1.220",
  "effort": { "level": "medium" },
  "thinking": { "enabled": true },
  "fast_mode": false,
  "exceeds_200k_tokens": false,
  "output_style": { "name": "default" },
  "model": { "id": "claude-opus-5", "display_name": "Opus 5" },
  "workspace": {
    "current_dir": "/home/manemone/projects/lora-dataset-forge/sweep-throughput",
    "project_dir": "/home/manemone/projects/lora-dataset-forge/sweep-throughput",
    "added_dirs": [],
    "git_worktree": "sweep-throughput",
    "repo": { "host": "github.com", "owner": "manemone", "name": "lora-dataset-forge" }
  },
  "cost": {
    "total_cost_usd": 0,
    "total_duration_ms": 26215997,
    "total_api_duration_ms": 0,
    "total_lines_added": 0,
    "total_lines_removed": 0
  },
  "rate_limits": {
    "five_hour": { "used_percentage": 0, "resets_at": 1785562800 },
    "seven_day": { "used_percentage": 77, "resets_at": 1785654000 }
  },
  "context_window": {
    "total_input_tokens": 0,
    "total_output_tokens": 0,
    "context_window_size": 1000000,
    "current_usage": null,
    "used_percentage": null,
    "remaining_percentage": null
  }
}
```

> **注**: `pr` と `worktree` キーは計画書5.6の公式スキーマには記載されているが、**今回収集した66サンプル中1件も出現しなかった**。PR番号の取得は transcript の `pr-link` または `ocw-meter bind-pr` に委ねる。

**確認事項**（2026-08-01T17:04+09:00 時点のスナップショット、66サンプル / 13セッション）:

| 項目 | 結果 |
|---|---|
| `rate_limits` の出現 | ✅ Claude本家セッションで出現（8/8サンプル）。DeepSeekセッションでは不在（58/58） |
| `five_hour.used_percentage` | ✅ 0–100の整数値。実測値: 0, 2, 4, 10, 11（5種類 / 8サンプル） |
| `five_hour.resets_at` | ✅ Unix epoch秒。実測値: `1785520200` / `1785562800` / `1785578400`（3種類 / 8サンプル）。**⚠️ ただし全8件は同一時刻（17:04:36）の1バーストであり、時系列での安定性は未検証** |
| `seven_day.used_percentage` | ✅ 実測値: 0, 1, 77, 78（4種類） |
| `seven_day.resets_at` | ✅ Unix epoch秒 |
| `resets_at` の窓識別子としての信頼性 | ⚠️ **注意**: 8サンプル中3件が観測時点で**既に過去の `resets_at`**（例: `1785520200` = 2026-07-31T17:50Z = 2026-08-01T02:50JST、観測は2026-08-01T17:04JST=08:04Z）。これらは前の5時間窓に属するstale値であり、`window_id` として使うには現在時刻との比較による**鮮度判定**が必須 |
| `context_window.used_percentage` | ⚠️ **59/66が非null**（範囲: 4%–48%）。Claude本家: 4/8非null（4%–48%）。DeepSeek: 55/58非null（8%–9%）。**「常にnull」は誤り。** ただしnullのケースもあるため null-safe な処理は必要 |
| `cost.total_cost_usd` | ✅ **66/66サンプルすべてに存在**。セッション開始からの累積コスト（USD）。DeepSeekセッションでも取得可能。**費用観測の1次データとして極めて有用** |
| statusLine トップレベルキー | 実測: `context_window`, `cost`, `cwd`, `effort`, `exceeds_200k_tokens`, `fast_mode`, `model`, `output_style`, `prompt_id`, `rate_limits`, `session_id`, `session_name`, `thinking`, `transcript_path`, `version`, `workspace`（`pr`/`worktree` は出現せず） |

#### DeepSeek（`claude-ds`）セッション — `rate_limits` なし（想定通り） ✅

`deepseek-v4-pro[1m]` セッション: **58/58サンプルすべてで `rate_limits` 不在**。
これは想定通り。DeepSeekセッションの quota は `null` + `completeness: "unknown"` として記録する。
なお **`cost.total_cost_usd` はDeepSeekセッションでも取得可能**（66/66サンプルで出現）。

#### statusLine の呼び出し頻度 ⚠️

1セッションあたり**最大54サンプル/約1時間**（DeepSeekセッション）。statusLine は描画のたびに呼ばれるため、
サンプリング間隔の自制（既定60秒）が必須（計画書R6のリスクが実在することを確認）。

### 2.2 P3: transcript突合（✅ 実証完了）

**方法**: `~/.claude/projects/*/*.jsonl` 全331ファイルを走査。
`type: "assistant"` 行（98,230行）から `message.id` で重複排除し、distinct 39,888メッセージを集計。

**7月分の実測値**:

| model | msgs | cache miss入力 | cache read入力 | cache create入力 | 出力 |
|---|---|---|---|---|---|
| `deepseek-v4-pro` | 29,676 | 38,336,862 | 5,428,087,040 | 0 | 11,983,028 |
| `claude-opus-4-8` | 6,970 | 334,850 | 1,257,701,774 | 32,359,266 | 6,879,838 |
| `claude-opus-5` | 2,137 | 4,029 | 287,041,135 | 8,455,043 | 2,173,348 |
| `claude-fable-5` | 282 | 30,019 | 21,338,804 | 893,461 | 273,868 |

**DeepSeek v4-pro 7月分 推定費用**: **$46.78**

| 内訳 | トークン数 | 単価(/1M) | 金額 |
|---|---|---|---|
| cache hit | 5,428,087,040 | $0.003625 | $19.68 |
| cache miss | 38,336,862 | $0.435 | $16.68 |
| 出力 | 11,983,028 | $0.87 | $10.43 |

**重複排除の重要性（計画書5.3の実証）**:  
assistant行 98,230行 → distinct message.id 39,888（**59.4%が重複**）。
`message.id` による重複排除がないと **2.5倍の過大計上**になる。

**カバレッジ（計画書5.10の再確認）**:
- `deepseek-v4-flash`: transcript上 **0件**（背景ユーティリティ呼び出しは記録されない）
- `deepseek-v4-pro`: 管理画面 6.177B tokens（計画書 §5.10の7月実測値より）に対し transcript 5.478B = **約89%カバー**
  - ⚠️ **分母（6.177B）は計画書執筆時点のスナップショットであり、7月請求確定値との突合は未了。人間による管理画面確認待ち**

**7月請求 $58.80 との比較**:
- transcript推定: $46.78
- ギャップ: $12.02（21%不足）。以下の既知要因で説明可能だが、正確な内訳は管理画面との突合が必要:
  - v4-pro未カバー分（transcriptに現れない約11%）: 仮にproportionalとすると約 $5.8 (= $46.78 × 11/89)
  - v4-flash分（transcriptカバー率0%）: 計画書 §5.10 の「107M tokens」から試算すると、hit率次第で $1未満〜最大$15
  - streaming中断・retry課金分: 定量不可
  - 複数マシン・複数プロジェクトの集約誤差: 定量不可
  - **結論**: ギャップの大部分は v4-pro未カバー + v4-flash で説明可能だが、突合による検証なしに「閉じている」とは言えない。孫3で改めて突合する

### 2.3 P2: DeepSeek 生リクエストprobe（スクリプト作成済み・人間実行待ち）

`docs/adr/probes/deepseek-raw-probe.sh` を作成。以下の情報を採取する:

- 非streaming / streaming 両方のレスポンスヘッダキー名一覧
- 実課金モデル名（`deepseek-v4-pro[1m]` 指定時のレスポンス値）
- streaming の `message_start` / `message_delta` に載る usage
- （注: 中断テストは本スクリプトでは行わない。中断時の課金有無は管理画面で翌日確認）

**APIキーは一切出力しない**（`set -x`不使用、環境変数経由のみ、出力前にpythonでフィルタ）。

→ **人間の実行結果を待ってADRに反映する。**

### 2.4 P4: `/usage` 非対話probe（未実施・人間確認待ち）

`claude -p "/usage" --output-format json` を1回実行し、出力が機械可読か判定する。
Claude枠を1ターン消費するため、**実行前に人間の確認が必要**。

→ **現時点では statusLine JSON の方が機械可読性で優れているため、P4は参考確認の位置づけ。**

### 2.5 P5: 制限到達の受動観測（未観測）

probe期間中（2026-08-01）に5時間枠への到達は発生しなかった。
「未観測」と正直に記録し、孫4では `blocked` を best-effort 扱いとする。

---

## 3. 取得できない項目と未確認項目

以下は本方式では**現時点で取得できない、または未確認**の項目である。曖昧にせず明示する。
「原理的に取得不可」と「未確認（P2/P4/P5待ち）」を区別して記載する。

| 項目 | 区分 | 理由 |
|---|---|---|
| `deepseek-v4-flash` の全usage | **原理的不可** | Claude Code の背景ユーティリティ呼び出し（タイトル生成・要約等）とサブエージェントは transcript に**一切記録されない**（計画書5.10） |
| streaming中断・retryで課金されたリクエスト | **原理的不可** | transcript には「usage付きの完成メッセージ」としてしか現れない（計画書5.4） |
| APIキー・認証ヘッダの値 | **原理的不可**（意図的） | transcript に記録されない。meter も一切触れない |
| プロンプト全文・モデル応答全文 | **原理的不可**（意図的） | transcript の `message.content` は意図的に読まない |
| DeepSeek管理画面のリアルタイム値 | **原理的不可** | APIが存在しない（月次請求のみ） |
| `context_window.used_percentage` の実値 | **条件付き可** | 取得可能な場合が多い（59/66非null）が、nullのケースもある（7/66）。null-safeな処理が必要 |
| 5時間枠到達による待機時間 | **未確認**（P5待ち） | 原理的には `agent_status: "blocked"` と statusLine の組み合わせで検出可能だが、実データ未収集のため第一段階では best-effort |
| reasoning（thinking）トークン | **未確認**（P2待ち） | transcriptの `usage` に `reasoning_tokens` フィールドが存在するかはP2後に判明。現時点では `reasoning_tokens: null` |

---

## 4. 壊れやすい箇所と検知方法

| 壊れ方 | 影響 | 検知方法 |
|---|---|---|
| statusLine JSONに未知キー追加 | 解析失敗の可能性 | `parser_version` を付けて partial 記録。未知キーは無視して続行 |
| statusLine JSONから既知キー消失 | `rate_limits` が取れなくなる | `completeness: "unknown"` + `meter.error`。落ちない |
| `message.id` の形式変更 | 重複排除が効かず過大計上 | `validate` で distinct 比率を監視。異常検出時に警告 |
| transcript のスキーマ変更 | ingest が失敗 | `parser_version` + `quarantine` に退避。データを捨てない |
| Herdr が `~/.claude/settings.json` の `hooks` を書き換える | statusLine 消失 or Herdr 機能停止 | **deploy 前後の `hooks` 確認を必須手順化**（計画書R3。本probeでも実際に1度hooks消失が発生した） |
| `resets_at` が過去時刻を返す（stale値） | 前窓の値を新窓の `window_id` として誤用 | 現在時刻と比較し `resets_at <= now` ならstaleと判定。孫4で鮮度チェックを実装（本probeで3/8件のstaleを実測） |
| `context_window.used_percentage` がnull | 一部セッションで使用率欠落 | null-safe処理。`total_input_tokens / context_window_size` をフォールバック計算（本probeで7/66件のnullを実測） |
| DeepSeek ピーク/オフピーク料金開始 | 費用推定が外れる | 価格表をversion管理。新version追加（上書き禁止）。過去データは再計算しない |

---

## 5. 秘密情報の扱い

### 保存しないもの（計画書9.2準拠）

- プロンプト全文 / モデル応答全文 / ソースコード本文
- `.env` / APIキー / 認証ヘッダ / GitHub token / DeepSeek token / Claude credential
- ターミナル全文
- `Authorization` ヘッダの値
- `sk-[A-Za-z0-9]+` パターンにマッチする文字列

### 保存するもの

- トークン数（`input_tokens` / `cache_read_input_tokens` / `cache_creation_input_tokens` / `output_tokens`）
- モデル名、セッションID、タイムスタンプ、ブランチ名
- `rate_limits` の使用率（パーセンテージ）と `resets_at`（epoch秒）
- 工程名、ラウンド数、PR番号、役割
- イベントのメタデータ（`event_id` / `idempotency_key` / `schema_version` / `completeness`）

### 保存先

`~/.local/state/ocw-meter/`（リポジトリ外、mode 700）。リポジトリ配下への書き込みはプログラムで拒否。

### opt-in raw保存

`OCW_METER_RAW=1` 時のみ `raw/` に保存。保存前に `authorization` / `api[-_]?key` / `token` / `sk-[A-Za-z0-9]+` を `[REDACTED]` に置換。

---

## 6. 採用案: 事後読み取り + 軽量イベント刻み

計画書7.1のアーキテクチャを、probe結果により**すべて実現可能**と確認した。

```
本番フロー → ocw / claude / claude-ds / pr-review-loop （一切割り込まない）
                │
   ┌────────────┼──────────────┐
   ▼            ▼              ▼
transcript   herdr list    statusLine
(usage)      (role↔session) (rate_limits)
   │            │              │
   └────────────┴──────────────┘
                ▼
        ocw-meter ingest / snapshot-quota
                ▼
      ~/.local/state/ocw-meter/events/
```

**採用の根拠（probe結果による裏付け）**:

1. transcript に費用計算に必要な全トークン数が入っている（P3実測）
2. statusLine に `rate_limits` が機械可読で入っている（P1実測）
3. statusLine に `cost.total_cost_usd`（セッション累積コスト）が入っている（P1実測、66/66サンプル）。DeepSeekセッションでも取得可能であり、費用推定の補完・検証に使える
4. `message.id` 重複排除で正確な集計が可能（P3実測: 59.4%重複除去）
5. Herdr の役割↔セッション結合キーが存在する（計画書5.7確認済み）

**制約（許容可能と判断）**:

1. v4-flash のカバレッジが0%（金額寄与は限定的: 107M tokens ≒ 最大$15、大半がhitなら$1未満）
2. v4-pro カバレッジが約89%（coverageを全レポートに併記することで誤認防止）
3. streaming中断分は捕捉不可（`cost_basis: estimated` を明示）

---

## 7. 代替案と不採用理由

probe結果を踏まえて計画書7.3を更新する。

| 案 | 内容 | 不採用理由（probe結果による更新） |
|---|---|---|
| **A. ローカル透過gateway** | HTTPプロキシで全捕捉 | **保留**（U6の乖離率が許容できない場合の将来option）。P3で89%カバレッジを確認したため、第一段階では過剰と判断 |
| **B. OpenTelemetry** | `CLAUDE_CODE_ENABLE_TELEMETRY=1` | collector常駐が必要。console exporterはTUIを汚す。P1でstatusLineという軽量代替を確認済み |
| **C. Claude Code hooks** | `Stop` hook で usage 収集 | **hook入力にusageは含まれない**（5.9で確認済み）。さらに `settings.json` の競合問題（本probeでhooks消失を実体験） |
| **D. `/usage` TUIパース** | ペインから `/usage` を送る | P1で statusLine JSON に `rate_limits` が機械可読で入ることを確認。TUIパースより遥かに安定 |
| **E. SQLite** | イベントをDBに | 全期間 39,888 messages / 数MB。JSONL + python集計で秒オーダー。P3実測でも331ファイルの全走査が数秒で完了 |
| **F. provider請求API** | DeepSeek利用履歴API | 月次総額のみ。PR別内訳にならない。P3で transcript由来の内訳が可能なことを確認済み |

---

## 8. 孫3・孫4への設計指示

probe結果を踏まえ、計画書の孫3・孫4プロンプトに以下の反映が必要。

### 孫3（DeepSeek usage収集）への指示

1. **重複排除は `message.id` で行う**（P3で59.4%重複を実測済み。計画書5.3の想定通り）
2. **価格表は計画書8.4の式で計算**。P3の推定値 $46.78 が基準値
3. **v4-flash の不可視性を `report` 出力に明記**すること
4. **P2の結果が得られたら反映**（モデル名正規化、reasoningトークンの扱い、streaming中断の実態）

### 孫4（Claude quota収集）への指示

1. **`rate_limits` は Claude本家セッションでのみ取得可能**。DeepSeekセッションは `null` + `completeness: "unknown"`（P1実測）
2. **サンプリング間隔の自制（既定60秒）が必須**（P1で1セッション最大54サンプル/1時間を実測。予想以上に高頻度）
3. **`context_window.used_percentage` は非nullが多数（59/66）だがnullのケースもある**（P1実測）。null-safeに処理し、null時は `total_input_tokens / context_window_size` をフォールバック計算する
4. **`resets_at` を `window_id` として使用する際は鮮度判定が必須**（P1で8サンプル中3件がstale値＝過去窓の `resets_at` を返していた）。現在時刻と比較し `resets_at <= now` ならstaleとして扱う
5. **`cost.total_cost_usd` が全セッションで取得可能**（P1実測、66/66サンプル）。Claude本家・DeepSeek両方で出現。quotaサンプルに含めて `report` で参照できるようにする
6. **`settings.json` の `hooks` 消失リスクが実在する**（本probe中に1度発生）。PR説明文に必ず `hooks` 確認の証跡を含めること
7. **statusLine の表示文字列は `5h:37% 7d:12% ctx:24%` 程度の最小限に**。`context_window.used_percentage` がnullの場合は `ctx` を非表示にする

### P2結果待ち項目

P2（DeepSeek生リクエスト）の結果が得られたら以下を更新する:

- `deepseek-v4-pro[1m]` 指定時の実課金モデル名
- レスポンスヘッダのキー名（`request-id` 系の有無）
- streaming `message_delta` の usage 構造
- reasoning トークンの扱い
- 中断時の課金有無

---

## 9. 見積もり

probe結果を踏まえた孫1〜5の実装規模。P1〜P5の結果により計画書から大きく変わらない見通し。

| 孫 | 内容 | ファイル数 | 行数目安 |
|---|---|---|---|
| 1 | `bin/ocw-meter` コア + テスト基盤 | 新規5〜7 | ~800行（本体）+ ~500行（テスト） |
| 2 | `ocw` + `pr-review-loop` へのイベント埋め込み | 変更4 | ~100行追加 |
| 3 | transcript ingest + 価格表 + 費用推定 | 変更2 + 新規2 | ~400行追加 |
| 4 | statusLine snapshot-quota（P1結果に基づき範囲確定済み） | 変更3 | ~300行追加 |
| 5 | 集計レポート + ベースライン手順書 | 変更2 + 新規1 | ~500行追加 + 手順書 |

**合計**: 新規8〜10ファイル、変更11ファイル、約2,600行。
**外部依存**: python3 標準ライブラリのみ。新規パッケージインストール不要。
**課金**: 実装・テストともにゼロ（全テストはfixture駆動。ネットワークテストは分離）。

---

## Appendix A: P1 probe 後始末チェックリスト

- [x] `claude/settings.machine.json` の `statusLine` 削除、`hooks` は保持（probe終了時に実施済み）
- [x] `claude/deploy.sh` 実行 → `~/.claude/settings.json` から `statusLine` 消失を確認
- [x] `~/.claude/settings.json` の `hooks.SessionStart`（`herdr-agent-state.sh`）健在を確認
- [x] `~/.claude/statusline-probe.sh` 削除済み
- [x] `/tmp/claude-statusline-probe.jsonl` 分析完了（66サンプル / 13セッション）
- [ ] `/tmp/claude-statusline-probe.jsonl` 削除（分析完了後、手動で削除）
- [ ] `/tmp/ds-probe-*.txt` 削除（P2実行後に手動で削除）

**後始末実施日**: 2026-08-01T17:11+09:00
**最終確認**: `~/.claude/settings.json` に `statusLine` キーなし、`hooks.SessionStart` あり（`herdr-agent-state.sh`）

## Appendix B: P3 集計スクリプト

集計に使用したPythonスクリプトは `docs/adr/probes/` 以下には保存しない（一時的な分析のため）。
同等の機能は孫3で `ocw-meter ingest` として恒久化される。

## Appendix C: P2 probeスクリプト

`docs/adr/probes/deepseek-raw-probe.sh` — 人間が手動実行する。APIキーを一切出力しない。
