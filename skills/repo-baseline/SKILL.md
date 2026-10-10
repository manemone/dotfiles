---
name: repo-baseline
description: "既存リポジトリに AI エージェント支援基盤（AGENTS.md / CLAUDE.md / opencode.json / pre-commit / DOC-ID運用 / CI）を copier テンプレートで導入する。dotfiles の templates/repo-baseline/ を撒き、撒いた後の判断が要る部分を埋める。/repo-baseline で明示的に起動。"
---

# repo-baseline — AI エージェント支援基盤の導入

dotfiles の `templates/repo-baseline/` は copier テンプレートで、決定論的に配れるもの
（規約文書の骨組み・pre-commit 設定・DOC-ID ツール・CI）だけを機械的に生成する。
**このリポジトリ固有の判断が要る部分は生成されない。** それを埋めるのがこのスキルの役目である。

分業の原則: **copier が撒けるものは撒く。撒けないもの（判断）は、このスキルを読んだ AI が埋める。**
どちらの仕事かを混同しないこと。

**持ち主が決めるべき規約を、AI が推測で決めない。** テストの道具や lint の設定は
持ち主が決める規約である。既存の設定（`Gemfile`・`.rubocop.yml`・CI 等）から読み取れず、
テンプレートの既定（`language=ruby` のときの RSpec・RuboCop）でも決まらないなら、
推測で埋めずに人間に確認する。

**道具のテストの形から、プロジェクトの規約を推測しない。** テンプレートが配る
`tools/doc-id/test/` が minitest なのは、Ruby 以外のリポジトリでも `Gemfile` 無しで
`ruby tools/doc-id/test/doc_id_test.rb` が動くようにするための**道具の都合**であり、
撒いた先のリポジトリのテストの規約ではない。過去に、これに合わせて AI が確認なしで
minitest を選び、持ち主が後から RSpec に直したことがある（modeldex・pixidex）。
Ruby のリポジトリのテストの既定は RSpec である（ADR DOC-2610110216）。

## 1. 前提の確認

導入前に以下を確認する。いずれかが欠けている場合は、人間に確認するか対処してから進める。

- 対象リポジトリが git リポジトリであること（DOC-ID の採番が `git log` に依存し、
  pre-commit が git フックを使うため）
- `uv` がインストールされていること（`uv --version`）。無ければ
  `uv tool install copier pre-commit` から始める前に人間に導入を依頼する
- 既に `AGENTS.md` / `CLAUDE.md` / `.pre-commit-config.yaml` 等が存在するか確認する
  (`ls`)。存在する場合は「3. 既存ファイルとの衝突」を先に読むこと

## 2. 実行手順

### 新規導入

```bash
cd <対象リポジトリのルート>
uv tool run copier copy https://github.com/manemone/dotfiles.git .
```

元（`_src_path`）は dotfiles のリポジトリのルート（ルートの `copier.yml` が入口。ADR
DOC-2610110435）。**推奨は公開の HTTPS の git URL** で、どのマシンからでも撒ける・update できる。
ローカルの絶対パスは、そのマシンでしか update できない。URL から撒くとリモートの既定ブランチ
（`master`）の HEAD が撒かれるので、**マージ前のテンプレートの直しを試すときだけ**ローカルの
絶対パス（必要なら `--vcs-ref`）を使う。相対パスは update が失敗するので使わない。
`--trust` は要らない。

ローカルの絶対パスで試すときは、元の作業ツリーの変更を先にコミットする。未コミットの変更があると
copier は変更を一時クローンの中でコミットして撒き、`_commit` にどこにも存在しないコミットが記録されて、
撒いた先は update できなくなる。撒いたあと `_commit` が本物のコミットかを確かめ、試し用の撒き先は
本番に使わない。

copier が対話式に質問してくる。答え方の判断は「4. 質問への答え方」を参照。
`--defaults` を付けると全質問が既定値になるが、**AI が代わりに答える場合も既定値に
流されず、対象リポジトリの実態を見て個別に判断すること。**

