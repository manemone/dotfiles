# ADR: CLAUDE.md の人格のパーソナライズをマシンローカル化する（固定パス実体 + 定義元を指すベース文言）

## ステータス

確定（2026-09-16）

## 1. 背景

`claude/CLAUDE.md`（配布物）の冒頭に人格のパーソナライズ（口調・一人称/二人称・
キャラクター付けなど）が直書きされている:

```markdown
# Personal instructions
脳筋後輩っぽく対応してください。語尾はッス、いじってくるような感じでラフに喋る。一人称は俺。二人称は先輩。
```

このファイルは symlink で Claude Code / Codex / OpenCode の3エージェントへ配られる
（ADR [DOC-2609072334](DOC-2609072334_codex-opencode-global-instructions-distribution.md)）。
symlink である以上、デプロイ先でパーソナライズをいじる＝リポジトリの追跡ファイルを
書き換えることになり、**マシン固有のパーソナライズを持つ手段が一切無かった。**
`settings.json` には `settings.machine.json` という「世代を経由しない固定パスの
マシンローカル上書き」の枠組みがあるのに、`CLAUDE.md` には無かった。

人間の確定事項（傘 `local-persona` 計画書
[DOC-2609162320](../planning/DOC-2609162320_local-persona_計画.md) 背景1・2）:

- パーソナライズは Claude Code / Codex / OpenCode の3エージェント全部で効かせる
- デフォルト（ローカル設定が空）のとき、ベース側にデフォルト文言を書いておく
  （「パーソナライズの節ごと出さない」は却下）
- **編集即反映が最優先要件である。** デプロイを挟む方式は Codex を除いて認められない
  （「連結してデプロイ時に生成する」という当初案は、この要求が出た時点で
  Claude Code / OpenCode には適用しない方針へ縮小された）

**用語について**: 相談の時点では人間もブリーフも「口調」と呼んでいたが、計画書起草後に
「扱う対象は口調に限らない人格のパーソナライズである」と人間が方針を示した（計画書
DOC-2609162320「用語」節）。現行の `claude/CLAUDE.md` の文言がたまたま口調中心なだけで、
本 ADR は仕組みを「このマシンでの人格をマシンローカルに差し替える枠組み」として設計・
説明する。「口調設定」は仕組みの名前としては使わず、具体例として添えるに留める。

本 ADR は孫1（Claude Code 向けの土台）が確定させた設計を記録する。孫2（OpenCode）・
孫3（Codex）は同じ ADR に自分の担当分の決着を節として追記する。

## 2. 決定

### 2.1 共通実体: 世代を経由しない固定パス

`<prefix>/CLAUDE.machine.md`
（`${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/CLAUDE.machine.md`。`current` や
`settings.machine.json` と同じ階層。git 管理外・世代を経由しない固定パス）を
マシンローカルな人格のパーソナライズの実体とする。パスは `shared/helpers.sh` の
`dotfiles_machine_md_path()`（`dotfiles_machine_json_path()` と同じ形）が一次情報源。

理由は `settings.machine.json` が固定パス化された理由（計画書
[DOC-2609121700](../planning/DOC-2609121700_autopilot-permissions_計画.md) 設計6）と
全く同じ: git 非追跡のマシン固有ファイルを世代・ワークツリー相対に置くと、
その実体を持たないワークツリー（傘・孫など）から deploy した瞬間に「実体が無い」
扱いになり、人間の設定が消える。

`settings.machine.json` と異なり、`CLAUDE.machine.md` には移行元となる
「旧・ソースツリー相対パス」が存在しない（この設計で新規に導入する実体のため）。
そのため `claude/deploy.sh` に移行ロジックは不要。

**命名は `CLAUDE.local.md` ではなく `CLAUDE.machine.md`。** `settings.machine.json` と
語彙を揃えるためと、Claude Code 側が別概念として持つ `CLAUDE.local.md`
（プロジェクト用のローカル指示ファイル）との混同を避けるため。

### 2.2 `~/.claude/CLAUDE.machine.md`: 固定パスへの symlink

`claude/deploy.sh` が `symlink_backup` で `~/.claude/CLAUDE.machine.md` を固定パスへ
symlink する。固定パスに実体が無ければ **空ファイル** を作る（`settings.machine.json` の
空 `{}` 生成と同じ作法。**`--dry-run` では作らない**）。

