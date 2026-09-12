# 計画書: lora-dataset-forge のレビュー方針を dotfiles のレビュースキルと repo-baseline テンプレへ取り込む

傘ブランチ: `review-policy-harvest`
ターゲット: `master`

## 概要

`~/projects/lora-dataset-forge`（以下 **forge**）で洗練されてきたコードレビュー方針のうち、
dotfiles 側にまだ無いものを、**レビュースキル（`skills/pr-review-loop/`）** と
**プロジェクト立ち上げ用テンプレ（`templates/repo-baseline/`）** の2系統へ取り込む。
ゴールは「新規リポジトリを `repo-baseline` で立ち上げた時点で方針が効いている」状態である。

扱う穴は4つ（詳細は背景4）。

1. **穴①** `repo-baseline` が `.claude/pr-review.yml` を生成していない（copier で既に聞いている
   lint/test の答えが pr-review-loop に渡らない）
2. **穴②** risk-based テスト方針が、実装者が普段読む `AGENTS.md` 層に無い
3. **穴③** linter 対応の作法が forge の方が一段細かい
4. **穴④** finding に failure scenario（どう壊れるかの具体的な連鎖）の記載が必須化されていない

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。既に削除済みであり
> 参照できない前提で書く）を material として司令官が起草したものである。** ブリーフに
> 書かれていた問題意識・決定事項・既存の穴・制約・スコープ外・検証ステップ・孫分割の
> 叩き台は、**すべて本計画書へ転記済み**であり、以降はこの計画書が正典である。
> ブリーフの主張は司令官が 2026-09-12 に実ファイルで再確認した（背景4・背景5）。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `review-policy-harvest-01-pr-review-yml` | repo-baseline テンプレに `.claude/pr-review.yml` を生成させる（穴①） | ✅ PR #81 マージ済 |
| 2 | `review-policy-harvest-02-template-test-policy` | テンプレの `AGENTS.md.jinja` に risk-based テスト方針と linter 対応の作法を入れる（穴②③・テンプレ側） | ✅ PR #82 マージ済 |
| 3 | `review-policy-harvest-03-dotfiles-test-policy` | dotfiles 本体の `AGENTS.md` に同じ方針を入れ、3箇所の乖離防止ルールを置く（穴②③・本体側） | 🔄 実装中 |
| 4 | `review-policy-harvest-04-failure-scenario` | pr-review-loop の finding gate に failure scenario の記載様式を足す（穴④） | ⬜ 待機中 |

## ワークスペースラベル

- 傘: `dotfiles :: レビュー方針の取り込み`
- 孫1: `dotfiles :: レビュー方針の取り込み 孫1 テンプレにpr-review.yml`
- 孫2: `dotfiles :: レビュー方針の取り込み 孫2 テンプレのテスト方針`
- 孫3: `dotfiles :: レビュー方針の取り込み 孫3 本体AGENTSのテスト方針`
- 孫4: `dotfiles :: レビュー方針の取り込み 孫4 findingの失敗シナリオ`

## 依存関係と実行順序

```
孫1 (テンプレ: .claude/pr-review.yml 生成)          ← 最も費用対効果が高い。新しい判断を人間に求めない
  ↓ 同じ templates/repo-baseline/ と tests/template_smoke.sh を触るので直列にする
孫2 (テンプレ: AGENTS.md.jinja にテスト方針 + linter 作法)
  ↓ 孫3 は孫2 がマージした文言を下敷きにして語彙を揃える
孫3 (本体: dotfiles AGENTS.md にテスト方針 + linter 作法 + 乖離防止ルール)
  ↓ ファイルは重ならないが、傘の運用上 1本ずつ進める
孫4 (pr-review-loop: finding の failure scenario)
```

**直列。** ブリーフの叩き台は「二重管理をどう解くかの設計判断が他の孫の書き方に影響するので、
テスト方針の孫を先行させるか、少なくとも方針だけ先に決める」ことを勧めていた。**司令官は
その設計判断を本計画書の「設計判断」節（D1〜D5）で先に確定させた。** そのため孫の順序は
依存ではなく費用対効果と衝突回避で決めている。

- 孫1 と孫2 はどちらも `templates/repo-baseline/` と `tests/template_smoke.sh` を触る
  （孫1 は新規生成物の検証追加、孫2 は `AGENTS.md.jinja` の変更による既存検証の再実行）
- 孫3 は孫2 の文言（テンプレ版のテスト方針節）を下敷きにする。孫2 より先に走らせると、
  2つの表現を後から揃え直す手戻りが出る
- 孫4 は `skills/pr-review-loop/SKILL.md` の単独変更で閉じ、他の孫とファイルが重ならない。
  最後に置いているのは単に直列運用のためで、依存があるからではない

---

## 背景1: 人間の問題意識（逐語）

> いま ~/projects/lora-dataset-forge にあるコードレビュー方針がなかなか洗練されてきていて、ほかのプロジェクトを立ち上げる時もこの方針を踏襲したいんだが、現在 dotfiles にあるレビュースキルやプロジェクト作成時のAI化のためのテンプレに、この方針から取り込めるところあるかね？

この問いに対し、相談AIが forge と dotfiles の双方を読み比べて調査した結果が背景4である。
人間は調査結果を見たうえで `/umbrella-handoff` を起動した（＝傘ブランチで進めることに同意した）。

## 背景2: 人間が確定させた決定事項（覆さないこと）

- **取り込み先は2系統である。** 「dotfiles にあるレビュースキル」（`skills/pr-review-loop/`）と
  「プロジェクト作成時のAI化のためのテンプレ」（`templates/repo-baseline/`）。
  どちらか一方だけに寄せない
- **目的は「ほかのプロジェクトを立ち上げる時も踏襲できる」状態にすること。**
  dotfiles 自身が良くなるだけでは目的を満たさない。新規リポジトリを `repo-baseline` で
  立ち上げた時点で方針が効いていることがゴール
- **forge の方針を人間は「洗練されてきている」と評価している。** forge 側の方針を薄めたり
  再設計したりするのではなく、dotfiles 側へ取り込む方向である

## 背景3: 既に取り込み済みのもの（重複作業を避けるため明記する）

forge の「洗練されたレビュー方針」の中核は forge `AGENTS.md` の**テスト方針（risk-based）**
（forge `AGENTS.md` 118〜171行目「## テスト方針」節。forge のコミット
`5a7001a AGENTS.mdにrisk-basedなテスト方針を追加する (#176)`）である。
**これ自体は既に `skills/pr-review-loop/SKILL.md` へ移植済み。**

- `skills/pr-review-loop/SKILL.md` 202行目「## finding の判定基準（general finding qualification gate）」
- 同 269行目「## テストの判断基準（risk-based testing）」
- 同 329行目「## Phase 1.5: PR提出前の自己レビュー（必須）」
- 同 577行目「## テスト・lint 実行の方針（ラウンドごとに変える）」（A/B 分類、full-suite 証拠の
  強度序列 CI > 実装者の SHA 付き記録 = pre-commit フック）

PR作法（dotfiles `docs/design/DOC-2608020715_プルリクエストの作法.md` ↔
forge の `docs/design/` にある同名の「プルリクエストの作法」文書。forge 側の DOC-ID は
dotfiles の `doc-id verify` が切れ参照と見なすため、ここでは ID を書かない）も内容はほぼ同一で、
dotfiles 側の方が新しい（ブランチ構成節が `ai/` 接頭辞廃止・傘/孫の一般形に更新済み）。
**PR作法文書の取り込みは不要。**

## 背景4: 既存の穴

相談AIが実際にファイルを読んで確認した事実に、司令官の再確認結果（2026-09-12）を併記する。
行番号は本計画書作成時点（`master` = `84543ae`）のもの。

### 穴① `.claude/pr-review.yml` を repo-baseline テンプレが生成していない

