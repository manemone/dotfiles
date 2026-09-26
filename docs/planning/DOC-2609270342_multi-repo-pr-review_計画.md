# 計画書: 複数リポにまたがる PR 群のレビュー作法（レビュワー用・依頼者用スキル）

傘ブランチ: `multi-repo-pr-review`
ターゲット: `master`

## 概要

他人が出した PR 群（複数リポにまたがる）を AI にまとめてレビューさせた際、
dotfiles に「**レビュワーとして**他人の PR をレビューする」スキルも、
「自分の PR 群のレビューを**他人に頼む**」スキルも存在しないことが分かった。
既存の `pr-review-loop` はレビュイー（自分の PR を直す側）から起動するスキルであり、
相手が他人のときには使えない。

そこで次の 2 つのスキルを `skills/` に追加する。

- **`pr-group-review`（レビュワー用）**: 他人の PR 群を受け付け、読み取り専用で取得し、
  「PR 群の地図」を検証（または作成）し、レビューし、まとめの HTML を作り、
  人間の確認を経て COMMENT として投稿する。追いレビューは人間が手動で起動する
- **`pr-group-request`（依頼者用）**: 自分の PR 群（傘ブランチの計画書からでも作れる）について
  地図を作り、継ぎ目を自分でチェックし、各 PR の本文と依頼文を用意する

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。転記後に削除済みで
> 参照できない前提で書く）を material として司令官が起草したものである。** ブリーフに
> 書かれていた問題意識・決定事項・実測値・制約・未決定事項は本計画書へ転記済みであり、
> 以降はこの計画書が正典である。ブリーフが未決定として残していた 4 点は、司令官が人間へ
> 確認して確定させた（「背景5」参照）。
>
> **このリポジトリは公開リポジトリである。** ブリーフに含まれていた同僚の実名、社内 Slack
> スレッドの URL、社内リポジトリ名や PR へのリンク、相談中の発言の逐語全文は、実装に
> 必要な情報ではないため載せず、経緯は要約で残した（背景1）。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `mrpr-01-adr` | ADR。2 スキルの線引き・状態の置き場所・まとめ文書の形式・外部書き込みの扱い・blocking の表示・単体 PR の扱い | ✅ PR #113 マージ済 |
| 2 | `mrpr-02-reviewer-skill` | レビュワー用スキル `pr-group-review`（共通の参照文書: 地図テンプレート・継ぎ目チェックリスト・状態ファイル形式を含む） | ✅ PR #114 マージ済 |
| 3 | `mrpr-03-requester-skill` | 依頼者用スキル `pr-group-request` と、`skills/README.md`・`pr-review-loop`・`umbrella-orchestrator` からの相互参照 | 🔄 実装中 |

依存: 孫1 → 孫2 → 孫3 の順に直列で進める（孫2 は孫1 の ADR に従い、孫3 は孫2 の参照文書を再利用する）。

## ワークスペースラベル

- 傘: `dotfiles :: 複数リポPRレビュー作法`
- 孫1: `dotfiles :: 複数リポPRレビュー 孫1 ADR`
- 孫2: `dotfiles :: 複数リポPRレビュー 孫2 レビュワー用`
- 孫3: `dotfiles :: 複数リポPRレビュー 孫3 依頼者用`

---

## 背景1: 経緯と問題意識

発端は、同僚（PR 群の作者。以下「作者」）が出した、複数リポにまたがる PR 群（9 リポ 18 本）を、
人間が AI にまとめてレビューさせたこと。作者自身も「個々の PR より PR 群の構造のレビューを
受けたい」という趣旨で、PR 群の構造をまとめた文書を自作していた。

レビューの途中で、次の 2 つの失敗が起きた。どちらも本傘の決定の直接の根拠である。

- AI が他人の PR に修正コミットを作り、push してよいか尋ねた。人間の返答:
  「修正じゃなくてレビューをしてほしいんだが。これは僕のPRじゃないので。」
  → レビュワーはレビューだけをする（背景2）
- AI が GitHub への投稿を権限の仕組みに止められ、投稿スクリプトを人間に渡して「自分で
  実行してください」とした。人間の返答:「なんでや！やってくれ！」
  → 権限に止められたら許可を得て AI 自身が投稿する（設計1.6）

これを受けて人間は、他人の PR（特に複数リポにまたがるもの）を**純粋にレビュワーとして**
扱う作法が dotfiles に無いこと、また逆に自分が複数リポの PR 群のレビューを**他人に頼む**
場面もありうることに気づき、両方を補助するスキルを傘で作ることにした。相手（背後に AI が
いる他人）の返信を待って追いレビューを返す流れは `pr-review-loop` と同じだが、起動する側が
レビュイーではなくレビュワーである点が違う。

## 背景2: 人間が確定させた決定事項（覆さないこと）

- **スキルは 2 つにする。** (A) 他人の PR 群をレビューする「レビュワー用」と、
  (B) 自分の PR 群のレビューを他人に頼む「依頼者用」。どちらも複数リポにまたがる PR 群を
  主な対象にする（単体 PR の扱いは背景5.2 で確定）
