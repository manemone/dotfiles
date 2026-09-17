# 計画書: ローカルマシン ⇄ 共有サーバ のファイル受け渡しコマンド

傘ブランチ: `file-handoff`
ターゲット: `master`

## 概要

人間は共有サーバ（`toybox-001.kenko.work`、ARM64 Ubuntu 22.04）上で Claude Code を起動して
作業しているが、作業に必要なファイル（議事録・データ等）はローカルマシンにあることが多い。
現状の dotfiles には**ファイルを受け渡す手段が一切存在しない**（`bin/README.md` の
"What's Included" にあるのは `ocw` / `claude-ds` / `ocw-meter` の3つのみ）。

そこで、**引数なしで叩ける上り／下り2本のコマンド**を `bin/` に追加し、
ローカルマシン（macOS または Linux）から共有サーバの `~/uploads` へのアップロードと、
そこからのダウンロードを1コマンドで行えるようにする。

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。既に削除済みで参照
> できない前提で書く）を material として司令官が起草したものである。** ブリーフに書かれて
> いた問題意識・決定事項・実測値・制約・未確定事項は、**すべて本計画書へ転記済み**であり、
> 以降はこの計画書が正典である。ブリーフが未確定として残していた設計判断は、司令官が
> 人間へ確認して確定させた（「背景5: 司令官が人間に確認して確定させた決定事項」参照）。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `file-handoff-01-dfup` | 共通基盤（`bin/dfxfer-lib.sh`）＋上りコマンド `dfup`。配布登録・lint登録・README・テスト一式 | ⬜ 待機中 |
| 2 | `file-handoff-02-dfdown` | 下りコマンド `dfdown`。孫1の共通基盤に乗せる。ホストごとの受信ディレクトリ | ⬜ 待機中 |

## ワークスペースラベル

- 傘: `dotfiles :: ファイル受け渡し`
- 孫1: `dotfiles :: ファイル受け渡し 孫1 上り(dfup)`
- 孫2: `dotfiles :: ファイル受け渡し 孫2 下り(dfdown)`

---

## 背景1: 人間の問題意識（逐語）

> このマシンは共有サーバにあって、Claude Code をそこで起動して作業している。作業するために必要なファイル（議事録とかデータとか）はローカルマシンにあることが多い。普段はローカルマシンでClaudeCodeを使っているから問題にならないが、このマシン上で作業させるときは、それらのデータをここに持ってくるための手段が必要だ。そこで、この upload ディレクトリを切って、ここをDownloadsフォルダみたいに、ファイルの受け渡し場所として使いたい。簡便にこのフォルダにデータを渡せるようにしたいのだが、どういう風にしたらいいと思う？

> ローカルマシンは macOS で、このマシンでもつかってる dotfiles を使ってる。だから zshrc の local 限定のファイルに簡単なスクリプトを足すことはできる。あるいは任意のマシンに向けて同期フォルダを作って、なにか特定のディレクトリにファイルを入れると勝手に同期されるような Drop box 的スクリプトを汎用的に作る勝ちはあるかな？毎回コマンド打つのは面倒くさいからね

> それなりに面倒そうだな。コマンド一発（引数なし）で同期する（アップロードする）、という仕組みで一旦いいかな。アップロード先を環境変数やリストで、dotfilesをつかうマシンごとに選べるようになってるといいんだけどな。あと、このマシンからローカルに成果物を落としてきたいときもあるから、それも頼むよ。どちらのコマンドも、ローカルマシン側から叩くことになると思うね。傘にハンドオフできる？

> launchd は macOS 専用と思うが、ローカルマシンが Linux だったり Windows になったりすることあはあると思うから、ホントに自動実行を汎用化しようと思ったらそれなりにめんどいはず。でも、Windows環境はWSLにするから別にいいか。

