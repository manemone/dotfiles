# Claude Code Config (claude)

## Overview

Claude Code の設定ファイル群。`~/.claude/` にデプロイして使う。

| File | Purpose | Deploy Method |
|---|---|---|
| `CLAUDE.md` | Claude Code の個人指示（プロジェクト横断で適用されるグローバル指示） | symlink |
| `settings.json` | Claude Code の汎用設定（モデル、権限ポリシー、テーマ等）。マシン固有設定は**含まない** | 生成（マージ） |
| `settings.machine.json.example` | マシン固有設定のテンプレート・参照用サンプル。**配布されない**（手でコピーする用） | （手動コピー） |

`~/.claude/settings.machine.json`（マシン固有設定の実体）はこのリポジトリの中身では**ない**。
実体は `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/settings.machine.json`
という、`current` や `generations/` と同じ階層にある**世代を経由しない固定パス**にあり、
`~/.claude/settings.machine.json` はそこへの symlink として `settings.json` の隣に
張られる（§4参照）。世代（`claude/settings.machine.json`）を経由しないのは、git 非追跡の
マシン固有ファイルをワークツリーごとに持たせると、machine.json を持たないワークツリー
（傘や孫など）から deploy した瞬間に空扱いされて人間の設定が消えるため
（計画書 [DOC-2609121700](../docs/planning/DOC-2609121700_autopilot-permissions_計画.md)
設計6）。

## 1. Requirements

| Tool | Why | Install |
|---|---|---|
| **Claude Code** CLI | 設定ファイルの読み取り元 | `npm install -g @anthropic-ai/claude-code` |
| **Python 3** | `settings.machine.json` とのマージ、および学習済み `permissions.allow` の保全用。**`settings.machine.json` が無い環境では任意**（無ければ保全だけがスキップされ、ベース設定のみで生成される）。**`settings.machine.json` がある環境では必須**（無いと deploy が失敗する） | `mise use python@latest` |

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
- Symlinks `settings.machine.json` → `~/.claude/settings.machine.json`（固定パスの実体。無ければ
  空の `{}` を作ってから symlink する。§4参照）
- Generates `~/.claude/settings.json` as a real file（※symlink ではない）。入力は3つ:
  1. ベース設定（`claude/settings.json`）
  2. マシン固有設定（固定パスの `settings.machine.json`。存在すれば）
  3. **今まさに置き換えようとしている生成物（`~/.claude/settings.json`）の `permissions.allow`**
     — Claude Code が対話で学習した allow を deploy 越しに保全する（§3.2.1参照）

`~/.claude/skills/` はこのスクリプトの担当ではない。スキルは Claude Code 専用ではなく
Codex・OpenCode にも同じ実体が配られるため、トップレベルの `skills/` ツールが受け持つ
（[skills/README.md](../skills/README.md) / ADR
[DOC-2608272128](../docs/adr/DOC-2608272128_skills-multi-agent-distribution.md)）。

> **⚠️ 重要**: deploy 実行時に既存の `~/.claude/settings.json` はバックアップ（`.backup` 付きで退避）されます。
> `permissions.allow` は次回 deploy でも自動的に保全されますが（§3.2.1参照）、
> Herdr の `SessionStart` hook や `additionalDirectories` など**`allow` 以外のマシン固有設定は
> 保全されません**。失われるのを防ぐには、**deploy 前に `settings.machine.json`（固定パスの実体。
> §4参照）を作成**してください。固定パスの実体は生成のたびに空へ戻ることはない（§4冒頭参照）ので、
> 一度作れば以後の deploy で毎回作り直す必要はない。

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
リポジトリ側のベース設定には分類器対策の狭いルール（`mkdir -p` 等。§3.5・
ADR §7.4参照）のみ含む。deploy 時には、これに加えて学習済みの分が自動的に
合成される — §3.2.1参照）。

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
| `permissions.allow` | 分類器対策の狭いルール（1件） | `mkdir -p` は auto mode の分類器待ちになるため、`permissions` 側で即決させる（§3.5・ADR §7.4） |
| `permissions.deny` | セキュリティポリシー（24件） | `.env`, `.ssh`, `.aws`, API キー等へのアクセスをブロック |
| `permissions.ask` | 危険コマンドパターン（54件） | `git push --force`, `rm -r /home*` 等の名指しした絶対パス, `sudo` 等の実行前に確認（§3.5参照） |
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
`settings.machine.json` が無ければ `python3` が無くても保全をスキップして動作するが、
`settings.machine.json` がある環境では `python3` は必須である（§1参照）。

