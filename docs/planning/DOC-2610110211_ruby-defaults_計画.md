# 計画書: Ruby のリポジトリの既定（RSpec・厳しめの RuboCop）をテンプレートとスキルに持たせる

傘ブランチ: `ruby-defaults`
ターゲット: `master`

## 概要

`templates/repo-baseline/`（copier テンプレート）と `skills/repo-baseline/SKILL.md` に、
**Ruby のリポジトリのときだけ効く既定**（テストは RSpec、RuboCop は厳しめの設定）を持たせる。
あわせて、テンプレート自身が配る Ruby の道具（`tools/doc-id/`）をその RuboCop の設定に通し、
スキルには「道具のテストの形からプロジェクトの規約を推測しない」ことを書く。

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。転記後に削除済みで
> 参照できない前提で書く）を material として司令官が起草したものである。** ブリーフに
> 書かれていた問題意識（持ち主の発言の逐語）・根本原因・決定事項・手本と実例・既存の穴・
> 制約・スコープ外・検証ステップは本計画書へ転記済みであり、以降はこの計画書が正典である。
> ブリーフの「孫分割の叩き台」は司令官が検討し、ほぼそのままの3本で確定させた（「孫分割の
> 判断」参照）。

**この傘の変更は、これから撒くリポジトリにだけ効く。** `copier update` が使えない
（背景5）ため、既存のリポジトリ（modeldex・pixidex ほか）へは自動では届かない。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `rbd-01-template` | テンプレート: Ruby かを問う質問・Ruby のときだけ生成する `.rubocop.yml`／RSpec の足場／`files:` 付きの lint・test フック／CI の Ruby 準備、ADR | ✅ PR #130 マージ済 |
| 2 | `rbd-02-doc-id-rubocop` | テンプレート自身の Ruby の道具（`tools/doc-id/`）を孫1の `.rubocop.yml` に通す（dotfiles 側の複製も同期） | ✅ PR #131 マージ済 |
| 3 | `rbd-03-skill` | スキル `repo-baseline` の更新（道具のテストから規約を推測しない・Ruby の既定・§4 の答え方）と、生成される `AGENTS.md` への注記 | 🔄 実装中 |

依存: 孫1 → 孫2 → 孫3 の順に直列で進める（孫2 は孫1 の `.rubocop.yml` を基準にし、孫3 は孫1 の
質問名と孫2 の結果を前提に書く）。

## ワークスペースラベル

- 傘: `dotfiles :: Rubyの既定`
- 孫1: `dotfiles :: Rubyの既定 孫1 テンプレート`
- 孫2: `dotfiles :: Rubyの既定 孫2 doc-idをRuboCopへ`
- 孫3: `dotfiles :: Rubyの既定 孫3 スキル`

---

## 背景1: 問題意識（持ち主の発言の逐語）

2026-10-11、pixidex（持ち主の Ruby の新しいリポジトリ）の最初の実装の傘で、持ち主が気づいた。
持ち主の発言（pixidex の傘の司令官経由で受け取った逐語）:

> Rspec にしたいよ。てかmodeldexもそうすべきだな

> modeldexはなんでミニテストにしたのかな、、、これも特に確認してなかった気がする

> rubocop の設定はLDFを参考にして欲しい。あれ割ときっちりしてたはず

> なんというかこの辺の環境差異とかも、別リポにしたマイナス点が出てきてる気はする

> dotfiles の方には傘を切ってもらえる？LDFっていう固有のリポに依存せずにスキルやなんかの側をなおせるといいんだが。

（「LDF」は持ち主の別のリポジトリ `lora-dataset-forge`。RuboCop の設定の手本がそこにある）

## 背景2: 何が起きたか（根本原因）

**テストの道具という、持ち主が決めるべき規約を、AI が確認せずに推測で決めていた。**

- modeldex のテストが minitest なのは、modeldex の最初の実装の傘の計画書（modeldex リポジトリの
  `docs/planning/` にある ingest-place の計画書。ファイル名の DOC-ID は dotfiles の索引に無いため省く）の 384 行目に
  「lint は RuboCop、テストは minitest（リポジトリの既存のテスト `tools/doc-id/test/`・`spike/test/` と同じ）」
  とあるため。**repo-baseline テンプレートが配る `tools/doc-id/test/` が minitest だったので、AI がそれに
  合わせただけ**で、持ち主は確認していない
- pixidex は modeldex に合わせて minitest で始め、持ち主が気づいて RSpec に替えた（pixidex の PR #19、
  マージコミット `fd3a1a2`）
- RuboCop も同様に、テンプレートは何も持っておらず、各リポジトリの AI がその場で決めている。modeldex の
  `.rubocop.yml` は既定ほぼそのまま

**注意: テンプレートの道具のテストが minitest であること自体は正しい。** テンプレートは Ruby 以外の
リポジトリにも撒かれる（例: Rust のリポジトリ・TypeScript のリポジトリ）。`tools/doc-id/test/` は
標準ライブラリの minitest なので、`Gemfile` の無いリポジトリでも `ruby tools/doc-id/test/doc_id_test.rb`
で動く。**これを RSpec に替えると、Ruby 以外のリポジトリに gem の依存が入る。** 直すべきは
「道具のテストの形から、プロジェクトの規約を推測させない」こと。

