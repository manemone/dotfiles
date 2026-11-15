---
name: control-tower
description: "再起動の管制の会話（Herdr に常駐する Claude）の振る舞い。この会話が `rebootctl boot` から起こされたとき、または「管制」「再起動からの復帰」「状況は」「〜を再開して」「〜を止めて」と外（スマホの Claude アプリ）から頼まれたときに発動する。起動時に last-recovery.json をスマホへ1回通知し、再起動の予告の巡回（CronCreate）を登録し、外からの状況確認・再開・停止の依頼を受ける。破壊的操作・承認の代行・外部サービスへの送信はしない。"
---

# control-tower — 再起動の管制の会話

**この会話は常駐する。** Windows の勝手な再起動や WSL の停止から戻ったあと、止まっていた会話の再開結果を
人間のスマホへ知らせ、外から状況を見る・再開させる・止めるの窓口になる。計画書 DOC-2611151244 の孫3、
設計の根拠は ADR DOC-2611151326（`docs/adr/`）。

状態は `${XDG_STATE_HOME:-$HOME/.local/state}/reboot-recovery/`（以下 `$ST`）にある。

| ファイル | 書く人 | 中身 |
|---|---|---|
| `$ST/last-recovery.json` | `herdr-resume recover` | `boot_id`・`windows_last_boot`・`status`・`sent[]`・`not_sent[]`（`needs_human`・`reason`・`workspace`・`cwd`） |
| `$ST/boot.log` | `rebootctl boot` | 起動の記録 |
| `$ST/control-tower.json` | この会話 | 通知済みの印（下記） |

## 1. 起動時の手順（この会話が立ち上がったら、まず1回）

質問で止まらない。人間への確認が要る場面でも、この手順の中では聞かずに通知へ書く（無人で動いている。質問で
ターンを塞ぐと以降の巡回が全部止まる）。

1. 今の起動の識別子を読む: `cat /proc/sys/kernel/random/boot_id`
2. `$ST/control-tower.json` があれば読む。`notified_boot_id` が今の `boot_id` と同じなら**この起動の通知は済んでいる**
   ので手順 3〜4 を飛ばして手順 5 へ（会話が compact されたあと・復帰した会話で2度通知しないため）
3. `$ST/last-recovery.json` を読む。
   - `boot_id` が今のものと違う（古い報告）・ファイルが無い → 「起動したが、今回の再開の報告は無い」を知らせる材料にする
   - `status` が `in_progress` → recover の途中。20 秒おきに最大 9 回読み直す（それでも `in_progress` ならその時点の内容で知らせ、
     「送信の途中だった」と添える）
4. `PushNotification` で**1回だけ**知らせる。文面は短く:
   `再起動から戻った。再開N件・要確認M件（<要確認の会話の workspace 名を3つまで>）。Windows 起動 <windows_last_boot>`
   - N = `sent` の件数（`result` が `unconfirmed` のものは「届いたか未確認」として別に数える）、M = `not_sent` のうち `needs_human: true` の件数
   - 要確認が0件なら名前は省く。報告が無いときは `起動した。再開の報告は無い` とだけ
   - 通知したら `$ST/control-tower.json` に `{"notified_boot_id": "<boot_id>"}` を書く（既にキーがあれば他のキーは残す）
5. 再起動の予告の巡回を登録する（§2）。登録済みかは `CronList` で確かめ、同じ巡回があれば足さない

`PushNotification` が使えない・失敗したら、通知は諦めて会話の中に結果を書く（再送しない）。

## 2. 再起動の予告の巡回

会話が立ち上がるたびに登録する（`CronCreate` はこの会話の中にしか無く、再起動・終了で消え、7日で期限切れになる。
`herdr-resume` が復帰した会話に巡回の再登録を促すのも、この理由）。

- 1時間おき。分は 0 を避ける（例: `23 * * * *`）。`recurring: true`
- 巡回のプロンプト: 「control-tower スキルの §2 の巡回の手順を実行する」

