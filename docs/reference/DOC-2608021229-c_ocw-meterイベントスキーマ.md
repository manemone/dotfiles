# DOC-2608021229-c: ocw-meter イベントスキーマ

`ocw-meter`（`bin/ocw-meter`）が `~/.local/state/ocw-meter/events/YYYY-MM-DD.jsonl` に書く
全イベントの恒久リファレンス。**このファイルがスキーマの一次情報源。**
`docs/planning/DOC-2608021229-a_ai-llm-cost-observability_計画.md`（計画書）第8章にも同内容の初期設計があるが、
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

> **⚠️ 孫5で実データ検証して判明した重大な制約（実測。計画書
> [DOC-2608081456](../planning/DOC-2608081456_ocw-meter-accuracy_計画.md)【3】）**: このマシンの実ストア
> （`~/.local/state/ocw-meter/events/`、57,164件の`usage.message`）を集計すると、直接解決だけで
> `run_id`が設定されている`usage.message`は**3,043件（5.3%）**、`role`が`unknown`のままのものは
> **51,959件（90.9%）**だった。原因は`ingest`の直接解決ロジック
> （`run_id`は`resolve_run_id_via_ocw_run_id_file`が「そのメッセージの`cwd`（＝worktreeパス）の
> `<git-dir>/ocw-run-id`ファイルを**ingest実行時点**で読む」方式、`role`はHerdrの`pane list`を
> **ingest実行時点**の生きたペイン状態から読む方式）であること: `ocw rm`はworktreeごと
> `ocw-run-id`ファイルを削除し、ペインを閉じればHerdrの`pane list`からも消えるため、
> **PRマージ後にworktreeを消してから（あるいはペインを閉じてから）`ingest`を実行すると、
> そのメッセージのrun_id/roleは直接解決の対象では永久に`null`/`"unknown"`のまま保存される**（§4の
> 「過去は再計算しない」不変条件により、後から`ingest`し直しても直らない）。
>
> **孫5でこれを緩和する`session_id` joinを追加した**（下記「attributionの解決順」参照）。
> `quota.sample`がsession_idを100%持つのに対し、`run_id`は78%・`role`は78%（unknown 22%）しか
> 持たないため、直接解決に失敗した`usage.message`を`quota.sample`とのsession_id joinで補う。
> `quota.sample`の記録が始まった2026-08-01以降の実測では、`run_id` 17.2% → **61.6%**、
> `role` 27.2% → **72.1%**まで上がった。**ただしこのjoinは`quota.sample`の記録開始より前へは
> 遡れない**ため、7月の29,676件（DeepSeek時代の`deepseek-v4-pro`分）の`run_id`/`role`は
> 復元手段が無いままである。`report`の`--reconcile`を除く全ビューのフッターに出る
> `attribution (run_id):`/`attribution (role):`行が、実行のたびの実測内訳
> （`direct`/`via session_id`/`unresolved`）を示す（`--reconcile`は`session_id` joinを経由しない
> ためattributionを計算せず、この行自体が出ない）。
> `report --phase`を意味のある形で使うには、引き続き**PRの作業中〜マージ直後、worktreeを
> `ocw rm`する前に`ocw-meter ingest`を実行する運用**が望ましい（`docs/reference/DOC-2608021229-b_...`
> §2で手順化。session_id joinは直接解決の救済策であり、完全な代替ではない）。

### 2.4 `usage.message` のペイロードフィールド（共通エンベロープに加えて）

`~/.local/state/ocw-meter/events/*.jsonl`の実データ（当初44,425件、2026-08-01時点。本傘
[DOC-2608081456](../planning/DOC-2608081456_ocw-meter-accuracy_計画.md)の調査時点では57,164件）で
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
| `time_of_day_basis` | string \| null | `not_applicable` / `in_window` / `base_rate` / `unknown_timestamp`、または`null`（Anthropicモデル`cost_basis: "subscription"`のとき、または適用可能な価格表が1枚も無いとき。孫3。§4.2「時間帯課金」参照） |
| `currency` | string \| null | `USD`。`cost_basis == "subscription"`のときは`null` |
| `run_id_source` | string \| null | `run_id`をどの経路で解決したか。`"direct"` / `"session_id"` / `null`（未解決、またはこのフィールドが無かった旧バージョンでのingest。孫5。§4.5「attributionの解決順」参照） |
| `role_source` | string \| null | `role`をどの経路で解決したか。値の意味は`run_id_source`と同じ（孫5） |

