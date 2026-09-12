# 計画書: 傘 autopilot が承認ダイアログで止まる問題の解消

傘ブランチ: `autopilot-permissions`
ターゲット: `master`

## 概要

傘ブランチ方式（`umbrella-orchestrator`）で無人運転しようとすると、孫→傘のマージ・
傘への上流取り込み・孫の rebase + force push・レビュワーの pull といった**傘の内側で
完結する操作のたびに承認ダイアログが出て止まる**。押す人間がいない孫のペインでは
そこで固まり、autopilot が autopilot として機能していない。

一方で、人間は**すべてを許したいわけではない**。線引きは1本だけである。

> **`main` / `master` へのマージは人間がやる。それ以外は AI に任せる。**

本傘はこの線引きを、(1) 許可設定、(2) 配布の仕組み、(3) 文言（`AGENTS.md` /
テンプレート）、(4) 配布スキルの4層すべてに一貫して通す。

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。既に参照できない前提で
> 書く）を material として司令官が起草したものである。** ブリーフに書かれていた問題意識・
> 決定事項・実測値・制約は、**すべて本計画書へ転記済み**であり、以降はこの計画書が正典である。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `autopilot-permissions-01-git-guard` | 許可ポリシーの確定（ADR DOC-2609121719）＋ 保護ブランチ判定の PreToolUse ガードフック新設 ＋ `claude/settings.json` 再設計 | ✅ PR #88 マージ済 |
| 2 | `autopilot-permissions-02-allow-preservation` | `claude/deploy.sh` が学習済み `allow` を deploy 越しに保全する仕組み ＋ `claude/README.md` 追随 | ✅ PR #89 マージ済 |
| 3 | `autopilot-permissions-03-agents-rules` | ルート `AGENTS.md` と `templates/repo-baseline/template/AGENTS.md.jinja` の最重要ルールを「`main` は人間 / 傘配下は AI」の軸で書き直す | ✅ PR #90 マージ済 |
| 4 | `autopilot-permissions-04-skill-exceptions` | `skills/pr-review-loop` / `skills/umbrella-orchestrator` の傘例外条項と、同一スキル内の矛盾の解消 | ✅ PR #91 マージ済 |
| 5 | `autopilot-permissions-05-non-git-prompts` | 無人ペインを止める**非 git 操作**の解消。`chmod +x` / `rm -r` をガードフックへ取り込み（背景3-G）、`mkdir` のように分類器で止まるコマンドへ狭い `allow` を置く（背景3-H） | 🔄 実装中 |
| 6 | `autopilot-permissions-06-machine-json-symlink` | `settings.machine.json` を `~/.claude/settings.json` の兄弟として symlink し、発見可能にする（背景3-I） | ⬜ 待機中 |

## ワークスペースラベル

傘のラベルは `umbrella-handoff` が既に日本語で付けている（`dotfiles :: 自動進行の権限詰まり`）。
既定形ではないので**司令官は改名しない**。孫のラベルはこれを親要約として導出する。

- 傘: `dotfiles :: 自動進行の権限詰まり`（既存。変更しない）
- 孫1: `dotfiles :: 自動進行の権限詰まり 孫1 ガードフックと許可設計`
- 孫2: `dotfiles :: 自動進行の権限詰まり 孫2 学習allowの保全`
- 孫3: `dotfiles :: 自動進行の権限詰まり 孫3 最重要ルールの書き直し`
- 孫4: `dotfiles :: 自動進行の権限詰まり 孫4 スキルの傘例外条項`
- 孫5: `dotfiles :: 自動進行の権限詰まり 孫5 chmodなど非git操作`
- 孫6: `dotfiles :: 自動進行の権限詰まり 孫6 machine.jsonの発見性`

## 依存関係と実行順序

```
孫1 (ガードフックで「main/master は人間、それ以外は AI」を機械的に担保し、
     その設計判断を ADR に固定する)
  ↓ 孫3・孫4 が書く文言は「ガードフックがどこで止めるか」と一致していなければならない。
  ↓ ADR が確定する前に文言だけ緩めると、文書と実際の挙動が食い違う
孫2 (学習 allow の保全。claude/deploy.sh を触るため孫1 と同じファイルに当たりうる)
  ↓
孫3 (ルート AGENTS.md + repo-baseline テンプレートの最重要ルール)
  ↓
孫4 (配布スキルの傘例外条項)
  ↓
孫5 (chmod など非 git 操作をガードフックへ取り込む。孫1 のフックが前提)
  ↓
孫6 (settings.machine.json の発見性。孫2 が変更した claude/deploy.sh をさらに触る)
```

**直列。** 理由は2つ。

1. **孫1 が確定させる ADR が、孫3・孫4 が書く文言の一次情報源になる。** 「AI がやってよい
   操作」の定義が先に確定していないと、文言側が独自の線引きを発明してしまう
2. **孫1 と孫2 はどちらも `claude/deploy.sh` に触る**（孫1 はフックの symlink 追加、
   孫2 は settings 生成ロジックの変更）。並列にすると確実に衝突する
3. **孫5 は孫1 が作ったガードフックへ arm を足す孫**である。フックが存在しない状態では
   着手できない
4. **孫6 は孫2 が変更した `claude/deploy.sh` の settings 生成部をさらに触る。**
   また `claude/README.md` は孫2・孫5・孫6 が共通で触るため、直列でないと衝突する

---

## 背景1: 人間の問題意識（逐語）

以下は相談時の人間の発言そのままである。**要約に置き換えないこと。**

> sheaf / lora-dataset-forge 両方に言えることだが、スキルの umbrella-orchestrator で進めるときに、傘ブランチへのマージや、傘に main の変更をrebaseで取り込んでプッシュ、孫に傘の更新を rebase でプッシュ、レビュワーが変更を pull するなどの動作にいちいち承認ダイアログがでて、非常にストレス。autopilot の意味がない。main や master へのマージは人間がやりたいが、それ以外は任せたいのに。原因を探って、それぞれのリポジトリがわで変更を加えないといけなそうな点、そもそも dotfiles 側で何とかする必要がある点などを洗い出してくれ

> これはいろんなリポジトリにまたがるから、こういうときどういうふうに開発するのがいいんだろうな。傘へのハンドオフは、一個一個のリポジトリにばらけるんだよね？総司令官みたいなのがいるのかな。

## 背景2: 人間が確定させた決定事項（覆さないこと）

- **`main` / `master` へのマージは人間がやる。それ以外は AI に任せる。** これが
  許可ポリシーを設計するときの唯一の線引き。孫→傘マージ、傘への上流取り込み、
  孫の rebase + force push は AI に任せたい側。
- **総司令官（リポジトリ横断の司令官）は作らない。** 傘はリポジトリに1本という前提を
  崩さない。この傘は dotfiles 1本。
- **sheaf / lora-dataset-forge 側の変更は、この傘の孫にしない。** dotfiles でポリシーが
  確定してから、各リポジトリの単発 PR として別途行う（順序は dotfiles が先）。
- 各リポジトリの `AGENTS.md` が持つ「`git merge` / `git push --force` 禁止」条項は、
  `templates/repo-baseline/template/AGENTS.md.jinja` が出所である。
  **個別リポジトリを直す前に、まずテンプレートを直す**という方針で合意している。

## 背景3: 既存の穴

調査は 2026-09-12 に相談 AI が実施。以下はすべてその時点の実測に基づく。
司令官が本計画書の起草時（同日）に再確認し、追加で判明した点は「司令官の追検証」として
併記した。

### A. ユーザーグローバルの `ask` が `allow` を握りつぶしている

`~/.claude/settings.json`（deploy が生成する実ファイル）の `permissions.ask`:

```
"Bash(git merge *)"
"Bash(git push *--force*)"
"Bash(git push *--force-with-lease*)"
"Bash(git push -f*)"
"Bash(rm -r *)"  ほか
```

権限の優先順位は **deny > ask > allow**。人間が承認ダイアログで「今後確認しない」を
押すと `allow` に積まれるが、`ask` パターンに当たる限り永久に聞かれ続ける。

**実際にその跡が残っている。** 同じファイルの `allow` に次の2件が積まれている:

```
"Bash(git merge --ff-only:*)"
"Bash(git merge --ff-only *)"
```

1回許可しても効かず、書式を変えてもう1度押した跡である。`ask` の `Bash(git merge *)`
が勝つため、どちらも効かない。

該当する人間の不満:

- 「傘に main の変更を rebase で取り込んでプッシュ」→ `--force-with-lease` が `ask` 直撃
- 「孫に傘の更新を rebase でプッシュ」→ 同上
- sheaf の作法である `git fetch` + `git merge --ff-only` → `Bash(git merge *)` に食われる

なお `gh pr merge --squash` は `ask` に無いので**権限上は通る**。孫→傘マージが
止まっているのは D / E が原因であり、A ではない。ここを混同しないこと。

**司令官の追検証**: `Bash(git merge *)` は**追跡されている `claude/settings.json` の
`ask` には無い**。`~/.claude/settings.json` にだけ存在する。つまりこの1件は deploy 由来
ではなく、`/permissions` 等で人間または AI が生成物へ直接足したものである（実測値の節を参照）。
追跡側の `ask` に実在するのは `Bash(git push *--force*)`
`Bash(git push *--force-with-lease*)` `Bash(git push -f*)` `Bash(git push * -f*)`
`Bash(git push *+*)` `Bash(git push *--delete*)` などである。

### B. `claude/settings.machine.json` が `git merge` を deny している（時限爆弾）

`claude/settings.machine.json`（git 非追跡。`claude/deploy.sh` がベース設定とマージして
`~/.claude/settings.json` を生成する）:

```json
"deny": ["Bash(git merge *)", "Bash(git merge --*)"]
```

`deny` は対話で覆せない。かつ `~/.claude/settings.json` は**生成される実ファイル**
なので、次に `./deploy-all.sh` を実行した時点で:

1. 現在 `~/.claude/settings.json` に手で入っている `ask` / `allow` が全部消える
2. machine.json の `deny: git merge` が復活し、マージが**完全に不能**になる

さらに構造的な欠陥として、**Claude Code が学習した `allow` を
`claude/settings.machine.json` へ還流させる経路が存在しない**。学習した権限は
deploy のたびに揮発する。`claude/README.md` は「deploy 前に settings.machine.json を
作成してください」と警告しているだけで、継続的な還流は扱っていない。

**司令官の追検証（重要）**: `claude/settings.machine.json` は
**`/home/manemone/projects/dotfiles/master`（main ワークツリー）にだけ存在し、
本傘のワークツリーには存在しない**。git 非追跡ファイルはワークツリー間で共有されない
ためである。したがって:

- **傘や孫のワークツリーから deploy すると、machine.json ごと消える。**
  生成物はベース設定そのものになり、`allow`・`hooks`（herdr のエージェント状態フック）・
  `additionalDirectories` が丸ごと落ちる（`.backup` には退避される）
