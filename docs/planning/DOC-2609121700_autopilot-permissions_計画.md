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
| 1 | `autopilot-permissions-01-git-guard` | 許可ポリシーの確定（ADR）＋ 保護ブランチ判定の PreToolUse ガードフック新設 ＋ `claude/settings.json` 再設計 | 🔄 実装中 |
| 2 | `autopilot-permissions-02-allow-preservation` | `claude/deploy.sh` が学習済み `allow` を deploy 越しに保全する仕組み ＋ `claude/README.md` 追随 | ⬜ 待機中 |
| 3 | `autopilot-permissions-03-agents-rules` | ルート `AGENTS.md` と `templates/repo-baseline/template/AGENTS.md.jinja` の最重要ルールを「`main` は人間 / 傘配下は AI」の軸で書き直す | ⬜ 待機中 |
| 4 | `autopilot-permissions-04-skill-exceptions` | `skills/pr-review-loop` / `skills/umbrella-orchestrator` の傘例外条項と、同一スキル内の矛盾の解消 | ⬜ 待機中 |

## ワークスペースラベル

傘のラベルは `umbrella-handoff` が既に日本語で付けている（`dotfiles :: 自動進行の権限詰まり`）。
既定形ではないので**司令官は改名しない**。孫のラベルはこれを親要約として導出する。

- 傘: `dotfiles :: 自動進行の権限詰まり`（既存。変更しない）
- 孫1: `dotfiles :: 自動進行の権限詰まり 孫1 ガードフックと許可設計`
- 孫2: `dotfiles :: 自動進行の権限詰まり 孫2 学習allowの保全`
- 孫3: `dotfiles :: 自動進行の権限詰まり 孫3 最重要ルールの書き直し`
- 孫4: `dotfiles :: 自動進行の権限詰まり 孫4 スキルの傘例外条項`

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
```

**直列。** 理由は2つ。

1. **孫1 が確定させる ADR が、孫3・孫4 が書く文言の一次情報源になる。** 「AI がやってよい
   操作」の定義が先に確定していないと、文言側が独自の線引きを発明してしまう
2. **孫1 と孫2 はどちらも `claude/deploy.sh` に触る**（孫1 はフックの symlink 追加、
   孫2 は settings 生成ロジックの変更）。並列にすると確実に衝突する

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

### 設計2: `claude/settings.json` はフックの下敷き（fail-safe の網）として残す

PreToolUse フックの `allow` 判定は permissions の `ask` より先に評価される。したがって
「フックが安全と判定したものだけを通し、フックが黙っているものは従来どおり `ask` で
止める」という二層構造が組める。

- `ask` から `git push` 系のパターンを**消さない**。フックが `allow` を返したときだけ
  素通りする形にする
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

1. 孫1〜4 の PR がすべて傘ブランチへマージ済み
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
- `claude/settings.json` の `ask` からは**何も消さない**（計画書「設計2」）
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
