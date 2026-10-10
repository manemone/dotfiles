# ADR: repo-baseline に Ruby のリポジトリ向けの既定（RSpec・厳しめの RuboCop）を持たせる

## ステータス

確定（2026-10-11）

## 1. 背景

テストの道具や lint の設定は、持ち主が決めるべき規約である。ところが repo-baseline
テンプレートは Ruby のテストの道具も RuboCop の設定も持たず、撒いた先のリポジトリの AI が
その場で決めていた。その際の手がかりが、テンプレート自身が配る `tools/doc-id/test/`
（標準ライブラリの minitest）だったため、AI が「リポジトリのテストはこの形」と推測して
minitest を選び、持ち主に確認されないまま既定になった。RuboCop も既定ほぼそのままで
始めていた。

人間の確定事項（傘 `ruby-defaults` 計画書
[DOC-2610110211](../planning/DOC-2610110211_ruby-defaults_計画.md) 背景3）:

- Ruby のリポジトリのテストの既定は RSpec
- RuboCop は、持ち主の別のリポジトリで使っている設定相当の厳しさにする
- テンプレート・スキルは特定のリポジトリを参照しない。設定はテンプレート自身に持つ

本 ADR は孫1（テンプレート）が確定させた設計を記録する。孫2（`tools/doc-id/` を RuboCop に
通す）・孫3（スキル）は担当分の決着を節として追記する。

## 2. 決定

### 2.1 Ruby の既定は Ruby のリポジトリのときだけ生成する。質問は choice `language`

`copier.yml` に `language`（選択肢 `ruby` / `other`、既定 `other`）を足す。`lint_cmd` /
`test_cmd` の既定値がこの回答に依存するため、その2つより前に置く。

- 既定を `other` にする理由: Ruby 以外のリポジトリに撒く人が何も考えずに進めても、Ruby の物が
  1つも生成されないようにするため
- bool（`is_ruby`）にしなかった理由: Ruby 以外の言語の既定を将来足すとき、質問を作り直して
  既存の回答（`.copier-answers.yml`）との互換を気にせずに済むため。ただし選択肢を増やすことは
  この傘ではしない（先回り実装の禁止）

`language=ruby` のときだけ `.rubocop.yml` `.ruby-version` `.rspec` `Gemfile` `Rakefile`
`spec/spec_helper.rb` を生成する。出し分けは `copier.yml` の `_exclude` の条件で行う
（既存の `docs` `tools` `.github` と同じ作法）。

### 2.2 `.rubocop.yml` はテンプレート自身に持つ。特定のリポジトリを参照しない

持ち主の別のリポジトリの設定を手本にした（プラグインの performance・rspec、
`Layout/ClassStructure`、Style の追加〈宣言的・関数型の方針〉、Metrics と RSpec の上限）。
手本の値と方針のコメント（`NewCops: disable` の理由など）はそのまま写したが、設定ファイルは
自己完結にし、手本のファイルを読みに行かせる記述は置かない。

**写さなかったもの**: `tools/**/*` の丸ごと除外（AI が除外を足さない規則に反し、
`tools/doc-id/` を RuboCop に通すという孫2の方針とも衝突する）、手本固有のファイル名を指した
`Metrics/ClassLength` の除外、手本固有のクラスを理由にしたコメント。

**「厳しい」は Metrics の数字を小さくすることではない。** RuboCop の既定は MethodLength 10・
ClassLength 100 で、手本の値はむしろ緩い。厳しさの源泉はプラグインと `Layout/ClassStructure`
と Style の追加にあるので、Metrics を既定より小さくしない。

### 2.3 `TargetRubyVersion` は書かず、`.ruby-version` から推定させる

手本の固定値を書くと、撒いた先の Ruby とずれる。`.rubocop.yml` には書かず、RuboCop が
`.ruby-version` から推定するのに任せる（Ruby のバージョンの定義元が1つで済む）。推定元が
無いと RuboCop は古い版を仮定するため、`.ruby-version` を生成する。その値のために質問
`ruby_version`（`language=ruby` のときだけ、既定 `3.3`）を足した。CI の `ruby/setup-ruby` も
同じファイルを読む。`Gemfile` には `ruby` 指令を書かない（`.ruby-version` がパッチ無しの `3.3` のような
値のとき、bundler の厳密な版指定と食い違いうるため）。

