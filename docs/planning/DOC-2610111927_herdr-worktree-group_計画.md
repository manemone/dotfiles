# 計画書: herdr のサイドバーで傘と孫のワークスペースを自動でまとめる

傘ブランチ: `herdr-worktree-group`
ターゲット: `master`

## 概要

`ocw -H` が作る Herdr ワークスペースは、herdr から見るとどのリポのどのワークツリーとも
結び付かない「無関係なワークスペース」になっている。そのためサイドバーの spaces には
傘・孫・他リポのワークスペースがフラットに並び、人間が手で並べ替えるしかない。
傘は3ペイン、孫は2ペインを開くので、数が増えると雑然とする。

herdr 本体にはワークツリーのグループ表示（リポのメインのチェックアウトを親として、
リンクされたワークツリーのワークスペースを子としてインデントして並べる）がある。
この傘では、`ocw -H` がこの仕組みに乗るように変え、**手で並べ替えなくても自動で
まとまる**ようにする。人間が求めている単位は「傘ブランチとその孫」であり、herdr の
グループの単位（リポ）とは一致しない見込みなので、どこまで寄せられるかを最初の孫で
確かめ、人間に一度見せてから先へ進む。

あわせて、**Claude アプリ（Remote Control）で見る会話のタイトルを herdr のラベルと揃える**
（人間から追加で依頼された。背景5）。今は会話のタイトルが `<ホスト名>-<ランダム語>` の
自動の名前になっていて、外から進捗を見るときにどの会話がどの傘・孫か分からない。

さらに、spaces の欄の入れ子は実現したが、**agents の欄はグループに合わせて並ばず、常駐する
エージェントが多くて混雑する**（人間から追加で依頼された。背景6）。孫6 で、要らないうちは
エージェントを起動しないようにする。

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。転記後に削除済みで
> 参照できない前提で書く）を material として司令官が起草したものである。** ブリーフに
> 書かれていた問題意識・決定事項・実測値・制約・未確認の点・孫分割の叩き台は本計画書へ
> 転記済みであり、以降はこの計画書が正典である。会話のタイトルの件（背景5・孫2）は、
> 計画書の作成後に相談の会話からセッション間の送信で追加依頼されたもので、その本文も
> 背景5 へ転記済みである。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `hwg-01-probe` | herdr のワークツリーグループの実際の動きを使い捨ての環境で確かめ、傘単位に寄せられるかの結論と採る方式を ADR にまとめる | ✅ PR #142 マージ済 |
| 2 | `hwg-02-session-name` | `ocw -H` がペインの claude を herdr のラベルと役割から作った名前（`--name`）で起動し、Claude アプリの会話タイトルを揃える（実測・テスト込み） | ✅ PR #143 マージ済 |
| 3 | `hwg-03-ocw-open` | `ocw -H` のワークスペース作成を herdr のワークツリーグループに乗る方式へ切り替える（テスト込み） | ✅ PR #144 マージ済 |
| 4 | `hwg-04-cleanup` | 片付け側（`ocw rm`・`worktree-cleanup` の孤児の判定）を、グループになったワークスペースに対応させる | ✅ PR #145 マージ済 |
| 5 | `hwg-05-skill-docs` | `umbrella-orchestrator` §5 などスキル・README の記述を新しい方式に合わせる | ✅ PR #146 マージ済 |
| 6 | `hwg-06-lazy-agents` | `ocw -H` はペインを今までどおり全部作り、エージェントは要るペインだけ起動する（司令官のワークスペースは司令官だけ、孫は implementer だけ）。残りは要るときに会話の名前つきで起動する | 🔄 実装中 |

依存: 孫1 と孫2 は**並列**。そのあと **孫1・孫2 の両方のマージ ＋ 人間の判断（設計2「判断ゲート」）**
→ 孫3 → 孫4 → 孫5 の順に**直列**で進める。

- 孫2 は孫1 の結論（グループの方式）に依存しない。孫1 は ADR だけを足しコードを変えないので、
  孫2（`bin/ocw` を変える）と並列にしてもコンフリクトしない（`docs/README.md` の索引の行が
  重なる程度）。人間が判断ゲートで考えているあいだに孫2 を進めておける
- 孫3 は孫2 の上に作る（孫2 で入る「ラベルを `ocw -H` に先に渡す」形を、孫3 がワークスペースの
  作成でもそのまま使う）。孫2 が先にマージされていないと、`bin/ocw` の同じ関数でぶつかる
- 孫1 の結果次第で孫3 以降の設計が分かれる（ブリーフの決定。結果は人間に一度見せる）。
  **孫1 のマージを検出しても、判断ゲートが「未」のあいだは孫3 を spawn しない。**
- 孫3・孫4 はどちらも `bin/ocw` と `bin/tests/test_ocw.py` の Herdr 連携部分を触るため、
  並列にするとコンフリクトする
- 孫5 は孫2〜4 で確定した挙動を文書へ反映するので最後に置く
- 孫6 は孫1〜5 がマージされ、最終 PR #147 を出したあとに人間から追加で依頼された（背景6）。
  孫5 のあとに置く。孫6 のマージまで最終 PR #147 は保留にし、マージ後に本文を更新して
  レビューし直す
- 孫1 の結論によっては、司令官が孫3〜5 のプロンプトを書き直す・孫を統合／追加する
  （設計2 の判断を受けて計画書を更新してから spawn する）

## ワークスペースラベル

- 傘: `dotfiles :: サイドバーを傘でまとめる`
- 孫1: `dotfiles :: サイドバーを傘でまとめる 孫1 グループ挙動の実測`
- 孫2: `dotfiles :: サイドバーを傘でまとめる 孫2 会話タイトル`
- 孫3: `dotfiles :: サイドバーを傘でまとめる 孫3 ocw -H切替`
- 孫4: `dotfiles :: サイドバーを傘でまとめる 孫4 片付け対応`
- 孫5: `dotfiles :: サイドバーを傘でまとめる 孫5 スキル文書更新`
- 孫6: `dotfiles :: サイドバーを傘でまとめる 孫6 エージェント遅延起動`

---

## 背景1: 問題意識（人間の発言の逐語）

> 別件なんだが、herdr の左のサイドバーの spaces、傘ブランチとその孫の単位で並び変えることはできないのかな、自動で。手で動かすのが面倒だし、傘は3ないし2のペーンが開くから、雑然とするんだよ

（相談AIが「herdr 本体にワークツリーのグループの仕組みがあるが、ocw -H がそれを使っていない。
まとまる単位はリポごとで、傘ごとではない」と調査結果を返したあとの発言）

> 判断して。なんか調整ありそうだし、傘にした方が良いかも

## 背景2: 人間が確定させた決定事項（覆さないこと）

- 傘ブランチ方式で進める（`herdr-worktree-group`、ターゲット `master`）
- 手で並べ替えるのではなく、**自動で**まとまること
- 進行中の別の傘 `herdr-09-cli-migration` には足さない（相談AIが判断し、人間が委ねた。
  理由は「スコープ外」の節）

## 背景3: 既存の穴

- `bin/ocw` の `-H` は `herdr workspace create --cwd <ワークツリー> --label ... --env OCW_ROLE=...
  --env OCW_RUN_ID=... --no-focus` でワークスペースを作る（`bin/ocw` の `setup_herdr_workspace`
  相当の関数。2026-10-11 時点で 861 行付近）。herdr から見ると、どのリポのどのワークツリーとも
  結び付かない無関係なワークスペースになる
