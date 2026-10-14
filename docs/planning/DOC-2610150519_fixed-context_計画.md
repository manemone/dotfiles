# 計画書: 全会話に毎回乗る固定分を削る

傘ブランチ: `fixed-context`
ターゲット: `master`

## 概要

Claude Code の会話は、compact の直後でも毎回、ルール文書（各リポの `CLAUDE.md` → `@AGENTS.md`、
グローバルの `CLAUDE.md`、`MEMORY.md`）・スキル一覧・ツール定義などの固定分を頭に載せて走る。
実測では固定分の最大は各リポの `AGENTS.md` で、次いでスキル一覧（Figma プラグインの14個分を含む）だった
（背景4）。この傘では、人間が決めた次の2つで固定分を削る。

1. **各リポの `AGENTS.md` を、毎回要る「芯」と、作業のときだけ読む「詳細」に分ける（孫1〜6）。**
   まず dotfiles で分け方の方針を決めて dotfiles 自身と `templates/repo-baseline` の雛形に適用し（孫1）、
   その方針で他の5リポ（lora-dataset-forge・pixidex・modeldex・sheaf・iosci）の `AGENTS.md` を分ける（孫2〜6）
2. **Figma プラグインを、ユーザー全体では止め、Figma を使うリポ（iosci・sheaf・pixidex）でだけ有効にする（孫7 ほか）。**
   そのリポでは、ラフに指示すれば自動で Figma のスキルを読む体験を残す

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。転記後に削除済みで
> 参照できない前提で書く）を material として司令官が起草したものである。** ブリーフに
> 書かれていた問題意識・決定事項・既存の穴・実測値・未確認の前提・制約・スコープ外・必須の
> 検証ステップ・孫分割の叩き台は本計画書へ転記済みであり、以降はこの計画書が正典である。

## 孫ブランチ進捗