- **レビュワーはレビューだけをする。** 他人の PR に対して、修正のコードを書かない、
  push しない、PR の本文を書き換えない。指摘も「マージ前の前提」も、すべてレビューコメントで返す
- **追いレビューは手動で起動する。** 相手（背後に AI がいる他人）からの返信を待ち、
  人間が起動したら次のラウンドのレビューを返す。定期的に確認する仕組みは入れない
- **`pr-review-loop` とは別物にする。** `pr-review-loop` はレビュイー側から起動するスキルだが、
  今回欲しいのは純粋にレビュワーとして振る舞うスキル
- **まとめ文書は Claude の artifact にしない（脆いため）。** 自己完結した HTML ファイルで作る。
  必要なら Notion に上げてもよい
- **レビュー状態は、どれか 1 つのリポには置かない。** 複数リポにまたがるので、別の場所に
  置き場を設ける。ここでいう「状態」は、コードを読むための worktree ではなく、
  **レビューという仕事の記録**のこと（人間が「そういう意味の状態だよね？」と確認し、
  AI がそのとおりだと答えた）
- **ワークツリーの配置規則。** 読み取り用の clone は「リポ名の下にメインブランチの
  ディレクトリ」（例: `~/work/<repo>/master`、`~/work/<repo>/main`）の形にする。
  ワークツリーを使うため
- 外部のベストプラクティスは「参考までに」調べたもの（背景4.2）

## 背景3: 既存の穴

- `skills/pr-review-loop/SKILL.md` の description:
  「PRレビューサイクルを自動化。Herdrワークスペースのreviewerペインと連携して
  レビュー→修正→返信→再レビューを承認まで繰り返す。」
  レビュイー側（自分の PR を直す側）の自動化であり、相手が他人のときに Herdr のペインを
  通して待つことはできない。**レビュワーとして他人の PR にコメントし、返信を待って
  追いレビューする工程を担当するスキルが無い**
- 複数リポにまたがる PR 群について、「PR 群の地図」（グループ、依存、積んでいる PR、
  マージと適用の順序、手作業の工程、未決の ADR、リポ間の照合表、ロールバック）を
  **作る、または検証する手順がどのスキルにも無い**。今回は作者が自分で artifact を作り、
  レビュワー側の AI もその場の判断で同じ形のまとめを作った
- 自分の PR 群のレビューを人に頼むとき、その地図と依頼文を用意する手順が無い
- 傘ブランチの計画書（`umbrella-orchestrator`）には孫の PR の並びがあるが、
  それをレビュー依頼用の地図に変える手順が無い
- （司令官が裏取り）`skills/deploy.sh` は `skills/` 直下の**ディレクトリをすべて**自動検出して
  配る（`SKILL.md` の有無を見ない）。したがって**スキルのディレクトリは、それを作る PR の中で
  完結させる**こと。半端なディレクトリだけを先にマージすると、その状態で全エージェントへ配られる

## 背景4: 実測値（2026-09-26〜27、上記 PR 群のレビューで測ったもの）

### 4.1 レビューの実測

- 対象: 9 リポ 18 本（リポごとの内訳は 2 / 3 / 1 / 1 / 3 / 1 / 5 / 2。うち 1 リポは
  ADR の PR 3 本を含む）。**Slack のリストには 15 本しか無く、ADR の 3 本は作者の artifact に
  だけ載っていた。レビュー対象の列挙は、1 つの情報源からだけでは漏れる**
- 手元のリポの状態はばらばらだった。「リポ名/メインブランチ」の形のものと、フラットな clone で
  別の作業ブランチが dirty のまま checkout されているものが混在していた。各 PR の head を
  `git fetch origin pull/N/head:refs/review/pr-N` で取り、scratchpad に **detached worktree** として
  展開して、**作業ツリーには触れずに**読んだ
- レビューの workflow: グループ別 7 体 + リポ間の継ぎ目担当 1 体 + 反証役 1 体 = 9 体。
  サブエージェントのトークン約 130 万、所要約 22 分
- 指摘 62 件を反証した結果: confirmed 41 / plausible 6 / refuted 3 / duplicate 12。
  ブロッカー 0、重大 8。**重大 8 件のうち 6 件は、コードではなく「順序と手作業」**
  （DB スキーマ管理ツールの適用順、submodule が古い系統を指す、コンテナデプロイツールの
  サービス作成の前提、ブランチから apply 済みのインフラ）だった。**リポ間の照合
  （ペイロード↔スキーマ↔受信、OAS↔実装、バケット名↔ENV、outbox の列↔relay）は全部一致して
  いて、事故の種は順序の側にあった**
- 投稿用の文面の workflow: 7 体、トークン約 57 万、約 3 分。17 本の PR に、COMMENT のレビュー
  17 件とインラインコメント 47 件。**インラインコメントの行が diff の hunk 内にあるかを投稿前に
  スクリプトで検証し、全件が通った。レビューの後で head が動いていないかも、投稿の直前に確認した**
