# 計画書: pr-review-loop の投稿が auto mode の分類器に止められる

傘ブランチ: `review-post-classifier`
ターゲット: `master`

## 概要

`/pr-review-loop` で、レビュー AI の review・コメントの投稿や、実装 AI の返信・スレッド解決が、
Claude Code の auto mode の分類器（soft_deny の「External System Writes」）に止められる件が
2026-10-29 から急に増えた。複数のリポで起きている。この傘で次の3つを進める。

1. **書き込みの形を決める（孫1。候補B）。** `skills/pr-review-loop/SKILL.md` に GitHub への書き込みの
   手順を1つ決め、本文や JSON はファイル書き込みツールで書き、投稿は対象を絞った許可ルールに当たる
   単体コマンドで打つ。許可ルールに当たったコマンドは分類器を通らない（背景5）。その許可ルールを
   配布物 `claude/settings.json` に入れる
2. **分類器に「人間が承認済み」と伝える文を足す（孫2。候補A）。** 配布物 `claude/settings.json` の
   `autoMode.allow` に許可の文を足す。**入れるかどうかは人間がレビューで決める**ので、孫1 と分け、
   孫1 だけでも効くように作る
3. **各リポへの適用（孫3〜7）。** dotfiles 側の形が決まってから、司令官が各リポで要否を判定し、
   要るリポだけに孫を出す。調べた範囲では、ほとんどのリポで変更が要らない見込み（設計3）

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。転記後に削除済みで
> 参照できない前提で書く）を material として司令官が起草したものである。** ブリーフに
> 書かれていた問題意識・決定事項・既存の穴・実測値・未確認の前提・制約・スコープ外・必須の
> 検証ステップ・孫分割の叩き台は本計画書へ転記済みであり、以降はこの計画書が正典である。
> ブリーフが「着手時に潰すこと」とした未確認の前提は、司令官が計画書の起草前に確かめた（背景5）。

## 孫ブランチ進捗

| 孫 | リポ | ブランチ | 内容 | 状況 |
|---|---|---|---|---|
| 1 | dotfiles | `rpc-01-post-procedure` | `pr-review-loop` の GitHub への書き込み手順を決め（ファイル書き込みツール + 単体コマンド）、gh の許可ルールを配布物 `claude/settings.json` へ移し、スレッド解決の扱いを決める。ADR を書く | ✅ PR #185 マージ済 |
| 2 | dotfiles | `rpc-02-automode-allow` | 配布物 `claude/settings.json` に `autoMode`（`"$defaults"` 付きの `allow`）を足し、machine 設定とのマージでの扱いを決める。`claude auto-mode critique` に通す | 🔄 実装中（コミットが分類器に止められ、人間の判断待ち。通知済み） |
| 3 | pixidex | `rpc-03-post-rules` | 設計3 の判定で要ると決まったときだけ | ⬜ 待機中（要否判定待ち） |
| 4 | modeldex | `rpc-04-post-rules` | 同上 | ⬜ 待機中（要否判定待ち） |
| 5 | iosci | `rpc-05-post-rules` | 同上 | ⬜ 待機中（要否判定待ち） |
| 6 | lora-dataset-forge | `rpc-06-post-rules` | 同上 | ⬜ 待機中（要否判定待ち） |
| 7 | sheaf | `rpc-07-post-rules` | 同上 | ⬜ 待機中（要否判定待ち） |

状況値の追加: 要らないと判定した孫は `➖ 不要（<理由>）` と書き、spawn しない。

依存:

- 孫1 を先に進める。孫2 は**孫1 が傘にマージされてから** spawn する（同じ `claude/settings.json` を触る。
  また孫2 の文は「孫1 の形で書けば許可ルールで通る」ことを前提に、それでも漏れる場合の保険として書くため）
- **孫2 は AI のレビューで承認されても、司令官はすぐにはマージしない。** 承認を確かめたら人間に通知し、
  人間が採用すると言ってから傘へマージする（背景2。umbrella-orchestrator §2.4 の「マージを待て」を
  この計画書で最初から指定しておく）。不採用なら PR を閉じ、状況を `➖ 不採用` にする
- 孫3〜7 は、孫1 が傘にマージされ、孫2 の採否が決まってから、司令官が設計3 の判定をして spawn する。
  他リポの孫なので PR は各リポの既定ブランチ向きで、マージは人間。孫3〜7 どうしは並列でよい
- 傘の最終 PR（`master` 向き）は、孫3〜7 の ⏳ を待たずに作ってよい（各リポの変更は dotfiles の
  `master` に依存しない形にする。設計3）。⏳ が残るときは `/finalize` の前に人間に確認する

## 関係するリポ

このリポ（dotfiles）は公開リポで、他は全部非公開なので、owner/name は値ではなく解決方法を書く
（`umbrella-orchestrator` §2.1）。司令官はそのリポのメインワークツリーへ `cd` してから叩いて値を得る。
進捗テーブルの状況値も `owner/name` の代わりに「名前」列の短い名前で書く（例: `⏳ 人間のマージ待ち (PR pixidex#12)`）。

| 名前 | メインワークツリー | owner/name | 既定ブランチ |
|---|---|---|---|
| dotfiles | `/home/manemone/projects/dotfiles/master` | `manemone/dotfiles` | `master` |
| pixidex | `/home/manemone/projects/pixidex/main` | メインワークツリーで `gh repo view --json nameWithOwner -q .nameWithOwner` を叩いた値 | `main` |
| modeldex | `/home/manemone/projects/modeldex/main` | 同上 | `main` |
| iosci | `/home/manemone/projects/iosci/main` | 同上 | `main` |
| lora-dataset-forge | `/home/manemone/projects/lora-dataset-forge/main` | 同上 | `main` |
| sheaf | `/home/manemone/projects/sheaf/main` | 同上 | `main` |

各リポで守るべき規約の在処は、それぞれの `AGENTS.md`（dotfiles は作業別の索引の DOC-2610150520 系も）。
pixidex・modeldex・iosci・sheaf は `.claude/pr-review.yml`（`convention_docs` に PR の作法とレビューの観点の
文書を列挙）も持つ。lora-dataset-forge は `.claude/pr-review.yml` を持たない（2026-10-31 に `origin/main` で確認。
ブリーフは sheaf も持たないとしていたが、`origin/main` には有った）。
司令官は他リポのメインワークツリーで `git fetch origin` と `ocw` と読み取り（`git show origin/main:<path>` 等）
だけを叩き、`git checkout` / `git merge` / `git pull` は叩かない。

