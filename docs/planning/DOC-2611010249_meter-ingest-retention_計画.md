# 計画書: ocw-meter の使用量の記録が、取り込み前に transcript が消えて欠落するのを二度と起こさない

傘ブランチ: `meter-ingest-retention`
ターゲット: `master`

## 概要

`ocw-meter` の使用量の記録（`usage.message`）は、Claude Code の transcript（`~/.claude/projects/*/*.jsonl`）を
`ingest` して初めて作られる。ところが `ingest` は手で叩くか `report` / `dash` を叩いたときにしか走らず、Claude Code は既定で
30 日より古い transcript を消す。この2つが重なり、2026-08-06〜09-04 の 30 日間の使用量が永久に失われた。この傘で再発を防ぐ。

1. **transcript の保持期間を延ばす（孫1）。** `claude/settings.json` に `cleanupPeriodDays` を足し、値と理由を ADR に残す。
   孫2 の自動の取り込みが届かない隙間（長く Claude Code を使わなかった後の起動など。設計1）の保険
2. **ingest を定期的に自動で走らせる（孫2）。** statusLine の `snapshot-quota` を起点に、間引いて、呼び出し元を止めない形
   （バックグラウンド・ロック）で ingest を起動する。再発防止の本体
3. **取り込みが遅れていることに、`report` を叩かなくても気づけるようにする（孫3）。** statusLine に鮮度の警告を出す。
   孫2 の自動の取り込みが失敗し続けたときの見張り

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。転記後に削除済みで
> 参照できない前提で書く）を material として司令官が起草したものである。** ブリーフに
> 書かれていた問題意識・決定事項・既存の穴・実測値・制約・スコープ外・必須の検証ステップ・
> 孫分割の叩き台は本計画書へ転記済みであり、以降はこの計画書が正典である。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `mir-01-transcript-retention` | `claude/settings.json` に `cleanupPeriodDays` を足し、値（ディスク使用量の実測から決める）と理由を ADR に残す | 🔄 実装中 |
| 2 | `mir-02-background-ingest` | statusLine の `snapshot-quota` から、間引き・バックグラウンド・ロック付きで ingest を自動起動する。方式の比較と選択を ADR に残す | 🔄 実装中 |
| 3 | `mir-03-statusline-stale-warning` | 取り込みが一定時間以上止まっている・自動の取り込みが失敗し続けていることを statusLine に短く出す | ⬜ 待機中 |

依存:

- 孫1 と孫2 は**並列**（最初に同時に spawn する）。孫1 は `claude/settings.json` と ADR、孫2 は `bin/ocw-meter` と
  そのテスト・文書・ADR を触るので、ぶつかるとすれば `docs/` の索引程度。後からマージされる側が傘へ rebase で追随する
- 孫3 は**孫2 が傘にマージされてから** spawn する（孫2 が残す「最後に自動の取り込みを試みた時刻・結果」を読み、同じ
  `snapshot-quota` の経路を触るため）。孫1 の完了は待たない

## ワークスペースラベル

接頭辞は `ocw label-prefix`（dotfiles では `dotfiles`）。

- 傘: `dotfiles :: 記録欠落の再発防止`
- 孫1: `dotfiles :: 記録欠落の再発防止 孫1 transcript 保持を延長`
- 孫2: `dotfiles :: 記録欠落の再発防止 孫2 ingest の自動実行`
- 孫3: `dotfiles :: 記録欠落の再発防止 孫3 取り込み遅れの警告`

## 背景1: 問題意識（要約）

前の傘 `ocw-meter-pretty-charts`（PR #192 で master にマージ済み）で足した `ocw-meter dash` のヒートマップを人間が見て、
8 月だけ大きく穴が開いていることに気づいた。相談の AI が原因を調べ、transcript が取り込まれる前に Claude Code に消されて
いたことを報告すると、人間はこれを深刻と受け止め、二度と起きないようにしたいと求めた。PR #192 のマージ後、この件を
傘として振り分けるよう指示した。

## 背景2: 人間が確定させた決定事項（覆さないこと）

- 目的は「使用量の記録（`usage.message`）が、取り込み前に transcript が消えて欠落する」ことの**再発防止**
- dotfiles だけで閉じる・PR は複数本・司令官は dotfiles（task-intake で人間が確認済み）
- 失われた 2026-08-06〜09-04 の記録の復元はこの傘の目的ではない（このマシンには元の transcript が残っていない。背景4）

## 背景3: 既存の穴（相談の AI が 2026-11-01 に調べた事実）

