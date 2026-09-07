# 計画書: ワークツリー掃除をスキル化する

傘ブランチ: `worktree-cleanup`
ターゲット: `master`

## 概要

不要になった git ワークツリーの掃除を、毎回自然言語で指示せずに済むスキルへ落とし込む。
発端は、実際に dotfiles の残骸ワークツリー7本を手作業で掃除したことだった。

2つの論点を扱う。

1. **マージ判定の食い違いの解消**（`skills/umbrella-orchestrator`）— 実測では孫6本すべてが
   `ocw rm -f` を要求したのに、既存スキルは「`--force` は基本的に不要」と書いている。
   原因を突き止め、記述を実態に合わせる
2. **掃除スキルの新設**（`skills/worktree-cleanup`）— 現在地からスコープを自動決定し、
   削除候補をリストして人間の承認を取ってから消すフローを持つスキルを作る

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。既に参照できない前提で
> 書く）を material として司令官が起草したものである。** ブリーフに書かれていた問題意識・
> 決定事項・実測値・制約は、**すべて本計画書へ転記済み**であり、以降はこの計画書が正典である。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `worktree-cleanup-01-merge-detection` | `ocw rm` が `-f` を要求した原因の究明と、`umbrella-orchestrator` §3.3 の記述是正 | ✅ PR #78 マージ済 |
| 2 | `worktree-cleanup-02-cleanup-skill` | 掃除スキル `skills/worktree-cleanup/` の新設と `skills/README.md` の追随 | 🔄 実装中 |

## ワークスペースラベル

- 傘: `dotfiles :: ワークツリー掃除`
- 孫1: `dotfiles :: ワークツリー掃除 孫1 マージ判定の原因究明`
- 孫2: `dotfiles :: ワークツリー掃除 孫2 掃除スキル新設`

## 依存関係と実行順序

```
孫1 (ocw rm が -f を要求した原因を突き止め、-f が要る条件を確定させる)
  ↓ 「いつ -f が要るのか」が確定して初めて、孫2 が -f の判断手順をスキルへ書ける
孫2 (worktree-cleanup スキル新設。孫1 が確定した条件を安全確認フローに埋め込む)
```

**直列。** 触るファイルは孫1（`skills/umbrella-orchestrator/SKILL.md` と、必要なら
`docs/` 配下の新規文書）・孫2（`skills/worktree-cleanup/` 新規 + `skills/README.md`）で
重ならないが、**孫2 のスキル本文の中核が「`-f` を使ってよい条件」であり、それを確定させるのが
孫1 の仕事**なので並列にできない。孫1 の結論が「実は運用を変えれば `-f` は要らない」だった
場合、孫2 が書くべき手順そのものが変わる。

> スキル名 `worktree-cleanup` は本計画書で固定する（孫2 が勝手に変えない）。傘ブランチ名と
> 一致させてある。変えたくなったら孫2 は実装前に司令官へ報告すること。

---

## 背景1: 人間の問題意識（逐語）

掃除の依頼そのもの（スキル化の対象となった作業）。

> dotfiles のもう不要なワークツリーをクリーンアップしてください。ocw rm で。

その直後、スキル化を求めた発言。**これが本傘の要求仕様の一次情報源である。**

> こういうクリーンアップを毎回自然言語で指示するの面倒だから、なんらかスキルにしておきたい。
> いまいるのが傘だったら孫を、main とか master みたいなところだったら同じリポジトリの、
> 明示的に指示したら herdr 全体のワークスペースを、という形でスコープを分けられるといいな。
> 消す前には一応リストして確認してくれるとよい。

相談AIが自分で実装を始めようとした時点での介入。

> へい、この会話でやらず委譲してよ。スキル探して

## 背景2: 人間が確定させた決定事項（覆さないこと）

相談中の選択式の問いに対して人間が選んだ内容。いずれも司令官・孫が覆してよいものではない。

- **発動方式は「自動発動＋明示起動の両対応」。** `description` に発動条件を書きつつ、
  `argument-hint` でスコープ指定も受ける。`/xxx` 明示起動のみの案（`pr-review-loop` /
  `umbrella-handoff` と同じ型）は**選ばれなかった**。理由は背景1の逐語のとおり、
  「毎回自然言語で指示するのが面倒」という動機に直接効くのが自動発動だから
- **`herdr` スコープの定義は「全ワークスペースの全リポジトリを横断」。**
  各ワークスペースが指すリポジトリを集め、それぞれで不要ワークツリーを探す。dotfiles 以外
  （`lora-dataset-forge` / `gallery-dl` / `sheaf` など）も対象に入る。「孤児ワークスペースの
  閉鎖」を含める案・「孤児ワークスペースの閉鎖だけ」にする案は**どちらも選ばれなかった**
- **`ocw rm` が「not merged」で拒否したときは、`gh` で PR のマージ状態を確認したうえで、
  人間に承認を取ってから `-f` を使う。** 確認を取らず自動で `-f` する案は**選ばれなかった**。
  また `ocw.githubMergeCheck` の有効化を勧める案も**選ばれなかった**（「スコープ外」参照）
