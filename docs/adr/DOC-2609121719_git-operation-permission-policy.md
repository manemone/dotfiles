# ADR: git 操作の許可ポリシー — 保護ブランチへの破壊的操作だけを人間に残す

## ステータス

確定（2026-09-12）

## 1. 背景

計画書 `docs/planning/DOC-2609121700_autopilot-permissions_計画.md`（傘
`autopilot-permissions`）が確定させた唯一の線引きは次のとおり。

> **`main` / `master` へのマージは人間がやる。それ以外は AI に任せる。**

傘ブランチ方式（`umbrella-orchestrator`）で無人運転しようとすると、孫→傘のマージ・
傘への上流取り込み・孫の rebase + force push といった、傘の内側で完結する操作の
たびに承認ダイアログが出て止まる。一方で `~/.claude/settings.json` の `permissions.ask`
にはもともと `Bash(git push *--force*)` 等が広く登録されており、これは
`--force-with-lease` にも一致するため、`permissions.allow` をいくら足しても
`ask` が勝ち（優先順位は deny > ask > allow）、パターンだけでは「main/master への
force push だけ止め、孫ブランチへの force-with-lease は通す」という区別を表現できない。

## 2. なぜパターンマッチでは足りないか

実際にコマンドを叩いて確認した結果、`permissions` のパターンマッチだけでは
この線引きを機械的に担保できないことが分かった。

1. **`gh pr merge <PR番号>` のコマンドラインに base ブランチが現れない。**
   base は PR 側の属性であり、`gh pr view <N> --json baseRefName` を別途叩かない
   限り、コマンド文字列だけからは「この PR のマージ先が main か傘ブランチか」を
   判別できない。実測: `gh pr merge 123 --squash` という文字列のどこにも
   base 情報は含まれない。
2. **`git push --force-with-lease` は refspec を省略できる。** 省略時の対象は
   「現在のブランチ」であり、これもコマンドラインには現れない。
   `git push --force-with-lease` だけでは、どのブランチへの force push なのか
   コマンド文字列単体からは分からず、実行時に `git branch --show-current` 相当を
   引く必要がある。
3. **`Bash(git push *--force*)` は `--force-with-lease` にも一致してしまう。**
   `permissions.allow` に `--force-with-lease` 用のパターンを足しても、
   `ask` パターンが先に一致する（deny > ask > allow）ため、「lease 付きだけ許す」を
   `permissions` の文字列パターンだけで表現できない。実機の
   `~/.claude/settings.json` には `Bash(git merge --ff-only:*)` /
   `Bash(git merge --ff-only *)` という `allow` エントリが積まれていたが、
   `Bash(git merge *)` という広い `ask` パターンに food われて一度も効いていない
   痕跡が残っていた（計画書 背景3-A）。

これらはいずれも「コマンドライン文字列だけでは判定に必要な情報（PR の base、
現在のブランチ）が手に入らない」という構造的な限界であり、`permissions.ask` /
`permissions.allow` のパターンをどれだけ工夫しても解決できない。

## 3. 決定

**保護ブランチ（`main` と `master`）への破壊的操作（`gh pr merge` によるマージ・
`git push` の force 系・`git merge`）だけを人間に残し、それ以外の git 操作は AI に
許す。担保は PreToolUse フック（`claude/hooks/git-guard.sh`）で行う。**

### 3.1 判定表

| 対象コマンド | 判定 |
|---|---|
| `gh pr merge`（PR 番号 / URL / 省略＝現ブランチ） | `gh pr view --json baseRefName` で base を解決し、保護ブランチなら **deny**、それ以外は **allow** |
| `git push` に `--force` / `--force-with-lease` / `-f` / `+<refspec>` が付く | 対象ブランチを解決し、保護ブランチなら **deny**。それ以外は `--force-with-lease` を **allow**、裸の `--force` / `-f` は **ask** |
| `git merge`（マージ先＝現在のブランチ） | 現在のブランチが保護ブランチなら **deny**、それ以外は **allow** |
| 上記以外 | 何も言わない（既存の `permissions` に委ねる） |

