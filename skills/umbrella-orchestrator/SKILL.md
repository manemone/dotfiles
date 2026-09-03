---
name: umbrella-orchestrator
description: 傘ブランチの孫ライフサイクル管理。計画書の読み取り、孫ブランチのspawn、マージ検出と検証、計画書更新を自動化。
argument-hint: "spawn <grandchild> | check | status | finalize | autopilot"
---

# Umbrella Orchestrator — 傘ブランチ自動化スキル

**AI 不問。** YAML frontmatter を除き自然言語のみで完結する。
Herdr があると自動化度が上がるが、必須ではない。

## 1. 概要

傘ブランチ方式（1本の傘の下に複数の孫ブランチを切り、順次マージする開発フロー）の
司令官役を自動化する。このドキュメントを読んだ AI が司令官として振る舞う。

### 3つの役割と分業

```
司令官（このスキルを読んだAI）
  → spawn, マージ検出, 検証, 計画書更新
  → 実装コードのレビューはしない
  → PRマージはしない（人間の仕事）

実装AI（別ペーン/別会話）
  → 実装, PR作成, /pr-review-loop 起動
  → review 工作は全部こっち

レビューAI（pr-review-loop が管理）
  → レビュー, 指摘, 再レビュー
```

**司令官が見るのは「PR がマージされたか」だけ。** 中身には関与しない。

## 2. 計画書のフォーマット

司令官が読める計画書は以下を必須とする:

### 2.1 孫ブランチ進捗テーブル

```markdown
| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 0 | `ph-00-fix` | 修正 | ✅ PR #80 マージ済 |
| 1 | `ph-01-feat` | 機能 | 🔄 実装中 |
```

- 「孫」列: 整数
- 「ブランチ」列: コードスパンで完全なブランチ名（`ocw` は接頭辞を一切付けないので、
  ここに書いた値がそのまま実ブランチ名になる。§5「`ocw -H` が作るもの」参照）
- 「状況」列: `⬜ 待機中` / `🔄 実装中` / `✅ PR #XX マージ済`

### 2.2 孫用プロンプト

`## 孫N用プロンプト:` で始まるセクションがあり、その中のコードブロックに
実装AI向けプロンプト全文が入っている。全孫のプロンプトが事前に含まれていること。

**外側のフェンスは4バッククォート（````）にすること。** 孫プロンプトの中には
`` ```bash `` や `` ```python `` を書きたくなる。外側を3バッククォートにすると
**内側のブロックの閉じで外側が終わってしまい、司令官が抽出するプロンプトが
黙って途中で切れる。** 実装AIは切れたプロンプトで作業を始めてしまい、
気づくのは成果物を見たときになる。

計画書を書いたら、全孫について「外側フェンスがちょうど2本あるか」を検算すること。

### 2.3 検証方針の書き方

孫用プロンプトに検証項目を書くとき、**`## テスト（受け入れ条件）` としてテストケースを
番号付きで列挙しない。** 4項目書けば実装AIは「最低4 example 必要」と解釈し、
1つの behavior が細かい example へ過剰分割される。

原則として次の形式にする。

````markdown
## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- （守るべき behavior を書く）
- （守るべき behavior を書く）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。
````

本当に重要な安全性については、その項目に限って

> **この regression は必ず自動テストで固定する**

と明示してよい。例: 破壊的処理が原本を消さない / hardlink 先を誤って上書きしない /
検証失敗時に原本を削除しない / 実際に発生した致命的バグ。

**「必ずテスト」は本当に重要なリスクにだけ使う。** 全項目に付けると、
元の「受け入れ条件＝テストケース」列挙と何も変わらなくなる。

## 2.4 レビュー判定の読み方（マージ可否の唯一の根拠）

**`event` 種別で判断してはいけない。** 実装AIと同じアカウントが作ったPRには
GitHub が `APPROVE` / `REQUEST_CHANGES` を受け付けないため、レビューAIは
**常に `event: COMMENT` で投稿する**。`APPROVED` を待つ実装にすると
**永久に1本もマージできない。**

判定は**レビュー本文**から読む。以下の3点を守らないと取りこぼす。

1. **全件を走査する。** `gh pr view <PR> --json reviews` には
   本文なしのインラインコメントが大量に混ざる（実測で17件中13件が本文なし）。
   本文ありだけ拾うと末尾の承認が埋もれる
2. **装飾記号を除去してから照合する。** レビューAIの書式は揺れる
   （`判定: 承認` のことも `**判定**: **承認**` のこともある）
3. **SHA は前方一致で比較する。** 対象HEADは短縮7桁のことも
   フル40桁のこともあり、単純な文字列一致では取りこぼす
4. **`判定:` 行が無い形式がある。** 承認が見出しにしか現れず
   （`🤖✅ 承認` / `🤖🔍 レビュー指摘` のような1行目だけ）、本文に `判定:` が
   1つも出てこないことがある。`判定:` だけを探す実装は**承認を丸ごと取りこぼす**
   （実測: 同一の傘の中で、`判定:` 付きの回と無しの回が混在した）

```python
plain = re.sub(r'[*`]', '', body)
lines = plain.strip().splitlines()
m = re.search(r'判定\s*[:：]\s*(\S+)', plain)
if m:                                   # 通常形: 本文に 判定: がある
    verdict = '承認' if m.group(1).startswith('承認') else '変更要求'
elif lines and re.search(r'✅|🔍|承認|レビュー指摘', lines[0]):  # 見出しだけの形
    head = lines[0]
    verdict = '変更要求' if ('🔍' in head or 'レビュー指摘' in head) else '承認'
else:                                   # どちらの形でも読めない
    verdict = None