### 2.5 `quota.sample` のペイロードフィールド（共通エンベロープに加えて）

| フィールド | 型 | 由来 |
|---|---|---|
| `five_hour_used_pct` / `five_hour_resets_at` | number \| null | `rate_limits.five_hour`。`claude-ds`セッションは常に`null`一式 |
| `seven_day_used_pct` / `seven_day_resets_at` | number \| null | `rate_limits.seven_day` |
| `window_id` | string \| null | `five_hour_resets_at`の値そのもの。**未来時刻のときのみ**採用（stale値は`null`にする — 計画書§8.5） |
| `context_used_pct` | number \| null | `context_window.used_percentage`。`null`のときは`total_input_tokens / context_window_size`からのフォールバック計算値が入る場合がある（表示文字列側は使わない。`bin/README.md`参照） |
| `session_cost_usd` | number \| null | statusLineの`cost.total_cost_usd`（Claude Code自己申告のセッション累積コスト）。`usage.message`の`cost_estimate_usd`とは別カラムで、合算しない。`report`はこれを`list_price_equiv_usd`として集計・表示する（孫4。§4.4「`list_price_equiv_usd`の集計定義」参照） |
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

### 4.1 価格表（`bin/prices/*.json`）

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

### 4.2 時間帯（peak/off-peak）課金

孫3、計画書 [DOC-2608081456](../planning/DOC-2608081456_ocw-meter-accuracy_計画.md)【5】。

価格表は`models`（基本単価）に加えて、任意で`time_of_day_pricing`ブロックを持てる:

```jsonc
"time_of_day_pricing": {
  "tz_offset": "+08:00",
  "tz_label": "Beijing time (China Standard Time, UTC+8, no DST)",
  "boundary": "start_inclusive_end_exclusive",
  "windows": [
    {"start": "09:00", "end": "12:00", "models": {"<model名>": {"cache_hit_in": ..., "cache_miss_in": ..., "out": ...}}},
    {"start": "14:00", "end": "18:00", "models": {"<model名>": {...}}}
  ]
}
```

設計上の決まりごと（詳しい書き方・実例は`bin/prices/README.md`を参照。ここではスキーマの意味だけ
記す）:

- **`tz_offset`は固定オフセット文字列（`"+08:00"`形式）のみ。** タイムゾーン名（`Asia/Shanghai`等）
  は使えない — `zoneinfo`はPython 3.9+かつtzdataが必要で、実行環境に無い場合があるため。オフセットは
  価格表側が持ち、コードにハードコードしない
- **境界は開始時刻を含み、終了時刻を含まない**（`start <= t < end`）。この規則はコード側に固定されて
  おり、価格表の`boundary`フィールドはこの規則と一致するかを検査するアサーション専用（別の境界規則
  を選べるオプションではない）
- **日を跨ぐ窓は表現できない。** `start >= end`（例`"22:00"`-`"02:00"`）な窓は単に一致しない
- **窓ごとに単価を直接書く（倍率ではない）。** `models`ブロックと同じ形で窓ごとの単価をそのまま書く
- **`in_window`/`base_rate`という中立な名前を使い、「どちらが高い時間帯か」は表現しない。**
  窓が「割高な時間帯」を表すか「割引の時間帯」を表すかはプロバイダごとに違い、`usage.message`に
  焼き込まれる`time_of_day_basis`は「過去は再計算しない」不変条件のため後から意味を直せないため
- `time_of_day_pricing`が無い価格表（この機能より前から存在するすべての価格表を含む）は、
  常に基本`models`の単価がそのまま全時間帯に適用される（後方互換）

