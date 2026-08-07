# DOC-2608062258: `ocw` のワークツリー命名とリポジトリレイアウトの外部化

- **Status**: Accepted
- **Date**: 2026-08-06
- **Decision by**: 傘 `ai/ocw-naming-and-layout` の調査フェーズ（`bin/ocw` の全量読解 + 使い捨てリポジトリでの実測）

> これは ADR（Architecture Decision Record）である。実測・調査に基づいて確定した技術的決定の記録であり、
> 原則として変更しない（新しい決定は新しい ADR を追加する）。

---

## 1. Context

`bin/ocw` は「git worktree を作り、ブランチを切り、（任意で）Herdr のワークスペースを立てる」ツールである。
現状、次の4つを**ハードコードで前提**にしている。

### 1.1 ブランチ名は必ず `ai/<slug>`

`bin/ocw:446` / `bin/ocw:705` の `branch="ai/${slug}"`。接頭辞に実用上の意味がない。

### 1.2 ワークツリー名にスラッシュを入れられない

`normalize_name()`（`bin/ocw:87`）が `[^a-z0-9._-]+` を `-` に潰すため、`ocw feature/foo` は
ブランチ `ai/feature-foo` になる。**ブランチ名の名前空間（`feature/`, `hotfix/`）を使えない。**

さらに `remove_worktree()` は「入力 slug → `ai/<slug>` と `<project_dir>/<slug>` を**再計算**する」一方向の
作りになっている。ディレクトリ名とブランチ名が別物になった瞬間、この再計算は成立しない。

### 1.3 リポジトリレイアウトが1種類に決め打ち

`init_repo_context()`（`bin/ocw:184`）が

```
repo_root    = git worktree list --porcelain の先頭エントリ（メインワークツリー）
project_dir  = dirname(repo_root)
repo_name    = basename(project_dir)
worktree_dir = project_dir/<slug>
```

を無条件で組み立てる。つまり **`<project>/main` と `<project>/<slug>` が並ぶ構成**しか扱えない。
bare リポジトリをベースにした運用、リポジトリ内に worktree を隠す運用、中央プールに集める運用は表現できない。

### 1.4 マージ済み判定が ancestry しか見ない

`bin/ocw:741` の `git -C "$repo_root" merge-base --is-ancestor "$branch" HEAD`。次の2つの問題がある。

1. **squash マージを検出できない。** GitHub の squash merge は孫ブランチのコミットを履歴に残さないため、
   ancestry 判定は**必ず落ちる**。実際にマージ済みの worktree を `ocw rm` で消せず、`-f` を強いられる。
2. **`HEAD` が「メインワークツリーのチェックアウト」を前提にしている。** bare では意味が変わる。
   またメインワークツリーが別ブランチに居るとき、判定は無意味な比較になる。

加えて `remove_worktree()` は **`-f` が指定されたことをそのまま `run.end` の `outcome: failure` に変換**
している（`bin/ocw:754-757`）。1 の理由で `-f` を使わされた結果、**マージ済みの成功した run が
メトリクス上「失敗」として記録される**。工程効率の集計（`ocw-meter` の process efficiency）が壊れる。

---

## 2. 調査で確定した事実

決定の前提になった事実。いずれも本 ADR を書いた時点で、使い捨てリポジトリに対して実測したものである。

### 2.1 bare リポジトリでは `git rev-parse --show-toplevel` が失敗する

```
$ git -C proj.git rev-parse --show-toplevel
fatal: this operation must be run in a work tree   (exit 128)
```

`init_repo_context()` の1行目がこれである。**bare 対応の最初の壁はここ**であり、
`invocation_root` を必須にしている限り bare では何もできない。

`invocation_root` の唯一の用途は `remove_worktree()` の「今いる worktree を消そうとしていないか」ガードで
ある。bare ディレクトリにはワークツリーが無いため、この値は**空でよい**（空なら比較をスキップする）。

### 2.2 bare でも `git worktree list --porcelain` の先頭エントリは取れる

```
$ git -C proj.git worktree list --porcelain
worktree /tmp/xxx/proj.git
bare
```

