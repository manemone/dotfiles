# CLI Tools (bin)

## Overview

自作 CLI ツール集。`~/bin/` に symlink して使う。

| Tool | Purpose |
|---|---|
| `ocw` | Git worktree 作成・管理。Herdr 連携で commander/implementer/reviewer の三面体制を自動セットアップ |
| `claude-ds` | Claude Code を DeepSeek API 経由で実行するラッパー |
| `ocw-meter` | LLM費用・Claude利用枠の観測基盤。既存ログの事後読み取り専用。fail-open |

## 1. Requirements

| Tool | Why | Install |
|---|---|---|
| **Git** | worktree 操作 (`ocw`) | Built-in on most systems |
| **Python 3** | JSON パース (`ocw` Herdr モード) | `mise use python@latest` |
| **claude** (CLI) | `claude-ds` の実体 | `npm install -g @anthropic-ai/claude-code` |
| **DeepSeek API key** | `claude-ds` の認証 | `~/.config/deepseek/api_key` に保存 |
| **VS Code** `code` CLI (optional) | `ocw` のデフォルトモードで worktree を開く | `code` コマンドを PATH に通す（macOS: Cmd+Shift+P → "Shell Command: Install 'code' command in PATH"） |
| **Herdr** (optional) | `ocw --herdr` のマルチペイン管理 | Herdr プロジェクトのインストール手順に従う（スタティックリンクされたバイナリとして配布） |

## 2. Quick Start

新規マシンでは単体の `bin/deploy.sh` ではなく、リポジトリルートの `deploy-all.sh` を実行してください。
`$HOME` 側のリンクは `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/` 配下の配布実体を経由しており、
これを作るのは `deploy-all.sh` だけです。`current` がまだ無い状態で `bin/deploy.sh` を単体実行すると、
エラーで終了し `./deploy-all.sh` の実行を案内されます。

```bash
# 1. リポジトリルートから実行
cd ~/.dotfiles
./deploy-all.sh --only bin

# 2. Restart your shell (or source ~/.zshrc) so ~/bin is on PATH
exec $SHELL -l

# 3. Verify
which ocw
which claude-ds
```

すでに一度 `deploy-all.sh` を実行済みで配布実体（`current`）が存在するなら、
`bin/` ディレクトリから単体の `./deploy.sh` を実行しても構いません。

> **Note**: `~/bin` の PATH 追加は `zsh/.zshrc` が担っています。bash 等他のシェルを使う場合は、各自で `~/bin` を PATH に通してください。

The deploy script:
- Creates `~/bin/` directory if missing
- Symlinks `ocw`, `claude-ds`, and `ocw-meter` into `~/bin/`

## 3. What's Included

### 3.1 ocw — Opinionated Claude Worktree

Git worktree を作成し、オプションで Herdr マルチペイン環境をセットアップする。

```bash
# 基本的な worktree 作成（VS Code で開く）
ocw my-feature

# スラッシュ入りの名前（ブランチ名の名前空間をそのまま使える）
ocw feature/foo

# Herdr 連携（commander/implementer/reviewer の3ペイン）
ocw --herdr my-feature

# ベースブランチを指定
ocw new --herdr my-feature origin/main

# worktree 削除
ocw rm my-feature
ocw rm -f my-feature  # 強制削除（マージ済み判定による拒否・未コミット変更のチェックを迂回する）

# worktree 一覧
ocw ls
```

**Herdr モードのペイン構成:**
- **commander**: 司令塔（デフォルト: `claude`）
- **implementer**: 実装担当（デフォルト: `claude`）
- **reviewer**: レビュー担当（デフォルト: `claude`）

#### 設定（`git config ocw.*`）

`git config` の通常の優先順位（local > global > system）で読む4つのキーで、ワークツリーの作成先やマージ済み判定をカスタマイズできる。**ワークツリーの作成先パスは、無設定なら現行どおりの挙動になる**（`<project>/main` + 兄弟ワークツリーの構成、bare リポジトリ + 同階層の構成のどちらも無設定で動く）。ただし作成先パス以外にも、`ai/` 接頭辞の廃止・`repo_name` の解決順・Herdr ワークスペースラベルの区切り・`ocw rm` の一部挙動など、設定の有無に関わらず現行から変わる点がある（詳細は各節を参照）。リポジトリの `.git/config`（local）に置けばそのリポジトリだけに、`~/.gitconfig`（global）に置けば全リポジトリ共通の既定値にできる。**リポジトリローカルに設定した場合**、`.git/config` は全ワークツリーで共有されるため、bare を含むどのワークツリーから設定・参照しても同じ値が効く。

| キー | 既定 | 意味 |
|---|---|---|
| `ocw.worktreeDir` | `{repo_parent}/{name}` | ワークツリーの作成先を表すフルパス雛形（プレースホルダは次項） |
| `ocw.repoName` | 自動解決（後述） | 表示用のリポジトリ名。`repo:` 行・Herdr ワークスペースラベル・`ocw.worktreeDir` の `{repo}` に使う |
| `ocw.mergedInto` | 自動解決（後述） | `ocw rm` のマージ済み判定で最優先される基準 ref |
| `ocw.githubMergeCheck` | `false` | `true` にすると、マージ済み判定に `gh pr list --head <branch> --state merged` の問い合わせを追加する（opt-in・fail-open） |

Herdr ワークスペースラベルの書式は `<repo_name> :: <slug>` である（区切りは `/` ではなく `::`）。`slug` 自体がスラッシュを含みうる（ネスト方針）ため、`/` のままでは `repo_name` と `slug` の境界が視覚的に区別できなくなることへの対策。

設定例:

```bash
git config ocw.worktreeDir '{repo_root}/.worktrees/{name}'
git config ocw.repoName myrepo
git config ocw.mergedInto develop
git config ocw.githubMergeCheck true
```

#### `ocw.worktreeDir` のプレースホルダ