> あと、とりあえず手元のファイルをあげるのを試すかと思ったけど、以下のようになっちゃった
>
> ```
> ❯ rsync -avhP --protect-args ~/Downloads/analysis-reporting-redesign-handoff.md toybox:uploads/
> rsync: unrecognized option `--protect-args'
> usage: rsync [-0468BCDEFHIKLOPRSTWVabcdghiklnopqrtuvxyz] [-e program]
>         [-f filter] [--8-bit-output] [--address=sourceaddr] [--append]
>         ...（以下 usage 全文。--iconv も --protect-args も含まれていない）
> ```

## 背景2: 人間が確定させた決定事項（覆さないこと）

- **コマンド一発・引数なし**で同期する。毎回パスを打たせない
- **上り（ローカル → リモート）と下り（リモート → ローカル）の2本**を作る
- **どちらのコマンドもローカルマシン側から叩く**
- 宛先は**環境変数ないしリスト**で、dotfiles を使うマシンごとに選べるようにする
- リモート側の受け渡し場所は `~/uploads`
- **launchd 等による自動同期（置いたら勝手に飛ぶ）は今回スコープ外。** 人間が
  「それなりに面倒そうだな」と明言して手動コマンドへ降格させた経緯がある
- **ローカルマシンは macOS とは限らない。Linux のこともある。** したがって上り／下り
  両コマンドは **macOS ローカルでも Linux ローカルでも動く**必要がある
- **Windows はネイティブ対応しない。WSL を使うので考慮不要**（人間の明言）

## 背景3: 既存の穴（司令官が実ファイルで裏取り済み）

- `bin/README.md` の "What's Included"（§3）にあるのは `ocw` / `claude-ds` / `ocw-meter` の
  3つのみ。**ファイル受け渡しの手段が dotfiles に存在しない**
- `zsh/.zshrc` の "Machine-local overrides" 節（末尾。司令官が実ファイルで確認済み）に
  `~/.zshrc.local` を source する機構がある。現物の引用:

  ```sh
  # =============================================================================
  # Machine-local overrides
  # =============================================================================
  # ~/.zshrc.local is intentionally NOT tracked in this repository. Put anything
  # specific to one machine there — host addresses, API keys, work-only paths —
  # so it never reaches the shared history. Sourced last, so it can override
  # everything above.
  if [ -f "$HOME/.zshrc.local" ]; then
    source "$HOME/.zshrc.local"
  fi
  ```

  `zsh/README.md` §「Machine-Local Settings (`~/.zshrc.local`)」（132行目付近）にも
  人間向けの説明がある。**マシンごとの宛先設定の受け皿として既に存在するが、この用途では未使用**

## 背景4: 実測値（調査日 2026-09-17、共有サーバ上で実施）

- `sshd` active（`:22` で LISTEN）、`rsync` は `/usr/bin/rsync` にあり
- `tailscale` / `syncthing` / `croc` / `rclone` / `socat` / `lsyncd` / `inotifywait` /
  `lrzsz` は**いずれも無い**
- `sudo` はパスワードを要求する → システムワイドなパッケージ導入は人間の手が要る。
  **ユーザー権限で完結する設計にすること**
- ARM64 Ubuntu 22.04 (jammy)、`/home` は 128G 中 101G 空き
- `/home/manemone/uploads` は作成済み・空・`drwxrwxr-x manemone:manemone`
- `/home/manemone` が `drwxr-x---` のため、同居する他ユーザー
  （`ec2-user` / `naru-shimizu` / `takumi-ogawa` / `ubuntu`）は uploads に到達できない。
  **権限を緩める必要も締める必要もない**
- dotfiles 実体は `/home/manemone/projects/dotfiles/master`、配布は世代方式
  （`.dotfiles-manifest` の `mode: generation`）

### 最重要の実測: macOS 標準 rsync には `--iconv` も `--protect-args` も無い

人間の実機で再現済み（背景1の逐語 usage 出力）。`--protect-args` と `--iconv` はどちらも
**rsync 3.0 で追加されたオプション**である。macOS が同梱するのは長らく rsync 2.6.9（2006年）
であり、新しめの macOS では Apple が openrsync へ差し替えている。**どちらも 3.x ではない。**

これにより、素朴に `--iconv=UTF-8-MAC,UTF-8` を前提とした設計は**前提ごと成立しない**。
対処方針は「背景5」で確定させた。

## 背景5: 司令官が人間に確認して確定させた決定事項（覆さないこと）

ブリーフが「未確定。人間に確認する価値が高い」として残していた4点について、司令官が人間に
確認し、以下のとおり確定した。

### 5.1 NFD/NFC と rsync バージョン: **(a)+(b) の合わせ技**

- rsync 3.x が見つかればそれを使い、`--iconv` を付ける
- 見つからなければ**エラーで止めず**、警告を出して素の転送へ降格する
- `bin/README.md` の Requirements に「日本語ファイル名を使うなら `brew install rsync`」を
  推奨として追記する

人間の言葉: 「3.x があれば使い、無ければ警告付きで素の転送に降格しつつ README で brew 版を
推奨する。エラーで止めず、日本語ファイル名を使うときだけ人間が入れればよい」

### 5.2 コマンド名: **`dfup` / `dfdown`**

dotfiles 由来と分かる接頭辞付き。衝突しにくく、`df` で始まるので補完も効きやすい。
（`up` / `down` は短すぎて衝突・誤爆のリスクが高いとして却下。`upload` / `download` は
汎用語すぎて他ツールと衝突しうるとして却下）

### 5.3 宛先選択と、下りの受信ディレクトリ: **ホストごとに別ディレクトリ**

人間の言葉（逐語）: 「DL はホストごとに別ディレクトリを作ったほうがいいかもね」

この回答を受けて司令官が確定させた設計（「設計1」で詳述）:

- ローカル側のディレクトリは**宛先名ごとに切る**。上りも下りも同じ規則にして、
  覚えることを1つに減らす（上りを単一ディレクトリにすると、既定の宛先を切り替えた
  瞬間に前の宛先向けの残骸が新しい宛先へ飛ぶ。上りでも宛先ごとに切ればこの事故が起きない）
- 宛先の選択は、**リストと既定の指名を別々の環境変数で持つ**方式にする
  （人間の「環境変数やリストで選べるといい」を両方満たす形）

### 5.4 転送後のローカル原本: **残す（コピー）**

`--remove-source-files` は使わない。`--drain` のような削除フラグも**用意しない**
（人間は「残す（コピー）」を選んだ。オプションで逃げ道を用意する案は選ばれていない）。
rsync の差分転送なので2回目以降は速い。事故が起きにくい方を採る。

---

## 設計1: ディレクトリとコマンドの外形（司令官が確定。孫はこれに従う）

### 1.1 コマンド

| コマンド | 向き | 動作 |
|---|---|---|
| `dfup` | ローカル → リモート | `$DFXFER_DIR/<宛先名>/out/` の中身を、リモートの `~/uploads/` へ送る |
| `dfdown` | リモート → ローカル | リモートの `~/uploads/` の中身を、`$DFXFER_DIR/<宛先名>/in/` へ落とす |

**どちらもローカルマシン側から叩く。** 引数なしで完結する。

### 1.2 ローカル側のディレクトリ構成

```
$DFXFER_DIR/                 # 既定: ~/dfxfer
  toybox/                    # 宛先名（= ssh の Host エイリアス）ごと
    out/                     # ここに置いたものが dfup で飛ぶ
    in/                      # dfdown で落ちてくる先
  work-box/
    out/
    in/
