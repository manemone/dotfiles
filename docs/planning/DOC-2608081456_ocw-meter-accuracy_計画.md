# 計画書: `ocw-meter` の計測精度の是正

傘ブランチ: `ocw-meter-accuracy`
ターゲット: `master`
作成日: 2026-08-08

## 概要

`ocw-meter` は「観測基盤としては動いているが、出している数字が事実とズレている」状態にある。
このマシンの実ストア（`~/.local/state/ocw-meter`、events 68MB / 62,763件）を transcript と
実際に突合した結果、6つの問題が確認された。本傘でこの6つをすべて解消する。

**この計画書に書かれた数値はすべて実測済みである。孫は再調査しなくてよい**（するなら
それは検証であって発見ではない）。**逆に、ここに書かれていない数値を推測で補わないこと。**

対象コード: `bin/ocw-meter`（4,283行）/ `bin/tests/test_ocw_meter.py`（3,081行）/
`bin/prices/` / `bin/README.md` / `docs/reference/DOC-2608021229-c_ocw-meterイベントスキーマ.md`

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `ocw-meter-01-store-hygiene` | 【4】【6】テストによる実ストア汚染の停止・`quota-worktree-refusal.json` のプルーニング片手落ち修正・診断ファイル専用の掃除サブコマンド新設 | 🔄 実装中 |
| 2 | `ocw-meter-02-ingest-freshness` | 【1】`report` からの ingest 自動実行と、最終 ingest 時刻・鮮度のフッター表示 | ⬜ 待機中 |
| 3 | `ocw-meter-03-price-tables` | 【5】価格表スキーマの時間帯（peak/off-peak）対応・フォールバック時の警告・適用期間ミスマッチの可視化 | ⬜ 待機中 |
| 4 | `ocw-meter-04-list-price-equiv` | 【2】`quota.sample` の `session_cost_usd` から `list_price_equiv_usd` を集計して `report` に出す | ⬜ 待機中 |
| 5 | `ocw-meter-05-session-attribution` | 【3】`session_id` join による `run_id` / `role` の帰属解決（ingest 側フォールバック + report 側 join）と attribution 行 | ⬜ 待機中 |
| 6 | `ocw-meter-06-docs` | 文書（`bin/README.md` / スキーマ文書 DOC-2608021229-c / ADR DOC-2608021229 への追記節 / ルート `README.md`） | ⬜ 待機中 |

**ブランチ名に `ai/` 接頭辞は付けない。** PR #54（DOC-2608062258）で `ocw` の `ai/` 接頭辞は
廃止済みであり、傘ブランチ自体も `ocw-meter-accuracy`（接頭辞なし）である。
`ocw -H <孫ブランチ名> ocw-meter-accuracy` には上表の「ブランチ」列の値をそのまま渡すこと。

## 依存関係と実行順序

```
孫1 (ストア衛生: テスト汚染の停止 + refusal プルーニング + 診断掃除)
  ↓ 以後の孫がテストを回すたびに実ストアが汚れるのを先に止める
孫2 (ingest 自動実行 + 鮮度表示)
  ↓ 欠測を塞いでから、その上に乗る数字の意味を直す。孫5 と同じ ingest 経路を触るので先に入れる
孫3 (価格表: 時間帯対応 + フォールバック警告)
  ↓ compute_cost() のシグネチャが変わる。build_usage_event() を触る孫5 より前に入れる
孫4 (list_price_equiv: quota.sample 集計)
  ↓ report のフッター/月次/PR出力に行が増える。孫5 の attribution 行はその上に足す
孫5 (session_id join による帰属解決)
  ↓ 挙動が全部確定してから文書を書く（先に書くと必ず嘘になる）
孫6 (文書)
```

**全孫が直列。** 6本とも同じ `bin/ocw-meter`（単一ファイル4,283行）と
`bin/tests/test_ocw_meter.py` を触るため、並列に走らせると衝突が避けられない。
**前の孫が傘へマージされてから次を spawn すること。**

---

## 調査で判明した事実（実測。再調査不要）

### 計測の仕組み（前提の共有）

| 系統 | 入口 | 内容 |
|---|---|---|
| `usage.message` | `ocw-meter ingest` が `~/.claude/projects/*/*.jsonl` を走査 | トークン4種・model・推定費用。`message.id` で重複排除、`state/ingest-cursor.json` に (inode,size,mtime,offset) で増分・冪等 |
| 工程イベント | `bin/ocw:19` の fail-open 呼び出し | `run.start` / `phase.start`/`end` / `review.round` / `pr.bind` |
| `quota.sample` | `claude/settings.json` の statusLine → `snapshot-quota` | 5時間枠・週間枠の使用率、`window_id`、ctx%、**`session_cost_usd`**。60秒スロットル |

費用計算式は `bin/ocw-meter:2717`（`compute_cost`）。`claude-*` は定額契約なので一律
`cost_estimate_usd: null` / `cost_basis: "subscription"`（`bin/ocw-meter:2693`）。

### 【1】ingest が手動のみ → 直近4日分が丸ごと欠落（最重要）

`state/ingest-cursor.json` の最終更新が **2026-08-05 02:50**。transcript と events を
`message.id` で突合した実測:

```
transcript の distinct message.id : 60,460
events の distinct message_id     : 57,164
未取り込み                        : 6,878 件（全体の 11.4%）
  内訳 8/04:1312  8/05:610  8/06:2477  8/07:1407  8/08:1072
```

`phase.start` / `run.start` は 8/8 まで流れ続けているため、
**「工程は記録されているのにトークンだけゼロ」という歪んだ月次が出る。**

`report` にも `report --month` にも「最後に ingest したのはいつか」を示す行が一切ない
（`usage_cost_footer()` = `bin/ocw-meter:1514` は件数と `--reconcile` の案内だけ）。

**計画書 DOC-2608021229-a:440 は ingest の実行契機を「手動 / `report` が自動実行」と
書いているが、`cmd_report()`（`bin/ocw-meter:2284-2534`）に ingest 呼び出しは1つも無い。**
計画書と実装の食い違いが、そのまま欠測になっている。

### 【2】費用メトリクスが「もう使っていないプロバイダ」専用になっている

月別・モデル別の実測:

```
2026-06  cost=$0.00   claude-opus-4-8:327
2026-07  cost=$46.78  deepseek-v4-pro:29676 / claude系:9390
2026-08  cost=$1.34   claude系:16750 / deepseek-v4-pro:918   ← 95%がClaude
```

`OCW_*_COMMAND` の既定が `claude` になった今、**メッセージの46%（26,467件）は設計上ずっと
`cost_estimate_usd: null`**。看板の `$48.12` は事実上7月の DeepSeek 代。
`report --month` の process efficiency も **`avg_cash_cost_usd: None`**（承認済み8PR全部）。

### 【3】`--phase` / `--role` がほぼ機能していない

```
run_id が入っている usage.message : 3,043 / 57,164 (5.3%)
role=unknown                      : 51,959 / 57,164 (90.9%)
report --phase の (unassigned)    : 56,648 / 57,164 (99.1%)
```

原因は共通で、**解決タイミングが「ingest 実行時点のライブ状態」だから**。

- `run_id`: `cwd` 配下の `<git-dir>/ocw-run-id` を読む（`resolve_run_id_via_ocw_run_id_file`
  = `bin/ocw-meter:3041`）→ `ocw rm` 済みなら消えている
- `role`: `herdr pane list`（`bin/ocw-meter:2954`）→ ペインを閉じていたら引けない

しかも「過去は再計算しない」不変条件があるため、**後から ingest し直しても永久に直らない。**

### 【4】テストが実ストアを汚染している（純粋なバグ）

`bin/tests/test_ocw_meter.py:2149`
`test_git_worktree_home_refuses_write_but_still_prints_display` が `HOME` を上書きしていない。
ヘルパ `run_snapshot_quota()`（同 :78）は `dict(os.environ)` ベースなので実 `HOME` が素通りし、
`default_storage_root()` が実 `~/.local/state/ocw-meter` を指して退避キャッシュを書く。

証拠（実ストアに現存）:

```
state/quota-worktree-refusal.json
  → "/tmp/tmp0aymq67u/repo/ocw-meter-home": "2026-08-06T15:05:04Z" ... 計37件
state/meter-errors.jsonl
  → storage_home_inside_git_worktree × 6件（8/1〜8/7）
```

パス形状 `<tmpdir>/repo/ocw-meter-home` がそのテストと完全一致。
**同ファイル :2895 の兄弟テスト `test_worktree_refusal_is_throttled_and_stops_rewarning` は
「HOME を上書きしないとこの開発者の実 `~/.local/state/ocw-meter` を触ってしまう」という
コメント付きで正しく `extra_env={"HOME": str(fake_home)}` を渡している**ため、片方が漏れている
だけである。

副作用: `report` の「meter.error diagnostics: 7 lines」のうち **6件がテストのゴミ**で、
自己診断シグナルが濁っている。

### 【5】価格表の適用が実態とズレている

`bin/prices/` に `deepseek-2026-08-01.json` の**1枚しかない**。
`select_price_table()`（`bin/ocw-meter:2673`）は「`effective_date <= 対象日` の最新」を選ぶが、
該当が1枚も無いときは `tables[0]`（＝最古の表）にフォールバックする。
唯一の表の `effective_date` が `2026-08-01` なので、**6月〜7月の29,676件も8月の価格表で
計算されている**（`$46.78` はその前提の数字）。フォールバックしたことは出力のどこにも出ない。