- `skills/pr-review-loop/SKILL.md` 79〜155行目「Phase 0.5: プロジェクト設定の読み取り」は
  `.claude/pr-review.yml` を**最優先の情報源**として読む。無い場合は「リポジトリ構成からの
  自動検出」→「スキル内蔵のデフォルト値」に落ちる
- 読み取るキー: `lint_cmd` / `test_cmd` / `convention_docs` / `markers`（`approved` /
  `changes_requested` / `reply`）/ `reviewer_cmd`。**すべて省略可**で、省略したキーは
  自動検出またはデフォルトに落ちる（同 102行目のコメント「すべて省略可。省略時は自動検出
  またはデフォルト」）。`lint_cmd: null` / `test_cmd: null` は「スキップ」の意味になる
  （同 103〜104行目）。**省略と `null` は意味が違う**
- dotfiles 本体には `.claude/pr-review.yml` が存在する（内容は
  `lint_cmd: "bin/tests/lint.sh"` / `test_cmd: "python3 -m unittest discover -s bin/tests -v"`
  の2行のみ）
- **`templates/repo-baseline/template/` 配下には `.claude/` ディレクトリごと存在しない。**
  確認コマンド: `grep -rn "pr-review" templates/ skills/repo-baseline/` の結果は
  `skills/repo-baseline/SKILL.md:114`（pr-review-loop への言及）の1件のみ（司令官も同じ結果を確認）
- **`templates/repo-baseline/copier.yml` は既に `lint_cmd` と `test_cmd` を質問している**
  （14〜28行目）。しかしその値の流し先は `.pre-commit-config.yaml.jinja`（`repo: local` の
  `lint` / `test` フック。値は `| tojson` でクォートしている）と `AGENTS.md.jinja`
  （104〜113行目）だけで、`.claude/pr-review.yml` には渡っていない
- 結果: repo-baseline で撒いた新規リポジトリで `/pr-review-loop` を回すと、人間が答えた
  lint/test コマンドが使われず自動検出に落ち、生成した PR作法 doc も `convention_docs` として
  渡らず、マーカー（🤖✅ / 🤖🔍 / 🤖💬）も内蔵デフォルト頼りになる
- **相談AIの評価では、これが4つの穴のうち最も費用対効果が高い**（既に聞いている答えを
  流し込むだけで、新しい判断を人間に求めない）

### 穴② risk-based テスト方針が「AGENTS.md 層」に無い

- forge の強みは、この方針が**実装者が普段読む `AGENTS.md`** にあること
- dotfiles では `skills/pr-review-loop/SKILL.md` にしか無い。確認コマンド:
  `grep -rn "risk-based\|production asset\|機械的に増やし\|scenario 統合" --include="*.md" --include="*.jinja" .`
  → ヒットは `skills/pr-review-loop/SKILL.md` のみ（221・269・284・355・358・458・459行目）。
  dotfiles 本体の `AGENTS.md` にも `templates/repo-baseline/template/AGENTS.md.jinja` にも無い
  （司令官も同じ結果を確認）
- pr-review-loop の方針はレビュー依頼ファイル（`/tmp/pr-review-loop/<owner>-<repo>-<PR>.md`）へ
  貼られてレビュワーに渡るが、**実装者が実装中に読む導線が無い**
- forge の該当節（forge `AGENTS.md`「## テスト方針」）が持つ要素（司令官が原文を確認済み）:
  - **基本原則**: 「テストも保守対象の production asset であり、無料ではない。書いた分だけ
    読む・直す・実行する時間がかかる。**新しいコードや受け入れ条件の数に比例して機械的に
    テストを増やしてはいけない。**」「**最小限のテストで、意味のある behavior と現実的な
    regression risk を保護する。** テスト数・coverage率・spec LOC そのものは目標値ではない。」
  - **必須性の判断**（対象×方針の表）:

    | 対象 | 方針 |
    |---|---|
    | 実バグの修正 | そのバグを再現する regression test を必ず追加する |
    | destructive / resume / integrity 系（forge では `raw/` 保護、削除・上書き・移動、archive/restore、hardlink、state recovery） | 厚くテストする |
    | 複雑な pure logic | 不変条件と重要な境界値をテストする |
    | public CLI / API / 永続化フォーマット | 外部contractをテストする |
    | config / glue | authoritative な層を中心にテストする |
    | trivial delegation / private helper | 専用 spec 不要をデフォルトとする |

    表の後に「edge case は『思いついたから全部』ではなく、**発生可能性 × 影響度 × 既存coverage**
    で追加要否を判断する。コード上で安全に処理されていて低リスクなら、専用 spec は要らない。
    **壊れないことを確認するのと、専用テストを足すのは別の判断である。**」
  - **重複防止**: 「新しい spec を追加する前に、必ず既存 spec を確認する。」「既存テストが同じ
    regression を検出できるなら、新しい example を追加しない」「共通処理へ責務を集約した場合、
    その性質は**共通層で authoritative にテストする**。上位 consumer すべてで同じ性質を
    再テストしない。必要なら代表的な integration を1本だけ置く」「下位レイヤーで保証済みの
    性質を、上位 caller から再確認しない」
  - **scenario 統合**: 「複数の受け入れ条件を1つの scenario で検証してよい。**受け入れ条件と
    test example は1対1対応ではない。**」「実質的に同じ契約を別 example に分割しない。
    たとえば『長い文字列が全文出力される』と『`...` が出力されない』は、どちらも『truncate
    されない』という1つの behavior なので、1つの example で検証してよい。」
  - **テスト追加時の問い**: 「> このテストが存在しなかった場合、どんな現実的な regression を
    逃すのか？」「明確に答えられず、既存テストでも足りるなら追加しない。」
- 注意: pr-review-loop 側と AGENTS.md 側で**同じ基準が二重管理になる**構造上の問題がある。
  → **司令官の設計判断は「設計判断 D1」に確定させた**

### 穴③ linter 対応の作法が forge の方が一段細かい

dotfiles の `AGENTS.md`「最重要ルール」と `templates/repo-baseline/template/AGENTS.md.jinja` の
「最重要ルール」（19〜22行目）は、どちらも「抑制ディレクティブを AI の判断で追加しない」
「構造を変えて指摘そのものを解消できる場合はそちらを優先する」まで持っている。
forge にあって**両方に無い**のは次の2点（forge `AGENTS.md`「## コミット前の必須ステップ」節。
司令官が原文を確認済み）。

- forge `AGENTS.md` 68行目: 「**rubocop 違反は原則リファクタで対応すること。** 長さ違反への
  対応では、機械的にクラスやメソッドを分割しない。分割後に責務・凝集性・読みやすさが
  改善する場合だけリファクタする。」
- forge `AGENTS.md` 71行目: 「**新規ファイルの追加時、または既存Rubyファイルを大幅変更した
  時点で、対象ファイル単位のRuboCopを実行する。** RuboCopの実行をコミット直前まで遅らせない。」

後者は「lint を前倒しする」という実装中の作法であり、レビューラウンドを減らす効果がある
（pr-review-loop の Phase 1.5 自己レビューと同じ方向の施策）。

### 穴④ finding に failure scenario が必須化されていない

- forge の `.claude/findings.json` は、記録されている5件すべてが
  `file` / `line` / `summary` / `failure_scenario` の4フィールドを持つ。`failure_scenario` は
  「どの入力・状態で、何が起き、ユーザーから何がどう見えるか」を具体的な連鎖として書いたもの。
  実例（原文は英語。司令官が訳した）:
  - 「`text_encoder_path: ''` を設定 → `unless te_path` は `''` が truthy なので通過 →
    `File.expand_path('')` が CWD を返す → `validate_path!` は CWD が存在するので通過 →
    sd-scripts が誤った TE パスを受け取り不可解なエラーで失敗 → ユーザーは生成が壊れた理由を
    辿れない」（correctness の例）
  - 「将来のリファクタで `@step_range =~` と `Regexp.last_match` の間にログ出力や別の正規表現
    呼び出しが入る → `last_match` が別のマッチを参照する → step range の境界がずれる →
    評価対象のチェックポイントを取り違える → 評価マトリクスが誤ったステップを網羅し結果が
    無効になる」（maintainability の例。「どんな将来変更で、どう壊れるか」の書き方になっている）