- 保護ブランチの定義は `claude/hooks/git-guard.sh` 内の1箇所（`main` と `master`）に
  集約する。
- **判定できなかったら `ask` に倒す（fail-safe）。** PR 番号が解決できない・`gh` が
  失敗した・現在のブランチが取れない・`&&` / `;` / `|` で複数コマンドが連なって
  いて対象を一意に特定できない・`git push` に値を取りうる未知のオプション
  （`-o` / `--push-option` 等）が含まれ安全に対象ブランチを解決できない・
  `git` / `gh` の前にグローバルオプション（`-C <dir>` / `--repo <owner/repo>` 等）が
  挟まりサブコマンドの位置を一意に特定できない、のいずれも `ask`。
  **`allow` に倒すことは絶対にしない。**
- python3 が見つからない環境では、JSON をパースする前に固定の `ask` 応答を返す
  （フックが判定不能なまま黙って通すことを避けるため）。
- **この判定表はフック単体の判定であり、最終的にユーザーへ確認が出るかどうかは
  `permissions.ask` にも一致しないかどうかに依存する（§3.2/§3.3 参照）。**
  `--force-with-lease` を摩擦なく通すには、フックが `allow` を返すだけでなく
  `permissions.ask` 側にも一致しないよう `claude/settings.json` を設計する必要がある
  （§3.3「`git push --force-with-lease` を摩擦なく通すための具体策」）。

### 3.2 PreToolUse フックの入出力契約（一次情報での確認結果）

サブエージェント（`claude-code-guide`）経由で Claude Code 公式ドキュメント
（Hooks Guide / Hooks Reference: `https://code.claude.com/docs/en/hooks.md` ほか）を
2026-09-12 に確認した。確認時点のドキュメントは comma 区切り matcher をサポートする
バージョン（Claude Code v2.1.191 以降）向けに更新されたものだった。

- **stdin の JSON**: `hook_event_name: "PreToolUse"`、`tool_name`（Bash なら
  `"Bash"`）、`tool_input.command` にコマンド文字列、`cwd` に実行時のカレント
  ディレクトリが入る。
- **判定結果**: stdout に
  `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"|"deny"|"ask", "permissionDecisionReason": "..."}}`
  という JSON を書き、exit 0 する。`permissionDecision` と
  `permissionDecisionReason` は必ず `hookSpecificOutput` の直下に置く
  （トップレベルに置くと無視される）。
- **終了コード**: exit 0 で stdout が空、または解釈できない場合は「意見なし」
  として通常の permission flow に委ねられる。exit 2 は stderr の内容を
  Claude へのフィードバックとしてツール呼び出しを強制ブロックする経路だが、
  本フックは deny/ask の理由を人間が読みやすい形で返したいため、
  exit 2 ではなく JSON 出力（`permissionDecision: "deny"` / `"ask"`）で表現する。
- **フックと `permissions` の評価順序**: PreToolUse フックは、`bypassPermissions`
  モードや `--dangerously-skip-permissions` を含む**すべての permission mode
  より前**に評価される。フックが `"deny"` を返せばそれらのモードでもブロック
  される（"A blocking hook also takes precedence over allow rules"）。
  **一方、フックが `"allow"` を返しても、その後 `permissions.deny` /
  `permissions.ask` は変わらず評価され、一致すればブロック・確認が発生する
  （"a matching ask rule still prompts even when the hook returned
  `"allow"` or `"ask"`"）。フックの `allow` は `permissions.deny` /
  `permissions.ask` を一切上書きできない。**
  **この事実は当初の実装で見落としており、孫1 の PR レビューで発覚し
  2026-09-12 に司令官が原文で再確認して訂正した（§3.3 参照）。**

### 3.3 フックは制限を足せるだけ。`permissions` を緩める方向には使えない（2026-09-12 訂正）

