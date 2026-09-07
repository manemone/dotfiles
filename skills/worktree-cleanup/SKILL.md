---
name: worktree-cleanup
description: "不要になった git ワークツリーの掃除・クリーンアップ・削除を求められたら発動（「ワークツリー消して」「worktree 掃除して」「残骸を片付けて」等）。現在地（傘ブランチのワークツリー／main・master 等の統合ブランチ／明示指定）からスコープを自動決定し、削除候補を一覧提示して人間の承認を得てから `ocw rm` で削除する。マージ未確認のまま `--force` へは進まない。"
argument-hint: "[umbrella | repo | herdr]"
---

# worktree-cleanup — 不要ワークツリーの掃除

**AI 不問。** YAML frontmatter を除き自然言語のみで完結する。特定エージェント固有の
機能（`SendMessage` 等）には依存しない。本スキルは AI 間通信を行わないため、
そもそも登場しない。

## 1. 概要

不要になった git ワークツリーを、現在地から自動でスコープを決めて掃除する。
削除は必ず `ocw`（`bin/ocw`。詳細は `skills/ocw/SKILL.md`）の `ocw rm` で行う。
**削除候補は必ず一覧で提示し、人間の承認を得てから実行する。無言で消さない。**

3つのスコープを持つ。引数が無ければ現在地から自動決定する。

| スコープ | 発動条件 | 対象 |
|---|---|---|
| `umbrella` | 現在地が傘ブランチのワークツリー | その傘の孫ワークツリーだけ |
| `repo` | 現在地が `main` / `master` 等の統合ブランチ | 同じリポジトリの全ワークツリー |
| `herdr` | **明示指定でのみ発動** | 全ワークスペースの全リポジトリを横断 |

どれにも当てはまらない・曖昧なときは、**広いスコープを勝手に選ばず人間に聞く。**
破壊的操作のスコープを推測で広げるのは事故の型である。

## 2. スコープの自動決定

### 2.1 まず現在地の情報を集める

```bash
CUR_BRANCH=$(git branch --show-current)
CUR_TOPLEVEL=$(git rev-parse --show-toplevel)
DEFAULT_BRANCH=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's#^origin/##')
```

`origin/HEAD` が未設定なら `main` / `master` のどちらかがローカルに存在するかで
代用してよい。

### 2.2 `umbrella` スコープの判定

現在のリポジトリの `docs/planning/*.md` の中に、`傘ブランチ: \`$CUR_BRANCH\`` という
行を持つ計画書があるかを探す（`umbrella-orchestrator` スキルが定める計画書の形式。
§2.1 参照）。

```bash
grep -rl "傘ブランチ: \`$CUR_BRANCH\`" docs/planning/*.md 2>/dev/null
```

見つかれば `umbrella` スコープ。その計画書の「孫ブランチ進捗テーブル」
（`| 孫 | ブランチ | 内容 | 状況 |` の形式）から「ブランチ」列の値（バッククォートで
囲まれた文字列）を全行抜き出し、それが対象の孫ブランチ一覧になる。

