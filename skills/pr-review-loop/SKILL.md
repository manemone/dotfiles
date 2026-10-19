---
name: pr-review-loop
description: "PRレビューサイクルを自動化。Herdrワークスペースのreviewerペインと連携してレビュー→修正→返信→再レビューを承認まで繰り返す。AI 不問（Claude Code / Codex / OpenCode）。自動発動はしない。/pr-review-loop で明示的に起動。"
---

# PRレビューループ

Herdrワークスペース内の `reviewer` ペインと連携してPRレビューサイクルを自動化する。

**AI 不問。** 司令官（このスキルを読んでいる側）もレビュワーも、特定の AI コーディング
エージェントを前提としない。Herdr が対応するエージェント（`herdr integration status` で
一覧できる。Claude Code / Codex / OpenCode など）であれば、`agent_status` による状態
取得と `umbrella-orchestrator` §5 の送信手順（`herdr agent prompt` を含む）による依頼送信という本スキルの2つの接点はどれも同じように使える。
司令官とレビュワーが別のエージェントであってもよい。

本スキルには工程計測用の `ocw-meter` 呼び出しが含まれる。すべて fail-open であり、
`ocw-meter` が存在しない環境でも本スキルは完全に動作する。
計測はレビュー判定に一切影響しない。

相手が他人の PR をレビュワーとしてレビューするなら `pr-group-review`、自分の PR 群の
レビューを他人に頼む準備は `pr-group-request` を使う（本スキルは他人から返ってきた指摘への対応に使う）。

## 前提条件

Herdr内で実行されていること。確認:

```bash
test "${HERDR_ENV:-}" = 1
```

失敗したら「Herdr内ではありません」と報告して停止。

レビュワーペインで動くエージェントについては、Herdr の agent 連携がインストール済みで
あること。未インストールだと `agent_status` が常に取れず、Phase 3 の完了待ちが機能しない:

```bash
herdr integration status
```

## 呼び出し

```
/pr-review-loop [PR_NUMBER_OR_URL]
```

- PR番号またはURLが与えられたらそれを使う。
- 省略時は現在のgitブランチからPRを特定:

```bash
gh pr view --json number,url
```

## Phase 0: reviewerペインの特定

推測するな。neighborsや位置レイアウトを使うな。

```bash
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
```

`label` が `"reviewer"` と完全一致するペインを1つだけ探す。その `pane_id` を使う。

- 0件 → 停止。「'reviewer' ラベルのペインがありません。`herdr pane split --current --direction right --no-focus` で分割、`herdr pane rename <id> reviewer` でリネーム、レビュー役に使う AI エージェント（`claude` / `codex` / `opencode` など）を起動してください」と伝える。
- 2件以上 → 停止。「'reviewer' ラベルのペインが複数あります。1つだけ残してリネームしてください」と伝える。

レビュワーペインIDを `$REVIEWER_PANE` に保存（例: `w4:p3`）。

### レビュワーのエージェント種別を記録する

**推測するな。ペイン自身が報告している値を読む。**

```bash
herdr pane get "$REVIEWER_PANE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result']['pane'].get('agent') or '')"
```

得られた値（`claude` / `codex` / `opencode` など）を `$REVIEWER_AGENT` として保存する。
Phase 2 Step 2 で、終了していたレビュワーを再起動するときの起動コマンドに使う。

空だった場合（そのペインでまだエージェントが起動していない、または agent 連携が未導入）は
`$REVIEWER_AGENT` を空のままにし、Phase 2 Step 2 の「起動コマンドの決定」に従う。

## Phase 0.5: プロジェクト設定の読み取り

プロジェクト固有の設定を収集する。以下の優先順位で解決:

1. `.claude/pr-review.yml`（あれば最優先）
2. リポジトリ構成からの自動検出
3. スキル内蔵のデフォルト値

**`.claude/` というディレクトリ名だが、これは Claude Code の設定ではない。** このファイルを
読むのは本スキル自身であり、どの AI エージェントから実行しても同じように読める。既存の
リポジトリに配置済みのものを尊重するため、パスはこのまま維持している。

### Step 1: 設定ファイルの確認

```bash
cat .claude/pr-review.yml 2>/dev/null || echo "NOT_FOUND"
```

### Step 2: 設定の解決

**設定ファイルがある場合**、以下のキーを読み取る:

```yaml
# .claude/pr-review.yml（すべて省略可。省略時は自動検出またはデフォルト）
lint_cmd: "bundle exec rubocop"    # null でlintスキップ
test_cmd: "bundle exec rspec"      # null でテストスキップ
convention_docs:                   # レビュー規約が書かれたdocのパス（省略可）
  - "docs/CONTRIBUTING.md"
markers:
  approved: "🤖✅ 承認"
  changes_requested: "🤖🔍 レビュー指摘"
  reply: "🤖💬 対応報告"
reviewer_cmd: "claude"            # レビュワーペインでエージェントを起動し直すコマンド
```

**設定ファイルがない場合**、リポジトリ構成から自動検出:

```bash
if [ -f Gemfile ]; then echo "ruby"
elif [ -f pyproject.toml ] || [ -f setup.py ] || [ -f setup.cfg ]; then echo "python"
elif [ -f package.json ]; then echo "javascript"
elif [ -f go.mod ]; then echo "go"
elif [ -f Cargo.toml ]; then echo "rust"
else echo "unknown"
fi
```

検出結果に応じたデフォルトコマンド:

| 言語 | LINT_CMD | TEST_CMD |
|------|----------|----------|
| ruby | `bundle exec rubocop` | `bundle exec rspec` |
| python | `ruff check` | `python -m pytest` |
| javascript | `npx eslint .` | `npx jest` |
| go | `go vet ./...` | `go test ./...` |
| rust | `cargo clippy --all-targets` | `cargo test` |
| unknown | （スキップ） | （スキップ） |

**マーカー**は未設定なら以下のデフォルト値:

- 承認: `🤖✅ 承認`
- 変更要求: `🤖🔍 レビュー指摘`
- 返信: `🤖💬 対応報告`

**convention_docs** が未設定の場合、このスキル自体のレビュー規約を唯一の情報源とする。

**reviewer_cmd** が未設定なら、Phase 0 で読み取った `$REVIEWER_AGENT` を KIND として
`herdr agent start` で起動する（Herdr が報告する agent 名は起動の KIND と一致するのが通例）。
`$REVIEWER_AGENT` も空なら、Phase 2 Step 2 の「起動コマンドの決定」に従う。

以降のフェーズでは、解決した設定値を以下の変数で参照する:

- `LINT_CMD` / `TEST_CMD` — コマンド（空または `null` ならスキップ）
- `APPROVED_MARKER` / `CHANGES_REQUESTED_MARKER` / `REPLY_MARKER` — マーカー文字列
- `CONVENTION_DOCS` — 規約docのパスリスト（空ならスキル内蔵規約のみ）
- `REVIEWER_CMD` — レビュワーを再起動するコマンド（空なら Phase 2 Step 2 で決める）

## Phase 1: コンテキスト収集

サイクル開始時に1回だけ実行:

**工程計測についての注記（このPhase以降で共通）**: `$ROUND` はシェル変数ではない。本スキルの各コードブロックは独立したBashツール呼び出しとして実行され、シェル変数は呼び出しをまたいで保持されない。`$ROUND` は「エージェントが追跡している現在のレビューサイクル数（1始まり。Phase 7の報告項目にある『レビューサイクル数』と同じ値、安全制約の『6サイクル』のカウントと同じ値）」を指す記法であり、`--round` を実行する際は、この時点のサイクル数をリテラルな整数値として埋めること。`$PR` / `$HEAD_SHA` / `$FINDINGS_COUNT` / `$URL` / `$OCW_RUN_ID` / `$REVIEW_REQUEST`（Phase 2 Step 1 で決めるレビュー指示ファイルの絶対パス）/ `$REVIEWER_PANE` / `$REVIEWER_AGENT` / `$REVIEWER_CMD` も同様に、直前に取得・保持した実際の値をその場でリテラルに埋め込む記法であり、新しいシェル変数を宣言する意味ではない。**特に `$REVIEW_REQUEST` は `herdr agent prompt` などでレビュワーへ渡す文字列の中に入る。** レビュワーのペインは別プロセスでこちらのシェル変数を参照できないため、必ずリテラルな絶対パスとして埋めること。