さらにその表の `notes` に
`peak/off-peak 2x pricing announced (Beijing 09:00-12:00, 14:00-18:00) — effective date TBD`
とあるが、価格表の粒度は**日単位**（`effective_date`）なので、これが発効したら時間帯を
表現する手段が無い。最大2倍の過小計上になる構造。

### 【6】細かいもの

- **`quota-worktree-refusal.json` のプルーニングが片手落ち**（`bin/ocw-meter:3999` 付近）。
  24時間超（`QUOTA_SESSION_STATE_MAX_AGE_SECONDS`）の古いエントリを消すのは
  **新しい refusal を書き込む瞬間だけ**なので、汚染が止まると古いエントリが残り続ける
  （現に 8/6〜8/7 の37件が居座っている）
- **`<synthetic>` が103件混入**（本傘のスコープ外。人間の判断で見送り）
- **`five_hour_window_completion` が実質ノイズ**（本傘のスコープ外。人間の判断で見送り）
- **`prune` 未実装**（本傘のスコープ外。`bin/README.md:457` の意図的据え置きを維持する）
- **`bin/README.md:525` の記述が古い**。「run_id が設定されているものは0件」→ 実測3,043件

### 問題なかったもの（再調査不要）

- `validate` 0件、malformed 0行。`message.id` 重複排除は正しく機能
  （transcript の assistant 135,926行 → 60,460 distinct = 重複59.4%）
- transcript 側の壊れた行の隔離は2件のみ。生コンテンツを保存せず reason だけ残す実装は妥当
- fail-open 契約（`event`/`bind-pr`/`snapshot-quota` は必ず exit 0）は実装・テストとも一貫
- `is_sidechain` が全件 False なのは `ocw-meter` のバグではない
  （transcript 側の assistant 行 135,926件すべてが `isSidechain: false`）

---

## 【2】【3】の鍵: 答えは既に `quota.sample` の中にある

**【2】【3】とも、新しく測り足す必要はない。**

### 材料A: `session_cost_usd` が実は全件埋まっている

`snapshot-quota` が statusLine の `cost.total_cost_usd` を `session_cost_usd` として記録している
（`bin/README.md:412` が「別カラムであり合算しない」と書いているもの）。
**これが 4,704 / 4,705 件で埋まっていて、しかもどのレポートにも一切出てこない。**

```
provider別（セッション累積の最大値を合計）
  anthropic : $2,995.36 / 205 sessions（全部 2026-08）
  deepseek  : $93.35    / 10 sessions

PR単位にも落ちる（anthropic セッション 140/205 に pr_number あり）
  PR #33: $103.36   PR #39: $126.94   PR #32: $58.14
  PR #41: $56.56    PR #28: $49.60    PR #35: $33.77 ...
```

→ **`report --month 2026-08` が `$1.34` と表示している裏で、同じストアに $2,995 分の
Claude 側自己申告コストが眠っている。**

### 材料B: `session_id` で join できる

`quota.sample` は `session_id` 100% / `run_id` 78% / `role` 78%（unknown 22%）を持つ。
`usage.message` も transcript 由来の `session_id` を100%持つ。
**両者を `session_id` で突き合わせるだけ**で、実測こうなる:

```
8/1以降（quota.sample 稼働後）の usage.message 17,670件
  run_id : 3,043 (17.2%)  ->  10,885 (61.6%)
  role   : 4,814 (27.2%)  ->  12,740 (72.1%)
```

**この join は `ocw rm` に一切影響されない。** 現行の
`resolve_run_id_via_ocw_run_id_file()`（`bin/ocw-meter:3041`）が
`<git-dir>/ocw-run-id` という *消える実ファイル* を見ているのが根本原因で、
`quota.sample` は *消えないイベント* なので、worktree を消した後でも遡って解決できる。

---

## 確定事項（人間が選択済み。孫の判断で覆さないこと）

| 領域 | 決定 |
|---|---|
| 【1】ingest | **`report` から ingest を自動実行する**（計画書 DOC-2608021229-a:440 の記述に実装を合わせる）。加えてフッターに最終 ingest 時刻と鮮度を出す |
| 【2】費用 | **A案: `quota.sample` の `session_cost_usd` を集計する。** 価格表に anthropic を足して自前計算する案（B）、サブスク月額を按分する案（C）は採らない |
| 【3】帰属 | **A+B 併用。** ingest 側フォールバック（B）と report 側 join（A）の両方を入れる。既存イベントを書き戻す `reattribute` 案（C）は採らない |
| 【4】汚染 | テスト側の `HOME` 上書き修正に加え、**掃除手段を `ocw-meter` に足す** |
| 【5】価格表 | **時間帯（peak/off-peak）課金に対応できるスキーマまで入れる。** 加えてフォールバック時の警告 |
| 【6】細部 | **`quota-worktree-refusal.json` のプルーニング修正のみ。** `<synthetic>` / `five_hour_window_completion` / `prune` は本傘のスコープ外 |
| ADR | **改訂は不要。** ただし「Anthropic 自己申告値は *換算* ではないので採用する」という線引きを**追記節として1つ足す**（孫6） |

### 検討して却下した案（蒸し返さないこと）

**【2】について:**

- **B「価格表に anthropic を足して `usage.message` 側で自前計算」** → 全期間を遡れるが、
  「定額契約を API 単価に換算しない」という ADR DOC-2608021229 の判断を覆す必要がある。
  なお B は A の後から足すこともできる（A は「Anthropic 自己申告値」、B は「ocw-meter 推定値」で
  意味の異なるカラムなので共存可能）。**最初から B 込みにすると ADR 改訂が必要になり傘が重くなる**
- **C「サブスク月額を按分」** → 実支払額と一致する唯一の方式だが、月末まで確定せず
  按分の分母が恣意的になる

**【3】について:**

- **C「`reattribute` サブコマンドで既存イベントを埋め直す」** → 保存値も過去も直るが、
  **「過去は再計算しない」不変条件を明示的に破る。** A（読み取り時解決）で同じ結果が得られる以上、
  不変条件を破ってまで書き戻す価値が薄い

**【4】について:**

- **「何もしない（テスト修正のみ）」** → 汚染は止まるが、`report` の
  「meter.error diagnostics: 7 lines」のうち6件がテストのゴミのまま残り、
  自己診断シグナルが濁った状態が続く
- **「README に手動削除手順を書くだけ」** → ツールが自分のストアを消す経路を作らずに済むが、
  診断ファイルの掃除という定型作業を毎回人間の手作業に落とすことになる

**【5】について:**

- **「フォールバック警告のみ」** → 数字の意味は変わらないまま。発効済みの時間帯課金を
  表現できない構造が残る

**【6】について:**

- `<synthetic>` の除外・`five_hour_window_completion` の再定義・`prune` の実装は、
  いずれも**本傘では扱わない**と人間が決めた。**孫が先回りして実装しないこと**
  （AGENTS.md「指示された範囲外の機能を先回りして実装しない」）

---

## 実装上の罠（絶対に踏まないこと）

ここに書かれた5点は**実測で判明した落とし穴**である。素直に実装すると必ず踏む。

### 罠1: `quota.sample` 由来の `run_id` に `run.start` 逆転チェックを適用してはいけない（孫5）

`build_usage_event()`（`bin/ocw-meter:3141`）付近には、`ocw-run-id` ファイルから引いた
`run_id` に対して「その `run_id` の `run.start` より前のメッセージなら捨てる」という
逆転チェックがある（`bin/ocw-meter:3186` 付近）。

**これは「worktree パスは再利用される」ことを前提にした stale path 対策であり、
`session_id` 由来の `run_id` に適用してはいけない。** `session_id` は再利用されないため、
かけると**正しい帰属まで null 化してしまう**。解決経路ごとにチェックの適用を分けること。

### 罠2: `deepseek` の `session_cost_usd`（$93.35）は絶対に混ぜない（孫4）

Claude Code が DeepSeek のモデル名に何の単価を当てているか不明であり、
`ocw-meter` 自身の推定 $48.12 と**二重計上**になる。
`provider == "anthropic"` で明示的にスコープすること。

`quota.sample` の `provider` フィールドは `infer_provider(model_normalized)`、
`model` が取れないときは `has_rate_limits` から `"anthropic"` にフォールバックして
決まっている（`bin/ocw-meter:4069` 付近）。DeepSeek セッションは `rate_limits` を持たないため、
`provider == "anthropic"` によるスコープはこの実装で正しく機能する。

### 罠3: `session_cost_usd` は非単調。`max()` ではなく「正の差分の総和」を取る（孫4）

**214セッション中26セッションで値が減少している**（累積のはずが非単調）。
`/clear` やコンパクションでリセットされていると思われる。単純な `max()` では
リセット前の分を取りこぼす。**`session_id` ごとに時系列でソートし、正の差分だけを合計する。**

上記の **$2,995.36 は `max()` による集計なので下振れした値**である。
正の差分の総和で取り直せば、これ以上の値になるはずである。

### 罠4: 必ず「下限値」として表示する（孫4）

最後の statusLine 描画以降の消費が入らないため、この数字は原理的に下限である。
`$2,995+ (下限・請求書ではない)` のような出し方にすること。
**cash cost と絶対に足さない**（現行の設計方針どおり維持）。

### 罠5: 過去の価格表を足しても、既に保存されたイベントの費用は直らない（孫3）

`cost_estimate_usd` は `ingest` 時点で計算されて**イベントに焼き込まれる**。
「過去は再計算しない」不変条件があるため、**6〜7月に有効だった価格表を後から
`bin/prices/` に足しても、既存の29,676件の `cost_estimate_usd` は変わらない。**

