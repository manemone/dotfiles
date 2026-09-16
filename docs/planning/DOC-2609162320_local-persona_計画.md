# 計画書: 配布される人格のパーソナライズ設定をデプロイ先でローカルにカスタマイズ可能にする

傘ブランチ: `local-persona`
ターゲット: `master`

## 概要

`claude/CLAUDE.md`（配布物）の冒頭に人格のパーソナライズ設定（現状は口調の指定）が直書きされており、このファイルは symlink で
Claude Code / Codex / OpenCode の3エージェントへ配られている（ADR DOC-2609072334）。
symlink である以上、デプロイ先でパーソナライズをいじる＝リポジトリの追跡ファイルを書き換えることになり、
**マシン固有のパーソナライズを持つ手段が一切ない**。`settings.json` には `settings.machine.json` という
マシンローカルな上書きの枠組みがあるのに、`CLAUDE.md` には無い。

本傘は、パーソナライズ設定を**世代を経由しない固定パスのマシンローカルファイル**
（`<prefix>/CLAUDE.machine.md`）へ切り出し、ベースの `claude/CLAUDE.md` はデフォルト文言と
「定義元を指す」記述だけを持つ形にする。3エージェントそれぞれの「別ファイル読み込み」手段の
差に合わせて、孫を3本に分ける。

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。既に削除済み）を
> material として司令官が起草したものである。** ブリーフに書かれていた問題意識・決定事項・
> 実測値・未解決論点・制約は、**すべて本計画書へ転記済み**であり、以降はこの計画書が正典である。

### 用語: 「口調」ではなく「人格のパーソナライズ」

相談の時点では人間もブリーフも「口調」と呼んでいたが、**扱う対象は口調に限らない人格のパーソナライズ**
（口調・語尾・一人称/二人称・キャラクター付け・応答のノリなど）である、と人間が計画書起草後に方針を示した
（2026-09-16）。現行の `claude/CLAUDE.md` の文言がたまたま口調中心なだけで、仕組みは「このマシンでの人格を
マシンローカルに差し替える枠組み」として設計・説明する。

- ドキュメント（README・ADR・`claude/CLAUDE.md` のデフォルト文言）・コマンドのヘルプ・コメントでは
  「人格のパーソナライズ」（文脈上くどければ「パーソナライズ」）と書き、「口調設定」を仕組みの名前として使わない。
  具体例として「口調など」と添えるのは構わない
- 背景1 の人間の発言（逐語）と、背景3 の現物の引用は当時の言葉のまま残す
- ブランチ名 `local-persona-*` とワークスペースラベル（既に作成済み）は変えない
- 孫3 の新コマンド名も「tone」ではなく人格/パーソナライズを表す名前にする

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `local-persona-01-claude-machine-md` | Claude Code 向けの土台（固定パス実体 `CLAUDE.machine.md`・`@` import・ベースのデフォルト文言・deploy/uninstall/status・新規 ADR） | ✅ PR #96 マージ済 |
| 2 | `local-persona-02-opencode` | OpenCode 対応（`opencode.json` の新規配布。未解決論点1・2の検証と決着） | ⬜ 待機中 |
| 3 | `local-persona-03-codex` | Codex 対応（ベース + machine の連結生成と `bin/` の再生成コマンド。未解決論点3・4の決着） | ⬜ 待機中 |

## ワークスペースラベル

- 傘: `dotfiles :: 口調のローカル化`（`umbrella-handoff` が付けた既存ラベル。司令官は改名しない）
- 孫1: `dotfiles :: 口調のローカル化 孫1 ClaudeCode土台`
- 孫2: `dotfiles :: 口調のローカル化 孫2 OpenCode対応`
- 孫3: `dotfiles :: 口調のローカル化 孫3 Codex再生成コマンド`

## 依存関係と実行順序

```
孫1 (固定パス実体・ベース文言・ADR を確定させる)
  ↓ 孫2・孫3 は孫1 が決めた実体パス helper と ADR の上に乗る
孫2 (OpenCode)
  ↓ shared/helpers.sh の links_for_tool()・uninstall.sh・tests/deploy_smoke.sh・
  ↓ AGENTS.md・ADR を孫2 と孫3 が共通で触るため、並列にすると確実に衝突する
孫3 (Codex)
```

**直列。** 理由:

1. **孫1 が固定パス helper（`shared/helpers.sh`）と新規 ADR を作る。** 孫2・孫3 はそこへ
   arm や節を足す側であり、土台が無い状態では着手できない
2. **孫2・孫3 は同じファイル群（`shared/helpers.sh` `uninstall.sh` `tests/deploy_smoke.sh`
   ルート `AGENTS.md` 新規 ADR）に触る。**
3. 孫1 を先に出す価値は「一番欲しい機能（Claude Code で編集即反映）が、`bin/` の新ツール設計で
   揉めている間に止まらない」点にある（ブリーフの判断をそのまま採用）

**孫2 と孫3 の順序について**: OpenCode は「静的 symlink で済むか／生成が要るか」が未確定
（未解決論点1）で、孫3 の Codex 生成物の置き場所・uninstall の扱いと設計が似る可能性がある。
先に小さい方（孫2）で固定パス配下の配布物の作法を固め、孫3 がそれに合わせる。