工程計測（サイクル1周目の開始）:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.start --phase pr_create --source pr-review-loop --round "$ROUND" || true
```

1. PR番号、タイトル、URL、base/head ref、stateを取得:

```bash
gh pr view $PR --json number,title,url,baseRefName,headRefName,state
```

取得した `url` は `$URL` として以降で参照する。

PR番号が確定したら、`run_id` を後付けbindする（`OCW_RUN_ID` が環境にある場合のみ。無ければ発行しない。`bind-pr` は `--source` を受け付けないため、同じ情報を汎用の `event pr.bind` で発行し `--source` を明示する）:

```bash
[ -n "${OCW_RUN_ID:-}" ] && command -v ocw-meter >/dev/null && ocw-meter event pr.bind --run-id "$OCW_RUN_ID" --pr-number "$PR" --pr-url "$URL" --source pr-review-loop --idempotency-key "bind:$OCW_RUN_ID:$PR" || true
command -v ocw-meter >/dev/null && ocw-meter event phase.end --phase pr_create --source pr-review-loop --round "$ROUND" || true
```

2. 現在のHEAD SHAを取得:

```bash
git rev-parse HEAD
```

この値は `$HEAD_SHA` として、以降このサイクルでレビュー対象とするHEADの参照に使う。

3. 規約docを読む（`CONVENTION_DOCS` が設定されている場合のみ）:

```bash
ls docs/ 2>/dev/null || echo "NO_DOCS_DIR"
```

`CONVENTION_DOCS` にパスが列挙されていればそれらを読む。設定がなく `docs/` が存在する場合は、PR・コードレビュー・レビューコメント・再レビュー・承認・テスト・lintに言及しているdocを探して読む。`docs/` が存在しないか該当docがなければ、このスキルの内蔵規約だけを使う。

**重要**: プロジェクト固有のdocがあればその規約を優先するが、docがないからといって停止しない。スキル内蔵の規約で進行する。

## finding の判定基準（general finding qualification gate）

実装者（Phase 1.5 の自己レビュー）とレビュワー（Phase 2 のレビュー依頼）が**同じ基準**で使う。

レビューで気づいたことは、まず**「そもそもこれは finding か」**を判定する。finding と認定した
ものの扱いは従来どおり厳格（全件 blocking、全件修正要求）である。変わるのは**入口だけ**であり、
finding 認定後の厳格さではない。

### blocking finding にしてよいもの

次のいずれかを**具体的に説明できる**もの。

- correctness の不具合
- user-visible behavior / CLI contract / API contract の誤り
- safety / security / permission / data integrity / 破壊的操作の危険
- 後方互換性の破壊
- 実際に誤操作を誘発するドキュメント不整合
- 将来の現実的な不具合につながる maintainability problem
- scope violation / 責務の誤配置（無関係変更の混入を含む）
- テスト不足のうち、risk-based testing の入口判定（テスト不足の判定基準）を通過したもの

maintainability を理由にする場合は、**「この状態だと、どんな将来変更で、どう壊れるのか」**を
具体的に説明できること。説明できるなら blocking finding でよい。

例（いずれも blocking finding にしてよい）:

- カテゴリ定数を3箇所目に複製しており、カテゴリ追加時にこの機能だけ silent miss する
- 同じ表示フォーマットが2箇所に複製され、片方だけ変更される現実的な divergence がある

### blocking finding にしないもの（pure nit）

具体的な correctness / safety / 意味のある maintainability risk を説明できない、純粋な nit。

- コメントの折り返し幅が不揃い
- コメントの1行だけ短い
- 動作・理解・保守性に実害のない表面的な表現差
- formatter / linter も問題にしない単なる好み
- どちらでも意味が変わらない軽微な命名の好み
- 「こっちの方がきれい」「統一感のため」「自分ならこう書く」

これらは finding に昇格させない。**nit だけを理由に変更要求にしない**（孫 PR のレビューにも、
傘→既定ブランチの最終レビューにも当てはまる）。気づいたものは、書くなら承認コメントの末尾に
「任意」と明記して添えるだけにし、修正要求として投稿しない（修正要求ではないので、
「1レビュー1判定」の未解決指摘には数えない）。実装者は直さなくてよい。
ユーザーが明示的に「nit も全部出して」と依頼した場合だけ別扱いとしてよい。

### 文書だけの PR のレビュー範囲

傘ブランチへ向く孫 PR のうち、変更が文書・コメントだけで、実行されるコードや設定を含まないもの
（判断がつかなければ「文書だけ」としない）は、レビューを省かず、**見る範囲を次の2つに絞る**。

- 計画書・他の孫・既存の契約との食い違い（計画からの逸脱・孫どうしのズレ）
- 文書を信じた人が誤った操作をしうる不整合（上の「実際に誤操作を誘発するドキュメント不整合」）

テスト・エッジケース・並行実行など、文書に当てはまらない次元は確認しなくてよい。絞るのは
見る範囲であり、finding と認定したものの扱い（全件 blocking）は変わらない。土台・実装コード・
小さい PR、傘→既定ブランチの最終レビュー、傘の外の PR のレビューは絞らない。根拠は ADR DOC-2610140228。

### 「伏せる」と「finding ではない」は別

- substantive な問題を、ラウンドが増えるのを嫌って伏せることは**禁止**。
- この gate を通らない nit は、伏せているのではなく、そもそも finding ではない。
- actual bug / safety / data loss / security / 後方互換性の問題は、**後続ラウンドで気づいた
  としても必ず出す。**

**「nit を blocking にしない」を「小さいバグなら無視してよい」に変形してはいけない。**
バグは1行でも finding である。

### 後続ラウンド（ラウンド2以降）の新規 finding 閾値

再レビューでは、まず前回レビュー対象SHAと現HEADの差分を確認する。新規 finding は次の
どちらかに限る。

1. 今回の修正差分によって**新しく導入された** substantive problem
2. 前回見落としたが、この gate を**明確に通る** substantive problem

コメントの折り返し・空白・cosmetic formatting・表面的な言い回し・実害を説明できない軽微な
style を、後続ラウンドで新規 blocking finding として出してはいけない。**pure nit 1件のために
レビューラウンドを1回増やすことは、レビュー品質ではなく浪費である。**

ただし「前回見落としたからもう言えない」というルールにはしない。actual defect は後からでも出す。

### finding として書くときの作法（全 finding 共通）

blocking finding には、**failure scenario**（どの入力・状態で → 何が起き → 利用者
（ユーザー・呼び出し側・将来の変更者）から何がどう見えるか、の具体的な連鎖）を書く。
**failure scenario を書けない指摘は、そもそも finding ではない。**

maintainability を理由にする finding では、「どんな将来変更で → どう壊れ → 何が
見えるか」という連鎖になる（「blocking finding にしてよいもの」で要求している
maintainability の説明を、記載様式として具体化したもの）。

例:

- 空文字列を設定 → 「値が空でなければ」というチェックは空文字列を真として通過 →
  デフォルト値の解決処理に空文字列がそのまま渡る → 存在チェックはカレント
  ディレクトリを指すため通過してしまう → 呼び出し先が誤った値を受け取り、
  意味の分からないエラーで失敗する → 利用者は根本原因を辿れない
- 将来のリファクタで、正規表現マッチとその結果を参照する処理の間に別の処理が
  挟まる → 参照している結果が別のマッチにすり替わる → 対象範囲の境界がずれる →
  誤った範囲が処理対象になる → 出力全体が無効な結果になる

テスト不足の finding における「逃す regression（何が、どういう変更で壊れるか）」
（「テスト不足の finding として書くときの作法」参照）は、この failure scenario を
テスト不足の場合に具体化したものであり、両者は矛盾しない。

## テストの判断基準（risk-based testing）

実装者（Phase 1.5 の自己レビュー）とレビュワー（Phase 2 のレビュー依頼）が**同じ基準**で使う。

テストは「コード・分岐・受け入れ条件」の数ではなく、**外部から意味のある behavior と
現実的な regression risk** を守るために追加する。

### テスト不足を finding にする前に確認すること

以下を**すべて**説明できないものは finding ではない。

1. そのテストが無い場合に逃す、具体的かつ現実的な regression を説明できるか
2. 既存テストではその regression をすでに検出できないか
3. 下位レイヤーの authoritative なテストで保証済みの性質を、上位 caller で再検証していないか
4. implementation detail ではなく、意味のある behavior を検証しているか
5. 新しい example を増やす代わりに、既存 example への assertion 追加や scenario 統合で足りないか

**「テストがあったほうが安心」は finding の理由にならない。**

### 理由にしてはいけない要求

以下を根拠に新しいテストを要求しない。

- 新しい method なので専用 spec が必要
- 新しい branch なので各 branch にテストが必要
- 受け入れ条件が4項目なので4 example 必要
- edge case として思いついたので全部テストする
- private helper ごとにテストする
- 同じ性質を複数の caller から再確認する
- 「念のため」

**受け入れ条件と test example は1対1対応ではない。** 複数の受け入れ条件を1つの scenario で
検証してよい。

### リスク分類

| リスク | 対象 | 方針 |
|---|---|---|
| 高 | 実際に発生したバグの修正 / 削除・上書き・移動・archive・restore / resume・cache・state recovery / hardlink・inode・filesystem 整合性 / データ損失につながる処理 / concurrency / 認証・権限・security / 複雑なアルゴリズム / 外部公開API・CLI・永続化フォーマットの契約 / 後方互換性の重要な境界 | 厚くテストする。regression test を積極的に要求してよい |
| 中 | config 解釈 / validation / 複数component間のintegration | authoritative な unit test を中心にする。必要なら代表的な integration test を1本程度 |
| 低 | 単純な delegation / glue code / private helper / trivial formatter / 単なる値の受け渡し / 下位層で保証された性質を使っているだけの caller | 専用テストをデフォルトでは要求しない |

### edge case の扱い

思いついた edge case をすべてテストするのではなく、**発生可能性 × 影響度 × 既存coverage**
で追加要否を判断する。コード上で安全に処理されており、低リスクで、既存テストで足りるなら
専用 spec は不要。

**「壊れないことを確認する」と「専用テストを足す」は別の判断である。** 確認は必ずやる。
テストを足すかどうかだけをこの基準で決める。

### テスト不足の finding として書くときの作法

テスト不足を finding にする場合、レビューコメントに可能な限り以下を書く
（「finding の判定基準」の「finding として書くときの作法（全 finding 共通）」が
要求する failure scenario を、テスト不足の場合に具体化したもの）。

- 逃す regression（何が、どういう変更で壊れるか）
- なぜ既存 spec では捕まらないか

これが書けない指摘は、そもそも finding ではない。

## Phase 1.5: PR提出前の自己レビュー（必須）

**実装が完了したら、レビュワーに依頼する前に、自分で自分をレビューする。**
このステップをスキップしてレビュー依頼するな。

工程計測:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.start --phase self_review --source pr-review-loop --round "$ROUND" || true
```

### なぜ必要か

レビュワーと同じ AI なのに、実装者が「作る脳」のままだとエッジケースに気づけない。
レビュワーは「壊す脳」で見るから気づける。実装者も提出前に「壊す脳」に切り替えれば、
レビュワーが見つけるはずの問題の大半は事前に潰せる。

### 手順

1. **コードを客観的に読む**: 自分が書いたコードを、**他人が書いたものとして**読む。
   すべての行に「これはなぜ必要なのか」「これが失敗したらどうなるか」を問いかける。

2. **レビュワーと同じ7次元でチェックする**（レビュー指示と同じ基準。文書だけの孫 PR は「文書だけの PR のレビュー範囲」に従う）:
   - **正当性**: 計画書・プロンプトの指示を全部実装したか
   - **エッジケース**: 空/nil/異常入力/並行実行/権限不足で壊れないか。
     壊れるなら直す。**壊れないことの確認と、そこに専用テストを足すかは別の判断**
     （「テストの判断基準（risk-based testing）」の edge case の扱いに従う）
   - **テスト**: 意味のある behavior と現実的な regression risk が守られているか。
     **新規動作すべてに専用 spec を足すことではない**
     （「テストの判断基準（risk-based testing）」に従う）
   - **無関係変更**: diff に紛れ込んだゴミがないか
   - **後方互換性**: 既存の挙動を壊してないか
   - **保守性**: 命名・責務・エラー処理は適切か
   - **スタイル**: lintが通っているか。**lint / formatter が問題にしない表面的なスタイルは
     finding ではない**（「finding の判定基準（general finding qualification gate）」に従う）

   自分のコードに対しても同じ gate を使う。pure nit は直すのが安ければ直してよいが、
   PR説明の「レビュワーに特に見てほしい点」に挙げて往復の材料にしない。

3. **コードを実行して確認する**（コマンドが設定されている場合のみ）:
   ```bash
   command -v ocw-meter >/dev/null && ocw-meter event phase.start --phase lint_test --source pr-review-loop --round "$ROUND" || true
   # LINT_CMD が設定されていれば実行
   # TEST_CMD が設定されていれば実行
   command -v ocw-meter >/dev/null && ocw-meter event phase.end --phase lint_test --source pr-review-loop --round "$ROUND" || true
   ```

4. **自分で見つけた問題は、レビュー前に自分で直す。**
   レビュワーに指摘させるな。指摘される前に潰せ。

5. **PR説明文に自己レビュー結果を明記する**:
   ```
   ## 自己レビュー
   - 正当性: 計画書の全項目を実装済み
   - エッジケース: nil/空入力/再実行を確認
   - テスト: XX examples, 0 failures
   - 無関係変更: なし
   ```

### 完了条件

