# ADR: スキルを AI エージェント横断で配布する

## ステータス

確定（2026-08-27）

## 1. 背景

このリポジトリのスキル（`repo-baseline` / `umbrella-orchestrator` / `pr-review-loop`）は
`claude/skills/` に置かれ、`claude/deploy.sh` が `~/.claude/skills/<名前>` へスキルごとに
個別 symlink を張ることで配布されていた。配布先は Claude Code ただ1つである。

一方、実機には Claude Code 以外の AI コーディングエージェントが同居している。

### 1.1 実機調査（2026-08-27）

| エージェント | ユーザースキルの置き場 | 調査根拠 |
|---|---|---|
| Claude Code | `~/.claude/skills/<名前>/` | 既存の配布先 |
| Codex | `$CODEX_HOME/skills/<名前>/`（既定 `~/.codex/skills/`） | 同梱スキル `skill-installer/SKILL.md` の記述、および `scripts/list-skills.py` が `os.path.join(_codex_home(), "skills")` を参照 |
| OpenCode 1.17.13 | `~/.config/opencode/skill(s)/<名前>/SKILL.md` | 実行バイナリ内の文字列 |

調査時点で、Codex 側は同梱のビルトイン（`.system/` 配下）のみ、OpenCode 側は
skill ディレクトリ自体が存在せず、このリポジトリのスキルは1件も届いていなかった。

### 1.2 スキル形式の同一性

3者とも「`SKILL.md` + YAML frontmatter（`name` / `description`）+ Markdown 本文」で共通し、
補助ファイル（`scripts/` `references/` `assets/`）を同梱できる点も同じである。
Codex は `metadata.short-description`、OpenCode は独自の任意フィールドを追加で解釈するが、
いずれも必須ではない。

**したがって、スキルの中身を変換する必要はない。配布先を増やすだけで3者が同じ実体を読める。**

## 2. 決定

### 2.1 `claude/skills/` を `skills/` へ切り出し、独立したツールディレクトリにする

`skills/` を `AVAILABLE_TOOLS` の一員（`zsh nvim tmux bin claude skills`）とし、
`skills/deploy.sh` が全エージェントへの配布を担う。`claude/deploy.sh` からスキル配布の
責務を取り除く。

`AVAILABLE_TOOLS` の並び順では `skills` を `claude` の後ろに置く。ただしこれは
「ディレクトリの持ち主が先に作る」という見た目の整理であって、依存ではない（§2.3）。

### 2.2 スキルの中身はエージェントごとに分岐させない

同一の `SKILL.md` を全エージェントの skills ディレクトリから symlink する。
エージェント別のバリアントや変換処理は持たない（§1.2）。

### 2.3 配布先はエージェントの設定ディレクトリが存在する場合のみ（このリポジトリが所有するものを除く）

`skill_agent_home()` が返すディレクトリ（`~/.claude` / `$CODEX_HOME` / `~/.config/opencode`）が
実在するエージェントにだけ配る。使っていないエージェントのディレクトリツリーを勝手に作らない。

例外は `~/.claude` である。このリポジトリは Claude Code の設定（`CLAUDE.md` /
`settings.json`）を無条件に配っており、`~/.claude` は「ユーザーがそのエージェントを
入れた証拠」ではなく**このリポジトリ自身の持ち物**だからである。`agent_home_mode()` が
「このリポジトリが作ってよいディレクトリか」と「作るときのモード」を1つの値で返し、
`skills/deploy.sh` は無ければ自分で作る。

これを「未導入」として扱うと、`--dry-run` が実行結果と食い違う。`claude/deploy.sh` の
DRY-RUN 分岐は `~/.claude` を実際には作らず「作る予定」を表示するだけなので、その直後に
走る `skills` の実在チェックは常に空振りし、**新品のマシンに対する dry-run が Claude Code
向けの配布を1件も計画しない**。これは `claude/deploy.sh` の `CLAUDE_SRC_DIR` が既に
避けている dry-run と実行の乖離と同じ種類の不具合である。

0700（`~/.claude` は資格情報を含みうる）というモードが `claude/deploy.sh` と
`skills/deploy.sh` の2箇所に散らないよう、モードの一次情報源も `agent_home_mode()` に置く。

