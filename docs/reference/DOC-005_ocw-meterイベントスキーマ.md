# DOC-005: ocw-meter イベントスキーマ

`ocw-meter`（`bin/ocw-meter`）が `~/.local/state/ocw-meter/events/YYYY-MM-DD.jsonl` に書く
全イベントの恒久リファレンス。**このファイルがスキーマの一次情報源。**
`docs/planning/DOC-003_ai-llm-cost-observability_計画.md`（計画書）第8章にも同内容の初期設計があるが、
計画書は傘ブランチ完了後は歴史的記録（意思決定の経緯を追う副次的な参照）になる。
保存済みイベントは `schema_version: 1` を持ったまま何年も残り続けるため、
「今すぐこのフィールドが何を意味するか」を調べるときは常にこの文書を読むこと。

対象読者: `ocw-meter report`/`ingest` の出力を読む人、新しい `event_type` を追加する人、
将来 `schema_version: 2` を検討する人。

---

## 1. 共通エンベロープ

全イベントに共通するフィールド。値は `bin/ocw-meter` の `ENVELOPE_FIELDS` 定数と一致する。

| フィールド | 型 | 必須 | 意味 |
|---|---|---|---|
| `schema_version` | int | 必須 | 常に `1`（本ドキュメント時点）。§6参照 |
| `event_id` | string(uuid4) | 必須 | イベント一意ID。呼び出し側が指定しなければ自動生成される |
| `idempotency_key` | string | 必須 | 重複排除キー。**§3で型ごとの生成規則を説明** |
| `event_type` | string | 必須 | §2の一覧のいずれか。表に無い型も forward-compatible として保存される（拒否しない） |
| `ts` | string (RFC3339 UTC) | 必須 | 例 `2026-08-01T09:05:00.000Z`。**常にUTC**。日次ファイル名（`events/YYYY-MM-DD.jsonl`）もこの値のUTC日付で決まる（ローカル日付ではない） |
| `ts_local_offset` | string | 必須 | イベントを記録したマシンのローカルoffset（例 `+09:00`）。集計には使わない参考情報 |
| `source` | string | 必須（`unknown`許容） | `ocw` / `pr-review-loop` / `transcript` / `statusline` / `unknown`。呼び出し元を明示するが、**実際には多くの呼び出しでこのフラグは渡されずデフォルト値 `unknown` のまま**（下記の実例参照）。値が入っていない＝観測できていない、ではなく「呼び出し側がこのフィールドを渡さなかった」ことを意味する点に注意 |
| `parser_version` | int \| null | `transcript`/`statusline`由来のみ必須 | 生データ解釈ロジックのバージョン。`usage.message`（ingest由来）は `INGEST_PARSER_VERSION`、`quota.sample`は `STATUSLINE_PARSER_VERSION`（いずれも現在`1`）。それ以外の型は常に `null`（生データの「解釈」を挟まない、CLI引数をそのまま保存するイベントのため） |
| `completeness` | string | 必須 | `complete` / `partial` / `unknown`。**判定基準は §5参照** |
| `run_id` | string \| null | — | 実行系列ID。`bin/ocw`がworktree作成時にULID風 `<epoch>-<rand>` で採番し `OCW_RUN_ID` 環境変数で各ペインに渡す。非Herdrモードや環境変数未exportの呼び出しでは `null` |
| `repo` | string \| null | — | `owner/name`。`git remote`から解決 |
| `worktree` | string \| null | — | worktree絶対パス |
| `branch` | string \| null | — | git branch |
| `head_sha` | string \| null | — | 記録時点のHEAD |
| `workspace_id` | string \| null | — | Herdr workspace（`HERDR_WORKSPACE_ID`環境変数から） |
| `pane_id` | string \| null | — | Herdr pane（`HERDR_PANE_ID`環境変数から） |
| `role` | string | 必須（`unknown`許容） | `commander` / `implementer` / `reviewer` / `unknown`。優先順位は計画書§7.4: ①`OCW_ROLE`環境変数 ②（`ingest`のみ）Herdr `pane list`の`label`をsession_id経由で解決 ③どちらも失敗したら`unknown`（推測しない） |
| `session_id` | string \| null | — | Claude Codeのsession_id。`ingest`（transcript由来）のみ設定される |
| `provider` | string \| null | — | `anthropic` / `deepseek` / `unknown` / `null`。`model`名から`infer_provider()`で機械的に判定（`claude-`prefix→anthropic、`deepseek-`prefix→deepseek） |
| `model` | string \| null | — | 実モデル名。`ingest`は`[1m]`等のcontext-windowサフィックスを`normalize_model_name()`で除去して保存 |
| `phase` | string \| null | — | §2.3の phase 列挙のいずれか。**`usage.message`（ingest由来）は常に`null`** — transcriptにはpr-review-loopの工程情報が無いため、`ingest`はこのフィールドを解決しない。`ocw-meter report --phase`はここではなく時刻範囲でのベストエフォート対応を行う（§2.3参照） |
| `round` | int \| null | — | レビューラウンド（1始まり） |
| `pr_number` | int \| null | — | 後からbind可能。計画書§7.4のPR帰属ロジック（①`pr.bind` ②transcriptの`pr-link`行 ③`gh pr list --head`フォールバック）で解決 |
| `pr_url` | string \| null | — | 同上 |