- **削除前に必ずリストを出して確認を取る。** 逐語「消す前には一応リストして確認して
  くれるとよい」

## 背景3: 既存の穴

### 穴1: 単体で発動できるクリーンアップスキルが無い

`skills/ocw/SKILL.md` は `ocw` CLI の存在告知に徹しており、使い方は `ocw help <topic>` へ
誘導するだけである（同スキル冒頭「使い方は `ocw help` で調べる」）。
**どのワークツリーが不要かを判断するフローは持っていない。**

`skills/umbrella-orchestrator/SKILL.md` §3.3 `/check` の手順5「クリーンアップ提案」は
判断フローを持っているが、**傘の司令官が `/check` を回している最中にしか動かない**。

> 5. **クリーンアップ提案**
>    - マージ済み＋検証済みの孫のうち、まだワークツリーが残っているものがあれば
>      `ocw rm <孫ブランチ名>` を提案（**まず `--force` なしで**。…）

今回まさに、**傘の司令官セッションが既に終了した後に、残骸だけが7本残っていた**。
この状態を拾う主体が現状どこにもいない。

### 穴2: スコープという概念自体が無い

`umbrella-orchestrator` のクリーンアップは「計画書の進捗テーブルに載っている孫」に対象が
閉じている。人間が求めているのは、**今いる場所からスコープを自動決定する**振る舞い
（傘 → 孫だけ／`main`・`master` → そのリポジトリ全体／明示指示 → Herdr 全体）であり、
これは既存のどのスキルにも無い。

### 穴3: 既存スキルの記述と実測が食い違っている

`skills/umbrella-orchestrator/SKILL.md` §3.3 は次のように書いている。

> - **`--force` は基本的に不要。** `ocw rm`（`bin/ocw`）のマージ済み判定は
>   `ocw.mergedInto`（設定） → 作成時のベース（`<worktree の git dir>/ocw-base-ref`
>   に永続化される） → `HEAD` → `origin/HEAD` の順に候補を集め、各候補について
>   `git merge-base --is-ancestor` に加えて squash マージ検出（`commit-tree` +
>   `git cherry` によるパッチID比較）も試す。孫は傘ブランチへ squash マージされることが
>   多いが、作成時のベース（＝傘ブランチ）が候補に入り squash 検出も効くため、
>   **`--force` なしの `ocw rm` が普通に通る**

**実測はこれに反した（背景4参照）。** 孫6本すべてが `-f` を要求した。同スキルはこの拒否に
ついて「傘運用で実際に遭遇するのはほぼこちら」とも書いており、**記述内部でも整合していない**。
この食い違いの原因究明と記述是正が孫1 の担当範囲である。

## 背景4: 実測値

すべて 2026-09-08 に dotfiles リポジトリで実測した。

### 4.1 掃除した7本と `-f` の要否

`ocw rm`（`-f` なし）を実行した結果。

| ワークツリー | PR | `-f` 要否 | `ocw rm` の応答 |
|---|---|---|---|
| `agent-handoff`（傘） | #77 | 不要 | そのまま削除できた |
| `agent-handoff-01-ai-messaging`（孫） | #71 | **必要** | `branch is not merged into any known integration ref` |
| `agent-handoff-02-handoff-skill`（孫） | #73 | **必要** | 同上 |
| `agent-handoff-03-trigger-distribution`（孫） | #76 | **必要** | 同上 |
| `ocw-usage-01-help-topics`（孫） | #72 | **必要** | 同上 |
| `ocw-usage-02-skill-and-readme`（孫） | #74 | **必要** | 同上 |
| `ocw-usage-discovery`（傘） | #75 | **必要** | 同上 |

- 孫1本目（`agent-handoff-01-ai-messaging`）を試した時点では、その傘 `agent-handoff` の
  ローカルブランチは**まだ存在していた**。それでも拒否された
- 傘 `agent-handoff` が `-f` なしで通ったのは、`git diff master..agent-handoff` が
  0ファイルだったため。もう一方の傘 `ocw-usage-discovery` は master が #77 で先へ進んだぶん
  差分が残り、拒否された

**重要**: この7本のワークツリーは既に削除済みであり、**当時の `ocw-base-ref` や git dir を
事後に読むことはできない**。孫1 は原因究明を、合成した再現ケース（テスト用リポジトリで
傘→孫を作り、squash マージしてから `ocw rm` を試す）で行うこと。

### 4.2 相談AIが実際に踏んだ安全確認の手順

`-f` を使う前にこの3点を確認した。**この手順をスキルへ落とし込むことが本傘の中核。**

1. `gh pr list --state all --json number,title,headRefName,state,mergedAt` で全ブランチの
   PR が `MERGED` であること
2. 各ブランチの最終コミット時刻（`git log -1 --format=%cI <branch>`）が PR のマージ時刻より
   **前**であること（マージ後の取りこぼしコミットが無いこと）