```

- ディレクトリが無ければコマンド側が作る（初回実行で人間が `mkdir` しなくてよい）
- **上りも下りも宛先名ごとに切る**（5.3 の理由）

### 1.3 設定（環境変数。`~/.zshrc.local` に `export` して使う）

| 環境変数 | 既定値 | 役割 |
|---|---|---|
| `DFXFER_HOSTS` | （空） | 宛先名を空白区切りで列挙したリスト。宛先名は `~/.ssh/config` の `Host` エイリアス |
| `DFXFER_HOST` | （空） | 引数なしで使う既定の宛先名 |
| `DFXFER_DIR` | `$HOME/dfxfer` | ローカル側のベースディレクトリ |
| `DFXFER_REMOTE_DIR` | `uploads` | リモート側の受け渡しディレクトリ（リモートのホームからの相対パス） |
| `DFXFER_RSYNC` | （空） | 使う rsync を明示指定する。指定があれば探索をスキップしてこれを使う |

**宛先の決定規則**（上り下り共通。孫1が実装し、孫2が再利用する）:

1. `DFXFER_HOST` が設定されていればそれを使う
2. 未設定で、`DFXFER_HOSTS` の要素がちょうど1つならそれを使う
3. 未設定で、`DFXFER_HOSTS` が空 → エラー。`~/.zshrc.local` への設定例を出して終了
4. 未設定で、`DFXFER_HOSTS` が2つ以上 → エラー。候補を列挙し、`DFXFER_HOST` で
   既定を指名するよう案内して終了
5. `DFXFER_HOST` が設定されているが `DFXFER_HOSTS`（非空）に含まれない → エラー。
   候補を列挙して終了。`DFXFER_HOSTS` が空なら**この検査は行わない**
   （リストを使わず既定1つだけで運用する人を弾かないため）

**`~/.zshrc.local` は zsh が source するファイルであり、`dfup` / `dfdown` は別プロセスの
スクリプトである。したがって設定は必ず `export` すること。** README の設定例でも
`export` を省かない。

### 1.4 rsync の探索とバージョン判定（5.1 の (a)+(b) を実装する）

探索順（最初に「3.x である」と確認できたものを採用）:

1. `$DFXFER_RSYNC`（設定されていれば、バージョンによらずこれを使う。テストの差し込み口も兼ねる）
2. `PATH` 上の `rsync`
3. Homebrew の rsync: `brew --prefix` が引けるならその `bin/rsync`、加えて
   `/opt/homebrew/bin/rsync` と `/usr/local/bin/rsync` を直接見る
4. どれも 3.x でなければ、`PATH` 上の `rsync`（無ければ 2〜3 で見つかった何か）に降格する

バージョン判定は `<rsync> --version` の1行目から**メジャー番号**を読む。
openrsync のように `rsync version N` 形式で出ないものは「3.x ではない」と扱う。

### 1.5 `--iconv` を付ける条件

`--iconv=UTF-8-MAC,UTF-8` を付けるのは、**次の両方**を満たすときだけ:

- ローカルが macOS である
- 採用した rsync が 3.x である

**ローカルが Linux のときは絶対に付けない**（元から NFC なので、付けると逆に壊れる）。

**`--iconv=LOCAL,REMOTE` の指定は「ローカル側の文字集合, リモート側の文字集合」であり、
転送の向き（送信／受信）ではなくマシンの側で決まる。** したがって司令官の読みでは
**`dfup` と `dfdown` で同じ `--iconv=UTF-8-MAC,UTF-8` を渡してよい**（ブリーフには
「下り方向では変換の向きが逆になる」と書かれていたが、rsync のオプション仕様としては
向きを書き分ける必要がない、というのが司令官の読みである）。
**孫はこれを鵜呑みにせず `man rsync` の `--iconv` の項で裏取りし、
読みが違っていたら実物に合わせて実装し、PR 説明でその旨を報告すること。**

ローカルが macOS なのに rsync が 3.x でなかった場合は、**警告を1行出してから素の転送を
続行する**（止めない）。警告文には `brew install rsync` を案内する。
ローカルが Linux のときはこの警告を出さない（`--iconv` が不要なので、そもそも問題が無い）。

### 1.6 `--protect-args` に依存しない書き方

**そもそも必要にならない設計にする。** 個々のファイル名をコマンド引数に並べるのではなく、
**ディレクトリ単位で同期する**（`rsync ... "$local_dir/" "$host:$remote_dir/"`）。
ファイル名は rsync のプロトコルに載って渡るため、シェルの引数分割の問題は起きない。
コマンド引数に現れるのは固定のディレクトリパスだけである。

`DFXFER_REMOTE_DIR` に空白を含む値を入れられると崩れうるので、**README に
「リモート側パスに空白を含めない」旨を明記する**こと（実装で頑張って対処しなくてよい）。

### 1.7 rsync に渡すオプション（上り下り共通）

- `-a`（アーカイブ）。**`-X` / `-A` は使わない**（macOS の拡張属性・ACL を Linux へ
  持ち込むと rsync がエラーを吐くため）
- `-v -h -P`（進捗表示。人間が手で叩くコマンドなので出す）
- `--exclude=.DS_Store --exclude=._*`（AppleDouble と Finder のゴミを除外）
- **`--delete` は使わない**（片道コピーであり、削除の伝播はスコープ外）
- **`--remove-source-files` は使わない**（5.4）

コマンドに追加で渡された引数は、そのまま rsync へ透過する（`dfup -n` で rsync の
dry-run が使える）。**これは司令官の判断であり、人間の指示ではない。**
1行で済む affordance であり、テストと事故予防の両方に効くため採用する。

### 1.8 プラットフォーム判定（AGENTS.md 制約との突き合わせ。孫1が最初に片付ける）

AGENTS.md「クロスプラットフォーム制約」に **「プラットフォーム分岐は `is_macos` /
`is_linux` / `is_wsl` / `get_brew_prefix` を使い、直接 `uname` を叩かない」** とある。

**司令官が実ファイルで確認した事実**:

- `is_macos` 等は `shared/helpers.sh` にあり、deploy スクリプト群が source している
- **既存の `bin/` 配下のスクリプト（`ocw` / `claude-ds` / `ocw-meter`）は、
  プラットフォーム分岐を一切していない**（`uname` も `$OSTYPE` も1箇所も出てこない。
  司令官が grep で確認済み）。つまり `bin/` から `shared/helpers.sh` を使う前例は無い
- `shared/` は世代ディレクトリにコピーされる（AGENTS.md「配布実体レイヤ」: コピー対象は
  `AVAILABLE_TOOLS` の各ディレクトリと `shared/`）。したがって `~/bin/dfup` の symlink を
  解決した先（`<世代>/bin/dfup`）から見て `../shared/helpers.sh` は**必ず実在する**
- ただし `shared/helpers.sh` は末尾に **source 時に発火するガード**を持ち、linked worktree
  から source されると「Deploying from a linked git worktree: ...」という**deploy 文脈の
  警告を出す**。ファイル転送コマンドがこれを出すのは明確に不適切

**司令官の方針（孫1はこれに従うこと）**:

`bin/dfxfer-lib.sh` から `shared/helpers.sh` を source して `is_macos` を使う。
その際、**source の直前に `DOTFILES_QUIET_WORKTREE_WARNING=1` を設定して
上記の deploy 文脈の警告を抑止する**（これは linter の抑制ディレクティブではなく、
`shared/helpers.sh` が公式に用意している環境変数であり、ヘッダコメントに
「Set DOTFILES_QUIET_WORKTREE_WARNING=1 to silence.」と明記されている）。

自身のパス解決は **`readlink -f` を使わない**（macOS の BSD 版に無い。AGENTS.md
「クロスプラットフォーム制約」が名指しで警告している）。`readlink`（オプション無し）を
ループで辿る移植性のあるイディオムを使うこと。

**この方針で実装してみて、どうしても成立しない（source が副作用を起こす・名前が衝突する等）
と判明した場合は、黙って `uname` を直書きに倒さず、いったん実装を止めて理由とともに
人間へ報告すること。** AGENTS.md の明文ルールを AI の判断で緩めない。

---

## 設計2: リポジトリへの登録（登録漏れが黙って通る箇所。孫は必ず全部潰すこと）

新しい `bin/` コマンドを足すときに触る必要がある箇所を、司令官が実ファイルで洗い出した。
**このうち 2.3 は、漏らしてもエラーにならず黙って対象から外れる。**

### 2.1 `bin/deploy.sh` — `~/bin` への symlink

現物（司令官が確認済み）:

```sh
symlink_backup "$DOTFILES_DEPLOY_SRC/bin/ocw" "$BIN_DIR/ocw" || FAIL=1
symlink_backup "$DOTFILES_DEPLOY_SRC/bin/claude-ds" "$BIN_DIR/claude-ds" || FAIL=1
symlink_backup "$DOTFILES_DEPLOY_SRC/bin/ocw-meter" "$BIN_DIR/ocw-meter" || FAIL=1
```

ここに新コマンドの行を足す。**`bin/dfxfer-lib.sh`（共通ライブラリ）は `~/bin` へ
symlink しない。** コマンドから相対パスで source されるだけで、PATH に置く意味が無い。

### 2.2 `shared/helpers.sh` の `links_for_tool()` — `bin` の arm

現物:

```sh
    bin)
      printf '%s\n' \
        "$HOME/bin/ocw" \
        "$HOME/bin/claude-ds" \
        "$HOME/bin/ocw-meter"
      ;;
