# Claude Code Config (claude)

## Overview

Claude Code の設定ファイル群。`~/.claude/` にデプロイして使う。

| File | Purpose | Deploy Method |
|---|---|---|
| `CLAUDE.md` | Claude Code の個人指示（プロジェクト横断で適用されるグローバル指示） | symlink |
| `settings.json` | Claude Code の汎用設定（モデル、権限ポリシー、テーマ等）。マシン固有設定は**含まない** | 生成（マージ） |
| `settings.machine.json.example` | マシン固有設定のテンプレート。コピーして使う | （手動コピー） |

## 1. Requirements

| Tool | Why | Install |
|---|---|---|
| **Claude Code** CLI | 設定ファイルの読み取り元 | `npm install -g @anthropic-ai/claude-code` |
| **Python 3** | `settings.machine.json` とのマージ、および学習済み `permissions.allow` の保全用（任意。無ければ両方スキップされ、ベース設定のみで生成される） | `mise use python@latest` |

## 2. Quick Start

初回（新規マシン、まだ何もデプロイしていない状態）は、単体の `claude/deploy.sh` ではなく
必ずリポジトリルートの `deploy-all.sh` を実行してください。単体実行は配布実体
（`current`）経由でしか読まないため、`current` がまだ無い新規マシンではエラーで終了します
（詳細はルート `AGENTS.md`「デプロイの仕組み」節を参照）。

```bash
# 1. リポジトリルートから実行（初回は必ずこちら）
cd ~/.dotfiles
./deploy-all.sh --only claude

# 2. Verify
ls -la ~/.claude/CLAUDE.md         # symlink（current 経由）
ls -la ~/.claude/settings.json     # 実ファイル（deploy.sh が生成）
```

すでに一度 `deploy-all.sh` を実行済みで `current` が存在する状態であれば、
`claude/` ディレクトリから単体の `./deploy.sh` を実行しても構いません（配布実体を
作り直さず、既存の `current` を読み直すだけです）。

The deploy script:
- Creates `~/.claude/` directory with mode `700`（認証情報を置く可能性があるため）
- Symlinks `CLAUDE.md` → `~/.claude/CLAUDE.md`
- Generates `~/.claude/settings.json` as a real file（※symlink ではない）。入力は3つ:
  1. ベース設定（`claude/settings.json`）
  2. マシン固有設定（`claude/settings.machine.json`。存在すれば）
  3. **今まさに置き換えようとしている生成物（`~/.claude/settings.json`）の `permissions.allow`**
     — Claude Code が対話で学習した allow を deploy 越しに保全する（§3.2.1参照）

`~/.claude/skills/` はこのスクリプトの担当ではない。スキルは Claude Code 専用ではなく
Codex・OpenCode にも同じ実体が配られるため、トップレベルの `skills/` ツールが受け持つ
（[skills/README.md](../skills/README.md) / ADR
[DOC-2608272128](../docs/adr/DOC-2608272128_skills-multi-agent-distribution.md)）。

> **⚠️ 重要**: deploy 実行時に既存の `~/.claude/settings.json` はバックアップ（`.backup` 付きで退避）されます。
> `permissions.allow` は次回 deploy でも自動的に保全されますが（§3.2.1参照）、
> Herdr の `SessionStart` hook や `additionalDirectories` など**`allow` 以外のマシン固有設定は
> 保全されません**。失われるのを防ぐには、**deploy 前に `settings.machine.json` を作成**してください。

## 3. What's Included

### 3.1 CLAUDE.md

Claude Code がセッション開始時に読み込むグローバルな個人指示（project-level の CLAUDE.md より優先度は低い）。

現在の設定:
- 脳筋後輩キャラクターでの応答スタイル指定（語尾・一人称・二人称）
- 傘ブランチへの引き継ぎ判断（複数PR規模だと判断したら `umbrella-handoff` スキルへの
  引き継ぎを人間に提案する）

**このファイルは Claude Code 専用ではない。** [`codex/deploy.sh`](../codex/README.md) と
[`opencode/deploy.sh`](../opencode/README.md) も同じファイルを symlink しており、
`~/.codex/AGENTS.md` と `${XDG_CONFIG_HOME:-~/.config}/opencode/AGENTS.md` は実体としては
この `CLAUDE.md` と同一である（ADR
[DOC-2609072334](../docs/adr/DOC-2609072334_codex-opencode-global-instructions-distribution.md)）。
編集する際は3エージェント全部に影響することを意識すること。