したがって孫3の実質的な価値は「過去表を足すこと」ではなく、次の3点にある:

1. **フォールバックしたことを黙らせない**（該当する価格表が無い期間の費用は概算であると明示する）
2. **時間帯課金を表現できる構造を用意する**（発効したときに慌てない）
3. **適用された `price_table_version` と対象期間のミスマッチを可視化する**

**孫3は「6〜7月の正しい DeepSeek 単価」を自分で調べて価格表を作ってはいけない。**
価格表は出典 URL 付きの一次情報であり、AI が記憶から書くと静かに嘘の数字が入る。
過去表の投入は**人間の作業**として手順だけ整備する。

---

## 残る限界（正直に書くこと。「直った」と言わない）

- **7月以前の帰属は救えない。** `quota.sample` が 8/1 開始のため、7月の29,676件
  （DeepSeek 時代）の `run_id` / `role` は復元手段が無い
- 8月でも `run_id` 61.6% / `role` 72.1% で100%にはならない。
  `claude-ds` セッションや statusLine が回らなかったセッションは取れない
- `role` の 22% unknown は Herdr 外で起動した Claude なので**原理的に取得不能**
  （推測で埋めない方針を維持する）
- **6〜7月の Claude 側コストは永久に不明。** `quota.sample` が無い期間である
- `list_price_equiv_usd` は常に下限値であり、請求書ではない

---

## 全孫共通の注意（プロンプトにも再掲するが、ここが正）

### 1. `AGENTS.md` の最重要ルールに従う

- **人間の明示的指示がない限り `git merge` / `git pull` / `git reset --hard` /
  `git push --force` / `gh pr merge` を実行しない。**
- **deploy スクリプトを実オペレーションで実行しない。** 本傘は `bin/` と `docs/` しか触らないが、
  `pre-commit` のフックが `./deploy-all.sh --dry-run` を走らせる点は変わらない。
- **linter の抑制ディレクティブ（`# shellcheck disable=...` 等）を AI の判断で追加しない。**
  指摘が設計上不合理だと判断したら、抑制せず内容・対象・理由を人間に報告する。
- **指示された範囲外の機能を先回りして実装しない。**

### 2. `bin/ocw-meter` は「bash スクリプトの中に Python が heredoc で埋まっている」

これを知らないと編集も lint も外す。

- shebang は `#!/usr/bin/env bash`、`set -uo pipefail`（**`-e` は意図的に付けていない**。
  fail-open 契約を手で管理しているため。`bin/ocw-meter:10` のコメント参照）
- Python 本体は `bin/ocw-meter:353` の `cat >"$_ocw_meter_py" <<'PY'` から `:4255` の `PY` まで。
  **クォート付き heredoc（`<<'PY'`）なのでシェル展開は起きない**が、行頭の `PY` を
  Python コード中に書くと heredoc がそこで終わる
- `bin/tests/lint.sh` はこの heredoc を `awk` で抽出して `py_compile` にかける。
  **shellcheck / shfmt（シェル部分）と `py_compile`（Python 部分）の両方が効く**
- macOS（BSD / bash 3.2）互換を壊さない。直近の PR #49 がまさにこの非互換の解消である

### 3. テストは黒箱。そして**実 `$HOME` を絶対に触らない**

`bin/tests/test_ocw_meter.py` は tempdir に使い捨てストアを作り、実 `bin/ocw-meter` を
subprocess で叩く方式。**この方式を変えない。**

**本傘の主題そのものだが、新しく書くテストでも同じ穴に落ちないこと。**
`run_meter()` / `run_snapshot_quota()` は `dict(os.environ)` ベースなので、
`OCW_METER_HOME` を tempdir に向けても**実 `HOME` は素通りする**。
`default_storage_root()`（`bin/ocw-meter:698`）や `emit_meter_error()` のフォールバック先は
`HOME` から組み立てられるため、**`HOME` を明示的に上書きしないと実ストアに書き込む**。

### 4. 検証（省略しない。省略してよいのは人間が明示的に指示した場合のみ）

```
pre-commit run --all-files
bin/tests/lint.sh
python3 -m unittest discover -s bin/tests -v      # 193件・約40秒（本傘で増える）
```

**テストを回したあとに、実ストアが汚れていないことを確認すること:**

```
git -C ~/.local/state/ocw-meter status 2>/dev/null || true
python3 -c "import json,pathlib; p=pathlib.Path.home()/'.local/state/ocw-meter/state/quota-worktree-refusal.json'; print(len(json.loads(p.read_text())) if p.exists() else 'absent')"
```

### 5. 「推測で埋めない」がこのツールの根本方針

補完・推定・下限値は、**そうであることを出力に明示する**こと。
黙って数字を良く見せる変更は、たとえ正確でも本ツールの方針に反する。

### 6. PR の作法

[docs/design/DOC-2608020715_プルリクエストの作法.md](../design/DOC-2608020715_プルリクエストの作法.md)
を PR 作成前に読むこと。
**PR の向き先は必ず傘ブランチ `ocw-meter-accuracy`。`master` には出さない。**

---

## 孫1用プロンプト:

````
`ocw-meter` のストア衛生を直してください（テストによる実ストア汚染の停止・
`quota-worktree-refusal.json` のプルーニング片手落ち修正・診断ファイル専用の掃除サブコマンド新設）。

## 最初に読むもの（順番に）

1. リポジトリルートの `AGENTS.md`（最重要ルール）
2. `docs/planning/DOC-2608081456_ocw-meter-accuracy_計画.md`（この計画書。
   「調査で判明した事実」の【4】【6】、「確定事項」、「全孫共通の注意」を必ず読む）
3. `docs/reference/DOC-2608021229-c_ocw-meterイベントスキーマ.md`
4. `bin/ocw-meter`（4,283行。特に `default_storage_root`:698 / `emit_meter_error` /
   `load_worktree_refusal_state` / `save_worktree_refusal_state` / `cmd_snapshot_quota` の
   refusal 判定部 3955-4010 付近）
5. `bin/tests/test_ocw_meter.py`（3,081行。特に `run_meter`:60付近 / `run_snapshot_quota`:78 /
   `OcwMeterTestCase`:213 / :2149 / :2895）

## この孫のスコープ

**ストアの衛生だけ。** 費用計算・ingest・帰属・価格表には一切触らないこと（孫2〜5の担当）。

### 1. テストによる実ストア汚染を止める（本傘の【4】）

`bin/tests/test_ocw_meter.py:2149`
`test_git_worktree_home_refuses_write_but_still_prints_display` が `HOME` を上書きしていない。

同ファイル :2895 の兄弟テスト `test_worktree_refusal_is_throttled_and_stops_rewarning` は
`extra_env={"HOME": str(fake_home)}` を渡していて正しい。片方が漏れているだけである。

**個別テストに1行足すだけで終わらせないこと。** 同じ穴は今後も開く。
次の優先順で検討し、選んだ理由を PR 説明文に書くこと:

- **第一候補: ヘルパ側での横断防御。** `run_meter()` / `run_snapshot_quota()` が
  `extra_env` で明示されない限り `HOME` を必ずテスト専用の tempdir に差し替える。
  これで「HOME を書き忘れる」という失敗モード自体が消える。
  既存テストの中に実 `HOME` に依存しているものが無いかを確認すること
  （あれば、そのテストが何を確認しているのかを読んでから判断する）
- **第二候補（第一候補が既存テストを壊す場合）**: :2149 に `extra_env` を足したうえで、
  「`HOME` を差し替えていないテストが無いか」を検出する仕組み（テストヘルパでの
  アサーション等）を入れる

**`OcwMeterTestCase.setUp` は tempdir しか作っていない**（`bin/tests/test_ocw_meter.py:213`）。
ここに `HOME` 用の tempdir も用意するのが素直だが、`self.home`（= `OCW_METER_HOME`）と
**別のディレクトリにすること**（同じにすると、退避キャッシュの「refused root とは別の場所に
書く」という設計そのものがテストで検証できなくなる）。

### 2. `quota-worktree-refusal.json` のプルーニング片手落ちを直す（本傘の【6】）

`bin/ocw-meter:3999` 付近。24時間超（`QUOTA_SESSION_STATE_MAX_AGE_SECONDS`）の古いエントリを
消しているのは **新しい refusal を書き込む瞬間だけ**。汚染が止まると古いエントリが残り続ける
（実測: このマシンの実ストアに 8/6〜8/7 の37件が居座っている）。

**読み取り時にもプルーニングすること。** `load_worktree_refusal_state()` が返す時点で
期限切れエントリを落とすのが素直だが、次の2点に注意:

- **`snapshot-quota` は statusLine から高頻度（60秒スロットル）で呼ばれる。**
  読み取りのたびにファイルを書き戻すと、正常系（refusal が1件も無い普通のマシン）で
  無駄な書き込みが毎回走る。**落とすべきエントリが実際にあったときだけ書き戻す**こと
- refusal 判定に到達する前の早期 return 経路（スロットル成立時など）でも、
  期限切れエントリが読み取り側で除外されていること

この修正により、**実ストアに居座っている37件は次回の `snapshot-quota` で自然に消える**
（すべて24時間より古いため）。これを PR 説明文で明示すること。

### 3. 診断ファイル専用の掃除サブコマンドを新設する（本傘の【4】の後始末）

上記2で refusal 37件は自動的に消えるが、**`state/meter-errors.jsonl` の6件は append-only の
診断ログなので残る**（`storage_home_inside_git_worktree` × 6件、8/1〜8/7。全部テスト由来）。

