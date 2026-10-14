# AGENTS.md

## 概要

クロスプラットフォーム（macOS / Linux / WSL2）対応の dotfiles。mise でランタイムを固定し、
各ツールディレクトリ（`zsh/` `nvim/` `tmux/` `bin/` `claude/` `skills/`）の `deploy.sh` が、配布実体
（世代ディレクトリ + `current` シンボリックリンク。詳細は「デプロイの仕組み」節）を経由して
ユーザーの `$HOME` に symlink を張ることで設定を配布する。

## 最重要ルール

- **`master` を書き換える操作（マージ・push・force push）は人間だけが行う。例外はない。**
  - 傘ブランチ配下の操作は AI が行ってよい。孫ブランチ → 傘ブランチのマージは**レビューで承認済みの PR に限り**、傘の司令官
    （傘ブランチを進行させる AI）が実行してよい（`gh pr merge <PR番号> --squash --delete-branch`）。
    孫の実装 AI は承認されてもマージせず、司令官へ承認を報告して止まる（孫が人間のフィードバック前に
    勝手にマージするのを防ぐため）。傘ブランチは孫を安全に統合するための隔離された場所であり、
    そこへのマージまで人間待ちにすると傘ブランチ方式が機能しない
  - **上流（`master`）の変更の取り込みは rebase で行う。** 傘ブランチへは
    `git fetch origin` + `git rebase origin/master`、そのあと
    `git push --force-with-lease`（傘のコミットが書き換わるため force push が要る。
    これは想定どおりの操作であり、毎回の確認は要らない）
  - **rebase しない例外は、コンフリクトが多すぎて解消の手間が見合わない場合だけ。**
    そのときに限り `git merge origin/master` を使い、なぜ rebase を諦めたかを PR に書く
  - 孫ブランチを傘ブランチへ追随させるときも同じく rebase で行う
    （`git rebase origin/<傘ブランチ>` + `git push --force-with-lease`）。孫ブランチは
    自分の作業コミットを持つのが通常であり、傘ブランチが他の孫のマージで進んでいれば
    孫と傘は必ず分岐するため、`git merge --ff-only` は使わない
  - **`master` への force push は対象外**（人間だけが `master` を書き換える）
  - `git pull` は AI の判断では使わない。人間が「pull しろ」と指示したときは、
    読み替えず `git pull --ff-only` をそのまま打つ（`--ff-only` なら暗黙の merge
    コミットも rebase も起きず、fast-forward できるときだけ成功する）。**失敗したときは、
    原因（上流との分岐・未コミットの変更との衝突・追跡ブランチ未設定・ネットワークや
    認証のエラーなど）を問わず、`--rebase`・`git merge`・`git stash`・`git reset` などで
    回避して再実行せず、エラー内容を人間に報告して止まる。** 人間は止まることを承知で
    `--ff-only` を選んでいる。
    これは冒頭の「書き換える操作」には当たらない。そこで人間だけが行うのはリモートの
    `master` への反映（マージ・push・force push）であり、ローカルの `master` を
    `origin/master` に追随させる取り込みは含まない（ローカルに未 push のコミットが
    無ければ `--ff-only` は fast-forward するだけで履歴を書き換えない）
  - `git reset --hard` / `git clean` / 裸の `git push --force`（lease なし）は、
    ブランチを問わず引き続き人間の承認が要る
  - `claude/hooks/git-guard.sh`（PreToolUse フック。ADR
    [DOC-2609121719](docs/adr/DOC-2609121719_git-operation-permission-policy.md)
    参照）が機械的に担保するのは**`gh pr merge` の base が保護ブランチかどうか、
    その1点だけ**である。base は PR 側の属性でコマンド文字列に現れず、
    `permissions` のグロブで表現できないため。`main`/`master` への `git push` は
    `claude/settings.json` の `permissions.ask` グロブが受け持つ。
    **それ以外——`git pull` を AI の判断で使わないこと・孫→傘のマージをレビュー承認済みPRに
    限ること・ローカルの `git merge` の向き先——はフックの対象外であり、
    この文言だけが歯止め。** フックは判定できない入力に対して何も言わない
    （`ask` に倒さない）。また `permissions.allow` を返しても `ask` / `deny` を
    上書きできない（制限を足すだけ）ため、`claude/settings.json` 側の
    `ask` / `allow` パターンと矛盾がないか合わせて確認すること

  すべての不可逆操作の前に、この節のルールを照合すること。ただし**この節の禁止は
  「AI が自分の判断で先回りして行わない」ためのものであり、人間が明示的に指示した
  操作まで止めるものではない**（`master` を書き換える操作〔マージ・push・force push〕は
  指示の有無によらず人間が自分で行うので、この限りでない。`git reset --hard` 等の
  承認が要る操作は、人間の明示指示がそのまま承認になる）。人間の指示が明確なら、
  この文書に書かれていないことを理由に拒否せず、安全な手順で実行する。
