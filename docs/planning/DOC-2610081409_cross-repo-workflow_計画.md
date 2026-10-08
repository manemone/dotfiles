# 計画書: 製品リポと分析リポをまたぐ作業の入口スキルと、複数リポ対応の傘

傘ブランチ: `cross-repo-workflow`
ターゲット: `master`

## 概要

「こういうことをやりたい」と思いついた会話から、専用の会話（herdr のペイン）へ引き継ぎ、
個別のトピックは孫にやらせる——という一連の流れを、毎回迷わずに進められるようにする。
特に、製品リポ（ツール本体がある側）と分析リポ（`analysis`。実験・分析の記録がある側）の
両方にまたがる作業を正しく扱えるようにする。

この傘で作るもの:

- **入口スキル `task-intake`（新設）**: 「どのリポにまたがるか」「PR 1本か複数か」
  「司令官をどのリポに置くか」を判断し、1本なら軽いハンドオフ（このスキルの中に含める）、
  複数なら `umbrella-handoff` へ振り分ける
- **`umbrella-handoff` / `umbrella-orchestrator` の複数リポ対応**: 傘の司令官が、
  傘とは別のリポの孫を同じ進捗テーブルで管理できるようにする
- **配布物 `claude/CLAUDE.md`「傘ブランチへの引き継ぎ判断」を入口スキルへの誘導に書き換える**
  （**人間の承認が要る**）
- **分析リポ側の記録規約**: 「製品側のツールで回した実験を分析リポにどう記録するか」を
  分析リポの `adhoc-analysis` スキルの `references/` に1枚足す。**この傘で作った複数リポの
  手順で、分析リポの孫として回す（ドッグフーディング）**

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。転記後に削除済みで
> 参照できない前提で書く）を material として司令官が起草したものである。** ブリーフに
> 書かれていた問題意識・決定事項・既存の穴・実測値・制約・スコープ外・孫分割の叩き台は
> 本計画書へ転記済みであり、以降はこの計画書が正典である。
>
> **このリポジトリは公開リポジトリである。** ブリーフに含まれていた共同研究先・顧客の名前、
> 学会演題の具体、社内 Slack での発言の逐語、社内の分析ディレクトリ名は、実装に必要な
> 情報ではないため載せず、要約で残した（背景1）。人間自身の問題意識の発言は、
> 設計の検証に使うため逐語で残す。

## 孫ブランチ進捗

| 孫 | リポ | ブランチ | 内容 | 状況 |
|---|---|---|---|---|
| 1 | dotfiles | `xrw-01-adr` | ADR。入口スキルの判断軸と振り分け・司令官の置き場・リポ間の役割分担・複数リポの傘の設計・軽いハンドオフ | ✅ PR #120 マージ済 |
| 2 | dotfiles | `xrw-02-multi-repo-umbrella` | `umbrella-handoff` / `umbrella-orchestrator` の複数リポ対応 | ✅ PR #121 マージ済 |
| 3 | dotfiles | `xrw-03-task-intake` | 入口スキル `task-intake` の新設（軽いハンドオフを含む）と `skills/README.md` | ✅ PR #122 マージ済 |
| 4 | analysis | `xrw-04-analysis-record-ref` | 分析リポ `adhoc-analysis` の `references/` に「他リポのツールで回した実験の記録」を1枚足す（ドッグフーディング。マージは人間） | 🔄 実装中 |
| 5 | dotfiles | `xrw-05-claude-md-pointer` | 配布物 `claude/CLAUDE.md`「傘ブランチへの引き継ぎ判断」を入口スキルへの誘導に更新（**人間の承認後に spawn**） | ⬜ 待機中 |

依存: 孫1 → 孫2 → 孫3 → 孫4 → 孫5 の順に直列で進める。

- 孫2 は孫1 の ADR に従う。孫3 は孫2 の複数リポ対応を前提に振り分け先を書く
- 孫4 は孫2 の手順で spawn する最初の「他リポの孫」である（設計2.3）。中身は孫3 に依存しないが、
  入口スキルの検証題材としても使うため孫3 の後に置く
- **孫5 は人間の承認を得るまで spawn しない。** 孫3 がマージされた時点で、司令官は人間に
  「`claude/CLAUDE.md` の該当節を `task-intake` への誘導に書き換えてよいか」を尋ねる。
  承認が得られたら、この計画書の「背景5」に承認の日付と文言を書き足してから spawn する。
  孫4 は承認を待たずに進めてよい

## 関係するリポ

| 名前 | メインワークツリー | owner/name | 既定ブランチ |
|---|---|---|---|
| dotfiles | `/Users/kazuki-hamada/projects/dotfiles/master` | `manemone/dotfiles` | `master` |
| analysis | `/Users/kazuki-hamada/work/analysis/main` | （private の社内リポ。公開リポのここには書かず、メインワークツリーで `gh repo view --json nameWithOwner -q .nameWithOwner` を叩いた値を使う） | `master` |

## ワークスペースラベル

- 傘: `dotfiles :: 複数リポ作業の入口`
- 孫1: `dotfiles :: 複数リポ作業の入口 孫1 ADR`
- 孫2: `dotfiles :: 複数リポ作業の入口 孫2 傘の複数リポ対応`
- 孫3: `dotfiles :: 複数リポ作業の入口 孫3 入口スキル`
- 孫4: `analysis :: 複数リポ作業の入口 孫4 他リポ実験の記録`
- 孫5: `dotfiles :: 複数リポ作業の入口 孫5 CLAUDE.md誘導`

---

## 背景1: 経緯と問題意識

2026-10-08、分析リポで行っていた相談会話（学会発表に向けた、食事写真の LLM 栄養推定の評価の
準備）の途中で、次の問題意識が出てきた。

