# 計画書: ocw-meter の数え漏れ（サブエージェント）と週の上限の見積もり

傘ブランチ: `meter-subagent-quota`
ターゲット: `master`

## 概要

`bin/ocw-meter` について、次の3件をこの傘で進める。

1. **サブエージェントの記録を数える（孫1。いちばん大事）。** `ingest` はメインの会話の記録
   （`~/.claude/projects/*/*.jsonl`）しか読まず、Agent ツールで立てたサブエージェントの記録
   （`~/.claude/projects/<proj>/<session>/subagents/agent-*.jsonl`）が丸ごと抜けている。これを読み、親の会話へ結びつける
2. **時間範囲を指定した使用量の report（孫3）。** `--since <時刻> [--until <時刻>]` で、その間のモデル別トークンを出す
   （「この作業でどれだけ使ったか」を後から測るため）
3. **モデルごとの「週の上限の 1% あたりのトークン」の report（孫2）。** `quota.sample` の 7 日の % の増えと、同じ時間帯の
   `usage.message` をモデル別に突き合わせて推定する。孫3 の範囲の report にも推定 % を足す

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。転記後に削除済みで
> 参照できない前提で書く）を material として司令官が起草したものである。** ブリーフに
> 書かれていた問題意識・決定事項・注文・実測値・制約・スコープ外・必須の検証ステップ・
> 孫分割の叩き台は本計画書へ転記済みであり、以降はこの計画書が正典である。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `msq-01-ingest-subagents` | `ingest` がサブエージェントの記録（`<session>/subagents/agent-*.jsonl`）を読み、親の会話・run_id・role へ結びつける。スキーマ文書を更新する | ✅ PR #181 マージ済 |
| 2 | `msq-02-quota-per-model` | モデル系統ごとの「週の 1% あたりのトークン」を推定する report を足し、孫3 の範囲の report に推定 % を足す。推定方法を ADR に残す | ✅ PR #183 マージ済 |
| 3 | `msq-03-range-report` | `report` に `--since` / `--until` の時間範囲を足し、その間のモデル別トークン（と費用）を出す | ✅ PR #182 マージ済 |

依存:

- 孫1 と孫3 は**並列**（孫1 は `ingest` 側、孫3 は `report` 側を触る。同じ `bin/ocw-meter` と `bin/tests/test_ocw_meter.py` を
  触るので、後からマージされる側が傘へ rebase で追随する）
- 孫2 は**孫1 と孫3 の両方が傘にマージされてから** spawn する（孫1 で Haiku の分が入ってから測るため。孫3 の範囲の report に
  推定 % を足すため）

## ワークスペースラベル

接頭辞は `ocw label-prefix`（dotfiles では `dotfiles`）。

- 傘: `dotfiles :: meter数え漏れと週上限`
- 孫1: `dotfiles :: meter数え漏れと週上限 孫1 サブエージェントを数える`
- 孫2: `dotfiles :: meter数え漏れと週上限 孫2 モデル別1%あたり`
- 孫3: `dotfiles :: meter数え漏れと週上限 孫3 時間範囲の使用量`

## 背景1: 問題意識（要約）

pixidex の傘（生成ページの使い勝手）の司令官の会話で、持ち主が LoRA 約 2,300 本の説明文を AI に読ませる作業の費用を尋ねた。

- 持ち主は 200〜300 万トークンが各モデルで週の利用上限の何 % に当たるかを知りたがった。司令官が「週の上限はトークン数で公開されて
  いないので出せない」と答えたところ、持ち主は「最上位（月 200 ドル）のプランで今 54%。ocw-meter があるのだから、モデルごとの
  使用トークンが分かれば % を割り出せるはず」と返した。作業はほぼこのマシンだけで行っている
- 作業は Haiku のサブエージェントで回した。途中で持ち主がトークンの使用量は想定どおりかを尋ね、司令官が ocw-meter を見たところ、
  **ocw-meter はメインの会話の記録しか読まず、裏で回したサブエージェント（Haiku）の分が数えられていない**ことが分かった
- 持ち主は、これを dotfiles に傘を立てて直させたい、ほかに ocw-meter への注文があれば一緒に頼みたいと述べた

## 背景2: 人間が確定させた決定事項（覆さないこと）

- dotfiles に傘を作って進める（task-intake で「dotfiles だけ・複数本・司令官は dotfiles」を持ち主が選んだ。2026-10-31）
- 注文は「概要」の 3 つ（pixidex の司令官がまとめ、持ち主がそのまとめを task-intake で渡すよう指示した）

## 背景3: 注文の原文の要点（pixidex の司令官のまとめより）

