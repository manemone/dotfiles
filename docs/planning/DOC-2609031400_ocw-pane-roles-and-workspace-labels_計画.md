# 計画書: `ocw -H` のペイン構成切り替えと Herdr ワークスペースラベルの日本語化

傘ブランチ: `ai/ocw-pane-roles`
ターゲット: `master`

## 概要

3つの要望をまとめて片付ける傘である。

1. **要望1（`bin/ocw`）**: `ocw -H` が常に commander/implementer/reviewer の3ペインを立てるのをやめ、
   **commander を省いた2ペイン（implementer/reviewer）でも起動できるようにする。**
   `umbrella-orchestrator` の `/spawn` が作る孫ワークスペースでは commander ペインが
   誰にも使われないまま放置され、メモリとサイドバーを食っている。
2. **要望2（`umbrella-orchestrator` スキル）**: Herdr ワークスペースのラベルが
   `<repo_name> :: <slug>`（例: `dotfiles :: ocw-pane-roles`）でサイドバーから内容を判別できない。
   **リポジトリ名はそのまま、作業内容部分を日本語にする。** `bin/ocw` 本体は変えず、
   スキル側が `ocw -H` 直後に `herdr workspace rename` を叩く形で実現する。
3. **要望3（`umbrella-orchestrator` スキル）**: ブランチ名・ワークスペース名に `ai/` 接頭辞を
   付ける方針をやめる。`bin/ocw` は DOC-2608062259 の孫2 で既に接頭辞を自動付与しなくなっており、
   **直すのはスキル文書側に残った前提・例示だけ**である。

要望1が `bin/ocw` の挙動変更、要望2・要望3が `claude/skills/umbrella-orchestrator/SKILL.md` の
文書変更で、綺麗に2本に割れる。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `ocw-pane-roles-01-no-commander` | `ocw -H` に commander 省略モードを追加（`bin/ocw` 本体・`bin/tests/test_ocw.py` に Herdr シムを新設・`bin/README.md`） | ⬜ 待機中 |
| 2 | `ocw-pane-roles-02-skill-docs` | `umbrella-orchestrator` SKILL.md の更新（孫 spawn を2ペインモードへ・ワークスペースラベルの日本語化・`ai/` 接頭辞前提の除去） | ⬜ 待機中 |

> **孫ブランチ名に `ai/` を付けていないのは要望3の方針の適用である。**
> 傘ブランチ `ai/ocw-pane-roles` 自体は、要望3を決める前に作られた既存ブランチなので
> **改名しない**（作業中の改名は進行中のファイル操作と競合する）。要望3は今後新規に作る
> ブランチ・ワークスペースへの方針であり、遡って適用しない。

## 依存関係と実行順序

```
孫1 (bin/ocw に --no-commander を実装 + テスト + bin/README.md)
  ↓ 実装されて初めて「実際のフラグ名と実際の挙動」が確定する
孫2 (SKILL.md をその実物に合わせて書き換える + ラベル + ai/ 接頭辞除去)
```

**直列。** 触るファイルは孫1（`bin/ocw` 系）と孫2（`SKILL.md`）で重ならないので技術的には
並列も可能だが、**孫2は「孫1が実際に実装したフラグ名と出力」を実物で確認してから書く**必要がある。
孫1のレビューでフラグ名や出力が変われば、並列に走っていた孫2の記述は黙って嘘になる。
DOC-2608062259 の孫4（文書）が孫1〜3のマージ後に走ったのと同じ理由である。

---

## ADR を書かない判断

DOC-2608062259 には対になる ADR（DOC-2608062258）があるが、**本傘では ADR を書かない。**

- ADR は `docs/README.md` の定義上「**実測・調査結果に基づいて確定した技術的決定**の記録」である。
  DOC-2608062258 は bare リポジトリでの `git rev-parse` の挙動・`check-ref-format` の判定・
  squash マージ検出のレシピなど、**使い捨てリポジトリでの実測がなければ決められない事項**を
  多数抱えていたため ADR が必要だった。
- 本傘の決定は「CLI にどう opt-in フラグを生やすか」「ラベル文字列をどの情報から作るか」という
  **インターフェースの取り決め**であり、新しい実測を根拠にしていない。既存コードの読解だけで
  決まる。
- 決定の分量も、下の「確定事項」表と「却下した案」節に収まる程度である。

