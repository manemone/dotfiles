# AGENTS.md

## 概要

クロスプラットフォーム（macOS / Linux / WSL2）対応の dotfiles。mise でランタイムを固定し、
各ツールディレクトリ（`zsh/` `nvim/` `tmux/` `bin/` `claude/`）の `deploy.sh` が、配布実体
（世代ディレクトリ + `current` シンボリックリンク。詳細は「デプロイの仕組み」節）を経由して
ユーザーの `$HOME` に symlink を張ることで設定を配布する。

## 最重要ルール

- **人間の明示的指示がない限り、`git merge` / `git pull` / `git reset --hard` /
  `git push --force` / `gh pr merge` を実行しない。例外はない。**
  すべての不可逆操作の前にこのルールを照合すること。
- **deploy スクリプト（`deploy-all.sh` / `uninstall.sh` / `*/deploy.sh`）を実オペレーションで
  実行しない。** `$HOME` 側のシンボリックリンクは配布実体
  （`${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/` 配下の世代ディレクトリ + `current`）を
  経由するが、リンクの向き先が指す実体は結局ユーザーの実 `$HOME` であり、`~/.zshrc`
  `~/.tmux.conf` `~/.claude/settings.json` `~/bin/*` を実際に置き換える。世代の作成・`current`
  の切り替え・古い世代の削除も同じ prefix 配下で実際に行われる。動作確認は
  `deploy-all.sh --dry-run`（全ツール対象）で行うのを基本とする。**`deploy-all.sh --status` は
  副作用が無いため実 `$HOME` に対して実行してよいが、`--rollback` と `--dev` は `current` を
  実際に付け替えるため、`--dry-run` を付けずに実 `$HOME` に対して実行しない。**
  `HOME` を一時ディレクトリに差し替えるサンドボックス実行が許されるツールの範囲は無条件ではない。
  副作用が `$HOME` の外（システムパッケージのインストール）や外部ネットワークに及ぶツール
  （`tmux` `zsh` `nvim`）は対象外であり、詳細と対象ツールの分類は `docs/design/` の
  「テスト方針（DOC-2608020715-b）」に従うこと。
  **個別の `<tool>/deploy.sh` は `--dry-run` 引数を解釈しない**（環境変数 `DRY_RUN=1` のみ見る）。
  `sh zsh/deploy.sh --dry-run` のように直接引数を渡しても無視され実際に書き換えが起きるため、
  個別スクリプトを dry-run するときは `DRY_RUN=1 sh zsh/deploy.sh` のように環境変数で渡すこと。
  単体実行時、配布元は環境変数 `DOTFILES_DEPLOY_SRC` が未設定なら `current` を自動的に使う
  （`current` も無ければエラーで `./deploy-all.sh` を案内して終了する）。
- 指示された範囲外の機能を先回りして実装しない。
- **shellcheck / shfmt を含む linter の抑制ディレクティブ（`# shellcheck disable=...` 等）や、
  `.pre-commit-config.yaml` の `exclude` / `exclude_types` 追加・`shfmt` のオプション緩和などの
  linter 設定の除外・閾値緩和を、AI の判断で追加しない。** 指摘が設計上不合理だと判断した場合は、
  抑制せず違反内容・対象ファイル・判断理由を人間に報告する。コードの構造を変えて指摘そのものを
  解消できる場合（例: 動的変数名参照を case 文に置き換える）は、抑制よりそちらを優先する。

## ディレクトリ構成

| ディレクトリ | 役割 |
|---|---|
| `zsh/` | Zsh 設定（Antidote でプラグイン管理） |
| `nvim/` | NeoVim 設定（lazy.nvim でプラグイン管理） |
| `tmux/` | tmux 設定 |
| `bin/` | スタンドアロンの CLI ツール（`ocw`, `claude-ds`, `ocw-meter`）。`bin/tests/` は `ocw-meter` 等の Python テスト、`bin/prices/` は費用計算用の価格表 |
| `claude/` | Claude Code 向け配布物（設定・スキル） |
| `shared/` | 全 deploy スクリプトが共有するヘルパー（`helpers.sh`） |
| `docs/` | このリポジトリ自体の設計文書・ADR・計画書・運用リファレンス。`design/`（現役の規約）・`adr/`（確定した技術決定の記録）・`planning/`（傘ブランチ計画書）・`reference/`（運用中に繰り返し引く事実）の4フォルダに分かれる。詳細は [docs/README.md](docs/README.md) を参照 |
| `tools/` | このリポジトリ自体の開発を支援するツール（`doc-id` など）。`bin/` と異なり `$HOME` へは配布しない |
| `templates/` | 他リポジトリへ配布する copier テンプレート（`repo-baseline` など）。`$HOME` へは配布せず、dotfiles 本体にも依存しない自己完結ディレクトリ |