| プレースホルダ | 意味 |
|---|---|
| `{repo_root}` | メインワークツリーのパス（bare リポジトリの場合はリポジトリ本体のパス） |
| `{repo_parent}` | `dirname({repo_root})` |
| `{repo}` | 解決済みの `repo_name`（下記「レイアウトの実例」の `repo_name` 解決順を参照） |
| `{name}` | ディレクトリ側の名前。ネスト方針（後述）により**ブランチ名そのもの**（`/` を含みうる） |

先頭の `~` は `$HOME` へ展開される。次のいずれかに該当する雛形は `die` する（それぞれ独立した検査であり、まとめて1種類のエラーになるわけではない）:

- **未知のプレースホルダ**（`{rep_root}` のようなタイプミス）を含む — 黙って literal なディレクトリ名にしない
- **`{name}` を含まない**
- **`{name}` の直前に `/` が無い**（例: `{name}` 単体）— 掃除境界（後述）が定義できない
- **掃除境界がファイルシステムのルートになる**（例: `/{name}`）
- **展開結果が絶対パスにならない**（相対パスの雛形）

`ocw rm` はワークツリー削除後、そのディレクトリの親から**掃除境界**（雛形中の `{name}` の直前にある最後の `/` までを展開したパス）に達するまで、空になった親ディレクトリを `rmdir` で遡って削除する。境界そのものは削除しない。同じ親を共有する他のワークツリーが残っていれば `rmdir` が失敗するため、そちらは自然に残る。

| 雛形 | 掃除境界 |
|---|---|
| `{repo_parent}/{name}` | `{repo_parent}` |
| `{repo_root}/.worktrees/{name}` | `{repo_root}/.worktrees` |
| `~/.cache/ocw/{repo}/{name}` | `~/.cache/ocw/{repo}` |

#### レイアウトの実例

| レイアウト | 設定 |
|---|---|
| 現行の兄弟構成（`<proj>/main` + `<proj>/<name>`） | **無設定**（既定 `{repo_parent}/{name}`） |
| bare + 同階層（`<proj>/foo.git` + `<proj>/<name>`） | **無設定**（`dirname(bare リポジトリのパス)` が `{repo_parent}` になるため） |
| リポジトリ内に隠す | `git config ocw.worktreeDir '{repo_root}/.worktrees/{name}'` |
| 中央プールに集める | `git config ocw.worktreeDir '~/.cache/ocw/{repo}/{name}'` |
| 普通の clone の隣に接頭辞付きで置く | `git config ocw.worktreeDir '{repo_parent}/{repo}-{name}'` |

`repo_name`（`{repo}` の展開値）の解決順: 1. `ocw.repoName` が設定されていればそれ。2. `remote.origin.url` の basename から `.git` を剥がしたもの。3. パスからの推測（bare なら `basename(repo_root)` の `.git` 剥がし／`basename(repo_root)` が `main` `master` `trunk` のいずれかなら `basename(repo_parent)`／それ以外は `basename(repo_root)`）。

**「リポジトリ内に隠す」レイアウトの注意**: `{repo_root}/.worktrees/{name}` のように worktree をメインワークツリーの内側に作ると、git はそのディレクトリを自動では無視しない。メインワークツリーの `git status` が常に汚れ、`git clean -fdx` が他のワークツリーごと削除してしまう。このレイアウトを使う場合は、メインワークツリーの `.gitignore` か `.git/info/exclude` に `.worktrees/` を追加すること。

#### ブランチ名・ディレクトリ名

`ocw <入力>` は次の順で処理される。

1. **正規化**（小文字化 → `[a-z0-9._/-]` 以外の並びを `-` に潰す → 連続する `/` を1つに潰す → 先頭・末尾の `/` `-` を除去）。**`/` は潰されず温存される**ため、`feature/foo` のようなブランチ名の名前空間がそのまま使える。正規化だけでも多くの「一見不正な入力」はエラーにならず変換されて通る:
   - `Fix The Thing` → `fix-the-thing`
   - `feature//foo` → `feature/foo`
   - `HEAD` → `head`
   - `-x` → `x`
2. 正規化した結果が空文字列になった入力（記号だけの入力等）は `die` する。この時点で `die` した入力は、次の検証には到達しない
3. **検証**（`git check-ref-format --branch`。自前の正規表現ではなく git 自身のルールに委ねている）。正規化で中和できなかったものだけがここで弾かれる。例: `foo.lock`（末尾 `.lock`）、`..` を含むもの。拒否されると git 自身の `fatal:` メッセージを添えて `die` する。`..` や先頭 `/` もここで弾かれるため、`{name}` をパスへ埋め込む際のパストラバーサル対策もこの検証が兼ねている。

**「不正な名前は全部エラーになる」わけではない。** 正規化で救えるものは変換されて通る。エラーになるのは、正規化を素通りしてなお git のブランチ名ルールに違反するものだけである。

**ブランチ名に `ai/` 接頭辞は付かない。** 既定のブランチ名は正規化した入力そのものであり、`ocw.branchPrefix` のような接頭辞専用の設定も存在しない。接頭辞が欲しい場合は `ocw ai/foo` のように入力側にスラッシュを含めればよい。

ディレクトリはブランチ名の階層をそのまま写す（**ネスト**）: `feature/foo` というブランチは `<ocw.worktreeDir 展開>/feature/foo` に作られる。`git worktree add` が親ディレクトリを自動生成するため、`feature/bar` を後から作っても衝突しない。**`ocw` が作ったワークツリー同士が入れ子で衝突することは、git 自身の ref のディレクトリ/ファイル衝突チェックにより原理的に起こり得ない**（ブランチ `feature` と `feature/foo` は共存できないため、両者のワークツリーディレクトリが互いの祖先になることもない）。ただし `ocw` 管理外の既存ディレクトリとの衝突は普通に起こりうる。その場合は展開先パスの存在チェック（`[ ! -e "$worktree_dir" ]`）が `worktree dir already exists: <path>` で停止する。

**移行**: `ai/` 接頭辞の廃止より前に作成した `ai/foo` ブランチの既存ワークツリーも、`ocw rm foo`（接頭辞なし）で削除できる（後述の `ocw rm` 解決規則の3段目）。