`usage.message`の`time_of_day_basis`フィールド（§2.4）は、そのメッセージに実際にどの単価が
適用されたかを示す:

| 値 | 意味 |
|---|---|
| `not_applicable` | 価格表に`time_of_day_pricing`が無い、またはこのモデルがどの窓にも登場しない（時間帯課金の対象外） |
| `in_window` | メッセージのタイムスタンプがいずれかの窓に一致し、その窓の単価を適用した |
| `base_rate` | このモデルは時間帯課金の対象だが、タイムスタンプがどの窓にも一致しなかったため基本単価を適用した |
| `unknown_timestamp` | このモデルは時間帯課金の対象だが、メッセージのタイムスタンプが取得できなかったため基本単価にフォールバックした（**時間帯を推測しない**） |

`time_of_day_pricing`キー自体はあるが形が壊れている（`tz_offset`が不正、`windows`が配列でない、
`boundary`が上記の規則と食い違う等）価格表は、「`time_of_day_pricing`を最初から持たない」場合と
同じ扱い（基本単価を適用、クラッシュしない）になるが、`ingest`は`state/meter-errors.jsonl`に
`price_table_time_of_day_pricing_unusable`という診断を記録し、意図した時間帯課金が黙って無視
されている状態を検知できるようにしている。

**このスキーマ拡張は既存の価格表と互換であり、`bin/prices/deepseek-2026-08-01.json`は現時点で
`time_of_day_pricing`を使っていない**（DeepSeekの時間帯課金は本傘の調査時点で発効日未定のため）。

### 4.3 価格表フォールバックの検出（孫3、罠5対策）

`select_price_table()`は、対象日以前に有効な価格表が1枚も無いとき、クラッシュせず最も古いテーブル
（`tables[0]`）にフォールバックする。このとき保存される`price_effective_date`は、実際のメッセージ
日付より**後**になる — この状態（`price_effective_date`がメッセージ自身の日付より後）を、
`report`は（イベントを書き換えずに）読み取り時の突き合わせで検出する:

- `report`の`--reconcile`を除くフッター`price_table:`行に、フォールバックが起きた件数を表示する
  （`--reconcile`は`usage_cost_footer()`を経由せず自前で`price_table`文字列を組み立てており、
  フォールバック件数に相当する情報を持たない）
- `report --month`の`price_tables_applied[]`の各エントリに`is_fallback`（そのバージョンで
  フォールバックが1件でも起きたか）と`fallback_event_count`（そのバージョンの中で実際に
  フォールバックした件数。1つの価格表が月の前半はフォールバック・後半は正しく適用、という
  混在も表現できる）を持つ

### 4.4 `list_price_equiv_usd` の集計定義

孫4、計画書 [DOC-2608081456](../planning/DOC-2608081456_ocw-meter-accuracy_計画.md)【2】。

`quota.sample`の`session_cost_usd`（statusLineの`cost.total_cost_usd`。Claude Code自身の
セッション累積コスト自己申告）を集計し、`report --month`のcapacity cost節・`report --pr`・
`report --window`に`list_price_equiv_usd`として出す。`usage.message`の`cost_estimate_usd`
（ocw-meter自身の価格表推定値。cash cost）とは**出所も信頼レベルも異なる別カラム**であり、
絶対に合算しない。

集計規則:

1. **`provider == "anthropic"`のイベントのみを対象にする。** `deepseek`（`claude-ds`経由の
   セッション）は除外する。Claude Codeが DeepSeekのモデル名にどの単価を当てて
   `cost.total_cost_usd`を計算しているか不明であり、含めると`usage.message`側の
   DeepSeek価格表推定（cash cost）と二重計上になる。`provider`が`deepseek`以外
   （`provider: null`を含む）のサンプルはすべて`list_price_equiv_excluded_other_provider_count`
   に計上される。`deepseek`専用カウンタ（`list_price_equiv_excluded_deepseek_count`）とは
   別だが、`deepseek`以外の非anthropicプロバイダ（`provider: null`を含む）は互いに区別されず
   同じ`other_provider`カウンタへまとめて計上される