m = re.search(r'HEAD\s*[:：]\s*([0-9a-f]{7,40})', plain)
ok = m and (latest_sha.startswith(m.group(1)) or m.group(1).startswith(latest_sha))
```

`body` が空文字列（本文なしのインラインコメント）の場合、`lines` は空リストになる。
`lines[0]` にそのまま添字アクセスすると `IndexError` になる（本文なしは
17件中13件という**最頻出のケース**なので、ここで落ちると全件走査が止まる）。
`elif lines and ...` の短絡評価で空リストを弾き、`verdict = None`（＝次段落の
「どちらの形でも読めなかった」状態）へ落とす。

`'承認' in head` のような部分一致だけで判定すると、「前回の承認を取り消します」
のような**変更要求の見出しに「承認」という字面が混ざるケース**を誤って承認判定
してしまう（`re.sub(r'[*`]', '', body)` は絵文字を落とさないため、`✅`/`🔍` の
マーカーは見出しに残っている）。**変更要求を示す `🔍` / `レビュー指摘` を先に
判定してから承認に倒す**ことで、変更要求のPRを誤って承認扱いする向きの事故を防ぐ。

**どちらの形でも読めなかったら、本文末尾の結論を人間の目で読む。**
「上記N件は必ず修正してください」で終わっていれば変更要求、
「未解決の指摘なし。承認します」で終わっていれば承認である。
**読めなかったことを「承認されていない」と同一視して黙って待つのが最悪の分岐**で、
承認済みのPRが誰にも拾われないまま止まる。

**マージしてよいのは次をすべて満たすときだけ**:

- 判定を含む**最後の**レビューが「承認」
- その対象HEAD が PR の最新コミットと前方一致（古いHEADへの承認でマージしない）
- implementer が `working` でない

**implementer が `working` だからといって「承認はまだ出ていない」と推測しないこと。**
承認の有無は必ず API で確認する（この推測で2回取り逃した実績がある）。

### 2.5 ワークスペースラベル（任意節）

計画書に `## ワークスペースラベル` 節を書くと、司令官が Herdr ワークスペースを
改名するときの日本語ラベルを即興で作らずに済む（書式・導出規則は §5「ワークスペース
ラベル」参照）。必須ではない。節が無い計画書では、司令官が計画書の見出しや
進捗テーブルから機械的に要約を導出する。

## 3. コマンド

| コマンド | 用途 |
|----------|------|
| (引数なし) | 進捗表示＋次の一手提案 |
| `/status` | 進捗表示 |
| `/spawn <N>` | 孫Nを spawn（手動進行） |
| `/check` | PRマージ検出＋検証＋計画書更新 |
| `/finalize` | 傘→main PR作成 |
| `/autopilot` | 計画書作成後の全孫 spawn→finalize まで自動進行 |

### 3.0 引数なし（デフォルト）— 司令官モード

`/umbrella-orchestrator` だけが呼ばれたときの挙動:

1. **計画書を探して読み、進捗を表示**（`/status` と同じ）
2. **次の一手を提案**:
   - 未着手の孫があれば「`/spawn <N>` しますか？」または「`/autopilot` で全自動進行しますか？」
   - 全孫マージ済みなら「`/finalize` しますか？」
3. ユーザーが「はい」と言ったら該当コマンドを実行

### 3.1 `/status`

計画書の進捗テーブルを読んで表示する。副作用なし。

```
進捗:
  ✅ 0: ph-00-fix        PR #80
  🔄 1: ph-01-feat       実装中
  ⬜ 2: ph-02-cleanup     待機
```

### 3.2 `/spawn <grandchild>`

**前提**: `<grandchild>` は計画書の「孫」列の値。数値でもブランチ名でも可。

**やること**:

1. **計画書からプロンプトを抽出**
   - 進捗テーブルから該当行を特定しブランチ名を取得
   - `## 孫N用プロンプト:` セクションからコードブロックを抽出

