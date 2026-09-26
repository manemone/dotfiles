---
name: pr-group-review
description: "他人の PR 群（複数リポにまたがるものを含む。1 本だけでもよい）をレビュワーとしてレビューする。対象 PR を複数の情報源から列挙し、人間の作業ツリーに触れずに読み取り専用で取得し、PR 群の地図を検証または作成し、リポ間の継ぎ目を含めてレビューし、まとめの HTML を作り、人間の確認を経て COMMENT として投稿する。追いレビューも同じスキルを人間が再起動して行う。修正コードは書かない。AI 不問（Claude Code / Codex / OpenCode）。自動発動はしない。/pr-group-review で明示的に起動。"
---

# pr-group-review — 他人の PR 群をレビュワーとしてレビューする

**AI 不問。** このスキルを読んでいる AI（以下「レビュワーAI」）が、人間（レビュワー本人）の
代わりにレビューの作業をする。YAML frontmatter を除き自然言語のみで完結する。実行可能な
スクリプトは同梱しない（手順中のコマンドは例であり、そのまま使っても書き換えてもよい）。

決定の経緯と却下案は ADR DOC-2609270420 を参照。

## 0. 線引き（最重要・明示的に禁止する）

**レビュワーはレビューだけをする。** 相手は他人であり、PR は相手のものである。
このスキルを実行している間、レビュワーAIは次を**行わない**。

- 他人の PR に対して**修正のコードを書かない**（手元の worktree で直してみせることも含む）
- 他人の PR のブランチへ **push しない**。修正コミットを作って「push してよいか」と尋ねることもしない
- 他人の PR の**本文・タイトル・ラベル・レビュワー設定を書き換えない**
- **`APPROVE` / `REQUEST_CHANGES` を投稿しない。** 投稿するのは `COMMENT` だけ。承認と変更要求は
  人間が判断する
- 人間の明示的な了承なしに**外部へ書き込まない**（GitHub への投稿も含む。§6）
- **チャット（Slack 等）へ投稿しない。** まとめの HTML は人間が添付する（§5）

指摘も「マージ前の前提」も、すべてレビューコメントで返す。「こう直せばよい」はコードではなく
提案の文章として書く（短いコード片を提案の中に引用するのは構わない）。

実際にあった失敗: AI が他人の PR に修正コミットを作り、push してよいか尋ねた。人間の返答は
「修正じゃなくてレビューをしてほしいんだが。これは僕のPRじゃないので。」だった。

**自分の PR 群のレビューを他人に頼む準備**はこのスキルの担当ではない（`pr-group-request` を使う）。
自分の PR に来た指摘へ対応するのは `pr-review-loop` の担当。

## 呼び出し

```
/pr-group-review [PR の URL / 一覧 / 作者の地図 / テーマ名 など]
```

- 引数は自由形式。PR の URL の列挙、作者が書いた PR 群のまとめ、チャットのスレッドの要約などを受け取る
- 既存の状態ディレクトリのテーマ名が与えられたら、追いレビュー（§8）として扱う
- 何も与えられなかったら、人間に対象（PR 群の手がかり）を尋ねる

## 参照文書

`references/` 配下を手順の中で読む。依頼者用スキル `pr-group-request` も同じファイルを使う。

| ファイル | 中身 |
|---|---|
| `references/state-format.md` | 状態ディレクトリの置き場所・構成、`state.json` と下書きの形式 |
| `references/group-map.md` | PR 群の地図の項目定義、作り方・検証のしかた、Markdown テンプレート |
| `references/seam-checklist.md` | リポ間の継ぎ目チェックリスト（冒頭の注意を必ず読む） |
| `references/summary-template.html` | まとめの HTML の雛形（自己完結、外部依存なし） |

## 1. 受付

### 1.1 新規か追いレビューかを決める

状態ディレクトリのベースは `${PR_GROUP_REVIEW_DIR:-$HOME/work/reviews}`
（`references/state-format.md` §1）。

```sh
ls "${PR_GROUP_REVIEW_DIR:-$HOME/work/reviews}"
```

- 人間が指したテーマ、または与えられた PR を含む `state.json`（`role` が `reviewer`）があれば
  追いレビュー → §8 へ