- B の「時限爆弾」は**どのワークツリーから deploy するかで挙動が変わる**という形でも
  存在する。孫2 の設計判断はこの事実を前提にすること

### C. `.claude/settings.local.json` が孫ワークツリーへ引き継がれない

（**この傘のスコープ外**。各リポジトリ側の単発 PR で扱う。背景として記録しておく）

sheaf の実測:

| ワークツリー | `.claude/` の中身 |
|---|---|
| `sheaf/main` | `settings.json` + `settings.local.json`（学習済み allow 100件超） |
| `sheaf/ai/flow-boundary-impl-05-cluster-nav` | `settings.json` のみ |
| `sheaf/ai/flow-boundary-impl-06-status-hints` | `settings.json` のみ |

孫は spawn のたびに権限学習をゼロからやり直し、`ocw rm` で worktree ごと捨てられる。
恒久的に必要な allow は checked-in の `.claude/settings.json` へ昇格させるべきだが、
sheaf は7件、lora-dataset-forge は4件しかない。

### D. repo-baseline テンプレートに傘運用の例外条項が無い

`templates/repo-baseline/template/AGENTS.md.jinja:14-16`:

```
- **人間の明示的指示がない限り、`git merge` / `git pull` / `git reset --hard` /
  `git push --force` / `gh pr merge` を実行しない。例外はない。**
```

この文言がそのまま lora-dataset-forge の `AGENTS.md:11` に出ている（`pull.rebase`
未設定の注記が足された形）。sheaf も repo-baseline 生成物で、そこへ人間が後から
手で傘の例外を足した状態になっている。sheaf の現行文面（**流用の下敷きにできる**）:

```
- **`main` を書き換える操作は人間だけが行う。** `main` へのマージ・push を AI が
  実行しない。例外はない。
- **孫ブランチ → 傘ブランチのマージは AI が行ってよい。** ただしレビューで承認済みの
  PR に限る（`gh pr merge <PR番号> --squash --delete-branch`）。傘ブランチは孫を
  安全に統合するための隔離された場所であり、そこへのマージまで人間待ちにすると
  傘方式が機能しない。
- **`git pull` は使わない。** ブランチの追随は `git fetch origin` +
  `git merge --ff-only origin/<branch>` で行う。
```

ただし sheaf にも穴が残っている:

```
- **`git reset --hard` / `git push --force` は、ブランチを問わず実行しない。例外はない。**
```

これがあるため「孫に傘の更新を rebase して push」が原則禁止のままになっている。
**孫ブランチ限定の `--force-with-lease` 例外**がテンプレートに要る。

つまりテンプレートが持つべきなのは「`main` は人間 / 傘配下は AI」という軸で書き直した
最重要ルールであり、それを撒けば各リポジトリの作業は数行の追従で済む。

### E. 配布スキルのルールが autopilot と矛盾している

`skills/pr-review-loop/SKILL.md`「安全制約」:

> **承認されても、人間の明示的指示がない限りマージ（`git merge` / `gh pr merge`）を
> 絶対に実行しない。** これはこのスキルの最優先ルール。承認＝マージ許可ではない。
> Phase 7 で「マージは実行していないこと」を報告するのはこのルールに基づく。

`skills/umbrella-orchestrator/SKILL.md` §3.2（孫用プロンプトの雛形内）:

> 4. 承認されたら人間に「マージしてください」と依頼する

`skills/umbrella-orchestrator/SKILL.md` §6「司令官がやらないこと」:

> - PR マージ（人間の仕事）

ところが同じスキルの §3.5 `/autopilot` 手順5 は:

> 5. 判定が「承認」かつ 対象HEAD が最新コミットと前方一致するならマージ:
>    `gh pr merge <PR番号> --squash --delete-branch`

**同一スキル内で正面衝突している。** 孫の implementer は pr-review-loop の最優先ルールに
従って承認後に必ず人間待ちになり、司令官も §6 に従えばマージしない。autopilot が
動かない直接原因のひとつ。**base が傘ブランチの PR に限る例外条項**が、
pr-review-loop 側と umbrella-orchestrator §6 / 孫用プロンプトの両方に要る。

**司令官の追検証**: `umbrella-orchestrator` §3.2 の孫用プロンプト雛形と §7 の
「人間が手動でPRをマージしていた場合」には `git pull --rebase origin <傘ブランチ>` が
書かれている。これはルート `AGENTS.md`（および repo-baseline テンプレート）の
「`git pull` を実行しない」と衝突しており、E と同じ構図の矛盾がもう1組ある。孫4 の
対象に含める。

### H. 承認ダイアログの出どころは permissions だけではない（auto mode の分類器）

**本傘の実運用中に人間が観測した追加の穴**（2026-09-12、孫2 の実装中に報告された）:

> mkdir でもつまる

`mkdir` は `ask` にも `deny` にも入っていない。**止めているのは permissions ではなく
auto mode の分類器**である。司令官が公式ドキュメント
（<https://code.claude.com/docs/en/permission-modes>）で確認した評価順（原文の要約）:

1. **allow / ask / deny ルールに一致した操作は即決**（分類器へ行かない）
2. 読み取りと作業ディレクトリ内の編集は自動承認
3. **それ以外はすべて分類器へ行く**
4. 分類器がブロックすると Claude は理由を受け取って代替を試す

つまり `mkdir` のように**どのルールにも当たらないコマンドは、毎回分類器の判断待ちになる**。
そして決定的なのが次の2点である。

- **auto mode に入るとき、広すぎる allow ルールは落とされる**（原文: 「On entering auto
  mode, broad allow rules that grant arbitrary code execution are dropped」。対象は
  `Bash(*)` / `PowerShell(*)`、`Bash(python*)` のようなワイルドカード付きインタプリタ、
  パッケージマネージャの run、`Agent`、`Monitor`）。**人間の
  `~/.claude/settings.json` の `allow` 先頭に入っている `"Bash"` はこれに該当し、
  auto mode では効いていない。** 「allow に積んだのに毎回聞かれる」の一因がこれである。
  一方 `Bash(npm test)` のような**狭いルールは効き続ける**
- **分類器が3回連続または累計20回ブロックすると auto mode が一時停止し、通常の
  プロンプトに戻る**（原文: 「if the classifier blocks an action 3 times in a row or 20
  times total, auto mode pauses and Claude Code resumes prompting」）。無人ペインは
  ここで確実に死ぬ

**対策はフックでも `ask` の絞り込みでもなく、「狭い `allow` ルールを置くこと」**である。
allow に一致すれば評価順1で即決し、分類器を通らない。孫5 の守備範囲に含める。

実測（同日、司令官の巡回中）: 司令官自身が叩いた
`gh pr list ... && herdr pane list ... | python3 -c ...` という連結コマンドが
`Blocked by classifier` で弾かれた（`&&` による連結・引用符・`python3 -c` が
重なった形）。単体のコマンドに分割したら通った。

**この傘では解けないもの（孫5 が追いかけないこと）**:

- **連結コマンドや `python3 -c` を含む形が分類器に弾かれるケース。**
  狭い `allow` で表現できる形をしていない（`Bash(python*)` のような
  ワイルドカード付きインタプリタの allow は auto mode で落とされる）。対処は
  「コマンドを分割して叩く」という運用側の作法であり、設定では解けない
- **`CronCreate` のプロンプト本文が分類器に弾かれるケース**（実測: `gh pr merge` を
  含む cron 登録が `[Merge Without Review]` で拒否された）。Bash の許可ルールとは
  別の経路であり、`permissions` では表現できない。対処は人間の明示的な承認を
  プロンプト本文へ書くこと

### I. `settings.machine.json` がどこにあるか人間から見えない

**本傘の実運用中に人間が出した追加要求**（2026-09-12、逐語）:

> claude/settings.machine.json とはどのフォルダやねん

> settings.machine.json は、settings.json のデプロイ先に兄弟ファイルとしてシムリンク
> 張るべきだと思うわ。わかりにくい

> 傘に足したほうがいいね。あと、example を一緒に貼るんじゃなくて、なければ空っぽのものを
> 作って symlink すればいいのかなと思ったけどね

**傘に足すことは人間が決めている。** 採否は司令官の判断事項ではない。

背景3-B で扱った時限爆弾（`deny: Bash(git merge *)`）に人間が自力でたどり着けなかったのが
この要求の発端である。`claude/settings.machine.json` は git 非追跡のうえ、**実在するのが
`master` ワークツリー1箇所だけ**で、その場所は `claude/README.md` にしか書かれていない。
生成物である `~/.claude/settings.json` の隣に置かれていれば、人間は自分の設定を
その場で見つけて直せる。

司令官が起草時に確認した実測（2026-09-12）:

- `links_for_tool()` の `claude)` arm は `$HOME/.claude/CLAUDE.md` と
  `$HOME/.claude/hooks/git-guard.sh`（孫1 が追加）の2件。machine.json は無い
- `state_files_for_tool()` の arm は `nvim` のみ
- `uninstall.sh` には `KNOWN_GENERATED_claude` が定義済み。したがって
  `links_for_tool()` への追加を忘れても「No link list defined」ガードは**発火せず**、
  警告なしに撤去漏れする（ルート `AGENTS.md`「実装時の注意」に既出の罠）
- `detect_state_writeback()` は `[ -f "$gen_file" ] && [ -f "$src_file" ]` の
  **両方が存在するときだけ**比較する。片側にしか無いファイルは黙って無視される
- `claude/settings.machine.json.example` の中身は `"allow": ["Bash", "Read", "Edit",
  "WebFetch", ...]` という全許可と、存在しないパス `/path/to/your/hook.sh` を指す
  `SessionStart` フック。**これを自動配布すると、この傘で締め直した権限が無効化され、
  壊れたフックが毎セッション走る。** 人間も example ではなく空ファイル案を選んでいる

### F. ペインの起動コマンドに permission-mode が渡っていない

`bin/ocw:12-14`:

```sh
COMMANDER_COMMAND="${OCW_COMMANDER_COMMAND:-claude}"
IMPLEMENTER_COMMAND="${OCW_IMPLEMENTER_COMMAND:-claude}"
REVIEWER_COMMAND="${OCW_REVIEWER_COMMAND:-claude}"
```

既定は素の `claude`。上書き用の環境変数は `ocw help env` に document されているが、
`zsh/` 配下に `OCW_` の記述は1件も無く、既定値を置く導線が存在しない。無人で回る孫の
implementer / reviewer は既定モードで起動するため、settings で弾かれた時点で
押す人がおらず固まる。

**司令官の判断: F はこの傘の孫にしない。** 理由は「スコープ外」の節に記す。

### G. 無人ペインを止めるのは git 操作だけではない（`chmod +x`）

**本傘の実運用中に人間が観測した追加の穴**（2026-09-12、孫1 の実装中に報告された）:

> 実際この傘の孫でもよく起きてるが、chmod+x で詰まることがある