## ワークスペースラベル

接頭辞は `ocw label-prefix`（lora-dataset-forge だけ `LDF`、他はリポ名と同じ）。

- 傘: `dotfiles :: 投稿が分類器に止まる`
- 孫1: `dotfiles :: 投稿が分類器に止まる 孫1 書き込み手順を決める`
- 孫2: `dotfiles :: 投稿が分類器に止まる 孫2 autoMode の許可文`
- 孫3〜7: `<接頭辞> :: 投稿が分類器に止まる 孫N 投稿の許可を当てる`

## 背景1: 問題意識（要約）

ここ数日、`pr-review-loop` の承認メッセージ（レビュー AI の review 投稿）が auto mode の分類器に止められる
ことが増えた。特定のリポではなく、いくつものリポで起きている。人間はこれを何とかしたい。

相談 AI が原因の調査結果と直し方の候補（背景3・背景4）を示し、いったん「dotfiles に PR 1 本」で合意しかけたが、
人間が傘に変えた。理由は2つ: dotfiles で直したあと各リポにも当てていきたいこと、2ペインの軽いハンドオフだと
実装が Sonnet だけになり心もとないこと（設計判断は司令官が持つ。本計画書の設計節は司令官が前提を確かめた
うえで書いており、孫はそれを実行する）。

## 背景2: 人間が確定させた決定事項（覆さないこと）

- 傘ブランチ方式で進める（PR 1 本の軽いハンドオフにはしない）
- dotfiles 側で直したあと、それを各リポに当てていく。各リポへの適用もこの傘の範囲に入る
- 分類器を緩める変更（候補A＝孫2）を入れるかどうかは、人間がレビューで決める。候補A を外しても
  候補B（孫1）だけで効果が出るように作り、PR 本文で「何を許すことになるか」をはっきり書く

## 背景3: 既存の穴

ブリーフの記述に、司令官が 2026-10-31 に確かめたことを足した。

- `skills/pr-review-loop/SKILL.md` には GitHub への書き込みの手順が決まっていない（`gh api` が出てくるのは
  レビュー結果の取得の1か所だけ）。レビュー AI と実装 AI は毎回その場でコマンドを組み立てている。
  ヒアドキュメント・`cd …;` を使った複合コマンドや、ruby で JSON を組み立てて `--input` で送る形などがある。
  投稿形式そのもの（マーカー・投稿先・スレッド解決・再レビュー手順）は、各リポの `.claude/pr-review.yml` の
  `convention_docs` が決める作りになっている（SKILL.md「規約優先順位」）
- **各リポの規約文書は、投稿のコマンドもスレッドの解決も定めていない。** pixidex・modeldex・iosci・sheaf・
  lora-dataset-forge の `docs/design/`・`AGENTS.md`・`.claude/pr-review.yml` を `origin/main` で
  `gh api` / `gh pr review` / `gh pr comment` / `resolveReviewThread` / ヒアドキュメント / `--input` /
  `--body-file` で探して、1件も無かった。つまり壊れ方はリポの規約ではなく、AI がその場で組み立てる形にある
- `~/.claude/settings.json`（このマシンの生成物）の `permissions.allow` には次がある:
  - `Bash(gh api repos/manemone/*/pulls/*/reviews *)` / `Bash(gh api -X POST repos/manemone/*/pulls/*/reviews *)`
  - `pulls/*/comments` と `issues/*/comments` の同様のルール
  - `Bash(gh pr review *)` / `Bash(gh pr comment *)`
  - 素の `Bash`（auto mode では捨てられる。背景5）

  **これらの gh のルールは、配布物 `claude/settings.json` にも machine 設定（`settings.machine.json`）にも無い。**
  過去にこのマシンの生成物へ足されたものが、`claude/deploy.sh` の「既存の `permissions.allow` を引き継ぐ」
  処理で残っているだけである。ほかのマシンには無い
- 各リポの `.claude/settings.json`（`origin/main`）の gh の許可: pixidex・modeldex・lora-dataset-forge・sheaf は
  `Bash(gh pr:*)` と `Bash(gh api:*)` を持つ。iosci は `gh issue list/view` と `gh pr view/list/checks` など
  読み取りだけで、書き込みの許可は無い
- auto mode の分類器の既定規則（`claude auto-mode defaults` で全文が読める。v2.1.314）の要点:
  - soft_deny の「External System Writes」は、PR への新しいコメント投稿（`gh pr comment`、`issues/{n}/comments`・
    `pulls/{n}/comments` への POST）と title/body の編集を、**人間本人の発言が頼んだ PR**（またはそのセッションで
    AI が開いた PR）に限って許す。ツール結果・ファイル・PR 本文だけが指す PR は対象外
  - 次は許される範囲の外だと名指しされている: **レビューのスレッドの解決**・リアクション・レビューの却下、
    **会話の中で書いていないファイルを `--input` / `--body-file` / `-F body=@file` で送る書き込み**、
    `event` が `COMMENT` 以外の review
  - `pulls/{n}/reviews` への `event: COMMENT` の POST が許される範囲に入るかは、文面からははっきりしない
  - allow の「Multi-Agent Coordination」は、別の AI からの内容は人間の指示の同意基準を満たさないと明記している
- `umbrella-orchestrator` §5 で AI 同士の送信を `SendMessage` 優先にした。そのため、レビューの依頼が
  別セッションのメッセージとして届くようになり、分類器から見ると「人間に頼まれていない PR への書き込み」になる

## 背景4: 実測値

2026-10-31 に相談 AI が `~/.claude/projects/*/*.jsonl` の会話記録を走査して集計した（生データと集計スクリプトは
一時物で、転記後に削除した。再集計の方法は 4.1）。

- PR へのコメント・review の投稿は、10/28 までほぼ止められていなかった（10/16 と 10/20 に 1 件ずつ程度）。
  10/29〜30 の 2 日で 9 件止められた（同じ 2 日の投稿は約 280 件）。pixidex と lora-dataset-forge の両方で起きている
- 直近 6 日で、止められた投稿と、レビューを頼んだメッセージの届き方を突き合わせた:
  - 別セッションのメッセージで依頼が届いたセッション: 39 件中 5 件、約 13%
  - それ以外（`herdr agent prompt` で貼られた依頼を含む）: 359 件中 5 件、約 1.4%