- 全7次元をチェックしたと言える
- `LINT_CMD` + `TEST_CMD` が設定されていれば実行し、緑であること
- 「ここ大丈夫かな」と一瞬でも思った箇所を直した
- どうしても自信がない箇所だけ、PR説明文に「レビュワーに特に見てほしい点」として明記した

このフェーズを通過してから Phase 2 へ進む。**通過せずにレビュー依頼した場合、
往復の全責任は実装者にある。**

工程計測:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.end --phase self_review --source pr-review-loop --round "$ROUND" || true
```

## Phase 2: レビュー依頼

工程計測:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.start --phase review_request --source pr-review-loop --round "$ROUND" || true
```

レビュー指示をファイルに書き出し、短い依頼文でレビュワーに読ませる。**依頼文に長文を詰め込まない**（0.9.0 より前の `herdr pane run` ではペースト確認が入って2往復になった。経緯はADR DOC-2609072215）。

### Step 1: レビュー指示ファイルを作成

#### 置き場所

```bash
mkdir -p /tmp/pr-review-loop
gh repo view --json nameWithOwner -q .nameWithOwner    # 例: manemone/dotfiles
```

得られた `owner/repo` の `/` を `-` に置き換え、次のパスを `$REVIEW_REQUEST` とする
（`$PR` などと同じ記法。以降このファイルを指すときは、この**絶対パス**をリテラルに埋める）。

```
/tmp/pr-review-loop/<owner>-<repo>-<PR番号>.md
```

**リポジトリ名をファイル名に含めるのは必須。** PR番号だけだと、別リポジトリの同番号のPRを
並行して回したときに同じファイルを取り合い、レビュワーが**別リポジトリのレビュー依頼を読む**。

作業中のリポジトリの中には置かない。このスキルは任意のリポジトリで動くため、`tmp/` のような
ディレクトリはそのリポジトリで既に意味を持っていることがあり、既存ファイルを壊す。
また、無視されないまま Phase 5 の `git add -A` を通れば PR に混入する。

`$TMPDIR` も使わない。書く側（このペイン）と読む側（レビュワーペイン）は別プロセスであり、
macOS のようにセッションごとに `TMPDIR` が異なる環境ではパスがズレて解決できなくなる。
ベタ書きの `/tmp` は、両者が同じ値を見ることを保証するためのものである。

#### テンプレートの置換

テンプレート内の `{{...}}` は実際の値で置換する。`CONVENTION_DOCS` が空なら該当行を削除する。

`{{LINT_CMD}}` / `{{TEST_CMD}}` には、Phase 0.5 で**解決済みの**コマンド文字列をそのまま入れる。
レビュワーはこのファイルしか読まないため、ここに書かないとレビュワーは `.claude/pr-review.yml`
や自動検出から自力で再導出することになり、実装者と違うコマンドを走らせうる。値が空または
`null`（スキップ）なら、コマンドの代わりに `（未設定。このリポジトリでは実行しない）` と書く。

`{{FINDING_GATE}}` と `{{RISK_BASED_TESTING}}` だけは値ではなく、**本スキルの該当節の本文**で
置換する。レビュワーはこのファイルしか読まないため、節への参照ではなく本文を貼ること
（実装者とレビュワーが同じ基準を使うことが目的なので、片方だけ書き換えない）。どちらも、
見出し行とその直下の「実装者とレビュワーが同じ基準で使う」の1行（スキル内部の案内であり、
レビュワーには不要）は貼らない。

- `{{FINDING_GATE}}` ← 「finding の判定基準（general finding qualification gate）」節。
  `レビューで気づいたことは、` の段落から、その節の末尾（`両者は矛盾しない。`）
  までを貼る。**次の「テストの判断基準（risk-based testing）」節まで巻き込まない。**
- `{{RISK_BASED_TESTING}}` ← 「テストの判断基準（risk-based testing）」節。
  `テストは「コード・分岐・受け入れ条件」の数ではなく、` の段落から末尾までを貼る。

```bash
cat > "$REVIEW_REQUEST" << 'REVIEW_EOF'
# PR #{{PR}} レビュー依頼

対象PR: {{URL}}
対象HEAD: {{HEAD_SHA}}

## 最初のステップ
1. リポジトリを確認
2. {{CONVENTION_DOCSがあればそれを読む。なければスキップ}}
3. GitHubからPR説明・最新HEADの差分・既存コメント・既存レビューを取得
4. 最新HEADでPRをレビュー

## 読み方の作法（文脈を膨らませない）
- 保存ファイルに逃がされた大きい出力（persisted-output）を Read で全文読み直さない。`grep` / `tail` / 行範囲で読む
- 旧版の状態を `git show <sha>:<path> | cat -n` で取り直さない。`git diff <前回SHA>..HEAD -- <path>` で差分だけ読む
- 規約文書は全文 cat せず、`grep -n '^#'` で見出しを引いて要る節だけ読む
- ラウンド2以降は、最新のレビュー1件と未解決のスレッドだけ読む（`gh pr view --json reviews` の全件は読み直さない）

## 規約優先順位
{{CONVENTION_DOCSがあれば}}: 指定されたdocがレビューコメント形式・投稿先・承認/変更要求マーカー・スレッド解決・再レビュー手順の情報源。docにない規約を自作しない。
{{CONVENTION_DOCSがなければ}}: このレビュー依頼に記載された規約を情報源とすること。記載のない規約を自作しない。

## レビューガイドライン
- {{CONVENTION_DOCSがあればそのパスを列挙、なければ「この依頼の規約」}}を最優先
- 以下の**全7次元を必ずチェック**。どれか1つでもスキップして後続ラウンドで発見するのは禁止（ただし文書だけの孫 PR は、下記「finding の判定基準」の「文書だけの PR のレビュー範囲」に従う）:
  1. **正当性**: 仕様通り動くか。実装が計画書・issue・プロンプトの指示と一致しているか
  2. **エッジケース**: 異常系・境界値・空入力・nil・権限不足・並行実行
  3. **テスト**: 既存テストが壊れていないか。意味のある behavior と現実的な regression risk が保護されているか。**テスト追加を指摘する場合は、後述の「テスト不足の判定基準」の5項目を必ず通してから finding にする**
  4. **無関係変更**: diff に紛れ込んだ無関係な変更（lint設定・除外・フォーマット・他PRの残骸）がないか
  5. **後方互換性**: 既存の挙動を壊していないか。設定ファイルの既定値変更が波及していないか
  6. **保守性**: 命名・責務分離・コメント・エラー処理が適切か。**具体的な将来の壊れ方を説明できるものだけを finding にする**（後述の「finding の判定基準」）
  7. **スタイル**: lint違反がないか。**lint / formatter が問題にしない表面的なスタイルは finding ではない**（後述の「finding の判定基準」）
- **すべての指摘を、投稿前に「finding の判定基準」に通す。** 通らない pure nit は変更要求にしない（書くなら承認コメント末尾に「任意」として添える）
- 具体的で行動可能な指摘のみを投稿
- 指摘を重複させない
- 実際のコード・テスト結果・PR差分を読まずに承認しない
- コード修正・コミット・プッシュ・マージをしない
- 指摘と承認は必ずGitHubに投稿（画面上だけでは不可）
- 行レベルの指摘はインラインコメント、全体指摘はレビュー本文に（規約に従う）
- どのHEAD SHAを対象にしたレビューか明記

## 承認・変更要求マーカー
- 承認: `{{APPROVED_MARKER}}`
- 変更要求: `{{CHANGES_REQUESTED_MARKER}}`
- 返信: `{{REPLY_MARKER}}`

## finding の判定基準

{{FINDING_GATE}}

## 譲れないレビュー基準

**1. 一発で網羅。小出し厳禁。**
最初のラウンドでdiff全体を精査し全指摘を一度に出す。ラウンドを重ねるたびに実装者が修正→テスト→プッシュのサイクルを1回余計に回すことになる。ラウンド1を投稿する前に以下を確認: 全変更ファイルを端から端までチェックしたか、diffが参照するコマンド名・パス・設定デフォルト値を実物と突合したか、diffが「要参照」と指すファイルを読んだか、無関係な変更（lint設定・除外・フォーマット）が紛れ込んでいないか。

**2. substantive な問題を絶対に伏せない。ただし pure nit はそもそも finding ではない。**
「finding の判定基準」を通る問題は、一つも伏せない。以下は沈黙の正当な理由にならない:
- 「変更行じゃなくてコンテキスト行だから」
- 「このPRのテーマ外だから」
- 「既存の問題でこの変更が原因じゃないから」
- 「小さい指摘だから」「指摘するとラウンドが増えるから」

承認後に伏せていたことに気づいたら、即座に承認を取り消して投稿する。隠すことは遅れて出すより常に悪い。

**「伏せる」と「finding ではないと分類する」を混同しない。** 「finding の判定基準」を通らない pure nit を変更要求にしないのは沈黙ではなく分類の結果である。逆に、実バグ・安全性・データ破壊・security・後方互換性の問題は、後続ラウンドで気づいたとしても必ず出す。テストを追加するかどうかは、加えて「テスト不足の判定基準」の入口判定も通す。**バグそのものを「テストの話だから」と黙るのは、この入口判定の対象外である。**

**3. finding の入口と、finding 後の扱いは別。**
まず「そもそもこれは finding か」を「finding の判定基準」（テストについては加えて「テスト不足の判定基準」）で判断する。**「こっちの方がきれい」「追加するとより安心」だけでは finding ではない。**

いったん finding と認定したら、扱いは従来どおり厳格である。全指摘を「直してください」と書く。禁止表現: 「このPRでの対応は不要」「参考まで」「お任せします」「気になったときに直すのが良い」「別PRで」。重要度は順序で表現し、指摘をオプション扱いしてはいけない。

**4. 範囲判断には証拠を添える。**
問題がPRの範囲を超える場合（例: 古い名前が多数のファイルに出現）、測定し（ファイル別grep件数）、このPRで修正すべき範囲を明示し、その境界の理由を述べ、上書き権をユーザーに委ねる。

**5. 生成物は実物を読む。想定で済ませない。**
PRがファイルを生成する場合（テンプレート・設定・doc）、実際に実行またはレンダリングして出力を読む。記載された全コマンドの実在・全パスの解決可能性・ステップ順序の前提条件を確認する。

**6. 1レビュー1判定。未解決指摘ありで承認しない。**
投稿前に未修正の指摘を数える。1件以上 → 判定は変更要求。レビューには変更要求マーカー（`{{CHANGES_REQUESTED_MARKER}}`）を付ける。0件 → 承認（`{{APPROVED_MARKER}}`）。
修正要求があるのに承認することは禁止。以下はすべて同じ禁止行為:
- 「承認。ただしマージ前に1点だけ直してください」
- 「承認（再レビュー不要なので直したらマージしてOK）」
- 承認本文＋インラインでの修正要求
重要度は変更要求レビュー内での順序で表現する。1行の修正でも変更要求。

**7. 再レビュー免除は権限外。**
PRへのプッシュ（自分が指示した1行修正含む）は承認を無効化し新HEADの再レビューを必須とする。変更が小さすぎて見るまでもないと決める権限はレビュワーにない。
禁止表現:
- 「修正後の再レビューは不要です」
- 「直したらマージして構いません」
- 「1〜2行の移動で済むので確認しなくて大丈夫です」
代わりに「修正後、新しいHEADで再レビューします」と書く。承認はそれが指すSHAに対してのみ有効。

**8. 再レビューは新規差分のみ。蒸し返し禁止。**
2ラウンド目以降のレビューでは、まず前回レビュー対象SHAと現HEADの差分を確認し、前回のレビューで確認済みの領域を再指摘してはいけない:
- 前回「✅ 解決」と確認した指摘は、**そのコードに新たな変更が加わっていない限り**再指摘しない
- インラインコメントが解決済みのスレッドは再提起しない
- レビュー本文の先頭に「前回レビュー: #N（全X件中Y件解決、Z件持ち越し）」と明記する
- **新規に発見した問題だけを報告する**
- 新規 finding は「今回の修正差分が新しく導入した substantive problem」か「前回見落としたが『finding の判定基準』を明確に通る substantive problem」のどちらかに限る。コメントの折り返し・空白・cosmetic formatting・表面的な言い回しを、後続ラウンドの新規 blocking finding にしない
- ただし「前回見落としたからもう言えない」ではない。actual bug / safety / data loss / security / 後方互換性の問題は後からでも出す

蒸し返しが発生した場合、それはレビュワーが前回の自分の指摘を覚えていないのではなく、
実装者が「解決」と偽装した証拠である。Phase 5 Step 0 の自己検証漏れを疑え。

## テスト不足の判定基準

{{RISK_BASED_TESTING}}

## 検証コマンド

このリポジトリで使うコマンド。**自分で別のコマンドを推測して使わない。**
実装者もこれと同じコマンドで検証しているため、食い違うと結果を突き合わせられなくなる。

- lint: `{{LINT_CMD}}`
- test: `{{TEST_CMD}}`

targeted test（対象を絞った実行）は、上記の test コマンドに対象パスやフィルタを足して作る。
絞り方がリポジトリの流儀として不明なら、絞らず full suite を実行してよい。

## テスト・lint 実行の方針（ラウンドごとに変える）

**初回レビュー（ラウンド1）は従来どおり広く確認する。** diff全体、仕様・計画との突合、
必要なら実物実行、上記「検証コマンド」の lint / test の full suite。初回レビューの品質は
落とさない。

**再レビュー（ラウンド2以降）は、最初に「前回レビュー対象SHA → 現HEAD」の差分を確認し、
次の A / B に分類してから検証する。**

**分類はレビュワー自身が差分を見て行う。** 実装者が対応報告コメントで「コメント・docs のみ」と
申告していても、それは参考情報であって根拠ではない。**自分の分類と食い違ったら、常に
レビュワーの分類を採る。** 実装者の申告を信じて B に倒した結果、runtime に効く変更が
full suite を通らずに素通りするのが最悪の分岐である。判断がつかないものは A に倒す。

### A. runtime behavior に影響する変更

production code / 実行スクリプト / runtime config / 依存 / build設定 /
永続化・APIスキーマ / テスト対象となるロジック など。

- 変更に直接関係する **targeted test をレビュワー自身が独立に実行する**
- 必要なら関連する lint を実行する
- **現HEADに対する信頼できる full-suite 成功結果がすでに存在するなら、レビュワー自身が
  full suite を再実行する必要はない。** ただし証拠には強さの差がある。強い順に:

  1. **CI が現HEADで green。** CI は現HEADのツリーそのものを取得して実行するため、
     SHA が一致すれば「そのツリーがテストされた」ことまで保証される。**これだけが独立した証拠**
  2. **実装者が現HEADで実行し、GitHubコメントにSHA付きで結果を記録している。** 自己申告であり、
     実行環境も実装者のローカルである。内容の妥当性（コマンド・examples数・failures数）は読む
  3. **pre-commit フックが現HEADのコミット作成時に full suite を実行している。** 2と同じく
     自己申告で、**強度は2と同等であって CI とは別格**。フックは commit 前の**ワーキングツリー**
     に対して走るため、`--no-verify`・未ステージ変更の混在・`--amend`・rebase では現HEADのツリーと
     一致しない。この不一致は**SHAの照合では検出できない**（SHAが合っていても、そのツリーが
     テストされたとは限らない）

- **SHAの一致は必要条件であって十分条件ではない。** 2 / 3 を根拠にする場合は、記録されたSHAと
  現HEADの一致に加えて、実装者が `--no-verify` を使っていないこと・実行結果の内容が妥当なことを
  コメントから確認する。確認できなければ、後述「レビュワー自身が full suite を実行する場合」に倒す

### B. runtime behavior に影響しない変更

コメントのみ / Markdown・docs / README / typo / コメントの折り返し / 純粋な散文 など。

- Ruby / Python / JS 等の **full test suite を実行しない**
- runtime lint も、変更と無関係なら実行しない
- doc verifier / markdown lint / link check など、その変更に直接関係する検証だけを使う
- 該当する検証が無ければ diff の目視確認だけでよい

**コメント数行の折り返し修正のために数千 examples を回さない。**

### レビュワー自身が full suite を実行する場合

次のいずれかに当たるときは、レビュワーが full suite を実行する:

- 現HEADに対する full-suite 結果が存在しない
- rebase / merge / 外部プッシュで baseline が不明
- dependency / shared config / build infrastructure など影響範囲の広い変更
- targeted test が失敗した
- 影響範囲を合理的に限定できない
- CI や pre-commit の結果の信頼性に疑義がある

### 承認の条件

承認条件は「レビュワー自身が full suite を回した」ではなく、
**「現HEADに対して必要な full-suite 保証が存在し、レビュワーがそれを確認した」**である。
承認レビューには、**どの full-suite 結果を、どのSHAに対するものとして確認したか**を明記する。
現HEADに対する保証が確認できない場合は承認せず、自分で full suite を実行する。

完了したらサマリーとレビュー状態（承認/変更要求）を報告すること。
REVIEW_EOF
```