### 1.1 人間の発言（逐語）

1回目:

> ここまでの実験の流れや成果物など、どっか Notion
>   などにまとめといたほうがいいかね。あと、こういう kenko
>   リポとかのツールを使って行う実験の結果、まとめとしては analysis
>  に置いておくのがいいとも思うんだが、分散するしどう扱うのがいいかを検討したいのだが。

2回目（この傘の直接の動機）:

> この、製品と analysis をまたいで分析したり記録したりするやり方をスキルにしておきたいんだけど。どこに置くのがいいかな。analysis？普通のAI会話で、ああこういうことやりたいなと思ったら、専用会話（herdr のぺーンをやりやすいようの揃えてある）を立ち上げてハンドオフして、個別のトピックは孫にやらせるとか、一連のワークフローを確立しておきたいんだ。こういうこと非常によくやり、そのたびにどう進めようか迷いたくないから

### 1.2 直近の具体例2件（設計の検証に使う）

**例1: PR 1本規模のハンドオフ（2026-10-06）。** 共同研究先から提供された食事写真
（AI 食事記録を使っていない、写真だけのもの）に、直前の実験と同じ栄養推定を当てて結果を
先方に見せたい。実験したうえで分析リポのスキルでスライドにまとめるところまでを、
「まずトライ」としてクイックにやりたい、という依頼だった。

PR 1本規模だったため `umbrella-handoff` は使わず、相談AIが Markdown のブリーフを手書きして
別の会話に渡した。そのブリーフ（分析リポの外、`~/work/analysis/` 直下に置かれた約150行の
Markdown。dotfiles の外にあるが、孫3 は読んでよい）の節立ては次のとおりで、**軽いハンドオフの
ブリーフの実物として参考になる**:

1. 依頼（原文）
2. この分析の位置づけ
3. 再利用できる資産（すべて master にある）
4. 先に潰すべき前提（モデルが生きているか / 認証 / データの所在・件数・同意範囲 /
   正解値があるか — 設計が分かれる）
5. 作業の骨子
6. 文体・用語で毎回指摘される点（成果物に効く）
7. 引き継ぎ元に残っている未処理

これを受けた別会話が分析リポに PR を1本立てて進めた。

**例2: 製品リポと分析リポの両方にまたがる見込みの件（2026-10-08、人間が社内で受けた相談）。**
製品の AI 食事解析で使っている旧モデルが近く廃止されるため、新しいモデルに乗り換えた場合の
評価をしたい。発表のためではなく製品開発のためという建付けだが、評価でやることは例1の
実験と似ている。製品リポ（`kenko`）側でモデルを差し替え、分析リポ側で評価・記録する形に
なる見込み。翌週に打ち合わせがあり、まだ何も決まっていない。
**この傘の設計が両リポにまたがる場合を正しく扱えるかを確かめる題材として使う**
（実施そのものはスコープ外）。

## 背景2: 人間が確定させた決定事項（覆さないこと）

いずれも相談AIの提案に、人間が「OK」「OK。」で同意したもの。

- **ワークフロー本体は dotfiles に置く。分析リポには置かない。** 理由（相談AIが挙げ、人間が同意）:
  1. 分析リポの `.claude/skills/` に置くと、分析リポで開いた会話でしか読み込まれない。
     「こういうことやりたい」と思いつく会話は製品リポで作業中かもしれないし雑談かもしれない
  2. 土台（`umbrella-handoff` / `umbrella-orchestrator` / `ocw` / `pr-group-*`、herdr 前提の
     道具）がすべて dotfiles の `skills/` にあり、新しいスキルはそれらを組み合わせて使う側
  3. 分析リポの `AGENTS.md`「道具の置き場の決め方」は「分析リポの構造に依存するか」で
     置き場を決める。ハンドオフ・herdr・孫の回し方は分析リポの構造に依存しない
- **分析リポに置くのは「製品側のツールで回した実験を分析リポにどう記録するか」だけ。**
  分析リポの `adhoc-analysis` スキルの `references/` に1枚足す形
- **リポ間の役割分担**（散らばること自体は問題にせず、同じものが2か所にあることと、
  片方から辿れないことを問題にする）:

  | 何を | どこに |
  |---|---|
  | ツール本体（プロンプト・推論コード） | 製品リポ（`kenko` 等）。分析リポにコピーしない |
  | 実行履歴（どの版で・何に・どう流して・何が出たか） | 分析リポ。製品リポのコミット SHA・PR 番号・実行コマンドを残す |
  | 結論・意思決定 | Notion（分析リポの既存規約どおり） |

  製品リポの PR からも分析リポの分析ディレクトリへリンクを貼る（双方向）
- **作るのは `umbrella-handoff` の手前に立つ「入口」のスキル。** 毎回迷っている判断を肩代わりする:
  - どのリポにまたがるか（製品だけ／分析だけ／両方）
  - 規模（PR 1本／複数）
  - 司令官をどのリポに置くか
  - → 1本なら軽いハンドオフ（ブリーフ＋herdr のペインを立てる）、複数なら
    `umbrella-handoff`（複数リポ対応に広げる）へ振り分ける
- **両リポにまたがるとき、司令官は「問いと結論が載るほうのリポ」に置く。** 評価が目的なら
  分析リポ、製品の変更が主目的で評価が確認にすぎないなら製品リポ
- **この傘は dotfiles に立てる**（本体が dotfiles にあるため）

## 背景3: 既存の穴