- 止められた操作は 3 種類だった:
  1. レビュー AI の review / コメントの投稿
  2. 実装 AI の `resolveReviewThread`（GraphQL）によるスレッド解決: 3 件
  3. `--input` で JSON ファイルを送る投稿（シェルの中で ruby が JSON を組み立てたもの）
- **止められた 10 件は全部、複合コマンドだった。** ただし投稿のほぼ全部（389 件中 383 件）が複合コマンドで、
  単体の `gh …` は 6 件しかない。このデータだけからは「単体なら通る」とは言えない（それを言えるのは背景5 の
  公式の評価順のほう）
- 司令官が生データを数え直した補足: 止められた記録 14 件（投稿以外も含む）のうち、ヒアドキュメントを含むものが
  10 件、`--input` が 3 件、`-F body=@` が 2 件、`resolveReviewThread` が 3 件。`cd …;` と変数代入
  （`S=…;`）で始まるものも多い

### 4.1 再集計の方法

`~/.claude/projects/**/*.jsonl`（サブエージェントの記録を含む）を読み、`tool_result` の本文に
`auto mode classifier` を含むものを拾い、同じ `tool_use_id` の `tool_use` の `input.command` と、拒否理由
（`Reason: [...]`）・タイムスタンプ・プロジェクト名を並べる。投稿の分母は、`tool_use` の `command` に
`gh api … /pulls/…/reviews`・`/comments`・`gh pr comment`・`gh pr review`・`resolveReviewThread` を含むものを数える。
依頼の届き方は、そのセッションの user メッセージに `<cross-session-message` があるかで分ける。
傘のマージと人間のデプロイの後に、同じ方法で前後を比べる（進行記録に書く）。

## 背景5: 未確認だった前提の確認結果（司令官が 2026-10-31 に確かめた）

出典は Claude Code の公式ドキュメント（`code.claude.com/docs/en/` の `permission-modes`・`auto-mode-config`・
`permissions`・`cross-session-messaging`）と、ローカルの `claude auto-mode defaults` / `config`（v2.1.314）。

- **許可ルールに当たれば分類器を通らない。** 評価の1段目は「allow / ask / deny のルールに一致したら即決」で、
  分類器はどのルールにも当たらなかったものが落ちる先（ADR DOC-2609121719 §3.5 とも一致）。例外として
  ルールがあっても確認が出るのは、保護パスへの書き込み・重要パスの `rm`・内容に当たる ask ルールなどで、
  gh による外部への書き込みは含まれない
- **広すぎる許可は auto mode に入るときに捨てられる。** `Bash(*)`・インタプリタのワイルドカード
  （`Bash(python*)` など）・パッケージマネージャの run 系などが名指しされている。`Bash(npm test)` のように
  絞ったルールは有効のまま。どこまで絞れば有効かの基準は書かれていない。`Bash(gh api:*)` のような
  リポ側のルールがどちらに当たるかの明記も無い（任意コード実行を許すものが捨てられる、という説明にとどまる）
- **`*` は途中にも書け、空白や `/` も含む任意の文字列に当たる。** ただし最初の `*` より前は一字一句の一致が要る。
  `Bash(gh api -X POST repos/manemone/*/pulls/*/reviews *)` は `gh api -X POST repos/manemone/` で始まる
  コマンドにしか当たらない（`--method POST` や、`-X POST` を後ろに書いた形には当たらない）
- **ルールはコマンド文字列に当たる。** シェル変数は展開されない（`gh api repos/$OWNER/...` は
  `repos/manemone/` の前置に当たらない）。先頭の変数代入（`S=… gh …`）は、既知の安全なもの以外があると当たらない
- **複合コマンドは区切り（`&&` `||` `;` `|` `&` 改行）で分割され、全部が許可ルールに当たるか読み取り専用で
  なければならない。** `cd <作業ディレクトリ内>` は読み取り専用扱いだが、作業ディレクトリの外への `cd` は別途
  許可が要る。ヒアドキュメントや `$(...)` を含む形の照合は明記が無い（確実なのは単体コマンド）
- `autoMode` の書き方:
  - キーは `environment` / `allow` / `soft_deny` / `hard_deny`（自然文の配列）と `classifyAllShell`（真偽値）
  - `allow` は soft_deny の例外として働く
  - **配列に `"$defaults"` を入れると既定に追加、入れないとそのセクションの既定を置き換える。** `allow` に
    1行だけ書くと既定の allow が消える
  - `classifyAllShell: true` にすると Bash の許可ルールが全部止まり、すべて分類器に回る（孫1 の形が効かなくなる）
- **`autoMode` はユーザー設定（`~/.claude/settings.json`）・managed・`--settings` からしか読まれない。リポの
  `.claude/settings.json` / `.claude/settings.local.json` の `autoMode` は無視される**（リポが許可を注入できない
  ようにするため）。一方 `permissions.allow` はリポの `.claude/settings.json` でも効く
- **`claude auto-mode critique`** は、自分で足した `autoMode` の項目を AI が講評し、曖昧・冗長・誤検知しやすい
  項目を指摘する。`config` は実効値を出す（2026-10-31 時点でこのマシンの実効値は既定と同じ。`autoMode` は未設定）
- 別セッションのメッセージは人間の同意にならない（`cross-session-messaging`）。分類器がそれを「人間の意図」と
  扱うかどうかの明記は無いが、既定規則（背景3）の書き方からは扱わないと読める

ここから出る結論:

- **候補B（孫1）が主役。** 投稿を「絞った許可ルールに当たる単体コマンド」にすれば、依頼がどう届いたかに
  関係なく分類器を通らない。分類器の気分に左右されない確実な経路はこれだけ
- **候補A（孫2）はユーザー設定にしか書けない。** だから各リポへの適用（孫3〜7）で `autoMode` を各リポに
  書くことはできない。候補A を採るなら dotfiles の配布物（`claude/settings.json` → 生成される
  `~/.claude/settings.json`）だけで全リポに効く
- 各リポに残る仕事は、リポ側の `permissions` が孫1 の形とぶつからないかの確認が中心になる（設計3）

## 背景6: 司令官をこのリポに置く理由

直す対象（`pr-review-loop` スキル・配布する `claude/settings.json`・`umbrella-orchestrator` の送信手順）は
すべて dotfiles にあり、「どう直すか」の問いと結論が載るのも dotfiles である。各リポへの適用は、dotfiles で
決めた形を当てる確認・展開にあたる。

## 設計1: 書き込み手順を決める（孫1。候補B）