- auto mode の分類器に 2 回止められた。①ローカルのテスト DB を使ったテストの実行（共有リソースの
  変更とみなされた）、②GitHub への投稿（外部システムへの書き込み）。②は人間が「やってくれ」と
  言ったあと、auto mode を抜けた状態で実行できた。**外部へ書き込む工程は、人間が確認する
  ステップと、権限の扱いをスキルに書いておく必要がある**
- 今回の成果物（参照用。**セッション固有の場所にあり、消えている可能性がある**。孫2 は
  存在すれば読んでよいが、無くても作業できるように本計画書に要点を落としてある。
  社内の PR 内容を含むため、**中身をこのリポジトリへコピーしないこと**）:
  - レビューの workflow スクリプト:
    `~/.claude/projects/-Users-kazuki-hamada-work/551af5b1-c89e-44dc-9f68-8c93b9ea1894/workflows/scripts/tanoken-registration-pr-review-wf_b5725982-a76.js`
  - 文面の workflow スクリプト: 同じディレクトリの `tanoken-review-comment-drafts-wf_e11cb6c7-ab0.js`
  - 状態ファイル、HTML の生成スクリプト、投稿スクリプト:
    `/private/tmp/claude-501/-Users-kazuki-hamada-work/551af5b1-c89e-44dc-9f68-8c93b9ea1894/scratchpad/`
    （`review.json`、`drafts.json`、`gen.py`、`tpl.html`、`post_reviews.py`、`pr-prereq-drafts.md`）

### 4.2 外部のベストプラクティス（2026-09-27 に調べたもの。参考）

- Google eng-practices「Navigating a CL in review」: ①まず説明を読み、変更全体に意味があるかを
  見る → ②主要なファイルを先に見て、設計の指摘は**すぐに返す**（設計の手戻りは大きいため）→
  ③残りを順に見る。https://google.github.io/eng-practices/review/reviewer/navigate.html
  - 相談AIの提案: 1 ラウンド目は構造・順序・blocking の指摘だけを先に返し、細かい指摘は後から
    返す、という 2 段の投稿。今回は全部を一度に出した（司令官の扱いは設計1.6）
- Graphite「Best Practices For Reviewing Stacked PRs」: 各 PR を単独の変更として見る。スタックの
  文脈が無いと意味が通らないなら、分け方を変えてもらう。main に近い側から順に見る。上の PR での
  変更も確認する。https://graphite.com/docs/best-practices-for-reviewing-stacks
- GitHub の Stacked PRs（2026-07-30 にパブリックプレビュー）: 各 PR は自分の層の差分だけを見せる。
  `gh stack rebase` で上の PR へ変更が伝わる。ドキュメントには複数リポについての記述が無い。
  https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/reviewing-stacked-pull-requests /
  https://github.blog/changelog/2026-07-30-stacked-pull-requests-are-now-in-public-preview/
- Conventional Comments: `issue` / `question` / `suggestion` などのラベルと、`(blocking)` /
  `(non-blocking)` の修飾。https://conventionalcomments.org/
- Qodo の cross-repo code review: 依存関係を Code / Service / Data / Pipeline / Docs に分類し、
  影響を**両方向**に追う（変更に依存するコードと、PR の中で他のリポとぶつかるコード）。
  https://docs.qodo.ai/governance/cross-repo-code-review
  - 相談AIの提案: 今回の継ぎ目チェックは「PR 群の中どうし」しか見ていない。
    **「PR 群に入っていない利用者」を見る項目を足す**（設計1.5 に取り込み済み）
- Interdiff の問題: rebase や force-push をされると、GitHub の「前回のレビュー以降の変更」が壊れる。
  `git range-diff` で取り直すのが定番。https://pyor.review/blog/re-reviewing-pull-requests-interdiff
- 450K ファイルのモノレポで AI レビューツールを比べた記事では、サービスをまたぐ破壊的変更を
  どのツールも見つけられなかった。
  https://www.augmentcode.com/tools/open-source-ai-code-review-tools-worth-trying

## 背景5: 司令官が人間に確認して確定させた決定事項（覆さないこと）

ブリーフが未決定として残していた 4 点について、司令官が 2026-09-27 に人間へ確認し、
以下のとおり確定した。

### 5.1 レビュー状態の置き場所: **環境変数で可変・既定は `~/work/reviews`**

- ベースディレクトリは環境変数で上書き可能にし、既定値を `~/work/reviews` にする
  （環境変数名は設計1.2 で司令官が確定）
- その下に `<YYYY-MM-DD>-<テーマ>/` を切る。どのリポにも属さないディレクトリで、
  そこで `git init` してラウンドの履歴を残す（ブリーフで相談AIが提案した形）

### 5.2 単体リポの PR: **同じスキルで扱う（「PR が 1 本だけの PR 群」として）**

地図や継ぎ目チェックは PR 群の規模に応じて縮退させ、同じフローで回す。スキルを増やさない。