1. **傘が1リポ前提で、複数リポの孫を同じ司令官の下に置けない。**
   `skills/umbrella-orchestrator/SKILL.md` §3.2 は孫を
   `ocw -H --no-commander <孫ブランチ名> <傘ブランチ名>` で作る（孫は傘ブランチから切る＝
   同じリポの中）。マージ検出（§3.3）も同じリポの `gh pr list` / 傘ブランチしか見ない。
   `umbrella-handoff` / `umbrella-orchestrator` の SKILL.md に複数リポへの言及は0件
   （2026-10-08、`grep -i "複数リポ|別リポ|cross|multi-repo"` で確認）
2. **PR 1本規模の軽いハンドオフが無い。** `umbrella-handoff` §1 の流れは傘ブランチを作ることが
   前提。1本で済む件（例1）は相談AIが毎回やり方を即興で決めている
3. **入口の判断がどこにも書かれていない。** 配布物 `claude/CLAUDE.md`
   「傘ブランチへの引き継ぎ判断」は「複数の PR に分かれる規模なら `umbrella-handoff` を提案」
   だけで、1本規模のとき・複数リポにまたがるときの扱いが無い
4. **分析リポ側に、他リポのツールで回した実験の記録規約が無い。** 分析リポの `AGENTS.md`・
   `adhoc-analysis` スキルに該当する記述は0件（2026-10-08、grep で確認）。散らかりの実例として、
   分析リポの中で Vertex AI のバッチ投入スクリプト `run_batch.py` が3か所に複製されている
   （食事写真の LLM 評価の束の中の2つの分析の `scripts/` と、例1の分析の `scripts/`）

**使える先行例**（dotfiles 内）:

- `skills/pr-group-review` / `skills/pr-group-request`（PR #116）— 複数リポにまたがる PR 群の
  「地図」と「継ぎ目」の考え方。複数リポの傘の進捗管理に借りられる可能性がある
- `docs/planning/DOC-2609072212_agent-handoff_計画.md` — 前回の傘 `agent-handoff`
  （`umbrella-handoff` を作った傘）
- `docs/planning/DOC-2609172237_file-handoff_計画.md`
- `docs/planning/DOC-2609270342_multi-repo-pr-review_計画.md`

## 背景4: 実測値

- 2026-10-08 時点、herdr のワークスペースは29個。ラベルの接頭辞（`<repo> ::`）は7つのリポに
  わたる（`kenko`・`analysis`・`dotfiles` ほか社内リポ4つ）。**同じテーマが複数のリポの
  ワークスペースに分かれている例がある**（分析リポ側の「傘の孫立て検討中」のワークスペースと、
  ラベルにリポ名の無い同じ依頼対応のワークスペースが並存していた）
- （司令官が裏取り、2026-10-08）**`ocw` は別リポに孫のワークツリーを作れる。変更は不要。**
  `bin/ocw` の `init_repo_context` は対象リポを**カレントディレクトリ**から
  `git worktree list --porcelain` で解決する（`-C` のようなオプションは無い）。したがって
  司令官が `cd <別リポのメインワークツリー> && ocw -H --no-commander <孫> <base-ref>` の形で
  叩けば、そのリポにワークツリーと herdr ワークスペースができる。ワークツリーの置き場は
  そのリポの `ocw.worktreeDir`（既定 `{repo_parent}/{name}`）に従い、分析リポ
  （`~/work/analysis/main`）なら `~/work/analysis/<孫>` になる（Pattern A の配置と一致）。
  **実行はしていない（コードを読んで確認した）。** 孫2 が実際に1度叩いて確かめる
- （司令官が裏取り）分析リポ（`analysis`）は private、既定ブランチは `master`。
  `.claude/pr-review.yml` を持ち、`pr-review-loop` が回る。分析リポの `AGENTS.md` では
  `.claude/skills/` 配下の変更は「構造・規約の変更」に当たり、**PR を作ってレビューを通す。
  `master` へのマージは人間**。構造・規約の変更のブランチ名に決まった形は無い

## 背景5: 人間の承認の記録

- （未）孫5（配布物 `claude/CLAUDE.md` の書き換え）の承認。孫3 のマージ後に司令官が尋ね、
  得られたらここに日付と文言を書き足す

---

## 設計1: 入口スキル `task-intake`（司令官が確定。孫1・孫3 はこれに従う）

### 1.1 名前と位置づけ

- 名前は `task-intake`。`skills/task-intake/SKILL.md`
- 「こういうことをやりたい」が固まった会話（相談AI）が使う。**相談AIは実装も計画書執筆も
  しない**（`umbrella-handoff` と同じ線引き）
- 自動発動はしない。人間が `/task-intake` で起動するか、相談AIが提案して人間が同意したら使う
- AI 不問（Claude Code / Codex / OpenCode）。`SendMessage` のような Claude Code 固有の手段は
  `umbrella-orchestrator` §5「AI間送信手順（二段構え）」を参照して使い、それに依存しきらない

### 1.2 判断の3軸と振り分け

相談AIは次の順で判断し、**判断結果と根拠を人間に1回見せて確認を取ってから**振り分ける。

1. **どのリポにまたがるか**: 製品だけ／分析だけ／両方（その他のリポも同じ扱い）。
   「ツール本体を変えるか」「実行履歴を残すか」を背景2 の役割分担表に当てて決める
2. **規模**: PR 1本か複数か。目安は配布物 `claude/CLAUDE.md`「傘ブランチへの引き継ぎ判断」の
   3つ（独立にレビュー・マージできる単位に分かれる／関心事が分離できる／複数セッション・
   複数日にまたがる）。**両リポにまたがる時点で PR は最低2本**（リポごとに1本）になる点に注意
3. **司令官をどのリポに置くか**（複数のときだけ）: 「問いと結論が載るほうのリポ」。
   評価が目的なら分析リポ、製品の変更が主目的で評価が確認にすぎないなら製品リポ

振り分け:

| リポ | 規模 | 行き先 |
|---|---|---|
| 1つ | 1本 | 軽いハンドオフ（設計1.3） |
| 1つ | 複数 | `umbrella-handoff`（従来どおり） |
| 両方 | 各リポ1本ずつ程度 | `umbrella-handoff`。司令官を 3. で決めたリポに置き、もう一方のリポの PR を「他リポの孫」とする（設計2） |
| 両方 | 複数 | 同上 |

両リポにまたがるのに軽いハンドオフを2本別々に立てる案は採らない（片方から辿れなくなる。
背景2 の役割分担が問題にしているのはまさにこれ）。

例2（モデル乗り換え評価）を当てると: 両方にまたがる／製品側はモデル差し替え、分析側は評価と
記録で最低2本／目的は「新モデルに乗り換えてよいか」の判断＝評価なので司令官は分析リポ、
製品リポの差し替え PR は他リポの孫、となる。**孫3 はこの当てはめを SKILL.md の例として載せる。**

### 1.3 軽いハンドオフ（`task-intake` の中に含める。別スキルにしない）

別スキルにしない理由: 判断の直後にしか使わず、単独で起動する場面が無いため。

1. **ブリーフを書く。** 置き場は**作るワークツリーの外**、対象リポの `{repo_parent}`
   （Pattern A なら `~/work/<repo>/handoff_<slug>.md`）。ワークツリーの中に置くと誤って
   コミットされる。節立ては例1 の実物を一般化したものを雛形にする:
   依頼（原文）／位置づけ／再利用できる資産／先に潰すべき前提／作業の骨子／
   成果物の文体・用語で毎回指摘される点／引き継ぎ元に残っている未処理
2. **対象リポのメインワークツリーで `ocw -H --no-commander <ブランチ名> origin/<既定ブランチ>`
   を叩く**（2ペイン。1本規模に司令官は要らない）。ブランチ名は対象リポの規約に従う
   （例: 分析リポの単発分析なら `adhoc/<YYYY-MM>_<スラッグ>`）
3. 出力の `workspace:` を日本語ラベルへ改名する（`umbrella-orchestrator` §5「ワークスペース
   ラベル」の書式。`<repo> :: <説明>`）
4. implementer に**ブリーフの絶対パスだけ**を送る。送信手順・到達確認は
   `umbrella-orchestrator` §5「AI間送信手順（二段構え）」に従う。末尾に「PR 作成後は
   `/pr-review-loop` を回す。マージは人間」の1文を付ける
5. 相談AIはそこで手を引く。ブリーフは一時ファイルであり、実装AIが PR 本文に必要な内容を
   転記したあとは消してよい（消すのは実装AIではなく人間か相談AI。勝手に消さない）

---

## 設計2: 複数リポの傘（司令官が確定。孫1・孫2 はこれに従う）

### 2.1 傘ブランチは司令官のリポにだけ立てる

- 傘ブランチ・計画書・司令官ワークスペースは、設計1.2 の 3. で決めたリポにだけ置く
- **他リポの孫は、そのリポの既定ブランチ（`origin/<既定ブランチ>`）から切り、既定ブランチへ
  PR を出す。** 他リポに副傘は立てない（既定）。理由: 他リポの孫は通常1〜2本で、副傘を立てても
  「副傘→既定ブランチ」の最終 PR が1本増えるだけになる
- **他リポの孫の PR は既定ブランチ向きなので、承認されても AI はマージしない（人間の仕事）。**
  `umbrella-orchestrator` §2.4 の「base がこのリポジトリの既定ブランチでない」条件がそのまま
  効く（既定ブランチの判定は**そのリポで** `gh repo view` する）
- 他リポ側にも独立にマージしたい孫が3本以上あるなど、副傘を立てたほうが安い規模なら、
  計画書にそう書いて副傘を立ててよい（例外。ADR に条件を書く）

### 2.2 進捗テーブルに「リポ」列を足す（後方互換）

- 列順は `| 孫 | リポ | ブランチ | 内容 | 状況 |`（本計画書の進捗テーブルが実例）
- **「リポ」列が無い計画書は、全孫が傘と同じリポ**として扱う（既存の計画書を書き換えない）
- 「リポ」列の値はリポの短い名前。**計画書の別の節（例: `## 関係するリポ`）に、名前→
  メインワークツリーの絶対パス・`owner/name`・既定ブランチ の対応表を置く**。司令官は
  そこから `cd` 先と `gh -R` の引数を引く
- 状況の値に `⏳ 人間のマージ待ち (PR <owner/name>#XX)` を足す（他リポの孫が承認済みで、
  人間のマージを待っている状態）

### 2.3 spawn・検出・検証・後片付け（他リポの孫）

- **spawn**: 関係するリポの表のメインワークツリーへ `cd` して
  `ocw -H --no-commander <孫ブランチ> origin/<既定ブランチ>`。base-ref を省略しない
  （省略すると `ocw rm` のマージ判定が壊れるのは同じリポの孫と同じ理由。`umbrella-orchestrator`
  §3.2）。孫用プロンプトの「実装開始前の必須手順」も、傘ではなくそのリポの既定ブランチから
  切る形で書く
- **マージ検出**: `gh pr list -R <owner/name> --head <孫ブランチ> --state merged`
- **検証**: 司令官は他リポのメインワークツリーで `git checkout` しない（人間の作業ツリーで
  あり、dirty なことがある）。他リポの孫の lint / test は、その孫自身の `pr-review-loop`
  （そのリポの `.claude/pr-review.yml`）と CI に委ね、司令官はマージ検出だけを行う
- **`/autopilot`**: 他リポの孫が承認済みになったら `⏳ 人間のマージ待ち` に更新して人間へ通知し、
  マージされるまで次の孫へ進んでよいかは計画書の依存の書き方に従う（依存が無ければ進む）