- 一方 `skills/pr-review-loop/SKILL.md` の finding gate（202〜267行目）は、**テスト不足の
  finding にだけ**「逃す regression（何が、どういう変更で壊れるか）」「なぜ既存 spec では
  捕まらないか」の記載を要求している（320〜327行目「### finding として書くときの作法」）。
  一般の blocking finding については 210〜224行目で「次のいずれかを**具体的に説明できる**もの」
  「maintainability を理由にする場合は『この状態だと、どんな将来変更で、どう壊れるのか』を
  具体的に説明できること」までで、**成果物としての記載様式は要求していない**
- ブリーフの注意: `.claude/findings.json` の形式自体は Claude Code の `/code-review` が
  `ReportFindings` ツールで出力する形式に由来する可能性が高く、forge 固有の発明とは言い切れない。
  取り込むべきは JSON ファイルの形式ではなく「finding には failure scenario を書かせる」という
  要求のほうである → **司令官の見極めは背景5.1 と「設計判断 D3」**

## 背景5: 司令官が追加で確認した事実（2026-09-12）

### 5.1 forge の `findings.json` は forge の「方針」ではなくツールの出力物である

- forge の `.gitignore` 38行目 `/.claude/*` により `.claude/findings.json` は **git 管理外**
  （`git check-ignore -v .claude/findings.json` → `.gitignore:38:/.claude/*`）。forge が
  リポジトリの規約として配っているものではない
- Claude Code の `ReportFindings` ツール（`/code-review` が使う）の finding は
  `file` / `line` / `summary` / `failure_scenario` を持つ（司令官が自分のツール定義で確認）。
  forge の `findings.json` の各要素と一致する
- したがってブリーフの推測どおり、**取り込むのは「failure scenario を書かせる」という要求
  だけ**である。`ReportFindings`・`/code-review`・`findings.json` は Claude Code 固有であり、
  AI 不問を掲げる pr-review-loop へ持ち込んではいけない（設計判断 D3）

### 5.2 `doc-id assign` がプレースホルダを置換するのは「git 追跡済み」の対象拡張子ファイルだけ

- `tools/doc-id/lib/doc_id/tool.rb` 15行目 `SEARCHABLE_EXTENSIONS = %w[.md .sh .yml .yaml .json]`
  → `.yml` は置換・検証の対象拡張子に入っている
- `tools/doc-id/lib/doc_id/scanner.rb` の `git_tracked_files` は `git ls-files --cached` で
  対象を列挙する（git リポジトリでない場合のみ glob にフォールバック）。つまり
  **git に追跡されていないファイルのプレースホルダは置換されない**
- 孫1 が `.claude/pr-review.yml` の `convention_docs` に PR作法 doc のプレースホルダパス
  （`docs/design/DOC-2609120054_プルリクエストの作法.md`）を書く場合、
  **その `.claude/pr-review.yml` が `.gitignore` で無視されていると、`doc-id assign` 後に
  切れたパスが残り、`doc-id verify` も検出しない**（追跡されていないので走査されない）

### 5.3 `.claude/` を丸ごと無視しているリポジトリは実在する

- forge の `.gitignore`: `/.claude/*` + `!/.claude/skills/` + `!/.claude/settings.json`
  （**`pr-review.yml` は否定されていない**。forge 自体も `.claude/pr-review.yml` を持っていない）
- dotfiles の `.gitignore`: `/.claude/*` + `!/.claude/pr-review.yml` + `!/.claude/settings.json`
  （過去の傘 DOC-2608020558 の判断4で否定行を足した経緯がある）
- **repo-baseline テンプレは `.gitignore` を生成しない。** 撒き先に既存の `.gitignore` があり
  `.claude/` を無視していれば、生成した `.claude/pr-review.yml` はコミットされず、5.2 の
  置換漏れも起きる

### 5.4 テンプレ内の古いパス

`templates/repo-baseline/copier.yml` 6行目と `templates/repo-baseline/template/AGENTS.md.jinja`
6行目が、判断ガイドの場所を `claude/skills/repo-baseline/SKILL.md` と書いている。
**`claude/skills/` はもう存在しない**（スキルは `skills/` 直下へ移った。ADR DOC-2608272128）。
現在のパスは `skills/repo-baseline/SKILL.md`。

### 5.5 dotfiles のテスト方針文書（DOC-2608020715-b）の一部が古い

`docs/design/DOC-2608020715-b_テスト方針.md` 65〜68行目は「`shellcheck` / `shfmt` および CI
（`.github/workflows/`）は、このリポジトリにまだ導入されていない」と書いているが、
現在は `.pre-commit-config.yaml` に `shellcheck`（`args: ["-x"]`）と `shfmt`
（`args: ["-i", "2", "-ci", "-d"]`）があり、`.github/workflows/ci.yml` も存在する。
この文書はデプロイ検証の方法（サンドボックス実行等）を定義するもので、
「テストを足すかどうかの判断」（risk-based）は扱っていない。

### 5.6 pr-review-loop 側の関連する既存の挙動

- `CONVENTION_DOCS` が未設定で `docs/` がある場合、Phase 1 手順3は「PR・コードレビュー・
  レビューコメント・再レビュー・承認・テスト・lintに言及しているdocを探して読む」
  （同 198行目）。つまり `convention_docs` を書かなくても PR作法 doc は**推測で**拾われうるが、
  明示すれば推測に頼らない
- 同 200行目「プロジェクト固有のdocがあればその規約を優先する」。**プロジェクト固有 > スキル
  内蔵**の向きは既に確立している（設計判断 D1 はこれと同じ向き）
- `{{FINDING_GATE}}` / `{{RISK_BASED_TESTING}}` はレビュー依頼ファイルへ**節の本文をそのまま
  貼る**運用（同 450〜461行目）。`{{FINDING_GATE}}` の範囲は「`レビューで気づいたことは、` の
  段落から、その節の末尾（`actual defect は後からでも出す。`）まで」と**本文の書き出しと
  末尾の文字列で指定**されている（同 456〜458行目）。節の末尾に文を足すと、この範囲指定が
  新しい末尾を指さなくなる

## 設計判断（司令官が確定。孫は覆さない）

変えたい孫は、実装前に司令官へ理由を添えて報告すること。

### D1: テスト方針の二重管理は「役割で分けて両方持つ」。片方を正典にして他方から参照させる形は取らない

同じ方針を次の3箇所が持つことになる。

| 場所 | 役割（視点） | 読む人 |
|---|---|---|
| `skills/pr-review-loop/SKILL.md`「テストの判断基準（risk-based testing）」 | **レビュー時の gate**: テスト不足を finding にしてよいか | レビュワー（依頼ファイルに貼られる）と自己レビュー中の実装者 |
| `templates/repo-baseline/template/AGENTS.md.jinja`「テスト方針」（孫2 で新設） | **実装時の方針**: テストを書くか・どこに書くか | 撒いた先のリポジトリの実装者 |
| dotfiles 本体 `AGENTS.md`「テスト方針」（孫3 で新設） | 同上（dotfiles 自身の実装者向け） | dotfiles で作業する AI |

参照で済ませない理由:

1. **テンプレは自己完結でなければならない**（dotfiles 本体のファイルを参照しない）。撒いた先の
   マシンに pr-review-loop が配られている保証も無い
2. **pr-review-loop のレビュワーはレビュー依頼ファイルしか読まない設計**であり、スキルは節の
   本文を貼っている（背景5.6）。AGENTS.md への参照に置き換えるとレビュワーに基準が届かない
