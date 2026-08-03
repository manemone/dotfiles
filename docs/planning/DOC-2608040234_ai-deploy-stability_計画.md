# 計画書: デプロイ配布方式の安定化（作業ツリー直リンクからの脱却）

傘ブランチ: `ai/deploy-stability`
ターゲット: `master`

## 概要

現在の `deploy-all.sh` / 各 `<tool>/deploy.sh` は、リポジトリの作業ツリー内のファイルへ
`$HOME` から直接シンボリックリンクを張る。この設計には次の3つの不安定さがある。

1. **配布物と作業ツリーが同一。** deploy 後にリポジトリ側のファイルを編集すると、コミットもしていない
   編集途中の状態がそのまま `$HOME` の設定として有効になる。壊れた中間状態が即座に本番になり、
   シェルや nvim が起動しなくなり得る。
2. **ワークツリーからデプロイすると寿命が違う。** `git worktree` を消した時点で `$HOME` 側の symlink が
   全部リンク切れになる。このリポジトリは `ocw` / 傘ブランチ運用でワークツリーを日常的に作っては消す。
3. **どこからデプロイされたか追跡できない。** 今 `$HOME` に効いている設定がどのツリーのどのコミット
   由来なのかを、リンク先パスを読む以外に知る手段がない。

本傘では、リポジトリと `$HOME` の間に**配布実体を1段挟む**。世代ディレクトリへツリーをコピーし、
`current` シンボリックリンクを切り替え、`$HOME` からは `current` 経由で参照する
（Capistrano の `releases/` + `current` と同じ構造）。

方式の比較検討と却下理由は **ADR DOC-2608040229**
（[../adr/DOC-2608040229_deploy-distribution-method.md](../adr/DOC-2608040229_deploy-distribution-method.md)）
に記録済み。**孫はまず ADR を読むこと。** この計画書は ADR で確定した方式を実装単位へ分解したものである。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `ai/ds-01-distribution-layer` | 配布実体レイヤ（世代ディレクトリ + `current` + manifest + GC）と、単純 symlink 系4ツール（`zsh` `nvim` `tmux` `bin`）の切り替え | ⬜ 待機中 |
| 2 | `ai/ds-02-claude-sources` | `claude` の例外2箇所（`settings.json` の生成・`skills/` の個別 symlink）を `current` 経由へ追従 | ⬜ 待機中 |
| 3 | `ai/ds-03-uninstall` | `uninstall.sh` の追従（配布実体の後片付け・由来判定の両対応）と `KNOWN_LINKS_bin` の `ocw-meter` 欠落修正 | ⬜ 待機中 |
| 4 | `ai/ds-04-operations` | 運用コマンド `--status` / `--rollback` / `--dev` / リンク切れ検出 | ⬜ 待機中 |
| 5 | `ai/ds-05-docs` | 文書の更新（`AGENTS.md` / ルート `README.md` / テスト方針）と運用リファレンスの新規作成 | ⬜ 待機中 |
| 6 | `ai/ds-06-ocw-meter-prices` | `bin/ocw-meter` が symlink 経由起動で価格表を見失うバグの修正 | ⬜ 待機中 |

## 依存関係と実行順序

```
孫1 (配布実体レイヤ + 単純symlink系4ツール)
  ↓ current が存在しないと claude 側も切り替えられない
孫2 (claude の例外2箇所)
  ↓ skills のリンク先が確定してからでないと uninstall の由来判定を書けない
孫3 (uninstall 追従 + ocw-meter 欠落修正)
  ↓ 配布・撤去の往復が閉じてから運用コマンドを足す
孫4 (--status / --rollback / --dev / doctor)
  ↓ 挙動が全部確定してから文書を書く（先に書くと必ず嘘になる）
孫5 (文書 + 運用リファレンス)

孫6 (ocw-meter の価格表参照)  ← 完全に独立。いつ実施してもよい
```

孫1〜5 は直列。**孫6 だけは他孫と触るファイルが重ならない**（`bin/ocw-meter` と `bin/tests/` のみ）ため、
並列に走らせてよい。

---

## 確定事項（孫の判断で覆さないこと）

ADR DOC-2608040229 で決着済み。実装時に蒸し返さない。