1. **サブエージェントの記録を数える（いちばん大事）**
   - `ingest` は `~/.claude/projects/*/*.jsonl` しか読まない。Agent ツールで立てたサブエージェントの記録は
     `~/.claude/projects/<proj>/<session>/subagents/agent-*.jsonl` にあり、数えられていない
     （pixidex の司令官セッション 1 つで 58 ファイル。Haiku で LoRA 2,278 本を読ませた分がまるごと抜けた）
   - 親セッション・run_id・role への結びつけも（親の session_id から辿れるはず）
2. **モデルごとの「週の 1% あたりのトークン」を出す report**
   - `quota.sample` の 7 日の % の増えと、同じ時間帯の `usage.message` をモデル別に突き合わせて、1% あたりのトークン
     （入力・キャッシュ作成・キャッシュ読み・出力の重み付き）を推定する
3. **時間範囲を指定した使用量の report**
   - `--since <時刻> [--until]` で、その間のモデル別トークンと、2 があれば推定 % を出す
     （「この作業でどれだけ使ったか」を後から測るため）

## 背景4: 実測値

### 4.1 pixidex の司令官の手計算（2026-10-31）

- 10 月分の events（`quota.sample` 34,832 件・`usage.message` 145,253 件）を手で突き合わせた
- 方法: 3・6・12 時間の区切りで、同じ 7 日の期間（`seven_day_resets_at` が同じ）の中の Δ% を、モデルの系統（opus・sonnet・haiku・fable）
  ごとの重み付きトークン（`input + 1.25×cache_creation + 0.1×cache_read + 5×output`）に非負の最小二乗で当てた
- 結果: **Opus は 1% あたり重み付き約 1,000 万（生のトークンで約 7,000 万。大半がキャッシュの読み）で、区切りを変えても安定した。**
  Sonnet は区切りで 0.04〜0.18%/百万とぶれた。Haiku は記録にほぼ出てこず測れなかった（孫1 の数え漏れのため）
- 10 月の総量: Opus 生 214 億・重み付き 31.7 億、Sonnet 生 87 億・重み付き 11.8 億
- サブエージェント 1 回（Haiku、LoRA 50 本の読み取り）の終わりの通知に出た `subagent_tokens` はおよそ 10〜15 万。
  ingest 後の合計がこれと桁で合うかで孫1 を確かめられる

### 4.2 司令官が確かめたサブエージェントの記録の形（2026-10-31）

確かめの材料: `~/.claude/projects/-home-manemone-projects-pixidex-gen-usability/b4c664cd-5753-4f80-bad0-f533bf75a36c/subagents/`
（`agent-*.jsonl` 58 本と、同名の `agent-*.meta.json`）

- `agent-*.jsonl` の `type: "assistant"` 行は、メインの記録と同じ形（`message.id` / `message.model` / `message.usage` / `timestamp` /
  `cwd` / `gitBranch`）に加えて、**`sessionId` が親の会話の session_id のまま**、`isSidechain: true`、`agentId`（ファイル名の
  `agent-<agentId>` と同じ）を持つ。親への結びつけは `sessionId` でそのまま辿れる
- `agent-*.meta.json` は `agentType`（例 `general-purpose`）・`model`（例 `haiku`）・`spawnDepth`・`description`（親が書いた作業の
  説明文）などを持つ。**`description` は会話の中身に当たるので ocw-meter に記録しない**
- この 58 本の `message.id` ごとの集計（重複は最後の行）: Haiku 309 件（入力 618・キャッシュ作成 487 万・キャッシュ読み 2,015 万・
  出力 214 万）、**Opus 568 件**（キャッシュ読み 1.17 億ほか）、Sonnet 18 件。内訳は `meta.json` の `model` で分かれる:
  LoRA の読み取り（10/30 16:15〜16:52）は `haiku` 指定の 49 本で全部 Haiku。Opus の分は、親が `opus` を明示して立てた別の作業
  （PR の画面の文言の点検や QA。10/29〜10/30）の 8 本。モデルの指定なしの 1 本は、`~/.claude/settings.json` の
  `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` により Sonnet で動いた。どのモデルの分も今は数えられていない
- マシン全体では `~/.claude/projects/*/*/subagents/agent-*.jsonl` が 321 本ある。同じ深さのほかのディレクトリは `tool-results/`
  （`.jsonl` を含まない）だけだった

### 4.3 既存の ocw-meter の関係する所（2026-10-31 時点の `bin/ocw-meter`）