3. `git -C <worktree> status --porcelain` が空であること

### 4.3 配布済み `ocw` の版ずれ

- `~/bin/ocw` は `~/.local/share/dotfiles/current/bin/ocw` への symlink で、`current` の実体は
  `~/.local/share/dotfiles/generations/20260904T005108-e721b36/bin/ocw`（`e721b36` = PR #70 相当）
- そのため `ocw help <topic>`（PR #72 で入った help のトピック階層化）が**配布側にはまだ無い**。
  `ocw help rm` を叩いても素の usage が返る（司令官が 2026-09-08 に再確認済み）
- 一方 squash マージ検出は配布側にも入っている（`grep -c 'cherry\|patch-id\|squash'` が
  配布版 12 / master 版 16）。`ocw-base-ref` の永続化も配布版・master 版の両方に存在する
  （`grep -c 'ocw-base-ref'` が配布版 3 / master 版 4。司令官が 2026-09-08 に確認）。
  **したがって今回の拒否は「配布版が古いから」では説明できない。** 原因は未解明であり、
  孫1 が突き止める
- 副作用として、`skills/ocw/SKILL.md` は「使い方は `ocw help <topic>` を叩いて調べる」と
  指示しているのに、デプロイ前の環境ではそれが空振りする状態にある

### 4.4 Herdr 側の状態（孫2 の一次情報源選定に効く）

- `herdr workspace list` は JSON を返す。各要素に `workspace_id` / `label` / `agent_status` が
  あり、**`worktree` フィールドは有るものと無いものがある**（実測 14 ワークスペース中、
  `worktree` を持つのは1つだけだった）。`herdr` スコープの実装は、`worktree` フィールドの
  存在を前提にできない
- `herdr worktree list [--workspace ID | --cwd PATH] [--json]` という別系統のサブコマンドが
  ある。**司令官が 2026-09-08 に実測したところ、こちらのほうが一次情報源として素直である。**
  引数なしで叩くと呼び出し元とは無関係のリポジトリ（実測では `lora-dataset-forge`）を返した
  ため、**`--workspace` か `--cwd` を必ず指定すること。** `--json` の返り値は次の形をしており、
  `source.repo_root` でリポジトリを一意化でき、各 worktree が `branch` / `path` /
  `open_workspace_id` / `is_prunable` を持つ:

  ```json
  {"result":{"source":{"repo_root":"/home/manemone/projects/lora-dataset-forge/main",
    "repo_name":"main","source_workspace_id":"w3"},
   "worktrees":[{"branch":"oc-01-canon-recipe","is_linked_worktree":true,
     "is_prunable":false,"open_workspace_id":"w9M",
     "path":"/home/manemone/projects/lora-dataset-forge/oc-01-canon-recipe"}]}}
  ```

  これは司令官の実測であり、孫2 は鵜呑みにせず自分でも叩いて確認したうえで採用・不採用を
  判断してよい。ただし採用しない場合は理由を PR 説明に書くこと

- `herdr pane list` の各 pane は `cwd` / `workspace_id` / `label`（`commander` /
  `implementer` / `reviewer`）を持つ。ワークスペース → リポジトリの対応を取るもう一つの経路

## 背景5: `ocw` 側の既存の仕組み

`ocw help rm` / `ocw help config`（master 版）と `bin/ocw` 本体から読み取った事実。

- マージ判定の候補 ref は4段階: `ocw.mergedInto` → 作成時 base-ref（worktree の git dir 内
  `ocw-base-ref` に永続化）→ `HEAD` → `origin/HEAD`
- 判定は各候補について (a) ancestry → (b) squash 検出 → 全候補が落ちた後に一度だけ
  (c) `ocw.githubMergeCheck` が true かつ `gh` がある場合の `gh pr list --head <branch>
  --state merged`
- `ocw.githubMergeCheck` の既定は **false**
- 候補は**解決後の SHA でキーイングされる**（`bin/ocw` のコメント: 「keyed by the resolved SHA
  rather than the ref string」）。`ocw.mergedInto`・永続化された base_ref・`HEAD`・`origin/HEAD`
  が同じコミットを指すことは珍しくない
- 拒否メッセージは2種類あり、原因も対処も異なる:
  - `branch is not merged into any known integration ref: <branch>` — 候補 ref は解決できたが、
    is-ancestor でも squash 検出でも「マージ済み」と判定できなかった場合。**実測7本の拒否は
    すべてこちら**
  - `cannot determine an integration ref ...: set ocw.mergedInto or use -f` — 候補 ref が
    1つも解決できなかった場合。非 bare リポジトリでは `HEAD` が必ず解決するため、通常は出ない
- `ocw rm` は成功時に「cwd が一致する Herdr ワークスペースを閉じる」まで面倒を見る。実測でも
  7本すべてで `closing Herdr workspace: <id>` が出た。**スキル側でワークスペースを個別に
  閉じる処理を書く必要は無い**