各ツールディレクトリは「設定ファイル本体 + `deploy.sh` + `README.md`」という共通構造を持つ。

## 3つの領域（混同しないこと）

| 対象 | 正体 | 誰が読むか |
|---|---|---|
| `claude/CLAUDE.md`, `claude/settings.json`, `claude/skills/` | **配布される成果物。** `claude/deploy.sh` がユーザーの `~/.claude/` 配下へ配置する（`CLAUDE.md` と `skills/` は symlink、`settings.json` は生成。詳細は「デプロイの仕組み」参照） | このリポジトリを使う人間のマシンの Claude Code |
| ルート `AGENTS.md` / `CLAUDE.md`（このファイル） | **このリポジトリを開発するためのルール** | このリポジトリで作業する AI |
| `.claude/settings.json` | リポジトリで作業する AI 向けの permissions を置く場所 | このリポジトリで作業する Claude Code |

**`claude/CLAUDE.md`（配布物。個人の口調設定などが入っている。ルート `CLAUDE.md` とは別物）は、
指示が無い限り編集しない。**

## AI 支援ツールの設定

ルールの本体は常に `AGENTS.md`（このファイル）に書く。各 AI 製品向けの設定ファイルは、
ルールを書き写さず `AGENTS.md` を指すことに徹する。新しい AI 製品を使い始めるときも同様に、
その製品の設定ファイルから `AGENTS.md` を参照する形にする。

| AI 製品 | 設定ファイル | 中身 |
|---|---|---|
| Claude Code | `CLAUDE.md` | `@AGENTS.md` の1行のみ |
| opencode | `opencode.json` | `instructions` に `AGENTS.md` と `docs/design/` 配下の規約文書パスを列挙 |

## デプロイの仕組み

`$HOME` はリポジトリの作業ツリーへ直接リンクしない。`deploy-all.sh` は作業ツリーを
**配布実体**（世代ディレクトリ）へコピーし、`current` というシンボリックリンクをそこへ向け、
各 `<tool>/deploy.sh` は `current` 経由で `$HOME` からリンクする（Capistrano の `releases/` +
`current` と同じ構造）。採用理由と却下案は ADR
[DOC-2608040229](docs/adr/DOC-2608040229_deploy-distribution-method.md) を参照。

### 配布実体レイヤ

- canonical prefix: `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles`
- 世代ディレクトリ: `<prefix>/generations/<date +%Y%m%dT%H%M%S>-<short sha>`（作業ツリーから
  `cp -a`。**`AVAILABLE_TOOLS` の各ディレクトリと `shared/` のみ**が対象で、`docs/` `tools/`
  `templates/` `tests/` `.git` はコピーされない）
- `current`: `<prefix>/current`。`ln -sfn` で切り替える（原子性は追わない。ADR §4.7）
- 世代直下の `.dotfiles-manifest` にデプロイ日時・ソースツリーの絶対パス・コミット SHA・
  ブランチ名・dirty だったか・リンクされた git ワークツリーからのデプロイか・モード（世代 or
  dev）・ホスト名を平文で記録する
- 保持世代数は既定3（`DOTFILES_KEEP_GENERATIONS` で上書き可）。GC は `current` が指す世代を
  決して削除せず、dev モード中は何も削除しない
- **`--only <tools>` は `$HOME` のどのリンクを張るかだけを制御し、世代の内容には影響しない。**
  世代は常に全ツール分をコピーする（部分的な世代を作ると、他ツールのリンクが新世代に
  存在しないパスを指してリンク切れになるため）

### デプロイの流れ