- **後片付け**: `ocw rm` は他リポのメインワークツリーへ `cd` して叩く。base-ref が既定ブランチ
  なので、通常は `--force` なしで通る
- **継ぎ目**: 他リポの孫の PR 本文と、司令官のリポ側の対応する PR / 計画書の間に双方向リンクを
  貼る（背景2 の役割分担と同じ考え方）。複数リポの PR 群をまとめて人にレビューを頼むときは
  `pr-group-request`（進捗テーブルの「リポ」列から PR 群の地図を作れる）

### 2.4 `umbrella-handoff` 側

- ブリーフ雛形に「関係するリポ」節（名前・メインワークツリーのパス・`owner/name`・既定
  ブランチ・そのリポで守るべき規約の在処）と「司令官をこのリポに置く理由」を足す
- 傘ブランチ・司令官ワークスペースを作るリポは、設計1.2 の 3. で決めたリポ。
  `umbrella-handoff` は今と同じく1リポにだけ傘を作る

---

## 設計3: 分析リポの記録規約（孫4 の中身。役割分担は背景2 で確定済み）

分析リポの `.claude/skills/adhoc-analysis/references/` に1枚足し、`adhoc-analysis` の
SKILL.md の該当工程から参照する。書く内容:

- 背景2 の役割分担表（ツール本体／実行履歴／結論・意思決定の置き場）
- 他リポのツールを使った実験を分析ディレクトリに記録するとき、`README.md` 等に残すもの:
  製品リポの名前・コミット SHA・PR 番号・実行コマンド・入力と出力の所在
- **ツール本体（プロンプト・推論コード）を分析リポにコピーしない。** 製品リポのツールを
  分析の都合で変えたくなったら、製品リポに PR を出す（その PR から分析ディレクトリへリンク）
- 双方向リンク: 製品リポの PR 本文に分析ディレクトリへのリンクを貼る
- 分析リポ自身の補助スクリプト（例: バッチ投入）を分析ごとにコピーしている現状は、
  この reference の対象外として触れるに留める（共通化はスコープ外）

---

## 決定的な制約（孫は全部守ること）

- dotfiles `AGENTS.md`「最重要ルール」
  - `master` を書き換える操作（マージ・push・force push）は人間だけ
  - 孫 → 傘のマージはレビューで承認済みの PR に限り AI が行ってよい
  - 上流の取り込みは rebase（`git fetch origin` + `git rebase origin/master` +
    `git push --force-with-lease`）。`git pull` は使わない
  - `git reset --hard` / `git clean` / 裸の `git push --force` は人間の承認が要る
  - deploy スクリプトを実オペレーションで実行しない（`--dry-run` / サンドボックス）
  - linter の抑制・除外・閾値緩和を AI の判断で足さない
- **配布物 `claude/CLAUDE.md` は指示が無い限り編集しない**（dotfiles `AGENTS.md`「3つの領域」）。
  孫5 だけがここを変え、**人間の承認を取ってから**行う。Codex / OpenCode にも効く
- `skills/` のスキルは **AI 不問**（Claude Code / Codex / OpenCode。`skills/README.md`）。
  `SendMessage` のような Claude Code 固有の手段に依存しきらない
- `skills/deploy.sh` は `skills/` 直下のディレクトリをすべて自動検出して配る。
  **スキルのディレクトリは、それを作る PR の中で完結させる**
- **分析リポは別リポで、独自の `AGENTS.md` を持つ。** 分析リポ側の変更は分析リポの規約に従う:
  `.claude/skills/` 配下の変更は「構造・規約の変更」として PR を作りレビューを通す。
  `master` へのマージは人間
- **dotfiles は公開リポジトリである。** dotfiles 側の成果物（ADR・スキル・この計画書の追記）に、
  共同研究先・顧客の名前、社内 URL、社内の分析ディレクトリ名、社内での発言の逐語を書かない。
  リポ名 `kenko` / `analysis` と、汎用化した例（「製品のモデル乗り換え評価」等）は書いてよい

## スコープ外

- Notion にテーマの親ページを作ること（相談会話側で別途扱う）
- モデル乗り換え評価そのものの実施や、それを分析リポの定期分析にすること
  （この傘では例2を設計の検証題材として使うだけ）
- 分析リポの `run_batch.py` の複製を `lib/` に共通化すること（分析リポ側の別件）
- `bin/ocw` の変更（背景4 のとおり不要の見込み。孫2 で変更が要ると判明したら、
  実装せず司令官に報告する）

## 必須の検証ステップ（AGENTS.md「コミット前の必須ステップ」より。省略しない）

- `pre-commit run --files <path>` を新規ファイル追加時・大幅変更時に対象ファイル単位で実行する
  （コミット直前まで遅らせない）
- `docs/` 配下に新規ファイルを足すときは `DOC-DOCID_PLACEHOLDER_<名前>.md` で作り、
  `./tools/doc-id/doc-id assign` で採番する
- デプロイ関連のシェルスクリプトを変えたら `tests/deploy_smoke.sh`
- `bin/` 配下を変えたら `python3 -m unittest discover -s bin/tests -v`（この傘では変えない見込み）
- スキルを足したら `skills/README.md` の一覧表を更新する
- 最後に `pre-commit run --all-files`

## テスト方針（AGENTS.md「テスト方針」に従う）

この傘の成果物は自然言語の文書（ADR・SKILL.md・reference）が中心で、自動テストの対象になる
コードは無い見込み。**検証は pre-commit（doc-id の check / verify、Markdown の基本チェック）で
足りる。** 新しいテストを足すのは、`bin/` やシェルスクリプトに手を入れることになった場合だけ。

