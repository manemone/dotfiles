# 計画書: ocw-meter で Codex の使用量も記録し、表示する

傘ブランチ: `codex-meter`
ターゲット: `master`

## 概要

`bin/ocw-meter` は今、Claude Code の会話記録（`~/.claude/projects/`）と Claude Code の statusLine だけを
取り込んでいて、Codex CLI の使用量は記録も表示もされない。この傘で次の2つを作る。

1. **Codex の会話記録（`~/.codex/sessions/` の rollout）を `ingest` で取り込む（孫1）。** トークン使用量を
   `usage.message` に、rollout に入っている Codex の利用枠（5時間・週）の使用率を `quota.sample` に載せる。
   あわせて、既存の Claude の利用枠の表示・集計が Codex の `quota.sample` で汚れないようにする
2. **`dash` と `report` で Codex の利用枠を見られるようにする（孫2）。** Claude の利用枠のグラフとは混ぜず、
   Codex の週の利用枠を別に出す

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `cm-01-codex-ingest` | Codex の rollout を `ingest` で取り込み、`usage.message`（provider `openai`）と `quota.sample`（Codex の5時間・週の使用率）を書く。既存の Claude の利用枠の集計・表示から Codex の `quota.sample` を外す | ⬜ 待機中 |
| 2 | `cm-02-codex-dash` | `dash` と `report --quota-progress` で Codex の週の利用枠を Claude とは別に表示する（Codex の記録が無いマシンでは今と同じ見た目） | ⬜ 待機中 |

依存:

- 孫2 は孫1 のマージ後に spawn する（孫2 は孫1 が書くイベントを読む。どちらも `bin/ocw-meter` と
  `bin/tests/test_ocw_meter.py` を触るので並べない）
- 縛り合う値（provider 名・`source` 名・フィールド名・環境変数名・`--provider` の値）は「設計0」で固定してある。
  孫1・孫2 はこれを変えない。変える必要が出たら司令官に知らせる

## ワークスペースラベル

接頭辞は `ocw label-prefix`（dotfiles では `dotfiles`）。

- 傘: `dotfiles :: Codex の使用量記録`
- 孫1: `dotfiles :: Codex の使用量記録 孫1 rollout の取り込み`
- 孫2: `dotfiles :: Codex の使用量記録 孫2 dash と report の表示`

## 背景1: 問題意識（要約。PUBLIC リポのため逐語では書かない）

人間から「ocw-meter で Codex の使用量も記録できるようにしたい。あわせて `dash` などの表示も変える必要が
あるかもしれない」という依頼が1回あった。仕様の詳細は人間から出ていない（相談の会話は振り分けの確認に
同意しただけ）。

## 背景2: 人間が確定させた決定事項（覆さないこと）

- dotfiles リポだけで完結させる。PR は複数で、傘で進める（task-intake の振り分けに人間が同意した）
- 表示側（`dash` など）も、Codex の記録に合わせて必要なら変える

## 背景3: 相談の会話が見た既存の穴（ブリーフより転記。master `d68900d` 時点）

- `bin/ocw-meter` は 9,275 行の単一ファイル（bash の中に Python を埋め込んだもの）
- `ingest` は Claude Code の会話記録だけを読む。ヘルプ（57行目付近）に `~/.claude/projects/*/*.jsonl` と
  サブエージェントの記録を走査するとあり、既定のルートは `$HOME/.claude/projects`（環境変数
  `OCW_METER_CLAUDE_PROJECTS_DIR` で上書き）
- 集計に `provider=anthropic` 前提の箇所がある。例: 2579行目付近の定価換算の説明「provider=anthropic のみに
  絞り…」、2616行目付近の `quota.sample` の絞り込み `e.get("provider") != "anthropic"`
- 価格表 `bin/prices/` には `deepseek-*.json` しか無い
- `report` は provider+model 単位で集計し、`--reconcile` は `--provider-total` を受ける。provider を増やすこと
  自体は想定にありそう

## 背景4: 司令官が確かめたこと（2026-11-16、傘 `codex-meter` = origin/master `710449f` の上、このマシン。読み取りだけ）

ブリーフの「先に潰すべき前提（未確認）」の3点を確かめた。

### 4.1 Codex の会話記録の置き場所と形式

- `~/.codex/sessions/YYYY/MM/DD/rollout-<日時>-<thread id>.jsonl`（このマシンで63ファイル）。1行1イベントの JSONL。
  行の形は `{"timestamp", "ordinal", "type", "payload"}`