`null` と値が存在しないことの違いはない（JSON上は同じ `null`）。**`0`と`null`は明確に区別される**
（例: `reasoning_tokens: null`＝「取得できていない」、`reasoning_tokens: 0`＝「実測してゼロだった」。
現状 `reasoning_tokens` は常に`null`。U5未確定のため、実測せずに0で埋めることはしない）。

`event_type`が上記envelope表に定義されていない値であっても、イベント自体は拒否されず保存される
（`ocw-meter`が新しい`event_type`を知らないバージョンでも、将来追加された型のイベントを黙って
quarantineしない設計。計画書§9.1「未知フィールドは保持する」の型レベルへの拡張）。

---

## 2. 全 `event_type` 一覧

`bin/ocw-meter`の`EVENT_PAYLOAD_REQUIRED`辞書に列挙されている型が「必須payloadフィールドの検証対象」。
**この辞書に無い`event_type`は forward-compatible 扱い（payload検証なし）であり、
「未対応」ではなく「まだ誰も使っていないので検証ルールが無いだけ」を意味する。**

| `event_type` | 発生源（実際に呼んでいるコード） | 必須payload | 状態 |
|---|---|---|---|
| `run.start` | `bin/ocw`（`ocw <name>` / `ocw -H <name>` 実行時） | `base_ref`, `command` | ✅ 実装済み・実際に発火する |
| `run.end` | `bin/ocw`（`ocw rm` 実行時。`-f`強制削除時は`outcome: failure`） | `outcome` | ✅ 実装済み・実際に発火する |
| `phase.start` | `claude/skills/pr-review-loop/SKILL.md`（各Phaseの開始時） | `phase` | ✅ 実装済み。**ただし`implement`と`verdict`はphase.start/endのペアを一切発火しない**（下記§2.3参照） |
| `phase.end` | 同上（各Phaseの終了時） | `phase` | ✅ 同上。`outcome`（`success`/`failure`/`blocked`）は**`done`フェーズのみ**実際に渡される（他フェーズのphase.endは`outcome`無しで発火する） |
| `pr.bind` | `claude/skills/pr-review-loop/SKILL.md`（Phase 2、PR作成直後） / `ocw-meter bind-pr` CLI | `pr_number` | ✅ 実装済み。**この型だけ`idempotency_key`が明示的に決定論的**（§3参照） |
| `review.round` | `claude/skills/pr-review-loop/SKILL.md`（Phase 4、判定確定時） | `round`, `verdict`, `findings_count` | ✅ 実装済み。`verdict`は`approved`/`changes_requested`/`ambiguous`のみ |
| `human.intervention` | `claude/skills/pr-review-loop/SKILL.md`（規約上の停止条件に到達したとき） | `reason` | ✅ 実装済み |
| `usage.message` | `ocw-meter ingest`（transcript走査） | `message_id`, `input_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`, `output_tokens`, `cost_basis` | ✅ 実装済み。**`phase`/`round`は常に`null`**（上記参照） |
| `quota.sample` | `ocw-meter snapshot-quota`（statusLineコマンドとして呼ばれる） | `plan_source` | ✅ 実装済み |
| `block.start` | （未実装） | `cause` | ❌ **未実装** — スキーマ（`EVENT_PAYLOAD_REQUIRED`のenum制約含む）は定義されているが、これを発火する呼び出しはリポジトリ内のどこにも存在しない。計画書§8.2で「best-effort」と明記された通り、5時間枠blockedの検出は現状statusLineの`rate_limits`スナップショットからの間接推測（`quota.sample`側）のみで、専用イベントとしては未収集 |
| `block.end` | （未実装） | `cause` | ❌ 同上 |
| `meter.error` | `ocw-meter`自身の自己診断（lock timeout、worktree誤設定検知、ingest中の予期しない例外等） | `stage` | ✅ 実装済み。**`events/`ではなく`state/meter-errors.jsonl`という別ファイルに書かれる**（`report`のquarantine件数とは別カウントで表示される） |