`branch` 行が無く `bare` 行が出る点だけが違い、**`repo_root` を先頭の `worktree ` 行から取る現行ロジックは
そのまま使える**。bare 判定は `git -C "$repo_root" rev-parse --is-bare-repository` で行える。

### 2.3 bare でも既定ブランチは `git symbolic-ref HEAD` から取れる

```
$ git -C proj.git symbolic-ref HEAD
refs/heads/main
```

bare における「HEAD」の自然な意味は**そのリポジトリの既定ブランチ**であり、マージ判定・`base_ref` の
既定値の両方でこれを使える。

### 2.4 `git worktree add` はネストした親ディレクトリを自動生成する

```
$ git -C main worktree add -b feature/foo ../feature/foo main
Preparing worktree (new branch 'feature/foo')
$ ls ..
feature/  main/
```

**ネスト案の作成側に追加コードは要らない。** `mkdir -p` は不要。

### 2.5 ディレクトリ名の衝突は git 自身が防ぐ

`refs/heads/feature/foo` が存在する状態で `git branch feature` を作ろうとすると git が拒否する。

```
fatal: cannot lock ref 'refs/heads/feature': 'refs/heads/feature/foo' exists;
       cannot create 'refs/heads/feature'
```

これは git の D/F（directory/file）conflict であり、**ブランチ名をそのままディレクトリ階層に写す限り、
ディレクトリの衝突は原理的に起こり得ない**ことを意味する。

### 2.6 `git check-ref-format --branch` は自前正規表現より確実

実測で以下をすべて拒否した（いずれも exit 128 + `fatal:` メッセージ）。

| 入力 | 結果 |
|---|---|
| `feature/foo` | 通過（stdout に `feature/foo`） |
| `feature//foo` | 拒否（連続スラッシュ） |
| `foo.lock` | 拒否（`.lock` 末尾） |
| `-x` | 拒否（先頭ハイフン） |
| `HEAD` | 拒否 |
| `@{-1}` | 拒否 |

`..` `~` `^` `:` 等の禁止文字も git のルールで一括して弾かれる。
**`{name}` をパスに埋め込む際のパストラバーサル安全性も、この検証に委ねられる**
（`..` と先頭 `/` が弾かれるため）。

### 2.7 squash マージは `commit-tree` + `git cherry` で検出できる

```sh
base=$(git merge-base "$integration" "$branch")
tree=$(git rev-parse "${branch}^{tree}")
dangling=$(git commit-tree "$tree" -p "$base" -m _)   # 作者情報は env で固定値を注入
git cherry "$integration" "$dangling"                  # 先頭が '-' なら適用済み
```

実測結果（`feat` を `main` へ squash マージした状態から）:

| 状況 | `merge-base --is-ancestor` | 上記レシピ |
|---|---|---|
| squash マージ直後 | ✗ 未マージ判定 | `-`（適用済み）✅ |
| その後 `main` に無関係コミットが乗った | ✗ | `-` ✅ |
| その後 `main` で**同じファイル**を編集した | ✗ | `-` ✅ |
| 一度もマージしていないブランチ（対照） | ✗ | `+`（未適用）✅ |

`git cherry` は patch-id で比較するため、後から integration 側が変化しても
**squash コミット自身の patch-id は変わらない**。これが3行目が通る理由である。

**限界**（検出できないケース。README に明記する）:

- squash 後に integration 側で rebase / amend されて patch-id が変わった
- マージ時の衝突解決で diff が変わった
- 空のブランチ（差分ゼロ）— ただしこれは ancestry 判定側が先に通す

`git commit-tree` は dangling なコミットオブジェクトを1個作る。到達不能なので次回以降の `git gc` で
回収される。副作用として残るのはこれだけである。
作者・コミッタ情報が未設定のリポジトリでは `commit-tree` が失敗しうるため、
`GIT_AUTHOR_*` / `GIT_COMMITTER_*` を固定値で注入して呼ぶ。

### 2.8 `git config --get --type=bool --default=false` は未設定でも exit 0 を返す

```
$ git config --get ocw.nonexistent || true          # 未設定は exit 1。set -e 下では || true が要る
$ git config --get --type=bool --default=false ocw.nonexistentBool
false                                                # exit 0
```