3. **forge の強みは実装者の導線にあること**（背景4 穴②）。スキル側だけに置く現状がまさに穴

乖離を抑える手当て:

- **優先順位**: 対象リポジトリの `AGENTS.md`（プロジェクト固有）> スキル内蔵（デフォルト）。
  pr-review-loop の既存原則（背景5.6「プロジェクト固有のdocがあればその規約を優先する」）と同じ向き
- **語彙を揃える**: 3箇所とも次のキーフレーズを同じ字面で使う（言い換えない）
  - 「意味のある behavior と現実的な regression risk」
  - 「受け入れ条件と test example は1対1対応ではない」
  - 「発生可能性 × 影響度 × 既存coverage」
  - 「壊れないことを確認するのと、専用テストを足すのは別の判断」
  - 「このテストが存在しなかった場合、どんな現実的な regression を逃すのか？」
- **テンプレ版・本体版は forge の節構成（基本原則／必須性の判断／重複防止／scenario 統合／
  テスト追加時の問い）を踏襲する。** 薄めない（背景2）。言語固有の語（`spec`・RSpec 等）と
  forge 固有の対象（`raw/` 保護等）だけを一般化する
- **本体の `AGENTS.md`「実装時の注意」に、3箇所のどれかを変えたら残り2箇所も確認する旨の
  ルールを置く**（孫3）。dotfiles の開発ルールは本体の `AGENTS.md` が正典なので、ここが
  二重管理を監視する唯一の場所になる
- **pr-review-loop の risk 表（高/中/低）とテンプレ版の対象×方針の表は、表の形を揃えない。**
  視点が違う（gate と方針）ので形は違ってよい。ただし**内容が矛盾してはいけない**
  （例: テンプレ版の「実バグの修正 → regression test を必ず追加」は、スキル版の「高: 実際に
  発生したバグの修正 → regression test を積極的に要求してよい」と整合している）

### D2: `.claude/pr-review.yml` の各キーの扱い（孫1）

| キー | 扱い | 理由 |
|---|---|---|
| `lint_cmd` / `test_cmd` | 回答が空でなければ値を埋める（YAML のダブルクォート文字列にし、`\` と `"` だけをエスケープする。**`\| tojson` は使わない** — 下記「改訂」参照）。**空欄ならキー自体を出さない**（`null` にしない） | 空欄は「まだ決まっていない」であって「スキップと決めた」ではない。省略なら pr-review-loop の自動検出が効く。`null` はスキップという人間がしていない判断を焼き込む（背景4 穴①の「省略と `null` は意味が違う」） |
| `convention_docs` | `use_doc_id=true` のときだけ、生成される PR作法 doc のパスを1件入れる。`use_doc_id=false` なら出さない | PR作法 doc が pr-review-loop の `convention_docs` の役割（コメント形式・マーカー・再レビュー手順の情報源）に一致する。コーディング方針 doc は撒いた直後は TODO の骨組みで、その役割にも当たらないので入れない |
| `markers` | 3つとも既定値（`🤖✅ 承認` / `🤖🔍 レビュー指摘` / `🤖💬 対応報告`）を明示して書く | 生成される PR作法 doc のプレフィクスと同じ字面であることを、生成物の上で固定する（内蔵デフォルト頼りにしない） |
| `reviewer_cmd` | **copier の質問を足さない。** コメントアウトした行で書き方だけ示す | レビュワーにどのエージェントを使うかはリポジトリではなく人・マシンの都合。pr-review-loop は `$REVIEWER_AGENT` から自動で解決する。質問を足すと「既に聞いている答えを流し込むだけ」という穴①の費用対効果を崩す |

**改訂（2026-09-12、孫1 PR #81 のレビューを受けて）**: 当初は `lint_cmd` / `test_cmd` を
`.pre-commit-config.yaml.jinja` と同じく `| tojson` でクォートすると指定していたが、Jinja の
`tojson` は `&` `'` `<` `>` を HTML 向けに `\uXXXX` へエスケープする。YAML パーサで読むなら
元の値に戻るが、**pr-review-loop は `.claude/pr-review.yml` を `cat` で生テキストのまま読む**
（`skills/pr-review-loop/SKILL.md` Phase 0.5 Step 1）ため、`ruff check . && mypy .` のような
回答が `&&` 入りの壊れたコマンドとして渡る。そこで孫1 は `\` と `"` だけを
エスケープする YAML ダブルクォート文字列に変えた（`\` を先に置換する）。司令官が
コミット `1d1901e` を展開して検算し、`&&` `<` `>` `'` `\` `"` を含む回答で生テキストに
`\uXXXX` が混ざらず、`yaml.safe_load` で読み戻した値が入力と完全に一致することを確認して
承認した。D2 の意図（クォート崩れで別の値にならない）は変わらない。
`.pre-commit-config.yaml.jinja` は YAML パーサで読む pre-commit 向けなので `| tojson` のままでよい。

加えて、背景5.2・5.3 の問題（`.claude/` が無視されていると置換漏れ・コミット漏れが起きる）に
対して、**テンプレ側で `.gitignore` を生成しない**（撒き先の既存 `.gitignore` を上書きする
リスクの方が大きい）。代わりに `skills/repo-baseline/SKILL.md` の撒いた後チェックリストに
「`.claude/pr-review.yml` が git に追跡される状態か確認し、無視されていれば否定行を足す」を
入れる。

### D3: failure scenario は「要求」として取り込み、形式（JSON・ツール）は持ち込まない（孫4）

- 取り込むもの: **blocking finding には failure scenario（どの入力・状態で → 何が起き →
  利用者から何がどう見えるか、の具体的な連鎖）を書く。書けない指摘は finding ではない**
- 持ち込まないもの: `findings.json`・`ReportFindings`・`/code-review` など Claude Code 固有の
  形式やツール（背景5.1）。書く場所は従来どおり GitHub のレビュー本文・インラインコメント
- 既存の「テスト不足の finding の作法」（逃す regression／なぜ既存テストで捕まらないか）は、
  failure scenario をテスト不足の場合に具体化したものとして位置づけ、両者を矛盾させない

### D4: linter 対応の作法は「締める方向」だけ足す。抑制禁止ルールそのものは変えない（孫2・孫3）

- 足すのは forge の2点（背景4 穴③）: (a) 違反はリファクタで直すが、長さ系の指摘に対して
  機械的に分割しない（分割後に責務・凝集性・読みやすさが改善する場合だけ）、
  (b) 新規ファイル追加時・大幅変更時点で対象ファイル単位の lint を前倒しで実行する
- **既存の「抑制ディレクティブや設定の除外・閾値緩和を AI の判断で追加しない」は一字も
  緩めない。** 本傘は linter 対応の作法を扱うためこのルールの近くを編集するが、緩める方向の
  変更は人間の承認なしに行わない（AGENTS.md 最重要ルール）

### D5: テンプレに足す節は copier の質問で出し分けない（孫1・孫2）

`.claude/pr-review.yml`・テスト方針節・linter 作法は、**どの回答の組み合わせでも生成する**
（`convention_docs` のように中身が回答に依存する部分だけ出し分ける）。質問を増やすと
「立ち上げた時点で方針が効いている」（背景2）が回答次第で崩れる。

## 実測値

この傘について定量的な測定は行っていない（調査はファイルの読み比べと grep のみ）。

## 決定的な制約

- AGENTS.md「最重要ルール」: **人間の明示的指示がない限り `git merge` / `git pull` /
  `git reset --hard` / `git push --force` / `gh pr merge` を実行しない。例外はない。**
- AGENTS.md「最重要ルール」: **linter の抑制ディレクティブや設定の除外・閾値緩和を AI の判断で
  追加しない。** 本傘は「linter 対応の作法」を扱うため、このルールの近くを編集対象に含む。
  **ルールを緩める方向の変更は人間の承認なしに行わない**（設計判断 D4）