**`.copier-answers.yml` の `_commit` と `_src_path` を消したり伏せたりしない。** update が使うので、
伏せると update できなくなる。手で編集もしない（copier が update のたびに書き直す）。

namecheck（個人名等の混入を検出する確認系）を持つリポジトリでは、`_src_path` の git URL にユーザー名が
入るため namecheck に当たる。**許可リスト（`tools/namecheck/allowlist.txt`）に `.copier-answers.yml` を
足す**（持ち主が許可済み）。行末の `namecheck:allow-line` では足りない: copier は update のたびに
`.copier-answers.yml` を書き直し、行末のマーカーが消えるため、ファイル単位の許可しか手が無い。
namecheck を持たないリポジトリでは何もしない。

### 既存導入の更新

`.copier-answers.yml` に `_commit` がある（= ルートの入口から撒いた）リポジトリは、`copier update` で
テンプレートの直しを取り込める。撒いた版（`_commit`）と今の版のテンプレートの差分が、撒いた先の
手元の変更との3者マージで取り込まれる。

```bash
cd <撒いた先のリポジトリのルート>
git status                      # 作業ツリーはきれいにしておく（未コミットの変更があると copier が拒否する）
git switch -c <update 用のブランチ>
uv tool run copier update --defaults --data <増えた質問>=<答え> ...   # 増えた質問が無ければ --data は不要（見つけ方は下記）
```

- `--trust` は要らない
- 版はタグではなく HEAD で扱われる（タグは打たない運用。copier が `0.0.0.postN.devM+<sha>` と表示する）。
  ただし `.copier-answers.yml` の `_commit` は `v20130702_00-N-g<sha>` という `git describe` 形式で
  記録される（先頭の `v20130702_00` は dotfiles にある 2013 年の古いタグ名で、版としては使われない）。
  版は `g` 以降の `<sha>` で一意に決まるので、update で進んだかは `<sha>` で見る。`_commit` を手で直さない
- **マージ前のテンプレートの直しを本番の撒き先に取り込まない。** `--vcs-ref <ブランチ>` やローカルの
  絶対パスで取り込むと、`_commit` にそのブランチだけにあるコミットが記録される。ブランチは squash
  マージで消えるため、そのコミットが辿れなくなり、次の update が落ちる。マージ前の直しを試すのは、
  試し用の複製の撒き先に限る。本番の撒き先は、直しがリモートの既定ブランチ（`master`）に入ってから、
  `--vcs-ref` 無しで update する。`_src_path` を書き換えない
- 質問は撒いた先の答えを既定にして聞き直される。**増えた質問（例: `language`・`ruby_version`）は、
  既定値に流されず、「4. 質問への答え方」に従って実態を見て答える。** たとえば自前で Ruby の設定を持つ
  リポジトリに `language=ruby` と答えると、テンプレートが生成しようとするファイルと既存のものがぶつかる
  - 端末の無いシェル（AI の Bash ツール等）では、copier は対話の質問ができず
    `Interactive session required` で終わる。そこでは `--defaults` を付け、**増えた質問はすべて
    `--data <名前>=<答え>` で明示する**（`--defaults` 単独で回すと、増えた質問が既定値
    〈`language` は `other`、`ruby_version` は `3.3`〉になる）。答え済みの質問は撒いた先の答えが引き継がれる
  - **増えた質問は、update の前に洗い出す。** 撒く元の `copier.yml`（`--vcs-ref` 無しなら
    リモートの既定ブランチのもの）の質問名と、撒いた先の `.copier-answers.yml` のキーを突き合わせ、
    answers に無い質問が増えた質問である。`--data` が漏れても copier は何も知らせず、既定値で
    answers に書く。そのため update のあと `git diff .copier-answers.yml` で足されたキーを確かめ、
    `--data` で渡していないキーがあれば、作業ツリーを戻して `--data` を足し、回し直す
  - 端末のある対話の実行なら、`--skip-answered` を付けると答え済みの質問を飛ばし、増えた質問だけが聞かれる