- **deploy スクリプト（`deploy-all.sh` / `uninstall.sh` / `*/deploy.sh`）を、人間の指示なしに
  AI の判断で実オペレーションで実行しない。人間が「デプロイしろ」と明示的に指示したときは
  実行してよい**（その場合も、先に `./deploy-all.sh --dry-run` を通し、状態ファイルの
  書き戻し差分が無いことを確認してから実行する。非対話環境では `--force` が要るが、
  `--force` は書き戻し差分の破棄も兼ねるため、差分ゼロを確認できたときだけ付ける。
  差分があれば人間に報告して止まる）。理由: `$HOME` 側のシンボリックリンクは配布実体
  （`${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/` 配下の世代ディレクトリ + `current`）を
  経由し、リンクの**向き先**（symlink のターゲット）自体はこの prefix 配下を指す。危険なのは
  向き先ではなく、**リンクを張る先（dst）がユーザーの実 `$HOME`** であることで、`~/.zshrc`
  `~/.tmux.conf` `~/.claude/settings.json` `~/bin/*` という実在のパスを実際に置き換える。世代の
  作成・`current` の切り替え・古い世代の削除も同じ prefix 配下で実際に行われる。動作確認は
  `deploy-all.sh --dry-run`（全ツール対象）で行うのを基本とする。**`deploy-all.sh --status` は
  副作用が無いため実 `$HOME` に対して実行してよいが、`--rollback` と `--dev` は `current` を
  実際に付け替えるため、人間の明示指示なしに AI の判断で `--dry-run` を付けず実 `$HOME` に
  対して実行しない（人間が明示的に指示したときは実行してよい）。**
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

## 作業別の索引

この `AGENTS.md` は毎回読まれる芯だけを持つ。作業に応じて、次の詳細を**先に**読むこと
（`@` import ではなく普通のパスなので、必要なときに自分で開く）。

| 作業 | 先に読むもの |
|---|---|
| デプロイ・uninstall・世代・`--rollback` / `--dev`・`shared/helpers.sh` のリンク一覧 | DOC-2610150520-b（デプロイの仕組み） |
| テストを足す・直す・レビューする | DOC-2610150520-a（テストを足す判断基準） |
| コミット前・スモークテストの選び方 | DOC-2610150520（コミット前の必須ステップ） |
| 新ツール・スキル・配布先の追加、README、`docs/` への言及、テスト方針3箇所 | DOC-2610150520-c（実装時の注意） |
| シェルを書く | DOC-2608020715-a（シェルスクリプトコーディング方針） |
| PR を作る | DOC-2608020715（プルリクエストの作法） |
| 実 `$HOME` を汚さずに検証する | DOC-2608020715-b（テスト方針） |
| `AGENTS.md` 自体を分ける・太らせない | DOC-2610150522（AGENTS.md の芯と詳細の分け方） |

## ディレクトリ構成

| ディレクトリ | 役割 |
|---|---|
| `zsh/` | Zsh 設定（Antidote でプラグイン管理） |
| `nvim/` | NeoVim 設定（lazy.nvim でプラグイン管理） |
| `tmux/` | tmux 設定 |
| `bin/` | スタンドアロンの CLI ツール（`ocw`, `claude-ds`, `ocw-meter`, `persona`, `dfup`, `dfdown`）。`bin/tests/` は `ocw-meter` 等の Python テスト、`bin/prices/` は費用計算用の価格表 |
| `claude/` | Claude Code 向け配布物（`CLAUDE.md` / `settings.json`） |
| `skills/` | AI コーディングエージェント向けのスキル。Claude Code だけでなく Codex・OpenCode にも同じ実体を配る（ADR DOC-2608272128） |
| `codex/` | Codex CLI のグローバル指示（`~/.codex/AGENTS.md`）を、`claude/CLAUDE.md` + 人格のパーソナライズ（`CLAUDE.machine.md`）を連結生成した実ファイルから symlink で配る（基本構造は ADR DOC-2609072334、連結生成の理由は ADR DOC-2609162327 §6） |
| `opencode/` | OpenCode のグローバル指示（`~/.config/opencode/AGENTS.md`）を `claude/CLAUDE.md` から symlink で配る（ADR DOC-2609072334）。加えて `opencode.json` で `instructions` を配り、マシンローカルな人格のパーソナライズを OpenCode にも効かせる（ADR DOC-2609162327 §5） |
| `shared/` | 全 deploy スクリプトが共有するヘルパー（`helpers.sh`） |
| `docs/` | このリポジトリ自体の設計文書・ADR・計画書・運用リファレンス。`design/`（現役の規約）・`adr/`（確定した技術決定の記録）・`planning/`（傘ブランチ計画書）・`reference/`（運用中に繰り返し引く事実）の4フォルダに分かれる。詳細は [docs/README.md](docs/README.md) を参照 |
| `tools/` | このリポジトリ自体の開発を支援するツール（`doc-id` など）。`bin/` と異なり `$HOME` へは配布しない |
| `templates/` | 他リポジトリへ配布する copier テンプレート（`repo-baseline` など）。`$HOME` へは配布せず、dotfiles 本体にも依存しない自己完結ディレクトリ。ただし `repo-baseline` の copier 設定 `copier.yml` だけは `copier update` のためリポジトリのルートにある（ADR DOC-2610110435_copier-root-entry） |