2. **ワークツリーを作成し実装AIを起動**

   **Herdr あり（`ocw -H` が使える場合）**:
   - `ocw -H --no-commander <孫ブランチ名> <傘ブランチ名>` を叩く
   - これだけで「git worktree 作成＋Herdr ワークスペース作成＋implementer ペーン＋reviewer ペーン」が
     全部できる（孫ワークスペースに commander ペーンは作らない。§5「ワークスペース階層」参照）
   - 出力の `workspace:` 行の ID に対して `herdr workspace rename` でラベルを日本語化する
     （書式・手順は §5「ワークスペースラベル」参照。**プロンプト送信より前**に行う）
   - 起動した implementer ペーンにプロンプトを送信する

   **⚠️ herdr pane run の最重要注意点（このルールを破ると毎回実装AIが動かない）**:

   1. **プロンプト全文を打ち込まない。** 計画書の絶対パスとセクション名だけを伝える。
      `herdr pane run` は文字を1文字ずつターミナルに打ち込む。長文プロンプトは途中で止まり、
      送信されずペーストされただけの状態で放置される（Enterが送られない）。
   2. **絶対に「〜とだけ返事してください」「〜だけ確認してください」のようなメタ指示を付けない。**
      実装AIはそれを実行して返事だけして停止する。
   3. **`herdr pane run` は本文だけ打ち込んで Enter を送らないことがある。送信後に必ず
      `herdr pane send-keys <pane-id> Enter` を撃つこと。**
      1つの傘で **8回送って8回とも** これだった（spawn 4回・復帰指示 4回）。
      「たまに届かない」ではなく**届かないのが既定**だと思って手順に組み込む。

      **herdr 自身の公式ドキュメント（`herdr` skill）は「`pane run` sends the text
      and Enter together」（テキストとEnterをまとめて送る）と説明しており、この
      実測とは食い違う。** 原因は特定できていない（herdr のバージョン差か、長文・
      複数行プロンプト特有の条件かは不明）。ドキュメント通りに動くと信じて確認を
      省略しないこと — このPRのレビュー往復自体でも、送信後に確認したところ
      `idle` のままだったケースが複数回発生している（実測）。

      送信 → `herdr pane get <pane-id>` で `agent_status` を確認 → `idle` のままなら
      `send-keys Enter` → 再確認、を `working` になるまで繰り返す。

      **`herdr pane run` で同じ本文を再送してはいけない。** 本文自体は届いており
      Enter だけが送られていないので、再送するとプロンプト欄に**2重に積まれる**。
      画面上は `Press up to edit queued messages` のような表示になり、送信済みに見えて
      実際には走っていない状態が続く。確認を省略すると孫が起動しないまま巡回だけが進む。
   4. **spawn したコマンドが意図どおりか `ps` で確認する。**
      implementer / reviewer のモデルや権限モードを環境変数
      （`OCW_IMPLEMENTER_COMMAND` / `OCW_REVIEWER_COMMAND`）で指定している場合、
      cron から呼ぶときは**その cron のプロンプト内にも export を書く**こと。
      司令官のシェルの export は cron に継承されない。

      ```bash
      ps -eo args | grep "permission-mode"   # 起動したコマンドの実体を確認
      ```

   **推奨フォーマット（これだけ送ればよい）**:
   ```
   herdr pane run <pane-id> "計画書 <計画書の絶対パス> の「## 孫N用プロンプト」セクションのコードブロック内の指示に従って実装してください。実装が完了したら計画書末尾の指示に従ってPR作成・レビューまで自律的に進めてください。reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングしてレビューの有無を確認してください。"
   ```

   **末尾の1文を削らないこと。** これが §5「レビュー待ちデッドロック」の**予防**である。
   この1文の有無で実測がはっきり分かれた（同一の傘での実測。内訳は §5 を参照）:

   | 孫 | 末尾の1文 | デッドロック発生 |
   |---|---|---|
   | 孫1 | なし | 1回（約10分ロス） |
   | 孫3 | なし | **3回**（司令官が毎回拾いに行った） |
   | 孫4 | **あり** | **0回** |

   孫2 はこの表に含めていない。デッドロック発生の有無を個別に記録していないため、
   憶測で0回や1回と書き足すと表そのものの信頼性を損なう。この表が支える主張は
   「末尾の1文があれば発生しない」であり、孫1・孫3（なし）と孫4（あり）の対比だけで
   十分に示せる。

   デッドロックは司令官が拾えば復旧できるが、**拾えるのは次の巡回まで待ってから**である。
   予防はプロンプトに1文足すだけなので、検知・復旧より常に安い。

   - **プロンプト末尾には必ず以下の指示を自動付与すること**:

     ```
     ## 実装完了後の流れ（必須）
     実装が完了したら、以下を**自律的に**実行してください:
     1. PRを作成する。**PRの向き先は必ず <傘ブランチ> にすること。main には絶対に出さない。**
     2. /pr-review-loop を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
     3. レビュー指摘があれば修正し、承認されるまで繰り返す
     4. 承認されたら人間に「マージしてください」と依頼する
     実装が終わったタイミングで止まらず、必ずここまでやりきってください。

     ## ブランチ作成時の注意（最重要）
     作業ブランチは**必ず <傘ブランチ> から切ること**。
     main から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
     実装開始前に以下を必ず実行すること:
     git checkout <傘ブランチ> && git pull --rebase origin <傘ブランチ>
     git checkout -b <新しいブランチ名>
     ```

    `<傘ブランチ>` は実際の傘ブランチ名（計画書の進捗テーブルやブランチ命名から取得）に置換すること。

   **Herdr なし**:
   - `git worktree add -b <孫ブランチ名> ../<dir> <傘ブランチ名>` を表示
   - 以下のプロンプトを新しい会話で実行するよう案内する:
     ```
     計画書 <計画書の絶対パス> の「## 孫N用プロンプト」セクションのコードブロック内の指示に従って実装してください。
     実装が完了したら計画書末尾の指示に従ってPR作成・レビューまで自律的に進めてください。
     ```
     **プロンプト全文をコピペしない。** 計画書のパスを伝えるだけでよい

3. **計画書を更新**
   - 該当行の状況を `⬜ 待機中` → `🔄 実装中` に
   - commit + push（`git add <計画書> && git commit -m "docs: 孫N spawn" && git push`）

### 3.3 `/check`

**やること**:

1. **PR マージを検出**
   ```bash
   gh pr list --head <孫ブランチ名> --state merged --json number,title
   ```
   **これが一次手段。** `git branch -r --merged origin/<傘ブランチ>` は
   squash マージされた孫を検出できない（ブランチ tip の祖先関係しか見ないため。
   §3.3 後述のとおり孫は squash マージされることが多く、GitHub の squash merge
   でリモートブランチごと消えていれば `git branch -r` の一覧にも載らない）ので、
   一括検出の代替としては使わない

2. **マージ済み孫を検証**
   - 傘ブランチに checkout
   - `git pull --rebase`
   - プロジェクトの言語を自動検出し、該当する lint / test を実行（pr-review-loop Phase 0.5 と同じ方式）:
     - `Gemfile` があれば `bundle exec rubocop` + `bundle exec rspec`
     - `pyproject.toml` / `setup.py` / `setup.cfg` があれば `ruff check` + `python -m pytest`
     - `package.json` があれば `npx eslint .` + `npx jest`
     - `go.mod` があれば `go vet ./...` + `go test ./...`
     - `Cargo.toml` があれば `cargo clippy --all-targets` + `cargo test`
     - `.claude/pr-review.yml` の `lint_cmd` / `test_cmd` があればそれを最優先
     - 検出できなければ検証をスキップ（失敗扱いにしない）
   - `bin/doc-id verify`（存在すれば）