1. `deploy-all.sh` が `shared/helpers.sh` を source し、`AVAILABLE_TOOLS` を解決する
2. 新しい世代ディレクトリを作り、`.dotfiles-manifest` を書く
3. `current` を新世代へ切り替える
4. 各 `<tool>/deploy.sh` を、配布元を環境変数 `DOTFILES_DEPLOY_SRC`（= `current` を指す
   固定パス）として export した状態で呼び出す。symlink は `shared/helpers.sh` の
   `symlink_backup` 経由で `$DOTFILES_DEPLOY_SRC/<tool>/...` へ張る
5. 古い世代を GC する

オプション: `--dry-run` / `--force` / `--only <tools>` / `--backup` / `--no-backup` /
`--status` / `--rollback [世代ID]` / `--dev`。後者3つは `current` シンボリックリンク自体を
操作するコマンドで、互いに組み合わせられず、`--only` / `--force` / `--backup` / `--no-backup`
とも組み合わせられない（`--dry-run` のみ併用可）。

- `--status`: 副作用なし。`current` の向き先（世代か dev モードか）・その manifest の内容
  （dev モードでは manifest が無いためソースツリーの git 状態をその場で読んで代わりに表示する）・
  保持世代一覧・`$HOME` 側リンクの健全性（リンク切れ検出）を表示する
- `--rollback [世代ID]`: `current` を1つ前（または指定した）世代へ付け替える。`$HOME` 側の
  symlink は張り直さない（`current` の付け替えだけで全リンクの向き先が変わるのが世代方式の要）
- `--dev`: `current` を作業ツリーそのものへ向ける（世代は作らない。編集が即座に `$HOME` へ
  反映される）。dev モード中は GC を行わない

`$HOME` 側の配布先一覧は `shared/helpers.sh` の `links_for_tool()`（symlink 系のツール）と
`claude_skill_links()`（`claude/skills/` の個別 symlink）に一元化されており、`uninstall.sh` と
`deploy-all.sh --status` の両方がここを参照する。リストを二重管理すると片方だけ更新される
事故が起きる（`uninstall.sh` 側から `ocw-meter` が漏れていた過去の不具合がまさにこれ）。

### 単体 `<tool>/deploy.sh` 実行時の規約

`DOTFILES_DEPLOY_SRC` が未設定なら `current` を自動的に使う（`shared/helpers.sh` の
`resolve_deploy_src`）。`current` も無ければ、エラーメッセージで `./deploy-all.sh` を案内して
終了する。単体実行が自分で世代を作ることはない（世代は常に全ツール分でなければならないため）。

### symlink の退避

symlink は `shared/helpers.sh` の `symlink_backup` 経由で張る。既存ファイルは `.backup`
（既に存在する場合はタイムスタンプ+PID 付きの別名）に退避される。`symlink_restore` が
uninstall 側の対応関数。ただし退避の前提は次の3点で崩れる:

- `--no-backup`（`BACKUP=0`）指定時は退避されず `rm -f` される
- dst が既にこのリポジトリ由来の symlink（リンク先が canonical prefix 配下、またはソースツリー
  配下）であれば、退避せず張り替える。旧方式（作業ツリー直リンク）の symlink がそのまま
  `.backup` として残り、後日 `uninstall.sh` がそれを「ユーザーの元設定」として誤って復元するのを
  防ぐための判定
- `claude/skills/` は `symlink_backup` を通らない。`claude/deploy.sh` がスキルごとに
  個別に symlink を張り、退避先も `~/.claude/skills-backup/<名前>.<日時>.<PID>` になる

### claude の例外

`claude/settings.json` だけは symlink ではなく、`current` 経由の `claude/settings.json` と
`claude/settings.machine.json`（マシン固有・非追跡だが `cp -a` で世代内にコピーされる）を
マージした**実ファイル**として生成される。マシンごとの上書き設定を git 管理下に置かずに
反映するため。

### uninstall.sh の後片付け

`uninstall.sh` は `$HOME` 側の symlink・生成ファイルを撤去したあと、配布実体
（`<prefix>/generations/` `<prefix>/.tmp/` と `current`、空になった `<prefix>` 自体）も
片付ける。撤去対象に含まれないツールの symlink がまだ配布実体を参照している場合は片付けを
行わず安全側に倒す。dev モード中（`current` が人間の作業ツリーを指している）でも
`generations/` `.tmp/` と `current` 自体は通常どおり片付けられる。保護されるのは
**`current` が指す作業ツリーの実体だけ**であり、そちらには一切触れない。