### 2.1 `phase.end`の`outcome` enum

`success` / `failure` / `blocked`（`EVENT_ENUM_FIELDS["phase.end"]["outcome"]`）。
不正な値は`validate`実行時に`completeness: partial`へダウングレードされる（quarantineはされない — payload形状違反であり壊れたJSONではないため）。

### 2.2 `review.round`の`verdict` enum

`approved` / `changes_requested` / `ambiguous`（`EVENT_ENUM_FIELDS["review.round"]["verdict"]`）。

### 2.3 `phase` 列挙（計画書§8.3）と実際の発火状況

計画書§8.3が定義する12個のphase名のうち、**`implement`と`verdict`はこのリポジトリのどのコードからも
phase.start/phase.endとして発火されない**:

| phase名 | 実際に`phase.start`/`phase.end`が発火するか |
|---|---|
| `implement` | ❌ 発火しない。実装作業（pr-review-loop起動前の通常のコーディング）は工程境界イベントの対象外 |
| `self_review` | ✅ |
| `lint_test` | ✅ |
| `pr_create` | ✅ |
| `review_request` | ✅ |
| `review_wait` | ✅ |
| `review_collect` | ✅ |
| `verdict` | ❌ 発火しない。判定の確定は`review.round`イベント（phase境界ではなく単発イベント）としてのみ記録される |
| `fix` | ✅ |
| `reply` | ✅ |
| `rereview_request` | ✅ |
| `done` | ✅（`phase.end`のみ。`phase.start`は発火しない — 「完了」は瞬間的な状態でありstart/endのペアを持たない） |

`ocw-meter report --phase`はこの表の「✅」のphaseのみ実際にwindow（時間区間）として現れる。
`(unassigned)`バケットには「`implement`フェーズ中に生成されたusage.message」が実質的に集約される
（`implement`という名前のバケットは決して現れない）。

> **⚠️ 孫5で実データ検証して判明した重大な制約（実測）**: このマシンの実ストア
> （`~/.local/state/ocw-meter/events/`、44,425件の`usage.message`）を集計すると、**`run_id`が
> 設定されている`usage.message`は0件**だった。`report --phase`のトークン内訳は、この時点の実データでは
> **全件が`(unassigned)`になる**（実行結果は`docs/reference/DOC-004_LLM費用観測ベースライン計測手順.md`
> §2.2参照）。原因は`ingest`の`run_id`解決ロジック
> （`resolve_run_id_via_ocw_run_id_file`）が「そのメッセージの`cwd`（＝worktreeパス）の
> `<git-dir>/ocw-run-id`ファイルを**ingest実行時点**で読む」方式であること: `ocw rm`はworktreeごと
> このファイルを削除するため、**PRマージ後にworktreeを消してから`ingest`を実行すると、
> そのworktreeで生成された全メッセージのrun_idが永久に`null`のまま保存される**（§4の
> 「過去は再計算しない」不変条件により、後から`ingest`し直しても直らない）。
> `report --phase`を意味のある形で使うには、**PRの作業中〜マージ直後、worktreeを`ocw rm`する前に
> `ocw-meter ingest`を実行する運用**が必須（`docs/reference/DOC-004_...`§2で手順化）。