### 2.4 lint・test の既定値とフックの `files:`

`language=ruby` のとき `lint_cmd` / `test_cmd` の既定値は `bundle exec rubocop` /
`bundle exec rake spec`（別の値を答えることは妨げない）。このとき両フックに `files:` を付ける
（Ruby のファイル `.rb` `.rake` `.gemspec` と、結果を左右する `Gemfile` `Gemfile.lock`
`Rakefile` `.rspec` `.ruby-version` `.rubocop*.yml`）。`Gemfile` がまだ無い段階や文書だけの
コミットで毎回走って落ちる、という既存の穴（フックが `pass_filenames: false` で常に走る）を
Ruby のときは塞ぐ。

`language=other` で `lint_cmd` / `test_cmd` を答えた場合の `files:` は、言語が分からず正しい
絞り込みを機械的に決められないため、この傘では現状の挙動（絞り込み無し）を変えない。
撒いた後に AI が足すべきこととしてスキルに書く（孫3）。

CI は `language=ruby` のときだけ、`pre-commit` の前に `ruby/setup-ruby`（`bundler-cache: true`）
を入れる。`language=other` の `ci.yml` は従来と同一。

### 2.5 既存ファイルは上書きしない（`_skip_if_exists`）

既に `Gemfile` 等のあるリポジトリに Ruby として撒いたとき、`copier.yml` の `_skip_if_exists`
で Ruby の6ファイルを上書きしない。copier の対話的な上書き確認に任せる案は、AI が非対話で
回すと扱いにくく、実物の `Gemfile` を潰す事故になりうるため採らなかった。代わりに、
スキップされたファイルは撒いた後に既存の内容とテンプレートの既定を人（AI）が突き合わせる。
この手順はスキル（孫3）に書く。

### 2.6 `tools/doc-id/` のテストは minitest のままにする

テンプレートは Ruby 以外のリポジトリにも撒かれる。`tools/doc-id/test/` は標準ライブラリの
minitest なので `Gemfile` の無いリポジトリでも `ruby tools/doc-id/test/doc_id_test.rb` で動く。
RSpec に替えると Ruby 以外のリポジトリに gem の依存が入る。直すべきは「道具のテストの形から
プロジェクトの規約を推測させない」ことであり、道具の形ではない（スキルと生成される
`AGENTS.md` への注記は孫3）。

## 3. 却下した案

- **Ruby の既定を言語を問わず常に生成する**: Ruby 以外のリポジトリに `Gemfile` 等が入る
- **`tools/doc-id/test/` を RSpec にする**: 2.6 の理由
- **`TargetRubyVersion` を固定値で書く**: 撒いた先の Ruby とずれる
- **`tools/**/*` を除外して `tools/doc-id/` の指摘を避ける**: 除外で通したことにしない
  （孫2が `tools/doc-id/` を通す）

## 4. 影響と既知の状態

- **この変更は、これから撒くリポジトリにだけ効く。** `copier update` は使えない
  （テンプレートが git リポジトリのルートでないため `_commit` が記録されない）ので、既存の
  リポジトリへは自動では届かない。後から取り込むなら、スキルの手順（孫3）で手動で持ってくる
- 孫1の時点で、`language=ruby` かつ `use_doc_id=true` では `bundle exec rubocop` が
  `tools/doc-id/` に **25 件**（3 ファイル: `lib/doc_id/scanner.rb`・`lib/doc_id/tool.rb`・
  `test/doc_id_test.rb`）の指摘を出す。内訳は Style/MethodCallWithArgsParentheses 12・
  Metrics/AbcSize 6・Lint/AmbiguousBlockAssociation 2・Metrics/MethodLength 2・
  Naming/MethodParameterName 2・Metrics/ClassLength 1。孫2が解消する