| 領域 | 決定 | 根拠 |
|---|---|---|
| 配布方式 | **世代ディレクトリ + `current` シンボリックリンク** | ADR §4 |
| canonical prefix | `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles` | XDG に従う。`$HOME` 直下を汚さない |
| 世代 ID の形式 | `<date +%Y%m%dT%H%M%S>-<short sha>` | `date +FORMAT` は BSD/GNU 共通で安全 |
| `$HOME` 側リンクの向き先 | **必ず `current` 経由**。世代ディレクトリを直接指さない | `current` 1本の付け替えで全リンクが切り替わる。これが世代方式の要（ADR §4.1） |
| 世代の中身 | **常に全ツール分**。`--only` は `$HOME` のどのリンクを張るかだけを制御し、世代の内容には影響しない | 部分的な世代を作ると、他ツールのリンクが新世代に存在しないパスを指してリンク切れになる（ADR §4.3） |
| 保持世代数 | **既定 3**（`DOTFILES_KEEP_GENERATIONS` で上書き可） | 走行中 nvim の遅延ロード保護 + 直前へのロールバック（ADR §4.6） |
| GC の不変条件 | `current` が指す世代は決して削除しない。dev モード中は世代を削除しない | 同上 |
| コピー手段 | **`cp -a`**。`rsync` に依存しない | 最小構成の Linux に `rsync` が無いことがある。`-a` は BSD/GNU 双方にある |
| 配布実体の作り方 | **作業ツリーのファイルコピー**。`git archive` は使わない | 非追跡の `claude/settings.machine.json` が落ちる（ADR §2.4） |
| `current` の差し替え | **`ln -sfn`**。原子性は追わない | `mv -T`（GNU）/ `mv -h`（BSD）の分岐は macOS 実機で検証できない（ADR §4.7） |
| 即時反映 | **dev モードとして残す。** 既定は世代モード、dev は明示指定のみ | 試行錯誤の利便性を失わない。ただし既定から外す（ADR §4.5） |
| `~/.claude/settings.json` | **実ファイル生成のまま**（symlink にしない） | 現行の設計判断を維持する |
| `claude/skills/` | **スキルごとの個別 symlink のまま**（ディレクトリ丸ごとの symlink は禁止のまま） | Herdr 管理・ユーザー所有のスキルと共存させるため |
| 単体 `<tool>/deploy.sh` 実行時 | `DOTFILES_DEPLOY_SRC` が未設定なら **`current` を使う**。`current` も無ければエラーで `deploy-all.sh` を案内 | 「zsh だけ張り直す」用途を残しつつ、世代が常に全ツール分という不変条件を単体実行が破れないようにする |

### 検討して却下した案（蒸し返さないこと）

詳細は ADR DOC-2608040229 §5。

- **現状維持 / 警告のみ** → `warn_if_linked_worktree` は既に実装済みであり、これが現状そのもの。問題1に手が届かない
- **ガード強化のみ**（worktree からの deploy を拒否 + 状態表示） → 問題1に原理的に手が届かない。ただし状態表示・リンク切れ検出は孫4 として採用案に取り込む
- **`$HOME` へ実体をコピー（symlink 廃止）** → `symlink_restore` の「実ファイルはユーザーデータ」判定と衝突し、ハッシュ台帳が必要になる。1人の dotfiles に過剰
- **世代を保持しない（`current` のみ）** → 安全に作ると実装は世代方式とほぼ同じになり、差は GC のみ。それで走行中プロセス保護とロールバックを失う
- **`mv -T` / `mv -h` による原子的差し替え** → macOS 実機で検証できない分岐を抱えるコストが利益を上回る
- **`git archive` で配布実体を作る** → 非追跡ファイルが落ちる
- **ファイル監視による自動再同期（watch）** → 監視ツール依存が増える。dev モードで足りる

---

## 全孫共通の注意（プロンプトにも再掲するが、ここが正）

### 1. deploy スクリプトを実オペレーションで実行しない

symlink 先は**人間の実 `$HOME`** である。`~/.zshrc` `~/.tmux.conf` `~/.claude/settings.json`
`~/bin/*` を実際に置き換えてしまう。動作確認は次の2つだけで行う。

- `./deploy-all.sh --dry-run`（全ツール対象）
- `tests/deploy_smoke.sh`（`HOME` を一時ディレクトリへ差し替えたサンドボックス。既定対象は `bin,claude`）

**個別の `<tool>/deploy.sh` は `--dry-run` 引数を解釈しない。** `DRY_RUN=1 sh zsh/deploy.sh` のように
環境変数で渡すこと。引数で渡すと黙って無視され、実際の書き換えが起きる。

`tests/deploy_smoke.sh` の `new_sandbox` にあるガード（一時ディレクトリ配下であること・実 `$HOME` と
一致しないこと）を**弱めない**。ここが壊れると人間の実 `$HOME` に対して deploy が走る。

### 2. `rm -rf` の扱い（本傘で最も事故りやすい箇所）

本傘では世代の GC と uninstall で**ディレクトリの再帰削除を書くことになる**。事故れば人間の
`$HOME` やリポジトリの作業ツリーそのものが消える。次を必ず守る。

- 変数展開込みの `rm -rf "$var"` を、`$var` の中身を検証せずに書かない
- 削除前に必ず「存在すること」「シンボリックリンクではなく実ディレクトリであること」
  「canonical prefix 配下のパスであること（前方一致で確認）」を確認する
- **dev モードでは `current` は作業ツリーを指している。** ここを削除対象に含めない。
  `current` の実体ではなく `current` というリンク自体を消す操作と、世代ディレクトリを消す操作を
  混同しない

### 3. POSIX sh の制約

`shared/helpers.sh` `deploy-all.sh` `uninstall.sh` `*/deploy.sh` はすべて `#!/bin/sh`。
配列・`[[ ]]`・`local`・`source`・`<<<`・`$'...'`・`function` キーワードを書かない。
詳細は
[シェルスクリプトコーディング方針 DOC-2608020715-a](../design/DOC-2608020715-a_シェルスクリプトコーディング方針.md)。
`tests/deploy_smoke.sh` は bash なのでこの制約を受けない。