- AGENTS.md「最重要ルール」: **deploy スクリプトを実オペレーションで実行しない。**
  動作確認は `deploy-all.sh --dry-run` を基本とする
- AGENTS.md「3つの領域（混同しないこと）」: **`claude/CLAUDE.md`（配布物）は指示が無い限り
  編集しない。** `codex/deploy.sh` と `opencode/deploy.sh` もこのファイルを symlink 元に
  しているため影響が3エージェントへ及ぶ（ADR DOC-2609072334）
- `skills/` 配下は Claude Code だけでなく Codex・OpenCode にも同じ実体が配られる
  （ADR DOC-2608272128）。**pr-review-loop は「AI 不問」を明示的な設計方針として持っている**
  （`skills/pr-review-loop/SKILL.md` 10〜14行目）。特定エージェント前提の記述を持ち込まない
- `docs/` 配下に新規ファイルを追加する場合は `DOC-2609120054_<説明的ファイル名>.md` で
  作り `./tools/doc-id/doc-id assign` で採番する。地の文で文書に言及するときは DOC-ID を明示する
- `templates/repo-baseline/` は「`$HOME` へは配布せず、dotfiles 本体にも依存しない自己完結
  ディレクトリ」である（AGENTS.md ディレクトリ構成表）。**テンプレ側から dotfiles 本体の
  ファイルを参照する設計にしない**
- `templates/repo-baseline/copier.yml` の `_exclude` は copier の既定除外パターンを**置換**
  するため、パターンを足すときは既存の列挙を壊さない（同ファイル 65〜66行目にコメントあり）

## スコープ外

- **forge リポジトリ自体への変更。** 本傘は dotfiles 側だけを触る。forge への書き戻しが必要だと
  判断した場合も、この傘では行わず人間に報告する
- **`claude/CLAUDE.md`（配布物）の編集。** 上記「決定的な制約」参照
- **PR作法文書（DOC-2608020715）の改訂。** forge 側と内容がほぼ同一で、dotfiles 側の方が
  新しいことを確認済み。取り込むものが無い
- **`.opencode/commands/レビュー.md`（forge 側）の移植。** forge の MVP 期のプロジェクト固有
  コマンドであり（`raw/` を変更していないか、MVP中にVLM・WD14を混ぜていないか等）、汎用性が無い
- **`ocw-meter` による工程計測の拡張。** pr-review-loop には計測呼び出しが埋まっているが、
  本傘の問題意識とは別軸
- **dotfiles 本体の `.claude/pr-review.yml` の変更**（`convention_docs` 等の追加）。本傘の
  ゴールはテンプレ経由で新規リポジトリに効かせることであり、本体側は現状でも Phase 1 手順3の
  推測（背景5.6）で PR作法 doc が拾われる
- **`tools/doc-id/` の改修**（背景5.2 の「未追跡ファイルを置換しない」挙動の変更）。
  `tools/doc-id/` と `templates/repo-baseline/template/tools/doc-id/` の同一性チェックが絡み
  影響範囲が広い。孫1 が問題に当たった場合は運用（`.gitignore` の否定行）で解き、ツール改修が
  必要だと判断したら司令官へ報告する
- **テンプレによる `.gitignore` の生成**（設計判断 D2）

## 共通の必須検証（全孫が省略しない）

AGENTS.md「コミット前の必須ステップ」から、本傘に関係するものを転記する。

- `pre-commit run --all-files`（`trailing-whitespace` 等の基本チェック、`shellcheck` / `shfmt`、
  `./tools/doc-id/doc-id check` / `verify`、シェルスクリプト変更時の `./deploy-all.sh --dry-run`、
  `tools/doc-id/` と `templates/repo-baseline/template/tools/doc-id/` の同一性チェック）
- **`templates/repo-baseline/` 配下を変更した場合は `tests/template_smoke.sh`。**
  AGENTS.md は「**`templates/repo-baseline/` 配下のどのファイルを変更した場合も対象**であり、
  YAML を含むファイルに限らない」と明記している。孫1 は新規生成物を足すため、
  **新しい生成物に対する検証項目を `tests/template_smoke.sh` へ追加する必要があるかを必ず
  検討する**（孫1 のプロンプト参照）
- デプロイ関連のシェルスクリプトを変更した場合は `tests/deploy_smoke.sh`（`skills/` 配下の
  SKILL.md だけを変更する場合は不要だが、`skills/deploy.sh` や `shared/helpers.sh` に触れた
  場合は必要になる。**本傘ではどの孫も触らない想定**。触る設計になったら実装前に司令官へ報告）
- `bin/` 配下を変更した場合は `python3 -m unittest discover -s bin/tests -v`（本傘では触らない見込み）
- **AI はこれらのステップを省略しない。省略するのは人間が明示的に指示した場合に限る。**
- **実オペレーションの deploy（`deploy-all.sh` の素の実行）は禁止。**

### 司令官がマージ後に傘で行う検証（`/check`）

`umbrella-orchestrator` §3.3 の手順2に従い `.claude/pr-review.yml` の `lint_cmd` / `test_cmd`
（`bin/tests/lint.sh` / `python3 -m unittest discover -s bin/tests -v`）を実行する。
本傘は `bin/` を触らないためこれらは回帰確認に過ぎず、**本傘に効く検証として加えて
`pre-commit run --all-files` と、`templates/repo-baseline/` を変更した孫のマージ後は
`tests/template_smoke.sh` を実行する。**

---

## 孫1用プロンプト:

````markdown
# 孫1: repo-baseline テンプレに `.claude/pr-review.yml` を生成させる（穴①）

## 背景

計画書 `docs/planning/DOC-2609120054_review-policy-harvest_計画.md` を**必ず先に読むこと。**
特に次の節は本孫の要求仕様そのものである。

- 「背景2: 人間が確定させた決定事項」— ゴールは「新規リポジトリを repo-baseline で立ち上げた
  時点で方針が効いている」こと
- 「背景4」の穴① — 何が欠けていて、なぜ最も費用対効果が高いか
- 「背景5.2」「背景5.3」— `doc-id assign` が未追跡ファイルを置換しないこと、`.claude/` を
  丸ごと無視しているリポジトリが実在すること。**本孫が踏みうる落とし穴**
- 「背景5.4」— テンプレ内の古いパス `claude/skills/repo-baseline/SKILL.md`
- 「設計判断 D2」— 各キーの扱い（空欄はキー省略、`reviewer_cmd` は質問を足さない等）。**覆さない**
- 「設計判断 D5」— 質問で出し分けない

要点だけ再掲する。`skills/pr-review-loop/SKILL.md` の Phase 0.5 は `.claude/pr-review.yml` を
最優先で読むが、repo-baseline はこのファイルを生成しておらず、`copier.yml` が既に聞いている
`lint_cmd` / `test_cmd` の答えがレビューに届いていない。

## やること

### 1. `templates/repo-baseline/template/.claude/pr-review.yml.jinja` を新設する

設計判断 D2 の表どおりに書く。

- `lint_cmd` / `test_cmd`: 回答が空でなければ埋める。クォートは YAML のダブルクォート文字列で、
  `\` と `"` だけをエスケープする（**`| tojson` は使わない**。`&` `'` `<` `>` が `\uXXXX` に
  なり、生テキストで読む pr-review-loop に壊れたコマンドが渡る。計画書 設計判断 D2 の「改訂」参照。
  `tests/template_smoke.sh` の全部盛りパターンが `"` や `: ` を含む値を渡している）。
  **空欄ならキーを出さない。** 空欄のときに「未設定なら自動検出、スキップしたいなら `null`」
  と分かるコメントを残すかは判断してよい
