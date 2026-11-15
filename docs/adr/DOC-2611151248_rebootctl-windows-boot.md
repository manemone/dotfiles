# ADR: Windows の勝手な再起動からの復帰の入口 `rebootctl`

## ステータス

決定（2026-11-15）。起動の方式は A（起動時タスク・S4U）に決まったが、**サインイン無しで WSL と Herdr と Claude が
動くことは未確認**（§6）。傘 `reboot-recovery` の計画書 DOC-2611151244 の孫1。

## 1. 背景（2026-11-15 の経過の要約）

- 早朝に Windows Update が累積更新のために2回続けて再起動した。更新の再起動のあと誰もサインインせず、
  WSL は人間がターミナルを開くまで約5時間半起動しなかった。その間、動いていた Claude の会話はすべて止まっていた
- Windows のアクティブ時間は 11〜5 時（最大幅いっぱいの18時間）で、5〜11 時は再起動してよい時間だった
- 調べた時点で、再起動止めのポリシー（`NoAutoRebootWithLoggedOnUsers`）は未適用だった
- 「ログオン時に起こす」仕掛けは、サインインが起きないと発火しないので今回のケースを救えない
- Herdr は再起動で会話を戻すが、会話は再開の指示が来るまで待つだけ（再開の判定と送信は孫2、管制は孫3）

## 2. 決めたこと

| 項目 | 決定 |
|---|---|
| 置き場所 | `bin/rebootctl`（bash）。`status` / `setup` / `boot` の3つ。新しいトップレベルのディレクトリは作らない |
| 管理者操作 | `setup` は管理者 PowerShell に貼るコマンドを**表示するだけ**。AI も `rebootctl` も `powershell.exe` 経由で書き込まない（テストで固定） |
| 読み取り | `status [--json]` が `powershell.exe` で読むだけ。読めないときも落ちず、`windows_readable: false` を返す |
| 起動の入口 | 方式 A: 起動時トリガーのタスク（`dotfiles-reboot-recovery`、S4U、パスワードを保存しない） |
| WSL の維持 | タスクは `rebootctl boot --hold` を呼ぶ。`boot` の後に `sleep infinity` で居座り、`wsl.exe` のプロセスを終わらせない |
| 冪等 | `boot` は `flock` で同時実行を避け、Herdr のサーバが動いていれば起動しない。`herdr-resume` が無ければ飛ばし、失敗しても止まらない |
| 記録 | `${XDG_STATE_HOME:-~/.local/state}/reboot-recovery/boot.log`（`sessions/` と `last-recovery.json` は孫2） |

## 3. 再起動止めの設定: 効くもの・効かないもの

出典は Microsoft Learn「Manage device restarts after updates」（`learn.microsoft.com/windows/deployment/update/waas-restart`、
2025-09 更新版）。

| 設定 | Windows 11 で | 備考 |
|---|---|---|
| `AUOptions=4` + `NoAutoRebootWithLoggedOnUsers=1`（`HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU`） | 文書は適用可能と読めるが、保証は弱い | 「ログオン中は再起動しない」。`AUOptions=4` が前提。ログオンしているユーザーが居ない（今朝のケース）と再起動される。同じ文書が「CSP が作られなかった」「期待どおりに動かない」「更新の再起動が永久に来なくなりうる」と注意しており、ユーザーが予約した再起動はこの設定を上書きする。**最初の防壁として入れるが、これだけに頼らない** |
| アクティブ時間（`SetActiveHours` / `ActiveHoursStart` / `ActiveHoursEnd`） | 効く | 最大幅は18時間（開始時刻から数える）なので、6時間の穴が必ず残る。上のポリシーとの併用は「再起動の方針は1つの道だけ選ぶ」「競合すると期待どおりにならない」とされるため、`setup` には入れない |
| `AlwaysAutoRebootAtScheduledTime` 系・再起動の期限・再起動の通知系 | 効かない | 文書が「レガシー、Windows 11 には適用されない」と明記 |

文書が推す置き換えは、コンプライアンス期限（deadline）＋事前の自動再起動の抑止だが、これは管理されたデバイス向けの
Update ポリシー CSP であり、この PR の範囲では扱わない。二段構えとして、それでも再起動したときは起動の入口（§4）と
`herdr-resume`（孫2）が受ける。

## 4. 起動の方式の比較と選択

| 方式 | 内容 | 判断 |
|---|---|---|
| **A. 起動時のタスク** | 「ログオンしているかどうかにかかわらず実行」を S4U で登録する（管理者操作。パスワード保存なし） | **選択。** 人間が選んだ。秘密をマシンの外へも、マシンの中へも置かない。S4U ではネットワーク資格情報が使えないため、Claude の認証や Remote Control が動くかは実験で確かめる |
| B. ログオン時のタスク + 更新後の自動サインイン（ARSO） | 管理者無しで登録できうる | 今朝は自動サインインが起きなかった。ARSO は BitLocker 等の条件に左右されるとされ、更新の再起動で確実に効く保証が無い |
| C. 自動ログオン + ログオン時のタスク | 確実に近い | パスワードがマシンに保存され、物理的に触れる人がサインインできる |

人間の選択: A（起動時タスク）。A が実験で動かなければ B、次に C を再検討する。

## 5. WSL を落とさない

タスクが起こした WSL は、`wsl.exe` のプロセスが終わるとアイドル停止で落ちうる（未確認）。確実に防ぐため、
タスクの `wsl.exe` に `rebootctl boot --hold` を渡し、`boot` 完了後に `sleep infinity` で居座る。タスクの実行時間の上限は無し
（`ExecutionTimeLimit` = 0）。

## 6. 確かめた範囲と未確認の範囲

確かめた（このマシンの WSL から）:

- `rebootctl status` / `status --json` が Windows の値（ポリシー・アクティブ時間・最終起動時刻・タスクの有無）を読む
- `rebootctl boot` が Herdr 稼働中のマシンで何も壊さず終わる（Herdr のサーバは二重に起動しない。スタブで固定）
- `setup` が `powershell.exe` を呼ばない（スタブで固定）

**未確認（実験が要る。人間が叩く。動いている会話が全部止まるので時刻は人間が決める）:**

1. サインイン無しの S4U のセッションで WSL が起動し、`rebootctl boot` が走り、Herdr のサーバと Claude が普通に動くか
   （認証・ネットワーク・Remote Control）
2. 起こした WSL が少なくとも10分は落ちないか
3. `herdr server` をヘッドレスで起動する呼び方（`herdr server` を引数なしで常駐させる）が実機で期待どおりか。
   このマシンでは Herdr が稼働中のためサーバの起動経路は叩いていない
4. 本物の再起動（傘の最終 PR の後の通しの試験）

実験の手順は `bin/README.md` §3.7 に書いた。結果は人間が PR または計画書の進行記録に残す。
