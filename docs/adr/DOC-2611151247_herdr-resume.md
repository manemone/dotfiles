# ADR: 再起動で止まった Claude の会話を、再開してよいものだけ `herdr-resume` で起こす

## ステータス

確定（2026-11-15）。計画書 DOC-2611151244 の孫2。

## 1. 背景

Windows の勝手な再起動のあと、Herdr は会話（ペイン）を元の Claude の会話へ戻すが、会話は再開の指示が来るまで待つだけになる
（Herdr の `agent_status` は再起動で失われ、`CronCreate` の巡回も会話の中にしか無いので消える）。止まった時間は損失なので、
再開してよい会話にだけ自動で再開を送る。承認待ちだった会話を勝手に進めてはならない。

## 2. 決定: 会話の状態は Claude Code のフックで落ちる直前まで記録する

| 方式 | 正確さ | 配布の手間 | 採否 |
|---|---|---|---|
| a. Claude Code のフック | 落ちた瞬間の状態が残る | `claude/hooks/` と `claude/settings.json` に足すだけ（既存の配布経路） | **採用** |
| b. Herdr のスナップショットを定期記録 | 記録の間隔ぶん古い | 定期実行（systemd user timer 等）の配布が新たに要る | 不採用 |

`claude/hooks/session-state.sh` が `sessions/<session_id>.json` に `state`（`working`/`idle`/`blocked`/`ended`）・`updated_at`・
`crons` を書く。イベントとの対応: `UserPromptSubmit`→working、`Stop`→idle、`Notification`（`permission_prompt`・
`elicitation_dialog`）と `PreToolUse(AskUserQuestion)`→blocked、blocked のあとの `PostToolUse`→working（承認されて動き出した）、
`PostToolUse(CronCreate/CronDelete)`→`crons` の増減、`SessionEnd`→ended。ただし次の3点で補う（レビューで判明）:

- **`Stop` は人間の割り込み（Esc）では走らない**（公式文書）。割り込んだ会話は `working` のまま残るので、フックは `transcript_path` も記録し、
  `recover` / `plan` は `working` の記録について transcript の末尾を読む。最後のやり取りが `[Request interrupted by user` で始まる
  user の記録なら「割り込みで止めた会話」として送らない（`needs_human` は付けない。人間が自分で止めたため）
- **一回きりの `CronCreate`（`recurring: false`）は巡回に数えない。** 実行後に自分で消え、`CronDelete` も来ないため
- **`SessionEnd` は理由で分ける。** 人間が終えたと分かる理由（`prompt_input_exit` / `logout` / `clear` / `resume`）だけ ended にする。
  `other` などは WSL の停止に伴う終了でも出うるので、直前の状態を残す（全会話が ended で上書きされて再開が全滅するのを防ぐ）

- 全ツール呼び出しで走るため速くし、**失敗しても会話を止めない**（入力が壊れている・書き込めない・python3 が無い、で何も出さず exit 0）
- 状態のファイルへのキーは Claude の `session_id`。Herdr のペインの `agent_session.value` と一致するので、再起動後のペインから引ける
- 副作用: すべての Claude の会話でフックが走る（配布後に効く）

## 3. 判定（`herdr-resume` の `decide`。入力から出力を返す純粋な関数）

| 落ちる直前の状態（ペインの再起動後の状態） | 判定 |
|---|---|
| 再起動後のペインが `blocked` | 送らない（記録より優先） |
| 記録なし・時刻が読めない・Claude 以外 | 送らない。「判定できない。人間が見る」 |
| 承認待ち・質問待ち（`blocked`） | **送らない**（人間の承認待ちだった） |
| 人間が終えた（`ended`） | 送らない |
| 作業中の記録だが、人間が割り込みで止めた | 送らない（報告には載る。要確認にはしない） |
| ペインが `idle` / `done` でない | 送らない（動いている・読めない。`done` は背面のペインの待機中） |
| 作業中（記録が24時間以内） | 送る（再開の文） |
| 待機中で有効な巡回あり（7日以内） | 送る（巡回の再登録を促す文） |
| 待機中で巡回なし | 送らない（人間の返答待ちか完了） |
| 記録が古すぎる（作業中24時間・待機中7日超） | 送らない（人間が見る） |
| ラベル `管制` のワークスペースの会話 | 送らない（`rebootctl boot` が起こす。ADR DOC-2611151326 §5。要確認にはしない） |