`~/.claude/CLAUDE.md` を直接編集すればその場ですぐに反映されるが、これは配布実体（世代
ディレクトリ）内のコピーを直接編集しているだけで、リポジトリの作業ツリー側
（`claude/CLAUDE.md`）には反映されない。恒久的に変更したい場合はリポジトリ側を編集して
再デプロイするか、編集のたびに即時反映させたいなら dev モード（`./deploy-all.sh --dev`）を
使うこと。詳細は §4.8 を参照。

### 3.2 settings.json

Claude Code の設定ファイル。以下の汎用設定を含む（マシン固有の `additionalDirectories`、
`hooks`（git-guard フックを除く。§3.5参照）は**意図的に除外**。`permissions.allow` は
リポジトリ側のベース設定には含まれないが、deploy 時に学習済みの分が自動的に合成される
— §3.2.1参照）。

| Setting | Value | Notes |
|---|---|---|
| `model` | `opus` | デフォルトモデル |
| `language` | `Japanese` | 応答言語 |
| `effortLevel` | `high` | 推論深度 |
| `theme` | `dark` | テーマ |
| `editorMode` | `normal` | エディタモード |
| `autoCompactEnabled` | `true` | 自動コンパクション |
| `switchModelsOnFlag` | `true` | フラグによるモデル切り替え |
| `skipWorkflowUsageWarning` | `true` | ワークフロー警告スキップ |
| `permissions.defaultMode` | `acceptEdits` | 権限のデフォルトモード |
| `permissions.deny` | セキュリティポリシー（24件） | `.env`, `.ssh`, `.aws`, API キー等へのアクセスをブロック |
| `permissions.ask` | 危険コマンドパターン（20件） | `git push --force`, `rm -rf`, `sudo` 等の実行前に確認 |
| `statusLine` | `{"type":"command","command":"ocw-meter snapshot-quota"}` | Claude 利用枠(5時間枠・週間枠)のステータスバー表示。§3.4参照 |

#### 3.2.1 学習した allow は deploy 越しに保全される

Claude Code が対話中に「今後確認しない」で `~/.claude/settings.json` の
`permissions.allow` へ学習した内容は、**deploy を実行しても消えない**。
`claude/deploy.sh` は settings 生成の入力として、ベース設定・
`settings.machine.json`（存在すれば）に加えて、**今から置き換えようとしている
生成物自身の `permissions.allow`** を読み、重複を除いて合成する
（設計の詳細は計画書
[DOC-2609121700](../docs/planning/DOC-2609121700_autopilot-permissions_計画.md)
設計3を参照）。

**保全されるのは `permissions.allow` だけ。** `ask` / `deny` / `hooks` /
`additionalDirectories` などその他のキーは保全されない。理由は2つ:

- 優先順位は `deny > ask > allow` なので、保全した `allow` が既存の `deny` / `ask` を
  弱める心配が要らない。`ask` や `deny` まで保全すると、対話や `/permissions` で
  一時的・誤って足された `ask` が deploy のたびに引き継がれ続けてしまう
  （実際に一度これが起きた。§2の「⚠️ 重要」参照）
- `hooks` や `additionalDirectories` のようなマシン固有の恒久設定は、
  `settings.machine.json` に書くのが正規の経路（§4.3・§4.5）

既存の生成物が無い・壊れている・`permissions.allow` を持たない場合は、
何も保全せず従来どおりベース（+machine）だけで生成する（deploy は失敗しない）。
`python3` が無い環境では保全そのものがスキップされ、警告を出したうえでベース設定を
そのままコピーする（`settings.machine.json` を使わない限り `python3` は必須ではない）。

`--dry-run` では、何件の `allow` を保全する予定かをログに出す
（実ファイルには一切書き込まない）。

### 3.3 Skills

スキルは `claude/` の配布物ではない。Claude Code / Codex / OpenCode の3者が同じ
`SKILL.md` 形式を読むため、トップレベルの `skills/` ツールが全エージェントへ同じ実体を
配っている。スキルの一覧・配布先・追加方法は [skills/README.md](../skills/README.md) を、
切り出した理由と却下案は ADR
[DOC-2608272128](../docs/adr/DOC-2608272128_skills-multi-agent-distribution.md) を参照。

### 3.4 statusLine — Claude 利用枠スナップショット