`uninstall.sh` 側は追加の分岐が要らない。`shared/helpers.sh` の `links_for_tool()` の
`claude)` arm に `$HOME/.claude/CLAUDE.machine.md` を追加するだけで、既存の
「`_links` を1本ずつ `symlink_restore` する」ループがそのまま **symlink だけを撤去し
固定パスの実体は残す** という `settings.machine.json` と同じ保護を実現する
（`CLAUDE.machine.md` は `settings.json` と違って生成・マージされたファイルではなく
常に単純な symlink なので、`settings.machine.json` のように `KNOWN_GENERATED_claude` へ
個別のバックアップ・復元ロジックを書く必要が無い）。

### 2.3 ベース `claude/CLAUDE.md`: 「定義元を指す」文言

```markdown
# Personal instructions

このマシンでの人格のパーソナライズ（口調・一人称/二人称・キャラクター付けなど）は次の取り込みファイルが定める。
空であればパーソナライズの指定は無し（通常どおりの人格・口調で応答する）。

@~/.claude/CLAUDE.machine.md
```

**単純に「デフォルト文言 + ローカル文言」を連結する案は採らない。** 連結すると
「後の節が前を上書きする」という曖昧な指示を LLM に解釈させることになる。定義元を
指す形にすれば、連結された2つの指示が競合しない。人間が選んだ「デフォルト文言を
書いておく」という決定と、曖昧さの排除を両立させる。

import 行は **`@~/.claude/CLAUDE.machine.md`（ホーム相対）** を採り、叩き台にあった
相対パス `@CLAUDE.machine.md` は採らない。理由: `~/.claude/CLAUDE.md` は symlink であり、
その実体は世代ディレクトリ（`<prefix>/generations/<ID>/claude/CLAUDE.md`、dev モードでは
作業ツリー）にある。Claude Code が相対 import を「symlink の置き場所」基準で解決するか
「実体（readlink 後）」基準で解決するかは未検証であり、後者なら
`<prefix>/generations/<ID>/claude/CLAUDE.machine.md` を探しに行って見つからない。
ホーム相対 `@~/.claude/CLAUDE.machine.md` なら、この symlink 解決方式の違いに依存しない。

この案では **生成ファイルが1つも増えない**（Codex 向けを除く）。ベースの
`claude/CLAUDE.md` は今までどおり1実体・3リンクの symlink のまま維持される
（ADR [DOC-2609072334](DOC-2609072334_codex-opencode-global-instructions-distribution.md)
の前提は崩れない。同 ADR に本 ADR への参照を追記した）。

**「傘ブランチへの引き継ぎ判断」節は変更しない。** 今回のスコープはパーソナライズ節のみ。

### 2.4 人間の現在のパーソナライズの移行は自動化しない

deploy は空の `CLAUDE.machine.md` を作るだけで、現行の「脳筋後輩」文言を自動で
書き込まない（「デフォルトはパーソナライズ指定なし」という決定事項どおり）。移行手順
（現行文言を `~/.claude/CLAUDE.machine.md` へ書く）は `claude/README.md` §3.1・§4.9 と、
傘→`master` PR 本文に記載する。

## 3. 却下した案

### 3.1 連結生成を3エージェントに適用する

Claude Code / OpenCode にも Codex と同じ「ベース + machine を連結した実ファイルを
deploy 時に生成する」方式を適用する案。**「デプロイせずにパーソナライズ部分を
変えるだけで済むようにしたい」という人間の追加要求（編集即反映）を満たさない**
ため却下。Codex だけは `@include` 相当の手段が無い（背景4.1）ため、やむを得ず
連結生成を採る。

### 3.2 デフォルトが空のときパーソナライズの節ごと出さない

人間が明示的に却下。「何も指定していない状態」を明示する文言（2.3）を残すほうを選んだ。

### 3.3 `CLAUDE.local.md` という命名

Claude Code 側に既に別概念として存在する `CLAUDE.local.md`（プロジェクトの
ローカル指示ファイル）と混同するため却下。`settings.machine.json` と語彙を揃えた
`CLAUDE.machine.md` を採用。