---

## 孫1用プロンプト:

````markdown
# 傘ブランチ: cross-repo-workflow
# 孫ブランチ: xrw-01-adr
# ターゲット: master（傘経由）

計画書: `/Users/kazuki-hamada/projects/dotfiles/cross-repo-workflow/docs/planning/DOC-2610081409_cross-repo-workflow_計画.md`

**まず計画書の「概要」「背景1〜5」「設計1〜3」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」を全部読むこと。** 以下はその上での作業指示である。

## 実装開始前の必須手順

作業ブランチは**必ず `cross-repo-workflow`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout cross-repo-workflow
git fetch origin
git merge --ff-only origin/cross-repo-workflow
git checkout -b xrw-01-adr
```

（`ocw` が既に `xrw-01-adr` を作って checkout 済みなら、`git fetch origin` と
`git log --oneline -1 origin/cross-repo-workflow` で傘の先端を含んでいることだけ確認すればよい）

## やること

`docs/adr/` に ADR を 1 本追加する。この孫は**決定の記録だけ**を行い、スキル本体は書かない。

- ファイル名は `docs/adr/DOC-DOCID_PLACEHOLDER_cross-repo-task-intake.md` で作り、
  `./tools/doc-id/doc-id assign` で採番する
- 既存の ADR（例: `docs/adr/DOC-2609162327_claude-md-machine-local-tone.md`）の構成
  （ステータス・背景・決定・却下案 など）に倣う
- 記録する決定（すべて計画書で確定済み。**ADR で決定を変えない**）:
  1. ワークフロー本体を dotfiles に置き、分析リポには記録規約だけを置くこと（背景2）
  2. 入口スキル `task-intake` の判断の3軸と振り分け表（設計1.1・1.2）
  3. 司令官の置き場の規則「問いと結論が載るほうのリポ」（背景2・設計1.2）
  4. リポ間の役割分担表と双方向リンク（背景2・設計3）
  5. 軽いハンドオフを `task-intake` に含めること、ブリーフの置き場と節立て（設計1.3）
  6. 複数リポの傘: 傘は司令官のリポにだけ立てる／他リポの孫は既定ブランチから切り既定ブランチへ
     PR／そのマージは人間／副傘は例外／進捗テーブルの「リポ」列と後方互換／
     他リポの孫の検証を司令官がしない理由（設計2）
  7. `ocw` を変えずに済む根拠（背景4。カレントディレクトリでリポを解決する）
  8. 配布物 `claude/CLAUDE.md` の書き換えを人間の承認後にすること（計画書の依存の節）
- 却下案も書く（例: ワークフロー本体を分析リポに置く案、軽いハンドオフを別スキルにする案、
  両リポにまたがる件で軽いハンドオフを2本別々に立てる案、他リポにも常に副傘を立てる案、
  `ocw` に `-C <repo>` を足す案）。根拠は計画書の背景から引く
- 例2（モデル乗り換え評価）を設計1.2 に当てはめた結果を、決定の検証として ADR に載せる
- `docs/README.md` のクイックナビゲーションと全 DOC-ID 索引（adr/）に行を足す
- **公開リポジトリなので、共同研究先・顧客の名前、社内 URL、社内の分析ディレクトリ名、
  社内での発言の逐語を書かない**（計画書「決定的な制約」）。計画書の要約済みの書き方を使う

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

1. PRを作成する。**PRの向き先は必ず `cross-repo-workflow` にすること。master には絶対に出さない。**
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
# 傘ブランチ: cross-repo-workflow
# 孫ブランチ: xrw-02-multi-repo-umbrella
# ターゲット: master（傘経由）

計画書: `/Users/kazuki-hamada/projects/dotfiles/cross-repo-workflow/docs/planning/DOC-2610081409_cross-repo-workflow_計画.md`

**まず計画書の「概要」「背景1〜5」「設計1〜3」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」と、孫1 が追加した ADR（`docs/adr/` の
`cross-repo-task-intake`）を全部読むこと。** 以下はその上での作業指示である。

## 実装開始前の必須手順

作業ブランチは**必ず `cross-repo-workflow`（傘ブランチ）から切ること**。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout cross-repo-workflow
git fetch origin
git merge --ff-only origin/cross-repo-workflow
git checkout -b xrw-02-multi-repo-umbrella
```

（`ocw` が既に `xrw-02-multi-repo-umbrella` を作って checkout 済みなら、`git fetch origin` と
`git log --oneline -1 origin/cross-repo-workflow` で傘の先端を含んでいることだけ確認すればよい）

## やること

計画書 設計2 を `umbrella-orchestrator` と `umbrella-handoff` に反映する。

### 1. `skills/umbrella-orchestrator/SKILL.md`

- §2.1 進捗テーブル: 「リポ」列（任意）と後方互換（列が無ければ全孫が傘と同じリポ）、
  `## 関係するリポ` 節の書式（名前→メインワークツリーの絶対パス・`owner/name`・既定ブランチ）、
  状況 `⏳ 人間のマージ待ち (PR <owner/name>#XX)` を足す
- §3.2 `/spawn`: 他リポの孫の spawn（関係するリポの表のメインワークツリーへ `cd` して
  `ocw -H --no-commander <孫> origin/<既定ブランチ>`。base-ref を省略しない）と、
  他リポの孫向けに自動付与する「実装開始前の必須手順」「実装完了後の流れ」の差分
  （既定ブランチから切る／既定ブランチへ PR／承認後もマージせず人間に依頼）