`--dry-run` では、何件の `allow` を保全する予定かをログに出す
（実ファイルには一切書き込まない）。

**保全は一方通行 — `allow` の取り消しは deploy では反映されない。** この仕組みは
「既存生成物の `allow` を無条件に次の生成物へ足し戻す」ものなので、**一度
`~/.claude/settings.json` の `permissions.allow` に入った項目は、以後どのような
deploy を実行しても消えない。** これは学習した allow を残したい場合は意図どおりだが、
`settings.machine.json` 由来の `allow` にも等しく効く。たとえば
`settings.machine.json.example` や §4.2 が例示する `"Bash"`（無条件許可）を一度
deploy した後、`settings.machine.json` からその行を削除して再デプロイしても、
生成物の `allow` には `"Bash"` が残り続ける。

取り消したい場合は、`~/.claude/settings.json` を直接編集する（または Claude Code の
`/permissions` から削除する）こと。`settings.machine.json` の行を消す・
`settings.machine.json` を削除する・`.backup` から復元する、のいずれも
**削除の取り消しにはならない**（§4.2・§4.7・§5「デプロイで既存設定が消えた」も参照）。

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
競合地帯**である。`claude/deploy.sh` は machine 設定（固定パスの実体。§4参照）が `hooks` を
含まない場合、Herdr が実行時に書き足した `hooks` ごと上書きしてしまう
（実機検証中に実際にこの事故が発生している — 詳細は DOC-2608021229 Appendix A 参照）。

> かつては machine.json が git 非追跡のワークツリー相対ファイルだったため、
> machine.json を持たないワークツリー（傘や孫など）から deploy するだけでもこの事故が
> 起きた（計画書 [DOC-2609121700](../docs/planning/DOC-2609121700_autopilot-permissions_計画.md)
> 背景3-B）。孫6でこの実体が固定パスへ移り、どのワークツリーから deploy しても同じ
> machine 設定を使うようになったため、**「別のワークツリーから deploy したら消えた」という
> 形のこの事故は起きなくなっている。** 残るのは、machine 設定自体が `hooks` を持っていない
> （そもそも設定していない）場合に Herdr の書き足しが上書きされるケースのみ。

**`statusLine` を配線した本設定を deploy する前に、必ず以下を確認・実施すること:**

1. `~/.claude/settings.json` の現在の `hooks` を確認する:
   ```bash
   python3 -c "import json; print(json.dumps(json.load(open('$HOME/.claude/settings.json')).get('hooks'), indent=2))"
   ```
2. `~/.claude/settings.machine.json`（固定パスへの symlink。§4参照）に、
   確認した `hooks`（通常は Herdr の `herdr-agent-state.sh`）を明記する（§4.3参照）
3. `./deploy-all.sh --only claude`（リポジトリルートから）を実行する。machine 設定は
   固定パスから直接読まれるため、単体の `claude/deploy.sh` でも反映されるが、
   `settings.json` のベース側の変更まで確実に拾いたい場合は `deploy-all.sh` を使うこと
4. deploy 後、再度 手順1 のコマンドを実行し、`hooks.SessionStart` が健在であることを確認する

**statusLine の無効化方法:**