- `_skip_if_exists` のファイル（`.rubocop.yml`・`.ruby-version`・`.rspec`・`Gemfile`・`Rakefile`・
  `spec/spec_helper.rb`）は update のときも既存のものが残り、テンプレートの直しは届かない。
  必要なら差分を人間に見せ、手で取り込むか判断を仰ぐ

update が終わったら、結果の差分を **人間に見せてからコミットする**（勝手にコミットしない）。

#### 衝突の解き方

3者マージで、撒いた先とテンプレートの両方が同じ行を変えていた箇所には、ファイルの中に衝突の印が残る:

```text
<<<<<<< before updating
（撒いた先の手元の内容）
=======
（テンプレートの新しい内容）
>>>>>>> after updating
```

- `git grep -n -e '<<<<<<< before updating' -e '>>>>>>> after updating'` で全部探す。
  印が1つも残っていない状態にするまでコミットしない
- 片方を採るか、両方の意図を残すように手で書く。**撒いた先で意図して変えた内容（リポジトリ固有の
  規約・コマンド）を黙って捨てない。** どちらを採るか迷う箇所は、両方の内容を人間に見せて決めてもらう
- `.rej` ファイルが出た場合（`--conflict rej` を指定したとき等）は、中身を見て手で反映し、
  反映したら `.rej` を消す。コミットに残さない
- 解いたあとの確かめ: 印と `.rej` が残っていないこと、`pre-commit run --all-files` が通ること、
  `language=ruby` なら `bundle exec rubocop` と `bundle exec rake spec` が通ること、`.copier-answers.yml` の
  `git diff .copier-answers.yml` で足されたキーが、すべて自分で決めた答えであること（既定値で
  黙って埋まったものが無いこと）、`_commit` が新しい版に進んでいること、`_src_path` が伏せられていないこと

#### 既に撒いたリポジトリ（`_commit` が無い・`_src_path` が伏せてある）

ルートの入口ができる前に撒いたリポジトリは、`_commit` が無く、`_src_path` が伏せてあることがある。
このままでは update できない。**`_commit` に適当なコミットを手で書いても通らない**
（ルートの `copier.yml` が無い版を書くと、copier がリポジトリ全体をテンプレートとして撒いて落ちる）。
最初の1回の移行には専用の手順（橋渡しのコミット。ADR DOC-2610110435 §4）が要るので、移行の手順書に従う。
手順書はまだ無い（別の PR で `docs/reference/` に追加される）ので、見つけたら移行を自分で始めず、
人間に報告して指示を仰ぐ。

## 3. 既存ファイルとの衝突

`copier copy` は、生成先に同名ファイルが既にある場合、上書きするかどうかを1ファイルずつ聞いてくる。

- 既に `AGENTS.md` がある場合: 中身を比較し、テンプレートが生成する骨組みとの差分が
  大きいなら上書きせず、テンプレート側の節構成（最重要ルール・ディレクトリ構成・
  AI 支援ツールの設定・テスト方針・コミット前の必須ステップ 等）を参考に既存ファイルへ
  手動で節を足す方が安全。丸ごと上書きして既存のルールを失わないこと
- `.pre-commit-config.yaml` が既にある場合: 既存のフックを消さず、DOC-ID 関連フック
  （`use_doc_id` を選んだ場合）を追記する形にする
- 既に `.claude/pr-review.yml` がある場合: 上書きせず、既存の設定（`lint_cmd` /
  `test_cmd` / `convention_docs` / `markers` / `reviewer_cmd`）を確認したうえで、
  テンプレートが生成する内容との差分だけを手動で足す。既存の設定を上書きで失わないこと
- `language=ruby` で撒く先に既に `Gemfile`・`.rubocop.yml`・`.ruby-version`・`.rspec`・
  `Rakefile`・`spec/spec_helper.rb` がある場合: これらは**上書きされずスキップ**される
  （`_skip_if_exists`）。撒いた後に、既存の内容とテンプレートの既定を突き合わせる:
  `Gemfile` に rspec・rake・rubocop・`rubocop-performance`・`rubocop-rspec` があるか、
  `.rubocop.yml` が `.ruby-version` からの推定に任せているか、テストが RSpec か。
  差があっても勝手に合わせず、差分を人間に提示して判断を仰ぐ（既存のテストが minitest
  のときに RSpec へ移行するかは持ち主が決める）
