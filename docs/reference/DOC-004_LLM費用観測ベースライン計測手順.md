# DOC-004: LLM費用観測ベースライン計測手順

`ai/llm-cost-observability`傘（孫1〜5）で構築した観測基盤（`ocw-meter`）を使って、
実PR 5〜10本の「観測基盤導入後の最初のベースライン」を取る手順。
計画書 `docs/planning/DOC-003_ai-llm-cost-observability_計画.md` 第15章を実行可能な粒度へ落とし込んだもの。

**目的**: 最適化案（第16章「Future experiments」）を評価する前に、まず「今の運用が実際どうなのか」を
数字で確定する。**このベースラインが揃うまで、最適化は一切実装しない**（計画書§2「最適化案を
評価する物差しが無いまま最適化を実装するのは、賭けであって改善ではない」）。

本文書中のコマンド出力例はすべて、この文書を書く時点で実際にこのマシンの実ストア
（`~/.local/state/ocw-meter`）に対して実行した結果（一部は数値を丸めている場合がある）。
架空の出力ではない。

---

## 1. 前提条件

- 孫1〜5（`bin/ocw-meter`本体・工程イベント埋め込み・DeepSeek ingest・Claude quota・本レポート機能）が
  すべて`master`にマージ済みであること
- `bin/deploy.sh`を実行し、`~/bin/ocw-meter`が配置され、`~/bin`がPATHに入っていること
  （確認: `which ocw-meter`）
- `claude/settings.json`の`statusLine`が`ocw-meter snapshot-quota`を指していること
  （確認: `claude/README.md` §3.4、または`cat ~/.claude/settings.json | grep statusLine`）
- **計測期間中、フロー・規約・モデル構成を一切変更しない。** 具体的には:
  - `claude/skills/pr-review-loop/SKILL.md`のレビュー基準を変更しない
  - implementer/reviewerのモデル構成（計画書§12「spawn時のペイン構成」）を固定する。
    計測開始時点の構成を本文書末尾（§8）に記録すること
  - `OCW_METER_QUOTA_INTERVAL`等の環境変数を計測期間中に変更しない
- 観測が壊れていないことの事前確認:

  ```bash
  ocw-meter report
  # coverage: / completeness: / quarantined: の行が出ることを確認。
  # quarantined行数が異常に多い場合は計測開始前に原因を調査すること
  ```

---

## 2. 計測対象と各PRでの手順

**対象: 実PR 5〜10本**（規模がばらけているのが望ましい。小さいドキュメント修正から
複数ラウンドのレビュー往復が発生する実装まで混在させる）。

### 2.1 各PRのライフサイクルでの手順

**特別な操作は一切しない。** 通常どおり`ocw -H`→実装→`/pr-review-loop`を回すだけでよい。
観測はfail-openなイベント埋め込みと事後の`ingest`で完結する。

1. 通常どおりPRを開始する:
   ```bash
   ocw -H <孫ブランチのslug> <ベースブランチ>
   ```
2. 通常どおり実装・`/pr-review-loop`を実行する。**工程イベントは`ocw`/`pr-review-loop`が
   自動的に発火する**（呼び出し側で何もする必要はない）
3. **⚠️ PRがマージされ、worktreeを`ocw rm`する前に、必ず`ocw-meter ingest`を実行する:**

   ```bash
   ocw-meter ingest
   ```

   これは孫5で実データ検証して判明した制約への対策（`docs/reference/DOC-005_ocw-meterイベントスキーマ.md`
   §2.4参照）: `usage.message`の`run_id`は「そのメッセージの`cwd`（worktreeパス）配下の
   `<git-dir>/ocw-run-id`ファイルを**ingest実行時点**で読む」方式で解決される。`ocw rm`は
   そのファイルをworktreeごと削除するため、**worktree削除後にingestすると、そのPRのメッセージは
   `run_id: null`のまま永久に保存される**（後から再ingestしても直らない — 「過去は再計算しない」
   不変条件のため）。`run_id`が無いと`report --phase`（工程別トークン内訳）がそのPRの分を
   `(unassigned)`にしか計上できなくなる。**`--model`/`--role`/`--pr`自体はこの制約の影響を
   受けない**（`run_id`ではなく`model`/`role`/`pr_number`を直接見るため）が、工程別の粒度で
   分析したいなら、worktreeが生きている間のingestが必須
