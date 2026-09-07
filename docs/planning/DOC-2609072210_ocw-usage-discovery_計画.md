# 計画書: AI が `ocw` の使い方を安く知れるようにする

傘ブランチ: `ocw-usage-discovery`
ターゲット: `master`

## 概要

**他プロジェクトで作業している AI が `ocw` の使い方を調べるとき、`bin/ocw` の実体
（44,642 B / 約12k トークン）を読み込むのをやめさせる。**

現状の問題は「ドキュメントが無いこと」ではない。`ocw help` は既に存在し、出力は
1,164 B（約 300 トークン）と十分に安い。問題は次の2点である。

1. **誘導**: AI は「`ocw help` を叩けばよい」と知らないので、実体か `bin/README.md` を読みに行く
2. **網羅性**: 叩いても答えが載っていないので、結局そのあと実体を読む

したがって打つ手は2つ。**`ocw help <topic>` を階層化して一次情報源にする**（網羅性）と、
**`skills/ocw/` を新設して AI に存在を気づかせる**（誘導）である。片方だけでは効かない
（階層 help だけ → 存在を知らなければ叩かない。skill だけ → SKILL.md が肥大化し同期ズレの
管理対象が増える）。

### 実測値（相談時に計測済み。コミット `79754ea` 時点）

| 読むもの | サイズ | 概算トークン |
|---|---|---|
| `bin/ocw` 実体（現在 1,519行） | 44,642 B | 約 12k |
| `bin/README.md`（3ツール分・756行） | 61,180 B | 約 20k 以上（日本語主体） |
| `ocw help` の出力 | 1,164 B（計測時点は 841 B） | 約 300 |
| `ocw-meter help` の出力（263行） | 14,449 B | 約 4.5k |

**実体が太ることのコストは発生しない。** そもそも実体を読ませないことが目的だからである。
help テキストを 300行ほど足して実体が 1,800行になっても、狙いどおりなら誰も読まない。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `ocw-usage-01-help-topics` | `ocw help <topic>` の階層化（`bin/ocw` 本体・`bin/tests/test_ocw.py`） | ⬜ 待機中 |
| 2 | `ocw-usage-02-skill-and-readme` | `skills/ocw/` 新設と参照の整理（`skills/README.md`・`bin/README.md`・ルート `README.md`） | ⬜ 待機中 |

## 依存関係と実行順序

```
孫1 (bin/ocw に help topic を実装。topic 名・分割・実際の出力がここで確定する)
  ↓ 実物が無いと「何を README から削れるか」「SKILL.md に何を書くか」が決まらない
孫2 (skills/ocw/SKILL.md 新設 + bin/README.md の重複削除 + ルート README 確認)
```

**直列。** 触るファイルは重ならないので技術的には並列も可能だが、孫2 の仕事は
**「孫1 が実際に help へ入れた内容」を実物で確認したうえで、その重複を README から削る**
ことである。孫1 のレビューで topic 名や収録範囲が変われば、並列に走っていた孫2 の削除は
過剰または不足になる。DOC-2609031400 の孫2（文書）が孫1 のマージ後に走ったのと同じ理由。

### なぜ3本ではなく2本か

ブリーフの叩き台は「help 階層化 / skill 新設 / README 整理」の3本だった。後2者を1本に
統合する。**「help を一次情報源とし、README と SKILL.md はそこへどう譲るか」は1つの設計
判断であり、2つの PR に割ると両者の線引きが食い違う**（README が消した記述を SKILL.md が
拾い直す、あるいは両方から落ちる）。どちらも純粋な文書変更で分量も小さいため、1本で
レビューできる。

---

## 確定事項（孫の判断で覆さないこと）

### 情報の一次情報源（三重管理を作らないための正典）

| 情報の種類 | 一次情報源 | 他の場所での扱い |
|---|---|---|
| コマンド構文・オプション一覧 | `usage()`（= `ocw help` 引数なし） | README は再掲しない |
| **挙動の事実**（設定キー・プレースホルダ・解決規則・マージ判定の意味論・環境変数・ペイン構成・run_id 連携） | **`ocw help <topic>`** | README は `ocw help <topic>` を指すだけ。SKILL.md は答えを書かない |
| **なぜそうなっているか**（設計判断・却下案・実測の根拠） | ADR DOC-2608062258 と各計画書 | README は要約とリンクのみ |
| インストール・前提・環境構築の失敗と対処 | `bin/README.md` | help には書かない |
| **存在の告知と誘導** | `skills/ocw/SKILL.md` | 挙動の事実は一切書かない |