- `type` の種類: `session_meta`（`payload.id` がスレッドID、`session_id`、`cwd`、`cli_version`、`model_provider`
  〈全件 `"openai"`〉、`source`〈`"vscode"` / `"cli"` / `"exec"` / `{"subagent": {"other": "guardian"}}`〉）・
  `turn_context`（`payload.model`・`effort`・`turn_id`・`cwd`）・`event_msg`（`payload.type` が `token_count`
  ほか）・`token_usage_record`・`response_item`（会話本文。**読まない**）・`compacted` など
- **使用量は2つの形で入っている。Codex のバージョンで違う:**
  - `token_usage_record`（0.155 以降で確認。1応答1行）: `payload.response_id`・`thread_id`・`turn_id`・`usage`
    （その応答の `input_tokens` / `cached_input_tokens` / `cache_write_input_tokens` / `output_tokens` /
    `reasoning_output_tokens` / `total_tokens`）・`thread_token_usage`（スレッドの累積）
  - `event_msg` の `token_count`（全バージョン）: `payload.info.last_token_usage`（直近の応答）と
    `total_token_usage`（累積）。0.155 より前（0.142〜0.150、このマシンの rollout の大半）はこちらしか無い
- **OpenAI の数え方は Anthropic と違う。** `input_tokens` は `cached_input_tokens` を**含む**
  （`total_tokens = input_tokens + output_tokens` で確認）。`output_tokens` は `reasoning_output_tokens` を
  含む（`last_usage_includes_reasoning: true`）。Anthropic の `input_tokens` はキャッシュ読み込みを含まない
- **1つの rollout に `session_meta` が複数入ることがある**（63ファイル中20。fork・resume・サブエージェント）。
  fork した rollout の先頭の `token_count` は、親スレッドの累積（`total_token_usage`）を持って出てくる
  （観測した例では先頭が累積 50万トークン級）。累積から差分を取るときも `last_token_usage` を使うときも、
  **親の分を二重に数えうる**。`token_usage_record` の `response_id` には重複が無かった（全2,225件）
- モデル名の例: `gpt-5.4`・`gpt-5.6-sol`・`gpt-5.6-luna`・`gpt-5.6-terra`・`gpt-6.1-terra`・`codex-auto-review`
  （最後のものは Codex の自動レビュー〈guardian サブエージェント〉。件数ではこれが最多）
- rollout には `session_meta` にアカウントの ID 類（`creator_user_id` など）が入っている。**取り込まない**

### 4.2 Codex の利用は定額か API 課金か

- このマシンの Codex は ChatGPT のアカウントでログインしている（`~/.codex/auth.json` の `auth_mode` が
  `chatgpt`。キー類は読んでいない）。**定額のサブスクリプションの枠で使っている**
- `token_count` の `payload.rate_limits` に利用枠の使用率が入っている（このマシンの rollout で 3,862 件）:
  `limit_id: "codex"`、`primary`（`used_percent`・`window_minutes: 300`・`resets_at`〈epoch 秒〉）が5時間枠、
  `secondary`（`window_minutes: 10080`）が週の枠、ほかに `plan_type`・`credits`。古いバージョンでは
  `rate_limits` が `null` の行もある
- よって**「費用」は定価換算ではなく、利用枠の消費（quota）で出す**（設計0 の 4）。Claude の
  `cost_basis: "subscription"` と同じ扱い。OpenAI の価格表は作らない

### 4.3 既存のイベントの形に載せられるか

- `usage.message` は provider / model / role / session_id / 4種のトークン / cost を持つ（`bin/ocw-meter` の
  `usage.message` を組み立てる箇所、6760行目付近）。Codex の応答をそのまま載せられる（トークンの写し方は設計0 の 3）
- `quota.sample` は `five_hour_used_pct` / `five_hour_resets_at` / `seven_day_used_pct` / `seven_day_resets_at`
  を持つ（`snapshot-quota`、8535行目付近）。Codex の `primary` / `secondary` をそのまま写せる
- **ただし既存の利用枠の集計は provider で絞っていないものがある。** `quota_periods()`（2984行目付近。
  `report --quota-progress` / `--quota-per-pct` / `dash` の週のグラフの元）は「使用率はアカウント全体の値」として
  全 `quota.sample` を混ぜる。ほかに `report --window`（4431行目付近）・`--month` の利用枠（4672行目付近）・
  `--pr` の 5h/7d の最大（2796行目付近）も provider を見ていない。Codex の `quota.sample` を足すと、
  Claude の週のグラフに Codex の % が混ざる。**孫1 で取り込むのと同じ PR で塞ぐ**（縛り合う値は1本に）