- `ocw rm` は入力が複数ワークツリーに曖昧一致すると自動選択せず停止する（破壊的操作のため）
- `outcome`（計測用）は `--force` の有無ではなくマージ判定の結果で決まる。マージ済みと判定
  できれば `success`、できなければ `failure`

## 背景6: AGENTS.md 最重要ルールとの関係整理（本傘の性質上、必読）

**本傘は「破壊的操作を自動化するスキル」を作るものである。** AGENTS.md の最重要ルールとの
関係を、孫が迷わないようここで確定させる。

### 6.1 禁止コマンドリストとの関係

AGENTS.md が人間の明示的指示なしに禁じているのは
`git merge` / `git pull` / `git reset --hard` / `git push --force` / `gh pr merge` の5つである。
本スキルが実行する `ocw rm`（内部で `git worktree remove` + `git branch -D` 相当）は
**このリストに含まれない。** したがって「禁止コマンドをスキルで迂回する」たぐいの設計ではない。

ただしリストの**精神**（不可逆操作の前に人間へ照会する）は本スキルにそのまま効く。
人間が確定させた「削除前に必ずリストを出して確認を取る」（背景2）は、この精神を満たすための
要件であり、**スキルから削ってはならない中核仕様**である。孫2 は次の2点を SKILL.md に
明記すること。

1. **削除候補は必ず一覧で提示し、人間の承認を得てから実行する。** 無言で消さない
2. **`-f` は「PR がマージ済みであることを `gh` で確認したうえで、人間に承認を取ってから」
   のみ使う。** 自動で `-f` に飛ぶ経路を作らない

### 6.2 スキル自身が禁止コマンドに触れないこと

スキル本文に `git pull` / `git merge` を書かない。掃除の前にリモートの状態を知りたい場合は
`git fetch`（禁止リストに無い）と `gh pr list` で足りる。

### 6.3 その他の最重要ルール

- **linter の抑制ディレクティブ（`# shellcheck disable=...` 等）や `.pre-commit-config.yaml` の
  除外追加を AI の判断で入れない。** 指摘が不合理だと判断したら抑制せず人間へ報告する
- **deploy スクリプトを実オペレーションで実行しない。** 検証は `--dry-run` か
  `tests/deploy_smoke.sh` のサンドボックス経由で行う

## スコープ外

- **`bin/ocw` 本体の改修。** マージ判定ロジックの変更・`ocw rm` への新オプション追加は本傘では
  扱わない。スキルは既存の `ocw` をそのまま呼ぶ。**孫1 が原因を突き止めた結果「`bin/ocw` を
  直すのが筋」という結論になった場合も、本傘では直さず、原因と推奨対処を文書に記録して
  司令官へ報告すること**（別傘の題材になる）
- **`ocw.githubMergeCheck` の既定変更や、その有効化を人間へ勧めること。** 相談で明示的に
  選ばれなかった選択肢である。孫1 が原因究明の過程で `githubMergeCheck` の挙動に触れるのは
  構わないが、「有効化を勧める」提案を成果物に書かない
- **Herdr の孤児ワークスペース閉鎖機能。** `herdr` スコープの定義から外れる（人間が選んだのは
  「全ワークスペースの全リポジトリを横断」する案）
- **配布済み `ocw` の版ずれの解消（デプロイ実行）。** 実測値として記録するに留める。
  デプロイは人間の操作であり、AGENTS.md が AI の実行を禁じている
- **`skills/ocw/SKILL.md` の改訂。** 版ずれで `ocw help <topic>` が空振りする件（背景4.3）は
  デプロイで解消するため、スキル側の記述は変えない

## 共通の必須検証（全孫が省略しない）

AGENTS.md「コミット前の必須ステップ」に従う。

- `pre-commit run --all-files`
- `docs/` に新規ファイルを追加したら
  `./tools/doc-id/doc-id assign docs/path/to/file.md` で採番し、地の文の言及にも DOC-ID を書く
- `shared/helpers.sh` / deploy スクリプト / `bin/` / `templates/repo-baseline/` を触るなら
  それぞれ AGENTS.md の該当ステップを追加で踏む

**本傘の想定では、孫1・孫2 とも `skills/` と `docs/` の Markdown しか触らない。** その範囲に
留まる限り `tests/deploy_smoke.sh` / `bin/tests` / `deploy-all.sh --dry-run` は要求されない
（`skills/` はディレクトリを足すだけで `skills/deploy.sh` が自動検出するため、deploy 側の
コード変更が発生しない）。**`skills/deploy.sh` や `shared/helpers.sh` に手を入れる設計を採る
場合は、`tests/deploy_smoke.sh` と `./deploy-all.sh --dry-run` が必須になる。** その判断が
必要になった孫は、実装前に司令官へ報告すること。

**実オペレーションの deploy（`deploy-all.sh` の素の実行）は禁止。**

---

## 孫1用プロンプト:

````markdown
# 孫1: `ocw rm` が `-f` を要求した原因の究明と、`umbrella-orchestrator` の記述是正

## 背景