2. **`session_id`ごとに時系列でソートし、隣り合うサンプル間の正の差分だけを合計する
   （`max()`は使わない）。ただし、そのセッションでストア全体を通じて最初に観測されたサンプル
   （直前サンプルが存在しない、時系列で1件だけ）だけは例外で、差分ではなく値そのものを計上する**
   （＝そのサンプルより前の消費も丸ごと含める）。
   `session_cost_usd`はセッション累積のはずだが、実測で214セッション中26セッション（12.1%）が
   非単調（値が減少する箇所がある）だった。`/clear`やコンパクションでのリセットが原因と推定される。
   単純な`max()`ではリセット前の消費分を取りこぼすため、隣り合うサンプル間の差分のうち正のものだけ
   を積算する（負の差分＝リセットは**0として扱う**。**リセット直後のサンプル自身の寄与は0であり、
   「最初のサンプル」の特別扱いはストア全体で最初の1件にしか適用されない** —
   リセットのたびに値そのものが計上されるわけではない）。この寄与（`event_id`ごとの寄与額）は
   **必ずストア全体の`quota.sample`から計算し、窓/PR/月でスコープを絞った部分集合から
   再計算してはいけない。** スコープを絞って計算すると、窓をまたぐセッションの累計が
   窓2の「最初のサンプル」として丸ごと再計上され、実ストアで`report --window`の行合計が
   48.7%（57/207 anthropicセッション、27.5%が2窓以上にまたがる）過大になることを実測で確認した
3. `session_id`が無い、または`session_cost_usd`が数値でないサンプルは除外し、
   `list_price_equiv_excluded_no_session_id_count` / `list_price_equiv_excluded_null_cost_count`
   としてそれぞれ数える（黙って捨てない）
4. 対象サンプルが1件も無いスコープ（例: `quota.sample`が始まる2026-08-01より前の月）では
   `list_price_equiv_usd: null`（`$0.00`ではない）、`list_price_equiv_is_lower_bound: null`
   になる — データが無いことと、ゼロだったことを区別する

**常に下限値である。** 最後のstatusLine描画以降の消費は含まれないため、`list_price_equiv_usd`が
`null`でない限り`list_price_equiv_is_lower_bound: true`が付く。請求書ではなく、cash costと
合算してはならない（線引きの記録は
`docs/adr/DOC-2608021229_llm-cost-observability-collection-method.md` §10参照）。

### 4.5 attribution の解決順

孫5、計画書 [DOC-2608081456](../planning/DOC-2608081456_ocw-meter-accuracy_計画.md)【3】。

`usage.message`の`run_id`/`role`は、次の優先順で解決される（`run_id_source`/`role_source`が
実際にどの経路で決まったかを保持する。§2.4参照）:

- `run_id`: **①**`ocw-run-id`ファイル（そのメッセージの`cwd`配下、ingest実行時点で直接読む）
  → **②**`quota.sample`との`session_id` join（同じ`session_id`を持つ`quota.sample`サンプルの
  うち、そのメッセージのタイムスタンプに時刻が最も近いものの`run_id`を採用） → **③**`null`
- `role`: **①**Herdr live（`herdr pane list`をingest実行時点で読む）→ **②**同上の`session_id`
  join → **③**`"unknown"`

②の`session_id` joinは2箇所で行われる: `ingest`実行時に新規イベントへ書き込む「ingest側
フォールバック」と、既に保存済みのイベント（`run_id`/`role`が未解決のまま保存されているもの）を
`report`の読み取り時に補完する「report側join」。**どちらも保存されたイベントファイルそのものは
書き換えない**（「過去は再計算しない」不変条件の維持）。`report`のフッターの`attribution`行は
両方を区別せず`via session_id`として合算する。