**この判断自体が誤りだと人間が考えるなら、実装着手前に指摘してほしい。** 孫の判断で
勝手に ADR を起こすことはしない（`AGENTS.md`「指示された範囲外の機能を先回りして実装しない」）。

---

## 確定事項（孫の判断で覆さないこと）

| 領域 | 決定 | 根拠 |
|---|---|---|
| 切り替え方式 | **`--no-commander` フラグによる明示オプトイン**。`-H` の意味は変えない | 既定（`ocw -H`）の3ペインは無警告で壊さない、が要望1の前提条件 |
| フラグの否定形 | `--no-commander`（否定形を採用する） | 「既定から1つ差し引く」という意味がそのまま名前になる。将来 `--no-reviewer` が要るようになっても同じ形で足せる |
| 2ペイン時の root pane | **root pane を implementer にする**（commander を作ってから閉じるのではない） | 使わないペインを一瞬でも起動しない。エージェント（`claude`）を余計に1本起動しないことが要望1の目的そのもの |
| 2ペイン時の `OCW_ROLE` | root pane に渡すのは `OCW_ROLE=implementer` | `ocw-meter` の role 帰属（`bin/ocw-meter` が `OCW_ROLE` を読む）が commander に誤集計されるのを防ぐ |
| ペインの並び | 2ペインは左が implementer、右が reviewer（root pane を右に split する） | 3ペインから commander の列を抜いただけの見た目にする |
| `--no-commander` 単独指定 | `-H` を伴わない `create` での指定は **`die`**（黙って無視しない） | 打ち間違いを握り潰さない。未知プレースホルダを `die` させている既存方針（ADR DOC-2608062258 §3.4）と揃える |
| `ls` / `rm` での指定 | 既存の `-H` と同じく**黙って無視**する | `-H` が既にそう振る舞っており、そこだけ挙動を変える理由がない |
| 標準出力 | 2ペインモードでは `commander:` 行を**出さない**。`workspace:` / `implementer:` / `reviewer:` は従来どおり | 存在しないペインの ID 行を出さない。スキル側は `implementer:` 行を拾うので影響しない |
| `herdr:` 行 | **変更しない**（`true` / `false` のまま） | 既存の目視・スクリプトの読み取りを壊さない |
| ラベルの担当 | ラベルの日本語化は**スキル側の `herdr workspace rename`**。`bin/ocw` の既定ラベル生成は変えない | 先輩の明示指定。`bin/ocw` はリポジトリ非依存のツールで、計画書の日本語要約を知る立場にない |
| ラベルの区切り | **` :: ` を維持**する | `bin/ocw` の既定（`bin/ocw:702`）と、既に手で付けられている実ラベル（実測: `tanoken :: 退会承認機能の実装` 等）の両方に一致する。ブリーフィング中の `: ` は例示であって指定ではない |
| ラベルの上書き条件 | 司令官スペースの改名は **`:: ` の右側が非 ASCII を1文字も含まないとき（＝ `ocw` 既定の slug のまま）だけ**行う | 人間が既に付けた日本語ラベルを勝手に上書きしない |
| rename の失敗 | **警告して続行**する。spawn を止めない | ラベルは表示上の都合であり、実装フローを止める理由にならない |
| `ai/` 接頭辞 | スキル文書から**前提・例示ごと除去**する。`bin/ocw` は変更不要 | `bin/ocw` は DOC-2608062259 孫2 で既に接頭辞を付けない。文書だけが取り残されている |
| 既存の `ai/*` ブランチ | **遡って改名しない。** 傘 `ai/ocw-pane-roles` もそのまま | 進行中の作業との競合リスク。要望3 は新規作成分への方針 |

### 検討して却下した案（蒸し返さないこと）

- **`--roles implementer,reviewer` のような任意ロール指定** → 今欲しいのは2択だけ。任意指定に
  すると「順序」「命名」「未知ロール名の扱い」まで仕様を決める羽目になる。必要になってから足す
- **`--panes full|worker` のようなプリセット名** → `full` / `worker` が何を指すか名前から読めず、
  結局 README を引くことになる。`--no-commander` は名前だけで意味が閉じている
- **環境変数（`OCW_PANES=...`）での切り替え** → シェルに export したまま忘れると、次に手で叩いた
  `ocw -H` が黙って2ペインになる。既定を壊さない要件と相性が悪い
