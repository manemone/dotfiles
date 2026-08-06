# 計画書: `ocw` のワークツリー命名とリポジトリレイアウトの外部化

傘ブランチ: `ai/ocw-naming-and-layout`
ターゲット: `master`

## 概要

`bin/ocw` は「ブランチ名は必ず `ai/<slug>`」「ワークツリー名にスラッシュを入れられない」
「`<project>/main` + 兄弟ワークツリーというレイアウト固定」「マージ済み判定は ancestry のみ」の
4つをハードコードで前提にしている。本傘でこの4つをすべて外部化・再定義する。

方式の比較検討と却下理由は **ADR DOC-2608062258**
（[../adr/DOC-2608062258_ocw-worktree-naming-and-layout.md](../adr/DOC-2608062258_ocw-worktree-naming-and-layout.md)）
に記録済み。**孫はまず ADR を読むこと。** この計画書は ADR で確定した方式を実装単位へ分解したものである。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `ai/ocw-01-config-context` | 設定リーダ（git config `ocw.*`）と `init_repo_context()` の再構築（bare 対応・パス雛形の展開と検証・掃除境界の逆算・`repo_name` の解決） | ✅ PR #50 マージ済 |
| 2 | `ai/ocw-02-naming` | 命名（`ai/` 接頭辞の廃止・ブランチ名／ディレクトリ名のサニタイズ分離・`git check-ref-format --branch` による検証・ネストディレクトリでの作成） | 🔄 実装中 |
| 3 | `ai/ocw-03-rm-resolution` | `ocw rm` の porcelain 逆引き解決・曖昧時の停止・空ディレクトリ掃除・マージ済み判定の再定義（squash 検出・基準 ref 候補・`gh` opt-in）・`outcome` の決定方法の修正 | ⬜ 待機中 |
| 4 | `ai/ocw-04-docs` | 文書（`bin/README.md` §3.1 の全面改訂・ルート `README.md` の追随） | ⬜ 待機中 |

## 依存関係と実行順序

```
孫1 (設定リーダ + repo context + パス雛形)
  ↓ worktree_dir の組み立て先が確定しないと命名を移せない
孫2 (接頭辞廃止 + スラッシュ対応 + ネスト作成)
  ↓ ブランチ名とディレクトリ名が別物になってから逆引きを書く
孫3 (rm 逆引き + マージ判定再定義 + outcome)
  ↓ 挙動が全部確定してから文書を書く（先に書くと必ず嘘になる）
孫4 (文書)
```

**全孫が直列。** 4本とも同じ `bin/ocw`（831行）と `bin/tests/test_ocw.py` を深く触るため、
並列に走らせると衝突が避けられない。前の孫がマージされてから次を spawn すること。

---

## 確定事項（孫の判断で覆さないこと）

ADR DOC-2608062258 で決着済み。実装時に蒸し返さない。

| 領域 | 決定 | 根拠 |
|---|---|---|
| ブランチ接頭辞 | **廃止。`ocw.branchPrefix` は作らない** | スラッシュが通れば `ocw ai/foo` で代替できる（ADR §3.1 / §4.2） |
| ブランチ名の検証 | **`git check-ref-format --branch`**。自前の正規表現を書かない | 連続スラッシュ・`.lock`・`..`・`HEAD` 等を git のルールで一括して弾ける（ADR §2.6） |
| 正規化 | 小文字化・記号の `-` 潰しは**残す**。ただし `/` は温存する | 既存の利便性を失わない（ADR §3.2） |
| ディレクトリ命名 | **ネスト**（`feature/foo` → `<root>/feature/foo`） | 作成側の追加コスト0（`worktree add` が親を掘る）、衝突は git の D/F conflict が原理的に防ぐ（ADR §2.4 / §2.5 / §3.3） |
| 設定ソース | **git config `ocw.*`**。環境変数・設定ファイルは使わない | リポジトリごとに別ポリシーを持てる。`.git/config` は全ワークツリーで共有（ADR §3.4） |
| レイアウトの表現 | **フルパス雛形1本 `ocw.worktreeDir`**（既定 `{repo_parent}/{name}`） | enum・2ノブ案より表現力が高く、掃除境界も逆算できる（ADR §3.4 / §4.3 / §4.4） |
| プレースホルダ | `{repo_root}` `{repo_parent}` `{repo}` `{name}` の4つ。未知の `{...}` は `die` | タイプミスを黙って literal のディレクトリ名にしない（ADR §3.4） |
| 自動検出 | **`dirname(repo_root)` の一本だけ**。ディレクトリ名による推測を入れない | 外したときに理由が説明できない（ADR §4.5） |
| 掃除境界 | 雛形の `{name}` より前の**最後の `/` まで**を境界とし、そこまで `rmdir` を遡る。境界自体は消さない | POSIX パラメータ展開だけで逆算できる（ADR §2.9 / §3.5） |
| `repo_name` | `ocw.repoName` > origin URL の basename から `.git` 剥がし > パス推測 | bare の `foo.git`、普通の clone の親ディレクトリ名、どちらの誤りも解消する（ADR §3.6） |
| マージ判定の基準 ref | `ocw.mergedInto` > **作成時の `base_ref`（永続化する）** > bare は `symbolic-ref --short HEAD` / 非 bare は `repo_root` の `HEAD` > `origin/HEAD`。**いずれか1つが「マージ済み」と言えば通す** | 傘ブランチ運用（孫は傘にマージされる）を直接救う（ADR §3.7） |
| squash 検出 | `merge-base` + `commit-tree` + `git cherry` のレシピ。先頭 `-` で適用済み | 実測で4パターン全部正しく判定した（ADR §2.7） |
| `gh` 問い合わせ | `ocw.githubMergeCheck`（既定 `false`）による **opt-in**。失敗は fail-open で無視 | 中核機能をネットワーク・認証に依存させない（ADR §3.7 / §4.6） |
| `run.end` の `outcome` | **マージ判定の結果から決める。`-f` の有無では決めない** | `-f` は拒否のバイパスであって失敗の宣言ではない（ADR §3.8） |
| `ocw rm` の解決 | **`git worktree list --porcelain` からの逆引き**。3段マッチ、同一段で複数ヒットなら候補を並べて `die` | 破壊的操作で推測しない。段3が `ai/*` の移行救済になる（ADR §3.9 / §4.8） |
| `invocation_root` | **取れなくてもよい値にする**。空ならカレント worktree ガードをスキップ | bare では `rev-parse --show-toplevel` が必ず失敗する（ADR §2.1 / §3.10） |

