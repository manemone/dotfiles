# AGENTS.md

## 概要

クロスプラットフォーム（macOS / Linux / WSL2）対応の dotfiles。mise でランタイムを固定し、
各ツールディレクトリ（`zsh/` `nvim/` `tmux/` `bin/` `claude/` `skills/`）の `deploy.sh` が、配布実体
（世代ディレクトリ + `current` シンボリックリンク。詳細は「デプロイの仕組み」節）を経由して
ユーザーの `$HOME` に symlink を張ることで設定を配布する。

## 最重要ルール

- **`master` を書き換える操作（マージ・push・force push）は人間だけが行う。例外はない。**
  - 傘ブランチ配下の操作は AI が行ってよい。孫ブランチ → 傘ブランチのマージは
    **レビューで承認済みの PR に限り** AI が実行してよい
    （`gh pr merge <PR番号> --squash --delete-branch`）。傘ブランチは孫を安全に
    統合するための隔離された場所であり、そこへのマージまで人間待ちにすると
    傘ブランチ方式が機能しない
  - 傘ブランチへの上流取り込みは `git fetch origin` + `git merge origin/master`
    で行う（傘ブランチは孫のマージで `master` より進んでいるため、ここは
    `--ff-only` ではなく通常の `merge` を使う）
  - 孫ブランチを傘ブランチへ追随させるときは `git rebase origin/<傘ブランチ>` +
    **孫ブランチ限定**の `git push --force-with-lease` で行う（`master` への
    force push は対象外）。孫ブランチは自分の作業コミットを持つのが通常であり、
    傘ブランチが他の孫のマージで進んでいれば孫と傘は必ず分岐するため、
    `git merge --ff-only` は使わない
  - `git pull` は使わない
  - `git reset --hard` / `git clean` / 裸の `git push --force`（lease なし）は、
    ブランチを問わず引き続き人間の承認が要る
  - `claude/hooks/git-guard.sh`（PreToolUse フック。ADR
    [DOC-2609121719](docs/adr/DOC-2609121719_git-operation-permission-policy.md)
    参照）が機械的に担保するのは**`gh pr merge` の base が保護ブランチかどうか、
    その1点だけ**である。base は PR 側の属性でコマンド文字列に現れず、
    `permissions` のグロブで表現できないため。`main`/`master` への `git push` は
    `claude/settings.json` の `permissions.ask` グロブが受け持つ。
    **それ以外——`git pull` を使わないこと・孫→傘のマージをレビュー承認済みPRに
    限ること・ローカルの `git merge` の向き先——はフックの対象外であり、
    この文言だけが歯止め。** フックは判定できない入力に対して何も言わない
    （`ask` に倒さない）。また `permissions.allow` を返しても `ask` / `deny` を
    上書きできない（制限を足すだけ）ため、`claude/settings.json` 側の
    `ask` / `allow` パターンと矛盾がないか合わせて確認すること

  すべての不可逆操作の前にこのルールを照合すること。
- **deploy スクリプト（`deploy-all.sh` / `uninstall.sh` / `*/deploy.sh`）を実オペレーションで
  実行しない。** `$HOME` 側のシンボリックリンクは配布実体
  （`${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/` 配下の世代ディレクトリ + `current`）を
  経由し、リンクの**向き先**（symlink のターゲット）自体はこの prefix 配下を指す。危険なのは
  向き先ではなく、**リンクを張る先（dst）がユーザーの実 `$HOME`** であることで、`~/.zshrc`
  `~/.tmux.conf` `~/.claude/settings.json` `~/bin/*` という実在のパスを実際に置き換える。世代の
  作成・`current` の切り替え・古い世代の削除も同じ prefix 配下で実際に行われる。動作確認は
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
- **linter の指摘は原則リファクタで対応する。** 長さ系の指摘に対して機械的に関数・ファイルを
  分割しない。分割後に責務・凝集性・読みやすさが改善する場合だけリファクタする。
- **新規ファイルの追加時、または既存ファイルを大幅に変更した時点で、対象ファイル単位の
  lint を実行する。** lint の実行をコミット直前まで遅らせない。`pre-commit run --files <path>`
  を使うと `.pre-commit-config.yaml` の引数（`shellcheck -x` / `shfmt -i 2 -ci -d`）込みで走る。