- **`-H` の既定を2ペインに変え、3ペインを `--with-commander` にする** → 既存ユーザーの
  `ocw -H` の意味が無警告で変わる。要望1が明示的に禁じている
- **commander ペインを作ってから閉じる** → `claude` を1本起動してしまい、目的（メモリ節約）を
  達成しない
- **`bin/ocw` 側で日本語ラベルを生成する** → 先輩の明示指定で却下。`bin/ocw` は計画書を知らない
- **ラベルを毎回無条件で rename する** → 人間が手で付けたラベルを踏み潰す

---

## ワークスペースラベルの設計（要望2の正典）

### 書式

```
<repo_name> :: <日本語の説明>
```

- 傘（司令官スペース）: `<repo_name> :: <傘の日本語要約>`
- 孫（実装ワークスペース）: `<repo_name> :: <傘の日本語要約> 孫N <孫の日本語要約>`

長さの目安は **傘の要約が全角12文字以内、孫の要約が全角16文字以内**。サイドバーは幅が
限られており、長いラベルは末尾が切れて判別できなくなる。

### 説明文の作り方（優先順）

1. **計画書に `## ワークスペースラベル` 節があれば、そこに書かれた文字列をそのまま使う。**
   司令官が要約を即興で作らないで済み、傘の中で表記が揺れない
2. 節が無い計画書（既存の計画書はすべてこれ）では機械的に導出する:
   - 傘の要約 = 計画書の H1 見出しから「計画書:」を除いて短縮したもの
   - 孫の要約 = 進捗テーブルの「内容」列を短縮したもの

### この傘自身のラベル

| 対象 | ラベル |
|---|---|
| 傘（司令官スペース） | `dotfiles :: ocwペイン構成とラベル` |
| 孫1 | `dotfiles :: ocwペイン構成とラベル 孫1 commander省略` |
| 孫2 | `dotfiles :: ocwペイン構成とラベル 孫2 スキル文書更新` |

### 改名の手順

`herdr workspace rename <workspace_id> <label>` が実在することは
`herdr workspace --help` の出力で確認済み。

- **孫**: `ocw -H --no-commander <孫ブランチ> <傘ブランチ>` の標準出力から `workspace:` 行の
  ID を拾い、その直後に rename する（プロンプト送信より前）
- **傘（司令官スペース）**: 司令官が自分のワークスペースを
  `herdr workspace list` から特定し、現在ラベルが**既定形のときだけ** rename する。
  既定形の判定は「` :: ` の右側に非 ASCII 文字が1つも含まれないこと」
- rename が失敗しても警告のみで続行する

---

## 全孫共通の注意（プロンプトにも再掲するが、ここが正）

### 1. `AGENTS.md` の最重要ルールに従う

- **人間の明示的指示がない限り `git merge` / `git pull` / `git reset --hard` / `git push --force` /
  `gh pr merge` を実行しない。**
- **deploy スクリプトを実オペレーションで実行しない。** 孫2 は `claude/` 配下を触るが、
  `claude/deploy.sh` を実行してはならない。`pre-commit` のフックが走らせる
  `./deploy-all.sh --dry-run` は従来どおりで構わない。
- **linter の抑制ディレクティブ（`# shellcheck disable=...` 等）を AI の判断で追加しない。**
  指摘が設計上不合理だと判断したら、抑制せず内容・対象・理由を人間に報告する。
  コードの構造を変えて指摘そのものを解消できるならそちらを優先する。
- **指示された範囲外の機能を先回りして実装しない。**
- **`claude/CLAUDE.md`（配布物。個人の口調設定が入っている）は編集しない。**
  本傘で触ってよいのは `claude/skills/umbrella-orchestrator/SKILL.md` だけである。

### 2. `bin/ocw` は bash（`#!/usr/bin/env bash`, `set -euo pipefail`）

- [docs/design/DOC-2608020715-a_シェルスクリプトコーディング方針.md](../design/DOC-2608020715-a_シェルスクリプトコーディング方針.md)
  に従う
- **macOS（BSD / bash 3.2）互換を壊さない。** 連想配列（`declare -A`）・`${var,,}`・`mapfile` /
  `readarray` は bash 4 以降であり**使えない**
- `set -e` 下で終了ステータス非0が正常系になる箇所は必ず `|| true` / `if` で受ける

### 3. テストは黒箱（既存方式を維持する）