- `perform_ingest()` が `projects_dir.glob("*/*.jsonl")` で記録を集める。ファイルごとのカーソル（inode・size・mtime・offset）と
  `message.id` による重複除去で、何度走らせても同じ結果になる
- `extract_assistant_candidate()` が読むのは許可した項目だけ（`message.content` は読まない）。`isSidechain` は既に
  `usage.message` の `is_sidechain` として記録している（スキーマ文書 DOC-2608021229-c §2.4）
- role・run_id は Herdr のペインのラベルや `quota.sample` との session_id join で解決する（同 §4.5）。サブエージェントの行は
  `sessionId` が親のままなので、同じ経路で親の role・run_id に結びつく見込み
- `report` は `--phase` / `--model` / `--role` / `--window` / `--month` / `--pr` を持つが、時間範囲の指定は無い。`ingest` には
  読み取り専用の絞り込みとしての `--since` が既にある（カーソルを進めない）
- `quota.sample` は statusLine から記録され、`seven_day_used_pct` / `seven_day_resets_at` / `session_id` を持つ
  （`claude-ds` のセッションは `null` 一式）

## 決定的な制約（孫は全部守ること）

- dotfiles の `AGENTS.md` の最重要ルール（`master` を書き換える操作は人間だけ。deploy スクリプトを人間の指示なしに実 `$HOME` で
  実行しない。linter の抑制を AI の判断で足さない）
- ocw-meter のイベントスキーマ（`docs/reference/DOC-2608021229-c_ocw-meterイベントスキーマ.md`）に従う。フィールドを足すときは
  同文書 §6「`schema_version` の変更ルール」に従い、同文書を更新する
- **fail-open の方針を崩さない（statusLine を壊さない）。** statusLine から呼ばれる経路（`quota.sample` の記録）を遅くしたり
  失敗させたりしない。`report` の自動 ingest の失敗が `report` を止めない今の振る舞いも保つ
- **`message.content` を読まない今の方針を保つ。** サブエージェントの `meta.json` の `description` も記録しない
- 推定は**見積もり**として出す。推定 % を使って止める・モデルを替えるなどの自動の制御はしない（スコープ外）
- 新しい依存を足さない（`bin/ocw-meter` は標準ライブラリだけで書かれている。非負の最小二乗も標準ライブラリで書く）

## スコープ外

- pixidex・modeldex の変更
- 推定 % を使った自動の制御（止める・モデルを替える）。見積もりを出すところまで
- このマシン以外で使った分の取り込み（持ち主はほぼこのマシンだけで使っている。推定の誤差の要因として ADR に書くにとどめる）

## 必須の検証ステップ

- dotfiles の `AGENTS.md`「コミット前の必須ステップ」に従う（詳細は DOC-2610150520）:
  - 変更したファイルごとに `pre-commit run --files <path>`（新規・大幅変更の時点で）と、最後に `pre-commit run --all-files`
  - `bin/` を変えたら `python3 -m unittest discover -s bin/tests -v`
  - `docs/` に新規ファイルを足すなら `DOC-DOCID_PLACEHOLDER_<名前>.md` で作って `./tools/doc-id/doc-id assign <path>`、最後に
    `./tools/doc-id/doc-id verify`
- 実データでの確かめは `OCW_METER_HOME` を一時ディレクトリに向けて行う（実の保存先を書き換えない）。読むのは実の
  `~/.claude/projects` でよい（読み取りだけ）

## テスト方針（dotfiles AGENTS.md「テスト方針」と DOC-2610150520-a に従う）

- 孫1: `bin/tests/test_ocw_meter.py` の既存の ingest のテスト（fixtures の合成の記録）に寄せて、次を保護する。サブエージェントの記録が
  数えられ、親の session_id に結びつく／2回走らせても増えない（カーソルと重複除去）。**サブエージェントの記録が数えられることは、
  この傘の発端なので必ず自動テストで固定する**
- 孫3: 範囲の境界（`--since` ちょうど・`--until` ちょうど）と、範囲外の `usage.message` が入らないことを1つの scenario で確かめる程度
- 孫2: 合成の `quota.sample` と `usage.message` から、既知の係数が推定で戻ることを1つの scenario で確かめる。データが足りない系統で
  「測れない」と出ることも同じ scenario に含めてよい

## 設計1: サブエージェントの記録を読む（孫1）

1. `perform_ingest()` が集める記録に `<projects>/*/*/subagents/agent-*.jsonl` を足す（`spawnDepth` が 2 以上のサブエージェントの置き場所が
   違うなら、実データで確かめて合わせる）。カーソル・重複除去は今の仕組みをそのまま使う