- `convention_docs`: `use_doc_id=true` のときだけ、生成される PR作法 doc
  （`docs/design/DOC-2609120054_プルリクエストの作法.md`）を1件
- `markers`: 3つとも既定値を明示。**生成される PR作法 doc
  （`templates/repo-baseline/template/docs/design/DOC-2609120054_プルリクエストの作法.md.jinja`
  の「プレフィクスのフォーマット」節）と字面が一致すること**を自分で確かめる
- `reviewer_cmd`: 質問は足さない。コメントアウトした行で書き方だけ示す
- ファイル冒頭に「このファイルを読むのは pr-review-loop スキルであり、`.claude/` という名前
  だが Claude Code 専用の設定ではない（AI 不問）」旨のコメントを置く
  （`skills/pr-review-loop/SKILL.md` 87〜89行目と同じ趣旨）

Jinja の空白制御に注意すること。回答の組み合わせによって空行が二重になったり、キーが
0個のブロックが残ったりしやすい（`markers` は常に出るので、ファイルが空になることはない）。

### 2. `doc-id assign` 後も `convention_docs` が実在ファイルを指すことを確かめる

計画書 背景5.2 のとおり、`doc-id assign` は **git 追跡済み**の `.yml` だけを置換する。
使い捨てディレクトリ（`mktemp -d`）で次を実際に行い、結果を PR 説明に書くこと。

1. `uvx copier copy templates/repo-baseline <dir> --defaults` で展開する
2. `git init` → `git add -A` する
3. `./tools/doc-id/doc-id assign docs/design/DOC-2609120054_プルリクエストの作法.md`
4. `.claude/pr-review.yml` の `convention_docs` が採番後の実在ファイルを指していること、
   `./tools/doc-id/doc-id verify` が通ることを確認する

置換されない場合は、`tools/doc-id/` を改修せず（計画書「スコープ外」）、司令官へ報告すること。

これを `tests/template_smoke.sh` に自動テストとして組み込むかは判断してよい
（`git init` と ruby が要り、既存の combo より重い）。組み込まない場合は理由を PR 説明に書く。

### 3. `.claude/` が無視されているリポジトリへの手当て（`skills/repo-baseline/SKILL.md`）

計画書 設計判断 D2 のとおり、テンプレは `.gitignore` を生成しない。代わりに
`skills/repo-baseline/SKILL.md` を次のように直す。

- 「5. 撒いた後に埋めるべきもの（チェックリスト）」に、`.claude/pr-review.yml` が git に
  追跡される状態か（`git check-ignore -v .claude/pr-review.yml` で何も出ないか）を確認し、
  無視されていれば `.gitignore` に否定行（例: `!/.claude/pr-review.yml`）を足す項目を入れる。
  **`doc-id assign` より前に**やる必要があることも書く（未追跡だと置換されないため）
- 同チェックリストの `lint_cmd` / `test_cmd` を空欄のまま進めた場合の項目に、コマンドが
  決まったら `.claude/pr-review.yml` にも足すことを加える
- 「3. 既存ファイルとの衝突」に、撒き先に既に `.claude/pr-review.yml` がある場合の扱いを足す
  （既存の設定を上書きで失わない。既存の節と同じ趣旨）

### 4. 周辺の記述を追随させる

- `templates/repo-baseline/copier.yml` の `lint_cmd` / `test_cmd` の `help`（「pre-commit の
  local フックと AGENTS.md に埋め込みます」）に `.claude/pr-review.yml` を足す
- `templates/repo-baseline/README.md` の質問表（`lint_cmd` / `test_cmd` の「効果」列）と、
  生成物に言及している箇所
- dotfiles 本体 `AGENTS.md`「コミット前の必須ステップ」の `tests/template_smoke.sh` の説明文
  （何を検証するかを列挙している段落）。smoke に検証を足したらここも直す
- 計画書 背景5.4 の古いパス（`copier.yml` 6行目・`AGENTS.md.jinja` 6行目の
  `claude/skills/repo-baseline/SKILL.md`）は、本孫が触るファイルの中にあるので
  `skills/repo-baseline/SKILL.md` に直してよい（1行の事実修正）。**直すなら両方直す**
- 撒き先の `AGENTS.md.jinja` から `.claude/pr-review.yml` に言及するかは判断してよい
  （最小限に留める。テスト方針や linter の節は孫2 の担当なので触らない）

## スコープ外

- `templates/repo-baseline/template/AGENTS.md.jinja` へのテスト方針節・linter 作法の追加（孫2）
- dotfiles 本体の `.claude/pr-review.yml` の変更
- `tools/doc-id/` の改修
- テンプレによる `.gitignore` の生成
- copier への新しい質問の追加（`reviewer_cmd` 含む）
- `skills/pr-review-loop/SKILL.md` の変更

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- どの回答の組み合わせ（全部盛り・最小構成・既定値のみ）でも `.claude/pr-review.yml` が
  生成され、有効な YAML である
- 特殊文字を含む `lint_cmd` / `test_cmd` の回答が、`.claude/pr-review.yml` 上で**値として
  そのまま**読み戻せる（クォート崩れで別の値にならない）
- 空欄の `lint_cmd` / `test_cmd` はキーごと出ない（`null` や空文字列にならない）
- `use_doc_id=false` のとき `convention_docs` が出ず、`use_doc_id=true` のとき列挙された
  パスが生成物の中に実在する
- `doc-id assign` 後も `convention_docs` が実在ファイルを指す（上記「やること 2」。
  自動テストにしない場合は手動確認の結果を PR 説明に書く）
- 既存の `tests/template_smoke.sh` の検証（Markdown の崩れ・`_exclude` の効き等）が引き続き通る

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい（既存の `check_combo` の中に足すのが自然）。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 必須の検証コマンド

```bash
pre-commit run --all-files
tests/template_smoke.sh
```

## 注意

- **テンプレ側から dotfiles 本体のファイルを参照しない**（自己完結。計画書「決定的な制約」）
- `copier.yml` の `_exclude` に触る場合は既存の列挙を壊さない（置換される）
- 一時ディレクトリは `mktemp -d` で作る
- **人間の明示的指示がない限り `git merge` / `git pull` / `git reset --hard` /
  `git push --force` / `gh pr merge` を実行しない**（AGENTS.md 最重要ルール）
- **linter の抑制ディレクティブや `.pre-commit-config.yaml` の除外追加を自分の判断で
  入れない**（AGENTS.md 最重要ルール）
````

---

## 孫2用プロンプト:

````markdown
# 孫2: テンプレの `AGENTS.md.jinja` に risk-based テスト方針と linter 対応の作法を入れる（穴②③・テンプレ側）

## 背景

計画書 `docs/planning/DOC-2609120054_review-policy-harvest_計画.md` を**必ず先に読むこと。**
特に次の節は本孫の要求仕様そのものである。

- 「背景2: 人間が確定させた決定事項」— **forge の方針を薄めたり再設計したりしない**
- 「背景4」の穴② — forge の「テスト方針」節の原文（基本原則／必須性の判断の表／重複防止／
  scenario 統合／テスト追加時の問い）。**これが取り込む中身**
- 「背景4」の穴③ — forge の linter 作法2点の原文
- 「設計判断 D1」— 3箇所で持つ理由、揃えるキーフレーズ、優先順位。**覆さない**
- 「設計判断 D4」— 締める方向だけ。抑制禁止ルールは一字も緩めない
- 「設計判断 D5」— 質問で出し分けない

## やること

### 1. `## テスト方針` 節を新設する

`templates/repo-baseline/template/AGENTS.md.jinja` に、forge の節構成を踏襲した
「テスト方針」節を**無条件で**（どの回答でも出るように）足す。

