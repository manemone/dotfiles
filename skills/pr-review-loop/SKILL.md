---
name: pr-review-loop
description: "PRレビューサイクルを自動化。Herdrワークスペースのreviewerエージェントと連携してレビュー→修正→返信→再レビューを承認まで繰り返す。自動発動はしない。/pr-review-loop で明示的に起動。"
---

# PRレビューループ

Herdrワークスペース内の `reviewer` Claude Codeペインと連携してPRレビューサイクルを自動化する。

本スキルには工程計測用の `ocw-meter` 呼び出しが含まれる。すべて fail-open であり、
`ocw-meter` が存在しない環境でも本スキルは完全に動作する。
計測はレビュー判定に一切影響しない。

## 前提条件

Herdr内で実行されていること。確認:

```bash
test "${HERDR_ENV:-}" = 1
```

失敗したら「Herdr内ではありません」と報告して停止。

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

推測するな。neighborsやagent detectionや位置レイアウトを使うな。

```bash
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
```

`label` が `"reviewer"` と完全一致するペインを1つだけ探す。その `pane_id` を使う。

- 0件 → 停止。「'reviewer' ラベルのペインがありません。`herdr pane split --current --direction right --no-focus` で分割、`herdr pane rename <id> reviewer` でリネーム、claudeを起動してください」と伝える。
- 2件以上 → 停止。「'reviewer' ラベルのペインが複数あります。1つだけ残してリネームしてください」と伝える。

レビュワーペインIDを `$REVIEWER_PANE` に保存（例: `w4:p3`）。

## Phase 0.5: プロジェクト設定の読み取り

プロジェクト固有の設定を収集する。以下の優先順位で解決:

1. `.claude/pr-review.yml`（あれば最優先）
2. リポジトリ構成からの自動検出
3. スキル内蔵のデフォルト値

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

以降のフェーズでは、解決した設定値を以下の変数で参照する:

- `LINT_CMD` / `TEST_CMD` — コマンド（空または `null` ならスキップ）
- `APPROVED_MARKER` / `CHANGES_REQUESTED_MARKER` / `REPLY_MARKER` — マーカー文字列
- `CONVENTION_DOCS` — 規約docのパスリスト（空ならスキル内蔵規約のみ）

## Phase 1: コンテキスト収集

サイクル開始時に1回だけ実行:

**工程計測についての注記（このPhase以降で共通）**: `$ROUND` はシェル変数ではない。本スキルの各コードブロックは独立したBashツール呼び出しとして実行され、シェル変数は呼び出しをまたいで保持されない。`$ROUND` は「エージェントが追跡している現在のレビューサイクル数（1始まり。Phase 7の報告項目にある『レビューサイクル数』と同じ値、安全制約の『6サイクル』のカウントと同じ値）」を指す記法であり、`--round` を実行する際は、この時点のサイクル数をリテラルな整数値として埋めること。`$PR` / `$HEAD_SHA` / `$FINDINGS_COUNT` / `$URL` / `$OCW_RUN_ID` / `$REVIEW_REQUEST`（Phase 2 Step 1 で決めるレビュー指示ファイルの絶対パス）も同様に、直前に取得・保持した実際の値をその場でリテラルに埋め込む記法であり、新しいシェル変数を宣言する意味ではない。**特に `$REVIEW_REQUEST` は `herdr pane run` でレビュワーへ渡す文字列の中に入る。** レビュワーのペインは別プロセスでこちらのシェル変数を参照できないため、必ずリテラルな絶対パスとして埋めること。

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

これらは finding に昇格させない。**原則として GitHub へ修正要求として投稿もしない。**
ユーザーが明示的に「nit も全部出して」と依頼した場合だけ別扱いとしてよい。

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

### finding として書くときの作法

テスト不足を finding にする場合、レビューコメントに可能な限り以下を書く。

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

2. **レビュワーと同じ7次元でチェックする**（レビュー指示と同じ基準）:
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

レビュー指示をファイルに書き出し、短いコマンドでレビュワーに読ませる。**長文を pane run に詰め込むとペースト確認が入って2往復になるため絶対にやらない。**

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
  `レビューで気づいたことは、` の段落から、その節の末尾（`actual defect は後からでも出す。`）
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