```bash
grep -oE '^\| *[0-9]+ *\| `[^`]+`' <計画書のパス> | grep -oE '`[^`]+`' | tr -d '`'
```

**このブランチ名一覧をそのまま候補にしない。** 進捗テーブルには `⬜ 待機中` の
未着手の孫や、既に掃除済みでワークツリーが存在しない孫も同じ形式で残り続ける。
`git worktree list --porcelain` の結果と突き合わせ、**実在するワークツリーを持つ
ブランチだけ**を候補にする（対応するワークツリーが無いブランチは対象外）。
§4.1 以降の手順はすべて「ワークツリー」を前提にしており、ブランチ名だけでは実行できない。

見つからなければ `umbrella` ではない。次へ。

**この判定方法は dotfiles リポジトリの計画書規約に依存する。** 対象リポジトリが
`umbrella-orchestrator` の計画書形式を使っていない場合、この判定は成立しない
（見つからないだけで、エラーにはしない）。その場合は次の `repo` 判定に進む。

### 2.3 `repo` スコープの判定

`$CUR_BRANCH` が `$DEFAULT_BRANCH` と一致する（または `main` / `master` そのもの）なら
`repo` スコープ。対象は現在のリポジトリの全ワークツリー。

```bash
git worktree list --porcelain
```

### 2.4 `herdr` スコープ

**明示指定でのみ発動する。** 2.2・2.3のどちらにも当てはまらなくても、`herdr` へは
自動で広げない。取得方法は §3 を参照。

### 2.5 どれにも当てはまらないとき

人間に「現在地からはスコープを自動決定できませんでした。`umbrella` / `repo` /
`herdr` のどれで実行しますか？」と聞く。**推測で広いスコープを選ばない。**

## 3. `herdr` スコープの取得方法

**一次情報源は `herdr pane list` の `cwd` を起点に `herdr worktree list --cwd <cwd>`
を叩く方式。** `herdr workspace list` の `worktree` フィールドに依存する方式は
**採用しない**。計画書の実測（`worktree` フィールドは大半のワークスペースに無い）を
本スキル実装時にも再実測して確認済み（2026-09-08、15ワークスペース中1つだけが
`worktree` を持っていた）。一方 `herdr pane list` はどのワークスペースの pane も
`cwd` を持っていたため、こちらを一次情報源にする。

```bash
herdr pane list | python3 -c "
import json, sys
panes = json.load(sys.stdin)['result']['panes']
seen = set()
for p in panes:
    cwd = p.get('cwd')
    if cwd and cwd not in seen:
        seen.add(cwd)
        print(cwd)
"
```

得られた各 `cwd` について `herdr worktree list --cwd <cwd>` を叩く。**`cwd` は
git リポジトリの外（プロジェクトの親ディレクトリ等）を指すことがあり、その場合は
`error.code` が `not_git_worktree` のエラーが返る。** 実機で確認済み:

```bash
$ herdr worktree list --cwd /home/manemone/projects
{"error":{"code":"not_git_worktree","message":"Herdr worktree actions require a path inside a Git work tree"},"id":"cli:worktree:list"}
```

**`not_git_worktree` は黙ってスキップし、次の `cwd` へ進む。** リポジトリ外の `cwd`
はそもそも掃除の対象になりようがないため、これはエラーではなく想定内の分岐である。

エラーにならなかった場合、返り値の `result.source.repo_root` でリポジトリを一意化し、
`result.worktrees` の各要素が `branch` / `path` / `is_linked_worktree` /
`open_workspace_id` / `is_prunable` を持つ。**`repo_root` が重複したら（複数の cwd が
同じリポジトリを指す）片方を捨てて重複排除する。** 引数なしで叩くと呼び出し元と
無関係なリポジトリを返すため、**必ず `--cwd`（または `--workspace <id>`）を指定すること。**

```json
{"result":{"source":{"repo_root":"/home/manemone/projects/lora-dataset-forge/main", ...},
 "worktrees":[{"branch":"oc-01-canon-recipe","is_linked_worktree":true,
   "is_prunable":false,"open_workspace_id":"w9M",
   "path":"/home/manemone/projects/lora-dataset-forge/oc-01-canon-recipe"}]}}
