# ADR: git 操作の許可ポリシー — フックが止めるのは `gh pr merge` の base だけ

## ステータス

確定（2026-09-12）／**改訂（2026-09-13）: 設計思想を反転。判定できない入力は
`ask` ではなく「何も言わない」に倒す。フックの担保範囲を `gh pr merge` の
base 判定だけに縮小した。**

初版（PR #94）の判定表・fail-safe 設計は本改訂で**破棄**した。初版に依拠した
コードコメント・レビューコメント・他文書の記述は、本文書の現行の記述で読み替える。
破棄した内容と破棄の理由は §6 に記録する。

## 1. 背景

計画書 [DOC-2609121700](../planning/DOC-2609121700_autopilot-permissions_計画.md)
（傘 `autopilot-permissions`）が確定させた線引きは1本だけである。

> **`main` / `master` へのマージは人間がやる。それ以外は AI に任せる。**

傘ブランチ方式（`umbrella-orchestrator`）の無人運転では、孫→傘のマージ・傘への
上流取り込み・孫の rebase + force push といった**傘の内側で完結する操作**が
日常的に何度も走る。ここに承認ダイアログが出ると、押す人間がいない孫のペインは
そこで固まり、autopilot が autopilot として機能しない。

**そして「autopilot でやることになる作業は、全部、承認なしで通す」。** 人間の
承認が要るのは `main` / `master` に変更が入る最終行為だけである。`git rebase` で
傘を上流に追いつかせて `git push --force-with-lease` する操作にまで承認を出す
実装は、この要件を満たしていない（初版がまさにそれだった。§6）。

## 2. なぜ `gh pr merge` だけがフックの仕事なのか

不可逆なのは**リモートを書き換える操作**だけである。ローカルの `git merge` も
`chmod` も `rm`（ワークツリー内）も、push しない限り巻き戻せる。

| 操作 | 不可逆か | コマンド文字列から判定できるか |
|---|---|---|
| ローカルの `git merge` | いいえ（push しなければ巻き戻せる） | — |
| `chmod +x` / 一時ディレクトリの `rm -r` | いいえ | 対象パスは文字列に現れる |
| `git push` で `main`/`master` を更新 | **はい** | **グロブで書ける**（`Bash(git push * master*)`） |
| `gh pr merge` で `main`/`master` へ | **はい** | **書けない**（base がコマンド文字列に現れない） |

`gh pr merge <PR番号>` のコマンドラインに base は現れない。base は PR 側の属性で
あり、`gh pr view <N> --json baseRefName` を別途叩かない限り「この PR のマージ先が
`master` か傘ブランチか」を判別できない。**グロブで表現できないのはこの1点だけ**で
あり、したがってフックが担保するのもこの1点だけでよい。

## 3. 決定

**フックは `gh pr merge` の base が保護ブランチ（`main` / `master`）と確定できた
ときだけ `deny` する。それ以外は何も言わない。**

### 3.1 判定表

| 対象コマンド | 判定 |
|---|---|
| `gh pr merge`（PR 番号 / URL / 省略＝現ブランチ）で base が `main`/`master` | **deny** |
| `gh pr merge` で base が上記以外だと確定できた | **allow**（孫→傘のマージを無音で通すための積極的な allow） |
| `gh pr merge` だが base を解決できない（`gh` の実行失敗・PR 不明・`shlex` で解釈できない等） | **何も言わない** |
| 上記以外のすべて（`git push` / `git merge` / `git fetch` / `chmod` / `rm` / 連結コマンド / `git -C` …） | **何も言わない** |

**`ask` を返す経路はフックに存在しない。** 「判定できない入力は必ず `ask` に倒す」
という初版の fail-safe は破棄した（§6）。判定できないなら既存の `permissions` に
委ねる。

`-R` / `--repo`（対象リポジトリを cwd から動かすオプション）は `gh pr view` 側へ
そのまま引き継ぐ。引き継がずに cwd で base を解決すると、**別リポジトリの PR を
手元のリポジトリのブランチ構成で判定してしまい、`master` へのマージを `allow` に
倒しうる**（初版の修正案を書いていた相談 AI が実際にこの穴を作りかけた）。

**`--repo` は `gh pr` 配下の inherited flag であり、`gh` の直後（`gh -R o/r pr
merge 7`）だけでなく `pr merge` の後ろ（`gh pr merge 7 -R o/r`）にも書ける。**
片側しか見ないと、後ろに置かれた `-R` は値を取らないフラグとして読み飛ばされ、
その値（`o/r`）がマージ対象として採用される。結果は cwd 基準の解決になり、
同じ穴が位置違いで残る。`-Ro/r` の密着形・`--repo=o/r` の等号形も同様。
`tests/git_guard_test.sh` が5つの書き方すべてについて、`deny` になることと
`gh pr view` へ引き継がれた引数の実物を固定している。