4. PRがマージされたら、そのPRのスナップショットを保存する:

   ```bash
   ocw-meter ingest
   ocw-meter report --pr <N> > /tmp/pr-<N>-report.txt
   ocw-meter report --pr <N> --json > /tmp/pr-<N>-report.json
   ```

5. worktreeを片付ける（通常どおり）:
   ```bash
   ocw rm <孫ブランチのslug>
   ```

### 2.2 実行結果の例（このマシンの実PRに対する実行）

```
$ ocw-meter report --pr 31
storage root:  /home/manemone/.local/state/ocw-meter
filter:        pr=31
total events:  127
  quota.sample: 15
  usage.message: 112
completeness: complete 98.4% / partial 1.6% / unknown 0.0%
quarantined:   0 lines (events this meter wrote)
transcript lines quarantined (ingest source data): 2 lines
meter.error diagnostics (state/meter-errors.jsonl): 2 lines
malformed (not yet quarantined; run 'ocw-meter validate'): 0 lines
coverage:      112 usage.message event(s); run 'ocw-meter report --reconcile' for model別 coverage against provider totals
price_table:   deepseek-2026-08-01
cost_basis:    estimated
cost_estimate: $0.13 (estimated — not an invoice)
five_hour_window_completion: no (window_ids seen: 1785629075, 1785632400)
duration_seconds: 2234706.305
review_round_count: 0
human_intervention_count: 0
final_result: unknown
cash_cost_usd: $0.1318
capacity_message_count (claude subscription, no dollar figure): 0
```

`review_round_count: 0`や`final_result: unknown`のように「取れていない」ものは`0`/`unknown`で
はっきり出る（推測で埋めない、が全体方針 — `docs/reference/DOC-005_...`§5参照）。ベースライン集計時は
こうした欠損もそのまま記録し、後から「なぜこのPRは取れなかったか」を調べられるようにすること。

---

## 3. 月末の突合手順（coverage確定）

月が変わったら、DeepSeek管理画面の実績とtranscript由来の集計を突き合わせ、coverage比率を確定する。

1. DeepSeek管理画面（`https://platform.deepseek.com/`等、契約時のダッシュボード）から、
   対象月の **model別** の総トークン数を取得する（`deepseek-v4-pro` / `deepseek-v4-flash`）
2. 突合コマンドを実行する:

   ```bash
   ocw-meter report --reconcile --month 2026-08 \
     --provider-total deepseek-v4-pro=<管理画面のtotal> \
     --provider-total deepseek-v4-flash=<管理画面のtotal> \
     --json
   ```

3. 出力の`models.<model>.coverage_ratio`を記録する。**既知のギャップ**
   （`known_gaps`フィールドに毎回併記される）:
   - `deepseek-v4-flash`はtranscriptに一切記録されない（実測カバー率0%。バックグラウンドの
     タイトル生成・サブエージェント呼び出しがtranscriptに現れないため）
   - `deepseek-v4-pro`のtranscriptカバー率は実測で約89%（ADR-001 §2.2）。残り約11%は
     streaming中断/retryで課金されたが記録されない分などが要因
   - 月境界は**UTC固定**。DeepSeek管理画面が北京時間（UTC+8）集計の場合、月初・月末で
     最大±8時間分のずれが生じうる