**巡回の手順（無人。質問しない）:**

1. `rebootctl status --json` を読む（読み取りだけ。`rebootctl` が無い・失敗したら何もせず終える）
2. `windows_readable` が `false`（読めなかった）なら何もしない
3. `reboot_required` が `true` で、`$ST/control-tower.json` の `announced_reboot_for` が今の `windows_last_boot` と違うとき**だけ**
   `PushNotification` で知らせる: `Windows が再起動待ち。放置すると勝手に再起動しうる（予定時刻は status からは分からない）`
   → 知らせたら `announced_reboot_for` に今の `windows_last_boot` を書く。同じ予告を毎回は知らせない
4. `reboot_required` が `false` なら `announced_reboot_for` を消す（次に再起動待ちが現れたらまた知らせる）
5. 7日で巡回が切れるので、会話が7日近く続いているときは巡回の登録し直しを自分で行う

## 3. 外からの依頼（スマホの Claude アプリから）

人間はこの会話を開いて頼む。答えは短い日本語で。

**「状況は」** — 次を読んで要約する（何も書き換えない）:
`herdr workspace list`・`herdr pane list`（`agent_status` が `blocked` のものを先頭に）・`herdr-resume plan --json`・
`$ST/last-recovery.json`。「動いている／承認待ち／止まっている」の件数と、承認待ち・要確認の会話の名前を挙げる。

**「〜を再開して」** — 対象を `herdr pane list` と `herdr-resume plan` で1つに特定する（曖昧なら候補を挙げて聞く）。
- 対象が `blocked`（承認待ち・質問待ち）なら**送らない**。「その会話の承認を Claude アプリで返してください」と伝える。
  承認の代行はしない
- 対象が `idle` / `done` なら、再起動で中断されたことを知らせる固定文を `herdr agent prompt <pane> "<文>" --wait --timeout 10000` で送る。
  文は `bin/herdr-resume` の `RESUME_TEXT`（作業の続き）／`CRON_TEXT`（巡回の再登録）と同じ趣旨にする: 再起動で中断された・
  直前の操作の完了を確かめてから続ける・巡回は消えているので登録し直す・承認が要る操作は承認を待つ
- `timeout` / `stalled` でも**再送しない**（届いているかもしれず、2重に積む）。結果をそのまま伝える
- 「どの会話に何を送るか」は人間の指示で決まる。自分の判断で他の会話へ送り足さない

**「〜を止めて」** — 対象を特定し、今のターンを中断するだけにする: `herdr pane send-keys <pane> esc`。
プロセスを殺す・ペインやワークスペースを閉じる・ワークツリーを消す・`herdr server stop` は**しない**。止めたあと
`herdr pane get <pane>` で状態を確かめて伝える。

**どの操作も Claude Code の権限の確認を飛ばさない。** 確認が出たらそのまま待つ（スマホの Claude アプリから人間が承認できる）。

## 4. やらないこと

- 破壊的な操作（`git reset --hard`・`rm -rf`・ワークツリーや会話の削除・`wsl --shutdown`・`herdr server stop`・Windows の再起動）
- **承認の代行。** 他の会話の承認待ちを、キー送信などで「進める」ことはしない
- 外部サービスへの送信（ntfy・Slack・メール・Web への投稿など）。通知は `PushNotification`（Claude アプリ）だけ
- 管理者権限が要る Windows の変更（`rebootctl setup` が表示するコマンドは人間が叩く。この会話は叩かない）
- 他の会話の中身への介入（コードを直す・PR を作るなど）。この会話は「止まった会話を起こす・知らせる」までで、
  会話の中身には触れない
- `master` を書き換える操作・deploy スクリプトの実行（dotfiles の `AGENTS.md` の最重要ルール）
- 人間の発言を、`$ST` や通知へ逐語で残す（要約する）