## 関係するリポ

傘のリポのみ（dotfiles。メインワークツリー `/home/manemone/projects/dotfiles/master`、既定ブランチ `master`、
規約は `AGENTS.md`）。

## 決定的な制約（孫は全部守ること）

- dotfiles の `AGENTS.md` の最重要ルール（`master` への反映は人間だけ。孫→傘のマージは司令官がレビュー承認済み
  PR に限って行う。孫は承認されてもマージしない）
- `bin/` を変えたら `python3 -m unittest discover -s bin/tests -v` を通す
- テストは DOC-2610150520-a（テストを足す判断基準）に従い、機械的に増やさない
- **会話の本文を読まない・保存しない。** Codex の rollout から読むのは設計0 の 2 に挙げたフィールドだけ
  （`response_item` などの本文、`session_meta` のアカウント ID 類、`base_instructions` は読まない）。既存の
  Claude 側の `ingest` が `message.content` に触れないのと同じ方針
- `ingest` の既存の性質を壊さない: 冪等（何度走らせても同じ結果）・ファイルごとのカーソルで増分・`--since` は
  読み取り側だけの絞り込み・予期しない失敗は fail-loud（`report` からの自動 ingest は失敗しても `report` を止めない）
- Codex の記録（`~/.codex/sessions/`）が無いマシンでは、`ingest` も `report` も `dash` も今とまったく同じに動く
  （エラーも警告も出さない）
- deploy はしない（配るのは人間）。実 `$HOME` の `~/.local/state/ocw-meter` に書く確認をしない。手での確かめは
  `OCW_METER_HOME` を `mktemp -d` に向けて行う（`OCW_METER_CODEX_SESSIONS_DIR` は実際の `~/.codex/sessions` を
  読み取り専用で指してよい）
- PR・ADR・計画書に、マシン名・アカウント ID・人間の発言の逐語を書かない（PUBLIC リポ）

## スコープ外

- OpenCode の使用量（頼まれていない。先回りして入れない）
- OpenAI の API キー課金での定価換算と、OpenAI の価格表（このマシンは定額の枠で使っている。背景4.2）
- Codex の利用枠の「1% が何トークンか」の推定（`report --quota-per-pct` は Claude のモデル系列〈opus/sonnet/…〉
  だけのまま）
- Codex の使用量を PR・`run_id`・ロールへ結び付けるための、Codex 側の新しい仕組み（フックなど）。既存の
  `cwd` からの解決で取れる分だけ取る（設計0 の 5）
- `report --month` の利用枠のコスト・`report --window`・`--pr` の 5h window 完了の判定を Codex に広げること
  （孫1 で Claude だけに絞るまで。Codex 版は作らない）

## 必須の検証ステップ（dotfiles AGENTS.md「コミット前の必須ステップ」より。省略しない）

- `pre-commit run --files <変更したファイル>`（まとめてなら `pre-commit run --all-files`）
- `python3 -m unittest discover -s bin/tests -v`
- `bin/tests/lint.sh`
- `docs/` に新規ファイルを足すときは `DOC-DOCID_PLACEHOLDER_<名前>.md` で作り、`./tools/doc-id/doc-id assign <path>` で採番、
  `./tools/doc-id/doc-id verify` を通す
- 詳細は AGENTS.md「コミット前の必須ステップ」と DOC-2610150520

## テスト方針（dotfiles AGENTS.md「テスト方針」と DOC-2610150520-a に従う）

テストも保守対象。受け入れ条件の数に比例して増やさず、「このテストが無いとどんな現実的な regression を逃すか」に
答えられるものだけ足す。既存の `bin/tests/test_ocw_meter.py` の ingest・quota・dash のテストの形（合成した
transcript・イベントを一時ディレクトリに置いて関数や CLI を叩く）に合わせ、まず既存テストで足りるかを確かめる。
Codex の rollout の合成データは、背景4.1 の形を最小限に写したものにする（実物の rollout をリポに入れない。
アカウント ID と会話本文が入っているため）。

## 設計0: 全孫に共通の方針（司令官が決めた。縛り合う値はここで1つに固定する）