4. `--month`（`--reconcile`無し）で、cash/capacity/process efficiencyの月次サマリも保存する:

   ```bash
   ocw-meter report --month 2026-08 --json > /tmp/month-2026-08.json
   ```

   実行例（cash costとcapacity costが別セクションであることを確認する）:

   ```
   $ ocw-meter report --month 2026-08
   month:         2026-08
   cash cost (metered API — currently DeepSeek only):
     usage.message count: 4931
     cash_cost_usd:       $0.19 (estimated — not an invoice)
   capacity cost (Claude subscription quota — never summed with cash cost):
     capacity_message_count: 4750
     quota_sample_count: 74
     five_hour_used_pct_max: 71
     seven_day_used_pct_max: 78
     distinct_five_hour_windows: 2
   process efficiency (approved PRs in 2026-08):
     approved_pr_count: 1
     avg_cash_cost_usd: None
     avg_review_round_count: 3.0
     avg_human_intervention_count: 0.0
     avg_duration_seconds: 2261934.57
     five_hour_window_completion_breakdown: {'yes': 0, 'no': 1, 'unknown': 0}
   quality_guardrail: 未計測 — 第一段階では収集項目が無い（計画書16章）。defect.escaped 等のevent_typeを将来追加可能
   ```

   `avg_cash_cost_usd: None`のように承認済みPR個別の値が欠損する場合がある
   （そのPRのusage.messageに`pr_number`/`run_id`が正しく紐付かなかった場合。§2.1の
   ingestタイミングの徹底で改善する）。これも「取れなかった」事実として、埋めずにそのまま記録する

---

## 4. 集計テンプレート

5〜10本のPRが揃ったら、以下の表に手で書き写す（`--json`出力からスクリプトで生成してもよいが、
第一段階では手動集計で十分な規模— 計画書§9.1参照）。

### 4.1 PR別

| PR# | 承認までの所要時間 | レビューラウンド数 | 各ラウンドの指摘数 | 人間介入回数 | 推定API費(cash) | 5h枠消費 | 同一窓完走 | 最終結果 |
|---|---|---|---|---|---|---|---|---|
| 31 | (`duration_seconds`/3600 h) | (`review_round_count`) | (`review_rounds[].findings_count`) | (`human_intervention_count`) | (`cash_cost_usd`) | — | (`five_hour_window_completion`) | (`final_result`) |
| ... | | | | | | | | |

`ocw-meter report --pr <N> --json`の該当フィールドをそのまま転記する。

### 4.2 工程別

| phase | 合計所要時間 | window数 | miss入力 | hit入力 | 出力 | 推定費用 |
|---|---|---|---|---|---|---|
| pr_create | | | | | | |
| self_review | | | | | | |
| review_request | | | | | | |
| review_wait | | | | | | |
| fix | | | | | | |
| reply | | | | | | |
| ... | | | | | | |
| (unassigned) | | | | | | |

`ocw-meter report --phase --json`の`by_phase`をそのまま転記する。**`(unassigned)`の割合が
大きい場合、§2.1のingestタイミングが守られていない可能性が高い** — その旨を注記すること。

### 4.3 model別 / role別

`ocw-meter report --model --json` / `ocw-meter report --role --json`をそのまま転記する。

### 4.4 5時間窓別

`ocw-meter report --window --json`の`by_window`をそのまま転記する。`prs_direct_link`
（statusLineの`pr`フィールドから直接紐付いたPR）と`prs_time_overlap`（イベント時刻範囲の
重なりからのベストエフォート推定）は別々の列にすること — 前者の方が信頼度が高い。

### 4.5 月次サマリ

§3の`--month`出力をそのまま転記する。cash costとcapacity costは**別の行・別の単位**で書き、
一つの合計値に混ぜない。

---

## 5. 必ず答える5つの問い（計画書§15.3）

集計が揃ったら、以下5問に**この計測で得た数字を根拠に**回答する。「わからない」も正直な回答として許容する
（推測で埋めない）。

1. **DeepSeek代の何割が初回実装 / 自己レビュー / 修正往復か** — §4.2の工程別表から
   `implement`（＝`(unassigned)`。§2.3節参照）/ `self_review` / `fix`の`cost_estimate_usd`の
   構成比を出す