- 無ければ新規。以下を続ける

### 1.2 対象 PR を複数の情報源から列挙して突き合わせる

**1 つの情報源だけで列挙しない。** 実際に、チャットに共有されたリストに 15 本しか無く、ADR の
PR 3 本が作者の自作文書にだけ載っていたことがある。次のうち手に入るものを全部当たる。

- 人間が示したリスト（URL の列挙、チャットの内容）
- 作者の地図（PR 群のまとめ文書）があればその中の PR
- 各 PR の本文に書かれた関連 PR のリンク
- 同じブランチ名・同じ issue / チケット番号で検索して見つかる PR

  ```sh
  gh search prs --owner <org> --state open "<ブランチ名やチケット番号>"
  gh search prs --owner <org> --state open --author <作者> --created ">=<日付>"
  ```

- 積んでいる PR の base（base が default branch 以外なら、その base を head に持つ PR が対象に入る）

情報源ごとに見つかった PR を記録し（`state.json` の `sources`）、**どれかにだけある PR を人間に
示して**、対象の一覧を確認してもらう。人間が確定させるまで取得に進まない。

### 1.3 状態ディレクトリを作る

テーマ名を人間に確認して決め、`$PR_GROUP_REVIEW_DIR/<今日の YYYY-MM-DD>-<テーマ>/` を作って
`git init` する。`state.json` を `role: "reviewer"`・`format_version: 1` で作り、`sources` と `prs`
（この時点では `heads` は空）を書く。形式は `references/state-format.md` §3。

## 2. 取得（読み取り専用。人間の作業ツリーに一切触れない）

### 2.1 clone の場所

読み取り用の clone は「リポ名の下にメインブランチのディレクトリ」の形にする
（例: `~/work/<repo>/main`、`~/work/<repo>/master`）。

```sh
default=$(gh repo view <owner>/<repo> --json defaultBranchRef --jq .defaultBranchRef.name)
clone="$HOME/work/<repo>/$default"
test -d "$clone/.git" || git clone "https://github.com/<owner>/<repo>.git" "$clone"
```

- その場所に既に clone があれば、それを使う（**checkout・reset・stash・pull をしない**。
  作業ブランチが dirty のまま checkout されていても触らない）
- 別の場所にフラットな clone があっても、そちらは使わない（人間の作業場所の可能性がある）。
  上の形の場所に無ければ新しく clone する

### 2.2 PR の head を取って detached worktree に展開する

```sh
git -C "$clone" fetch origin "+pull/<N>/head:refs/review/pr-<N>"
git -C "$clone" fetch origin "<base ブランチ>"
wt="<一時的な場所>/<repo>-<N>"   # scratchpad など。状態ディレクトリには置かない
git -C "$clone" worktree add --detach "$wt" "refs/review/pr-<N>"
```

- `fetch` は作業ツリーを書き換えない。`worktree add --detach` は新しい場所に展開するだけで、
  clone 側で checkout されているブランチには触れない
- 展開先は一時的な場所（AI の scratchpad など）にする。**状態ディレクトリにも、人間の作業ツリーの
  中にも置かない**
- レビューが終わったら `git -C "$clone" worktree remove "$wt"` で片付ける（`refs/review/pr-<N>` は
  追いレビューの起点になるので残す）

### 2.3 head SHA を記録する

```sh
gh pr view <N> -R <owner>/<repo> --json headRefOid,baseRefName,baseRefOid,state,title,author
```

`state.json` の `prs[].heads` に `{ "round": <n>, "sha": <headRefOid>, "base_sha": <baseRefOid> }` を
足す。展開した worktree の `HEAD` と一致することを確かめる（一致しなければ取り直す）。
この SHA は、追いレビューの差分の起点（§8）と投稿直前の確認（§6.4）に使う。

## 3. 地図の検証または作成

`references/group-map.md` を読んで従う。

- 作者が地図を出していれば、それを**検証**する（同文書 §3）。食い違いは `map.discrepancies` に残し、
  指摘にする。`map.source` は `author`