- 実測（背景4）でも、開いている30個のワークスペースのうち、herdr がワークツリーの情報を
  持っていたのは1個だけ。サイドバーは30個がフラットに並び、傘・孫・リポの区別がラベルの
  文字列にしか無い
- herdr の CLI にはワークスペースの並べ替え（move / reorder）のコマンドが無い
  （`herdr workspace --help` のサブコマンドは list / create / get / focus / rename /
  report-metadata / close のみ）

## 背景4: 実測値・調査結果

### 4.1 相談AIが確認したもの（2026-10-11）

- 手元の herdr: クライアント 0.9.0（`herdr status`）。`~/.config/herdr/release-notes.json`
  上の最新は 0.9.3
- herdr の公式ドキュメント（https://herdr.dev/llms.txt → 設定リファレンス
  `config-reference.json`、v0.9.3）:
  - `ui.sidebar.spaces.row_gap`: 「Blank terminal rows between worktree groups and unrelated
    top-level Spaces. Worktree parents and their indented children remain packed.」→ サイドバーには
    **ワークツリーの親と、インデントされた子**というグループ表示がある
  - `keys.new_worktree` / `keys.open_worktree` / `keys.remove_worktree`、`worktrees.directory`
    （既定 `~/.herdr/worktrees`）
  - 並び順の設定は `ui.agent_panel_sort`（`spaces` / `priority`。Agent 側の並び）しか
    見当たらない。**グループ内の並び順を指定する設定は見つからなかった**
- `herdr worktree` コマンド:
  ```
  herdr worktree list [--workspace ID | --cwd PATH] [--trust-repository]
  herdr worktree create [--workspace ID | --cwd PATH] [--branch NAME] [--base REF] [--path PATH] [--label TEXT] [--focus] [--no-focus] [--trust-repository]
  herdr worktree open [--workspace ID | --cwd PATH] (--path PATH | --branch NAME) [--label TEXT] [--focus] [--no-focus] [--trust-repository]
  herdr worktree remove --workspace ID [--force] [--trust-repository]
  ```
- `herdr --skill` の記述: 「`workspace close --group` closes the primary workspace and its linked
  worktree workspaces; never add it merely to bypass `workspace_group_close_required`.」→ グループに
  なったワークスペースを閉じるとき `workspace_group_close_required` が返る場面があるらしい
  （どの場面かは未確認）。また `--trust-repository` は「ユーザーがリポジトリを確認した後にだけ使う」
  とある
- `herdr workspace list` の JSON では、ワークツリーに結び付いたワークスペースは `worktree`
  オブジェクト（`checkout_path` / `is_linked_worktree` / `repo_key` / `repo_name` / `repo_root`）を
  持つ。ocw で作ったものには無い

### 4.2 司令官の追加確認（2026-10-11）

- **サーバーも 0.9.0**（`herdr status server`: `version: 0.9.0`、`private_protocol: 22`）。
  ブリーフで未確認だった点。設定リファレンス（v0.9.3）の記述が 0.9.0 にも当てはまるかは孫1で確かめる
- **`herdr worktree open` には `--env` が無い**（`herdr worktree open --help` のオプションは
  `--workspace` `--cwd` `--path` `--branch` `--label` `--focus` `--no-focus` `--trust-repository`
  のみ）。一方 `ocw -H` は今、ルートペインに `OCW_ROLE`（`commander` / `implementer`）と
  `OCW_RUN_ID` を `workspace create --env` で渡しており、`ocw-meter` の計測と `bin/tests/test_ocw.py`
  （ルートペインが `OCW_ROLE=implementer` を持つことを検証している箇所がある）がこれに依存する。
  `worktree open` へ切り替えると、**ルートペインへの環境変数の渡し方を別に用意する必要がある**
  （例: ルートペインは使わずに閉じ、`pane split --env` で作ったペインだけを使う／
  `pane run` で `env OCW_ROLE=... claude` のように起動する、など）。孫1で方式を決める
- herdr には名前付きの別セッション（`herdr --session <name>`、`herdr session <subcommand>`）がある。
  人間の作業中のセッションに触れずに実験する手段の候補
- `bin/ocw` の片付け: `ocw rm` は `herdr workspace list` → 各ワークスペースの `herdr pane list`
  の `cwd` がワークツリーと一致したら `herdr workspace close <id>` を叩く（2026-10-11 時点で
  1280〜1325 行付近）。作成失敗時のロールバック（`rollback_created_worktree`、1019 行付近）も
  `herdr workspace close` を叩く
- `skills/worktree-cleanup/SKILL.md` の孤児の判定は `herdr workspace close <workspace_id>`
  （321 行付近）を叩く

### 4.3 相談AIの見立て（未検証。孫1が確かめる）

- 案: ワークツリーは今までどおり `ocw` が作り（`ocw.worktreeDir` の設定を尊重するため）、
  ワークスペースは `herdr worktree open --cwd <メインのワークツリー> --path <作ったワークツリー>
  --label ...` で開く。そうすれば herdr がリポのメインのチェックアウトを親として、その下に
  インデントして並べるはず
- 限界: **まとまる単位はリポごとで、傘ごとではない**見込み。同じリポで傘を2本回すと、
  傘たちも孫たちも同じグループに並ぶ。人間が求めているのは「傘ブランチとその孫の単位」なので、
  ここをどこまで寄せられるか（例: 孫のワークツリーを傘のワークスペースの子にできるか、
  ラベルで補うか）は要検討。できない場合は、リポ単位のグループ化でどこまで解決するかを
  人間に示して判断を仰ぐ

### 4.4 未確認の点（孫1の調査項目）

1. **親子関係の決まり方**: `worktree open` の `--workspace ID` / `--cwd PATH` は何を親にするのか。
   メインのチェックアウトのワークスペースだけが親になれるのか、**傘（リンクされたワークツリー）の
   ワークスペースを親にして孫をその子にできるか**（できれば「傘単位」に寄せられる）。
   グループ内の並び順は何で決まるか（作成順・ブランチ名順・ラベル順など）
2. 親（メインのチェックアウトのワークスペース。例 `modeldex :: main`）が開いていないとき、
   `worktree open` がどう振る舞うか（親を自動で作るか、エラーか、トップレベルに置くか）。
   親を自動で作る場合、そのワークスペースのペイン構成・ラベルはどうなるか
3. `worktree open` で開いたワークスペースに、今の `ocw -H` と同じ2〜3ペイン構成（司令官・
   implementer・reviewer）と各ペインでのエージェント起動を作れるか。ルートペインへの
   環境変数（`OCW_ROLE` / `OCW_RUN_ID`）の渡し方（4.2）
4. `--trust-repository` が要る場面があるか（要るなら、それは人間がリポを確認する手順の一部として
   どう扱うか。エラー回避のためだけに付けない）
5. 片付け: グループになったワークスペースを `herdr workspace close` で閉じたとき
   `workspace_group_close_required` が出るか（親を閉じるとき／子を閉じるとき）。
   `herdr worktree remove` はワークツリーのチェックアウト自体を消すのか（`ocw rm` は git 側の
   削除を自分で行うので、二重に消さない設計が要る）
6. 既に開いている、ocw で作ったワークスペース（移行前のもの）をどう扱うか（放置して自然に
   入れ替わるのを待つ、で足りるか）
7. 設定リファレンス v0.9.3 の記述（グループ表示・`row_gap`）が手元の 0.9.0 でも成り立つか。
   成り立たない場合、0.9.3 への更新が要るか（更新は人間の判断）