#### `ocw rm` の解決規則

`ocw rm <入力>` は `git worktree list --porcelain` の出力から `(パス, ブランチ)` の対を作り、次の3段で入力に一致するワークツリーを探す。**入力は正規化せずそのまま照合する**（実在する名前を打っている前提のため）。

| 段 | 条件 |
|---|---|
| 1 | ブランチ名の完全一致 / ワークツリーの絶対パスの完全一致 / 掃除境界からの相対パス一致 |
| 2 | ワークツリーディレクトリの `basename` 一致 |
| 3 | ブランチ名が `*/<入力>` で終わる（旧 `ai/*` 接頭辞からの移行救済） |

**先に非空になった段の結果を採用する。同一段で複数ヒットした場合は、候補（パスとブランチ）を全て標準エラー出力に並べて `die` する**（自動選択はしない。破壊的操作なので、曖昧なら利用者に完全な名前を打たせる）。メインワークツリーと bare エントリは常に削除候補から除外される。

#### マージ済み判定の意味論

`ocw rm`（`-f` 無し）は、ブランチが「マージ済み」と判定できない限り拒否される。

**基準 ref（integration ref）の候補**を次の順で集め、解決できない候補は黙って読み飛ばす。すでに他の候補と同じコミットに解決済みの候補（`ocw.mergedInto` と作成時の base ref が同じコミットを指す、等）も読み飛ばす。1つも残らなければ「基準が決まらない」として `die` し、`ocw.mergedInto` の設定か `-f` の使用を案内する。

| 順 | 候補 |
|---|---|
| 1 | `ocw.mergedInto`（設定） |
| 2 | **作成時の base ref**（`ocw <name> [base-ref]` で指定・解決されたベース。worktree の git 管理領域に保存され、`ocw rm` 側で読み戻す） |
| 3 | bare なら `git symbolic-ref --short HEAD` / 非 bare なら `repo_root` の現在の `HEAD` |
| 4 | `git symbolic-ref --short refs/remotes/origin/HEAD` |

**各候補に対して、次のa・bを順に試す**（いずれか1つでも真ならその時点で「マージ済み」と確定し、残りの候補は見ずに打ち切る）:

a. `git merge-base --is-ancestor <branch> <candidate>`（通常の ancestry 判定）
b. **squash マージ検出**（`commit-tree` + `git cherry` によるパッチID比較のレシピ。GitHub の squash merge のようにコミット履歴に痕跡が残らないマージも検出できる）

**全ての候補で a・b の両方が偽だった場合に限り、最後に次の c を1回だけ評価する**（候補ごとではない。PR のマージ状態はどの基準 ref と比べるかに依存しないため、候補の数だけ同じ問い合わせを繰り返す意味がない）:

c. `ocw.githubMergeCheck` が `true` かつ `gh` が PATH にある場合のみ、`gh pr list --head <branch> --state merged` を問い合わせる（**opt-in**。既定は `false` — ネットワーク・認証への依存を既定経路に持ち込まないため。`gh` の失敗・未認証・ネットワーク不通は「判定できなかった」として無視され、`ocw` 自体は落ちない）

候補2（作成時の base ref）は傘ブランチ運用を直接救う: 孫ブランチは `main` ではなく傘ブランチにマージされることが多く、これが無いと ancestry・squash のどちらの判定も傘ブランチ自身を基準にできず、`ocw rm` は常に失敗していた。

**検出できない限界**（正直に書いておく）: squash マージ後に統合先で rebase・amend されて patch-id が変わった場合や、マージ時の衝突解決で diff が変わった場合は、squash 検出も見逃す。この場合はマージ済みであっても `-f` が必要になる。

**`run.end` の `outcome` は `-f` の有無ではなく、上記の判定結果から決まる**:

```
outcome = マージ済みと判定できた → success
          そうでない             → failure
```

`-f` は「未マージ・未コミット変更が残っていても拒否をスキップする」フラグであり、判定そのものはスキップしない。squash マージ済みのブランチを `-f` で消しても `outcome` は `success` になる（`ai/` 接頭辞廃止・マージ判定再定義より前は、`-f` を使った時点で無条件に `failure` として記録されていた）。

**工程計測（`ocw-meter` 連携。fail-open）:**

worktree作成のたびに `run_id` を採番し、標準出力に `run:` 行として表示する。
`run_id` は worktree の git管理領域（`git -C <worktree> rev-parse --absolute-git-dir` が指す
`ocw-run-id` というファイル）に保存され、`ocw rm` 実行時にそこから読み戻されて `run.end` イベントの
記録に使われる。この管理領域は `.git/worktrees/<worktree ディレクトリの basename>/` を基本形に
git が内部的に名付けるが、**同じ basename のワークツリーが複数あると `foo1` のような連番付きの別名
になる**（`feature/foo` と `hotfix/foo` はどちらも basename が `foo` だが、ネスト方針上は両方同時に
存在できる）。したがって `<slug>` や basename からパスを自分で組み立てて読みにいってはならず、
常に `git -C <worktree> rev-parse --absolute-git-dir` で解決すること。`bin/ocw` 自身もこの規則には
依存せず、常に `rev-parse --absolute-git-dir` 経由で読み書きしている。この領域は git worktree の
削除時に自動で掃除される、リポジトリには一切入らない場所である。

Herdrモードでは、commander/implementer/reviewer の各ペイン起動時に環境変数
`OCW_ROLE`（`commander`/`implementer`/`reviewer`）と `OCW_RUN_ID` が `herdr workspace create --env` /
`herdr pane split --env` 経由で自動的に渡される。`ocw-meter event` はこれらの環境変数を
自動的に読み取り役割・runを紐付けるため、呼び出し側で明示的に指定する必要はない。