```

ここにも足す。AGENTS.md「実装時の注意」のとおり、`uninstall.sh` と
`deploy-all.sh --status` の両方がここを一次情報源にしている。**足し忘れると
uninstall で撤去されずに `~/bin` に残る**（`bin` は `KNOWN_GENERATED_<tool>` を
持たないので、この場合の挙動は AGENTS.md の説明どおり）。

### 2.3 `bin/tests/lint.sh` の `list_shell_scripts()` — **漏らすと黙って lint されない**

現物（司令官が確認済み）:

```sh
list_shell_scripts() {
  find "$repo_root" \
    \( -path "$repo_root/.git" -o -path "$repo_root/*/.git" \) -prune -o \
    -type f \( -name '*.sh' -o -name 'ocw' -o -name 'claude-ds' -o -name 'ocw-meter' \) -print0
}
```

**拡張子の無いスクリプトは名前のハードコード一覧でしか拾われない。** `dfup` / `dfdown` は
拡張子を持たないので、ここに `-o -name 'dfup' -o -name 'dfdown'` を足さないと
`bash -n` / macOS bash 3.2 互換チェックの対象から**警告もエラーも出さずに外れる**。

この関数のコメント自身が、まさにこの事故を予見して書かれている（現物の引用）:

> Duplicating this find in two places is exactly the failure shape AGENTS.md warns about
> for links_for_tool(): a future standalone CLI added to bin/ only gets appended to one of
> the two copies, and the other silently checks one file fewer with no error or warning.

なお `bin/dfxfer-lib.sh` は `*.sh` なので、こちらは自動で拾われる（追記不要）。

### 2.4 ドキュメント

- `bin/README.md`
  - Overview の表に `dfup` / `dfdown` の行を足す
  - §1 Requirements に **rsync**（および日本語ファイル名を使う場合の `brew install rsync`）
    と **ssh** を足す
  - §2 Quick Start の「The deploy script:」の箇条書き（symlink するコマンド名の列挙）を更新
  - §3 What's Included に新しい小節を足す（`### 3.4` / `### 3.5`）
  - §5 Troubleshooting に、想定される詰まり（宛先未設定エラー、rsync が古い警告）を足す