**当初はここに「フックが `allow` を返せば `permissions.ask` を素通りできる」という
二層構造を書いていたが、§3.2 の契約と正面から矛盾しており成立しない。** 孫1 の
実装中に判明したため、計画書
`docs/planning/DOC-2609121700_autopilot-permissions_計画.md`「設計2」を書き直し、
本 ADR もそれに合わせて訂正した。訂正前の記述に依拠したコードコメント・レビュー
コメントは、この節の内容で読み替えること。

公式ドキュメントはむしろ逆方向の使い方を明示的に推奨している。

> To run all Bash commands without prompts except for a few you want blocked,
> add `"Bash"` to your allow list and register a PreToolUse hook that rejects
> those specific commands.

つまり **PreToolUse フックは、`permissions` が許した範囲の中から危険な部分集合を
`deny`/`ask` へ引き上げる（制限を足す）ことしかできない。** `ask`/`deny` を
緩める方向には一切効かない。本設計は次の構造を取る。

- **AI に摩擦なくやらせたい操作は、`permissions.ask` / `permissions.deny` の
  どのパターンにも一致してはならない。** その操作の安全性はフックだけが担保する
- **`permissions.ask` に残すのは「フックが不在でも無条件に止めたいもの」だけ**に
  する。条件つき（ブランチ次第・PR の base 次第）で許したい操作を `ask` に
  置いてはいけない。置いた瞬間、フックが `allow` を返しても止まる
- 上記の推奨形（`allow` に `Bash` を置き、フックで個別に弾く）と本設計は同じ
  構造である。実際、人間の実機の `~/.claude/settings.json` の `permissions.allow`
  には既に `"Bash"` が含まれている（実測 2026-09-12）
- 追跡されている `claude/settings.json` に `Bash(git merge *)` は**足さない**
  （フックが唯一の担保）

#### `git push --force-with-lease` を摩擦なく通すための具体策

`permissions` のパターンは `*` のみだが、**空白の有無を厳密に区別する**
（"A `*` in a Bash rule matches any text, including spaces" /
"The space before a trailing `*` is part of the rule."）。これを利用して
「裸の `--force` だけ」を単語境界で拾い、`--force-with-lease` を除外できる。

- **削除**（どちらも `--force-with-lease` に一致してしまう。`*--force*` は
  空白を挟まないため `--force-with-lease` の中の `--force` を拾う）:
  `"Bash(git push *--force*)"` / `"Bash(git push *--force-with-lease*)"`
- **代わりに置く**（裸の `--force` だけを単語境界で拾う4パターン）:
  `"Bash(git push --force)"` / `"Bash(git push --force *)"` /
  `"Bash(git push * --force)"` / `"Bash(git push * --force *)"`
- **残す**: `"Bash(git push -f*)"` `"Bash(git push * -f*)"`
  `"Bash(git push *+*)"` `"Bash(git push *--delete*)"`（いずれも
  `--force-with-lease` には一致しない。`* -f*` が要求する「空白 + `-f`」は
  `--force-with-lease` の中に現れない）
- **追加**（フックが不在でも効く、ブランチ名の形をした残余の網）:
  `"Bash(git push * main*)"` / `"Bash(git push * master*)"`。ブランチ名を
  明示した保護ブランチへの push は、force かどうかに関わらず人間の仕事なので、
  ここで止まるのが正しい挙動。孫ブランチ名（例: `autopilot-permissions-01-git-guard`）
  には一致しない

これらの非一致・一致は `tests/git_guard_test.sh` の
`claude/settings.json` パターン検証で回帰テスト化している。

#### 受け入れる残余リスク

`"Bash(git push * master*)"` / `"Bash(git push * main*)"` が拾えるのは、
**コマンド文字列中に「空白の直後の裸のブランチ名」として `main`/`master` が
現れる形（例: `git push origin master`）だけ**である（実測で確認済み。下記
5パターンのうち拾えるのは1つだけ）。したがってパターンだけでは表現できない
穴は、refspec を省略した形の1つではなく、**対象ブランチ名がコマンド文字列
中で裸の単語として現れないあらゆる書き方**に及ぶ。実測（`fnmatch` で
`permissions.ask` の全パターンと突合）:

| コマンド（保護ブランチをチェックアウトした状態で `git push --force-with-lease origin ...`） | `permissions.ask` に一致するか |
|---|---|
| `origin master`（裸のブランチ名） | ✅ 一致する（`* master*`） |
| `origin HEAD` | ❌ 一致しない |
| `origin @` | ❌ 一致しない |
| `origin HEAD:master`（refspec のコロン区切り） | ❌ 一致しない（`master` の直前が `:` で空白ではない） |
| `origin refs/heads/master`（完全参照） | ❌ 一致しない（`master` の直前が `/`） |
| refspec 省略（`git push --force-with-lease` のみ） | ❌ 一致しない |

**これらすべてで、フック自体は refspec を正しく解析し `master`/`main` へ
解決して deny する。** 一致しないのは `permissions.ask` 側のバックアップ
（フック不在・故障時の網）だけであり、**フックが唯一の担保**になっている
範囲は「refspec 省略形」よりずっと広い。フックが配布されていない・壊れて
いる環境では、上記の ❌ の書き方すべてが素通りする（fail-open）。

受け入れる根拠:

1. フックは `claude/deploy.sh` が配り、`deploy-all.sh --status` がリンク切れを
   検出する（本 PR で `links_for_tool()` の `claude` arm に追加済み）
2. `--force-with-lease` はリモートの ref がローカルの認識と一致するときだけ
   push できるため、**他人の更新を消さない**（force push 一般の危険性のうち
   「他人の作業を上書きする」リスクは lease の仕組み自体が防ぐ）
3. 保護ブランチ（`main`/`master`）をチェックアウトして作業すること自体が、
   本傘の傘ブランチ運用では例外的である（通常は孫・傘ブランチ上で作業する）

**`permissions.ask` 側の網をこれ以上広げてこの残余リスクを縮める判断
（例えば `HEAD:master` や `refs/heads/master` まで拾うパターンを追加するか）
は、本 PR のスコープでは行わない。** 広げるほど誤検出（無関係な操作への
過剰な `ask`）も増えるトレードオフがあり、範囲を広げるかどうかの判断は
司令官に委ねる。

**フックが配布されていない・壊れている環境で黙って通らないこと自体は
引き続き大切にする。** そのため `claude/settings.json` の `ask` には
「フック不在でも無条件に止めたいもの」（裸の `--force`/`-f`、`+<refspec>`、
`--delete`、ブランチ名が空白区切りの裸の単語として `main`/`master` に
一致する push）を残す。フックが動作しない環境でも、これらのパターンに
一致する危険な操作は `permissions.ask` の網に落ちる。

### 3.4 `claude/settings.machine.json` が `hooks.PreToolUse` を持つ場合の落とし穴

`claude/deploy.sh` の settings 生成は、`machine.json` が持つキーを `permissions`
以外は浅い `update()` でベース設定へマージする（`claude/deploy.sh` の
`PYEOF` ブロック参照）。イベント名が異なる `hooks` エントリ同士（例:
ベース側の `PreToolUse` と machine 側の `SessionStart`）は共存するが、
**machine 側が `PreToolUse` を定義すると、浅いマージによりベース側の
`hooks.PreToolUse`（＝本フックの配線）が丸ごと上書きされて消える。**
実測（2026-09-12）では `claude/settings.machine.json` は `SessionStart`
（Herdr の `herdr-agent-state.sh`）のみを持ち、この落とし穴には未だ踏み込んで
いないが、将来 machine 側に `PreToolUse` を足す変更をする場合は、ベース側の
エントリを配列に追記する形にしないと本フックが無効化されることに注意する。

## 4. 却下案

### 4.1 `permissions` のパターンだけで表現する