8. `ocw.worktreeDir` で herdr の `worktrees.directory`（既定 `~/.herdr/worktrees`）以外の場所に
   作ったワークツリーでも、`worktree open --path` でグループに乗るか
9. 他リポの孫（umbrella-orchestrator §2.1。傘とは別のリポのメインワークツリーで `ocw -H` を叩く）は、
   そのリポのグループに入る。傘のグループには入らない見込みで、それで足りるか

## 背景5: 追加の依頼 — Claude アプリの会話タイトルを herdr のラベルと揃える

### 5.1 問題意識（人間の発言の逐語）

> あと、外から進捗等を見るときにClaudeのアプリで開くと、会話のタイトルがランダムな単語になってて非常に見にくい。このタイトルもherdrと同じにしたいんだがそれはできるの

（相談AIが 5.2 の調査結果と「この傘に足すのがよい」を返したあと）

> 頼んで

孫の切り方・順序は司令官の判断に任された。

### 5.2 相談AIの調査結果（2026-10-11。出典 https://code.claude.com/docs/en/remote-control ・ /sessions ・ /cross-session-messaging）

- Remote Control の会話タイトルの優先順位: (1) `claude --name <名前>` / `--remote-control <名前>` で
  起動時に付けた名前 → (2) `/rename` の名前 → (3) 会話の最後の意味のあるメッセージ →
  (4) 自動生成 `<ホスト名>-<ランダム語>`。アプリ側でのリネームは CLI 側にも反映される
  （v2.1.221 以降）
- いまの ocw は素の `claude` で起動し（`bin/ocw` の `COMMANDER_COMMAND` / `IMPLEMENTER_COMMAND` /
  `REVIEWER_COMMAND`、既定 `claude`）、`~/.claude/settings.json` の `remoteControlAtStartup: true`
  で自動接続しているだけなので、名前が渡っていない
- 案: `ocw -H` がペインの claude を `--name "<herdr のラベル> / <役割>"` で起動する。役割
  （司令官・実装・レビュー）で区別しないと、同じワークスペースのペイン同士で名前が重なる

### 5.3 注意点（未確認。孫2 が確かめる）

1. `--name` はセッション間メッセージ（`SendMessage`）の宛先名も兼ねる（cross-session-messaging の
   ページに明記）。`~/.claude/sessions/<pid>.json` の `name` は今は `nameSource: "derived"` の
   自動の名前（例 `herdr-worktree-group-16`）。**日本語・空白・`::` を含む名前で `SendMessage` が
   届くか、umbrella-orchestrator §5「AI間送信手順（二段構え）」の宛先の解決
   （`agent_session.value` → `~/.claude/sessions/*.json` の `name`）が今のまま動くか**を試す
2. いまは `ocw -H` でワークスペースを作ったあとに `herdr workspace rename` で日本語ラベルに
   している。`--name` は起動時に渡すので、**ラベルを ocw に先に渡せる形（例 `ocw -H --label`）が
   要る**。umbrella-handoff §5・task-intake §5.3・umbrella-orchestrator §5「ワークスペースラベル」の
   手順順序にも影響する
3. `remoteControlAtStartup: true` と `--name` を併用したとき、本当に `--name` がタイトルになるかは
   ドキュメントに書かれていない。実測する
4. いま動いている会話は、人間が `/rename` すれば変えられる（移行の扱いは要検討）

### 5.4 司令官の追加確認（2026-10-11）

- `claude --help`: `-n, --name <name>  Set a display name for this session`、
  `--remote-control [name]`、`--remote-control-session-name-prefix <prefix>`（自動生成名の接頭辞。
  既定はホスト名）がある
- `remoteControlAtStartup: true` は `~/.claude/settings.json`（生成物）にあり、リポの
  `claude/settings.json` には無い（マシンの設定 `settings.machine.json` 由来と見られる）
- **`OCW_*_COMMAND` は人間が任意のコマンド文字列で上書きできる**（例 `claude --permission-mode auto`、
  あるいは Codex / OpenCode）。`--name` を機械的に足すと、claude 以外のコマンドを壊す。足すのは
  コマンドが claude のときだけにする、などの扱いが要る

## 背景6: 追加の依頼 — agents の欄の混雑を減らす

### 6.1 問題意識（人間の発言の逐語。2026-10-11、全孫のマージ後）

確認用のワークスペースで spaces の欄の入れ子を見たあとの発言:

> spaces の欄で入れ子が見えたよ。だけど、agents のところは並び替えされないんだ、、、ここが混雑するんで困るんだ

司令官が「herdr の設定では agents の欄を並べ替え・折りたたみできない。1件1行に詰める／
常駐するエージェントを減らす／herdr に要望を出す」の3案を示したあと:

> 1行にすると絶対見にくくなる。ギャップを減らすのはやってみたい。常駐するエージェントを増やすのはいいかもしれない。司令官の場合も implementer はいらない。ただ最終PR出す時は両方必要になるからね。でも、同時に作らないと、エージェントの欄で一つの孫や司令官のエージェントが連続しなくなるから、さらにカオスになる気もする。

（「常駐するエージェントを増やす」は、文脈から「減らす」の意と司令官が読んだ。）
司令官が「ペインは最初に全部作り、エージェントの起動だけ遅らせる。後から起動しても並びは
崩れない（6.2 の実測）」と返し、この傘でやるか別の PR にするかを尋ねたあと:

> ああ、ペーンを先に作るってことね、、、この傘でやってほしいですね

### 6.2 司令官の調査・実測（2026-10-11）

- herdr 0.9.3 の設定リファレンス（`config-reference.json`）で、agents の欄に効く設定は
  `ui.agent_panel_sort`（`spaces` / `priority`）と `ui.sidebar.agents.rows` / `row_gap` /
  `rows_by_agent` だけ。ワークツリーのグループに合わせた入れ子・折りたたみ・待機中の
  エージェントを隠す設定は無い。0.9.1〜0.9.3 のリリースノートにも無い
- **`row_gap` は人間の了承を得て 1 → 0 にした**（`~/.config/herdr/config.toml`。dotfiles の
  管理外のマシン設定。バックアップ `config.toml.bak-20261011-211632`。`herdr server reload-config` で反映）。
  1件2行の表示は人間の希望で変えていない
- **後から起動したエージェントも、agents の欄では同じワークスペースのまとまりに入る。**
  使い捨ての名前付きセッション（`herdr --session hwgorder`）で、ワークスペース AAA（2ペイン）と
  BBB（1ペイン）を作り、偽の `claude`（`sleep` の複製）を AAA の1つ目 → BBB → AAA の2つ目の順に
  起動して、`tmux capture-pane` で agents の欄（見出し `grouped`。`agent_panel_sort = "spaces"`）を
  読んだ。並びは AAA, AAA, BBB だった。人間の心配（同時に作らないと連続しなくなる）は、
  ペインを先に全部作れば当たらない。実験のセッション・一時ファイルは片付け済み
- 0.9.2 のリリースノートに「`worktree open` no longer takes over the repository's own workspace,
  so removing the worktree no longer closes it.」とある。孫1 の実測（0.9.0）では、メインの
  チェックアウトで開いていた普通のワークスペースがそのまま親になった。herdr を 0.9.2 以降に
  上げると親の扱いが変わりうる（最終 PR の「人間に見てほしい点」に書く）
- `pr-review-loop` Phase 2 Step 2 は、reviewer ペインにエージェントがいなければ
  `herdr agent start --kind <KIND> --pane <reviewer>`（KIND は `reviewer_cmd` の先頭の語か、
  ペインで読み取ったエージェント名）で起動する。ただし会話の名前（孫2 の `--name`）は付かない