### Step 2: レビュワーの状態確認と起動

**依頼を送る前（およびレビュワーを起動し直す前）にこの手順を実行すること。`agent_status` が `unknown` なのは「エージェントがいない」場合だけではない（下表）。**

```bash
STATUS=$(herdr pane get "$REVIEWER_PANE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result']['pane'].get('agent_status',''))")
```

`agent_status` は Herdr がエージェント種別によらず同じ語彙で返す値であり、レビュワーが
どのエージェントでもこの表がそのまま使える。

| status | 意味 | 取るべき行動 |
|--------|------|-------------|
| `idle` | エージェント起動中、待機状態 | Step 3へ |
| `done` | 前ラウンドの完了結果が未読のまま。待機状態であることは `idle` と同じ | Step 3へ |
| `working` | エージェントが処理中 | Phase 3a と同じ `herdr agent wait "$REVIEWER_PANE" --timeout 600000`（`--until` なし）で待ち、**抜けたら `agent_status` を取り直してこの表を引き直す**（`blocked` でも待ちは成立するため、権限確認のダイアログに依頼文を送らないよう、`idle` / `done` を確認してからStep 3へ）。無人の背面ペインは完了しても `done` で止まり自動では `idle` にならないため、`--until idle` だけを待つと10分空転する |
| `blocked` | 判断待ちで停止 | ペイン出力を読んで可能なら回答。人手が必要ならユーザーに伝える |
| `unknown` または空 | エージェントのいないペイン（シェルだけのペインなど）は `unknown` を返す。**エージェントがいるが herdr が状態を分類できない場合にも `unknown` が返る**ので、`unknown` だけでは終了とは決められない | 以下の「unknown 時の確認手順」を実行 |

**unknown 時の確認手順:**

`unknown` でもエージェントは動いていることがある。必ず目視で確認する（検出ルールと根拠を見たいときは `herdr agent explain "$REVIEWER_PANE"` も使える。ただし target は「エージェントがいるペイン」に限られ、終了済みのペインには使えない）:

```bash
herdr pane read "$REVIEWER_PANE" --source detection --lines 3
```

判定は**エージェント固有の飾りではなく、次の3つのどれに当たるか**で行う。
**入力欄（`❯` の行）に文が見えるだけでは「本文を抱えている」と判定しない。** Claude Code は
次に打ちそうな文を自動で推測し、入力欄に薄い字の候補として出す。`herdr pane read` では普通の
文字と同じに見えるが、人が打った本文ではない（入力モードやペースト確認の表示が無ければ候補である）。
人間の操作の根拠にもしない:

- **エージェントが入力欄に本文を抱えたまま確定待ち**（入力モードやペースト確認の表示が出ている）
  → 起動済み。`herdr pane send-keys "$REVIEWER_PANE" Enter` で確定させ、`idle` または `done`
  になってから Step 3 へ。
- **シェルプロンプト**（`$` や `❯` で終わる行だけがあり、エージェントの応答が無い）
  → エージェントはいない（終了したのか、`ocw -H` が作ったまま一度も起動していないのかは
  区別しなくてよい。どちらも「シェルだけのペイン」で、起動してよいという結論が同じ）。
  下記「`ocw agent` での起動」を先に試し、使えなければ「起動コマンドの決定」に従って
  起動し直す（主経路の `herdr agent start` は入力可能になってから戻る。`pane run` に
  落ちたときは同じ節の起動待ちが要る）。
- **エージェントの応答が表示されている**（直近の行がエージェントの出力）→ 実は起動中。
  `herdr pane get` を再実行して状態を再確認。

エージェント別の見え方の例（参考。この一覧に無い表示でも上の3分類で判断する）:

| エージェント | 確定待ちの表示例 | 応答中の表示例 |
|---|---|---|
| Claude Code | `-- INSERT --`, `accept edits on`, `← for agents` | `●` や `✻` で始まる行 |

**`ocw agent` での起動（`ocw -H` で作ったワークスペースの reviewer ペイン）:**

`ocw -H` は reviewer のエージェントを起動せずペインだけ作る（agents の欄を混雑させないため。
ADR DOC-2610112129）。作成時に reviewer の起動行（会話の名前 `--name '<ラベル> / レビュー'` と
`OCW_REVIEWER_COMMAND` の上書き込み）が git dir に残っているので、`ocw agent` を打てば
即時起動と同じエージェントが立つ。**ペインが上の判定でシェルだけと確かめられたときに限る**
（エージェントが動いているペインに打つと、その文字列が依頼として届く）。使えるのは、`ocw` が
PATH にあり、かつ起動行が残っているときだけ:

```bash
command -v ocw >/dev/null && test -f "$(git rev-parse --absolute-git-dir)/ocw-agent-reviewer" && echo OK
```

`OK` のとき、次で起動し、下記「`pane run` での起動（フォールバック）」と同じ起動待ち
（`agent_status` が `idle` / `done` / `blocked` になるまで最大30秒）をする。
`OK` が出ない（`ocw` が無い環境・他人のリポ・Codex 等・`ocw agent` ができる前に作った
ワークスペース）ときは使わず、そのまま下の「起動コマンドの決定」へ進む。