計画書 `docs/planning/DOC-2609080222_worktree-cleanup-skill_計画.md` の
「背景3: 既存の穴」の穴3、「背景4: 実測値」、「背景5: `ocw` 側の既存の仕組み」を
**必ず先に読むこと。** 実測値・拒否メッセージの全文・候補 ref の解決順がそこにある。

要点だけ再掲する。

- `skills/umbrella-orchestrator/SKILL.md` §3.3 は「**`--force` は基本的に不要**。…
  作成時のベース（＝傘ブランチ）が候補に入り squash 検出も効くため、**`--force` なしの
  `ocw rm` が普通に通る**」と書いている
- **実測では、傘へ squash マージ済みの孫6本すべてが `-f` を要求した。** 拒否メッセージは
  全件 `branch is not merged into any known integration ref: <branch>` だった
- 同じ §3.3 は別の箇所で、この拒否について「**傘運用で実際に遭遇するのはほぼこちら**」とも
  書いている。**同一節の中で記述が矛盾している**
- 配布版と master 版の差（版ずれ）では説明できない。squash 検出も `ocw-base-ref` の永続化も
  両方に存在することを司令官が確認済み（計画書 背景4.3）

## やること

### 1. 原因を突き止める

**当時のワークツリーは既に削除済みで、`ocw-base-ref` や git dir を事後に読むことはできない。**
合成した再現ケースで調べること。

再現の型（あくまで出発点。実態に合わせて調整してよい）:

1. 一時ディレクトリにテスト用リポジトリを作る（`mktemp -d` を使う。`/tmp` 直下に散らかさない）
2. `master` 相当のブランチを作り、そこから傘ブランチを切る
3. 傘から孫ワークツリーを `ocw` で作る（`ocw-base-ref` に傘が記録されることを確認する）
4. 孫で**複数コミット**を積む（実際の運用では実装コミット＋レビュー修正コミットで
   複数になるのが普通だった）
5. 傘へ **squash マージ**する（`git merge --squash` は AGENTS.md の禁止リストにある
   `git merge` にあたる。**テスト用の使い捨てリポジトリ内であっても、本タスクでは
   `git merge` 系コマンドを使わずに再現すること。** `git commit-tree` や
   `git read-tree` + `git commit` で squash 相当のコミットを合成すれば、禁止コマンドに
   触れずに同じ形の履歴が作れる。どうしても再現できない場合は、無断で禁止コマンドを
   使わず司令官へ報告して指示を仰ぐこと）
6. `ocw rm <孫>` を `-f` なしで叩き、通るか拒否されるか観測する

調べる観点の候補（網羅ではない。実測で絞ること）:

- `ocw-base-ref` に書かれた値が、`ocw rm` 実行時点で解決できているか
  （傘ブランチが削除済み／改名済みだと解決に失敗しうる。ただし実測では孫1本目の時点で
  傘のローカルブランチは存在していた）
- squash 検出（`commit-tree` + `git cherry` によるパッチ ID 比較）が、**孫が複数コミットを
  持つ場合**に成立するか。複数コミットを1つに潰した squash のパッチ ID は、個々のコミットの
  パッチ ID とは一致しない
- squash 後に傘ブランチ側で別の孫がマージされて先へ進んだ場合に、パッチ ID 比較が崩れるか
- 候補 ref が「解決後の SHA でキーイングされる」ことにより、意図した候補が別候補に
  吸収されて消えていないか
- 実測で唯一 `-f` なしで通った傘 `agent-handoff` は `git diff master..agent-handoff` が
  0ファイルだった。これは ancestry ではなく「差分ゼロ」で通ったのか

**原因が特定できなかった場合は、無理に断定しない。** 「何が起きていないかは確かめられた」
という否定的知見も価値がある。その場合は「試したこと・排除できた仮説・残る仮説」を
文書に残すこと。

### 2. `skills/umbrella-orchestrator/SKILL.md` §3.3 の記述を実態に合わせる

最低限、次の2つを解消すること。

- **同一節内の矛盾**: 「`--force` は基本的に不要」と「傘運用で実際に遭遇するのはほぼこちら
  （= 拒否される）」が並んでいる。実測に照らしてどちらが実態かを決め、片方を書き換える
- **実測との食い違い**: 孫6本すべてが `-f` を要求した事実を、実測値として記述に反映する
  （何本中何本か、どの拒否メッセージだったかまで書く。このスキルの既存の書きぶりは
  実測を数値付きで残す作法になっているので、それに揃える）

原因が判明した場合は「どういう条件のとき `-f` が要るのか」を条件付きで書く。判明しなかった
場合は「原因は未特定。実測では傘運用の孫は `-f` を要求した」と正直に書く。
**推測を実測であるかのように書かないこと。**

### 3. 文書化の要否を判断する

原因究明の結果が「運用中に繰り返し引く事実」になるなら `docs/reference/` へ、
「技術決定の記録」になるなら `docs/adr/` へ新規文書を起こす。ただし
**SKILL.md への追記で足りるなら新規文書は作らない**（文書を増やすこと自体が目的ではない）。