上記2節のとおり、`gh pr merge` の base 情報も `git push` の対象ブランチ
（refspec 省略時）もコマンドライン文字列に現れないため、原理的に表現不能。
`permissions.allow` に `--force-with-lease` 用のパターンを足しても、より広い
`ask` パターン（`Bash(git push *--force*)`）に飲まれて無効化される実例が
既に手元の環境にあった（計画書 背景3-A）。

### 4.2 孫ペインを `--dangerously-skip-permissions` 相当で起動する

無人運転の障害を「確認そのものを無くす」ことで解消する案。しかし、これは
「main/master へのマージは人間」という唯一の線引きごと消し飛ばす。傘の
目的は「線引きを保ったまま無人運転の摩擦を無くす」ことであり、線引き自体を
放棄する手段は本末転倒として却下した。ADR §3.2 で確認したとおり、PreToolUse
フックは `bypassPermissions` モードでも `deny` を強制できるため、フック方式は
将来 `--dangerously-skip-permissions` 相当の起動が検討される場面でも
線引きを保てるという副次的な利点がある。

### 4.3 すべて人間が押す（現状）

計画書の問題意識そのもの。押す人間がいない孫のペインでは無人運転が
そこで止まり、autopilot が autopilot として機能しない。

## 5. 実装

- `claude/hooks/git-guard.sh`: POSIX sh + python3（ヒアドキュメント）で
  判定表を実装した PreToolUse フック本体。
- `claude/settings.json` の `hooks.PreToolUse` に配線（matcher: `Bash`）。
- `shared/helpers.sh` の `links_for_tool()` の `claude` arm に
  `$HOME/.claude/hooks/git-guard.sh` を追加し、`uninstall.sh` /
  `deploy-all.sh --status` の両方から見えるようにした。
- `tests/git_guard_test.sh`: フックへ JSON を流し込み判定を突き合わせる
  スタンドアロンテスト。`gh` / `git` はスタブに差し替え、ネットワークにも
  実リポジトリの状態にも依存しない。

## 6. 既知の制限

- **force 系フラグ（`--force` / `--force-with-lease` / `-f` / `+<refspec>`）を伴わない
  `git push`（例: `git push origin master`）はこのフックの対象外であり、何も言わず
  `permissions` の判定に委ねる。** 判定表の「上記以外」に該当する。
- コマンドのトークン化には `shlex.split()`（POSIX モード）を使う。複雑な
  シェル構文（コマンド置換、変数展開を含むもの）は正しく解釈できない場合が
  あるが、その場合は例外を捕捉して `ask` に倒すため安全性は保たれる。
- **サブコマンドの判定は「`git`/`gh` という単語が最初に現れる位置の直後
  にある最初の非オプショントークン」を見る単純な方式（`subcommand_of`）。**
  `git merge` を含むかどうかを連続文字列で判定すると、
  `git commit -m "merge conflict fix"` のような日常的なコマンドまで
  誤検出してしまい（`git merge` に対する `permissions.ask` 側の保険が
  無い設計のため、逆に緩い文字列一致で拾いすぎると無関係な操作に
  頻繁に `ask` が出て autopilot の目的を損なう）、トークンベースの
  サブコマンド特定でこれを避けている。副作用として `echo git merge` の
  ように `git`/`gh` が別コマンドの引数値として現れる場合を誤検出する
  ことがあるが、その場合は実際に git/gh が実行されないため deny/ask に
  倒れても実害は無い。
- `git -C <dir>` や `gh --repo <owner/repo>` のようにサブコマンドの位置へ
  グローバルオプションを挟む書き方は、直後のトークンが `-` 始まりになり
  サブコマンドを安全に断定できないため `ask` に倒れる（誤って `allow` には
  ならない）。
- `git push` のオプションのうち、値を取りうる可能性がある未知のフラグ
  （`-o` / `--push-option` / `--repo` / `--receive-pack` 以外の未知の `-` 始まり
  トークン）が出現した場合は、対象ブランチの解決を諦めて `ask` に倒す。