3. **計画書を更新**
   - 検証通過した孫を `🔄 実装中` → `✅ PR #XX マージ済` に
   - commit + push

4. **未着手の孫を列挙**

5. **クリーンアップ提案**
   - マージ済み＋検証済みの孫のうち、まだワークツリーが残っているものがあれば `ocw rm <孫ブランチ名>` を提案（**まず `--force` なしで**。§5「`ocw -H` が作るもの」と同じく進捗テーブルの「ブランチ」列の値をそのまま渡す。短縮形は複数一致で停止しうる — 後述の補足を参照）
   - 例: `ph-00 のワークツリーが残っています。ocw rm ph-00-must-keep しますか？`
   - `ocw rm` は worktree + Herdr ワークスペース + ブランチをまとめて削除する
   - 未マージの孫は削除しない（`ocw rm` が未マージを拒否するため安全）
   - **`--force` は基本的に不要。** `ocw rm`（`bin/ocw`）のマージ済み判定は
     `ocw.mergedInto`（設定） → 作成時のベース（`<worktree の git dir>/ocw-base-ref`
     に永続化される） → `HEAD` → `origin/HEAD` の順に候補を集め、各候補について
     `git merge-base --is-ancestor` に加えて squash マージ検出（`commit-tree` +
     `git cherry` によるパッチID比較）も試す。孫は傘ブランチへ squash マージされることが
     多いが、作成時のベース（＝傘ブランチ）が候補に入り squash 検出も効くため、
     **`--force` なしの `ocw rm` が普通に通る**
   - 判定できない場合の拒否は2種類あり、原因も対処も異なる:
     - **`branch is not merged into any known integration ref: <branch>`** —
       候補 ref は解決できたが、is-ancestor でも squash 検出でも「マージ済み」と
       判定できなかった場合。**傘運用で実際に遭遇するのはほぼこちら**。ありうる
       原因は squash 後に統合先で rebase・amend されて patch-id が変わった、
       マージ時の衝突解決で diff が変わった等（`bin/ocw` 自身が検出できないと
       明記している限界）。この場合だけ `--force` を検討する。飛ぶ前に、
       `ocw.githubMergeCheck`（opt-in）を有効にして `gh pr list --head <branch>
       --state merged` によるマージ判定を試す手もある。司令官は `/check` の時点で
       PR番号とマージ状態を既に握っているので、この運用ではマージチェックを
       丸ごと迂回する `--force` より素直
     - **`cannot determine an integration ref ...: set ocw.mergedInto or
       use -f`** — 候補 ref が1つも解決できなかった場合。非 bare リポジトリでは
       `HEAD` が必ず解決するため、**通常の傘運用ではまず出ない**
   - **`outcome`（計測用）は `--force` の有無ではなくマージ判定の結果で決まる。**
     マージ済みと判定できれば `success`、できなければ `failure`。squash マージ済みの
     孫を `--force` で消しても、マージ済みと判定できていれば `success` になる

   **`gh pr merge --delete-branch` はブランチを消し残すことがある。**
   孫のワークツリーがそのブランチを掴んでいるとローカル削除が失敗し、
   **その時点で処理が止まってリモートブランチも消えない**。ワークツリーを片付けたあとに、
   リモートにまだ残っていれば明示的に消すこと（実測: 4本中4本で発生した）:

   ```bash
   git ls-remote --exit-code --heads origin <孫ブランチ名> >/dev/null 2>&1 &&
     git push origin --delete <孫ブランチ名>
   ```

   既にリモートも消えている場合はこのチェックで何もしない。存在確認なしに
   `git push origin --delete` だけを叩くと、リモートに無い場合
   `remote ref does not exist` でエラー終了する。

**補足**:
- 検証失敗時は人間に報告。計画書は更新しない
- 実装中の孫はスキップ
- クリーンアップは確認を取ってから実行。無言で `ocw rm` しない
- `ocw rm` は入力が複数のワークツリーに曖昧一致すると、候補を列挙して自動選択せずに
  停止する（`bin/ocw` の設計。破壊的操作のため）。`/check` `/autopilot` の無人巡回中に
  これが起きたら、そのクリーンアップだけをスキップして人間に完全な名前の指定を仰ぐ。
  他の孫の処理は止めない
- 傘運用で `ocw.mergedInto` を明示設定する必要は無い。作成時のベース（傘ブランチ）が
  自動的にマージ判定の候補へ入るため（本節冒頭を参照）、squash 検出との組み合わせで
  素の `ocw rm` が通常どおり通る

### 3.4 `/finalize`

全孫が `✅ マージ済` なら、傘→main PR を implementer に作成させ、pr-review-loop で承認まで持っていく。

**最重要: `/finalize` は「司令官自身がいるワークスペース」の implementer/reviewer で実行する。**
孫 spawn で作られたワークスペース（w2G, w2H, w2J 等）は使わない。階層が違う。
（孫→傘 は各孫ワークスペース、傘→main は司令官ワークスペース）

**やること**:

1. **司令官自身のワークスペースを特定**
   ```bash
   herdr pane list | python3 -c "
   import sys, json
   for p in json.load(sys.stdin)['result']['panes']:
       if p.get('agent_status') == 'working':
           print(f'MY_WORKSPACE={p[\"workspace_id\"]}')
   "
   ```
   出力された `MY_WORKSPACE` が司令官のワークスペース。以後このワークスペースの implementer/reviewer を使う。

2. **ペーン構成を確認**
   ```bash
   herdr pane list --workspace $MY_WORKSPACE
   ```
   - commander（司令官自身）、implementer、reviewer の3ペーンが揃っていることを確認
   - 足りなければ `herdr pane split` で追加