1. **`usage.message` は transcript（`~/.claude/projects/*/*.jsonl`）を ingest して初めて記録される。** ingest が走るのは
   `ocw-meter ingest` を手で叩いたときと、`report`（と `dash`）を叩いたときの先頭（`bin/ocw-meter` の `auto_ingest_for_report()`。
   計画書 DOC-2608081456 孫2 / PR #57、2026-08-08 マージ）だけ。定期的に走る仕組みは無い
2. **Claude Code は既定で 30 日より古い transcript を自動で消す**（設定 `cleanupPeriodDays`、既定 30）。dotfiles の配布物
   `claude/settings.json` にも、このマシンの `~/.claude/settings.json` にも `cleanupPeriodDays` の指定は無い
3. 1 と 2 が重なると、「30 日以上 `report` を叩かない」だけで、その間の使用量が永久に失われる。鮮度の警告
   （`ingest_freshness_footer()` の `ingest_freshness_warning`）は `report` を叩いたときにしか見えず、叩かない間は誰も気づけない
4. 一方、`quota.sample` は statusLine（`claude/settings.json` の `"statusLine": {"command": "ocw-meter snapshot-quota"}`）から、
   run / phase / review.round 等は hook・`ocw` からその場で書かれるので、欠落期間中も残っている。欠けたのは transcript 経由の
   `usage.message` だけ

## 背景4: 実測値

### 4.1 ブリーフに書かれていた実測（2026-11-01、このマシン、`~/.local/state/ocw-meter`、`--no-ingest` で読むだけ）

- `report --daily --days 120 --json --no-ingest`: 2026-08-06〜09-04 の 30 日間、`usage.message` が 0 件。前後は
  08-05: 65.6M（重み付き）/ 2,019 件、09-05: 33.9M / 739 件
- 同期間の日別イベントファイルには `quota.sample`・`run.start/end`・`phase.*`・`review.round` はある（例: 08-06 に
  quota.sample 633 件・run.start 19 件、08-20 に quota.sample 234 件）。Claude Code は使われていた
- `state/ingest-cursor.json`: 取り込み済みの transcript 2,874 本。そのうち最終更新が 7 月のもの 321 本・8 月のもの 105 本は
  **すべて今は存在しない**。9 月のもの 448 本のうち 439 本も存在しない。8 月分の最終更新日は 08-05 が最後
  （= 08-05 ごろの ingest の後、次の ingest まで約 1 か月空いた）
- 記録が戻るのはちょうど 09-05 から。次の ingest が 10-05 ごろに走り、その時点で残っていた 30 日分だけを拾ったと見るのが
  自然（推定。ingest の実行時刻の履歴は残っていないので確定はできない）
- `ingest` は 1 回およそ 1 分半かかる（前の傘の計画書 DOC-2610312019「スコープ外」に記載の実測）

### 4.2 司令官が確かめたこと（2026-11-01、master 8875ec4、このマシン）

- `~/.claude/projects` の transcript は **2,189 本・14 GB**。最終更新の月の内訳は 9 月 9 本・10 月 2,013 本・11 月 167 本で、
  いちばん古いものは 2026-09-13。**このマシンでは 1 か月あたりおよそ 14 GB 増える**（孫1 の値の決め方に効く。設計1）。
  ホームのディスクは 1,007 GB 中 567 GB 空き
- `ingest-cursor.json` の `last_ingest_at` は 2026-10-31T11:09:33Z（前の傘の作業中に `report` が走ったもの）
- `bin/ocw-meter`（約 8,300 行。bash ラッパー + 埋め込み Python）の関係箇所:
  - `auto_ingest_for_report()`（`perform_ingest(root)` を呼び、失敗しても例外を投げず `{"status": "failed", ...}` を返す）
  - `ingest_freshness_footer()` と `INGEST_STALE_THRESHOLD_SECONDS = 24 * 60 * 60`（`report` の鮮度の警告の閾値）
  - `cmd_snapshot_quota()`: stdin の statusLine JSON を読み、表示の1行を作り、`record_quota_sample()` で保存し、必ず
    0 で終わる（fail-open。3段それぞれを try で囲んでいる）。bash 側も `snapshot-quota` は終了コードを 0 に倒し、空行を保証する
  - 保存のロックは `fcntl.flock` の1本（`state/.lock`）。**`write_event()`（`quota.sample` の書き込みが通る）は 0.1 秒で諦める**
    一方、**ingest の `bulk_write_events()` はバッチ全体のあいだロックを握る**（取得の待ちは 30 秒）。自動の ingest が
    ロックを長く握ると、その間の `quota.sample` が書けずに落ちうる（孫2 で確かめること。設計2）