1. **入口**: Codex の取り込みは既存の `ocw-meter ingest` の中で行う（別のサブコマンドを作らない）。`report` /
   `dash` の自動 ingest・`snapshot-quota` のバックグラウンド ingest で、Claude と一緒に取り込まれる。
   読む場所は環境変数 `OCW_METER_CODEX_SESSIONS_DIR`、未設定なら `$CODEX_HOME/sessions`、`CODEX_HOME` も
   未設定なら `$HOME/.codex/sessions`。存在しなければ何もしない（設計の制約のとおりエラーにしない）
2. **読むフィールド**: `session_meta` の `id` / `session_id` / `cwd` / `cli_version` / `model_provider` / `source` /
   `timestamp`、`turn_context` の `model` / `effort` / `turn_id` / `cwd`、`token_usage_record` の `response_id` /
   `thread_id` / `turn_id` / `usage`、`event_msg` の `token_count` の `info.last_token_usage` /
   `info.total_token_usage` / `rate_limits`、各行の `timestamp` / `ordinal`。これ以外は読まない
3. **`usage.message` への写し方**（1応答 = 1イベント）:
   - `provider`: `session_meta.model_provider`（このマシンでは全件 `"openai"`）。**provider の値は `"openai"`**
   - `model`: その応答の直前の `turn_context.model`
   - `source`: **`"codex-rollout"`**（既存の Claude は `"transcript"`）
   - `input_tokens` = OpenAI の `input_tokens` − `cached_input_tokens`、`cache_read_input_tokens` =
     `cached_input_tokens`、`cache_creation_input_tokens` = `cache_write_input_tokens`、`output_tokens` =
     `output_tokens`（推論分を含んだまま）、`reasoning_tokens` = `reasoning_output_tokens`（内訳。合計に足さない）。
     こうすると既存の「入力・キャッシュ読み・キャッシュ書き・出力」の4区分が Claude と同じ意味になる
   - `cost_basis`: **`"subscription"`**、`cost_estimate_usd`: null（Claude と同じ。背景4.2）
   - 重複除去のキー（既存の `message_id`）: `token_usage_record` があれば `response_id`。無い古い rollout では
     孫1 が決める（スレッドIDと `ordinal` から作るなど）。**fork・resume の rollout で親スレッドの使用量を
     二重に数えないこと**（背景4.1）。どう見分けるかは孫1 が実物で確かめて決め、ADR に書く
   - guardian サブエージェント（`source` が `subagent`）の応答も記録する（利用枠を消費しているため）。
     既存の `is_sidechain` / `agent_id` に写す
4. **`quota.sample` への写し方**: `token_count` の `rate_limits` が null でない行から作る。
   - `provider`: **`"openai"`**、`source`: **`"codex-rollout"`**、`plan_source`: `"codex-rollout"`
   - `window_minutes` が 300 の枠 → `five_hour_used_pct` / `five_hour_resets_at`、10080 の枠 →
     `seven_day_used_pct` / `seven_day_resets_at`（`primary` / `secondary` の位置ではなく `window_minutes` で
     見分ける。それ以外の長さの枠は捨てる）。`resets_at` は既存と同じく epoch 秒の整数
   - 間引き方（毎ターン出ているので、変化した行だけにするなど）は孫1 が決めて ADR に書く。ただし何度
     ingest しても件数が増えない（冪等）こと
5. **run_id・role・repo**: 既存の Claude 側の解決（`cwd` から worktree の git dir の `ocw-run-id` を読む等）を
   Codex の `cwd` にもそのまま使う。解決できなければ既存どおり `unknown` / null。Codex 専用の解決を作らない
6. **既存の Claude の利用枠の集計・表示は、provider が `"openai"` の `quota.sample` を見ない**（孫1）。
   `quota_periods()`・`report --window`・`--month` の利用枠・`--pr` の 5h/7d・定価換算（既に anthropic に
   絞ってある）をすべて確かめる。絞り方は「`openai` を除く」ではなく「Claude の利用枠のサンプルだけを取る」
   形にするか、どちらが既存の記録（provider が null のまま残っている古い `quota.sample` があるか）に安全かを
   孫1 が実物の `~/.local/state/ocw-meter` を読み取り専用で確かめて決める
7. **表示の provider の指定**（孫2）: `report --quota-progress` に **`--provider <anthropic|openai>`** を足す
   （既定 `anthropic`。今の出力と同じ）。`dash` は Codex の `quota.sample` が1件でもあれば Codex の週の利用枠を
   Claude とは別に出し、1件も無ければ今と同じ画面にする