- 無ければ**作成**する（同文書 §2）。`map.source` は `reviewer`
- 単体 PR（1 本だけの PR 群）では、地図を「1 本だけの表」に縮退させてよい（同文書 §1 末尾）

地図は `state.json` の `map` に書く。

## 4. レビュー

### 4.1 観点

次の 3 つを行う。

1. **グループ別のレビュー**: 地図のグループごとに PR を読む。まず本文を読んで変更全体に意味が
   あるかを見て、主要なファイルから読む（Google eng-practices「Navigating a CL in review」）。
   stack は main に近い側から順に、各 PR を単独の変更として見る。スタックの文脈が無いと意味が
   通らないなら、それ自体を分け方の指摘にする（Graphite の stacked PR のレビュー作法）
2. **継ぎ目のレビュー**: `references/seam-checklist.md` の全項目。**冒頭の注意（事故の種は照合より
   順序と手作業の側にあった）を読み、順序と手作業に時間を割く**
3. **反証**: 出た指摘を 1 件ずつ、本当に問題か・重複していないかを疑って確かめる。結果を
   `verdict`（`confirmed` / `plausible` / `refuted` / `duplicate`）に入れる。実測では 62 件中
   refuted 3・duplicate 12 だった。反証を飛ばすと、誤った指摘や重複を他人の PR に出すことになる

テスト不足の指摘は、投稿先のリポのテスト方針（AGENTS.md など）があればそれに照らす。

コードを動かして確かめたいとき（テストの実行など）は、展開した worktree の中だけで行う。
**ローカルの共有リソース（テスト用 DB、共有のコンテナなど）を使う操作は、実行前に人間に確認する**
（権限の仕組みに止められた場合も同じ。§6.5）。

### 4.2 指摘の記録

各指摘を `state.json` の `findings` に書く（形式は `references/state-format.md` §3.6）。
特に次を必ず埋める。

- `severity`（`blocker` / `major` / `minor` / `nit`）と、それとは独立の `blocking`（マージ前に対応が必要か）
- `category`（`structure` / `order` / `manual` / `seam` / `code` / `test` / `docs`）。投稿の段分けに使う
- インラインで付けるなら `path` / `line` / `side`。付けられない（リポ間・順序の）指摘は本文だけに書く

### 4.3 並列化の目安

PR が数本なら、1 つのセッションで順に読めば足りる。規模が大きい場合は、AI の並列化の仕組み
（サブエージェント、workflow など）で分担してよい。**分担の単位は「グループ別 + 継ぎ目担当 1 +
反証役 1」** を基本にする。

実測（9 リポ 18 本の PR 群）: グループ別 7 + 継ぎ目 1 + 反証 1 = 9 体で、トークン約 130 万・
所要約 22 分。投稿用の文面づくりは 7 体で約 57 万トークン・約 3 分。

トークンの消費が大きいので、**並列化する前に人間へ規模の見込み（体数・おおよそのトークン）を示して
了承を得る。** 継ぎ目担当には全 worktree のパスと地図を渡す（グループ別の担当は自分のグループしか
見ないため、継ぎ目は専任を置かないと誰も見ない）。

## 5. まとめの HTML

`references/summary-template.html` を状態ディレクトリへ `summary.html` としてコピーし、`state.json`
の内容で埋める。雛形の先頭コメントの使い方に従う。

- **自己完結した 1 ファイルにする。** 外部の CSS / JS / フォント / 画像を読み込まない。
  Claude の artifact など特定の製品に載せない
- 雛形のダミー行を残さない
- blocking の指摘は先頭の枠に全部並べる
- 生成したらブラウザで開けることを確かめ、パスを人間に伝える。**共有（チャットへの添付）は人間が
  行う。** AI はチャットへ投稿しない
- Notion へのアップロードは、**人間が求めたときだけ**行う（任意の追加手段）

## 6. 投稿（下書き → 人間の確認 → 投稿）

### 6.1 書式を投稿先のルールから決める

コメントの書式（接頭辞・分類タグ・文体など）は、**投稿先のリポのルールを読んで従う。** 各 PR の
リポで次を読む（展開した worktree の中、または `gh api` で取得）。

