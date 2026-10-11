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

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。転記後に削除済みで
> 参照できない前提で書く）を material として司令官が起草したものである。** ブリーフに
> 書かれていた問題意識・決定事項・実測値・制約・未確認の点・孫分割の叩き台は本計画書へ
> 転記済みであり、以降はこの計画書が正典である。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `hwg-01-probe` | herdr のワークツリーグループの実際の動きを使い捨ての環境で確かめ、傘単位に寄せられるかの結論と採る方式を ADR にまとめる | 🔄 実装中 |
| 2 | `hwg-02-ocw-open` | `ocw -H` のワークスペース作成を herdr のワークツリーグループに乗る方式へ切り替える（テスト込み） | ⬜ 待機中 |
| 3 | `hwg-03-cleanup` | 片付け側（`ocw rm`・`worktree-cleanup` の孤児の判定）を、グループになったワークスペースに対応させる | ⬜ 待機中 |
| 4 | `hwg-04-skill-docs` | `umbrella-orchestrator` §5 などスキル・README の記述を新しい方式に合わせる | ⬜ 待機中 |

依存: 孫1 → **人間の判断（設計2「判断ゲート」）** → 孫2 → 孫3 → 孫4 の順に**直列**で進める。

- 孫1 の結果次第で孫2 以降の設計が分かれる（ブリーフの決定。結果は人間に一度見せる）。
  **孫1 のマージを検出しても、判断ゲートが「未」のあいだは孫2 を spawn しない。**
- 孫2・孫3 はどちらも `bin/ocw` と `bin/tests/test_ocw.py` の Herdr 連携部分を触るため、
  並列にするとコンフリクトする
- 孫4 は孫2・孫3 で確定した挙動を文書へ反映するので最後に置く
- 孫1 の結論によっては、司令官が孫2〜4 のプロンプトを書き直す・孫を統合／追加する
  （設計2 の判断を受けて計画書を更新してから spawn する）

## ワークスペースラベル

- 傘: `dotfiles :: サイドバーを傘でまとめる`
- 孫1: `dotfiles :: サイドバーを傘でまとめる 孫1 グループ挙動の実測`
- 孫2: `dotfiles :: サイドバーを傘でまとめる 孫2 ocw -H切替`
- 孫3: `dotfiles :: サイドバーを傘でまとめる 孫3 片付け対応`
- 孫4: `dotfiles :: サイドバーを傘でまとめる 孫4 スキル文書更新`

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

## 設計1: 司令官が確定させた判断（孫はこれに従う）

### 1.1 孫の分割と順序

ブリーフの叩き台（4本）をそのまま採る。孫1 を ADR を成果物とする調査の孫にしたのは、
調査結果と方式の決定（却下案を含む）を後から追えるように残すため（AGENTS.md の docs/ の
役割分担: 実測に基づく技術決定は `docs/adr/`）。孫1 の ADR は「状態: 提案」で出し、
判断ゲート（設計2）で人間が方式を決めたあと、孫2 の PR で「採用」へ更新する。

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

## 設計2: 判断ゲート（孫1 の後に人間が決める）

判断ゲート: **未**

（孫1 のマージ後、司令官が ADR の結論を人間に示し、人間が方式を決めたら、司令官がここを
「済」に書き換え、決まった方式と人間の発言を記録し、必要なら孫2〜4 のプロンプトを書き直してから
孫2 を spawn する。**この欄が「未」のあいだ、巡回は孫2 を spawn しない。**）

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
  変えざるを得ない場合は ADR に理由を書き、スキル側（孫4）を合わせる

## スコープ外

- `herdr-09-cli-migration`（スキルを herdr 0.9 のコマンドに追随させる傘。孫4本ともマージ済みで
  締めの段階）とは別。あちらに足さない。テーマ（スキルの文面の追随）も触る場所も違うため
- herdr 本体の改造・プラグインの作成（必要になったら人間に相談）
- 同時に進行中の PR #141（司令官の区切り compact。ブランチ `commander-compact`。
  `skills/umbrella-orchestrator/SKILL.md` を触る）とは別件。孫4 が同じファイルを触るので、
  孫4 の着手時に #141 がマージ済みなら傘を `origin/master` へ rebase してから始める
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
結合は、偽物では確かめられないので、孫2・孫3 が使い捨ての環境で手で確かめて PR に書く。

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
   - 状態は「提案」（人間が判断ゲートで決めたあと、孫2 が「採用」へ更新する）
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