8. **日ごとの棒（`--daily`）とヒートマップ（`--heatmap`）は今のまま**全モデルの `usage.message` を数える
   （DeepSeek も既に混ざっている）。Codex のモデルは自然に現れる。加重の式も変えない（Claude の利用枠の
   加重だが、この2つは「量の目安」として全モデル共通で使っている。式をモデルごとに変えるのはスコープ外）

## 設計1: Codex の rollout の取り込み（孫1）

- `ingest` に Codex の rollout の走査を足す。カーソル（`state/ingest-cursor.json`）は Claude の記録と同じ仕組みで
  ファイルごとに持つ（キーが衝突しない形で）
- `infer_provider()` の扱い: Codex の応答は `session_meta.model_provider` から provider を取るので、モデル名の
  前方一致に頼らない。ただし `infer_provider()` を呼ぶ既存の箇所（`report --model` のまとめ方、定価換算の
  `cost_basis` の判定など）に `gpt-*` / `codex-*` が来たときに `"unknown"` 扱いで変な表示にならないかを確かめ、
  要れば直す
- 既存の Claude の利用枠の集計を Claude だけに絞る（設計0 の 6）
- `ocw-meter help` の `ingest` の説明と環境変数の節に Codex の記録と `OCW_METER_CODEX_SESSIONS_DIR` を足す。
  `bin/README.md` の `ocw-meter` の節、イベントスキーマ（`docs/reference/DOC-2608021229-c_ocw-meterイベントスキーマ.md`）に
  `source: "codex-rollout"` と provider `openai` を足す
- ADR を `docs/adr/` に1本足す: rollout の形式（背景4.1 の要約）、定額の枠として扱う理由（背景4.2）、
  トークンの写し方、fork・resume の二重計上の避け方、`quota.sample` の間引き方、Claude の利用枠の集計の絞り方

## 設計2: `dash` と `report` の表示（孫2）

- `report --quota-progress --provider openai` で Codex の週の利用枠の推移を出す（描画は既存と同じコード。
  provider で `quota.sample` を選ぶだけにする）。`--json` / `--plain` にも provider を出す。Codex の
  `--quota-per-pct` は無いので、残りの % をトークンに換算する欄は Codex では出さない（理由を1行出す）
- `dash`: Codex の `quota.sample` があるときだけ、Codex の週の利用枠のグラフ（と、上部の数字のタイルに Codex の
  5時間・週の %）を足す。Claude のものと見分けがつく見出しにする。端末の高さが足りないときに何から省くかは、
  既存の省き方（グラフを縮める → ヒートマップ → 日ごとの棒）に Codex のグラフをどこで入れるかを孫2 が決め、
  PR に書く
- `report --model` / `--daily` / `--heatmap` に Codex のモデルが現れることを確かめる（設計0 の 8。直す必要が
  無ければ直さない）
- `ocw-meter help` の `dash` / `--quota-progress` の説明と `bin/README.md` を更新する

## 孫ブランチ分割の叩き台（ブリーフより転記。採った分割は上の進捗テーブル）

ブリーフの叩き台は「孫1: Codex の会話記録の取り込みと OpenAI の価格表（記録側）」「孫2: `dash` / `report` の表示を
Codex に対応させる（`provider=anthropic` 前提の箇所の見直し）」で、両者が provider 名・モデル名の値を共有するので
縛り合いが強ければ1本にまとめてよい、とあった。司令官は次のとおり変えた。

- OpenAI の価格表は作らない（背景4.2。定額の枠で使っているため）
- 「`provider=anthropic` 前提の箇所の見直し」のうち、Codex の `quota.sample` で Claude の表示が汚れるのを防ぐ
  部分は孫1 に移した（取り込みと同じ PR で塞がないと、傘の上で一時的に Claude の週のグラフが壊れる）
- 縛り合う値は設計0 で固定し、孫2 は孫1 のマージ後に直列で進める

## 進行記録

（司令官が運用中に分かったこと・人間の決定をここに追記する）

- 2026-11-16: 傘は `ocw -H` でローカルの `master`（`d68900d`）から切られていたので、`origin/master`（`710449f`）へ
  rebase して push した。背景4 の確認を行い、計画書を起草した。ブリーフは転記後に削除した。孫1 を spawn する

## 孫1用プロンプト:

````markdown
# 傘ブランチ: codex-meter
# 孫ブランチ: cm-01-codex-ingest
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/codex-meter/docs/planning/DOC-2611160715_codex-meter_計画.md`

**まず計画書の「概要」「背景3」「背景4」「決定的な制約」「スコープ外」「必須の検証ステップ」「テスト方針」「設計0」
「設計1」「進行記録」を読むこと。** 続けて dotfiles の `AGENTS.md` の作業別の索引から、テストを足す
（DOC-2610150520-a）・コミット前（DOC-2610150520）・実装時の注意（DOC-2610150520-c）を読む。
`bin/ocw-meter` は 9,000 行を超えるので、`grep -n` で当たりをつけて必要な範囲だけ読むこと。

## 実装開始前の必須手順

`ocw` がすでに `cm-01-codex-ingest` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/codex-meter` の
先端から切られていることを確かめる（`git pull` は使わない）。

## やること

1. 実物の Codex の rollout（`~/.codex/sessions/`）を**読み取り専用で**、計画書 設計0 の 2 のフィールドだけ見て、
   背景4.1 の観測を確かめる。特に fork・resume の rollout（`session_meta` が複数ある）で、親スレッドの使用量を
   二重に数えない見分け方を決める。`token_usage_record` が無い古い rollout の扱いも決める
2. `ingest` に Codex の rollout の取り込みを足す（設計0 の 1〜5、設計1）。`usage.message` と `quota.sample` を書く
3. 既存の Claude の利用枠の集計・表示が Codex の `quota.sample` を見ないようにする（設計0 の 6）。絞り方を決める
   前に、実物のストア（`~/.local/state/ocw-meter/events/`）を**読み取り専用で**見て、provider が null の古い
   `quota.sample` があるかを確かめる
4. `OCW_METER_HOME` を `mktemp -d` に向けて実物の rollout を取り込み、`report --model` に Codex のモデルが出ること、
   `report --quota-progress` と `dash` の Claude の週のグラフが取り込み前と変わらないことを手で確かめる
   （確かめた範囲を PR 本文に書く。数字の中身やアカウント ID は書かない）
5. `ocw-meter help`・`bin/README.md`・イベントスキーマ（DOC-2608021229-c）を更新する
6. ADR を `docs/adr/` に足す（`DOC-DOCID_PLACEHOLDER_<名前>.md` で作って `./tools/doc-id/doc-id assign <path>`）。
   書くことは計画書 設計1 の最後の項目
7. 設計0 で固定した値（provider `openai`・`source` `codex-rollout`・環境変数名・フィールドの写し方）を変える必要が
   出たら、変えずに司令官へ知らせる

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- Codex の rollout から `usage.message` が1応答1件で書かれ、トークンの4区分が設計0 の 3 のとおり写る
  （`input_tokens` からキャッシュ分が引かれている）
- **fork・resume の rollout で親スレッドの使用量を二重に数えない。この regression は必ず自動テストで固定する**
- 何度 `ingest` しても `usage.message` と `quota.sample` の件数が増えない（冪等）
- **Codex の `quota.sample` があっても、Claude の週の利用枠（`quota_periods()` を通る表示）の値が変わらない。
  この regression は必ず自動テストで固定する**
- Codex の記録のディレクトリが無いときに `ingest` が今と同じに成功する
- 会話の本文（`response_item`）とアカウント ID 類がイベントに入らない

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --all-files
bin/tests/lint.sh
python3 -m unittest discover -s bin/tests -v
./tools/doc-id/doc-id verify
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `codex-meter` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** `/pr-review-loop` の手順にマージへ進む記述があっても実行しない
   （孫が人間のフィードバック前に勝手にマージするのを防ぐため。マージは傘の司令官が行う）
5. （Herdr あり・司令官が宛先を埋め込んだときだけ）最終報告を書き終えたら、最後の行動として
   司令官へ承認を報告する。宛先は、司令官が spawn の送信文で渡した司令官の Herdr ペイン
   （渡されていなければ報告せず、人間に「承認済み。マージは司令官（または人間）が行う」と伝えて止まる）。
   送り方は umbrella-orchestrator スキル §5「AI間送信手順（二段構え）」に従う。本文は
   「孫1 `cm-01-codex-ingest` の PR #<番号> が HEAD <短縮SHA> で承認されました。マージをお願いします。」
   だけにする（「〜とだけ返事して」のような指示は付けない）。報告は1回だけ。送れなくても
   再送せず（司令官の巡回が拾う）、送れなかったことを人間に1行伝えて止まる