## ディレクトリ構成

| ディレクトリ | 役割 |
|---|---|
| `zsh/` | Zsh 設定（Antidote でプラグイン管理） |
| `nvim/` | NeoVim 設定（lazy.nvim でプラグイン管理） |
| `tmux/` | tmux 設定 |
| `bin/` | スタンドアロンの CLI ツール（`ocw`, `claude-ds`, `ocw-meter`）。`bin/tests/` は `ocw-meter` 等の Python テスト、`bin/prices/` は費用計算用の価格表 |
| `claude/` | Claude Code 向け配布物（`CLAUDE.md` / `settings.json`） |
| `skills/` | AI コーディングエージェント向けのスキル。Claude Code だけでなく Codex・OpenCode にも同じ実体を配る（ADR DOC-2608272128） |
| `codex/` | Codex CLI のグローバル指示（`~/.codex/AGENTS.md`）を `claude/CLAUDE.md` から symlink で配る（ADR DOC-2609072334） |
| `opencode/` | OpenCode のグローバル指示（`~/.config/opencode/AGENTS.md`）を `claude/CLAUDE.md` から symlink で配る（ADR DOC-2609072334） |
| `shared/` | 全 deploy スクリプトが共有するヘルパー（`helpers.sh`） |
| `docs/` | このリポジトリ自体の設計文書・ADR・計画書・運用リファレンス。`design/`（現役の規約）・`adr/`（確定した技術決定の記録）・`planning/`（傘ブランチ計画書）・`reference/`（運用中に繰り返し引く事実）の4フォルダに分かれる。詳細は [docs/README.md](docs/README.md) を参照 |
| `tools/` | このリポジトリ自体の開発を支援するツール（`doc-id` など）。`bin/` と異なり `$HOME` へは配布しない |
| `templates/` | 他リポジトリへ配布する copier テンプレート（`repo-baseline` など）。`$HOME` へは配布せず、dotfiles 本体にも依存しない自己完結ディレクトリ |

各ツールディレクトリは「設定ファイル本体 + `deploy.sh` + `README.md`」という共通構造を持つ。
例外は `codex/` と `opencode/` で、この2つは設定ファイル本体を持たず、`deploy.sh` が
`claude/CLAUDE.md` を symlink で指す（内容がエージェント非依存の個人指示のため。理由は
ADR DOC-2609072334 参照）。

## 3つの領域（混同しないこと）

| 対象 | 正体 | 誰が読むか |
|---|---|---|
| `claude/CLAUDE.md`, `claude/settings.json` | **配布される成果物。** `claude/deploy.sh` がユーザーの `~/.claude/` 配下へ配置する（`CLAUDE.md` は symlink、`settings.json` は生成。詳細は「デプロイの仕組み」参照） | このリポジトリを使う人間のマシンの Claude Code |
| `skills/` | **配布される成果物。** `skills/deploy.sh` が各 AI エージェントのスキルディレクトリへスキルごとに symlink する | このリポジトリを使う人間のマシンの Claude Code / Codex / OpenCode |
| ルート `AGENTS.md` / `CLAUDE.md`（このファイル） | **このリポジトリを開発するためのルール** | このリポジトリで作業する AI |
| `.claude/settings.json` | リポジトリで作業する AI 向けの permissions を置く場所 | このリポジトリで作業する Claude Code |

**`claude/CLAUDE.md`（配布物。個人の口調設定などが入っている。ルート `CLAUDE.md` とは別物）は、
指示が無い限り編集しない。** `codex/deploy.sh` と `opencode/deploy.sh` もこのファイルを
symlink 元にしている（ADR DOC-2609072334）ため、編集の影響は3エージェントへ及ぶことに注意する。

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
  ブランチ名・dirty だったか・リンクされた git ワークツリーからのデプロイか・モード（常に
  `generation`。dev モードは manifest を書かない。dev モード中の `--status` はソースツリーの
  git 状態をその場で読んで代わりに表示する）・ホスト名を平文で記録する
- 保持世代数は既定3（`DOTFILES_KEEP_GENERATIONS` で上書き可）。GC は `current` が指す世代を
  決して削除せず、dev モード中は何も削除しない