### 2.4 スキルごとの配布先の絞り込みは行わない

全スキルを全エージェントへ一律に配る。特定のエージェントでしか意味を持たないスキルは、
配布側で絞るのではなく、**スキル自身がエージェント非依存に書かれること**で解決する
（この決定に伴い `pr-review-loop` の Claude Code 依存を除去した）。

### 2.5 一元化の作法は既存を踏襲する

「どの `$HOME` パスへ配るか」の一次情報源を `shared/helpers.sh` に集約する既存方針
（ADR DOC-2608040229 §2.6）をそのまま拡張する。スキルの symlink はスキル名が可変で
固定リストにできないため `links_for_tool()` には載らず、`claude_skill_links()` を
一般化した `skill_links()` が全エージェント分を走査して返す。`uninstall.sh` と
`deploy-all.sh --status` の両方がこれを参照する。

## 3. 却下した案

### 3.1 `claude/deploy.sh` に他エージェント向けの symlink を足す

最小の変更で済むが、「`claude` ツールが `codex` と `opencode` にも配る」という構造上の
矛盾が残る。`--only claude` の意味が「Claude Code だけを配る」ではなくなり、
`uninstall.sh` の `KNOWN_*_claude` 系も同じ歪みを引き継ぐ。却下。

### 3.2 スキルごとに配布先エージェントを指定できる設定ファイルを置く

`skills/targets.conf` のようなマッピングを持ち、スキル単位で配布先を絞る案。
配布先を絞りたい動機は「そのエージェントでは動かないスキルがある」ことであり、
それは配布の問題ではなくスキルの書き方の問題である。設定ファイルという新しい一次情報源が
増え、`deploy` / `uninstall` / `--status` の3箇所がそれを読む必要が生じる割に、
解決しているのは一覧のノイズだけ。却下（§2.4）。

### 3.3 OpenCode 側を `skill/`（単数）にする

OpenCode は `skill/` と `skills/` の両方を受け付ける。単数形は OpenCode の慣習に寄るが、
3エージェントで綴りが揃わないと `skill_dir_for_agent()` の読み手が毎回どちらか確認する
ことになる。`skills/` に統一する。

## 4. 移行

### 4.1 既存の symlink

移行前のリンクは `<prefix>/current/claude/skills/<名前>` を指している。移行後は
`<prefix>/current/skills/<名前>` を指す。スキル名は変わらないため配布先のパスは同じで、
`_dotfiles_symlink_is_repo_owned()` が「このリポジトリ由来の symlink」と判定するため、
退避されずにそのまま張り替えられる。

### 4.2 旧スキームの認識

`skill_links()` は新旧両方のパス（`.../skills/*` と `.../claude/skills/*`）を
リポジトリ由来として認識する。移行前にデプロイしたマシンで、その後に削除・リネームされた
スキルの残骸が `uninstall.sh` から見えなくなるのを防ぐ。

### 4.3 stale symlink の掃除

`skills/deploy.sh` の stale 掃除も同様に新旧両方のプレフィックスを対象にする。
片方だけを見ると、移行前に作られたリンクのうち配布元が消えたものが永久に残る。

## 5. 影響範囲

| ファイル | 変更 |
|---|---|
| `skills/`（新規） | `claude/skills/` から移動。`deploy.sh` と `README.md` を追加 |
| `claude/deploy.sh` | スキル配布の節を削除。`~/.claude` のモードを `agent_home_mode()` から取得 |
| `shared/helpers.sh` | `AVAILABLE_TOOLS` に `skills`、`skill_agents()` / `skill_agent_home()` / `agent_home_mode()` / `skill_dir_for_agent()` / `skill_backup_dir_for_agent()` / `skill_backup_dir_for_link()` を追加、`claude_skill_links()` → `skill_links()` |
| `uninstall.sh` | スキル撤去を `claude` から `skills` へ移し、全エージェント分を走査 |
| `deploy-all.sh` | `--status` のスキルリンク走査を `skill_links()` へ |
| `tests/deploy_smoke.sh` | 既定対象に `skills` を追加、スキル系シナリオを全エージェント対応へ |