`ocw-meter snapshot-quota`（`bin/README.md` §3.3 参照）を `statusLine` コマンドとして配線し、
Claude Code のステータスバーに 5時間枠（使用率とリセット時刻）/ 週間枠 / コンテキスト使用率を表示する。
詳細設計は `docs/planning/DOC-2608021229-a_ai-llm-cost-observability_計画.md` 第5.6章・第8.5章、
`docs/adr/DOC-2608021229_llm-cost-observability-collection-method.md` §2.1・§8 を参照。

**表示内容**（例）:

```
5h:37%→04:10 7d:12% ctx:24%
```

`5h:` の `→04:10` は**5時間枠がリセットされる時刻**（`rate_limits.five_hour.resets_at` を
ローカルタイムの `HH:MM` に変換したもの）。週間枠には併記しない（日付まで書かないと読めず、
statusLine には長すぎるため）。`resets_at` が取得できない場合、および既に過ぎた時刻
（stale 値）が来た場合は併記を省いて `5h:37%` に戻る。

取得できない項目は表示しない（例: `claude-ds`（DeepSeek）セッションでは `rate_limits` が
一切来ないため `5h:`/`7d:` は出ず、`ctx:` のみになるか、コンテキスト情報も無ければ完全に空になる）。
`ctx` は `context_window.used_percentage` が生の値として取得できているときのみ表示する
（推定値からのフォールバック計算は記録用イベントにのみ使い、表示には使わない）。

**事前準備（必須）**: `ocw-meter` が PATH に無い環境では statusLine コマンド自体が
`command not found` になり、表示が壊れる。必ず先に `./deploy-all.sh --only bin`
（リポジトリルートから）を実行して `~/bin/ocw-meter` を配置し、`~/bin` が PATH に
入っていることを確認すること（`~/bin` の PATH 追加は `zsh/.zshrc` 依存。`bin/README.md` §5 参照）。

**観測は既存フローに一切割り込まない。** `snapshot-quota` は例外が起きても必ず表示文字列を
stdout に返し exit 0 する（statusLine が壊れて画面が崩れる事態を避けるための最優先事項）。
サンプリングは既定60秒に1回（`OCW_METER_QUOTA_INTERVAL` で変更可）に自制されており、
statusLine が描画のたびに呼ばれても書き込みが肥大しない。

**取得できない項目（実測に基づく既知の制約。詳細は DOC-2608021229 §2.1 参照）:**

- `claude-ds`（DeepSeek）セッションでは `rate_limits` が原理的に来ない
  （Claude.ai サブスクリプションの利用枠であり、DeepSeek API 経由のセッションには適用されない）。
  `five_hour_used_pct` 等は `null`、`completeness: "unknown"` として記録される（推測しない）
- 5時間枠に到達して待機した際の挙動は**未観測**（その状況が発生した際のログをまだ収集できていない）。
  `blocked` の検出は best-effort であり、`ocw-meter` は明示的な待機時間を計測しない
- `rate_limits.five_hour.resets_at` が過去時刻（stale値）を返すケースが実測されている
  （DOC-2608021229 §2.1: 8サンプル中3件）。stale と判定された場合は `window_id` を `null` にして
  `completeness: "partial"` で記録する（推測で新しい窓を開始しない）

**⚠️ 重大な注意 — `~/.claude/settings.json` の `hooks` 消失リスク（計画書17章 R3）:**

`~/.claude/settings.json` は **Herdr（`SessionStart` hook）と `claude/deploy.sh` の両方が書き込む
競合地帯**である。`claude/deploy.sh` は `claude/settings.machine.json` が存在しない、または
存在しても `hooks` を含まない場合、Herdr が実行時に書き足した `hooks` ごと上書きしてしまう
（実機検証中に実際にこの事故が発生している — 詳細は DOC-2608021229 Appendix A 参照）。

**`statusLine` を配線した本設定を deploy する前に、必ず以下を確認・実施すること:**

1. `~/.claude/settings.json` の現在の `hooks` を確認する:
   ```bash
   python3 -c "import json; print(json.dumps(json.load(open('$HOME/.claude/settings.json')).get('hooks'), indent=2))"
   ```
2. `claude/settings.machine.json`（無ければ `settings.machine.json.example` からコピー）に、
   確認した `hooks`（通常は Herdr の `herdr-agent-state.sh`）を明記する（§4.3参照）
3. `./deploy-all.sh --only claude`（リポジトリルートから）を実行する。**単体の
   `claude/deploy.sh` では不可**（配布実体経由でしか読まないため、今編集した
   `settings.machine.json` の内容を拾わない）