- `claude/settings.json` の hook は `PreToolUse`（git-guard）と `PostToolUse`（compact-reminder）だけ。`statusLine` は
  `ocw-meter snapshot-quota`。`cleanupPeriodDays` は無い。`settings.machine.json` で machine ごとに上書きできる
  （`claude/deploy.sh` がマージする。DOC-2610150520-b）

## 決定的な制約（孫は全部守ること）

- dotfiles の `AGENTS.md` の最重要ルール（`master` を書き換える操作は人間だけ。deploy スクリプトを人間の指示なしに実 `$HOME` で
  実行しない。`claude/settings.json` を変えても、配るのは人間の `deploy-all.sh`。linter の抑制を AI の判断で足さない）
- `claude/settings.json` は**配布される成果物**（`claude/deploy.sh` が machine 設定とマージして `~/.claude/settings.json` を生成する）。
  変更は全マシンに効く。詳細は DOC-2610150520-b（デプロイの仕組み）
- `bin/ocw-meter` は 1 ファイルを各マシン（macOS / Linux / WSL2）へ配る bash + 埋め込み Python。**標準ライブラリだけ**。
  **macOS（BSD / bash 3.2）互換を壊さない**。ocw-meter は **fail-open**（計測の失敗で本来の作業を止めない）
- statusLine は Claude Code の画面更新のたびに呼ばれる。**1 分半かかる ingest をそこで同期実行すると画面が固まる。**
  定期実行を足すなら、呼び出し元を止めない形（間引き・バックグラウンド・ロック）にする。`snapshot-quota` の表示の1行と
  `quota.sample` の記録は、自動の取り込みを足しても今までどおり出す・書く
- 見積もり・計測を自動の制御（止める・モデルを替える）に使わない（既存の ocw-meter の方針。ADR DOC-2610310237）
- `--json` の出力形式を変えない（キーを足すのは可）

## スコープ外

- 失われた 2026-08-06〜09-04 の記録の復元
- ingest 自体の高速化（前の傘で「スコープ外」とした件。孫2 で、バックグラウンドで走らせても困らないかを確かめ、困るなら
  司令官に報告する。この傘の中で速くするかは、そのとき司令官が人間と決める）
- `report` / `dash` の見た目の変更（前の傘で済んだ）
- OS のスケジューラ（cron / launchd / systemd timer）への登録（設計2 で却下した。理由はそこに書いた）

## 必須の検証ステップ

- dotfiles の `AGENTS.md`「コミット前の必須ステップ」に従う（詳細は DOC-2610150520）:
  - 変更したファイルごとに `pre-commit run --files <path>`（新規・大幅変更の時点で）と、最後に `pre-commit run --all-files`
  - `bin/` を変えたら `python3 -m unittest discover -s bin/tests -v`
  - デプロイ関連のシェルや `claude/settings.json` の配り方を変えたら `tests/deploy_smoke.sh`（キーを1つ足すだけなら配り方は
    変わらないので不要）
  - `docs/` に新規ファイルを足すなら `DOC-DOCID_PLACEHOLDER_<名前>.md` で作って `./tools/doc-id/doc-id assign <path>`、最後に
    `./tools/doc-id/doc-id verify`
- 実 `$HOME` を汚さない検証は DOC-2608020715-b（テスト方針）に従う。デプロイの動作確認は `./deploy-all.sh --dry-run`
- ocw-meter の実データでの確かめは、本物の保存先に対して `--no-ingest` を付けて読むだけにする。**自動の取り込みの動作確認は、
  一時ディレクトリに置いた保存先と合成の transcript で行い、本物の保存先へは書かない**（保存先は `OCW_METER_HOME`、transcript の場所は `OCW_METER_CLAUDE_PROJECTS_DIR` で
  差し替えられる。詳しくは `bin/ocw-meter --help` と既存テストを見る）

## テスト方針（dotfiles AGENTS.md「テスト方針」と DOC-2610150520-a に従う）

- 孫1: 設定のキーを1つ足すだけなので、新しい自動テストは要らない（JSON として正しいことと schema の検査は pre-commit が見る）
- 孫2: 守るのは「statusLine を止めない」「二重に走らない」「間引きが効く」「失敗しても表示と `quota.sample` は出る」の4つ。
  **`snapshot-quota` が自動の取り込みの完了を待たずに戻ること（バックグラウンドで起動し、呼び出し元をブロックしないこと）は
  必ず自動テストで固定する**（ここが壊れると、全マシンの Claude Code の画面が毎回 1 分半固まる）。実際に子プロセスを起動する
  テストは、合成の保存先と、すぐ終わる ingest で1つの scenario にまとめる程度にする
