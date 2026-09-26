# レビュー状態ディレクトリと状態ファイルの形式

`pr-group-review`（レビュワー用）と `pr-group-request`（依頼者用）が共通で使う。
決定の経緯は ADR DOC-2609270420 §2.2 を参照。

**このファイルの名前は `pr-group-request` から相対パス
（`../pr-group-review/references/state-format.md`）で参照される。リネームしないこと。**

## 1. 置き場所

- ベースディレクトリ: 環境変数 `PR_GROUP_REVIEW_DIR`。未設定なら `$HOME/work/reviews`
- PR 群 1 つにつき `$PR_GROUP_REVIEW_DIR/<YYYY-MM-DD>-<テーマ>/` を作り、そこで `git init` する
  - 日付は**そのレビュー（依頼）を始めた日**。追いレビューで日付が変わってもディレクトリ名は変えない
  - テーマは英小文字・数字・ハイフンの短い名前（例: `signup-flow-v2`）。人間に確認して決める
- どのリポにも属さないディレクトリである。対象リポの中に作らない
- **コードを読むための worktree はここに置かない。** ここに置くのは「レビューという仕事の記録」だけ

```sh
base="${PR_GROUP_REVIEW_DIR:-$HOME/work/reviews}"
dir="$base/2026-09-27-signup-flow-v2"
mkdir -p "$dir" && git -C "$dir" init
```

## 2. ディレクトリの中身

```
<YYYY-MM-DD>-<テーマ>/
├── state.json                 # 状態ファイル（本書 §3。正典）
├── drafts/
│   ├── r1-s1.json             # ラウンド1・1段目の投稿用下書き（本書 §4）
│   ├── r1-s2.json             # ラウンド1・2段目
│   └── r2-s1.json
├── summary.html               # まとめの HTML（ラウンドごとに上書き。履歴は git に残る）
└── notes/                     # 任意。作者の地図の写し、調査メモなど
```

- 依頼者用（`pr-group-request`）は `drafts/` の代わりに依頼文の下書きなど自分の成果物を置いてよい。
  追加するファイルは `pr-group-request` 側で定める
- **ラウンドの区切り（投稿の後、依頼文を確定した後）ごとに `git commit` する。** コミット
  メッセージは `round 1: stage 1 posted` のように、何が確定したかを書く
- 社外秘の内容（他人の PR の中身）を含みうるので、このディレクトリをリモートへ push しない
  （人間が明示的に求めた場合を除く）

## 3. `state.json`

JSON オブジェクト 1 つ。**未知のキーは無視する**（片方のスキルだけが使うキーを足してよい）。

### 3.1 トップレベル

| キー | 型 | 説明 |
|---|---|---|
| `format_version` | 数値 | 本書の版。現行は `1` |
| `role` | `"reviewer"` \| `"requester"` | どちらのスキルが作った状態か |
| `theme` | 文字列 | ディレクトリ名のテーマ部分 |
| `started_on` | 文字列 | `YYYY-MM-DD` |
| `sources` | 配列 | 対象 PR を列挙した情報源（§3.2） |
| `prs` | 配列 | 対象 PR（§3.3） |
| `map` | オブジェクト | PR 群の地図（§3.4。項目の意味は `group-map.md`） |
| `rounds` | 配列 | ラウンドの記録（§3.5） |
| `findings` | 配列 | 指摘（§3.6）。依頼者用では自己チェックの結果を入れる |
| `requester` | オブジェクト | 依頼者用だけが使う（§3.7）。レビュワー用では省略 |

### 3.2 `sources[]`

対象 PR の列挙は 1 つの情報源だけでは漏れる（ADR DOC-2609270420 §3.8）。どこから列挙したかを残す。

| キー | 説明 |
|---|---|
| `kind` | `human_list`（人間が示したリスト）/ `author_map`（作者の地図）/ `pr_body`（PR 本文のリンク）/ `branch_search`（同じブランチ名・関連 issue での検索）/ `umbrella_plan`（傘ブランチの計画書）/ `other` |
| `ref` | URL・ファイルパス・検索クエリなど。**チャットの URL などを状態に残すのは構わないが、公開の場へ転記しない** |
| `found` | この情報源で見つかった PR の ID の配列 |