**迷ったら送らない**。理由: 誤って送ると、承認の要る操作を人間の知らないうちに進めうる（取り返しがつかない側）が、送らなくても
報告（`last-recovery.json`）に理由つきで載り、人間と管制の会話（孫3）が外から再開できる（取り返せる側）。時間の上限は
`CronCreate` の巡回が7日で期限切れになる仕様に合わせ、作業中の上限24時間は「長い1ターンでも1日は超えない」という見積もり。

再開の文は固定文。再起動で中断されたこと・直前の操作の完了を確かめてから続けること・巡回の再登録・承認は待つこと、を含む。
送信は `herdr agent prompt <pane> <text> --wait --timeout 10000`（umbrella-orchestrator §5 のフォールバック）。
`timeout` / `stalled` でも再送しない（届いているかもしれず、再送は2重に積む）。`agent_blocked` は送られておらず、報告の要確認に載せる。

## 4. 冪等: 同じ `boot_id` では1回だけ送る

`boot_id` は `/proc/sys/kernel/random/boot_id`（WSL の起動ごとに変わる）。**取れないとき（macOS など）は `recover` は何も送らずエラーで終える**
（冪等の鍵が無いまま送ると2重に積むため。`plan` は使える）。`recover` は送る前に `status: in_progress` の
`last-recovery.json` を書き、同じ `boot_id` の報告があれば何も送らずその報告を返す。途中で落ちて再実行されても2度送らない。

**ペインの準備完了を待つ（`rebootctl boot` との分担）。** `boot_id` は最初の `recover` で使い切るので、会話を読み込み中のペイン
（`unknown` / `working`、またはまだエージェントと認識されていない `claude` を含む題名のペイン）のまま判定すると、全部が
`pane_not_idle` になり、そのあと何度呼んでも `already_recovered` が返るだけになる。そのため **`recover` 自身が**、判定の前に
Claude のペインが待機中・承認待ち（`idle` / `done` / `blocked`）になるまで3秒間隔で読み直す（上限は `HERDR_RESUME_SETTLE_SECONDS`、
既定180秒）。上限に達したらそのまま判定し、落ち着かなかったペインは送らず報告に載せる（迷ったら送らない）。
`rebootctl boot` が待つのは Herdr のサーバとワークスペースが戻るところまでで、ペインの状態の読み取りと待ちはこのツールの責務とする。

## 5. `last-recovery.json` の形式（孫3 が読む）

```json
{
  "version": 1,
  "boot_id": "<WSL の boot_id>",
  "windows_last_boot": "<ISO 8601。取れなければ null>",
  "recovered_at": 1800000000,
  "status": "done",
  "sent": [{"pane_id": "", "session_id": "", "workspace": "", "cwd": "", "kind": "resume|cron", "reason": "", "result": "sent|unconfirmed", "detail": ""}],
  "not_sent": [{"pane_id": "", "session_id": "", "workspace": "", "cwd": "", "code": "", "reason": "", "needs_human": true}]
}
```

`status` が `in_progress` の間は送信の途中。2回目以降の呼び出しの戻りには `already_recovered: true` が付く（ファイルには書かない）。

## 6. 確かめた範囲と未確認の範囲

確かめた: `decide` の判定表・`recover` の冪等・フックの状態遷移とフック失敗時に会話を止めないこと（自動テスト、偽の `herdr` を使用）。
実機の `herdr pane list` に対する `plan`（何も送らない）が、承認待ちのペインを送らない側に倒すこと。

**未確認**: (0) 割り込みの記録（`[Request interrupted by user`）は手元の transcript の形に合わせた。`SessionEnd` が WSL の停止で走るか、走るときの理由は未確認（`other` を残す側に倒してある）。
(1) 実際の Claude Code のフックが `notification_type` などのフィールドを渡す形（公式の文書の記述に拠った。配布後に
実際の `sessions/*.json` が育つかを確かめる宿題）。(2) `CronCreate` の応答の形（id の取り出しは緩く探し、取れなければ匿名で記録する）。
(3) 本物の再起動・`wsl --shutdown` での通し（このマシンの会話が全部止まるため人間が行う。傘の最終 PR のあとの宿題）。