`claude/settings.json` の `ask` に `Bash(chmod *)` が**丸ごと**入っている。孫が
新しいスクリプト（`claude/hooks/git-guard.sh` `tests/*.sh` など）を作れば必ず
`chmod +x` するので、**無人の孫ペインがそこで固まる**。押す人間がいないという点で
A〜E とまったく同じ構図であり、原因が git 操作でないだけである。

同じ形の穴は他にもある。`ask` に入っているもののうち、無人の孫が正当な作業の過程で
踏みうるのは次のあたり:

- `Bash(chmod *)` — 新規スクリプトへの実行ビット付与（**実測で発生**）
- `Bash(rm -r *)` / `Bash(rm -rf *)` — セッションの scratchpad ディレクトリの後片付け
  （`mktemp -d` で作った一時ディレクトリの削除で止まる、という別件の実測がある）

**この傘の孫2 で実際に発生した（2026-09-12、司令官が巡回中に観測）。** 孫2 の
implementer が `HOME` を `mktemp -d` へ差し替えたサンドボックスで deploy を検証し、
その後片付け `rm -rf "$SBX" "$SBX2"` が `Bash(rm -rf *)` に当たって `blocked` で停止した。
**サンドボックス検証は AGENTS.md が要求している正規の手順**（実 `$HOME` を汚さないための
唯一の方法）であり、その後片付けで無人ペインが止まるのは、まさに孫5 が解くべき形である。
なお同じ巡回で、司令官自身の `gh pr list ... && herdr pane list ...` という連結コマンドも
auto mode の分類器に弾かれた（連結や引用符を含むコマンドは弾かれやすい）。

`chmod` も `rm -r` も、**危険かどうかは「対象がどこにあるか」で決まる**。
`chmod +x` がリポジトリのワークツリー内のファイルに掛かるのと、`/usr/bin` 配下や
`-R` で広範囲に掛かるのとでは意味がまるで違うが、`Bash(chmod *)` という
1本のパターンは両者を区別できない。**設計1 で git 操作について述べたのと同じ理由で、
これもガードフックの仕事である**（孫5）。

**`rm -r` を孫5 に含めるかどうかは人間が確定させた**（司令官が「やりすぎなら削る」と
確認したのに対する回答。逐語）:

> 巻き込んでいい。特にフォルダ単位で制限してあるならなおさら

つまり**「対象フォルダで縛る」という形そのものが許容の根拠**である。レビューで
「`rm -r` まで緩めるのは危険では」と指摘された場合、線引きを勝手に狭めるのではなく、
この決定と「scratchpad 配下に解決されるときだけ」という制限を示すこと。
制限の**範囲を広げる**（ワークツリー内も allow にする等）のは別の話であり、
それは人間の決定を得ていない。

## 背景4: 実測値

2026-09-12 時点、WSL2（Linux 6.6.87.2-microsoft-standard-WSL2）で計測。

- `~/.claude/settings.json` mtime: **2026-09-12 01:09**
- `claude/settings.machine.json` mtime: 2026-08-04 12:36（**main ワークツリー側にのみ実在**）
- `claude/settings.json` mtime: 2026-08-02 12:29
- 最後の deploy: `~/.local/share/dotfiles/current` → `generations/20260908T055729-84543ae`（2026-09-08）

→ `~/.claude/settings.json` は**最後の deploy より後に手で書き換えられている**。
machine.json は `git merge` を `deny` に置いているのに、生成物側では `ask` に移動して
`git merge --ff-only` の allow が2件足されている。deploy の外で（おそらく
`/permissions` か `update-config` 経由で）AI か人間が編集した跡であり、**次の deploy で
確実に失われる**。B の時限爆弾はこの実測で裏付けられている。

司令官が起草時に追加で確認した値:

- `git worktree list` は `master` と `autopilot-permissions` の2本。
  `claude/settings.machine.json` が実在するのは `master` 側だけ（4010 バイト）
- 現行の世代 `20260908T055729-84543ae` の中には machine.json が入っている
  （`cp -a` 時点の main ワークツリーの内容）
- 追跡されている `claude/settings.json` の `permissions` は `deny` 24件・`ask` 20件・
  `allow` なし。`defaultMode` は `acceptEdits`
- `~/.claude/settings.json` の `allow` は40件。うち大半が LoRA 学習まわりの
  1回限りのコマンド。恒久的に意味があるのは `Bash(git checkout *)` `Bash(git fetch *)`
  `Bash(git branch *)` `Bash(git ls-remote *)` `Bash(bundle exec *)` 程度

## 背景5: 決定的な制約

ルート `AGENTS.md`「最重要ルール」より（この傘の作業に直接効くもの）:

- **人間の明示的指示がない限り、`git merge` / `git pull` / `git reset --hard` /
  `git push --force` / `gh pr merge` を実行しない。例外はない。**
  （※この傘は「そのルールをどう書き換えるか」を扱うが、**作業中の AI 自身は現行の
  ルールに従う**。ルールの書き換え＝ファイルの編集であって、実行の許可ではない）
- **deploy スクリプト（`deploy-all.sh` / `uninstall.sh` / `*/deploy.sh`）を実オペレーションで
  実行しない。** 動作確認は `deploy-all.sh --dry-run` か `tests/deploy_smoke.sh`
  （`HOME` を一時ディレクトリへ差し替えたサンドボックス）で行う。
  `--status` は副作用が無いので実 `$HOME` に対して実行してよい。
  `--rollback` / `--dev` は実 `$HOME` に対して `--dry-run` 無しで実行しない。
- **linter の抑制ディレクティブ・除外設定・閾値緩和を AI の判断で追加しない。**
- `shared/helpers.sh` は POSIX sh。bashism を書かない。
- `claude/CLAUDE.md`（配布物）は指示が無い限り編集しない。`codex/` `opencode/` も
  同じ実体を symlink しているため影響が3エージェントへ及ぶ（ADR DOC-2609072334）。

この傘に固有の制約:

- **`claude/settings.machine.json` は git 非追跡のマシン固有ファイル**である。
  リポジトリの変更として扱えない。**孫はこのファイルを編集しない**（PR の diff に
  乗らない変更を人間が知らないうちに受け取ることになるため）。B を解くための
  machine.json 側の編集は、手順を文書化して人間に実行してもらう
- **`~/.claude/settings.json` は人間の実環境の設定である。孫はこれを書き換えない。**
  検証は `deploy-all.sh --dry-run` と `tests/deploy_smoke.sh` のサンドボックス、
  および生成された JSON の内容比較で行う
- **許可ポリシーを緩める変更なので、レビューで安全性が争点になる。**
  「`main`/`master` へのマージは人間」という線引きだけは絶対に崩さない設計にすること

---

## 設計: 司令官が確定させた方針

以下は司令官が本傘の設計として確定させたものであり、**孫が勝手に覆さない**。
technically 成立しないと判明した場合は、実装を進める前に司令官へ報告すること。

### 設計1: 線引きの担保はパターンではなくガードフックで行う

**パターンマッチだけでは「`main`/`master` へのマージ」を判別できない。** 理由:

- `gh pr merge 123 --squash` のコマンドラインに **base ブランチは現れない**。
  base は PR 側の属性であり、`gh pr view <N> --json baseRefName` を引かないと分からない
- `git push --force-with-lease` は refspec を省略できる。省略時の対象は
  「現在のブランチ」であり、これもコマンドラインには現れない
- `Bash(git push *--force*)` は `--force-with-lease` にも一致する。`allow` を足しても
  `ask` が勝つ（deny > ask > allow）ため、パターンだけで「lease 付きは許す」を表現できない

したがって、**`claude/hooks/git-guard.sh`（PreToolUse フック）が線引きの一次的な担保**に
なる。判定は次のとおり。

| 対象コマンド | 判定 |
|---|---|
| `gh pr merge`（PR 番号 / URL / 省略＝現ブランチ） | base を解決し、保護ブランチなら **deny**、それ以外は **allow** |
| `git push` に `--force` / `--force-with-lease` / `-f` / `+<refspec>` が付く | 対象ブランチを解決し、保護ブランチなら **deny**。それ以外は `--force-with-lease` を **allow**、裸の `--force` / `-f` は **ask** |
| `git merge`（マージ先＝現在のブランチ） | 現在のブランチが保護ブランチなら **deny**、それ以外は **allow** |
| 上記以外 | 何も言わない（既存の permissions に委ねる） |

- **保護ブランチは `main` と `master`。** 定義はフック内の1箇所に集約する
- **判定できなかったら `ask` に倒す（fail-safe）。** PR 番号が解決できない・`gh` が
  失敗した・現在のブランチが取れない・`&&` や `;` で複数コマンドが連なっていて
  対象を一意に特定できない、のいずれも `ask`。**`allow` に倒すことは絶対にしない**
- **フックが配布されていない／壊れている環境で黙って通らないこと。** そのため
  `claude/settings.json` の `ask` は**保険として残す**（設計2）

### 設計2（**2026-09-12 訂正**): フックは制限を足せるだけ。`ask` は「フック不在でも止めたいもの」だけを残す

> **この節は孫1 の実装中に技術的前提が崩れたため書き直された。** 当初は「フックが
> `allow` を返せば `permissions.ask` を素通りできる」という二層構造を想定していたが、
> **それは成立しない**。孫1 のレビューで発覚し、司令官が公式ドキュメント
> （<https://code.claude.com/docs/en/permissions.md>）の原文で確認した。
> 訂正前の記述に依拠した実装・レビューコメントは、この節の内容で読み替えること。

確認できた契約（原文ママ）:

> Hook decisions don't bypass permission rules. Claude Code evaluates deny and ask rules
> regardless of what a PreToolUse hook returns: a matching deny rule blocks the call, and a
> matching ask rule still prompts even when the hook returned `"allow"` or `"ask"`.

> A blocking hook also takes precedence over allow rules. A hook that exits with code 2 stops
> the tool call before permission rules are evaluated (...). **To run all Bash commands without
> prompts except for a few you want blocked, add `"Bash"` to your allow list and register a
> PreToolUse hook that rejects those specific commands.**

つまり **PreToolUse フックは制限を「足す」ことしかできない。** `ask` / `deny` を緩める
方向には一切効かない。したがって本傘の構造はこうなる。

- **AI に摩擦なくやらせたい操作は、`ask` / `deny` のどのパターンにも一致してはならない。**
  その操作の安全性は**フックだけ**が担保する
- **`permissions.ask` に残すのは「フックが不在でも無条件に止めたいもの」だけ**にする。
  条件つき（ブランチ次第・パス次第）で許すものを `ask` に置いてはいけない。置いた瞬間、
  フックが何を返しても止まる
- フックの役割は「危険な部分集合を `ask` / `deny` へ引き上げること」。ドキュメントが
  推奨している形（allow に `Bash` を置き、フックで個別に弾く）と同じ構造であり、
  実際に人間の `~/.claude/settings.json` の `allow` には既に `"Bash"` が入っている