`settings.machine.json`（固定パスの実体）に `"statusLine": null` は効かない（machine側の shallow merge は
`null` も値として上書きしてしまうだけで、キー自体を消せない）。無効化したい場合は
`~/.claude/settings.json` の `statusLine` キーを deploy 後に手動で削除する
（**次回 `./deploy-all.sh` 実行時に `claude/settings.json` の内容で再度上書きされる**ので、
恒久的に無効化したい場合はリポジトリ側の `claude/settings.json` から `statusLine` を削除すること）。

### 3.5 git-guard フック — main/master への破壊的操作・chmod・rm -r の機械的ガード

`~/.claude/hooks/git-guard.sh`（`claude/hooks/git-guard.sh` から symlink される PreToolUse
フック）が、「`main`/`master` へのマージ・push は人間、それ以外の git 操作は AI に任せる」
という線引きに加えて、無人ペインを止める非 git 操作（`chmod +x`・`rm -r`）のうち
安全と判定できるものを機械的に担保する。設計の根拠・却下案・PreToolUse フックの
入出力契約の確認結果は ADR
[DOC-2609121719](../docs/adr/DOC-2609121719_git-operation-permission-policy.md)
（chmod/rm-r への適用は同 ADR §7）を参照。

**何を止めて何を通すか（判定表）:**

| 対象コマンド | 判定 |
|---|---|
| `gh pr merge`（PR 番号 / URL / 省略＝現ブランチ） | base ブランチが `main`/`master` なら **deny**、それ以外は **allow** |
| `git push` に `--force` / `--force-with-lease` / `-f` / `+<refspec>` が付く | 対象ブランチが `main`/`master` なら **deny**。それ以外は `--force-with-lease` を **allow**、裸の `--force`/`-f` は **ask** |
| `git merge` | 現在のブランチ（マージ先）が `main`/`master` なら **deny**、それ以外は **allow** |
| `chmod`（`-R`/`--recursive` 無し・モードが実行ビット付与のみのシンボリック指定 `+x`/`u+x`/`a+x` 等・対象パスが1つ残らずシェル展開文字（`~ $ * ? [ ] { } \` < >`）を含まず、かつ全て現在の git ワークツリー内かつ `.git` 配下でない） | **allow**。1つでも満たさなければ **ask**（`deny` ではない） |
| `rm -r`/`-rf`/`-fr`/`-R`/`--recursive`（対象パスが1つ残らず上記と同じ意味でシェル展開文字を含まず、一時ディレクトリ配下——このセッションの scratchpad、または `$TMPDIR`/`/tmp` 自身より深い場所——に解決され、かつ git ワークツリー内でない） | **allow**。1つでも満たさなければ **ask** |
| 上記以外の git/gh/chmod/rm コマンド、対象を安全に判定できないコマンド | 何も言わず `permissions.ask` の判定に委ねる、または **ask** |

判定できない入力（PR 番号が解決できない・`gh` の実行に失敗する・現在のブランチが
取れない・複数コマンドが `&&`/`;`/`|` で連結されている・chmod/rm の未知のオプション
等）は必ず `ask` に倒す。**`allow` に倒すことは絶対に無い。**

`chmod`/`rm -r` を対象に含めた理由（背景3-G）: `Bash(chmod *)`/`Bash(rm -r *)` の
ようなパターンは「対象がワークツリー内か `/etc` 配下か」を区別できず、無人の孫
ペインが新規スクリプトへの `chmod +x` や `mktemp -d` の後片付けで頻繁に止まって
いた。詳細は ADR §7 を参照。

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