```

**`is_linked_worktree: false` の要素（各リポジトリの main チェックアウト自体）は
削除候補に含めない。** 掃除の対象は「不要になった孫ワークツリー」であり、
main チェックアウトはどのスコープでも消さない。

`is_prunable` は herdr 側の登録状態のヒントに過ぎず、マージ済み判定の代わりには
ならない。マージ済みかどうかは必ず §4 の手順で確認する。

## 4. 削除候補の収集と安全確認（本スキルの中核）

**削除前に必ずリストを出して確認を取る。無言で消さない。**
**`-f` は「PR がマージ済みであることを `gh` で確認したうえで、人間に承認を取ってから」
のみ使う。自動で `-f` に飛ぶ経路を作らない。**

### 4.1 候補の絞り込み

スコープで集めた各ワークツリー（自分がいるワークツリーは除く）について、次を確認する。

1. **自分がいるワークツリーではないか。** `git rev-parse --show-toplevel` と比較し、
   一致するものは候補から外す（自分自身は消せない）
2. **ブランチを持つワークツリーか。** `git worktree list --porcelain`（`herdr` スコープ
   では `herdr worktree list` の `branch`）で detached（ブランチ無し）と分かった
   ワークツリーは、この時点で候補から外し理由を添えて人間へ報告する。**空のブランチ名で
   次のPR確認へ進んではいけない。** `gh pr list --head ""` はフィルタが無視されて全PRを
   返すため、`state` が `MERGED` の要素がたまたま含まれ、次のゲートを素通りしてしまう
   （実機で確認済み）
3. **未コミットの変更が無いか**: `git -C <worktree> status --porcelain` が空であること
4. **対応する PR がマージ済みか**: そのブランチの PR を、**そのワークツリーが属する
   リポジトリを対象にして**（`herdr` スコープでは §3 で得た `repo_root` の
   `owner/repo` を `gh pr list -R <owner>/<repo> --head <branch> ...` のように明示する。
   `umbrella` / `repo` スコープでは現在のリポジトリで実行すればよい）
   `gh pr list --head <branch> --state all --json number,title,state,mergedAt` で調べ、
   `state` が `MERGED` であること。**リポジトリを明示しないと、`gh` は実行時の cwd の
   remote から対象リポジトリを決めるため、`herdr` スコープで他リポジトリのブランチ名を
   誤って現在地のリポジトリへ問い合わせることになる**（該当PRが見つからず全滅する、
   または同名ブランチが現在地に存在すると無関係なPRのマージ状態を根拠に削除候補へ
   載る、のどちらかの事故につながる）

いずれかを満たさないワークツリーは**候補から外し、理由を添えて人間へ報告する**
（detached／未コミット変更あり／PRが無い／PRがマージされていない、等）。GitHub remote が
無いなどでPR確認自体ができないリポジトリも、候補から外して人間の判断を仰ぐ。

### 4.2 候補リストの提示と承認

絞り込んだ候補を一覧にして人間に見せ、実行してよいか確認する。

```
以下のワークツリーが削除候補です:
- worktree-cleanup-01-merge-detection (PR #78 マージ済み) → /path/to/...
- ocw-usage-01-help-topics (PR #72 マージ済み) → /path/to/...
削除してよいですか？
```

**承認が得られるまで `ocw rm` を一切実行しない。**

### 4.3 削除の実行（まず `-f` なし）

承認された候補それぞれについて、**まず `--force` なしで** `ocw rm <branch>` を試す。

```bash
ocw rm <branch>
```

- 成功すればそのワークツリーは完了（`ocw rm` は worktree + ブランチ + cwd の一致する
  Herdr ワークスペースまで面倒を見る。§6 参照）
- **入力が複数ワークツリーに曖昧一致すると `ocw` は自動選択せず停止する。** このときは
  そのワークツリーだけスキップし、完全なブランチ名を人間に確認する。他の候補の削除は
  止めない（§6 参照）

### 4.4 拒否されたら: `-f` を使う前の安全確認

`ocw rm` の拒否メッセージは4種類あり、うち3種類は同じ安全確認フローを踏む
（原因は異なるが対処は共通）。残る1種類（未コミット変更）は**フローの対象外であり、
`-f` で解消してはならない。**

- `branch is not merged into any known integration ref: <branch>` — 候補 ref は
  解決できたが、マージ済みと判定できなかった場合。**傘の孫を掃除する際に
  実際に遭遇するのはほぼこちら**（`skills/umbrella-orchestrator/SKILL.md` §3.3
  参照。傘へ squash マージされた孫は、孫のワークツリー作成時に傘ブランチ名が
  base-ref として正しく永続化されていない限り、`--force` なしでは通らないのが
  基本である）
- `cannot determine an integration ref ...: set ocw.mergedInto or use -f` —
  候補 ref が1つも解決できなかった場合。非 bare リポジトリでは通常出ない
- `detached worktree has no branch to check for a merge; use -f: <name>` —
  detached なワークツリー。**このケースは §4.1 の手順2で既に候補から除外している
  はずであり、ここに到達すべきではない。** 到達した場合は §4.1 の除外判定が
  漏れている証拠であり、削除を進めず人間に報告する
- `worktree has uncommitted or untracked changes: <path>` — 未コミット・未追跡の
  変更が残っているワークツリー。**このケースは §4.1 の手順3で既に候補から除外して
  いるはずであり、ここに到達すべきではない。** `-f` は「未マージ」と「未コミット
  変更」の両方の拒否を握りつぶし、`git worktree remove --force` によって未コミット・
  未追跡の変更をそのまま失う。到達した場合は §4.1 の除外判定が漏れている証拠であり、
  上記3種類と同じ安全確認フローには進まず、削除を進めず人間に報告する

いずれの場合も、**すでに §4.1 でそのブランチの PR がマージ済みであることは
確認済み。** ここでは取りこぼしが無いかを追加で確認する。

1. 最終コミット時刻と PR の `mergedAt` を**同じ基準（UTC）に揃えてから**比較し、
   最終コミットがマージより**前**であることを確認する（マージ後に取りこぼした
   コミットが無いこと）:
   ```bash
   TZ=UTC git -C <worktree> log -1 --date=iso-strict-local --format=%cd <branch>
   ```
   **`git log --format=%cI` はローカルタイムゾーンのオフセット付きで、`gh` の
   `mergedAt` は UTC（`Z`）である。** 素直に文字列比較すると、JST 等のプラス
   オフセット環境ではマージ済みの孫が軒並み「コミット時刻が逆転している」と
   誤判定され本スキルの主目的が機能しなくなり、マイナスオフセット環境では逆に
   取りこぼしコミットを見逃して安全弁をすり抜ける。上記のように `TZ=UTC` で
   正規化してから比較すること
2. `git -C <worktree> status --porcelain` が空であることを再確認する（§4.1 から
   時間が空いている場合、その間に変更が入っていないか）
3. 上記2点が揃ったら、**改めて人間に「マージ済みを確認しました。`--force` で
   削除してよいですか」と承認を求める**
4. 承認を得てから `ocw rm -f <branch>` を実行する

**この4ステップを飛ばして自動で `-f` へ進む経路を作らない。** 1点でも崩れたら
（コミット時刻が逆転している／未コミットの変更がある）そのワークツリーは
削除候補から外し、理由を添えて人間に報告する。

## 5. スコープ別の注意

- **`umbrella` スコープでは、司令官自身のワークツリー（傘ブランチのワークツリー
  そのもの）を孫の候補に含めない。** §4.1 の「自分がいるワークツリー」除外で
  自然に外れるが、傘ワークツリーの外から `umbrella` スコープを実行する場合
  （例: 傘の孫が終わった後、司令官セッションが既に終了している状況で人間が
  傘ワークツリーに入って実行する場合）も、傘ブランチ自身は「孫」ではないので
  対象に含めない
- **`herdr` スコープでは、対象リポジトリごとに `gh` の設定・GitHub remote の有無が
  異なりうる。** リポジトリごとに §4.1 の PR 確認を個別に行う

## 6. 落とし穴

- **`ocw rm` は入力が複数ワークツリーに曖昧一致すると自動選択せず停止する。**
  そのときはそのワークツリーだけスキップし、完全な名前を人間に仰ぐ。他の掃除は止めない
- **`ocw rm` は成功時に cwd の一致する Herdr ワークスペースを閉じるところまで
  面倒を見る。** スキル側でワークスペースを個別に閉じる処理を書かない
  （実測: 掃除した7本すべてで `closing Herdr workspace: <id>` が出た）
- **自分がいるワークツリーは消せない。** `umbrella` スコープで司令官自身の
  ワークツリーを候補に入れない
- **`herdr worktree list` は引数なしで叩くと呼び出し元と無関係のリポジトリを
  返す。** 必ず `--cwd` か `--workspace` を指定する

## 7. スコープ外（本スキルが踏み込まないこと）

- `bin/ocw` 本体の改修。既存の `ocw` をそのまま呼ぶ
- `ocw.githubMergeCheck` の有効化を勧めること
- Herdr の孤児ワークスペース閉鎖機能（`herdr` スコープは「全ワークスペースの
  全リポジトリを横断」であり、孤児ワークスペースの閉鎖は含まない）
- リモートの状態を知るために `git pull` / `git merge` を使うこと。
  `git fetch` と `gh pr list` で足りる