#### `git push --force-with-lease` を摩擦なく通すための具体策

`permissions` のパターンは `*` のみだが、**空白の有無を厳密に区別する**（原文:
「A `*` in a Bash rule matches any text, including spaces」「**The space before a trailing
`*` is part of the rule.**」）。これを使って「裸の `--force` だけ」を単語境界で拾える。

- **削除する**（どちらも `--force-with-lease` に一致してしまうため。`*--force*` は
  空白を挟んでいないので `--force-with-lease` の中の `--force` を拾う）:
  - `"Bash(git push *--force*)"`
  - `"Bash(git push *--force-with-lease*)"`
- **代わりに置く**（裸の `--force` だけを拾う4パターン）:
  - `"Bash(git push --force)"` / `"Bash(git push --force *)"`
  - `"Bash(git push * --force)"` / `"Bash(git push * --force *)"`
- **残す**: `"Bash(git push -f*)"` `"Bash(git push * -f*)"` `"Bash(git push *+*)"`
  `"Bash(git push *--delete*)"`（いずれも `--force-with-lease` には一致しない。
  `* -f*` が要求する「空白 + `-f`」は `--force-with-lease` の中に現れない）
- **足す**（フックが不在でも効く、ブランチ名の形をした残余の網）:
  - `"Bash(git push * main*)"` / `"Bash(git push * master*)"`
  ブランチ名を明示した保護ブランチへの push は、force かどうかに関わらず人間の仕事
  なので、ここで止まるのは正しい挙動である。孫ブランチ名には一致しない

#### 受け入れる残余リスク（ADR に明記すること）

パターンで表現できないのは「refspec を省略した `git push --force-with-lease` を、
保護ブランチをチェックアウトした状態で叩く」形である。これは**フックが唯一の担保**で
あり、フックが配布されていない／壊れている環境では素通りする（fail-open）。

受け入れる根拠: (1) フックは `claude/deploy.sh` が配り、`deploy-all.sh --status` が
リンク切れを検出する。(2) `--force-with-lease` は他人の更新を消さない。
(3) 保護ブランチをチェックアウトして作業すること自体が本傘の運用では例外的である。

#### 変わらない部分

- 追跡されている `claude/settings.json` に `Bash(git merge *)` を**足さない**
  （フックが判定するため。生成物側に手で入っている1件は、人間が machine.json の
  移行と併せて片付ける）
- フックの配線は `claude/settings.json` の `hooks.PreToolUse` に書く。
  コマンドは `$HOME` を使った絶対パス（`"$HOME/.claude/hooks/git-guard.sh"`）にし、
  マシン依存の絶対パスを追跡ファイルへ焼き込まない
- **`claude/settings.machine.json` が `hooks` を持つ場合、`claude/deploy.sh` のマージは
  `hooks` を浅い `update()` で扱う。** イベント名が異なれば共存する（実測では machine 側は
  `SessionStart` のみ）が、machine 側が `PreToolUse` を定義するとベース側を丸ごと
  上書きする。この落とし穴は ADR に明記する

### 設計3: 学習した `allow` は deploy が保全する

`claude/deploy.sh` の settings 生成に、**既存 `~/.claude/settings.json` の
`permissions.allow` を第3の入力として加える**（base → machine → 既存 allow の順に
重ね、重複は除く）。

- **保全するのは `allow` だけ。** `ask` / `deny` / それ以外のキーは保全しない
  （手で足された `ask` を永久に引きずると、まさに今回の A の状態が固定化する）
- **安全性の根拠**: 優先順位は deny > ask > allow なので、保全された `allow` が
  base / machine の `deny` / `ask` を弱めることはない
- `--dry-run` では「何件保全するか」を出力する
- machine.json が存在しない経路（本傘のワークツリーからの deploy）でも同じ保全が働くこと。
  背景3-B の追検証のとおり、machine.json はワークツリーごとに在ったり無かったりする

**machine.json の `deny: git merge` 2行の削除は人間が行う。** 孫は削除手順を
`claude/README.md` に書くところまでを担当する。

### 設計4: 文言レイヤの軸は「`main` は人間 / 傘配下は AI」

ルート `AGENTS.md` と `templates/repo-baseline/template/AGENTS.md.jinja` の最重要ルールを、
禁止コマンドの列挙から**対象ブランチによる線引き**へ書き直す。骨子:

- `main` / `master` を書き換える操作（マージ・push・force push）は人間だけが行う。例外はない
- 傘ブランチ配下（孫→傘のマージ、傘の中での rebase、孫ブランチへの
  `--force-with-lease`）は AI が行ってよい。ただし孫→傘のマージはレビュー承認済みの
  PR に限る
- `git pull` は使わない。追随は `git fetch origin` + `git merge --ff-only origin/<branch>`、
  孫を傘へ追随させるときは `git rebase origin/<傘>` + `git push --force-with-lease`
- `git reset --hard` / `git clean` / 裸の `git push --force` は引き続き人間の承認が要る

**両ファイルで同じ軸・同じ用語を使うこと。** テンプレートは他リポジトリへ撒かれるので、
リポジトリ固有の前提（dotfiles の deploy など）を混ぜない。

### 設計5: スキルの傘例外は「base が傘ブランチの PR に限る」形で書く

- `skills/pr-review-loop/SKILL.md`: 最優先ルールに例外を1つ足す。
  「base が**リポジトリの既定ブランチ（`main` / `master`）である PR** は、承認されても
  AI がマージしない」を残したうえで、「base が傘ブランチの PR は、レビュー承認済みなら
  AI がマージしてよい」を明記する。判定は `gh pr view <N> --json baseRefName` で行う
- `skills/umbrella-orchestrator/SKILL.md`: §6「司令官がやらないこと」から
  「PR マージ（人間の仕事）」を、§3.5 の `/autopilot` 手順5 と整合する形へ書き直す。
  孫用プロンプト雛形の手順4（「人間に依頼する」）も同様
- 併せて、スキル内に残る `git pull --rebase` を fetch + rebase / merge --ff-only へ置き換える

### 設計6: `settings.machine.json` は世代を経由させず、マシン固有の固定パスに置く

背景3-I の要求（`~/.claude/settings.json` の兄弟として symlink する）を満たす置き方は
2つある。**司令官は後者を採る。**

**案A（却下）: ソースツリーの `claude/settings.machine.json` を世代経由で symlink する。**
`nvim/lazy-lock.json` と同じ「状態ファイル」の型に乗せ、`state_files_for_tool()` に
`claude)` arm を足し、書き戻しは `--adopt-state` で取り込む。

却下の理由は**この傘が実際に踏んだバグを悪化させる**こと。背景3-B の追検証のとおり、
machine.json は git 非追跡なので**ワークツリーごとに在ったり無かったりする**。案A で
「無ければ空の `{}` を作る」を deploy に足すと、**machine.json を持たないワークツリー
（＝この傘や孫のワークツリー）から deploy した瞬間に空ファイルが正となり**、人間の
`hooks`（herdr のエージェント状態フック）と `additionalDirectories` が消える。
孫2 の allow 保全は `allow` しか救わないので、これは実害のある退行である。

**案B（採用）: canonical prefix 直下の固定パスに実体を置く。**

- 実体: `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/settings.machine.json`
  （`current` や `generations/` と同じ階層。**世代の中には入れない**）
- `~/.claude/settings.machine.json` はこの固定パスへの symlink
- `claude/deploy.sh` の settings 生成は、machine 設定をこの固定パスから読む
- 無ければ deploy が `{}` を作る（**`--dry-run` では作らない**）

案B が優れている点:

- **ワークツリーをまたいで1つ。** どのワークツリーから deploy しても同じ machine 設定に
  なる。背景3-B の追検証で見つけた「傘から deploy すると machine.json ごと消える」が
  原理的に消滅する
- **人間が symlink 経由で編集した内容がそのまま残る。** 世代を経由しないので
  `state_files_for_tool()` / `--adopt-state` の機構が要らない（案A は編集のたびに
  「書き戻し検知 → adopt」を人間に強いる）
- **世代のロールバックで machine 設定が巻き戻らない。** machine 設定は配布物ではなく
  マシン固有の設定なので、`--rollback` の対象外であるほうが正しい

案B で必ず扱うこと:

- **移行**: 既存の `master` ワークツリーの `claude/settings.machine.json`（実在。4010バイト）を
  固定パスへ移す。deploy が自動移行してよいが、**何をどこへ移したかを必ずログに出す**。
  固定パスとソースツリーの両方に存在して内容が異なる場合は、勝手にどちらかを採らず
  警告して停止する
- **`uninstall.sh`**: `~/.claude/settings.machine.json` の symlink は撤去する。
  **固定パスの実体は消さない**（人間のマシン設定であり、この傘の配布物ではない）。
  その結果 prefix が空にならないので、既存の「空になった prefix を消す」処理が
  それを許容するか確認し、必要なら明示的に扱う
- **`links_for_tool()` の `claude)` arm に追加する。** 忘れても
  `KNOWN_GENERATED_claude` があるため `uninstall.sh` は警告なしに撤去漏れする（背景3-I）
- **`settings.machine.json.example` は配布しない。** 中身が全許可と壊れたフックであり、
  撒くとこの傘の成果を無効化する（背景3-I）。空の `{}` を作るだけにする

---

## スコープ外

- **sheaf / lora-dataset-forge のリポジトリ側変更（背景3の C / D の適用）。**
  この傘が確定させたポリシーを受けて、各リポジトリの単発 PR として別途行う。
  傘の孫にしない（人間の決定事項）
- リポジトリ横断の「総司令官」機構の新設。作らないと決まっている
- `herdr` 本体の変更
- 既存 ADR の書き換え（必要なら新しい ADR を足す）
- **背景3-F（`OCW_*_COMMAND` の既定導線）。** 司令官の判断で孫にしない。理由:
  孫1〜4 が効けば、無人ペインが止まる原因そのものが消える。permission-mode を
  緩めるのは「線引きを機械的に担保する」方針と逆行し、`--dangerously-skip-permissions`
  相当へ近づく。**孫1〜4 の完了後もまだ止まるようなら、そのとき別傘で扱う。**
  暫定回避が要る場合は `OCW_IMPLEMENTER_COMMAND` / `OCW_REVIEWER_COMMAND` を
  人間がその場で export すればよく、リポジトリの変更は要らない
  （**孫5 で背景3-G を扱うのは、これとは別の話である**。孫5 は permission-mode を
  緩めるのではなく、判定をフックへ移して「安全なものだけ通す」を増やす側）
- `claude/settings.machine.json` そのものの編集（git 非追跡。人間が行う）
- `~/.claude/settings.json` の直接編集（人間の実環境）

## 必須の検証ステップ

ルート `AGENTS.md`「コミット前の必須ステップ」より、この傘に関係するもの。**孫はこれを
省略しない。**