### 検討して却下した案（蒸し返さないこと）

詳細は ADR DOC-2608062258 §4。

- **ディレクトリ名のフラット化** → `feature/foo` と `feature-foo` が同じディレクトリを要求し、理由の分かりにくいエラーになる
- **`ocw.branchPrefix`** → スラッシュが通れば不要
- **レイアウトを enum で表現** → 想定外の構成のたびに enum を増やすことになる
- **レイアウトを2ノブで表現** → 同じ1つの事実が2箇所に分かれる
- **賢い自動検出** → 外したときに理由が説明できない
- **マージ判定を `gh` だけに寄せる** → オフラインで中核機能が動かなくなる
- **`{flat_name}` プレースホルダ** → 現時点で需要がない。必要になったら1個足すだけで済む
- **曖昧一致の自動選択** → `rm` は破壊的操作。推測で対象を選ばない

---

## 全孫共通の注意（プロンプトにも再掲するが、ここが正）

### 1. `AGENTS.md` の最重要ルールに従う

- **人間の明示的指示がない限り `git merge` / `git pull` / `git reset --hard` / `git push --force` /
  `gh pr merge` を実行しない。**
- **deploy スクリプトを実オペレーションで実行しない。** 本傘は `bin/` しか触らないが、
  `pre-commit` のフックが `./deploy-all.sh --dry-run` を走らせる点は変わらない。
- **linter の抑制ディレクティブ（`# shellcheck disable=...` 等）を AI の判断で追加しない。**
  指摘が設計上不合理だと判断したら、抑制せず内容・対象・理由を人間に報告する。
  コードの構造を変えて指摘そのものを解消できるならそちらを優先する。
- **指示された範囲外の機能を先回りして実装しない。**

### 2. `bin/ocw` は bash（`#!/usr/bin/env bash`, `set -euo pipefail`）

- [docs/design/DOC-2608020715-a_シェルスクリプトコーディング方針.md](../design/DOC-2608020715-a_シェルスクリプトコーディング方針.md)
  に従う
- **macOS（BSD/bash 3.2）互換を壊さない。** 連想配列（`declare -A`）・`${var,,}`・`mapfile` /
  `readarray` は bash 4 以降であり**使えない**。直近の PR #49 がまさにこの非互換の解消であり、
  同じ轍を踏まないこと
- BSD と GNU で挙動が違うコマンド（`sed -i` / `date` / `readlink -f` / `realpath -m`）に注意する。
  `bin/ocw` には既に `realpath_m()` という BSD 互換の自前実装がある
- `set -e` 下で終了ステータス非0が正常系になる箇所（`git config --get` の未設定、
  `merge-base --is-ancestor` の偽）は必ず `|| true` / `if` で受ける

### 3. テストは黒箱（既存方式を維持する）

