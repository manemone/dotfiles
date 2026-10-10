# repo-baseline で旧形に撒いたリポジトリを copier update できる形へ移す手順

既に撒いたリポジトリ（modeldex・pixidex・sheaf）を `copier update` できる形へ移すときに、
繰り返し引く手順書である。移行の方式の決定とその根拠は
[ADR DOC-2610110435](../adr/DOC-2610110435_copier-root-entry.md) §4 にあり、
update 一般の手順と衝突の解き方はスキル
[`skills/repo-baseline/SKILL.md`](../../skills/repo-baseline/SKILL.md) §2 にある。**この文書には
移行に固有のことだけを書く。**

このリポジトリは公開リポジトリなので、他のリポジトリの中身（コード・計画書の本文）は書かない。
リポジトリ名・コミット・ファイル名・答えの値だけを書く。

## 1. 対象と前提

「旧形」とは、ルートの `copier.yml` ができる前に撒いたリポジトリのこと。`.copier-answers.yml` に
`_commit` が無く、`_src_path` が伏せてある（または dotfiles のサブディレクトリを指している）ため、
このままでは `copier update` できない。

- 移行は**各リポジトリで、この手順書ができたあとに行う**。この手順書を書いた傘では移行していない
- **移行を始める前に、傘 `copier-update`（ルートの `copier.yml`）が `master` にマージされていること。**
  手順 4 の `--vcs-ref` に、ルートの `copier.yml` を含む本物のコミットを使うため
- modeldex は、RSpec 移行の傘（`rspec-rubocop`）が終わってから。両方が
  `.pre-commit-config.yaml`・`AGENTS.md` を触るため
- 作業ツリーはきれいにしておく（未コミットの変更があると copier が拒否する）。
  `main` から update 用のブランチを切る
- 以下の記録は 2026-10-11 時点（copier 9.18.2）の読み取りと、使い捨ての複製での模擬による。
  読み取り時点の各リポジトリの状態は「5. リポジトリごとの注意」に書く

## 2. なぜ橋渡しのコミットが要るか（要約）

answers に `_commit` を手で書けば update できるが、その版にルートの `copier.yml` が無いと、
copier はリポジトリ全体をテンプレートとして撒いて3者マージの元にし、非 ASCII のファイル名で落ちる。
かといって `_commit` を「ルートの `copier.yml` を含む最初のコミット」にすると、3者マージの元が
撒いた版より新しくなり、撒いた版からそのコミットまでのテンプレートの直しが update で届かない。
そこで、**撒いた版 V のテンプレートそのままで入口だけルートにある「橋渡しのコミット S」**を、
使い捨てのクローンの中だけに作り、それを `_commit` に書く（ADR DOC-2610110435 §4）。

## 3. 共通の手順

`<V>` は「4. リポジトリごとの表」の撒いた版。`<repo>` は移行するリポジトリ。

```bash
# 1. 橋渡し用の使い捨てクローンを作る。このクローンはどこにも push しない。
#    update が終わるまで消さない
BRIDGE=$(mktemp -d)
git clone https://github.com/manemone/dotfiles.git "$BRIDGE/dotfiles"
cd "$BRIDGE/dotfiles"

# 2. V から一時ブランチを切り、V のテンプレートの copier.yml をルートへ写して橋渡しのコミット S を作る
git switch -c bridge <V>
git show <V>:templates/repo-baseline/copier.yml \
  | sed 's#^_subdirectory: template#_subdirectory: templates/repo-baseline/template#' > copier.yml
git add copier.yml
git commit -m "bridge"
S=$(git rev-parse HEAD)

# 3. ルートの copier.yml を含む本物のコミット（master の先頭）を控える
git fetch origin
REAL=$(git rev-parse origin/master)
echo "S=$S REAL=$REAL BRIDGE=$BRIDGE"
```

```bash
# 4. 移行するリポジトリ（作業ツリーはきれい。update 用のブランチを切ってある）で、
#    answers に _commit と _src_path を書いてコミットする
cd <repo>
#   .copier-answers.yml の _src_path: を "$BRIDGE/dotfiles"（絶対パス）にし、
#   _commit: $S を足す。冒頭の「update できない」旨のコメントは update が書き直すので放っておいてよい
git commit -am "移行のため answers に撒いた版と撒く元を書く"

# 5. update。増えた質問（language 等）は --data で明示する（答えは「4. リポジトリごとの表」）
uv tool run copier update --defaults --vcs-ref "$REAL" \
  --data language=<ruby|other> [--data ruby_version=<版>]
```