3. **implementer に最終PR作成プロンプトを送信**
   - implementer が `idle` または `done`（どちらも待機状態）であることを確認
   - 以下の情報を含むプロンプトを `herdr pane run` で送信:
     - base: `<ベースブランチ>`、head: `<傘ブランチ名>`（ベースブランチは傘ブランチが追跡するリモートブランチから判定。`main`/`master` 等リポジトリごとに異なる）
     - 変更概要（孫PR番号、変更ファイル数、テスト結果）
     - reviewer ペーン ID
     - PR説明文の作法（対象リポジトリの `docs/design/` にある「プルリクエストの作法」文書を
       参照させる指示。DOC-ID は対象リポジトリごとに異なるため、文書名で指示する）

   **⚠️ プロンプトは短くする。** `herdr pane run` は文字を1文字ずつ打ち込むため、
   長文プロンプトは途中で止まり届かない。要点だけを伝え、詳細は計画書を読ませる。

   **推奨フォーマット**:
   ```
   herdr pane run <implementer-id> "最終PRを作成してください。base:<ベースブランチ> head:<傘ブランチ>。完了したらpr-review-loopを起動。reviewerは<reviewer-id>。計画書 docs/planning/DOC-XXXX_計画.md も参照。"
   ```

4. **implementer の起動を確認**

   §3.2 注意点3と同じ手順を踏む（本文とEnterは別送信。届いていないのは
   大抵Enterだけで、本文自体は届いている）:
   ```bash
   herdr pane get <implementer-id>
   ```
   `agent_status: working` になれば成功。**`working` にならない（`idle` または
   `done` のまま）なら** `herdr pane send-keys <implementer-id> Enter` を撃って
   再確認する。**同じ本文を `herdr pane run` で再送しない**（プロンプト欄に2重に積まれる）。

5. **以降は自律運転**
   - implementer が PR を作成し、`/pr-review-loop` を起動
   - reviewer がレビューし、指摘があれば implementer が修正
   - 承認されたら implementer が人間に「マージしてください」と依頼する
   - 司令官は関与しない（PRマージは人間の仕事）

**補足**:
- 孫ブランチと異なり、新たな worktree は不要（傘ブランチそのものが作業ディレクトリ）
- PR の向き先は **傘ブランチのベースブランチ**（孫は傘に向けるが、最終PRはベースブランチに向ける）。ベースブランチは `git rev-parse --abbrev-ref @{upstream}` から `origin/` を除いたもの、または計画書に明記されたものを使用する。リポジトリによって `main` や `master` 等異なるため、ハードコードしない
- 司令官は実装もレビューもしない。implementer と reviewer に任せる

### 3.5 `/autopilot`

**前提**: 計画書が作成済みで、全孫のプロンプトが記述済みであること。

計画書作成後の全工程（spawn → check → merge → next spawn → ... → finalize）を
CronCreate による自動監視で進行させ、main マージ直前（finalize PR作成完了）まで自動化する。
main へのマージは人間が手動で行う。

**やること**:

1. **計画書を読む**
   - 孫ブランチ進捗テーブルから全孫のブランチ名・内容・状況を取得
   - 傘ブランチ名を特定（現在のブランチまたは計画書から）

2. **未着手の孫があれば最初の1件を spawn**
   - `/spawn <N>` と同じ手順で `ocw -H` + プロンプト送信
   - 計画書を「🔄 実装中」に更新して commit + push

3. **CronCreate で自動進行ジョブを登録**（約10分おき、`:00` `:30` 回避で `3,13,23,33,43,53`）

   以下のプロンプトを cron に設定する。`<計画書の絶対パス>` と `<傘ブランチ名>` と
   `<司令官のworkspace_id>` は実際の値に置換すること：

   ```
   # 傘ブランチ自動進行 (autopilot)

   計画書: <計画書の絶対パス>
   傘ブランチ: <傘ブランチ名>

   ## 手順

   1. 計画書を読み、進捗テーブルから「現在アクティブな孫」を特定する
      （🔄 実装中 が現在の孫、✅ マージ済 は完了）
   2. アクティブな孫の implementer 状態を確認:
      herdr pane list | python3で全workspaceのpaneを確認
   3. PRが出ているか確認:
      gh pr list --head <孫ブランチ名> --json number,title,state
   4. PRがあれば review 状況を確認:
      gh pr view <PR番号> --json reviews,commits
      ※ 判定の読み方は下記「レビュー判定の読み方」に従うこと。
        event 種別（APPROVED 等）で判断してはいけない
   5. 判定が「承認」かつ 対象HEAD が最新コミットと前方一致するならマージ:
      gh pr merge <PR番号> --squash --delete-branch
   6. マージ後、傘ブランチで検証:
      git pull --rebase origin <傘ブランチ>
      §3.3 手順2 と同じ方式で検証（.claude/pr-review.yml の lint_cmd/test_cmd を
      最優先、無ければ言語自動検出。Ruby 固定ではない）
   7. 検証通過後、計画書を「✅ PR #XX マージ済」に更新してcommit+push
   8. 次の未着手の孫があれば spawn:
      ocw -H --no-commander <次の孫ブランチ名> <傘ブランチ>
      出力の workspace: 行のIDに herdr workspace rename でラベルを日本語化する
        （書式・手順は §5「ワークスペースラベル」参照。プロンプト送信より前に行う。
        失敗しても警告のみで続行する）
      implementerにプロンプト送信（末尾に「reviewerはdone状態で完了し完了通知は
        来ないので、待機して停止せず gh pr view をポーリングしてレビューの有無を
        確認してください」を必ず含める。§3.2 注意点3参照）
      送信後 herdr pane get で agent_status を確認し、idle のままなら
        herdr pane send-keys <implementer-id> Enter で確定させる
      計画書を「🔄 実装中」に更新してcommit+push
   9. 全孫マージ済みなら finalize:
      司令官自身のworkspaceを特定:
        herdr pane list | python3 -c "import sys,json; [print(p['workspace_id']) for p in json.load(sys.stdin)['result']['panes'] if p.get('agent_status')=='working']"
      そのworkspaceのimplementerに送信:
        herdr pane run <impl-pane-id> "最終PRを作成。base:main head:<傘ブランチ>。pr-review-loop起動。reviewerは<同workspaceのreviewer>。mainマージは人間手動。計画書 <計画書の絶対パス> 参照。"
      送信後 herdr pane get で agent_status を確認し、working にならない
        （idle または done のまま）なら herdr pane send-keys <impl-pane-id> Enter
        で確定させる（このimplementerは以前に作業を終えている可能性があり、
        フォーカスされていなければ done のまま張り付く）
      CronDelete でこのcronを停止
      PushNotification でユーザーに「全工程完了。mainへのPR作成済み。手動マージしてください」と通知

   ## 注意
   - 実装AIが working なら何もせず次のcron
   - 判定が「承認」でないPRはマージしない
   - PRがない/実装中なら待機
   - 検証失敗時は計画書を更新せずユーザーに通知
   - **進捗テーブルは計画書が正典。** この cron 本文に焼き込んだ「現在の状況」は
     孫が進むたびに嘘になる。食い違ったら計画書を信じること
   - 人間が GitHub UI から手動でPRをマージすることがある。`gh pr view` の state を
     必ず確認し、MERGED なら差し戻しではなく追随PRで対応する
   - mainへのマージは絶対にしない
   - implementerへのプロンプトは短く（計画書パスとセクション名だけ）
   ```