- `zsh/README.md` §「Machine-Local Settings (`~/.zshrc.local`)」に、`DFXFER_*` を
  `export` する設定例を足す（**設定の置き場所が zsh 側にあるため。ここを書かないと
  人間が設定方法に辿り着けない**）
- ルート `README.md` — AGENTS.md「実装時の注意」に「README は二層構造。片方だけ更新しない」
  とある。ルート README に `bin/` のコマンド一覧を持っている箇所があれば更新する。
  **孫が実物を読んで、該当箇所の有無を確認すること**

---

## 決定的な制約（AGENTS.md 由来。孫は全部守ること）

- **クロスプラットフォーム制約**: `bin/ocw` `bin/claude-ds` は bash
  （`#!/usr/bin/env bash`）。新規の `dfup` / `dfdown` / `dfxfer-lib.sh` もこれに倣う。
  プラットフォーム分岐は `is_macos` / `is_linux` / `is_wsl` を使い、**直接 `uname` を
  叩かない**（設計1.8 で方針を確定済み）。macOS の BSD 版コマンドと GNU 版の差異
  （`sed -i`、`date`、`readlink -f` など）に注意する
- **macOS の `/bin/bash` は 3.2 である。** `bin/tests/lint.sh` が `/bin/bash -n` での
  互換チェックを持っているのはこのため。bash 4 以降でしか通らない構文
  （連想配列 `declare -A`、`${var^^}` 等）を使わない
- コードの書き方は
  [docs/design/DOC-2608020715-a_シェルスクリプトコーディング方針.md](../design/DOC-2608020715-a_シェルスクリプトコーディング方針.md)
  に従う