- 孫3: 鮮度の判定（閾値の手前と後ろ・失敗の記録あり）で表示に警告が付く・付かないを1つの scenario で確かめる程度。
  表示の1行を丸ごと文字列で固定するテストは作らない

## 設計0: 全孫に共通の方針（司令官が決めた）

1. **守りは二段にする。** 本体は孫2 の自動の取り込み（使っている間は欠かさず拾う）。孫1 の保持期間の延長は、孫2 が
   届かない隙間の保険。孫3 は孫2 が壊れたときに人間が気づくための見張り。どれか1つに頼らない
2. **自動の取り込みは「Claude Code を使っている間」に走れば足りる。** transcript は Claude Code を使っている間にしか増えず、
   statusLine も使っている間にしか呼ばれない。だから statusLine を起点にすれば、増えた分を消える前に拾える
   （例外は設計1 の隙間）
3. **新しい外部依存・常駐プロセス・OS のスケジューラを足さない。** 1 ファイルを配るだけで全マシンで動く今の形を保つ

## 設計1: transcript の保持期間を延ばす（孫1）

- `claude/settings.json` に `cleanupPeriodDays` を足す。**保険の役目は、孫2 が届かない隙間を埋めること**:
  孫2 は statusLine 起点で間引いて走るので、最後の取り込みの後に少し使ってから長く Claude Code を開かなかった場合、
  次に起動したときの掃除（Claude Code は起動時に古い transcript を消す）が取り込みより先に走り、最後の少しを失いうる。
  保持期間はこの「長く使わない期間」より長くすればよい
- **値はディスク使用量の実測から決め、ADR に理由を残す。** このマシンでは 1 か月あたり約 14 GB 増える（背景4.2）ので、
  1 年（365）にすると 170 GB 前後になる。値の目安は 90 日前後（このマシンで約 40 GB）だが、孫が実測と他の選択肢
  （180 / 365 など）を比べて決めてよい。マシンごとに違う値にしたいときは `settings.machine.json` で上書きできることも ADR に書く
- **`cleanupPeriodDays` の意味を Claude Code の公式の文書で確かめる**（数え方の基準〈最終更新か作成か〉、0 を入れたときの
  扱い〈版によっては保存そのものを止める〉、上限）。0 や負の値は使わない。確かめた出典を ADR に書く
- `claude/README.md` に設定の一覧があれば、そこにも足す
- 配るのは人間の `deploy-all.sh`。孫は deploy しない

## 設計2: ingest を定期的に自動で走らせる（孫2）

**司令官の判断: 起点は statusLine の `snapshot-quota` にする。** 方式の比較は ADR に残す。比べる候補と司令官の見立て:

| 方式 | 見立て |
|---|---|
| statusLine（`snapshot-quota`）から、間引いてバックグラウンドで起動 | **採る。** 既に全マシンに配られていて、Claude Code を使っている間だけ確実に呼ばれる（設計0 の2）。新しい配線が要らない |
| hook（`SessionStart` / `Stop` 等）から起動 | 次点。`claude/settings.json` に hook を足す必要があり、hook の種類ごとに呼ばれる頻度が違う。孫が statusLine より明らかに良いと示せれば、ADR に理由を書いて採ってよい |
| OS のスケジューラ（cron / launchd / systemd timer） | **採らない。** `$HOME` への symlink だけで配る今の deploy の外に出る（macOS は launchd、Linux は cron/systemd、WSL2 は cron が既定で動かない）。Claude Code を使っていない間も回る |

実装の要件:

1. **呼び出し元を止めない。** `snapshot-quota` は、間引きの判定を済ませたら、ingest を**切り離した子プロセス**として起動し
   （標準入出力を切る・新しいセッションにする等。macOS でも動く方法）、完了を待たずに今までどおり表示の1行を出して戻る
2. **間引く。** statusLine は画面更新のたびに呼ばれるので、間引きの判定はファイルを1つ読む程度の軽さにする（2,000 本超の
   エントリを持つ `ingest-cursor.json` を毎回読まない）。間隔は孫が決めて ADR に残す（目安: 1 時間前後。短すぎると無駄に走り、
   長すぎると設計1 の隙間が広がる）。「最後に自動の取り込みを試みた時刻」と「その結果（成功・失敗とエラー）」を、孫3 が
   安く読める小さな状態ファイルに残す