4. **ユーザーに報告**
   - 最初の孫の spawn 完了を報告
   - cron ジョブID を表示
   - 「以降は10分おきに自動進行。mainマージ直前で停止して通知します」と伝える

**補足**:
- このモードは計画書が完成した後の「実装フェーズ」全体を自動化するもの
- 計画書の作成・レビューは人間が行う前提
- 予期せぬエラー（lint/test失敗など）はユーザーに通知して停止
- cron ジョブはセッション限り（7日で自動期限切れ）

## 4. 状態機械

```
⬜ pending ──→ 🔄 active ──→ ✅ merged ──→ 🏁 verified
   │              │               │
   └ /spawn ──────┘               │
                  └── 実装AI ──────┘
                  （実装＋/pr-review-loop）
                                  │
                        └ /check ─┘
                        （検出＋検証＋計画書更新）
```

## 5. Herdr 連携

### 検出

```bash
test "${HERDR_ENV:-}" = 1
```

### ワークスペース階層（最重要）

```
傘ブランチのワークスペース（司令官が常駐。3ペイン）
  ├─ commander ← 司令官自身
  ├─ implementer ← /finalize で使う
  └─ reviewer ← /finalize で使う

孫ワークスペース（ocw -H --no-commander で孫ごとに作成される別workspace。2ペイン）
  ├─ w2H: 孫1のworkspace（implementer / reviewer）
  └─ w2J: 孫2のworkspace（implementer / reviewer）
```

- **司令官は常に傘ブランチのworkspaceにいる。** 孫workspaceではない。
- **傘（司令官）ワークスペースは人間が素の `ocw -H`（3ペイン、`--no-commander` を付けない）
  で作る。** 司令官は起動後、自分の workspace を見つけて（後述）日本語ラベルへ改名する
  （§5「ワークスペースラベル」参照）
- **`/spawn`**: `ocw -H --no-commander` が孫workspaceを**新規作成**し、そこの
  implementerに実装させる。commander ペインは作らない（誰も使わないため）
- **`/check`**: 孫workspaceのimplementerを監視
- **`/finalize`**: **司令官自身のworkspace**のimplementer/reviewerで実行。孫workspaceは使わない

### 自分のworkspaceの見つけ方

```bash
herdr pane list | python3 -c "
import sys, json
for p in json.load(sys.stdin)['result']['panes']:
    if p.get('agent_status') == 'working':
        print(p['workspace_id'])
"
```

司令官は常に1つだけ `working` なpane。そのworkspace_idが司令官のworkspace。

### `ocw -H` が作るもの

孫の spawn では `--no-commander` を付ける。傘（司令官）ワークスペースは付けない
既定のままにする（3ペインが要る理由は上の「ワークスペース階層」参照）。

```bash
ocw -H --no-commander <孫ブランチ名> <傘ブランチ名>
```

**`<孫ブランチ名>` には、進捗テーブルの「ブランチ」列（§2.1）の値をそのまま渡すこと。**
`ocw` はブランチ名に接頭辞を一切付けない（正規化した入力そのものがブランチ名になる）ので、
テーブルの値がそのまま実ブランチ名である。これは**新規に作る**孫ブランチの命名方針であり、
既存の `ai/*` ブランチを遡って改名する話ではない（既存ブランチはそのままでよい）。

これだけで以下が**全部**できる:

```
git worktree 作成（<孫ブランチ名> がそのままブランチ名になる。`/` はディレクトリの
  ネストとして温存される）
  → herdr workspace 作成（ラベルは既定で `<repo_name> :: <slug>`。区切りは `::`。
    このあと「ワークスペースラベル」節に従って日本語ラベルへ改名する）
  → 2ペーン構成（commander は作らない）:
     ┌──────────────┬──────────┐
     │ implementer  │ reviewer │
     │ claude       │ claude   │
     │ 実装+PR      │ レビュー │
     └──────────────┴──────────┘
  → 全ペーンでエージェント起動済み
  → 標準出力に pane ID が出力される（`commander:` 行は出ない）
```