- `pre-commit run --all-files`（`shellcheck` / `shfmt` / `check-json` /
  `doc-id check` / `doc-id verify` ほか）
- シェルスクリプト（`claude/deploy.sh` `shared/helpers.sh` `uninstall.sh` 等）を
  変更した場合: **`tests/deploy_smoke.sh`**
- `templates/repo-baseline/` 配下を**どのファイルでも**変更した場合:
  **`tests/template_smoke.sh`**（`.jinja` は `check-yaml` の対象外なので、YAML の壊れも
  Markdown の崩れもこのテストでしか検出できない）
- `bin/` 配下を変更した場合: `python3 -m unittest discover -s bin/tests -v`
  （193件・約40秒。pre-commit には入っていない）
- `docs/` に新規ファイルを追加する場合: ルート `AGENTS.md` の採番手順に従い、
  予約リテラル `DOCID_PLACEHOLDER` を使った仮ファイル名
  （`DOC-<予約リテラル>_<説明的ファイル名>.md`）で作り、
  `./tools/doc-id/doc-id assign <path>` で採番する。**地の文の言及にも
  DOC-ID を追記する**（採番ツールはファイル名・リンク先パスと、
  そのファイル自身の本文中のプレースホルダしか置換しない）
- PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読む

## 実装完了条件

1. 孫1〜6 の PR がすべて傘ブランチへマージ済み
2. `pre-commit run --all-files` / `tests/deploy_smoke.sh` / `tests/template_smoke.sh` が通る
3. 傘→`master` の PR に、**人間が deploy 前に行う移行手順**（machine.json の
   `deny: git merge` 2行の削除、生成物側に手で入った `ask` の扱い）が明記されている

---

## 孫1用プロンプト: 許可ポリシーの確定とガードフックの新設

````
# 孫1: 許可ポリシーの確定と git ガードフックの新設

あなたはこの孫ブランチの実装 AI です。計画書
`docs/planning/DOC-2609121700_autopilot-permissions_計画.md`
（本プロンプトの出典。背景1〜5と「設計」節を必ず読むこと）に基づいて実装してください。

## ゴール

「**`main` / `master` へのマージ・push は人間、それ以外の git 操作は AI に任せる**」
という線引きを、**機械的に担保する**仕組みを dotfiles 側に作る。

## やること

### 1. ADR を書く

`docs/adr/` に ADR を新規作成する。説明的ファイル名は
`git-operation-permission-policy` とし、ルート `AGENTS.md` の採番手順どおり
予約リテラル `DOCID_PLACEHOLDER` を使った仮ファイル名で作ってから
`./tools/doc-id/doc-id assign <path>` で採番すること。書く内容:

- 決定: 保護ブランチ（`main` / `master`）への破壊的操作だけを人間に残し、
  それ以外の git 操作は AI に許す。担保は PreToolUse フックで行う
- **なぜパターンマッチでは足りないか**（計画書「設計1」の3点。`gh pr merge` の
  コマンドラインに base が現れない／`git push --force-with-lease` は refspec を
  省略できる／`Bash(git push *--force*)` が lease 付きにも一致し `allow` で
  覆せない）。実際にコマンドを叩いて確認した結果を根拠として書くこと
- フックと `permissions` の二層構造（フックが `allow` したものだけ素通り、
  フックが黙っているものは従来どおり `ask`）とその fail-safe 性
- `claude/settings.machine.json` が `hooks.PreToolUse` を定義するとベース側を
  上書きしてしまう落とし穴（`claude/deploy.sh` の浅い `update()` 由来）
- 却下案: (a) `permissions` のパターンだけで表現する、(b) 孫ペインを
  `--dangerously-skip-permissions` 相当で起動する、(c) すべて人間が押す（現状）。
  それぞれ却下理由を書く
- `docs/README.md` の「全 DOC-ID 索引」の `adr/` 表にも行を追加する

### 2. `claude/hooks/git-guard.sh` を新設する

PreToolUse フックとして動く POSIX sh スクリプト。標準入力から Claude Code が渡す
JSON を受け取り、判定結果を標準出力へ返す。

**実装に着手する前に、PreToolUse フックの入出力契約（stdin の JSON スキーマ、
`hookSpecificOutput.permissionDecision` の値、終了コードの意味、`matcher` の書式）を
必ず一次情報で確認すること。** 確認手段は `claude-code-guide` サブエージェント
（Task ツール）または公式ドキュメント。**記憶で書かない。** 確認した内容と、
どのバージョンの Claude Code で確認したかを ADR に残すこと。

判定表（計画書「設計1」より。ここを勝手に変えない）:

| 対象 | 判定 |
|---|---|
| `gh pr merge`（PR 番号 / URL / 省略＝現ブランチ） | base を `gh pr view --json baseRefName` で解決。保護ブランチなら deny、それ以外は allow |
| `git push` に `--force` / `--force-with-lease` / `-f` / `+<refspec>` | 対象ブランチを解決（明示 refspec が無ければ現在のブランチ）。保護ブランチなら deny。それ以外は `--force-with-lease` を allow、裸の `--force` / `-f` は ask |
| `git merge` | 現在のブランチ（＝マージ先）が保護ブランチなら deny、それ以外は allow |
| 上記以外 | 何も出力せず終了（既存の permissions に委ねる） |

必須の性質:

- **保護ブランチの定義はスクリプト内の1箇所**（`main` と `master`）
- **判定できなければ `ask`。** PR 番号が解決できない・`gh` が失敗した・
  現在のブランチが取れない・`&&` `;` `|` などで複数コマンドが連なっていて
  対象を一意に特定できない、のいずれも `ask` に倒す。**`allow` に倒さない**
- **速い経路を先に置く。** 標準入力に `git merge` / `git push` / `gh pr merge` の
  いずれの字面も含まれなければ、JSON をパースせずに即 exit する（このフックは
  すべての Bash 呼び出しで走るため）
- JSON のパースが要る箇所は `python3` を使ってよい（`claude/deploy.sh` に前例がある）。
  シェル側は POSIX sh。`docs/design/DOC-2608020715-a_シェルスクリプトコーディング方針.md`
  に従う
- `deny` / `ask` を返すときは、人間が読んで理由が分かる `permissionDecisionReason` を付ける

### 3. 配布の配線

- `claude/deploy.sh` が `claude/hooks/git-guard.sh` を
  `~/.claude/hooks/git-guard.sh` へ symlink する（`symlink_backup` 経由。
  `~/.claude/hooks/` には dotfiles 由来でないフック（`herdr-agent-state.sh`）が
  既に居るので、**ディレクトリごとではなくファイル単位で張る**）
- `shared/helpers.sh` の `links_for_tool()` の `claude` arm に
  `$HOME/.claude/hooks/git-guard.sh` を追加する（`uninstall.sh` と
  `deploy-all.sh --status` の両方がここを一次情報源にしている）
- `claude/settings.json` に `hooks.PreToolUse` を追加し、`"$HOME/.claude/hooks/git-guard.sh"`
  を呼ぶ。matcher は Bash ツールに限る。`timeout` を適切に設定する
  （`gh pr view` のネットワーク往復が入るため）
- `claude/settings.json` の `ask` は**設計2（訂正版）のとおりに書き換える**。
  `Bash(git push *--force*)` と `Bash(git push *--force-with-lease*)` を削除し、裸の
  `--force` を拾う4パターンとブランチ名の形の網（`* main*` / `* master*`）を足す。
  **フックの `allow` は `ask` を素通りさせられない**ので、消さないと目的を達成できない
- `claude/README.md` にフックの節を足す（何を止めて何を通すか、無効化したいときどうするか）

### 4. テスト

`tests/git_guard_test.sh` を新設する。フックに JSON を流し込んで判定を突き合わせる形。
`tests/deploy_smoke.sh` と同じく、実 `$HOME` を汚さないこと。
`gh` / `git` の呼び出しは `PATH` の先頭にスタブを置くなどして固定する
（ネットワークに出ない。実リポジトリの状態に依存しない）。

## 検証方針

以下の重要な behavior / regression risk が、自動テストによって保護されていること。

- **base が `main` / `master` の PR に対する `gh pr merge` が deny されること。**
  **この regression は必ず自動テストで固定する**（本傘の唯一の線引きであり、
  ここが崩れると傘全体の前提が壊れる）
- **判定できない入力（PR 番号が解決できない、`gh` が失敗する、複数コマンドの連結、
  現在のブランチが取れない）が `allow` に倒れないこと。**
  **この regression は必ず自動テストで固定する**
- base が傘ブランチ（保護ブランチ以外）の PR に対する `gh pr merge` が allow されること
- 保護ブランチ以外への `git push --force-with-lease` が allow され、保護ブランチへの
  それが deny されること
- 裸の `git push --force` / `-f` が（保護ブランチ以外でも）allow されないこと
- 保護ブランチ上での `git merge` が deny され、それ以外のブランチでは allow されること
- git / gh と無関係なコマンドでフックが何も出力せず、既存の permissions の判断を
  邪魔しないこと
- `deploy-all.sh --status` と `uninstall.sh` が新しい symlink を認識すること
  （`links_for_tool()` への追加漏れの検出。`tests/deploy_smoke.sh` で担保できる）

各項目と test example を1対1対応させる必要はない。複数の条件を1つの scenario で
検証してよい。既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## やらないこと

- `~/.claude/settings.json`（人間の実環境）を書き換えない
- `claude/settings.machine.json`（git 非追跡）を編集しない
- `deploy-all.sh` / `*/deploy.sh` を実オペレーションで実行しない
  （`--dry-run` と `tests/deploy_smoke.sh` のサンドボックスのみ）
- `bin/ocw` の起動コマンド既定値には触らない（この傘のスコープ外）
- linter の抑制ディレクティブ・除外設定を足さない

## コミット前に必ず実行する