### 3.3 `prs[]`

| キー | 説明 |
|---|---|
| `id` | `<owner>/<repo>#<番号>`。状態ファイル内の参照はすべてこの形 |
| `url` | PR の URL |
| `title` / `author` | 取得時点の値 |
| `base` | base ブランチ名（積んでいる PR なら下の PR のブランチ） |
| `group` | `map.groups[].id` |
| `clone` | 読み取り用 clone のパス（例: `~/work/<repo>/<default-branch>`）。依頼者用では自分の作業場所 |
| `heads` | `[{ "round": 1, "sha": "<40桁>", "base_sha": "<40桁>" }]`。**レビューした時点の head SHA と、そのときの base の SHA**。追いレビューの差分の起点と投稿直前の確認に使う |
| `state` | `open` / `merged` / `closed`。追いレビューの受付で更新する |

### 3.4 `map`

`group-map.md` の各項目をそのまま持つ。

```json
{
  "source": "author",
  "verified_round": 1,
  "groups": [{ "id": "G1", "name": "受信側の API", "purpose": "…", "prs": ["o/api#12"] }],
  "dependencies": [{ "from": "o/web#40", "to": "o/api#12", "kind": "service", "note": "…" }],
  "stacks": [{ "chain": ["o/api#12", "o/api#13"] }],
  "order": [{ "step": 1, "action": "merge", "target": "o/schema#7", "note": "…" }],
  "manual_steps": [{ "id": "M1", "when": "step 2 の後", "what": "…", "who": "作者" }],
  "open_adrs": [{ "pr": "o/docs#3", "title": "…", "blocks": ["o/api#12"] }],
  "cross_repo_matrix": [{ "contract": "イベント payload", "producer": "o/api#12", "consumers": ["o/worker#5"], "status": "match", "note": "…" }],
  "rollback": [{ "for": "step 3", "how": "…", "reversible": true }],
  "discrepancies": [{ "item": "order", "note": "作者の地図ではマイグレーションが後だが依存上は先" }]
}
```

- `source`: `author`（作者の地図を検証した）/ `reviewer`（レビュワーが作った）/ `requester`（依頼者が作った）
- `action`: `merge` / `apply`（インフラやスキーマの適用）/ `deploy` / `manual`
- `dependencies[].kind`: `code` / `service` / `data` / `pipeline` / `docs`（依存の種類。
  `seam-checklist.md` の分類と揃える）
- `cross_repo_matrix[].status`: `match` / `mismatch` / `unverified`
- `discrepancies`: 作者の地図と実物が食い違った点。レビュワー用で地図を検証したときに使う

### 3.5 `rounds[]`

| キー | 説明 |
|---|---|
| `n` | 1 から始まる通し番号 |
| `date` | `YYYY-MM-DD` |
| `posting` | `two-stage`（既定）/ `single`（人間が「一度に出す」を選んだ） |
| `posted` | `[{ "pr": "o/api#12", "stage": 1, "review_id": 123, "url": "…", "commit_id": "<40桁>" }]`。投稿できた分だけ入れる |
| `skipped` | `[{ "pr": "…", "stage": 1, "reason": "head moved" }]`。投稿を見送った分 |

### 3.6 `findings[]`