## 規約優先順位
{{CONVENTION_DOCSがあれば}}: 指定されたdocがレビューコメント形式・投稿先・承認/変更要求マーカー・スレッド解決・再レビュー手順の情報源。docにない規約を自作しない。
{{CONVENTION_DOCSがなければ}}: このレビュー依頼に記載された規約を情報源とすること。記載のない規約を自作しない。

## レビューガイドライン
- {{CONVENTION_DOCSがあればそのパスを列挙、なければ「この依頼の規約」}}を最優先
- 以下の**全7次元を必ずチェック**。どれか1つでもスキップして後続ラウンドで発見するのは禁止:
  1. **正当性**: 仕様通り動くか。実装が計画書・issue・プロンプトの指示と一致しているか
  2. **エッジケース**: 異常系・境界値・空入力・nil・権限不足・並行実行
  3. **テスト**: 既存テストが壊れていないか。意味のある behavior と現実的な regression risk が保護されているか。**テスト追加を指摘する場合は、後述の「テスト不足の判定基準」の5項目を必ず通してから finding にする**
  4. **無関係変更**: diff に紛れ込んだ無関係な変更（lint設定・除外・フォーマット・他PRの残骸）がないか
  5. **後方互換性**: 既存の挙動を壊していないか。設定ファイルの既定値変更が波及していないか
  6. **保守性**: 命名・責務分離・コメント・エラー処理が適切か。**具体的な将来の壊れ方を説明できるものだけを finding にする**（後述の「finding の判定基準」）
  7. **スタイル**: lint違反がないか。**lint / formatter が問題にしない表面的なスタイルは finding ではない**（後述の「finding の判定基準」）
- **すべての指摘を、投稿前に「finding の判定基準」に通す。** 通らない pure nit は投稿しない
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

**「伏せる」と「finding ではないと分類する」を混同しない。** 「finding の判定基準」を通らない pure nit を投稿しないのは沈黙ではなく分類の結果である。逆に、実バグ・安全性・データ破壊・security・後方互換性の問題は、後続ラウンドで気づいたとしても必ず出す。テストを追加するかどうかは、加えて「テスト不足の判定基準」の入口判定も通す。**バグそのものを「テストの話だから」と黙るのは、この入口判定の対象外である。**

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

**すべての `herdr pane run` の前にこの手順を実行すること。`agent_status=None` を「Claude未起動」と思い込むな。**

```bash
STATUS=$(herdr pane get "$REVIEWER_PANE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result']['pane'].get('agent_status',''))")
```

| status | 意味 | 取るべき行動 |
|--------|------|-------------|
| `idle` | Claude起動中、待機状態 | Step 3へ |
| `done` | 前ラウンドの完了結果が未読のまま。待機状態であることは `idle` と同じ | Step 3へ |
| `working` | Claudeが処理中 | Phase 3a と同じループ（`--status done` を60秒刻みで待ち、`idle`/`blocked` も完了として拾う）で完了を待ってからStep 3へ。無人の背面ペインは完了しても `done` で止まり自動では `idle` にならないため、単発の `--status idle` 待ちは10分空転する |
| `blocked` | 判断待ちで停止 | ペイン出力を読んで可能なら回答。人手が必要ならユーザーに伝える |
| `unknown` / `None` または空 | 要確認。ClaudeがINSERTモードで動いている可能性がある | 以下の「None時の確認手順」を実行 |

**None時の確認手順:**

`agent_status=None` でも Claude は動いていることがある。必ず目視で確認する:

```bash
herdr pane read "$REVIEWER_PANE" --source detection --lines 3
```

- **INSERTモード表示**（`-- INSERT --`、`accept edits on`、`← for agents`）→ Claudeは起動済みでペースト確認待ち。`herdr pane send-keys "$REVIEWER_PANE" Enter` で確定させ、`idle` または `done` になってから Step 3 へ。
- **シェルプロンプト**（`$` や `❯` で終わる行、Claudeの応答がない）→ Claudeは終了している。`herdr pane run "$REVIEWER_PANE" "claude"` で起動し、`herdr wait agent-status "$REVIEWER_PANE" --status idle --timeout 30000` で起動完了を待つ。
- **Claudeの応答が表示されている**（`●` や `✻` で始まる行）→ 実は起動中。`herdr pane get` を再実行して状態を再確認。

### Step 3: 依頼を送信