## 設計1: 司令官が確定させた判断（孫はこれに従う）

### 1.1 孫の分割と順序

ブリーフの叩き台（4本）に、追加依頼の会話タイトルの孫（孫2。背景5）を1本足して5本にする。
孫2 を孫1 と並列にした理由は「孫ブランチ進捗」の依存の節に書いた。孫1 を ADR を成果物とする調査の孫にしたのは、
調査結果と方式の決定（却下案を含む）を後から追えるように残すため（AGENTS.md の docs/ の
役割分担: 実測に基づく技術決定は `docs/adr/`）。孫1 の ADR は「状態: 提案」で出し、
判断ゲート（設計2）で人間が方式を決めたあと、孫3 の PR で「採用」へ更新する。

### 1.2 実験の作法（孫1 が守る）

- **人間が今使っている Herdr のセッション・ワークスペースを閉じたり動かしたり改名したりしない。**
  実験は名前付きの別セッション（`herdr --session <使い捨ての名前>` などで起こしたサーバー）か、
  人間のセッション上なら実験用に自分で作った使い捨てのワークスペースだけを対象にする。
  別セッションへ CLI を向ける方法（環境変数・ソケットの指定など）は `herdr --skill` / ヘルプで
  確かめる。分からなければ人間のセッション上の使い捨てワークスペースに留める
- 実験用のリポは `mktemp -d` で作る使い捨ての git リポ（実在のリポ・人間の作業ツリーで
  `worktree open` / `worktree create` を試さない）
- 実験で作ったワークスペース・ワークツリー・セッションは、終わったら自分で片付ける。
  片付けた結果（残骸が無いこと）を PR に書く
- `--group` / `--trust-repository` は、それが必要な理由を確かめるためにだけ使う。エラーを
  回避する目的で付けない（herdr のスキルの作法）
- サイドバーの見た目は CLI からは見えない。`herdr workspace list` / `herdr api` の JSON で
  親子関係・並び順を確かめ、見た目の確認が要るところは人間に見てもらう前提で、
  「人間に見てほしい点」として ADR と PR に書く

### 1.3 方式の候補（孫1 が比べる）

- **A. リポ単位のグループ**: `herdr worktree open --cwd <メインワークツリー> --path <ワークツリー>`。
  傘と孫が同じリポのグループに入る。傘を同じリポで2本回すと混ざる（ラベルの接頭辞で区別する）
- **B. 傘単位のグループ**: 孫を傘のワークスペースの子にできるなら、そうする（`--workspace <傘のID>`
  など）。人間の要望にいちばん近い
- **C. A ＋ ラベルの工夫**: グループの中の並び順がラベル順などで決まるなら、ラベルの付け方で
  傘とその孫を隣に並べる
- **D. 現状維持**（グループに乗らない）: どの方式も成り立たない・副作用が大きいときの比較対象

### 1.4 採用しないもの（理由つき）

- **herdr 本体の改造・プラグインの作成**: 相談の時点では検討していない（ブリーフ）。必要に
  なったら人間に相談する
- **`ocw` がワークツリーの作成を `herdr worktree create` に任せる**: `ocw.worktreeDir` の
  レイアウト設定（ADR DOC-2608062258）・`ocw-base-ref` の永続化・ブランチ命名を `ocw` が
  握っている前提が崩れるため。ワークツリーは今までどおり `ocw` が作る（相談AIの見立て）。
  孫1 の実測で `worktree open --path` が任意の場所のワークツリーを開けないと分かった場合に限り、
  判断ゲートで改めて人間に諮る

### 1.5 会話タイトル（孫2）

- **ラベルを `ocw` に先に渡せるようにする。** `ocw -H` にワークスペースのラベルを指定する
  オプション（名前は孫2 が既存のオプションの命名に合わせて決める。例 `--label <text>`）を足す。
  指定が無ければ今までどおり `<repo_name> :: <slug>`。作成後に `herdr workspace rename` する
  今の手順も引き続き動くこと（後方互換。スキル側の手順の書き換えは孫5）
- **ペインの claude を `--name "<ラベル> / <役割>"` で起動する。** 役割は 司令官 / 実装 / レビュー
  （`commander` / `implementer` / `reviewer` のどれと対応するかが分かる日本語。表記は孫2 が決めて
  ADR に書く）。同じワークスペースのペイン同士で名前が重ならないこと
- **`--name` を足すのは、起動コマンドが claude のときだけ。** `OCW_*_COMMAND` で claude 以外
  （Codex / OpenCode 等）が指定されていれば、コマンドに何も足さない（背景5.4）
- **実測してから決める**（背景5.3 の 1・3）。日本語・空白・`::`・`/` を含む名前で
  (a) Claude アプリの会話タイトルになるか（`remoteControlAtStartup: true` との併用。見た目は
  人間に確かめてもらう点として PR に書く）、(b) `SendMessage` が届くか、(c) umbrella-orchestrator
  §5 の宛先の解決（`~/.claude/sessions/*.json` の `name`）が一意に引けるか、を確かめる。
  (b)(c) が日本語の名前で壊れる場合は、名前の形（例: 宛先として安全な部分を先頭に置く、
  `--remote-control <名前>` でタイトルだけ付けられるか）を実測で比べて選ぶ。**どれも成り立たなければ
  推測で進めず、司令官に報告して止まる**
- 実測は、使い捨てのリポと自分で作った使い捨ての Herdr ワークスペースで行い、人間の会話・
  ワークスペースの名前を変えない（設計1.2 と同じ作法）。終わったら片付ける
- 決定（名前の形・役割の表記・claude 以外の扱い・却下した案）は孫2 の ADR に残す
  （孫1 の ADR とは別ファイル。テーマが違うため）
- **いま動いている会話は移行しない。** 人間が必要なら `/rename` で変える（孫5 で文書に書く）

### 1.6 エージェントの遅延起動（孫6）

- **ペインは今までどおり全部作る**（傘3・孫2。ペインの label・`OCW_ROLE` / `OCW_RUN_ID` も
  今までどおり）。**エージェントを起動するのは、すぐ使うペインだけ**にする:
  - 既定（`--no-commander` なし。司令官のワークスペース）: commander だけ起動。implementer と
    reviewer は最終 PR（umbrella-orchestrator §3.4 `/finalize`）のときに起動する
  - `--no-commander`（孫・`task-intake` の軽いハンドオフ）: implementer だけ起動。reviewer は
    `pr-review-loop` がレビューを頼むときに起動する
- **後から起動するときも、孫2 の会話の名前（`--name '<ラベル> / <役割>'`）が付くこと**、
  `OCW_*_COMMAND` の上書きが効くこと、`OCW_ROLE` / `OCW_RUN_ID` がそのエージェントに届くこと。
  起動の仕方（例: `ocw` に「このペインの役割のエージェントを起動する」サブコマンドを足し、
  `pr-review-loop` と `/finalize` がそれを呼ぶ／起動コマンドをワークツリーの git dir に書き残す／
  `herdr agent start ... -- --name ...` を使う、など）は孫6 が比べて決め、ADR に残す。
  `pr-review-loop` は `ocw` が無い環境（他人のリポ・Codex 等）でも動く配布スキルなので、
  `ocw` に頼る場合も今の起動手順へのフォールバックを残す
- **今までどおり全部起動する手段を残すかは、孫6 が既存の利用者（`task-intake` の軽いハンドオフ、
  `umbrella-handoff`）の手順を読んで決める**（要らなければ足さない。先回りしない）