- §2.4・§3.3・§3.5: マージ検出に `gh pr list -R <owner/name>`、他リポの孫は司令官が
  マージしない（既定ブランチ判定はそのリポで行う）、検証は司令官がせずその孫の
  `pr-review-loop` と CI に委ねる理由、`/autopilot` の cron 本文に他リポの孫の分岐を足す、
  後片付けの `ocw rm` は他リポのメインワークツリーへ `cd` して叩く
- 進捗テーブルの「リポ」列から `pr-group-request` の PR 群の地図を作れる旨の相互参照
  （`skills/pr-group-request/SKILL.md` §1.3 側にも「リポ」列の読み方を1行足す）
- **既存の1リポの傘の手順を壊さない**（「リポ」列が無い計画書での挙動は今と同じ）

### 2. `skills/umbrella-handoff/SKILL.md`

- ブリーフ雛形に「関係するリポ」節と「司令官をこのリポに置く理由」を足す（設計2.4）
- 入口スキル `task-intake`（孫3 で作る）から呼ばれる前提を1行で書く。`task-intake` の
  ディレクトリはまだ無いので、リンクではなく名前で言及する

### 3. `ocw` で別リポにワークツリーが作れることの実地確認

計画書 背景4 はコードを読んだだけで、実行していない。次の手順で1度だけ確かめ、結果を
PR 本文に書く（**分析リポではなく、捨ててよい合成リポジトリで行う**）:

- scratchpad に `git init` した合成リポジトリ（コミット1つ）を作り、その中へ `cd` して
  `ocw xrw-probe HEAD`（`-H` なし。herdr ワークスペースは作らない）を叩き、ワークツリーが
  合成リポ側の `{repo_parent}` にできることを確認する
- 確認後 `ocw rm xrw-probe` で片付け、合成リポジトリも消す
- **変更が要ると判明したら `bin/ocw` を直さず、PR 本文と司令官への報告に書く**（スコープ外）

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 「リポ」列が無い既存の計画書を読むときの手順が、今と変わらない（文書上で確認する）
- 他リポの孫の PR を AI がマージする経路が SKILL.md のどこにも無い
- `pre-commit run --all-files` が通る

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files skills/umbrella-orchestrator/SKILL.md skills/umbrella-handoff/SKILL.md skills/pr-group-request/SKILL.md
pre-commit run --all-files
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `cross-repo-workflow` にすること。master には絶対に出さない。**
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
# 傘ブランチ: cross-repo-workflow
# 孫ブランチ: xrw-03-task-intake
# ターゲット: master（傘経由）

計画書: `/Users/kazuki-hamada/projects/dotfiles/cross-repo-workflow/docs/planning/DOC-2610081409_cross-repo-workflow_計画.md`

**まず計画書の「概要」「背景1〜5」「設計1〜3」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」と、孫1 の ADR、孫2 で更新された
`skills/umbrella-orchestrator/SKILL.md` / `skills/umbrella-handoff/SKILL.md` を全部読むこと。**
以下はその上での作業指示である。

## 実装開始前の必須手順

作業ブランチは**必ず `cross-repo-workflow`（傘ブランチ）から切ること**。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout cross-repo-workflow
git fetch origin
git merge --ff-only origin/cross-repo-workflow
git checkout -b xrw-03-task-intake
```

（`ocw` が既に `xrw-03-task-intake` を作って checkout 済みなら、`git fetch origin` と
`git log --oneline -1 origin/cross-repo-workflow` で傘の先端を含んでいることだけ確認すればよい）

## やること

### 1. `skills/task-intake/SKILL.md`（新設）

計画書 設計1 をそのままスキルにする。

- YAML frontmatter（`name` / `description`）は既存スキル（例: `skills/umbrella-handoff/SKILL.md`）に
  倣う。description に「自動発動はしない。/task-intake で明示的に起動」「AI 不問」を含める
- 判断の3軸・振り分け表・判断結果を人間に1回見せて確認を取る手順（設計1.2）
- 例2（製品のモデル乗り換え評価）の当てはめを例として載せる（設計1.2 末尾）。
  例1（PR 1本規模の分析）も「1つのリポ × 1本 → 軽いハンドオフ」の例として載せる
- 軽いハンドオフの手順（設計1.3）。ブリーフ雛形は `skills/task-intake/references/` に
  置いてよい。節立ての参考として、計画書 背景1.2 の例1 のブリーフの実物
  （`~/work/analysis/` 直下の `handoff_*.md`。読んでよい）を読むこと。
  **ただし公開リポジトリなので、実物の固有名・社内事情は雛形に持ち込まず、節立てと
  各節に何を書くかだけを一般化して移す**
- 複数のときは `umbrella-handoff` へ引き渡す（司令官のリポ・関係するリポを渡す）
- 送信・ラベル改名は `umbrella-orchestrator` §5 を参照する（全文をコピーしない）
- 背景2 のリポ間の役割分担表を載せ、分析リポ側の記録規約は分析リポの
  `adhoc-analysis` の reference（孫4 で追加予定）にあることを名前で示す

### 2. 相互参照・一覧

- `skills/README.md` の一覧表に `task-intake` を足す
- `skills/umbrella-handoff/SKILL.md` の、孫2 が名前で言及した `task-intake` をリンクにする
- **配布物 `claude/CLAUDE.md` は触らない**（孫5 の担当。人間の承認待ち）

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- `skills/task-intake/` がこの PR の中で完結している（`skills/deploy.sh` が自動検出して配るため）
- 公開リポジトリに出してはいけない固有名が含まれていない（`git grep` で目視確認する）
- `pre-commit run --all-files` が通る

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files skills/task-intake/SKILL.md skills/README.md skills/umbrella-handoff/SKILL.md
DRY_RUN=1 sh skills/deploy.sh
pre-commit run --all-files
```