### 2.4 `usage.message` のペイロードフィールド（共通エンベロープに加えて）

`~/.local/state/ocw-meter/events/*.jsonl`の実データ（44,425件、2026-08-01時点）で
フィールド名の過不足を確認済み。

| フィールド | 型 | 由来 |
|---|---|---|
| `message_id` | string | transcriptの`message.id`。重複排除キーの元（§3） |
| `input_tokens` | int \| null | `usage.input_tokens` = cache **miss** トークン |
| `cache_read_input_tokens` | int \| null | cache **hit** トークン |
| `cache_creation_input_tokens` | int \| null | Anthropicのみ非0。DeepSeekは常に0 |
| `output_tokens` | int \| null | |
| `reasoning_tokens` | null（常に） | U5未確定（孫0 P2待ち）。フィールドとしては存在するが、実データは常に`null` — 0で埋めない |
| `is_sidechain` | bool \| null | `isSidechain`（サブエージェント判定） |
| `effort` | string \| null | `high`等 |
| `stop_reason` | string \| null | |
| `cost_estimate_usd` | float \| null | §4の式で計算。Anthropicは常に`null` |
| `price_table_version` | string \| null | 適用した価格表のバージョン（再計算されない、§4） |
| `price_effective_date` | string \| null | 同上の`effective_date` |
| `cost_basis` | string | `estimated`（DeepSeek等の従量課金） / `subscription`（Anthropic定額契約） |
| `currency` | string \| null | `USD`。`cost_basis == "subscription"`のときは`null` |

### 2.5 `quota.sample` のペイロードフィールド（共通エンベロープに加えて）

| フィールド | 型 | 由来 |
|---|---|---|
| `five_hour_used_pct` / `five_hour_resets_at` | number \| null | `rate_limits.five_hour`。`claude-ds`セッションは常に`null`一式 |
| `seven_day_used_pct` / `seven_day_resets_at` | number \| null | `rate_limits.seven_day` |
| `window_id` | string \| null | `five_hour_resets_at`の値そのもの。**未来時刻のときのみ**採用（stale値は`null`にする — 計画書§8.5） |
| `context_used_pct` | number \| null | `context_window.used_percentage`。`null`のときは`total_input_tokens / context_window_size`からのフォールバック計算値が入る場合がある（表示文字列側は使わない。`bin/README.md`参照） |
| `session_cost_usd` | number \| null | statusLineの`cost.total_cost_usd`（Claude Code自己申告のセッション累積コスト）。`usage.message`の`cost_estimate_usd`とは別カラムで、合算しない |
| `plan_source` | string | 常に`"statusline"` |
| `raw_ref` | string \| null | `OCW_METER_RAW=1`時のみ、redaction済みraw snapshotのファイル参照。既定`null` |
| `cwd` | string \| null | statusLine JSONの`cwd`（作業ディレクトリ）。**`ENVELOPE_FIELDS`には含まれない forward-compatible な追加フィールド** — envelope標準の`worktree`とは別に、statusLineが報告した生の`cwd`をそのまま保存する |

### 2.6 その他のevent_typeのペイロードフィールド（孫5で棚卸し・全て共通エンベロープに加えて）

孫5レビューで判明: `usage.message`/`quota.sample`以外にもペイロードフィールドを持つ型があり、
`EVENT_PAYLOAD_REQUIRED`（§2の「必須payload」列）には**必須のものしか載っていない**。
以下は残り全型の**任意（optional）を含む全ペイロードフィールド**の棚卸し。