4. deploy 後、再度 手順1 のコマンドを実行し、`hooks.SessionStart` が健在であることを確認する

**statusLine の無効化方法:**

`claude/settings.machine.json` に `"statusLine": null` は効かない（machine側の shallow merge は
`null` も値として上書きしてしまうだけで、キー自体を消せない）。無効化したい場合は
`~/.claude/settings.json` の `statusLine` キーを deploy 後に手動で削除する
（**次回 `./deploy-all.sh` 実行時に `claude/settings.json` の内容で再度上書きされる**ので、
恒久的に無効化したい場合はリポジトリ側の `claude/settings.json` から `statusLine` を削除すること）。

### 3.5 git-guard フック — main/master への破壊的操作の機械的ガード

`~/.claude/hooks/git-guard.sh`（`claude/hooks/git-guard.sh` から symlink される PreToolUse
フック）が、「`main`/`master` へのマージ・push は人間、それ以外の git 操作は AI に任せる」
という線引きを機械的に担保する。設計の根拠・却下案・PreToolUse フックの入出力契約の確認結果は
ADR [DOC-2609121719](../docs/adr/DOC-2609121719_git-operation-permission-policy.md)
を参照。

**何を止めて何を通すか（判定表）:**

| 対象コマンド | 判定 |
|---|---|
| `gh pr merge`（PR 番号 / URL / 省略＝現ブランチ） | base ブランチが `main`/`master` なら **deny**、それ以外は **allow** |
| `git push` に `--force` / `--force-with-lease` / `-f` / `+<refspec>` が付く | 対象ブランチが `main`/`master` なら **deny**。それ以外は `--force-with-lease` を **allow**、裸の `--force`/`-f` は **ask** |
| `git merge` | 現在のブランチ（マージ先）が `main`/`master` なら **deny**、それ以外は **allow** |
| 上記以外の git/gh コマンド、対象を安全に判定できないコマンド | 何も言わず `permissions.ask` の判定に委ねる、または **ask** |

判定できない入力（PR 番号が解決できない・`gh` の実行に失敗する・現在のブランチが
取れない・複数コマンドが `&&`/`;`/`|` で連結されている等）は必ず `ask` に倒す。
**`allow` に倒すことは絶対に無い。**

**上の判定表はフック単体の判定であり、フックが `allow` を返しても
`permissions.ask` に一致すれば確認は出る。** PreToolUse フックは
`permissions` の判定を緩める方向には使えず、危険な部分集合を引き上げる
（制限を足す）ことしかできない（公式ドキュメントより。ADR §3.2/§3.3 参照）。
`git push --force-with-lease` を実際に無確認で通すため、`claude/settings.json`
の `permissions.ask` からは `--force-with-lease` に一致するパターンを外し
（`*--force*` / `*--force-with-lease*` は空白を挟まず一致してしまうため
どちらも置かない）、裸の `--force` だけを単語境界で拾う4パターンに
置き換えている（ADR §3.3「`git push --force-with-lease` を摩擦なく通すための
具体策」）。

**無効化したいとき:**

`claude/settings.machine.json` に `hooks.PreToolUse` を定義すると、`claude/deploy.sh` の
浅い `update()` マージによりベース側の `hooks.PreToolUse`（本フックの配線）が丸ごと
上書きされる（§4.3・ADR §3.4 参照）。恒久的に無効化したい場合は、machine.json に
空配列 `"PreToolUse": []` を持つ `hooks` を書くか、リポジトリ側の `claude/settings.json` から
`hooks.PreToolUse` を削除する。

`git merge` と、対象ブランチ名がコマンド文字列中に空白区切りの裸の単語として
現れない書き方の `git push --force-with-lease`（refspec 省略・`HEAD`/`@`・
`HEAD:master` のようなコロン区切り・`refs/heads/master` のような完全参照）
には `permissions.ask` 側の保険が無い設計（ADR §3.3「受け入れる残余リスク」）
なので、無効化すると保護ブランチへのこれらの操作がガード無しで通るように
なることに注意すること。

## 4. Customization — マシン固有設定の追加

`settings.json` にはマシン固有の設定（`permissions.allow`、`additionalDirectories`、`hooks`）が含まれていません。

**Claude Code はユーザーレベルの `~/.claude/settings.local.json` を読み取りません。**
（`--setting-sources` の `local` はプロジェクトレベルの `.claude/settings.local.json` を指します。）