`bin/tests/test_ocw.py` は tempdir に使い捨てリポジトリを作り、実 `bin/ocw` を subprocess で叩く方式。
**この方式を変えない。** また既存の2重の VS Code 誤起動防止（`_CODE_SHIM_DIR` と `OCW_NO_VSCODE`）を
**絶対に外さない**。過去に実際に VS Code のウィンドウが大量に開いた事故がある。

### 4. 検証（省略しない。省略してよいのは人間が明示的に指示した場合のみ）

```
pre-commit run --all-files
python3 -m unittest discover -s bin/tests -v      # 193件・約40秒（本傘で増える）
bin/tests/lint.sh
```

### 5. PR の作法

[docs/design/DOC-2608020715_プルリクエストの作法.md](../design/DOC-2608020715_プルリクエストの作法.md)
を PR 作成前に読むこと。**PR の向き先は必ず傘ブランチ `ai/ocw-naming-and-layout`。master には出さない。**

---

## 孫1用プロンプト:

````
`bin/ocw` の設定機構とリポジトリコンテキスト解決を再構築してください。

## 最初に読むもの（順番に）

1. リポジトリルートの `AGENTS.md`（最重要ルール）
2. `docs/adr/DOC-2608062258_ocw-worktree-naming-and-layout.md`（本傘の技術決定。ここが正典）
3. `docs/planning/DOC-2608062259_ai-ocw-naming-and-layout_計画.md`（この計画書。「確定事項」と「全孫共通の注意」を必ず読む）
4. `docs/design/DOC-2608020715-a_シェルスクリプトコーディング方針.md`
5. `bin/ocw`（831行。全量読むこと）と `bin/tests/test_ocw.py`

## この孫のスコープ

**設定の読み取りと、リポジトリコンテキストの解決だけ。** 命名（`ai/` 接頭辞・スラッシュ）と
`ocw rm` の逆引きは孫2・孫3の担当なので触らないこと。

### 1. 設定リーダを新設する

git config から `ocw.*` を読むヘルパを作る。`set -euo pipefail` 下なので、
未設定キーで `git config --get` が exit 1 を返す点を必ず受けること
（実測: `git config --get --type=bool --default=false <key>` は未設定でも exit 0 で `false` を返す）。

読み取りは `git -C "$repo_root" config ...` で行う。`.git/config` は全ワークツリーで共有されるため、
どのワークツリーから叩いても同じ値が効く。bare でも同様に読める。

対象キー（ADR §3.4 の全4個。この孫では `worktreeDir` と `repoName` を実際に使い、
`mergedInto` / `githubMergeCheck` は孫3が使う）:

- `ocw.worktreeDir`（既定 `{repo_parent}/{name}`）
- `ocw.repoName`（既定は自動解決）
- `ocw.mergedInto`（既定は自動解決）
- `ocw.githubMergeCheck`（bool、既定 `false`）

### 2. `init_repo_context()` を bare 対応に作り直す

現状の1行目 `git rev-parse --show-toplevel` は **bare で必ず `fatal:` で落ちる**（実測済み）。

- `invocation_root` は**取れなくてもよい値**にする。取れなければ空文字にし、後段（孫3が触る
  カレント worktree ガード）がそれを見てスキップできるようにする
- `repo_root` は現行どおり `git worktree list --porcelain` の先頭 `worktree ` 行から取る
  （bare でも先頭エントリは出る。`branch` 行が無く `bare` 行が出るだけ。実測済み）
- bare 判定を `git -C "$repo_root" rev-parse --is-bare-repository` で行い、変数に持つ
- 「run ocw from inside a Git worktree」というエラーメッセージを、Git リポジトリの中から実行する旨に改める

### 3. `repo_name` の解決順を実装する（ADR §3.6）

1. `ocw.repoName` が設定されていればそれ
2. `remote.origin.url` の basename から `.git` を剥がしたもの
3. パス推測: bare なら `basename(repo_root)` の `.git` 剥がし /
   `basename(repo_root)` が `main` `master` `trunk` なら `basename(dirname(repo_root))` /
   それ以外は `basename(repo_root)`

### 4. `ocw.worktreeDir` の雛形展開・検証・掃除境界の逆算を実装する（ADR §3.4 / §3.5 / §2.9）

プレースホルダは `{repo_root}` `{repo_parent}` `{repo}` `{name}` の4つ。