### 3.4 相対 import（`@CLAUDE.machine.md`）

2.3 で述べたとおり、`~/.claude/CLAUDE.md` が symlink であることに起因する解決方式の
不確実性（symlink 置き場所基準 vs 実体基準）を理由に却下。ホーム相対パスを採用した。

## 4. 未検証事項

**Claude Code が実際に `@~/.claude/CLAUDE.machine.md` を解決して読み込むかどうかは
実機で確認できていない。** サンドボックス化した `HOME` で `claude` CLI を起動して
確認を試みたが、サンドボックスには認証情報が無く（`Not logged in · Please run
/login`）、対話セッションを要する検証（`/doctor` や実際の応答生成）まで到達できな
かった。人間の実 `~/.claude` の認証情報をサンドボックスへコピーする手段は計画書
（背景5「人間の実設定ディレクトリを検証のために書き換えない」）で明示的に禁止されて
いるため、この経路での検証は行っていない。

根拠として次は確認済み: (1) 計画書 DOC-2609162320 背景4.1 に「`CLAUDE.md` 内の `@path`
import はホームディレクトリの `CLAUDE.md` でも機能する（既知の仕様）」という記載が
あり、司令官による事前調査に基づく。(2) インストール済み Claude Code バイナリの文字列
に "Not yet auto-imported; append it to ~/.claude/CLAUDE.md (your user-level memory
file)" という記述があり、ユーザーレベル `CLAUDE.md` が import の仕組みを持つ設定ファイル
として扱われていることを示唆する。

**したがって「効く」と断定はしない。** 人間が実マシンで deploy した後、
`~/.claude/CLAUDE.machine.md` を編集して Claude Code を再起動し、パーソナライズが
実際に変わるかを確認することを推奨する。効かないことが判明した場合、設計2.3
（定義元を指す構造）自体は崩さず、import 記法だけを見直すことになる。

## 5. 孫2（OpenCode）の決着

### 5.1 未解決論点1: `instructions` のパス解決