3. **二重に走らせない。** 前回の自動の取り込みがまだ走っている間は起動しない（ノンブロッキングのロック等）。手で叩いた
   `ingest` / `report` の ingest と重なったときも壊れない（既存の保存のロックがあるが、待ちの間に何が起きるかを確かめる）
4. **`quota.sample` を落とさない。** 背景4.2 のとおり、`quota.sample` の書き込みはロックを 0.1 秒しか待たず、ingest の書き込みは
   バッチ全体のあいだロックを握る。自動の取り込みが走っている間に `quota.sample` がどれだけ落ちるかを合成のデータで測り、
   無視できない量なら、ロックを握る時間を短くする等で対処する（対処が大きくなるなら司令官に報告する）
5. **fail-open。** 起動の失敗・子の ingest の失敗は、statusLine の表示と `quota.sample` の記録に影響させない。失敗は
   状態ファイル（2）と既存の `emit_meter_error` に残す
6. **止める手段を用意する。** 環境変数などで自動の取り込みを無効にできるようにする（テストと、使いたくないマシンのため）。
   既存の `OCW_METER_*` の環境変数の命名に合わせる
7. 文書: `bin/ocw-meter --help`・`bin/README.md`・`docs/reference/DOC-2608021229-b`（計測手順）に、自動の取り込みがあること、
   間隔、無効にする方法、状態ファイルの場所を書く。方式の比較と決定は ADR（`docs/adr/`）に残す

## 設計3: 取り込みの遅れを statusLine で知らせる（孫3）

- 孫2 の状態ファイル（最後に自動の取り込みを試みた時刻・結果）と、取り込みに成功した最後の時刻を読み、次のどちらかのとき
  だけ statusLine の表示の1行に短い警告を足す（ふだんは何も足さない）:
  - 取り込みに成功した最後の時刻から一定時間以上たっている（閾値は孫2 の間隔から決める。目安は間隔の数倍〜1 日。
    `report` の `INGEST_STALE_THRESHOLD_SECONDS`〈24 時間〉と揃えるかも孫が判断する）
  - 自動の取り込みが続けて失敗している
- 警告は短く（例: `⚠ ingest 3d` のような数文字）、色に頼らず読めるようにする。読むのは小さなファイル1つ程度にし、
  statusLine を重くしない
- 「最古の未取り込み transcript が保持期限に近い」ことの検知（ブリーフの叩き台にあった案）は、transcript の一覧を
  statusLine から毎回なめることになり重いので、**孫2 の状態ファイルで足りるなら作らない**。作るなら間引いた側
  （孫2 の子プロセス）で数え、結果を状態ファイルに書く形にする
- 文書: `bin/README.md` と `docs/reference/DOC-2608021229-b` に警告の意味と対処（`ocw-meter ingest` を手で叩いて結果を見る等）を書く

## 孫ブランチ分割の叩き台（ブリーフより転記。採った分割は上の進捗テーブル）

ブリーフの叩き台（相談の AI が出したもので、司令官が再設計してよいとされていた）:

- A: transcript の保持期間を延ばす（`claude/settings.json` に `cleanupPeriodDays` を足す。値と理由を ADR に残す。
  ディスク使用量の実測が要るかもしれない）。いちばん小さく、すぐ効く
- B: ingest を定期的に自動で走らせる（statusLine の `snapshot-quota` から間引いてバックグラウンドで起動する／hook から／
  別の仕組み、の比較と選択。ロック・重複起動・fail-open・macOS 互換）
- C: 取り込みが遅れていることに、`report` を叩かなくても気づけるようにする（例: statusLine に鮮度の警告を出す。
  「最古の未取り込み transcript が保持期限に近い」ことの検知など）
- B が入れば C の必要性は下がるかもしれない。A は B・C と独立

司令官の判断: A→孫1、B→孫2、C→孫3 とそのまま採った。C は B が入っても、B が黙って失敗し続ける場合の見張りとして
残す価値がある（設計0 の1）が、B の状態ファイルに乗せて小さくする（設計3）。順序は A と B を並列、C は B の後。

## 進行記録

（司令官が運用中に分かったこと・人間の決定をここに追記する）

- 2026-11-01: 計画書を起草した。傘は `origin/master`（8875ec4）から切られている。孫1・孫2 を並列で spawn する。孫3 は孫2 のマージ後

## 孫1用プロンプト:

````markdown
# 傘ブランチ: meter-ingest-retention
# 孫ブランチ: mir-01-transcript-retention
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/meter-ingest-retention/docs/planning/DOC-2611010249_meter-ingest-retention_計画.md`

**まず計画書の「概要」「背景2」「背景3」「背景4」「決定的な制約」「スコープ外」「必須の検証ステップ」「テスト方針」「設計0」「設計1」
「進行記録」を読むこと。** 続けて dotfiles の `AGENTS.md` の作業別の索引から、デプロイの仕組み（DOC-2610150520-b）・
コミット前（DOC-2610150520）・実装時の注意（DOC-2610150520-c）を読む。

## 実装開始前の必須手順

`ocw` がすでに `mir-01-transcript-retention` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/meter-ingest-retention` の
先端から切られていることを確かめる（`git pull` は使わない）。

## やること

1. Claude Code の公式の文書で `cleanupPeriodDays` の意味（数え方の基準・0 の扱い・上限）を確かめる（計画書 設計1）
2. transcript のディスク使用量を実測する（`du` などで読むだけ。消さない・動かさない）。計画書 背景4.2 の値を出発点にしてよい
3. 値を決め、`claude/settings.json` に `cleanupPeriodDays` を足す。`claude/README.md` に設定の説明があれば足す
4. ADR を `docs/adr/` に足す（`DOC-DOCID_PLACEHOLDER_<名前>.md` で作って `./tools/doc-id/doc-id assign <path>`）。
   書くこと: 欠落が起きた仕組み（計画書 背景3・4 の要約）、この設定が孫2 の自動の取り込みの「保険」である理由（設計1）、
   値と比べた選択肢とディスク使用量、0 を使わない理由と出典、マシンごとの上書き（`settings.machine.json`）
5. deploy はしない（配るのは人間）。PR 本文に「マージ後に人間が `deploy-all.sh` で配ると効く」と書く

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- `claude/settings.json` が JSON として正しく、既存の pre-commit の検査を通る
- 既存の設定のキーを消したり変えたりしていない

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。
この孫では新しい自動テストは要らない（計画書「テスト方針」）。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --all-files
./tools/doc-id/doc-id verify
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `meter-ingest-retention` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** `/pr-review-loop` の手順にマージへ進む記述があっても実行しない
   （孫が人間のフィードバック前に勝手にマージするのを防ぐため。マージは傘の司令官が行う）
5. 最終報告を書き終えたら、最後の行動として、司令官が spawn の送信文で渡した司令官の Herdr ペインへ
   承認を報告する（渡されていなければ報告せず、人間に「承認済み。マージは司令官（または人間）が行う」と伝えて止まる）。
   送り方は umbrella-orchestrator スキル §5「AI間送信手順（二段構え）」に従う。本文は
   「孫1 `mir-01-transcript-retention` の PR #<番号> が HEAD <短縮SHA> で承認されました。マージをお願いします。」
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

## 大きい出力を文脈へ流し込まない（実装中ずっと）

文脈の膨張は、1k〜20k字級の出力の積み重ねと、自分で書く長い出力で起きる。次を守ること:
- ファイルを `cat` / `sed -n` で丸ごと読まず、`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む
- 約100行・5,000字を超えそうな出力（テスト・分析・ログ・`git diff`・JSON）は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る
- 既存の長いファイルや、繰り返し直して実行するスクリプトを Write / heredoc で丸ごと書き直さない。一度ファイルに置き、変更は Edit の差分で行う（新規ファイルを最初に1回書くのは構わない）

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `meter-ingest-retention` から切ること**。master から切ると PR の diff に傘ブランチ全体が
混入してレビュー不能になる。`ocw` が `origin/meter-ingest-retention` から切ったワークツリーを用意済みなので、
上の「実装開始前の必須手順」で確かめるだけでよい（`git pull` は使わない）。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

## 孫2用プロンプト:

````markdown
# 傘ブランチ: meter-ingest-retention
# 孫ブランチ: mir-02-background-ingest
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/meter-ingest-retention/docs/planning/DOC-2611010249_meter-ingest-retention_計画.md`

**まず計画書の「概要」「背景2」「背景3」「背景4」「決定的な制約」「スコープ外」「必須の検証ステップ」「テスト方針」「設計0」「設計2」
「設計3」「進行記録」を読むこと。**（設計3 は孫3 の仕事だが、孫3 があなたの状態ファイルを読むので、何を残すべきかを知っておく）
続けて dotfiles の `AGENTS.md` の作業別の索引から、テスト（DOC-2610150520-a）・コミット前（DOC-2610150520）・
シェル（DOC-2608020715-a。bash 側を触るときだけ）を読む。