- 起動していないペインはシェルのまま。`pr-review-loop` の状態判定（`unknown`）や
  umbrella-orchestrator §5 の宛先の解決が、起動前のペインを「エージェントが終了した」と誤読して
  余計なことをしないこと
- 最終 PR の手順（umbrella-orchestrator §3.4 手順2・3）に「implementer / reviewer に
  エージェントがいなければ起動する」を足す

## 設計2: 判断ゲート（孫1 の後に人間が決める）

判断ゲート: **済**（2026-10-11）

- 司令官が孫1 の ADR DOC-2610111932 の結論（傘単位のグループは herdr の仕様で不可。推奨は
  方式 A＋C＝リポ単位のグループ＋ラベルの接頭辞。同じリポで傘を複数回すと孫が混ざる）を人間へ提示した
- 人間の発言（逐語）:
  > そうするしかないよな、残念だが
- **決定: 方式 A＋C を採る。** 同じリポで傘を複数本回したときに混ざることは受け入れる。
  孫3〜5 は ADR DOC-2610111932 §4「推奨」の `ocw -H` の変更に従う

（孫1 のマージ後、司令官が ADR の結論を人間に示し、人間が方式を決めたら、司令官がここを
「済」に書き換え、決まった方式と人間の発言を記録し、必要なら孫3〜5 のプロンプトを書き直してから
孫3 を spawn する。**この欄が「未」のあいだ、巡回は孫3 を spawn しない。** 孫3 の spawn には、
孫2 のマージも要る（依存の節）。）

## 決定的な制約（孫は全部守ること）

- AGENTS.md の最重要ルール（`master` を書き換えるのは人間だけ。孫→傘のマージはレビューで
  承認済みの PR に限り AI が行ってよい。`git pull` は使わない 等）
- `bin/ocw` は bash（AGENTS.md「クロスプラットフォーム制約」）。macOS / Linux / WSL2 で動くこと
- ocw の AI 間の送信・ワークスペース階層の正典は `skills/umbrella-orchestrator/SKILL.md` §5。
  変更が及ぶなら合わせて直す。ADR DOC-2609072215（AI間送信）も関係しうる
- herdr のスキルの作法: 人間が作っていないワークスペースを勝手に閉じない。`--group` や
  `--trust-repository` を、エラーを回避する目的だけで付けない
- 実験で herdr の状態を壊さない。人間が今使っているワークスペースを閉じたり動かしたりしない
  （設計1.2）
- linter の抑制ディレクティブや除外の追加を AI の判断でしない（AGENTS.md）
- `ocw` の既存の外部契約（`workspace:` / `commander:` / `implementer:` / `reviewer:` の出力行、
  `--no-commander`、`OCW_*_COMMAND`、`OCW_ROLE` / `OCW_RUN_ID` の環境変数）を壊さない。
  変えざるを得ない場合は ADR に理由を書き、スキル側（孫5）を合わせる

## スコープ外

- `herdr-09-cli-migration`（スキルを herdr 0.9 のコマンドに追随させる傘。孫4本ともマージ済みで
  締めの段階）とは別。あちらに足さない。テーマ（スキルの文面の追随）も触る場所も違うため
- herdr 本体の改造・プラグインの作成（必要になったら人間に相談）
- 同時に進行中の PR #141（司令官の区切り compact。ブランチ `commander-compact`。
  `skills/umbrella-orchestrator/SKILL.md` を触る）とは別件。孫5 が同じファイルを触るので、
  孫5 の着手時に #141 がマージ済みなら傘を `origin/master` へ rebase してから始める
  （コンフリクトに注意）
- 既存のワークスペースを一括で作り直す移行ツール（孫1 の結論で必要と分かった場合に限り、
  判断ゲートで人間に諮る）

## 必須の検証ステップ（AGENTS.md「コミット前の必須ステップ」より。省略しない）

- pre-commit（shellcheck / shfmt、`bin/tests/lint.sh`、doc-id の check / verify 等）:
  `pre-commit run --files <変更したファイル>` と `pre-commit run --all-files`
- `bin/` 配下を変えたら `python3 -m unittest discover -s bin/tests -v`
- デプロイ関連のシェルスクリプトを変えたら `tests/deploy_smoke.sh`
- herdr の実際の動きは、人間の作業中のワークスペースに触れない形で確かめる（設計1.2）
- `docs/` に新規ファイルを足すときは `DOC-DOCID_PLACEHOLDER_<名前>.md` で作り、
  `./tools/doc-id/doc-id assign <path>` で採番する

## テスト方針（AGENTS.md「テスト方針」に従う）

`bin/tests/test_ocw.py` は herdr を偽物のスクリプトで置き換えて `ocw` の呼び出しを検証している。
herdr の呼び出し方を変えたら、その偽物と検証を新しい呼び出しに合わせる（外部契約＝`ocw` の
出力行・ペイン構成・環境変数のテストは残す）。テスト数を機械的に増やさない。本物の herdr との
結合は、偽物では確かめられないので、孫3・孫4 が使い捨ての環境で手で確かめて PR に書く。

---

## 孫1用プロンプト:

````markdown
# 傘ブランチ: herdr-worktree-group
# 孫ブランチ: hwg-01-probe
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/herdr-worktree-group/docs/planning/DOC-2610111927_herdr-worktree-group_計画.md`

**まず計画書の「概要」「背景1〜4」「設計1」「設計2」「決定的な制約」「スコープ外」
「必須の検証ステップ」を全部読むこと。** 以下はその上での作業指示である。

## 実装開始前の必須手順

作業ブランチは**必ず `herdr-worktree-group`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
`ocw` がすでに `hwg-01-probe` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/herdr-worktree-group` の
先端から切られていることを確かめる（`git pull` は使わない）。

## やること

この孫の成果物は**コードではなく ADR 1本**である（`bin/ocw` は変えない）。

1. 計画書 背景4.4 の未確認の点 1〜9 を、計画書 設計1.2 の作法で実測する
   - 人間が今使っている Herdr のワークスペースには触れない。使い捨てのリポ（`mktemp -d`）と、
     名前付きの別セッションまたは自分で作った使い捨てのワークスペースだけを使う
   - 何を叩いて何が返ったか（コマンドと JSON の要点）を記録しながら進める
   - サイドバーの見た目は CLI から見えないので、`herdr workspace list` / `herdr api` 等の JSON で
     親子関係・並び順を確かめる。見た目の確認が要るところは「人間に見てほしい点」として残す
2. 計画書 設計1.3 の方式 A〜D を比べ、**傘単位（B または C）に寄せられるか**の結論を出す。
   推奨する方式を1つ選び、その方式で `ocw -H` がどう変わるか（呼ぶコマンドの列、ルートペインへの
   `OCW_ROLE` / `OCW_RUN_ID` の渡し方、`ocw rm` とロールバックの閉じ方、`worktree-cleanup` への
   影響、移行前のワークスペースの扱い）まで具体的に書く
3. 結果を ADR にまとめる
   - `docs/adr/DOC-DOCID_PLACEHOLDER_herdr-worktree-group.md` で作り、
     `./tools/doc-id/doc-id assign` で採番する
   - 状態は「提案」（人間が判断ゲートで決めたあと、孫3 が「採用」へ更新する）
   - 構成の目安: 背景（計画書の背景1〜3を要約し計画書の DOC-ID を明示）／実測（未確認の点ごとに
     コマンドと結果）／方式の比較（A〜D、それぞれの限界）／推奨と理由／却下した案と理由／
     人間に判断してほしい点（方式の選択、見た目の確認が要る点、herdr の更新が要るか等）
   - 既存の ADR の書き方（`docs/adr/` 配下）に揃える。`docs/README.md` の索引にも行を足す