**非Herdrモード（`ocw <name>`、VS Codeを開く既定モード）では `OCW_RUN_ID` は自動では渡らない。**
`run_id` は `run:` 行と `ocw-run-id` ファイルには保存されるが、それを読んで環境変数へ載せる主体が
Herdrのペイン起動以外に存在しないため、そのworktree内で動く `ocw-meter event`（`pr-review-loop` の
工程イベント等）は明示的にexportしない限り `run_id: null` として記録される。紐付けたい場合は
worktree内で以下を実行してから作業を始めること:

```bash
export OCW_RUN_ID="$(cat "$(git rev-parse --absolute-git-dir)/ocw-run-id" 2>/dev/null)"
```

`ocw-meter` が PATH に無い場合、`run:` 行と `ocw-run-id` の保存は変わらず行われる
（純粋なgit/bashロジックのため）が、`ocw-meter event` 呼び出しは `command -v` ガードにより静かにスキップされ、
`ocw` 自体の動作・終了コードには一切影響しない。`ocw-meter` はあるがそのイベントの書き込みだけが失敗する場合
（例: `OCW_METER_HOME` が読み取り専用）も、`run_id` の採番・`run:` 出力・`ocw-run-id` の保存・`ocw` 自体の
終了コードは影響を受けない（fail-open）。ただし `ocw-meter` 自身は書き込み失敗を stderr に1行warnとして出す
設計（`bin/ocw-meter` 自身の既知の限界。誤りを隠さない方針のため）であり、これは `ocw` の出力への追加として
現れうる。

**`run.end` が記録されない run が存在しうる**（best-effort の限界）: `ocw rm` は「マージ済みと
判定できない」「未コミット・未追跡の変更がある」等で `die` して停止する経路が複数あり、そこに
到達する前に停止した場合は `run.end` が一切記録されない。`-f` はこれらの拒否をスキップするが、
それでも対象が解決できない・曖昧・カレントワークツリー自身である・`git worktree remove` 自体が
失敗する、といった経路では `-f` の有無に関わらず途中で停止し `run.end` は記録されない。**完了時に**
（＝拒否されず最後まで進んだ場合に）記録される `outcome` は、前述のとおり `-f` の有無ではなく
マージ判定の結果から決まる（マージ済みと判定できれば `success`、できなければ `failure`）。

### 3.2 claude-ds — Claude Code via DeepSeek API

Claude Code CLI を DeepSeek API に繋ぎ替えて実行する。`exec env` で以下の環境変数を**すべて上書き固定**する。`claude "$@"` で CLI 引数は素通しされるため `--model` 等のオプションは通常通り指定可能だが、デフォルトモデルは以下の値に固定される:

```bash
claude-ds
# 実体:
#   ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
#   ANTHROPIC_AUTH_TOKEN="<キーファイルの中身>"
#   ANTHROPIC_MODEL="deepseek-v4-pro[1m]"
#   ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-pro[1m]"
#   ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-pro[1m]"
#   ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek-v4-flash"
#   CLAUDE_CODE_SUBAGENT_MODEL="deepseek-v4-flash"
#   claude "$@"
```

| モデル種別 | 固定値 |
|---|---|
| メイン / Opus / Sonnet | `deepseek-v4-pro[1m]` |
| Haiku / subagent | `deepseek-v4-flash` |

API キーは `DEEPSEEK_API_KEY_FILE` 環境変数で指定可能（デフォルト: `~/.config/deepseek/api_key`）。

### 3.3 ocw-meter — LLM費用・Claude利用枠の観測基盤

`ocw` / `claude-ds` / `pr-review-loop` の**本番経路には一切割り込まない**、事後読み取り専用の観測ツール。
設計の経緯・意思決定の背景は `docs/planning/DOC-2608021229-a_ai-llm-cost-observability_計画.md`（計画書。
傘の完了とともに歴史的記録になる）を参照。**イベントスキーマ（全フィールド・全event_type・
idempotency_keyの生成規則・費用計算式・schema_versionの変更ルール）の一次情報源は計画書ではなく
[`docs/reference/DOC-2608021229-c_ocw-meterイベントスキーマ.md`](../docs/reference/DOC-2608021229-c_ocw-meterイベントスキーマ.md)。**
運用手順（ベースライン計測）は
[`docs/reference/DOC-2608021229-b_LLM費用観測ベースライン計測手順.md`](../docs/reference/DOC-2608021229-b_LLM費用観測ベースライン計測手順.md)を参照。

**観測は fail-open。`ocw-meter` が無くても、PATH から消えても、書き込みに失敗しても、
本スキル・`ocw` は完全に動作し続ける。** 呼び出し側は必ず次の形で呼ぶ:

```bash
command -v ocw-meter >/dev/null && ocw-meter event ... || true
```

```bash
# 任意のイベントを1行append（--key value で任意フィールドを上書き・追加可能）
ocw-meter event <event_type> [--key value ...]

# PRの後付けbind（run_id → PR番号）
ocw-meter bind-pr --run <run_id> --pr <n> [--url <url>]

# ~/.claude/projects/*/*.jsonl を走査し usage.message イベントを生成（冪等・増分）
ocw-meter ingest [--since <rfc3339-ts>]

# 保存済みイベントのschema検証。壊れた行はquarantineへ隔離
ocw-meter validate [--file <path>]

# イベント件数・completeness・coverage・推定費用の要約
# --pr <n> を付けるとレビューラウンド一覧・人間介入回数・最終結果・
# 同一5時間窓完走可否・そのPRのcash cost内訳も併せて出す
ocw-meter report [--pr <n>] [--repo <owner>/<name>] [--json]

# 工程別（phase.start/endの時間ペアとusage.messageの時刻範囲による
# ベストエフォート対応）のトークン・費用・所要時間
ocw-meter report --phase [--pr <n>] [--repo <owner>/<name>] [--json]

# provider+model別のトークン・推定費用
ocw-meter report --model [--pr <n>] [--repo <owner>/<name>] [--json]

# role（commander/implementer/reviewer/unknown）別のイベント数・トークン・推定費用
ocw-meter report --role [--pr <n>] [--repo <owner>/<name>] [--json]

# 5時間窓（window_id）別のquota.sample集計。直接紐付き/時間範囲重複の
# PRを別フィールドで提示
ocw-meter report --window [--pr <n>] [--repo <owner>/<name>] [--json]

# 月次: cash cost（従量API）/ capacity cost（Claudeサブスク枠）/
# process efficiency（承認済みPRあたりの費用・ラウンド数等）を分離して表示
# --reconcile とは別物（こちらは突合をしない）
ocw-meter report --month [YYYY-MM] [--repo <owner>/<name>] [--json]

# model別トークン集計・推定費用・provider管理画面との突合（coverage比率）
ocw-meter report --reconcile [--month <YYYY-MM>] [--provider-total <model>=<tokens> ...] [--json]

# statusLineコマンドとして呼ばれ、stdinのJSONからquota.sampleを1行append、表示文字列をstdoutへ返す
ocw-meter snapshot-quota

# state/meter-errors.jsonl・state/quota-worktree-refusal.jsonの古いエントリを掃除する（events/には触れない）。
# 既定はdry-run。--applyで実削除、--older-than <日数>で保持期間指定（既定30日）
ocw-meter prune-diagnostics [--older-than <days>] [--apply]
```