## 実装開始前の必須手順

`ocw` がすでに `mir-02-background-ingest` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/meter-ingest-retention` の
先端から切られていることを確かめる（`git pull` は使わない）。

## やること

1. 計画書 設計2 の実装の要件 1〜6 を実装する（`snapshot-quota` からの間引き・切り離した子プロセスでの ingest の起動・
   二重起動の防止・`quota.sample` を落とさないことの確認と対処・fail-open・無効にする手段）
2. 状態ファイル（最後に自動の取り込みを試みた時刻・結果・エラー）の場所と形を決め、孫3 が安く読めるようにする
3. 計画書 設計2 の 7 の文書を直し、ADR を `docs/adr/` に足す（`DOC-DOCID_PLACEHOLDER_<名前>.md` で作って
   `./tools/doc-id/doc-id assign <path>`）。方式の比較表（statusLine / hook / OS のスケジューラ）・間隔・ロック・
   `quota.sample` への影響の実測を書く
4. 動作確認は、一時ディレクトリの保存先と合成の transcript で行う。**本物の保存先（`~/.local/state/ocw-meter`）と
   本物の transcript へは書かない。** `snapshot-quota` を連続で呼んで、(a) すぐ戻る、(b) 間隔の中では2回目が起動しない、
   (c) 子の ingest が終わると状態ファイルと `usage.message` が増える、を確かめ、PR 本文に結果を書く
5. ingest をバックグラウンドで走らせても困らないか（CPU・ロックを握る時間）を測る。困るなら実装を広げず司令官に報告する
   （ingest の高速化はこの傘のスコープ外。計画書「スコープ外」）

`bin/ocw-meter` は全マシン（macOS / Linux / WSL2）の statusLine から呼ばれる。子プロセスの切り離し方は macOS でも
動く方法にすること（Python の標準ライブラリで足りるはず）。

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- `snapshot-quota` が自動の取り込みの完了を待たずに戻る（バックグラウンドで起動し、呼び出し元をブロックしない）
  > **この regression は必ず自動テストで固定する**
- 間隔の中では自動の取り込みが起動しない。前回がまだ走っている間も起動しない
- 自動の取り込みの起動や子の ingest が失敗しても、`snapshot-quota` の表示の1行と `quota.sample` の記録は今までどおり出る
  （既存の fail-open のテストで守られていれば足さない）
- 無効にする手段を使うと起動しない

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。
**既存のテストが `snapshot-quota` を呼ぶとき、本物の ingest が裏で走り出さないようにすること**（無効にする手段か、
テスト用の保存先で）。

## 実行すべき検証コマンド（省略しない）

```bash
python3 -m unittest discover -s bin/tests -v > "$(mktemp -d)/unittest.log" 2>&1; echo $?
pre-commit run --all-files
./tools/doc-id/doc-id verify
```

（unittest の出力は長いので一時ファイルへ書き出し、`tail` で結果だけ見る）

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `meter-ingest-retention` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** `/pr-review-loop` の手順にマージへ進む記述があっても実行しない
   （孫が人間のフィードバック前に勝手にマージするのを防ぐため。マージは傘の司令官が行う）
5. 最終報告を書き終えたら、最後の行動として、司令官が spawn の送信文で渡した司令官の Herdr ペインへ
   承認を報告する（渡されていなければ報告せず、人間に「承認済み。マージは司令官（または人間）が行う」と伝えて止まる）。
   送り方は umbrella-orchestrator スキル §5「AI間送信手順（二段構え）」に従う。本文は
   「孫2 `mir-02-background-ingest` の PR #<番号> が HEAD <短縮SHA> で承認されました。マージをお願いします。」
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

## 大きい出力を文脈へ流し込まない（実装中ずっと）

文脈の膨張は、1k〜20k字級の出力の積み重ねと、自分で書く長い出力で起きる。次を守ること:
- ファイルを `cat` / `sed -n` で丸ごと読まず、`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む
  （`bin/ocw-meter` は約 8,300 行、`bin/tests/test_ocw_meter.py` は約 5,600 行ある）
- 約100行・5,000字を超えそうな出力（テスト・分析・ログ・`git diff`・JSON）は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る
- 既存の長いファイルや、繰り返し直して実行するスクリプトを Write / heredoc で丸ごと書き直さない。一度ファイルに置き、変更は Edit の差分で行う（新規ファイルを最初に1回書くのは構わない）

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `meter-ingest-retention` から切ること**。master から切ると PR の diff に傘ブランチ全体が
混入してレビュー不能になる。`ocw` が `origin/meter-ingest-retention` から切ったワークツリーを用意済みなので、
上の「実装開始前の必須手順」で確かめるだけでよい（`git pull` は使わない）。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