同じ理由で `chmod`/`rm -r` も narrow 化している（ADR §7.3）。`Bash(chmod *)`
は削除し、`-R`/`--recursive`・絶対パス（`chmod * /*`。`/Users` 等の macOS の
ホームを含む全ての `/` 始まりパスを拾う）・`~`/`$HOME`（`chmod * ~*`/
`chmod * $HOME*`）だけを無条件 `ask` として残した。`Bash(rm -r *)`/
`Bash(rm -rf *)`/`Bash(rm -fr *)` も削除し、
`/home`/`/usr`/`/etc`/`/var`/`/mnt`/`/opt`/`~`/`$HOME`/`/Users`（macOS の
ホーム）を名指しした絶対パスだけを無条件 `ask` として残している。
**ワークツリー内の相対パスへの chmod/rm -r はこれらのパターンのどれにも
一致しない**（それがフックに allow させる目的）ため、フックが配布されて
いない・壊れている環境では、これらの操作はガード無しで通る
（fail-open。ADR §7.3「受け入れる残余リスク」）。

**無効化したいとき:**

`settings.machine.json`（固定パスの実体）に `hooks.PreToolUse` を定義すると、`claude/deploy.sh` の
浅い `update()` マージによりベース側の `hooks.PreToolUse`（本フックの配線）が丸ごと
上書きされる（§4.3・ADR §3.4 参照）。恒久的に無効化したい場合は、machine.json に
空配列 `"PreToolUse": []` を持つ `hooks` を書くか、リポジトリ側の `claude/settings.json` から
`hooks.PreToolUse` を削除する。

`git merge` と、対象ブランチ名がコマンド文字列中に空白区切りの裸の単語として
現れない書き方の `git push --force-with-lease`（refspec 省略・`HEAD`/`@`・
`HEAD:master` のようなコロン区切り・`refs/heads/master` のような完全参照）
には `permissions.ask` 側の保険が無い設計（ADR §3.3「受け入れる残余リスク」）
なので、無効化すると保護ブランチへのこれらの操作がガード無しで通るように
なることに注意すること。同様に、ワークツリー内の相対パスへの `chmod +x` /
`rm -r`（scratchpad・`/tmp` 配下）にも `permissions.ask` 側の保険が無い
（ADR §7.3）ため、無効化するとこれらも無確認で通るようになる。

## 4. Customization — マシン固有設定の追加

`settings.json` にはマシン固有の設定（`permissions.allow`、`additionalDirectories`、`hooks`）が含まれていません。

**Claude Code はユーザーレベルの `~/.claude/settings.local.json` を読み取りません。**
（`--setting-sources` の `local` はプロジェクトレベルの `.claude/settings.local.json` を指します。）

代わりに `settings.machine.json` を使います。実体は
`${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/settings.machine.json`
という**世代を経由しない固定パス**（`current` や `generations/` と同じ階層）にあり、
`~/.claude/settings.machine.json` はそこへの symlink です。deploy.sh がこれをベース設定と
マージして `~/.claude/settings.json` を生成します。

**settings.json のベース設定や CLAUDE.md と違い、machine 設定は世代を経由しない実パスから
直接読まれる。** そのため、`~/.claude/settings.machine.json`（またはその実体）を編集した後は、
単体の `claude/deploy.sh`（`current` さえあれば動く）でも `./deploy-all.sh` でも、
どちらでも変更が反映される。

### 4.1 初回セットアップ

初回 deploy 時に固定パスの実体が無ければ、deploy が自動的に空の `{}` を作成します。
最初から内容を入れておきたい場合は、deploy 前に手動で固定パスへ作成してください:

```bash
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles"
vim "${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/settings.machine.json"
```

`settings.machine.json.example` は**内容を確認するための参照用サンプルであり、
丸ごとコピーしてはいけません。** 中身は `"allow": ["Bash", "Read", "Edit", "WebFetch", ...]`
という無条件の全許可と、存在しないパス（`/path/to/your/hook.sh`）を指す壊れた
`SessionStart` フックです。この傘（計画書 [DOC-2609121700](../docs/planning/DOC-2609121700_autopilot-permissions_計画.md)
背景3-I）が締め直した権限をこれで上書きすると、孫1のガードフックが `allow` を返しても
無条件 `Bash` の `allow` が並び立ってしまい、権限ポリシーが実質的に無効化されます。
固定パスはワークツリーをまたいで共有され `uninstall.sh` でも消えないため、一度ここに
全許可が入ると以前より気づきにくく消えにくくなります。実際に必要な項目（自分の
`additionalDirectories` や Herdr の `hooks.SessionStart` など）だけを、パスを自分の
環境に合わせて書き換えたうえで手で書き写してください。

