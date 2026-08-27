# AI Agent Skills (skills)

## Overview

AI コーディングエージェント向けのスキル。**Claude Code 専用ではない。**
同じスキルディレクトリを、このマシンに入っている全エージェントのスキルディレクトリへ
個別 symlink で配る。

| Skill | Purpose |
|---|---|
| `pr-review-loop` | PRレビューサイクルを自動化。Herdr の reviewer ペインと連携し、レビュー→修正→再レビューを承認まで繰り返す |
| `umbrella-orchestrator` | 傘ブランチの孫ライフサイクル管理。計画書の読み取り、孫ブランチの spawn、マージ検出と検証、計画書更新を自動化 |
| `repo-baseline` | `templates/repo-baseline/` copier テンプレートを既存リポジトリへ適用する手順と判断ガイド |

`pr-review-loop` は各Phaseの境界で `ocw-meter event`（工程計測。
`docs/planning/DOC-2608021229-a_ai-llm-cost-observability_計画.md` 参照）を呼び出す。
すべて `command -v ocw-meter >/dev/null && ... || true` 形式の fail-open 呼び出しで、
レビュー規約・判定基準・停止条件には一切影響せず、`ocw-meter` が存在しない環境でも
スキルは完全に動作する。

## 1. 配布先

| エージェント | 配布先 | 配布条件 |
|---|---|---|
| Claude Code | `~/.claude/skills/<名前>/` | 常に配る（`~/.claude` はこのリポジトリの持ち物） |
| Codex | `$CODEX_HOME/skills/<名前>/`（既定 `~/.codex/skills/`） | `$CODEX_HOME` が実在するときだけ |
| OpenCode | `~/.config/opencode/skills/<名前>/` | `~/.config/opencode` が実在するときだけ |

3者はいずれも「`SKILL.md` + YAML frontmatter（`name` / `description`）+ Markdown 本文」
という同じスキル形式を読む。だからスキルの中身をエージェントごとに分岐させる必要は無く、
1つの実体を複数箇所から symlink するだけで済む。

エージェントの設定ディレクトリが存在しない場合、そのエージェントはスキップされる
（インストールしていないツールのためにディレクトリツリーを勝手に掘らない）。
例外は `~/.claude` で、このリポジトリは Claude Code の設定を無条件に配っているため、
無ければ作る。採用理由と却下案は ADR
[DOC-2608272128](../docs/adr/DOC-2608272128_skills-multi-agent-distribution.md) を参照。

## 2. Quick Start

初回（新規マシン、まだ何もデプロイしていない状態）は、単体の `skills/deploy.sh` ではなく
必ずリポジトリルートの `deploy-all.sh` を実行してください。単体実行は配布実体
（`current`）経由でしか読まないため、`current` がまだ無い新規マシンではエラーで終了します
（詳細はルート `AGENTS.md`「デプロイの仕組み」節を参照）。

```bash
# 1. リポジトリルートから実行（初回は必ずこちら）
cd ~/.dotfiles
./deploy-all.sh --only skills

# 2. Verify
ls -la ~/.claude/skills/           # 各スキルが symlink（herdr など独自スキルは残る）
ls -la ~/.codex/skills/            # Codex を入れていれば同じスキルが並ぶ
ls -la ~/.config/opencode/skills/  # OpenCode を入れていれば同じスキルが並ぶ
```

すでに一度 `deploy-all.sh` を実行済みで `current` が存在する状態であれば、
`skills/` ディレクトリから単体の `./deploy.sh` を実行しても構いません（配布実体を
作り直さず、既存の `current` を読み直すだけです）。

## 3. デプロイの仕組み

- **ディレクトリ全体 symlink は禁止。** 例えば `~/.claude/skills` をまとめて symlink すると、
  Herdr 管理の `herdr` スキルやユーザー独自スキルが消える。Codex では同梱のビルトイン
  （`~/.codex/skills/.system/`）が巻き添えになる。
- 代わりに **`skills/` 内の全ディレクトリを自動検出**し、1スキルずつ個別 symlink する。
- これにより、エージェント同梱のスキル・Herdr 管理のスキル・手動追加した独自スキルと
  安全に共存できる（**`skills/` 配下と同名でない限り**）。
- 将来スキルが増えても `deploy.sh` の修正は不要（自動検出のため）。スキルを削除・リネームした
  場合も、`deploy.sh` が古い symlink を自動的に掃除する。

**重要**: `skills/` 配下と同名のファイル／ディレクトリが既にエージェントのスキルディレクトリに
ある場合、そのエージェントの `skills-backup/` に退避されます。

```bash
# 退避からの復元は手動（例: Claude Code）
mv ~/.claude/skills-backup/<name>.<timestamp>.<pid> ~/.claude/skills/<name>
```

`uninstall.sh` は symlink を撤去したあと、この退避を自動で元の場所へ戻します。

## 4. スキルの追加

### 4.1 このリポジトリで管理するスキル

`skills/` にディレクトリを追加するだけで、次回 deploy 時に自動検出される。

```bash
mkdir -p skills/new-skill
# ... SKILL.md を作成 ...
cd ~/.dotfiles && ./deploy-all.sh --only skills  # 自動検出されて symlink が作られる
```

`SKILL.md` の frontmatter は3エージェント共通の `name` / `description` だけで足りる。
特定のエージェントでしか動かない書き方（そのエージェント固有のコマンドや画面表示への
依存）は避ける。配布側でエージェントを絞る仕組みは持たない方針のため
（ADR DOC-2608272128 §2.4）。

### 4.2 このリポジトリで管理しない独自スキル

エージェントのスキルディレクトリに手動でディレクトリを作り `SKILL.md` を置くだけでよい。
`deploy.sh` はリポジトリ管理下のスキルのみを symlink し、**同名衝突がない限り**手動追加した
スキルには触れない。

```bash
mkdir -p ~/.claude/skills/my-skill
cat > ~/.claude/skills/my-skill/SKILL.md << 'EOF'
---
name: my-skill
description: 自分のスキル
---
# My Skill
...
EOF
```

## 5. 配布先エージェントを増やす

`shared/helpers.sh` の `skill_agents()` に名前を足し、`skill_agent_home()` と
`skill_dir_for_agent()` に arm を追加する。そのエージェントの設定ディレクトリを
このリポジトリが作ってよい場合は `agent_home_mode()` にも arm を足す（足さなければ
「ディレクトリが実在するときだけ配る」という既定の扱いになる）。

`uninstall.sh` と `deploy-all.sh --status` はどちらも `skill_links()` を一次情報源に
しているので、この3〜4箇所を直せば撤去とリンク健全性スキャンも自動的に追随する。

## 6. Uninstall

```bash
cd ~/.dotfiles
./uninstall.sh --only skills            # 対話モード
./uninstall.sh --only skills --dry-run  # 何が起きるか確認
```

全エージェント分の symlink を撤去し、deploy 時に `skills-backup/` へ退避した元スキルが
あれば復元します。