4. 実験で作ったワークスペース・ワークツリー・セッションを全部片付け、残っていないことを確かめる

## 検証方針

以下の重要な behavior / regression risk が守られていること。

- ADR の実測が、実際に叩いたコマンドと返り値に基づいている（推測を実測として書かない。
  確かめられなかった点は「未確認」と明記する）
- 実験の前後で、人間のワークスペース（実験開始前の `herdr workspace list` に載っていたもの）の
  数・ラベル・親子関係が変わっていない
- doc-id の check / verify が通る

各項目と test example を1対1対応させる必要はない。
新しい自動テストは要らない（コードを変えない孫のため）。
何を叩いて確かめたか・片付けたことは PR の説明に書く。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files docs/adr/<採番後のファイル> docs/README.md
pre-commit run --all-files
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `herdr-worktree-group` にすること。master には絶対に出さない。**
   PR 本文の冒頭に、推奨する方式と「人間に判断してほしい点」を3〜5行で要約する
   （司令官がこれを人間に見せる）
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）
5. マージを終えたら、司令官が spawn の送信文で渡した司令官の Herdr ペインへ完了を通知する
   （渡されていなければ通知しない）。送り方は傘ブランチ上の `skills/umbrella-orchestrator/SKILL.md`
   §5「AI間送信手順（二段構え）」に従う。本文は
   「孫1 `hwg-01-probe` の PR #<番号> を herdr-worktree-group へマージしました。」だけにする。
   通知は1回だけ。送れなくても止まらず（司令官の巡回が拾う）、送れなかったことを最終報告に1行書く

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

## 孫2用プロンプト:

> 孫1 と並列で spawn してよい（依存の節）。

````markdown
# 傘ブランチ: herdr-worktree-group
# 孫ブランチ: hwg-02-session-name
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/herdr-worktree-group/docs/planning/DOC-2610111927_herdr-worktree-group_計画.md`

**まず計画書の「概要」「背景5」「設計1.1」「設計1.2」「設計1.5」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」を全部読むこと。** 背景1〜4（herdr のワークツリーグループ）は
孫1 の担当で、この孫は触らない。

## 実装開始前の必須手順

`ocw` がすでに `hwg-02-session-name` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/herdr-worktree-group` の
先端から切られていることを確かめる（`git pull` は使わない）。

## やること

1. 実測（コードを変える前に行う。計画書 設計1.5）
   - 使い捨てのリポ（`mktemp -d`）と、自分で作った使い捨ての Herdr ワークスペースで、
     `claude --name "<日本語・空白・::・/ を含む名前>"` を起動し、
     (a) `~/.claude/sessions/<pid>.json` の `name` / `nameSource` がどうなるか、
     (b) その名前を宛先に `SendMessage` が届くか、
     (c) umbrella-orchestrator §5「AI間送信手順（二段構え）」の宛先の解決（`herdr pane get` の
     `agent_session.value` → `~/.claude/sessions/*.json`）で一意に引けるか、を確かめる。
     (a)〜(c) で壊れる場合は、名前の形や `--remote-control <名前>` を比べる
   - Claude アプリの会話タイトルになるか（`remoteControlAtStartup: true` との併用）は、
     CLI から確かめられる範囲（セッションの記録・Remote Control の表示名など）を確かめ、
     見た目の確認は「人間に見てほしい点」として PR に書く
   - 人間の会話・ワークスペースの名前を変えない。終わったら起動したセッション・ワークスペースを
     片付ける
   - **(b)(c) がどの形でも成り立たなければ、推測で実装に進まず、司令官のペインへ報告して止まる**
2. `bin/ocw`
   - `-H` にワークスペースのラベルを指定するオプションを足す（設計1.5。指定が無ければ今までどおり）
   - 起動コマンドが claude のときだけ、各ペインの claude に `--name "<ラベル> / <役割>"` を付けて
     起動する。claude 以外のコマンド（`OCW_*_COMMAND` の上書き）には何も足さない。
     コマンドが claude かどうかの判定方法は、上書きの例（`claude --permission-mode auto` など）を
     壊さない形にする
   - `ocw help` / `ocw help herdr` の該当箇所を直す（`bin/README.md` 等の文書は孫5 の担当）
3. `bin/tests/test_ocw.py` を合わせる
4. 決定を ADR にまとめる（`docs/adr/DOC-DOCID_PLACEHOLDER_<説明的な名前>.md` で作り
   `./tools/doc-id/doc-id assign` で採番。`docs/README.md` の索引にも行を足す。孫1 の ADR とは
   別ファイル。孫1 と `docs/README.md` の索引の行が重なったら、rebase で両方残す）
5. 本物の herdr で、使い捨てのリポに対して `ocw -H --<ラベルのオプション> ...` と
   `ocw -H --no-commander ...` を叩き、ラベルとペインごとのセッション名を確かめ、`ocw rm` で片付ける

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- ラベルを指定すれば、ワークスペースのラベルとペインごとの `--name` がそれになる。
  指定しなければ今までどおりのラベルになる
- 同じワークスペースのペイン同士で名前が重ならない
- 起動コマンドが claude でなければ、コマンドが変わらない
  （**この regression は必ず自動テストで固定する**。人間の `OCW_*_COMMAND` の上書きを壊すため）
- 既存の外部契約（出力行・ペイン構成・`OCW_ROLE` / `OCW_RUN_ID`）が変わっていない

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。
実測で何を叩いて何が返ったかは ADR と PR の説明に書く。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files bin/ocw bin/tests/test_ocw.py docs/README.md docs/adr/<採番後のファイル>
pre-commit run --all-files
python3 -m unittest discover -s bin/tests -v
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `herdr-worktree-group` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）
5. マージを終えたら、司令官が spawn の送信文で渡した司令官の Herdr ペインへ完了を通知する
   （渡されていなければ通知しない）。送り方は傘ブランチ上の `skills/umbrella-orchestrator/SKILL.md`
   §5「AI間送信手順（二段構え）」に従う。本文は
   「孫2 `hwg-02-session-name` の PR #<番号> を herdr-worktree-group へマージしました。」だけにする。
   通知は1回だけ。送れなくても止まらず、送れなかったことを最終報告に1行書く

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

## 孫3用プロンプト:

> 判断ゲート（設計2）が「済」になり、孫2 もマージされたので spawn する（2026-10-11、ADR の結論を
> 反映して書き直し済み）。

````markdown
# 傘ブランチ: herdr-worktree-group
# 孫ブランチ: hwg-03-ocw-open
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/herdr-worktree-group/docs/planning/DOC-2610111927_herdr-worktree-group_計画.md`

**まず計画書の「概要」「背景1〜4」「設計1」「設計2」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」と、孫1 の ADR（`docs/adr/` 配下の herdr-worktree-group の
ADR）を全部読むこと。** 方式は設計2 で人間が決めたものに従う。

## 実装開始前の必須手順

`ocw` がすでに `hwg-03-ocw-open` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/herdr-worktree-group` の
先端（孫1・孫2 のマージを含む）から切られていることを確かめる（`git pull` は使わない）。

## やること