- 持ち主が既存のテストの道具・lint の設定を残すと決めた場合（例: minitest のまま）:
  生成された `AGENTS.md` の Ruby の段落（テスト・lint の道具とコマンド）をその規約に
  書き換え、使わない生成物（`.rspec`・`spec/spec_helper.rb`。`.rubocop.yml` を採らないなら
  それも）を消し、`.claude/pr-review.yml` の `lint_cmd` / `test_cmd` と lint・test フックも
  合わせる。放置すると、生成物の「テストは RSpec」が持ち主の決めた規約を上書きする
- 判断に迷う場合は上書きせず、人間に差分を提示して判断を仰ぐ

## 4. 質問への答え方

`templates/repo-baseline/README.md` に質問の一覧と既定値がある。対象リポジトリを見て答える。

- `default_branch`: `git symbolic-ref refs/remotes/origin/HEAD` や `git branch` で確認する
- `language`: 対象リポジトリの主な言語で答える（`ruby` / `other`。既定は `other`）。
  Ruby のリポジトリ（`Gemfile` や `*.gemspec` がある等）なら `ruby`。`ruby` にすると
  RSpec の足場・`.rubocop.yml` が生成され、`lint_cmd` / `test_cmd` の既定値と CI の
  Ruby 準備が Ruby 用になる。Ruby 以外なら Ruby の物は何も生成されない。
  既定値に流されず、実態を見て答えること
- `ruby_version`（`language=ruby` のときだけ）: 既存の `.ruby-version`・`.tool-versions`・
  `mise.toml`・`Gemfile.lock` 等から探して答える。`.ruby-version` に書かれ、RuboCop の
  `TargetRubyVersion` の推定元と CI の `ruby/setup-ruby` の入力になる
- `lint_cmd` / `test_cmd`: `language=ruby` では既定値が `bundle exec rubocop` /
  `bundle exec rake spec` になる。既存の設定が別のコマンドを使っているなら、それに合わせて
  答える。それ以外の言語では、既存の `package.json` / `Rakefile` / `Makefile` / CI 設定等から
  実際に使われているコマンドを探して答える。**テンプレートの道具（`tools/doc-id/test/`）の
  テストの形から推測して決めない。** 既存の設定から読み取れず、テンプレートの既定でも
  決まらないなら、推測で埋めず人間に確認する。確認できず空欄のまま進める場合は、
  「5. 撒いた後に埋めるべきもの」で、実際のコマンドが定まった時点で埋める
  （基準は、そのリポジトリの既存の設定と持ち主の回答。道具の都合ではない）
- `use_doc_id`: 迷ったら true。複数人・複数 AI が並行して `docs/` に文書を書く前提があるなら
  特に有効
- `use_ci`: GitHub を使っていなければ false
- `has_long_running_commands`: 学習・大量データ処理・長時間バッチ等を扱うリポジトリなら true
- `use_adr` / `use_reference`: そのリポジトリで「一度確定した技術決定を記録する」文化や
  「運用中に繰り返し引くリファレンス文書」の需要があるかで判断する。無ければ false のままで良い
  （後から `docs/README.md` を手で拡張することもできる）

## 5. 撒いた後に埋めるべきもの（チェックリスト）

生成直後の状態は骨組みに過ぎない。以下を対象リポジトリの実態を調べたうえで埋める。

- [ ] `.claude/pr-review.yml` が git に追跡される状態か確認する
      （`git check-ignore -q .claude/pr-review.yml` を実行し、終了コードが1なら
      無視されていない。**`-v` は否定行にマッチした場合もその行を出力するため、
      「何も出なければよい」という判定はできない**）。既存の `.gitignore` が
      `.claude/` や `/.claude` のように**ディレクトリそのもの**を無視している場合、
      `!/.claude/pr-review.yml` のような否定行を足すだけでは効かない
      （gitignore の仕様上、無視された親ディレクトリの中身は否定行で戻せない）。
      その行を `/.claude/*` に書き換えたうえで否定行を足す。無視を解いたら
      `git add .claude/pr-review.yml` し、`git ls-files --error-unmatch
      .claude/pr-review.yml` でインデックスに載っていることを確かめる。
      **`doc-id assign` より前に**やること（未追跡だと `convention_docs` の
      参照が置換されず、切れたパスが残る）