各ツールディレクトリは「設定ファイル本体 + `deploy.sh` + `README.md`」という共通構造を持つ。
例外は `codex/` で、設定ファイル本体を持たず、`deploy.sh` が `claude/CLAUDE.md` + 人格の
パーソナライズ（`CLAUDE.machine.md`）を連結生成した実ファイル（世代を経由しない固定パス。
`shared/helpers.sh` の `dotfiles_codex_agents_md_path()` が一次情報源）を symlink で
指す（内容がエージェント非依存の個人指示であることの基本構造は ADR DOC-2609072334、
Codex だけ連結生成が要る理由〈Codex には追加読み込み手段が無い〉は ADR DOC-2609162327 §6
参照）。`opencode/` も同じ理由で `AGENTS.md`（`claude/CLAUDE.md` の symlink。ただし
Codex と異なり生成を挟まない直接 symlink）を持つが、
`opencode.json`（トラッキング対象のこのツール自身の設定ファイル本体）も持つため、
この例外には完全には当てはまらない。`opencode.json` の役割は「3つの領域」節と
[opencode/README.md](opencode/README.md) を参照。

## 3つの領域（混同しないこと）

| 対象 | 正体 | 誰が読むか |
|---|---|---|
| `claude/CLAUDE.md`, `claude/settings.json` | **配布される成果物。** `claude/deploy.sh` がユーザーの `~/.claude/` 配下へ配置する（`CLAUDE.md` は symlink、`settings.json` は生成。詳細は「デプロイの仕組み」参照） | このリポジトリを使う人間のマシンの Claude Code |
| `opencode/opencode.json` | **配布される成果物。** `opencode/deploy.sh` がユーザーの `~/.config/opencode/` 配下へ symlink する。`instructions` に `~/.claude/CLAUDE.machine.md` を列挙し、マシンローカルな人格のパーソナライズを OpenCode にも効かせる（ADR DOC-2609162327 §5） | このリポジトリを使う人間のマシンの OpenCode |
| `skills/` | **配布される成果物。** `skills/deploy.sh` が各 AI エージェントのスキルディレクトリへスキルごとに symlink する | このリポジトリを使う人間のマシンの Claude Code / Codex / OpenCode |
| ルート `AGENTS.md` / `CLAUDE.md`（このファイル） | **このリポジトリを開発するためのルール** | このリポジトリで作業する AI |
| `.claude/settings.json` | リポジトリで作業する AI 向けの permissions を置く場所 | このリポジトリで作業する Claude Code |

**`claude/CLAUDE.md`（配布物。ルート `CLAUDE.md` とは別物）は、指示が無い限り編集しない。**
人格のパーソナライズ（口調など）は直書きされておらず、マシンローカルな固定パス実体
`CLAUDE.machine.md` への import（`@~/.claude/CLAUDE.machine.md`）のみを持つ（ADR
DOC-2609162327）。`codex/deploy.sh` と `opencode/deploy.sh` もこのファイルを symlink 元に
している（ADR DOC-2609072334）ため、編集の影響は3エージェントへ及ぶことに注意する。
`opencode/opencode.json` はこの import 行とは別経路で、`instructions` から直接
`~/.claude/CLAUDE.machine.md` を指す（`@` import は Claude Code だけが解釈する記法で
OpenCode には効かないため。詳細は ADR DOC-2609162327 §5 / [opencode/README.md](opencode/README.md)）。

## AI 支援ツールの設定

ルールの本体は常に `AGENTS.md`（このファイル）に書く。各 AI 製品向けの設定ファイルは、
ルールを書き写さず `AGENTS.md` を指すことに徹する。新しい AI 製品を使い始めるときも同様に、
その製品の設定ファイルから `AGENTS.md` を参照する形にする。

| AI 製品 | 設定ファイル | 中身 |
|---|---|---|
| Claude Code | `CLAUDE.md` | `@AGENTS.md` の1行のみ |
| opencode | `opencode.json` | `instructions` に `AGENTS.md` と `docs/design/` 配下の規約文書パスを列挙 |

## デプロイの仕組み