1. `bin/ocw` の `-H` のワークスペース作成を、設計2 で決まった方式（herdr のワークツリーグループに
   乗る方式）へ切り替える
   - 既存の外部契約（出力行・ペイン構成・`--no-commander`・`OCW_*_COMMAND`・
     `OCW_ROLE` / `OCW_RUN_ID`）と、孫2 で入ったラベルのオプション・ペインごとの `--name` を保つ
     （計画書「決定的な制約」）
   - 作成失敗時のロールバック（`rollback_created_worktree`）が、新しい方式で作ったワークスペースを
     正しく閉じられるようにする（閉じ方の詳細は ADR に従う。片付け側の本格対応は孫4）
   - 具体的には ADR DOC-2610111932 §4 に従う: ワークツリーは今までどおり `ocw` が作り、
     ワークスペースは `herdr worktree open --cwd <メインのワークツリー> --path <作ったワークツリー>
     --label <ラベル> --no-focus` で開く。`--trust-repository` はエラー回避のために付けない
   - ルートペインには `--env` で環境変数を渡せない（ADR §2.2 の3）。ルートペインの起動コマンドに
     `OCW_ROLE=… OCW_RUN_ID=…` を前置して渡すか、ルートペインを使わない構成にするかは、
     `bin/ocw-meter`（`os.environ` から `OCW_RUN_ID` / `OCW_ROLE` を読む）と突き合わせて決める。
     **孫2 の claude 判定（先頭の `VAR=値` は読み飛ばす・`env X=1 claude` はラッパーとして
     `--name` を足さない）と組み合わせても `--name` が付くこと**を確かめる（前置するなら、
     `--name` を足したあとのコマンドに前置する、`env` ではなく `VAR=値` の形にする、など）
   - ロールバックで閉じるのは `ocw` が開いた子のワークスペースだけ。`worktree open` が自動で
     作った親（メインのチェックアウトのワークスペース）は閉じない（ADR §4）。
     `herdr worktree remove` は使わない（チェックアウトごと消えるため）
   - 同じパスのワークスペースが既に開いていると `already_open: true` で既存のものが返る
     （ADR §2.2 の6）。そのとき既存のペインに重ねてペインを増やさないよう扱いを決める
     （例: エラーにして止める）
2. `bin/tests/test_ocw.py` の偽の herdr と検証を新しい呼び出しに合わせる
3. `ocw help herdr` の記述を新しい方式に合わせる（`bin/README.md` 等の文書は孫5 の担当）
4. 孫1 の ADR DOC-2610111932 の状態を「採用」へ更新し、§4 で実装する孫が決めるとしていた点
   （ルートペインの環境変数の渡し方、`already_open` の扱い）の決定を追記する
5. 本物の herdr で、使い捨てのリポと使い捨てのワークスペースを使って `ocw -H` と
   `ocw -H --no-commander` を叩き、グループに入ること・ペイン構成・エージェント起動を確かめ、
   片付ける（人間のワークスペースには触れない。計画書 設計1.2）

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- `ocw -H` が herdr のワークツリーグループに乗る呼び出しでワークスペースを作る
- 既存の外部契約（出力行・2/3ペイン構成・各ペインの `OCW_ROLE` / `OCW_RUN_ID`・起動コマンド）が
  変わっていない
- 作成途中で失敗したとき、ワークスペース・ワークツリー・ブランチが残らない
  （**この regression は必ず自動テストで固定する**）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。
本物の herdr で何を確かめたかは PR の説明に書く。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files bin/ocw bin/tests/test_ocw.py
pre-commit run --all-files
python3 -m unittest discover -s bin/tests -v
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `herdr-worktree-group` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）
5. マージを終えたら、司令官が spawn の送信文で渡した司令官の Herdr ペインへ完了を通知する
   （渡されていなければ通知しない）。送り方は傘ブランチ上の `skills/umbrella-orchestrator/SKILL.md`
   §5「AI間送信手順（二段構え）」に従う。本文は
   「孫3 `hwg-03-ocw-open` の PR #<番号> を herdr-worktree-group へマージしました。」だけにする。
   通知は1回だけ。送れなくても止まらず、送れなかったことを最終報告に1行書く

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

## 孫4用プロンプト:

> 孫3 のマージ後に spawn する。孫1 の結論次第で、司令官が spawn 前に書き直すことがある。

````markdown
# 傘ブランチ: herdr-worktree-group
# 孫ブランチ: hwg-04-cleanup
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/herdr-worktree-group/docs/planning/DOC-2610111927_herdr-worktree-group_計画.md`

**まず計画書の「概要」「背景1〜4」「設計1」「設計2」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」と、孫1 の ADR を全部読むこと。**

## 実装開始前の必須手順

`ocw` がすでに `hwg-04-cleanup` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/herdr-worktree-group` の
先端（孫3 のマージを含む）から切られていることを確かめる（`git pull` は使わない）。

## やること

1. `ocw rm` の Herdr ワークスペースの閉じ方を、グループになったワークスペースに対応させる
   - `workspace_group_close_required` が出る場面（ADR の実測）で、人間が作っていない
     ワークスペースを巻き込まずに閉じられるようにする。`--group` は、その対象が `ocw` の作った
     ものだけだと確かめられる場合にしか使わない（エラー回避のためだけに付けない）
   - `herdr worktree remove` を使うか `herdr workspace close` のままにするかは ADR に従う。
     git 側の削除（`ocw rm` が自分で行う）と二重に消さない
   - 移行前（グループに乗っていない）のワークスペースも今までどおり閉じられること
2. `skills/worktree-cleanup/SKILL.md` の孤児の判定・閉鎖（`herdr workspace close`）を、
   グループになったワークスペースに対応させる（親のワークスペースを孤児と誤判定しない、等。
   ADR の実測に従う）
3. `bin/tests/test_ocw.py` を合わせる
4. 本物の herdr で、使い捨てのリポと使い捨てのワークスペースを使って、孫3 の方式で作った
   ワークスペースを `ocw rm` で片付けられることを確かめる（人間のワークスペースには触れない）

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- `ocw rm` が、グループになったワークスペースと移行前のワークスペースの両方を閉じられる
- `ocw rm` が、対象のワークツリーと無関係なワークスペース（同じグループの他のワークスペース・
  親のワークスペース）を閉じない（**この regression は必ず自動テストで固定する**）
- 閉じられなかったときも git 側の削除は今までどおり進む（既存の警告の振る舞い）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。
本物の herdr で何を確かめたかは PR の説明に書く。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files bin/ocw bin/tests/test_ocw.py skills/worktree-cleanup/SKILL.md
pre-commit run --all-files
python3 -m unittest discover -s bin/tests -v
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `herdr-worktree-group` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）
5. マージを終えたら、司令官が spawn の送信文で渡した司令官の Herdr ペインへ完了を通知する
   （渡されていなければ通知しない）。送り方は傘ブランチ上の `skills/umbrella-orchestrator/SKILL.md`
   §5「AI間送信手順（二段構え）」に従う。本文は
   「孫4 `hwg-04-cleanup` の PR #<番号> を herdr-worktree-group へマージしました。」だけにする。
   通知は1回だけ。送れなくても止まらず、送れなかったことを最終報告に1行書く

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

## 孫5用プロンプト:

> 孫4 のマージ後に spawn する。spawn 前に PR #141（`commander-compact`）が `master` へマージ済みなら、
> 司令官が傘を `origin/master` へ rebase してから spawn する（スコープ外の節）。

````markdown
# 傘ブランチ: herdr-worktree-group
# 孫ブランチ: hwg-05-skill-docs
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/herdr-worktree-group/docs/planning/DOC-2610111927_herdr-worktree-group_計画.md`

**まず計画書の「概要」「背景1〜4」「設計1」「設計2」「決定的な制約」「スコープ外」
「必須の検証ステップ」と、孫1 の ADR を全部読むこと。**

## 実装開始前の必須手順

`ocw` がすでに `hwg-05-skill-docs` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/herdr-worktree-group` の
先端（孫4 のマージを含む）から切られていることを確かめる（`git pull` は使わない）。