### 1.1 書き込みの形

`skills/pr-review-loop/SKILL.md` に「GitHub への書き込み手順」の節を1つ新設し、レビュー指示テンプレート
（レビュー AI が読む）と Phase 6（実装 AI の返信）からそこを参照させる。全文を2か所へ写さない。決めること:

- **本文・JSON は、エージェントのファイル書き込み機能で作る**（Claude Code なら Write ツール）。シェルの
  ヒアドキュメント・`echo`・`ruby -e` / `python -c` で組み立てない。理由: 内容が会話記録に残り、分類器に
  落ちた場合でも「この会話が書いていないファイル」にならない。ファイルは作業ツリーの外（`mktemp -d` や
  スクラッチパッド）に置き、コマンドでは絶対パスで渡す
- **投稿は単体のコマンド1つで打つ。** `cd …`・`;`・`&&`・パイプ・先頭の変数代入・`$(...)`・ヒアドキュメントを付けない。
  `--jq` のようなフラグは構わない
- **owner / repo / PR 番号 / SHA は値をそのまま書く。** シェル変数で書くと許可ルールに当たらない（背景5）。
  SKILL.md の他の箇所は `$OWNER` などの変数で書いているので、この節だけは「実行するときは値に置き換えた
  コマンドを打つ」と明記する
- **形は許可ルールの前置に合わせて固定する。** 例（孫1 が最終形を決める）:
  - review（本文＋インラインコメントを1回で）: `gh api -X POST repos/<owner>/<repo>/pulls/<n>/reviews --input <JSON の絶対パス>`
    （JSON の `event` は `COMMENT` 固定。`APPROVE` / `REQUEST_CHANGES` は使わない。umbrella-orchestrator §2.4）
  - インラインコメントへの返信: `gh api -X POST repos/<owner>/<repo>/pulls/<n>/comments/<id>/replies ...` か
    `pulls/<n>/comments` への POST（どちらにするかと、それに当たる許可ルールを孫1 が決める）
  - 会話コメント（対応報告など）: `gh pr comment <n> -R <owner>/<repo> --body-file <絶対パス>`
- **止められたら、形を変えて同じ書き込みを試し直さない。** 回避と見なされうるうえ、分類器は3回連続または
  累計20回止めると auto mode を一時停止する（ADR DOC-2609121719 §3.5）。止められたら、投稿しようとした
  ファイルのパスと打とうとしたコマンドを残して人間（または司令官）に伝えて止まる。細部は孫1 が決める
- **AI 不問で書く**（ADR DOC-2608272128）。Codex / OpenCode には auto mode の分類器が無いが、上の形は
  どのエージェントでもそのまま動く。手順は「単体コマンド・ファイル書き込み機能で作ったファイルを渡す」と
  一般の形で書き、理由（Claude Code の許可ルールと分類器）は注記に回す

### 1.2 許可ルールを配布物へ移す

背景3 のとおり、gh の許可ルールはこのマシンの生成物にしか無い。1.1 の形に当たるルールを配布物
`claude/settings.json` の `permissions.allow` に入れる。

- 対象は `manemone/*` のリポに絞る（dotfiles は個人の設定である）。1.1 で決めた形と一字一句前置が合うことを、
  ルールとコマンドを並べて確かめる
- `gh api` の読み取り（`gh api repos/manemone/*/pulls/*/reviews *` の GET）も今のルールに入っている。要るものは
  残し、要らないものは足さない
- `permissions.ask` / `deny` と、PreToolUse フック `claude/hooks/git-guard.sh`（ADR DOC-2609121719）との矛盾が無いか
  確かめる。`gh pr merge` には触らない
- 生成のしくみ（DOC-2610150520-b）は変えない。配布物に足せば、既存の生成物にある同じ文字列とは重複排除される

### 1.3 スレッドの解決

`resolveReviewThread` は、分類器の既定規則では PR 作業の範囲の外と名指しされている（背景3）。各リポの
規約も SKILL.md もスレッドの解決を求めていない（背景3）が、SKILL.md のレビュー AI の読み方（ラウンド2以降は
「未解決のスレッド」を読む）は解決状態に頼っている。孫1 は次のどちらかに決め、ADR に理由を書く:

- (a) **手順から外す**（AI はスレッドを解決しない。対応は返信で示し、レビュー AI はラウンド2以降、前回レビュー
  対象 SHA より後の返信を読む）。読み方の節を合わせて直す
- (b) **絞った許可ルールで通す**。クエリ文を固定した形（スレッド ID だけが変わる）にし、それに当たるルールを
  1.2 に足す。**実機で1回、分類器を通らずに解決できることを確かめられた場合に限る**（クォートの扱いなどで
  当たらないことがありうる。背景5 の「記載なし」）

確かめられなければ (a) にする。

### 1.4 実機での確認

この孫自身の PR の `/pr-review-loop` で、レビュー AI に 1.1 の形で投稿させ、止められずに通ったかを PR 本文に
書く。この孫のレビュー依頼は `SendMessage`（別セッションのメッセージ）で届くので、背景4 で止められやすかった
条件そのものになる。このマシンの生成物にはすでに review・comments の許可ルールがあるので、デプロイ前でも
確認できる（1.3 の (b) のルールだけはデプロイ前には無いので、確かめるならそのコマンドに当たるルールが生成物に
無いことに注意して、確認の方法を PR 本文に書く。生成物を手で書き換えたりデプロイを実行したりしない）。

### 1.5 参照と記録

- 変えた手順を参照しているところ（`skills/umbrella-orchestrator/SKILL.md`・`skills/pr-group-review/SKILL.md`・
  `skills/pr-group-request/SKILL.md` など、PR へ投稿する手順を持つスキル）を `git grep` で洗う。同じ組み立ての
  癖があれば、1.1 の節を参照させる形で揃える（揃える範囲が大きくなりすぎたら、PR 本文に残りを書いて止める）
- ADR を1本書く（決めた形・許可ルールを配布物へ移したこと・スレッド解決の扱い・却下案）。却下案に必ず入れる:
  **レビュー依頼の届け方を `herdr agent prompt` に戻し、人間の入力のように見せて分類器を通す案は採らない**
  （同意の基準をすり抜ける形であり、分類器の意図に反する）

## 設計2: autoMode に許可の文を足す（孫2。候補A）