新規文書を作る場合は `DOC-2609080222_<説明的ファイル名>.md` で作り、
`./tools/doc-id/doc-id assign docs/path/to/file.md` で採番すること。地の文で言及するときは
DOC-ID を明示する。

### 4. 孫2 への申し送りを PR 説明に書く

孫2 は本孫の結論を使って「`-f` を使ってよい条件」をスキル本文へ書く。**PR 説明に
「孫2 が使う結論」を1〜3行で明示すること。** 例:

> 孫2 への申し送り: 傘へ squash マージされた孫は `-f` なしでは削除できない（原因: XXX）。
> スキルは「拒否されるのが既定」を前提にした安全確認フローを持つこと。

## スコープ外

- **`bin/ocw` 本体の改修。** 原因が `bin/ocw` の実装にあると判明しても、本孫では直さない。
  原因と推奨対処を記録して司令官へ報告すること
- **`ocw.githubMergeCheck` の有効化を勧めること。** 挙動の調査は構わないが、
  「有効にすべき」という提案を成果物に書かない（人間が明示的に選ばなかった選択肢）
- `skills/ocw/SKILL.md` の改訂

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって保護されて
いること。ただし本孫の成果物は主に Markdown 文書であり、シェルコードを追加しない場合は
自動テストの追加が適さない。**その場合はテストを追加せず、手で確認した結果を PR 説明に
書くこと。**

- `pre-commit run --all-files` が通る（`doc-id check` / `verify` を含む）
- `skills/umbrella-orchestrator/SKILL.md` §3.3 に、同一節内で矛盾する記述が残っていない
- 記述された挙動が、実際に再現ケースで観測した結果と一致している
- 新規文書を追加した場合、DOC-ID が採番され、地の文の言及にも DOC-ID が書かれている

各項目と test example を1対1対応させる必要はない。複数の条件を1つの scenario で検証してよい。

## 必須の検証コマンド

```bash
pre-commit run --all-files
./tools/doc-id/doc-id check
./tools/doc-id/doc-id verify
```

`shared/helpers.sh` や deploy スクリプトを触った場合のみ追加で（本孫では想定していない）:

```bash
./deploy-all.sh --dry-run
tests/deploy_smoke.sh
```

**実オペレーションの deploy（`deploy-all.sh` の素の実行）は禁止。**

## 注意

- **人間の明示的指示がない限り `git merge` / `git pull` / `git reset --hard` /
  `git push --force` / `gh pr merge` を実行しない**（AGENTS.md 最重要ルール）。
  再現ケースの構築でもこれは変わらない（上記「1. 原因を突き止める」参照）
- **linter の抑制ディレクティブや `.pre-commit-config.yaml` の除外追加を自分の判断で
  入れない**（AGENTS.md 最重要ルール）。不合理だと思ったら人間へ報告する
- 一時ディレクトリは `mktemp -d` で作る。使い終わったら片付ける
- 実 `$HOME` のワークツリーや Herdr ワークスペースを削除しない。**再現は使い捨ての
  テスト用リポジトリの中だけで行うこと**
- `docs/` の文書に地の文で言及するときは DOC-ID を明示する（AGENTS.md）
````

---

## 孫2用プロンプト:

````markdown
# 孫2: 掃除スキル `skills/worktree-cleanup/` の新設

## 背景

計画書 `docs/planning/DOC-2609080222_worktree-cleanup-skill_計画.md` を
**必ず先に全部読むこと。** 特に次の節は本孫の要求仕様そのものである。

- 「背景1: 人間の問題意識（逐語）」— スコープ3種と「消す前にリストして確認」の出どころ
- 「背景2: 人間が確定させた決定事項（覆さないこと）」— 発動方式・`herdr` スコープの定義・
  `-f` の扱い
- 「背景4.2」— 相談AIが実際に踏んだ安全確認の3点。**これをスキルへ落とし込むことが本孫の中核**
- 「背景4.4」— Herdr 側の実測（`herdr worktree list` の JSON 形状。司令官の実測）
- 「背景5」— `ocw` 側の既存の仕組み（マージ判定の候補 ref、拒否メッセージ2種、
  `ocw rm` がワークスペースまで閉じること、曖昧一致で停止すること）
- 「背景6」— AGENTS.md 最重要ルールとの関係整理。**破壊的操作を扱うスキルなので必読**

**孫1（`worktree-cleanup-01-merge-detection`）の PR 説明に「孫2 への申し送り」がある。
必ず読み、その結論を本スキルの `-f` 判断フローへ反映すること。**
`gh pr list --search "worktree-cleanup-01" --state all` で見つかる。

## やること

### 1. `skills/worktree-cleanup/SKILL.md` を新設する

`skills/` にディレクトリを作るだけでよい（`skills/deploy.sh` が自動検出する。
AGENTS.md「実装時の注意」）。**`skills/deploy.sh` や `shared/helpers.sh` を触る必要は無い。**
触る設計になりそうなら、実装前に司令官へ報告すること（検証ステップが増えるため）。