```bash
# 6. 衝突を解き、確かめる（スキル §2「衝突の解き方」）
git diff .copier-answers.yml    # _commit が S ではなく本物のコミット（"$REAL" の短縮 SHA を含む）に進んでいること

# 7. _src_path を git の URL に書き換える。以後の update はこの URL から普通に通る
#    _src_path: https://github.com/manemone/dotfiles.git
```

- 手順 5 の直後の `_commit` は `v20130702_00-N-g<sha>` という `git describe` 形式になる
  （先頭は dotfiles にある古いタグ名で、版としては使われない。`g<sha>` が `"$REAL"`）。
  `_commit` に S（橋渡しのコミット）が残っていないことを確かめる。S はクローンの中にしか無く、
  クローンを消すと辿れなくなる
- 手順 7 の書き換えを忘れると、`_src_path` が使い捨てのクローンのまま残り、クローンを消した
  時点で次の update が落ちる
- `--trust` は要らない。`--defaults` を付けても増えた質問は既定値になるだけなので、`language` は
  必ず `--data` で渡す（渡し漏れは update のあと `git diff .copier-answers.yml` の `language:` で気づく）
- update の結果の差分は**人間に見せてからコミットする**
- 移行用の PR の説明には、どの V を使ったか・`language` をどう答えたか・衝突をどう解いたかを書く

### namecheck を持つリポジトリ

手順 7 で `_src_path` が git の URL になるとユーザー名が入るため、namecheck に当たる。
`tools/namecheck/allowlist.txt` に `.copier-answers.yml` の1行を足す（持ち主が許可済み。ADR
DOC-2610110435 §2.2）。行末の `namecheck:allow-line` では足りない（copier が update のたびに
ファイルを書き直し、マーカーが消えるため）。足したあと
`tools/namecheck/namecheck .copier-answers.yml` が通ることを確かめる。

## 4. リポジトリごとの表

| | modeldex | pixidex | sheaf |
|---|---|---|---|
| 撒いたコミット（そのリポジトリ側） | `002f3eb`（2026-09-14） | `21c7080`（2026-10-10） | `6182d5f`（2026-08-21） |
| **撒いた版 V**（dotfiles のコミット） | `c9bb1a4` | `3ba114c` | `25e1430` |
| V の確かめ | 下記 §4.1 | 下記 §4.1 | 下記 §4.1 |
| 言語 | Ruby | Ruby（`mise.toml` で 4.0.5） | Rust |
| **`language`** | **持ち主が決める**（§4.2） | **持ち主が決める**（§4.2） | `other` |
| `ruby_version`（`language=ruby` のとき） | 4.0.5（`mise.toml` と一致） | 4.0.5（同左） | 聞かれない |
| answers の既存の答え | `lint_cmd` = `bundle exec rubocop`、`test_cmd` = `bundle exec rake test` | `lint_cmd` / `test_cmd` ともに空 | 同左（空） |
| namecheck | あり | あり | 無し |
| 移行してよい時期 | `rspec-rubocop` の傘が終わってから | `master` に傘 `copier-update` が入ったあと（`language` の決定が済んでから） | 同左（`master` に入ったあと） |

### 4.1 撒いた版 V の割り出しの根拠

dotfiles の `master` で `templates/repo-baseline/` を変えたコミットのうち、撒いた日時の直前のものを
叩き台にし、**その版のテンプレートを、そのリポジトリの撒いたコミットの `.copier-answers.yml` の答えで
撒き直して、撒いたコミットの中身と突き合わせた**。テンプレートが生成するファイル
（`tools/doc-id/`・`.github/`・`.pre-commit-config.yaml` 等）が一致するかを見る。撒いた後に AI が
埋める `AGENTS.md`・`docs/README.md`・`opencode.json` の固有部分と、採番された文書の名前は一致しない。

| リポジトリ | V と一致した根拠 | 隣の候補と区別できた点 |
|---|---|---|
| sheaf | `25e1430`（#39。テンプレート化した最初のコミット）のテンプレートと、`tools/`・`.github/` 等が一致 | 次にテンプレートの生成物を変えたのは `e721b36`（2026-09-03）で、撒いた日（08-21）より後。その間の `336b1e5` は README だけを変えるので、生成物は同じ |
| modeldex | `c9bb1a4`（#94）のテンプレートと、`tools/doc-id/` を含め一致。`AGENTS.md` の最重要ルールが #94 で書き換わった後の文面 | 次の `6f927c6`（#111）は `tools/doc-id/` を変えるが、撒いた先の `tools/doc-id/` は #111 の前の版 |
| pixidex | `3ba114c`（#112）のテンプレートと一致。`AGENTS.md` の上流の取り込みが「rebase」の文面 | 次の `ae02266`（#133）は `tools/doc-id/` を変えるが、撒いた先は #133 の前の版 |

