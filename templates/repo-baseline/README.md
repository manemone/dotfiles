# repo-baseline テンプレート

AI エージェント（Claude Code / opencode 等）と協働開発するためのリポジトリ基盤を配布する
[copier](https://copier.readthedocs.io/) テンプレートです。

dotfiles（本リポジトリ）・lora-dataset-forge（LDF、社内の別リポジトリ）・master に統合された
ocw-meter 傘の3例を突き合わせ、汎用的な部分だけを抽出しています。詳細な経緯は、
dotfiles リポジトリ内の `docs/planning/DOC-2608020558_repo-baseline_計画.md`
を参照してください（このディレクトリを別リポジトリへ移動した場合、このリンク先は
存在しなくなります。経緯を知りたい場合のみ、移動元の dotfiles リポジトリを参照してください）。

## 自己完結

このディレクトリは dotfiles の他の部分（`shared/helpers.sh` 等）に一切依存しません。
ただし copier の設定ファイル `copier.yml` だけは、`copier update` を使えるようにするため
dotfiles リポジトリの**ルート**に置いてあります（`_subdirectory` でこのディレクトリの
`template/` を指す。経緯は
[ADR DOC-2610110435_copier-root-entry](../../docs/adr/DOC-2610110435_copier-root-entry.md)）。
このディレクトリを別リポジトリへ切り出すときは、ルートの `copier.yml` もそのリポジトリのルートへ
移し、`_subdirectory` を `template` に戻してください。

## 前提

- 展開先が git リポジトリであること（DOC-ID の採番が `git log` に依存し、pre-commit が git フックを使うため）
- [uv](https://docs.astral.sh/uv/) がインストールされていること
- 初回セットアップ時のみネットワーク（`copier copy` と `pre-commit install-hooks`）

`language=ruby` を選んだ場合のみ、展開後に Ruby と bundler（`bundle install`）が必要になります。

**要求しないもの**: Ruby 等の特定の言語ランタイム（`language=ruby` を選ばない限り。pre-commit の隔離環境が用意する）、
mise/rbenv 等のバージョンマネージャ、Docker、Claude Code であること、GitHub であること
（CI は `use_ci` で無効化できる）。

## 使い方: 新規展開

```bash
cd <展開先リポジトリのルート>
uv tool run copier copy https://github.com/manemone/dotfiles.git .
```

元（`_src_path`）はこのリポジトリのルート（git の URL を推奨。他のマシンでも update できる）。
URL から撒くとリモートの既定ブランチ（`master`）の HEAD が撒かれるので、マージ前の直しを試すときは
ローカルの絶対パス（必要なら `--vcs-ref`）を使います。相対パスは update が失敗するので使いません。
`.copier-answers.yml` の `_commit` / `_src_path` は update が使うので、消したり伏せたりしません。

質問に答えると、選んだ内容に応じて以下が生成されます。

| 質問 | 型 | 既定値 | 効果 |
|---|---|---|---|
| `default_branch` | 文字列 | `master` | プルリクエストの作法のブランチ構成節に埋め込む |
| `language` | 選択（`ruby` / `other`） | `other` | `ruby` を選ぶと Ruby の既定（下記）を生成し、`lint_cmd` / `test_cmd` の既定値と CI の Ruby 準備が Ruby 用になる。`other` なら Ruby の物は何も生成しない |
| `ruby_version` | 文字列 | `3.3` | `language=ruby` のときだけ質問。`.ruby-version` に書く（RuboCop の `TargetRubyVersion` の推定元、CI の `ruby/setup-ruby` の入力） |
| `lint_cmd` | 文字列 | `""`（`language=ruby` では `bundle exec rubocop`） | pre-commit の local フック・AGENTS.md・`.claude/pr-review.yml` に埋め込む lint コマンド。空欄なら生成しない |
| `test_cmd` | 文字列 | `""`（`language=ruby` では `bundle exec rake spec`） | 同上（test コマンド） |
| `use_doc_id` | bool | `true` | DOC-ID 運用一式（`docs/`・`tools/doc-id/`・関連 pre-commit フック）を生成するか |
| `use_ci` | bool | `true` | `.github/workflows/ci.yml` を生成するか |
| `has_long_running_commands` | bool | `false` | AGENTS.md にバックグラウンド実行 + ポーリングの規約節を追加するか |
| `use_adr` | bool | `false` | `docs/README.md` に adr/ フォルダの説明を含めるか（`use_doc_id` が true の場合のみ質問） |
| `use_reference` | bool | `false` | `docs/README.md` に reference/ フォルダの説明を含めるか（同上） |

### `language=ruby` のときだけ生成されるもの

| ファイル | 内容 |
|---|---|
| `.rubocop.yml` | プラグイン（performance・rspec）・`Layout/ClassStructure`・Style の追加などで厳しめにした RuboCop の設定。`NewCops: disable`。`TargetRubyVersion` は書かず `.ruby-version` からの推定に任せる |
| `.ruby-version` | `ruby_version` の回答 |
| `Gemfile` | rake・rspec・rubocop・rubocop-performance・rubocop-rspec |
| `.rspec` / `spec/spec_helper.rb` | RSpec の最小の足場。example 0 件でも `rake spec` は成功する |
| `Rakefile` | `spec` タスク（`default` も `spec`） |

加えて、Ruby のとき lint・test の pre-commit フックには `files:` が付き（Ruby のファイルと
`Gemfile` 等の設定ファイルを変更したときだけ走る。文書だけのコミットでは走らない）、
`ci.yml` には `pre-commit` の前に `ruby/setup-ruby`（`bundler-cache`）の手順が入ります。
`language=other` で `lint_cmd` / `test_cmd` を答えた場合は、従来どおり `files:` の絞り込みは付きません。

既に `.rubocop.yml` / `.ruby-version` / `.rspec` / `Gemfile` / `Rakefile` / `spec/spec_helper.rb` がある
リポジトリへ展開しても、これらは**上書きされず**そのまま残ります（`_skip_if_exists`）。
展開後に既存の内容とテンプレートの既定を突き合わせてください。

`use_doc_id=true` のとき、生成される `AGENTS.md` には、`tools/doc-id/` のテストが minitest なのは
道具の都合であり、そのリポジトリのテストの規約ではない旨の注記が入ります。

質問の回答に関わらず常に `.claude/pr-review.yml` を生成します。`skills/pr-review-loop/`
スキルが Phase 0.5 で最優先に読む設定ファイルで、`lint_cmd` / `test_cmd`（空欄なら省略）・
`markers`（既定値を明示）・`convention_docs`（`use_doc_id` 選択時のみ、生成される
PR作法 doc を1件）を埋めます。`.claude/` という名前ですが Claude Code 専用の設定ではなく、
どの AI エージェントから実行しても同じように読めます。

生成直後、まだ手を付けていない状態でやること:

```bash
# .claude/pr-review.yml が既存の .gitignore で無視されていないか確認する
# （git check-ignore -q の終了コードが1なら無視されていない。-v は否定行にマッチした
# 場合もその行を出力するため「何も出なければよい」という判定はできない）。
# .claude/ や /.claude のようにディレクトリそのものを無視している場合、
# !/.claude/pr-review.yml のような否定行を足すだけでは効かない（gitignore の仕様上、
# 無視された親ディレクトリの中身は否定行で戻せない）。その行を /.claude/* に
# 書き換えたうえで否定行を足すこと。doc-id assign より前にやる必要がある
# （未追跡だと convention_docs 等の参照が置換されず、切れたパスが残る）
git check-ignore -q .claude/pr-review.yml && echo "無視されています。.gitignore を修正してください" || echo OK

# git add より前に doc-id assign を実行しない（`doc-id assign` が参照を置換するのは
# git ls-files --cached で列挙される追跡済みファイルだけであり、copier copy 直後の
# 生成物は未追跡のため、先に git add しないと .claude/pr-review.yml の
# convention_docs 等の参照が置換されずに残る）
git add -A

# DOC-ID の採番（プレースホルダのままのファイルがある場合）
./tools/doc-id/doc-id assign docs/design/DOC-DOCID_PLACEHOLDER_プルリクエストの作法.md
./tools/doc-id/doc-id assign docs/design/DOC-DOCID_PLACEHOLDER_コーディング方針.md

# pre-commit の有効化
uv tool install pre-commit
pre-commit install
pre-commit run --all-files
```

`docs/README.md`（および `use_doc_id` 選択時に生成される `docs/design/README.md`）の
索引表は DOC-ID 列を持たず、ファイル名へのリンクだけで構成されています（DOC-ID はファイル名から
自明なため）。`doc-id assign` を実行するとリンク先のファイル名（プレースホルダ）が自動で
実際の DOC-ID に置き換わるため、索引表を手で更新する必要はありません。

**ここで終わりではありません。** `AGENTS.md` の「概要」「ディレクトリ構成」など、このリポジトリ固有の
判断が要る部分は空欄・TODO のままです。埋め方の判断ガイドは
`skills/repo-baseline/SKILL.md`（dotfiles から配布され `~/.claude/skills/` に置かれるスキル）
に従ってください。

## 使い方: 更新

撒いた先で `copier update` が使えます（`--trust` は不要）。撒いた版（`_commit`）と今の版の
テンプレートの差分が、撒いた先の手元の変更との3者マージで取り込まれ、両側が同じ行を変えた
ところには `<<<<<<< before updating` 〜 `>>>>>>> after updating` の衝突の印が付きます。
`_skip_if_exists` のファイル（`.rubocop.yml` 等）は update のときも既存のものが残ります。

```bash
cd <撒いた先のリポジトリのルート>   # 作業ツリーはきれいにしておく
uv tool run copier update
```

タグは打っていないので、版は HEAD（`0.0.0.postN.devM+<sha>`）で扱われます。
手順の詳細・増えた質問への答え方・既に撒いた（`_commit` の無い）リポジトリの移行は
`skills/repo-baseline/SKILL.md` と移行の手順書に従ってください。

## 分業の原則

- **決定論的に配れるもの**（規約文書の骨組み・pre-commit 設定・doc-id ツール・CI）は
  この copier テンプレートが撒きます
- **判断が要るもの**（このリポジトリ固有のルール、コーディング方針の中身、AGENTS.md の
  「概要」等）は、撒いた後に `skills/repo-baseline/SKILL.md` を読んだ AI が埋めます

## docs/ フォルダ規約について

3例（LDF / dotfiles / ocw-meter）を突き合わせた結果、共通していたのは `planning/` だけでした。
このテンプレートは以下の方針で切り分けています。

- `design/`・`planning/` は常に前提とする（`design/` は PR の作法という完全汎用な資産の置き場所であり、
  `planning/` は傘ブランチ運用の前提だが、両方とも文書が無い間は物理的なディレクトリを作りません。
  `planning/` は空ディレクトリを git が追跡できないため、最初の計画書ができるまで実体を持ちません）
- `adr/`・`reference/` は質問（`use_adr` / `use_reference`）で選ばせる。ocw-meter 由来の語彙で、
  3例中1例にしか無いため
- `archive/` はどの例でも「空ならディレクトリを作らない」運用のため、質問にはせず
  `docs/README.md` 内で説明するだけに留める

## 検証結果

以下を実施し、確認しました（実施日: 2026-08-02。`language` 関連の項目は 2026-10-11）。

- `language=ruby` で展開し、`bundle install`・`bundle exec rubocop`・`bundle exec rake spec` が通ること
  （`use_doc_id=true` でも `tools/doc-id/` を含めて RuboCop の指摘は出ない。経緯は
  [ADR DOC-2610110216](../../docs/adr/DOC-2610110216_ruby-defaults-in-repo-baseline.md) に記録）
- `language=ruby` で、文書だけのコミットでは lint・test フックが Skipped になり、`.rb` を含むコミットでは走ること
- `language=other`（既定）で Ruby の物が何も生成されず、`tools/doc-id/` のテストが `Gemfile` 無しで動くこと

- 空の git リポジトリに `uv tool run copier copy <このリポジトリのルート> <展開先>` で展開できること
- 展開直後に `./tools/doc-id/doc-id assign` を実行すると、プレースホルダが実際のタイムスタンプへ
  採番され、`AGENTS.md` / `docs/README.md` / `docs/design/README.md` / `opencode.json` 内の
  参照が自動更新されること
- 展開先で `ruby tools/doc-id/test/doc_id_test.rb` が全緑（24 runs / 0 failures）
- 展開先で `git init` 後、`pre-commit install && pre-commit run --all-files` が全緑
- `use_doc_id=false` / `use_ci=false` の組み合わせで `docs/` `tools/` `.github/` が
  生成されないこと（`_exclude` による制御）
- `use_doc_id=false` かつ `lint_cmd` / `test_cmd` が空欄の場合、`.pre-commit-config.yaml` には
  `pre-commit-hooks` 由来の基本フックのみが残り、有効な YAML であること
- 展開先に `.copier-answers.yml` が生成され、`_commit` が記録されること（2026-10-11。
  ルートの `copier.yml` が入口のため。`tests/template_smoke.sh` が検査する）。
  テンプレートを変えたあとの `copier update` が `--trust` 無しで通ること
- 旧形（`_commit` 無し）で撒いたリポジトリは、橋渡しのコミット経由で最初の1回を update できること
  （「使い方: 更新」。手順は移行の手順書）
- `tests/template_smoke.sh` の3つの回答パターン（全部盛り・最小構成・既定値のみ）それぞれで、
  生成された `docs/` 配下の全 `.md`（`docs/design/*コーディング方針.md` / `docs/README.md` 等）に
  Jinja の空白制御ミスによる崩れ（二重空行・見出し直前の空行欠落）が無いこと。
  「既定値のみ」パターン（`use_doc_id=true` かつ `lint_cmd` / `test_cmd` が空欄）は、
  実際にこの崩れが発生していた組み合わせであり、再発防止のため combo に加えてある