| `event_type` | フィールド | 型 | 必須/任意 | 由来 |
|---|---|---|---|---|
| `run.start` | `base_ref` | string | 必須 | ベースブランチ名 |
| | `command` | string | 必須 | 起動コマンド（例 `claude`） |
| `run.end` | `outcome` | string | 必須 | enum制約なし（文字列自由）。`bin/ocw`実測では`success`（通常の`ocw rm`）/ `failure`（`ocw rm -f`の強制削除）の2値のみ |
| `phase.start` | `phase` | string | 必須 | §2.3のphase列挙のいずれか（enum制約なし。文字列自由） |
| `phase.end` | `phase` | string | 必須 | 同上 |
| | `outcome` | string | 任意 | `success`/`failure`/`blocked`（enum制約あり、§2.1）。**`pr-review-loop`の実際の埋め込みでは`phase: "done"`のphase.endにしか渡されない** — 他のphaseのphase.endには存在しない |
| | `duration_ms` | number | 任意（スキーマ定義のみ） | `NUMERIC_PAYLOAD_FIELDS`に列挙されているが、**実際にこれを渡す呼び出しはリポジトリ内に存在しない**（実データでも0件）。将来pr-review-loopが計測して渡すことを想定した予約フィールド |
| `pr.bind` | `pr_number` | int | 必須 | envelopeの`pr_number`と同じ値（`pr.bind`はこのフィールドを主目的に持つイベント） |
| `review.round` | `round` | int | 必須 | envelopeの`round`と同じ値 |
| | `verdict` | string | 必須 | `approved`/`changes_requested`/`ambiguous`（enum制約あり、§2.2） |
| | `findings_count` | int | 必須 | 未解決指摘の件数（承認なら0） |
| | `reviewed_head_sha` | string | 任意（スキーマ定義のみ・実質常に存在） | レビュー対象のHEAD SHA。`EVENT_PAYLOAD_REQUIRED`には無いが、`claude/skills/pr-review-loop/SKILL.md`の実際の埋め込みは毎回渡しており、実ストアでも**10/10件**に存在する。本PR（孫5）が新設した`report --pr <n> --json`の`pr_detail.review_rounds[].reviewed_head_sha`としてこの値を出力する |
| `human.intervention` | `reason` | string | 必須 | 停止条件の短い識別子（自由文字列。`claude/skills/pr-review-loop/SKILL.md`の「停止してユーザーに報告する条件」の一覧に対応する識別子を渡す想定だが、値そのものにenum制約は無い） |
| `meter.error` | `stage` | string | 必須 | 自己診断が発生した処理段階（例 `ingest`） |
| | `message` | string | 任意（スキーマ定義のみ・実質常に存在） | 例外メッセージ等の短い説明。**入力データそのものは含めない**（第9.2節「`meter.error`の`message`も例外文字列のみで、入力データを含めない」）。redactionは他フィールドと同じ規則が適用される |
| `block.start` | `cause` | string | 必須（型は定義済みだが未実装） | `rate_limit`/`api_error`/`unknown`（enum制約あり）。**発火する呼び出しがリポジトリ内に無い**（§2参照） |
| `block.end` | `cause` | string | 必須（同上） | 同上 |
| | `wait_ms` | number | 任意（同上） | 待機時間（ミリ秒）。`NUMERIC_PAYLOAD_FIELDS`に列挙されているが`block.*`自体が未実装のため実例なし |

---

## 3. `idempotency_key` の生成規則

計画書§8.1は「`usage.message`は`msg:<message.id>`、`phase.*`は`<run_id>:<phase>:<round>:<boundary>`」
と書いているが、**実装は`phase.*`について計画書と異なる**。実際の生成規則は次の通り:

