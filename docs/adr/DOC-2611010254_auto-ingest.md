# ADR: ocw-meter の ingest を、statusLine から間引いて自動で走らせる

## ステータス

決定（2026-11-01）。傘 `meter-ingest-retention`（計画書 DOC-2611010249）の孫2 で決めた。実装は `bin/ocw-meter` の
「automatic background ingest」の区画（`maybe_start_auto_ingest()` / `cmd_auto_ingest()`）、使い方は
[bin/README.md](../../bin/README.md) と [DOC-2608021229-b](../reference/DOC-2608021229-b_LLM費用観測ベースライン計測手順.md) §2.3。

## 1. 背景

`usage.message` は Claude Code の transcript を `ingest` して初めて作られる。`ingest` は手で叩くか `report` / `dash` を叩いたときにしか
走らず、Claude Code は既定で 30 日より古い transcript を消す。このため 2026-08-06〜09-04 の 30 日間の `usage.message` が永久に失われた
（`quota.sample` や run / phase の記録は hook・statusLine からその場で書かれるので残っている）。再発防止の本体として、使っている間は
欠かさず拾う自動の取り込みを足す。transcript は Claude Code を使っている間にしか増えないので、「使っている間に走れば足りる」。

## 2. 決定

1. **起点は statusLine の `snapshot-quota`。** 間隔（既定 1 時間）に1回、`ocw-meter auto-ingest`（内部用のサブコマンド）を
   **切り離した子プロセス**（`start_new_session=True`・stdin/stdout/stderr を `/dev/null`・`close_fds`）として起動し、完了を待たずに
   表示の1行を出して戻る。標準ライブラリだけで書けるので macOS（BSD / bash 3.2）でも動く
2. **間引きは小さな状態ファイル1つで判定する。** `state/auto-ingest.json`（数百バイト）の `last_attempt_at` を読むだけ。2,000 本超の
   エントリを持つ `ingest-cursor.json` は読まない。起動の直前に `last_attempt_at` を書いてから子を起こすので、複数ペインの statusLine が
   同時に呼んでも、ほぼ1本しか起動しない
3. **二重に走らせないのは子のロック。** 子は `state/auto-ingest.lock` を `flock(LOCK_EX|LOCK_NB)` で取り、取れなければ黙って終わる。
   前回がまだ走っている間・手で叩いた `auto-ingest` と重なった間は走らない。手で叩く `ingest` / `report` とは別のロックなので止め合わない
   （保存側の `state/.lock` は `bulk_write_events` が30秒まで待つ既存のままで、壊れずに直列化される）
4. **起動は「保存先がすでにある」ときだけ。** 直前の `record_quota_sample` が保存先を作る（Git ワークツリー内の保存先は拒否して作らない）。
   だから、拒否された保存先に状態ファイルや子が生まれることはない。保存先を作る前の最初の1回目は起動せず、次の呼び出しで起動する
5. **fail-open。** 起動の判定・状態ファイルの読み書き・`Popen` は、`snapshot-quota` の4段目として個別に例外を握りつぶす。表示の1行、
   `quota.sample` の記録、終了コード 0 は変わらない。子の失敗は `state/auto-ingest.json` と `state/meter-errors.jsonl`
   （`auto_ingest_failed` / `auto_ingest_spawn_failed`）に残る
6. **無効にする手段。** `OCW_METER_AUTO_INGEST=0`（`false` / `no` / `off` も可）。間隔は `OCW_METER_AUTO_INGEST_INTERVAL`（秒）。
   テストの共通ヘルパは既定で無効にする
7. **孫3 が読む状態ファイルの形。** `state/auto-ingest.json`:
   `last_attempt_at`（最後に試みた時刻）・`last_finished_at`・`last_result`（`running` / `ok` / `failed`）・`last_success_at`・
   `last_error`・`consecutive_failures`・`version`（=1）。時刻は UTC の RFC3339

## 3. 方式の比較