`set -euo pipefail` 下で config を読むときの作法がこれで確定する。

### 2.9 パス雛形の「掃除境界」は POSIX パラメータ展開だけで逆算できる

`{name}` より前の最後の `/` までを取れば、`{name}` に依存しない最長の接頭辞が得られる。
正規表現も外部コマンドも不要（実測）。

| 雛形 | 逆算される境界 |
|---|---|
| `{repo_parent}/{name}` | `{repo_parent}` |
| `{repo_root}/.worktrees/{name}` | `{repo_root}/.worktrees` |
| `~/.cache/ocw/{repo}/{name}` | `~/.cache/ocw/{repo}` |
| `{repo_parent}/{repo}-{name}` | `{repo_parent}` |
| `{name}`（`/` が前に無い） | **エラーにする**（境界が定義できない） |
| `{repo_parent}/wt`（`{name}` 不在） | **エラーにする** |

---

## 3. 決定

### 3.1 ブランチ接頭辞は廃止する。設定で復活させる仕組みは作らない

既定のブランチ名は `<正規化した入力>` そのものとする。

**`ocw.branchPrefix` のような設定は作らない。** 3.3 でスラッシュが通るようになるため、接頭辞が欲しい人は
`ocw ai/foo` と打てば済む。設定を1つ増やす価値がない。

失うのは「ブランチは `ai/foo`、ディレクトリは `foo`」という分離だけであり、その需要は確認できていない。

### 3.2 ブランチ名の妥当性検証は `git check-ref-format --branch` に委ねる

自前の正規表現は書かない（2.6）。正規化で作った候補名をこれに通し、拒否されたら git 自身の
`fatal:` メッセージをそのまま添えて `die` する。

正規化（小文字化・記号の `-` への潰し込み・前後の区切り除去）自体は**残す**。`ocw "Fix the thing"` が
`fix-the-thing` になる利便性は既存の挙動であり、失う理由がない。**ただし `/` は潰さず温存する。**

### 3.3 ディレクトリはブランチ名の階層をそのまま写す（ネスト）

`feature/foo` → `<worktree_root>/feature/foo`。

```
projects/myrepo/
├── main/
├── feature/
│   ├── foo/      ← branch feature/foo
│   └── bar/      ← branch feature/bar
└── hotfix/
    └── urgent/   ← branch hotfix/urgent
```

- 作成側の追加コストは**ゼロ**（2.4）
- ディレクトリ衝突は**原理的に起きない**（2.5）
- ブランチ名の情報を落とさない

代償は `ocw rm` 後の空ディレクトリ掃除だけであり、3.5 の境界まで `rmdir` を遡るループで閉じる。

### 3.4 設定のソースは git config `ocw.*`。レイアウトは**フルパス雛形1本**で表現する

**ソースの選定:**

| 候補 | 判断 |
|---|---|
| **git config `ocw.*`** | **採用。** リポジトリごとに別ポリシーを持てるのが要件そのもの。`.git/config` は全ワークツリーで共有されるため、どのワークツリーから叩いても同じ設定が効く。system < global < local の階層解決がタダで手に入り、`--global` に個人の既定値を置ける |
| 環境変数 `OCW_*` | **レイアウトには採用しない。** シェル単位という粒度が「リポジトリごとのポリシー」と噛み合わない。既存の `OCW_*`（コマンド差し替え・`OCW_NO_VSCODE`）は用途が別なので、そこへ混ぜない |
| 設定ファイル（`~/.config/ocw/config`） | **却下。** パーサを自作したうえ、リポジトリごとの出し分けをパスマッチで実装する羽目になる。git config の劣化版 |

**設定キー（全4個）:**

| キー | 既定 | 意味 |
|---|---|---|
| `ocw.worktreeDir` | `{repo_parent}/{name}` | ワークツリーの**フルパス雛形** |
| `ocw.repoName` | 自動（3.6） | Herdr ワークスペースラベル等に使う表示名 |
| `ocw.mergedInto` | 自動（3.7） | マージ済み判定の基準 ref |
| `ocw.githubMergeCheck` | `false` | マージ済み判定で `gh` に問い合わせるか（3.7） |