macOS の BSD 版コマンドと GNU 版の差異に注意する。`readlink -f` は GNU 専用で使えない。
`date` はオプション無しの `date +FORMAT` のみ。

### 4. linter の抑制を自己判断で追加しない

`# shellcheck disable=...` などの抑制ディレクティブ、`.pre-commit-config.yaml` の `exclude` /
`exclude_types` 追加、`shfmt` のオプション緩和を AI の判断で追加しない。指摘が設計上不合理だと
判断した場合は、抑制せず違反内容・対象ファイル・判断理由を人間に報告する。
コードの構造を変えて指摘そのものを解消できるならそちらを優先する。

### 5. 破壊的な git 操作の禁止

**人間の明示的指示がない限り、`git merge` / `git pull` / `git reset --hard` /
`git push --force` / `gh pr merge` を実行しない。** 例外はない。

### 6. `claude/` と `.claude/` とルート `AGENTS.md` を混同しない

| 対象 | 正体 |
|---|---|
| `claude/CLAUDE.md`, `claude/settings.json`, `claude/skills/` | **配布される成果物。** 人間のマシンの `~/.claude/` へ配置される |
| ルート `AGENTS.md` / `CLAUDE.md` | **このリポジトリを開発するためのルール** |
| `.claude/settings.json` | このリポジトリで作業する AI 向けの permissions |

`claude/CLAUDE.md`（配布物。個人の口調設定が入っている）は**どの孫も編集しない**。

### 7. コミット前の必須ステップを省略しない

```
pre-commit run --all-files
tests/deploy_smoke.sh
```

`bin/` 配下を変更した孫は加えて `python3 -m unittest discover -s bin/tests -v`（193件・約40秒）。
`templates/repo-baseline/` は本傘では触らない。

---

## 孫1用プロンプト:

````
## タスク: 配布実体レイヤ（世代ディレクトリ + current）を導入する

まず以下を順に読むこと。

1. ADR `docs/adr/DOC-2608040229_deploy-distribution-method.md`（採用方式と却下理由）
2. 計画書 `docs/planning/DOC-2608040234_ai-deploy-stability_計画.md` の
   「確定事項」と「全孫共通の注意」
3. `AGENTS.md`
4. `docs/design/DOC-2608020715-a_シェルスクリプトコーディング方針.md`

### 背景

現在 `$HOME` のシンボリックリンクはリポジトリの作業ツリーを直接指している。この孫では
リポジトリと `$HOME` の間に配布実体を1段挟み、単純な symlink だけを張る4ツール
（`zsh` `nvim` `tmux` `bin`）を新方式へ切り替える。`claude` は例外処理が2箇所あるため孫2 の担当。

### 作るもの

#### 1. `shared/helpers.sh` に配布実体レイヤを足す

POSIX sh。関数内の一時変数は既存慣行どおりアンダースコア始まり + 関数固有プレフィクスにする。

- canonical prefix は `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles`
- 世代ディレクトリは `<prefix>/generations/<date +%Y%m%dT%H%M%S>-<short sha>`
- `current` は `<prefix>/current`

必要な関数（名前は提案。既存の命名慣行に合わせて調整してよい）:

- 世代を作る: 作業ツリーから `cp -a` でツリーをコピーする。**コピー対象は
  `AVAILABLE_TOOLS` の各ディレクトリと `shared/` に限る**（`docs/` `tools/` `templates/`
  `tests/` `.git` は配布物ではないのでコピーしない）。`--only` が指定されていても
  **常に全ツール分をコピーする**（確定事項を参照。部分的な世代を作ると他ツールのリンクが切れる）
- manifest を書く: 世代ディレクトリ直下に `.dotfiles-manifest` を平文で置く。
  デプロイ日時 / ソースツリーの絶対パス / コミット SHA / ブランチ名 / 作業ツリーが dirty か /
  リンクされた git ワークツリーからのデプロイか / モード（世代 or dev）/ ホスト名
- `current` を切り替える: `ln -sfn` を使う。`mv -T` / `mv -h` は使わない（確定事項）
- 古い世代を GC する: 保持数は `${DOTFILES_KEEP_GENERATIONS:-3}`。
  **`current` が指す世代は決して消さない。dev モード中は何も消さない。**
  削除前に「存在する」「シンボリックリンクではない実ディレクトリ」「canonical prefix 配下
  （前方一致で確認）」を必ず検証する

`DRY_RUN=1` のときは実際のコピー・切り替え・削除を行わず、何をするかを出力すること
（既存の `symlink_backup` の dry-run 出力の書き方に合わせる）。

#### 2. `symlink_backup` を改修する

現行は dst に既存のものがあれば無条件で `.backup` へ退避する。このままだと**旧方式の symlink が
`.backup` として残り**、後日 `uninstall.sh` がそれを「ユーザーの元設定」として復元してしまう。

**dst が既にこのリポジトリ由来の symlink であれば、退避せずに張り替える**判定を足すこと。
判定基準は「リンク先が canonical prefix 配下、またはソースツリー配下であること」。
ユーザー自身が置いた無関係な symlink やファイルは、これまでどおり退避すること。