- **`--only <tools>` は `$HOME` のどのリンクを張るかだけを制御し、世代の内容には影響しない。**
  世代は常に全ツール分をコピーする（部分的な世代を作ると、他ツールのリンクが新世代に
  存在しないパスを指してリンク切れになるため）

### デプロイの流れ

1. `deploy-all.sh` が `shared/helpers.sh` を source し、`AVAILABLE_TOOLS` を解決する
2. `current` が指す世代とソースツリーの間で、状態ファイル（後述）の書き戻しが無いか検知する。
   差分があれば警告して停止する（`--force` で破棄して続行可）
3. 新しい世代ディレクトリを作り、`.dotfiles-manifest` を書く
4. `current` を新世代へ切り替える
5. 各 `<tool>/deploy.sh` を、配布元を環境変数 `DOTFILES_DEPLOY_SRC`（= `current` を指す
   固定パス）として export した状態で呼び出す。symlink は `shared/helpers.sh` の
   `symlink_backup` 経由で `$DOTFILES_DEPLOY_SRC/<tool>/...` へ張る
6. 古い世代を GC する

オプション: `--dry-run` / `--force` / `--only <tools>` / `--backup` / `--no-backup` /
`--status` / `--rollback [世代ID]` / `--dev` / `--adopt-state`。後者4つは通常の
世代作成/デプロイ/GCフローを迂回するコマンドで、互いに組み合わせられず、`--only` /
`--force` / `--backup` / `--no-backup` とも組み合わせられない（`--dry-run` のみ併用可）。

- `--status`: 副作用なし。`current` の向き先（世代か dev モードか）・その manifest の内容
  （dev モードでは manifest が無いためソースツリーの git 状態をその場で読んで代わりに表示する）・
  保持世代一覧・未取り込みの状態ファイル書き戻し・`$HOME` 側リンクの健全性（リンク切れ検出）を表示する
- `--rollback [世代ID]`: `current` を1つ前（または指定した）世代へ付け替える。`$HOME` 側の
  symlink は張り直さない（`current` の付け替えだけで全リンクの向き先が変わるのが世代方式の要）。
  切り替え前に、離れる世代に未取り込みの状態ファイル書き戻しがあれば警告する（ブロックはしない）
- `--dev`: `current` を作業ツリーそのものへ向ける（世代は作らない。編集が即座に `$HOME` へ
  反映される）。dev モード中は GC を行わない
- `--adopt-state`: `current` が指す世代の状態ファイル（後述）をソースツリーへコピーバックする。
  世代を作らず `current` も `$HOME` symlink も一切触らない。コピーバックのみで終了するので、
  `git diff` で確認・コミットしたうえで改めて通常の deploy を実行する

`$HOME` 側の配布先一覧は `shared/helpers.sh` の `links_for_tool()`（symlink 系のツール）と
`skill_links()`（`skills/` の個別 symlink。全エージェント分）に一元化されており、`uninstall.sh` と
`deploy-all.sh --status` の両方がここを参照する。リストを二重管理すると片方だけ更新される
事故が起きる（`uninstall.sh` 側から `ocw-meter` が漏れていた過去の不具合がまさにこれ）。

### 状態ファイル（$HOME 側からの書き戻し）

`nvim/lazy-lock.json` のように、`$HOME` 側から symlink 経由でツール自身が書き戻すファイルがある
（lazy.nvim の `:Lazy update` 等）。書き込み先は `current` が指す**世代ディレクトリ**であって
ソースツリーではないため、何もしなければ次のデプロイで作られる新世代に引き継がれず消える。
`shared/helpers.sh` の `state_files_for_tool()`（`links_for_tool()` と同じ一元化の作法）が
対象ファイルの一覧を返し、`detect_state_writeback()` が `current` の世代とソースツリーの間で
`cmp -s` により差分を検知する。デプロイ時の検知・`--status` での表示・`--adopt-state` による
取り込みは、いずれもこの2関数が一次情報源。詳細と却下案は ADR DOC-2608040229 §4.9 を参照。

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
- `skills/` は `symlink_backup` を通らない。`skills/deploy.sh` がスキルごとに
  個別に symlink を張り、退避先も `<エージェントのホーム>/skills-backup/<名前>.<日時>.<PID>` になる