計画書 DOC-2609162320 設計3 が挙げた3案のうち、**opencode.json からの相対パスは成立しない**
ことをソースコードで確認した（`opencode/opencode.json` — この dotfiles 自身が開発時に使う
プロジェクト設定 — から `git clone` した [sst/opencode](https://github.com/sst/opencode) の
`packages/opencode/src/session/instruction.ts` の `systemPaths()` を読んだ。参照した clone は
`package.json` の `version: 1.18.31`、インストール済みバイナリは `opencode --version` で
`1.18.23` — ごく近いバージョンで、この経路のロジックが変わっている可能性は低い）。

`config.instructions` の各エントリは次のように解決される（`systemPaths()` 135〜150行目）:

```js
const instruction = raw.startsWith("~/") ? path.join(global.home, raw.slice(2)) : raw
const matches = yield* (
  path.isAbsolute(instruction)
    ? fs.glob(path.basename(instruction), { cwd: path.dirname(instruction), absolute: true, include: "file" })
    : relative(instruction)  // = fs.globUp(instruction, ctx.directory, ctx.worktree)
)
```

- **`~/` で始まるエントリは `$HOME` からの展開で絶対パスになる。** 展開後は
  `fs.glob(basename, { cwd: dirname })` で解決される — **成立する**
- **`~/` で始まらない相対パスは `globUp(instruction, ctx.directory, ctx.worktree)` で
  解決される。** `ctx.directory` は「今動いている OpenCode セッションのプロジェクト
  ディレクトリ（cwd）」であり、**グローバル `opencode.json` 自身が置かれているディレクトリ
  （`${XDG_CONFIG_HOME:-$HOME/.config}/opencode/`）とは無関係。** 実機の
  `opencode debug config`（`$XDG_CONFIG_HOME` を `mktemp -d` の一時ディレクトリへ差し替えて
  実行）でも、`instructions: ["CLAUDE.machine.md"]` は raw な文字列として返るのみで
  グローバル config 自身のディレクトリを基準にした解決は行われないことを確認した
  （本 dotfiles リポジトリ自身の `opencode.json` の `"AGENTS.md"` のようなプロジェクト内
  相対パスは、そのプロジェクトの cwd で動いているときだけ意図通りに解決される —
  グローバル config の相対パスとして使う用途とは別物）。
  **→ 未成立。計画書の案1は採らない**

**結論: 案2（`~/` 展開）を採用する。**

### 5.2 未解決論点1（続き）: `~/` の参照先 — `~/.claude/CLAUDE.machine.md` を再利用する

計画書は案2として「Claude Code 側の symlink（`~/.claude/CLAUDE.machine.md`）を再利用する」
案と「OpenCode 自身の配下に別途 symlink を張る」案を両にらみで挙げていたが、**後者は
`$XDG_CONFIG_HOME` のカスタマイズ耐性が無いため採らない。**

`~/` 展開は `global.home`（= `$HOME`）からの展開であり、**`$XDG_CONFIG_HOME` からの展開では
ない。** もし `opencode/opencode.json` の `instructions` に
`"~/.config/opencode/CLAUDE.machine.md"` のような「OpenCode 自身のホームが既定値
（`$HOME/.config/opencode`）である前提」の決め打ちパスを書き、かつ OpenCode 自身の symlink
先もその決め打ちパスに作るとしても、`$XDG_CONFIG_HOME` を変更しているマシンでは
`skill_agent_home opencode`（実際の配布先）と `~/.config/opencode`（instructions に書いた
決め打ちパス）が一致しなくなり、**instructions のエントリだけが静かに解決しなくなる**
（symlink 自体は正しい場所に作られるので気づきにくい regression になる）。

`~/.claude` は Claude Code の固定パス（`skill_agent_home claude` は常に `$HOME/.claude`。
`$XDG_CONFIG_HOME` に依存しない — ADR DOC-2608272128 の分類でも claude だけが特別扱いされて
いる）であり、この問題が起こらない。**そのため `opencode/opencode.json` は
`~/.claude/CLAUDE.machine.md`（claude/deploy.sh が既に固定パス実体へ symlink 済みのもの）を
直接指す。** OpenCode 自身の配下に別の symlink を新設しない（作らない分、
`opencode/deploy.sh` に固定パス実体の空ファイル生成ロジックを複製する必要も無くなる）。

**トレードオフ（計画書が評価を求めていた点）**: `--only opencode` のように `claude` を
一度もデプロイしていないマシンでは `~/.claude/CLAUDE.machine.md` が存在しない。この場合
`fs.glob` はマッチ無しを返し（`systemPaths()` の `.pipe(Effect.catch(() => Effect.succeed([])))`
で例外も握り潰される）、そのエントリはただ無視される — エラーにはならず、
`CLAUDE.machine.md` が空のときと同じ「パーソナライズ指定なし」に自然劣化する。
`deploy-all.sh`（引数無し）は常に全ツールを対象にするため、通常の使い方でこの状態には
ならない。受容できるトレードオフと判断した。

### 5.3 未解決論点2: `opencode.json` の配布方式

論点1が静的配布（symlink）で決着したため、計画書の司令官判断どおり
**`opencode/opencode.json`（新規トラッキングファイル）を `symlink_backup` で配る。**
マージ生成機構は作らない。実測（計画書 DOC-2609162320 背景4.2 時点）でこのマシンに
`opencode.json` は存在しなかった（`opencode.jsonc` という別拡張子のファイルはあったが、
これは人間の実設定であり検証のために読んでいない — 計画書背景5「人間の実設定
ディレクトリを検証のために書き換えない」に準拠し、`cat` の実行はユーザーの承認が
下りなかったため試みを止めた）。既存の `opencode.json` がある環境では `symlink_backup` の
退避で `.backup` に逃がされる。

### 5.4 変更点まとめ

- 新規トラッキングファイル `opencode/opencode.json`:
  ```json
  {
    "$schema": "https://opencode.ai/config.json",
    "instructions": ["~/.claude/CLAUDE.machine.md"]
  }
  ```
- `opencode/deploy.sh` が `$OPENCODE_HOME_DIR/opencode.json` へ `symlink_backup` する
  （OpenCode 未導入マシンでは既存の早期 return によりスキップされる）
- `shared/helpers.sh` の `links_for_tool()` `opencode)` arm に
  `$(skill_agent_home opencode)/opencode.json` を追加

## 6. 孫3（Codex）の決着

（孫3のPRで追記）