**`ocw.worktreeDir` のプレースホルダ:**

| | 意味 |
|---|---|
| `{repo_root}` | メインワークツリーのパス（bare ならリポジトリ本体のパス） |
| `{repo_parent}` | `dirname(repo_root)` |
| `{repo}` | 解決済みの `repo_name`（3.6） |
| `{name}` | ディレクトリ側の名前。ネスト方針（3.3）により**ブランチ名そのもの**（`/` を含む） |

先頭の `~` は `$HOME` へ展開する。展開後が絶対パスでなければ `die` する。
未知のプレースホルダ（`{foo}`）は**黙って literal にせず `die` する**（タイプミスを握り潰さないため）。

**表現できる構成:**

| 構成 | 設定 |
|---|---|
| 現行（`<proj>/main` + 兄弟） | **無設定**。既定のまま |
| **bare + 同階層**（`<proj>/foo.git` + `<proj>/<name>`） | **無設定**。`dirname(bare)` が `{repo_parent}` なので既定で通る |
| リポジトリ内に隠す | `ocw.worktreeDir = {repo_root}/.worktrees/{name}` |
| 中央プール | `ocw.worktreeDir = ~/.cache/ocw/{repo}/{name}` |
| 普通の clone の隣に接頭辞付き | `ocw.worktreeDir = {repo_parent}/{repo}-{name}` |

**自動検出は `dirname(repo_root)` の一本だけ**とし、それ以上の推測（ディレクトリ名が `main` かどうかで
挙動を変える等）は入れない。外したときに理由が分からなくなるコストが、当たったときの利益を上回る。

### 3.5 空ディレクトリの掃除境界は雛形から逆算する

`{name}` より前の最後の `/` までを境界とする（2.9）。`ocw rm` は削除後、
worktree のディレクトリの親から**境界に達するまで** `rmdir` を遡り、`rmdir` が失敗した時点で止める
（非空なら失敗するので、他のワークツリーが残っている親は消えない）。**境界そのものは削除しない。**

### 3.6 `repo_name` は「リポジトリの名前」から導く

現行の `basename(dirname(repo_root))` は、bare が共有の親（`~/repos/foo.git`）に居ると `repos` になり、
普通の clone（`~/src/myrepo`）だと `src` になる。どちらも意図と違う。

解決順:

1. `ocw.repoName` が設定されていればそれ
2. `remote.origin.url` の basename から `.git` を剥がしたもの（＝リポジトリの実名）
3. パスからの推測:
   - bare なら `basename(repo_root)` から `.git` を剥がす
   - `basename(repo_root)` が `main` / `master` / `trunk` なら `basename(dirname(repo_root))`（現行挙動）
   - それ以外は `basename(repo_root)`

`repo_name` の用途は Herdr のワークスペースラベルと `repo:` 行の表示だけであり、影響範囲は表示に閉じる。

### 3.7 `ocw rm` のマージ済み判定を再定義する

**基準 ref（integration ref）は複数候補を持ち、いずれか1つでも「マージ済み」と言えば通す。**

| 順 | 候補 |
|---|---|
| 1 | `ocw.mergedInto`（設定） |
| 2 | **作成時の `base_ref`**（worktree の git dir に `ocw-base-ref` として保存したもの） |
| 3 | bare なら `git symbolic-ref --short HEAD`／非 bare なら `repo_root` の `HEAD`（**現行挙動の保存**） |
| 4 | `git symbolic-ref --short refs/remotes/origin/HEAD`（ローカルが古いだけのケースの救済） |

解決できない候補は黙って飛ばす。1つも解決できなければ「基準が決まらない」として `die` し、
`ocw.mergedInto` の設定か `-f` を案内する。

**候補2 は傘ブランチ運用を直接救う。** 孫ブランチは main ではなく傘ブランチにマージされるため、
現状は `ocw rm` が必ず失敗し、`umbrella-orchestrator` スキルが「`--force` が必要」と明記する状態に
なっている。作成時の base を覚えておけば、そのまま正しく判定できる。

**各候補に対する判定:**