なお `/pr-review-loop` は、レビューを依頼した直後の区切りで文脈が大きければ `ocw self-compact` で
自分を compact する（その手順は pr-review-loop 側。使えなければ何もしない）。compact の後は、
復帰メモに従ってレビュー待ちに戻り、この「実装完了後の流れ」を最後まで続けること。
実装の途中でも、検証が通ってコミットした直後の区切りで、文脈が
150,000 トークン（claude-ds 以外の Claude は 200,000。`ANTHROPIC_BASE_URL` に `deepseek` を含むかで見分ける）を超えていれば
`ocw self-compact` で自分を compact してよい（WIP のコミットは区切りでない。指摘対応の修正の途中は対象外。回数の上限は無いが、
前回の compact から文脈が 100,000 以上増えていなければ見送る。ADR DOC-2610142337・DOC-2611032102）。
測り方は `/pr-review-loop` の「区切りでの自己 compact（実装側のみ）」の手順1のコマンドと同じ（その節の (3) の項だけを読めばよい。
手順の「Phase 3 へ進む」は実装途中には当てはまらない）。復帰メモ（リポの外の一時ファイル）には、計画書のパスと孫の節・
済んだこと（コミットの一覧）・作業中に下した判断とその理由・残り・次の一手・検証コマンドを書き（増分の起点は復帰後に測るので
メモには書かない）、先頭に「計画書の続きから実装を再開する。レビュー待ちではない」と書く。コマンドを実行したらそのターンを終える。
使えない・拒否・失敗なら何もせず実装を続ける（人間に提案もしない）。
実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## 大きい出力を文脈へ流し込まない（実装中ずっと）

文脈の膨張は、1k〜20k字級の出力の積み重ねと、自分で書く長い出力で起きる。次を守ること:
- ファイルを `cat` / `sed -n` で丸ごと読まず、`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む
- 約100行・5,000字を超えそうな出力（テスト・分析・ログ・`git diff`・JSON）は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る
- 既存の長いファイルや、繰り返し直して実行するスクリプトを Write / heredoc で丸ごと書き直さない。一度ファイルに置き、変更は Edit の差分で行う（新規ファイルを最初に1回書くのは構わない）

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `codex-meter` から切ること**。master から切ると PR の diff に傘ブランチ全体が
混入してレビュー不能になる。`ocw` が `origin/codex-meter` から切ったワークツリーを用意済みなので、
上の「実装開始前の必須手順」で確かめるだけでよい（`git pull` は使わない）。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
人間の発言を逐語で書かない（PUBLIC リポ。要約する）。マシン名・アカウント ID を書かない。
````

## 孫2用プロンプト:

````markdown
# 傘ブランチ: codex-meter
# 孫ブランチ: cm-02-codex-dash
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/codex-meter/docs/planning/DOC-2611160715_codex-meter_計画.md`

**まず計画書の「概要」「背景4」「決定的な制約」「スコープ外」「必須の検証ステップ」「テスト方針」「設計0」
「設計2」「進行記録」を読むこと。** 孫1 は傘にマージ済みなので、孫1 の ADR（進行記録に DOC-ID がある）と、
孫1 が `bin/ocw-meter` に足した Codex の `quota.sample` の形も読む。続けて dotfiles の `AGENTS.md` の作業別の
索引から、テストを足す（DOC-2610150520-a）・コミット前（DOC-2610150520）・実装時の注意（DOC-2610150520-c）を読む。
`bin/ocw-meter` は 9,000 行を超えるので、`grep -n` で当たりをつけて必要な範囲だけ読むこと。

## 実装開始前の必須手順