**`gh` はコマンド位置にあるものだけを拾う**（先頭、または直前が `&&` / `||` /
`;` / `|` / `do` / `then` などのシェル演算子）。`shlex.split()` はヒアドキュメントの
本文も同じトークン列に混ぜるため、位置を見ないと
`cat >> notes.md <<'EOF' ... gh pr merge 93 ... EOF` のような**ただのファイル
書き込みが `deny` される**。`deny` は `bypassPermissions` でも覆せないぶん `ask`
より強く止まり、しかもエラーメッセージ（「この PR の base は 'master' です」）は
実際に起きたこと（ドキュメントの追記）と対応しないため切り分けも難しい。
傘の commander が進捗表や対応報告を書き込む経路そのものであり、
`skills/umbrella-orchestrator/SKILL.md` 自身がこの文字列を手順として持っている。

### 3.2 `git push` は `permissions.ask` のグロブが受け持つ

`main`/`master` への push は対象がコマンド文字列に現れるため、フックではなく
`claude/settings.json` の `permissions.ask` で止める。

- `Bash(git push * main*)` / `Bash(git push * master*)` — 空白区切りの裸の
  ブランチ名での push
- `Bash(git push *:main*)` / `Bash(git push *:master*)` /
  `Bash(git push *heads/main*)` / `Bash(git push *heads/master*)` —
  コロン区切りの refspec（`HEAD:master`）と完全参照（`refs/heads/master`）。
  **上の2パターンは `master` の直前が空白でないと一致しないため、これらが
  無いと `git push origin HEAD:master` がどの層からも漏れる**（初版では
  force 系に限ってフックが refspec をパースして拾っていた形）。autopilot が
  日常的に打つ `git push -u origin <孫ブランチ>` /
  `git push --force-with-lease origin <傘ブランチ>` はどれにも一致しない
- `Bash(git push --force)` / `Bash(git push --force *)` / `Bash(git push * --force)` /
  `Bash(git push * --force *)` / `Bash(git push -f*)` / `Bash(git push * -f*)` /
  `Bash(git push *+*)` — 裸の force 系（AGENTS.md 最重要ルールでも人間の承認が要る）

`--force-with-lease` はこのどのパターンにも一致しない（`--force` の直後が空白では
なく `-with-lease` のため）。傘・孫ブランチへの `--force-with-lease` は無音で通る。
**`Bash(git push *--force*)` のように空白を挟まないパターンを置くと
`--force-with-lease` まで拾ってしまい、autopilot が止まる。置かないこと。**

`Bash(git push *--delete*)` は**削除した**。孫→傘のマージ後に残るリモートブランチの
掃除（`git push origin --delete <孫ブランチ>`。`skills/umbrella-orchestrator` §3.3 が
明示している手順）が毎回止まっていたため。`--delete` で `master` を消す形は
`Bash(git push * master*)` 側が拾う。

### 3.3 フックから外した `chmod` / `rm -r` は狭い `permissions.allow` で通す

初版は `chmod +x` と一時ディレクトリの `rm -r` もフックで判定していた（旧 §7）。
これらは対象パスがコマンド文字列に現れるため、フックを使わずグロブで表現できる。
`claude/settings.json` の `permissions.allow` に次を追加した。

- `Bash(chmod +x *)`
- `Bash(rm -r /tmp/tmp.*)` / `-rf` / `-fr`（`mktemp -d` の後片付け）
- `Bash(rm -r /tmp/claude-*)` / `-rf` / `-fr`（セッションの scratchpad の後片付け）

初版の旧 §7.4.1 は `Bash(chmod +x *)` を「ワークツリー外への `chmod +x` も通して
しまう」として却下していたが、**この却下理由は本改訂で取り下げる。** `chmod +x` は
不可逆ではなく、守るべき線引き（`main`/`master` を書き換えさせない）にも触れない。
729行のフックを維持する理由としては釣り合わない。なお `ask` は `allow` に優先する
（deny > ask > allow）ため、`Bash(chmod * /*)` / `Bash(chmod * ~*)` /
`Bash(chmod * $HOME*)` に一致する絶対パス・ホーム配下への `chmod` は従来どおり止まる。

### 3.4 PreToolUse フックの入出力契約（一次情報での確認結果、2026-09-12）

サブエージェント（`claude-code-guide`）経由で Claude Code 公式ドキュメント
（Hooks Guide / Hooks Reference: `https://code.claude.com/docs/en/hooks.md` ほか）を
確認した結果。**本改訂でも有効な事実である。**