- 先頭の `~` は `$HOME` へ展開する
- 展開後が絶対パスでなければ `die`
- **未知のプレースホルダ（`{foo}` 等）は黙って literal にせず `die`**（タイプミスを握り潰さない）
- 雛形に `{name}` が無ければ `die`
- 掃除境界は「`{name}` より前の最後の `/` まで」。**POSIX パラメータ展開だけで逆算できる**
  （正規表現も外部コマンドも要らない。実測済み）:

  ```
  prefix="${tmpl%%\{name\}*}"      # {name} 以降を切る
  boundary_tmpl="${prefix%/*}"      # 最後の / までに詰める
  ```

  `{name}` の前に `/` が無い雛形（例: `{name}` 単体）は境界が定義できないので `die`

  逆算結果（実測。テストの期待値にそのまま使える）:

  | 雛形 | 境界 |
  |---|---|
  | `{repo_parent}/{name}` | `{repo_parent}` |
  | `{repo_root}/.worktrees/{name}` | `{repo_root}/.worktrees` |
  | `~/.cache/ocw/{repo}/{name}` | `~/.cache/ocw/{repo}` |
  | `{repo_parent}/{repo}-{name}` | `{repo_parent}` |

- 展開済みの境界は変数として持たせる（孫3の空ディレクトリ掃除がこれを上限に使う）

### 5. 既存の呼び出し側を新しいコンテキストへ繋ぎ替える

`create_worktree()` の `worktree_dir="${project_dir}/${slug}"` を雛形展開経由に変える。
`remove_worktree()` 側も同様に繋ぎ替えるが、**逆引き化は孫3の担当**なので、この孫では
「同じパスが出る」ところまでで止めること。

### 6. `base_ref` の既定値を bare 対応にする（ADR §3.10）

`refs/remotes/origin/HEAD` が引けなければ `git symbolic-ref --short HEAD` へフォールバックし、
それも駄目なら `main`。

## 重要: この孫では既定挙動を一切変えない

`ai/` 接頭辞は**まだ残す**（孫2の担当）。`ocw.worktreeDir` 無設定時のワークツリー作成先は
`{repo_parent}/{name}` であり、これは現行の `dirname(repo_root)/<slug>` と**完全に同一**でなければ
ならない。既存テストが1件も落ちないことが、この孫の正しさの主要な根拠になる。

## テスト（`bin/tests/test_ocw.py`）

既存の `make_repo()`（`<root>/main` + bare origin）は**そのまま残す**（現行レイアウトの回帰検出に要る）。
加えて次を用意すること:

- `make_bare_repo(root)`: `<root>/proj.git`（bare）を作り、そこにコミットが入っている状態。
  ワークツリーは `<root>/<name>` に作られる（無設定で通ることの確認）
- 雛形を効かせた構成を作るヘルパ（`git config ocw.worktreeDir ...` を叩くだけでよい）

追加するテスト:

- bare リポジトリの中から `ocw <name>` が成功し、`<root>/<name>` に worktree ができる
- bare で `ocw ls` が動く
- `ocw.worktreeDir = {repo_root}/.worktrees/{name}` で作成先が変わる
- `ocw.worktreeDir = ~/.cache/...` の `~` 展開が効く（`HOME` を tempdir に差し替えて確認する。
  **実 `$HOME` に書かないこと**）
- 未知プレースホルダ `{nope}` を含む雛形で `die` し、stderr にキー名が出る
- `{name}` を含まない雛形で `die`
- 相対パスになる雛形で `die`
- `repo_name` の解決: `ocw.repoName` 設定時 / origin URL からの導出 / bare での `.git` 剥がし
  （`repo:` 行の出力を見れば黒箱で確認できる）

## 完了条件

- `pre-commit run --all-files` が通る
- `python3 -m unittest discover -s bin/tests -v` が全件通る（既存193件 + 追加分）
- `bin/tests/lint.sh` が通る
- `bash -n bin/ocw` が通る
- **既定設定での挙動が現行と同一**であることを、既存テストが無改変で通ることで示せている

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:
1. PRを作成する。**PRの向き先は必ず `ai/ocw-naming-and-layout` にすること。master には絶対に出さない。**
2. /pr-review-loop を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する
実装が終わったタイミングで止まらず、必ずここまでやりきってください。

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `ai/ocw-naming-and-layout` から切ること**。
master から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:
git checkout ai/ocw-naming-and-layout && git pull --rebase origin ai/ocw-naming-and-layout
git checkout -b ai/ocw-01-config-context
````

## 孫2用プロンプト:

````
`bin/ocw` の命名規則を変更してください（`ai/` 接頭辞の廃止とスラッシュ対応）。

## 最初に読むもの（順番に）

1. リポジトリルートの `AGENTS.md`（最重要ルール）
2. `docs/adr/DOC-2608062258_ocw-worktree-naming-and-layout.md`（本傘の技術決定。ここが正典）
3. `docs/planning/DOC-2608062259_ai-ocw-naming-and-layout_計画.md`（この計画書。「確定事項」と「全孫共通の注意」を必ず読む）
4. `docs/design/DOC-2608020715-a_シェルスクリプトコーディング方針.md`
5. `bin/ocw`（孫1でリポジトリコンテキストと設定リーダが入っている。全量読むこと）と `bin/tests/test_ocw.py`