`bin/tests/test_ocw.py` は tempdir に使い捨てリポジトリを作り、実 `bin/ocw` を subprocess で叩く方式。
**この方式を変えない。** また既存の2重の VS Code 誤起動防止（`_CODE_SHIM_DIR` と `OCW_NO_VSCODE`）を
**絶対に外さない**。過去に実際に VS Code のウィンドウが大量に開いた事故がある。

### 4. 検証（省略しない。省略してよいのは人間が明示的に指示した場合のみ）

```
pre-commit run --all-files
bin/tests/lint.sh
python3 -m unittest discover -s bin/tests -v
```

孫2 は `bin/` を変更しないため `python3 -m unittest ...` は必須ではないが、
`pre-commit run --all-files` は必ず通すこと（`doc-id check` / `verify` を含む）。

### 5. PR の作法

[docs/design/DOC-2608020715_プルリクエストの作法.md](../design/DOC-2608020715_プルリクエストの作法.md)
を PR 作成前に読むこと。**PR の向き先は必ず傘ブランチ `ai/ocw-pane-roles`。master には出さない。**

---

## 孫1用プロンプト:

````
`bin/ocw` の `-H`（Herdr モード）に、commander ペインを立てない2ペインモードを追加してください。

## 最初に読むもの（順番に）

1. リポジトリルートの `AGENTS.md`（最重要ルール）
2. `docs/planning/DOC-2609031400_ocw-pane-roles-and-workspace-labels_計画.md`
   （この計画書。「確定事項」と「全孫共通の注意」を必ず読む。ここが正典）
3. `docs/adr/DOC-2608062258_ocw-worktree-naming-and-layout.md`
   （直近の `ocw` 改修で確定した方式。命名・レイアウト・マージ判定の前提はここ）
4. `docs/design/DOC-2608020715-a_シェルスクリプトコーディング方針.md`
5. `bin/ocw`（1457行。全量読むこと）と `bin/tests/test_ocw.py`
6. `bin/README.md` の §3.1（`ocw`）と、環境変数・`ocw-meter` 連携の節

## この孫のスコープ

**`bin/ocw` のペイン構成切り替えと、そのテスト、`bin/README.md` の追随だけ。**
`claude/skills/umbrella-orchestrator/SKILL.md` は孫2の担当なので触らないこと。
Herdr ワークスペースのラベル文字列も孫2の担当であり、`bin/ocw` の既定ラベル生成
（`bin/ocw:702` の `workspace_label="${repo_name} :: ${slug}"`）は**変更しない**。

### 1. `--no-commander` フラグを追加する

`ocw -H --no-commander <name> [base-ref]` で、Herdr ワークスペースのペインが
implementer と reviewer の2つだけになるようにする。

現状の `setup_herdr_workspace()`（`bin/ocw:472`）は

- `herdr workspace create --env OCW_ROLE=commander` の `root_pane` を commander に固定
- そこから `herdr pane split --direction right` で implementer
- さらに split して reviewer

という組み立てになっている。2ペインモードでは **root pane をそのまま implementer にする**。
つまり `herdr workspace create` に渡す `--env OCW_ROLE=` を `implementer` にし、
`herdr pane rename` の名前も `implementer` にし、split は reviewer の1回だけにする。

**commander ペインを作ってから閉じる実装にしないこと。** `claude` を1本起動してしまい、
このフラグの目的（不要なエージェントを起動しない）を達成しない。

`OCW_ROLE` を正しく渡すのは表示上の問題ではない。`bin/ocw-meter` がこの環境変数から
role を帰属させている（`bin/ocw-meter:1068` 付近）ため、`commander` のまま渡すと
2ペインモードの実装作業の費用が全部 commander に計上される。

### 2. フラグの受け付け位置

既存の `-H` / `--herdr` は**2箇所**で解釈されている（`bin/ocw:1403` の cmd 前ループと、
`bin/ocw:1430` の `new` サブコマンド後ループ）。`--no-commander` も**同じ2箇所**で
受け付けること。以下がすべて等価になる:

```
ocw -H --no-commander foo
ocw --no-commander -H foo
ocw -H --no-commander new foo
ocw new -H --no-commander foo
```

現状の `while [ "${1:-}" = "-H" ] || [ "${1:-}" = "--herdr" ]; do` という形は
選択肢が増えると読みにくくなる。`case` を使ったループへ書き換えてよい
（`AGENTS.md` の linter 抑制禁止に照らしても、構造を変えて解消するのが正しい方向）。