Claude が `idle` または `done`（どちらも待機状態）であることを確認した上で、短いコマンドで依頼を送信する:

```bash
herdr pane run "$REVIEWER_PANE" "以下を読んでPRレビューを実行してください。レビュー指示: $REVIEW_REQUEST"
```

### Step 4: 配信確認

**herdr 自身の公式ドキュメント（`herdr` skill）は「`pane run` sends the text and
Enter together」（テキストとEnterをまとめて送る）としているが、実際にはこの
実装がプロンプトを打ち込むだけで Enter を送らないことがある。** ドキュメント通りに
動くと信じて確認を省略しないこと:

```bash
sleep 2
herdr pane get "$REVIEWER_PANE"
```

`agent_status` が `working` になっていれば送信成功。**`working` にならない
（`idle` または `done` のまま）なら `herdr pane send-keys "$REVIEWER_PANE" Enter`
を撃って再確認する。** `done` は Step 2 の表が「Step 3へ」に振る待機状態であり、
Enter が送られず `done` のまま止まっているケースも同じ手当てが要る。同じ本文を
`herdr pane run` で再送してはいけない（本文自体は届いており、再送するとプロンプト欄に
2重に積まれる）。それでも届いていなければ `herdr pane read "$REVIEWER_PANE"
--source detection --lines 3` で画面を確認する。

工程計測:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.end --phase review_request --source pr-review-loop --round "$ROUND" || true
```

## Phase 3: レビュワーの完了を待つ

工程計測:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.start --phase review_wait --source pr-review-loop --round "$ROUND" || true
```

### 作業開始を待つ

```bash
herdr wait agent-status "$REVIEWER_PANE" --status working --timeout 30000
```

タイムアウトしたら `herdr pane get "$REVIEWER_PANE"` と `herdr pane read "$REVIEWER_PANE" --source detection --lines 10` で確認。
本文が届いたまま Enter だけが送られていない状態（Step 4 と同一の症状）なら、
Step 4 と同じ手段で確定させる:

```bash
herdr pane send-keys "$REVIEWER_PANE" Enter
```

その後、再度workingを待つ。

### Phase 3a: 完了を待つ（イベント駆動）

`herdr wait` はイベント駆動で、状態遷移までブロックする。正しい対象状態を選ぶのが重要。

**`done` と `idle` は別の状態への遷移ではなく、同じ「完了」状態を「見られたか」で
呼び分けているだけ**（herdr 自身の公式ドキュメント、`herdr` skill）。ペインの
タブ／ワークスペースが背面（フォーカスされていない）のまま完了すると `done` になり、
**実際にそのタブをフォーカスするまで自動では `idle` に変わらない**。フォーカスされた
状態で完了すれば直接 `idle` になる。

`REVIEWER_PANE` は無人（誰もそのタブを見に行かない）で完了することが多いが、
**端末クライアントが繋がっていないヘッドレス実行（cron 等）では、globally active
tab にいるペインは完了時に直接 `idle` になる**（herdr 公式ドキュメントの記述。
`/autopilot` から回すときはこちらが標準的な条件）。`herdr wait agent-status` は
`--status` を1つしか取れず「`done` か `idle` のどちらか」を1回の待機では
表現できないため、**短く区切って両方を見るループにする**。`done` を待たずに
`idle` へ直行するケースでフルタイムアウトを浪費しないための工夫である:

```bash
# herdr wait は --status を1つしか取れないため、短く待って両方を見る
for _ in $(seq 1 10); do
  herdr wait agent-status "$REVIEWER_PANE" --status done --timeout 60000 && break
  STATUS=$(herdr pane get "$REVIEWER_PANE" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['pane'].get('agent_status',''))")
  case "$STATUS" in idle|blocked) break ;; esac
done
```

（合計タイムアウトは 60000ms × 10 = 600000ms＝10分。`done` に到達すれば即座に
`break`、`idle`/`blocked` になっていればそこで `break`、どちらでもなければ次の
60秒枠へ）

10分以内に `done` にも `idle` にも達しなかった場合の確認:

```bash
STATUS=$(herdr pane get "$REVIEWER_PANE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result']['pane'].get('agent_status',''))")
```