撒いた時点の `master` の先頭（sheaf `22c4309`・modeldex `c16be85`・pixidex `6c56278`）はいずれも
V と同じテンプレートの中身を持つので、`master` から撒かれたと見てよい。V は「テンプレートを最後に
変えたコミット」を使う（`master` の先頭を使っても同じ結果になる）。

### 4.2 `language` の答え方（持ち主の判断を仰ぐ点）

`_skip_if_exists` のファイル（`.rubocop.yml`・`.ruby-version`・`.rspec`・`Gemfile`・`Rakefile`・
`spec/spec_helper.rb`）は **update でも効く**（既にあるファイルは上書きされず、テンプレートの直しも
届かない）。模擬で、modeldex の `Gemfile`・`.rubocop.yml`・`Rakefile` が `language=ruby` の update 後も
手つかずで残ることを確かめた。無いファイルは新規に生成される。

`language=ruby` と `other` の結果の違い（模擬による）:

| | modeldex | pixidex |
|---|---|---|
| `other` | 衝突なし。`tools/doc-id/` の修正と `AGENTS.md` の最重要ルールの更新が入るだけ | `AGENTS.md` に衝突1箇所（lint・テストの段落）。ほかは `tools/doc-id/` の修正 |
| `ruby`（`ruby_version=4.0.5`） | 上に加え、`.ruby-version`・`.rspec`・`spec/spec_helper.rb` が新規生成、`ci.yml` に Ruby の準備が足される。`.pre-commit-config.yaml` に衝突2箇所（lint・test フックの `files:`）。`AGENTS.md` に「テストは RSpec」の段落が足される | `Gemfile`・`.rubocop.yml`・`.rspec`・`.ruby-version`・`Rakefile`・`spec/spec_helper.rb` がすべて新規生成、`ci.yml` に Ruby の準備が足される。`AGENTS.md` に衝突1箇所（lint・テストの段落） |

**AI は `language` を推測で決めない。** 判断材料は次のとおり。

- **modeldex**: 今のテストは minitest（`test_cmd` が `bundle exec rake test`）で、`.rspec`・`spec/` は無い。
  `ruby` と答えると `AGENTS.md` に「テストは RSpec」と生成されるので、RSpec への移行（`rspec-rubocop`
  の傘）が終わる前に `ruby` で update すると、現状と食い違う。傘が終わってから移行するのは、
  この点でも筋が合う。移行した時点の実態（RSpec になっているか）を見て `ruby` か `other` かを決める
- **pixidex**: Ruby のスクリプトはあるが、`Gemfile`・`.rubocop.yml` 等のプロジェクトの足場がまだ無く、
  lint・テストのコマンドも未確定（answers が空）。`ruby` と答えると、足場一式（`Gemfile`・RSpec・RuboCop の
  設定）が新規生成される。足場をテンプレートの既定で持つか、`other` のまま足場を自分で決めるかは持ち主が決める。
  足場を作る作業の前に `other` で移行し、足場ができた後に改めて `language` を変える手もある
  （`language` を変える update が通ることは未検証）
- **sheaf**: Rust なので `other`。聞かれないので `ruby_version` は渡さない

## 5. リポジトリごとの注意（update で衝突・追加が出るファイル）

模擬は、各リポジトリの `main` を `mktemp -d` に `git clone` した複製で、上の手順どおりに行った
（本物には触れていない）。`--vcs-ref` には、この傘の作業ツリーのコミットを使った。

### 5.1 sheaf（`language=other`）

- update は通る（`tools/doc-id/` の修正が入る）。**`AGENTS.md` に衝突が5箇所**出る。リポジトリ固有の
  規則・節がテンプレート由来の節と隣り合っており、テンプレート側の更新（最重要ルール・テスト方針・
  コミット前の必須ステップの節）と同じ範囲を触って衝突する。固有の規則を黙って捨てない。
  解いたあと、同名の節が二重になっていないかも見る