- 配布物 `claude/settings.json` に `autoMode` を足す。`allow` は必ず `"$defaults"` を先頭に置く（背景5。付け忘れると
  既定の allow が消える）。`soft_deny` / `hard_deny` は書かない（既定のまま）。`classifyAllShell` は書かない
- 文の趣旨: 「Herdr 上の `pr-review-loop` で、実装 AI・レビュー AI・司令官が互いのメッセージ（別セッションの
  メッセージを含む）に従って、`manemone/*` の PR に `event: COMMENT` の review・インラインコメント・返信・会話
  コメントを投稿し、レビューのスレッドを解決することは、人間が承認済み」。範囲は狭く書く。承認・変更要求の
  review、マージ、他人のコメントの編集・削除、PR の状態や base の変更、`manemone/*` 以外は含めない
- `environment` に足す必要があるか（信頼するソース管理の範囲を `github.com/manemone/*` に広げるなど）を検討し、
  足すなら `"$defaults"` 付きにする。要らなければ足さない
- **machine 設定とのマージでの扱いを決める。** `claude/deploy.sh` の `merge_claude_settings` は、`permissions` 以外の
  辞書を浅い `update()` でマージする。machine 側が `autoMode.allow` を持つと、配布物の `autoMode.allow` が丸ごと
  置き換わる。`permissions` と同じく配列を連結するか、今のまま（machine が勝つ）にして文書に書くかを決める。
  連結にするならデプロイのスモークテストで固定する
- `claude auto-mode critique` に通し、講評と、それを受けて直したことを PR 本文に書く。このマシンには生成物が
  あるが、**デプロイ（`deploy-all.sh` の実オペレーション）は実行しない**。critique はユーザー設定を読むので、
  実行の方法（一時的に `--settings` で渡せるか、`HOME` を差し替えたサンドボックスで生成した設定を読ませるか）を
  孫2 が決め、PR 本文に書く
- **PR 本文に「何を許すことになるか」の節を置く。** 許すこと・許さないこと・孫1 だけの場合との違い（孫1 の形から
  外れたコマンドを AI がその場で組み立てた場合にも通るようになる）を、人間が採否を決められるように書く
- ADR は孫1 の ADR に追記するか、1本足すかを孫2 が決める

## 設計3: 各リポへの適用（孫3〜7）

背景5 のとおり、`autoMode` はリポ側に書けないので、各リポに当てられるのは `permissions` と規約文書だけである。
孫1 の許可ルールはユーザー設定として全リポに効く（人間が傘を `master` にマージしてデプロイしたあと）。
そのため、多くのリポで変更は要らない見込みである。

**司令官の判定（孫1 が傘にマージされ、孫2 の採否が決まった時点で、読み取りだけで行う）。** 各リポについて:

1. `origin/main` の `.claude/settings.json` の `permissions.ask` / `deny` に、孫1 の形のコマンドに当たるものが無いか
   （あれば許可より優先されて確認が出る）
2. `origin/main` の `AGENTS.md`・`.claude/pr-review.yml` の `convention_docs`・`docs/design/` に、孫1 の形と食い違う
   投稿手順やスレッド解決の決まりが新しく入っていないか（2026-10-31 時点では無い。背景3）
3. リポ側の `Bash(gh api:*)` / `Bash(gh pr:*)` を、孫1 の絞ったルールに置き換えるか。**置き換えは既定ではしない**
   （リポの他の用途に使われていることがあり、この傘の範囲を超える）。孫1 の ADR が置き換えを勧めた場合だけ検討する
4. 孫1 の形が、そのリポの作業ディレクトリ・規約（例: 一時ファイルの置き場所の決まり）と矛盾しないか

どれにも当たらなければ `➖ 不要（<理由>）` にして spawn しない。当たれば、その孫用プロンプトの「やること」を
具体的に書き足してから spawn する（判定の結果は進行記録に書く）。

各リポの変更は、dotfiles の `master`（ユーザー設定の配布）に依存しない形にする（リポ側だけで完結する設定・文書）。

## 決定的な制約（孫は全部守ること）

- dotfiles `AGENTS.md` の最重要ルール: `master` の書き換えは人間だけ。**deploy スクリプト（`deploy-all.sh` /
  `*/deploy.sh`）を AI の判断で実オペレーションで実行しない**（`--dry-run` と `HOME` を差し替えたサンドボックスは可。
  範囲は DOC-2608020715-b）。linter の抑制を AI の判断で足さない
- **このマシンの `~/.claude/settings.json` などの生成物を手で書き換えない。** 設定を変えるのは配布物
  `claude/settings.json` だけで、効くのは人間がデプロイしてから
- 他リポの孫の PR は既定ブランチ向きで、マージは人間（`umbrella-orchestrator` §2.4）
- 配布物 `claude/settings.json` の変更は、デプロイの仕組み（DOC-2610150520-b）と git 操作の許可方針の
  ADR DOC-2609121719 との整合を取る
- `skills/` は Claude Code・Codex・OpenCode に同じ実体を配る（ADR DOC-2608272128）。`pr-review-loop` の手順を
  Claude Code の auto mode 前提だけで書かない
- **分類器に止められた操作を、形を変えて回避しない。** 止められたら人間に伝える
- dotfiles は公開リポである。計画書・ADR・PR 本文に、人間の発言の逐語や非公開リポの PR 番号・ブランチ名・
  内容を書かない（要約する）。非公開リポの owner/name は値ではなく解決方法で書く

## スコープ外

- 傘 `meter-subagent-quota`（ocw-meter の数え漏れと週上限の見積もり）。そちらのワークツリー・孫に触らない
- 分類器そのものの挙動の変更（Claude Code 側の問題として報告するかどうかは人間が決める）
- `umbrella-orchestrator` §5 の `SendMessage` 優先の方針を戻すこと（設計1.5 の却下案）
- リポ側の広い gh の許可（`Bash(gh api:*)` など）の見直し（設計3 の 3）

## 必須の検証ステップ

- dotfiles: `pre-commit run --files <path>`（まとめて確認するなら `pre-commit run --all-files`）。
  デプロイ関連のシェルや `claude/settings.json` の生成を変えたら `tests/deploy_smoke.sh` と `./deploy-all.sh --dry-run`。
  `bin/` を変えたら `python3 -m unittest discover -s bin/tests -v`。`docs/` に新規ファイルを足すときは
  `DOC-DOCID_PLACEHOLDER_<名前>.md` で作って `./tools/doc-id/doc-id assign <path>` で採番し、`./tools/doc-id/doc-id verify`