| サブコマンド | 失敗時の挙動 |
|---|---|
| `event` / `bind-pr` | **常に exit 0**。stderrに1行warnのみ。本番フローを止めない |
| `snapshot-quota` | **常に exit 0 かつ必ずstdoutに表示文字列を出す**（statusLineが壊れて画面が崩れる事態を絶対に避ける。event/bind-pr以上に厳格なfail-open） |
| `validate` / `report` / `ingest` / `prune-diagnostics` | 失敗したら非ゼロで落ちる（壊れたデータを黙って集計しない） |

**`--repo <owner>/<name>`（`--pr`・standalone `--month`専用。孫5後半で追加）**:

`~/.local/state/ocw-meter`は本マシンの`ocw-meter`が向いた**全リポジトリで共有される1つのストア**だが、
PR番号はリポジトリ**内**でしか一意でない。`--pr`とstandaloneの`--month`（`process_efficiency`集計）は
どちらもこの「どのリポジトリのPR番号か」を解決する必要があり、通常はカレントディレクトリの
`git remote get-url origin`から自動解決される。**git管理外のディレクトリから実行した場合や、
`origin` remoteが無い場合は自動解決できず、`--pr`/standalone `--month`はfail-loudでエラーになる**
（黙って別リポジトリの同番号PRにスコープする、または全イベントを取りこぼす、のどちらの誤動作も避けるため）。
そのようなときは`--repo <owner>/<name>`で明示指定する（`<owner>/<name>`の形式、両側非空でなければ拒否される）。

典型的にこれが必要になるのは、**PRのworktreeを`ocw rm`した後**（`docs/reference/DOC-2608021229-b_...`§2.1の
手順どおりworktree削除前にingestしていれば通常は発生しない）に、別の場所から`report --pr <N>`を
取り直す場合。`--repo`は`--pr`または（`--reconcile`を伴わない）standaloneの`--month`と組み合わせない限り
一切参照されないフィールドのため、それ以外の組み合わせ（`--repo`単体、`--model`と`--repo`のみ等）で
渡すとエラーになる（値を受理して黙って無視する、という状態を避けるため）。

**`ingest` の要点（`docs/planning/DOC-2608021229-a_..._計画.md` 孫3プロンプト / DOC-2608021229 §8 準拠）:**

- **`message.id` で重複排除する。** 1レスポンスがcontent blockごとに複数行へ分割追記されるため
  （実測: assistant行の59.4%がmessage.id重複、DOC-2608021229 §2.2）、素朴に合計すると2倍以上の過大計上になる。
  同一message.idの行が複数あれば**ドキュメント順で最後の行**（usage/stop_reasonが最も完全）を採用する
- **冪等**。`state/ingest-cursor.json` に transcriptファイルごとの (inode, size, mtime, offset) を保持し、
  差分だけ読む。カーソルは書き込み成功後にのみ保存されるため、途中で中断しても再実行で結果が変わらない。
  inode変化・サイズ縮小（ローテート/切り詰め）を検出したら該当ファイルを頭から読み直す
  （重複は message.id キーで自然に吸収される）
- **`message.content` には一切触れない。** 抽出するのは `id`/`model`/`usage`/`stop_reason`/`timestamp`/
  `sessionId`/`gitBranch`/`cwd`/`isSidechain`/`effort` のみ
- 費用推定は `bin/prices/*.json` から。**Anthropicモデル（`claude-*`）は定額契約のため
  `cost_estimate_usd: null` / `cost_basis: "subscription"`**（API単価には換算しない）。
  価格表に無いモデルは `cost_estimate_usd: null` / `completeness: "unknown"`
- role の帰属は Herdr (`herdr pane list`) から解決する。`run_id` はメッセージ自身の `cwd`（=
  worktree）にある `<git-dir>/ocw-run-id` を直接読んで解決する（`bin/ocw` が `git worktree add` 直後に
  書き込み、`ocw rm` が読み戻すのと同じファイル・同じ仕組み）。PR番号は ①その`run_id`に対する
  `pr.bind`（`state/session-pr-links.json` とは別に、このmeter自身のイベントストアから解決）
  ②`state/session-pr-links.json` に永続化されたtranscriptの `pr-link` 行（増分実行をまたいでも保持される）
  ③`gh pr list --head` フォールバック、の順。どれも失敗したら
  `role: "unknown"` / `pr_number: null` / `run_id: null`。**推測で埋めない**
- `--since <ts>` を渡した実行は**増分カーソルを進めない**（読み取り専用）。`--since` でスキップした
  期間を後から `--since` 無しで実行すれば取り込まれる — カーソルが先に進んで永久に欠落することはない
- メッセージの費用は**そのメッセージ自身のtimestampの日付**に対応する価格表で計算する（`ingest`を
  実行した日ではない）。過去に書き込んだイベントの `cost_estimate_usd` は、価格表を追加・更新しても
  **再計算されない**
