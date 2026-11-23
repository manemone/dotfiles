# ADR: 再起動の管制の会話を、Herdr の専用ワークスペースに常駐させ、外からの制御は Claude アプリだけで行う

## ステータス

確定（2026-11-15）。計画書 DOC-2611151244 の孫3。

## 1. 背景

再起動から戻ったあと、止まっていた会話の再開結果を人間のスマホへ知らせ、外から状況を見る・再開させる・止めるの窓口が要る
（計画書 DOC-2611151244 設計3）。再開の判定と送信は `herdr-resume`（ADR DOC-2611151247）、Windows 側の起動は `rebootctl`
（ADR DOC-2611151248）が担う。この ADR は、それらの結果を人間へ届け、人間の指示を受ける常駐の会話の置き方を決める。

## 2. 決定: 外からの制御の経路は Claude アプリ（Remote Control と `PushNotification`）だけにする

| 経路 | 採否 | 理由 |
|---|---|---|
| Claude アプリ（`remoteControlAtStartup` と `PushNotification`） | **採用** | 人間のアカウントの内側で閉じる。承認もスマホから Remote Control で返せ、Claude Code の権限の確認を飛ばさない |
| ntfy・Slack など外部の通知サービス | 不採用 | 通知文に会話名やパスが載り、秘密を人間のアカウントの外へ出す。足すなら人間の確認が先（計画書の決定的な制約） |
| Tailscale 等で SSH して Herdr に入る | 不採用 | 新しい経路と認証を足す。スマホからの操作性も Claude アプリより劣る |

マシンごと落ちて戻らないことの外部からの検知は、計画書のスコープ外とした。戻れば通知が来る・来なければ戻っていない、
Remote Control の会話一覧がオフラインになる、の2つで分かる形に留める。

## 3. 決定: 置き場所・会話名・モデル・巡回の間隔

- **置き場所:** Herdr の専用ワークスペース（ラベル `管制`、cwd は `$HOME`、ペイン1つ）。傘や孫のワークツリーに置かない
  （ワークツリーの掃除で巻き込まれず、どのリポの作業にも属さないため）。`rebootctl boot` の手順4 が起こす。ラベルが
  `管制` のワークスペースが既にあれば作り直さない（冪等）。Herdr が復元した管制の会話は待つだけで起動時の手順が走らないので、
  待機中（`idle` / `done`）ならそのペインへ起動時の手順を送る（承認待ちなど待機中でなければ送らない）。ペインにエージェントが
  居なければ起動し直す
- **会話名:** `再起動管制`（`claude --name`。ADR DOC-2610111939 の流儀。Claude アプリの一覧で一目で分かる日本語）
- **モデル:** Sonnet（`claude --model sonnet`）。常駐して巡回するので費用を抑える（計画書 設計0 の 5）
- **巡回の間隔:** 1時間おき。当初は会話内の `CronCreate` だったが、OS の cron（`rebootctl watch`）へ移した（ADR DOC-2611232111）。`rebootctl status --json` を読むだけで軽い
- **ふるまいの本体:** スキル `skills/control-tower/SKILL.md`。起動時に `last-recovery.json` を読んで1回通知する（巡回の登録は、cron への移行で会話の役目から外れた。ADR DOC-2611232111）。
  通知済みかは `reboot-recovery/control-tower.json` に印を置く（compact・復帰で2度通知しない）。同じ再起動の予告を1回にする印は `rebootctl watch` が書く

## 4. 外からの制御のかたち

- **状況:** `herdr` と `herdr-resume plan` と `last-recovery.json` を読んで答える。書き換えない
- **再開:** 承認待ち・質問待ち（`blocked`）の会話には送らない（承認の代行をしない。承認は Claude アプリでその会話に返してもらう）。
  待機中の会話には `herdr agent prompt` で固定趣旨の文を送る。`timeout` / `stalled` で再送しない
- **止める:** 対象のペインへ `esc` を送り今のターンを中断するだけ。プロセスを殺す・ペインを閉じる・ワークツリーを消す・
  `herdr server stop` はしない
- **破壊的操作・外部サービスへの送信・管理者権限の変更はしない。** 無人の巡回と起動時の手順では質問で止まらない

## 5. 結果

- 管制の会話が戻った会話と同じ Herdr のサーバに居るため、WSL ごと落ちれば管制の会話も止まる。復帰後は `rebootctl boot` が
  ワークスペースの復元を待ったうえで起こし、復元されていなければ新しく立てる。復元されていれば起動時の手順を送る。`herdr-resume` が管制の会話へ送らないので文が重ならない。それでも通知は
  `control-tower.json` の印で1回にする（スキル §1）。再起動待ちの巡回は会話に持たせず cron の `rebootctl watch` だけが回すので、重複しない（ADR DOC-2611232111）
- 管制の会話（ラベル `管制` のワークスペース）は `herdr-resume` の送信の対象から外す（`not_sent` に `code: "control_tower"`・
  `needs_human: false` で載る）。対象にすると、巡回の再登録を促す文のターンが `rebootctl boot` の手順4より先に走って管制の会話が
  `working` になり、起動時の手順が送られず、スマホへの通知が行われないことがあるため。起こすのは手順4だけに任せる（`herdr-resume` は管制のペインの読み込みが済むまで待つので、手順4が読み込み途中のペインに当たらない）。ラベルは
  `bin/herdr-resume` と `bin/rebootctl` の両方に同じ値で書く
- 費用: 平常時は cron が `rebootctl status --json` を読むだけでモデルを呼ばない。常駐の Sonnet が動くのは起動時の通知と外からの依頼のときだけ（ADR DOC-2611232111）

## 6. 確かめた範囲と未確認の範囲

確かめた: `herdr workspace create --cwd --label` が `root_pane.pane_id` を返し、そのペインへ `herdr pane run` でコマンドを流せ、
`herdr workspace close` で閉じられること（使い捨てのワークスペースで実測）。`rebootctl status --json` の形。

**未確認（配布後に人間が確かめる。傘の最終 PR のあとの通しの試験に含める）:**
(1) `PushNotification` がスマホへ届くこと。(2) Claude アプリの Remote Control の一覧に、管制の会話と、Herdr が戻した会話が
出ること（`remoteControlAtStartup`）。出ないなら原因と対処をここに追記する。(3) 外から頼んだ「状況は」「再開して」「止めて」が
設計どおりに動くこと。(4) サインイン無しの起動（`rebootctl` の方式 A）の下で管制の会話の Claude が認証・ネットワーク・
Remote Control を保てること。いずれも WSL や Herdr を落とす試験を含むか、スキルの配布（人間の `deploy-all.sh`）が先に要るため、
孫3 の PR の時点では行っていない。