| 方式 | 判断 | 理由 |
|---|---|---|
| statusLine（`snapshot-quota`）から間引いて起動 | **採る** | 全マシンに配布済みで新しい配線が要らない。Claude Code を使っている間だけ呼ばれ、transcript が増える間と一致する。呼び出しは画面更新のたびなので間引きが要るが、判定は小さなファイル1つで済む |
| hook（`SessionStart` / `Stop` 等） | 採らない | `claude/settings.json` に hook を足す必要があり、hook の種類ごとに頻度が違う。`SessionStart` は起動時にしか走らず、長く開きっぱなしのセッションの間は拾えない。`Stop` は応答のたびで statusLine より頻度の利点がない。statusLine より明らかに良い点を示せなかった |
| OS のスケジューラ（cron / launchd / systemd timer） | 採らない | `$HOME` への symlink だけで配る deploy の外に出る。macOS は launchd、Linux は cron / systemd、WSL2 は cron が既定で動かない。Claude Code を使っていない間も回る |

## 4. 間隔

既定 1 時間。ingest 1 回の実測（下）は増分で数秒〜、初回の一括で数十秒〜1分半で、1 時間に1回なら負荷として無視できる。一方、
transcript が消えるまでの猶予（保持期間 30 日、孫1 で延長）に対して 1 時間の遅れは十分小さい。短すぎると無駄に走り、長すぎると
「最後の取り込みの後に使って、次の取り込み前に消える」隙間が広がる。1 時間は両方の中間で、孫3 の警告の閾値（間隔の数倍〜1 日）も
決めやすい。

## 5. `quota.sample` への影響の実測

`write_event()`（`quota.sample`）はロックを 0.1 秒しか待たず、`bulk_write_events()`（ingest）はバッチ全体でロックを握る。合成の
transcript と一時の保存先（本物の保存先・本物の transcript には触れていない）で、`ingest` を走らせながら `snapshot-quota` を
**間隔 0 で連続して**呼び続け、`quota.sample` がどれだけ書けたかを数えた（実運用では 1 セッションあたり 60 秒に1回なので、これは
最悪側の見積もり）。

| ケース | ingest の時間 | snapshot の呼び出し | 書けた quota.sample | 最大の待ち |
|---|---|---|---|---|
| 初回の一括（60 本 × 1,000 メッセージ） | 4.4 秒 | 26 | 24 | 0.26 秒 |
| 増分（各 50 メッセージ追加） | 0.8 秒 | 5 | 5 | 0.19 秒 |
| 初回の一括（300 本 × 2,000 = 60 万メッセージ） | 50.1 秒 | 237 | 207（約 13% 欠落） | 0.98 秒 |
| 増分（各 50 メッセージ追加、300 本） | 5.6 秒 | 13 | 12 | 0.65 秒 |

- 欠落は、ロックを握る「書き込みバッチ」の間だけ起きる。実運用は 60 秒に1回なので、増分で数秒のロックなら欠落は最大でも1サンプル
  （次の 60 秒後のサンプルが拾う）。初回の一括のような最悪の場合でも、欠落は 1 分半以内に収まる
- statusLine 側の待ちは最大 1 秒弱（ロックの待ち 0.1 秒 + `git` の呼び出し等）。画面が固まるほどではない
- ロックを握る時間を短くする等の対処は、**入れない**。欠落は `quota.sample` の1サンプルで、次の呼び出しが埋める。ingest の改造は
  この傘のスコープ外（計画書「スコープ外」）
- メモリ: 60 万メッセージの一括で最大 RSS が約 2.8 GB になった。ingest 自体の性質（候補をメモリに溜める）で、手で叩いたときと
  同じ。自動の取り込みは増分が普通なので小さいが、初回や長い空白の後は大きくなりうる。高速化・省メモリ化は別件として司令官に報告する
- CPU: 一括 50 秒のあいだ 1 コアほぼ占有。増分は数秒

## 6. 却下した案

- **子プロセスを待ってから表示する**: 画面更新のたびに数秒〜1 分半固まる。本件の最重要の制約に反する
- **`ingest-cursor.json` の `last_ingest_at` で間引く**: 2,000 本超のエントリを持つファイルを statusLine の度に読む。手で叩いた `ingest` も
  `last_ingest_at` を進めるが、自動の側は独立した状態ファイルで足りる
- **Python の `os.fork()` で切り離す**: 埋め込みプログラムが一時ファイルで、親の bash が終わると消える。子は bash ラッパーを
  `OCW_METER_SELF` で再実行する形にしたので、プログラムの寿命と切り離せた