| キー | 説明 |
|---|---|
| `id` | `F001` から通し番号。ラウンドをまたいで振り直さない |
| `round_raised` | 初めて出したラウンド |
| `pr` | 主な対象 PR の ID。リポ間の指摘で複数にかかるなら `related_prs` に残りを入れる |
| `path` / `line` / `side` | インラインで付ける位置。`side` は `RIGHT`（追加・文脈行）/ `LEFT`（削除行）。本文だけに書く指摘なら省略 |
| `severity` | `blocker` / `major` / `minor` / `nit` |
| `blocking` | 真偽値。**マージ前に対応が必要か**。`severity` とは独立に持つ（`major` でも前提の確認だけなら非 blocking でありうる） |
| `kind` | `issue`（技術的な問題）/ `question`（仕様の確認）/ `suggestion` / `nitpick` |
| `category` | `structure`（分け方・構成）/ `order`（マージ・適用の順序）/ `manual`（手作業の前提）/ `seam`（リポ間の照合）/ `code` / `test` / `docs` |
| `stage` | 投稿の段（`1` = 構造・順序・blocking、`2` = 細かい指摘）。本書 §4.1 |
| `title` / `detail` / `suggestion` | 指摘の要旨・根拠・提案 |
| `verdict` | 反証の結果。`confirmed` / `plausible` / `refuted` / `duplicate` |
| `duplicate_of` | `verdict` が `duplicate` のときの元の ID |
| `status` | `new`（このラウンドで初出）/ `open`（前のラウンドから未解決）/ `resolved` |
| `thread` | 投稿後の GitHub 上のスレッド。インラインで付けたものはそのコメントの ID、本文だけに書いたものはレビューの ID。**空なら未投稿**（次のラウンドの下書きに新しい指摘として入れてよいのは、これが空のものだけ） |
| `history` | `[{ "round": 2, "status": "resolved", "note": "fixup コミット abc123 で対応" }]` |

- `refuted` と `duplicate` も**消さずに残す**（次のラウンドで同じ指摘を蒸し返さないため）。
  投稿の下書きに入れるのは `confirmed` と `plausible` だけ
- `status` の遷移: `new` →（次のラウンドで）`open` か `resolved`。`open` → `resolved`
- **遷移させるのは投稿済み（`thread` が埋まっている）の指摘だけ。** 未投稿の指摘（前回出さなかった
  2 段目など）は相手が見ていないので `new` のまま持ち越し、新しい head でまだ当てはまるかを確かめて
  から投稿する。当てはまらなくなったら `verdict` を `refuted` にする（`resolved` にはしない）

### 3.7 `requester`（依頼者用のみ）

`pr-group-request` が使う。最低限次を持つ。

| キー | 説明 |
|---|---|
| `pr_bodies` | `[{ "pr": "…", "updated_at": "YYYY-MM-DD" }]`。本文へ「PR 群の中での位置」「マージ前の前提」を書き込んだ PR |
| `request_draft` | 依頼文の下書きのファイル名（状態ディレクトリからの相対パス） |

## 4. 投稿用の下書き（`drafts/r<ラウンド>-s<段>.json`）

PR ごとに 1 レビュー。GitHub の「レビューを作成する」API にそのまま渡せる形に近づけておく。

```json
[
  {
    "pr": "o/api#12",
    "commit_id": "<state.json の prs[].heads の最新 sha>",
    "body": "レビューサマリの本文",
    "comments": [
      { "finding_id": "F003", "path": "app/handler.rb", "line": 42, "side": "RIGHT", "body": "…" }
    ],
    "body_only_finding_ids": ["F001"],
    "replies": [
      { "finding_id": "F002", "in_reply_to": 123456, "body": "…" }
    ]
  }
]
```

- `body_only_finding_ids`: 行に紐づかず、サマリ本文にだけ書いた指摘（リポ間・順序の指摘の多くはこれ）
- 複数行にかけるときは `start_line` / `start_side` を足してよい
- `comments` に入れるのは**未投稿の**指摘（`thread` が空）だけ。投稿済みで未解決の指摘は新しい
  コメントにせず、サマリで列挙する。相手の返信に答える必要があるときだけ `replies` に入れ、
  `in_reply_to` にそのスレッドの先頭コメントの ID（指摘の `thread`）を書く

### 4.1 段の分け方

- 段に振り分けるのは未投稿の指摘だけ（投稿済みのものは上のとおりサマリと `replies` で扱う）
- **1 段目**: `category` が `structure` / `order` / `manual` / `seam` のもの、および `blocking` が
  真のもの。設計・順序の手戻りは大きいため先に返す（Google eng-practices）
- **2 段目**: それ以外の細かい指摘
- 人間が「一度に出す」を選んだら、`rounds[].posting` を `single` にして全部を 1 段目に入れる
- 1 段目で相手が構造を変えた場合、2 段目の指摘は前提が崩れていることがある。2 段目を投稿する
  前に head を取り直し、指摘がまだ当てはまるかを確かめる