2. **Claude 5時間枠の何割が初回レビュー / 再レビュー / 別設計作業か** — §4.4の窓別表と§4.2の
   工程別表を突き合わせ、`review_request`/`rereview_request`ウィンドウの`five_hour_used_pct`の
   変化量で見積もる（`quota.sample`は差分ではなく各時点のスナップショットである点に注意 —
   `bin/README.md`「同一window_id内でのサンプル間の消費量差分は現時点では未実装」参照）
3. **1PRを同一5時間枠で完走できているか（完走率）** — §4.1の「同一窓完走」列の`yes`の割合
4. **Maxへ上げてDSを切った場合、総額はどう変わるか（推定シナリオ計算）** — §4.5のcash
   cost（DeepSeek実績）をベースに、Claude Max価格と現在のDeepSeekトークン量から試算する
   （試算であり実額ではないことを明記する）
5. **どの最適化候補を最初に試すべきか** — 上記1〜4の結果と計画書§16「Future experiments」の
   案A/B/Cを照らし合わせて選ぶ。**この時点で初めて最適化候補を評価する**（計画書§2の方針）

---

## 6. 比較実験の事前基準（計画書§16、固定して結果を見てから変更しない）

ベースライン計測後に**別の傘ブランチ**で最適化案（A/B/C）を比較する際の合格基準。
**この基準は本文書に記載した時点で確定し、実験結果を見てから変更しない。**

- API変動費 30%以上減
- Claude利用枠消費 20%以上減
- 人間介入が増えない
- blocking defectの見逃しが増えない
- 完了時間が悪化しない

比較指標: API費/承認済みPR、5h枠消費/承認済みPR、同一窓完走率、週間枠消費、blocked時間、
レビューラウンド数、人間介入、所要時間、品質guardrail（現状「未計測」— §7参照）。

**基準の固定方法**: 実験傘ブランチを開始する際は、本文書のこの節の commit hash を引用して参照すること。
**実験結果を見てから閾値を編集するPRは、「基準変更」であることをPRタイトル・説明文で明示した
独立PRとしてのみ許可する（実験結果のPRと同一PRで変えない）。** これを破ると、都合の良い基準へ
後付けで動かす余地が生まれ、比較実験そのものの意味が無くなる。

---

## 7. 品質guardrailについて（現状の限界）

第一段階では品質guardrail（レビューの見逃し・回帰の有無）を測る収集項目が無いため、
「未計測」として扱う。`ocw-meter report`の全出力に`quality_guardrail: 未計測 ...`という
文言が出るのはこのため（推測や代理指標で埋めていない）。

将来必要になった場合、`event_type`の追加だけでschemaを後付けできる設計になっている
（`docs/reference/DOC-005_...`§6「schema_versionの変更ルール」参照）:
`defect.escaped`（マージ後に発覚した重大問題）/ `revert.occurred` / `followup_fix.pr` /
`ci.failed` / `human.found_issue`。

---

## 8. 計測開始時点の構成（記入すること）

計測を開始する前に、以下を埋めて本文書に残すこと（実験比較時に「何と比べていたか」を追えるように）。

| 項目 | 値 |
|---|---|
| 計測開始日 | (記入) |
| 計測対象PR数の目標 | 5〜10 |
| implementerモデル構成 | (例: `claude --model sonnet --permission-mode auto`) |
| reviewerモデル構成 | (例: `claude --model opus --effort high --permission-mode auto`) |
| `OCW_METER_QUOTA_INTERVAL` | (既定60秒のままか、変更しているか) |
| pr-review-loop バージョン | (SKILL.mdの該当commit hash) |

---

## 9. 関連文書

- 設計の経緯・意思決定の背景: `docs/planning/DOC-003_ai-llm-cost-observability_計画.md`
- feasibility probeの実測結果: `docs/adr/ADR-001_llm-cost-observability-collection-method.md`
- イベントスキーマの恒久リファレンス: `docs/reference/DOC-005_ocw-meterイベントスキーマ.md`
- CLIの使い方全般: `bin/README.md` §3.3