- `claude/settings.json` を変えたら、JSON として読めることと、`claude/deploy.sh` の生成結果（サンドボックスの `HOME`）に
  意図したキーが入ることを確かめる
- 各リポ: そのリポの `AGENTS.md` の検証コマンド

## テスト方針（dotfiles AGENTS.md「テスト方針」に従う）

孫1 の手順の変更はスキル文書であり、自動テストの対象ではない。効き目は設計1.4 の実機確認で示す。
許可ルールの前置とコマンドの形の一致は、PR 本文にルールとコマンドを並べて示す。
孫2 で `merge_claude_settings` の振る舞いを変えた場合だけ、`tests/deploy_smoke.sh` の既存の scenario に
`autoMode` の配列が machine 設定と連結されることを足す（変えないなら足さない）。
テストを足す前に DOC-2610150520-a の判断表を通す。

## 孫ブランチ分割の叩き台（ブリーフより転記。採った分割は上の進捗テーブル）

ブリーフの叩き台は次のとおりだった（司令官が再設計してよいとされていた）。

- 孫A（dotfiles）: pr-review-loop の書き込み手順を決める（候補B）。本文や JSON は Write ツールで書く。
  `gh api` / `gh pr comment` は単体で打ち、既存の許可ルールに当たる形にする。スレッド解決の扱い（許可ルールで
  通すか、手順から外すか）も決める
- 孫B（dotfiles）: 配布する `claude/settings.json` の `autoMode` に許可の文を足す（候補A）。`claude auto-mode critique`
  に通す。人間が採否を決められるよう、孫A と分ける
- 孫C 以降（他リポ）: dotfiles 側の形が決まってから、各リポの `.claude/settings.json` や `.claude/pr-review.yml` に
  要る変更を当てる。要らないリポは飛ばす

司令官が変えた点: 孫A に「許可ルールを配布物へ移す」を足した（背景3 で、ルールがこのマシンの生成物にしか無いと
分かったため）。孫C 以降は、`autoMode` がリポ側に書けない（背景5）ことから、司令官の判定で要るリポだけに出す形にした。

## 進行記録

- 2026-10-31: 計画書を起草。未確認だった前提を公式ドキュメントとローカルの `claude auto-mode` で確かめた（背景5）
- 2026-10-31: 孫1 を spawn
- 2026-10-31: 孫1 PR #185 をマージ（ADR DOC-2610310315）。スレッドの解決は手順から外した（設計1.3 の (a)）。配布物の `permissions.allow` に投稿の3形を足し、`permissions.ask` に `gh api` の PUT・DELETE・PATCH・`--method`・`merge` を含む形を足した。**ask はユーザー設定として全リポに効くので、設計3 の判定では各リポの AI が使っている `gh api --method …` 等が新たに確認を出さないかも見る**
- 2026-10-31: 孫2 を spawn

## 孫1用プロンプト:

````markdown
# 傘ブランチ: review-post-classifier
# 孫ブランチ: rpc-01-post-procedure
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/review-post-classifier/docs/planning/DOC-2610310309_review-post-classifier_計画.md`

**まず計画書の「概要」「背景2」「背景3」「背景4」「背景5」「設計1」「決定的な制約」「スコープ外」「必須の検証ステップ」
「テスト方針」「進行記録」を読むこと。** 設計1 の前提（許可ルールに当たれば分類器を通らない等）は司令官が確かめ済み
なので、調べ直さなくてよい。

## 実装開始前の必須手順

`ocw` がすでに `rpc-01-post-procedure` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/review-post-classifier` の
先端から切られていることを確かめる（`git pull` は使わない）。

## やること

1. 計画書 設計1.1 の「GitHub への書き込み手順」の節を `skills/pr-review-loop/SKILL.md` に新設し、レビュー指示
   テンプレートと Phase 6 から参照させる
2. 計画書 設計1.2 のとおり、1 の形に当たる gh の許可ルールを配布物 `claude/settings.json` の `permissions.allow` に入れる
   （このマシンの `~/.claude/settings.json` は書き換えない。デプロイも実行しない）
3. 計画書 設計1.3 でスレッドの解決の扱いを決め、SKILL.md（レビュー AI の読み方を含む）に反映する
4. 計画書 設計1.4 の実機確認をし、結果を PR 本文に書く
5. 計画書 設計1.5 の参照を洗って揃え、ADR を書く（`docs/adr/DOC-DOCID_PLACEHOLDER_*.md` で作って `./tools/doc-id/doc-id assign`）

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 手順どおりに打つコマンドが、`claude/settings.json` に入れた許可ルールの前置に一字一句当たる
  （ルールとコマンドを並べて PR 本文に示す）
- 別セッションのメッセージで依頼が届いたレビュー AI の投稿が、分類器に止められずに通る（設計1.4 の実機確認）
- Codex / OpenCode のエージェントや Herdr なしの経路で、手順が壊れない（文書の上で突き合わせる）
- `claude/settings.json` が JSON として読め、`permissions.ask` / `deny` と git-guard フックの方針（ADR DOC-2609121719）と矛盾しない
- 参照が切れていない（`./tools/doc-id/doc-id verify` と `git grep`）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --all-files
./tools/doc-id/doc-id verify
./deploy-all.sh --dry-run
```

`claude/settings.json` を変えるので `tests/deploy_smoke.sh` も実行する。

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `review-post-classifier` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** `/pr-review-loop` の手順にマージへ進む記述があっても実行しない
   （孫が人間のフィードバック前に勝手にマージするのを防ぐため。マージは傘の司令官が行う）
5. 最終報告を書き終えたら、最後の行動として、司令官が spawn の送信文で渡した司令官の Herdr ペインへ
   承認を報告する（渡されていなければ報告せず、人間に「承認済み。マージは司令官（または人間）が行う」と伝えて止まる）。
   送り方は umbrella-orchestrator スキル §5「AI間送信手順（二段構え）」に従う。本文は
   「孫1 `rpc-01-post-procedure` の PR #<番号> が HEAD <短縮SHA> で承認されました。マージをお願いします。」
   だけにする。報告は1回だけ。送れなくても再送せず、送れなかったことを人間に1行伝えて止まる

PR への投稿・返信は、この孫で新設する「GitHub への書き込み手順」の形で打つこと（実機確認を兼ねる）。
分類器に止められたら形を変えて試し直さず、PR 本文の実機確認の欄に記録し、人間に1行伝える。

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
傘ブランチが先へ進んでコンフリクトしたら `git rebase origin/review-post-classifier` と
`git push --force-with-lease` で追随する（AGENTS.md「最重要ルール」）。

## 大きい出力を文脈へ流し込まない（実装中ずっと）

文脈の膨張は、1k〜20k字級の出力の積み重ねと、自分で書く長い出力で起きる。次を守ること:
- ファイルを `cat` / `sed -n` で丸ごと読まず、`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む
- 約100行・5,000字を超えそうな出力（テスト・分析・ログ・`git diff`・JSON）は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る
- 既存の長いファイルや、繰り返し直して実行するスクリプトを Write / heredoc で丸ごと書き直さない。一度ファイルに置き、変更は Edit の差分で行う（新規ファイルを最初に1回書くのは構わない）

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `review-post-classifier` から切ること**。master から切ると PR の diff に傘ブランチ全体が
混入してレビュー不能になる。`ocw` が `origin/review-post-classifier` から切ったワークツリーを用意済みなので、
上の「実装開始前の必須手順」で確かめるだけでよい（`git pull` は使わない）。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