出力例（`--no-commander`。`commander:` 行が無いことに注意）:
```
workspace:   w1
implementer: w1:p2
reviewer:    w1:p3
```

**既定（`--no-commander` を付けない）の `ocw -H` は3ペイン。** 傘（司令官）ワークスペースを
人間が立ち上げるときはこちらを使う。

```
     ┌────────────┬─────────────┬────────────┐
     │ commander  │ implementer │ reviewer   │
     │ claude     │ claude      │ claude     │
     │ 司令官自身 │ finalize用  │ finalize用 │
     └────────────┴─────────────┴────────────┘
```

出力例（既定・3ペイン）:
```
workspace:   w0
commander:   w0:p1
implementer: w0:p2
reviewer:    w0:p3
```

各ペーンの既定の起動コマンドは `claude`（`bin/ocw` の `OCW_COMMANDER_COMMAND` /
`OCW_IMPLEMENTER_COMMAND` / `OCW_REVIEWER_COMMAND` で個別に上書き可能。§3.2 注意点4。
`--no-commander` の2ペインモードでは `OCW_COMMANDER_COMMAND` は使われない）。

### ワークスペースラベル

Herdr ワークスペースの既定ラベルは `<repo_name> :: <slug>`（区切りは ` :: `。
`bin/ocw` が生成する）で、サイドバーからは内容が判別できない。`ocw -H` の直後に
`herdr workspace rename <workspace_id> <label>` を叩いて日本語ラベルへ改名する。

**書式**:

```
<repo_name> :: <日本語の説明>
```

- 傘（司令官スペース）: `<repo_name> :: <傘の日本語要約>`
- 孫（実装ワークスペース）: `<repo_name> :: <傘の日本語要約> 孫N <孫の日本語要約>`

長さの目安は傘の要約が全角12文字以内、孫の要約が全角16文字以内（サイドバーの幅で
末尾が切れないように）。

**説明文の作り方（優先順）**:

1. 計画書に `## ワークスペースラベル` 節があれば、そこに書かれた文字列をそのまま使う（§2.5）
2. 節が無ければ機械的に導出する: 傘の要約＝計画書の H1 見出しから「計画書:」を
   除いて短縮したもの、孫の要約＝進捗テーブルの「内容」列を短縮したもの

**孫の rename**: `ocw -H --no-commander ...` の出力の `workspace:` 行の ID に対して、
**プロンプト送信より前**に行う（§3.2「/spawn」）。

**傘（司令官スペース）の rename**: 司令官が自分のワークスペースを `herdr workspace list`
から特定し（「自分のworkspaceの見つけ方」参照）、現在ラベルが**既定形のときだけ**
rename する。既定形の判定は「` :: ` の右側に非 ASCII 文字が1文字も含まれないこと」。
人間が既にラベルを日本語で手付けしていれば上書きしない。

**rename が失敗しても警告のみで続行する。** ラベルは表示上の都合であり、spawn や
finalize のフローを止める理由にならない。

### `/spawn` の Herdr ありフロー

1. `ocw -H --no-commander <孫ブランチ> <傘ブランチ>` を実行
2. 出力から `workspace:` 行の ID を拾い、`herdr workspace rename` で日本語ラベルへ
   改名する（§5「ワークスペースラベル」参照。失敗しても警告のみで続行）
3. 出力から `implementer:` 行の pane ID を拾う
4. `herdr pane run <implementer-id> "<prompt>"` でプロンプト送信
5. `herdr pane get <implementer-id>` で `agent_status` を確認し、`idle` のままなら
   `herdr pane send-keys <implementer-id> Enter` を撃って再確認する（§3.2 注意点3）
6. 以上。reviewer は `/pr-review-loop` が勝手に使うので司令官は触らない

### 状態確認（`/check` から使う）

```bash
# implementer の状態を見る
herdr pane get <implementer-id>  # agent_status: idle/working/blocked/done

# 完了を待つ（--status は1つしか取れないため、短く区切ってdone/idle両方を見る。
# 端末クライアントが繋がっていないヘッドレス実行では globally active tab のペインは
# 完了時に直接 idle になりうるため、done 単独で120000msフル待機すると空転する）
for _ in $(seq 1 6); do
  herdr wait agent-status <implementer-id> --status done --timeout 20000 && break
  STATUS=$(herdr pane get <implementer-id> | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['pane'].get('agent_status',''))")
  case "$STATUS" in idle|blocked) break ;; esac
done

# PR 番号を検出（出力から抽出）
herdr pane read <implementer-id> --source recent-unwrapped --lines 40
```

### レビュー待ちデッドロック（頻出。司令官が拾わないと止まったまま）

**まず予防する。** spawn 時のプロンプト末尾に
「reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view を
ポーリングしてレビューの有無を確認してください」を入れるだけで発生しなくなる
（§3.2 の推奨フォーマット参照。実測: 入れなかった孫で計4回発生、入れた孫で0回）。
以下は**予防し損ねたときの検知と復旧**である。

**無人監視しているペインは、完了しても `done` のままで `idle` にはならない。**
herdr 自身の公式ドキュメント（`herdr` skill）によれば、`idle` と `done` は
別の状態への遷移ではなく、**同じ「完了」状態を「見られたか」で呼び分けているだけ**
である: ペインのタブ／ワークスペースが背面（誰にもフォーカスされていない）の
まま完了すると `done` になり、**そのタブを実際にフォーカスするまで自動では
`idle` に変わらない**。司令官が孫の implementer 越しに reviewer の完了を
無人監視する場面では、そのペインを誰も見に行かないため `done` のまま張り付く
（herdr の不具合ではなく仕様どおりの挙動）。