## 背景3: 人間が確定させた決定事項（覆さないこと）

- **Ruby のリポジトリのテストの既定は RSpec**（持ち主「Rspec にしたいよ」）
- **RuboCop は、持ち主の LDF の設定相当の厳しさ**（持ち主「LDFを参考にして欲しい」）
- **テンプレート・スキルは、特定のリポジトリ（LDF）を参照しない形で直す**（持ち主「LDFっていう固有のリポに
  依存せずに」）。設定はテンプレート自身に持つ

## 背景4: 手本と実例

### 4.1 RuboCop の設定の手本（LDF の `.rubocop.yml`）

手本の実体は持ち主のマシンの `/home/manemone/projects/lora-dataset-forge/main/.rubocop.yml`
（**読むだけ。テンプレートからもスキルからも参照しない**）。孫が手本を開かなくても作業できるように、
写すべき内容を以下に転記する（2026-10-11 に司令官が実物から転記）。

**写すもの:**

```yaml
plugins:
  - rubocop-performance
  - rubocop-rspec

AllCops:
  # NewCops は disable: RuboCop やプラグイン更新時に新しい Cop が
  # 無審査で CI 必須になることを防ぐ。新 Cop は依存更新時に内容を確認し、
  # 必要なものを個別に有効化する運用とする。
  NewCops: disable
  TargetRubyVersion: 4.0        # ← 手本の値。テンプレートでの扱いは設計1.4 を参照
  DisplayCopNames: true
  DisplayStyleGuide: true
  ExtraDetails: true
  SuggestExtensions: false
  Exclude:
    - 'vendor/bundle/**/*'
    - 'bin/bundle'
    - 'Gemfile.lock'
    - '*.gemspec.lock'

Layout/LineLength:
  Max: 120
  AllowHeredoc: true
  AllowURI: true
  URISchemes: [http, https]

Layout/ClassStructure:
  Enabled: true
  Categories:
    module_inclusion: [include, prepend, extend]
    constants: [CONSTANT]
    associations: [attr_accessor, attr_reader, attr_writer]
    initializer: [initialize]
  ExpectedOrder:
    - module_inclusion
    - constants
    - associations
    - initializer
    - public_methods
    - protected_methods
    - private_methods
    - nested_classes

# Style: 宣言的・関数型・Ruby way の方針を反映
Style/StringLiterals:          { EnforcedStyle: double_quotes }
Style/Documentation:           { Enabled: false }   # 手本の注記「MVP 段階では RDoc 名寄せ必須としない。方針文書で人間/AIに期待を記述」
Style/RedundantReturn:         { Enabled: true, AllowMultipleReturnValues: false }
Style/RedundantSelf:           { Enabled: true }
Style/ConditionalAssignment:   { Enabled: true, EnforcedStyle: assign_inside_condition }
Style/MethodCallWithArgsParentheses:
  Enabled: true
  EnforcedStyle: omit_parentheses
  AllowedMethods: [print, puts, p, pp, raise, require, require_relative]
  IgnoreMacros: true
Style/BlockDelimiters:         { Enabled: true, EnforcedStyle: line_count_based }
Style/For:                     { Enabled: true, EnforcedStyle: each }
Style/AndOr:                   { Enabled: true, EnforcedStyle: always }
Style/Not:                     { Enabled: true }
Style/TernaryParentheses:      { Enabled: true, EnforcedStyle: require_parentheses_when_complex }
Style/Semicolon:               { Enabled: true }
Style/UnlessElse:              { Enabled: true }
Style/NegatedIf:               { Enabled: true }
Style/NegatedUnless:           { Enabled: true }
Style/NegatedWhile:            { Enabled: true }
Style/Attr:                    { Enabled: true }
Style/MethodDefParentheses:    { Enabled: true }
# 関数型変換系: 一時配列/一時変数の蓄積ではなく変換メソッドを使う
Style/MapIntoArray:            { Enabled: true }
Style/MapToHash:               { Enabled: true }
Style/MapToSet:                { Enabled: true }
Style/HashTransformValues:     { Enabled: true }
Style/HashTransformKeys:       { Enabled: true }
# 文字列の逐次結合を避ける (複雑なら Heredoc / ERB)
Style/StringConcatenation:     { Enabled: true }

RSpec/MultipleExpectations:    { Max: 2 }
RSpec/ExampleLength:           { Max: 12 }

Metrics/MethodLength:
  Max: 20
  CountComments: false
  CountAsOne: [array, hash, heredoc]
Metrics/AbcSize:
  Max: 17
  CountRepeatedAttributes: false
  Exclude: ['spec/**/*']
Metrics/ClassLength:
  Max: 200
  CountComments: false
  CountAsOne: [array, hash, heredoc]
Metrics/CyclomaticComplexity:  { Max: 7 }
Metrics/ModuleLength:
  Max: 200
  CountComments: false
  CountAsOne: [array, hash, heredoc]
Metrics/BlockLength:
  Exclude: ['spec/**/*_spec.rb', '*.gemspec', 'Gemfile', 'Rakefile']
Metrics/ParameterLists:        { Max: 6 }
```