### 5.3 まとめ HTML の置き場所と共有: **状態ディレクトリに置き、人間が Slack に添付する**

- HTML は 5.1 のレビュー状態ディレクトリ内に生成する
- 共有は人間が Slack に添付する（**AI は Slack へ投稿しない**）
- Notion へのアップロードは、人間が求めたときだけの任意の追加手段としてスキルに記載する

### 5.4 blocking の表示: **投稿先ルール優先＋本文で明記**

- ラベル・タグは**投稿先のリポのルールに従う**（例: タグを 1 つしか付けられないルールなら、
  それを崩さない）
- blocking であることは、**コメント本文の定型文**（例:「マージ前に対応が必要です」）と、
  **レビューサマリの先頭での列挙**で示す
- 投稿先にルールが無いリポでは、Conventional Comments の `(blocking)` / `(non-blocking)` を使う

---

## 設計1: 2 つのスキルの外形（司令官が確定。孫はこれに従う）

### 1.1 スキル名と線引き

| スキル | 役割 | 起動 | 外部への書き込み |
|---|---|---|---|
| `pr-group-review` | 他人の PR 群を**レビュワーとして**レビューする。追いレビューも同じスキルで行う | 手動（`/pr-group-review`。自動発動しない） | GitHub への **COMMENT レビュー投稿のみ**（人間の確認後） |
| `pr-group-request` | 自分の PR 群のレビューを他人に頼む準備をする | 手動（`/pr-group-request`。自動発動しない） | 自分の PR の本文の更新（人間の確認後）。Slack 用の依頼文は**下書きを渡すだけ**で、投稿は人間 |

- どちらも **AI 不問**（Claude Code / Codex / OpenCode。既存スキルと同じく、YAML frontmatter を
  除き自然言語で完結させる）。**実行可能なスクリプトはスキルに同梱しない。** 手順の中に
  コマンド例やコード断片を書くのは構わない
- `pr-group-review` がやらないこと（明示的に禁止としてスキルに書く）: 他人の PR への
  修正コミットの作成・push、PR 本文の書き換え、`APPROVE` / `REQUEST_CHANGES` の投稿
  （承認と変更要求は人間が判断する）
- 返ってきた指摘への対応（依頼者側）は、PR ごとに `pr-review-loop` で回す、と
  `pr-group-request` から接続を説明する。`pr-review-loop` 自体は改修しない

### 1.2 レビュー状態ディレクトリ（5.1 を具体化）

- 環境変数 `PR_GROUP_REVIEW_DIR`（既定 `$HOME/work/reviews`）
- レビュー 1 件（1 つの PR 群）につき `$PR_GROUP_REVIEW_DIR/<YYYY-MM-DD>-<テーマ>/`
  を作り、`git init` する。ラウンドごとにコミットする
- **レビュワー用・依頼者用の両方がこの置き場を使う**（依頼者用も地図・依頼文を置く）。
  どちらの用途かは状態ファイル内に記録する
- 中身（形式の詳細は孫2 が参照文書で定める）:
  - 状態ファイル（JSON）: 対象 PR の一覧（リポ・番号・URL・レビュー時の head SHA）、
    PR 群の地図、ラウンドごとの指摘（ID・重要度・blocking か・状態）、投稿済みレビューの ID
  - 投稿用の下書き（JSON または Markdown）
  - まとめの HTML
- **コードを読むための worktree はここに置かない**（背景2。worktree は設計1.3）

### 1.3 読み取り用の取得（背景4.1 の実測をそのまま手順化）

- clone は「リポ名の下にメインブランチのディレクトリ」の形（例: `~/work/<repo>/<default-branch>`）。
  無ければその形で clone する
- **人間の作業ツリーに一切触れない。** 各 PR の head を `git fetch origin pull/N/head:refs/review/pr-N`
  で取り、detached worktree として展開して読む。展開先は scratchpad など一時的な場所
- レビュー時点の head SHA を状態ファイルに記録する（追いレビューの差分の起点、投稿直前の確認に使う）

### 1.4 PR 群の地図

地図に載せる項目: グループ、PR 間の依存、積んでいる PR（stack）、マージと適用の順序、
手作業の工程、未決の ADR、リポ間の照合表、ロールバック。

- レビュワー用: 作者が地図を出していればそれを**検証**し、無ければ**作成**する
- 依頼者用: 地図を**作成**する。傘ブランチの計画書があれば、その孫の PR の並びから作れる
- **対象 PR の列挙は複数の情報源から行い、突き合わせる**（背景4.1: 1 つの情報源だけでは漏れた）
- 単体 PR（5.2）では地図を「1 本だけの表」に縮退させてよい

### 1.5 リポ間の継ぎ目チェックリスト

少なくとも次を含める。