- **linter の抑制ディレクティブ（`# shellcheck disable=...` 等）や
  `.pre-commit-config.yaml` の除外・閾値緩和を AI の判断で追加しない。**
  指摘が不合理と判断したら抑制せず、違反内容・対象ファイル・判断理由を人間に報告する。
  コードの構造を変えて指摘そのものを解消できるなら、抑制よりそちらを優先する
- **新規ファイルの追加時・既存ファイルの大幅変更時点で、対象ファイル単位の lint を
  実行する。** コミット直前まで遅らせない（`pre-commit run --files <path>`）
- **deploy スクリプトを実オペレーションで実行しない。** 確認は
  `./deploy-all.sh --dry-run`。個別スクリプトは `--dry-run` 引数を解釈せず環境変数
  `DRY_RUN=1` のみ見るため、単体で試すなら `DRY_RUN=1 sh bin/deploy.sh` と書く
- **`master` を書き換える操作（マージ・push・force push）は人間だけが行う。**
  孫 → 傘のマージはレビュー承認済み PR に限り AI が実行してよい。**`git pull` は使わない**
- **`sudo` を要求する手順を設計に入れない**（背景4: 共有サーバの `sudo` はパスワードを
  要求する。ユーザー権限で完結させる）
- 指示された範囲外の機能を先回りして実装しない

## スコープ外（人間が明示的に降格・除外させたもの。孫が勝手に入れないこと）

- **launchd / fswatch / cron による自動同期**（人間が「それなりに面倒そうだな」と言って
  手動コマンドへ降格させた）
- Syncthing / Mutagen / rclone 等の常駐同期デーモンの導入
- **双方向同期**（競合解決・削除の伝播・リネーム検出）。今回は片道 × 2本
- リモート側 `~/uploads` の権限変更（背景4 の実測どおり不要）
- **リモート側の定期掃除（cron で古いファイルを消す）は、人間が採否を明言していない。
  孫が勝手に入れないこと。** 必要だと感じたら PR 説明で提案するに留める
- Windows ネイティブ対応（WSL を使うので不要。人間の明言）
- 転送後のローカル原本の削除（5.4 で「残す」に確定。削除フラグも用意しない）

## 必須の検証ステップ（AGENTS.md「コミット前の必須ステップ」より。省略しない）

- `pre-commit run --files <path>` — 新規追加・大幅変更の**その時点で**実行する
- `pre-commit run --all-files` — まとめ確認
- **`bin/` 配下を変更するので**: `python3 -m unittest discover -s bin/tests -v`
  （193件・約40秒。pre-commit には入っていないので手動で回す。新規テストを足すと件数は増える）
- `bin/tests/lint.sh`（pre-commit に組み込み済み。`files: ^bin/` で発火する）
- **`bin/deploy.sh` を変更するので**: `tests/deploy_smoke.sh`
  （`HOME` を一時ディレクトリへ差し替えたサンドボックス上で実行する。
  **人間の実 `$HOME` に対して直接実行しない**。既定の対象に `bin` が含まれている）
- `./deploy-all.sh --dry-run`（pre-commit のシェルスクリプト変更フックが自動で走らせる）
- PR を作る前に
  [docs/design/DOC-2608020715_プルリクエストの作法.md](../design/DOC-2608020715_プルリクエストの作法.md)
  を読む

**AI はこれらのステップを省略しない**（AGENTS.md の明示ルール）。

## テスト方針（AGENTS.md「テスト方針」に従う）

`dfup` / `dfdown` は **public CLI** であり、その外部 contract（宛先解決の規則、
組み立てられる rsync コマンド）はテストする。一方で、**受け入れ条件の数に比例して機械的に
テストを増やさない。**

テストの差し込み口は `DFXFER_RSYNC`（設計1.3）である。**引数を記録するだけのスタブを
`DFXFER_RSYNC` に指定すれば、ssh も実転送も伴わずに、組み立てられたコマンドライン全体を
検証できる。** これ以上のテスト専用フラグは要らない。

既存テストは `bin/tests/` に Python の `unittest` として置かれている
（`test_ocw.py` / `test_ocw_meter.py` / `test_worktree_guard.py`）。同じ流儀で
`bin/tests/test_dfxfer.py` を足す。

---

## 孫1用プロンプト:

````markdown
# 傘ブランチ: file-handoff
# 孫ブランチ: file-handoff-01-dfup
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/file-handoff/docs/planning/DOC-2609172237_file-handoff_計画.md`

**まず計画書の「背景1〜5」「設計1」「設計2」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」を全部読むこと。** 以下はその上での作業指示である。

## 実装開始前の必須手順

作業ブランチは**必ず `file-handoff`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout file-handoff
git fetch origin
git merge --ff-only origin/file-handoff
git checkout -b file-handoff-01-dfup
```

## やること

この孫は**共通基盤と上りコマンド `dfup`** を作る。下りコマンド `dfdown` は孫2が
この基盤の上に乗せるので、**共通化できる処理は必ず `bin/dfxfer-lib.sh` 側へ置く**こと。