`$HOME` はリポジトリの作業ツリーへ直接リンクしない。`deploy-all.sh` は作業ツリーを配布実体
（`${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/generations/` 配下の世代ディレクトリ）へコピーし、
`current` シンボリックリンクをそこへ向け、各 `<tool>/deploy.sh` は `current` 経由で `$HOME` から
リンクする。`claude/settings.json` だけは symlink ではなく、machine 設定とマージした実ファイルを生成する。
マシンローカルな `settings.machine.json` / `CLAUDE.machine.md` は世代を経由しない固定パスに置かれる。

**デプロイ・`uninstall.sh`・`shared/helpers.sh` の `links_for_tool()` / `skill_links()` /
`state_files_for_tool()`・世代・`--rollback` / `--dev` / `--adopt-state`・状態ファイルの書き戻し・
symlink の退避を触るときは、先に
[docs/design/DOC-2610150520-b_デプロイの仕組み.md](docs/design/DOC-2610150520-b_デプロイの仕組み.md)
を読むこと**（採用理由と却下案は ADR
[DOC-2608040229](docs/adr/DOC-2608040229_deploy-distribution-method.md)）。

## クロスプラットフォーム制約

- `shared/helpers.sh` は POSIX sh。bashism を書かない。
- `deploy-all.sh` `uninstall.sh` `*/deploy.sh` も `#!/bin/sh`。
- `bin/ocw` `bin/claude-ds` `bin/persona` は bash（`#!/usr/bin/env bash`）。
- プラットフォーム分岐は `is_macos` / `is_linux` / `is_wsl` / `get_brew_prefix` を使い、
  直接 `uname` を叩かない。
- macOS の BSD 版コマンドと GNU 版の差異（`sed -i`、`date`、`readlink -f` など）に注意する。

## コードの書き方

シェルスクリプトを書く・直すときは
[docs/design/DOC-2608020715-a_シェルスクリプトコーディング方針.md](docs/design/DOC-2608020715-a_シェルスクリプトコーディング方針.md)
を参照すること。POSIX sh / bash の使い分け、bashism の回避、エラーハンドリングの既存方針などを定めている。

## テスト方針

テストも保守対象の production asset。**新しいコードや受け入れ条件の数に比例して機械的にテストを増やさず、
最小限のテストで意味のある behavior と現実的な regression risk を保護する。** テストを足す前に既存テストを
確認し、「このテストが無いとどんな現実的な regression を逃すのか」に答えられなければ足さない。
**テストを足す・直す・レビューするときは、先に
[docs/design/DOC-2610150520-a_テストを足す判断基準.md](docs/design/DOC-2610150520-a_テストを足す判断基準.md)
を読むこと**（必須性の判断表・重複防止・scenario 統合）。デプロイを実 `$HOME` を汚さずに検証する手順は
「テスト方針（DOC-2608020715-b）」を参照する。

## コミット前の必須ステップ

clone 後に初回のみ `uv tool install pre-commit` と `pre-commit install` を実行する。コミット前に
`pre-commit run --files <path>`（手元でまとめて確認するなら `pre-commit run --all-files`）を通す。
デプロイ関連のシェルスクリプトを変えたら `tests/deploy_smoke.sh`、`templates/repo-baseline/` かルートの
`copier.yml` を変えたら `tests/template_smoke.sh`、`bin/` を変えたら
`python3 -m unittest discover -s bin/tests -v` も実行する。`docs/` に新規ファイルを足すときは
`DOC-DOCID_PLACEHOLDER_<名前>.md` で作って `./tools/doc-id/doc-id assign <path>` で採番する。

**AI はこれらのステップを省略しない。省略するのは人間が明示的に指示した場合に限る。**
フックの内訳・各スモークテストが検証する範囲・特殊文字の扱いなどの詳細は
[docs/design/DOC-2610150520_コミット前の必須ステップ.md](docs/design/DOC-2610150520_コミット前の必須ステップ.md)
を読むこと。

## PR 作成時の注意

PR を作る前に
[docs/design/DOC-2608020715_プルリクエストの作法.md](docs/design/DOC-2608020715_プルリクエストの作法.md)
を読むこと。

## 実装時の注意

新しいツールディレクトリ・スキル・配布先エージェント・状態ファイルを足すとき、README を更新するとき、
`docs/` の文書に言及するとき、risk-based なテスト方針の3箇所のどれかを変えるときは、**先に
[docs/design/DOC-2610150520-c_実装時の注意.md](docs/design/DOC-2610150520-c_実装時の注意.md)
を読むこと。** 特に次の2点は常に守る。

- `shared/helpers.sh` の `links_for_tool()` に arm を足し忘れると `uninstall.sh` / `--status` から静かに漏れる
  （`skills` は `skill_links()` が一次情報源）
- `docs/` の文書への地の文での言及には、説明的ファイル名だけでなく DOC-ID を明示する