```bash
herdr pane run "$REVIEWER_PANE" "ocw agent reviewer"
```

**起動コマンドの決定:**

KIND（`herdr agent start --kind` に渡す種別）と引数を、次の順で決める。KIND の一覧は
スキルに書き写さず、`herdr agent` の出力の `kinds:` 行を正典として参照する
（herdr のバージョンで増減する）。

1. `REVIEWER_CMD`（Phase 0.5 の `reviewer_cmd`）があるとき、その**先頭の語**を見る
   - 先頭の語が `herdr agent` の `kinds:` に載っている → それが KIND。残りの語は引数
     （`claude --model opus` なら KIND=`claude`、引数=`--model opus`）。**ただし残りに引用符・
     バックスラッシュ・`$`・`;` などシェルの解釈が要る文字が含まれるときは、引数に分けず**
     KIND が決まらない場合と同じく `pane run` で `REVIEWER_CMD` をそのまま起動する
     （引数の分割をシェル任せにすると、zsh では1語にまとまり、bash では引用符が壊れる）
   - 先頭が環境変数の代入（`FOO=bar claude`）やラッパー（`env ...` など）、または
     `kinds:` に無い語で KIND が決まらない → **推測せず**、下記「`pane run` での起動
     （フォールバック）」で `REVIEWER_CMD` をそのまま起動する
2. `REVIEWER_CMD` が無ければ、Phase 0 で読み取った `$REVIEWER_AGENT` を KIND に使う
   （引数なし）。この経路で `pane run` に落ちるときは `REVIEWER_CMD` の代わりに
   `$REVIEWER_AGENT` をそのままコマンド名として使う
3. どちらも空なら**推測して起動しない。** 停止してユーザーに
   「レビュワーペインのエージェントが終了しており、起動コマンドが特定できません。
   `.claude/pr-review.yml` に `reviewer_cmd` を設定するか、ペインで手動で起動してください」
   と伝える。誤ったコマンドを撃つとシェルにゴミが流れ、以降の状態判定が壊れる。

**`herdr agent start` での起動（主経路）:**

`agent start` は、ペインにシェルが前面でプロンプト待ちのとき、エージェントが検出されて入力可能に
なってから戻る。起動待ちの手順は要らない。NAME は**サーバー全体で一意**
（`[a-z][a-z0-9_-]{0,31}`、生きているエージェントの間で一意）でなければならないため、
ペインIDから機械的に作る（`wEB:p3` → `rv-web-p3`。小文字化して `:` を `-` にする）。
役割の識別に NAME は使わない（ワークスペースごとに reviewer がいて衝突する。役割は
ペインの `label` で識別する）。

```bash
NAME="rv-$(printf '%s' "$REVIEWER_PANE" | tr 'A-Z:' 'a-z-')"
# 引数なし
herdr agent start "$NAME" --kind "$KIND" --pane "$REVIEWER_PANE"
# 引数あり（例: REVIEWER_CMD が "claude --model opus" のとき。-- の後ろに、
# 先頭の語より後ろの単語をリテラルに並べる。シェル変数には入れない）
herdr agent start "$NAME" --kind "$KIND" --pane "$REVIEWER_PANE" -- --model opus
```

`$NAME` / `$KIND` と `--` の後ろの引数は、Phase 1 の注記と同じく実際の値をその場で
リテラルに埋める記法である。

実測（2026-10-11、herdr 0.9.0、`--kind claude`）: 空のシェルペインで約4秒で戻り、返りの
`result.agent` に `agent_status: "idle"`・`interactive_ready: true`・`name` が入る
（`result.argv` は起動された実際のコマンド列）。`-- --model haiku` は
`argv: ["claude","--model","haiku"]` として渡った。既定のタイムアウト（30秒）で足りたので
`--timeout` は通常指定しない。戻ったら `agent_status` が `idle` であることだけ確認して
Step 3 へ進む。

失敗したときは**同じ呼び出しを繰り返さず**、エラーコードで分ける:

- `agent_name_taken`（名前の衝突）→ NAME の末尾に `-2` などを付けて**一度だけ**作り直す
  （実測: 同じ名前を別ペインに使うと、衝突している側のペインを `candidates` に付けて
  このコードで即座に失敗する）。それでも失敗したらフォールバックへ
- `unsupported interactive agent kind: ...`（`kinds:` に無い種別）→ フォールバックへ
- `agent_not_ready`（起動時に `blocked`。ログイン・承認待ちなど）→ フォールバックには落とさず、
  `herdr pane read "$REVIEWER_PANE" --source detection --lines 10` で画面を確認して、可能なら
  回答し、人手が必要ならユーザーに伝える
- タイムアウト → エージェントは起動中かもしれない。`herdr pane get "$REVIEWER_PANE"` の
  `agent` / `agent_status` を確認し、検出されていれば成功として扱う。検出されていなければ
  `herdr pane read "$REVIEWER_PANE" --source detection --lines 10` で画面を見て、
  **シェルプロンプトに戻っているときだけ**フォールバックへ進む。それ以外（起動途中の画面）は
  何も送らず、少し待って `pane get` で確かめ直すか、ユーザーに伝える（起動途中の入力欄に
  `pane run` の文字列が入ると、レビュワーへの最初の指示になってしまう）

**`pane run` での起動（フォールバック）:**

KIND が決まらない `REVIEWER_CMD`、および上記で `agent start` が使えなかった場合にだけ使う。
コマンドは `REVIEWER_CMD`、無ければ `$REVIEWER_AGENT`（「起動コマンドの決定」の手順2）。

```bash
herdr pane run "$REVIEWER_PANE" "$REVIEWER_CMD"
```

`pane run` で起動した場合、エージェントが検出されるまで `herdr agent wait` の target に
ならない（`agent_not_found` で即失敗する）ので、`agent_status` を短い間隔で見て最大30秒待つ:

```bash
for _ in $(seq 1 30); do
  STATUS=$(herdr pane get "$REVIEWER_PANE" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['pane'].get('agent_status',''))")
  case "$STATUS" in idle|done|blocked) break ;; esac
  sleep 1
done
```

抜けたあとの `STATUS` が `idle` / `done` でなければ（`unknown` のまま、または `blocked`）、
Step 3 へ進まず `herdr pane read "$REVIEWER_PANE" --source detection --lines 10` で画面を確認する。

**起動したあとは `$REVIEWER_AGENT` を読み直す。** Phase 0 の時点でエージェントがいなかった
（`ocw -H` が作ったまま）と `$REVIEWER_AGENT` は空のままで、Step 3 と Phase 6 の
`SendMessage` の条件（「`$REVIEWER_AGENT` が `claude`」）が成り立たず、毎ラウンド
`herdr agent prompt` に落ちる。`ocw agent` / `herdr agent start` / `pane run` のどれで
起動した場合も、起動待ちが終わったら Phase 0 と同じ手順で `agent` を取り直して更新する
（Phase 6 の再依頼も Step 2 を通るので、ここに置けば両方に効く）:

```bash
herdr pane get "$REVIEWER_PANE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result']['pane'].get('agent') or '')"
```

### Step 3: 依頼を送信

レビュワーが `idle` または `done`（どちらも待機状態）であることを確認した上で、依頼を送信する。

**送信は `umbrella-orchestrator/SKILL.md` §5「AI間送信手順（二段構え）」に従う**
（正典はそちらにあり、本スキルは参照するだけで全文をコピーしない。背景・実測は
ADR DOC-2609072215 参照）: **自分（この Phase を実行している側）が `SendMessage` を
呼べる Claude Code セッションで**、かつ `$REVIEWER_AGENT` が `claude` で
`$REVIEWER_PANE` の `agent_session.value` から `~/.claude/sessions/` を引けたら
`SendMessage` を使う。自分が `SendMessage` を呼べない（Codex / OpenCode 等で実行
している）、`$REVIEWER_AGENT` が `claude` 以外、または索引が引けない場合は次の
フォールバックへ落ちる。

```bash
herdr agent prompt "$REVIEWER_PANE" "以下を読んでPRレビューを実行してください。レビュー指示: $REVIEW_REQUEST" --wait --timeout 10000
```

返り値の読み方（`timeout` / `agent_prompt_stalled` は未達の証明にならず**再送しない**、
`agent_blocked` は何も送られていない、など）は同節「フォールバック」に従う。

### Step 4: 配信確認

**`SendMessage` を使った場合**: 送信直前に控えた `agent_status`（Step 3 の直前に
`herdr pane get "$REVIEWER_PANE"` で取得しておく）から変化していることを確認する。
変化していなければ（特に送信前がすでに `done` だった場合、状態だけでは届いたか
判別できない）`herdr pane read "$REVIEWER_PANE" --source recent-unwrapped --lines 10`
で画面を目視し、新しい応答が出ていなければフォールバック（`herdr agent prompt`）に切り替える。

**フォールバック（`herdr agent prompt`）を使った場合**: 返り値と、必要なら
`herdr agent get "$REVIEWER_PANE"` / `herdr agent read "$REVIEWER_PANE"` で確認する
（読み方は `umbrella-orchestrator/SKILL.md` §5「フォールバック」に従う。`send-keys Enter` は
不要）。**同じ本文を再送しない。**