**⚠️ 重要な設計上の判断**: `quota.sample`由来（②）の`run_id`には、`ocw-run-id`ファイル経由
（①）にのみ適用される「その`run_id`の`run.start`より前のメッセージなら捨てる」という逆転
チェックを**適用しない**。このチェックは「worktreeパスは再利用される」ことを前提にしたstale
path対策であり、`session_id`はworktreeパスと違って再利用されないため、②に適用すると正しい
帰属まで`null`化してしまう。解決経路ごとにこのチェックの適用を分けている（テストで固定済み）。

1つの`session_id`に複数の`run_id`/`role`が紐づく場合（同じセッションでworktreeを移った等）は、
「一意でなければ解決しない」ではなく、**そのメッセージのタイムスタンプに時刻が最も近いサンプルの
値を採用する**方針とした（前後どちらのサンプルが「そのときの状態」かを決める積極的な根拠が無い
ため、単に時刻近傍則で決定的に1つへ絞る。同点は前方のサンプルを優先する）。

**この解決順・joinはどちらも`ocw rm`（worktree削除）に一切影響されない**（`quota.sample`は
消えないイベントだが、`ocw-run-id`ファイルはworktreeと一緒に消える）。ただし限界は残る:
`quota.sample`の記録が始まる前（各マシンへのデプロイ日より前）の期間は、session_id joinによる
復元ができない。以降の期間でも100%には到達しない — `claude-ds`セッションやstatusLineが一度も
走らなかったセッションは`run_id`/`role`とも復元不能。`role`の`unknown`の一部はHerdr外で起動
したClaudeであり原理的に取得不能（推測で埋めない方針を維持）。

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
- **本傘（計画書
  [DOC-2608081456](../planning/DOC-2608081456_ocw-meter-accuracy_計画.md)）は`schema_version`を
  変更していない。** 孫3が`time_of_day_basis`、孫5が`run_id_source`/`role_source`をそれぞれ
  `usage.message`へ新規追加したが、いずれも既存フィールドの意味変更・削除・型変更を伴わない
  「フィールドの追加」（上記の互換ケース）にあたるため、`v1`のまま据え置いた。`list_price_equiv_usd`
  はイベントのフィールドではなく`report`が集計時に計算する派生値のため、そもそもスキーマ変更の
  対象外である

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
 "run_id_source": "direct", "role": "implementer", "role_source": "direct", "provider": "deepseek",
 "model": "deepseek-v4-pro", "phase": null, "round": null,
 "pr_number": 42, "message_id": "m1", "input_tokens": 1000, "cache_read_input_tokens": 500,
 "cache_creation_input_tokens": 0, "output_tokens": 200, "reasoning_tokens": null,
 "cost_estimate_usd": 0.01, "price_table_version": "deepseek-2026-08-01",
 "price_effective_date": "2026-08-01", "cost_basis": "estimated", "time_of_day_basis": "not_applicable",
 "currency": "USD"}
```

`run_id_source`/`role_source`（孫5追加）は、この例のように`run_id`/`role`が`ocw-run-id`ファイル /
Herdr liveから直接解決できた場合は`"direct"`、`quota.sample`とのsession_id joinで解決した場合は
`"session_id"`になる（§4.5参照）。`time_of_day_basis`（孫3追加）はこの例が使う価格表
（`bin/prices/deepseek-2026-08-01.json`）が`time_of_day_pricing`を持たないため`"not_applicable"`。
サンドボックス実行で実際に確認した`run_id_source: "session_id"`の例:

```json
{"run_id": "run-sandbox-1", "run_id_source": "session_id", "role": "implementer",
 "role_source": "session_id", "provider": "anthropic", "model": "claude-opus-5",
 "cost_basis": "subscription", "cost_estimate_usd": null, "time_of_day_basis": null, "...": "..."}
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

- 設計の経緯・意思決定の背景: `docs/planning/DOC-2608021229-a_ai-llm-cost-observability_計画.md`
- feasibility probeの実測結果: `docs/adr/DOC-2608021229_llm-cost-observability-collection-method.md`
- 運用手順: `docs/reference/DOC-2608021229-b_LLM費用観測ベースライン計測手順.md`
- CLIの使い方全般: `bin/README.md` §3.3