### 3. `-H` を伴わない `--no-commander` はエラーにする

`ocw --no-commander foo`（Herdr モードでない）は**黙って無視せず `die` する。**
メッセージは「`--no-commander` は `-H` / `--herdr` と一緒に使う」旨が分かる文にすること。

ただし `ocw --no-commander ls` / `ocw --no-commander rm foo` のように **create 以外の
サブコマンドでは、既存の `-H` と同じく黙って無視される**（現状 `ocw -H ls` は `-H` を
無視して動く）。検証は create の経路に置くこと。そこだけ挙動を変える理由がない。

### 4. 標準出力

2ペインモードでは `commander:` 行を**出さない**。`workspace:` / `implementer:` / `reviewer:` は
従来どおり出す。`herdr:` 行（`true` / `false`）は**変更しない**。

### 5. usage() の更新

`usage()` の `create behavior:` に `--no-commander` を追記し、`examples:` にも1行足す。
`environment:` の `OCW_COMMANDER_COMMAND` が2ペインモードでは使われないことも書く。

### 6. ロールバック経路の確認

`setup_herdr_workspace()` が途中で失敗したときの `rollback_created_worktree()`
（`bin/ocw:617`）は、2ペインモードでも従来どおり「ワークスペースを閉じる → ワークツリーを
削除 → ブランチを削除」を完遂しなければならない。2ペインモードでは
`HERDR_SETUP_COMMANDER_PANE_ID` が空のままになる点に注意すること
（現状のロールバックはワークスペース ID しか見ていないが、実際にそうなっているか確認すること）。

## テストの土台を作る（この孫の主要な作業）

**現在 `bin/tests/test_ocw.py` には Herdr モードのテストが1件も無い。**
ファイル冒頭の docstring がその理由を「実 Herdr サーバーが要り、実ターミナルペインが
開いてしまうから」と説明している。この孫の変更は Herdr モード**のみ**に効くので、
このままでは自動テストで固定できない。

**`herdr` の偽コマンド（シム）を PATH に置く方式で解決すること。**
同じファイルに既にある `_CODE_SHIM_DIR`（`code` のシム）と
`write_git_shim_failing_absolute_git_dir()`（`git` の部分シム）と同じ作法である。

シムが応答する必要があるサブコマンドは、`bin/ocw` が実際に呼ぶものだけでよい:

- `herdr status server` — 終了ステータス0を返す（`herdr_server_running()` が見る）
- `herdr workspace create ...` — `workspace` / `root_pane` / `tab` を含む JSON
- `herdr pane split ...` — `pane` を含む JSON
- `herdr tab rename` / `herdr pane rename` / `herdr pane run` / `herdr workspace focus` /
  `herdr workspace close` — 終了ステータス0

**JSON の形は実物に合わせること。** 実 `herdr` の応答は
`{"id":"cli:workspace:list","result":{...}}` のように `result` の下にぶら下がる形をしている
（`herdr workspace list` で実測できる）。`bin/ocw` の `json_nested_field()` は
任意の深さを再帰的に探すので厳密な一致は不要だが、実物とかけ離れた形にすると
テストが実装の間違いを検出できなくなる。

シムは**呼ばれた引数を全部ログファイルへ追記**すること。「commander の起動コマンドが
1回も走っていない」「`--env OCW_ROLE=implementer` が渡っている」といった検証は
このログに対して行う。

`require_herdr_ready()` は `python3` も要求する。テストの PATH（`BASE_PATH_DIRS`）に
`python3` が居ることを確認すること（居なければ PATH に足す。実 `python3` を使ってよい）。

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 既定の `ocw -H <name>`（フラグなし）が、これまでどおり commander / implementer / reviewer の
  3ペインを作り、3つの pane 行を標準出力に出す。
  **この regression は必ず自動テストで固定する** — 「既存ユーザーの `-H` の挙動を無警告で
  壊さない」ことが本傘の前提条件そのものであり、ここが崩れたら変更全体が無効になる
- `--no-commander` を付けたときだけペインが2つになり、**commander の起動コマンドが
  1度も実行されない**
- 2ペインモードで root pane に渡る `OCW_ROLE` が `implementer` である
  （`ocw-meter` の役割別集計が commander に誤って寄らない）