## クロスプラットフォーム制約

- `shared/helpers.sh` は POSIX sh。bashism を書かない。
- `deploy-all.sh` `uninstall.sh` `*/deploy.sh` も `#!/bin/sh`。
- `bin/ocw` `bin/claude-ds` は bash（`#!/usr/bin/env bash`）。
- プラットフォーム分岐は `is_macos` / `is_linux` / `is_wsl` / `get_brew_prefix` を使い、
  直接 `uname` を叩かない。
- macOS の BSD 版コマンドと GNU 版の差異（`sed -i`、`date`、`readlink -f` など）に注意する。

## コードの書き方

シェルスクリプトを書く・直すときは
[docs/design/DOC-2608020715-a_シェルスクリプトコーディング方針.md](docs/design/DOC-2608020715-a_シェルスクリプトコーディング方針.md)
を参照すること。POSIX sh / bash の使い分け、bashism の回避、エラーハンドリングの既存方針などを定めている。

## コミット前の必須ステップ

初回のみ、clone 後に以下を実行して pre-commit フックを有効化する。

```
uv tool install pre-commit
pre-commit install
```

以降はコミット時に `.pre-commit-config.yaml` のフックが自動で走る
（`trailing-whitespace` 等の基本チェック、`shellcheck` / `shfmt`、
`./tools/doc-id/doc-id check` / `verify`、`tools/doc-id/` 配下の変更時の
`ruby tools/doc-id/test/doc_id_test.rb`、シェルスクリプト変更時の
`./deploy-all.sh --dry-run`、`bin/` 配下変更時の `bin/tests/lint.sh`、
`tools/doc-id/` または `templates/repo-baseline/template/tools/doc-id/` 変更時の
両者の同一性チェック）。手元でまとめて確認したい場合は次を実行する。

```
pre-commit run --all-files
```

pre-commit のフックではデプロイの実動作までは検証しないため、
デプロイ関連のシェルスクリプトを変更した場合は追加で以下も実行する。

```
tests/deploy_smoke.sh
```

`HOME` を一時ディレクトリへ差し替えたサンドボックス上で実際に deploy /
uninstall を行い、symlink・既存ファイルの退避・冪等性・
`claude/settings.json` の実ファイル生成に加えて、世代の作成と GC・
ソースツリー消失耐性・編集分離・`--rollback`・`--dev`・
配布実体（世代 + `current`）の後片付けを検証する（既定の対象は
`bin,claude`。デプロイの検証は必ずこのサンドボックス経由で行い、
人間の実 `$HOME` に対して直接実行しない。詳細は
[docs/design/DOC-2608020715-b_テスト方針.md](docs/design/DOC-2608020715-b_テスト方針.md)
を参照）。

`templates/repo-baseline/` 配下を変更した場合は、加えて以下も実行する。

```
tests/template_smoke.sh
```

代表的な質問への回答（全部盛り・最小構成）で `copier copy` を実際にレンダリングし、
生成された `.pre-commit-config.yaml` / `ci.yml` が壊れていないか、生成された全 `.md`
（`AGENTS.md` と `docs/` 配下の全ファイル）に Jinja 空白制御ミスによる Markdown の崩れ
（行ゼロの表・見出し直前の空行欠落・二重空行・Jinja 構文の残骸）が無いか、`_exclude` の
効き（`use_doc_id=false` 時に `docs/` `tools/` `.github/` が生成されないこと）を検証する
（`.pre-commit-config.yaml.jinja` / `ci.yml.jinja` は拡張子が `.jinja` のため
`check-yaml` フックの対象外であり、YAML の壊れもMarkdownの崩れもこのテストでしか
検出できない）。**`templates/repo-baseline/` 配下のどのファイルを変更した場合も対象**
であり、YAML を含むファイルに限らない。

`bin/` 配下（`ocw` / `ocw-meter` 等）を変更した場合は、加えて以下も実行する。

```
python3 -m unittest discover -s bin/tests -v
```