- `AGENTS.md` / `CLAUDE.md` などの AI 向け指示
- `docs/` 配下のレビュー規約、`CONTRIBUTING.md`、`.github/` 配下の規約
- 組織共通の規約が参照されていれば、それも

たとえば、ある組織では組織内の文書と各リポの AGENTS.md が次を必須にしている（**特定組織の規則の
例であり、このスキルの既定ではない**）。

- 先頭に `🔍【AIレビュー | <AI名> | <版> | effort:<level>】` を付ける
- 指摘には続けて `⚙️【技術指摘】` か `❓【仕様確認】` の**どちらか 1 つ**を付ける
- ですます調で書く
- サマリには分類タグを付けず、未回答の仕様確認をサマリの先頭に並べる

リポごとにルールが違うことがある。PR ごとにそのリポのルールを当てる。

### 6.2 blocking の表示

- ラベル・タグは投稿先のルールに従い、**それを崩さない**（例: タグを 1 つしか付けられないルール
  なら、blocking を示すためにタグを足さない）
- blocking であることは、**コメント本文の定型文**（例:「マージ前に対応が必要です」）と、
  **レビューサマリの先頭での列挙**で示す
- 投稿先にルールが無いリポでは、Conventional Comments のラベル（`issue` / `question` /
  `suggestion` / `nitpick`）と `(blocking)` / `(non-blocking)` の修飾を使う

### 6.3 下書きを作る（2 段の投稿が既定）

`references/state-format.md` §4 の形式で `drafts/r<ラウンド>-s<段>.json` を作る。下書きに入れるのは
`verdict` が `confirmed` / `plausible` の指摘だけ。

- **1 段目**: 構造・順序・手作業・継ぎ目の指摘と、blocking の指摘。設計と順序の手戻りは大きいので
  先に返す
- **2 段目**: 残りの細かい指摘。1 段目への相手の返信を待ってから出す（相手が構造を変えれば、
  細かい指摘の前提が崩れることがある）
- リポ間の指摘は、主な対象 PR のサマリに書き、関係する他の PR のサマリからは参照だけする
  （同じ文面を全 PR に貼らない）

下書きの内容（段ごとに、PR ごとのサマリとインラインコメント）を人間に見せ、次を確認する。

- この内容で投稿してよいか（**明示的な了承が得られるまで投稿しない**）
- 2 段に分けるか、一度に出すか（人間が「一度に出す」を選んだら `rounds[].posting` を `single` にして
  全部を 1 段目に入れる）

### 6.4 投稿直前の確認

PR ごとに、投稿の直前に次を確かめる。

1. **head が動いていないか。** `gh pr view <N> -R <owner>/<repo> --json headRefOid` の値が、
   `state.json` に記録した最新の `sha` と一致するか。**動いていたらその PR には投稿せず**、
   `rounds[].skipped` に記録して人間に報告する（行番号がずれているため、取り直して読み直す必要がある）
2. **インラインコメントの行が diff の hunk 内にあるか。** GitHub は PR の差分（base と head の
   merge-base からの差分）の hunk の外の行へのコメントを受け付けない。

   ```sh
   git -C "$clone" diff "$(git -C "$clone" merge-base <base_sha> <head_sha>)" <head_sha> -- <path>
   ```

   の各 `@@ -a,b +c,d @@` について、`side: RIGHT` なら `c` 〜 `c+d-1`、`side: LEFT` なら
   `a` 〜 `a+b-1` の範囲に行が入っているかを確かめる。外れていたら、その指摘を本文だけの指摘
   （`body_only_finding_ids`）へ移す

### 6.5 投稿する（COMMENT のみ）

```sh
gh api -X POST "repos/<owner>/<repo>/pulls/<N>/reviews" --input payload.json
```

`payload.json` は `{ "commit_id": "<head_sha>", "event": "COMMENT", "body": "…", "comments": [ { "path": "…", "line": 42, "side": "RIGHT", "body": "…" } ] }`。
**`event` は必ず `COMMENT`。** `APPROVE` / `REQUEST_CHANGES` は使わない。

投稿できたらレビューの ID と URL を `rounds[].posted` に、インラインコメントの ID を各指摘の
`thread` に記録する。