代わりに `claude/settings.machine.json` を使います。deploy.sh がベース設定とマージして
`~/.claude/settings.json` を生成します。

### 4.1 初回セットアップ

```bash
cd ~/.dotfiles/claude

# テンプレートから settings.machine.json を作成
cp settings.machine.json.example settings.machine.json

# 自分の環境に合わせて編集
vim settings.machine.json

# デプロイ実行(ベース + machine をマージして ~/.claude/settings.json を生成)
# 単体の ./deploy.sh ではなく、リポジトリルートから ./deploy-all.sh を実行すること。
# 単体実行は配布実体(current)経由でしか settings.machine.json を読まないため、
# 作業ツリー側で今編集した内容を拾わない(ルート AGENTS.md「デプロイの仕組み」節参照)。
cd ~/.dotfiles
./deploy-all.sh --only claude
```

`settings.machine.json` は `.gitignore` で除外されているため、commit されません。

### 4.2 `permissions.allow` の追加

```json
{
  "permissions": {
    "allow": [
      "Bash",
      "Read",
      "Edit",
      "WebFetch",
      "Read(//home/manemone/projects/my-project/**)",
      "Bash(git checkout *)",
      "Bash(git fetch *)",
      "Bash(git branch *)"
    ]
  }
}
```

マージの仕組み:
- `settings.json`（ベース）の上に `settings.machine.json` を shallow merge
- `permissions` 内のリストキー（`allow`, `deny`, `ask`）は**結合**（重複除去、machine 側の項目が末尾に追加）
- それ以外のキーは machine 側の値で上書き

### 4.3 `hooks` の追加

セッション開始時のフックを追加する例:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash '/path/to/your/hook.sh' session",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

> **注意**: Herdr の `herdr-agent-state.sh` hook が必要な場合は、これを含めてください。

### 4.4 `model` / `theme` の上書き

```json
{
  "model": "sonnet",
  "theme": "light"
}
```

### 4.5 `additionalDirectories` の追加

```json
{
  "permissions": {
    "additionalDirectories": [
      "/home/manemone/projects/my-other-project/config"
    ]
  }
}
```

### 4.6 `defaultMode` の上書き

```json
{
  "permissions": {
    "defaultMode": "acceptEdits"
  }
}
```

### 4.7 設定の反映確認

`settings.machine.json` を編集した後は、再デプロイで反映されます。**単体の `claude/deploy.sh`
ではなく `./deploy-all.sh` を使うこと**（単体実行は配布実体経由でしか読まないため、
作業ツリー側の編集を拾わない）:

```bash
cd ~/.dotfiles
./deploy-all.sh --only claude
```

Claude Code は起動時に設定を読み込むため、設定変更後は Claude Code を再起動してください。

### 4.8 CLAUDE.md の編集

既定（世代モード）では、`~/.claude/CLAUDE.md` は配布実体（世代ディレクトリ）内のコピーへの
symlink であり、**リポジトリの作業ツリーを直接指してはいない**（旧方式（作業ツリー直リンク）
とは異なる点に注意）。

- `~/.claude/CLAUDE.md` を直接編集すると即座に反映されるが、リポジトリ側には反映されず、
  次回 `./deploy-all.sh` 実行時に上書きされる
- リポジトリ側の `claude/CLAUDE.md` を編集しても、`./deploy-all.sh` を再実行するまで
  `~/.claude/CLAUDE.md` には反映されない。**単体の `claude/deploy.sh` を実行しても
  反映されない**（配布実体経由でしか読まないため。新しい世代を作るのは `deploy-all.sh` だけ）
- 編集のたびに即時反映させたい場合は dev モード（`./deploy-all.sh --dev`）を使う。この場合
  `current` が作業ツリーそのものを指すため、リポジトリ側の編集がそのまま
  `~/.claude/CLAUDE.md` に反映される（世代方式の詳細はルート `AGENTS.md`
  「デプロイの仕組み」・ADR DOC-2608040229 を参照）

```bash
# 恒久的に変更する場合（世代モード）
vim ~/.dotfiles/claude/CLAUDE.md
cd ~/.dotfiles && ./deploy-all.sh --only claude

# 試行錯誤したい場合（dev モード）
./deploy-all.sh --dev
vim ~/.dotfiles/claude/CLAUDE.md   # 即座に ~/.claude/CLAUDE.md に反映される
```

## 5. Troubleshooting

### `~/.claude/settings.json` の変更を反映したい

Claude Code は起動時に設定を読み込みます。

