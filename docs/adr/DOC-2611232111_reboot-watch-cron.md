# ADR: 再起動待ちの巡回を、会話の CronCreate から OS の cron へ移し、通知は管制の会話に頼む

## ステータス

確定（2026-11-23）。計画書 DOC-2611232047 の孫1。ADR DOC-2611151326 §3 の「巡回の間隔: 1時間おき（`CronCreate`）」を置き換える。

## 1. 背景

管制の会話（ADR DOC-2611151326）は、Windows が再起動待ちかどうかを会話の中の `CronCreate` で1時間おきに確かめていた。
再起動待ちはごく稀なのに、巡回のたびにモデルが1往復し、「変化なし」の往復が会話に溜まってトークンを使う。巡回は会話の
中にしか無く、会話の再起動・終了で消え、期限切れもある。

## 2. 決定: 巡回は OS の cron が `rebootctl watch` で行い、再起動待ちのときだけ管制の会話へ頼む

- cron が1時間おきに `rebootctl watch` を呼ぶ。`watch` は `rebootctl status --json` を読むだけで、再起動待ちでなければ
  何も送らない（モデルを呼ばない）。
- 再起動待ちを見つけたら、管制のペインへ固定の1文（`herdr agent prompt`。送り先の探し方は `rebootctl boot` の手順4と同じ関数）
  を送る。スマホへ通知するのは管制の会話で、手順はスキル `control-tower` §2 に書く。
- 同じ `windows_last_boot` への予告は1回だけ。`$ST/control-tower.json` の `announced_reboot_for` に書くのは `watch` だけで、
  管制の会話は書かない（書く人を1人にする）。再起動待ちが解けたら `watch` が印を消す。ほかの鍵（`notified_boot_id`）は残す。
- 置き場所は `rebootctl` のサブコマンドにした。配布のリンク（`links_for_tool()`）を足さずに済み、`status --json` の読み取りと
  `test_rebootctl.py` の偽物をそのまま使える。

## 3. 却下: cron から `claude -p` で通知する

当初の案は、cron が `claude -p`（`PushNotification` だけを許可）を呼んでスマホへ通知する形だった。実機で確かめて成り立たなかった。

| 確かめたこと | 結果 |
|---|---|
| 対話シェルの `claude -p` | 「この端末がアクティブなので送らない」（`user_present`） |
| cron の下の `claude -p` | 同じ。加えて cron の PATH に `claude` が無く、絶対パスが要る |
| `CLAUDE_CODE_DISABLE_NOTIFICATION_PRESENCE_CHECK=1` で上の判定を外す | 「Mobile push not sent (Remote Control inactive)」 |

スマホへ送る経路は Remote Control のつなぎで、対話のセッションにしか無い（`--remote-control` も対話専用）。`claude -p` では
`PushNotification` を呼べてもスマホへは届かない。Windows のトースト通知は、目的が外出中のスマホ通知なので人間が却下した。
状態ファイルに印だけ書いて管制が次に開かれたときに読む案は、即時性が落ちるので採らなかった。人間がこの ADR の方式
（cron が管制のペインへ送る）を選んだ。

## 4. 決定: 送るのは管制が idle / done のときだけ。印を書く条件

`rebootctl boot` の手順4と同じ扱いにする。

| 管制の状態 | 送るか | 印 |
|---|---|---|
| idle / done | 送る | 成功なら書く |
| `--wait` の timeout / stalled | 送った（届いたか未確認） | 書く（再送で二重に通知しないため） |
| working・blocked（承認待ち） | 送らない | 書かない（次の巡回で試す） |
| 管制のワークスペースが無い・エージェントが居ない・送信が失敗 | 送らない | 書かない（次の巡回で試す） |

届いたか未確認のときは、再送して二重に通知するより、まれに取りこぼすほうを選んだ。取りこぼしは、人間が管制の会話か
`rebootctl status` で気づける。結果は `boot.log` に残す。

## 5. 判断: cron は WSL が動いているときしか回らない

WSL が止まっているあいだは、止まる会話も管制の会話も無いので、予告の意味が薄い。予告の目的は「WSL が動いていて会話が
走っているときに、Windows が勝手に再起動しうると知らせる」ことで、1時間おきの cron で足りる。再起動後の復帰は
`rebootctl boot`（ADR DOC-2611151248）が受ける。

## 6. 測ったこと: `rebootctl status` を1時間おきに呼ぶ重さ

`rebootctl status --json` の所要時間は約3.3秒（powershell.exe の起動が大半）。1時間に1回なので問題にならない。

## 7. 7日と30日の食い違い

`control-tower` スキル §2 と `bin/herdr-resume` の `CRON_MAX_AGE`（と、それを流用した `IDLE_MAX_AGE`）は、`CronCreate` の
巡回が7日で切れる前提で書かれている。2026-11-23 時点の `CronCreate` の説明は30日。管制の巡回は cron へ移るのでスキル側は
書き換える。`herdr-resume` の扱いは PR 本文に書く。

## 8. 確かめた範囲と確かめていない範囲

- 確かめた: `watch` の挙動（再起動待ちでなければ送らない・1回だけ・解けたら印を消す・送れなかったら印を書かない）は
  `bin/tests/test_rebootctl.py`。`claude -p` が cron の下でもスマホへ届かないことは実機。
- 確かめていない: 管制の会話が `PushNotification` でスマホへ届くこと（管制の会話にも「端末がアクティブ」の判定が
  かかりうる）。cron の下の `rebootctl watch` の実機の動き。いずれも人間の配布と crontab の登録のあとに確かめる宿題とする。