### 傘の途中状態について（既知・許容）

孫1 マージ後・孫2/孫3 マージ前の傘ブランチでは、ベース `claude/CLAUDE.md` に Claude Code
専用の `@` import 行が入るため、**OpenCode / Codex には import 行が文字列のまま届き、パーソナライズは
効かない**（デフォルト＝パーソナライズ指定なしの状態になる）。傘は `master` へまとめて入るので実害は無い。
ただし傘ワークツリーから deploy して人間が使うことは想定しない。

---

## 背景1: 人間の問題意識（逐語）

> 配布ファイルの中に、口調を設定してるところがあると思うんだが、これをデプロイ先でローカルにカスタマイズできるようにしたい。デフォルトでは口調を指定するのではなく、なんらかのオプションを渡して設定できるようにしたい。どういう風にするのがいいと思う？

相談AIが「連結してデプロイ時に生成する」案を出した直後、人間から次の追加要求が出た。
**この一言が設計の中心であり、生成方式を却下した根拠である。**

> でも、変えたいとき、デプロイせずに口調部分を変えるだけで済むようにしたいなあ

## 背景2: 人間が確定させた決定事項（覆さないこと）

相談中の選択式質問で人間が明示的に選んだもの。

- **パーソナライズは Claude Code / Codex / OpenCode の3エージェント全部で効かせる。**
  Claude Code だけに絞る案は明示的に却下された
- **デフォルト（ローカル設定が空）のとき、ベース側にデフォルト文言を書いておく。**
  「パーソナライズの節ごと出さない」案は却下された。何も指定していない状態が明示されるほうを選んだ
- **Codex 向けには専用の再生成コマンドを用意する。** Codex だけパーソナライズ非対応にして
  割り切る案・`codex/` への配布自体をやめる案は、どちらも却下された
- **OpenCode 向けに `opencode.json` を新規配布物にしてよい。** OpenCode もパーソナライズ
  非対応にして変更範囲を `claude/` 内に閉じる案は却下された
- **編集即反映が最優先要件である。** デプロイを挟む方式は Codex を除いて認められない

### 決定事項の解釈上の注意（重要）

人間は相談の第1ラウンドで「3エージェント共通（連結生成）」を選んでいる。しかしこれは
**「deploy せずに変えたい」という追加要求が出る前の選択**であり、その後の再設計で
連結生成は Codex 専用に縮小された。「3エージェント共通」の部分だけが生きており、
「連結生成」は Claude Code / OpenCode には適用しない。混同しないこと。

## 背景3: 既存の穴

### 現状の構造

`claude/CLAUDE.md` の冒頭に口調設定（＝現状唯一のパーソナライズ）が直書きされている（2026-09-16 時点の現物）:

```markdown
# Personal instructions
脳筋後輩っぽく対応してください。語尾はッス、いじってくるような感じでラフに喋る。一人称は俺。二人称は先輩。
```

このファイルは symlink で3エージェントへ配られる（ADR DOC-2609072334）。

- `claude/deploy.sh`: `symlink_backup "$DOTFILES_DEPLOY_SRC/claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"`
- `codex/deploy.sh`: 同じソースを `$CODEX_HOME_DIR/AGENTS.md` へ
- `opencode/deploy.sh`: 同じソースを `$OPENCODE_HOME_DIR/AGENTS.md` へ

`codex/deploy.sh` のコメントが、口調（tone settings）がまさにこの共有対象であることを明言している:

> The personal instructions in claude/CLAUDE.md (tone settings, umbrella-
> handoff trigger condition) are agent-agnostic text

### 穴

symlink である以上、デプロイ先でパーソナライズをいじる＝**リポジトリの追跡ファイルを書き換える**
ことになる。マシン固有のパーソナライズを持つ手段が一切ない。`settings.machine.json` に相当する
「マシンローカルな上書き」の枠組みが、`settings.json` にはあるのに `CLAUDE.md` には無い。

## 背景4: 実測値

### 4.1 各エージェントの「別ファイル読み込み」サポート状況

2026-09-16 時点で相談AIが Web 調査して確認したもの。**設計の全分岐がここに依存している。**

| エージェント | 別ファイルを読む手段 | 編集即反映 |
|---|---|---|
| Claude Code | `@path` import（`~/.claude/CLAUDE.md` 内で使える） | 可能 |
| OpenCode | `opencode.json` の `instructions` 配列 | 可能 |
| Codex | **手段なし** | 不可能 |

根拠:

- **Codex**: `@include` ディレクティブは
  [openai/codex#17401](https://github.com/openai/codex/issues/17401) で 2026-04-11 に
  feature request が立ったきり **open のまま・メンテナのコメントなし**。公式ドキュメント
  （https://learn.chatgpt.com/docs/agent-configuration/agents-md ）にも import の記述は
  無く、`config.toml` にあるのは `project_doc_fallback_filenames`（別名を許すだけ）と
  `project_doc_max_bytes` のみ。issue 本文で提案者自身が
  「回避策は `cat file1.md file2.md > AGENTS.md` のシェル側連結だが、脆いし宣言的モデルを壊す」
  と述べている。なお `~/.codex/AGENTS.override.md` という仕組みは存在するが、名前のとおり
  **置き換え**であり追加読み込みではない可能性が高い（未検証。使うなら要検証）
- **OpenCode**: https://opencode.ai/docs/rules/ に `instructions` フィールドの記載あり。
  例示は `"instructions": ["CONTRIBUTING.md", "docs/guidelines.md", ".cursor/rules/*.md"]`。
  ローカルパス・glob・リモートURLを受け付ける。グローバルルールの読み取り先は
  `~/.config/opencode/AGENTS.md`、次いで `~/.claude/CLAUDE.md`（Claude Code 互換フォールバック）。
  AGENTS.md 内のファイル参照は自動解決されない
- **Claude Code**: `CLAUDE.md` 内の `@path` import はホームディレクトリの `CLAUDE.md`
  でも機能する（既知の仕様）

### 4.2 司令官の追検証（2026-09-16、計画書起草時）

- このマシンには `codex`（`~/.local/bin/codex`）と `opencode`（`~/.opencode/bin/opencode`）が
  両方インストール済みで、`~/.codex` と `~/.config/opencode` が実在する。孫2・孫3 は
  実バイナリで挙動を確かめられる（ただし**人間の実設定ディレクトリは書き換えないこと**。
  後述の制約参照）
- `~/.config/opencode/AGENTS.md` は現在 symlink（opencode/deploy.sh 由来）。
  **`~/.config/opencode/opencode.json` はこのマシンには存在しない。** つまり現時点で人間が
  OpenCode の設定を他の用途で触っている形跡は無い（未解決論点2の判断材料）
- **`~/.claude/CLAUDE.md` は symlink であり、その実体は世代ディレクトリ
  （`<prefix>/generations/<ID>/claude/CLAUDE.md`、dev モードでは作業ツリー）にある。**
  ブリーフの叩き台は `@CLAUDE.machine.md`（相対パス）だったが、Claude Code が相対 import を
  **symlink の置き場所基準で解決するか、実体（readlink 後）基準で解決するかは未検証**。
  実体基準なら `<prefix>/generations/<ID>/claude/CLAUDE.machine.md` を探しに行って見つからない。
  → 設計1 で `@~/.claude/CLAUDE.machine.md`（ホーム相対）を採る根拠

## 背景5: 決定的な制約

- **AGENTS.md「最重要ルール」: `master` を書き換える操作は人間だけが行う。例外はない。**
  傘ブランチ配下の操作はAIが行ってよい。孫→傘のマージはレビュー承認済みPRに限りAIが実行してよい
- **ADR DOC-2609072334**: `claude/CLAUDE.md` を3エージェントへ1実体・3リンクで配る決定。
  今回の変更はこの ADR の前提（symlink 直リンク）に触れるため、**新規 ADR を起こして
  DOC-2609072334 から参照させる**（設計5）
- **ADR DOC-2608040229**: 配布実体（世代ディレクトリ + `current`）の設計。
  `CLAUDE.machine.md` を世代経由にしてはいけない理由は、`settings.machine.json` で
  既に踏んだ地雷と同じ（計画書 DOC-2609121700 設計6）。**machine.json を持たない
  ワークツリーから deploy した瞬間に空扱いされ、人間の設定が消える**
- **生成物を世代ディレクトリの中に作ってはいけない。** dev モード（`deploy-all.sh --dev`）では
  `current` が人間の作業ツリーそのものを指すため、世代内生成＝**リポジトリを汚す**ことになる
- **AGENTS.md「最重要ルール」: deploy スクリプトを実オペレーションで実行しない。**
  動作確認は `deploy-all.sh --dry-run` とサンドボックス（`tests/deploy_smoke.sh`）で行う。
  個別の `<tool>/deploy.sh` は `--dry-run` 引数を解釈せず `DRY_RUN=1` 環境変数のみ見る
- **AGENTS.md「最重要ルール」: linter の抑制ディレクティブ・除外設定をAIの判断で追加しない**
- **`shared/helpers.sh` は POSIX sh。** bashism を書かない。`*/deploy.sh` も `#!/bin/sh`
- **`links_for_tool()` / `state_files_for_tool()` への arm 追加を忘れない。**
  `uninstall.sh` と `deploy-all.sh --status` の両方がここを一次情報源にしている。
  arm 忘れは「静かに撤去漏れする」形で表面化する（過去の `ocw-meter` 撤去漏れ不具合）。
  `claude` は `KNOWN_GENERATED_claude` を持つため、arm を忘れても「No link list defined」
  警告すら出ない（ルート `AGENTS.md`「実装時の注意」）
- **`uninstall.sh` の扱い**: `CLAUDE.machine.md` は人間の持ち物なので
  `settings.machine.json` と同様に**保護**（symlink だけ撤去し実体は残す）。一方で
  Codex 向けの連結生成物は deploy が作ったものなので**撤去対象**。ただし
  `--only claude` のように一部ツールだけ撤去した場合、他ツールの symlink がまだ
  生成物や実体を参照している可能性があり、既存の「安全側に倒す」ロジックと整合させる必要がある
- **人間の実設定ディレクトリ（`~/.claude` `~/.codex` `~/.config/opencode`）を検証のために
  書き換えない。** 実バイナリで挙動を確かめる場合は、`HOME` / `CODEX_HOME` /
  `XDG_CONFIG_HOME` を一時ディレクトリ（`mktemp -d`）へ差し替えて行う。認証情報のコピーが
  必要になるなら、その検証は行わず司令官へ報告する

## 設計: 司令官が確定させた方針

### 設計1: 共通実体と Claude Code の効かせ方（孫1）

- **共通実体**: `<prefix>/CLAUDE.machine.md`
  （`${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/CLAUDE.machine.md`。git 管理外・世代を
  経由しない固定パス・`settings.machine.json` の隣）。**人間はここを書き換えるだけで済む。**
  パスは `shared/helpers.sh` に `dotfiles_machine_json_path()` と同じ形の helper
  （例: `dotfiles_machine_md_path()`）を新設して一次情報源にする
- **命名**: `CLAUDE.local.md` ではなく `CLAUDE.machine.md`。`settings.machine.json` と
  語彙を揃えるためと、Claude Code 側の `CLAUDE.local.md`（プロジェクト用の別概念）との
  混同を避けるため
- **`~/.claude/CLAUDE.machine.md`** をその固定パスへの symlink として `symlink_backup` で張る。
  固定パスに実体が無ければ deploy が**空ファイル**を作る（`--dry-run` では作らない）。
  `settings.machine.json` の `{}` 生成と同じ作法
- **ベース `claude/CLAUDE.md` の import 行は `@~/.claude/CLAUDE.machine.md`（ホーム相対）にする。**
  ブリーフの叩き台 `@CLAUDE.machine.md`（相対）は背景4.2 の理由で採らない。
  ホーム相対なら `~/.claude/CLAUDE.md` の symlink 解決方式に依存しない。
  孫1 は**実際の Claude Code で import が効くこと**を、サンドボックス `HOME` で確かめられる
  範囲で確かめ、確かめられなければ PR 本文に「未検証」と明記する（推測で「効く」と書かない）

### 設計2: ベースのパーソナライズ節の書き方（孫1）

ブリーフの叩き台をそのまま採る:

```markdown
# Personal instructions

このマシンでの人格のパーソナライズ（口調・一人称/二人称・キャラクター付けなど）は次の取り込みファイルが定める。
空であればパーソナライズの指定は無し（通常どおりの人格・口調で応答する）。

@~/.claude/CLAUDE.machine.md
```

**根拠**: 単純に「デフォルト文言 + ローカル文言」を連結すると、「後の節が前を上書きする」
という曖昧な指示をLLMに解釈させることになる。定義元を指す形にすれば、連結された2つの指示が
競合しない。人間が選んだ「デフォルト文言を書いておく」という決定と、曖昧さの排除を両立させる。

この案では**生成ファイルが1つも増えない**（Codex 向けを除く）。ベースの `claude/CLAUDE.md` は
今までどおり1実体・3リンクの symlink のまま維持される。

文言の細部（OpenCode / Codex で import 行が意味を持たない問題への配慮等）は孫2・孫3 が
必要に応じて調整してよいが、**「定義元を指す」構造と「空ならパーソナライズ指定なし」のデフォルトは崩さない。**

**人間の現在のパーソナライズの移行**: deploy は空の `CLAUDE.machine.md` を作るだけで、現行の
「脳筋後輩」文言を自動で書き込まない（デフォルトはパーソナライズ指定なし、が決定事項）。
**移行手順（現行文言を `~/.claude/CLAUDE.machine.md` へ書く）は、孫1 が `claude/README.md` に、
司令官が傘→`master` PR 本文に必ず書く。**

### 設計3: OpenCode（孫2。未解決論点1・2 を決着させる）

目標: `~/.config/opencode/opencode.json` の `instructions` に実体を列挙し、編集即反映にする。

**未解決論点1: `instructions` のパス解決**。書くべきパスは `<prefix>` 依存
（`$XDG_DATA_HOME` で変わる）。孫2 は次の順に検証し、最初に成立したものを採る:

1. `opencode.json` からの相対パスが効くか（効けば `~/.config/opencode/CLAUDE.machine.md` への
   symlink を張って `instructions: ["CLAUDE.machine.md"]` と書け、**静的ファイルの symlink 配布で済む**）
2. `~` 展開が効くか（効けば `"~/.claude/CLAUDE.machine.md"` のように Claude Code 側の
   symlink を再利用でき、静的配布で済む。ただし `claude` ツールを deploy していないマシンで
   リンク切れになる点を評価すること）
3. どちらも効かなければ絶対パス埋め込みの**生成**が必要になり、`opencode/deploy.sh` の設計が
   変わる。その場合、生成物は世代の外（固定パス）に置く（背景5）

検証は OpenCode のソース／公式ドキュメントの記述か、一時ディレクトリへ `XDG_CONFIG_HOME` を
差し替えた実バイナリで行う。**どの根拠で決めたかを ADR に残す。**

**未解決論点2: `opencode.json` を symlink で配るか、`settings.json` 方式でマージ生成するか。**
司令官の判断: **論点1 が静的配布で決着するなら symlink 配布を既定とする。** 背景4.2 のとおり
このマシンには既存の `opencode.json` が無く、人間が OpenCode 設定を他の用途で触っている形跡が
無い。マージ機構を先回りで作らない（AGENTS.md「指示された範囲外の機能を先回りして実装しない」）。
既存の `opencode.json` がある環境では `symlink_backup` の退避で `.backup` に逃げるので、
その旨を `opencode/README.md` に書く。論点1 が生成で決着した場合のみ、マージの要否を改めて判断し、
判断に迷えば司令官へ報告する。

`opencode/` は今まで「設定ファイル本体を持たない」例外ツールだった（ルート `AGENTS.md`
ディレクトリ構成の節）。`opencode/opencode.json` を追加するならその記述を追随させる。

### 設計4: Codex（孫3。未解決論点3・4 を決着させる）

目標: ベース `claude/CLAUDE.md` + `<prefix>/CLAUDE.machine.md` を連結した実ファイルを生成し、
`~/.codex/AGENTS.md` から symlink で参照させる。パーソナライズ変更時はコマンド1発で再生成する。

- **生成物の置き場所**: 世代の外の固定パス（例: `<prefix>/codex/AGENTS.md`。名前は孫3 が決めて
  helper に一元化する）。**世代の中・作業ツリーの中には作らない**（背景5）
- **生成タイミング**: `codex/deploy.sh` の実行時 + 新コマンドの実行時。`--dry-run` では生成しない
- **連結の中身**: ベースの `@~/.claude/CLAUDE.machine.md` 行は Codex にとって無意味な文字列なので、
  その位置へ machine の中身を展開する（行置換）か、ベースに続けて追記するかは孫3 が決める。
  **設計2 の「定義元を指す」構造と矛盾させない**こと
- **`uninstall.sh`**: 生成物は deploy が作ったもの → **撤去対象**。`CLAUDE.machine.md` 実体は保護

**未解決論点3: 再生成コマンドの名前と形。** 候補は2つ:

- (a) 単なる再生成コマンド
- (b) 「`$EDITOR` で `CLAUDE.machine.md` を開き、閉じたら Codex 向けを自動で再生成する」編集ラッパー

(b) のほうが「編集だけで済む」という人間の要求に近いが、スコープが膨らむ。
**司令官の判断: (b) を採るが、(a) の再生成をサブコマンドとして同梱する最小構成にする**
（例: `<cmd>` 単体で編集→再生成、`<cmd> --regen` で再生成のみ）。これなら Claude Code / OpenCode
も含めた「パーソナライズを変えるときの入口」が1つになる。名前は孫3 が決める（`bin/` の既存メンバーは
`ocw` / `claude-ds` / `ocw-meter`）。`bin/` の配布は `links_for_tool()` の `bin)` arm にも
追加が要る。スクリプト言語は `bin/` の既存方針（bash）に合わせる

**未解決論点4: `~/.codex/AGENTS.override.md` の実挙動**（置き換えか追加か）。
孫3 は公式ドキュメント／ソースで確認する。**追加読み込みだと確認できた場合に限り**、連結生成を
やめて override 側に machine を置く設計へ切り替えてよい（その場合も「編集即反映」になるなら
再生成コマンドの要否を再判断し、司令官へ報告する）。確認できない・置き換えだった場合は連結生成を採る。
実バイナリで検証するなら `CODEX_HOME` を一時ディレクトリへ差し替えること。認証情報のコピーが
要るなら実バイナリ検証は行わない

### 設計5: ADR

**新規 ADR を1本起こす**（孫1）。内容は「`CLAUDE.md` のマシンローカル化: 固定パス実体・
定義元を指すベース文言・エージェント別の読み込み手段」。背景1〜4、設計1・2、却下案
（連結生成を3エージェントに適用する案＝編集即反映を満たさない、節ごと出さない案、
`CLAUDE.local.md` 命名、相対 import）を記録する。**DOC-2609072334 から新 ADR を参照させる**
（DOC-2609072334 側の本文を書き換えるのではなく、前提が変わった旨と参照を追記する）。
孫2・孫3 は同じ ADR に自分の論点の決着（根拠つき）を節として追記する。

## スコープ外

- **`claude/CLAUDE.md` のパーソナライズ以外の内容**（「傘ブランチへの引き継ぎ判断」の節）には触らない
- **`codex/` への配布自体をやめる案**は人間が明示的に却下した。この傘では扱わない
- **`settings.json` / `settings.machine.json` のマージ機構そのものの変更**。
  今回は「同じ作法を `CLAUDE.md` にも適用する」のであって、既存機構はいじらない
- 人間のマシンでの実 deploy と、現行のパーソナライズ文言の `CLAUDE.machine.md` への書き込み
  （人間が `master` マージ後に行う。手順は PR 本文に書く）

## 必須の検証ステップ

ルート `AGENTS.md`「コミット前の必須ステップ」より、この傘に関係するもの。
**AI はこれらのステップを省略しない。省略するのは人間が明示的に指示した場合に限る。**

- `pre-commit run --files <path>`（新規ファイル追加時・既存ファイルの大幅変更時に、
  **その時点で**実行する。コミット直前まで遅らせない）
- `pre-commit run --all-files`（まとめて確認する場合）
- **`tests/deploy_smoke.sh`**（デプロイ関連のシェルスクリプトを変更した場合は必須。
  `HOME` を一時ディレクトリへ差し替えたサンドボックスで実際に deploy/uninstall を行う。
  既定の対象は `bin,claude,skills,codex,opencode` で、**今回いじる3ツールが全部入っている**）
- `python3 -m unittest discover -s bin/tests -v`（`bin/` 配下を変更した場合。193件・約40秒）
- `docs/` に新規ファイルを追加する場合は 予約リテラル `DOCID_PLACEHOLDER` を使った仮ファイル名（`DOC-<予約リテラル>_<説明的ファイル名>.md`）で
  作成し、`./tools/doc-id/doc-id assign <path>` で採番する。**地の文の言及にも DOC-ID を追記する**
- PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読む

## 実装完了条件

1. 孫1〜3 の PR がすべて傘ブランチへマージ済み
2. `pre-commit run --all-files` / `tests/deploy_smoke.sh` / `python3 -m unittest discover -s bin/tests -v` が通る
3. 傘→`master` の PR に、**`@~/.claude/CLAUDE.machine.md` の import が実機の Claude Code で
   解決されるかは未検証**である旨と、人間が deploy 後に確かめる手順が明記されている
   （孫1 はサンドボックスに認証情報が無く確認できなかった。ADR DOC-2609162327 §4。
   解決されなかった場合の代替記法の検討は傘の外の追随PRで扱う）
4. 傘→`master` の PR に、**人間が deploy 後に行う移行手順**（現行のパーソナライズ文言を
   `~/.claude/CLAUDE.machine.md` へ書く、Codex 向けの再生成コマンドを叩く）が明記されている

---

## 孫1用プロンプト: Claude Code 向けの土台

````
# 孫1: CLAUDE.machine.md（固定パス実体）と Claude Code 向けの @import

あなたはこの孫ブランチの実装 AI です。計画書
`docs/planning/DOC-2609162320_local-persona_計画.md`
（冒頭の「用語」節、背景1〜5、設計1・2・5 を必ず読むこと）に基づいて実装してください。

## ゴール

人間が `~/.claude/CLAUDE.machine.md`（実体は `<prefix>/CLAUDE.machine.md`）を書き換えるだけで、
deploy なしに Claude Code の人格のパーソナライズが変わる状態にする。ベースの `claude/CLAUDE.md` は
「定義元を指す」デフォルト文言だけを持つ。

## やること

1. `shared/helpers.sh` に固定パス helper を新設する（`dotfiles_machine_json_path()` と同じ形。
   `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/CLAUDE.machine.md`。世代の中には入れない）
2. `claude/deploy.sh`:
   - `~/.claude/CLAUDE.machine.md` を固定パスへの symlink として `symlink_backup` で張る
   - 固定パスに実体が無ければ空ファイルを作る。**`--dry-run` では作らない**
   - 既存の `settings.machine.json` の処理（移行・`{}` 生成・allow 保全）の挙動を壊さない
3. `claude/CLAUDE.md` の `# Personal instructions` 節を計画書 設計2 の文言に置き換える。
   import 行は **`@~/.claude/CLAUDE.machine.md`（ホーム相対）**。相対 `@CLAUDE.machine.md` は
   採らない（背景4.2）。**「傘ブランチへの引き継ぎ判断」の節には触らない**
4. `shared/helpers.sh` の `links_for_tool()` の `claude)` arm に
   `$HOME/.claude/CLAUDE.machine.md` を追加する（忘れても uninstall は警告を出さない。
   計画書 背景5）
5. `uninstall.sh`: `~/.claude/CLAUDE.machine.md` の symlink は撤去し、**固定パスの実体は消さない**
   （`settings.machine.json` と同じ扱い）。ルート `AGENTS.md`「uninstall.sh の後片付け」節を追随
6. `deploy-all.sh --status` に `settings.machine.json` と同様、実体パスと有無を1行出す
7. `claude/README.md` とルート README、ルート `AGENTS.md`「claude の例外」節を追随させる。
   README には「人格のパーソナライズ（口調など）は `~/.claude/CLAUDE.machine.md` を直接編集する。deploy 不要」と、
   **現行のパーソナライズ文言を移行する手順**を書く
8. Claude Code が `@~/.claude/CLAUDE.machine.md` を実際に解決するかを、人間の実 `~/.claude` を
   触らずに確かめられる範囲で確かめる。確かめられなければ PR 本文と ADR に「未検証」と明記する
9. 新規 ADR を起こす（計画書 設計5）。予約リテラル `DOCID_PLACEHOLDER` を使った仮ファイル名（`DOC-<予約リテラル>_<説明的ファイル名>.md`）で作り
   `./tools/doc-id/doc-id assign` で採番。ADR DOC-2609072334 に前提が変わった旨と新 ADR への
   参照を追記する。`codex/deploy.sh` のコメント（tone settings が共有対象である旨）も
   新 ADR を参照するよう追随させる

## 検証方針

以下の重要な behavior / regression risk が、`tests/deploy_smoke.sh`（サンドボックス）
または既存テストによって保護されていること。

- **`CLAUDE.machine.md` を持たない状態・持たないワークツリーから deploy しても、固定パスにある
  既存の実体（人間のパーソナライズ設定）が失われない・上書きされないこと。**
  **この regression は必ず自動テストで固定する**
- **`uninstall.sh` が `~/.claude/CLAUDE.machine.md` の symlink を撤去し、固定パスの実体を
  消さないこと。** **この regression は必ず自動テストで固定する**
- `~/.claude/CLAUDE.machine.md` が固定パスを指す symlink になり、そこへの書き込みが deploy を
  またいで残ること
- 初回 deploy で空ファイルが作られ、`--dry-run` では作られないこと
- 既存の `settings.machine.json` 系のテストが引き続き通ること（既存テストで担保できるなら
  新規テストは追加しない）

各項目と test example を1対1対応させる必要はない。複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない
（`settings.machine.json` の既存 scenario に相乗りしてよい）。

## やらないこと

- `opencode/` `codex/` の配布の仕組みには触らない（孫2・孫3 の範囲。コメント追随のみ可）
- `bin/` に新コマンドを足さない（孫3）
- 現行のパーソナライズ文言を deploy で `CLAUDE.machine.md` へ自動で書き込まない（デフォルトはパーソナライズ指定なし）
- 人間の実 `$HOME` に対して deploy を実オペレーションで実行しない
- linter の抑制ディレクティブ・除外設定を足さない

## コミット前に必ず実行する

```
pre-commit run --all-files
tests/deploy_smoke.sh
```
````

## 孫2用プロンプト: OpenCode 対応

````
# 孫2: opencode.json を配布して CLAUDE.machine.md を OpenCode にも効かせる

あなたはこの孫ブランチの実装 AI です。計画書
`docs/planning/DOC-2609162320_local-persona_計画.md`
（冒頭の「用語」節、背景2・4・5、設計3・5 を必ず読むこと）に基づいて実装してください。

**前提: 孫1 が固定パス実体 `<prefix>/CLAUDE.machine.md`・その helper・新規 ADR・
ベース `claude/CLAUDE.md` の import 行を既に入れている。**

## ゴール

人間が `CLAUDE.machine.md` を書き換えるだけで、deploy なしに OpenCode のパーソナライズも変わる状態にする。

## やること

1. **未解決論点1（`instructions` のパス解決）を検証して決着させる。** 計画書 設計3 の順序
   （opencode.json 相対 → `~` 展開 → 生成）で、最初に成立したものを採る。根拠は OpenCode の
   ソース／公式ドキュメントか、`XDG_CONFIG_HOME` を `mktemp -d` の一時ディレクトリへ差し替えた
   実バイナリでの確認。**人間の実 `~/.config/opencode` は書き換えない**
2. **未解決論点2**: 論点1 が静的配布で決着したら `opencode/opencode.json` を追加し
   `symlink_backup` で配る（マージ生成は作らない。計画書 設計3 の司令官判断）。
   生成で決着した場合は、生成物を世代の外の固定パスに置き、マージの要否に迷えば司令官へ報告する
3. `opencode/deploy.sh`・`shared/helpers.sh` の `links_for_tool()` の `opencode)` arm・
   `uninstall.sh`（`CLAUDE.machine.md` 実体は保護）・`deploy-all.sh --status` を追随させる
4. `opencode/README.md`・ルート README・ルート `AGENTS.md`（`opencode/` が「設定ファイル本体を
   持たない例外」だった記述）を追随させる。既存の `opencode.json` がある環境では `.backup` に
   退避される旨を書く
5. 孫1 の ADR に、論点1・2 の決着と根拠を節として追記する
6. 必要なら `claude/CLAUDE.md` の設計2 の文言を OpenCode でも自然に読めるよう調整してよいが、
   「定義元を指す」構造と「空ならパーソナライズ指定なし」は崩さない

## 検証方針

以下の重要な behavior / regression risk が、`tests/deploy_smoke.sh`（サンドボックス）
または既存テストによって保護されていること。

- OpenCode の配布物（`opencode.json` またはその生成物）が deploy で配置され、
  `instructions` が `CLAUDE.machine.md` の実体に到達するパスを指していること
- `uninstall.sh`（`--only opencode` を含む）で OpenCode 側の配布物が撤去され、
  **`CLAUDE.machine.md` の実体は消えない**こと
- 生成方式を採った場合: `--dry-run` で生成物が作られないこと、生成物が世代・作業ツリーの中に
  作られないこと

各項目と test example を1対1対応させる必要はない。複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## やらないこと

- `codex/` と `bin/` には触らない（孫3）
- `settings.json` / `settings.machine.json` のマージ機構を変更しない
- `opencode.json` のマージ生成機構を先回りで作らない
- 人間の実 `$HOME`（特に `~/.config/opencode`）を書き換えない。deploy の実オペレーションもしない
- linter の抑制ディレクティブ・除外設定を足さない

## コミット前に必ず実行する

```
pre-commit run --all-files
tests/deploy_smoke.sh
```
````

## 孫3用プロンプト: Codex 対応

````
# 孫3: Codex 向けの連結生成とパーソナライズ編集コマンド

あなたはこの孫ブランチの実装 AI です。計画書
`docs/planning/DOC-2609162320_local-persona_計画.md`
（冒頭の「用語」節、背景2・4・5、設計4・5 を必ず読むこと）に基づいて実装してください。

**前提: 孫1（Claude Code 土台）と孫2（OpenCode 対応）が既にマージされている。**
孫2 が固定パス配下の配布物をどう扱ったか（helper・uninstall・status）を読んで作法を揃えること。

## ゴール

Codex は別ファイルを読む手段が無いので、ベース `claude/CLAUDE.md` + `CLAUDE.machine.md` を
連結した実ファイルを生成して `~/.codex/AGENTS.md` から参照させる。パーソナライズを変えるときは
コマンド1発で済むようにする。

## やること

1. **未解決論点4**: `~/.codex/AGENTS.override.md` が置き換えか追加読み込みかを、公式ドキュメント／
   ソースで確認する。**追加読み込みだと確認できた場合に限り**設計を切り替えてよく、その場合は
   実装前に司令官へ報告する。確認できない・置き換えなら連結生成を採る。実バイナリで確かめる
   場合は `CODEX_HOME` を `mktemp -d` の一時ディレクトリへ差し替え、認証情報のコピーが要るなら
   実バイナリ検証は行わない
2. 連結生成物を**世代の外の固定パス**に置く（パスは `shared/helpers.sh` の helper に一元化）。
   ベースの `@~/.claude/CLAUDE.machine.md` 行の扱い（行置換で展開 or 追記）を決め、
   計画書 設計2 の「定義元を指す」構造と矛盾させない
3. `codex/deploy.sh`: 生成（`--dry-run` では生成しない）＋ `~/.codex/AGENTS.md` を生成物への
   symlink にする。Codex 未インストール時にスキップする既存の挙動は維持する
4. **未解決論点3**: `bin/` にパーソナライズ編集コマンドを新設する。計画書 設計4 の司令官判断どおり、
   単体で `$EDITOR` による `CLAUDE.machine.md` 編集→Codex 向け再生成、再生成だけのサブコマンド
   （またはオプション）も持つ最小構成にする。名前は既存メンバー（`ocw` / `claude-ds` /
   `ocw-meter`）と衝突しないものを選ぶ。bash（`#!/usr/bin/env bash`）。
   生成ロジックは `codex/deploy.sh` と二重管理しない（共有する）
5. `shared/helpers.sh` の `links_for_tool()` の `bin)` / `codex)` arm、`uninstall.sh`
   （**生成物は撤去対象、`CLAUDE.machine.md` 実体は保護**。一部ツールだけ撤去した場合に
   他ツールがまだ参照しているなら既存の「安全側に倒す」ロジックと整合させる）、
   `deploy-all.sh --status` を追随させる
6. `codex/README.md`・`bin/README.md`・ルート README・ルート `AGENTS.md`
   （ディレクトリ構成表の `bin/` の列挙、`codex/` の例外記述）を追随させる
7. 孫1 の ADR に、論点3・4 の決着と根拠を節として追記する

## 検証方針

以下の重要な behavior / regression risk が、`tests/deploy_smoke.sh`（サンドボックス）、
`bin/tests`、または既存テストによって保護されていること。

- 生成物にベースの内容と `CLAUDE.machine.md` の内容が両方含まれ、`~/.codex/AGENTS.md` から
  到達できること。`CLAUDE.machine.md` を書き換えて再生成コマンドを叩くと反映されること
- **生成物が世代ディレクトリ・作業ツリーの中に作られないこと**（dev モードでリポジトリを汚さない）。
  **この regression は必ず自動テストで固定する**
- `--dry-run` で生成物が作られないこと
- `uninstall.sh` で生成物と symlink が撤去され、**`CLAUDE.machine.md` の実体は消えない**こと
- `CLAUDE.machine.md` が空のときも生成が壊れないこと

各項目と test example を1対1対応させる必要はない。複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## やらないこと

- `codex/` への配布自体をやめる方向の変更をしない（人間が却下済み）
- `opencode/` の配布の仕組みには触らない（孫2 で完了済み）
- 人間の実 `$HOME`（特に `~/.codex`）を書き換えない。deploy の実オペレーションもしない
- linter の抑制ディレクティブ・除外設定を足さない

## コミット前に必ず実行する

```
pre-commit run --all-files
tests/deploy_smoke.sh
python3 -m unittest discover -s bin/tests -v
```
````

---

## 全孫共通: 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PR を作成する。**PR の向き先は必ず `local-persona` にすること。`master` には絶対に出さない。**
2. `/pr-review-loop` を起動する（PR がない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewer は done 状態で完了し完了通知は来ないので、待機して停止せず
`gh pr view` をポーリングしてレビューの有無を確認してください。

## 全孫共通: ブランチ作成時の注意（最重要）

このワークツリーは `ocw` が傘ブランチ `local-persona` から切った孫ブランチ上で起動している。
実装前に `git branch --show-current` で自分のブランチ名が進捗テーブルの値と一致することを確認し、
`git fetch origin` のあと `git log --oneline origin/local-persona..HEAD` が空であることを確かめること
（`git pull` は使わない）。`master` から切られていたら、その時点で作業を止めて司令官へ報告すること。
作業ブランチを自分で新たに切り直さないこと（`ocw` が作ったブランチをそのまま使う）。