| `event_type` | 実際のキー | 決定論的か |
|---|---|---|
| `usage.message`（`ingest`由来） | `msg:<message.id>` | ✅ 決定論的。同じtranscript行を何度ingestしても1件に収束する（第5.3節の重複行問題への対策） |
| `pr.bind` | `bind:<run_id>:<pr_number>` | ✅ 決定論的（`ocw-meter bind-pr`のCLIコードと`pr-review-loop`の呼び出し双方が明示的に指定） |
| `meter.error` | `meter-error:<stage>:<YYYY-MM-DD>` | ✅ 決定論的（1日1stage1件に自然にまとまる。自己診断が同じ理由で1日に何度も記録されないようにするため） |
| `run.start` / `run.end` / `phase.start` / `phase.end` / `review.round` / `human.intervention` | `auto:<event_id>`（`event_id`はランダムuuid4） | ❌ **ランダム。呼び出し側が`--idempotency-key`を明示的に渡さない限り重複排除は効かない。** `claude/skills/pr-review-loop/SKILL.md`・`bin/ocw`のいずれもこれらの型に`--idempotency-key`を渡していない（実際のコードを確認済み） |
| `quota.sample` | `auto:<event_id>`（同上） | ❌ ランダム。ただし呼び出し元の`snapshot-quota`サブコマンド自体が`state/quota-last-sample.json`によるスロットリング（既定60秒に1回まで）を`record_quota_sample`呼び出しの手前で行っているため、**実質的に「同じ内容が重複して書かれる」ことは起きない**（idempotency_keyでの重複排除ではなく、呼び出し頻度そのものの抑制で同じ目的を達成している） |

**実務上の含意**: `run.start`/`phase.start`/`phase.end`/`review.round`/`human.intervention`は、
同じ工程境界を手動で2回叩いてしまった場合（例: `pr-review-loop`のリトライ、ネットワーク再送等）、
**2件の別イベントとして記録される**（後勝ち上書きされない）。現状の運用（各行は1回しか実行されない
逐次スクリプト）では実害が出ていないが、将来リトライ機構を追加する場合はこの型のidempotency_keyを
明示的に決定論的なものへ変更する必要がある。

`idempotency_key`が空文字列や未指定で渡された場合、`build_envelope`は`auto:<event_id>`へ
フォールバックする（空キーで保存されることはない）。

重複排除そのものの意味論: 同一`idempotency_key`のイベントを再送すると、既存行を
**後勝ち(last-write-wins)で置き換える**（新しい行を追記するのではなく、保存済みの行をmkstemp+os.replaceで
原子的に上書きする）。`usage.message`はこの性質を使って「同一message.idの複数行のうち最後（最も完全な
usage/stop_reasonを持つ）行を採用する」を実現している。

---

## 4. 費用計算式

```
cost = ( cache_read_input_tokens               * price.cache_hit_in
       + (input_tokens + cache_creation_input_tokens) * price.cache_miss_in
       + output_tokens                         * price.out ) / 1_000_000
```

- `input_tokens` = cache **miss** 入力（DeepSeekの`cache_creation_input_tokens`は常に0 — DeepSeekは
  明示的なcache writeを課金しない自動prefixキャッシュのため）
- `cache_read_input_tokens` = cache **hit** 入力
- Anthropicモデル（`model`が`claude-`で始まる）は**定額契約**であり、上記の式を一切適用しない。
  `cost_estimate_usd: null` / `cost_basis: "subscription"`固定（`compute_cost()`内で早期リターン）
- 価格が定義されていないモデル（現状`deepseek-v4-flash`は価格表に含まれるが、
  価格表自体が存在しない/読めない等の異常時）は `cost_estimate_usd: null` / `completeness: "unknown"`
  （§5参照）

### 価格表（`bin/prices/*.json`）

```json
{
  "price_table_version": "deepseek-2026-08-01",
  "effective_date": "2026-08-01",
  "source": "https://api-docs.deepseek.com/quick_start/pricing",
  "currency": "USD",
  "unit": "per_1m_tokens",
  "models": {
    "deepseek-v4-pro":   { "cache_hit_in": 0.003625, "cache_miss_in": 0.435, "out": 0.87 },
    "deepseek-v4-flash": { "cache_hit_in": 0.0028,   "cache_miss_in": 0.14,  "out": 0.28 }
  }
}
```

