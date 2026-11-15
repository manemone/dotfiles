# ADR: ocw-meter は Codex の rollout を ingest で取り込み、利用枠は Claude と分けて扱う

## ステータス

決定（2026-11-16）。

## 1. 背景

`ocw-meter` は Claude Code の会話記録と statusLine だけを取り込んでいて、Codex CLI の使用量は記録も表示もされなかった。
Codex は ChatGPT のアカウントでログインした**定額のサブスクリプションの枠**で使っているため、API 課金の定価換算ではなく
利用枠の消費（5時間・週）で見るのが実態に合う。

## 2. 決定

### 2.1 rollout の形式と読む範囲

- 置き場は `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`（`OCW_METER_CODEX_SESSIONS_DIR` →
  `$CODEX_HOME/sessions` → `$HOME/.codex/sessions` の順）。1行1イベントの JSONL
- 取り込みは既存の `ocw-meter ingest` の中で行う（別のサブコマンドは作らない）。`report` / `dash` の自動 ingest と
  `snapshot-quota` のバックグラウンド ingest にもそのまま乗る。置き場が無ければ何もしない（出力も変えない）
- 読むのは `session_meta`（スレッドID・`cwd`・`cli_version`・`model_provider`・`source`）、`turn_context`
  （`model`・`effort`・`cwd`）、`token_usage_record`、`event_msg` の `token_count`（`info`・`rate_limits`）と各行の
  `timestamp` / `ordinal` だけ。会話本文（`response_item`）、`base_instructions`、アカウントの ID 類は読まない
- 使用量は Codex のバージョンで2つの形がある。0.155 以降は `token_usage_record`（1応答1行）、それより前は
  `token_count` の `last_token_usage` だけ。`cli_version` が 0.155 以上、または `token_usage_record` を1行でも
  見たファイルは前者で数え、`token_count` の使用量は数えない（同じ応答の二重計上を避ける）

### 2.2 定額の枠として扱い、OpenAI の価格表は作らない

`cost_basis: "subscription"`・`cost_estimate_usd: null`（Claude と同じ）。OpenAI の価格表と定価換算は作らない。
`provider` は `session_meta.model_provider`（実測は全件 `openai`）、`source` は `codex-rollout`。

### 2.3 トークンの写し方

OpenAI の `input_tokens` は `cached_input_tokens` を**含み**、`output_tokens` は推論分を含む。Anthropic の入力は
キャッシュ読み込みを含まない。既存の4区分を Claude と同じ意味にするため次のように写す。

| `usage.message` | Codex |
|---|---|
| `input_tokens` | `input_tokens` − `cached_input_tokens` |
| `cache_read_input_tokens` | `cached_input_tokens` |
| `cache_creation_input_tokens` | `cache_write_input_tokens`（無ければ 0） |
| `output_tokens` | `output_tokens`（推論分を含んだまま） |
| `reasoning_tokens` | `reasoning_output_tokens`（内訳。合計に足さない） |

guardian などのサブエージェント（`source` が `subagent`）の応答も利用枠を消費するので記録し、既存の `is_sidechain` /
`agent_id` に写す。`run_id` / `repo` は Claude と同じ `cwd` からの解決をそのまま使う（Codex 専用の解決は作らない）。

### 2.4 fork・resume で親スレッドの使用量を二重に数えない

実測では、fork したスレッド（guardian のサブエージェントなど）の rollout は、先頭の `token_count` に**親スレッドの累積**を
持って出てくる。1つの rollout に `session_meta` が複数入ることもあるが、これは同じスレッドの再開で、使用量は重ならない。

- 新形式は `response_id` で重複を除く（実測で重複なし）。fork が引き継ぐのは累積だけで、`token_usage_record` は
  そのスレッド自身の応答の分だけ