```
pre-commit run --all-files
tests/deploy_smoke.sh
tests/git_guard_test.sh
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PR を作成する。**PR の向き先は必ず `autopilot-permissions` にすること。
   `master` には絶対に出さない。**
2. `/pr-review-loop` を起動する（PR がない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewer は done 状態で完了し完了通知は来ないので、待機して停止せず
`gh pr view` をポーリングしてレビューの有無を確認してください。

## ブランチ作成時の注意（最重要）

このワークツリーは `ocw` が傘ブランチ `autopilot-permissions` から切った孫ブランチ上で
起動している。実装前に `git branch --show-current` で自分のブランチ名を確認し、
`git log --oneline origin/autopilot-permissions..HEAD` が空であることを確かめること
（＝傘の先頭から分岐した直後）。`master` から切られていたら、その時点で作業を止めて
司令官へ報告すること。PR の diff に傘ブランチ全体が混入するとレビュー不能になる。
````

## 孫2用プロンプト: 学習した allow を deploy 越しに保全する

````
# 孫2: 学習した allow が deploy で揮発する問題の解消

あなたはこの孫ブランチの実装 AI です。計画書
`docs/planning/DOC-2609121700_autopilot-permissions_計画.md`
（背景3-B、背景4、設計3 を必ず読むこと）に基づいて実装してください。

## 問題（計画書 背景3-B より）

`~/.claude/settings.json` は `claude/deploy.sh` が生成する**実ファイル**であり、
Claude Code が対話で学習した `permissions.allow` を書き戻す先でもある。ところが
学習結果を追跡側（`claude/settings.json`）や machine 側
（`claude/settings.machine.json`）へ還流させる経路が存在しないため、
**次の deploy で学習した allow が丸ごと消える**（`.backup` には退避されるが、
人間が手で拾い直さない限り戻らない）。

さらに `claude/settings.machine.json` は git 非追跡なので**ワークツリーごとに
在ったり無かったりする**。実測（2026-09-12）では main ワークツリーにだけ存在し、
傘のワークツリーには無かった。傘や孫のワークツリーから deploy すると
machine.json ごと落ちる。

## やること

### 1. `claude/deploy.sh` の settings 生成に「既存 allow の保全」を足す

生成の入力を3つにする: ベース（`claude/settings.json`）→ machine
（`claude/settings.machine.json`。存在すれば）→ **既存の生成物
（`$HOME/.claude/settings.json`）の `permissions.allow`**。

- **保全するのは `permissions.allow` だけ。** `ask` / `deny` / その他のキーは保全しない。
  手で足された `ask` を引きずると、計画書 背景3-A の状態（`ask` が `allow` を
  握りつぶす）が永久に固定化する
- 重複は除く。順序は「ベース・machine 由来 → 保全分」
- 既存の生成物が無い / 壊れた JSON / `permissions.allow` が無い場合は、
  保全せずに従来どおり生成する（**deploy を失敗させない**）
- machine.json が無い経路（今まさに傘のワークツリーがそうである）でも同じ保全が働くこと。
  現状のコードは machine.json の有無で分岐が丸ごと分かれているので、
  保全処理が片方の枝にしか入らない書き方をしないこと
- `DRY_RUN=1` のときは「何件保全するか」をログに出す。実ファイルは触らない

**なぜ安全か**（README と PR 説明文に書くこと）: 優先順位は deny > ask > allow なので、
保全された `allow` がベース／machine の `deny` / `ask` を弱めることはない。

### 2. `claude/README.md` の追随

- 「学習した allow は deploy 越しに保全される」ことと、その限界
  （`ask` / `deny` / `hooks` は保全されない → machine.json に書くこと）
- **人間向けの移行手順**（この傘のマージ後、次の deploy の前に人間が行う）:
  - `claude/settings.machine.json` の `permissions.deny` から
    `"Bash(git merge *)"` と `"Bash(git merge --*)"` の2行を削除する。
    これを消さないと、新しいガードフック（孫1）が allow を返しても `deny` が勝ち、
    マージが完全に不能になる
  - machine.json は git 非追跡でワークツリーごとに独立しているため、
    **どのワークツリーから deploy するかで生成物が変わる**。deploy は
    machine.json を持つワークツリーから行うこと
  - 現在の `~/.claude/settings.json` に手で入っている `"Bash(git merge *)"`（`ask`）は
    保全対象外なので、次の deploy で自然に消える

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- **既存 `~/.claude/settings.json` にしか無い `allow` エントリが、deploy 後の生成物にも
  残っていること**（machine.json がある場合・無い場合の両方）
- **保全された `allow` が `deny` / `ask` を上書きしないこと**（生成物の
  `deny` / `ask` がベース + machine のとおりであること）。
  **この regression は必ず自動テストで固定する**（保全が安全でいられる唯一の根拠のため）
- 既存の生成物が無い・壊れた JSON・`permissions` キーが無い、のいずれでも
  deploy が失敗せず、従来どおりの生成物ができること
- `DRY_RUN=1` で実ファイルが一切変更されないこと（既存の `tests/deploy_smoke.sh` と
  `deploy-all.sh --dry-run` で担保できるならそれでよい）
- 冪等性: 同じ状態で2回 deploy しても生成物が変わらないこと（`allow` が
  重複して増殖しない）

各項目と test example を1対1対応させる必要はない。複数の条件を1つの scenario で
検証してよい。既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## やらないこと

- `~/.claude/settings.json`（人間の実環境）を書き換えない。検証は
  `tests/deploy_smoke.sh` のサンドボックス（`HOME` を一時ディレクトリへ差し替える）で行う
- `claude/settings.machine.json`（git 非追跡）を編集しない。**手順を README に書くだけ**
- `deploy-all.sh` / `*/deploy.sh` を実オペレーションで実行しない
- 孫1 が入れたフックの判定ロジックには触らない（衝突したら司令官へ報告）
- linter の抑制ディレクティブ・除外設定を足さない

## コミット前に必ず実行する

```
pre-commit run --all-files
tests/deploy_smoke.sh
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PR を作成する。**PR の向き先は必ず `autopilot-permissions` にすること。
   `master` には絶対に出さない。**
2. `/pr-review-loop` を起動する（PR がない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewer は done 状態で完了し完了通知は来ないので、待機して停止せず
`gh pr view` をポーリングしてレビューの有無を確認してください。

## ブランチ作成時の注意（最重要）

このワークツリーは `ocw` が傘ブランチ `autopilot-permissions` から切った孫ブランチ上で
起動している。実装前に `git branch --show-current` で自分のブランチ名を確認し、
`git log --oneline origin/autopilot-permissions..HEAD` が空であることを確かめること。
`master` から切られていたら、その時点で作業を止めて司令官へ報告すること。
````

## 孫3用プロンプト: 最重要ルールを「main は人間 / 傘配下は AI」の軸で書き直す

````
# 孫3: 最重要ルールの書き直し（ルート AGENTS.md と repo-baseline テンプレート）

あなたはこの孫ブランチの実装 AI です。計画書
`docs/planning/DOC-2609121700_autopilot-permissions_計画.md`
（背景3-D、設計4、および孫1 が確定させた ADR を必ず読むこと）に基づいて実装してください。

## 問題（計画書 背景3-D より）

`templates/repo-baseline/template/AGENTS.md.jinja` の最重要ルールが

> **人間の明示的指示がない限り、`git merge` / `git pull` / `git reset --hard` /
> `git push --force` / `gh pr merge` を実行しない。例外はない。**

となっており、この文言がテンプレート経由で各リポジトリへ撒かれている
（lora-dataset-forge の `AGENTS.md` にそのまま出ている）。傘ブランチ方式では
孫→傘のマージや孫ブランチへの `--force-with-lease` を AI が行う必要があるため、
この文言が autopilot を原理的に不可能にしている。

sheaf では人間が後から手で例外を足しているが、そこにも
「`git reset --hard` / `git push --force` は、ブランチを問わず実行しない。例外はない。」
が残っており、「孫に傘の更新を rebase して push」が禁止のままになっている。

## やること

ルート `AGENTS.md` と `templates/repo-baseline/template/AGENTS.md.jinja` の
「最重要ルール」節を、禁止コマンドの列挙から**対象ブランチによる線引き**へ書き直す。
骨子（計画書 設計4）:

- `main` / `master` を書き換える操作（マージ・push・force push）は**人間だけ**が行う。例外はない
- 傘ブランチ配下は AI が行ってよい:
  - 孫→傘のマージ（**レビューで承認済みの PR に限る**。
    `gh pr merge <PR番号> --squash --delete-branch`）
  - 傘への上流取り込み、孫ブランチの傘への追随
  - **孫ブランチ限定**の `git push --force-with-lease`
- `git pull` は使わない。追随は `git fetch origin` +
  `git merge --ff-only origin/<branch>`、孫を傘へ追随させるときは
  `git rebase origin/<傘>` + `git push --force-with-lease`
- `git reset --hard` / `git clean` / 裸の `git push --force`（lease なし）は
  引き続き人間の承認が要る

**両ファイルで同じ軸・同じ用語を使うこと。** ただし:

- テンプレート側には**このリポジトリ固有の前提を持ち込まない**
  （dotfiles の deploy 事情、`claude/hooks/git-guard.sh` の存在、DOC-ID など、
  撒かれた先に存在しないものを前提にしない）。テンプレートは
  「傘ブランチ方式を使わないリポジトリ」にも撒かれることを忘れない
- ルート `AGENTS.md` 側には、この dotfiles 自身のガードフック（孫1）が
  何を機械的に止めるかを1〜2行で触れてよい

`docs/design/DOC-2608020715_プルリクエストの作法.md` に傘・孫のブランチ構成の記述が
あるので、矛盾していないか確認し、必要なら追随する。

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- `tests/template_smoke.sh` が通ること（代表的な回答パターンで `copier copy` が
  実際にレンダリングでき、生成された Markdown に Jinja 空白制御ミスによる崩れ
  ——行ゼロの表・見出し直前の空行欠落・二重空行・Jinja 構文の残骸——が無いこと）。
  **`.jinja` は `check-yaml` の対象外であり、Markdown の崩れもこのテストでしか
  検出できない。この regression は必ずこのテストで固定する**
- `use_doc_id` / `use_ci` の各分岐で最重要ルール節が正しくレンダリングされること
- 生成物と dotfiles 自身の `AGENTS.md` で、線引きの軸と用語が食い違っていないこと
  （人間のレビューで確認する。テスト化は不要）

各項目と test example を1対1対応させる必要はない。

## やらないこと

- `claude/CLAUDE.md`（配布物。個人の口調設定が入っている）を編集しない。
  `codex/` `opencode/` も同じ実体を symlink しているため影響が3エージェントへ及ぶ
- sheaf / lora-dataset-forge 側のファイルを触らない（別リポジトリ・スコープ外）
- スキル（`skills/`）の文言は孫4 の担当。触らない
- linter の抑制ディレクティブ・除外設定を足さない

## コミット前に必ず実行する