- `-H` を伴わない `--no-commander` が、黙って無視されずに理由の分かるエラーで停止する
- フラグをどの位置に置いても（cmd の前 / `new` の後 / `-H` との前後）同じ結果になる
- Herdr セットアップが途中で失敗したとき、2ペインモードでもワークツリー・ブランチ・
  ワークスペースが残骸として残らない。
  **この regression は必ず自動テストで固定する** — ロールバックは実際にワークツリーと
  ブランチを削除する破壊的な処理であり、新しい分岐が入る以上「消し損ねる」「消しすぎる」の
  両方向を押さえておく必要がある
- 非 Herdr の既定モード（`-H` なし）、`ocw rm`、`ocw ls` の挙動が一切変わっていない
  （既存テストが無改変で通ることで示せていればよい）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## `bin/README.md` の更新

- §3.1 の使用例に `--no-commander` を追加する
- 「Herdr モードのペイン構成」の節に、既定の3ペインと `--no-commander` の2ペインの
  両方を書く
- `OCW_COMMANDER_COMMAND` の説明に、2ペインモードでは使われないことを書く
- `OCW_ROLE` の説明（226行目付近）に、2ペインモードでは root pane に `implementer` が
  渡ることを書く
- 冒頭の一覧（9行目付近）の「commander/implementer/reviewer の三面体制を自動セットアップ」が
  嘘になるので直す

ルート `README.md` は `ocw` をツリーの1行説明でしか扱っていないので、おそらく変更不要。
**ただし読んで確認すること**（嘘になっている記述があれば直す）。README は
「ルート = 全体像 / 各ツール = 詳細」の二層構造であり、片方だけ更新しない。

## 完了条件

- `pre-commit run --all-files` が通る
- `python3 -m unittest discover -s bin/tests -v` が全件通る（既存分 + 追加分）
- `bin/tests/lint.sh` が通る
- `bash -n bin/ocw` が通る
- `ocw --help` に `--no-commander` が載っている
- `bin/README.md` に実装と食い違う記述が残っていない

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:
1. PRを作成する。**PRの向き先は必ず `ai/ocw-pane-roles` にすること。master には絶対に出さない。**
2. /pr-review-loop を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する
実装が終わったタイミングで止まらず、必ずここまでやりきってください。

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `ai/ocw-pane-roles` から切ること**。
master から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:
git checkout ai/ocw-pane-roles && git pull --rebase origin ai/ocw-pane-roles
git checkout -b ocw-pane-roles-01-no-commander
````

## 孫2用プロンプト:

````
`claude/skills/umbrella-orchestrator/SKILL.md` を3点まとめて更新してください。
孫の spawn を2ペインモードへ、ワークスペースラベルを日本語へ、そして `ai/` 接頭辞の前提を除去。

## 最初に読むもの（順番に）

1. リポジトリルートの `AGENTS.md`（最重要ルール）
2. `docs/planning/DOC-2609031400_ocw-pane-roles-and-workspace-labels_計画.md`
   （この計画書。「確定事項」「ワークスペースラベルの設計」「全孫共通の注意」を必ず読む。ここが正典）
3. **孫1がマージ済みの `bin/ocw` の実装そのもの**と `bin/README.md`。
   文書は計画書ではなく**実装**に合わせること。食い違いがあれば実装を正とし、
   その食い違い自体を人間に報告する
4. `claude/skills/umbrella-orchestrator/SKILL.md`（793行。全量読むこと）

## この孫のスコープ

**`claude/skills/umbrella-orchestrator/SKILL.md` のみ。**
`bin/ocw` と `bin/tests/test_ocw.py` は変更しない（読んで確認するのが仕事）。
**`claude/CLAUDE.md` は絶対に触らない**（配布物であり、指示が無い限り編集しない）。
`claude/deploy.sh` を実行しないこと。

## 1. 孫の spawn を2ペインモードにする（要望1のスキル反映）

孫の実装ワークスペースには commander は要らない。孫1で入った `--no-commander` を使う形に
書き換える。**書き換える前に `ocw --help` を実際に叩いて、フラグ名と挙動を実物で確認すること。**

対象箇所（行番号は変更前のもの。全文を読んで漏れが無いか自分で確認すること）:

- §3.2「`/spawn`」の Herdr ありフロー: `ocw -H <孫ブランチ名> <傘ブランチ名>` の記述
- §3.5「`/autopilot`」の cron 本文 手順8: `ocw -H <次の孫ブランチ名> <傘ブランチ>`
- §5「ワークスペース階層（最重要）」の図: 孫ワークスペースが2ペインであることが分かる形にする。
  **傘（司令官）ワークスペースは3ペインのまま**である（`/finalize` で implementer と
  reviewer を使うため）
- §5「`ocw -H` が作るもの」: 3ペインの図しか無いので、**既定（3ペイン）と
  `--no-commander`（2ペイン）の両方**を書く。出力例（`workspace:` / `commander:` /
  `implementer:` / `reviewer:` の行）も、2ペインモードでは `commander:` 行が出ないことを書く
- §5「`/spawn` の Herdr ありフロー」の手順1

**§3.4「`/finalize`」は変更しないこと。** 司令官自身のワークスペースは3ペインが正しく、
手順2の「commander、implementer、reviewer の3ペーンが揃っていることを確認」はそのまま有効である。
むしろ「司令官スペースは素の `ocw -H`（3ペイン）で作る」ことを §5 に明記して、
孫スペースとの違いが読み取れるようにすること。

## 2. ワークスペースラベルを日本語にする（要望2）

サイドバーに `dotfiles :: ocw-pane-roles` のような slug が並んでも、どれが何の作業か
判別できない。`ocw -H` の直後に `herdr workspace rename` を叩いてラベルを日本語にする手順を
スキルへ組み込む。

**`herdr workspace rename <workspace_id> <label>` が実在することは確認済み**
（`herdr workspace --help` の出力）。書く前に自分でも一度確認すること。

書式・導出規則・上書き条件は、この計画書の「ワークスペースラベルの設計」節が正典である。
そこに書いてある内容を SKILL.md 側へ、司令官が読んで実行できる形で落とし込むこと。要点:

- 書式は `<repo_name> :: <日本語の説明>`。**区切りは ` :: ` を維持する**
  （`bin/ocw` の既定ラベルと、既に手で付けられている実ラベルの両方に一致する）
- 傘は `<repo_name> :: <傘の日本語要約>`、孫は
  `<repo_name> :: <傘の日本語要約> 孫N <孫の日本語要約>`
- 説明文は、計画書に `## ワークスペースラベル` 節があればそれをそのまま使う。
  無ければ H1 見出し（傘）と進捗テーブルの「内容」列（孫）から導出する
- 孫の rename は `ocw -H --no-commander ...` の出力の `workspace:` 行の ID に対して、
  **プロンプト送信より前**に行う
- 司令官スペースの rename は、現在ラベルが**既定形（` :: ` の右側に非 ASCII が1文字も
  含まれない）のときだけ**行う。人間が既に付けた日本語ラベルを踏み潰さない
- **rename に失敗しても警告のみで続行する。** spawn を止めない

書き足す先:

- §3.2「`/spawn`」の Herdr ありフローと §5「`/spawn` の Herdr ありフロー」に、
  rename の手順を1ステップとして追加する
- §3.5「`/autopilot`」の cron 本文 手順8 にも同じ rename を入れる
  （cron 経由でも孫が立つため、ここが漏れるとラベルが付かない孫が生まれる）
- §5 に「ワークスペースラベル」の小節を新設し、書式と導出規則を1箇所にまとめる。
  各所からはそこを参照させる（同じ規則を何箇所にも書き写さない）
- **司令官スペースの立ち上げ方**を §5 に明記する。司令官スペースは人間が素の `ocw -H` で
  作る想定なので、「素の `ocw -H`（3ペイン）で作り、司令官が起動後に自分のワークスペースを
  日本語ラベルへ改名する」という流れが読み取れるようにすること

§2「計画書のフォーマット」にも、**任意節として `## ワークスペースラベル` を書いてよい**ことを
1〜2行で触れておくこと（必須にはしない。既存の計画書はどれもこの節を持たない）。

## 3. `ai/` 接頭辞の前提を除去する（要望3）

ブランチ名・ワークスペース名に `ai/` 接頭辞を付ける方針をやめた。`bin/ocw` は
DOC-2608062259 の孫2 で既に接頭辞を自動付与しないので、**直すのは SKILL.md の記述・例示だけ**。

`git grep -n "ai/" claude/skills/umbrella-orchestrator/SKILL.md` で全件を洗い出すこと。
変更前の時点では以下に出現する（漏れが無いか自分で確認すること）:

- §2.1 進捗テーブルの例（`ai/ph-00-fix` / `ai/ph-01-feat`）とその直後の
  「コードスパンで `` `ai/xxx` ``」という説明
- §3.3 のクリーンアップ提案（`ocw rm <孫ブランチ名>` の説明と `ocw rm ai/ph-00-must-keep` の例）
- §5「`ocw -H` が作るもの」の「`<孫ブランチ名>` は `ai/xxx` を含む完全なブランチ名を
  そのまま渡すこと」以下の段落
- §7 の追随PRの例（`git checkout -b ai/<追随孫名> origin/<傘ブランチ>`）

**元の記述が伝えていた「短縮形ではなく進捗テーブルの値をそのまま渡せ」という趣旨は
残すこと。** 接頭辞の有無に関係なく、`ocw rm` は曖昧一致で停止しうるため、完全な
ブランチ名を渡す必要があるという事実は変わらない。書き換え後は
「進捗テーブルの『ブランチ』列の値をそのまま渡す。`ocw` は接頭辞を一切付けないので、
テーブルの値がそのまま実ブランチ名である」という形になるはず。

**既存の `ai/*` ブランチを遡って改名する話は書かないこと。** これは新規作成分への方針であり、
現に走っている傘 `ai/ocw-pane-roles` もそのままである。その旨を1行添えておくと、
読んだ司令官が既存ブランチを改名しに行かずに済む。

## 検証方針

以下の重要な behavior / regression risk が保護されていること。SKILL.md は自然言語の文書で
自動テストが書けないため、`git grep` と実コマンドでの確認によって示すこと。

- SKILL.md に現れる `ocw -H` の呼び出し例が、すべて実装の実際のフラグ名と一致している
  （`ocw --help` の出力と突き合わせて確認する）
- 孫を作る経路（`/spawn` と `/autopilot` の cron 本文）が**どちらも**2ペインモードを使っている。
  片方だけ直すと、cron 経由の孫にだけ commander が付く
- ラベル rename の手順が、孫を作る経路の**両方**に入っている
- 司令官スペースが3ペインであるという前提（`/finalize` が implementer と reviewer を使う）が
  壊れていない
- `ai/` 接頭辞の除去によって、「完全なブランチ名を渡す」という元の趣旨が失われていない
- `git grep -n "ai/" claude/skills/umbrella-orchestrator/SKILL.md` の残存が、
  意図して残したもの（あれば）だけになっている
- 文書内の相互参照（§番号での参照）が、節を追加・改名した後も正しい先を指している

各項目を機械的なチェック1件ずつに対応させる必要はない。

## 完了条件

- `pre-commit run --all-files` が通る（`doc-id check` / `verify` を含む）
- SKILL.md に、孫1の実装と食い違う記述が残っていない
- 上記「検証方針」の各項目を、どう確認したかが PR 説明文に書かれている

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:
1. PRを作成する。**PRの向き先は必ず `ai/ocw-pane-roles` にすること。master には絶対に出さない。**
2. /pr-review-loop を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する
実装が終わったタイミングで止まらず、必ずここまでやりきってください。

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `ai/ocw-pane-roles` から切ること**。
master から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:
git checkout ai/ocw-pane-roles && git pull --rebase origin ai/ocw-pane-roles
git checkout -b ocw-pane-roles-02-skill-docs
````

---

## 傘の完了条件

- 孫1・孫2 がともに `ai/ocw-pane-roles` にマージ済み
- 傘ブランチ上で以下がすべて通る:
  - `pre-commit run --all-files`
  - `python3 -m unittest discover -s bin/tests -v`
  - `bin/tests/lint.sh`
- **`ocw -H`（フラグなし）の挙動が現行と完全に同一**である
- `ocw -H --no-commander <name>` が implementer / reviewer の2ペインだけを作り、
  commander の起動コマンドを1度も実行しない
- `bin/tests/test_ocw.py` に Herdr モードのテストが存在する（本傘以前はゼロ件だった）
- `bin/README.md` が実装と一致している
- `claude/skills/umbrella-orchestrator/SKILL.md` において:
  - 孫を作る経路（`/spawn` と `/autopilot`）が両方とも2ペインモードを使っている
  - ワークスペースラベルの日本語化手順が、孫・傘の両方について書かれている
  - `ai/` 接頭辞を前提とした記述・例示が残っていない