2. `usage.message` に、サブエージェントの記録から来たことを示す項目を足す（例 `agent_id`。`is_sidechain` は既にある）。項目名と
   `schema_version` の扱いはスキーマ文書 §6 に従って孫が決め、同文書 §2.4 に書く。`meta.json` から足すなら `agentType` 程度に
   とどめ、`description` は読まない
3. role・run_id・PR の結びつけは、親の session_id から今の経路（§4.5）で解決されることを確かめる。サブエージェント専用の role は
   作らない（親の役割の中で使った分として数える）。`report --role` などで親の分とサブエージェントの分を見分けたくなったら、
   既存の出力を壊さない範囲で足してよい（必須ではない）
4. スキーマ文書 DOC-2608021229-c と `bin/ocw-meter` の `ingest` のヘルプ文・`bin/README.md` の読む範囲の記述を更新する
5. 確かめ: `OCW_METER_HOME` を一時ディレクトリにして実の `~/.claude/projects` を ingest し、背景4.2 の材料のセッションで Haiku の
   `usage.message` が 309 件前後入ること、サブエージェント 1 回分の合計が 10〜15 万の桁で合うことを PR 本文に書く

## 設計2: モデルごとの「週の 1% あたりのトークン」（孫2）

1. 推定の方法は背景4.1 の手計算を既定にする: `seven_day_resets_at` が同じ期間の中で、区切り（3・6・12 時間）ごとの `seven_day_used_pct`
   の増えを、同じ区切りのモデル系統（opus・sonnet・haiku・fable）ごとの重み付きトークン（`input + 1.25×cache_creation + 0.1×cache_read
   + 5×output`）に非負の最小二乗で当てる。`claude-*` 以外のモデル（`claude-ds` の DeepSeek など。上限に数えられない）は除く
2. 出すもの（系統ごと）: 1% あたりの重み付きトークン・生のトークン、区切りの長さごとの値（安定しているかが見える形で）、使った区切りの数。
   **データが足りない・区切りでぶれが大きい系統は、数字を出さず「測れない」と理由を出す**（ぶれの基準は孫が決めて ADR に書く）
3. 推定に使う期間は引数で選べるようにし、既定は孫が決める（例: 直近の 1〜2 回分の 7 日の期間）
4. 孫3 の範囲の report に、推定できた系統について「推定 %（週の上限に対して）」を足す。推定できない系統は空欄にする
5. 推定の方法・重み・区切り・測れないとする基準・誤差の要因（`quota.sample` の % の刻み、このマシン以外の使用、`quota.sample` の
   記録の間隔など）を ADR に残す（`docs/adr/DOC-DOCID_PLACEHOLDER_*.md` で作って `./tools/doc-id/doc-id assign`）。却下した案
   （単純な比の合計など）も書く
6. 確かめ: 実データ（`OCW_METER_HOME` は実の保存先を読み取りだけで使うか、コピーした一時ディレクトリで）で推定し、Opus が背景4.1 の
   約 1,000 万（重み付き）と桁で合うか、孫1 のあとで Haiku が測れるようになったかを PR 本文に書く

## 設計3: 時間範囲の使用量（孫3）

1. `report` に `--since <時刻>` と `--until <時刻>`（省略時は今）を足し、その範囲の `usage.message` のモデル別トークン
   （入力・キャッシュ作成・キャッシュ読み・出力・合計）と費用（今の `--model` と同じ列）を出す。`--json` にも対応する
2. 時刻の書式は `ingest --since` と同じく `parse_ts()` が受け付けるもの（RFC3339）にし、ヘルプ文に書く
3. **`ingest --since` と意味を混ぜない。** `report` の自動 ingest には範囲を渡さない（範囲は読み出しの絞り込みだけ）
4. 既存の `--model` / `--role` などと組み合わせられるようにするか、範囲専用の出力にするかは孫が決める。既存の出力の形は壊さない
5. 推定 % の列は孫2 が足す（孫3 では出さない）
6. `bin/ocw-meter` のヘルプ文と `bin/README.md` を更新する

## 孫ブランチ分割の叩き台（ブリーフより転記。採った分割は上の進捗テーブル）

叩き台であり、司令官が再設計してよいとされていた。

- 孫1: ingest がサブエージェントの記録を読む（親への結びつけ込み）
- 孫2: モデルごとの 1% あたりのトークンの report（孫1 のあと。Haiku の分が入ってから測る）
- 孫3: 時間範囲の report（孫2 と並べてよい）