- **マシン固有の設定を追加・変更する** → `claude/settings.machine.json` を編集して再デプロイ
  （単体の `claude/deploy.sh` ではなく `./deploy-all.sh` を使うこと。単体実行は配布実体
  経由でしか読まないため、今編集した内容を拾わない）:
  ```bash
  cd ~/.dotfiles && ./deploy-all.sh --only claude
  ```
- **`~/.claude/settings.json` を何らかの理由で直接編集した** → Claude Code を再起動。
  ただし次回 `./deploy-all.sh` 実行時に上書きされるため、恒久的な変更は `settings.machine.json` に転記してください。

### `settings.machine.json` の変更が反映されない

`settings.machine.json` を編集した後は、**必ず `./deploy-all.sh` で再デプロイ**してください。
単体の `claude/deploy.sh` では配布実体（`current`）経由でしか読まないため、
今編集した `settings.machine.json` の内容を拾いません。

```bash
cd ~/.dotfiles && ./deploy-all.sh --only claude
```

### デプロイで既存設定が消えた

deploy.sh は既存の `~/.claude/settings.json` を `.backup` 付きで退避します。
退避されたファイルから設定を確認し、`settings.machine.json` に転記してください:

```bash
# バックアップを確認
ls -la ~/.claude/settings.json.backup*

# バックアップから復元（必要に応じて）
cp ~/.claude/settings.json.backup ~/.claude/settings.json
```

### `python3` がないと言われる

`settings.machine.json` を使わない場合は必須ではありませんが、無いと**学習した
`permissions.allow` の保全（§3.2.1）もスキップされます**（deploy 自体は失敗せず、
警告を出してベース設定のみで生成します）。`settings.machine.json` によるマージ・
allow の保全のどちらかでも使いたい場合は python3 をインストールしてください:

```bash
mise use python@latest
# または
sudo apt install python3
```

### `settings.machine.json` が JSON として invalid

```bash
python3 -m json.tool claude/settings.machine.json
```

エラーが出たら JSON の構文を修正してください。

### symlink が壊れている

```bash
cd ~/.dotfiles

# 確認
ls -la ~/.claude/CLAUDE.md
./deploy-all.sh --status   # current の向き先・リンク切れの有無も確認できる

# 修復
./deploy-all.sh --only claude
```

## 6. 移行手順 — この変更（allow 保全）を取り込んだ後、次の deploy 前に人間が行うこと

孫2（学習した allow の deploy 越し保全。計画書
[DOC-2609121700](../docs/planning/DOC-2609121700_autopilot-permissions_計画.md)
設計3）と、孫1（git-guard フック。ADR
[DOC-2609121719](../docs/adr/DOC-2609121719_git-operation-permission-policy.md)）が
両方マージされたあと、実際に deploy する前に**必ず**次を行うこと。
どちらも `claude/settings.machine.json` は git 非追跡のマシン固有ファイルなので、
AI はこのファイルを編集しない（PR の diff に乗らない変更を人間が知らないうちに
受け取ることになるため）。**この節はその手順を文書化するだけで、AI 自身は実行しない。**

1. **`claude/settings.machine.json` の `permissions.deny` から
   `"Bash(git merge *)"` と `"Bash(git merge --*)"` の2行を削除する。**
   この2行を消さないと、新しい git-guard フックが `allow` を返しても
   `deny` が勝つため（優先順位は `deny > ask > allow`）、`git merge` が
   保護ブランチ以外でも一切実行できないままになる（計画書 背景3-B参照）
2. `settings.machine.json` は git 非追跡でワークツリーごとに独立している。
   **`settings.machine.json` を持つワークツリー（通常は main ワークツリー）から
   deploy すること。** 傘や孫のワークツリーには存在しないため、そこから
   deploy すると machine.json ごと消えた生成物になる（`hooks` の Herdr
   `SessionStart` などが一時的に失われる。§2の「⚠️ 重要」参照）
3. 現在 `~/.claude/settings.json` に**手で**入っている `"Bash(git merge *)"`
   （`permissions.ask`）は、この孫2の保全対象（`allow` のみ）に含まれないため
   **何もしなくても次の deploy で自然に消える**。これは意図した挙動であり
   （背景3-Aで指摘された「手で足された `ask` が永久に固定化する」状態を
   壊すのが目的）、復元する必要はない

上記1・2を行わずに deploy すると、`git merge` が保護ブランチ以外でも
`deny` によって完全に不能になる（時限爆弾。背景3-B参照）。
