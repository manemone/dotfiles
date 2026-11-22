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

## 7. 2026-11-21 の再起動で分かったこと: S4U の WSL から Windows 経由の NAS が使えない（傘 `reboot-network-creds`）

### 経過（要約）

2026-11-21 の再起動で、起動時タスク（§4 の方式 A）が WSL を起こした。その WSL の fstab の drvfs による NAS のマウントは失敗し、
以後この WSL の中からは、Windows を経由した NAS のアクセスが全部失敗した（drvfs のマウント、WSL から呼んだ `cmd.exe`
〔「A specified logon session does not exist」〕と `powershell.exe`〔`Test-Path` が False〕、別リポの学習ツールが WSL から
Windows の `ruby.exe` 経由で呼ぶ登録ツール）。同じとき、人間がサインインしたエクスプローラーからは NAS に入れ、NAS の
445 番ポートには届いた。

§4 は「S4U ではネットワーク資格情報が使えないため、動くかは実験で確かめる」と書いたが、**確かめる対象に NAS（WSL から
Windows 経由で使う処理）が入っていなかった**。§6 の実験項目も同じ。

### 確かめた原因（2026-11-23、読み取りだけ）

- 起動時タスクは LogonType S4U。タスクの `wsl.exe`（セッション 0）が 2026-11-21 23:08:40 に WSL を起こした。
  このとき作られたログオンセッションの種類は 4（バッチ）
- いまの WSL から `powershell.exe` で `klist` を叩くと、現在のログオン ID は、そのタスクのログオンと同じものだった。
  人間がその後サインインして（セッション 1 の `wsl.exe` が複数ある）も、**WSL から呼ぶ Windows のプログラムのログオンは
  S4U のまま変わらない**。起こした WSL が生きている間は、後からサインインしても切り替わらない
- そのログオンには Kerberos のチケットが無く（`klist` が 0 件）、`net use` の接続も無い。資格情報マネージャー
  （`cmdkey /list`）には NAS の資格情報があるが、S4U のログオンはそれを使えない。NAS の共有フォルダの UNC への
  `Test-Path` は False、445 番ポートへは届く
- 結論: S4U にはネットワーク資格情報が無い、という §4 の想定どおりで、WSL から呼ぶ Windows のプログラムも同じログオンで動くため、
  UNC・drvfs 経由の NAS は届かない

確かめていない: S4U 以外のログオンの種類で WSL を起こした場合の比較（このマシンでは再起動を伴うため）。S4U のログオンで
起きた WSL でも、LogonType Interactive の一時タスクを登録して走らせ、その中で Windows の `ruby.exe` から登録ツールを動かすと
NAS の保存先に届いて登録が通った（計画書 DOC-2611230305 の実測。人間がサインインしている間）。

### 影響を受ける処理の洗い出し（このマシンの `$HOME` 配下を読み取りだけで探した）

WSL から Windows のプログラム（`*.exe`）を呼び、NAS を UNC で使う処理:

- 別リポの学習ツールの NAS 転送（`robocopy.exe` で送り、`powershell.exe` で読み戻す）
- 同じ学習ツールが、モデルを公開する手順で Windows の `ruby.exe` 経由で呼ぶ登録ツール（保存先は NAS 上のフォルダ）
- 画像生成ツールの Windows 版 CLI を WSL から呼ぶ経路（`tools/winrun` 系。NAS を使う設定のとき）

ほかの `*.exe` 呼び出し（`taskkill.exe`・`cmd.exe /c start`・GPU アプリの起動）は NAS を使わないので影響しない。
このリポの `bin/`・`shared/`・`skills/` には、NAS を Windows 経由で使う処理は無い。

### 直し方の案と人間の選択

| 案 | 内容 | 判断 |
|---|---|---|
| **1. WSL の cifs 経由のパスで渡す** | S4U のまま。WSL の中の cifs マウントを、Windows のプログラムに `wslpath -w` のパス（`\\wsl.localhost\<ディストロ>\...`）で渡す | **人間が選択。** NAS の資格情報は `/etc/nas-credentials`（WSL の中、root 600）だけに置かれ、S4U を選んだ理由（秘密をマシンの外にも中にも新しく置かない）と衝突しない。人間の作業が要らない |
| 2. Interactive の一時タスク経由 | NAS を使う Windows 側の処理だけ、Interactive の一時タスクで走らせる | 登録が通った実測はあるが、サインインが無いときに動かない見込み・出力と終了コードの受け渡し・登録に管理者が要るかが未確認で、ラッパーの追加も要る |
| 3. タスクの方式を変える | §4 の B・C、またはパスワード保存の通常ログオン | NAS の資格情報は使えるが、パスワードがマシンに残り、S4U を選んだ理由と衝突する |
| 4. サインイン後に WSL を起こし直す | `wsl --shutdown` して Interactive のログオンで起こし直す | 動いている会話と学習のキューが全部止まる。最終手段 |

案 1 の確かめた範囲: S4U のログオンの WSL から、`/mnt/nas`（cifs）を Windows 側のパス（`\\wsl.localhost\<ディストロ>\mnt\nas`）で
`Test-Path` と一覧取得ができた（資格情報なしで通る）。**確かめていない範囲:** その経路での `robocopy.exe` /
`ruby.exe` の書き込み・大容量の転送の速度、サインインしない本物の再起動後の確認。別リポの側は UNC 前提のコードを持つので、
そちらを案 1 に合わせる直しは別の作業（この傘では行わず、傘の司令官が人間に相談する）。

### `rebootctl` に入れたもの

`rebootctl status [--json]` に、NAS の確認を足した。確認先は環境ごとに違うので設定から読み、既定値を持たない
（`REBOOTCTL_NAS_MOUNT`: WSL の中のマウント先、`REBOOTCTL_NAS_UNC`: Windows から見た共有フォルダ）。未設定の確認は
飛ばし（`skipped`）、確認する道具が使えないときは「届かない」でなく「確認できなかった」（JSON は null）と出す。
次の3つを別々に出す: (1) WSL の中のマウントが生きているか、(2) Windows のプログラムから UNC に届くか、
(3) Windows のプログラムから WSL のマウント経由のパスに届くか。サインインしない再起動のあとは、(2) が届かず (3) が届くのが
想定どおりの形になる。

### 未確認（人間が叩く）

§6 の実験に加えて: サインインしないまま再起動し、起きた WSL で `rebootctl status` の NAS の3つが
（マウントが生きている・UNC は届かない・WSL 経由は届く）になること、案 1 に合わせた別リポの処理が通ること。