新サブコマンド `ocw-meter prune-diagnostics` を追加する。設計制約:

- **対象は `state/meter-errors.jsonl` と `state/quota-worktree-refusal.json` の2つだけ。**
  `events/` には**絶対に触らない**。`prune`（`events/` の削除）は `bin/README.md:457` で
  意図的に据え置くと決めた機能であり、**この孫でその決定を覆さない**
- **既定は dry-run。** 何件消えるかを表示して終わる。実際に消すのは `--apply` を明示したときだけ
- 保持期間は `--older-than <日数>` で指定。既定値を決め、その根拠をヘルプに書く
- 消した件数・残した件数を報告する。**黙って消さない**
- `report` / `validate` と同じく **fail-loud**（失敗したら非0で終わる）。
  `event` / `bind-pr` / `snapshot-quota` の fail-open 契約とは別系統である
- 「テスト由来と思われるエントリ」（`<tmpdir>/repo/ocw-meter-home` のようなパス形状）の
  **判別はヒューリスティックなので、削除条件にはしない**。dry-run の表示で
  「うち N 件はテスト由来の可能性がある」と**補助情報として出すだけ**にとどめること。
  パス形状で自動削除すると、本物の設定ミスによる診断まで消しかねない

`usage()`（`bin/ocw-meter:20` 付近）と `bin/README.md` のサブコマンド一覧にも追加すること
（README の詳細な説明は孫6が書くので、この孫では1行の追加でよい）。

## テスト（`bin/tests/test_ocw_meter.py`）

追加するテスト:

**汚染防止:**
- `HOME` を上書きしていない状態で `run_snapshot_quota` を呼んでも、テスト用 tempdir の外に
  何も書かれない（第一候補を採った場合、これがヘルパの契約テストになる）
- :2149 のテストが `bad_home` の外（＝差し替えた `HOME` 配下）に退避キャッシュを書き、
  **実 `HOME` 配下には書かない**

**プルーニング:**
- 24時間より古いエントリだけが入った `quota-worktree-refusal.json` を用意し、
  refusal が一切発生しない普通の `snapshot-quota` を1回呼ぶと、古いエントリが消えている
- 期限内のエントリは残る
- **落とすべきエントリが無いときはファイルの mtime が変わらない**（無駄な書き戻しをしない）

**prune-diagnostics:**
- 既定（`--apply` なし）では何も消えず、件数だけが出る
- `--apply` で古いエントリだけが消え、新しいものは残る
- `events/` 配下のファイルが**1バイトも変わっていない**
- 対象ファイルが存在しないストアでも exit 0 で「0件」と出る
- 壊れた JSON の `quota-worktree-refusal.json` があっても落ちない

## 完了条件

- `pre-commit run --all-files` が通る
- `bin/tests/lint.sh` が通る
- `python3 -m unittest discover -s bin/tests -v` が全件通る（既存193件 + 追加分）
- **テストスイートを回した直後に、実 `~/.local/state/ocw-meter` が変化していない**ことを
  確認済み（確認方法は計画書「全孫共通の注意」§4 を参照。結果を PR 説明文に書くこと）

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:
1. PRを作成する。**PRの向き先は必ず `ocw-meter-accuracy` にすること。master には絶対に出さない。**
2. /pr-review-loop を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する
実装が終わったタイミングで止まらず、必ずここまでやりきってください。

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `ocw-meter-accuracy` から切ること**。
master から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:
git checkout ocw-meter-accuracy && git pull --rebase origin ocw-meter-accuracy
git checkout -b ocw-meter-01-store-hygiene
````

## 孫2用プロンプト:

````
`ocw-meter report` から `ingest` を自動実行し、最終 ingest 時刻と鮮度をフッターに出してください。

## 最初に読むもの（順番に）

1. リポジトリルートの `AGENTS.md`（最重要ルール）
2. `docs/planning/DOC-2608081456_ocw-meter-accuracy_計画.md`（この計画書。
   「調査で判明した事実」の【1】、「確定事項」、「全孫共通の注意」を必ず読む）
3. `docs/planning/DOC-2608021229-a_ai-llm-cost-observability_計画.md` の440行目付近
   （**実装をこの記述に合わせるのが本孫の主目的**）
4. `bin/ocw-meter`（孫1がマージ済み。特に `cmd_report`:2284 / `cmd_ingest`:3389 /
   `usage_cost_footer`:1514 / `print_footer_text` / `load_ingest_cursor`:2724 付近 /
   `save_ingest_cursor` / `_report_month_standalone`:2534 付近）
5. `bin/tests/test_ocw_meter.py`

## この孫のスコープ

**ingest の実行契機と鮮度表示だけ。** 費用の中身・帰属・価格表には触らないこと（孫3〜5の担当）。

## 背景（実測）

`state/ingest-cursor.json` の最終更新が 2026-08-05 02:50 で止まっており、
transcript と events を `message.id` で突合すると **6,878件（11.4%）が未取り込み**だった
（8/04:1312 / 8/05:610 / 8/06:2477 / 8/07:1407 / 8/08:1072）。
一方 `phase.start` / `run.start` は 8/8 まで流れているので、
**「工程は記録されているのにトークンだけゼロ」という歪んだ月次が出ている。**

計画書 DOC-2608021229-a:440 は ingest の実行契機を「手動 / `report` が自動実行」と書いているが、
`cmd_report()` に ingest 呼び出しは1つも無い。**計画書と実装の食い違いがそのまま欠測になっている。**

### 1. `report` の先頭で ingest を実行する

`cmd_report()`（`bin/ocw-meter:2284`）の先頭、イベントを読み込む前に ingest を走らせる。
`report --month` のスタンドアロン経路（`_report_month_standalone`）も含め、
**`report` の全ビュー（既定 / `--phase` / `--model` / `--role` / `--window` / `--month` /
`--reconcile`）で同じように効くこと**。1つでも漏れると、そのビューだけ古いデータを見る。

設計上の要件:

- **`--no-ingest` オプションを用意する。** 読み取り専用で使いたい場合と、
  テストで ingest を切りたい場合の両方に要る
- **ingest の失敗で `report` を落とさない。** ingest が失敗したら警告を出し、
  既に保存済みのイベントでレポートを出す。ただし**失敗したという事実をフッターに必ず出す**
  （黙って古いデータを新しい顔で出すのが最悪）
- **ingest の詳細な進捗出力で `report` の出力を汚さない。** 要約1行に抑えるか stderr に出す。
  `--json` 指定時は **stdout に JSON 以外を1バイトも出さない**こと
  （既存の `--json` 経路が JSON のみを stdout に出していることを確認してから書く）
- `ingest` は `in_git_worktree(root)` で refuse する経路を持つ（`bin/ocw-meter:3400` 付近）。
  そのケースも「ingest できなかった」として上記と同じ扱いにすること
- **`report` に書き込み副作用が生まれる。** これは意図した変更だが、
  `iter_stored_events` の docstring が「`report` stays read-only」と書いている等、
  読み取り専用を前提にしたコメントが他にもあるはずなので、**探して追随させること**

### 2. 最終 ingest 時刻を記録する

**ファイルの mtime に頼らないこと。** `cp -a` や rsync や世代デプロイで mtime は動きうる。
`save_ingest_cursor()` が書く `ingest-cursor.json` の中に、
**最終 ingest の実行時刻と結果を明示的なフィールドとして書く**。

**後方互換**: 既存の `ingest-cursor.json` にはこのフィールドが無い。
`load_ingest_cursor()` は現状 `{"files": {}}` を返すフォールバックを持っているので、
そこを壊さないこと。フィールドが無い場合は「unknown（次回 ingest で記録される）」と出し、
**mtime から推測して埋めない**（このツールの「推測で埋めない」方針）。

`schema_version` の変更が要るかどうかを
`docs/reference/DOC-2608021229-c_ocw-meterイベントスキーマ.md` §6 のルールに照らして判断すること
（`ingest-cursor.json` はイベントではなく状態ファイルなので、おそらく不要。判断理由を PR に書く）。

### 3. 鮮度をフッターに出す

`usage_cost_footer()`（`bin/ocw-meter:1514`）に行を足す。この関数は
**「どのビューでも同じフッターが出る」ことを保証するために切り出されている**
（docstring 参照）ので、ここに足せば全ビューに乗る。

出すべき情報:

- 最終 ingest 時刻（RFC3339）と、そこからの経過時間
- 今回の `report` が ingest を実行したか / スキップしたか（`--no-ingest`）/ 失敗したか
- 鮮度警告: 最終 ingest から一定時間以上経っていたら明示する。
  **閾値をハードコードするならその根拠をコメントに書くこと**

`print_footer_text()`（テキスト出力）と `--json` の両方に反映すること。
**既存のフッター項目（`coverage` / `price_table` / `cost_basis` / `cost_estimate`）の
意味を変えないこと。** 行を足すだけである。

## テスト（`bin/tests/test_ocw_meter.py`）

追加するテスト:

- `report` が transcript を自動で取り込む（fixture の transcript を置いて、
  `ingest` を明示的に叩かずに `report` だけで件数が増える）
- `--no-ingest` では取り込まれない
- **全ビューで自動 ingest が効く**（既定 / `--phase` / `--model` / `--role` / `--window` /
  `--month` / `--reconcile` を1件ずつ）