| 孫 | リポ | ブランチ | 内容 | 状況 |
|---|---|---|---|---|
| 1 | dotfiles | `fc-01-agents-md-policy` | `AGENTS.md` の芯と詳細の分け方の方針を決めて文書にし、dotfiles の `AGENTS.md` と `templates/repo-baseline` の雛形に適用する。他リポへの適用手順（copier を撒いたリポの扱いを含む）も決める | ✅ PR #170 マージ済 |
| 2 | lora-dataset-forge | `fc-02-agents-md-split` | 孫1 の方針で `AGENTS.md` を芯と詳細に分ける | ⏳ 人間のマージ待ち (PR lora-dataset-forge#494) |
| 3 | pixidex | `fc-03-agents-md-split` | 孫1 の方針で `AGENTS.md` を分ける（孫7 の検証済みなら Figma の有効化の1行も同乗） | 🔄 実装中 |
| 4 | modeldex | `fc-04-agents-md-split` | 孫1 の方針で `AGENTS.md` を分ける | ✅ PR modeldex#114 マージ済 |
| 5 | sheaf | `fc-05-agents-md-split` | 孫1 の方針で `AGENTS.md` を分ける（孫7 の検証済みなら Figma の有効化の1行も同乗） | ✅ PR sheaf#278 マージ済 |
| 6 | iosci | `fc-06-agents-md-split` | 孫1 の方針で `AGENTS.md` を分ける（孫7 の検証済みなら Figma の有効化の1行も同乗） | ✅ PR iosci#130 マージ済 |
| 7 | dotfiles | `fc-07-figma-scope` | `figma@synced` にリポごとの `enabledPlugins` の上書きが効くかを確かめ、machine 設定でユーザー全体を止める手順とリポ側で有効にする書き方を書く | ✅ PR #171 マージ済 |

依存:

- 孫1 は最初に単独で走る。
- 孫2〜6 は**孫1 のマージ後**（方針と、他リポへの適用手順を孫1 が決める）。孫2〜6 どうしは**並列**
  （リポが別で、触るファイルが重ならない）。他リポの孫なので PR はそのリポの既定ブランチ向きで、マージは人間。
  ⏳（人間のマージ待ち）のあいだも、他の孫は依存しないので先へ進んでよい
- 孫7 は孫1 と触るファイルが重ならないので**並列**（背景5-2 は人間が決めた。進行記録 2026-10-15）
- Figma の有効化の1行（iosci・sheaf・pixidex の `.claude/settings.json`）は、孫7 の検証（背景5-1）が済んでから入れる。
  その時点で孫3・5・6 がまだ spawn 前ならその PR に同乗させ、すでに走っていたら司令官が追加の孫を足す（設計3.3）
- **ユーザー全体で止める設定が実機に効くのは、3リポの有効化がそれぞれの既定ブランチにマージされた後にする**
  （先に止めると、Figma を使うリポで体験が途切れる。設計3.3）

## 関係するリポ

このリポ（dotfiles）は公開リポで、他の5リポは非公開なので、owner/name は値ではなく解決方法を書く
（`umbrella-orchestrator` §2.1）。司令官はそのリポのメインワークツリーへ `cd` してから叩いて値を得る。
進捗テーブルの状況値も `owner/name` の代わりに「名前」列の短い名前で書く（例: `⏳ 人間のマージ待ち (PR pixidex#12)`）。

| 名前 | メインワークツリー | owner/name | 既定ブランチ |
|---|---|---|---|
| dotfiles | `/home/manemone/projects/dotfiles/master` | `manemone/dotfiles` | `master` |
| lora-dataset-forge | `/home/manemone/projects/lora-dataset-forge/main` | メインワークツリーで `gh repo view --json nameWithOwner -q .nameWithOwner` を叩いた値 | `main` |
| pixidex | `/home/manemone/projects/pixidex/main` | 同上 | `main` |
| modeldex | `/home/manemone/projects/modeldex/main` | 同上 | `main` |
| sheaf | `/home/manemone/projects/sheaf/main` | 同上 | `main` |
| iosci | `/home/manemone/projects/iosci/main` | 同上 | `main` |

各リポで守るべき規約の在処は、それぞれの `AGENTS.md`（lora-dataset-forge の `AGENTS.md` には傘ブランチ方式の規定がある）。
sheaf のメインワークツリーは人間が別のブランチを checkout して作業中のことがある。司令官はメインワークツリーで
`git fetch origin` と `ocw` だけを叩き、`git checkout` / `git merge` / `git pull` は叩かない。

## ワークスペースラベル

接頭辞は `ocw label-prefix`（dotfiles では `dotfiles`。他リポはそのリポで評価した値）。

- 傘: `dotfiles :: 毎回の固定分を削る`
- 孫1: `dotfiles :: 毎回の固定分を削る 孫1 AGENTS.mdの分け方`
- 孫2〜6: `<そのリポの接頭辞> :: 毎回の固定分を削る 孫N AGENTS.mdを分ける`
- 孫7: `dotfiles :: 毎回の固定分を削る 孫7 Figmaの有効範囲`

## 背景1: 問題意識（要約）

人間は、上位のプランにしても利用枠をすぐ使い切ってしまい、開発速度が上がった実感も薄いので、トークンが
どこに消えているかを数字で見たいと相談した。相談の AI が集計したところ、学習の会話でキャッシュ切れが
多いことが見つかり、これは lora-dataset-forge の傘 `ai/training-skill-tidy` で対処した。その傘の調査で
「compact の直後でも毎回乗る固定分が大きい」ことが分かり、人間の決定で別件としてこの傘に回ってきた。

相談の中で、スキルは本文ではなく一覧が毎回乗っていること、固定分の最大は Memory files（各リポの
`AGENTS.md`）であること、全会話に Figma プラグインのスキル一覧も乗っていることが分かった。人間は、
スキルを必要に応じて読み込むオプションでもこの量になるのかを問い、Figma を使うのは iosci・sheaf と
おそらく pixidex だけだが、ラフに指示して自動で Figma のスキルを読んでくれる体験はとても良いので
悩ましい、と述べた。相談の AI は「ユーザー全体では止め、使うリポでだけ有効にする」案と、
`AGENTS.md` の整理が本命であることを示し、人間は task-intake に回すと決めた。

## 背景2: 人間が確定させた決定事項（覆さないこと）

- この傘でやるのは次の2つ（task-intake で人間が確認済み。司令官は dotfiles、他の5リポは他リポの孫）:
  1. **各リポの `AGENTS.md` を、毎回要る芯と、作業のときだけ読む詳細（`docs/design/` など）に分ける。**
     対象: dotfiles・lora-dataset-forge・pixidex・modeldex・sheaf・iosci
  2. **Figma プラグインを、ユーザー全体では止め、Figma を使うリポ（iosci・sheaf・pixidex）でだけ有効にする。**
     そのリポでは「ラフに指示すれば自動で Figma のスキルを読む」体験を残す（人間がこの体験を高く評価している）
- 次は**やらない**（相談で検討して外した）:
  - dotfiles が配るスキルを `skillOverrides` の `"name-only"` にする（合計 0.8k しか無く効果が小さい）
  - dotfiles のスキルに `disable-model-invocation: true` を付ける（AI が AI にスキルを回させる運用
    〔「PR 作成後は /pr-review-loop を回して」など〕が壊れる）
- claude.ai から同期されているスキル（docx・pptx・xlsx・google-workspace・ブラウザ系など、約 3.3k）を絞るかは、
  人間が残すものを選ぶ話としてまだ決めていない。この傘で扱うなら人間に選んでもらう（「人間に確認すること」）

## 背景3: 既存の穴

- 公式ドキュメント（code.claude.com/docs/en/memory）の目安は CLAUDE.md 1ファイル 200 行以内。各リポの `AGENTS.md` は
  全部これを超えていて、毎回の会話の頭に丸ごと乗る（Claude Code では `CLAUDE.md` の `@AGENTS.md` から読み込まれる）
- dotfiles の `templates/repo-baseline/template/AGENTS.md.jinja`（撒いた先の `AGENTS.md` の雛形。271 行）にも、
  芯と詳細を分ける方針は無い（相談 AI の推測。未確認）。撒いた先が同じように太る
- Figma プラグイン `figma@synced`（claude.ai から同期）は全会話で有効。Figma を使わないリポ（lora-dataset-forge・dotfiles など）の
  会話にも、スキル14個分の一覧が毎回乗る

## 背景4: 実測値

### 4.1 相談の会話の `/context`（2026-10-15、dotfiles のメインワークツリー、Opus 5.5）

| 中身 | トークン |
|---|---|
| Memory files（CLAUDE.md・AGENTS.md・MEMORY.md） | 17.6k |
| System tools（組み込みツールの定義） | 18.4k |
| Skills（スキル一覧） | 8.9k |
| System prompt ＋ MCP の説明 | 3.2k |
| （deferred は毎回は乗らない: System tools 23.2k・MCP tools 8.4k） | — |

スキル一覧 8.9k の内訳: dotfiles が配るスキル 11 個で約 0.8k、Figma 14 個＋cowork 2 個で約 2.5k、claude.ai 同期で約 3.3k、組み込み約 3.1k。

### 4.2 `AGENTS.md` の大きさ（2026-10-15、各リポのメインワークツリー。`wc -lm`）

| リポ | 行 | 文字 |
|---|---|---|
| dotfiles | 505 | 22,830 |
| lora-dataset-forge | 329 | 15,531 |
| modeldex | 315 | 12,696 |
| pixidex | 309 | 14,507 |
| iosci | 275 | 9,887 |
| sheaf | 263 | 10,475 |

参考: `templates/repo-baseline/template/AGENTS.md.jinja` は 271 行・8,239 字（司令官が 2026-10-15 に計測）。

### 4.3 その他

- lora-dataset-forge の傘 `ai/training-skill-tidy` の孫1 の調査（lora-dataset-forge の `docs/design/` にある
  学習の会話のトークン消費調査。lora-dataset-forge 側の採番で 2610150029）: 学習の会話の compact 直後の文脈は中央値 91k、うち約 3.5 万トークンが
  固定分。学習の会話 20 本だけで固定分に週約 $160（毎回の読み約 $50＋キャッシュ切れのたびの書き直し約 $110）
- 相談 AI の集計（2026-10-08〜14、`~/.claude/projects/**/*.jsonl`、API 単価換算）: 全体の API 呼び出し約 5 万回・約 $4,886。
  固定分を 1 回あたり 1〜1.5 万トークン減らせれば、読みだけで週 $100〜150 程度（目安）。キャッシュ切れの書き直しも同じ割合で減る
- Figma 系の一覧（約 2.5k）を Figma を使わないリポで外した場合の節約は週 $20〜25 程度（目安）。`AGENTS.md` の整理が本命
- 公式ドキュメントで確認した設定（claude-code-guide サブエージェント経由。URL は code.claude.com/docs/en/skills ・ /plugins/install ・ /memory）:
  - プラグインの有効・無効は `enabledPlugins`。user（`~/.claude/settings.json`）＜ project（`.claude/settings.json`）＜
    local（`.claude/settings.local.json`）の順で上書き
  - claude.ai から同期されたプラグインは `<name>@synced` と表示され、`/plugin` の Installed タブで切り替えられる
  - `skillOverrides`（`"on"` / `"name-only"` / `"user-invocable-only"` / `"off"`）はプラグインのスキルには効かない
  - `MEMORY.md` は先頭 200 行か 25KB の先に来たほうまでしか読まれない（lora-dataset-forge の `MEMORY.md` は 235 行で後ろが切れている）
  - 計測は `/context`（Skills の行）・`/doctor`（一覧の内訳）・`claude plugin details <name>`

## 背景5: 先に潰すべき前提（未確認）

1. **`figma@synced` にリポごとの `enabledPlugins` の上書きが効くか。** 公式ドキュメントで確かめられたのは「Installed タブで
   切り替えられる」までで、synced プラグインにも user / project / local の上書きが効くかは書かれていなかった。まず 1 リポで
   ユーザー全体を止め・そのリポで有効にして、Skills の一覧から Figma が消える／戻るかを確かめる（孫7）。効かなければ
   人間に相談する（代替: そのまま全体で有効にしておく、など）
2. **ユーザー全体で止める設定の置き場。** `~/.claude/settings.json` は dotfiles のデプロイが生成し直すので直接いじっても消える。
   `claude/settings.json`（配布物。全マシンに効く）か `settings.machine.json`（マシンローカル。固定パス。AGENTS.md「claude の例外」）か。
   → **人間が `settings.machine.json`（このマシンだけ）に決めた**（2026-10-15）
3. **リポ側の有効化は `.claude/settings.json`（コミットされる）に書く。** `.claude/settings.local.json` は作業ツリーごとで、
   `ocw` で作る新しいワークツリーに引き継がれない
4. **`AGENTS.md` の「芯」の基準。** 毎回の作業で守らせたい最重要ルール（`master` を書き換えない・linter を抑制しない等）は芯に
   残す。詳細へ出したものは「この作業のときはここを読め」と芯から参照させる。opencode は `opencode.json` の `instructions` に
   規約文書を列挙しているリポがある（dotfiles など）ので、分けた先のファイルを opencode にも読ませるか判断が要る（孫1）
5. **他の AI（Codex・OpenCode）への影響。** `AGENTS.md` は Codex / OpenCode もそのまま読む。詳細を外へ出したときに参照を
   辿れるか（孫1）
6. **各リポの `MEMORY.md`**（`~/.claude/projects/<リポ>/memory/`。リポの外）も固定分。lora-dataset-forge の 235 行は上限超えで
   切れている。→ **人間がこの傘で扱うと決めた**（2026-10-15。設計4）。リポの外なので PR にならない
7. **（司令官が追加）copier で雛形を撒いたリポとの整合。** pixidex・modeldex・sheaf・iosci の4リポは `templates/repo-baseline` を
   copier で撒いている（`.copier-answers.yml` あり。lora-dataset-forge は無し）。pixidex・modeldex は `_src_path` が dotfiles の
   GitHub で `_commit` が記録されており `copier update` できるが、sheaf・iosci はローカルパスから撒いて `_commit` が無く
   `copier update` できない。孫1 が雛形の `AGENTS.md.jinja` を分けると、
   - `copier update` は既定で `_src_path` の既定ブランチ（`master`）の版を取るので、雛形の変更は**傘が `master` に入るまで**他リポに届かない
   - 孫2〜6 が手で分けた後に `copier update` を当てると、同じ変更が二重に当たってコンフリクトしうる

   孫1 は、他リポへの適用手順（手で分けるか、`copier update --vcs-ref` で傘の版を当てるか、雛形と同じファイル配置に揃えて
   後の update を軽くするか、など）を決めて方針文書に書く。孫2〜6 はそれに従う

## 設計1: 芯と詳細の分け方（孫1）

### 1.1 決めること

孫1 は次を決め、`docs/design/` に方針文書（DOC-ID を採番）として書く。決定に却下案があれば ADR にしてもよい。

- **芯に残すものの基準。** 毎回の作業で守らせたいもの（不可逆操作の禁止・linter 抑制の禁止・最重要ルール・
  どの作業のときにどの詳細を読むかの索引）は芯。特定の作業でしか要らない手順・仕組みの説明（例: dotfiles の
  「デプロイの仕組み」「テスト方針」「コミット前の必須ステップ」の詳細）は詳細へ出す候補
- **芯の大きさの目安。** 公式の目安（1ファイル 200 行以内）を出発点にする。最終的な数字は孫1 が決める
- **詳細の置き場と、芯からの参照の書き方。** `@` で import すると Claude Code は起動時に読み込むので固定分が減らない。
  芯からは `@` を付けない普通のパス（と DOC-ID）で「この作業のときはここを読め」と書く。置き場の候補は `docs/design/`、
  各ツールディレクトリの `README.md`、Claude Code の `.claude/rules/`（`paths:` で触ったファイルに応じて読み込まれる）、
  サブディレクトリの `AGENTS.md` / `CLAUDE.md` など。Codex / OpenCode でも辿れるか（背景5-5）を判断材料にする
- **opencode.json の `instructions` の扱い（背景5-4）。** `instructions` に列挙したファイルは OpenCode が毎回読むので、
  分けた詳細を列挙すると OpenCode の固定分は減らない。列挙を減らすか残すかを決める
- **他リポへの適用手順（背景5-7）。** copier を撒いたリポ（update 可能な2リポ・不可能な2リポ）と撒いていないリポ
  （lora-dataset-forge）のそれぞれについて、孫2〜6 が従う手順を書く
- **効果の測り方。** 分ける前後で、毎回読み込まれるファイル（`CLAUDE.md` から `@` で辿れるもの）の合計の行数・文字数を
  `wc -lm` で比べる。トークンで測れるならそれも書く（`/context` の Memory files の行は人間が対話で見られる）

### 1.2 適用

- dotfiles のルート `AGENTS.md` を方針どおりに分ける。**中身を失わない**（詳細へ移しただけで、消したルールが無い）こと
- `templates/repo-baseline/template/AGENTS.md.jinja` にも方針を入れ、撒いた先が太らないようにする（必要なら詳細の
  雛形ファイルを足す）。`tests/template_smoke.sh` が通ること
- 移した節を参照している箇所（`skills/`・`docs/`・`templates/`・`.claude/pr-review.yml` の `convention_docs`・
  `opencode.json`・各 `README.md`）を `git grep` で洗い、参照先を直す。例: スキルや文書が「AGENTS.md「テスト方針」」
  「AGENTS.md「コミット前の必須ステップ」」のように節名で指している箇所
- risk-based なテスト方針の3箇所（`skills/pr-review-loop/SKILL.md`・`AGENTS.md.jinja`・ルート `AGENTS.md`）の関係が
  崩れないこと。テスト方針をルート `AGENTS.md` から詳細へ移すなら、3箇所の重複の注記（AGENTS.md「実装時の注意」の最後の項目）も
  移した先に合わせて直す

## 設計2: 他リポへの適用（孫2〜6）

- 各リポの孫は、孫1 の方針文書と他リポへの適用手順に従って、そのリポの `AGENTS.md` を芯と詳細に分ける
- そのリポ自身の規約（ブランチ名・PR の作法・コミット前の手順・DOC-ID の運用）に従う。DOC-ID を持つリポで
  `docs/` に新規ファイルを足すなら、そのリポの採番手順に従う
- 中身を失わない・移した節への参照を直す（そのリポのスキル・文書・`opencode.json` など）は孫1 と同じ
- 分ける前後の `wc -lm` を PR 本文に書く
- PR 本文に、この計画書（dotfiles の `docs/planning/` のこのファイル）と孫1 の PR へのリンクを書く（継ぎ目）
- pixidex・sheaf・iosci の孫は、spawn の時点で孫7 の検証（背景5-1）が済んで進行記録に書かれていれば、Figma の有効化の
  1行（設計3.2）も同じ PR に入れる。書かれていなければ入れない（後で司令官が追加の孫を足す）

## 設計3: Figma の有効範囲（孫7 ほか）

### 3.1 検証（背景5-1）

孫7 は、まず `figma@synced` に `enabledPlugins` の上書きが効くかを確かめる。実 `$HOME` の `~/.claude/settings.json` は
デプロイの生成物なので書き換えない。確かめ方は孫7 が選ぶ（例: 一時ディレクトリで project 側の `.claude/settings.json` /
`.claude/settings.local.json` に `"figma@synced": false` を書き、ヘッドレス起動〈`claude -p --output-format stream-json --verbose`
の最初の init イベント〉のスキル・プラグイン一覧から Figma が消えるかを見る。逆向き〈user で止めて project で戻す〉は、
`HOME` を差し替えたサンドボックスか `--settings` など、実 `$HOME` を触らない方法で確かめる）。確かめ方と結果は文書に残す。
**効かなければ、設定を入れずに司令官へ報告して止まる**（司令官が人間に相談する）。

### 3.2 リポ側の有効化

iosci・sheaf・pixidex の `.claude/settings.json`（コミットされる。背景5-3）の `enabledPlugins` に `"figma@synced": true` を足す。
既存のキーを壊さない。

### 3.3 ユーザー全体で止める設定と順序

- 置き場は **`settings.machine.json`（このマシンだけ）**（人間の決定。背景5-2）。配布物 `claude/settings.json` には入れない
- machine 設定はリポの外（固定パス。`~/.claude/settings.machine.json` はその symlink）なので PR にならない。孫7 は、
  止め方（machine 設定に何を書くか・書いた後に `~/.claude/settings.json` を作り直すにはデプロイが要ること）と、リポ側で
  有効にする書き方を `claude/README.md` 等に書くだけにする。**machine 設定の実際の編集とデプロイは人間が行う**
  （人間が明示的に指示すれば AI が行ってよい）
- **実機で止めるのは、3リポの有効化がそれぞれの既定ブランチにマージされてから。** 司令官は、3リポのマージが揃ったら
  人間に「machine 設定で止めてデプロイしてよい」と伝える

## 設計4: 各リポの `MEMORY.md`（孫1〜6。PR の外）

### 4.1 現状（2026-10-15、司令官が計測。`~/.claude/projects/<メインワークツリーのパス>/memory/MEMORY.md`、`wc -lc`）

| リポ | 行 | バイト |
|---|---|---|
| lora-dataset-forge | 236 | 36,701 |
| sheaf | 73 | 14,006 |
| pixidex | 33 | 6,631 |
| modeldex | 24 | 4,630 |
| iosci | 14 | 2,530 |
| dotfiles | 13 | 2,257 |

lora-dataset-forge は 200 行・25KB の両方を超えていて後ろが読まれていない。sheaf は行数は少ないが1行が長い。
memory のディレクトリはワークツリーではなくリポ（メインワークツリーのパス）ごとなので、そのリポの孫のセッションが
システムプロンプトで渡される memory のパスがそのまま対象になる。

### 4.2 作法（孫1 が方針文書に書く）

- `MEMORY.md` は索引だけにする。1つの記憶に1行（`- [題](ファイル.md) — 短いフック`）。中身は個別のファイルへ
- 目安は 200 行・25KB より十分小さく。フックは1行で読み切れる長さに
- **記憶を消さない。** `MEMORY.md` に直書きされている中身は個別のファイルへ移すだけ。重複・古いと思うものは消さずに報告する

### 4.3 適用（孫2〜6。PR とは別の作業）

- そのリポの孫が、`AGENTS.md` の PR とは別に、自分の memory ディレクトリの `MEMORY.md` を 4.2 の作法で整える
- 触る前に memory ディレクトリを丸ごと複製しておく（`cp -a <memory> <memory>.bak-<日付>`。memory の親ディレクトリに置く）。
  同じリポで他の会話が同時に記憶を書き足すことがあるので、書き換える直前に読み直し、差分は小さく当てる
- 前後の `wc -lc` と複製のパスを最終報告と PR 本文に書く（中身は書かない）
- 整える必要が無いほど小さければ（目安: 50 行・10KB 未満）何もしない
- 編集が auto mode の分類器などに止められたら回避せず、止められたことを最終報告に書く（`AGENTS.md` の PR は止めない）
- dotfiles 自身の `MEMORY.md` は小さいので対象外

## 人間に確認すること（2026-10-15 に答えをもらった。詳細は進行記録）

1. 背景5-2: ユーザー全体で Figma を止める設定の置き場 → `settings.machine.json`（このマシンだけ）
2. 背景5-6: 各リポの `MEMORY.md` → この傘で扱う（設計4）
3. 背景2: claude.ai から同期されているスキル（約 3.3k）→ この傘では扱わない（進行記録）

## 決定的な制約（孫は全部守ること）

- dotfiles `AGENTS.md`「最重要ルール」: `master` を書き換えるのは人間だけ。孫→傘のマージは司令官がレビュー承認済み PR に限る。
  他リポの孫の PR はそのリポの既定ブランチ向きで、マージは人間（`umbrella-orchestrator` の他リポの孫の扱い）
- 配布物 `claude/CLAUDE.md` / `claude/settings.json` は指示が無い限り編集しない（3 エージェントに及ぶ）。Figma をユーザー全体で
  止める設定を配布物に入れるなら、人間の確認を取る（設計3.3）
- deploy スクリプトを AI の判断で実 `$HOME` に実行しない。`~/.claude/settings.json` を直接書き換えない
- risk-based なテスト方針は dotfiles の 3 箇所（`skills/pr-review-loop/SKILL.md`・`templates/repo-baseline/template/AGENTS.md.jinja`・
  ルート `AGENTS.md`）に意図的に重複している。どれかを触るなら残り 2 つも確認する
- `docs/` の文書に言及するときは DOC-ID を明示する（dotfiles の規約）
- リポの文書・PR 本文に人間の発言を逐語で書かない（要約する）。dotfiles は公開リポなので、他リポ（非公開）の中身を
  dotfiles の文書・PR に書き写さない（リポ名と行数などの数字はよい）
- `AGENTS.md` を分けるときに**ルールを消さない**。移すだけ。消したほうがよいルールを見つけたら、消さずに PR 本文と司令官への報告に書く

## スコープ外

- 組み込みツールの定義（System tools 18.4k）。Claude Code 本体の話で手が出せない
- 学習の会話の待ち方・スキル分割（lora-dataset-forge の傘 `ai/training-skill-tidy` で PR #493 として main に入った）
- 実装の孫の文脈膨張（dotfiles の傘 `context-bloat`、PR #169 で master に入った。デプロイはまだ）
- グローバルの `claude/CLAUDE.md`（配布物）の整理。今回の対象は各リポの `AGENTS.md`

## 必須の検証ステップ

- dotfiles: `pre-commit run --files <path>`（新規・大幅変更の時点で）と `pre-commit run --all-files`。`templates/repo-baseline/` か
  ルートの `copier.yml` を触るなら `tests/template_smoke.sh`。`claude/settings.json` 等デプロイ関連を触るなら `tests/deploy_smoke.sh`。
  `docs/` に新規ファイルを足すなら `DOC-DOCID_PLACEHOLDER_*.md` で作って `./tools/doc-id/doc-id assign`
- 他リポ: それぞれの `AGENTS.md` のコミット前の手順に従う
- `AGENTS.md` を分けた効果は、分けた前後の `wc -lm`（設計1.1）で測る。`/context` の Memory files の行は人間が対話で見られる

## テスト方針（dotfiles AGENTS.md「テスト方針」に従う）

`AGENTS.md` と方針文書の変更は文書の変更なのでテスト対象外（レビューで「ルールを失っていないか」「参照が切れていないか」を見る）。
雛形を触ったら既存の `tests/template_smoke.sh` で生成物の Markdown の崩れと参照先の実在を確かめる。足した詳細の雛形ファイルの
参照先が実在することを smoke に足す価値があるかは孫1 が判断する。Figma の設定は設定値1行なので専用テストは要らない
（検証は設計3.1 の実測）。`claude/settings.json` を触るなら `tests/deploy_smoke.sh` で生成が壊れていないかを確かめる。

## 孫ブランチ分割の叩き台（ブリーフより転記。採った分割は上の進捗テーブル）

叩き台であり、司令官が再設計してよいとされていた。

- 孫1（dotfiles）: `AGENTS.md` の芯と詳細の分け方の方針を決め、dotfiles の `AGENTS.md` に適用。あわせて `templates/repo-baseline` の
  雛形にも方針を入れる（撒いた先が太らないように）
- 孫2〜6（他リポの孫。各リポ 1 本）: 孫1 の方針で各リポの `AGENTS.md` を分ける。リポごとに中身が違うので独立に進められる
- 孫7（Figma）: 前提1 を 1 リポで確かめてから、ユーザー全体で止める設定（dotfiles）と、iosci・sheaf・pixidex の
  `.claude/settings.json` での有効化。リポ側の 1 行は孫2〜6 の `AGENTS.md` の PR に同乗させてもよい

司令官の判断: 叩き台どおり7本に分けた。変えたのは次の2点。

- 4リポが copier で雛形を撒いていると分かった（背景5-7）ので、他リポへの適用手順を決めることを孫1 の仕事に足した
- 孫7 はリポ側の1行を自分では入れず、検証と dotfiles 側の設定に絞った（他リポの変更は他リポの孫の PR に載せる）。
  リポ側の1行が孫3・5・6 に同乗できなければ、司令官が追加の孫を足す

## 進行記録

（司令官が運用中に分かったこと・人間の決定をここに追記する）

- 2026-10-15: 計画書を起草した。孫1 を spawn した
- 2026-10-15: 「人間に確認すること」の3点を人間に上げた。孫7 は背景5-2 の答えを待つ
- 2026-10-15: 人間の答え。(1) Figma を止める設定は `settings.machine.json`（このマシンだけ）に置く（設計3.3 を書き換えた）。
  (2) 各リポの `MEMORY.md` もこの傘で扱う（設計4 を足した。孫1 にも方針文書へ作法を足すよう伝えた）。(3) claude.ai 同期の
  スキルは、人間が重くないのではと見たので扱わない。司令官の目安でも、Figma の約 2.5k が週 $20〜25 なので 3.3k は週 $25〜35 程度で、
  `AGENTS.md`（dotfiles だけで 2 万字超）より一桁小さい。孫7 を spawn する
- 2026-10-15: 孫7 の PR #171 を司令官がマージした。**孫7 の検証済み（Figma の有効化の1行を同乗させてよい）。** `figma@synced` は user で `false`・project の `.claude/settings.json` で `true` にすると戻る（local でも戻る）。結果は DOC-2610150527、止め方とリポ側の書き方は `claude/README.md` §4.10。孫3・5・6 は設計3.2 の1行を同乗させる。傘で `pre-commit run --all-files` が通った
- 2026-10-15: 孫1 の PR #170 を司令官がマージした。**方針文書は DOC-2610150522（`docs/design/` 配下の「AGENTS.mdの芯と詳細の分け方」）。** 他リポへの適用手順と `MEMORY.md` の作法（設計4.2）もこの文書にある（§6 が `MEMORY.md`）。dotfiles の `AGENTS.md` の詳細は DOC-2610150520 系（`docs/design/DOC-2610150520*`）へ移った。傘で `pre-commit run --all-files`・`tests/template_smoke.sh`・`tests/deploy_smoke.sh` が通った。孫2〜6 を spawn する
- 2026-10-15: 孫5 sheaf#278 は人間がマージした。孫2・3・4・6 も承認済みで人間のマージ待ち。**孫3 pixidex#114 には Figma の有効化の1行が入っていない**（`.claude/settings.json` の書き換えを、孫の auto mode の分類器が自己変更として止めた。孫は回避せず止まった）。人間が孫3 のペインで許可し、同じ PR に積ませている（積んだら再レビューが要るので、状況を 🔄 に戻した）。iosci#130 には入っている

## 孫1用プロンプト:

````markdown
# 傘ブランチ: fixed-context
# 孫ブランチ: fc-01-agents-md-policy
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/fixed-context/docs/planning/DOC-2610150519_fixed-context_計画.md`

**まず計画書の「概要」「背景1〜5」「設計1」「設計2」「決定的な制約」「スコープ外」「必須の検証ステップ」
「テスト方針」「進行記録」を全部読むこと。**

## 実装開始前の必須手順

`ocw` がすでに `fc-01-agents-md-policy` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/fixed-context` の
先端から切られていることを確かめる（`git pull` は使わない）。

## やること

1. 計画書 設計1.1 の項目を決め、`docs/design/` に方針文書を書く（`DOC-DOCID_PLACEHOLDER_*.md` で作って
   `./tools/doc-id/doc-id assign`）。他リポへの適用手順（背景5-7。copier を撒いたリポの扱い）もこの文書に書く。
   孫2〜6（他リポの実装AI）がこの文書だけを読んで作業できるように書く。計画書 設計4.2 の `MEMORY.md` の作法もこの文書に書く
2. 計画書 設計1.2 に従い、dotfiles のルート `AGENTS.md` を芯と詳細に分ける。ルールを消さず、移すだけにする
3. `templates/repo-baseline/template/AGENTS.md.jinja` にも方針を入れる（必要なら詳細の雛形ファイルを足す）
4. 移した節への参照を `git grep` で洗って直す（設計1.2）。`opencode.json` の `instructions` は設計1.1 の判断に従う
5. 分ける前後の `wc -lm`（毎回読み込まれるファイルの合計）を方針文書と PR 本文に書く
6. ルートの `README.md` / `docs/README.md` など二層構造の片側だけを直していないか確かめる

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 分けた後の芯と詳細を合わせて、分ける前の `AGENTS.md` のルールが1つも失われていない（レビューで突き合わせる）
- 芯から詳細への参照、およびスキル・文書から移した節への参照が切れていない（`doc-id verify` と `git grep`）
- 雛形から生成した `AGENTS.md` と詳細ファイルが壊れていない（`tests/template_smoke.sh`）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --all-files
tests/template_smoke.sh
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `fixed-context` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** `/pr-review-loop` の手順にマージへ進む記述があっても実行しない
   （孫が人間のフィードバック前に勝手にマージするのを防ぐため。マージは傘の司令官が行う）
5. 最終報告を書き終えたら、最後の行動として、司令官が spawn の送信文で渡した司令官の Herdr ペインへ
   承認を報告する（渡されていなければ報告せず、人間に「承認済み。マージは司令官（または人間）が行う」と伝えて止まる）。
   送り方は umbrella-orchestrator スキル §5「AI間送信手順（二段構え）」に従う。本文は
   「孫1 `fc-01-agents-md-policy` の PR #<番号> が HEAD <短縮SHA> で承認されました。マージをお願いします。」
   だけにする。報告は1回だけ。送れなくても再送せず、送れなかったことを人間に1行伝えて止まる

なお `/pr-review-loop` は、レビューを依頼した直後の区切りで文脈が大きければ `ocw self-compact` で
自分を compact する（その手順は pr-review-loop 側。使えなければ何もしない）。compact の後は、
復帰メモに従ってレビュー待ちに戻り、この「実装完了後の流れ」を最後まで続けること。
実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。
傘ブランチが先へ進んでコンフリクトしたら `git rebase origin/fixed-context` と
`git push --force-with-lease` で追随する（AGENTS.md「最重要ルール」）。

## 大きい出力を文脈へ流し込まない（実装中ずっと）

- ファイルを丸ごと読まず、`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む
- 約100行・5,000字を超えそうな出力は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る
- 既存の長いファイルを丸ごと書き直さず、Edit の差分で直す

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `fixed-context` から切ること**。master から切ると PR の diff に傘ブランチ全体が
混入してレビュー不能になる。`ocw` が `origin/fixed-context` から切ったワークツリーを用意済みなので、
上の「実装開始前の必須手順」で確かめるだけでよい（`git pull` は使わない）。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

## 孫2〜6用プロンプト（共通の本文）

孫2〜6 は同じ手順で、リポだけが違う。下の「孫N用プロンプト:」の各節は、この共通の本文を読ませる。

````markdown
# 傘ブランチ: fixed-context（dotfiles 側。このリポには傘を立てない）
# ターゲット: このリポの既定ブランチ `main`

計画書（dotfiles 側）: `/home/manemone/projects/dotfiles/fixed-context/docs/planning/DOC-2610150519_fixed-context_計画.md`

**まず計画書の「概要」「背景1〜5」「設計2」「決定的な制約」「スコープ外」「進行記録」を読むこと。**
進行記録に、孫1 が書いた方針文書の DOC-ID・パスと、孫1 の PR 番号が書いてある。方針文書は dotfiles の
傘ワークツリー（`/home/manemone/projects/dotfiles/fixed-context/` 配下。孫1 のマージ後の内容）にある。
**方針文書の「他リポへの適用手順」を全部読み、それに従うこと。**

## やること

1. このリポの `AGENTS.md`（と `CLAUDE.md` から `@` で読み込まれるもの）を、方針文書に従って芯と詳細に分ける。
   ルールを消さず、移すだけにする。消したほうがよいルールを見つけたら、消さずに PR 本文に書く
2. 移した節への参照（このリポのスキル・文書・`opencode.json`・`.claude/pr-review.yml` など）を `git grep` で洗って直す
3. 分ける前後の `wc -lm`（毎回読み込まれるファイルの合計）を PR 本文に書く
4. 計画書の進行記録に「孫7 の検証済み（Figma の有効化の1行を同乗させてよい）」と書かれていて、このリポが
   pixidex・sheaf・iosci のどれかなら、計画書 設計3.2 の1行を `.claude/settings.json` に足す。書かれていなければ足さない
5. PR とは別に、計画書 設計4.3 に従って、このリポの `MEMORY.md`（このセッションのシステムプロンプトに書かれた memory の
   ディレクトリ）を、方針文書の作法（設計4.2）で整える。触る前に複製を取り、記憶を消さない
6. このリポ自身の AGENTS.md 等の規約（ブランチ名・PR の作法・コミット前の手順・DOC-ID の運用）に従う

## 検証方針

- 分けた後の芯と詳細を合わせて、分ける前の `AGENTS.md` のルールが1つも失われていない（レビューで突き合わせる）
- 芯から詳細への参照、およびスキル・文書から移した節への参照が切れていない
- このリポのコミット前の手順（pre-commit・DOC-ID の検証など）が通る

文書の変更なので、新規テストは追加しない。

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は `main`（このリポの既定ブランチ）。**
   PR 本文に、傘の計画書（dotfiles の `docs/planning/` にあるこの計画書。DOC-ID で書く）と、
   孫1 の PR（dotfiles の PR。進行記録に番号がある）へのリンクを書く（複数リポにまたがる作業の継ぎ目）。
   dotfiles は公開リポなので、逆向き（dotfiles 側）にこのリポの中身は書かれない
2. /pr-review-loop を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** base が既定ブランチなので、マージは人間の仕事である。
   人間に「承認済みです。マージしてください」と依頼して止まる
なお `/pr-review-loop` は、レビューを依頼した直後の区切りで文脈が大きければ `ocw self-compact` で
自分を compact する。compact の後は、復帰メモに従ってレビュー待ちに戻り、この流れを最後まで続けること
実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## 大きい出力を文脈へ流し込まない（実装中ずっと）

- ファイルを丸ごと読まず、`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む
- 約100行・5,000字を超えそうな出力は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る
- 既存の長いファイルを丸ごと書き直さず、Edit の差分で直す

## ブランチ作成時の注意（最重要）

作業ブランチは傘ブランチではなく、**このリポの既定ブランチ（origin/main）から切られている。**
ocw が既に作業ブランチを作って checkout 済みなので、git fetch origin と git log --oneline -1 origin/main で、
作業ブランチが既定ブランチの先端を含んでいることだけを確認すればよい（git pull は使わない。
既定ブランチはメインワークツリーで checkout 済みのため、ここで git checkout しない）
````

## 孫2用プロンプト:

````markdown
# リポ: lora-dataset-forge
# 孫ブランチ: fc-02-agents-md-split

計画書 `/home/manemone/projects/dotfiles/fixed-context/docs/planning/DOC-2610150519_fixed-context_計画.md` の「## 孫2〜6用プロンプト（共通の本文）」のコードブロックの指示に従うこと。
このリポは copier で雛形を撒いていない（`.copier-answers.yml` が無い）。
````

## 孫3用プロンプト:

````markdown
# リポ: pixidex
# 孫ブランチ: fc-03-agents-md-split

計画書 `/home/manemone/projects/dotfiles/fixed-context/docs/planning/DOC-2610150519_fixed-context_計画.md` の「## 孫2〜6用プロンプト（共通の本文）」のコードブロックの指示に従うこと。
このリポは copier で雛形を撒いており、`copier update` できる（`_commit` あり）。Figma を使うリポである。
````

## 孫4用プロンプト:

````markdown
# リポ: modeldex
# 孫ブランチ: fc-04-agents-md-split

計画書 `/home/manemone/projects/dotfiles/fixed-context/docs/planning/DOC-2610150519_fixed-context_計画.md` の「## 孫2〜6用プロンプト（共通の本文）」のコードブロックの指示に従うこと。
このリポは copier で雛形を撒いており、`copier update` できる（`_commit` あり）。
````

## 孫5用プロンプト:

````markdown
# リポ: sheaf
# 孫ブランチ: fc-05-agents-md-split

計画書 `/home/manemone/projects/dotfiles/fixed-context/docs/planning/DOC-2610150519_fixed-context_計画.md` の「## 孫2〜6用プロンプト（共通の本文）」のコードブロックの指示に従うこと。
このリポは copier で雛形を撒いているが、`_commit` が無く `copier update` できない。Figma を使うリポである。
````

## 孫6用プロンプト:

````markdown
# リポ: iosci
# 孫ブランチ: fc-06-agents-md-split

計画書 `/home/manemone/projects/dotfiles/fixed-context/docs/planning/DOC-2610150519_fixed-context_計画.md` の「## 孫2〜6用プロンプト（共通の本文）」のコードブロックの指示に従うこと。
このリポは copier で雛形を撒いているが、`_commit` が無く `copier update` できない。Figma を使うリポである。
````

## 孫7用プロンプト:

````markdown
# 傘ブランチ: fixed-context
# 孫ブランチ: fc-07-figma-scope
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/fixed-context/docs/planning/DOC-2610150519_fixed-context_計画.md`

**まず計画書の「概要」「背景2」「背景4.3」「背景5」「設計3」「人間に確認すること」「決定的な制約」「進行記録」を読むこと。**
進行記録に、ユーザー全体で Figma を止める設定の置き場（背景5-2）についての人間の決定が書いてある。
**書かれていなければ作業を始めず、司令官のペインへ「背景5-2 の決定が計画書に無い」と報告して止まる。**

## 実装開始前の必須手順

`ocw` がすでに `fc-07-figma-scope` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/fixed-context` の
先端から切られていることを確かめる（`git pull` は使わない）。

## やること

1. 計画書 設計3.1 に従い、`figma@synced` に `enabledPlugins` の上書きが効くかを、実 `$HOME` を書き換えずに確かめる。
   確かめ方と結果を文書（`docs/reference/` か ADR。DOC-ID を採番）に残す。
   **効かなければ、設定を入れずに司令官のペインへ結果を報告して止まる**（PR は検証結果の文書だけで出してよい）
2. 効いたら、計画書 設計3.3 に従い、ユーザー全体で止める手順を `claude/README.md` に書く。人間の決定で置き場は
   `settings.machine.json`（このマシンだけ）なので、**配布物 `claude/settings.json` にも、実機の machine 設定にも
   書き込まない**（machine 設定の編集とデプロイは人間が行う）。machine 設定の `enabledPlugins` が生成される
   `~/.claude/settings.json` に正しくマージされるか（同じキーの深いマージになるか）は、`claude/deploy.sh` の生成の仕組みを
   読み、必要なら `HOME` を差し替えたサンドボックスで確かめて書く
3. リポ側で有効にする書き方（計画書 設計3.2）を、文書と `claude/README.md` に書く（他リポの変更はこの PR に含めない）
4. 実機で止めるのは3リポの有効化のマージ後、という順序（設計3.3）を `claude/README.md` か文書に書く
5. 検証結果（効いたか）を最終報告と司令官への報告に1行で入れる（司令官が進行記録に書き、孫3・5・6 に同乗させるか決める）

## 検証方針

- 設計3.1 の実測で、user で止めて project で戻せることが確かめられている（結果を文書に残す）
- machine 設定に書く `enabledPlugins` が、生成される `~/.claude/settings.json` に意図どおり入る（書いた手順が正しい）

文書だけの変更になる見込みなので、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --all-files
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `fixed-context` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** `/pr-review-loop` の手順にマージへ進む記述があっても実行しない
   （孫が人間のフィードバック前に勝手にマージするのを防ぐため。マージは傘の司令官が行う）
5. 最終報告を書き終えたら、最後の行動として、司令官が spawn の送信文で渡した司令官の Herdr ペインへ
   承認を報告する（渡されていなければ報告せず、人間に「承認済み。マージは司令官（または人間）が行う」と伝えて止まる）。
   送り方は umbrella-orchestrator スキル §5「AI間送信手順（二段構え）」に従う。本文は
   「孫7 `fc-07-figma-scope` の PR #<番号> が HEAD <短縮SHA> で承認されました。マージをお願いします。」
   だけにする。報告は1回だけ。送れなくても再送せず、送れなかったことを人間に1行伝えて止まる

なお `/pr-review-loop` は、レビューを依頼した直後の区切りで文脈が大きければ `ocw self-compact` で
自分を compact する（その手順は pr-review-loop 側。使えなければ何もしない）。compact の後は、
復帰メモに従ってレビュー待ちに戻り、この「実装完了後の流れ」を最後まで続けること。
実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。
傘ブランチが先へ進んでコンフリクトしたら `git rebase origin/fixed-context` と
`git push --force-with-lease` で追随する（AGENTS.md「最重要ルール」）。

## 大きい出力を文脈へ流し込まない（実装中ずっと）

- ファイルを丸ごと読まず、`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む
- 約100行・5,000字を超えそうな出力は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る
- 既存の長いファイルを丸ごと書き直さず、Edit の差分で直す

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `fixed-context` から切ること**。master から切ると PR の diff に傘ブランチ全体が
混入してレビュー不能になる。`ocw` が `origin/fixed-context` から切ったワークツリーを用意済みなので、
上の「実装開始前の必須手順」で確かめるだけでよい（`git pull` は使わない）。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````