- `report --reconcile` の月境界は**UTC固定**。DeepSeek管理画面（北京時間 UTC+8想定）等、provider側の
  集計タイムゾーンと異なる場合、月初・月末で最大±8時間分のずれが突合結果に生じうる（計画書17章 R8）

**`snapshot-quota` の要点（詳細設計: `docs/planning/DOC-2608021229-a_..._計画.md` §8.5 / DOC-2608021229 §2.1・§8）:**

- `claude/settings.json` の `statusLine` から `ocw-meter snapshot-quota` として呼ばれる想定
  （`claude/README.md` §3.4 参照）。stdinのstatusLine JSONから `quota.sample` イベントを1行appendし、
  ステータスバー表示文字列（例 `5h:37% 7d:12% ctx:24%`）をstdoutへ返す
- **例外が起きても必ずstdoutに表示文字列を出しexit 0する。** 空入力・不正JSON・巨大入力・
  `rate_limits`欠落のいずれでも壊れない
- **サンプリング間隔を自制する**（既定60秒、`OCW_METER_QUOTA_INTERVAL`で変更可）。statusLineは
  描画のたびに呼ばれるため（実測 最大54回/時間、DOC-2608021229 §2.1）、間隔内の呼び出しは
  `state/quota-last-sample.json` を見て書き込みをスキップし、表示文字列の計算のみ行う
- `rate_limits`（5時間枠・週間枠）が無いセッション（`claude-ds`＝DeepSeek経由は原理的に常にこれ）は
  `five_hour_used_pct`等を`null`、`completeness: "unknown"`として記録する。**推測で埋めない**
- `rate_limits.five_hour.resets_at` が既に過去の時刻（stale値。DOC-2608021229 §2.1で実測: 8サンプル中3件）の
  場合、`window_id`を`null`にして`completeness: "partial"`で記録する（stale値を新しい窓のIDとして
  採用しない）。同一`window_id`内で`used_percentage`が前回より減少した場合も`partial`にしstderrへ警告する
- `context_window.used_percentage`が`null`の場合、**記録するイベントの`context_used_pct`フィールドのみ**
  `total_input_tokens / context_window_size`からフォールバック計算する（DOC-2608021229実測: 66サンプル中7件がnull）。
  **statusLineの表示文字列にはこのフォールバック値を使わない**（DOC-2608021229 §8-7: 生の`used_percentage`が
  `null`の場合、フォールバック計算できても`ctx`セグメント自体を表示しない）
- statusLineの`cost.total_cost_usd`（Claude Code自己申告のセッション累積コスト）を`session_cost_usd`
  として記録する。`usage.message`の`cost_estimate_usd`（ocw-meter自身の推定値）とは**別カラム**であり、
  合算しない
- `report --pr <n>` はPRの最初と最後のイベント時刻の範囲に収まる`quota.sample`の`window_id`を集計し、
  同一5時間窓で完走できたか（`five_hour_window_completion`: `yes`/`no`/`unknown`）を出力する。
  **判定はレビュー待ち等の待機時間を含むPRの実時間レンジで行う**（＝PRが長時間openだと、
  実作業がどれだけ短くても`no`になりやすい。「実装に要した時間」ではなく「イベント時刻の
  span」で見ている点に注意）
- **同一`window_id`内でのサンプル間の消費量差分（累積消費のグラフ化等）は現時点では未実装。**
  `snapshot-quota`が記録するのは`window_id`と`five_hour_used_pct`の各時点の値のみで、差分算出・
  グラフ化・時系列集計は将来の集計レポート機能で扱う想定（現時点では`report --pr`の
  同一窓完走判定にのみ利用している）
- `OCW_METER_RAW=1`のときのみ、redaction済みのstatusLine生JSONを`raw/YYYY-MM-DD/`へ保存し、
  イベントの`raw_ref`にそのパスを記録する（既定では一切保存しない）
- **事前準備（必須）**: `ocw-meter` が PATH に無い環境では statusLine コマンド自体が
  `command not found` になり表示が壊れる。必ず先に `./deploy-all.sh --only bin`
  （リポジトリルートから）を実行して `~/bin/ocw-meter` を配置し、`~/bin` が PATH に
  入っていることを確認すること（本ドキュメント §5 参照）

**保存先と環境変数:**

| Variable | Default | Purpose |
|---|---|---|
| `OCW_METER_HOME` | `~/.local/state/ocw-meter` | 保存先ルート。**git worktree内を指すと拒否される**（誤commit防止）。`event`/`bind-pr`は書き込みをスキップして exit 0（設定ミスが誰にも気づかれないままにならないよう、既定の保存先へ `meter.error` を1件/日で記録し、fallbackした旨をstderrに警告する）、`validate`/`report`/`ingest`は非ゼロで停止する |
| `OCW_METER_RAW` | `0` | `1`にすると `snapshot-quota` がredaction済みのstatusLine生JSONを `raw/YYYY-MM-DD/` へ保存する（既定オフ） |
| `OCW_METER_CLAUDE_PROJECTS_DIR` | `~/.claude/projects` | `ingest` がtranscriptを探すディレクトリ |
| `OCW_METER_PRICE_DIR` | `<symlink を解決した先にある ocw-meter の実体のディレクトリ>/prices` | `ingest` が価格表(`*.json`)を探すディレクトリ |
| `OCW_METER_INGEST_USE_GH` | `0` | `1` にすると、PR番号未解決時に `gh pr list --head <branch>` へフォールバックする（既定オフ = ネットワークを一切叩かない） |
| `OCW_METER_QUOTA_INTERVAL` | `60`（秒） | `snapshot-quota` が実際に `quota.sample` を書き込む最短間隔。数値でない値・負値は既定値にフォールバックする |