#### 3. `deploy-all.sh` を配布実体経由にする

流れは次のとおり。

1. 世代ディレクトリを作る（全ツール分）
2. manifest を書く
3. `current` を新世代へ付け替える
4. 各 `<tool>/deploy.sh` を呼ぶ。このとき配布元パスを環境変数 `DOTFILES_DEPLOY_SRC`
   （= `<prefix>/current`）で渡し export する
5. 古い世代を GC する

`--dry-run` ではどの世代を作り `current` をどう付け替えるかを出力するだけにすること。

#### 4. 単純 symlink 系4ツールの `deploy.sh` を切り替える

`zsh/deploy.sh` `nvim/deploy.sh` `tmux/deploy.sh` `bin/deploy.sh` の
`symlink_backup` の第1引数（配布元）を、`$SCRIPT_DIR/...` から `$DOTFILES_DEPLOY_SRC/<tool>/...` に変える。

**単体実行への対応（確定事項）**: `DOTFILES_DEPLOY_SRC` が未設定なら `current` を使う。
`current` も無ければエラーメッセージで `./deploy-all.sh` を案内して終了する。
自分で世代を作ろうとしないこと（世代は常に全ツール分でなければならないため）。

`$SCRIPT_DIR` はスクリプト自身の位置解決には引き続き使ってよい（`shared/helpers.sh` の source など）。
**「配布元」と「スクリプトの居場所」を混同しないこと。**

#### 5. `tests/deploy_smoke.sh` にシナリオを追加する

bash。既存のシナリオと関数（`new_sandbox` / `run_deploy` / `assert_*`）を再利用すること。
対象は `bin`（既定対象のうち、この孫で切り替わるツール）。

- **ソースツリー消失耐性**: サンドボックス内にリポジトリのコピーを作り、そこから deploy して
  コピーを削除したあとでも `$HOME` 側の配布物が読めること
- **編集分離**: deploy 後にソースツリーのファイルを書き換えても `$HOME` 側から読める内容が変わらないこと
- **世代と GC**: 再デプロイで世代が増え `current` が新世代を指すこと。保持数を超えた古い世代が
  削除され、`current` が指す世代は削除されないこと（保持数は `DOTFILES_KEEP_GENERATIONS` を
  小さい値にして検証してよい）
- **`--only` は世代の内容に影響しない**: `--only bin` で deploy しても世代には全ツール分が入ること

既存シナリオ（退避 / 冪等性 / `--no-backup` / `--only` フィルタ / uninstall 復元）が
引き続き通ること。**通らなくなった場合、テストを緩めるのではなく実装を直すこと。**

### やらないこと

- `claude/deploy.sh` の変更（孫2 の担当）。この孫の後は「4ツールは `current` 経由、`claude` は
  作業ツリー直リンク」という混在状態になるが、**動作としては壊れないので許容する**
- `uninstall.sh` の変更（孫3 の担当）
- `--status` / `--rollback` / `--dev` の実装（孫4 の担当）
- `AGENTS.md` / `README.md` / テスト方針の更新（孫5 の担当）。ただし**この孫で挙動が変わったのに
  文書が古いままである点を、PR の説明文に明記して孫5 へ申し送ること**
- `bin/ocw-meter` の修正（孫6 の担当）

### 検証

```
pre-commit run --all-files
./deploy-all.sh --dry-run
tests/deploy_smoke.sh
```

`bin/` 配下のファイルは変更しない想定だが、もし触ったなら
`python3 -m unittest discover -s bin/tests -v` も実行すること。
````

## 孫2用プロンプト:

````
## タスク: claude の例外2箇所を配布実体経由へ追従させる

まず以下を順に読むこと。

1. ADR `docs/adr/DOC-2608040229_deploy-distribution-method.md`（特に §4.8）
2. 計画書 `docs/planning/DOC-2608040234_ai-deploy-stability_計画.md` の
   「確定事項」と「全孫共通の注意」
3. 孫1 が変更した `shared/helpers.sh` と `deploy-all.sh`（配布実体レイヤの実装）

### 背景

孫1 で `zsh` `nvim` `tmux` `bin` は配布実体（`current` 経由）へ切り替わった。`claude` だけは
他ツールに無い例外が2つあるため残してある。この孫で追従させる。

例外1: `~/.claude/settings.json` は symlink ではなく、`claude/settings.json` と非追跡の
`claude/settings.machine.json` を python3 でマージして**実ファイルとして生成**している。

例外2: `~/.claude/skills/<name>` はスキルごとに**個別に symlink** を張り、既存のものは
`symlink_backup` を通さず `~/.claude/skills-backup/<名前>.<日時>.<PID>` へ退避している。

### 作るもの

`claude/deploy.sh` を変更する。配布元を `$SCRIPT_DIR` から `$DOTFILES_DEPLOY_SRC/claude` へ変える。

- `~/.claude/CLAUDE.md` の symlink 先
- `settings.json` のマージ元2ファイル（base と machine）の読み取り元。
  **`settings.machine.json` は非追跡だが `cp -a` でコピーされるので世代の中に入っている。**
  世代の中のものを読むこと（作業ツリーのものを直接読まない）