- 中身は forge の原文（計画書 背景4 穴②）を土台にする。**薄めない。**
  変えてよいのは次だけ:
  - 言語固有の語（`spec`・RSpec・`example` の Ruby 的な用法など）を言語非依存の語にする。
    ただし `test example` のように pr-review-loop 側と共通の語は残す
  - forge 固有の対象（`raw/` 保護など）を一般的な書き方にする
  - forge 固有の文書への参照（`docs/design/DOC-2606281812_テスト方針.md` への言及）を落とす
- 計画書 設計判断 D1 のキーフレーズ5つを**同じ字面で**使う
- 「必須性の判断」の表の destructive / integrity 系の行に、撒き先のリポジトリ固有の高リスク
  領域を書き足す前提の `<!-- TODO: ... -->` を置くかは判断してよい（テンプレの既存の TODO
  コメントの作法に揃える）。置くなら `skills/repo-baseline/SKILL.md` の「5. 撒いた後に
  埋めるべきもの（チェックリスト）」にも対応する項目を足す
- 節の位置は判断してよい（「コミット前の必須ステップ」の前後が自然）

### 2. linter 対応の作法を足す

計画書 背景4 穴③の2点を、言語非依存の形で足す。

- (a) linter 違反は原則リファクタで直す。長さ系の指摘に対して機械的にクラス・関数・ファイルを
  分割しない。分割後に責務・凝集性・読みやすさが改善する場合だけリファクタする
- (b) 新規ファイルの追加時、または既存ファイルを大幅に変更した時点で、対象ファイル単位の
  lint を実行する。lint の実行をコミット直前まで遅らせない。テンプレは常に pre-commit を
  生成するので、`pre-commit run --files <path>` を使える形で書いてよい

**「最重要ルール」の抑制禁止の項（19〜22行目）は一字も緩めない**（設計判断 D4）。足す位置は
判断してよいが、`use_doc_id` 等の回答によって消える節（「コードの書き方」は `use_doc_id` の
ときしか出ない）に入れないこと（設計判断 D5）。

### 3. 周辺の追随

- `templates/repo-baseline/README.md` や `skills/repo-baseline/SKILL.md` に、生成される
  `AGENTS.md` の節を列挙・説明している箇所があれば追随する
- `skills/pr-review-loop/SKILL.md` は**触らない**。語彙はテンプレ側をスキル側・forge 側に
  合わせる（逆にスキル側を書き換えない）

## スコープ外

- dotfiles 本体の `AGENTS.md` の変更（孫3）
- `skills/pr-review-loop/SKILL.md` の変更（孫4 が別の節を触る）
- `.claude/pr-review.yml` 関連（孫1 でマージ済み）
- copier への新しい質問の追加
- forge リポジトリの変更

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- どの回答の組み合わせでも、生成された `AGENTS.md` にテスト方針節と linter 作法が含まれる
- 生成された `AGENTS.md` に Markdown の崩れ（行ゼロの表・見出し直前の空行欠落・二重空行・
  Jinja 構文の残骸）が無い。**新しい表を足すので、既存の `assert_markdown_hygiene` がそのまま
  効く**
- 既存の「最重要ルール」の抑制禁止の文言が変わっていない

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない
（節の存在チェックを smoke に足すかは、この方針自体に照らして判断し、理由を PR 説明に書く）。

## 必須の検証コマンド

```bash
pre-commit run --all-files
tests/template_smoke.sh
```

生成物は実物を読むこと（`uvx copier copy templates/repo-baseline "$(mktemp -d)" --defaults`
等で展開し、全部盛り・最小構成の両方で `AGENTS.md` を目視する）。

## 注意

- **テンプレ側から dotfiles 本体のファイルを参照しない**（自己完結）
- **linter の抑制ディレクティブや設定の除外・閾値緩和を足さない。抑制禁止ルールを緩めない**
- **人間の明示的指示がない限り `git merge` / `git pull` / `git reset --hard` /
  `git push --force` / `gh pr merge` を実行しない**（AGENTS.md 最重要ルール）
````

---

## 孫3用プロンプト:

````markdown
# 孫3: dotfiles 本体の `AGENTS.md` にテスト方針と linter 対応の作法を入れ、乖離防止ルールを置く（穴②③・本体側）

## 背景

計画書 `docs/planning/DOC-2609120054_review-policy-harvest_計画.md` を**必ず先に読むこと。**
特に次の節は本孫の要求仕様そのものである。

- 「背景4」の穴②③ — forge の原文
- 「背景5.5」— dotfiles のテスト方針文書（DOC-2608020715-b）の役割と、一部が古いこと
- 「設計判断 D1」— 3箇所で持つ理由と、**本体 `AGENTS.md` に乖離防止ルールを置くこと**
- 「設計判断 D4」— 締める方向だけ

**孫2（`review-policy-harvest-02-template-test-policy`）がテンプレの `AGENTS.md.jinja` に
テスト方針節と linter 作法を入れてマージ済みである。** 傘ブランチ上の
`templates/repo-baseline/template/AGENTS.md.jinja` を読み、**その文言を下敷きにすること**
（語彙を揃えるため。計画書 設計判断 D1）。孫2 の PR は
`gh pr list --search "review-policy-harvest-02" --state all` で見つかる。

## やること

### 1. 本体 `AGENTS.md` に `## テスト方針` 節を新設する

- 孫2 のテンプレ版と同じ節構成・同じキーフレーズで書く。dotfiles の実態に合わせてよいのは
  具体例だけ（例: 必須性の判断の表の destructive / integrity 系に、`$HOME` 側の symlink の
  張り替え・退避・世代 GC・uninstall の後片付けなど、dotfiles で実際に高リスクな処理を挙げる）
- **DOC-2608020715-b（`docs/design/DOC-2608020715-b_テスト方針.md`）との役割分担を明示する。**
  あちらは「デプロイ処理を実 `$HOME` を汚さずに検証する方法」、こちらは「テストを足すか
  どうかの判断」。本体 `AGENTS.md` の新節から DOC-2608020715-b を DOC-ID 付きで参照し、
  DOC-2608020715-b の冒頭にも新節への1行の参照を足す
- DOC-2608020715-b に手を入れるなら、計画書 背景5.5 の古い記述（65〜68行目「shellcheck /
  shfmt および CI はまだ導入されていない」）を事実に合わせて直してよい。直さない場合は
  PR 説明に既知の食い違いとして書く

### 2. linter 対応の作法を足す

計画書 背景4 穴③の2点を dotfiles に合わせて足す。

- (a) 違反はリファクタで直す。機械的に関数・ファイルを分割しない（分割後に責務・凝集性・
  読みやすさが改善する場合だけ）
- (b) 新規ファイルの追加時・大幅変更時点で対象ファイル単位の lint を実行し、コミット直前まで
  遅らせない。dotfiles では `pre-commit run --files <path>` が `.pre-commit-config.yaml` の
  引数（`shellcheck -x`・`shfmt -i 2 -ci -d`）込みで走るので、それを案内するのが素直

**「最重要ルール」の linter 抑制禁止の項は一字も緩めない**（設計判断 D4）。

### 3. 乖離防止ルールを「実装時の注意」に置く

計画書 設計判断 D1 の3箇所（`skills/pr-review-loop/SKILL.md`「テストの判断基準
（risk-based testing）」・`templates/repo-baseline/template/AGENTS.md.jinja`「テスト方針」・
本体 `AGENTS.md`「テスト方針」）について、**どれかを変えたら残り2箇所も確認する**旨を
本体 `AGENTS.md`「実装時の注意」に書く。3箇所が役割（gate と方針）の違いで形が違うこと、
優先順位（プロジェクト固有 > スキル内蔵）も一言添える。

## スコープ外

- `claude/CLAUDE.md`（配布物）の編集。**指示が無い限り触らない**
- `templates/repo-baseline/` 配下の変更（孫2 でマージ済み。文言に問題を見つけたら
  直さず司令官へ報告する）