（上は転記のため flow style に詰めてある。テンプレートに書くときの体裁は孫1 が決めてよいが、
**値と、手本にあった方針のコメント（NewCops を disable にする理由・Style の方針）は落とさない**）

**写さないもの:**

- `AllCops.Exclude` の `'tools/**/*'`（手本では「One-off dev/reporting scripts」として丸ごと除外）
- `Metrics/ClassLength.Exclude` の `lib/lora_forge/cli.rb`・`lib/lora_forge/commands/*.rb`
  （そのリポジトリ固有のファイル名を指した除外）
- `Metrics/ParameterLists` に付いていた、そのリポジトリ固有のクラスを理由にしたコメント

いずれも pixidex も写さなかった。AI が除外を足さない規則（dotfiles の `AGENTS.md`「最重要ルール」と
同趣旨の規則がテンプレートの `AGENTS.md` にもある）に反するうえ、そもそも他のリポジトリには関係ない。

**「厳しい」は数字が小さいことではない。** RuboCop の既定は MethodLength 10・ClassLength 100 で、
手本はむしろ緩めている。手本の厳しさは、プラグイン（performance・rspec）・`Layout/ClassStructure`・
Style の追加にある。Metrics の数字を「厳しくするために」既定より小さくしないこと。

### 4.2 実例: pixidex の PR #19

リポジトリ `manemone/pixidex` の PR #19（マージコミット `fd3a1a2`）。RuboCop を手本どおりにし、
`test/` を `spec/` の RSpec にした。`tools/doc-id`・`tools/namecheck`・`spike` の minitest は触っていない。
lint は `bundle exec rubocop`、テストは `bundle exec rake spec`。孫1 が Gemfile・`.rspec`・
`spec/spec_helper.rb`・`Rakefile` の形を決めるときの参考にしてよい（`gh pr view 19 -R manemone/pixidex`
と `gh pr diff 19 -R manemone/pixidex` で読める）。**テンプレートから pixidex を参照しない。**

## 背景5: 既存の穴

- `templates/repo-baseline/` は言語を問わない作りで、Ruby のテストの道具・RuboCop の設定を持たない
  （`copier.yml` の `lint_cmd`・`test_cmd` の help の例に `rubocop`・`bundle exec rspec` があるだけ）
- `skills/repo-baseline/SKILL.md` の §4 は `lint_cmd`・`test_cmd` を「既存の設定から探して答える。
  無ければ空欄」としか言っておらず、空欄のまま進んだあとに AI が何を基準に決めるかが書かれていない
- **テンプレートが生成する lint・test の pre-commit フックに `files:` の絞り込みが無い**
  （`template/.pre-commit-config.yaml.jinja`。`pass_filenames: false` で常に走る）。`Gemfile` がまだ無い
  リポジトリで lint・test のコマンドを入れると、文書だけのコミットでも毎回走って落ちる。pixidex の
  初期化では、このために lint・test を空欄にして撒いた。modeldex は後から `files:` を手で足した
- **テンプレート自身の Ruby の道具（`tools/doc-id/`）が、厳しい RuboCop に通らない。** modeldex は
  `tools/doc-id/**` を RuboCop の対象から外しており、理由を「配布元のテンプレートから配られたコード。
  直すなら配布元で直す」としている。除外を外したときの指摘は 37 件・3 ファイル（2026-09-16 の modeldex
  での実測。modeldex の当時の設定で Metrics/MethodLength 11・Metrics/AbcSize 7・Style/Documentation 7・
  Style/OneClassPerFile 6 ほか。**手本の設定とは前提が違う**——手本は Style/Documentation を無効にし、
  一方で `omit_parentheses` 等を足しているので、件数と内訳は孫2 が測り直す）。**この傘がその「配布元」**。
  テンプレートが Ruby の既定の RuboCop の設定を配るなら、テンプレート自身の Ruby の道具がそれに通ること
  （通さないなら、その理由を書いた除外にすること）を整合させる
- **`copier update` は使えない**（`skills/repo-baseline/SKILL.md` §2。テンプレートが git リポジトリの
  ルートでないため `.copier-answers.yml` に `_commit` が残らない）。この傘の変更は、
  **これから撒くリポジトリにだけ効く**

## 背景6: dotfiles 側の構造上の前提（司令官が調べたもの）

- `tools/doc-id/` は dotfiles 本体の道具でもあり、`templates/repo-baseline/template/tools/doc-id/` は
  その**完全な複製**である。pre-commit の `doc-id-template-sync` フック
  （`diff -r tools/doc-id templates/repo-baseline/template/tools/doc-id`）が同一性を検査する。
  **孫2 が道具を直すときは両方を同じに直す**（片方だけ直すとコミットできない）
- dotfiles 本体は Ruby のリポジトリではない（`Gemfile` も `.rubocop.yml` も無い）。dotfiles 本体に
  RuboCop・RSpec を導入するのはこの傘の範囲外。`tools/doc-id` を RuboCop に通したかの確認は、
  テンプレートを Ruby のリポジトリとして使い捨てのディレクトリに撒き、その中で行う
- `tests/template_smoke.sh` が `check_combo` で回答の組み合わせごとに `uvx copier copy` を実行し、
  生成物の YAML・Markdown の崩れを検査している。新しい質問を足したら、ここに組み合わせを足す