### 2. frontmatter — 自動発動と明示起動の両対応

人間が選んだ発動方式は「**自動発動＋明示起動の両対応**」である（`/xxx` 明示起動のみの案は
選ばれなかった）。したがって:

- `description` に**自動発動の条件**を書く。「ワークツリーの掃除・クリーンアップ・不要な
  worktree の削除を求められたら発動」といった趣旨。既存スキルの `description` の書きぶりを
  参考にすること（`skills/ocw/SKILL.md` が自動発動型、`skills/pr-review-loop/SKILL.md` と
  `skills/umbrella-handoff/SKILL.md` が明示起動型で「自動発動はしない」と明記している。
  **本スキルは前者側なので「自動発動はしない」と書かないこと**）
- `argument-hint` にスコープ指定を書く（`skills/umbrella-orchestrator/SKILL.md` が
  `argument-hint` を持つので書式の参考になる）

### 3. スコープの自動決定

人間の逐語（計画書 背景1）:

> いまいるのが傘だったら孫を、main とか master みたいなところだったら同じリポジトリの、
> 明示的に指示したら herdr 全体のワークスペースを

3つのスコープを定義し、**引数が無いときは現在地から自動決定する**手順を書くこと。

- **傘スコープ**: 現在地が傘ブランチのワークツリー。対象はその傘の孫だけ。傘かどうかの
  判定方法と、孫の一覧をどこから取るか（計画書の進捗テーブルか、ブランチ名の接頭辞か、
  その両方か）を決めて書く。**判定に使える材料は自分で確かめて選ぶこと**
- **リポジトリスコープ**: 現在地が `main` / `master` などの統合ブランチ。対象は同じ
  リポジトリの全ワークツリー
- **`herdr` スコープ**: 明示指定でのみ発動。**全ワークスペースの全リポジトリを横断する**
  （これが人間の選んだ定義。「孤児ワークスペースの閉鎖」は含めない）

**自動決定がどれにも当てはまらない／曖昧なときは、勝手に広いスコープを選ばず人間に聞くこと。**
破壊的操作のスコープを推測で広げるのは事故の型である。

### 4. `herdr` スコープの一次情報源を確定させる

計画書 背景4.4 に司令官の実測がある。要点:

- `herdr workspace list` の `worktree` フィールドは**大半のワークスペースに無い**
  （実測14中1）。これを前提にした実装は書けない
- `herdr worktree list --workspace <id> --json` は `source.repo_root` と、各 worktree の
  `branch` / `path` / `open_workspace_id` / `is_prunable` を返す。**引数なしで叩くと
  呼び出し元と無関係のリポジトリを返す**ので `--workspace` か `--cwd` を必ず指定する

**自分でも実際に叩いて確認し、どちらを一次情報源にするか決めること。** 司令官の実測を
鵜呑みにしなくてよいが、採用しない場合は理由を PR 説明に書くこと。

### 5. 安全確認フロー（本スキルの中核）

計画書 背景4.2 の3点を手順として書く。加えて計画書 背景6.1 の2要件を満たすこと。

必須の性質:

1. **削除候補を必ず一覧で提示し、人間の承認を得てから実行する。無言で消さない**
   （人間の逐語「消す前には一応リストして確認してくれるとよい」）
2. **まず `-f` なしの `ocw rm` を試す**
3. **`branch is not merged into any known integration ref` で拒否されたら、`gh` で
   PR のマージ状態を確認する。** その上で:
   - `gh pr list --state all --json number,title,headRefName,state,mergedAt` で
     PR が `MERGED` であること
   - `git log -1 --format=%cI <branch>` の最終コミット時刻が PR のマージ時刻より**前**で
     あること（マージ後の取りこぼしコミットが無いこと）
   - `git -C <worktree> status --porcelain` が空であること
4. **3点が揃ってから、改めて人間に承認を取って `-f` を使う。** 自動で `-f` へ飛ぶ経路を
   作らない（人間が明示的に「確認を取らず自動で `-f`」を却下している）
5. **PR が無い／`MERGED` でない／未コミットの変更があるワークツリーは削除候補から外す。**
   その旨を人間へ報告する

拒否メッセージがもう一方（`cannot determine an integration ref ...`）だった場合の扱いも
書くこと（計画書 背景5 に両者の違いがある）。

### 6. 落とし穴を書く

計画書 背景5 から、スキル利用者が踏む穴を SKILL.md に明記すること。

- **`ocw rm` は入力が複数ワークツリーに曖昧一致すると自動選択せず停止する。** そのときは
  そのワークツリーだけスキップし、完全な名前を人間に仰ぐ。他の掃除は止めない
- **`ocw rm` は成功時に cwd の一致する Herdr ワークスペースを閉じるところまで面倒を見る。**
  スキル側でワークスペースを個別に閉じる処理を書かない（実測7本すべてで
  `closing Herdr workspace: <id>` が出た）