```
pre-commit run --all-files
tests/template_smoke.sh
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PR を作成する。**PR の向き先は必ず `autopilot-permissions` にすること。
   `master` には絶対に出さない。**
2. `/pr-review-loop` を起動する（PR がない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewer は done 状態で完了し完了通知は来ないので、待機して停止せず
`gh pr view` をポーリングしてレビューの有無を確認してください。

## ブランチ作成時の注意（最重要）

このワークツリーは `ocw` が傘ブランチ `autopilot-permissions` から切った孫ブランチ上で
起動している。実装前に `git branch --show-current` で自分のブランチ名を確認し、
`git log --oneline origin/autopilot-permissions..HEAD` が空であることを確かめること。
`master` から切られていたら、その時点で作業を止めて司令官へ報告すること。
````

## 孫4用プロンプト: 配布スキルの傘例外条項と矛盾の解消

````
# 孫4: pr-review-loop / umbrella-orchestrator の傘例外条項

あなたはこの孫ブランチの実装 AI です。計画書
`docs/planning/DOC-2609121700_autopilot-permissions_計画.md`
（背景3-E、設計5、および孫1 の ADR・孫3 が書き直した `AGENTS.md` を必ず読むこと）に
基づいて実装してください。

## 問題（計画書 背景3-E より）

配布スキルの中で正面衝突している。

- `skills/pr-review-loop/SKILL.md`「安全制約」:
  「**承認されても、人間の明示的指示がない限りマージを絶対に実行しない。**
  これはこのスキルの最優先ルール。」
- `skills/umbrella-orchestrator/SKILL.md` §3.2 の孫用プロンプト雛形:
  「4. 承認されたら人間に『マージしてください』と依頼する」
- 同 §6「司令官がやらないこと」: 「PR マージ（人間の仕事）」
- ところが同 §3.5 `/autopilot` 手順5: 「判定が『承認』ならマージ:
  `gh pr merge <PR番号> --squash --delete-branch`」

**同一スキル内で矛盾している。** 孫の implementer は pr-review-loop の最優先ルールに
従って承認後に必ず人間待ちになり、司令官も §6 に従えばマージしない。autopilot が
動かない直接原因のひとつ。

さらに、`umbrella-orchestrator` の §3.2 孫用プロンプト雛形と §7
「人間が手動でPRをマージしていた場合」には `git pull --rebase origin <傘ブランチ>` が
書かれており、`AGENTS.md`（および repo-baseline テンプレート）の
「`git pull` を使わない」と衝突している。

## やること

### 1. `skills/pr-review-loop/SKILL.md`

最優先ルールに例外を1つ足す。**残す側と許す側を両方明示すること**:

- 残す: base が**リポジトリの既定ブランチ（`main` / `master`）**である PR は、
  承認されても AI がマージしない。例外はない
- 許す: base が**傘ブランチ**の PR は、レビューで承認済みならマージしてよい
  （`gh pr merge <PR番号> --squash --delete-branch`）
- 判定方法を明記する: `gh pr view <PR番号> --json baseRefName` で base を確認してから
  判断する。**base を確認せずにマージしない**
- Phase 7 の完了報告の書き方（「マージは実行していないこと」を報告する箇所）も追随させる

### 2. `skills/umbrella-orchestrator/SKILL.md`

- §6「司令官がやらないこと」の「PR マージ（人間の仕事）」を、§3.5 の `/autopilot`
  手順5 と整合する形へ書き直す（孫→傘のマージは司令官／autopilot が行う。
  傘→既定ブランチのマージだけが人間の仕事）
- §3.2 の孫用プロンプト雛形の手順4（「人間に『マージしてください』と依頼する」）を
  実態に合わせる
- スキル内に残る `git pull --rebase origin <傘ブランチ>` を、
  `git fetch origin` + `git rebase origin/<傘ブランチ>`（孫を傘へ追随させる場合）
  または `git merge --ff-only origin/<branch>`（早送りで足りる場合）へ置き換える。
  §7「人間が手動でPRをマージしていた場合」の `git stash` 手順も同様に見直す
  （**bare な `git stash` / `git stash pop` はワークツリー間で共有されるため危険**。
  一意なタグ付きの `git stash push -u -m` と `git stash apply <sha>` を使う形にするか、
  一時コミットを使う形にする）

### 3. 整合性の確認

`skills/` 配下で「マージは人間の仕事」「`git pull`」「`--force`」に言及している箇所を
`git grep` で洗い、書き換え漏れが無いことを確認する
（`skills/worktree-cleanup/` `skills/umbrella-handoff/` `skills/repo-baseline/` も対象）。
`skills/README.md` に追随が要るなら更新する。

## 検証方針

以下の重要な behavior / regression risk が、レビューまたは既存テストによって
保護されていること。

- スキル文書の中に「承認後もマージしない」と「承認後はマージしてよい」が
  **base の区別なしに併存している箇所が残っていないこと**（`git grep` の結果を
  PR 説明文に貼ること）
- 「`main` / `master` へのマージは人間」という線引きが、どのスキルからも読み取れること。
  **ここが緩んだら本傘の前提が壊れる**ので、レビューでは特にここを見てもらう
- `skills/` 配下に `git pull` の使用を促す記述が残っていないこと
- `docs/` 配下の文書への言及に DOC-ID が併記されていること（地の文の作法）

スキル文書は自動テストの対象ではないため、テストの追加は不要。
`pre-commit run --all-files`（`doc-id verify` による切れ参照の検出を含む）で足りる。

## やらないこと

- `claude/CLAUDE.md`（配布物）を編集しない
- スキルの配布の仕組み（`skills/deploy.sh`、`shared/helpers.sh` の `skill_*`）に触らない
- sheaf / lora-dataset-forge 側のファイルを触らない
- 孫1 のフック・孫3 の `AGENTS.md` の線引きと**異なる**線引きを発明しない。
  食い違いを見つけたら、自分で決めずに司令官へ報告する
- linter の抑制ディレクティブ・除外設定を足さない

## コミット前に必ず実行する

```
pre-commit run --all-files
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PR を作成する。**PR の向き先は必ず `autopilot-permissions` にすること。
   `master` には絶対に出さない。**
2. `/pr-review-loop` を起動する（PR がない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewer は done 状態で完了し完了通知は来ないので、待機して停止せず
`gh pr view` をポーリングしてレビューの有無を確認してください。

## ブランチ作成時の注意（最重要）

このワークツリーは `ocw` が傘ブランチ `autopilot-permissions` から切った孫ブランチ上で
起動している。実装前に `git branch --show-current` で自分のブランチ名を確認し、
`git log --oneline origin/autopilot-permissions..HEAD` が空であることを確かめること。
`master` から切られていたら、その時点で作業を止めて司令官へ報告すること。
````

## 孫5用プロンプト: 無人ペインを止める非 git 操作をガードフックへ取り込む

````
# 孫5: chmod など非 git 操作の承認ダイアログを止める

あなたはこの孫ブランチの実装 AI です。計画書
`docs/planning/DOC-2609121700_autopilot-permissions_計画.md`
（背景3-G、設計1、設計2、および孫1 が確定させた ADR を必ず読むこと）に基づいて
実装してください。

**前提: 孫1 が `claude/hooks/git-guard.sh` を傘ブランチへ入れ終えている。**
このフックに arm を足すのがこの孫の仕事であり、フックの既存の判定
（`gh pr merge` / `git push` / `git merge`）には手を入れない。

## 問題（計画書 背景3-G より）

`claude/settings.json` の `ask` に `Bash(chmod *)` が丸ごと入っているため、
新しいスクリプトを作った孫が `chmod +x` した瞬間に承認ダイアログが出て、
押す人間のいない無人ペインがそこで固まる。実際に本傘の孫で起きている。

`chmod` の危険度は**対象がどこにあるか**で決まる。ワークツリー内のファイルへの
実行ビット付与と、`/usr/bin` 配下や `-R` による広範囲の変更はまったく別物だが、
`Bash(chmod *)` という1本のパターンは両者を区別できない。git 操作と同じ理由で、
これはガードフックの仕事である。

## やること

### 1. `claude/hooks/git-guard.sh` に `chmod` の arm を足す

**allow に倒してよいのは、次を全部満たすときだけ**:

- `-R` / `--recursive` が付いていない
- モード指定が**実行ビットの付与だけ**である（`+x` `u+x` `a+x` `ug+x` などの
  シンボリック指定。**数値モード（`755` 等）は対象外**——`chmod 755` は
  他のビットも同時に書き換えるため、`+x` と同一視しない）
- 対象パスが1つ残らず**現在の git ワークツリーの内側**に解決される
  （`git rev-parse --show-toplevel` を基準に、シンボリックリンクと `..` を
  解決したうえで判定する。`../../etc/foo` のような脱出を通さない）
- 対象に `.git/` 配下が含まれていない

上記のどれか1つでも満たさなければ **ask**（deny ではない。人間が押せば通ってよい
操作であり、`gh pr merge` のような「人間だけの仕事」ではないため）。
判定できなければ ask に倒すのは既存 arm と同じ。

### 2. `rm -r` の扱いを決める

`Bash(rm -r *)` / `Bash(rm -rf *)` も同じ形で無人ペインを止める
（`mktemp -d` で作った一時ディレクトリの後片付けで止まった実測がある）。

**allow に倒してよいのは、対象パスが1つ残らず次のいずれかに解決されるときだけ**とする。
それ以外はすべて ask のまま。**ワークツリー内は allow にしない**
（コミット前のファイルは git でも復元できないため、`chmod` とは危険度が違う）。

- このセッションの scratchpad ディレクトリ配下（`/tmp/claude-*/…`）
- **`$TMPDIR`（未設定なら `/tmp`）の直下より深い一時ディレクトリ**。
  `mktemp -d` が作るのは `/tmp/tmp.XXXXXXXXXX` であって scratchpad 配下ではない
  （2026-09-12 実測。`TMPDIR` は未設定で、`/tmp/tmp.*` が多数残っていた）。
  **この2つ目を落とすと、実際に観測された停止3回がどれも解消しない**

`$TMPDIR` / `/tmp` そのもの、および1階層目（`/tmp` 直下のファイル1つを消すのではなく
`/tmp` 自体を消す形）は allow にしない。なお `rm` / `rmdir` が critical path
（`/`・`~` など）を対象にする場合は、**allow ルールでもフックの `allow` でも承認されず
必ず分類器へ回る**ことが公式ドキュメントで明記されているので、そこは二重に守られている。

**`rm -r` をこの孫に含めることは人間が明示的に決定している**（背景3-G の逐語を参照。
「巻き込んでいい。特にフォルダ単位で制限してあるならなおさら」）。フォルダで縛る形が
許容の根拠なので、**scratchpad 配下という制限を外したり広げたりしない**こと。

この判断が実装上むずかしい／別の設計のほうが素直だと分かった場合は、
自分で線を引き直さずに司令官へ報告すること。

### 3. `claude/settings.json` と ADR の追随

- **`ask` の該当パターンを消さないと、この孫の目的は達成できない**（設計2 の訂正版を読むこと。
  フックの `allow` は `ask` を素通りさせられない）。`Bash(chmod *)` が残っている限り、
  フックが何を返しても `chmod +x` は止まる。**`Bash(chmod *)` を削除し**、
  「フックが不在でも無条件に止めたいもの」だけをパターンとして残すこと
  （`-R` 付き・絶対パス・`sudo` 経由など。具体的なパターン集合は孫が設計してよいが、
  **`chmod +x <ワークツリー内の相対パス>` がどのパターンにも一致しないこと**が要件）
- `rm -r` も同様に、scratchpad 配下（`/tmp/claude-*`）がどのパターンにも一致しない形へ
  絞り込む必要がある。`Bash(rm -r *)` `Bash(rm -rf *)` を丸ごと残したままでは目的を達成できない。
  **ただし絞り込みすぎるとフック不在時の fail-open が広がる**ので、危険な絶対パス
  （`/home` `/usr` `/etc` `/var` `/mnt` `/opt` `~` 等）を名指しする形の網は残すこと