（`skills/deploy.sh` は `DRY_RUN=1` の環境変数で dry-run する。`--dry-run` 引数は解釈されず
実際に書き換えが起きるので渡さない。計画書「決定的な制約」の dotfiles `AGENTS.md` 参照）

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `cross-repo-workflow` にすること。master には絶対に出さない。**
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

## 孫4用プロンプト:

````markdown
# 司令官の傘: dotfiles の cross-repo-workflow（このリポではない）
# このリポ: analysis（他リポの孫）
# 孫ブランチ: xrw-04-analysis-record-ref
# ターゲット: master（傘を経由しない。マージは人間）

計画書（dotfiles 側）: `/Users/kazuki-hamada/projects/dotfiles/cross-repo-workflow/docs/planning/DOC-2610081409_cross-repo-workflow_計画.md`

**まず計画書の「背景2」「背景3 の4」「設計3」「決定的な制約」「スコープ外」を読むこと。
次に、このリポ（analysis）の `AGENTS.md` と `.claude/skills/adhoc-analysis/SKILL.md` を読むこと。
このリポでの作業は、このリポの `AGENTS.md` の規約が優先する。** 以下はその上での作業指示である。

## 実装開始前の必須手順

このリポには傘ブランチが無い。作業ブランチは**このリポの `origin/master` から切る**
（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git fetch origin
git checkout -b xrw-04-analysis-record-ref origin/master
```

（`ocw` が既に `xrw-04-analysis-record-ref` を `origin/master` から作って checkout 済みなら、
`git fetch origin` と `git log --oneline -1 origin/master` で先端を含んでいることだけ確認すればよい）

## やること

計画書 設計3 を、このリポの `.claude/skills/adhoc-analysis/references/` に1枚の reference として
書き、`adhoc-analysis` の SKILL.md の該当する工程（実行・記録の工程。どこが適切かは SKILL.md を
読んで判断する）から参照する。

- ファイル名は既存の references に倣う（例: `cross_repo_tools.md`）
- 書く内容は設計3 のとおり。役割分担表は計画書 背景2 からそのまま移す
- 記録の実例として、このリポの中で `run_batch.py` が複数の分析に複製されている現状に触れてよい
  （このリポは private なので分析ディレクトリ名を書いてよい）。ただし共通化はしない（スコープ外）
- このリポの `AGENTS.md` に、この reference への導線が要るか判断する（要るなら最小限で足す）

## 検証方針

- このリポの `.claude/pr-review.yml` の `lint_cmd` / `test_cmd` と pre-commit が通る
- `adhoc-analysis` の SKILL.md から新しい reference へ辿れる

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**向き先はこのリポの `master`。** これは「構造・規約の変更」に当たる
   （このリポの `AGENTS.md` 参照）。PR 本文に、dotfiles 側の計画書（傘 `cross-repo-workflow`）
   から来た孫であることを書く（dotfiles は公開リポなので、リンクは
   `https://github.com/manemone/dotfiles/tree/cross-repo-workflow` の傘ブランチでよい）
2. `/pr-review-loop` を起動する
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** base が `master` なので、マージは人間の仕事である。
   承認されたら人間に「マージしてください」と依頼して止まる

reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。
````

---

## 孫5用プロンプト:

````markdown
# 傘ブランチ: cross-repo-workflow
# 孫ブランチ: xrw-05-claude-md-pointer
# ターゲット: master（傘経由）

計画書: `/Users/kazuki-hamada/projects/dotfiles/cross-repo-workflow/docs/planning/DOC-2610081409_cross-repo-workflow_計画.md`

**まず計画書の「背景5」を読み、配布物 `claude/CLAUDE.md` の書き換えについて人間の承認が
記録されていることを確認すること。記録が無ければ何も変更せず、司令官に報告して止まる。**
次に「概要」「背景2・3」「設計1」「決定的な制約」と、孫3 で追加された
`skills/task-intake/SKILL.md` を読むこと。

## 実装開始前の必須手順

作業ブランチは**必ず `cross-repo-workflow`（傘ブランチ）から切ること**。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout cross-repo-workflow
git fetch origin
git merge --ff-only origin/cross-repo-workflow
git checkout -b xrw-05-claude-md-pointer
```

（`ocw` が既に `xrw-05-claude-md-pointer` を作って checkout 済みなら、`git fetch origin` と
`git log --oneline -1 origin/cross-repo-workflow` で傘の先端を含んでいることだけ確認すればよい）

## やること

- 配布物 `claude/CLAUDE.md` の「傘ブランチへの引き継ぎ判断」節を、`task-intake` への誘導に
  書き換える。PR 1本規模・複数リポにまたがる場合も含めて「こういうことをやりたい」が
  固まったら `task-intake` を提案する、という形にする。判断の目安（3つ）は残してよいが、
  詳細は `task-intake` に任せて二重管理を避ける。「同じ提案を繰り返さない」「人間が1本で
  済むと言ったら従う」は残す
- **それ以外の行を変えない。** 人格のパーソナライズの import 行（`@~/.claude/CLAUDE.machine.md`）
  には触れない
- このファイルは Codex（生成物）・OpenCode（symlink）にも効く（dotfiles `AGENTS.md`
  「3つの領域」）。文面が Claude Code 固有の手段に依存しないこと
- ルート `AGENTS.md` や `claude/README.md` に、この節の内容を説明している箇所があれば合わせる

## 検証方針

- `claude/CLAUDE.md` の差分が当該節だけである
- `pre-commit run --all-files` が通る
- `tests/deploy_smoke.sh` が通る（`claude/CLAUDE.md` と codex の生成物の配布を確認する）

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files claude/CLAUDE.md
pre-commit run --all-files
tests/deploy_smoke.sh
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `cross-repo-workflow` にすること。master には絶対に出さない。**
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