司令官の判断: 3 本の分け方はそのまま。並べ方だけ変え、孫3 を孫1 と並列で先に出し、孫2 を両方のマージ後にした。孫3 の範囲の
report は孫1 に依存しない（`usage.message` を読むだけ）ので先に出せる。孫2 を後にすると、孫2 が Haiku の分の入ったデータで測れ、
孫3 の範囲の report へ推定 % を足すところも孫2 の中で閉じる（孫2 と孫3 を並べると、推定 % を足す口をどちらが作るかで
同じ関数を取り合う）。

## 進行記録

（司令官が運用中に分かったこと・人間の決定をここに追記する）

- 2026-10-31: 計画書を起草した。傘を `origin/master`（5226074）へ追随させた。孫1・孫3 を並列で spawn した。孫2 は孫1・孫3 のマージ後
- 2026-10-31: 孫3 の PR #182 を司令官がマージした。傘で `python3 -m unittest discover -s bin/tests`（428件）と `pre-commit run --all-files` が通った
- 2026-10-31: 孫1 の PR #181 を司令官がマージした。傘で unittest（430件）と `pre-commit run --all-files` が通った。孫1・孫3 が揃ったので孫2 を spawn する
- 2026-10-31: 孫2 の PR #183 を司令官がマージした。傘で unittest（431件）と `pre-commit run --all-files` が通った。全孫が揃ったので master への最終 PR に進む

## 孫1用プロンプト:

````markdown
# 傘ブランチ: meter-subagent-quota
# 孫ブランチ: msq-01-ingest-subagents
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/meter-subagent-quota/docs/planning/DOC-2610310205_meter-subagent-quota_計画.md`

**まず計画書の「概要」「背景3」「背景4.2」「背景4.3」「設計1」「決定的な制約」「スコープ外」「必須の検証ステップ」
「テスト方針」「進行記録」を読むこと。** 続けて dotfiles の `AGENTS.md` の作業別の索引から、テスト（DOC-2610150520-a）・
コミット前（DOC-2610150520）を読む。

## 実装開始前の必須手順

`ocw` がすでに `msq-01-ingest-subagents` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/meter-subagent-quota` の
先端から切られていることを確かめる（`git pull` は使わない）。

## やること

1. 計画書 設計1 の 1〜4 を実装する（サブエージェントの記録を ingest の対象に足す・`usage.message` にサブエージェント由来を示す項目を
   足す・親への結びつけを確かめる・スキーマ文書とヘルプ文と `bin/README.md` を更新する）
2. 計画書 設計1 の 5 の確かめを行い、結果を PR 本文に書く（`OCW_METER_HOME` は `mktemp -d` の一時ディレクトリにする。実の保存先を
   書き換えない）

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- サブエージェントの記録の `usage.message` が数えられ、親の session_id に結びつく
  > **この regression は必ず自動テストで固定する**
- 2回 ingest しても件数が増えない（カーソルと `message.id` の重複除去がサブエージェントの記録にも効く）
- `message.content` と `meta.json` の `description` を記録しない
- 既存のメインの記録の ingest・`report` の出力が変わらない（既存テストで守られていればよい）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
python3 -m unittest discover -s bin/tests -v > "$(mktemp -d)/unittest.log" 2>&1; echo $?
pre-commit run --all-files
./tools/doc-id/doc-id verify
```

（unittest の出力は長いので一時ファイルへ書き出し、`tail` で結果だけ見る）

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `meter-subagent-quota` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** `/pr-review-loop` の手順にマージへ進む記述があっても実行しない
   （孫が人間のフィードバック前に勝手にマージするのを防ぐため。マージは傘の司令官が行う）
5. 最終報告を書き終えたら、最後の行動として、司令官が spawn の送信文で渡した司令官の Herdr ペインへ
   承認を報告する（渡されていなければ報告せず、人間に「承認済み。マージは司令官（または人間）が行う」と伝えて止まる）。
   送り方は umbrella-orchestrator スキル §5「AI間送信手順（二段構え）」に従う。本文は
   「孫1 `msq-01-ingest-subagents` の PR #<番号> が HEAD <短縮SHA> で承認されました。マージをお願いします。」
   だけにする。報告は1回だけ。送れなくても再送せず、送れなかったことを人間に1行伝えて止まる

なお `/pr-review-loop` は、レビューを依頼した直後の区切りで文脈が大きければ `ocw self-compact` で
自分を compact する（その手順は pr-review-loop 側。使えなければ何もしない）。compact の後は、
復帰メモに従ってレビュー待ちに戻り、この「実装完了後の流れ」を最後まで続けること。
実装の途中でも、検証が通ってコミットした直後の区切りで、文脈が
200,000 トークンを超えていれば `ocw self-compact` で自分を compact してよい（WIP のコミットは
区切りでない。指摘対応の修正の途中は対象外。1 PR につき多くて 3 回。ADR DOC-2610142337）。
測り方は `/pr-review-loop` の「区切りでの自己 compact（実装側のみ）」の手順1のコマンドと同じ（その節の (3) の項だけを読めばよい。
手順の「Phase 3 へ進む」は実装途中には当てはまらない）。復帰メモ（リポの外の一時ファイル）には、計画書のパスと孫の節・
済んだこと（コミットの一覧）・作業中に下した判断とその理由・残り・次の一手・検証コマンド・実装途中の compact の回数を書き、
先頭に「計画書の続きから実装を再開する。レビュー待ちではない」と書く。コマンドを実行したらそのターンを終える。
使えない・拒否・失敗なら何もせず実装を続ける（人間に提案もしない）。
実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。
傘ブランチが先へ進んでコンフリクトしたら（孫3 が同じ `bin/ocw-meter` を並行して触っている）、`git rebase origin/meter-subagent-quota` と
`git push --force-with-lease` で追随する（AGENTS.md「最重要ルール」）。

## 大きい出力を文脈へ流し込まない（実装中ずっと）

文脈の膨張は、1k〜20k字級の出力の積み重ねと、自分で書く長い出力で起きる。次を守ること:
- ファイルを `cat` / `sed -n` で丸ごと読まず、`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む
  （`bin/ocw-meter` は約 6,000 行、`bin/tests/test_ocw_meter.py` は約 5,000 行ある）