## 5. 孫2: `tools/doc-id/` を RuboCop に通した結果

孫1 が測った **25 件**（3 ファイル）を、抑制ディレクティブも除外も足さず、すべてリファクタ・
自動修正で解消した。残した指摘は無い。`tools/doc-id/` とテンプレート側の複製は同一に保っている。

| 指摘（件数） | 解消の仕方 |
|---|---|
| Style/MethodCallWithArgsParentheses（12） | `rubocop -a` の自動修正。結果は読んで確かめた。ただし `git_env.merge(...)` の複数行が行末の `\` 継続に変換された2箇所は読みにくいので、`dated_git_env` ヘルパーに置き換えた |
| Lint/AmbiguousBlockAssociation（2） | 自動修正（`assert_equal(1, ...count { })` と括る） |
| Naming/MethodParameterName（2） | `searchable_file?` / `extensionless_shebang_script?` の引数 `f` を `file` に改名 |
| Metrics/AbcSize（`git_tracked_files`） | git が使えないときの glob フォールバックを `glob_searchable_files` に切り出した。責務が「git の一覧を取る」と「git が無いときの代替を探す」の2つに分かれる箇所で、分割後のほうが読みやすい |
| Metrics/AbcSize・MethodLength・ClassLength（テスト `DocIdAssignTest`） | 繰り返しの `Open3.capture2 git_env, "git", ...` を `git` / `stage`（書く + add）/ `commit` / `assign_quietly` / `design_docs` ヘルパーに集約した。1つのシナリオが2段階の検証を抱えていたテスト（一方の採番がもう一方への参照を壊さないことと、後から採番したとき残っていた参照が書き換わること）は2本に分けた |

`ruby tools/doc-id/test/doc_id_test.rb` は修正前後とも全件通る（修正後 45 件。上記のテスト分割で
1 本増え、重複していた検証 2 つを統合したため assertion は 96 → 94）。テストが検証する
振る舞いは変えていない。

### 5.1 スモーク（`tests/template_smoke.sh`）には入れない

`tools/doc-id/` が RuboCop に通り続けることはスモークで守らない。理由: `bundle install` は
ネットワークを要し、撒き直しのたびに gem を取得するため `tests/template_smoke.sh`（現状は
ネットワークを `uvx copier` 以外に使わない）の実行時間と不安定さが見合わない。守りたい
regression は「将来 `tools/doc-id/` を直した人が RuboCop の違反を持ち込む」ことだが、これは
撒いた先のリポジトリの `pre-commit`（`bundle exec rubocop` フック。`files:` に `.rb` を含む）が
その場で捕まえるので、テンプレート側に二重のゲートは要らない。dotfiles 本体は Ruby の
リポジトリではないため、この確認は手動（本節の結果と PR 説明）で行った。

## 6. 孫3: スキルと生成される `AGENTS.md` への注記

根本原因（背景）は「道具のテストの形からプロジェクトの規約を推測した」ことなので、撒いた先の
AI が読む 2 箇所に、推測しない旨を書いた。

- スキル `repo-baseline`: 冒頭の原則に「持ち主が決めるべき規約を推測で決めない（読み取れず
  既定でも決まらないなら人間に確認する）」「`tools/doc-id/test/` が minitest なのは道具の都合」を
  追記。§2（既存導入の更新）に、Ruby の既定が既存のリポジトリへ自動では届かないことと手動で
  持ってくるファイルの一覧、§3 に既存の `Gemfile` 等があるときの突き合わせ、§4 に `language` /
  `ruby_version` / `lint_cmd` / `test_cmd` の答え方、§5 に `language=other` で `lint_cmd` /
  `test_cmd` を答えたときの `files:` の追記と Ruby のときの `bundle install` +
  `Gemfile.lock` のコミットを追加
- 生成される `AGENTS.md`（`use_doc_id` のとき）: `tools/doc-id/` のテストが minitest なのは
  道具の都合でありリポジトリのテストの規約ではない、と 1〜2 文書く。Ruby のときは既存の
  「テストは RSpec」の一文のすぐ後に置く