- 旧形式は、ファイルごとに前の累積を覚え、**累積か直近の応答のどちらかが前の行から変わった行**を1応答として数える（累積が更新されず直近だけ変わる行も別の応答）。ファイルの先頭で
  累積が直近の応答（`last_token_usage`）より大きいときは親から引き継いだ値なので数えない。累積が巻き戻った
  （圧縮などで 0 から数え直した）行は累積と直近の応答が一致するので数える。累積も直近も同じ行は再送なので数えない。
  重複排除のキーは `<スレッドID>:<累積>:<直近の応答の total_tokens>`
- ファイルごとの状態（累積・モデル・スレッドID など）は取り込みのカーソルに持たせ、増分の読み取りでも続きから数える。
  ファイルが差し替わった・縮んだときは状態も捨てて先頭から読み直す（キーが決定論的なので同じ結果に収束する）

### 2.5 `quota.sample` の写し方と間引き

`token_count` の `rate_limits`（`limit_id` が `codex` か無いもの）から作る。`window_minutes` が 300 の枠を
`five_hour_*`、10080 の枠を `seven_day_*` に写す（`primary` / `secondary` の位置では見分けない。無料プランでは
`primary` が週の枠になるため）。それ以外の長さの枠は捨てる。`provider: openai`・`source` / `plan_source`:
`codex-rollout`。

`rate_limits` は毎ターン出るので、**ファイルごとに前に書いた値（5時間・週の使用率とリセット時刻）から変わった行だけ**を
書く。キーは `<スレッドID>:<ordinal>`（`ordinal` が無い旧形式の rollout は `<timestamp>`）で、何度 ingest しても件数は増えない。

### 2.6 Claude の利用枠の集計は Codex の `quota.sample` を見ない

`quota_periods()`（`--quota-progress` / `dash` の週のグラフ）・`--window`・`--month` の利用枠・`--pr` の 5h/7d の最大・
5時間枠の完了判定・session_id による run_id の補完・capacity の件数は、`provider` が `openai`
または `source` が `codex-rollout` の行を除く形（`is_claude_quota_sample()`）にした。

「Claude のサンプルだけを取る」（`provider == anthropic`）にしなかったのは、`provider` が null の古い `quota.sample` や
DeepSeek のサンプルを今まで数えていた集計の結果を変えないため。実際のストアには null は無かったが、書式上ありうるので
安全側（今の結果を変えない側）に倒した。定価換算（`_quota_session_contributions`）は既に `anthropic` に絞ってあり、
Codex の行は件数の注記にも出さない。

## 3. 却下した案

- OpenAI の価格表を作って定価換算する: 定額の枠で使っており、数字の意味が Claude と揃わない
- 別のサブコマンド（`ingest-codex`）を作る: 自動 ingest の経路を二重に持つことになる
- `token_count` の累積の差分だけで数える: fork の先頭の累積（親の分）が差分に混ざる

## 4. 影響

- `report --model` / `--daily` / `--heatmap` に Codex のモデルが `openai/<model>` として現れる
- Codex の利用枠の表示は §5 のとおり

## 5. Codex の利用枠の表示（`dash`・`report --quota-progress --provider openai`）

- `report --quota-progress --provider <anthropic|openai>`（既定 `anthropic` = 今までと同じ出力）。描画は既存と同じコードで、
  `quota_periods()` が provider で `quota.sample` を選ぶだけ。`openai` は Codex 由来の行だけを読み、Claude の値は混ざらない。
  Codex には 1% あたりのトークン数の見積もりが無いので、残りの % のトークン換算の欄は出さず理由を 1 行出す。`--json` / `--plain` に `provider` を出す
- `dash` は Codex の `quota.sample` が 1 件でもあるときだけ、見出しに Codex のタイルの段（5時間・週の使用率、週のリセットまで。
  5時間の枠はリセット時刻を過ぎた記録なら —）と、Claude のグラフの下に「Codex の週の上限の推移」を足す。1 件も無ければ画面は変わらない
- 端末の高さが足りないときは、グラフの高さを詰める（Claude と Codex は同じ行数）→ ヒートマップ → 日ごとの縦棒 → Codex のグラフの順に省く。
  Codex のタイルは残す（数字は小さく、グラフより先に失う理由が無い）。Claude の週のグラフは今までどおり省かない