- 約100行・5,000字を超えそうな出力（テスト・分析・ログ・`git diff`・JSON）は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る
- 既存の長いファイルや、繰り返し直して実行するスクリプトを Write / heredoc で丸ごと書き直さない。一度ファイルに置き、変更は Edit の差分で行う（新規ファイルを最初に1回書くのは構わない）

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `meter-subagent-quota` から切ること**。master から切ると PR の diff に傘ブランチ全体が
混入してレビュー不能になる。`ocw` が `origin/meter-subagent-quota` から切ったワークツリーを用意済みなので、
上の「実装開始前の必須手順」で確かめるだけでよい（`git pull` は使わない）。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

## 孫2用プロンプト:

````markdown
# 傘ブランチ: meter-subagent-quota
# 孫ブランチ: msq-02-quota-per-model
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/meter-subagent-quota/docs/planning/DOC-2610310205_meter-subagent-quota_計画.md`

**まず計画書の「概要」「背景3」「背景4.1」「背景4.3」「設計2」「設計3」「決定的な制約」「スコープ外」「必須の検証ステップ」
「テスト方針」「進行記録」を読むこと。** 孫1（サブエージェントの記録の ingest）と孫3（`report --since` / `--until`）は傘にマージ済みなので、
`git log --oneline origin/meter-subagent-quota` でその PR を確かめ、孫3 が作った範囲の report の口を把握する。
続けて dotfiles の `AGENTS.md` の作業別の索引から、テスト（DOC-2610150520-a）・コミット前（DOC-2610150520）を読む。

## 実装開始前の必須手順

`ocw` がすでに `msq-02-quota-per-model` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/meter-subagent-quota` の
先端から切られていることを確かめる（`git pull` は使わない）。

## やること

1. 計画書 設計2 の 1〜3 を実装する（モデル系統ごとの「週の 1% あたりのトークン」を推定する report。非負の最小二乗は標準ライブラリで書く）
2. 計画書 設計2 の 4 のとおり、孫3 の範囲の report に推定 % を足す
3. 計画書 設計2 の 5 の ADR を書く（`docs/adr/DOC-DOCID_PLACEHOLDER_*.md` で作って `./tools/doc-id/doc-id assign`）。`bin/ocw-meter` の
   ヘルプ文と `bin/README.md` も更新する