- ペイロード ↔ スキーマ ↔ 受信側
- API 契約（OAS 等）↔ 実装
- インフラの名前 ↔ ENV ↔ アプリの設定
- DB の列 ↔ コード
- submodule や依存のバージョン（古い系統を指していないか）
- デプロイとマイグレーションの順序、手作業の前提
- ロールバック
- **PR 群に入っていない利用者**（変更に依存しているが PR 群の外にあるコード・サービス。背景4.2 Qodo）

背景4.1 の実測（重大指摘の大半は照合ではなく順序と手作業の側にあった）を、チェックリストの
冒頭の注意として書くこと。

### 1.6 投稿（外部への書き込み）の扱い

- 流れは **下書き → 人間の確認 → 投稿**。人間の明示的な了承なしに投稿しない
- 投稿するのは **COMMENT だけ**
- **2 段の投稿を既定にする**（背景4.2 Google eng-practices）: 1 段目で構造・順序・blocking の
  指摘を返し、細かい指摘は 2 段目で返す。人間が確認の時点で「一度に出す」を選んだらそれに従う
  （司令官の判断。人間はこの点を明言していないため、人間が選べる形にした）
- 投稿の直前に次を確認する: ①PR の head が状態ファイルに記録した SHA から動いていないか
  （動いていたら投稿せず人間に報告）、②インラインコメントの行が diff の hunk 内にあるか
- コメントの書式は**投稿先のリポのルールを読んで従う**（決定的な制約を参照）。blocking の表示は 5.4
- **権限の扱い**: 投稿が権限の仕組み（auto mode の分類器など）に止められたら、
  **スクリプトを人間に渡して「自分で実行してください」とはしない**（背景1: 人間は「なんでや！
  やってくれ！」と返した）。止められたことと理由を人間に伝え、許可（auto mode を抜ける等）を
  得たうえで AI 自身が投稿する。ローカルの共有リソース（テスト DB 等）を使う操作が止められた場合も
  同様に、人間の判断を仰ぐ

### 1.7 追いレビュー（手動起動）

- 人間が `/pr-group-review` を再び起動したら、状態ディレクトリから前回のラウンドを読み込む
- 前回の SHA から差分を取る。force-push / rebase されていたら `git range-diff` で取り直す
  （背景4.2 Interdiff）
- スレッドごとに「解決 / 未解決 / 新規」を判定し、状態ファイルに記録してコミットする
- 定期的な確認・自動の追いレビューは入れない（スコープ外）

### 1.8 共通の参照文書の置き場所

地図テンプレート（HTML の雛形を含む）・継ぎ目チェックリスト・状態ファイルの形式は、
**`skills/pr-group-review/` の中に置く**（例: `skills/pr-group-review/references/`）。
`pr-group-request` は同じものを再利用し、兄弟ディレクトリへの相対パス
（`../pr-group-review/references/...`）で参照する。スキルは全エージェントへスキル単位の
symlink で配られ、配布先でも兄弟として並ぶため、相対パスで届く。
**内容を 2 つのスキルに重複して持たない。**

---

## 決定的な制約（孫は全部守ること）

- レビューコメントの書式は、**投稿先のリポのルールに従う**。たとえば、ある投稿先の組織では
  組織内の文書と各リポの AGENTS.md が次を必須にしている。
  - 先頭に `🔍【AIレビュー | <AI名> | <版> | effort:<level>】` を付ける
  - 指摘には、続けて `⚙️【技術指摘】` か `❓【仕様確認】` の**どちらか 1 つ**を付ける
  - ですます調で書く
  - サマリには分類タグを付けず、未回答の仕様確認をサマリの先頭に並べる

  **dotfiles のスキルは会社のリポに限らない汎用のものなので、この書式を直接書き込まず、
  「投稿先のルール（AGENTS.md や docs 配下のレビュー規約）を読んで従う」形にすること。**
  上の書式はスキルに例として載せる場合も、特定組織の規則だと分かる書き方にし、組織名・
  リポ名は書かない
- 承認（APPROVE）と変更要求（REQUEST_CHANGES）は人間が判断する。AI が投稿するのは COMMENT だけ
- **このリポジトリは公開リポジトリである。** スキル・ADR・README に、社内の組織名・リポ名・
  同僚の名前・社内 URL・レビューした PR の中身を書かない
- dotfiles の AGENTS.md のルール（DOC-ID の採番、ADR、pre-commit、linter 抑制の禁止）に従う
- スキルのディレクトリは、それを作る PR の中で完結させる（背景3 最終項）
- 指示された範囲外の機能を先回りして実装しない

## スコープ外

- `pr-review-loop`（レビュイー側）そのものの改修。ただし、依頼者用スキルが「返ってきた指摘への
  対応は、PR ごとに `pr-review-loop` で回す」とつなぐ説明、および `pr-review-loop` の
  SKILL.md に「相手が他人の PR をレビューするなら `pr-group-review` を使う」旨の相互参照を
  1〜2 行足すことはスコープ内
- 今回の PR 群の追いレビュー（人間が別途、そのセッションの成果物を使って行う）
- 定期的に確認して自動で追いレビューする仕組み（手動起動に決まった）
- Slack への自動投稿（5.3）
- スキルへの実行可能スクリプトの同梱（設計1.1）