## この孫のスコープ

**作成側の命名だけ。** `ocw rm` の逆引き解決とマージ判定は孫3の担当なので触らないこと
（`rm` が孫1の状態のまま壊れずに動いていればよい。ただし後述の「移行の注意」を読むこと）。

### 1. `ai/` 接頭辞を廃止する（ADR §3.1）

`branch="ai/${slug}"` を `branch="${slug}"` にする（`create_worktree()` 側）。

**`ocw.branchPrefix` のような設定は作らないこと。** ADR §4.2 で明示的に却下している。
スラッシュが通るようになるので `ocw ai/foo` と打てば同じことができる。

### 2. サニタイズをブランチ名用とディレクトリ名用に分ける（ADR §3.2 / §3.3）

現状の `normalize_name()`（`bin/ocw:87`）は `[^a-z0-9._-]+` を `-` に潰しており、`/` も潰れている。

- **ブランチ名用**: 小文字化・記号の `-` 潰し・前後の区切り除去は**残す**が、**`/` は温存する**。
  連続する `/` の潰し込みや前後の `/` `-` 除去も行う
- **ディレクトリ名用**: ネスト方針（ADR §3.3）により**ブランチ名そのもの**。
  つまり `{name}` にはスラッシュが入ったまま渡る

### 3. ブランチ名の検証を `git check-ref-format --branch` に委ねる（ADR §3.2 / §2.6）

**自前の正規表現を書かないこと。** 正規化後の候補名をこれに通し、拒否されたら
git 自身の `fatal:` メッセージを添えて `die` する。

実測で以下が正しく弾かれることを確認済み: `feature//foo`（連続スラッシュ）、`foo.lock`、
`-x`（先頭ハイフン）、`HEAD`、`@{-1}`。`..` や先頭 `/` も弾かれるため、
**`{name}` をパスに埋め込む際のパストラバーサル安全性もこの検証に委ねられる。**

`set -euo pipefail` 下なので、`check-ref-format` の非0終了を必ず `if` / `|| ` で受けること。

### 4. ネストしたディレクトリでの作成

`git worktree add` は**親ディレクトリを自動で生成する**（実測済み）。`mkdir -p` は書かないこと。

ディレクトリ衝突（`feature` と `feature/foo`）は git の D/F conflict が原理的に防ぐ（実測済み）ため、
そのための追加チェックも書かないこと。既存の `[ ! -e "$worktree_dir" ]` チェックは残す。

### 5. 表示の追随

`create_worktree()` の `branch:` / `worktree:` 行が新しい値を出すことを確認する。
Herdr のワークスペースラベル（`${repo_name} / ${slug}`）に何を使うかも確認すること
（スラッシュ入りの名前が入る）。

## 移行の注意（既存の `ai/*` ワークツリーを壊さない）

この孫の後、既存の手元の `ai/foo` ワークツリーは `ocw rm foo` で消せなくなる
（`rm` はまだ入力から再計算しているため）。**これを救うのは孫3の逆引き解決であり、この孫の責務ではない。**
ただし PR 説明文にこの過渡状態を明記すること（傘の中でだけ発生し、傘のマージ時には解消している）。

## テスト（`bin/tests/test_ocw.py`）

既存テストのうちブランチ名を前提にしているものは、**期待値を新しい命名に更新する**
（挙動が変わるのが仕様なので、テストを緩めるのではなく期待値を正しく直す）。

追加するテスト:

- `ocw feature/foo` でブランチ `feature/foo` ができ、worktree が `<root>/feature/foo` にできる
- 同じ親を共有する2本（`feature/foo` と `feature/bar`）が両方作れる
- `ocw foo` でブランチが `foo`（`ai/foo` ではない）になる
- 大文字・空白入りの入力が従来どおり正規化される（`ocw "Fix The Thing"` → `fix-the-thing`）
- 不正なブランチ名で `die` する: `feature//foo` / `foo.lock` / `HEAD` / 先頭ハイフン
- 正規化後に空になる入力で `die` する
- `..` を含む入力が `check-ref-format` に弾かれ、リポジトリ外にディレクトリが作られない

## 完了条件

- `pre-commit run --all-files` が通る
- `python3 -m unittest discover -s bin/tests -v` が全件通る
- `bin/tests/lint.sh` が通る
- `bash -n bin/ocw` が通る

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:
1. PRを作成する。**PRの向き先は必ず `ai/ocw-naming-and-layout` にすること。master には絶対に出さない。**
2. /pr-review-loop を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する
実装が終わったタイミングで止まらず、必ずここまでやりきってください。

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `ai/ocw-naming-and-layout` から切ること**。
master から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:
git checkout ai/ocw-naming-and-layout && git pull --rebase origin ai/ocw-naming-and-layout
git checkout -b ai/ocw-02-naming
````