4. 計画書 設計2 の 6 の確かめを行い、結果を PR 本文に書く（実の保存先は書き換えない）

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 合成のデータで、既知の「1% あたりのトークン」が推定で戻る
- データが足りない・ぶれが大きい系統で、数字ではなく「測れない」が出る（誤った数字を自信ありげに出さない）
- `claude-*` 以外のモデルが推定に混ざらない
- 範囲の report の推定 % の列が、推定できない系統で空欄になる
- 既存の `report` の出力が変わらない（既存テストで守られていればよい）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
python3 -m unittest discover -s bin/tests -v > "$(mktemp -d)/unittest.log" 2>&1; echo $?
pre-commit run --all-files
./tools/doc-id/doc-id verify
```

（unittest の出力は長いので一時ファイルへ書き出し、`tail` で結果だけ見る）

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `meter-subagent-quota` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** `/pr-review-loop` の手順にマージへ進む記述があっても実行しない
   （孫が人間のフィードバック前に勝手にマージするのを防ぐため。マージは傘の司令官が行う）
5. 最終報告を書き終えたら、最後の行動として、司令官が spawn の送信文で渡した司令官の Herdr ペインへ
   承認を報告する（渡されていなければ報告せず、人間に「承認済み。マージは司令官（または人間）が行う」と伝えて止まる）。
   送り方は umbrella-orchestrator スキル §5「AI間送信手順（二段構え）」に従う。本文は
   「孫2 `msq-02-quota-per-model` の PR #<番号> が HEAD <短縮SHA> で承認されました。マージをお願いします。」
   だけにする。報告は1回だけ。送れなくても再送せず、送れなかったことを人間に1行伝えて止まる

なお `/pr-review-loop` は、レビューを依頼した直後の区切りで文脈が大きければ `ocw self-compact` で
自分を compact する（その手順は pr-review-loop 側。使えなければ何もしない）。compact の後は、
復帰メモに従ってレビュー待ちに戻り、この「実装完了後の流れ」を最後まで続けること。
実装の途中でも、検証が通ってコミットした直後の区切りで、文脈が
200,000 トークンを超えていれば `ocw self-compact` で自分を compact してよい（WIP のコミットは
区切りでない。指摘対応の修正の途中は対象外。1 PR につき多くて 3 回。ADR DOC-2610142337）。
測り方は `/pr-review-loop` の「区切りでの自己 compact（実装側のみ）」の手順1のコマンドと同じ（その節の (3) の項だけを読めばよい。
手順の「Phase 3 へ進む」は実装途中には当てはまらない）。復帰メモ（リポの外の一時ファイル）には、計画書のパスと孫の節・
済んだこと（コミットの一覧）・作業中に下した判断とその理由・残り・次の一手・検証コマンド・実装途中の compact の回数を書き、
先頭に「計画書の続きから実装を再開する。レビュー待ちではない」と書く。コマンドを実行したらそのターンを終える。
使えない・拒否・失敗なら何もせず実装を続ける（人間に提案もしない）。
実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。
傘ブランチが先へ進んでコンフリクトしたら `git rebase origin/meter-subagent-quota` と
`git push --force-with-lease` で追随する（AGENTS.md「最重要ルール」）。

## 大きい出力を文脈へ流し込まない（実装中ずっと）

文脈の膨張は、1k〜20k字級の出力の積み重ねと、自分で書く長い出力で起きる。次を守ること:
- ファイルを `cat` / `sed -n` で丸ごと読まず、`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む
  （`bin/ocw-meter` は約 6,000 行、`bin/tests/test_ocw_meter.py` は約 5,000 行ある）
- 約100行・5,000字を超えそうな出力（テスト・分析・ログ・`git diff`・JSON）は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る
- 既存の長いファイルや、繰り返し直して実行するスクリプトを Write / heredoc で丸ごと書き直さない。一度ファイルに置き、変更は Edit の差分で行う（新規ファイルを最初に1回書くのは構わない）

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `meter-subagent-quota` から切ること**。master から切ると PR の diff に傘ブランチ全体が
混入してレビュー不能になる。`ocw` が `origin/meter-subagent-quota` から切ったワークツリーを用意済みなので、
上の「実装開始前の必須手順」で確かめるだけでよい（`git pull` は使わない）。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

## 孫3用プロンプト:

````markdown
# 傘ブランチ: meter-subagent-quota
# 孫ブランチ: msq-03-range-report
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/meter-subagent-quota/docs/planning/DOC-2610310205_meter-subagent-quota_計画.md`

**まず計画書の「概要」「背景3」「背景4.3」「設計3」「決定的な制約」「スコープ外」「必須の検証ステップ」
「テスト方針」「進行記録」を読むこと。** 続けて dotfiles の `AGENTS.md` の作業別の索引から、テスト（DOC-2610150520-a）・
コミット前（DOC-2610150520）を読む。

## 実装開始前の必須手順

`ocw` がすでに `msq-03-range-report` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/meter-subagent-quota` の
先端から切られていることを確かめる（`git pull` は使わない）。

## やること