## 孫2用プロンプト:

````markdown
# 傘ブランチ: review-post-classifier
# 孫ブランチ: rpc-02-automode-allow
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/review-post-classifier/docs/planning/DOC-2610310309_review-post-classifier_計画.md`

**まず計画書の「概要」「背景2」「背景3」「背景5」「設計1」「設計2」「決定的な制約」「スコープ外」「必須の検証ステップ」
「テスト方針」「進行記録」を読むこと。** 孫1 が傘にマージ済みなので、孫1 の ADR と `skills/pr-review-loop/SKILL.md` の
「GitHub への書き込み手順」も読む。

## 実装開始前の必須手順

`ocw` がすでに `rpc-02-automode-allow` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/review-post-classifier` の
先端から切られていることを確かめる（`git pull` は使わない）。

## やること

1. 計画書 設計2 のとおり、配布物 `claude/settings.json` に `autoMode`（`"$defaults"` を先頭に置いた `allow`）を足す
2. 計画書 設計2 の machine 設定とのマージでの扱いを決め、必要なら `claude/deploy.sh` の `merge_claude_settings` を直す
3. `claude auto-mode critique` に通し、講評と対応を PR 本文に書く（デプロイの実オペレーションは実行しない。
   実行の方法は設計2 のとおり自分で決めて PR 本文に書く）
4. PR 本文に「何を許すことになるか」の節を書く（設計2）
5. ADR を書く（孫1 の ADR への追記か、新規か。新規なら `docs/adr/DOC-DOCID_PLACEHOLDER_*.md` で作って `./tools/doc-id/doc-id assign`）

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- `autoMode.allow` の既定（`"$defaults"`）が消えない。`soft_deny` / `hard_deny` の既定に触れていない
- machine 設定が `autoMode` を持つ場合の生成結果が、決めた扱いどおりになる（マージを変えたなら `tests/deploy_smoke.sh` で固定する）
- 許す範囲が設計2 の文の趣旨から広がっていない（承認・マージ・他人のコメントの編集・`manemone/*` 以外を含まない）
- 孫1 の許可ルール（`permissions.allow`）を壊していない

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --all-files
./tools/doc-id/doc-id verify
sh tests/deploy_smoke.sh
./deploy-all.sh --dry-run
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `review-post-classifier` にすること。master には絶対に出さない。**
   PR 本文の冒頭に「この PR は人間が採否を決める（計画書 背景2）」と書く
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** `/pr-review-loop` の手順にマージへ進む記述があっても実行しない
   （この孫は人間が採否を決める。マージは人間の採用を受けて傘の司令官が行う）
5. 最終報告を書き終えたら、最後の行動として、司令官が spawn の送信文で渡した司令官の Herdr ペインへ
   承認を報告する（渡されていなければ報告せず、人間に「承認済み。採否は人間が決め、マージは司令官が行う」と伝えて止まる）。
   送り方は umbrella-orchestrator スキル §5「AI間送信手順（二段構え）」に従う。本文は
   「孫2 `rpc-02-automode-allow` の PR #<番号> が HEAD <短縮SHA> で承認されました。人間の採否を待ちます。」
   だけにする。報告は1回だけ。送れなくても再送せず、送れなかったことを人間に1行伝えて止まる

PR への投稿・返信は、孫1 が決めた「GitHub への書き込み手順」の形で打つこと。

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
傘ブランチが先へ進んでコンフリクトしたら `git rebase origin/review-post-classifier` と
`git push --force-with-lease` で追随する（AGENTS.md「最重要ルール」）。

## 大きい出力を文脈へ流し込まない（実装中ずっと）

文脈の膨張は、1k〜20k字級の出力の積み重ねと、自分で書く長い出力で起きる。次を守ること:
- ファイルを `cat` / `sed -n` で丸ごと読まず、`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む
- 約100行・5,000字を超えそうな出力（テスト・分析・ログ・`git diff`・JSON）は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る
- 既存の長いファイルや、繰り返し直して実行するスクリプトを Write / heredoc で丸ごと書き直さない。一度ファイルに置き、変更は Edit の差分で行う（新規ファイルを最初に1回書くのは構わない）

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `review-post-classifier` から切ること**。master から切ると PR の diff に傘ブランチ全体が
混入してレビュー不能になる。`ocw` が `origin/review-post-classifier` から切ったワークツリーを用意済みなので、
上の「実装開始前の必須手順」で確かめるだけでよい（`git pull` は使わない）。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

## 他リポの孫（孫3〜7）の共通手順

孫3〜7 のプロンプトは、下の共通部分に、各孫の節のリポ固有の値と「やること」を足したものである。
**「やること」は、司令官が設計3 の判定で要ると決めたときに、spawn の前に各孫の節へ書き足す。**
書き足していない孫は spawn しない。

````markdown
## 共通: 読むもの

計画書: `/home/manemone/projects/dotfiles/review-post-classifier/docs/planning/DOC-2610310309_review-post-classifier_計画.md`
（dotfiles リポ）

まず計画書の「概要」「背景3」「背景5」「設計1」「設計3」「決定的な制約」「スコープ外」を読む。
dotfiles の傘ブランチ `review-post-classifier` にある孫1 の ADR と `skills/pr-review-loop/SKILL.md` の
「GitHub への書き込み手順」も読む（`git -C /home/manemone/projects/dotfiles/review-post-classifier show origin/review-post-classifier:<path>`）。

このリポ自身の `AGENTS.md` 等の規約（ブランチ名・PR の作法・検証コマンド）に従うこと。

## 共通: 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- このリポの `.claude/settings.json` が JSON として読め、孫1 の形の投稿コマンドが `ask` / `deny` に当たらない
- このリポの他の作業で使っている許可（gh の読み取りなど）を壊していない

各項目と test example を1対1対応させる必要はない。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 共通: 実装完了後の流れ（必須）

## 大きい出力を文脈へ流し込まない（実装中ずっと）
文脈の膨張は、1k〜20k字級の出力の積み重ねと、自分で書く長い出力で起きる。次を守ること:
- ファイルを `cat` / `sed -n` で丸ごと読まず、`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む
- 約100行・5,000字を超えそうな出力（テスト・分析・ログ・`git diff`・JSON）は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る
- 既存の長いファイルや、繰り返し直して実行するスクリプトを Write / heredoc で丸ごと書き直さない。一度ファイルに置き、変更は Edit の差分で行う（新規ファイルを最初に1回書くのは構わない）