- ingest が失敗しても `report` が exit 0 で出力を返し、フッターに失敗が出る
- `--json` 指定時、stdout が**厳密に valid JSON 単体**である（ingest の出力が混ざらない）
- 最終 ingest 時刻がフッターに出る
- `last_ingest_at` 相当のフィールドが無い**古い形式の `ingest-cursor.json`** を置いても落ちず、
  「unknown」と出る
- 鮮度警告が閾値を跨いだときだけ出る

## 完了条件

- `pre-commit run --all-files` が通る
- `bin/tests/lint.sh` が通る
- `python3 -m unittest discover -s bin/tests -v` が全件通る
- 実ストアが変化していないことを確認済み（計画書「全孫共通の注意」§4）

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:
1. PRを作成する。**PRの向き先は必ず `ocw-meter-accuracy` にすること。master には絶対に出さない。**
2. /pr-review-loop を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する
実装が終わったタイミングで止まらず、必ずここまでやりきってください。

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `ocw-meter-accuracy` から切ること**。
master から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:
git checkout ocw-meter-accuracy && git pull --rebase origin ocw-meter-accuracy
git checkout -b ocw-meter-02-ingest-freshness
````

## 孫3用プロンプト:

````
`ocw-meter` の価格表を時間帯（peak/off-peak）課金に対応させ、
該当する価格表が無い期間を黙って概算しないようにしてください。

## 最初に読むもの（順番に）

1. リポジトリルートの `AGENTS.md`（最重要ルール）
2. `docs/planning/DOC-2608081456_ocw-meter-accuracy_計画.md`（この計画書。
   「調査で判明した事実」の【5】、**「実装上の罠」の罠5**、「全孫共通の注意」を必ず読む）
3. `docs/reference/DOC-2608021229-c_ocw-meterイベントスキーマ.md` §4「費用計算式」と
   「価格表（`bin/prices/*.json`）」節
4. `bin/prices/deepseek-2026-08-01.json`（現状これ1枚しかない）
5. `bin/ocw-meter`（孫1・孫2がマージ済み。特に `load_price_tables`:2650 付近 /
   `select_price_table`:2673 / `compute_cost`:2691 / `build_usage_event`:3141 /
   `usage_cost_footer`:1514 / `report_month_cash_and_capacity`:2008）
6. `bin/tests/test_ocw_meter.py`

## この孫のスコープ

**価格表の構造と適用だけ。** 帰属（`run_id` / `role`）と `list_price_equiv` には触らないこと。

## 背景（実測）と、最初に理解すべき制約

`bin/prices/` に `deepseek-2026-08-01.json` の1枚しかない。`select_price_table()` は
「`effective_date <= 対象日` の最新」を選ぶが、該当が1枚も無いときは `tables[0]`（最古の表）に
フォールバックする。唯一の表の `effective_date` が `2026-08-01` なので、
**6月〜7月の29,676件も8月の価格表で計算されている**（`$46.78` はその前提の数字）。
フォールバックしたことは出力のどこにも出ない。

さらにその表の `notes` に
`peak/off-peak 2x pricing announced (Beijing 09:00-12:00, 14:00-18:00) — effective date TBD`
とあるが、価格表の粒度は日単位（`effective_date`）なので、発効したら時間帯を表現する手段が無い。
最大2倍の過小計上になる構造。

### ⚠️ 最重要の制約: 過去の価格表を足しても、既存イベントの費用は直らない

`cost_estimate_usd` は `ingest` 時点で計算されてイベントに焼き込まれる。
「過去は再計算しない」不変条件があるため、**6〜7月に有効だった価格表を後から足しても、
既存の29,676件の `cost_estimate_usd` は変わらない。**

**したがってこの孫では、過去の価格表を自分で作ってはいけない。**
価格表は出典 URL 付きの一次情報であり、AI が記憶から単価を書くと静かに嘘の数字が入る。
やるのは以下の3点である。

### 1. 価格表スキーマを時間帯対応に拡張する

現状の形（`bin/prices/deepseek-2026-08-01.json`）:

```
{
  "price_table_version": "deepseek-2026-08-01",
  "effective_date": "2026-08-01",
  "source": "...", "fetched_at": "...", "currency": "USD", "unit": "per_1m_tokens",
  "models": {
    "deepseek-v4-pro": { "cache_hit_in": 0.003625, "cache_miss_in": 0.435, "out": 0.87 }
  },
  "notes": "..."
}
```

**後方互換が絶対条件。** 時間帯を持たない既存の表がそのまま今までどおり動くこと。
時間帯情報はオプショナルな追加であり、無ければ従来の単価がそのまま全時間帯に適用される。

設計の要点:

- 時間帯窓は**タイムゾーン付きで定義する**。DeepSeek の告知は北京時間
  （`Beijing 09:00-12:00, 14:00-18:00`）である
- **中国は夏時間を採用していないので、北京時間は UTC+8 固定である。**
  `zoneinfo` は Python 3.9+ かつ tzdata が必要で、環境によっては入っていない。
  **固定オフセットで実装すること**（タイムゾーン名を書くなら、それは表示用の情報として持ち、
  計算は固定オフセットで行う）。オフセットは価格表側に持たせ、コードにハードコードしないこと
- 窓の境界の扱い（開始時刻を含むか、終了時刻を含むか）を**明示的に決めてコメントに書く**。
  境界1秒の差で単価が2倍変わるので、曖昧にしない
- 日を跨ぐ窓（例 `22:00-02:00`）を表現できるかどうかを決める。
  **できないなら「できない」とスキーマ文書に書く**（黙って壊れるより良い）
- 倍率で表現するか、時間帯ごとの単価を直接書くかを決め、理由を書くこと

### 2. `compute_cost()` に時刻を渡す

現在のシグネチャは `compute_cost(model, usage_fields, price_table)` で、
**時刻を受け取っていない**（`select_price_table` に日付を渡す側で日単位の解決が済んでいるため）。
時間帯判定にはメッセージのタイムスタンプが要るので、シグネチャを変える。

呼び出し元は `build_usage_event()`（`bin/ocw-meter:3141`）。
**時刻が取れないメッセージがあった場合の挙動を決めること**（推測で peak / off-peak を
決めないこと。取れないなら従来の単価に倒し、その旨を `cost_basis` か別のフィールドで示す）。

`compute_cost()` の既存の契約を壊さないこと:

- **`claude-*` は必ず `(None, None, None, "subscription")` を返す**（定額契約を換算しない。
  ADR DOC-2608021229 の判断。本傘でもこれは維持する）
- **絶対に raise しない**（docstring に「Never raises」と明記されている）
- 未知のモデル名には値段を当てない

### 3. 該当する価格表が無い期間を黙らせない

`select_price_table()` の `tables[0]` フォールバックは**残してよい**（クラッシュさせないため）。
だが**フォールバックが起きたことを呼び出し側に伝えること。** 現状は戻り値からは区別できない。

伝わった先で出すべきもの:

- `usage_cost_footer()`（`bin/ocw-meter:1514`）の `price_table` 行に、
  「対象期間より後に発効した価格表を適用した件数」を出す
- `report --month` の cash cost 節に、**その月に適用された `price_table_version` と、
  その表の `effective_date` が対象月より後であるかどうか**を出す。
  実測で言えば `report --month 2026-07` は「`deepseek-2026-08-01` を適用（対象月より後に発効）」
  と出るべきである

**既存イベントに焼き込まれた `price_table_version` / `price_effective_date` から
読み取り時に判定できる**（イベントを書き換える必要はない）。

### 4. 過去の価格表を足すための手順を用意する（データは入れない）

`bin/prices/` に価格表を追加する手順を短い README として書く。含めるもの:

- 必須フィールドと意味（`load_price_tables` が要求する3つは
  `price_table_version` / `effective_date` / `models`）
- **`source`（出典 URL）と `fetched_at` を必ず埋めること**。単価は一次情報であり、
  記憶や推測で書いてはいけない
- **過去の表を足しても既に保存されたイベントの `cost_estimate_usd` は変わらない**こと
  （変えたければイベントストアを作り直すしかない。それは本ツールの不変条件に反する）
- 時間帯課金の書き方（上記1で決めた形）

**サンプルの JSON を置く場合は、実在しない `example` プロバイダの明らかにダミーな数字にすること。**
実在プロバイダのそれらしい数字を例として置くと、いつか誰かが本物だと思って使う。

## テスト（`bin/tests/test_ocw_meter.py`）

追加するテスト:

**後方互換:**
- 時間帯情報を持たない既存形式の価格表で、費用が従来どおり計算される
  （既存のテストが無改変で通ることが主要な根拠になる）

**時間帯:**
- peak 窓の中のタイムスタンプで peak 単価、外で off-peak 単価が適用される
- 窓の境界ちょうどのタイムスタンプ（開始時刻・終了時刻）で、決めたとおりの単価になる
- UTC のタイムスタンプが正しく北京時間の窓へ変換される（**UTC 深夜 = 北京の朝** のように、
  日付を跨ぐケースを必ず含めること）
- 時刻が取れないメッセージで落ちず、決めたフォールバック挙動になる

**フォールバック警告:**
- 対象日より後に発効した価格表しか無いとき、`report` に警告が出る
- `report --month` に、適用された `price_table_version` と発効日ミスマッチが出る
- 期間に合う価格表があるときは警告が出ない

**壊れた価格表:**
- 時間帯定義が壊れている（窓が不正・オフセットが無い等）価格表があっても
  `ingest` が落ちない（`load_price_tables` の既存方針「malformed は skip、fatal にしない」を維持）

## 完了条件