**「実行中に遭遇する失敗」と「環境構築の失敗」の線引き**: `ocw` が出す `die` メッセージの
意味と対処（例: `branch is not merged into any known integration ref`）は**help 側**。
`which ocw` が何も返さない・`code` が見つからないといったセットアップ由来のものは
**README 側**。前者は他プロジェクトで作業中の AI が遭遇し、後者は人間が初回に遭遇する。

### topic 分割

| topic | 答える問い |
|---|---|
| `config` | ワークツリーはどこに作られるか。`git config ocw.*` の4キー、`ocw.worktreeDir` のプレースホルダと `die` 条件、掃除境界、レイアウトの実例、`repo_name` の解決順 |
| `naming` | 入力した名前がどうブランチ名・ディレクトリ名になるか。正規化 → 検証（`git check-ref-format`）、`/` の温存、ネスト方針、`ai/` 接頭辞は付かないこと |
| `rm` | `ocw rm` は何を消すか。入力の解決規則3段と曖昧時の停止、マージ済み判定の意味論（基準 ref 候補・is-ancestor・squash 検出・`githubMergeCheck`）、検出できない限界と `-f` |
| `herdr` | `-H` / `--no-commander` のペイン構成、各ペインの起動コマンド、`OCW_ROLE`、ワークスペースラベルの既定書式 |
| `meter` | `ocw-meter` 連携。`run_id` の発行と `ocw-run-id` ファイル、`OCW_RUN_ID` の伝搬と手動 export、fail-open の範囲、`run.end` が記録されない場合 |
| `env` | `ocw` が読む環境変数の一覧（`OCW_COMMANDER_COMMAND` / `OCW_IMPLEMENTER_COMMAND` / `OCW_REVIEWER_COMMAND` / `OCW_NO_VSCODE`）と、`ocw` が**設定する**もの（`OCW_ROLE` / `OCW_RUN_ID`） |

`env` を独立させたのは、`OCW_NO_VSCODE` が他のどの topic にも綺麗に収まらないためである
（`-H` の話でもマージ判定の話でもない）。かつ、**`ocw` をスクリプトから自動実行する AI が
最初に必要とするのがまさにこの変数**（VS Code を勝手に起動させない）なので、独立した
見出しで見つかるほうがよい。

### help の呼び出し規約

| 呼び出し | 挙動 | 終了コード |
|---|---|---|
| `ocw help` / `ocw -h` / `ocw --help` | 現行の `usage()` 出力 + 末尾に `topics:` 節（topic 名と1行説明の目次） | 0 |
| `ocw help <topic>` / `ocw --help <topic>` | その topic の本文のみ | 0 |
| `ocw help all` | 全 topic を連結して出力 | 0 |
| `ocw help <未知>` | `die`。標準エラーに「不明な topic」と**有効な topic 一覧**を出す | 1 |
| `ocw help <topic> <余分な引数>` | `die` | 1 |

- **`ocw help` の出力は 2 KB を超えさせない。** 追加するのは `topics:` 節だけである。
  代わりに現行 `usage()` の `environment:` 節は削除し、`ocw help env` を指す1行に置き換える
  （目次を短く保つ要件と、環境変数の一次情報源を1箇所にする要件の両方を満たす）
- **`ocw help` は git リポジトリの外でも動く。** `init_repo_context` を通さない
  （現行もそうなっている。dispatch を触るときに壊さないこと）
- `-h` / `--help` に topic を渡せるのは `help` と揃えるため。分岐を増やさない

### 実装の作法

- **help テキストは `bin/ocw` の実体に埋め込む。外部ファイル化しない。** 配布実体の
  パス解決（`DOTFILES_DEPLOY_SRC` / `current`）に依存させると壊れやすく、実体に埋め込めば
  **同期ズレが原理的にゼロ**になる