工程計測:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.end --phase review_request --source pr-review-loop --round "$ROUND" || true
```

次は「区切りでの自己 compact（実装側のみ）」の判断をしてから Phase 3 へ進む（閾値以下・使えないなら飛ばす）。

## 区切りでの自己 compact（実装側のみ）

実装者の会話は、PR を出してレビューを待つ間に文脈が大きく膨らんでいることが多い。文脈が大きい
ほど、レビュー待ちのあとの毎ターンの読み込みが重い（実ログでは、実装の費用の約 53% が文脈 20万超の
呼び出し。調査 DOC-2610130216 §3.4）。そこで **レビューを依頼した直後**（Phase 2 Step 4 の
あと、および Phase 6 手順5のあと）の区切りで、文脈が閾値を超えていれば自分で compact する。
さらに PR を出す前の実装の途中にも、区切りを1つ足してある（下記 (3)）。
専用コマンド `ocw self-compact` を使う（ADR DOC-2610130913。Claude Code 固有）。

**行う区切りは次の3つ**: (1) PR を出してレビューを依頼した直後、(2) レビュー指摘への対応を
push して再レビューを依頼した直後、(3) **PR を出す前の実装の途中で、検証が通ってコミットした直後**
（ADR DOC-2610142337）。**指摘対応の修正の途中、Phase 7（承認後の完了報告）、レビュワーでは
行わない。** (3) 以外の途中で compact すると作業中の判断が落ちる。レビュワーは文脈が 20万に
届かず、compact のコストのほうが大きい（調査 §3.4）。承認後は残る仕事が少ない。

**(3) は別の手順で行う。** (3) は `/pr-review-loop` の起動前の局面なので、実装中の孫は
`umbrella-orchestrator` §3.2 の自動付与指示でこれを受け取る（`task-intake` の軽いハンドオフの実装AIは
自動付与指示を受け取らず、`OCW_ROLE=implementer` に反応するフックの差し込みが入口になる）。下の手順1〜6はレビュー待ち（(1)(2)）用で、
「Phase 3 へ進む／戻る」と書かれている箇所は (3) には当てはまらない。(3) で使うのは次だけ:

- 測り方は手順1のコマンド、閾値は手順2の 200,000（測れない・超えていない・使えないときは何もせず
  実装を続ける。人間に提案も通知もしない）
- WIP・チェックポイントのコミット（あとで直すつもりのもの）は区切りでない。1 PR につき (3) の compact は
  多くて 3 回まで（復帰メモに回数を残す）
- 復帰メモは手順3のレビュー待ち用ではなく実装途中用にする。先頭に「計画書の続きから実装を再開する。
  レビュー待ちではない」、計画書のパスと孫の節（傘の外の1本規模ならブリーフの絶対パスと、最初に受けた指示）、済んだこと（コミットの一覧）、**作業中に下した判断と
  その理由**（要約で一番落ちやすい）、残り、次の一手、検証コマンド、(3) の compact の回数を書く
- コマンドは手順4の形で、引数は「復帰メモ <パス> を最初に読む。実装の途中。メモの先頭に従い計画書の
  続きから実装を再開する」。成功したらそのターンを終える。復帰したらメモを読み、一時ファイルは消す

**やること（区切りごとに1回だけ判断する）**:

1. 自分の文脈の大きさを測る（Claude Code 固有。測れない・失敗した・他のエージェントなら、
   この節を丸ごと飛ばして Phase 3 へ進む）:

   ```bash
   python3 -c "
   import glob,json,os
   f=glob.glob(os.path.expanduser('~/.claude/projects/*/'+os.environ['CLAUDE_CODE_SESSION_ID']+'.jsonl'))[0]
   u=[json.loads(l)['message']['usage'] for l in open(f) if '\"type\":\"assistant\"' in l][-1]
   print(u['input_tokens']+u.get('cache_read_input_tokens',0)+u.get('cache_creation_input_tokens',0))"
   ```

2. **200,000 を超えていなければ飛ばして Phase 3 へ進む。** 根拠は実ログの試算（調査 §3.4 の
   `simcap`。上限を超えたら 80k まで縮めるとして compact のコストを引いた実装の純削減）で、
   上限 150k は 98 回で 10%、200k は 44 回で **13%（最大）**、300k は 12 回で 8%。150k は
   回数が増えて 1回あたりの得が薄くなり、300k は多くの PR が届く前に終わって取りこぼす。
   200k を下限にした。実装は 1 PR ごとの作業で、区切りは PR 1本につき数回しか来ないので、
   取りこぼしを避けたい。見積もりであり、実運用で見直す
3. **復帰メモを書く。** リポの外（`mktemp -d` で作った一時ディレクトリ。システムの指定に
   スクラッチパッドがあればそこ）のファイルに、compact 後の自分が最初に読む内容を書く:
   - 先頭に「compact が終わったら何をするか」: **次は Phase 3（レビュワーの完了待ち）に戻る。
     レビュー依頼は送信済みなので再送しない。** まず `herdr pane get "$REVIEWER_PANE"` で
     レビュワーの状態を取り、`working` なら Phase 3a の `herdr agent wait`、`idle` / `done` なら
     Phase 3b（`gh pr view "$PR" --json reviews,comments` ほか）で結果を収集する。完了通知は
     来ないので、待たずに `gh pr view` で投稿の有無を確かめてよい
   - Phase 3 以降を続けるのに要る値: PR 番号とリポ（`$OWNER` / `$REPO`）、`$ROUND`（Phase 6 からの compact なら、手順6で繰り上げた後の値。次の Phase 3 で使う値）、
     レビュー対象の `$HEAD_SHA`（Phase 6 からなら差し替え後の、再レビュー依頼で送った現HEAD）、`$REVIEWER_PANE`、
     `$REVIEWER_AGENT`、`$REVIEW_REQUEST` の絶対パス、`.claude/pr-review.yml` から解決した設定
     （`TEST_CMD` ほか）、直近のレビュー指摘への対応の要点
   - 起動時の指示から引き継ぐもの: 計画書の絶対パスとその孫用プロンプトの場所、承認後に報告する
     司令官のペイン ID、「承認されてもマージしない」などの制約
4. **コマンドを実行して、そのターンを終える。** メモのパスを1行にして渡す:

   ```bash
   ocw self-compact "復帰メモ <メモの絶対パス> を最初に読む。PR #<番号> のレビュー待ちの途中。メモの先頭に従い Phase 3（レビュワーの完了待ち）に戻る。依頼は再送しない"
   ```

   - このコマンドは自分のペイン（`$HERDR_PANE_ID`）へ `/compact <引数>` だけをその場で送り、
     続きを促す固定の1通は compact の完了後にバックグラウンドの監視が送る。他のペインへは送れず、
     Herdr の外では何もせず失敗する。`herdr agent prompt` を自分で直接打たないこと
     （auto mode の分類器が自分のペインへの送信を拒否する。このコマンドだけは permission の allow
     ルール `Bash(ocw self-compact *)` で通す）
   - **成功したら新しい作業を始めず、そのターンを終える。** `/compact` は現ターンの終了後に実行される
   - 続きを促す固定の1通は「復帰メモがあれば読み、計画書の続きから再開してください。」である。
     メモの先頭に「計画書ではなく、メモの Phase 3 の指示に従う」と書いておけば食い違わない
5. **コマンドが使えない・拒否された・失敗した・Claude Code 以外のエージェントのときは、何もせず
   Phase 3 へ進む。** 人間に提案も通知もしない（人間の手を煩わせる価値が小さいため）。
   拒否は回避せず、同じ区切りで繰り返さない
6. **復帰したら**、メモを読んで Phase 3 から続ける。メモの一時ファイルは復帰が済んだら消す。
   レビュワーのペインは別のセッションなので影響を受けない。待っている間にレビューが完了していても、
   Phase 3b の収集（GitHub の投稿）で拾える。compact の完了を待つ間に孫のレビューが投稿されることは
   正常で、取りこぼさない

## Phase 3: レビュワーの完了を待つ

工程計測:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.start --phase review_wait --source pr-review-loop --round "$ROUND" || true
```

### 作業開始を待つ

```bash
herdr agent wait "$REVIEWER_PANE" --until working --timeout 30000
```

完了待ち（Phase 3a）の前にこの `working` を必ず観測する。`herdr agent wait` は対象がすでに
`idle` / `done` なら即座に戻るため、送信前の `idle` のまま完了待ちに入ると空振りする。

タイムアウトしたら `herdr pane get "$REVIEWER_PANE"` と `herdr pane read "$REVIEWER_PANE" --source detection --lines 10` で確認する。
**依頼を再送しない**（Step 4 と同じ。本文は届いている可能性がある）。本文が見えるのに
動いていなければ、人間に報告する。

### Phase 3a: 完了を待つ（イベント駆動）

`herdr agent wait` はイベント駆動で、状態が条件に合うまでブロックする。`--until` を省略すると
`idle` / `done` / `blocked` のどれかで成立する。

**`done` と `idle` は別の状態への遷移ではなく、同じ「完了」状態を「見られたか」で
呼び分けているだけ**（herdr 自身の公式ドキュメント、`herdr` skill）。ペインの
タブ／ワークスペースが背面（フォーカスされていない）のまま完了すると `done` になり、
**実際にそのタブをフォーカスするまで自動では `idle` に変わらない**。フォーカスされた
状態で完了すれば直接 `idle` になる。

`REVIEWER_PANE` は無人（誰もそのタブを見に行かない）で完了することが多いが、
**端末クライアントが繋がっていないヘッドレス実行（cron 等）では、globally active
tab にいるペインは完了時に直接 `idle` になる**（herdr 公式ドキュメントの記述。
`/autopilot` から回すときはこちらが標準的な条件）。したがって完了は `done` と `idle` の
両方で見る必要があるが、`--until` を省略した `herdr agent wait` は `idle` / `done` /
`blocked` のどれでも成立するので、ループは要らず1行で済む:

```bash
herdr agent wait "$REVIEWER_PANE" --timeout 600000
```

（タイムアウトは 600000ms＝10分。タイムアウトすると終了コード1で
`{"error":{"code":"timeout",...}}` が返る。対象がすでに `idle` / `done` なら即座に戻るので、
「作業開始を待つ」で `working` を観測してから呼ぶこと。target は「エージェントがいる
ペイン」でなければならず、エージェントが終了していると使えない）

待ちが終わったら（成功でもタイムアウトでも）、**毎回**状態を取り直して分岐する。`--until` なしの待ちは
`blocked` でも成立するため、成功で戻っても完了とは限らない:

```bash
STATUS=$(herdr pane get "$REVIEWER_PANE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result']['pane'].get('agent_status',''))")
```

- `blocked` → 出力を読んで可能なら回答。人手が必要なら停止してユーザーに伝える。
- `working`（継続中、タイムアウト）→ レビューに時間がかかっている。ペイン出力を読む。
- `idle` / `done` → Phase 3bへ。
- それ以外（`unknown` など） → ペインを目視して確認する。

工程計測:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.end --phase review_wait --source pr-review-loop --round "$ROUND" || true
```

### Phase 3b: 結果の収集

工程計測:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.start --phase review_collect --source pr-review-loop --round "$ROUND" || true
```

エージェントが `done`（または `idle`）に達したらレビュー完了。全内容（レビュー本文＋インラインコメント）はGitHubに投稿済み。以下両方で確認:

1. GitHub（真実の源）:

```bash
gh pr view "$PR" --json reviews,comments
gh api "repos/$OWNER/$REPO/pulls/$PR/comments"
```

2. レビュワーペイン出力（コンテキスト/サマリー用）:

```bash
herdr pane read "$REVIEWER_PANE" --source recent-unwrapped --lines 120
```

画面上の出力だけをレビュー結果として扱うな。GitHub投稿だけが本物。

収集したインラインコメント・レビュー本文中の修正要求のうち、未解決のものの件数を数え、`$FINDINGS_COUNT` として保持する（Phase 4 末尾の工程計測で使う）。