- `pre-commit run --all-files` が通る
- `bin/tests/lint.sh` が通る
- `python3 -m unittest discover -s bin/tests -v` が全件通る
- **既存の価格表 `deepseek-2026-08-01.json` を1バイトも変えていない**か、
  変えた場合はその内容が出典で裏が取れている（推測で単価を書き換えていない）
- 実ストアが変化していないことを確認済み（計画書「全孫共通の注意」§4）

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:
1. PRを作成する。**PRの向き先は必ず `ocw-meter-accuracy` にすること。master には絶対に出さない。**
2. /pr-review-loop を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する
実装が終わったタイミングで止まらず、必ずここまでやりきってください。

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `ocw-meter-accuracy` から切ること**。
master から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:
git checkout ocw-meter-accuracy && git pull --rebase origin ocw-meter-accuracy
git checkout -b ocw-meter-03-price-tables
````

## 孫4用プロンプト:

````
`quota.sample` に眠っている `session_cost_usd` を集計して、
Claude 側の list price 相当額を `report` に出せるようにしてください。

## 最初に読むもの（順番に）

1. リポジトリルートの `AGENTS.md`（最重要ルール）
2. `docs/planning/DOC-2608081456_ocw-meter-accuracy_計画.md`（この計画書。
   「【2】【3】の鍵」節、「確定事項」、**「実装上の罠」の罠2・罠3・罠4**、「残る限界」、
   「全孫共通の注意」を必ず読む）
3. `docs/adr/DOC-2608021229_llm-cost-observability-collection-method.md`
   （「定額契約を API 単価に換算しない」という判断。**本孫はこれを覆さない**）
4. `docs/reference/DOC-2608021229-c_ocw-meterイベントスキーマ.md` §2.5（`quota.sample` の
   ペイロード。`session_cost_usd` の定義がここにある）
5. `bin/ocw-meter`（孫1〜3がマージ済み。特に `report_month_cash_and_capacity`:2008 /
   `pr_review_summary`:1626 / `report_by_window` / `usage_cost_footer`:1514 /
   `print_footer_text` / `cmd_report`:2284 / `_report_month_standalone`:2534 付近 /
   `snapshot-quota` のイベント組み立て 4055-4110 付近）
6. `bin/tests/test_ocw_meter.py`

## この孫のスコープ

**`quota.sample` の集計と、その表示だけ。** `usage.message` の書き込み経路には一切触らない。
帰属（`run_id` / `role`）は孫5の担当。

**スキーマ変更なし。既存フィールドの集計のみ。書き込み経路は無変更。**

## 背景（実測。再調査不要）

`snapshot-quota` が statusLine の `cost.total_cost_usd` を `session_cost_usd` として記録している。
**これが 4,704 / 4,705 件で埋まっていて、しかもどのレポートにも一切出てこない。**

```
provider別（セッション累積の最大値を合計）
  anthropic : $2,995.36 / 205 sessions（全部 2026-08）
  deepseek  : $93.35    / 10 sessions

PR単位にも落ちる（anthropic セッション 140/205 に pr_number あり）
  PR #33: $103.36   PR #39: $126.94   PR #32: $58.14
  PR #41: $56.56    PR #28: $49.60    PR #35: $33.77 ...
```

つまり `report --month 2026-08` が `$1.34` と表示している裏で、
同じストアに $2,995 分の Claude 側自己申告コストが眠っている。

**この経路は `quota.sample` だけを見るので、【1】の ingest 遅延の影響を受けない。**

### 1. `report_capacity_list_price(quota_events)` を新設する

**⚠️ 罠2: `provider == "anthropic"` で明示的にスコープすること。**
`deepseek` の `session_cost_usd`（$93.35）を混ぜてはいけない。Claude Code が DeepSeek の
モデル名に何の単価を当てているか不明であり、`ocw-meter` 自身の推定 $48.12 と二重計上になる。

`quota.sample` の `provider` は `infer_provider(model_normalized)`、`model` が取れないときは
`has_rate_limits` から `"anthropic"` にフォールバックして決まっている
（`bin/ocw-meter:4069` 付近）。DeepSeek セッションは `rate_limits` を持たないため、
`provider == "anthropic"` によるスコープはこの実装で正しく機能する。

**⚠️ 罠3: `max()` を使ってはいけない。「正の差分の総和」を取ること。**
`session_cost_usd` はセッション累積のはずだが、**214セッション中26セッションで値が減少している**
（`/clear` やコンパクションでリセットされていると思われる）。`max()` ではリセット前の分を
取りこぼす。

```
session_id ごとに ts 昇順でソート
  → 隣り合うサンプルの差分を取る
  → 正の差分だけを合計（負の差分は「リセットが挟まった」と解釈して 0 扱い）
  → 各セッションの最初のサンプルの値そのものは初項として加算する
```

上記の **$2,995.36 は `max()` による集計なので下振れした値**である。
正の差分の総和で取り直せば、これ以上の値が出るはずである。

`session_id` が無いサンプル・`session_cost_usd` が `null` のサンプルの扱いを決め、
除外した件数を報告に出せるようにすること（黙って落とさない）。

### 2. 出し先

- **`report --month` の capacity cost 節**（`report_month_cash_and_capacity`:2008 の
  戻り値と、`_report_month_standalone` の `summary["capacity"]` 構築部）
- **`report --pr <n>`**（`pr_review_summary`:1626 の `capacity_message_count` の隣）
- **`report --window`**（自然に乗るはず。乗せられるか確認し、乗せられないなら理由を PR に書く）

### 3. 表示（⚠️ 罠4）

**必ず下限値として、請求書ではないと明示して出すこと。**
最後の statusLine 描画以降の消費が入らないため、この数字は原理的に下限である。

表示例:

```
list_price_equiv_usd: $2,995+ (下限 / Claude Code自己申告のlist price相当 / 請求書ではない / cash costと合算不可)
```

守るべき境界:

- **`usage_cost_footer()`（`bin/ocw-meter:1514`）の `cost_estimate` 行とは別行にする。混ぜない**
- **cash cost と絶対に足さない。** `report_month_cash_and_capacity` の docstring が
  「cash cost と capacity は never summed」と明記している。これは様式の好みではなく
  ハード要件である。`list_price_equiv_usd` は **capacity 側**に属する
- `--json` にも同じ情報を出すこと。**JSON のキー名に単位と性質が分かる名前を使う**
  （`list_price_equiv_usd` と、それが下限であることを示す別キー）
- **対象期間に anthropic の `quota.sample` が1件も無いときは `null`**。
  `$0.00` と出さない（「0ドルだった」と「データが無い」は別の事実である）

### 4. 限界を出力に書く（正直さの要件）

- `quota.sample` は **2026-08-01 開始**。それより前の月には Claude 側コストのデータが無い。
  `report --month 2026-07` 等では「この期間に quota.sample が無いため不明」と出すこと
- 下限であること（罠4）

## テスト（`bin/tests/test_ocw_meter.py`）

追加するテスト（計画書の「罠」に対応するものは省略不可）:

**非単調セッション（罠3）:**
- 1セッションで `10 → 20 → 5 → 15` と推移する `quota.sample` を並べ、
  結果が `max()` の `20` ではなく **正の差分の総和 `10 + 10 + 10 = 30`** になる
- 単調増加のみのセッションでは、最終値と一致する
- サンプル1件だけのセッションで、その値がそのまま入る

**deepseek 混入除外（罠2）:**
- anthropic セッションと deepseek セッションが混在するストアで、
  deepseek の `session_cost_usd` が**1セントも入っていない**
- `rate_limits` を持たない（= DeepSeek 形状の）サンプルが混ざっても除外される

**表示と境界:**
- `list_price_equiv_usd` が cash cost と**別のキー / 別の行**で出る
- 対象期間に anthropic の `quota.sample` が無いとき `null`（`0` ではない）
- `--json` に出る
- `report --pr <n>` に出る
- `session_cost_usd` が `null` のサンプル、`session_id` が無いサンプルが混ざっても落ちない

## 完了条件

- `pre-commit run --all-files` が通る
- `bin/tests/lint.sh` が通る
- `python3 -m unittest discover -s bin/tests -v` が全件通る
- **書き込み経路（`snapshot-quota` / `ingest`）の diff がゼロ**である
  （この孫は集計と表示だけ。スキーマも変えない）
- 実ストアが変化していないことを確認済み（計画書「全孫共通の注意」§4）

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:
1. PRを作成する。**PRの向き先は必ず `ocw-meter-accuracy` にすること。master には絶対に出さない。**
2. /pr-review-loop を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する
実装が終わったタイミングで止まらず、必ずここまでやりきってください。

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `ocw-meter-accuracy` から切ること**。
master から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:
git checkout ocw-meter-accuracy && git pull --rebase origin ocw-meter-accuracy
git checkout -b ocw-meter-04-list-price-equiv
````

## 孫5用プロンプト:

````
`session_id` で `quota.sample` と `usage.message` を突き合わせ、
`run_id` / `role` の帰属を解決してください（ingest 側フォールバック + report 側 join の併用）。

## 最初に読むもの（順番に）

1. リポジトリルートの `AGENTS.md`（最重要ルール）
2. `docs/planning/DOC-2608081456_ocw-meter-accuracy_計画.md`（この計画書。
   「調査で判明した事実」の【3】、「【2】【3】の鍵」節、「確定事項」、
   **「実装上の罠」の罠1**、「残る限界」、「全孫共通の注意」を必ず読む）