### claude の例外

`claude/settings.json` だけは symlink ではなく、`current` 経由の `claude/settings.json` と
machine 設定をマージした**実ファイル**として生成される。マシンごとの上書き設定を git 管理下に
置かずに反映するため。

machine 設定（`settings.machine.json`）の実体は `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/settings.machine.json`
という**世代を経由しない固定パス**に置かれる（`current` や `generations/` と同じ階層。
`shared/helpers.sh` の `dotfiles_machine_json_path()` が一次情報源）。`~/.claude/settings.machine.json`
はこの固定パスへの symlink であり、人間はそちらを直接編集してよい。ソースツリー配下の
`claude/settings.machine.json` は**旧方式の名残**でしかなく、`claude/deploy.sh` が検出したら
固定パスへ自動移行する（詳細は計画書 DOC-2609121700 設計6）。固定パスに置く理由は、
どのワークツリーから deploy しても同じ machine 設定を使い続けられるようにするため
（ワークツリーごとに在ったり無かったりする非追跡ファイルを世代経由にすると、machine.json を
持たないワークツリーから deploy した瞬間に空扱いされ、人間の設定が消えてしまう）。

### uninstall.sh の後片付け

`uninstall.sh` は `$HOME` 側の symlink・生成ファイルを撤去したあと、配布実体
（`<prefix>/generations/` `<prefix>/.tmp/` と `current`、空になった `<prefix>` 自体）も
片付ける。撤去対象に含まれないツールの symlink がまだ配布実体を参照している場合は片付けを
行わず安全側に倒す。dev モード中（`current` が人間の作業ツリーを指している）でも
`generations/` `.tmp/` と `current` 自体は通常どおり片付けられる。保護されるのは
**`current` が指す作業ツリーの実体だけ**であり、そちらには一切触れない。

`<prefix>` 直下の `settings.machine.json`（前節）も同様に保護対象であり、
`uninstall.sh` は `~/.claude/settings.machine.json` という symlink だけを撤去し、
固定パスの実体には触れない。したがって machine 設定を作成済みのマシンでは、
uninstall 後も `<prefix>` 直下に `settings.machine.json` だけが残り続け、
末尾の `rmdir <prefix>`（空のときだけ実行）は恒久的に no-op になる。
**これは意図した挙動である**（人間のマシン設定が uninstall を生き延びる）。

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

## テスト方針

この節は「テストを足すかどうか・どこに書くか」の判断基準を扱う。デプロイ処理を実 `$HOME` を
汚さずに検証する具体的な手順（サンドボックス実行の作り方等）は
「テスト方針（DOC-2608020715-b）」を参照すること。役割が違うので併読する。

### 基本原則

テストも保守対象の production asset であり、無料ではない。書いた分だけ読む・直す・
実行する時間がかかる。**新しいコードや受け入れ条件の数に比例して機械的にテストを
増やしてはいけない。**

**最小限のテストで、意味のある behavior と現実的な regression risk を保護する。**
テスト数・coverage率・テストコード量そのものは目標値ではない。

### 必須性の判断

| 対象 | 方針 |
|---|---|
| 実バグの修正 | そのバグを再現する regression test を必ず追加する |
| destructive / resume / integrity 系（`$HOME` 側 symlink の張り替え・退避、世代の作成・GC、`--rollback` / `--dev` / `--adopt-state`、uninstall の後片付け、状態ファイルの書き戻し等） | 厚くテストする |
| 複雑な pure logic（`shared/helpers.sh` のパス解決・世代判定等） | 不変条件と重要な境界値をテストする |
| public CLI / API / 永続化フォーマット（`bin/ocw` 等のサブコマンド、`.dotfiles-manifest` の形式等） | 外部contractをテストする |
| config / glue | authoritative な層を中心にテストする |
| trivial delegation / private helper | 専用テスト不要をデフォルトとする |

edge case は「思いついたから全部」ではなく、**発生可能性 × 影響度 × 既存coverage**
で追加要否を判断する。コード上で安全に処理されていて低リスクなら、専用テストは要らない。
**壊れないことを確認するのと、専用テストを足すのは別の判断である。**