実装AIが reviewer の完了を待つとき `herdr wait agent-status <reviewer> --status idle`
を使うことがあり、この待機は**（そのペインをフォーカスしない限り）成立せずタイムアウトまで
空回りする**。孫1で1回発生した（約10分ロス。§3.2 実測表と同じ事例）。

**注記**: `pr-review-loop` スキル（`skills/pr-review-loop/SKILL.md` Phase 3a）も
同じ仕組みに基づき、`idle` ではなく `done` を待つ形に修正済み（本PRで対応）。

**待ち方は1種類ではない。** 孫3では `herdr wait` を使わず
「バックグラウンドで再度待機中です。通知を待ちます」と称して**バックグラウンドシェルを
走らせたまま止まる**形が3回出た。このとき pane の `agent_status` は
`working` ではなく **`done`** になる。つまり
**`agent_status` が `working` でも `done` でもデッドロックはありうる**ので、
状態だけで判定しようとしないこと。共通しているのは
「**PR の最新HEADに対するレビューが既に投稿されているのに、実装側が次の行動に移らない**」
という一点だけである。

`agent_status` だけでは検知できない（上記のとおり `working` にも `done` にもなりうる）。
**次の3条件のANDで疑う**:

- 判定つきレビューが投稿済み
- かつ その対象HEAD が PR の最新コミットと一致（＝実装側が未対応）
- かつ 前回の巡回から PR のコミット数が増えていない

**該当しても即断しない。** `gh pr view` は数十秒キャッシュが遅れることがあり、
実際には push 済みのことがある（誤検知の実績あり）。必ずペーンを目視する:

```bash
herdr pane read <implementer-id> --source recent-unwrapped --lines 20
```

`herdr wait agent-status` が走っている、または「通知を待ちます」と言ったまま
バックグラウンドシェルが残っていることを確認してから、短く送って復帰させる:

```bash
herdr pane run <implementer-id> "reviewerは完了済みで最新レビューが投稿されています。待機をやめて gh pr view <PR番号> --json reviews で最新レビューを読み、指摘に対応してpushし、再レビューを依頼してください。"
herdr pane send-keys <implementer-id> Enter
```

**`send-keys Enter` を忘れない**（§3.2 の注意点3）。復帰指示も他の送信と同じく
Enter が送られないため、これを撃たないと「復帰させたつもりで止まったまま」になる。

**同じ孫で2回目以降の復帰になったら、対症療法ではなく待ち方そのものを変えさせる。**
復帰指示の末尾に「以後も push 後に完了通知を待つ形で停止しないでください。
レビューの有無は必ず `gh pr view` をポーリングして確認してください」を足す。
1つの孫で3回同じ穴に落ちた実績があり、3回目にこれを足して止まった。

### Herdr なし

全操作を標準出力に表示し、人間に手動実行を依頼する。

## 6. 分業

### 司令官がやること
- 計画書の読み取りと更新
- 孫の spawn（`ocw -H` + `herdr pane run`）
- PR マージの検出と検証
- 計画書の commit / push

### 司令官がやらないこと
- 実装コードのレビュー（pr-review-loop の仕事）
- PR マージ（人間の仕事）
- 孫ブランチ上での作業（司令官は傘ブランチに常駐）
- Herdr ワークスペースの手動構築（`ocw -H` の仕事）

### 実装AIに期待すること
- プロンプトを受け取ったら実装を開始
- PR 作成後 `/pr-review-loop` を起動
- 承認されたら人間にマージを依頼

## 7. エラー処理

| 状況 | 対応 |
|------|------|
| 計画書が見つからない | `docs/planning/DOC-*_計画.md` を探索 |
| プロンプトセクション不在 | 人間に依頼 |
| lint/test 失敗 | 人間に報告。計画書は更新しない |
| PR 番号不明 | `gh pr list --head <branch> --state merged` で再検索 |
| 依存未解決 | ブロックしている孫の完了を待つよう案内 |
| 人間が先に手動マージしていた | 差し戻しではなく**追随PR**で対応（下記） |
| 実装AIが設計判断を求めてきた（`blocked`） | 提示された選択肢を鵜呑みにせず**技術的に検算**してから答える。必要なら人間に判断を仰ぐ |

### 人間が手動でPRをマージしていた場合

司令官が差し戻しを判断している間に、人間が GitHub UI からマージしていることがある。
**マージ済みPRは再オープンできない。** 修正は**追随PR**で行う。

**追随ブランチは必ず `origin/<傘ブランチ>` から切ること。**
孫は squash マージされるため履歴を共有しない。元の孫ブランチの上でコミットして
PRを出すと、**マージ済みの変更が全部もう一度差分に出てレビュー不能**になる。

```bash
git stash                      # 作業中の変更を退避
git fetch origin
git checkout -b <追随孫名> origin/<傘ブランチ>
git stash pop                  # 退避した変更を適用
```

追随孫は進捗テーブルに新しい行として追加し、元の孫は `✅ マージ済` のまま残す。

### 実装AIが選択肢を出してきたとき

実装AIは行き詰まると3択程度を提示してくるが、**正解がその中に無いことがある。**
実測して選択肢の前提を検算すること。1つの傘で、提示された3択がいずれも
不適切で、4案目（実測で90倍速いことを確認した方法）が正解だった事例がある。

司令官が方針を答えるときは、**「何を」だけでなく「どう実装するか」まで指定する。**
「base を再ロードする」とだけ答えたところ、素直にディスクからの再生成が選ばれ、
1回12.39秒＋torch.compile 破棄という二次被害が出た（正解は in-place 復元で0.138秒）。