- CI のテンプレート（`template/.github/workflows/ci.yml.jinja`）は `uvx pre-commit run --all-files` を
  走らせるだけで、Ruby も bundler も用意しない。`language: system` の `bundle exec ...` フックを
  生成するなら、Ruby のときだけ Ruby の準備（`ruby/setup-ruby` と `bundle install` 相当）が要る
- 手元の Ruby は 3.3（mise）。手本の `TargetRubyVersion: 4.0` を固定で書くと、撒いた先の Ruby と
  ずれうる

---

## 設計1: 司令官が確定させた外形（孫はこれに従う）

ブリーフの叩き台を下敷きに、司令官が決めた外形。**細部（体裁・ファイル名の細かい選択）は孫が決めてよいが、
ここに書いた線は動かさない。** 動かす必要があると判断したら、実装を止めて司令官に理由を報告すること。

### 1.1 Ruby かどうかの質問

- `copier.yml` に、Ruby のリポジトリかを問う質問を足す。**`lint_cmd`・`test_cmd` より前に置く**
  （後述のとおり、その2つの既定値がこの回答に依存するため）
- 形は「主な言語を選ぶ choice（選択肢は `ruby` と `other`、既定 `other`）」を推奨する。Ruby 以外の言語の
  既定を将来足すときに質問を作り直さずに済むため。ただし**選択肢を Ruby 以外に増やすことはこの傘ではしない**
  （先回り実装の禁止）。bool にする案と比べてどちらにしたかと理由を ADR に書く
- **既定値は「Ruby ではない」側。** Ruby 以外のリポジトリに撒く人が何も考えずに進めても、Ruby の物が
  1つも生成されないこと

### 1.2 Ruby のときだけ生成するもの

- `.rubocop.yml`（背景4.1 の「写すもの」相当。**自己完結。LDF にも pixidex にも言及しない**）
- RSpec の足場: `Gemfile`（rubocop・rubocop-performance・rubocop-rspec・rspec・rake）、`.rspec`、
  `spec/spec_helper.rb`、`spec` タスクを持つ `Rakefile`。中身は最小限にする（pixidex の PR #19 を参考に
  してよい）。`bundle install` 直後に `bundle exec rubocop` と `bundle exec rake spec`（または孫1 が
  決めたコマンド）が通ること。**example 0 件で rspec が落ちない形**にすること（足場だけのリポジトリで
  test フックが失敗し続けないように）
- Ruby 以外のときは、上のどれも生成しない（copier の `_exclude` の条件、またはファイル名の Jinja 条件で制御）
- 既に `Gemfile` 等があるリポジトリに撒く場合の扱い（copier の衝突確認に任せるか、`_skip_if_exists` を
  使うか）は孫1 が決め、スキル（孫3）に書く材料として PR 説明に残す

### 1.3 lint・test の既定値とフック

- Ruby のとき、`lint_cmd`・`test_cmd` の既定値を Ruby の既定（例: `bundle exec rubocop` / `bundle exec rake spec`）
  にする（copier の `default:` に Jinja 式を書ける）。人間・AI が別の値を答えることは妨げない
- **lint・test のフックに `files:` の絞り込みを付ける。Ruby のときは必須。** Ruby のファイル
  （`.rb`・`.rake`・`.gemspec`）と、結果を左右する設定ファイル（`Gemfile`・`Gemfile.lock`・`Rakefile`・
  `.rubocop.yml`・`.rspec` など）の変更でだけ走るようにし、**文書だけのコミットでは走らない**こと
- Ruby 以外で `lint_cmd`・`test_cmd` を答えた場合の `files:` は、言語が分からず正しい絞り込みを機械的に
  決められない。この傘では**現状の挙動（絞り込み無し）を変えない**。撒いた後に AI が足すべきこととして
  スキル（孫3）のチェックリストに書く
- CI（`use_ci` のとき）: Ruby のときだけ、`pre-commit` を走らせる前に Ruby と gem を用意する手順を足す。
  Ruby 以外のときの `ci.yml` は今と同じ内容のまま

### 1.4 `TargetRubyVersion`

手本の `4.0` を固定で書かない。撒いた先の Ruby と食い違うため。推奨は「`.rubocop.yml` に書かず、
RuboCop が `.ruby-version`・`Gemfile.lock`・gemspec 等から推定するのに任せる」こと（自己完結を保ち、
値の二重管理を避けられる）。ただし推定元が無いと RuboCop は古い版を仮定するので、その場合の扱い
（`.ruby-version` を生成する・質問で聞く等）は孫1 が決めて ADR に書く。

### 1.5 テンプレートの道具（`tools/doc-id/`）は minitest のまま

- `tools/doc-id/test/` を RSpec に替えない。`doc-id-test` フックも `ruby tools/doc-id/test/doc_id_test.rb`
  のまま（Ruby 以外のリポジトリで `Gemfile` 無しで動くことを壊さない）
- Ruby のリポジトリでは `bundle exec rubocop` が `tools/doc-id/` も見る。孫2 がこれを通す
  （通さないなら、理由を書いた除外にする。**AI の判断で黙って除外を足さない**）

### 1.6 ADR