### 重複防止

新しいテストを追加する前に、必ず既存テストを確認する。

- 既存テストが同じ regression を検出できるなら、新しい test example を追加しない
- 共通処理へ責務を集約した場合、その性質は**共通層で authoritative にテストする**。
  上位 consumer すべてで同じ性質を再テストしない。必要なら代表的な integration を1本だけ置く
- 下位レイヤーで保証済みの性質を、上位 caller から再確認しない

### scenario 統合

複数の受け入れ条件を1つの scenario で検証してよい。**受け入れ条件と test example は
1対1対応ではない。**

実質的に同じ契約を別の test example に分割しない。たとえば「長い文字列が全文出力される」と
「省略記号が出力されない」は、どちらも「truncate されない」という1つの behavior なので、
1つの test example で検証してよい。

### テスト追加時の問い

新しいテストを書く前に、次を自問する。

> このテストが存在しなかった場合、どんな現実的な regression を逃すのか？

明確に答えられず、既存テストでも足りるなら追加しない。

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
`bin,claude,skills,codex,opencode`。デプロイの検証は必ずこのサンドボックス経由で行い、
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
効き（`use_doc_id=false` 時に `docs/` `tools/` `.github/` が生成されないこと）、
`.claude/pr-review.yml`（回答に関わらず常に生成される）の `lint_cmd` / `test_cmd` が
特殊文字を含む回答でも読み戻せて空欄ならキーごと出ないこと・`markers` が既定値であること・
`convention_docs` が `use_doc_id` に応じて出し分けられ参照先が実在することを検証する
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
  `skills` はこの `links_for_tool()` に arm を**持たない**唯一のツールである。配布先が
  「スキルごと × エージェントごと」で可変なため固定リストにできず、`skill_links()` が
  一次情報源になっている。`uninstall.sh` の「No link list defined」ガードは
  `_links` / `_generated` / `_skills_src` の3つが揃って空のときだけ発火するので、
  この判定順を崩さないこと（`_skills_src` をガードより後で解決すると、`skills` が
  警告付きで丸ごとスキップされる）。
- スキルを増やすときは `skills/` にディレクトリを作るだけでよい。`skills/deploy.sh` が
  自動検出する。配布先のエージェントを増やすときは `shared/helpers.sh` の
  `skill_agents()` に名前を足し、`skill_agent_home()` と `skill_dir_for_agent()` に
  arm を追加する。そのエージェントの設定ディレクトリをこのリポジトリが作ってよい場合は
  `agent_home_mode()` にも arm を足す（足さなければ「ディレクトリが実在するときだけ配る」
  という既定の扱いになる。詳細は ADR DOC-2608272128 §2.3）。
- ツールが `$HOME` 側の symlink 経由で世代ディレクトリへ書き戻すファイル（`nvim/lazy-lock.json`
  のような状態ファイル。詳細は「状態ファイル」節）を持つ場合は、`shared/helpers.sh` の
  `state_files_for_tool()` にも arm を追加する。ここに追加し忘れると、デプロイ時の検知・
  `--status` での表示・`--adopt-state` のいずれからも静かに漏れる（`links_for_tool()` と同じ
  一元化の作法）。
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
- **risk-based なテスト方針は、役割を分けて3箇所に持っている。** `skills/pr-review-loop/SKILL.md`
  「テストの判断基準（risk-based testing）」（レビュー時の gate。テスト不足を finding にして
  よいか）、`templates/repo-baseline/template/AGENTS.md.jinja`「テスト方針」（repo-baseline で
  撒いた先の実装者向け）、この `AGENTS.md`「テスト方針」（dotfiles 自身の実装者向け）の3つで、
  参照で済ませず内容を重複して持つ意図的な設計である。**このうちどれか1箇所を変えたら、
  残り2箇所も確認する。** 3箇所は視点（gate と方針）が違うため表現形式や具体例まで揃える
  必要はないが、内容を矛盾させない。優先順位はプロジェクト固有の方針（この `AGENTS.md` や
  撒いた先の `AGENTS.md`）がスキル内蔵のデフォルトに優先する。