> **判断ゲート（設計2）が「済」になるまで spawn しない。** 孫1 の結論次第で、司令官が
> spawn 前にこのプロンプトを書き直す。

````markdown
# 傘ブランチ: herdr-worktree-group
# 孫ブランチ: hwg-02-ocw-open
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/herdr-worktree-group/docs/planning/DOC-2610111927_herdr-worktree-group_計画.md`

**まず計画書の「概要」「背景1〜4」「設計1」「設計2」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」と、孫1 の ADR（`docs/adr/` 配下の herdr-worktree-group の
ADR）を全部読むこと。** 方式は設計2 で人間が決めたものに従う。

## 実装開始前の必須手順

`ocw` がすでに `hwg-02-ocw-open` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/herdr-worktree-group` の
先端（孫1 のマージを含む）から切られていることを確かめる（`git pull` は使わない）。

## やること

1. `bin/ocw` の `-H` のワークスペース作成を、設計2 で決まった方式（herdr のワークツリーグループに
   乗る方式）へ切り替える
   - 既存の外部契約（出力行・ペイン構成・`--no-commander`・`OCW_*_COMMAND`・
     `OCW_ROLE` / `OCW_RUN_ID`）を保つ（計画書「決定的な制約」）
   - 作成失敗時のロールバック（`rollback_created_worktree`）が、新しい方式で作ったワークスペースを
     正しく閉じられるようにする（閉じ方の詳細は ADR に従う。片付け側の本格対応は孫3）
2. `bin/tests/test_ocw.py` の偽の herdr と検証を新しい呼び出しに合わせる
3. `ocw help herdr` の記述を新しい方式に合わせる（`bin/README.md` 等の文書は孫4 の担当）
4. 孫1 の ADR の状態を「採用」へ更新し、設計2 で決まった内容と食い違う箇所があれば直す
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
   「孫2 `hwg-02-ocw-open` の PR #<番号> を herdr-worktree-group へマージしました。」だけにする。
   通知は1回だけ。送れなくても止まらず、送れなかったことを最終報告に1行書く

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

## 孫3用プロンプト:

> 孫2 のマージ後に spawn する。孫1 の結論次第で、司令官が spawn 前に書き直すことがある。

````markdown
# 傘ブランチ: herdr-worktree-group
# 孫ブランチ: hwg-03-cleanup
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/herdr-worktree-group/docs/planning/DOC-2610111927_herdr-worktree-group_計画.md`

**まず計画書の「概要」「背景1〜4」「設計1」「設計2」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」と、孫1 の ADR を全部読むこと。**

## 実装開始前の必須手順

`ocw` がすでに `hwg-03-cleanup` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/herdr-worktree-group` の
先端（孫2 のマージを含む）から切られていることを確かめる（`git pull` は使わない）。

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
4. 本物の herdr で、使い捨てのリポと使い捨てのワークスペースを使って、孫2 の方式で作った
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
   「孫3 `hwg-03-cleanup` の PR #<番号> を herdr-worktree-group へマージしました。」だけにする。
   通知は1回だけ。送れなくても止まらず、送れなかったことを最終報告に1行書く

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

## 孫4用プロンプト:

> 孫3 のマージ後に spawn する。spawn 前に PR #141（`commander-compact`）が `master` へマージ済みなら、
> 司令官が傘を `origin/master` へ rebase してから spawn する（スコープ外の節）。

````markdown
# 傘ブランチ: herdr-worktree-group
# 孫ブランチ: hwg-04-skill-docs
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/herdr-worktree-group/docs/planning/DOC-2610111927_herdr-worktree-group_計画.md`

**まず計画書の「概要」「背景1〜4」「設計1」「設計2」「決定的な制約」「スコープ外」
「必須の検証ステップ」と、孫1 の ADR を全部読むこと。**

## 実装開始前の必須手順

`ocw` がすでに `hwg-04-skill-docs` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/herdr-worktree-group` の
先端（孫3 のマージを含む）から切られていることを確かめる（`git pull` は使わない）。

## やること

孫2・孫3 で変わった `ocw -H` / `ocw rm` の挙動を、文書へ反映する。コードは変えない。

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

- 文書に書いたコマンド・挙動が、孫2・孫3 のコードと ADR の実測に一致している
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
   「孫4 `hwg-04-skill-docs` の PR #<番号> を herdr-worktree-group へマージしました。」だけにする。
   通知は1回だけ。送れなくても止まらず、送れなかったことを最終報告に1行書く

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````