工程計測:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.end --phase review_collect --source pr-review-loop --round "$ROUND" || true
```

## Phase 4: レビュー状態の判定

`CONVENTION_DOCS` が設定されていればその規約を、なければ以下のデフォルト判定基準を使う。

デフォルト判定基準:
- レビュー本文に `{{APPROVED_MARKER}}` → 承認
- レビュー本文に `{{CHANGES_REQUESTED_MARKER}}` → 変更要求
- レビュー本文に「修正要求」→ 変更要求

**承認は何も要求していない場合のみ。** 承認マーカーがあっても修正要求（インラインの「直してください」「マージ前に1点だけ」等）が1件でも残っていれば変更要求扱いでPhase 5へ。

曖昧なレビューに当たったら、Phase 6の再依頼で「判定が曖昧でした。単一の曖昧でない状態にしてください」と伝える。

承認 → Phase 7（報告）。
変更要求 → Phase 5（修正）。

工程計測（この判定の直後、Phase 5/6/7のいずれに進む場合も1回だけ実行する。`$VERDICT` には確定した判定を
`approved` / `changes_requested` / `ambiguous` のいずれかでリテラルに入れる（他の `$XXX` 表記と同じ記法。
`<...>` のような山括弧はbashの入力リダイレクト/パイプとして解釈されるため使わないこと）。`$FINDINGS_COUNT` は
Phase 3bで保持した未解決指摘の件数（承認なら0）、`$HEAD_SHA` はレビュー対象のHEAD）:

```bash
command -v ocw-meter >/dev/null && ocw-meter event review.round --round "$ROUND" --verdict "$VERDICT" --findings-count "$FINDINGS_COUNT" --reviewed-head-sha "$HEAD_SHA" --source pr-review-loop || true
```

## Phase 5: 修正

工程計測:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.start --phase fix --source pr-review-loop --round "$ROUND" || true
```

### Step 0: 修正前の必須チェック（毎ラウンド実行）

指摘を修正する**前に**、以下のチェックを必ず実行する。このチェックをスキップして「対応しました」と虚偽報告するな。

1. **全指摘を再読**: レビュワーの指摘を1件ずつ読み直し、**各指摘が何を要求しているか**を一言で要約する。曖昧な指摘があれば人間に確認。

2. **現在の状態を確認**:
   ```bash
   git status
   git diff  # 無関係な変更が混入していないか確認
   ```
   **修正前に full test suite を再実行しない。** 直前のラウンドで緑を確認済みのHEADに対する
   再実行は、同じ結果を出すためだけに時間とトークンを使う。以下のいずれかに該当するときだけ、
   `LINT_CMD` / `TEST_CMD` を実行して baseline を取る:

   - rebase した
   - HEADが外部で変わった（自分以外のプッシュがある）
   - baseline が緑だったか分からない
   - 指摘が既存の失敗と絡んでおり、切り分けが必要

### 大きい出力を文脈へ流し込まない

修正中も文脈は積もる（根拠: DOC-2610142335）。ファイルは `cat` / `sed -n` で丸ごと読まず、
`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む。約100行・5,000字を超えそうな出力
（テスト・ログ・`git diff` など）は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る。

### Step 1: 修正

1. GitHubから未解決の全指摘を収集（インラインコメント・レビュー本文・会話コメント・未解決スレッド）。
2. 各指摘に対して:
   - **妥当なら修正**: コードに修正を実装。
   - **修正済み**: 修正を確認し返信に記載。
   - **異議あり**: GitHub上で技術的理由を述べて再考を依頼。
   - **人間の判断が必要**: 停止してユーザーに尋ねる。
3. 全修正後、**毎件の指摘が本当に直っているか自己検証**してからコミットする:

   a. **指摘と修正を1件ずつ突合**: 各指摘について「何を変えたか」「なぜそれが修正になっているか」を確認。
   b. **lint + test を実行**（設定されている場合）。同一HEADで full suite を何度も回さないため、
      次の順序を守る:

      1. 修正に関係する **targeted test だけ**を実行する（変更したファイルに対応するテスト、
         該当ディレクトリのみ、など）。`LINT_CMD` も変更ファイルに絞れるなら絞る
      2. 修正する
      3. 同じ targeted test で確認する
      4. **full suite はコミット時に1回だけ。** pre-commitフックが full suite を走らせる
         リポジトリでは、フックに任せて手動での事前実行を重ねない。フックが無い、または
         full suite を走らせないリポジトリでのみ、コミット直前に1回 `TEST_CMD` を実行する
      5. その full suite の結果（コマンドと examples / failures 数）は、コミット後の
         **HEAD SHA を明記して** Phase 6 のサマリーコメントに記録する。レビュワーはこれを
         「現HEADに対する full-suite 証拠」として再利用し、同じ suite を重複実行しない。
         SHA を書かないと証拠として使えず、レビュワー側で full suite が回り直す

      targeted と full を設定で分けられない場合、無理に設定機構を足さない。
      「修正中は targeted、コミット時に full」という運用だけ守れば十分である。
   c. **無関係変更の混入チェック**: `git diff` で自分が変更した全行を目視。レビュー指摘と無関係な変更が混ざっていないか確認。
   d. **対応漏れのセルフチェック**: 全指摘リストを見ながら、1件も漏らさず対応したか確認。**1件でも対応が曖昧ならコミットする前に修正する。**

   この自己検証で1件でも引っかかったら、修正して再チェック。**「たぶん大丈夫」でコミットしない。**

4. テストやlintが失敗したら修正する。通過させるためにテストを消す・無効化する・弱めるな。
5. 説明的なメッセージでコミット:

```bash
git add -A
git commit -m "fix: <修正内容の要約>

<自分の Co-Authored-By トレーラ>"
```

`Co-Authored-By` には、**この修正を実際に書いているエージェント自身**を書く。
自分が何であるかを他のエージェントの名前で騙らない。リポジトリやエージェントの規約で
トレーラの書式が決まっている場合はそれに従い、決まっていなければトレーラを省略してよい
（例: Claude Code なら `Co-Authored-By: Claude <noreply@anthropic.com>`）。

6. 通常プッシュ（force push禁止）:

```bash
git push origin HEAD
```

工程計測:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.end --phase fix --source pr-review-loop --round "$ROUND" || true
```

## Phase 6: 返信と再依頼

工程計測:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.start --phase reply --source pr-review-loop --round "$ROUND" || true
```

1. 各指摘にGitHub上で `{{REPLY_MARKER}}` で返信。各返信にコミットSHAを含める。
   - **返信は十分な詳細さで書く。** どのファイルの何行目をどう修正したか、検証コマンドとその結果を記載する。
   - 「対応しました」だけの一行返信は禁止。読んだ人がcommitを見に行かなくても理解できる内容にする。
   - レビュワーへの再依頼プロンプトは短くてよいが、**GitHubのPRコメントは丁寧に書く**。この2つを混同しない。
2. 全返信後、PRレベルのサマリーコメントで全指摘の対応状況を個別に列挙し、テスト結果も記載する。
   - **テスト結果は「対象HEAD SHA + 実行コマンド + 結果（examples / failures 数）」の形で書く。**
     full suite を pre-commit フックが実行した場合は、その旨とSHAを書く。レビュワーはこれを
     現HEADの full-suite 証拠として再利用するため、SHA の明記を省略しない。
   - **`--no-verify` でフックを迂回した場合は、その事実を必ず書く。** 書かないと、レビュワーは
     フックが走ったものとして full suite の再実行を省き、誰もテストしていない HEAD が承認される。
   - 修正が**コメント・docs のみ**（runtime behavior に影響しない）だと考える場合は、その旨を
     書いてよい。ただしこれは参考情報であり、**検証範囲を決めるのはレビュワー自身の分類である。**
     「docs のみと書いたのだから full suite は不要」と実装者側が決めつけない。
3. 新しいHEAD SHAを取得:

```bash
git rev-parse HEAD
```

工程計測:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.end --phase reply --source pr-review-loop --round "$ROUND" || true
command -v ocw-meter >/dev/null && ocw-meter event phase.start --phase rereview_request --source pr-review-loop --round "$ROUND" || true
```

4. 先に下の「レビュワーの会話を新しくする」を実行する。**送信は次の2経路のどちらか一方だけ**:
   - 起動し直せた → 送信はその節の手順4で済んでいる。**ここでの送信はしない**（二重送信になる）。
     手順5へ進む
   - 起動し直さなかった（`/exit` で消えなかった等）→ 以下の**最小限の**再レビュー依頼を送信する

   修正内容を列挙するな。レビュワーはGitHubのコメントを読む。
   どちらの経路でも、次の3つは必ず渡す（新しくした会話への依頼は節の手順4の文言に3つとも入っている。
   下のフォールバック文言を使うときは、`何ラウンド目か` を足す）:

   - **レビュー指示ファイルの絶対パス**（Phase 2 Step 1 で作った `$REVIEW_REQUEST`）。
     finding の判定基準・テスト不足の判定基準・ラウンド別のテスト実行方針は**このファイルにしか
     書かれていない**。レビュワーペインのエージェントは、ラウンドの合間に終了して Phase 2 Step 2 の
     手順で起動し直されることがあり、そのときの新しいレビュワーはこのファイルを一度も読んでいない。
     パスを渡さないと、基準を持たない素のエージェントとして nit を出し full suite を回すレビューに戻る。

     **送信前に存在を確認し、無ければ Phase 2 Step 1 の手順で作り直す。** `/tmp` は再起動で
     消え、環境によっては古いファイルが定期的に掃除される。レビューサイクルは複数ラウンドに
     わたり、`/autopilot` の無人運用では日をまたぐこともある。消えたまま送ると、レビュワーは
     読めないファイルを指されて基準を持たないまま進む:

     ```bash
     test -f "$REVIEW_REQUEST" && echo OK || echo "MISSING — Phase 2 Step 1 で再生成する"
     ```
   - **差分の起点となる前回レビュー対象SHA**（このラウンドの `$HEAD_SHA`）。レビュワーはこの
     区間の差分を分類してから検証範囲を決めるため、起点が無いと full suite を回し直すことになる
   - **何ラウンド目の再レビューか**（`$NEXT_ROUND` = `$ROUND` + 1。手順6で繰り上げる前の値に1を足す）。新しくしたレビュワーは
     過去のラウンドを知らず、「後続ラウンド（ラウンド2以降）の新規 finding 閾値」を効かせる根拠がこの数字だけになる

送信は Phase 2 Step 3 と同じく `umbrella-orchestrator/SKILL.md` §5「AI間送信手順
（二段構え）」に従う（自分が `SendMessage` を呼べる Claude Code セッションで、かつ
`$REVIEWER_AGENT` が `claude` で宛先セッションが解決できれば `SendMessage`、
どちらかを満たさなければ以下のフォールバック）:

```bash
herdr agent prompt "$REVIEWER_PANE" "PR #$PR 再レビュー依頼。レビュー指示: $REVIEW_REQUEST 全指摘に対応コメント書きました。前回レビュー対象: $HEAD_SHA → 現HEAD: $NEW_HEAD_SHA。ラウンド$NEXT_ROUND" --wait --timeout 10000
```

   フォールバック送信前に、Phase 2 Step 2 と同じ手順でレビュワーの状態を確認する。
   **ラウンドの合間にエージェントが終了していることがあり**（上の「レビュワーの会話を新しくする」で
   自分から終了させた場合に限らない）、そのまま送るとエージェントが
   いないペインへの送信になって依頼が届かない（`herdr agent prompt` は
   エージェントのいないペインには使えない）。`idle` / `done` を確認してから送ること。