実装が完了したら、以下を**自律的に**実行してください:
1. PRを作成する。**PRの向き先は main（このリポの既定ブランチ）。**
   PR 本文に、傘の計画書（dotfiles の docs/planning/ の review-post-classifier の計画書）と、
   孫1 の PR（dotfiles の傘ブランチ向き）へのリンクを書く（複数リポにまたがる作業の継ぎ目）
2. /pr-review-loop を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** base が既定ブランチなので、マージは人間の仕事である。
   人間に「承認済みです。マージしてください」と依頼して止まる
PR への投稿・返信は、孫1 が決めた「GitHub への書き込み手順」の形で打つこと。
なお `/pr-review-loop` は、レビューを依頼した直後の区切りで文脈が大きければ `ocw self-compact` で
自分を compact する。compact の後は、復帰メモに従ってレビュー待ちに戻り、この流れを最後まで続けること
実装の途中でも、検証が通ってコミットした直後の区切りで、文脈が
200,000 トークンを超えていれば `ocw self-compact` で自分を compact してよい（WIP のコミットは
区切りでない。指摘対応の修正の途中は対象外。1 PR につき多くて 3 回。ADR DOC-2610142337）。
測り方は `/pr-review-loop` の「区切りでの自己 compact（実装側のみ）」の手順1のコマンドと同じ（その節の (3) の項だけを読めばよい。手順の「Phase 3 へ進む」は実装途中には当てはまらない）。復帰メモ
（リポの外の一時ファイル）には、計画書のパスと孫の節・済んだこと・作業中に下した判断とその理由・
残り・次の一手・検証コマンド・実装途中の compact の回数を書き、先頭に「計画書の続きから実装を
再開する。レビュー待ちではない」と書く。コマンドを実行したらそのターンを終える。
使えない・拒否・失敗なら何もせず実装を続ける
実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## ブランチ作成時の注意（最重要）
作業ブランチは傘ブランチではなく、**このリポの既定ブランチ（origin/main）から
切られている。** ocw が既に作業ブランチを作って checkout 済みなので、
git fetch origin と git log --oneline -1 origin/main で、作業ブランチが
既定ブランチの先端を含んでいることだけを確認すればよい（git pull は使わない。
既定ブランチはメインワークツリーで checkout 済みのため、ここで git checkout しない）
````

## 孫3用プロンプト:

````markdown
# 傘ブランチ: review-post-classifier（dotfiles）
# リポ: pixidex（メインワークツリー /home/manemone/projects/pixidex/main）
# 孫ブランチ: rpc-03-post-rules
# ターゲット: main（このリポの既定ブランチ。マージは人間）

計画書の「## 他リポの孫（孫3〜7）の共通手順」のコードブロックを先に読み、それに従うこと。

## やること

（司令官が設計3 の判定で要ると決めたときに書き足す。書き足されていなければ実装を始めず、司令官に問い合わせる）
````

## 孫4用プロンプト:

````markdown
# 傘ブランチ: review-post-classifier（dotfiles）
# リポ: modeldex（メインワークツリー /home/manemone/projects/modeldex/main）
# 孫ブランチ: rpc-04-post-rules
# ターゲット: main（このリポの既定ブランチ。マージは人間）

計画書の「## 他リポの孫（孫3〜7）の共通手順」のコードブロックを先に読み、それに従うこと。

## やること

（司令官が設計3 の判定で要ると決めたときに書き足す。書き足されていなければ実装を始めず、司令官に問い合わせる）
````

## 孫5用プロンプト:

````markdown
# 傘ブランチ: review-post-classifier（dotfiles）
# リポ: iosci（メインワークツリー /home/manemone/projects/iosci/main）
# 孫ブランチ: rpc-05-post-rules
# ターゲット: main（このリポの既定ブランチ。マージは人間）

計画書の「## 他リポの孫（孫3〜7）の共通手順」のコードブロックを先に読み、それに従うこと。

## やること

（司令官が設計3 の判定で要ると決めたときに書き足す。書き足されていなければ実装を始めず、司令官に問い合わせる）
````

## 孫6用プロンプト:

````markdown
# 傘ブランチ: review-post-classifier（dotfiles）
# リポ: lora-dataset-forge（メインワークツリー /home/manemone/projects/lora-dataset-forge/main）
# 孫ブランチ: rpc-06-post-rules
# ターゲット: main（このリポの既定ブランチ。マージは人間）

計画書の「## 他リポの孫（孫3〜7）の共通手順」のコードブロックを先に読み、それに従うこと。
このリポは `.claude/pr-review.yml` を持たない。規約の在処は `AGENTS.md` から辿ること。

## やること

（司令官が設計3 の判定で要ると決めたときに書き足す。書き足されていなければ実装を始めず、司令官に問い合わせる）
````

## 孫7用プロンプト:

````markdown
# 傘ブランチ: review-post-classifier（dotfiles）
# リポ: sheaf（メインワークツリー /home/manemone/projects/sheaf/main）
# 孫ブランチ: rpc-07-post-rules
# ターゲット: main（このリポの既定ブランチ。マージは人間）

計画書の「## 他リポの孫（孫3〜7）の共通手順」のコードブロックを先に読み、それに従うこと。

## やること

（司令官が設計3 の判定で要ると決めたときに書き足す。書き足されていなければ実装を始めず、司令官に問い合わせる）
````