## 必須の検証ステップ（AGENTS.md「コミット前の必須ステップ」より。省略しない）

- 初回のみ: `uv tool install pre-commit` と `pre-commit install`
- 新規ファイルを足したら、その時点で `pre-commit run --files <path>` を実行する
- コミットのたびに `.pre-commit-config.yaml` のフックが走る（`trailing-whitespace` などの基本
  チェック、`shellcheck` / `shfmt`、`./tools/doc-id/doc-id check` / `verify`、シェルスクリプトを
  変えたときの `./deploy-all.sh --dry-run`、`bin/` を変えたときの `bin/tests/lint.sh` など）。
  まとめて確かめるときは `pre-commit run --all-files`
- スキルの追加は `skills/deploy.sh` のデプロイ対象になるので、`./deploy-all.sh --dry-run` で
  新しいスキルが全エージェント分配布されることを確認する
- `tests/deploy_smoke.sh`（サンドボックス上で `skills` を含む deploy / uninstall を検証する）。
  **人間の実 `$HOME` に対して deploy スクリプトを直接実行しないこと**
- `docs/` 配下に新規ファイルを足すときは `DOC-DOCID_PLACEHOLDER_<説明的ファイル名>.md` で作り、
  `./tools/doc-id/doc-id assign <path>` で採番する。`docs/README.md` の索引も更新する

## テスト方針（AGENTS.md「テスト方針」に従う）

この傘で足すのは Markdown（スキル・ADR・README）と HTML の雛形だけで、実行コードは無い。
**新しい自動テストは原則として追加しない。** 保護すべきものは既存の仕組みで守られる:
スキルの配布は `tests/deploy_smoke.sh` と `deploy-all.sh --dry-run`、DOC-ID の整合は
`doc-id check` / `verify`。HTML の雛形は、ブラウザで開いて表示が崩れないことを目視で確認し、
PR 説明にその旨を書けばよい。

---

## 孫1用プロンプト:

````markdown
# 傘ブランチ: multi-repo-pr-review
# 孫ブランチ: mrpr-01-adr
# ターゲット: master（傘経由）

計画書: `/Users/kazuki-hamada/projects/dotfiles/multi-repo-pr-review/docs/planning/DOC-2609270342_multi-repo-pr-review_計画.md`

**まず計画書の「概要」「背景1〜5」「設計1」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」を全部読むこと。** 以下はその上での作業指示である。

## 実装開始前の必須手順

作業ブランチは**必ず `multi-repo-pr-review`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout multi-repo-pr-review
git fetch origin
git merge --ff-only origin/multi-repo-pr-review
git checkout -b mrpr-01-adr
```

## やること

`docs/adr/` に ADR を 1 本追加する。この孫は**決定の記録だけ**を行い、スキル本体は書かない。

- ファイル名は `docs/adr/DOC-DOCID_PLACEHOLDER_multi-repo-pr-review-skills.md` で作り、
  `./tools/doc-id/doc-id assign` で採番する
- 既存の ADR（例: `docs/adr/DOC-2609162327_claude-md-machine-local-tone.md`）の構成
  （ステータス・背景・決定・却下案 など）に倣う
- 記録する決定（すべて計画書で確定済み。**ADR で決定を変えない**）:
  1. スキルを 2 つに分けること、名前（`pr-group-review` / `pr-group-request`）、線引き
     （計画書 背景2・設計1.1）。`pr-review-loop` と別物にする理由
  2. レビュー状態の置き場所（`PR_GROUP_REVIEW_DIR`、既定 `~/work/reviews`、`<日付-テーマ>/` で
     `git init`。計画書 5.1・設計1.2）。「状態」が worktree ではなく仕事の記録であること
  3. 単体 PR を「1 本だけの PR 群」として同じスキルで扱うこと（5.2）
  4. まとめ文書を artifact にせず自己完結 HTML にし、状態ディレクトリに置いて人間が Slack に
     添付すること。Notion は任意（背景2・5.3）
  5. 外部への書き込みの扱い: 下書き → 人間の確認 → 投稿、COMMENT のみ、2 段投稿を既定、
     投稿直前の head と hunk の確認、権限に止められたときの振る舞い（設計1.6）
  6. blocking の表示（5.4）と、コメント書式を投稿先のルールに委ねること（決定的な制約）
  7. 共通の参照文書を `pr-group-review` 側に置き、`pr-group-request` から相対パスで参照すること（設計1.8）
  8. 追いレビューを手動起動にすること（背景2・設計1.7）
- 却下案も書く（例: レビュー状態を対象リポのどれかに置く案、artifact でまとめる案、
  自動で追いレビューする案、AI が APPROVE / REQUEST_CHANGES まで出す案、
  人間にスクリプトを渡して投稿させる案）。根拠は計画書の背景1・4 から引く
- `docs/README.md` のクイックナビゲーションと全 DOC-ID 索引（adr/）に行を足す
- **公開リポジトリなので、社内の組織名・リポ名・同僚の名前・社内 URL を書かない**
  （計画書「決定的な制約」）。実測値は計画書 背景4.1 の匿名化された書き方を使う

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 新しい ADR の DOC-ID が採番され、`doc-id check` / `verify` が通る
- `docs/README.md` の索引から新しい ADR へ辿れる

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files docs/adr/<採番後のファイル名> docs/README.md
pre-commit run --all-files
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `multi-repo-pr-review` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

---

## 孫2用プロンプト:

````markdown
# 傘ブランチ: multi-repo-pr-review
# 孫ブランチ: mrpr-02-reviewer-skill
# ターゲット: master（傘経由）

計画書: `/Users/kazuki-hamada/projects/dotfiles/multi-repo-pr-review/docs/planning/DOC-2609270342_multi-repo-pr-review_計画.md`

**まず計画書の「概要」「背景1〜5」「設計1」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」を全部読むこと。** さらに、**孫1 がマージ済みの ADR
（`docs/adr/` 配下の multi-repo-pr-review-skills）と、既存の `skills/pr-review-loop/SKILL.md`・
`skills/umbrella-orchestrator/SKILL.md` の書きぶりを読んでから着手すること。**

## 実装開始前の必須手順

作業ブランチは**必ず `multi-repo-pr-review`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout multi-repo-pr-review
git fetch origin
git merge --ff-only origin/multi-repo-pr-review
git checkout -b mrpr-02-reviewer-skill
```