1. `git merge-base --is-ancestor "$branch" "$candidate"` → 真ならマージ済み
2. squash 検出（2.7 のレシピ）→ `-` ならマージ済み
3. `ocw.githubMergeCheck` が真かつ `gh` が PATH にある場合のみ、
   `gh pr list --head "$branch" --state merged` が1件以上ならマージ済み。
   **fail-open**: `gh` の失敗・未認証・ネットワーク不通は「判定できなかった」として無視し、
   `ocw` 自体は落とさない（既定 `false` なのは、ネットワーク・認証依存を既定経路に入れないため）

### 3.8 `run.end` の `outcome` は `-f` ではなく**マージ判定の結果**から決める

`-f` は「拒否をバイパスするフラグ」であって「失敗の宣言」ではない。

```
outcome = マージ済みと判定できた → success
          そうでない             → failure
```

`-f` の有無は判定を**スキップさせない**（拒否をスキップさせるだけ）。これにより
「squash 済みなのに `-f` を強いられ、メトリクスに失敗が記録される」問題が消える。
3.7 の検出漏れケース（2.7 の限界）に当たった場合は従来どおり `failure` になる。

### 3.9 `ocw rm` は `git worktree list --porcelain` からの**逆引き**で解決する

入力から `branch` と `worktree_dir` を再計算する現行の一方向ロジックを捨てる。
porcelain 出力から `(path, branch)` の対を作り、段階マッチする。

| 段 | 条件 |
|---|---|
| 1 | ブランチ名の完全一致／パスの完全一致／`worktree_root` からの相対パス一致 |
| 2 | ディレクトリの `basename` 一致 |
| 3 | **ブランチが `*/<入力>` で終わる** |

**先に非空になった段の結果を採用する。同一段で複数ヒットしたら、候補（パスとブランチ）を並べて `die` する**
（勝手に1つ選ばない）。メインワークツリーと bare エントリは候補から除外する。

**段3が 3.1 の移行救済になる。** 接頭辞廃止後も、既存の `ai/foo` ワークツリーは `ocw rm foo` で消せる。
入力は正規化せずそのまま照合する（利用者は実在する名前を打っているため）。

### 3.10 bare 対応の周辺

- `invocation_root`（`git rev-parse --show-toplevel`）は**取れなくてもよい**値にする。
  取れなければ空とし、「今いる worktree を消そうとしていないか」ガードをスキップする（2.1）
- エラーメッセージは「run ocw from inside a Git worktree」→ Git リポジトリの中から実行する旨に改める
- `base_ref` の既定値は、`refs/remotes/origin/HEAD` が引けなければ
  **`git symbolic-ref --short HEAD`**（bare を含む）にフォールバックし、それも駄目なら `main`

---

## 4. 検討して却下した案（蒸し返さないこと）

### 4.1 ディレクトリ名をフラット化する（`feature/foo` → `feature-foo`）

掃除が不要になるのは利点だが、`feature/foo` と `feature-foo` という**別々に有効なブランチが同じ
ディレクトリを要求する**。既存の `[ ! -e "$worktree_dir" ]` チェックにより2本目の作成が
「dir already exists」で落ちるだけになり、**理由の分かりにくいエラー**になる。
ネストなら git の D/F conflict が原理的に防ぐ（2.5）ため、この論点自体が消える。

「ディレクトリ名からブランチ名を復元できるか」はフラット案の弱点として挙がるが、3.9 で `rm` を
porcelain 逆引きにするため**どちらの案でも論点にならない**。であれば情報を落とさない側を採る。

### 4.2 `ocw.branchPrefix` を設ける

3.1 のとおり、スラッシュが通れば `ocw ai/foo` で代替できる。設定は増やさない。

### 4.3 レイアウトを enum（`ocw.layout = sibling | nested | central | custom`）で表現する

discoverable ではあるが、想定外の構成が出るたびに enum を増やすか `custom` に逃がすことになる。
フルパス雛形1本なら**追加の実装なしで未知の構成に追随できる**。掃除境界も雛形から逆算できる（2.9）ため、
enum が持っていた「境界が明示的」という利点も失われない。