**`quota.sample` の保存量について（計画書 §9.1 の前提を上回る規模）**: 計画書 §9.1 の
「JSONLで十分」という判断は「全期間で39,805メッセージ、1イベント約600B」という実績に基づくが、
`quota.sample` は実測 **約1,022B/件**で、既定60秒スロットルの上限（＝1セッションあたり最大60件/時）
まで書き込まれうる。Herdr の commander/implementer/reviewer 3ペイン構成で1日10時間稼働した場合、
理論上限は 60件/時 × 10時間 × 3セッション × 365日 ≈ **65.7万件/年（約650MB/年）**で、
既存の全履歴（39,805件、`usage.message`等これまでの累計実績）を1年で一桁上回りうる規模になる
（実際の呼び出し頻度は DOC-2608021229 §2.1実測で最大54回/時であり、スロットルが常に上限まで
効くとは限らないため、これは理論上限であって実測の目安ではない）。

現時点では自動的なローテーション・削除の仕組みは無い（`OCW_METER_RAW=1`時の`raw/`ディレクトリを除き、
`events/`全体に対する`prune`相当のサブコマンドは未実装）。`ocw-meter report`/`validate`は
`events/`配下を毎回全走査するため、上記規模になった場合はその実行時間にも影響する。
運用上は、`OCW_METER_QUOTA_INTERVAL`を既定の60秒より大きくする、または手動で古い
`events/YYYY-MM-DD.jsonl`を別途アーカイブ・削除する、のいずれかを検討すること。

**`prune`を実装しない決定について（孫5、計画書9.3の積み残し解消）**: 計画書9.3は
「保存期間: 既定14日、`ocw-meter prune`で削除」と書いていたが、`prune`はどの孫の実装スコープにも
入っておらず、計画時の書き漏れだった。孫5で以下の理由により**意図的に未実装のまま据え置く**と決定した:

- `events/`（費用履歴そのもの）は数十MB/年〜数百MB/年規模（上記実測）であり、資産として残す価値が
  ディスクコストを上回る。誤って自動削除する仕組みを持ち込むリスクの方が大きい
- `raw/`（`OCW_METER_RAW=1`時のみ生成、既定オフ）は元々opt-inかつ再現性の低い生データであり、
  肥大化した場合は`rm -rf ~/.local/state/ocw-meter/raw/`で無条件に安全に削除できる
  （events/やstate/には一切影響しない、独立したディレクトリのため）
- 自動削除ロジック（cron等）を追加すること自体が「観測は本番フローに一切割り込まない」という
  本傘の設計方針（計画書§7.1）に新しい可動部を足すことになり、費用対効果に見合わない

必要になった場合の手動削除パス（**いずれもocw-meterの動作を止めない**）:

```bash
# raw/ を丸ごと削除（既定では空。OCW_METER_RAW=1を使った場合のみ意味がある）
rm -rf ~/.local/state/ocw-meter/raw/

# 古いイベントファイルを個別に削除（費用履歴が失われる点に注意）
rm ~/.local/state/ocw-meter/events/2026-01-*.jsonl
```

将来もし実際に運用上の困りごと（`report`/`validate`の実行時間が無視できなくなった等）が出た場合は、
その時点で`ocw-meter prune`の実装を独立したPRとして起票すること（本PRのスコープには含めない）。

保存レイアウト: `events/YYYY-MM-DD.jsonl`（基本はappend-only, mode 600。**例外**: 同一`idempotency_key`を再送すると
後勝ち(last-write-wins)でその日のファイル内の該当行をmkstemp+os.replaceで原子的に置き換える）/
`state/seen-keys/YYYY-MM.txt`（`idempotency_key`による重複排除）/
`quarantine/YYYY-MM-DD.jsonl`（`validate`が隔離した破損イベントの隔離先）/
`quarantine/ingest-transcript.jsonl`（`ingest`が隔離した破損transcript元行の隔離先。前者とは別カウントで
`report`に出る。生コンテンツは保存しない）/
`state/ingest-cursor.json`（`ingest`の増分読み取りカーソル）/
`state/session-pr-links.json`（`ingest`がtranscriptの`pr-link`行から学習したsession→PRの対応。
増分実行をまたいで保持される）/
`state/meter-errors.jsonl`（`meter.error`自己診断専用。
`events/`とは別ファイルにすることで、後勝ちdedupによるイベントファイル書き換えと競合せずlock無しで追記できる。
ただし `ocw-meter prune-diagnostics --apply` はこのファイルを丸ごと書き換える唯一の例外で、
書き換えの瞬間と重なった追記1行を失う可能性がある）/
`state/quota-last-sample.json`（`snapshot-quota`のサンプリング間隔自制・同一window内の異常値検知に使う
直近サンプルの状態）/
`raw/YYYY-MM-DD/*.json`（`OCW_METER_RAW=1`のときのみ。`snapshot-quota`が保存するredaction済みの
statusLine生スナップショット。既定では作成されない）。
ディレクトリは mode 700。`ocw-meter report` は `meter-errors.jsonl` の件数も表示する。

**プライバシー方針**: プロンプト全文・モデル応答全文・ソースコード本文・APIキー・認証ヘッダ・トークン類は
一切保存しない。`--key value` で渡された値のうち `sk-...`（任意長）/ `Bearer ...` / `Authorization: ...` /
GitHub token形式（`ghp_...` 等 / `github_pat_...`）に一致する値、キー名が
`api_key` / `token` / `secret` / `password` / `authorization` に一致するものは保存前に `[REDACTED]` へ置換される。
この置換は保存物だけでなく、meterが出す例外・警告メッセージにも適用される。

**既知の限界（カバレッジは「全部取れている」ものではない — 計画書5.10 / DOC-2608021229 §2.2 実測）**:
- **`deepseek-v4-flash` はtranscriptに一切記録されない（実測カバー率 0%）。** タイトル生成・要約等の
  背景ユーティリティ呼び出しやサブエージェント（`CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash`）分は
  `~/.claude/projects/*.jsonl` に現れないため、`ingest` では原理的に取得できない
- **`deepseek-v4-pro` のtranscriptカバー率は実測で約89%。** 残り約11%は他マシン・別期間・
  streaming中断/retryで課金されたが記録されない分などが要因（正確な内訳は provider管理画面との
  突合が必要 — `ocw-meter report --reconcile --provider-total <model>=<tokens>` を使うこと）