孫1 が ADR を1本書く（`docs/adr/`）。記録する決定: Ruby の既定を Ruby のリポジトリのときだけ生成すること
と質問の形（1.1）、`.rubocop.yml` をテンプレート自身に持ち特定のリポジトリを参照しないこと・写したもの
と写さなかったもの（背景4.1）、フックの `files:`（1.3）、`TargetRubyVersion` の扱い（1.4）、道具の
テストは minitest のままにする理由（背景2・1.5）、この変更が既存のリポジトリに届かないこと（背景5）。
孫2 の結果（`tools/doc-id` を通したか、除外にしたか）は孫2 が同じ ADR に追記してよい。

## 孫分割の判断

ブリーフの叩き台（1. テンプレート、2. `tools/doc-id` を通す、3. スキル）をそのまま採った。
変えた点は2つ:

- **ADR を孫1 に入れた。** 質問の形や `TargetRubyVersion` の扱いなど、孫1 で決まる設計判断が多いため
- **生成される `AGENTS.md` への「道具のテストの形から規約を推測しない」注記を孫3 に入れた。** 根本原因
  （背景2）に直接効くのは、撒いた先の AI が読む `AGENTS.md` の一文である。スキルの更新と同じ関心事
  なので同じ孫にまとめる

孫1 の時点では `tools/doc-id/` がまだ RuboCop に通らない（孫2 の仕事）。そのため孫1 は、
**Ruby かつ `use_doc_id=false`（`tools/` が生成されない）組み合わせで `bundle exec rubocop` が通ること**を
確かめ、`use_doc_id=true` で `tools/doc-id/` に指摘が出るのは既知として PR 説明に書く。

## 決定的な制約（孫は全部守ること）

- dotfiles の `AGENTS.md` に従う（とくに「最重要ルール」の linter 抑制・除外の禁止、「コミット前の必須
  ステップ」、DOC-ID の採番、README の二層構造）
- **テンプレートは Ruby 以外のリポジトリにも撒かれる。Ruby の既定は、Ruby のリポジトリのときだけ生成される**
- **テンプレートの道具のテスト（minitest・標準ライブラリ）は、Ruby 以外のリポジトリでも `Gemfile` 無しで
  動くことを壊さない**
- **テンプレート・スキル・ADR から LDF（`lora-dataset-forge`）や pixidex を参照しない。** 設定はテンプレート
  自身に持つ。ADR で「手本にした」と経緯を書くのは構わないが、手本のファイルを読みに行かせる記述にしない
- テンプレートは dotfiles の他の部分に依存しない自己完結ディレクトリである
  （`templates/repo-baseline/README.md`「自己完結」）
- `tools/doc-id/` と `templates/repo-baseline/template/tools/doc-id/` は常に同一に保つ（背景6）
- スキルは `skills/deploy.sh` で配布される。配布の確認は `./deploy-all.sh --dry-run` と
  `tests/deploy_smoke.sh`（サンドボックス）で行い、**実 `$HOME` に対して deploy スクリプトを実行しない**
- **このリポジトリは公開リポジトリである。** 他のリポジトリの中身（コード・計画書の本文）を転載しない。
  リポジトリ名・PR 番号・設定値の言及は構わない
- 指示された範囲外の機能を先回りして実装しない（スコープ外の節を参照）

## スコープ外

- **既存のリポジトリの移行**: modeldex は別の傘（`rspec-rubocop`。同時に切った。まずコストの見積もりから）。
  pixidex は済み
- **Windows の Ruby の環境の管理**（gem の導入時に RubyInstaller の仕組みが MSYS2 にパッケージを入れる件。
  持ち主「なんか環境をコントロールできないのは気持ち悪いな」）: pixidex の傘の孫1c が仕組みの調査・止め方・
  戻し方の提案をしている。結果を待つ
- **`copier update` を使えるようにすること（テンプレートを独立したリポジトリにする）**: 既存のリポジトリへ
  直しを届ける経路の問題で、大きい判断。この傘では扱わない
- 関連するが持ち主が頼んでいないもの（持ち主が望めば別の傘）: modeldex で生まれた `tools/namecheck/` を
  テンプレートへ取り込むこと、確認系の道具を pre-commit のリモートフックとして配ること
- Ruby 以外の言語の既定（Rust・TypeScript 等）
- Ruby のコーディング方針の文書（`docs/design/` のコーディング方針の雛形）に Ruby の思想を書き込むこと
- dotfiles 本体への RuboCop・RSpec の導入（背景6）

## 必須の検証ステップ（AGENTS.md「コミット前の必須ステップ」より。省略しない）

- 初回のみ: `uv tool install pre-commit` と `pre-commit install`
- 新規ファイルを足した・大きく変えたら、その時点で `pre-commit run --files <path>` を実行する
- まとめて確かめるときは `pre-commit run --all-files`
- **`templates/repo-baseline/` 配下を変えたら `tests/template_smoke.sh`**（YAML・Markdown の崩れはこれでしか
  検出できない）