**権限の仕組み（auto mode の分類器など）に投稿を止められたら**:

- **スクリプトやコマンドを人間に渡して「自分で実行してください」とはしない。** 実際にそうした
  ときの人間の返答は「なんでや！やってくれ！」だった。人間が求めているのは投稿という作業を AI が
  やることで、権限の仕組みが止めたのは「人間の了承なしに外部へ書き込むこと」である
- 止められたことと理由を人間に伝え、許可（auto mode を抜ける、該当の操作を許可する等）を得たうえで、
  **AI 自身が投稿する**
- ローカルの共有リソースを使う操作（§4.1）を止められた場合も同様に、人間の判断を仰ぐ

## 7. ラウンドを閉じる

1. `state.json` を更新する（`rounds` に今回の記録、各指摘の `status` と `thread`）
2. `summary.html` を最新の状態で作り直す
3. 状態ディレクトリで `git add -A && git commit -m "round <n>: stage <k> posted"` のようにコミットする
4. 展開した worktree を片付ける（§2.2。`refs/review/pr-<N>` は残す）
5. 人間に次を伝えて終わる:
   - 投稿したレビューの URL と、見送った PR とその理由
   - `summary.html` のパス（チャットへの添付は人間が行う）
   - 「相手の返信を待ち、次のラウンド（2 段目の投稿、または追いレビュー）は `/pr-group-review` を
     再起動してください」

**定期的に確認しに行かない。** 次のラウンドは人間が起動する。

## 8. 追いレビュー（再起動時）

1. 状態ディレクトリの `state.json` を読み、前回のラウンドと未投稿の段（2 段目が残っていないか）を
   確かめる
2. 各 PR の現在の状態を取る（`gh pr view --json headRefOid,baseRefOid,state`）。マージ・クローズ
   されたものは `prs[].state` を更新し、以降の対象から外す
3. head が前回の `sha` から動いた PR について、差分を取る
   - まず前回の head を別の ref に退避してから取り直す（force-push されると前回の head がどの
     ブランチからも辿れなくなるため）

     ```sh
     git -C "$clone" update-ref "refs/review/pr-<N>-r<前回>" "refs/review/pr-<N>"
     git -C "$clone" fetch origin "+pull/<N>/head:refs/review/pr-<N>"
     ```

   - 前回の head が新しい head の祖先なら、`git diff <前回の sha> <新しい sha>` で差分を読む
   - 祖先でない（force-push / rebase された）なら、GitHub の「前回のレビュー以降の変更」は当てに
     ならない。`git range-diff` で取り直す

     ```sh
     git -C "$clone" range-diff <前回の base_sha>..<前回の sha> <新しい base_sha>..<新しい sha>
     ```

4. 相手の返信を読む（レビューのスレッド、PR のコメント）

   ```sh
   gh api "repos/<owner>/<repo>/pulls/<N>/comments" --paginate
   gh api "repos/<owner>/<repo>/issues/<N>/comments" --paginate
   ```

5. 前回までの指摘ごとに「解決 / 未解決」を判定し、今回の差分から「新規」の指摘を拾う
   （§4 の観点。地図が変わっていれば地図も検証し直す）。`status` を `resolved` / `open` / `new` に
   し、`history` に根拠を残す
6. §2.3 のとおり新しい head SHA を記録し、§5〜§7 を同じように行う（投稿の前には人間の確認を取る）

## 9. 単体 PR のとき

PR が 1 本だけでも、このスキルで同じフローを回す（別のスキルは使わない）。規模に応じて縮退させる。

- 列挙（§1.2）: 本文のリンクと関連 PR の検索だけ当たり、関連が無ければ 1 本で確定する
- 地図（§3）: 「1 本だけの表」（順序・手作業・ロールバック）
- 継ぎ目（§4.1）: `references/seam-checklist.md` の順序・手作業・ロールバックと、PR 群に入っていない
  利用者の項目を中心に見る
- 並列化（§4.3）: 通常は不要
- 投稿（§6）: 1 段目と 2 段目の区別はそのまま使う。指摘が少なければ人間に一度に出すかを尋ねる