- `skills/` の走査元と、各スキルの symlink 先

**変えないもの（確定事項）**:

- `~/.claude/settings.json` が実ファイルであること。symlink にしない
- スキルを個別に symlink すること。ディレクトリ丸ごとの symlink は引き続き禁止
- `~/.claude/skills-backup/` という専用の退避先
- `~/.claude` の 700 パーミッション強制

**既存のガードを残すこと**: `~/.claude/skills` 自体が symlink だった場合のエラー、
配布元と配布先が同一パスになる場合のスキップ、`settings.json` が symlink だった場合の除去、
`SKILLS_SRC_DIR` 配下を指す stale な symlink の掃除。これらは配布元パスが変わっても
同じ意味で機能する必要がある。**stale 判定の前方一致に使うパスが `current` 経由になる点に注意。**

単体実行への対応は孫1 と同じ規約に従う（`DOTFILES_DEPLOY_SRC` 未設定なら `current` を使い、
無ければ `./deploy-all.sh` を案内して終了）。

### `tests/deploy_smoke.sh` に追加するシナリオ

対象は `claude`。既存の claude 関連アサーション（`settings.json` が実ファイルであること、
skills が個別 symlink であること、既存 skill が `skills-backup` へ退避されること、
uninstall で復元されること）が**新しいリンク先で**通るように更新した上で、次を追加する。

- **消失耐性（claude 版）**: サンドボックス内のリポジトリのコピーから deploy し、
  コピーを削除しても `~/.claude/CLAUDE.md` と各スキルが読めること
- **`settings.machine.json` が世代に入り、マージが効くこと**: サンドボックス用のリポジトリの
  コピー側に `claude/settings.machine.json` を置いた状態で deploy し、生成された
  `~/.claude/settings.json` にマージ結果が反映されていること
- **`settings.json` の冪等性**: 2回目の deploy で「already up to date」となること
  （既存アサーションの維持）

### やらないこと

- `uninstall.sh` の変更（孫3 の担当）。この孫の後、`uninstall.sh` の skills 由来判定
  （`KNOWN_SKILLS_SRC_claude`）は作業ツリーのパスを見たままなので、**新方式で張られた
  スキルの symlink を認識できない**状態になる。これは孫3 が直す。
  **PR の説明文にこの申し送りを明記すること**
- `--status` / `--rollback` / `--dev`（孫4）、文書（孫5）、`bin/ocw-meter`（孫6）
- `claude/CLAUDE.md`（配布物）の編集

### 検証

```
pre-commit run --all-files
./deploy-all.sh --dry-run
tests/deploy_smoke.sh
```
````

## 孫3用プロンプト:

````
## タスク: uninstall.sh を新方式へ追従させ、ocw-meter の欠落を直す

まず以下を順に読むこと。

1. ADR `docs/adr/DOC-2608040229_deploy-distribution-method.md`
2. 計画書 `docs/planning/DOC-2608040234_ai-deploy-stability_計画.md` の
   「確定事項」と「全孫共通の注意」（特に **2. `rm -rf` の扱い**）
3. 孫1・孫2 の変更（`shared/helpers.sh` / `deploy-all.sh` / 各 `deploy.sh`）
4. `AGENTS.md` の「実装時の注意」（`uninstall.sh` に arm を足し忘れる典型的な事故の説明がある）

### 背景

孫1・孫2 で配布経路が `current` 経由に変わったが、`uninstall.sh` は作業ツリーを前提にしたままである。
配布と撤去の往復が閉じていない状態なので、この孫で閉じる。

### 作るもの

#### 1. スキルの由来判定を両対応にする

`uninstall.sh` は `~/.claude/skills/` を走査し、リンク先が `KNOWN_SKILLS_SRC_claude`
（現行は `$SCRIPT_DIR/claude/skills`）の配下にある symlink だけを撤去対象にしている。

新方式で張られたスキルは `current` 経由のパスを指すため、**現状では認識されず撤去されない**。
判定を次の両方に一致させること。

- canonical prefix 配下（`<prefix>/current/claude/skills/...` および
  `<prefix>/generations/.../claude/skills/...`）
- 旧方式の作業ツリー配下（`$SCRIPT_DIR/claude/skills/...`）

**旧方式のリンクも撤去できる必要がある。** 新方式へ移行済みのマシンにも、移行前に張られた
リンクが残っている可能性があるため。

#### 2. 配布実体の後片付け

`uninstall.sh` は `$HOME` の symlink を剥がすだけで、canonical prefix
（`<prefix>/generations/` と `<prefix>/current`）が残る。これも片付けること。

**ここが本傘で最も事故りやすい箇所である。** 次を必ず守ること。

- **dev モードでは `current` は人間の作業ツリー（＝このリポジトリそのもの）を指している。**
  絶対に実体を削除しない。この場合に消してよいのは `current` というシンボリックリンク自体だけ
- 世代ディレクトリを削除する前に「存在する」「シンボリックリンクではない実ディレクトリ」
  「canonical prefix 配下（前方一致で確認）」を検証する