3. `docs/reference/DOC-2608021229-c_ocw-meterイベントスキーマ.md`
4. `bin/ocw-meter`（孫1〜4がマージ済み。特に
   `load_local_pr_binds_and_run_starts`:3007 / `resolve_run_id_via_ocw_run_id_file`:3041 /
   `build_usage_event`:3141 と **その run.start 逆転チェック 3186 付近** /
   `iter_stored_events`:1426 / `events_for_pr`:1589 / `pr_review_summary`:1626 /
   `report_by_role`:1756 / `report_by_phase`:1844 / `usage_cost_footer`:1514）
5. `bin/tests/test_ocw_meter.py`

## この孫のスコープ

**`run_id` / `role` の帰属解決だけ。** 費用計算・価格表・`list_price_equiv` には触らない。

## 背景（実測。再調査不要）

```
run_id が入っている usage.message : 3,043 / 57,164 (5.3%)
role=unknown                      : 51,959 / 57,164 (90.9%)
report --phase の (unassigned)    : 56,648 / 57,164 (99.1%)
```

原因は共通で、**解決タイミングが「ingest 実行時点のライブ状態」だから**。
`run_id` は `cwd` 配下の `<git-dir>/ocw-run-id` という *消える実ファイル* を読み、
`role` は `herdr pane list` という *閉じたら引けないライブ状態* を読んでいる。
しかも「過去は再計算しない」不変条件があるため、後から ingest し直しても永久に直らない。

**答えは既にストアの中にある。** `quota.sample` は `session_id` 100% / `run_id` 78% /
`role` 78%（unknown 22%）を持ち、`usage.message` も transcript 由来の `session_id` を100%持つ。
**両者を `session_id` で突き合わせるだけ**で、実測こうなる:

```
8/1以降（quota.sample 稼働後）の usage.message 17,670件
  run_id : 3,043 (17.2%)  ->  10,885 (61.6%)
  role   : 4,814 (27.2%)  ->  12,740 (72.1%)
```

**この join は `ocw rm` に一切影響されない**（`quota.sample` は消えないイベントだから）。

### 1. B: ingest 側フォールバック（新しく書き込むイベントを直す）

`load_local_pr_binds_and_run_starts()`（`bin/ocw-meter:3007`）の戻り値に
`session_attrs`（`session_id` → `{run_id, role, pr_number}`）を追加する。
**この関数は ingest 中に既にイベントストアを全走査している**ので、追加コストはほぼゼロ。

`build_usage_event()`（`bin/ocw-meter:3141`）の解決順を次にする:

- `run_id`: `ocw-run-id` ファイル → **quota.sample 由来** → `null`
- `role`: Herdr live → **quota.sample 由来** → `"unknown"`

**1つの `session_id` に複数の `run_id` / `role` が紐づくケースの扱いを決めること**
（同じセッションで worktree を移った場合など）。時刻で最も近いものを選ぶ / 一意でなければ
解決しない、などの方針を決め、**理由をコメントと PR 説明文に書く**。推測で1つ選ばないこと。

#### ⚠️ 罠1（この孫で最も踏みやすい）

**quota.sample 由来の `run_id` には、既存の `run.start` 逆転チェックを適用してはいけない。**

`bin/ocw-meter:3186` 付近に「その `run_id` の `run.start` より前のメッセージなら捨てる」という
チェックがある。これは **「worktree パスは再利用される」ことを前提にした stale path 対策**であり、
`ocw-run-id` ファイル経由の解決にのみ意味がある。

`session_id` は再利用されないため、このチェックを quota.sample 由来の解決にかけると
**正しい帰属まで null 化してしまう。** 解決経路ごとにチェックの適用を分けること。
**この点はテストで固定すること**（後の誰かが「統一しよう」と言って壊すのを防ぐため）。

### 2. A: report 側 join（既に保存済みのイベントを読み取り時に補完）

`iter_stored_events()`（`bin/ocw-meter:1426`）の走査時に同じマップを組み、
**`run_id` / `role` が `null` のイベントだけ**読み取り時に補完する。

**既に値が入っているイベントの値を上書きしないこと**（ingest 時に直接解決できた値のほうが
信頼度が高い）。

影響先:
`report_by_phase`（:1844）/ `report_by_role`（:1756）/ `events_for_pr`（:1589）/
`pr_review_summary`（:1626）。**これら全部で同じ補完が効くこと**を確認すること。

**保存されたイベントのファイルを書き換えないこと。** これは読み取り時の解決であり、
「過去は再計算しない」不変条件を破らないためにこの方式を選んでいる
（既存イベントを埋め直す `reattribute` サブコマンド案は、計画書で明示的に却下している）。

`iter_stored_events` は**全ビューが通る道**なので、性能に注意すること。
マップを毎回組み直さない（1回組んで使い回す）。実ストアは events 68MB / 62,763件である。

### 3. ⚠️ 譲れない条件: 補完したことを出力に明示する

これをしないと「推測で埋めない」という本ツールの方針に反して見える。
フッター（`usage_cost_footer` = `bin/ocw-meter:1514` に足せば全ビューに乗る）に1行足す:

```
attribution:   direct 17.2% / via session_id 44.4% / unresolved 38.4%
```

- `direct`: ingest 時に `ocw-run-id` / Herdr live から直接解決できたもの
- `via session_id`: quota.sample 由来（ingest 側フォールバックと report 側 join の両方を含む）
- `unresolved`: どちらでも解決できなかったもの

**`run_id` と `role` は別々の割合になる**（実測でも 61.6% と 72.1% で違う）。
1行にまとめるか2行に分けるかを決め、**どちらの数字か分かる形にすること**。
`--json` にも同じ情報を出す。

### 4. 残る限界を出力または文書に書く（正直さの要件。「直った」と言わない）

- **7月以前は救えない。** `quota.sample` が 2026-08-01 開始のため、
  7月の29,676件（DeepSeek 時代）の `run_id` / `role` は復元手段が無い
- 8月でも `run_id` 61.6% / `role` 72.1% で100%にはならない。
  `claude-ds` セッションや statusLine が回らなかったセッションは取れない
- `role` の 22% unknown は Herdr 外で起動した Claude なので**原理的に取得不能**

## テスト（`bin/tests/test_ocw_meter.py`）

追加するテスト:

**session join（B: ingest 側）:**
- `ocw-run-id` ファイルが無く、同じ `session_id` の `quota.sample` に `run_id` があるとき、
  新しく ingest した `usage.message` にその `run_id` が入る
- `ocw-run-id` ファイルがあるときは**そちらが優先される**
- `role` も同様（Herdr live 優先、無ければ quota.sample 由来、それも無ければ `"unknown"`）
- どちらも無ければ `run_id` は `null` / `role` は `"unknown"`

**罠1（逆転チェックの非適用）:**
- **`quota.sample` 由来の `run_id` が、対応する `run.start` より前の時刻の `usage.message` にも
  正しく付く**（`ocw-run-id` ファイル経由なら捨てられる条件を作り、
  session 経由では捨てられないことを対で確認する）
- `ocw-run-id` ファイル経由の逆転チェックは**従来どおり効いている**（回帰防止）

**A: report 側 join:**
- `run_id` が `null` のまま保存済みの `usage.message` が、`report --phase` で
  正しい phase に集計される（**保存ファイルは変わっていない**ことも確認する）
- 既に `run_id` が入っているイベントの値が上書きされない
- `report --role` / `report --pr` / `pr_review_summary` でも同じ補完が効く

**attribution 行:**
- `direct` / `via session_id` / `unresolved` の3分類が実際の内訳と一致する
- 3分類の合計が母数と一致する（どこにも計上されないイベントが無い）
- `--json` に出る

**曖昧なケース:**
- 1つの `session_id` に複数の `run_id` が紐づくとき、決めた方針どおりに振る舞う

## 完了条件

- `pre-commit run --all-files` が通る
- `bin/tests/lint.sh` が通る
- `python3 -m unittest discover -s bin/tests -v` が全件通る
- **保存済みイベントファイルを書き換える経路を一切追加していない**
- `report` の実行時間が実用範囲に収まっている（実ストア規模: events 68MB / 62,763件。
  サンドボックスで同等規模の合成ストアを作って測り、結果を PR 説明文に書くこと）
- 実ストアが変化していないことを確認済み（計画書「全孫共通の注意」§4）

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:
1. PRを作成する。**PRの向き先は必ず `ocw-meter-accuracy` にすること。master には絶対に出さない。**
2. /pr-review-loop を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する
実装が終わったタイミングで止まらず、必ずここまでやりきってください。

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `ocw-meter-accuracy` から切ること**。
master から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:
git checkout ocw-meter-accuracy && git pull --rebase origin ocw-meter-accuracy
git checkout -b ocw-meter-05-session-attribution
````

## 孫6用プロンプト:

````
本傘（`ocw-meter-accuracy`）で変わった `ocw-meter` の仕様を文書へ反映してください。

## 最初に読むもの（順番に）

1. リポジトリルートの `AGENTS.md`（最重要ルール）
2. `docs/planning/DOC-2608081456_ocw-meter-accuracy_計画.md`（この計画書。**全部読む**。
   特に「残る限界」節は、そのまま文書に書くべき内容である）
3. **`bin/ocw-meter` の実装そのもの**（孫1〜5がマージ済み。文書は計画書ではなく**実装**に
   合わせること。食い違いがあれば実装を正とし、**その食い違い自体を人間に報告する**）
4. `bin/README.md`（611行）と ルート `README.md`
5. `docs/reference/DOC-2608021229-c_ocw-meterイベントスキーマ.md`
6. `docs/adr/DOC-2608021229_llm-cost-observability-collection-method.md`