1. 計画書 設計3 の 1〜4 を実装する（`report --since` / `--until` で範囲のモデル別トークンと費用を出す。自動 ingest には範囲を渡さない）
2. 計画書 設計3 の 6 のとおり、ヘルプ文と `bin/README.md` を更新する
3. 実データ（`OCW_METER_HOME` は実の保存先を読み取りだけで使い、`--no-ingest` を付ける。または `mktemp -d` へコピーして使う）で、
   適当な数時間の範囲を出した結果を PR 本文に書く
4. 推定 % の列は足さない（孫2 が足す。設計3 の 5）。孫2 が足しやすいよう、範囲の集計を1つの関数にまとめておく

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 範囲の境界の `usage.message` の扱いが決まっていて（`--since` ちょうどは含む等）、範囲外が入らない
- 不正な時刻の指定で、分かるエラーになる
- 自動 ingest のカーソルが範囲の指定に影響されない
- 既存の `report` の出力が変わらない（既存テストで守られていればよい）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
python3 -m unittest discover -s bin/tests -v > "$(mktemp -d)/unittest.log" 2>&1; echo $?
pre-commit run --all-files
./tools/doc-id/doc-id verify
```

（unittest の出力は長いので一時ファイルへ書き出し、`tail` で結果だけ見る）

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `meter-subagent-quota` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** `/pr-review-loop` の手順にマージへ進む記述があっても実行しない
   （孫が人間のフィードバック前に勝手にマージするのを防ぐため。マージは傘の司令官が行う）
5. 最終報告を書き終えたら、最後の行動として、司令官が spawn の送信文で渡した司令官の Herdr ペインへ
   承認を報告する（渡されていなければ報告せず、人間に「承認済み。マージは司令官（または人間）が行う」と伝えて止まる）。
   送り方は umbrella-orchestrator スキル §5「AI間送信手順（二段構え）」に従う。本文は
   「孫3 `msq-03-range-report` の PR #<番号> が HEAD <短縮SHA> で承認されました。マージをお願いします。」
   だけにする。報告は1回だけ。送れなくても再送せず、送れなかったことを人間に1行伝えて止まる

なお `/pr-review-loop` は、レビューを依頼した直後の区切りで文脈が大きければ `ocw self-compact` で
自分を compact する（その手順は pr-review-loop 側。使えなければ何もしない）。compact の後は、
復帰メモに従ってレビュー待ちに戻り、この「実装完了後の流れ」を最後まで続けること。
実装の途中でも、検証が通ってコミットした直後の区切りで、文脈が
200,000 トークンを超えていれば `ocw self-compact` で自分を compact してよい（WIP のコミットは
区切りでない。指摘対応の修正の途中は対象外。1 PR につき多くて 3 回。ADR DOC-2610142337）。
測り方は `/pr-review-loop` の「区切りでの自己 compact（実装側のみ）」の手順1のコマンドと同じ（その節の (3) の項だけを読めばよい。
手順の「Phase 3 へ進む」は実装途中には当てはまらない）。復帰メモ（リポの外の一時ファイル）には、計画書のパスと孫の節・
済んだこと（コミットの一覧）・作業中に下した判断とその理由・残り・次の一手・検証コマンド・実装途中の compact の回数を書き、
先頭に「計画書の続きから実装を再開する。レビュー待ちではない」と書く。コマンドを実行したらそのターンを終える。
使えない・拒否・失敗なら何もせず実装を続ける（人間に提案もしない）。
実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。
傘ブランチが先へ進んでコンフリクトしたら（孫1 が同じ `bin/ocw-meter` を並行して触っている）、`git rebase origin/meter-subagent-quota` と
`git push --force-with-lease` で追随する（AGENTS.md「最重要ルール」）。

## 大きい出力を文脈へ流し込まない（実装中ずっと）

文脈の膨張は、1k〜20k字級の出力の積み重ねと、自分で書く長い出力で起きる。次を守ること:
- ファイルを `cat` / `sed -n` で丸ごと読まず、`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む
  （`bin/ocw-meter` は約 6,000 行、`bin/tests/test_ocw_meter.py` は約 5,000 行ある）
- 約100行・5,000字を超えそうな出力（テスト・分析・ログ・`git diff`・JSON）は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る
- 既存の長いファイルや、繰り返し直して実行するスクリプトを Write / heredoc で丸ごと書き直さない。一度ファイルに置き、変更は Edit の差分で行う（新規ファイルを最初に1回書くのは構わない）

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `meter-subagent-quota` から切ること**。master から切ると PR の diff に傘ブランチ全体が
混入してレビュー不能になる。`ocw` が `origin/meter-subagent-quota` から切ったワークツリーを用意済みなので、
上の「実装開始前の必須手順」で確かめるだけでよい（`git pull` は使わない）。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````