- `ingest`は`OCW_METER_PRICE_DIR`（既定 `bin/prices/`）配下の全`*.json`を読み込み、
  各イベントの**メッセージ自身のタイムスタンプの日付**に対して`effective_date <= その日付`の
  うち最も新しいテーブルを選んで適用する（`ingest`を実行した日ではない）
- **不変条件: 過去に書き込まれた`usage.message`の`cost_estimate_usd`は、新しい価格表を追加しても
  再計算されない。** 価格改定の反映は「新しい価格表ファイルを追加する」だけで、既存イベントは
  書き込み時点の`price_table_version`/`price_effective_date`をそのまま保持し続ける
- `price_table_version`と`price_effective_date`は、そのイベントの費用計算に**実際に使われた**
  価格表のバージョン・発効日をそのまま複写したもの。「今の価格表」ではなく「このイベントを
  計算したときの価格表」を指す

---

## 5. `completeness` の判定基準

| 値 | 意味 | 主な発生条件 |
|---|---|---|
| `complete` | 必要なフィールドが揃い、型も正しい | 既定値。`build_envelope`は特に問題が無ければこれを設定する |
| `partial` | 一部のフィールドが欠落・型不正だが、イベント自体は保存に値する | ①`event`コマンドでround/pr_number等の数値フィールドに非数値を渡した（coercion失敗） ②`validate`がpayload形状違反（必須フィールド欠落）を検知してダウングレードした ③`quota.sample`で`resets_at`がstale値だった、または同一window内で`used_percentage`が減少した ④`ingest`で`usage`オブジェクトはあるが一部の数値が欠けている |
| `unknown` | 観測できなかった、または信頼できる値が無い | ①`usage.message`で`usage`オブジェクト自体が無い（transcriptの行が壊れている） ②価格表が無いモデルで費用推定できない場合（`cost_basis == "estimated"`かつ`cost_estimate`が`None`） ③`quota.sample`で`rate_limits`が丸ごと欠落（DeepSeek/`claude-ds`セッションは原理的に常にこれ） |

**「取れないものを`0`や推測値で埋めない」が全体方針**（計画書§7.4「不明なら`role: "unknown"`。捏造しない」
の一般化）。`completeness`はこの方針が実際にどこで発動したかを追跡可能にするためのフィールド。

---

## 6. `schema_version` の変更ルール

現在 `1`。以下の指針で判断する:

- **フィールドの追加**（新しい`event_type`の追加を含む）→ **互換**。`schema_version`は変更しない。
  古い`ocw-meter`バイナリは未知のフィールド/型を「forward-compatible」として保持する（§1・§2参照）ため、
  新しいイベントを古いコードで読んでも壊れない
- **既存フィールドの意味変更・削除・型変更**（例: `input_tokens`の単位を変える、`role`のenumから
  値を削る）→ **非互換**。`schema_version`をインクリメントし、`ocw-meter`側は
  `schema_version`ごとに読み取りロジックを分岐させる必要がある
- **`schema_version`が上がった場合、過去の`v1`イベントは再解釈・再計算されない**
  （§4の価格表と同じ「過去は触らない」原則）。`report`/`ingest`は複数の`schema_version`が
  混在するストアを読めるように書くこと（未対応バージョンは`quarantine`せず、
  少なくとも件数として認識できるようにする）
- 現時点（v1）でこのルールが実際に発動した例は無い。将来v2を検討する際は、この節を更新し、
  移行時に何が壊れ得たか・どう吸収したかを追記すること

---

## 7. 実イベント例（型ごとに1件）

以下はすべて`ocw-meter`の実バイナリに対して手動で`event`コマンドを実行し、実際に保存された行から
取得したもの（秘密情報は含まれない。`worktree`/`repo`は実開発環境のパスがそのまま入っているが、
公開リポジトリのローカルパスであり機密ではない）。

### `run.start`

```json
{"schema_version": 1, "event_type": "run.start", "idempotency_key": "r1", "ts": "2026-08-01T09:00:00.000Z",
 "source": "unknown", "completeness": "complete", "run_id": "run1", "role": "implementer",
 "repo": "manemone/dotfiles", "branch": "ai/ph-05-reports-baseline", "base_ref": "master", "command": "claude"}
```