内容を書いたら、デプロイを実行します（ベース + machine をマージして
`~/.claude/settings.json` を生成）:

```bash
cd ~/.dotfiles
./deploy-all.sh --only claude
```

すでに `~/.claude/settings.machine.json` が symlink として存在する場合は、それを直接
編集して構いません（固定パスの実体を編集するのと同じことです）:

```bash
vim ~/.claude/settings.machine.json
cd ~/.dotfiles && ./deploy-all.sh --only claude
```

固定パスの実体は `.gitignore` で除外されている旧パス（`claude/settings.machine.json`）とは
別物で、そもそもリポジトリの外（`$XDG_DATA_HOME` 配下）にあるため commit されません。
旧パスにファイルが残っている場合は、次の deploy で自動的に固定パスへ移行されます
（§7「移行手順 — settings.machine.json の固定パス化」参照）。

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

> **⚠️ ここで足した `allow` は、後で `settings.machine.json` から行を削除しても取り消せない。**
> `~/.claude/settings.json` の生成物側に一度入った `allow` は deploy 越しに保全され続ける
> （§3.2.1「保全は一方通行」参照）。取り消すには `~/.claude/settings.json` を直接編集する
> （または `/permissions` から削除する）必要がある。

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

`settings.machine.json`（固定パスの実体、または `~/.claude/settings.machine.json` symlink
経由）を編集した後は、再デプロイで反映されます。固定パスは世代を経由せず直接読まれるため、
単体の `claude/deploy.sh`（`current` が既にある環境）でも `./deploy-all.sh` でも構いません:

```bash
cd ~/.dotfiles
./deploy-all.sh --only claude
```

Claude Code は起動時に設定を読み込むため、設定変更後は Claude Code を再起動してください。

**例外: `permissions.allow` の削除は反映されない。** `settings.machine.json` から
`allow` の行を削除して再デプロイしても、生成物側に既に入っている `allow` は消えない
（§3.2.1「保全は一方通行」参照）。反映されるのは `allow` の**追加**と、`allow` 以外の
キーの変更・削除だけである。

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

- **マシン固有の設定を追加・変更する** → `~/.claude/settings.machine.json`（固定パスへの
  symlink）を編集して再デプロイ:
  ```bash
  cd ~/.dotfiles && ./deploy-all.sh --only claude
  ```
- **`~/.claude/settings.json` を何らかの理由で直接編集した** → Claude Code を再起動。
  ただし次回 `./deploy-all.sh` 実行時に上書きされるため、恒久的な変更は `settings.machine.json` に転記してください。

### `settings.machine.json` の変更が反映されない

`settings.machine.json` は世代を経由しない固定パスから直接読まれるため、単体の
`claude/deploy.sh` でも `./deploy-all.sh` でも編集内容は拾われます。それでも反映されない
場合は、症状に応じて次を確認してください:

```bash
cd ~/.dotfiles && ./deploy-all.sh --only claude
```

- 固定パスとソースツリー（`claude/settings.machine.json`。旧パス）の**両方**にファイルが
  あり、内容が異なる場合は deploy がエラーで停止します（§7参照）。deploy のログに
  `Both ... exist with DIFFERENT content` が出ていないか確認してください
- 編集した先が `~/.claude/settings.machine.json` の symlink 先（固定パス）と一致しているか
  `readlink ~/.claude/settings.machine.json` で確認してください

**`permissions.allow` の行を削除した場合はこれに当てはまらない。** 削除は再デプロイしても
反映されない（§3.2.1「保全は一方通行」参照）。`allow` を取り消したいときは
`~/.claude/settings.json` を直接編集すること。