- [ ] `AGENTS.md` の「概要」: このリポジトリが何をするものかを1〜3文で
- [ ] `AGENTS.md` の「ディレクトリ構成」: 主要ディレクトリの役割を表にする
- [ ] `AGENTS.md` の「最重要ルール」: このリポジトリ固有の破壊的操作があれば追記
      （本番環境への反映、課金の発生する外部 API 呼び出し 等）
- [ ] `AGENTS.md` の「テスト方針」〜「必須性の判断」: このリポジトリ固有の高リスク領域
      （本番データの破壊、外部サービスへの書き込み等）があれば destructive / resume /
      integrity 系の行に書き足す
- [ ] `AGENTS.md` の「コミット前の必須ステップ」: `lint_cmd` / `test_cmd` を空欄のまま
      進めた場合、実際のコマンドが定まった時点で埋める。同じコマンドを
      `.claude/pr-review.yml` の `lint_cmd` / `test_cmd` にも足すこと
- [ ] `language=other` で `lint_cmd` / `test_cmd` を答えた場合: `.pre-commit-config.yaml`
      の該当フックに `files:` を足す。テンプレートは言語が分からず絞り込みを機械的に
      決められないため、生成されるフックは `pass_filenames: false` で常に走る。
      `lint_cmd` / `test_cmd` が見るファイル（ソースと、結果を左右する設定ファイル）の
      変更でだけ走る正規表現にしないと、文書だけのコミットでも毎回走って、依存がまだ無い
      段階では落ち続ける（`language=ruby` のときは生成済み）
- [ ] `language=ruby` で撒いたとき: `bundle install` を実行し、生成された `Gemfile.lock` を
      コミットする。そのあと `bundle exec rubocop` と `bundle exec rake spec` が通ることを
      確かめる（example 0 件でも `rake spec` は成功する）。`use_ci` なら CI の
      `ruby/setup-ruby`（`bundler-cache`）が `Gemfile.lock` を使う
- [ ] `AGENTS.md` の「実装時の注意」: 新しいモジュールを足すときに追従すべき箇所があれば
- [ ] `docs/design/DOC-DOCID_PLACEHOLDER_コーディング方針.md`
      （`use_doc_id` を選んだ場合）: このリポジトリの主要言語のコーディング規約を書き下ろす。
      linter が機械的に検出できることは書かず、判定できない思想と既存慣行を書く
- [ ] `opencode.json` の `instructions` に、上記で書いた固有文書のパスを追加する
      （`doc-id assign` で採番した後の実パスを使うこと。存在しないパスを書くと
      opencode が起動時に失敗する）
- [ ] `.claude/settings.json` の `permissions.allow` に、このリポジトリで頻出する
      安全な読み取り・検証コマンドを列挙する（マシン固有の絶対パスを含めないこと）

生成直後に置かれている `docs/design/DOC-DOCID_PLACEHOLDER_*.md` は
`./tools/doc-id/doc-id assign <file>` で採番してから中身を埋めること。**`doc-id assign` の
前に `git add` してから採番する。**`doc-id assign` が参照を置換するのは `git ls-files
--cached` で列挙される追跡済みファイルだけであり、`copier copy` 直後の生成物は未追跡のため、
先に追跡させないと `.claude/pr-review.yml` の `convention_docs` 等の参照が置換されずに残る。

## 6. 傘ブランチ運用について

このスキルは傘ブランチの spawn・マージ検出・進捗管理を扱わない。それらは
**umbrella-orchestrator スキル**の領分であり、再実装しない。導入作業自体を
傘ブランチで進める場合は umbrella-orchestrator スキルに従うこと。

PR を作成しレビューを回す場合は **pr-review-loop スキル**に従うこと（Herdr 環境が前提）。