- スキルを変えたら `./deploy-all.sh --dry-run` と `tests/deploy_smoke.sh`（サンドボックス）
- `tools/doc-id/` を変えたら `ruby tools/doc-id/test/doc_id_test.rb`（pre-commit の `doc-id-test` フックでも走る）
- **テンプレートを、使い捨てのディレクトリ（`mktemp -d` で作る）に実際に撒いて確かめる。** Ruby のリポジトリ
  として撒いた場合と、Ruby でないリポジトリとして撒いた場合の両方:
  - Ruby のとき: 生成された `.rubocop.yml` と RSpec の足場で `bundle install`・`bundle exec rubocop`・
    `bundle exec rake spec`（または決めたコマンド）が通ること。**文書だけのコミット（例: `README.md` だけの
    変更）で lint・test のフックが走らない（Skipped になる）こと**
  - Ruby でないとき: Ruby の既定が何も生成されず、`ruby tools/doc-id/test/doc_id_test.rb` が `Gemfile` 無しで
    動くこと
  - 撒いた先で `git init` してから `copier copy` すること（テンプレートの前提）
- `docs/` に新規ファイルを足すときは `DOC-DOCID_PLACEHOLDER_<説明的ファイル名>.md` で作り、
  `./tools/doc-id/doc-id assign <path>` で採番する。`docs/README.md` の索引も更新する
- **CI の課金エラーは無視して、手元の `pre-commit` と上記のスモークで判定する**（持ち主の方針）

## テスト方針（AGENTS.md「テスト方針」に従う）

この傘で主に変わるのはテンプレート（生成物の出し分け）と、`tools/doc-id/` のリファクタ。

- **生成物の出し分け**（Ruby のときだけ生成される・Ruby でないときは生成されない・`files:` が付く）は、
  回答に応じて壊れると撒いた先で気づきにくい外部 contract である。`tests/template_smoke.sh` に
  Ruby の組み合わせを足して authoritative に守る。既存の組み合わせが「Ruby でない」側を兼ねられるなら、
  そちらに「Ruby の物が生成されないこと」の検査を足すだけでよい
- **`tools/doc-id/` のリファクタ**は振る舞いを変えないことが要件で、既存の minitest（`doc_id_test.rb`）が
  その regression を守る。新しいテストは原則足さない
- `bundle install`（ネットワーク）を要する確認をスモークに入れるかは、孫が実行時間と現実的な regression
  risk（将来 `tools/doc-id` を直した人が RuboCop の違反を持ち込む）を比べて決め、PR 説明に書く。入れない
  なら、手動で確かめた結果を PR 説明に残す

## 司令官の運用メモ（持ち主の方針）

- マージ済みの孫のワークツリーは `ocw rm` で片付け、孤児の Herdr ワークスペースは `herdr workspace close`
  まで面倒を見る
- 孫の停止を数分で検知する見張り（cron の巡回）を常に持つ

---

## 孫1用プロンプト:

````markdown
# 傘ブランチ: ruby-defaults
# 孫ブランチ: rbd-01-template
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/ruby-defaults/docs/planning/DOC-2610110211_ruby-defaults_計画.md`

**まず計画書の「概要」「背景1〜6」「設計1」「孫分割の判断」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」を全部読むこと。** 以下はその上での作業指示である。

## 実装開始前の必須手順

作業ブランチは**必ず `ruby-defaults`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout ruby-defaults
git fetch origin
git merge --ff-only origin/ruby-defaults
git checkout -b rbd-01-template
```

（`ocw` で作られたワークツリーで既に `rbd-01-template` にいる場合は、`git fetch origin` のあと
`git log origin/ruby-defaults -1` が自分のブランチの祖先にあることを確かめればよい）

## やること

`templates/repo-baseline/` に、Ruby のリポジトリのときだけ効く既定を足す。計画書「設計1」の 1.1〜1.4 の
線に従う。

1. `copier.yml`: Ruby かを問う質問（設計1.1）。`lint_cmd`・`test_cmd` より前に置き、その2つの既定値を
   Ruby のとき Ruby の既定にする（設計1.3）
2. Ruby のときだけ生成するもの（設計1.2）: `.rubocop.yml`（計画書 背景4.1 の「写すもの」相当。
   「写さないもの」は写さない。LDF・pixidex に言及しない）、`Gemfile`、`.rspec`、`spec/spec_helper.rb`、
   `spec` タスクを持つ `Rakefile`
3. `.pre-commit-config.yaml.jinja`: Ruby のとき lint・test フックに `files:` を付ける（設計1.3）。Ruby 以外の
   ときの挙動は変えない
4. `.github/workflows/ci.yml.jinja`: Ruby のときだけ Ruby と gem を用意する手順を足す（設計1.3）
5. `TargetRubyVersion` の扱いを決める（設計1.4）
6. 生成される `AGENTS.md` の「コミット前の必須ステップ」等で、Ruby のときの lint・test が自然に読めるか
   確認し、必要なら直す（「道具のテストの形から規約を推測しない」注記は孫3 の仕事なので、ここでは書かない）
7. `templates/repo-baseline/README.md` の質問表・生成物の説明を更新する。ルート `README.md` に
   テンプレートの質問へ言及した箇所があれば合わせる（README の二層構造）
8. `tests/template_smoke.sh` に Ruby の組み合わせを足し、Ruby でないときに Ruby の物が生成されないことも
   検査する（計画書「テスト方針」）