- 変数展開込みの `rm -rf "$var"` を、`$var` の中身を検証せずに書かない
- `--dry-run` で何が消えるかを正確に出力すること

#### 3. `KNOWN_LINKS_bin` の `ocw-meter` 欠落を直す

`bin/deploy.sh` は `~/bin/ocw`・`~/bin/claude-ds`・`~/bin/ocw-meter` の3本を張るが、
`uninstall.sh` の `KNOWN_LINKS_bin` には `ocw-meter` が無く、**uninstall しても
`~/bin/ocw-meter` が残る**。追加すること。

`AGENTS.md`「実装時の注意」にあるとおり、`KNOWN_LINKS_*` 変数の定義と `case` 文の arm は
別々に書かれている。今回は既存ツールへの1行追加なので arm の追加は不要だが、
**`_links` / `_generated` / `_skills_src` を求める3つの `case` 文がそれぞれ正しく引けているかを
確認すること。**

### `tests/deploy_smoke.sh` に追加するシナリオ

- **配布実体の後片付け**: deploy 後に uninstall すると canonical prefix の世代ディレクトリと
  `current` が片付くこと
- **dev モードのソースツリー保護**: `current` がソースツリーを指している状態で uninstall しても、
  **ソースツリーが削除されないこと**（このアサーションは必ず入れること）
- **`ocw-meter` の撤去**: uninstall 後に `~/bin/ocw-meter` が残っていないこと
- **新方式スキルの撤去**: `current` 経由で張られたスキルの symlink が撤去され、
  `skills-backup` から元のスキルが復元されること
- **旧方式リンクの撤去**: 作業ツリー直指しの symlink を手で張った状態から uninstall して、
  それも撤去されること

孫4 の `--dev` はまだ無いので、dev モードの検証はサンドボックス内で `current` を手で
ソースツリーへ向けて作ればよい。

### やらないこと

- `--status` / `--rollback` / `--dev` の実装（孫4 の担当）
- 文書の更新（孫5 の担当）
- `bin/ocw-meter` 本体の修正（孫6 の担当）。この孫が触るのは `uninstall.sh` の
  `KNOWN_LINKS_bin` の1行だけ

### 検証

```
pre-commit run --all-files
./deploy-all.sh --dry-run
./uninstall.sh --dry-run
tests/deploy_smoke.sh
```
````

## 孫4用プロンプト:

````
## タスク: 運用コマンド（--status / --rollback / --dev / リンク切れ検出）を足す

まず以下を順に読むこと。

1. ADR `docs/adr/DOC-2608040229_deploy-distribution-method.md`（特に §4.4 manifest、§4.5 dev モード）
2. 計画書 `docs/planning/DOC-2608040234_ai-deploy-stability_計画.md` の
   「確定事項」と「全孫共通の注意」
3. 孫1〜3 の変更

### 背景

配布と撤去は孫1〜3 で閉じた。この孫は「今 `$HOME` に何が効いているのか」を人間が読める形にし、
壊れたときに戻せるようにする。計画書の問題3（どこからデプロイされたか追跡できない）への回答であり、
問題1（壊れた設定が本番になる）が起きたときの復旧手段でもある。

### 作るもの

`deploy-all.sh` にオプションを足す。既存の引数パースの書き方（`while [ $# -gt 0 ]` + `case`）に合わせること。

#### 1. `--status`

副作用なし。次を表示する。

- `current` が何を指しているか（世代ディレクトリか、dev モードでソースツリーか）
- dev モードなら**そうと分かるように明示**する。ソースツリーがリンクされた git ワークツリーなら警告も出す
- `current` が指す世代の `.dotfiles-manifest` の内容（デプロイ日時 / ソースツリー / コミット SHA /
  ブランチ / dirty だったか / ホスト名）
- 保持されている世代の一覧（どれが `current` かが分かること）
- **`$HOME` 側リンクの健全性**: `uninstall.sh` の `KNOWN_LINKS_*` に相当する配布先を走査し、
  リンク切れ（symlink だが実体が無い）を検出して報告する

配布先リストの二重管理を避けること。`uninstall.sh` が持つ `KNOWN_LINKS_*` と同じ内容を
`deploy-all.sh` にコピーして持つと、片方だけ更新される事故が起きる（`ocw-meter` の欠落が
まさにその事故だった）。**リストを `shared/helpers.sh` へ移して両者が同じものを参照する形にすること。**
`uninstall.sh` 側の `case` 文の構造（shellcheck が変数の使用を追えるようにするための設計）を
壊さないよう注意する。

#### 2. `--rollback [世代 ID]`

`current` を1つ前の世代（または引数で指定された世代）へ付け替える。

- `$HOME` 側の symlink は張り直さない。`current` の付け替えだけで全リンクの向き先が変わる
  （これが世代方式の要）
- 戻せる世代が無い場合は明確なエラーにする
- dev モード中の実行は、何が起きるかを明示した上で世代モードへ戻す扱いにする
- `--dry-run` に対応する

#### 3. `--dev`

`current` を作業ツリーそのものへ向ける。世代は作らない。

- 現行方式と等価の即時反映になる
- ソースツリーがリンクされた git ワークツリーなら、既存の `warn_if_linked_worktree` と同じ趣旨の
  警告を出す（そのワークツリーを消せば全リンクが切れるため）