- `skills/pr-review-loop/SKILL.md` の変更（孫4）
- dotfiles 本体の `.claude/pr-review.yml` の変更
- 既存テストの削減（方針を入れたからといって既存テストを間引かない）

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。ただし本孫の成果物は Markdown 文書のみであり、シェルコードを追加しない
場合は自動テストの追加が適さない。**その場合はテストを追加せず、手で確認した結果を PR 説明に
書くこと。**

- `pre-commit run --all-files` が通る（`doc-id check` / `verify` を含む）
- 本体 `AGENTS.md` の新節とテンプレ版で、計画書 設計判断 D1 のキーフレーズが同じ字面である
- 「最重要ルール」の抑制禁止の文言が変わっていない
- 文書への地の文の言及に DOC-ID が付いている

## 必須の検証コマンド

```bash
pre-commit run --all-files
```

## 注意

- `docs/` の文書に地の文で言及するときは DOC-ID を明示する（AGENTS.md）
- **linter の抑制ディレクティブや設定の除外・閾値緩和を足さない。抑制禁止ルールを緩めない**
- **人間の明示的指示がない限り `git merge` / `git pull` / `git reset --hard` /
  `git push --force` / `gh pr merge` を実行しない**（AGENTS.md 最重要ルール）
````

---

## 孫4用プロンプト:

````markdown
# 孫4: pr-review-loop の finding gate に failure scenario の記載様式を足す（穴④）

## 背景

計画書 `docs/planning/DOC-2609120054_review-policy-harvest_計画.md` を**必ず先に読むこと。**
特に次の節は本孫の要求仕様そのものである。

- 「背景4」の穴④ — forge の finding の実例（correctness と maintainability の2例）と、
  pr-review-loop の現状（テスト不足の finding にしか記載様式が無い）
- 「背景5.1」— forge の `findings.json` は gitignore された Claude Code `/code-review` の
  出力物であり、forge の方針そのものではないこと
- 「背景5.6」— `{{FINDING_GATE}}` の貼り付け範囲が**本文の書き出しと末尾の文字列**で
  指定されていること
- 「設計判断 D3」— 要求は取り込み、形式（JSON・ツール）は持ち込まない。**覆さない**

## やること

### 1. finding gate に「finding として書くときの作法（全 finding 共通）」を足す

`skills/pr-review-loop/SKILL.md`「## finding の判定基準（general finding qualification gate）」
節に、blocking finding の記載様式を足す。

- **各 blocking finding に failure scenario を書く**: どの入力・状態で → 何が起き →
  利用者（ユーザー・呼び出し側・将来の変更者）から何がどう見えるか、の具体的な連鎖
- maintainability を理由にする finding では「どんな将来変更で → どう壊れ → 何が見えるか」の
  連鎖になる（既存の 223〜224行目の要求を、記載様式として具体化したもの）
- **failure scenario を書けない指摘は finding ではない**（gate の入口と記載様式を結びつける）
- 例を載せるなら計画書 背景4 穴④の2例を土台にしてよいが、forge 固有の固有名詞
  （sd-scripts・`text_encoder_path` 等）を避けた一般形にする

既存の「### finding として書くときの作法」（テスト不足の finding 用。320〜327行目）とは
矛盾させない。テスト不足の「逃す regression」は failure scenario をテスト不足の場合に
具体化したものとして位置づけ、どちらを読んでも同じことを要求しているように整える
（見出し名が同じになるなら区別がつくように直す）。

### 2. `{{FINDING_GATE}}` の貼り付け範囲との整合を崩さない

計画書 背景5.6 のとおり、Phase 2 Step 1（450〜461行目）は `{{FINDING_GATE}}` の範囲を
「`レビューで気づいたことは、` の段落から、その節の末尾（`actual defect は後からでも出す。`）
まで」と文字列で指定している。

- 新しい作法を節の末尾に足すなら、この範囲指定の末尾の文字列を更新する
- 節の途中に足すなら範囲指定は変えなくてよいが、**レビュワーに貼られる範囲に新しい作法が
  入っていること**を確かめる
- どちらにしても、**実装者（Phase 1.5）とレビュワー（依頼ファイル）が同じ基準を使う**という
  既存の設計を崩さない

### 3. 関連箇所を追随させる（必要な範囲で）

- レビュー依頼テンプレートの「レビューガイドライン」（「具体的で行動可能な指摘のみを投稿」の
  あたり）で、各指摘に failure scenario を書くことが伝わるか確認する（`{{FINDING_GATE}}` で
  伝わるなら重ねて書かない）
- 承認・変更要求マーカーや見出しの書式は**変えない**（`skills/umbrella-orchestrator/SKILL.md`
  §2.4 がレビュー本文の1行目・`判定:` 行・`HEAD:` 行を機械的に読んでいる）

## スコープ外

- `findings.json` などファイルへの finding 出力、`ReportFindings`・`/code-review` など
  Claude Code 固有の仕組みの導入（設計判断 D3。**pr-review-loop は AI 不問**）
- 「テストの判断基準（risk-based testing）」節の中身の変更（語彙を揃える3箇所の1つであり、
  計画書 設計判断 D1 の乖離防止の対象。本孫では触らない）
- `ocw-meter` の工程計測の変更
- PR作法文書（DOC-2608020715）の改訂
- `templates/repo-baseline/` と dotfiles 本体 `AGENTS.md` の変更

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。ただし本孫の成果物は Markdown 文書のみであり、シェルコードを追加しない
場合は自動テストの追加が適さない。**その場合はテストを追加せず、手で確認した結果を PR 説明に
書くこと。**

- `pre-commit run --all-files` が通る
- Phase 2 Step 1 の範囲指定どおりに `{{FINDING_GATE}}` を切り出すと、新しい記載様式が
  含まれ、次の「テストの判断基準（risk-based testing）」節は巻き込まない
  （**実際に範囲指定の文字列で切り出して確かめ、結果を PR 説明に書く**）
- テスト不足の finding の作法と、全 finding 共通の作法が矛盾しない
- スキル本文が特定の AI エージェント固有の機能に依存していない

## 必須の検証コマンド

```bash
pre-commit run --all-files
```

## 注意

- **AI 不問を崩さない。** Claude Code 固有のツール名・コマンドを要求として書かない
- **人間の明示的指示がない限り `git merge` / `git pull` / `git reset --hard` /
  `git push --force` / `gh pr merge` を実行しない**（AGENTS.md 最重要ルール）
- **linter の抑制ディレクティブや設定の除外・閾値緩和を足さない**（AGENTS.md 最重要ルール）
````

---

## 実装完了後の流れ（各孫共通・必須）

実装が完了したら、以下を**自律的に**実行すること:

1. PR を作成する。**PR の向き先は必ず `review-policy-harvest` にすること。`master` には絶対に出さない。**
2. `/pr-review-loop` を起動する（PR がない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する

実装が終わったタイミングで止まらず、必ずここまでやりきること。

PR 説明の書き方は `docs/design/DOC-2608020715_プルリクエストの作法.md` に従うこと。

reviewer は完了すると `done` 状態で止まり、完了通知は来ない。push 後やレビュー依頼後に
待機して停止せず、`gh pr view` をポーリングしてレビューの有無を確認すること。

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `review-policy-harvest` から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。

司令官が `ocw -H --no-commander <孫ブランチ> review-policy-harvest` で作ったワークツリーでは、
孫ブランチは既に傘から切られている。実装開始前に次で確認するだけでよい:

```
git fetch origin
git branch --show-current
git merge-base --is-ancestor origin/review-policy-harvest HEAD && echo OK
```

自分でブランチを切る必要がある場合は次のようにする:

```
git fetch origin
git checkout -b <新しいブランチ名> origin/review-policy-harvest
```

**`git pull` / `git merge` を使わないこと**（AGENTS.md 最重要ルール）。`git fetch` +
`origin/review-policy-harvest` からの分岐で同じ結果になる。