- **stdin の JSON**: `hook_event_name: "PreToolUse"`、`tool_name`（Bash なら
  `"Bash"`）、`tool_input.command` にコマンド文字列、`cwd` に実行時のカレント
  ディレクトリが入る
- **判定結果**: stdout に
  `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"|"deny"|"ask", "permissionDecisionReason": "..."}}`
  を書き exit 0 する。2つのキーは必ず `hookSpecificOutput` の直下に置く
  （トップレベルに置くと無視される）
- **終了コード**: exit 0 で stdout が空なら「意見なし」として通常の permission flow に
  委ねられる。本フックの「何も言わない」はこの経路
- **評価順序**: PreToolUse フックは `bypassPermissions` モードや
  `--dangerously-skip-permissions` を含む**すべての permission mode より前**に
  評価され、`deny` はそれらのモードでもブロックする。**一方、フックが `allow` を
  返しても `permissions.deny` / `permissions.ask` は変わらず評価され、一致すれば
  止まる。フックの `allow` は `permissions` を緩める方向には一切効かない**
  （"a matching ask rule still prompts even when the hook returned `allow`"）

この非対称性が §3.2 の設計を要求する: **AI に摩擦なくやらせたい操作は
`permissions.ask` / `deny` のどのパターンにも一致してはならない。**

### 3.5 3層構造と分類器（2026-09-12 確認）

permission の評価は3層ある（<https://code.claude.com/docs/en/permission-modes>）。

1. `permissions.allow` / `ask` / `deny` に一致した操作は即決
2. PreToolUse フック（本フック）
3. auto mode の分類器 — 1のどのルールにも一致しない操作が落ちる先

分類器は3回連続または累計20回ブロックすると auto mode を一時停止する。無人ペインは
そこで確実に止まるため、分類器へ落ちる操作は減らしたい。**分類器を確実に迂回できると
分かっているのは `permissions.allow` に一致させる経路だけ**であり、フックの `allow` が
同じ効果を持つかは公式ドキュメントに明記が無い（未検証）。§3.3 で `chmod`/`rm -r` を
フックの `allow` から `permissions.allow` のグロブへ移したことは、この観点では
**未検証の前提への依存を1つ減らしている**。

`gh pr merge`（base が非保護のとき）は引き続きフックの `allow` に依存する。孫1〜4
（PR #88〜#91）が実際にこの経路で無人マージされており、運用上の状況証拠はある。

### 3.6 `claude/settings.machine.json` が `hooks.PreToolUse` を持つ場合の落とし穴

`claude/deploy.sh` の settings 生成は `machine.json` のキーを `permissions` 以外
浅い `update()` でマージする。**machine 側が `PreToolUse` を定義すると、ベース側の
`hooks.PreToolUse`（＝本フックの配線）が丸ごと上書きされて消える。** 実測
（2026-09-12）では machine 側は `SessionStart` のみを持ちこの穴は踏んでいないが、
将来 machine 側へ `PreToolUse` を足すときは配列に追記する形にすること。

## 4. 却下案

### 4.1 初版を維持したまま穴を塞ぐ

`cd <repo> && git status` が止まる穴・`git -C` が常に止まる穴を個別に塞ぐ差分
（326行）は実際に書かれ、テストも通っていた。**却下した。** 穴は fail-safe 設計
そのものの帰結であり、個別に塞いでも同じ形の巻き添えが再生産される（実際、その
差分自身が `git -C <他リポジトリ> merge` を `allow` に倒す新しい穴を作りかけた）。
1,789行（フック729 + テスト590 + 本 ADR 470）は、守っている線引き1本に対して
釣り合っていない。

### 4.2 `permissions` のパターンだけで表現する（フックを廃止する）

`gh pr merge` の base だけは原理的にグロブで表現できない（§2）。フックを完全に
廃止すると、AI が `master` へマージすることを機械的に止める手段が無くなる。

### 4.3 孫ペインを `--dangerously-skip-permissions` 相当で起動する

「main/master へのマージは人間」という線引きごと消し飛ぶため却下。

### 4.4 すべて人間が押す（初版導入前の状態）

押す人間がいない孫のペインでは無人運転がそこで止まる。

## 5. 実装

- `claude/hooks/git-guard.sh`（POSIX sh + 埋め込み python3、193行）: §3.1 の判定表
- `claude/settings.json`: `hooks.PreToolUse` への配線（matcher: `Bash`）と
  §3.2 / §3.3 の `permissions`
- `shared/helpers.sh` の `links_for_tool()` の `claude` arm に
  `$HOME/.claude/hooks/git-guard.sh`（`uninstall.sh` / `--status` の一次情報源）
- `tests/git_guard_test.sh`: 判定表と**「無音でなければならない操作」の一覧**を
  同じ重みで固定する。`.pre-commit-config.yaml` の `git-guard-test` フックから
  フック本体／テスト変更時に自動実行される（CI の `pre-commit run --all-files` も同じ）