### 1. `bin/dfxfer-lib.sh`（共通ライブラリ。`~/bin` へは配布しない）

計画書「設計1」の 1.3〜1.8 を実装する。少なくとも以下を提供する:

- 自身のパス解決（`readlink -f` を使わない移植性のあるイディオム）と
  `shared/helpers.sh` の source（直前に `DOTFILES_QUIET_WORKTREE_WARNING=1` を設定する。
  理由は計画書 1.8）
- 宛先の決定（`DFXFER_HOST` / `DFXFER_HOSTS`。決定規則は計画書 1.3 の5項目をそのまま）
- rsync の探索とメジャーバージョン判定（計画書 1.4）
- `--iconv` を付けるかの判定と、付けられないときの警告（計画書 1.5）
- 共通の rsync オプション列の組み立て（計画書 1.7）
- ローカル側ディレクトリの解決と作成（計画書 1.2）

`#!/usr/bin/env bash` のシェバンは付けなくてよい（source 専用）が、
`bin/tests/lint.sh` の `bash -n` は `*.sh` として自動的に拾う。

### 2. `bin/dfup`

`#!/usr/bin/env bash` + `set -euo pipefail`（既存の `bin/ocw` に倣う）。
`bin/dfxfer-lib.sh` を source し、`$DFXFER_DIR/<宛先>/out/` → `<宛先>:$DFXFER_REMOTE_DIR/`
を rsync する。追加引数は rsync へ透過する（計画書 1.7）。

送るものが1つも無いときは、rsync を叩いた結果として何も転送されないだけでよいが、
**人間が「動いたのか分からない」状態にならないよう、一言出すこと**。

### 3. リポジトリへの登録（計画書「設計2」を全部潰す）

- `bin/deploy.sh` に `dfup` の symlink 行を足す（`dfxfer-lib.sh` は足さない）
- `shared/helpers.sh` の `links_for_tool()` の `bin)` arm に `$HOME/bin/dfup` を足す
- **`bin/tests/lint.sh` の `list_shell_scripts()` に `-o -name 'dfup'` を足す。**
  ここを漏らすと警告もエラーも出さずに lint 対象から外れる（計画書 2.3）

### 4. ドキュメント

計画書 2.4 のうち、この孫の担当分:

- `bin/README.md`: Overview の表、§1 Requirements（rsync / ssh / `brew install rsync` の
  推奨）、§2 Quick Start の symlink 一覧、§3 に `dfup` の小節、§5 Troubleshooting
- `zsh/README.md` の「Machine-Local Settings (`~/.zshrc.local`)」に `DFXFER_*` の
  `export` 付き設定例を足す
- ルート `README.md` に `bin/` のコマンド一覧を持つ箇所があるか実物を確認し、あれば更新する

**`bin/README.md` §1 Requirements には、5.1 の確定事項どおり
「日本語ファイル名を扱うなら `brew install rsync`（3.x）を推奨。無くても動くが
濁点・半濁点が分離した別名で保存される」ことを明記すること。**

### 5. テスト

`bin/tests/test_dfxfer.py` を新規作成する。計画書「テスト方針」に従い、
`DFXFER_RSYNC` にスタブを差し込んで、組み立てられた rsync コマンドラインを検証する。

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 宛先の決定規則（計画書 1.3 の5項目）が期待どおりに効く。とくに、**宛先が決まらない
  ときにエラーで停止し、人間に何を設定すればよいかが伝わること**
- ローカルが macOS かつ rsync 3.x のときだけ `--iconv=UTF-8-MAC,UTF-8` が付く。
  **ローカルが Linux のときは付かない。この regression は必ず自動テストで固定する**
  （付けてしまうと Linux ローカルでファイル名が壊れる。壊れ方が静かで気づきにくい）
- rsync が 3.x でないときも**エラーで止まらず**、警告付きで転送が続行される
- `-X` / `-A` が付かない、`--delete` が付かない、`--remove-source-files` が付かない
  （**原本を消さない・リモートの既存ファイルを消さない。この regression は必ず自動テストで
  固定する**。破壊的な向きの事故であり、起きたときの被害が戻らない）
- `.DS_Store` / `._*` が除外される
- `$DFXFER_DIR` 配下のディレクトリが無ければ作られる

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files bin/dfup bin/dfxfer-lib.sh bin/deploy.sh shared/helpers.sh bin/tests/lint.sh bin/tests/test_dfxfer.py
pre-commit run --all-files
python3 -m unittest discover -s bin/tests -v
tests/deploy_smoke.sh
```

`tests/deploy_smoke.sh` は `HOME` を一時ディレクトリへ差し替えたサンドボックス上で走る。
**人間の実 `$HOME` に対して deploy スクリプトを直接実行しないこと。**

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `file-handoff` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）

実装が終わったタイミングで止まらず、必ずここまでやりきってください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。

計画書 1.5 の `--iconv` の向きについて、`man rsync` で裏取りした結果が司令官の読みと
違っていた場合は、実物に合わせて実装したうえで **PR 説明にその旨を書くこと**。
````

---

## 孫2用プロンプト:

````markdown
# 傘ブランチ: file-handoff
# 孫ブランチ: file-handoff-02-dfdown
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/file-handoff/docs/planning/DOC-2609172237_file-handoff_計画.md`