## やること

レビュワー用スキル `skills/pr-group-review/` を作る。**このディレクトリはこの PR の中で完結させる**
（`skills/deploy.sh` はディレクトリを見つけ次第全エージェントへ配るため。計画書 背景3 最終項）。

### 1. `skills/pr-group-review/SKILL.md`

- YAML frontmatter: `name: pr-group-review`、`description` には「他人の PR 群（複数リポにまたがる
  ものを含む。1 本だけでもよい）をレビュワーとしてレビューする」「自動発動はしない。
  `/pr-group-review` で明示的に起動」「AI 不問」を含める
- 本文はフェーズ順に書く（計画書 設計1.2〜1.7 を手順化する）:
  1. 受付: 複数の情報源（人間が示したリスト、作者の地図、各 PR の本文のリンク、
     同じブランチ名・関連 issue 等）から対象 PR を列挙して突き合わせ、人間に一覧を確認する。
     レビュー状態ディレクトリを作って `git init`（初回）/ 読み込む（追いレビュー）
  2. 取得: 設計1.3 のとおり。人間の作業ツリーに触れない。head SHA を記録
  3. 地図の検証または作成（設計1.4）
  4. レビュー: グループ別 + 継ぎ目（設計1.5 のチェックリスト）+ 反証。規模が大きい場合に
     サブエージェント / workflow で並列化してよいことと、その目安（計画書 背景4.1 の実測）を書く。
     **修正コードを書かない・push しない・PR 本文を書き換えない**を明示的な禁止として書く
  5. まとめの HTML を状態ディレクトリに生成する（references の雛形を使う）
  6. 下書き → 人間の確認 → 投稿（設計1.6。2 段投稿、投稿直前の head / hunk 確認、COMMENT のみ、
     書式は投稿先ルール、blocking の表示は計画書 5.4、権限に止められたときの振る舞い）
  7. 状態ファイルを更新してコミットし、人間に「相手の返信を待ち、次のラウンドは
     `/pr-group-review` を再起動してください」と伝えて終わる
  8. 追いレビュー（再起動時）: 設計1.7
- 単体 PR のときの縮退（計画書 5.2）を書く
- Notion へのアップロードは人間が求めたときだけ（計画書 5.3）

### 2. `skills/pr-group-review/references/`（共通の参照文書。孫3 も使う）

- PR 群の地図のテンプレート（Markdown の項目定義と、自己完結した HTML の雛形。
  外部 CDN に依存しない、1 ファイルで開ける HTML にする）
- リポ間の継ぎ目チェックリスト（計画書 設計1.5。冒頭に「事故の種は照合より順序と手作業の側に
  あった」実測の注意）
- 状態ファイルの形式（計画書 設計1.2。レビュワー用・依頼者用の区別、ラウンド、指摘の状態）
- ファイル分割と名前は任せる。`pr-group-request` から `../pr-group-review/references/...` で
  参照される前提で、ファイル名を安定させること

### 3. ドキュメント

- `skills/README.md` のスキル一覧の表に `pr-group-review` の行を足す
- ルート `README.md` にスキル一覧があるか実物を確認し、あれば更新する（README の二層構造）

**公開リポジトリなので、社内の組織名・リポ名・同僚の名前・社内 URL・レビューした PR の中身を
書かない**（計画書「決定的な制約」）。計画書 背景4.1 に載っているセッション固有の成果物は、
存在すれば構成の参考に読んでよいが、**中身をコピーしない**。

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 新しいスキルが `./deploy-all.sh --dry-run` で全エージェント分配布対象になり、
  `tests/deploy_smoke.sh` が通る