- `blocked` → 出力を読んで可能なら回答。人手が必要なら停止してユーザーに伝える。
- `working`（継続中）→ レビューに時間がかかっている。ペイン出力を読む。
- それ以外（`idle` を含む） → Phase 3bへ。

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

Co-Authored-By: Claude <noreply@anthropic.com>"
```

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

4. **最小限の**再レビュー依頼を送信。修正内容を列挙するな。レビュワーはGitHubのコメントを読む。
   ただし次の2つは必ず渡す:

   - **レビュー指示ファイルの絶対パス**（Phase 2 Step 1 で作った `$REVIEW_REQUEST`）。
     finding の判定基準・テスト不足の判定基準・ラウンド別のテスト実行方針は**このファイルにしか
     書かれていない**。レビュワーペインの Claude は、ラウンドの合間に終了して Phase 2 Step 2 の
     手順で起動し直されることがあり、そのときの新しいレビュワーはこのファイルを一度も読んでいない。
     パスを渡さないと、素の Claude として nit を出し full suite を回すレビューに戻る。

     **送信前に存在を確認し、無ければ Phase 2 Step 1 の手順で作り直す。** `/tmp` は再起動で
     消え、環境によっては古いファイルが定期的に掃除される。レビューサイクルは複数ラウンドに
     わたり、`/autopilot` の無人運用では日をまたぐこともある。消えたまま送ると、レビュワーは
     読めないファイルを指されて基準を持たないまま進む:

     ```bash
     test -f "$REVIEW_REQUEST" && echo OK || echo "MISSING — Phase 2 Step 1 で再生成する"
     ```
   - **差分の起点となる前回レビュー対象SHA**（このラウンドの `$HEAD_SHA`）。レビュワーはこの
     区間の差分を分類してから検証範囲を決めるため、起点が無いと full suite を回し直すことになる

```bash
herdr pane run "$REVIEWER_PANE" "PR #$PR 再レビュー依頼。レビュー指示: $REVIEW_REQUEST 全指摘に対応コメント書きました。前回レビュー対象: $HEAD_SHA → 現HEAD: $NEW_HEAD_SHA"
```

   送信前に、Phase 2 Step 2 と同じ手順でレビュワーの状態を確認する。**ラウンドの合間に
   Claude が終了していることがあり**、そのまま `herdr pane run` を撃つとプロンプトが
   シェルへ流れて依頼が届かない。`idle` / `done` を確認してから送ること。

5. 配信確認（Phase 2 Step 4と同様。`agent_status` が `working` にならなければ
   `herdr pane send-keys "$REVIEWER_PANE" Enter`）。

工程計測:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.end --phase rereview_request --source pr-review-loop --round "$ROUND" || true
```

6. レビュワーの作業開始を待ち、Phase 3に戻る。

次のサイクルに入るため、`$ROUND` が指すサイクル数を1つ進める（次にPhase 1.5以降で `--round` を発行するときは、この進めた後の値をリテラルに使う）。あわせて、次のサイクルでは `$NEW_HEAD_SHA` が `$HEAD_SHA`（レビュー対象HEAD）になる。

### アンチパターン: 冗長な再レビュープロンプト

修正内容とテスト結果を列挙した再レビュープロンプトを送るな。レビュワーはGitHubコメントを読む。長いプロンプトはトークンを浪費し本質を埋没させる。プロンプトは厳密に1行。

**ただし「1行」を理由に、レビュー指示ファイルのパスと前回レビュー対象SHAを削ってはいけない。**
この2つは修正内容の列挙ではなく、レビュワーが判定基準と検証範囲を決めるための入力である。
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

ユーザーに報告:
- PR番号とURL
- 承認されたHEAD SHA
- レビューサイクル数
- 修正した主な指摘
- テスト結果
- CI状態
- 未解決の非ブロッキング項目
- 承認条件をどう満たしたか
- マージは実行していないこと

工程計測:

```bash
command -v ocw-meter >/dev/null && ocw-meter event phase.end --phase done --outcome success --source pr-review-loop --round "$ROUND" || true
```

## 安全制約

**禁止事項:**
- **承認されても、人間の明示的指示がない限りマージ（`git merge` / `gh pr merge`）を絶対に実行しない。** これはこのスキルの最優先ルール。承認＝マージ許可ではない。Phase 7 で「マージは実行していないこと」を報告するのはこのルールに基づく。
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