## 孫3用プロンプト:

````
`bin/ocw` の `ocw rm` を逆引き解決に作り直し、マージ済み判定を再定義してください。

## 最初に読むもの（順番に）

1. リポジトリルートの `AGENTS.md`（最重要ルール）
2. `docs/adr/DOC-2608062258_ocw-worktree-naming-and-layout.md`（本傘の技術決定。ここが正典。特に §2.7 と §3.7〜§3.9）
3. `docs/planning/DOC-2608062259_ai-ocw-naming-and-layout_計画.md`（この計画書。「確定事項」と「全孫共通の注意」を必ず読む）
4. `docs/design/DOC-2608020715-a_シェルスクリプトコーディング方針.md`
5. `docs/reference/DOC-2608021229-c_ocw-meterイベントスキーマ.md`（`run.end` の `outcome` を触るため）
6. `bin/ocw`（孫1・孫2の成果が入っている。全量読むこと）と `bin/tests/test_ocw.py`

## この孫のスコープ

`ocw rm` の対象解決・マージ判定・空ディレクトリ掃除・`run.end` の `outcome` 決定。

### 1. 対象の解決を porcelain 逆引きにする（ADR §3.9）

現状の `remove_worktree()` は「入力 slug → ブランチとパスを**再計算**」する一方向の作り。
これを捨て、`git -C "$repo_root" worktree list --porcelain` から `(path, branch)` の対を作って照合する。

porcelain の形式（実測）:

```
worktree /path/to/main
HEAD <sha>
branch refs/heads/main

worktree /path/to/feature/foo
HEAD <sha>
branch refs/heads/feature/foo
```

bare リポジトリのエントリは `branch` 行が無く `bare` 行が出る。detached なワークツリーは
`detached` 行が出る。**メインワークツリーと bare エントリは削除候補から除外すること。**

段階マッチ（**先に非空になった段の結果を採用する**）:

| 段 | 条件 |
|---|---|
| 1 | ブランチ名の完全一致／パスの完全一致／掃除境界からの相対パス一致 |
| 2 | ディレクトリの `basename` 一致 |
| 3 | ブランチが `*/<入力>` で終わる |

**同一段で複数ヒットしたら、候補のパスとブランチを並べて `die` する。勝手に1つ選ばないこと**
（`rm` は破壊的操作。ADR §4.8）。

**入力は正規化せずそのまま照合する**（利用者は実在する名前を打っているため）。

**段3が `ai/*` の移行救済である。** 接頭辞廃止後も既存の `ai/foo` ワークツリーが `ocw rm foo` で
消せることを、テストで必ず担保すること。

### 2. マージ済み判定を再定義する（ADR §3.7）

現状の `git -C "$repo_root" merge-base --is-ancestor "$branch" HEAD` を置き換える。

**基準 ref（integration ref）の候補を順に集め、解決できないものは黙って飛ばす:**

1. `ocw.mergedInto`（設定。孫1の設定リーダで読める）
2. **作成時の `base_ref`** — `create_worktree()` で `ocw-run-id` を書いている隣（
   `git -C "$worktree_dir" rev-parse --absolute-git-dir` が指すディレクトリ）に
   `ocw-base-ref` として保存し、`rm` 側で読み戻す。
   **この保存も本孫の担当。** 既存の `ocw-run-id` 書き込みと同じ fail-open の作法に揃えること
   （`2>/dev/null` を `>file` より**前**に置く。理由は既存コードのコメントに書いてある）
3. bare なら `git symbolic-ref --short HEAD` / 非 bare なら `repo_root` の `HEAD`（**現行挙動の保存**）
4. `git symbolic-ref --short refs/remotes/origin/HEAD`

**1つも解決できなければ「基準が決まらない」として `die` し、`ocw.mergedInto` の設定か `-f` を案内する。**

**各候補に対して次を順に試し、いずれかが真ならマージ済みとする。候補のどれか1つでもマージ済みと
言えば全体としてマージ済み:**

a. `git merge-base --is-ancestor "$branch" "$candidate"`

b. **squash 検出**（ADR §2.7。実測で4パターン全部正しく判定した）:

   ```sh
   base=$(git merge-base "$candidate" "$branch")
   tree=$(git rev-parse "${branch}^{tree}")
   dangling=$(GIT_AUTHOR_NAME=ocw GIT_AUTHOR_EMAIL=ocw@invalid \
              GIT_COMMITTER_NAME=ocw GIT_COMMITTER_EMAIL=ocw@invalid \
              git commit-tree "$tree" -p "$base" -m _)
   git cherry "$candidate" "$dangling"    # 出力の先頭が '-' なら適用済み
   ```

   作者情報の env 注入は必須（未設定リポジトリで `commit-tree` が失敗するため）。
   このレシピはどこかで失敗したら「検出できなかった」として扱い、**`ocw` 自体を落とさないこと**。