## 6. 破棄した初版の設計と、破棄の理由（2026-09-13）

初版（PR #94、2026-09-12）は次の設計だった。

- 判定表に `git push`（force 系の対象ブランチ解決）・`git merge`（現ブランチ判定）・
  `chmod`・`rm -r` を含む5系統を持つ
- **「判定できない入力は必ず `ask` に倒す（`allow` に倒すことは絶対にしない）」**

deploy 直後の実環境（2026-09-13、WSL2）で、この設計は目的と逆の結果を出した。

- **連結の判定にはパイプ `|` も含まれていた**（`has_chain()` の正規表現は
  `&&|;|\|`）。エージェントが叩く Bash コマンドにはパイプか `&&` がほぼ必ず付くため、
  被害は「連結したとき」ではなく事実上**`git` と名のつくものほぼ全部**だった
  （`git log | head` / `git status | grep ...` / `git add -A && git commit -m "..."`）
- **deploy 後の最初の1コマンド目で発現した**:
  `for r in ...; do cd $r && git config --get ocw.worktreeDir; ...; done`。
  生コマンドに `git` があり、かつ `&&` で連結されているという理由だけで `ask`
- `git -C <dir> <任意のサブコマンド>` が常に `ask`（グローバルオプションで
  サブコマンドを断定できないため）
- 上2つの合成で、**別ディレクトリで git を叩く手段が全滅した**（`cd &&` は前者、
  `git -C` は後者、素の `git` は cwd が固定。harness は Bash 呼び出しごとに cwd を
  戻すため単独の `cd` も永続しない）
- 人間の複数セッションで同時多発した

シェルコマンドの大半は静的解析できない。したがって「判定できなければ `ask`」は
実質「大半を `ask` にする」と同義であり、**巻き添えはバグではなく設計どおりの
帰結だった**。承認ダイアログを減らすために入れた仕組みが、承認ダイアログを増やした。

初版のレビューは判定表（何を deny/ask するか）だけを見ており、**「無関係な日常
コマンドが止まらないこと」が受け入れ条件に無かった。** これが回帰を通した直接の
原因である。本改訂では `tests/git_guard_test.sh` に「無音でなければならない操作」の
一覧を置き、判定表と同じ重みで固定した。**判定表に1行足すときは、必ず無音一覧にも
足すこと。**

## 7. 受け入れる残余リスク

- **base を解決できない場合、フックは何も言わない。** この窓で AI が `master` への
  PR をマージしうる。線引きの一次的な担保はルート `AGENTS.md` の最重要ルール
  （AI が読む規範）であり、フックはその機械的な裏打ちにすぎない。
  **解決失敗は「`gh` が落ちている場合」に限らない**ので、「`gh` が落ちていれば
  マージ自体も失敗するから窓は狭い」という緩和だけに寄りかからないこと。
  - **`gh` は生きているが遅い場合**: `resolve_base()` は `gh pr view` を
    `GH_TIMEOUT`（12秒。`claude/settings.json` のフック `timeout: 15` より短く
    取っている）で打ち切る。一方この後に走る `gh pr merge` 本体にフックは関与せず
    タイムアウトも無い。**フックだけが先に諦めてマージは成功する**という非対称が
    実装上存在する（VPN 経由・CI ランナー・WSL2 の DNS 解決遅延など）
  - **`gh` が正常でもマージ対象を取り違えた場合**: 解析の穴は同じ窓を開ける。
    §3.1 の `--repo` の位置の取りこぼしが実例であり、テストで固定してある
- **`sh -c "gh pr merge ..."` や `$(gh pr merge ...)` のように、`gh` が引用符や
  コマンド置換の中にしか現れない形は検出しない**（`shlex.split()` が1トークンに
  畳む、あるいは `$(gh` という別トークンになるため）。初版はこの形を
  `mentions_guarded_command()` で `ask` に倒していたが、判定できないものは
  何も言わないという本改訂の方針により素通りする
- **`master` に checkout した状態での refspec 省略 `git push`** はグロブから漏れる。
  傘方式では commander は傘ブランチ、孫は孫ブランチに常駐し、誰も `master` に
  checkout しない（`AGENTS.md` もそれを禁じている）
- **ブランチ名に `main` / `master` を含む孫ブランチへの push は `ask` になる**
  （`Bash(git push * main*)` の巻き添え）。孫ブランチ名にこれらを含めないこと
- **`cd <別リポジトリ> && gh pr merge ...` の base 解決は cwd 基準になる。** 同一
  リポジトリの別ワークツリーなら remote が同じなので正しく解決できる。`-R` を
  使う形は §3.1 のとおり引き継ぐため正しい