- **フックが不在／壊れている環境で素通りするようになる範囲を洗い出し、ADR に明記する**

### 4. 分類器で止まるコマンドへ狭い `allow` を置く（背景3-H）

**`mkdir` のように `ask` にも `deny` にも入っていないコマンドは、permissions ではなく
auto mode の分類器が止めている。** 評価順は「allow / ask / deny に一致 → 即決」
「それ以外 → 分類器」なので、**対策は狭い `allow` ルールを置くこと**（フックでも
`ask` の絞り込みでもない。フックは分類器を飛ばせない）。

- 無人の孫が正当な作業の過程で叩くのに、どのルールにも当たらないコマンドを棚卸しする
  （`mkdir -p` は人間が実測で報告した1件。他に何があるかは
  `/permissions` の **Recently denied** タブや実際の巡回ログから拾えるものを拾う。
  **憶測で大量に足さない**）
- **広すぎる allow は auto mode で落とされるので意味がない。**
  対象は `Bash(*)`・`Bash(python*)` のようなワイルドカード付きインタプリタ・
  パッケージマネージャの run・`Agent`・`Monitor`。`Bash(npm test)` のような
  狭いルールだけが効き続ける。**`Bash(mkdir *)` がこの「広すぎる」に当たるかどうかは
  一次情報で確認すること**（当たるなら `Bash(mkdir -p *)` のようにさらに狭める）
- 追加する `allow` は**追跡されている `claude/settings.json`** に書く。
  人間の `~/.claude/settings.json` を直接編集しない
- この節の対策は ADR に「permissions・フック・分類器の3層があり、それぞれ効く相手が
  違う」という整理として残すこと
- 孫1 の ADR に「対象がどこにあるかで危険度が決まる操作は、パターンではなく
  フックで判定する」という一般則が書かれているはずなので、そこへ `chmod` / `rm -r` を
  適用した節を追記する（ADR は原則書き換えないが、**同じ決定の適用範囲を広げる追記**は
  この傘の中で行ってよい。判断に迷ったら新しい ADR を足す側に倒し、司令官へ報告する）
- `claude/README.md` のフックの節にも追随する

## 検証方針

以下の重要な behavior / regression risk が、自動テスト（`tests/git_guard_test.sh`。
孫1 が作ったものを拡張する）によって保護されていること。

- **ワークツリーの外を指す `chmod +x`（絶対パス・`..` による脱出・シンボリックリンク
  経由の両方）が allow に倒れないこと。**
  **この regression は必ず自動テストで固定する**（ここが緩むと、リポジトリの外の
  任意のファイルへ無確認で実行ビットが立つ）
- `-R` 付き・数値モード・実行ビット以外のシンボリック指定（`o+w` `u+s` 等）が
  allow に倒れないこと
- ワークツリー内のファイルへの `chmod +x` が allow されること（これが本題）
- scratchpad 配下以外を指す `rm -r` / `rm -rf` が allow に倒れないこと。
  **この regression は必ず自動テストで固定する**
- 孫1 が入れた git 系 arm の判定が、この変更で1つも変わっていないこと

各項目と test example を1対1対応させる必要はない。複数の条件を1つの scenario で
検証してよい。

## やらないこと

- 孫1 が入れた `gh pr merge` / `git push` / `git merge` の判定に手を入れない
- `~/.claude/settings.json`（人間の実環境）を書き換えない
- `claude/settings.machine.json`（git 非追跡）を編集しない
- `deploy-all.sh` / `*/deploy.sh` を実オペレーションで実行しない
- `ask` からパターンを削除しない
- linter の抑制ディレクティブ・除外設定を足さない

## コミット前に必ず実行する

```
pre-commit run --all-files
tests/deploy_smoke.sh
tests/git_guard_test.sh
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PR を作成する。**PR の向き先は必ず `autopilot-permissions` にすること。
   `master` には絶対に出さない。**
2. `/pr-review-loop` を起動する（PR がない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewer は done 状態で完了し完了通知は来ないので、待機して停止せず
`gh pr view` をポーリングしてレビューの有無を確認してください。

## ブランチ作成時の注意（最重要）

このワークツリーは `ocw` が傘ブランチ `autopilot-permissions` から切った孫ブランチ上で
起動している。実装前に `git branch --show-current` で自分のブランチ名を確認し、
`git log --oneline origin/autopilot-permissions..HEAD` が空であることを確かめること。
`master` から切られていたら、その時点で作業を止めて司令官へ報告すること。
````

## 孫6用プロンプト: settings.machine.json を発見可能にする

````
# 孫6: settings.machine.json を ~/.claude/settings.json の兄弟として symlink する

あなたはこの孫ブランチの実装 AI です。計画書
`docs/planning/DOC-2609121700_autopilot-permissions_計画.md`
（背景3-B、背景3-I、設計6 を必ず読むこと。設計6 が採る案と却下した案の理由が本体です）
に基づいて実装してください。

**前提: 孫2（PR #89）が `claude/deploy.sh` の settings 生成を既に変更している。**
学習済み `allow` の保全処理が入っているので、その挙動を壊さないこと。

## 問題（計画書 背景3-I より）

`claude/settings.machine.json` は git 非追跡のうえ、実在するのが `master` ワークツリー
1箇所だけで、場所は `claude/README.md` にしか書かれていない。この傘で扱った時限爆弾
（`deny: Bash(git merge *)`）に人間が自力でたどり着けなかった。生成物である
`~/.claude/settings.json` の隣に置かれていれば、その場で見つけて直せる。

## やること（設計6 の案B。**案A は却下済みなので採らない**）

1. **実体の置き場所を `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/settings.machine.json`
   にする**（`current` や `generations/` と同じ階層。**世代の中には入れない**）
2. `~/.claude/settings.machine.json` をその固定パスへの symlink として張る
   （`symlink_backup` 経由）
3. `claude/deploy.sh` の settings 生成が machine 設定をこの固定パスから読むようにする
4. 固定パスにファイルが無ければ deploy が `{}`（空の JSON オブジェクト）を作る。
   **`--dry-run` では作らない**
5. **移行**: 既存のソースツリー `claude/settings.machine.json` を固定パスへ移す。
   自動移行してよいが**何をどこへ移したかを必ずログに出す**。固定パスとソースツリーの
   両方に存在して内容が異なる場合は、勝手にどちらかを採らず**警告して停止する**
6. `shared/helpers.sh` の `links_for_tool()` の `claude)` arm に
   `$HOME/.claude/settings.machine.json` を追加する。
   **忘れても `uninstall.sh` は警告を出さない**（`KNOWN_GENERATED_claude` が定義済みのため
   「No link list defined」ガードが発火しない。ルート `AGENTS.md`「実装時の注意」参照）
7. `uninstall.sh`: `~/.claude/settings.machine.json` の symlink は撤去し、
   **固定パスの実体は消さない**。その結果 prefix が空にならないので、既存の
   「空になった prefix を消す」処理が破綻しないか確認し、必要なら明示的に扱う
8. `deploy-all.sh --status` に固定パスの状態（有無）が出るとよい（任意）
9. `claude/README.md` とルート `AGENTS.md` の「claude の例外」節を追随させる。
   README には「`~/.claude/settings.machine.json` を直接編集してよい」ことと、
   `settings.machine.json.example` の位置づけ（**配布しない。参照用のサンプル**）を書く

**`settings.machine.json.example` を自動配布しないこと。** 中身が
`"allow": ["Bash", "Read", "Edit", "WebFetch", ...]` の全許可と、存在しないパス
`/path/to/your/hook.sh` を指す `SessionStart` フックであり、撒くとこの傘で締め直した
権限が無効化され、壊れたフックが毎セッション走る。

## 検証方針

以下の重要な behavior / regression risk が、`tests/deploy_smoke.sh` によって
保護されていること（`HOME` を一時ディレクトリへ差し替えたサンドボックス上で検証する）。

- **machine.json を持たないソースツリーから deploy しても、固定パスにある既存の
  machine 設定が失われないこと。** **この regression は必ず自動テストで固定する**
  （案A を却下した理由そのものであり、この孫の存在意義）
- `~/.claude/settings.machine.json` が固定パスを指す symlink として張られ、
  そこへの書き込みが deploy をまたいで残ること
- 固定パスにファイルが無い初回 deploy で `{}` が作られ、生成される
  `~/.claude/settings.json` がベース設定のままであること（空 machine 設定でも壊れない）
- `--dry-run` で固定パスにファイルが作られないこと
- 移行: ソースツリーにだけ machine.json がある状態から deploy すると固定パスへ移り、
  ログにその旨が出ること。両方にあって内容が違う場合は警告して停止すること
- `uninstall.sh` が `~/.claude/settings.machine.json` の symlink を撤去し、
  **固定パスの実体を消さない**こと。**この regression は必ず自動テストで固定する**
  （人間のマシン設定を消す事故は取り返しがつかない）
- 孫2 が入れた「学習済み allow の保全」が引き続き動くこと（既存テストで担保できるなら
  新規テストは追加しない）

各項目と test example を1対1対応させる必要はない。複数の条件を1つの scenario で
検証してよい。

## やらないこと

- **案A（世代経由の状態ファイル方式）を採らない。** 設計6 に却下理由がある。
  実装してみて案B が成立しないと分かったら、自分で案を変えずに司令官へ報告する
- `~/.claude/` 配下の実ファイルを、サンドボックス外で書き換えない
- 人間の実 `$HOME` に対して `deploy-all.sh` を実オペレーションで実行しない
  （`--dry-run` と `tests/deploy_smoke.sh` のサンドボックスのみ）
- `settings.machine.json.example` を配布物にしない
- 孫5 が入れたガードフックの判定ロジックに触らない
- linter の抑制ディレクティブ・除外設定を足さない

## コミット前に必ず実行する

```
pre-commit run --all-files
tests/deploy_smoke.sh
tests/git_guard_test.sh
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PR を作成する。**PR の向き先は必ず `autopilot-permissions` にすること。
   `master` には絶対に出さない。**
2. `/pr-review-loop` を起動する（PR がない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewer は done 状態で完了し完了通知は来ないので、待機して停止せず
`gh pr view` をポーリングしてレビューの有無を確認してください。
またレビュワーペインが許可の確認待ちで止まっていても、人間に依頼して自分は停止しないこと。

## ブランチ作成時の注意（最重要）

このワークツリーは `ocw` が傘ブランチ `autopilot-permissions` から切った孫ブランチ上で
起動している。実装前に `git branch --show-current` で自分のブランチ名を確認し、
`git log --oneline origin/autopilot-permissions..HEAD` が空であることを確かめること。
`master` から切られていたら、その時点で作業を止めて司令官へ報告すること
（`master` から切ると孫2 の `claude/deploy.sh` 変更が入らず、確実に衝突する）。
````