5. 配信確認（Phase 2 Step 4と同様。`SendMessage` なら送信直前に控えた `agent_status`
   から変化したかを確認し、変化していなければ画面を目視。フォールバックなら
   返り値の読み方に従い、`timeout` / `stalled` でも再送しない）。

工程計測:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.end --phase rereview_request --source pr-review-loop --round "$ROUND" || true
```

6. 次のサイクルに入るため、`$ROUND` が指すサイクル数を1つ進める（次にPhase 1.5以降で `--round` を発行するときは、この進めた後の値をリテラルに使う）。あわせて、次のサイクルでは `$NEW_HEAD_SHA` が `$HEAD_SHA`（レビュー対象HEAD）になる。**この繰り上げは、次の手順7で compact する場合も先に済ませる**（復帰メモには繰り上げ後の値を書く）。
7. 「区切りでの自己 compact（実装側のみ）」の判断をする（閾値以下・使えないなら飛ばす）。
8. レビュワーの作業開始を待ち、Phase 3に戻る。

### レビュワーの会話を新しくする

再レビューのたびに、レビュワーのエージェントを終了して起動し直し、新しい会話で再レビューさせる（既定。ラウンド2以降の
頭だけで、初回のレビューには要らない）。同じ会話を続けると、ラウンドごとに積み上がった文脈が毎回の呼び出しの
cache read として払い直しになる。前ラウンドの指摘と返信は PR のコメントに残っているので、会話を捨てても失うものは少ない。
理由・費用の見込み・却下案は ADR DOC-2610200218 を参照。

1. レビュワーが `idle` / `done` であることを Step 2 の表で確かめる（`working` は待つ）
2. 終了させる。`/exit` は Claude Code / Codex / OpenCode が共通で持つ終了コマンドなので、種別を問わずこれを送る:

```bash
herdr pane send-text "$REVIEWER_PANE" "/exit"
herdr pane send-keys "$REVIEWER_PANE" Enter
```

   エージェントが消える（`herdr pane get` の `agent` が空になる）まで最大15秒、1秒間隔で見る:

```bash
for _ in $(seq 1 15); do
  AGENT=$(herdr pane get "$REVIEWER_PANE" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['pane'].get('agent') or '')")
  test -z "$AGENT" && break
  sleep 1
done
```

   **消えなかったら、作り直さず従来どおり同じ会話に再依頼する**（手順3をやらず、下の送信へ進む）。
   強制的に閉じない（`herdr pane close` はペインごと消え、`reviewer` ラベルが失われる）
3. 起動し直す。ペインはシェルだけになっているので、Phase 2 Step 2 の「`ocw agent` での起動」→
   「起動コマンドの決定」→ 主経路 / フォールバックの順で起動し、末尾の `$REVIEWER_AGENT` の読み直しまで行う
4. 新しいレビュワーへの最初の依頼は、**Step 3 と同じ文言で始め**、前回SHA・ラウンド・読み方を足す。
   文言の頭を変えない理由: ocw-meter や使用量の集計（`by_unit.py` など）は、会話の最初の発話の
   「PRレビューを実行してください」でレビュワーのセッションを見分けるので、「再レビュー依頼」で始めると
   実装のセッションに数えられる。送信は Step 3 と同じ二段構え:

```bash
herdr agent prompt "$REVIEWER_PANE" "以下を読んでPRレビューを実行してください。レビュー指示: $REVIEW_REQUEST — PR #$PR のラウンド$NEXT_ROUND（再レビュー）。前回レビュー対象: $HEAD_SHA → 現HEAD: $NEW_HEAD_SHA。全指摘に対応コメント書きました。前ラウンドの指摘と返信は、最新のレビュー1件と未解決のスレッドだけ読むこと" --wait --timeout 10000
```

   `$NEXT_ROUND` は `$ROUND` + 1 の整数をリテラルに埋める（このプロンプトは手順6で `$ROUND` を繰り上げる前に送る）。

起動し直せたとき、送信後の配信確認（手順5）も新しいレビュワーに対して行う。起動し直さなかったとき
（消えなかった・Herdr 外で動いている等）の再依頼は、上の手順4の従来のフォールバック文言で送る（二重に送らない）。

### アンチパターン: 冗長な再レビュープロンプト

修正内容とテスト結果を列挙した再レビュープロンプトを送るな。レビュワーはGitHubコメントを読む。長いプロンプトはトークンを浪費し本質を埋没させる。プロンプトは厳密に1行。

**ただし「1行」を理由に、レビュー指示ファイルのパスと前回レビュー対象SHAを削ってはいけない（ラウンド数も同様）。**
この3つは修正内容の列挙ではなく、レビュワーが判定基準と検証範囲を決めるための入力である。
削ると、レビュワーが基準を持たないまま全部を見直す方向へ戻る。

## Phase 7: 完了報告

承認に達したら:

1. 承認が現在のHEAD SHAを対象にしていることを確認。
2. ブロック中の未解決コメントがないことを確認。
3. **現HEADに対する full-suite 保証が存在することを確認。** 承認条件は「レビュワー自身が
   full suite を回した」ではなく、**「現HEADに対する信頼できる full-suite 成功結果が存在し、
   レビュワーがそれを確認した」**である。証拠の強さは、強い順に
   **CI green（独立した証拠）＞ 実装者がSHA付きで記録した結果 ＝ pre-commit フックによる実行
   （どちらも自己申告）**。自己申告を根拠にする場合は、SHAの一致に加えて `--no-verify` の申告が
   無いことを確認する。現HEADに対する結果が確認できない場合は完了報告に進まず、`TEST_CMD` を
   実行して結果を現HEADのSHA付きで記録する。
4. CIがパスしていることを確認。
5. **このスキルはどの PR もマージしない。** base が既定ブランチでも傘ブランチでも、承認は
   マージ許可ではない。マージは、既定ブランチ向きの PR なら人間、傘ブランチ向きの孫の PR なら
   傘の司令官（`umbrella-orchestrator` §2.4 の条件を満たしたとき）が行う。ここでは
   承認の事実を渡す相手を決めるために base を確認するだけである:
   - `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` でこのリポジトリの
     既定ブランチ名を取得し、`gh pr view <PR番号> --json baseRefName` の base と突合する。
     **`main` / `master` に固定しない。** リポジトリによって既定ブランチ名は異なり、
     `main`/`master`のどちらでもない名前（例: `trunk`）を既定ブランチにしているリポジトリもある
   - **base が既定ブランチ名と一致する** → 人間に「承認済み。マージしてください」と伝えて止まる
   - **一致しない**（傘ブランチ向きの孫の PR など）→ 起動時の指示（傘の司令官が孫へ渡す
     実装指示）で**司令官の Herdr ペインが渡されていれば**、完了報告（下記）を書き終えたあと、
     **最後の行動として**承認を司令官へ1回だけ報告して止まる。**渡されていなければ**、
     人間に「承認済み。司令官（または人間）がマージする」と伝えて止まる
   - 報告の本文は「孫N `<孫ブランチ名>` の PR #<番号> が HEAD <短縮SHA> で承認されました。
     マージをお願いします。」だけにする（承認の根拠は司令官が `gh` で自分で確かめる。
     本文に判定の詳細を書き足さない）。送り方は `umbrella-orchestrator/SKILL.md` §5
     「AI間送信手順（二段構え）」に従う。報告は1回だけで、送れなくても再送せず
     （司令官の巡回が拾う）、送れなかったことを人間に1行伝えて止まる
   - 承認後に PR へ変更を push しない（承認は無効になる）。司令官が「再レビューが要る」と
     返してきたら、その指示は新しいレビューサイクルの開始として扱う

ユーザーに報告:
- PR番号とURL
- 承認されたHEAD SHA
- レビューサイクル数
- 修正した主な指摘
- テスト結果
- CI状態
- 未解決の非ブロッキング項目
- 承認条件をどう満たしたか
- **マージの実施状況**: 「マージは実行していないこと」と、承認をだれ（人間／司令官のペイン）に
  渡す予定か（司令官への送信はこの報告を書き終えたあとなので、成否はここに書かない。
  送れなかったときは手順5のとおり人間に1行伝える）

工程計測:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.end --phase done --outcome success --source pr-review-loop --round "$ROUND" || true
```

## 安全制約

**禁止事項:**
- **どの PR も、承認されてもこのスキルはマージ（`git merge` / `gh pr merge`）を実行しない。base が既定ブランチでも傘ブランチでも同じである。** 承認＝マージ許可ではない。「既定ブランチ（多くの場合 `main` / `master`。判定方法は Phase 7 手順5）へのマージは人間だけが行う」という線引き（ADR DOC-2609121719、ルート `AGENTS.md`「最重要ルール」）に加え、傘ブランチ向きの孫の PR も、孫が勝手にマージして人間のフィードバックの機会を奪わないよう、司令官（`umbrella-orchestrator` §2.4 の条件を満たしたとき）か人間がマージする（ADR DOC-2610130212_commander-merges-grandchildren）。マージの要否は承認後に司令官・人間が決める。
- コミット履歴を破壊するマージ。GitHub Web UIのsquash mergeは全個別コミットメッセージをsquashコミット本文に連結する。よって各コミットに説明的なメッセージが必要。
- Force push (`git push --force`, `git reset --hard`)
- 破壊的削除（untracked files含む）
- テストをパスさせるための削除・無効化
- 無関係な変更の混入
- レビュワーに代わって承認マーカーを投稿
- 修正要求が残るレビューを承認扱い（マーカーに関わらず）
- 再レビュー不要とレビュワーが言ったからとスキップ（免除権限はない）
- 画面上だけのレビューを承認扱い（GitHub投稿が必須）
- 現HEADに対する full-suite 保証を確認しないままの完了報告（重複実行の削減は「誰が回すか」の話であって、「保証が要らない」ではない）
- ユーザー指示なしのlint/test設定の変更・抑制

**最重要: 承認後の変更は再レビュー必須。**
レビュワー承認後にPRに変更がプッシュされた場合、承認は無効。
新しいレビューサイクルを開始: 修正 → プッシュ → 返信 → 再レビュー依頼 → 再承認待ち。
最新HEADを対象とした新たな承認なしにマージしない。

**停止してユーザーに報告する条件:**
- 同じ実質的指摘が2回以上繰り返され進展がない
- 規約が相互に矛盾
- レビュー状態が判定不能
- レビュワーの要求がPR範囲を大幅に超える
- 破壊的操作・force push・秘密情報・権限変更が必要
- 外部サービス・環境障害でテスト不能
- レビュワーペインが一意に特定できない
- GitHubへの投稿・取得が不能
- 6サイクルを超えても承認されない
- HERDR_ENVが設定されていない

上記いずれかに該当して停止する場合、ユーザーへの報告と合わせて以下を実行する
（`--reason` には該当条件を表す短い識別子を入れる。理由の説明文そのものは記録しない）:

```bash
command -v ocw-meter >/dev/null && ocw-meter event human.intervention --reason "<該当条件の短い識別子>" --source pr-review-loop || true
```