9. ADR を1本書く（設計1.6）。`docs/adr/DOC-DOCID_PLACEHOLDER_<説明的な名前>.md` で作り
   `./tools/doc-id/doc-id assign` で採番、`docs/README.md` のクイックナビゲーションと全 DOC-ID 索引に足す。
   既存の ADR（例: `docs/adr/DOC-2609162327_claude-md-machine-local-tone.md`）の構成に倣う

**孫1 の時点では `tools/doc-id/` は RuboCop に通らない（孫2 の仕事）。** 撒いて確かめるとき、
`bundle exec rubocop` の全件通過は「Ruby かつ `use_doc_id=false`」の組み合わせで確かめ、
`use_doc_id=true` で `tools/doc-id/` に出る指摘は既知として件数と主な cop を PR 説明に書く
（孫2 がこれを読む）。既存の `Gemfile` があるリポジトリに撒いたときの扱い（設計1.2 最終項）も PR 説明に書く
（孫3 がこれを読む）。**除外を足して通したことにしない。**

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- Ruby でないリポジトリとして撒いたとき、Ruby の物（`.rubocop.yml`・`Gemfile`・`spec/` 等・CI の Ruby 準備）が
  1つも生成されず、`tools/doc-id` のテストが `Gemfile` 無しで動く
- Ruby のリポジトリとして撒いたとき、Ruby の既定一式が生成され、lint・test フックに `files:` が付いている
- 生成された `.pre-commit-config.yaml`・`ci.yml`・Markdown が壊れていない（既存の `template_smoke.sh` の検査）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

加えて、計画書「必須の検証ステップ」の「使い捨てのディレクトリに実際に撒いて確かめる」を手で行い
（`bundle install`・`bundle exec rubocop`・`bundle exec rake spec`・文書だけのコミットでフックが Skipped に
なること）、結果を PR 説明に書く。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files <変更・追加したファイル>
tests/template_smoke.sh
pre-commit run --all-files
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `ruby-defaults` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

---

## 孫2用プロンプト:

````markdown
# 傘ブランチ: ruby-defaults
# 孫ブランチ: rbd-02-doc-id-rubocop
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/ruby-defaults/docs/planning/DOC-2610110211_ruby-defaults_計画.md`

**まず計画書の「概要」「背景1〜6」「設計1」「決定的な制約」「スコープ外」「必須の検証ステップ」
「テスト方針」を全部読むこと。** 次に、孫1 の PR（`gh pr list --base ruby-defaults --state merged` で
`rbd-01-template` を探す）の説明と、孫1 が書いた ADR を読むこと。孫1 が測った `tools/doc-id/` の指摘の
件数と主な cop が書いてある。以下はその上での作業指示である。

## 実装開始前の必須手順

作業ブランチは**必ず `ruby-defaults`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout ruby-defaults
git fetch origin
git merge --ff-only origin/ruby-defaults
git checkout -b rbd-02-doc-id-rubocop
```

（`ocw` で作られたワークツリーで既に `rbd-02-doc-id-rubocop` にいる場合は、`git fetch origin` のあと
`origin/ruby-defaults` の最新（孫1 のマージを含む）が自分のブランチの祖先にあることを確かめればよい）

## やること

テンプレート自身の Ruby の道具（`tools/doc-id/`）を、孫1 がテンプレートに足した `.rubocop.yml` に通す。

1. 使い捨てのディレクトリ（`mktemp -d`）に `git init` し、テンプレートを Ruby のリポジトリとして
   `use_doc_id=true` で撒き、`bundle install` のあと `bundle exec rubocop` で `tools/doc-id/` の指摘を測る
2. 指摘は**リファクタで解消する**（dotfiles の `AGENTS.md`「最重要ルール」: linter の抑制ディレクティブ・
   除外の追加を AI の判断でしない。長さ系の指摘に対して機械的に分割せず、責務・凝集性・読みやすさが
   改善する場合だけ分割する）。`rubocop -a` 相当の自動修正を使ってよいが、結果は必ず読んで確かめる
3. 構造を変えても解消できない・解消すると明らかに悪くなる指摘があれば、**抑制も除外もせず**、
   違反内容・対象ファイル・判断理由を PR 説明に書いて止める（司令官・人間が判断する）。
   計画書 設計1.5 の「理由を書いた除外」は人間がそれを認めた場合だけの選択肢である
4. **`tools/doc-id/` と `templates/repo-baseline/template/tools/doc-id/` の両方を同一に直す**
   （`doc-id-template-sync` フック。計画書 背景6）
5. 振る舞いを変えない。`ruby tools/doc-id/test/doc_id_test.rb` が通り続けること。テストファイル
   （minitest のまま。RSpec に替えない）も RuboCop の対象なので同様に通す