**まず計画書の「背景1〜5」「設計1」「設計2」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」を全部読むこと。** さらに、**孫1が既に
マージ済みの `bin/dfxfer-lib.sh` と `bin/dfup` を読んでから着手すること。**
この孫は孫1が作った共通基盤に乗せるのが仕事であり、同じ処理を書き直すのではない。

## 実装開始前の必須手順

作業ブランチは**必ず `file-handoff`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout file-handoff
git fetch origin
git merge --ff-only origin/file-handoff
git checkout -b file-handoff-02-dfdown
```

## やること

### 1. `bin/dfdown`

リモートの `<宛先>:$DFXFER_REMOTE_DIR/` → ローカルの `$DFXFER_DIR/<宛先>/in/` へ rsync する。

- **宛先解決・rsync 探索・`--iconv` 判定・共通オプション列は、孫1の
  `bin/dfxfer-lib.sh` を source して再利用する。** 同じロジックを書き直さない。
  ライブラリ側に足りない関数があれば**ライブラリに足す**（`dfup` 側の挙動を変えないこと）
- 受信先の `$DFXFER_DIR/<宛先>/in/` が無ければ作る
- `--delete` は使わない（片道コピー）。**リモート側の原本も消さない**
  （`--remove-source-files` を使わない）
- 追加引数は rsync へ透過する（計画書 1.7）
- 落ちてくるものが無いときも、人間が「動いたのか分からない」状態にならないよう一言出すこと

**`--iconv` の向きについて**: 計画書 1.5 に司令官の読み（`--iconv=LOCAL,REMOTE` は
転送の向きではなくマシンの側で決まるので、上りと下りで同じ指定でよい）が書いてある。
**孫1が `man rsync` で裏取りした結論がコードとPR説明に残っているはずなので、
それに合わせること。** 食い違いに気づいたら、憶測で直さず PR 説明で報告する。

### 2. リポジトリへの登録（計画書「設計2」。孫1と同じ箇所をもう一度触る）

- `bin/deploy.sh` に `dfdown` の symlink 行を足す
- `shared/helpers.sh` の `links_for_tool()` の `bin)` arm に `$HOME/bin/dfdown` を足す
- **`bin/tests/lint.sh` の `list_shell_scripts()` に `-o -name 'dfdown'` を足す。**
  ここを漏らすと警告もエラーも出さずに lint 対象から外れる（計画書 2.3）

### 3. ドキュメント

- `bin/README.md`: Overview の表、§2 Quick Start の symlink 一覧、§3 に `dfdown` の小節、
  §5 Troubleshooting（下り特有の詰まりがあれば）
- `zsh/README.md` の設定例が上り専用の書き方になっていれば、下りも含む形へ直す
- ルート `README.md` に `bin/` のコマンド一覧があれば更新する

**孫1が書いたドキュメントの構成をなぞること。** 上りと下りで説明の粒度や書式がちぐはぐに
ならないようにする。

### 4. テスト

孫1が作った `bin/tests/test_dfxfer.py` に `dfdown` の分を足す。
**新しいテストファイルを作らない。** 孫1のスタブ（`DFXFER_RSYNC`）の仕組みをそのまま使う。

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- `dfdown` が組み立てる rsync の**引数の順序が上りの逆になっている**
  （リモートが src、ローカルが dst）。**この regression は必ず自動テストで固定する**
  （逆向きに組み立てると、ローカルの中身でリモートを上書きしに行く。向きの取り違えは
  静かに起きて被害が戻らない）
- 宛先解決・rsync 探索・`--iconv` 判定が、`dfup` と**同じ共通実装**を通っている
  （`dfup` 側で保護済みの behavior を `dfdown` 側で全部再テストしない。
  共通層で authoritative にテストされているなら、`dfdown` 固有の差分だけを見ればよい）
- `--delete` が付かない、`--remove-source-files` が付かない
  （**リモートの原本を消さない・ローカルの既存ファイルを消さない。この regression は
  必ず自動テストで固定する**）
- 受信先ディレクトリが無ければ作られる

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files bin/dfdown bin/dfxfer-lib.sh bin/deploy.sh shared/helpers.sh bin/tests/lint.sh bin/tests/test_dfxfer.py
pre-commit run --all-files
python3 -m unittest discover -s bin/tests -v
tests/deploy_smoke.sh
```

`tests/deploy_smoke.sh` は `HOME` を一時ディレクトリへ差し替えたサンドボックス上で走る。
**人間の実 `$HOME` に対して deploy スクリプトを直接実行しないこと。**

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `file-handoff` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）

実装が終わったタイミングで止まらず、必ずここまでやりきってください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````