- dev モード中は世代の GC を行わない（確定事項の不変条件）
- 世代モードへ戻す手順を、コマンド実行後のメッセージで案内する
- `--dry-run` に対応する

### `tests/deploy_smoke.sh` に追加するシナリオ

- **`--status`**: deploy 後に実行して、`current` の向き先・コミット SHA・世代一覧が出力に含まれること。
  リンク切れを作った状態で実行して検出されること
- **`--rollback`**: 2回 deploy して内容の違う世代を2つ作り、rollback すると
  **`$HOME` 側のリンクを張り直さずに**読める内容が前の世代のものへ戻ること
- **`--dev`**: `current` がソースツリーを指すこと。ソースツリーのファイルを書き換えると
  `$HOME` 側から読める内容が即座に変わること。dev モード中に GC が走らないこと

### やらないこと

- 文書の更新（孫5 の担当）。**この孫で増えたコマンドは孫5 が文書化する。
  PR の説明文に、追加したオプションと出力形式を孫5 への申し送りとして明記すること**
- ファイル監視（watch）の実装。ADR で却下済み
- `bin/ocw-meter` の修正（孫6 の担当）

### 検証

```
pre-commit run --all-files
./deploy-all.sh --dry-run
./deploy-all.sh --status
tests/deploy_smoke.sh
```

`--status` は副作用が無いので実 `$HOME` に対して実行してよい。
**`--dev` と `--rollback` は実 `$HOME` に対して実行しないこと**（`current` を実際に付け替えてしまう）。
````

## 孫5用プロンプト:

````
## タスク: 文書を新方式へ更新し、運用リファレンスを作る

まず以下を順に読むこと。

1. ADR `docs/adr/DOC-2608040229_deploy-distribution-method.md`
2. 計画書 `docs/planning/DOC-2608040234_ai-deploy-stability_計画.md` 全体
3. 孫1〜4 の変更内容と、各 PR の説明文に書かれた孫5 への申し送り
4. `docs/README.md`（新規文書追加時の3ステップが書いてある）

### 背景

孫1〜4 で挙動が変わったが、文書は古いままである。**実装より先に文書を書くと必ず嘘になる**ため
最後に回してある。この孫は実装を一切変更せず、文書だけを実態に合わせる。

**書く前に必ず実装を読んで裏を取ること。** 計画書や ADR に書いてある想定と、実際に
マージされた実装が食い違っている可能性がある。食い違いを見つけたら、文書は**実装に合わせ**、
その旨を PR の説明文に書くこと。

### 更新するもの

#### 1. ルート `AGENTS.md`

- 「最重要ルール」の deploy スクリプトに関する記述: 配布実体を1段挟む方式になったことを反映する。
  **「実オペレーションで実行しない」というルール自体は変わらない**（`$HOME` の symlink は
  実際に張り替わるため）
- 「デプロイの仕組み」節: 全面的に書き直す。世代ディレクトリ / `current` / manifest / 保持数 /
  GC の不変条件 / dev モード / `--only` は世代の内容に影響しないこと
- 個別 `<tool>/deploy.sh` の単体実行の規約（`DOTFILES_DEPLOY_SRC` 未設定時は `current` を使う）
- 「実装時の注意」: 新しいツールディレクトリを足すときに触る場所が増えていれば追記する
- 「コミット前の必須ステップ」: `tests/deploy_smoke.sh` の位置づけは変わらないが、
  検証項目が増えていれば反映する

#### 2. ルート `README.md`

- デプロイの説明と `deploy-all.sh` のオプション一覧（孫4 で増えたもの）
- 「Deploying from a git worktree」節: **前提が変わっている。**
  既定の世代モードではワークツリーを消してもリンクは切れない。この節は「dev モードを使う場合の注意」
  として書き直す
- Directory Structure に変更があれば反映する
- uninstall の説明（配布実体も片付くこと）

#### 3. 各ツールの `README.md`

`zsh/README.md` `nvim/README.md` `tmux/README.md` `bin/README.md` `claude/README.md` を確認し、
「リポジトリのファイルへ symlink される」という趣旨の記述があれば実態に合わせる。
**README は「ルート（全体）」と「各ツール（詳細）」の二層構造であり、片方だけ更新しない。**

#### 4. `docs/design/DOC-2608020715-b_テスト方針.md`

- 「前提となる事実」: 配布経路が変わったことを反映する
- 「サンドボックス実行の検証項目」チェックリスト: 孫1〜4 で追加した検証項目を加える
  （消失耐性 / 編集分離 / 世代と GC / ロールバック / dev モード / 配布実体の後片付け）
- **サンドボックス対象ツールの分類（`bin` `claude` のみ。`tmux` `zsh` `nvim` は対象外）は変更しない。**
  この分類の根拠（副作用が `$HOME` の外やネットワークに及ぶか）は今回の変更で変わっていない

#### 5. 運用リファレンスの新規作成（`docs/reference/`）

日々の運用で繰り返し引く事実を書く。`design/` のような行動規範ではなく、調べ物用の記述にすること。