6. 結果（解消した件数・残した指摘とその理由）を孫1 の ADR に追記する
7. `tools/doc-id/` が RuboCop に通り続けることをスモーク（`tests/template_smoke.sh`）で守るかどうかを、
   計画書「テスト方針」の最終項に従って決め、PR 説明に書く

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- `tools/doc-id` の振る舞い（`check` / `verify` / `assign` 等）が変わらない（既存の minitest で守られる）
- Ruby のリポジトリとして撒いた先で、`tools/doc-id/` を含めて `bundle exec rubocop` が通る
- Ruby でないリポジトリとして撒いた先で、`tools/doc-id` のテストが `Gemfile` 無しで動く
- dotfiles 側の `tools/doc-id/` とテンプレート側の複製が同一である（既存の `doc-id-template-sync` フック）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
ruby tools/doc-id/test/doc_id_test.rb
pre-commit run --files <変更したファイル>
tests/template_smoke.sh
pre-commit run --all-files
```

加えて、使い捨てのディレクトリに Ruby / Ruby でないの両方で撒き直し、`bundle exec rubocop`（Ruby のとき）と
`ruby tools/doc-id/test/doc_id_test.rb`（両方）を実行した結果を PR 説明に書く。

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `ruby-defaults` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

---

## 孫3用プロンプト:

````markdown
# 傘ブランチ: ruby-defaults
# 孫ブランチ: rbd-03-skill
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/ruby-defaults/docs/planning/DOC-2610110211_ruby-defaults_計画.md`

**まず計画書の「概要」「背景1〜6」「設計1」「孫分割の判断」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」を全部読むこと。** 次に、孫1・孫2 の PR
（`gh pr list --base ruby-defaults --state merged`）の説明と、孫1 が書いた ADR を読むこと。
質問名・生成物・既存の `Gemfile` があるときの扱い・`tools/doc-id` の RuboCop の扱いは、そこで確定している。
以下はその上での作業指示である。

## 実装開始前の必須手順

作業ブランチは**必ず `ruby-defaults`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout ruby-defaults
git fetch origin
git merge --ff-only origin/ruby-defaults
git checkout -b rbd-03-skill
```

（`ocw` で作られたワークツリーで既に `rbd-03-skill` にいる場合は、`git fetch origin` のあと
`origin/ruby-defaults` の最新（孫1・孫2 のマージを含む）が自分のブランチの祖先にあることを確かめればよい）

## やること

### 1. `skills/repo-baseline/SKILL.md`

- **道具のテストの形からプロジェクトの規約を推測しないこと**を明記する。`tools/doc-id/test/` が minitest
  なのはテンプレートの道具の都合（Ruby 以外のリポジトリでも `Gemfile` 無しで動かすため）であり、撒いた先の
  リポジトリのテストの規約ではない。根本原因（計画書 背景2）を短く添える。リポジトリ名は出してよいが、
  他のリポジトリの中身は転載しない
- **テストの道具・lint の設定のような、持ち主が決めるべき規約を AI が推測で決めない。** 既存の設定から
  読み取れず、テンプレートの既定（Ruby のときの RSpec・RuboCop）でも決まらないなら、人間に確認する
- §4「質問への答え方」: 孫1 で足した Ruby かを問う質問の答え方と、`lint_cmd`・`test_cmd` の答え方を更新する
  （Ruby のときは既定値が Ruby の既定になること、空欄のまま進んだときに後で何を基準に決めるか）
- §3「既存ファイルとの衝突」: 既に `Gemfile`・`.rubocop.yml`・`spec/`・`Rakefile` があるリポジトリに Ruby として
  撒く場合の扱い（孫1 の PR 説明を参照）
- §5「撒いた後に埋めるべきもの」: Ruby 以外で `lint_cmd`・`test_cmd` を答えたときに、フックへ `files:` を
  足すこと（計画書 設計1.3）。Ruby のときに `bundle install` して `Gemfile.lock` をコミットすること等、
  撒いた直後にやるべきことがあれば足す
- §2「既存導入の更新」: この傘の Ruby の既定は既存のリポジトリに自動では届かない（`copier update` が
  使えないため）ことを、Ruby の既定を後から取り込みたい場合の手動の手順（どのファイルを持ってくれば
  よいか）と合わせて書く

### 2. 生成される `AGENTS.md`（`templates/repo-baseline/template/AGENTS.md.jinja`）

- 撒いた先の AI が読む場所に、「`tools/doc-id/` のテストが minitest なのはテンプレートの道具の都合であり、
  このリポジトリのテストの規約ではない」旨を1〜2文足す（`use_doc_id` のときだけ出せばよい）
- Ruby のときは、このリポジトリのテストの規約が RSpec であることが読み取れるようにする（孫1 で既に
  読み取れるなら足さない）
- 変えたら `tests/template_smoke.sh` を実行する

### 3. 文書の整合

- `templates/repo-baseline/README.md` とスキルの記述が矛盾しないこと（README の二層構造）
- スキルの変更はグローバルに配布されるものなので、`./deploy-all.sh --dry-run` と `tests/deploy_smoke.sh` で
  配布を確かめる（実 `$HOME` に対して deploy しない）

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 生成される `AGENTS.md` が、どの回答の組み合わせでも壊れていない（既存の `template_smoke.sh` の検査）
- スキルが全エージェント分配布される（既存の `deploy_smoke.sh` と `deploy-all.sh --dry-run`）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

この孫は主に文書の変更であり、新しい自動テストは原則として追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files <変更したファイル>
tests/template_smoke.sh
./deploy-all.sh --dry-run
tests/deploy_smoke.sh
pre-commit run --all-files
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `ruby-defaults` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````