- HTML の雛形がブラウザで単体で開け、表示が崩れない（目視確認で可。PR 説明に書く）
- スキル本文に、レビュワーが修正・push・PR 本文の書き換え・APPROVE / REQUEST_CHANGES を
  しないことが明示されている（レビューで確認される）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files skills/pr-group-review/SKILL.md skills/README.md
pre-commit run --all-files
./deploy-all.sh --dry-run
tests/deploy_smoke.sh
```

`tests/deploy_smoke.sh` は `HOME` を一時ディレクトリへ差し替えたサンドボックス上で走る。
**人間の実 `$HOME` に対して deploy スクリプトを直接実行しないこと。**

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `multi-repo-pr-review` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

---

## 孫3用プロンプト:

````markdown
# 傘ブランチ: multi-repo-pr-review
# 孫ブランチ: mrpr-03-requester-skill
# ターゲット: master（傘経由）

計画書: `/Users/kazuki-hamada/projects/dotfiles/multi-repo-pr-review/docs/planning/DOC-2609270342_multi-repo-pr-review_計画.md`

**まず計画書の「概要」「背景1〜5」「設計1」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」を全部読むこと。** さらに、**孫1 の ADR と、孫2 がマージ済みの
`skills/pr-group-review/`（特に `references/`）を読んでから着手すること。** この孫は孫2 の
参照文書を再利用するのが仕事であり、同じ内容を書き直すのではない。

## 実装開始前の必須手順

作業ブランチは**必ず `multi-repo-pr-review`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout multi-repo-pr-review
git fetch origin
git merge --ff-only origin/multi-repo-pr-review
git checkout -b mrpr-03-requester-skill
```

## やること

### 1. `skills/pr-group-request/SKILL.md`

依頼者用スキルを作る（**このディレクトリはこの PR の中で完結させる**）。

- YAML frontmatter: `name: pr-group-request`、`description` には「自分の PR 群（複数リポに
  またがるものを含む）のレビューを他人に頼む準備をする」「自動発動はしない。
  `/pr-group-request` で明示的に起動」「AI 不問」を含める
- 本文はフェーズ順に書く:
  1. PR 群を列挙する。**傘ブランチの計画書（`umbrella-orchestrator` 形式の進捗テーブル）からも
     作れる**ことと、その読み方
  2. 地図を作る（`../pr-group-review/references/` のテンプレートを使う。重複して持たない）
  3. 継ぎ目を自分でチェックする（同じく `references/` のチェックリスト）
  4. 各 PR の本文に「PR 群の中での位置」と「マージ前の前提」を書く（**人間の確認後に更新する**）
  5. Slack 用の依頼文の**下書き**を作る（投稿は人間。計画書 5.3）。まとめ HTML を添付する前提で書く
  6. レビュー中のお願いを依頼文に添える: 指摘への修正は fixup コミットで行い、force-push を避ける
     （レビュワーの差分追跡が壊れるため。計画書 背景4.2 Interdiff）
  7. 返ってきた指摘への対応は、PR ごとに `pr-review-loop` で回すことを説明する
- 状態は計画書 設計1.2 の置き場所（`PR_GROUP_REVIEW_DIR`）に、依頼者用として置く

### 2. 相互参照

- `skills/README.md` のスキル一覧に `pr-group-request` の行を足す（ルート `README.md` に
  一覧があれば同様に）
- `skills/pr-review-loop/SKILL.md` に「相手が他人の PR をレビューするなら `pr-group-review`、
  自分の PR 群のレビューを他人に頼む準備は `pr-group-request`」を 1〜2 行で足す。
  **それ以外の改修はしない**（計画書「スコープ外」）
- `skills/umbrella-orchestrator/SKILL.md` に「傘の孫 PR の並びを他人のレビュー依頼用の地図に
  するなら `pr-group-request`」を 1〜2 行で足す
- `skills/pr-group-review/SKILL.md` から `pr-group-request` への参照が無ければ 1 行足す

**公開リポジトリなので、社内の組織名・リポ名・同僚の名前・社内 URL を書かない**
（計画書「決定的な制約」）。

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 新しいスキルが `./deploy-all.sh --dry-run` で全エージェント分配布対象になり、
  `tests/deploy_smoke.sh` が通る
- `pr-group-request` から `../pr-group-review/references/` の各ファイルへの参照が、
  実在するファイル名を指している（手で突き合わせ、PR 説明に書く）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files skills/pr-group-request/SKILL.md skills/README.md skills/pr-review-loop/SKILL.md skills/umbrella-orchestrator/SKILL.md
pre-commit run --all-files
./deploy-all.sh --dry-run
tests/deploy_smoke.sh
```

`tests/deploy_smoke.sh` は `HOME` を一時ディレクトリへ差し替えたサンドボックス上で走る。
**人間の実 `$HOME` に対して deploy スクリプトを直接実行しないこと。**

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `multi-repo-pr-review` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````