- **自分がいるワークツリーは消せない。** 傘スコープで司令官自身のワークツリーを候補に
  入れないこと

### 7. `skills/README.md` を追随させる

冒頭のスキル一覧表に `worktree-cleanup` の行を足す。README は「ルート `README.md`（全体）」と
「各ツールの `README.md`（詳細）」の二層構造なので、**ルート `README.md` にスキル一覧や
スキル名の列挙があれば、そちらも追随すること**（`git grep -n 'umbrella-handoff' README.md`
で確認できる）。片方だけ更新しない。

### 8. エージェント非依存

**スキルは AI 不問**（Claude Code / Codex / OpenCode）。YAML frontmatter を除き自然言語のみで
完結させる（既存スキル全てがこの作法）。

- **`SendMessage` は Claude Code 固有。** スキル本文がこれを前提にしてはいけない
  （`skills/umbrella-orchestrator/SKILL.md` §5 の二段構えが正典）。もっとも本スキルは
  AI 間通信をしないので、そもそも登場しないはず
- 特定エージェントの画面表示やコマンドに依存する書き方をしない

## スコープ外

- `bin/ocw` 本体の改修。スキルは既存の `ocw` をそのまま呼ぶ
- `ocw.githubMergeCheck` の既定変更や、その有効化を人間へ勧めること
- Herdr の孤児ワークスペース閉鎖機能
- `skills/ocw/SKILL.md` の改訂
- `skills/umbrella-orchestrator/SKILL.md` の §3.3 の書き換え（孫1 の担当）。
  ただし新スキルへの相互参照を1行足す程度は構わない

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって保護されて
いること。ただし本孫の成果物は Markdown 文書のみであり、シェルコードを追加しない場合は
自動テストの追加が適さない。**その場合はテストを追加せず、手で確認した結果を PR 説明に
書くこと。**

- `pre-commit run --all-files` が通る
- `skills/worktree-cleanup/SKILL.md` の frontmatter が `name` / `description` /
  `argument-hint` を持ち、既存スキルと同じ形式である
- **削除前に人間の承認を取る手順が、どのスコープの経路からも迂回できない**（無言で
  `ocw rm` へ到達する記述が1つも無い）
- **`-f` へ到達する経路が、`gh` でのマージ確認と人間の承認を必ず経る**
- スコープ3種それぞれについて、対象の集め方が手順として書かれている
- `skills/README.md`（およびルート `README.md` にスキルの言及があればそちら）が追随している
- スキル本文が特定の AI エージェント固有の機能に依存していない

各項目と test example を1対1対応させる必要はない。複数の条件を1つの scenario で検証してよい。

## 必須の検証コマンド

```bash
pre-commit run --all-files
```

`skills/deploy.sh` や `shared/helpers.sh` を触った場合のみ追加で（本孫では想定していない。
触る設計になったら実装前に司令官へ報告すること）:

```bash
./deploy-all.sh --dry-run
tests/deploy_smoke.sh
```

**実オペレーションの deploy（`deploy-all.sh` の素の実行）は禁止。**
`skills/deploy.sh` を単体で実行するのも禁止（実 `$HOME` の symlink を張り替えるため）。

## 注意

- **本孫が書いているのは「破壊的操作を自動化するスキル」である。** 計画書 背景6 を必ず読み、
  人間の承認を取る経路を絶対に迂回できない形で書くこと
- **スキル本文に `git pull` / `git merge` / `git reset --hard` / `git push --force` /
  `gh pr merge` を書かない**（AGENTS.md 最重要ルール。計画書 背景6.2）。リモートの状態が
  要るなら `git fetch` と `gh pr list` で足りる
- **linter の抑制ディレクティブや `.pre-commit-config.yaml` の除外追加を自分の判断で
  入れない**（AGENTS.md 最重要ルール）
- **実 `$HOME` のワークツリーや Herdr ワークスペースを、動作確認と称して削除しない。**
  スキルの検証は文書レビューと、`--json` 系の**読み取り専用コマンド**の実行に留めること
- `docs/` の文書に地の文で言及するときは DOC-ID を明示する（AGENTS.md）
````

---

## 実装完了後の流れ（各孫共通・必須）

実装が完了したら、以下を**自律的に**実行すること:

1. PR を作成する。**PR の向き先は必ず `worktree-cleanup` にすること。`master` には絶対に出さない。**
2. `/pr-review-loop` を起動する（PR がない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する

実装が終わったタイミングで止まらず、必ずここまでやりきること。

PR 説明の書き方は `docs/design/DOC-2608020715_プルリクエストの作法.md` に従うこと。

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `worktree-cleanup` から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:

```
git fetch origin
git checkout -b <新しいブランチ名> origin/worktree-cleanup
```

**`git pull` / `git merge` を使わないこと**（AGENTS.md 最重要ルール）。`git fetch` +
`origin/worktree-cleanup` からの分岐で同じ結果になる。傘ブランチがまだ origin に無い場合は
ローカルの `worktree-cleanup` から切ってよい。