c. `ocw.githubMergeCheck` が真かつ `gh` が PATH にある場合のみ、
   `gh pr list --head "$branch" --state merged` が1件以上ならマージ済み。
   **fail-open**: `gh` の失敗・未認証・ネットワーク不通は「判定できなかった」として無視する

### 3. `run.end` の `outcome` を判定結果から決める（ADR §3.8）

現状は `-f` の指定をそのまま `outcome: failure` に変換している（`bin/ocw:754-757` 付近）。これをやめる。

```
outcome = マージ済みと判定できた → success
          そうでない             → failure
```

**`-f` は判定をスキップさせない**（拒否をスキップさせるだけ）。`-f` 指定時も判定は実行し、
その結果で `outcome` を決める。これが「squash 済みなのに `-f` を強いられ、メトリクスに失敗が
記録される」問題の直接の修正である。

### 4. 空ディレクトリの掃除（ADR §3.5）

worktree 削除後、そのディレクトリの親から**孫1が用意した掃除境界に達するまで** `rmdir` を遡る。
`rmdir` が失敗した時点で止める（非空なら失敗するので、他のワークツリーが残っている親は消えない）。
**境界そのものは絶対に削除しない。** `rm -rf` は使わない（`rmdir` のみ）。

### 5. カレントワークツリーガードの追随

`invocation_root` は孫1で**空になりうる値**になっている（bare ディレクトリから叩いた場合）。
空なら比較をスキップすること。`realpath_m()` に空文字を渡さないよう注意。
エラーメッセージ中の `ocw rm ${slug}` の案内も、解決済みの名前を使うよう追随させる。

## テスト（`bin/tests/test_ocw.py`）

追加するテスト:

**逆引き解決:**
- ブランチ名で消せる（`ocw rm feature/foo`）
- ディレクトリの basename で消せる（`ocw rm foo`）
- 絶対パスで消せる
- **移行救済**: `git worktree add -b ai/legacy ...` で作った旧形式のワークツリーが `ocw rm legacy` で消せる
- 曖昧（`feature/foo` と `hotfix/foo` が両方あるときの `ocw rm foo`）で `die` し、
  **stderr に両方の候補が出る**。かつ**どちらのワークツリーも消えていない**
- メインワークツリーを名指ししても削除候補にならない
- 存在しない名前で `die` する

**マージ判定:**
- **squash マージ済みブランチが `-f` なしで消せる**（`git merge --squash` + `commit` で作る）
- 未マージブランチは従来どおり `-f` なしでは消せない
- 通常の（ancestry で追える）マージ済みブランチは従来どおり消せる
- `ocw.mergedInto` を別ブランチに設定すると、そこへのマージで判定が通る
- **傘ブランチ相当のケース**: `base` ブランチから切った worktree を作り、その `base` にだけ
  マージした状態で `-f` なしで消せる（`ocw-base-ref` が効いていることの確認）
- bare リポジトリでマージ判定が動く（`symbolic-ref HEAD` が基準になる）
- `ocw.githubMergeCheck=true` で `gh` が PATH に無いときに落ちない（fail-open）

**outcome:**
- squash マージ済みを `-f` で消したとき `run.end` の `outcome` が **`success`**（現状は `failure`）
- 本当に未マージなものを `-f` で消したとき `outcome` が `failure`（従来どおり）

**掃除:**
- `feature/foo` を消すと空になった `feature/` も消える
- `feature/foo` と `feature/bar` があるとき、片方を消しても `feature/` は残る
- 掃除境界（既定なら `{repo_parent}`）自体は消えない

**注意**: `gh` を使うテストは、`gh` を PATH から外した状態（既存の `BASE_PATH_DIRS` の作法）で
fail-open だけを確認すること。**実際に GitHub へ問い合わせるテストは書かない。**

## 完了条件

- `pre-commit run --all-files` が通る
- `python3 -m unittest discover -s bin/tests -v` が全件通る
- `bin/tests/lint.sh` が通る
- `bash -n bin/ocw` が通る

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:
1. PRを作成する。**PRの向き先は必ず `ai/ocw-naming-and-layout` にすること。master には絶対に出さない。**
2. /pr-review-loop を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する
実装が終わったタイミングで止まらず、必ずここまでやりきってください。

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `ai/ocw-naming-and-layout` から切ること**。
master から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:
git checkout ai/ocw-naming-and-layout && git pull --rebase origin ai/ocw-naming-and-layout
git checkout -b ai/ocw-03-rm-resolution
````

## 孫4用プロンプト:

````
本傘（`ai/ocw-naming-and-layout`）で変わった `ocw` の仕様を文書へ反映してください。