### `phase.start` / `phase.end`

```json
{"schema_version": 1, "event_type": "phase.start", "idempotency_key": "p1s", "ts": "2026-08-01T09:05:00.000Z",
 "run_id": "run1", "phase": "pr_create", "round": 1, "role": "implementer", "pr_number": 42}
{"schema_version": 1, "event_type": "phase.end", "idempotency_key": "done1", "ts": "2026-08-01T09:35:00.000Z",
 "run_id": "run1", "phase": "done", "round": 1, "outcome": "success", "role": "implementer", "pr_number": 42}
```

### `pr.bind`

```json
{"schema_version": 1, "event_type": "pr.bind", "idempotency_key": "bind:run1:42", "ts": "2026-08-01T21:46:47.657Z",
 "run_id": "run1", "pr_number": 42, "pr_url": "https://github.com/x/y/pull/42"}
```

### `review.round`

```json
{"schema_version": 1, "event_type": "review.round", "idempotency_key": "rv1", "ts": "2026-08-01T09:30:00.000Z",
 "run_id": "run1", "round": 1, "verdict": "approved", "findings_count": 0, "role": "reviewer", "pr_number": 42}
```

### `human.intervention`

```json
{"schema_version": 1, "event_type": "human.intervention", "idempotency_key": "hi1", "ts": "2026-08-01T09:20:30.000Z",
 "run_id": "run1", "reason": "review-blocked-condition", "role": "implementer", "pr_number": 42}
```

### `usage.message`

```json
{"schema_version": 1, "event_type": "usage.message", "idempotency_key": "u1", "ts": "2026-08-01T09:06:00.000Z",
 "source": "transcript", "parser_version": 1, "completeness": "complete", "run_id": "run1",
 "role": "implementer", "provider": "deepseek", "model": "deepseek-v4-pro", "phase": null, "round": null,
 "pr_number": 42, "message_id": "m1", "input_tokens": 1000, "cache_read_input_tokens": 500,
 "cache_creation_input_tokens": 0, "output_tokens": 200, "reasoning_tokens": null,
 "cost_estimate_usd": 0.01, "price_table_version": "deepseek-2026-08-01",
 "price_effective_date": "2026-08-01", "cost_basis": "estimated", "currency": "USD"}
```

### `quota.sample`

```json
{"schema_version": 1, "event_type": "quota.sample", "idempotency_key": "q1", "ts": "2026-08-01T09:12:00.000Z",
 "plan_source": "statusline", "window_id": "winA", "five_hour_used_pct": 20, "pr_number": 42, "role": "implementer"}
```

### `meter.error`

```json
{"schema_version": 1, "event_type": "meter.error", "idempotency_key": "meter-error:ingest:2026-08-01",
 "ts": "2026-08-01T09:40:00.000Z", "stage": "ingest", "message": "lock timeout"}
```
（`state/meter-errors.jsonl`に保存される。`events/`配下には現れない）

### `block.start` / `block.end`

**実例なし。** 計画書とスキーマ検証コード（`EVENT_PAYLOAD_REQUIRED`/`EVENT_ENUM_FIELDS`）は
存在するが、これを発火する呼び出しがリポジトリ内に一つも無いため、実際に保存された行が存在しない。
発火した場合の想定payload形は次の通り（未実測）:

```json
{"event_type": "block.start", "cause": "rate_limit"}
{"event_type": "block.end", "cause": "rate_limit", "wait_ms": 123456}
```

---

## 8. 関連文書

- 設計の経緯・意思決定の背景: `docs/planning/DOC-003_ai-llm-cost-observability_計画.md`
- feasibility probeの実測結果: `docs/adr/ADR-001_llm-cost-observability-collection-method.md`
- 運用手順: `docs/reference/DOC-004_LLM費用観測ベースライン計測手順.md`
- CLIの使い方全般: `bin/README.md` §3.3