- topic ごとに `help_topic_<name>()` 関数を定義し、**`case` 文でディスパッチする。**
  動的な変数名参照や `eval` を使わない（AGENTS.md の linter 抑制禁止と、
  「コードの構造を変えて指摘そのものを解消する」方針に従う）
- **すべての help テキストを `usage()` に隣接させて連続配置する。** 実装コードの間に
  散らさない。スクロール量が増えるより、同期ズレのほうが高くつく
- ヒアドキュメントの終端は `<<'TOPIC'` のようにクオートし、`$` や `` ` `` の展開を止める
- **実体への増分は 350行以内を目安とする。** 超えるなら内容を削る。外部ファイル化への
  逃げは禁止

### 内容の作り方

- **`bin/README.md` から機械的に転記しない。** README の記述は計測時点のものであり、
  実装が先に進んでいる箇所がある（実例: `--no-commander` はブリーフ作成時点で
  「usage にも README にも無い」とされていたが、PR #68 で既に両方へ入っている）。
  **必ず `bin/ocw` の実装を読んで裏を取る**
- 実装と README が食い違っていたら、**実装を正として help を書き、食い違いを PR 説明に
  列挙する**（README の修正は孫2 の担当。孫1 で直さない）
- 英語で書く。現行 `usage()` が英語であり、途中から日本語が混ざる形にしない

### スコープ外

- **`ocw-meter` の help 階層化。** 同じ問題（263行の一枚岩 usage、約 4.5k トークン）を
  抱えているが、人間が確定させた想定場面は `ocw` である。**将来課題として本節に記録する
  に留め、今回の孫には含めない**
- `bin/claude-ds`（35行。問題が無い）
- `claude/CLAUDE.md`（配布物。指示が無い限り編集しない）
- 既存の `ai/*` ブランチの改名

### 検討して却下した案（蒸し返さないこと）

- **`bin/README.md` を充実させる** → `bin/README.md` は `$HOME` に配布されない
  （`shared/helpers.sh` の `links_for_tool()` が配るのは `bin/ocw` の実体だけ）。
  他プロジェクトで作業している AI からは**見えない**。想定場面に一切効かない
- **help テキストを別ファイルに切り出して `ocw` が `cat` する** → 配布実体のパス解決に
  依存し、`current` の付け替えやツール単体実行で壊れる。実体に埋め込めば同期ズレはゼロ
- **SKILL.md に使い方そのものを書く** → SKILL.md が肥大化し、`ocw` を直す人が
  SKILL.md も直さねばならなくなる。腐る場所を増やすだけ
- **`ocw help` を短い目次だけに置き換える（現行 usage を捨てる）** → `ocw --help` で
  構文が読めなくなる無警告の劣化。目次は既存 usage の**末尾に足す**
- **`--help-config` のようなフラグ形式** → topic が増えるたびにフラグが増える。
  `help <topic>` なら dispatch が1箇所で済む
- **未知 topic で黙って usage を出す** → 打ち間違いを握り潰す。未知プレースホルダを
  `die` させている既存方針（ADR DOC-2608062258 §3.4）と揃えて `die` する

### 将来課題（今回やらない）

- **`ocw-meter help` の階層化。** 263行・14,449 B・約 4.5k トークンの一枚岩 usage。
  `ocw` と同じ構造の問題を抱えている。本傘で確立した `help <topic>` の作法をそのまま
  適用できるはずだが、想定場面（他プロジェクトでの利用）で `ocw-meter` を叩く頻度は
  `ocw` より低いため後回しとする

---

## `skills/ocw/` の設計（孫2 の正典）

### なぜ skill が要るのか

AI は `ocw help` の存在を知らない。skill の `description` は**エージェントが起動時に
読む索引**であり、ここに「ocw の使い方は `ocw help` で引ける」と書いてあることが唯一の
誘導経路である。**SKILL.md 本文の価値は「答え」ではなく「どこに答えがあるか」にある。**

### 制約

- **SKILL.md は 80行 / 4 KB を超えさせない。** 超えたら、答えを書き始めている証拠
- **挙動の事実を一切書かない。** 設定キー名・プレースホルダ・解決規則・マージ判定は
  すべて `ocw help <topic>` 側にある。SKILL.md はそこへ送るだけ
- **「`bin/ocw` の実体や `bin/README.md` を読まないこと」を明示する。** これが本傘の目的
  そのものである。README は配布されないので他プロジェクトからは読めない旨も書く
- topic の一覧は**名前と「答える問い」だけ**を載せる。答えは載せない。
  **正確な一覧の一次情報源は `ocw help` の `topics:` 節**であり、SKILL.md はその写しである
  ことを本文に明記する（topic が増えたとき SKILL.md が古くなっても、
  「`ocw help` を叩け」という誘導は生き続け、間違った答えにはならない）
- `name: ocw`。`description` には AI が引っかかる語を入れる:
  git worktree の作成・削除、ワークツリー、Herdr 連携、`ocw` コマンド、
  **「使い方は `ocw help <topic>` を叩く」**

### `bin/README.md` の整理方針

上の一次情報源テーブルに従い、**挙動の事実の再掲を削って `ocw help <topic>` への
ポインタに置き換える。** 削るのは「同じ事実がもう help にある」部分だけであり、
次のものは README に残す。

- `ocw` が何であるかの導入と代表的な使用例
- **なぜそうなっているか**（設計背景・ADR / 計画書へのリンク）。help には書かない
- レイアウト選択時の運用上の注意（例: `{repo_root}/.worktrees/{name}` を使うなら
  `.gitignore` に足せ、という判断材料）
- インストール・前提・環境構築のトラブルシューティング
- `claude-ds` / `ocw-meter` の節（今回触らない）

**ルート `README.md` は二層構造ルール（AGENTS.md）に従って確認する。** `ocw` の1行紹介と
ディレクトリツリーのコメントが実態と合っているかを見て、ズレていれば直す。
合っていれば変更しない（無理に触らない）。

---

## ワークスペースラベル

| 対象 | ラベル |
|---|---|
| 傘（司令官） | `dotfiles :: ocwの使い方を安く知る` |
| 孫1 | `dotfiles :: ocwの使い方を安く知る 孫1 help階層化` |
| 孫2 | `dotfiles :: ocwの使い方を安く知る 孫2 skill入口とREADME整理` |

---

## 検証（全孫共通・省略不可）

AGENTS.md「コミット前の必須ステップ」に従う。

```bash
pre-commit run --all-files
bin/tests/lint.sh                                  # bin/ を触る孫
python3 -m unittest discover -s bin/tests -v       # bin/ を触る孫（193件・約40秒）
tests/deploy_smoke.sh                              # skills/ にディレクトリを足す孫
```

**実オペレーションの deploy（素の `./deploy-all.sh`）は禁止。** 動作確認は
`./deploy-all.sh --dry-run` か `tests/deploy_smoke.sh`（`HOME` を一時ディレクトリへ
差し替えたサンドボックス）で行う。

---

## 孫1用プロンプト:

````
`bin/ocw` の `help` を topic 別に階層化してください。

## 背景（これを理解してから書くこと）

他プロジェクトで作業している AI が `ocw` の使い方を調べるとき、`bin/ocw` の実体
（44 KB / 約12k トークン）を読み込んでいる。`ocw help` は既にあり出力は約 300 トークンと
安いが、**知りたいことが載っていないので結局そのあと実体を読まれている。**

**この孫のゴールは「`ocw help <topic>` を叩けば実体を読む必要が無くなる」状態にすること。**
実体が 300行太ることは許容される（狙いどおりなら誰も実体を読まないため）。

計画書: docs/planning/DOC-2609072210_ocw-usage-discovery_計画.md
「確定事項」節を必ず読むこと。以下はその抜粋であり、食い違ったら計画書が正典。

## 実装する topic（6つ）

| topic | 答える問い |
|---|---|
| `config` | ワークツリーはどこに作られるか。`git config ocw.*` の4キー、`ocw.worktreeDir` のプレースホルダと `die` 条件、掃除境界、レイアウトの実例、`repo_name` の解決順 |
| `naming` | 入力した名前がどうブランチ名・ディレクトリ名になるか。正規化 → 検証（`git check-ref-format`）、`/` の温存、ネスト方針、`ai/` 接頭辞は付かないこと |
| `rm` | `ocw rm` は何を消すか。入力の解決規則3段と曖昧時の停止、マージ済み判定の意味論（基準 ref の候補・is-ancestor・squash 検出・`githubMergeCheck`）、検出できない限界と `-f` |
| `herdr` | `-H` / `--no-commander` のペイン構成、各ペインの起動コマンド、`OCW_ROLE`、ワークスペースラベルの既定書式 |
| `meter` | `ocw-meter` 連携。`run_id` の発行と `ocw-run-id` ファイル、`OCW_RUN_ID` の伝搬と手動 export、fail-open の範囲、`run.end` が記録されない場合 |
| `env` | `ocw` が読む環境変数（`OCW_COMMANDER_COMMAND` / `OCW_IMPLEMENTER_COMMAND` / `OCW_REVIEWER_COMMAND` / `OCW_NO_VSCODE`）と、`ocw` が設定するもの（`OCW_ROLE` / `OCW_RUN_ID`） |

## 呼び出し規約

| 呼び出し | 挙動 | 終了コード |
|---|---|---|
| `ocw help` / `-h` / `--help` | 現行 `usage()` の出力 + 末尾に `topics:` 節（topic 名と1行説明） | 0 |
| `ocw help <topic>` / `--help <topic>` | その topic の本文のみ | 0 |
| `ocw help all` | 全 topic を連結 | 0 |
| `ocw help <未知>` | `die`。標準エラーへ「不明な topic」+ 有効な topic 一覧 | 1 |
| `ocw help <topic> <余分な引数>` | `die` | 1 |

## 制約（守らないと成果物が無意味になる）

- **help テキストは `bin/ocw` の実体に埋め込む。外部ファイル化しない。** 別ファイルを
  `cat` する形にすると配布実体のパス解決（`DOTFILES_DEPLOY_SRC` / `current`）に依存して
  壊れる。実体に埋め込めば同期ズレが原理的にゼロになる。
- topic ごとに `help_topic_<name>()` を定義し、**`case` 文でディスパッチする。**
  動的変数名参照や `eval` は使わない。
- **すべての help テキストを `usage()` に隣接させて連続配置する。** 実装コードの間に
  散らさない。
- ヒアドキュメントの終端はクオートする（`<<'TOPIC'`）。
- **`ocw help` の出力は 2 KB を超えさせない。** そのために現行 `usage()` の
  `environment:` 節は削除し、`ocw help env` を指す1行に置き換える。
- **`ocw help` は git リポジトリの外でも動く**（`init_repo_context` を通さない）。
  現行もそうなっている。dispatch を触るときに壊さないこと。
- **実体への増分は 350行以内を目安。** 超えるなら内容を削る。
- 英語で書く（現行 `usage()` が英語のため）。

## 内容の作り方（最重要）

- **`bin/README.md` から機械的に転記しない。** README は計測時点のもので、実装が
  先に進んでいる箇所がある（実例: `--no-commander` は「README にも usage にも無い」と
  引き継がれていたが、PR #68 で既に両方に入っている）。**必ず `bin/ocw` の実装を読んで
  裏を取ること。**
- **実装と README が食い違っていたら、実装を正として help を書き、食い違いを PR 説明に
  列挙する。** README の修正は孫2 の担当なので、この孫では `bin/README.md` を触らない。
- `ocw` が出す `die` メッセージのうち、利用者が実行中に遭遇するもの
  （例: `branch is not merged into any known integration ref`、`unknown placeholder`、
  曖昧一致による停止）は、**意味と対処を該当 topic に書く。** これが「実体を読まずに
  済む」ことの実質である。

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。テストは `bin/tests/test_ocw.py` に追加する。

- **`ocw help` が広告する topic と、実際にディスパッチできる topic が一致すること。**
  目次に載っているのに引けない topic、引けるのに目次に無い topic が生まれないこと。
  **この regression は必ず自動テストで固定する**（目次と実装のズレは、まさに本傘が
  潰そうとしている「調べても答えが出ない」状態を再生産する）。
- **`ocw help` および `ocw help <topic>` が git リポジトリの外でも成功すること。**
  **この regression は必ず自動テストで固定する**（他プロジェクトの AI が任意の
  ディレクトリから叩く前提が崩れると、この機能は存在しないのと同じになる）。
- 未知 topic および余分な引数が非ゼロ終了し、標準エラーに有効な topic 一覧が出ること。
- `ocw help` 引数なしが従来どおりコマンド構文（synopsis）を含むこと。
- help の実行がワークツリーを作らず、`ocw-meter` イベントも出さないこと。

各項目と test example を1対1対応させる必要はない。複数の条件を1つの scenario で
検証してよい。既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行する検証コマンド

```bash
pre-commit run --all-files
bin/tests/lint.sh
python3 -m unittest discover -s bin/tests -v
```

`shellcheck` / `shfmt` の指摘を抑制ディレクティブ（`# shellcheck disable=...`）で
黙らせないこと。構造を変えて解消するか、解消できなければ理由とともに報告する。

## 実装完了後の流れ（必須）
実装が完了したら、以下を**自律的に**実行してください:
1. PRを作成する。**PRの向き先は必ず `ocw-usage-discovery` にすること。master には絶対に出さない。**
2. /pr-review-loop を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する
実装が終わったタイミングで止まらず、必ずここまでやりきってください。

## ブランチ作成時の注意（最重要）
作業ブランチは**必ず `ocw-usage-discovery` から切ること**。
master から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:
git checkout ocw-usage-discovery && git pull --rebase origin ocw-usage-discovery
git checkout -b ocw-usage-01-help-topics
````

## 孫2用プロンプト:

````
`skills/ocw/` を新設し、`bin/README.md` とルート `README.md` の参照関係を整理してください。

## 背景（これを理解してから書くこと）

孫1（マージ済み）で `ocw help <topic>` が階層化され、`ocw` の挙動の事実は
**すべて `ocw help` から引ける**ようになった。この孫の仕事は2つ。

1. **誘導**: AI は `ocw help` の存在を知らないので、実体（44 KB / 約12k トークン）を
   読みに行ってしまう。`skills/ocw/` を新設して気づかせる。
2. **重複の解消**: 同じ事実が `ocw help` と `bin/README.md` の両方にある状態を放置すると、
   次に `ocw` を直す人が両方を更新できずに必ず腐る。

**まず `ocw help all` を実際に叩いて、何が help に入ったかを目で確認すること。**
孫1 のレビューで内容が変わっている可能性がある。

計画書: docs/planning/DOC-2609072210_ocw-usage-discovery_計画.md
「確定事項」と「`skills/ocw/` の設計」の両節を必ず読むこと。食い違ったら計画書が正典。

## 一次情報源のテーブル（これが正典）

| 情報の種類 | 一次情報源 | 他の場所での扱い |
|---|---|---|
| コマンド構文・オプション一覧 | `usage()`（= `ocw help`） | README は再掲しない |
| **挙動の事実**（設定キー・プレースホルダ・解決規則・マージ判定・環境変数・ペイン構成・run_id 連携） | **`ocw help <topic>`** | README は `ocw help <topic>` を指すだけ。SKILL.md は答えを書かない |
| **なぜそうなっているか**（設計判断・却下案・実測の根拠） | ADR DOC-2608062258 と各計画書 | README は要約とリンクのみ |
| インストール・前提・環境構築の失敗と対処 | `bin/README.md` | help には書かない |
| **存在の告知と誘導** | `skills/ocw/SKILL.md` | 挙動の事実は一切書かない |

「実行中に遭遇する失敗」（`ocw` の `die` メッセージ）は help 側、「環境構築の失敗」
（`which ocw` が何も返さない等）は README 側、という線引きである。

## やること1: `skills/ocw/SKILL.md` の新設

- **80行 / 4 KB を超えさせない。** 超えたら答えを書き始めている証拠。
- `name: ocw`。`description` には AI が引っかかる語を入れる: git worktree の作成・削除、
  ワークツリー、Herdr 連携、`ocw` コマンド、**「使い方は `ocw help <topic>` を叩く」**。
  `description` はエージェントが起動時に読む索引であり、**ここが唯一の誘導経路**である。
- 本文に書くこと:
  - `ocw` が何か（2〜3行）
  - topic の一覧（**名前と「答える問い」だけ。答えは書かない**）
  - **正確な topic 一覧の一次情報源は `ocw help` の `topics:` 節**であり、
    SKILL.md のそれは写しであると明記する
  - **`bin/ocw` の実体や `bin/README.md` を読まないこと**を明示する。
    `bin/README.md` は `$HOME` に配布されない（`shared/helpers.sh` の `links_for_tool()`
    が配るのは `bin/ocw` の実体だけ）ので、他プロジェクトからはそもそも読めない
- **挙動の事実を一切書かない。** 設定キー名・プレースホルダ・解決規則・マージ判定は
  すべて `ocw help <topic>` にある。
- 既存の `skills/pr-review-loop/SKILL.md` と `skills/umbrella-orchestrator/SKILL.md` の
  frontmatter 書式に揃えること。
- `skills/README.md` の Skill 一覧テーブルに1行足す。
- **`skills/deploy.sh` は変更不要**（ディレクトリを自動検出する。AGENTS.md「実装時の注意」）。
  変更が要ると感じたら、それは設計を誤解しているので手を止めて報告すること。

## やること2: `bin/README.md` の整理

**挙動の事実の再掲を削り、`ocw help <topic>` へのポインタに置き換える。**
削ってよいのは「同じ事実がもう help にある」部分だけ。次は README に残す。

- `ocw` が何であるかの導入と代表的な使用例
- **なぜそうなっているか**（設計背景・ADR / 計画書へのリンク）。help には書かない
- レイアウト選択時の運用上の注意（例: `{repo_root}/.worktrees/{name}` を使うなら
  `.gitignore` に足せ、という判断材料）
- インストール・前提・環境構築のトラブルシューティング
- `claude-ds` / `ocw-meter` の節（**今回触らない**）

**孫1 の PR 説明に「実装と README の食い違い」が列挙されている場合、この孫で直す。**
`gh pr view <孫1のPR番号>` で確認すること。

## やること3: ルート `README.md` の確認

AGENTS.md の二層構造ルール（ルート README は全体、各ツール README は詳細。片方だけ
更新しない）に従い、`ocw` の1行紹介とディレクトリツリーのコメントが実態と合っているかを
確認する。ズレていれば直す。**合っていれば変更しない**（無理に触らない）。

## 検証方針

以下の重要な behavior / regression risk が保護されていること。

- `skills/ocw/` が全エージェント（Claude Code / Codex / OpenCode）へ配布されること。
  既存の `skills/deploy.sh` の自動検出で満たされるはずであり、**新規テストは追加しない。**
  `tests/deploy_smoke.sh` が既定対象に `skills` を含むので、それで確認する
- `bin/README.md` から削除した記述が、**`ocw help` 側に実在すること**（削っただけで
  どこにも無い、という状態を作らない）。これは `ocw help all` の出力との突き合わせで
  人力確認する
- SKILL.md / README のリンク切れが無いこと（`./tools/doc-id/doc-id verify` が
  pre-commit で走る）

自動テストの新規追加は不要である。文書変更であり、既存の deploy_smoke と doc-id の
フックで必要な保護は足りている。

## 実行する検証コマンド

```bash
pre-commit run --all-files
tests/deploy_smoke.sh
ocw help all    # README から削った記述が help 側に実在することの突き合わせ
```

`tests/deploy_smoke.sh` は `HOME` を一時ディレクトリへ差し替えたサンドボックスで動く。
**素の `./deploy-all.sh` を実オペレーションで実行しないこと**（AGENTS.md 最重要ルール）。

## 実装完了後の流れ（必須）
実装が完了したら、以下を**自律的に**実行してください:
1. PRを作成する。**PRの向き先は必ず `ocw-usage-discovery` にすること。master には絶対に出さない。**
2. /pr-review-loop を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する
実装が終わったタイミングで止まらず、必ずここまでやりきってください。

## ブランチ作成時の注意（最重要）
作業ブランチは**必ず `ocw-usage-discovery` から切ること**。
master から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:
git checkout ocw-usage-discovery && git pull --rebase origin ocw-usage-discovery
git checkout -b ocw-usage-02-skill-and-readme
````