## この孫のスコープ

**文書のみ。** `bin/ocw-meter` と `bin/tests/test_ocw_meter.py` は変更しない
（読んで内容を確認するのが仕事）。

### 1. `bin/README.md` の改訂

**古くなった記述の修正（必須）:**

- **`bin/README.md:525` 付近**: 「このマシンの実ストア44,425件の `usage.message` のうち
  `run_id` が設定されているものは0件」→ **実測3,043件 / 57,164件（5.3%）が正しい。**
  さらに孫5の session join により 8/1 以降は 61.6% まで上がる。この節は
  「`run_id` は解決できない」という前提で書かれているので、**孫5の解決策を含めて書き直す**
- **`bin/README.md:412` 付近**: `session_cost_usd` が「別カラムであり合算しない」とだけ
  書かれているが、孫4でこれが `list_price_equiv_usd` として集計・表示されるようになった。
  **「合算しない」は維持したまま、集計されて出るようになったことを追記する**
- **`bin/README.md:457` 付近の `prune` 未実装の決定**: **この決定は本傘でも維持している。**
  ただし孫1が `prune-diagnostics`（`state/` の診断ファイル専用）を追加したので、
  **両者が別物であることを明確に書く**（`events/` は消さない）

**新しく書くこと:**

- **`report` が `ingest` を自動実行するようになったこと**（孫2）と `--no-ingest`。
  フッターの最終 ingest 時刻・鮮度表示の読み方
- **価格表の時間帯（peak/off-peak）対応**（孫3）。スキーマの書き方は
  `bin/prices/` の README（孫3が作った）を指し、ここでは概要だけ。
  **該当する価格表が無い期間の費用は概算であり、警告が出ること**
- **`list_price_equiv_usd`**（孫4）。**下限値であること・請求書ではないこと・
  cash cost と合算できないこと・`quota.sample` が 2026-08-01 開始なので
  それ以前の月は不明であること**を必ず書く
- **attribution 行の読み方**（孫5）。`direct` / `via session_id` / `unresolved` の意味と、
  **7月以前は救えない**という限界
- **`prune-diagnostics` サブコマンド**（孫1）。既定が dry-run であること、
  `events/` には触らないこと
- **テストが実 `$HOME` を汚染していた不具合とその修正**（孫1）。
  過去に `state/meter-errors.jsonl` へテスト由来の診断が混入していたことと、
  `prune-diagnostics` で掃除できることを、運用上の注意として書く

### 2. `docs/reference/DOC-2608021229-c_ocw-meterイベントスキーマ.md` の追記

- **§4「費用計算式」/「価格表（`bin/prices/*.json`）」節**: 時間帯対応後のスキーマを追記。
  **窓の境界の扱い（開始/終了を含むか）とタイムゾーンの扱い（固定オフセット）を明記する**。
  日を跨ぐ窓が表現できるかどうかも書く（孫3の実装がどちらを選んだかを確認してから書く）
- **`list_price_equiv` の集計定義を新設**: `provider == "anthropic"` に限定すること、
  `session_id` ごとの**正の差分の総和**であること、**`max()` ではない**理由
  （214セッション中26セッションで非単調だった実測）、下限値であること、
  cash cost と合算しないこと
- **attribution の解決順を新設**: `run_id` は `ocw-run-id` ファイル → quota.sample 由来 → `null`、
  `role` は Herdr live → quota.sample 由来 → `"unknown"`。
  **quota.sample 由来の `run_id` に `run.start` 逆転チェックを適用しない**という設計上の判断と
  その理由（`session_id` は再利用されないため）を必ず記録する
- §6「`schema_version` の変更ルール」に照らして、**本傘で `schema_version` の変更が
  必要だったかどうか**を確認して記述を追随させる（孫2〜5がいずれもイベントのスキーマを
  変えていないなら、変更不要である旨を明記する）

### 3. ADR `DOC-2608021229` への追記節

**ADR 本体の判断は覆さない。** 「サブスクを API 単価に換算しない」は維持されている。

追記するのは**線引きの記録**である:

> **Anthropic 自己申告値（`session_cost_usd`）の採用は「換算」ではない。**
> 本 ADR が却下したのは「ocw-meter が定額契約を API 単価に換算して推定額を作ること」であって、
> 「Claude Code 自身が申告した値をそのまま記録・集計すること」ではない。
> 前者は ocw-meter の推定であり、後者は Anthropic 側の自己申告である。
> データの出所も信頼レベルも異なるため、別カラム・別行として共存させる。

既存の ADR の書式（見出しレベル・番号の付け方）に合わせること。
節番号は既存の最後（§9）の後ろに足すか、`## 7. 代替案と不採用理由` の関連箇所から
参照させるかを、文書全体を読んでから判断すること。

**却下案も記録すること:**
- B「価格表に anthropic を足して `usage.message` 側で自前計算」→ ADR の判断を覆す必要がある。
  ただし A の後から**共存可能**である（意味の異なるカラムなので）
- C「サブスク月額を按分」→ 実支払額と一致する唯一の方式だが、月末まで確定せず
  按分の分母が恣意的

### 4. ルート `README.md` の追随

`bin/` の説明と `ocw-meter` に言及している箇所を確認し、嘘になっている記述があれば直す。
**ルートは全体像、`bin/README.md` は詳細**という二層構造を崩さないこと
（AGENTS.md「片方だけ更新しない」）。

### 5. 実装との突き合わせ（省略不可）

書く前に `bin/ocw-meter` の該当箇所を読み、**実装が実際にそうなっていることを確認してから書くこと。**
計画書は決定の記録であって実装の保証ではない。食い違いを見つけたら文書を実装に合わせ、
**その事実を PR 説明文に書いて人間に報告する。**

特に確認すべき点:
- `prune-diagnostics` の実際のオプション名・既定値（孫1が決めたもの）
- 価格表の時間帯スキーマの実際の形（孫3が決めたもの）
- attribution 行の実際の出力形式（孫5が決めたもの）
- `list_price_equiv_usd` の実際のキー名と表示文言（孫4が決めたもの）

**推測でコマンド例やフィールド名を書かないこと。** 実際に実行して出力を貼るのが最も確実である
（`report` 系は副作用として ingest が走るようになっているので、
**実 `$HOME` ではなくサンドボックス（`OCW_METER_HOME` と `HOME` の両方を tempdir に向けた
環境）で実行すること**）。

## 完了条件

- `pre-commit run --all-files` が通る（`doc-id check` / `doc-id verify` を含む）
- `bin/README.md` / ルート `README.md` / DOC-2608021229-c / DOC-2608021229 に、
  実装と食い違う記述が残っていない
- `bin/README.md:525` 付近の「`run_id` が設定されているものは0件」が実測値に更新されている
- 本傘の**限界**（7月以前の帰属は救えない / `list_price_equiv` は下限値 /
  6〜7月の Claude 側コストは不明）が、「直った」と読める書き方になっていない
- 地の文で `docs/` の文書に言及する箇所で、**DOC-ID が明示されている**
  （AGENTS.md「説明的ファイル名だけで呼ばない」）

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:
1. PRを作成する。**PRの向き先は必ず `ocw-meter-accuracy` にすること。master には絶対に出さない。**
2. /pr-review-loop を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する
実装が終わったタイミングで止まらず、必ずここまでやりきってください。

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `ocw-meter-accuracy` から切ること**。
master から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:
git checkout ocw-meter-accuracy && git pull --rebase origin ocw-meter-accuracy
git checkout -b ocw-meter-06-docs
````

---

## 傘の完了条件

- 孫1〜6 がすべて `ocw-meter-accuracy` にマージ済み
- 傘ブランチ上で以下がすべて通る:
  - `pre-commit run --all-files`
  - `bin/tests/lint.sh`
  - `python3 -m unittest discover -s bin/tests -v`
- **テストスイートを回しても実 `~/.local/state/ocw-meter` が変化しない**
- `report` が `ingest` を自動実行し、最終 ingest 時刻と鮮度がフッターに出る
- `report --month 2026-08` に `list_price_equiv_usd` が下限値として出る
  （`$2,995+` を上回る値になるはず。罠3の「正の差分の総和」で取り直すため）
- `report --phase` の `(unassigned)` が 99.1% から大きく下がる
  （8月分について `run_id` 61.6% / `role` 72.1% が目安）
- attribution の内訳（`direct` / `via session_id` / `unresolved`）が全ビューのフッターに出る
- 対象期間より後に発効した価格表を適用した場合に警告が出る
- 価格表が時間帯（peak/off-peak）課金を表現できる
- `ocw-meter prune-diagnostics` が既定 dry-run で動き、`events/` には触らない
- **保存済みイベントを書き換える経路が1つも増えていない**（「過去は再計算しない」不変条件の維持）
- `bin/README.md` / ルート `README.md` / DOC-2608021229-c / DOC-2608021229 が実装と一致している

### 本傘で解決しないもの（明示）

以下は人間の判断でスコープ外とした。**孫が先回りして実装しない。**

- `<synthetic>` 103件の除外（`completeness: unknown` 0.7% の中身）
- `five_hour_window_completion` の定義見直しまたは廃止
- `prune`（`events/` の削除。`bin/README.md:457` の意図的据え置きを維持）
- 6〜7月の DeepSeek 価格表の投入（出典が要るため人間の作業。孫3は手順のみ整備）
- 7月以前の `run_id` / `role` の復元（`quota.sample` が無いため原理的に不可能）
- 6〜7月の Claude 側コスト（同上）