- canonical prefix のディレクトリ構造
- `.dotfiles-manifest` の全フィールド
- 世代の一覧を見る方法、今どの世代が効いているかを調べる方法
- ロールバックの手順
- dev モードの入り方・抜け方・注意点
- リンク切れを見つけたときの対処
- **旧方式（作業ツリー直リンク）からの移行手順**: 既存マシンで何をすればよいか。
  移行後に `.backup` として残りうるもの、残らないもの

**新規ファイルの作り方（`docs/README.md` の3ステップ。省略すると索引から漏れる）**:

1. `docs/README.md`「DOC-ID 命名規則」にあるプレースホルダ名（`DOC-DOCID_PLACEHOLDER_` +
   説明的ファイル名 + `.md`）で作る
2. `./tools/doc-id/doc-id assign docs/reference/<そのファイル名>` で採番する
3. `docs/README.md` の「全 DOC-ID 索引」の `reference/` の表に追記する

なお `doc-id assign` は**採番対象ファイル内のプレースホルダ文字列をすべて置換する**
（`tools/doc-id/lib/doc_id/tool.rb`）。採番するファイルの本文中でプレースホルダ命名そのものを
例示すると巻き込まれるので注意すること。

`docs/README.md` の索引には、本傘で追加された ADR（DOC-2608040229）と計画書も
載っているか確認し、抜けていれば追記すること。

#### 6. 地の文の DOC-ID 言及

`docs/` の文書に言及するときは説明的ファイル名だけで呼ばず、DOC-ID を明示すること
（例: 「テスト方針（DOC-2608020715-b）を参照」）。

### やらないこと

- **実装の変更。** この孫はシェルスクリプトを1行も変えない。文書と実装が食い違っていたら
  文書を実装に合わせ、実装側の問題だと判断した場合は修正せず PR の説明文で報告する
- `claude/CLAUDE.md`（配布物）の編集

### 検証

```
pre-commit run --all-files
./tools/doc-id/doc-id check
./tools/doc-id/doc-id verify
```

文書に書いたコマンド・パス・関数名が実在することを実際に確認すること
（`./deploy-all.sh --help` の出力と README のオプション一覧が一致しているか、など）。
````

## 孫6用プロンプト:

````
## タスク: ocw-meter が symlink 経由の起動で価格表を見失うバグを直す

まず以下を読むこと。

1. 計画書 `docs/planning/DOC-2608040234_ai-deploy-stability_計画.md` の「全孫共通の注意」
2. ADR `docs/adr/DOC-2608040229_deploy-distribution-method.md` §2.6（このバグの検出経緯）

**この孫は他の孫と独立している。** 触るのは `bin/ocw-meter` と `bin/tests/` だけであり、
配布方式の変更とは無関係に単独でマージできる。

### 背景

`bin/ocw-meter` は価格表 `bin/prices/*.json` の位置を次のように決めている。

```sh
OCW_METER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

`BASH_SOURCE[0]` のシンボリックリンクを解決していないため、`~/bin/ocw-meter`（deploy が張った
symlink）経由で起動すると `~/bin/prices` を探しにいき、価格表を見つけられない。
`ocw-meter ingest` の費用計算に影響する。

### 直すもの

`BASH_SOURCE[0]` を辿ってスクリプト本体の実体の位置を求めるようにする。

**移植性の注意**: `readlink -f` は GNU 専用で macOS には無い。使わないこと。
`while [ -L "$src" ]` でリンクを辿り、相対リンクは1つ前のディレクトリ基準で解決する形にする。
`bin/ocw-meter` は bash（`#!/usr/bin/env bash`、`set -euo pipefail`）なので bash の機能は使ってよい。

`OCW_METER_PRICE_DIR` による上書きが引き続き効くこと（テスト・カスタマイズ用の既存の逃げ道）。

### 検証

```
bin/tests/lint.sh
python3 -m unittest discover -s bin/tests -v
pre-commit run --all-files
```

`bin/tests/` に回帰テストを追加すること。**シンボリックリンク経由で起動したときに
価格表ディレクトリが正しく解決されること**を検証する形にする
（一時ディレクトリに `ocw-meter` への symlink を作って起動する、など）。
既存テスト193件が引き続き通ること。

### やらないこと

- 配布方式に関する変更（他孫の担当）
- `bin/prices/*.json` の中身の変更
- `ocw-meter` の機能追加
````

---

## 全孫共通: 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PR を作成する。**PR の向き先は必ず `ai/deploy-stability` にすること。`master` には絶対に出さない。**
2. `/pr-review-loop` を起動する（PR がない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する

実装が終わったタイミングで止まらず、必ずここまでやりきってください。

### ブランチ作成時の注意（最重要）

作業ブランチは**必ず `ai/deploy-stability` から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:

```bash
git checkout ai/deploy-stability && git pull --rebase origin ai/deploy-stability
git checkout -b <新しいブランチ名>
```

### PR 説明文について

[プルリクエストの作法 DOC-2608020715](../design/DOC-2608020715_プルリクエストの作法.md) に従うこと。
ですます調・平易な言葉で、セッション内の固有名詞や個人的な文脈を入れないこと。
