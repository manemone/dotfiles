# ADR: Codex / OpenCode のグローバル指示を dotfiles から配布する

## ステータス

確定（2026-09-07）

## 1. 背景

人間の確定事項（計画書 `docs/planning/DOC-2609072212_agent-handoff_計画.md` 背景2）:

> 発動条件は Claude Code だけでなく他のAI（Codex / OpenCode）にも効く形にする。
> `claude/CLAUDE.md` に1行入れるだけでは Claude Code にしか効かない。

「相談された課題が複数PRに分かれる規模だと判断したら、実装や計画書執筆を始めず
`umbrella-handoff` スキルへの引き継ぎを人間に提案する」という恒久的な振る舞いを配るには、
各エージェントが**常に読み込む**グローバル指示ファイルに書く必要がある。スキルの
`description`（`skills/umbrella-handoff/SKILL.md`）は、エージェントがそのスキルを
検索・招集しようとした時にしか参照されず、「複数PR規模かどうかを常に評価し続ける」
という常時発火の振る舞いの置き場所にはならない。

司令官の実測（2026-09-07）で判明した各エージェントのグローバル指示ファイル:

| エージェント | グローバル指示ファイル | 備考 |
|---|---|---|
| Claude Code | `~/.claude/CLAUDE.md` | 既に `claude/deploy.sh` が symlink で配布済み |
| Codex | `~/.codex/AGENTS.md` | **実ファイルとして既に存在するが symlink ではない。** 内容は `claude/CLAUDE.md` と全く同じ個人指示（口調設定）で、人間が手でコピーしたまま dotfiles の管理外にあった |
| OpenCode | `${XDG_CONFIG_HOME:-$HOME/.config}/opencode/AGENTS.md` | 司令官の実測時点では権限の都合で存在確認できず、[OpenCode公式ドキュメント](https://opencode.ai/docs/rules/) で調査し判明した。同ドキュメントによれば OpenCode は `~/.claude/CLAUDE.md` もフォールバックとして読むが、自身の `AGENTS.md` が存在すればそちらが優先される |

**Codex の `~/.codex/AGENTS.md` が既に `claude/CLAUDE.md` と同一内容を手で複製済みだった**
という事実が、本決定の出発点になっている。個人の口調設定（「脳筋後輩っぽく対応してください」
等）はエージェント名を問わない内容であり、人間は既にそれを承知の上で3エージェントへ同じ
指示を配ろうとしていた。

## 2. 決定

**`codex/` と `opencode/` を新しいツールディレクトリとして追加し、それぞれの
`deploy.sh` が Codex / OpenCode のグローバル指示ファイルを、`claude/CLAUDE.md` と
同一のソースファイル（`$DOTFILES_DEPLOY_SRC/claude/CLAUDE.md`）へ symlink する。**

```
~/.claude/CLAUDE.md              → <current>/claude/CLAUDE.md   (claude/deploy.sh)
~/.codex/AGENTS.md                → <current>/claude/CLAUDE.md   (codex/deploy.sh)
${XDG_CONFIG_HOME:-~/.config}/opencode/AGENTS.md → <current>/claude/CLAUDE.md   (opencode/deploy.sh)
```

- **ソースファイルは1つだけ。** `claude/CLAUDE.md` というファイル名は歴史的な経緯
  （元は Claude Code 専用だった）を残しているが、内容自体はエージェント非依存の個人指示
  （口調設定 + 傘ブランチ引き継ぎの発動条件）であり、3エージェントへ同じ内容を配ることに
  矛盾しない。ファイルの物理的な移動・改名は行わない（参照箇所が README / AGENTS.md /
  ADR / shared/helpers.sh / tests など広範囲に及び、今回の変更の主目的である
  「発動条件の配布」に対してブラストレディウスが不釣り合いに大きくなるため）
- **新しいツールディレクトリを2つ追加する理由**: 既存の `claude` ツールと同じ「1エージェント
  = 1ツールディレクトリ」という規約に揃える。`codex/deploy.sh` と `opencode/deploy.sh` は
  それぞれ自分のツールディレクトリの外（`claude/CLAUDE.md`）を読みにいくが、これは
  「配布先エージェントが増えるたびに配布元も増やす」のではなく「配布元は1つのまま、
  配布先だけを増やす」設計上の帰結であり、`skills/deploy.sh` が全スキルを全エージェントへ
  配る構造（ADR DOC-2608272128）と同じ「1つの正典 → 複数の配布先」のパターンである
- **エージェントのホームディレクトリが実在する場合のみ配布する**（ADR DOC-2608272128
  §2.3 と同じ判断基準）。`~/.codex/` や `${XDG_CONFIG_HOME:-~/.config}/opencode/` が
  存在しないマシンは、そのエージェントを未導入とみなし、ディレクトリを新規作成しない。
  `shared/helpers.sh` の `skill_agent_home()` / `agent_home_mode()` は既にこの判定基準を
  実装済みで、`codex` / `opencode` は `agent_home_mode()` が空文字を返す（＝作成不可）
  対象として元々分類されている（`skills/deploy.sh` が既にこの分類でスキルを配っている）ため、
  そのまま流用する
- **既存ファイルは `symlink_backup` で退避される。** `~/.codex/AGENTS.md` は既に実ファイルが
  存在するため、初回デプロイ時に `.backup` へ退避されたうえで symlink に置き換わる
  （`shared/helpers.sh` の既存の退避ロジックをそのまま使う。新しいコードは書かない）

## 3. 却下した案と却下理由

### 3.1 `codex/AGENTS.md` / `opencode/AGENTS.md` を別ファイルとして repo 内に複製する

各ツールディレクトリに自分専用のコンテンツファイルを持たせる案。`claude/CLAUDE.md` と
内容が実質同一になるため、3ファイルへ同じ文言を書き写すことになり、`AGENTS.md`
「実装時の注意」が繰り返し警告している「同じ情報を2箇所に書くと片方だけ更新される」
事故の再発になる。既に `~/.codex/AGENTS.md` がまさにこの事故（手作業での複製・
ドリフト）を起こしていたことが背景1で判明しているため、同じ失敗を repo 内で
繰り返さないよう単一ソース + 複数 symlink とした。

### 3.2 配布経路を増やさず `skills/umbrella-handoff/` の `description` を強化するだけにする

計画書の選択肢B。スキルの `description` は「あるスキルを検索・招集しようとする瞬間」に
しか参照されない可能性が高く、「相談中の会話が複数PR規模かどうかを常時判断し続ける」
という振る舞いの土台にはならない（背景1参照）。またこの案では
`~/.codex/AGENTS.md` の手動複製・管理外という既存の技術的負債も放置されたままになる。
却下し、Option A（新しい配布経路の新設）を選んだ。

### 3.3 `claude/CLAUDE.md` を配布元に依存しないニュートラルな場所へ物理的に移動する

ファイル名を `claude/CLAUDE.md` から中立的な名前（例: `agent-instructions/GLOBAL.md`）へ
移動し、`claude/deploy.sh` 側もそこから symlink し直す案。アーキテクチャ的には最も
一貫しているが、`claude/CLAUDE.md` への参照が README・AGENTS.md・既存 ADR・
`shared/helpers.sh` のコメント・`tests/deploy_smoke.sh` など広範囲に散らばっており
（`git grep` で14ファイル該当）、発動条件の配布という本来のスコープに対して不釣り合いな
リファクタリングになる。ソースファイルを移動せず、参照先を増やすだけに留めた。

## 4. 既知のリスク

- **OpenCode の `~/.claude/CLAUDE.md` フォールバック読み込みとの重複**: OpenCode は
  自身の `AGENTS.md` が無い場合に `~/.claude/CLAUDE.md` をフォールバックとして読む
  （[OpenCode公式ドキュメント](https://opencode.ai/docs/rules/)）。今回
  `${XDG_CONFIG_HOME}/opencode/AGENTS.md` を明示的に配布するため、フォールバック経路には
  依存しなくなるが、この重複読み込みの仕様自体は今回の決定に影響しない（明示的な
  symlink が常に優先されるため）
- **Codex / OpenCode 側の仕様変更**: 両エージェントとも「唯一のグローバル指示ファイル」
  という前提（複数ファイルの合成をサポートしない）で設計した。将来どちらかが
  複数ファイルの合成をサポートするようになっても、既存の symlink 配布方式が壊れることはない
  （単に選択肢が増えるだけ）