## やること

孫2〜4 で変わった `ocw -H` / `ocw rm` の挙動を、文書へ反映する。コードは変えない。

0. 孫2 の会話タイトル（ラベルを `ocw -H` に先に渡し、ペインの claude に `--name` を付ける）に
   合わせて、ラベルを付ける手順の順序を直す: `skills/umbrella-handoff/SKILL.md` §5・
   `skills/task-intake/SKILL.md` §5.3・`skills/umbrella-orchestrator/SKILL.md` §3.2 / §3.5 / §5
   「ワークスペースラベル」（作成後に `herdr workspace rename` する手順を、作成時にラベルを渡す
   手順へ。§5「AI間送信手順」の宛先の解決に影響があれば孫2 の ADR に従って直す）。
   いま動いている会話は人間が `/rename` で変えられることも書く

1. `skills/umbrella-orchestrator/SKILL.md` §5（「ワークスペース階層」「`ocw -H` が作るもの」
   「ワークスペースラベル」など）。サイドバーでのまとまり方（傘と孫がどう並ぶか）と、
   その限界（ADR の結論）を書く。§3.2「他リポの孫の spawn」のラベルの説明に影響があれば直す
2. `skills/ocw/SKILL.md`・`skills/worktree-cleanup/SKILL.md`・`skills/umbrella-handoff/SKILL.md`・
   `skills/task-intake/SKILL.md` など、`ocw -H` のワークスペースの作られ方・閉じ方に触れている
   箇所（`git grep -n -e "workspace create" -e "workspace close" -e "ocw -H" -- skills` で探す）
3. `bin/README.md` とルート `README.md`（二層構造。片方だけ更新しない。AGENTS.md「実装時の注意」）
4. ADR DOC-2609072215（AI間送信）に影響があれば追記する（無ければ触らない）

## 検証方針

以下の重要な behavior / regression risk が守られていること。

- 文書に書いたコマンド・挙動が、孫2〜4 のコードと ADR の実測に一致している
- 正典（umbrella-orchestrator §5）と参照側で食い違いが無い（参照側に全文をコピーしない）
- doc-id の check / verify が通る

新しい自動テストは要らない（コードを変えない孫のため）。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --all-files
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `herdr-worktree-group` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）
5. マージを終えたら、司令官が spawn の送信文で渡した司令官の Herdr ペインへ完了を通知する
   （渡されていなければ通知しない）。送り方は傘ブランチ上の `skills/umbrella-orchestrator/SKILL.md`
   §5「AI間送信手順（二段構え）」に従う。本文は
   「孫5 `hwg-05-skill-docs` の PR #<番号> を herdr-worktree-group へマージしました。」だけにする。
   通知は1回だけ。送れなくても止まらず、送れなかったことを最終報告に1行書く

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

## 孫6用プロンプト:

> 孫5 のマージ後、人間の追加依頼（背景6）を受けて足した孫。最終 PR #147 は孫6 のマージまで保留。

````markdown
# 傘ブランチ: herdr-worktree-group
# 孫ブランチ: hwg-06-lazy-agents
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/herdr-worktree-group/docs/planning/DOC-2610111927_herdr-worktree-group_計画.md`

**まず計画書の「概要」「背景5」「背景6」「設計1.5」「設計1.6」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」と、ADR DOC-2610111932・DOC-2610111939 を全部読むこと。**

## 実装開始前の必須手順

`ocw` がすでに `hwg-06-lazy-agents` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/herdr-worktree-group` の
先端（孫5 のマージを含む）から切られていることを確かめる（`git pull` は使わない）。

## やること

計画書 設計1.6 に従い、`ocw -H` がエージェントを要るペインだけ起動するようにし、残りを
要るときに起動できるようにする。

1. `bin/ocw`
   - ペインは今までどおり全部作る。エージェントを起動するのは、既定では commander だけ、
     `--no-commander` では implementer だけ
   - 後から起動する手段を用意する。会話の名前（`--name '<ラベル> / <役割>'`、claude のときだけ）・
     `OCW_*_COMMAND` の上書き・`OCW_ROLE` / `OCW_RUN_ID` が、今の即時起動と同じになること。
     方式は設計1.6 の例を比べて決める
   - `ocw help` / `ocw help herdr` を直す
2. `skills/pr-review-loop/SKILL.md` Phase 2 Step 2: reviewer ペインにエージェントがいないとき、
   1 の手段が使えればそれで起動し（会話の名前が付く）、使えなければ今の起動手順に落ちる。
   起動前のシェルだけのペインを、終了したエージェントと同じに扱ってよいかを確かめて書く
3. `skills/umbrella-orchestrator/SKILL.md` §3.4 `/finalize`（手順2・3）と §3.5 手順9:
   implementer / reviewer にエージェントがいなければ起動してから送る。§5「`ocw -H` が作るもの」の
   説明（「全ペーンでエージェント起動済み」など）を直す
4. `skills/ocw/SKILL.md`・`skills/task-intake/SKILL.md`・`skills/umbrella-handoff/SKILL.md`・
   `bin/README.md`・ルート `README.md` で、`ocw -H` がエージェントを起動する前提に立っている
   箇所を直す（`git grep -n -e "ocw -H" -e "起動済み" -- skills bin/README.md README.md` で探す）
5. 決定を ADR に残す（新しい ADR を `docs/adr/DOC-DOCID_PLACEHOLDER_<説明的な名前>.md` で作り
   `./tools/doc-id/doc-id assign` で採番し、`docs/README.md` の索引に行を足す）
6. 本物の herdr で、使い捨てのリポと使い捨てのワークスペース（名前付きの別セッションが望ましい。
   計画書 設計1.2 の作法）を使って、`ocw -H` と `ocw -H --no-commander` で起動したエージェントの数、
   後から起動したエージェントの会話の名前・`OCW_ROLE`、agents の欄で同じワークスペースの
   まとまりに入ることを確かめ、片付ける（人間のワークスペースには触れない）

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 既定の `ocw -H` は commander だけ、`--no-commander` は implementer だけエージェントを起動し、
  ペインは今までどおり全部作られる
- 後から起動したエージェントに、即時起動と同じ会話の名前・`OCW_ROLE` / `OCW_RUN_ID`・
  `OCW_*_COMMAND` の上書きが効く（**この regression は必ず自動テストで固定する**。
  名前が落ちると孫2 の成果が消え、`OCW_*_COMMAND` が効かないと人間の設定を壊すため）
- claude 以外の起動コマンドは今までどおり変わらない
- 既存の外部契約（出力行・ペイン構成）が変わっていない

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。
本物の herdr で何を確かめたかは ADR と PR の説明に書く。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --all-files
python3 -m unittest discover -s bin/tests -v
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `herdr-worktree-group` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）
5. マージを終えたら、司令官が spawn の送信文で渡した司令官の Herdr ペインへ完了を通知する
   （渡されていなければ通知しない）。送り方は傘ブランチ上の `skills/umbrella-orchestrator/SKILL.md`
   §5「AI間送信手順（二段構え）」に従う。本文は
   「孫6 `hwg-06-lazy-agents` の PR #<番号> を herdr-worktree-group へマージしました。」だけにする。
   通知は1回だけ。送れなくても止まらず、送れなかったことを最終報告に1行書く

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````