- `snapshot-quota`（Claude利用枠取得）は `claude-ds`（DeepSeek経由）セッションでは `rate_limits` を
  原理的に取得できない（Claude.aiサブスクリプションの利用枠であり、DeepSeek APIには適用されない）。
  また5時間枠に到達して待機した際の挙動は未観測（その状況が発生した際のログをまだ収集できていない）であり、`blocked`の検出は
  best-effort（`claude/README.md` §3.4参照）
- PR紐付け（`pr-link`）は`ingest`実行時点で読めた範囲の情報に基づく。transcriptへの`pr-link`追記が
  後から起きても、既に書き込み済みの`usage.message`イベントは遡って更新されない
  （`cost_estimate_usd`と同じ「過去は再計算しない」方針）
- `event`/`bind-pr` は1呼び出しごとに git メタ情報の解決（subprocess呼び出し数回）と
  月次seen-keysファイルの全読み込みを行う（実測 約75ms/回）。`ocw`/`pr-review-loop` の工程境界イベント
  （1runあたり数十件）には十分だが、**大量イベントをループでこのCLI経由で書き込む用途には向かない**。
  `ingest` はこの制約を踏まえ、Herdr/run/pr情報を1回だけ解決し、seen-key集合と書き込みロックを
  バッチ全体で保持する専用パス（`bulk_write_events`）を持つ
- **`usage.message`の`run_id`は、`ingest`をworktree削除（`ocw rm`）より後に実行すると解決できない
  （孫5で実データ検証して判明。実測: このマシンの実ストア44,425件の`usage.message`のうち`run_id`が
  設定されているものは0件）。** `run_id`解決（`resolve_run_id_via_ocw_run_id_file`）は、その
  メッセージの`cwd`（worktreeパス）配下の`<git-dir>/ocw-run-id`ファイルを**ingest実行時点**で
  読む方式であり、`ocw rm`はそのファイルをworktreeごと削除する。一度`run_id`無しで書き込まれた
  `usage.message`は、後から同じtranscriptを再ingestしても直らない（他のフィールドと同じ
  「過去は再計算しない」不変条件のため）。`ocw-meter report --phase`（工程別トークン内訳。
  `run_id`でphase.start/endの時間窓と対応付ける — `docs/reference/DOC-2608021229-c_...`§2.3参照）を
  意味のある形で使うには、**PRの作業中〜マージ直後、worktreeを消す前に`ocw-meter ingest`を
  実行する運用が必須**（`docs/reference/DOC-2608021229-b_...`§2の計測手順に反映済み）。`--model`/`--role`/
  `--pr`はこの制約の影響を受けない（`run_id`ではなく`model`/`role`/`pr_number`を直接見るため）

## 4. Customization

### ocw のコマンド差し替え

環境変数で commander / implementer / reviewer の実行コマンドを上書きできる:

```bash
# DeepSeek を使う場合（旧デフォルト）
export OCW_COMMANDER_COMMAND=claude-ds
export OCW_IMPLEMENTER_COMMAND=claude-ds

# 別のツールを指定
export OCW_REVIEWER_COMMAND=claude
```

| Variable | Default | Purpose |
|---|---|---|
| `OCW_COMMANDER_COMMAND` | `claude` | commander ペインで実行するコマンド |
| `OCW_IMPLEMENTER_COMMAND` | `claude` | implementer ペインで実行するコマンド |
| `OCW_REVIEWER_COMMAND` | `claude` | reviewer ペインで実行するコマンド |

### claude-ds の API キー設定

```bash
# デフォルトのキーファイル
mkdir -p ~/.config/deepseek
echo "sk-your-api-key" > ~/.config/deepseek/api_key
chmod 600 ~/.config/deepseek/api_key

# 別の場所に置く場合
export DEEPSEEK_API_KEY_FILE=/path/to/your/api_key
```

## 5. Troubleshooting

### `which ocw` returns nothing

`~/bin` の PATH 追加は `zsh/.zshrc` のシェル起動時チェックに依存しています。`deploy.sh` で `~/bin` を新規作成した直後は、シェルを再起動してください:

```bash
exec $SHELL -l
```

bash 等他のシェルを使う場合は、各自で `~/bin` を PATH に通してください。

### `error: Herdr server is not running. Start or attach first with: herdr`

`ocw --herdr` は Herdr サーバーが起動している必要があります。先に `herdr` を実行してサーバーを起動するか、アタッチしてください。

### `Error: DeepSeek API key file not found: ~/.config/deepseek/api_key`

`claude-ds` の API キーが未設定です。以下を実行してください:

```bash
mkdir -p ~/.config/deepseek
echo "sk-your-api-key" > ~/.config/deepseek/api_key
chmod 600 ~/.config/deepseek/api_key
```

別のパスにキーを置く場合は `DEEPSEEK_API_KEY_FILE` 環境変数で指定してください。

### `error: run ocw from inside a Git repository`

`ocw` は Git リポジトリ（bare を含む）の中で実行する必要があります。カレントディレクトリが Git リポジトリのワークツリーか、bare リポジトリ自体であることを確認してください。

### `warning: VS Code CLI 'code' was not found`

`ocw` のデフォルトモード（`--herdr` なし）では worktree 作成後に VS Code を開こうとします。`code` CLI がインストールされていない場合、この警告が出ますが worktree 作成自体は成功しています。VS Code をインストールするか、`--herdr` モードを使用してください。

### VS Code を開かずに worktree だけ作りたい（スクリプト・自動化・動作確認用）

`OCW_NO_VSCODE=1` を設定すると、`--herdr` なしのデフォルトモードでも VS Code を起動しません（`code` の有無に関わらず無条件でスキップします）。`ocw` 自体の動作をスクリプトや手元のシェルから直接検証したいとき、あるいは自動化パイプラインから呼ぶときに使ってください。

```bash
OCW_NO_VSCODE=1 ocw widget-maker
```