- **`.claude/pr-review.yml` が新規生成される**（V の後にできたファイル）。`convention_docs` が
  `docs/design/DOC-DOCID_PLACEHOLDER_プルリクエストの作法.md` のプレースホルダのまま出る。
  update は採番しないので、実在する PR の作法の文書のパスへ手で書き換える（残すと切れた参照になる）。
  スキル §5 のとおり、`.claude/pr-review.yml` が git に追跡される状態かも確かめる
- 撒いたコミット以降に `.copier-answers.yml` の答えに増えたものは `language` だけ
- 読み取り時点で、作業ツリーが `main` ではないブランチにあり未コミットの変更があった。
  移行は `main` から切ったきれいな作業ツリーで行う

### 5.2 modeldex

- `language=other`: 衝突なし。`AGENTS.md` の最重要ルール（git 操作の規則）が V 以降の版に
  置き換わり（上流の取り込みは rebase）、`tools/doc-id/` の修正が入る
- `language=ruby`: 上の表のとおり、`.pre-commit-config.yaml` に衝突2箇所。どちらも、リポジトリが
  意図して絞った `files:` の正規表現と、テンプレートの汎用の正規表現がぶつかる。リポジトリ側の
  絞り込みを残すか、テンプレートの汎用のものに寄せるかは、両方を人間に見せて決める
- `Gemfile`・`.rubocop.yml`・`Rakefile` は残る（`_skip_if_exists`）。差分が気になるときはスキル §3 の
  とおり、人間に差分を見せて判断を仰ぐ
- namecheck: `_src_path` を URL に書き換えると `.copier-answers.yml` が `manemone` の固有名詞として
  検出される。許可リストに足すと通る（模擬で確認）

### 5.3 pixidex

- `AGENTS.md` に衝突1箇所（lint・テストのコマンドについての段落）。`language` が `other` でも `ruby`
  でも同じ段落で出る。どちらを採るかは、足場の決定（§4.2）に連動する
- `.pre-commit-config.yaml` は、V の後に足した namecheck のフックがあっても衝突しなかった
- namecheck: modeldex と同じ（許可リストに足すと通る。模擬で確認）

## 6. 模擬の結果（2026-10-11）

3つのリポジトリの複製すべてで、この手順（橋渡しのコミット S・`--vcs-ref` に本物のコミット）の update が
通った。いずれも **`_commit` は S ではなく本物のコミットに進み**（`v20130702_00-195-g7e735d7` の形）、
V 以降のテンプレートの直し（`tools/doc-id/` の修正・`AGENTS.md` の更新）が取り込まれ、衝突の印が
付いたのは上の「5.」に書いたファイルだけだった。`.rej` は出なかった。`--trust` は不要だった。

- modeldex の複製（`language=other`）で、衝突なしの update をコミットし、続けて同じ `--vcs-ref` で
  update をもう一度回すと `Keeping template version`（変更なし）で終わり、作業ツリーに差分は出ない
- 模擬では撒く元に、この傘の作業ツリーのコミットを含む使い捨てのクローンを使った。**本番では
  `master` に傘がマージされたあとの `origin/master` を `--vcs-ref` に使い、手順 7 で `_src_path` を
  git の URL にする**
- 手順書どおりに橋渡しが成立したので、フォールバック（§7）は使っていない

## 7. 橋渡しが成立しなかったときのフォールバック

橋渡しの update が落ちる・3者マージの元が明らかにおかしいときの代替。ADR DOC-2610110435 §4 の最後の段落。

1. `_commit` に「ルートの `copier.yml` を含む最初のコミット」を書いて update する（`--vcs-ref` は同じ）
2. 3者マージの元が撒いた版より新しいので、V からそのコミットまでのテンプレートの直しは届かない。
   V のテンプレートとそのコミットのテンプレートを**同じ答えで**使い捨ての場所に撒き、差分を作って
   人間に見せ、必要なものを手で取り込む（`git diff --no-index <V で撒いた結果> <そのコミットで撒いた結果>`）

このフォールバックは使わずに済んだ（§6）。手順は書いただけで、模擬していない。

## 8. 持ち主に判断を仰ぐ点（まとめ）

- modeldex の `language`（`rspec-rubocop` の傘が終わった時点の実態で決める）
- pixidex の `language`（足場をテンプレートの既定で持つか）と、その移行の時期
- 衝突の解き方（リポジトリ固有の規則を残す／テンプレートに寄せる）は、移行のたびに差分を見て人間が決める