193件・約40秒かかるため pre-commit には組み込んでいない（コミットのたびに
待たされるコストが見合わない）。CI（`.github/workflows/ci.yml` の `bin-tests`
ジョブ）では毎PRで実行され、`bin/tests/lint.sh`（`bash -n` / `py_compile`。
高速なため pre-commit にも組み込み済み）と合わせて `.claude/pr-review.yml`
の `lint_cmd` / `test_cmd` としても定義されている。

**AI はこれらのステップ（pre-commit のフック相当の確認と
`tests/deploy_smoke.sh`）を省略しない。省略するのは人間が明示的に指示した
場合に限る。**

shellcheck / shfmt の指摘への対応も「最重要ルール」の linter 抑制禁止に従う。

`docs/` 配下に新規ファイルを追加する場合は、まず `DOC-DOCID_PLACEHOLDER_<説明的ファイル名>.md`
という名前で作り、`./tools/doc-id/doc-id assign docs/path/to/new_file.md` で DOC-ID を採番する
（`doc-id check` / `doc-id verify` フックが検証する）。

## PR 作成時の注意

PR を作る前に
[docs/design/DOC-2608020715_プルリクエストの作法.md](docs/design/DOC-2608020715_プルリクエストの作法.md)
を読むこと。

## 実装時の注意

- 新しいツールディレクトリを足すときは `shared/helpers.sh` の `AVAILABLE_TOOLS` に加えて、
  同じく `shared/helpers.sh` の `links_for_tool()` に `$HOME` 側リンク先を返す `case` の arm を
  追加する。**`uninstall.sh` と `deploy-all.sh --status` の両方がここを一次情報源として参照する**
  ため、二重管理を避けるためにここへ一元化されている（過去に `uninstall.sh` 側だけ
  `KNOWN_LINKS_bin` に `ocw-meter` が無く撤去漏れが起きた不具合の再発防止）。
  生成ファイル（symlink ではなく実ファイルを生成するツール。例: `claude/settings.json`）が
  あれば `uninstall.sh` の `KNOWN_GENERATED_<tool>` を定義し、`_generated` を求める
  `case "$_tool" in ... esac` にも arm を追加する。スキルの個別 symlink のように
  「リポジトリ由来判定」が別途必要な場合は `_skills_src` を求める `case` にも arm を追加する。
  **`uninstall.sh` に残る `case` 文はこの2つ（`_generated` / `_skills_src`）のみで、
  `_links` に相当する分岐は `shared/helpers.sh` の `links_for_tool()` へ移っている。**
  `links_for_tool()` に arm を足し忘れると、`uninstall.sh` 側の `_links` が空のまま扱われ
  「No link list defined」で静かにスキップされる。**ただし `KNOWN_GENERATED_<tool>` を
  定義済みのツール（`claude` 等）はこのスキップ自体が発生しない**（`_generated` が非空の
  ままループが継続するため）。この場合、警告なしに `_links` 側の symlink だけが撤去されずに
  残る。`deploy-all.sh --status` のリンク健全性スキャンには arm 忘れに対する警告経路が無く、
  その分の `$HOME` リンクが静かにレポートから抜け落ちる点にも注意する。
- README は「ルート `README.md`（全体）」と「各ツールの `README.md`（詳細）」の二層構造。
  片方だけ更新しない。
- `docs/` の文書に地の文で言及するときは、説明的ファイル名だけで呼ばず、その文書の DOC-ID を明示する
  （例: 「テスト方針（DOC-YYMMDDHHMM）を参照」のように、実際に割り当てられた DOC-ID を書く）。
  相対パスへのリンクを併記してもよいが、DOC-ID の明示は省略しない。DOC-ID は不変なので、
  ファイルが移動・リネームされても文書を一意に特定できる。
  - **移行措置**: 対象の文書がまだ `DOC-DOCID_PLACEHOLDER` のまま採番されていない間は、
    DOC-ID を書きようがないため説明的名称のみで言及してよい。`./tools/doc-id/doc-id assign` で採番する際は、
    ファイル名だけでなくリポジトリ内の地の文の言及（`git grep` で説明的ファイル名を検索して見つかる
    箇所）にも DOC-ID を追記すること。採番ツールによるプレースホルダ文字列の自動置換は
    ファイル名・リンク先パスのみが対象で、地の文中の言及までは拾わない。