## 最初に読むもの（順番に）

1. リポジトリルートの `AGENTS.md`（最重要ルール）
2. `docs/adr/DOC-2608062258_ocw-worktree-naming-and-layout.md`（本傘の技術決定）
3. `docs/planning/DOC-2608062259_ai-ocw-naming-and-layout_計画.md`（この計画書）
4. **`bin/ocw` の実装そのもの**（孫1〜3 がマージ済み。文書は ADR ではなく**実装**に合わせること。
   食い違いがあれば実装を正とし、その食い違い自体を人間に報告する）
5. `bin/README.md` と ルート `README.md`

## この孫のスコープ

**文書のみ。** `bin/ocw` と `bin/tests/test_ocw.py` は変更しない
（読んで内容を確認するのが仕事）。

### 1. `bin/README.md` §3.1（`ocw`）を全面改訂する

書くべきこと:

- **設定キー4つの一覧**（`ocw.worktreeDir` / `ocw.repoName` / `ocw.mergedInto` /
  `ocw.githubMergeCheck`）。既定値・意味・`git config` での設定例
- **`ocw.worktreeDir` のプレースホルダ4つ**（`{repo_root}` `{repo_parent}` `{repo}` `{name}`）と
  `~` 展開。未知プレースホルダがエラーになること
- **レイアウトの実例表**（現行の兄弟構成 / bare + 同階層 / リポジトリ内に隠す / 中央プール /
  接頭辞付き）。**現行構成と bare + 同階層は無設定で通る**ことを明記
- **スラッシュ入りのブランチ名**が使えること、ディレクトリがネストすること、
  `ocw rm` 後に空の親ディレクトリが掃除されること
- **`ai/` 接頭辞が廃止されたこと**と、既存の `ai/*` ワークツリーが
  `ocw rm <接頭辞なしの名前>` で消せること（移行の救済）
- **`ocw rm` の解決規則**（3段マッチ・曖昧なら停止して候補を表示）
- **マージ済み判定の意味論**: 基準 ref の候補の順番、ancestry と squash 検出の2段、
  `gh` は opt-in。そして**検出できない限界**（squash 後に rebase / amend された、
  マージ時の衝突解決で diff が変わった）を正直に書く
- **`run.end` の `outcome` が `-f` の有無ではなくマージ判定から決まること**。
  既存の §3.1 には「`ocw rm -f` は…その `outcome` は `failure`」と書いてあり、
  **これは現状の記述として誤りになるので必ず直すこと**

### 2. ルート `README.md` の追随

`bin/` の1行説明と、`ocw` に言及している箇所（139行目付近のツリー、195行目・206行目・213行目付近の
worktree 運用に関する注記）を確認し、嘘になっている記述があれば直す。
**ルートは全体像、`bin/README.md` は詳細**という二層構造を崩さないこと。

### 3. 実装との突き合わせ

書く前に `bin/ocw` の該当箇所を読み、**実装が実際にそうなっていることを確認してから書くこと。**
ADR は決定の記録であって実装の保証ではない。食い違いを見つけたら文書を実装に合わせ、
その事実を PR 説明文に書いて人間に報告する。

## 完了条件

- `pre-commit run --all-files` が通る（`doc-id check` / `verify` を含む）
- `bin/README.md` と ルート `README.md` に、実装と食い違う記述が残っていない
- `ocw rm -f` の `outcome` に関する旧記述が修正されている

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:
1. PRを作成する。**PRの向き先は必ず `ai/ocw-naming-and-layout` にすること。master には絶対に出さない。**
2. /pr-review-loop を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する
実装が終わったタイミングで止まらず、必ずここまでやりきってください。

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `ai/ocw-naming-and-layout` から切ること**。
master から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:
git checkout ai/ocw-naming-and-layout && git pull --rebase origin ai/ocw-naming-and-layout
git checkout -b ai/ocw-04-docs
````

---

## 傘の完了条件

- 孫1〜4 がすべて `ai/ocw-naming-and-layout` にマージ済み
- 傘ブランチ上で以下がすべて通る:
  - `pre-commit run --all-files`
  - `python3 -m unittest discover -s bin/tests -v`
  - `bin/tests/lint.sh`
- **無設定（既定）での挙動が、次の3点を除いて現行と同一である**
  1. ブランチ名に `ai/` が付かない
  2. squash マージ済みブランチが `-f` なしで削除できる
  3. `run.end` の `outcome` が `-f` の有無ではなくマージ判定から決まる
- bare リポジトリ + 同階層ワークツリーの構成が**無設定で**動作する
- 既存の `ai/*` ワークツリーが `ocw rm <接頭辞なしの名前>` で削除できる
- `bin/README.md` と ルート `README.md` が実装と一致している