## 孫3用プロンプト:

````markdown
# 傘ブランチ: meter-ingest-retention
# 孫ブランチ: mir-03-statusline-stale-warning
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/meter-ingest-retention/docs/planning/DOC-2611010249_meter-ingest-retention_計画.md`

**まず計画書の「概要」「背景2」「背景3」「背景4」「決定的な制約」「スコープ外」「必須の検証ステップ」「テスト方針」「設計0」「設計2」
「設計3」「進行記録」を読むこと。** 孫2 がこの傘にマージ済みなので、孫2 の ADR（`docs/adr/` にある、自動の取り込みの方式を
決めたもの）と、孫2 が足した状態ファイルの読み書きのコードも読む。続けて dotfiles の `AGENTS.md` の作業別の索引から、
テスト（DOC-2610150520-a）・コミット前（DOC-2610150520）を読む。

## 実装開始前の必須手順

`ocw` がすでに `mir-03-statusline-stale-warning` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/meter-ingest-retention` の
先端から切られていることを確かめる（`git pull` は使わない）。

## やること

1. 計画書 設計3 を実装する（孫2 の状態ファイルと最後に成功した取り込みの時刻から、遅れ・失敗の続きを判定し、
   そのときだけ `snapshot-quota` の表示の1行に短い警告を足す）
2. 閾値を決める（孫2 の間隔から。理由はコードのコメントか孫2 の ADR への追記で残す）
3. 計画書 設計3 の文書（`bin/README.md`・`docs/reference/DOC-2608021229-b`）を直す
4. 一時ディレクトリの保存先で、遅れていないとき・遅れているとき・失敗が続いているときの表示の例を作り、PR 本文に貼る
   （本物の保存先へは書かない）

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 遅れも失敗も無いとき、表示の1行が今までと変わらない
- 閾値を超えて遅れている・自動の取り込みが失敗し続けているときだけ、警告が付く
- 状態ファイルが無い・壊れているときも、`snapshot-quota` は今までどおり表示の1行を出して 0 で終わる（fail-open）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。
表示の1行を丸ごと文字列で固定するテストは作らない（計画書「テスト方針」）。

## 実行すべき検証コマンド（省略しない）

```bash
python3 -m unittest discover -s bin/tests -v > "$(mktemp -d)/unittest.log" 2>&1; echo $?
pre-commit run --all-files
./tools/doc-id/doc-id verify
```

（unittest の出力は長いので一時ファイルへ書き出し、`tail` で結果だけ見る）

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `meter-ingest-retention` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** `/pr-review-loop` の手順にマージへ進む記述があっても実行しない
   （孫が人間のフィードバック前に勝手にマージするのを防ぐため。マージは傘の司令官が行う）
5. 最終報告を書き終えたら、最後の行動として、司令官が spawn の送信文で渡した司令官の Herdr ペインへ
   承認を報告する（渡されていなければ報告せず、人間に「承認済み。マージは司令官（または人間）が行う」と伝えて止まる）。
   送り方は umbrella-orchestrator スキル §5「AI間送信手順（二段構え）」に従う。本文は
   「孫3 `mir-03-statusline-stale-warning` の PR #<番号> が HEAD <短縮SHA> で承認されました。マージをお願いします。」
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

## 大きい出力を文脈へ流し込まない（実装中ずっと）

文脈の膨張は、1k〜20k字級の出力の積み重ねと、自分で書く長い出力で起きる。次を守ること:
- ファイルを `cat` / `sed -n` で丸ごと読まず、`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む
  （`bin/ocw-meter` は約 8,300 行、`bin/tests/test_ocw_meter.py` は約 5,600 行ある）
- 約100行・5,000字を超えそうな出力（テスト・分析・ログ・`git diff`・JSON）は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る
- 既存の長いファイルや、繰り返し直して実行するスクリプトを Write / heredoc で丸ごと書き直さない。一度ファイルに置き、変更は Edit の差分で行う（新規ファイルを最初に1回書くのは構わない）

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `meter-ingest-retention` から切ること**。master から切ると PR の diff に傘ブランチ全体が
混入してレビュー不能になる。`ocw` が `origin/meter-ingest-retention` から切ったワークツリーを用意済みなので、
上の「実装開始前の必須手順」で確かめるだけでよい（`git pull` は使わない）。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````