### 4.4 レイアウトを2ノブ（`ocw.worktreeRoot` + `ocw.dirTemplate`）で表現する

境界が `worktreeRoot` として明示される点は素直だが、`{repo}-{name}` のようなディレクトリ名雛形と
親ディレクトリを別々に設定させることになり、**同じ1つの事実（どこに何という名前で作るか）が2箇所に
分かれる**。雛形1本のほうが、設定を読んだときに結果のパスがそのまま読める。

### 4.5 レイアウトの自動検出を賢くする

「`basename(repo_root)` が `main` なら兄弟、そうでなければ `.worktrees` に隠す」のような推測は、
外したときに理由が説明できない。既定は `dirname(repo_root)` の一本に固定し、それ以外は明示設定に倒す。

### 4.6 マージ判定を `gh` の PR 状態だけに寄せる

最も正確だが、ネットワーク・認証・GitHub 以外のホスティングに依存する。`ocw` の中核機能が
オフラインで動かなくなる代償が大きい。ローカルの ancestry + squash 検出（2.7）で実運用の大半を
拾えるため、`gh` は `ocw.githubMergeCheck` による opt-in の**上乗せ**に留める（3.7）。

### 4.7 `{flat_name}` プレースホルダを用意する（フラット化を選べるようにする）

3.3 でネストに決めた以上、現時点で必要ない。将来フラット化の需要が出たときは
**プレースホルダを1個足すだけ**で済む（雛形1本の設計がそれを許す）ため、先回りして実装しない。

### 4.8 `ocw rm` の曖昧一致を「最も具体的なものを自動選択」で解決する

`rm` は破壊的操作であり、推測で対象を選んではならない。候補を並べて停止し、利用者に完全な名前を
打たせる（3.9）。

---

## 5. 影響範囲

| 対象 | 影響 |
|---|---|
| `bin/ocw` | `init_repo_context` / `normalize_name` / `create_worktree` / `remove_worktree` を改修。設定リーダと雛形展開を新設 |
| `bin/tests/test_ocw.py` | `make_repo()` をレイアウト別に用意する必要がある（現行の兄弟構成に加え、bare 構成・雛形設定を効かせた構成） |
| `bin/README.md` | §3.1 の全面改訂（設定キー・レイアウト例・マージ判定の意味論と限界） |
| ルート `README.md` | `bin/` の1行説明の範囲で追随 |
| `claude/skills/umbrella-orchestrator/SKILL.md` | 「`ocw rm` には `--force` が必要」の記述が 3.7 の候補2により不要になる。**本傘の対象外**（配布物であり、`claude/` 配下は指示が無い限り触らない）。追随が必要になった時点で別途扱う |

**既定設定のまま使う限り、現行の挙動から変わるのは次の点である。**（実装時の実測により、
当初のリスト3点に加えて以下の4点があることが判明した。詳細は §3.6 / §3.9 を参照）

1. ブランチ名に `ai/` が付かなくなる（3.1）
2. マージ済み判定が squash マージを拾えるようになり、判定が通るケースが増える（3.7）
3. `run.end` の `outcome` が `-f` の有無ではなくマージ判定から決まる（3.8）
4. `repo_name` の解決順に `remote.origin.url` からの導出が優先で入るため、無設定でも表示名
   （`repo:` 行・Herdr ワークスペースラベル）が変わりうる（3.6）
5. Herdr ワークスペースラベルの区切りが `${repo_name} / ${slug}` から `${repo_name} :: ${slug}`
   に変わる（slug 自体がスラッシュを含みうるため、`/` のままでは境界が視覚的に区別できないことへの対策）
6. `ocw rm` はワークツリーのディレクトリが既に手動で消されている場合、従来の `die` ではなく
   warn して処理を続行するようになる（3.9）
7. `ocw rm` のブランチ削除が `git branch -d` ではなく `-D` になり、削除に失敗しても `die` せず
   warn するようになる（`-d` の ancestry-only チェックは squash 検出済みのマージを拒否してしまう
   ため。3.7 / 3.9）

ワークツリーの作成先パスは既定 `{repo_parent}/{name}` であり、**現行と同一**である。