`ocw` がすでに `cm-02-codex-dash` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/codex-meter` の
先端（孫1 のマージを含む）から切られていることを確かめる（`git pull` は使わない）。

## やること

1. `report --quota-progress` に `--provider <anthropic|openai>`（既定 `anthropic`）を足し、Codex の週の利用枠の
   推移を出せるようにする（設計0 の 7、設計2）。`--json` / `--plain` にも provider を出す
2. `dash` に、Codex の `quota.sample` があるときだけ Codex の週の利用枠のグラフと 5時間・週の % のタイルを足す。
   端末の高さが足りないときの省く順番を決めて PR に書く
3. `report --model` / `--daily` / `--heatmap` に Codex のモデルが現れることを確かめる（設計0 の 8。直す必要が
   無ければ直さない）
4. `OCW_METER_HOME` を `mktemp -d` に向けて実物の rollout を取り込み、`dash`（`--watch` なし）と
   `report --quota-progress --provider openai` を手で確かめる。Codex の記録が無いときの `dash` が今と同じ画面に
   なることも確かめる（`OCW_METER_CODEX_SESSIONS_DIR` を空のディレクトリに向ける）。確かめた範囲を PR 本文に書く
5. `ocw-meter help`・`bin/README.md` を更新する。設計判断が増えたら（省く順番など）孫1 の ADR に追記するか、
   小さければ PR 本文に書く
6. 設計0 で固定した値を変える必要が出たら、変えずに司令官へ知らせる

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- `report --quota-progress` を `--provider` なしで呼ぶと、今と同じ（Claude だけの）出力になる
- `--provider openai` では Codex の `quota.sample` だけで推移が描かれ、Claude の値が混ざらない
- **Codex の `quota.sample` が1件も無いとき、`dash` の画面が今と同じになる。この regression は必ず自動テストで固定する**
- Codex の `quota.sample` があるとき、`dash` に Codex の週の利用枠が Claude とは別に出る

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --all-files
bin/tests/lint.sh
python3 -m unittest discover -s bin/tests -v
./tools/doc-id/doc-id verify
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `codex-meter` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** `/pr-review-loop` の手順にマージへ進む記述があっても実行しない
   （孫が人間のフィードバック前に勝手にマージするのを防ぐため。マージは傘の司令官が行う）
5. （Herdr あり・司令官が宛先を埋め込んだときだけ）最終報告を書き終えたら、最後の行動として
   司令官へ承認を報告する。宛先は、司令官が spawn の送信文で渡した司令官の Herdr ペイン
   （渡されていなければ報告せず、人間に「承認済み。マージは司令官（または人間）が行う」と伝えて止まる）。
   送り方は umbrella-orchestrator スキル §5「AI間送信手順（二段構え）」に従う。本文は
   「孫2 `cm-02-codex-dash` の PR #<番号> が HEAD <短縮SHA> で承認されました。マージをお願いします。」
   だけにする（「〜とだけ返事して」のような指示は付けない）。報告は1回だけ。送れなくても
   再送せず（司令官の巡回が拾う）、送れなかったことを人間に1行伝えて止まる

なお `/pr-review-loop` は、レビューを依頼した直後の区切りで文脈が大きければ `ocw self-compact` で
自分を compact する（その手順は pr-review-loop 側。使えなければ何もしない）。compact の後は、
復帰メモに従ってレビュー待ちに戻り、この「実装完了後の流れ」を最後まで続けること。
実装の途中でも、検証が通ってコミットした直後の区切りで、文脈が
150,000 トークン（claude-ds 以外の Claude は 200,000。`ANTHROPIC_BASE_URL` に `deepseek` を含むかで見分ける）を超えていれば
`ocw self-compact` で自分を compact してよい（WIP のコミットは区切りでない。指摘対応の修正の途中は対象外。回数の上限は無いが、
前回の compact から文脈が 100,000 以上増えていなければ見送る。ADR DOC-2610142337・DOC-2611032102）。
測り方は `/pr-review-loop` の「区切りでの自己 compact（実装側のみ）」の手順1のコマンドと同じ（その節の (3) の項だけを読めばよい。
手順の「Phase 3 へ進む」は実装途中には当てはまらない）。復帰メモ（リポの外の一時ファイル）には、計画書のパスと孫の節・
済んだこと（コミットの一覧）・作業中に下した判断とその理由・残り・次の一手・検証コマンドを書き（増分の起点は復帰後に測るので
メモには書かない）、先頭に「計画書の続きから実装を再開する。レビュー待ちではない」と書く。コマンドを実行したらそのターンを終える。
使えない・拒否・失敗なら何もせず実装を続ける（人間に提案もしない）。
実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## 大きい出力を文脈へ流し込まない（実装中ずっと）

文脈の膨張は、1k〜20k字級の出力の積み重ねと、自分で書く長い出力で起きる。次を守ること:
- ファイルを `cat` / `sed -n` で丸ごと読まず、`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む
- 約100行・5,000字を超えそうな出力（テスト・分析・ログ・`git diff`・JSON）は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る
- 既存の長いファイルや、繰り返し直して実行するスクリプトを Write / heredoc で丸ごと書き直さない。一度ファイルに置き、変更は Edit の差分で行う（新規ファイルを最初に1回書くのは構わない）

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `codex-meter` から切ること**。master から切ると PR の diff に傘ブランチ全体が
混入してレビュー不能になる。`ocw` が `origin/codex-meter` から切ったワークツリーを用意済みなので、
上の「実装開始前の必須手順」で確かめるだけでよい（`git pull` は使わない）。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
人間の発言を逐語で書かない（PUBLIC リポ。要約する）。マシン名・アカウント ID を書かない。
````