### デプロイで既存設定が消えた

deploy.sh は既存の `~/.claude/settings.json` を `.backup` 付きで退避します。
退避されたファイルから設定を確認し、`settings.machine.json` に転記してください:

```bash
# バックアップを確認
ls -la ~/.claude/settings.json.backup*

# バックアップから復元（必要に応じて）
cp ~/.claude/settings.json.backup ~/.claude/settings.json
```

**このバックアップから `permissions.allow` を丸ごと復元すると、消したかったはずの
`allow` エントリも一緒に恒久化される。** バックアップは「消えた設定を探す」ためだけに使い、
`allow` は必要な項目だけを `~/.claude/settings.json` へ個別に転記すること。

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
python3 -m json.tool ~/.claude/settings.machine.json
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
`settings.machine.json` は git 非追跡のマシン固有ファイルなので、
AI はこのファイルを編集しない（PR の diff に乗らない変更を人間が知らないうちに
受け取ることになるため）。**この節はその手順を文書化するだけで、AI 自身は実行しない。**

1. **`settings.machine.json`（`~/.claude/settings.machine.json` の symlink先。固定パスの
   実体）の `permissions.deny` から `"Bash(git merge *)"` と `"Bash(git merge --*)"` の
   2行を削除する。** この2行を消さないと、新しい git-guard フックが `allow` を返しても
   `deny` が勝つため（優先順位は `deny > ask > allow`）、`git merge` が
   保護ブランチ以外でも一切実行できないままになる（計画書 背景3-B参照）
2. 現在 `~/.claude/settings.json` に**手で**入っている `"Bash(git merge *)"`
   （`permissions.ask`）は、この孫2の保全対象（`allow` のみ）に含まれないため
   **何もしなくても次の deploy で自然に消える**。これは意図した挙動であり
   （背景3-Aで指摘された「手で足された `ask` が永久に固定化する」状態を
   壊すのが目的）、復元する必要はない

上記1を行わずに deploy すると、`git merge` が保護ブランチ以外でも
`deny` によって完全に不能になる（時限爆弾。背景3-B参照）。

> 背景3-Bにはもう一つの側面（「machine.json を持たないワークツリーから deploy すると
> machine.json ごと消える」）があったが、これは孫6（§7参照）で実体を固定パス化した
> ことで解消済み。ワークツリーを選んで deploy する必要はもう無い。

## 7. 移行手順 — settings.machine.json の固定パス化（孫6）

孫6（計画書 [DOC-2609121700](../docs/planning/DOC-2609121700_autopilot-permissions_計画.md)
設計6）で、`settings.machine.json` の実体は git 非追跡のソースツリー相対パス
（`claude/settings.machine.json`）から、`${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/settings.machine.json`
という世代を経由しない固定パスへ移った。

- **旧パスにファイルがあり、固定パスに何も無い場合**: `claude/deploy.sh` が deploy 時に
  自動的に移行する（`mv` して、何をどこへ移したかログに出す）。人間が事前に何かする
  必要はない
- **旧パスと固定パスの両方にファイルがあり、内容が同じ場合**: deploy は警告を出すだけで
  続行する。旧パスのファイルは以後読まれないので、削除して構わない
- **旧パスと固定パスの両方にファイルがあり、内容が異なる場合**: **deploy はどちらを
  採用するか自動で決めず、エラーで停止する。** 該当するワークツリーの
  `claude/settings.machine.json`（旧パス）を、固定パスの内容を見比べたうえで
  手動で削除するかマージしてから再デプロイすること
- 移行後は `~/.claude/settings.machine.json` が固定パスへの symlink になる。以後の編集は
  この symlink（または固定パス自体）に対して行う
- `uninstall.sh` はこの symlink だけを撤去し、固定パスの実体には触れない
  （人間のマシン設定であり、この repo の配布物ではないため）
