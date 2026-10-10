# 計画書: repo-baseline テンプレートで `copier update` を使えるようにする

傘ブランチ: `copier-update`
ターゲット: `master`

## 概要

dotfiles のリポジトリのルートに `copier.yml` を置き、`_subdirectory` で repo-baseline テンプレートの中身
（`templates/repo-baseline/template`）を指す。これで撒いた先の `.copier-answers.yml` に `_commit` が記録され、
テンプレートの直しを `copier update`（3者マージ）で既存のリポジトリへ届けられるようにする。あわせて、
スキル `repo-baseline` の更新手順を書き直し、**既に撒いたリポジトリ（modeldex・pixidex・sheaf）を
update できる形へ移すための手順書**を作る（実際の移行はこの傘ではしない）。

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。転記後に削除済みで
> 参照できない前提で書く）を material として司令官が起草したものである。** ブリーフに
> 書かれていた問題意識（持ち主の発言の逐語）・決定事項・実測・既存の穴・移行の対象・制約・
> スコープ外・検証ステップは本計画書へ転記済みであり、以降はこの計画書が正典である。
> ブリーフの「孫分割の叩き台」は司令官が検討し、3本の分け方はそのまま、各孫の受け持ちを
> 一部入れ替えて確定させた（「孫分割の判断」参照）。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `cpu-01-root-entry` | ルートの `copier.yml`（入口の移動）・answers の雛形のコメント・スモークと README の追随・ADR。本物のテンプレートでの撒く・更新と、旧形からの移行の成立性の確かめ | ⬜ 待機中 |
| 2 | `cpu-02-skill` | スキル `repo-baseline` の更新（撒く元の推奨・`_src_path` を伏せない・namecheck の許可リスト・update の手順と衝突の解き方） | ⬜ 待機中 |
| 3 | `cpu-03-migration` | 既に撒いたリポジトリの移行の手順書（各リポジトリの撒いた版・`language` の答え方・衝突しやすいファイル）と、複製での模擬 | ⬜ 待機中 |

依存: 孫1 → 孫2 → 孫3 の順に直列で進める（孫2 は孫1 で決まった入口と撒く元を前提に書き、孫3 は
孫2 の update の手順を前提に、リポジトリごとの差分だけを手順書に書く）。

## ワークスペースラベル

- 傘: `dotfiles :: copier update`
- 孫1: `dotfiles :: copier update 孫1 ルートの入口`
- 孫2: `dotfiles :: copier update 孫2 スキル`
- 孫3: `dotfiles :: copier update 孫3 移行の手順書`

---

## 背景1: 問題意識（持ち主の発言の逐語）

2026-10-11。直前の傘（`ruby-defaults`、PR #133）でテンプレートに Ruby の既定を足したが、相談AIが
「`copier update` が使えないので、テンプレートの直しは既存のリポジトリ（modeldex・pixidex・sheaf）へ
自動では届かない」と報告したところ、持ち主:

> copier に関してはなんか直せないの。

相談AIが実験で原因と直し方を確かめ（背景3「実測」）、2 案（A: dotfiles のルートに copier.yml を置く／
B: テンプレートを独立したリポジトリに切り出す）と、`_src_path` を本物に戻すと namecheck に当たる件を
示したところ、持ち主:

> Aでよい。足していい。

（「足していい」= namecheck の許可リストに `.copier-answers.yml` を足してよい）

## 背景2: 人間が確定させた決定事項（覆さないこと）

- **案 A: dotfiles のリポジトリのルートに `copier.yml` を置き、`_subdirectory` でテンプレートの中身
  （`templates/repo-baseline/template`）を指す。** テンプレートを独立したリポジトリには切り出さない
- **namecheck を持つリポジトリでは、namecheck の許可リスト（`tools/namecheck/allowlist.txt`）に
  `.copier-answers.yml` を足してよい**（2026-10-11、持ち主）。理由: update には本当の `_src_path` が要り、
  git の URL にはユーザー名が入るので namecheck に当たる。copier は update のたびに `.copier-answers.yml` を
  書き直すので、行末の `namecheck:allow-line` は消える。ファイル単位の許可しか手が無い

## 背景3: 実測（2026-10-11、相談AI、copier 9.18.2、使い捨てのディレクトリで）

| 置き方 | `_commit`（撒いた版） | `copier update` |
|---|---|---|
| **今の dotfiles と同じ形**（`<repo>/templates/<name>/copier.yml`。リポジトリの中のサブディレクトリ） | **記録されない** | できない（`Updating is only supported in git-tracked templates.`） |
| **copier.yml をリポジトリのルートに置き `_subdirectory` で中身を指す**（中身が深い場所 `templates/rb/template` でも可。リポジトリの他のフォルダは撒かれない） | 記録される | **できる**。タグが無くても HEAD を版として使う（`No git tags found in template; using HEAD as ref`、版は `0.0.0.postN.devM+<sha>`） |
| **既に撒いたリポジトリ**（`_commit` 無し・`_src_path` がサブディレクトリ）の answers に、撒いたときの版（`_commit`）と本当の元（ルート）を**手で書く** | 手で足した | **できる**。3者マージが効き、両側で同じ行を変えたところには `<<<<<<< before updating` 〜 `>>>>>>> after updating` の衝突の印が付く。余計なファイルは撒かれなかった |

補足（ブリーフの逐語に近い形で転記）:

- 手で書いた `_commit` の時点ではルートの copier.yml がまだ存在しなかったが、update は正しく動いた
  （ただし実験は小さいテンプレート 1 つ。**本物のテンプレートで確かめ直すこと**）
- 最初の実験で `_src_path` が相対パスだったために update が失敗した。**`_src_path` は絶対パスか git の
  URL にすること**
- `skills/repo-baseline/SKILL.md` §2 の「`_commit` を手で足しても `Updating is only supported in
  git-tracked templates.` で止まる」は、元がリポジトリのルートでなかったことが原因だった
- 実験は `--defaults --trust` で回した。本物のテンプレートで `--trust` が要るか（`_tasks` などの有無）は
  確かめていない

## 背景4: 既存の穴

- `templates/repo-baseline/copier.yml` がリポジトリの中のサブディレクトリにあるため、`_commit` が
  記録されず update できない
- `skills/repo-baseline/SKILL.md` §2「既存導入の更新」が「現時点では `copier update` は使えない」と
  書いている（`templates/repo-baseline/README.md`「使い方: 更新」「検証結果」も同じ）
- テンプレートが生成する `.copier-answers.yml` の雛形
  （`templates/repo-baseline/template/{{ _copier_conf.answers_file }}.jinja`）の冒頭のコメントも
  「update できない」と書いている
- **既に撒いたリポジトリの `_src_path` が伏せてある。** modeldex・pixidex（相談AIが、namecheck に当たるのを
  避けるため `SRC_PATH_NOT_RECORDED_SEE_COMMENT_ABOVE` に書き換えた）。このままでは update できない。
  **新しく撒くときに `_src_path` を伏せる運用はやめる**（スキルに書く）
- **直前の傘で `language`（`ruby`／`other`）と `ruby_version` の質問が増えた。** 既に撒いたリポジトリの
  answers にはこの答えが無い
  - `--defaults` で update すると `language` は既定の `other` になる
  - `ruby` と答えると、テンプレートが `.rubocop.yml`・`Gemfile`・`.rspec`・`spec/spec_helper.rb`・
    `Rakefile`・`.ruby-version` を生成しようとし、自前でそれらを持つリポジトリ（modeldex・pixidex）と
    衝突する。`ruby_version` の既定は `"3.3"` で、modeldex・pixidex は 4.0.5
  - **移行の手順書で、リポジトリごとに答え方を決めること**

## 背景5: 既に撒いたリポジトリ（移行の対象。この傘では移行しない）

| リポジトリ | 撒いたコミット（そのリポジトリ側） | 撒いた日時 | 言語 | namecheck |
|---|---|---|---|---|
| modeldex（`~/projects/modeldex/main`） | `002f3eb` | 2026-09-14 02:18 | Ruby | あり |
| pixidex（`~/projects/pixidex/main`） | `21c7080` | 2026-10-10 11:04 | Ruby | あり |
| sheaf（`~/projects/sheaf/main`） | `6182d5f` | 2026-08-21 09:18 | Rust | 無し |

**それぞれが dotfiles のどのコミットから撒かれたか（`_commit` に書く値）を、この傘で割り出して手順書に
載せること**（撒いた日時と dotfiles の `templates/repo-baseline/` の履歴から。相談AIは割り出していない）。
pixidex を撒いたときの dotfiles の `master` は `6c56278` だった見込み（相談AIの記憶）。

**司令官の下調べ（孫3 が確かめ直す叩き台）**: `git log --first-parent master --before=<撒いた日時>` で
撒いた時点の `master` の先頭を引くと次のとおり。`templates/repo-baseline/` を変えた `master` のコミットとの
前後関係も併記する（その区間ならテンプレートの中身は同じ）。

| リポジトリ | 撒いた時点の `master` の先頭 | その直前に `templates/repo-baseline/` を変えたコミット | 直後に変えたコミット |
|---|---|---|---|
| sheaf | `22c4309`（2026-08-15） | `25e1430`（2026-08-03） | `336b1e5`（2026-08-27） |
| modeldex | `c16be85`（2026-09-13 11:53） | `c9bb1a4`（2026-09-13 00:31） | `6f927c6`（2026-09-20） |
| pixidex | `6c56278`（2026-09-27。相談AIの記憶と一致） | `3ba114c`（2026-09-20） | `ae02266`（2026-10-11） |

ただし**持ち主が `master` 以外（傘ブランチ・ローカルの作業ツリー）から撒いた可能性は排除できていない。**
孫3 は、その版のテンプレートをそのリポジトリの answers で撒き直した結果と、そのリポジトリ側の撒いた
コミットの中身を突き合わせて確かめる。

## 背景6: 司令官が調べた dotfiles 側の前提

- **入口を参照している箇所**（孫1 が追随させる）: `skills/repo-baseline/SKILL.md`（`copier copy` の例と
  §2）・`templates/repo-baseline/README.md`（使い方・更新・検証結果）・`tests/template_smoke.sh`
  （`TEMPLATE_DIR="$REPO_ROOT/templates/repo-baseline"`）・ルート `AGENTS.md`（「コミット前の必須ステップ」の
  `tests/template_smoke.sh` の説明、「ディレクトリ構成」の `templates/` の行）・answers の雛形。
  `git grep -n -e copier.yml -e repo-baseline -e _src_path -e "copier update" -e "copier copy"` で洗い直すこと
- **deploy への影響**: `deploy-all.sh` が世代へコピーするのは `AVAILABLE_TOOLS`（`zsh nvim tmux bin claude
  skills codex opencode`）と `shared/` だけで、ルートのファイルは対象外。ルートに `copier.yml` を置いても
  世代の中身は変わらない見込みだが、孫1 が `./deploy-all.sh --dry-run` と `tests/deploy_smoke.sh` で確かめる
- **ルートには `opencode.json`（このリポジトリで作業する AI 向けの設定）・`AGENTS.md`・`CLAUDE.md` もある。**
  `_subdirectory` で中身を指すので撒かれないはずだが、撒いた結果にこれらが紛れ込まないことを確かめる
- **ルートの `copier.yml` は pre-commit の `check-yaml` の対象になる。** 今の `copier.yml` は Jinja を
  文字列として持つだけの素の YAML なので通る見込み
- **dotfiles には古いタグ `v20130702_00`（2013-07-02）が1本ある。** copier は git の URL から撒くとき、
  PEP 440 として読めるタグの最新を版に使う。このタグは PEP 440 として読めない
  （`packaging.version.Version` で `InvalidVersion`。2026-10-11 に司令官が確認）ので無視され HEAD が使われる
  見込みだが、**孫1 が本物の URL（または本物のリポジトリのクローン）で、撒いた版が HEAD 由来
  （`0.0.0.postN.devM+<sha>`）になり 2013 年のコミットにならないことを確かめる**
- **撒く元のリポジトリは公開リポジトリ**（`github.com/manemone/dotfiles`、既定ブランチ `master`）。
  HTTPS の URL なら認証なしで、どのマシンからでも撒ける・update できる
- **テンプレートの `_skip_if_exists`（`.rubocop.yml`・`.ruby-version`・`.rspec`・`Gemfile`・`Rakefile`・
  `spec/spec_helper.rb`）は update のときにも効く**かどうかで、Ruby のリポジトリの移行の答え方が変わる
  （孫3 が確かめる）
- **テンプレートの「自己完結」の原則**（`templates/repo-baseline/README.md`）: 今は `templates/repo-baseline/`
  の中で完結しているが、入口がルートに出ると、テンプレートの一部（`copier.yml`）がディレクトリの外に出る。
  README と ADR でこの変化を説明する

---

## 設計1: 司令官が確定させた外形（孫はこれに従う）

**細部は孫が決めてよいが、ここに書いた線は動かさない。** 動かす必要があると判断したら、実装を止めて
司令官に理由を報告すること。

### 1.1 入口は1つ（ルートの `copier.yml`）

- `templates/repo-baseline/copier.yml` をルートの `copier.yml` へ**移す**（`git mv`）。古い場所には残さない。
  2つあると、どちらで撒いたかで update できるかが変わるため（ブリーフの制約）
- `_subdirectory: templates/repo-baseline/template` にする。他の中身（質問・`_exclude`・`_skip_if_exists`）は
  変えない。`_exclude` の `copier.yml` 等は `_subdirectory` の中に対して効くので、そのままでよい
- ルートの `copier.yml` の冒頭のコメントに、「これは repo-baseline テンプレートの設定で、ルートに置くのは
  update のため（ADR 参照）」と書く。dotfiles を読む人が、なぜルートに copier の設定があるのか分かるように
- 将来2つ目のテンプレートを dotfiles に足したくなったら、ルートの入口は1つしか置けない。そのときの選択肢
  （切り出し等）は ADR に「将来の課題」として一文書くだけで、この傘では何もしない

### 1.2 撒く元（`_src_path`）の推奨

- **推奨は dotfiles の公開 HTTPS の git URL**（`https://github.com/manemone/dotfiles.git`）。どのマシンでも
  撒ける・update できる。ローカルの絶対パスは、そのマシンでしか update できない
- git URL から撒くと、撒かれるのは**リモートの既定ブランチ（`master`）の HEAD**である。マージ前の
  テンプレートの直しを試すときは、ローカルの絶対パス（+ 必要なら `--vcs-ref`）を使う。この使い分けを
  スキル（孫2）に書く
- 相対パスは使わない（背景3: update が失敗する）
- **`_src_path` を伏せない。** 伏せると update できない。namecheck を持つリポジトリでは、許可リストに
  `.copier-answers.yml` を足す（背景2）
- タグを打つ運用はこの傘では始めない（HEAD を版として使う。背景3）。打つと copier はタグを優先するため、
  打つなら運用ごと決める必要がある、と ADR に一文書く

### 1.3 answers の雛形のコメント

`{{ _copier_conf.answers_file }}.jinja` の冒頭のコメントを、「`copier update` で上流の更新を取り込める。
手で編集しない（`_commit` と `_src_path` は update が使う）」という趣旨に直す。リポジトリ名やユーザー名を
コメントに書かない（namecheck に当たる）。

### 1.4 ADR

孫1 が ADR を1本書く（`docs/adr/`）。記録する決定: 案 A を採ったこと（案 B を採らなかった理由は持ち主の
選択と、切り出すとテンプレートと dotfiles のスキルが別々のリポジトリになる等の比較）、入口を1つにした
こと（1.1）、撒く元の推奨（1.2）、`_src_path` を伏せない・namecheck の許可リスト（背景2）、
タグの扱い（1.2）、旧形からの移行が成立する根拠（孫1 の確かめの結果）。

既存の ADR DOC-2610110216 と計画書 DOC-2608020558 の「update は使えない」は、その時点の事実の記録なので
書き換えない。必要なら DOC-2610110216 の末尾に「後の ADR で update できるようになった」旨の参照を
一行足すかどうかを孫1 が決める（`docs/README.md` の ADR の扱いに従う）。

### 1.5 移行の手順書の置き場所

孫3 が `docs/reference/` に置く（3つのリポジトリで繰り返し引く手順。`docs/reference/` の
「配布実体運用ガイド」に移行手順を置いた前例がある）。**このリポジトリは公開リポジトリなので、他の
リポジトリの中身（コード・計画書の本文）は転載しない。** リポジトリ名・コミット・ファイル名・答えの値の
言及は構わない。

## 孫分割の判断

ブリーフの叩き台（1. ルートの `copier.yml` と雛形、2. スキル、3. 移行の手順書と模擬）の3本をそのまま
採った。変えた点:

- **旧形からの移行が成立するか（背景3 の3行目）を、孫1 の確かめに前倒しした。** 叩き台では孫3 の模擬で
  初めて本物のテンプレートで確かめることになるが、これが成立しなければ手順書の前提が崩れ、スキル（孫2）の
  書き方も変わる。ルートの入口を作った直後に、最小の形（1つの旧形の複製で update が通るか）だけ確かめる。
  リポジトリごとの詳細（撒いた版の割り出し・`language` の答え方・衝突しやすいファイル）は孫3 に残す
- **ADR と README・スモークの追随を孫1 に入れた。** 入口の移動と同時に直さないと、スモークが壊れ、README が
  嘘になるため
- **孫3 がスキルを直すことを許した。** 模擬で、孫2 の書いた update の手順に足りないところが見つかったら、
  孫3 がスキルも直す（手順書から参照しているため）

**旧形からの移行で司令官が気にしている点**（孫1 が確かめる）: 手で書いた `_commit` の版にはルートの
`copier.yml` が無い。copier が3者マージの「元」を作るために古い版を撒き直すとき、その版の設定をどう読むか
（ルートに設定が無い版を、リポジトリ全体をテンプレートとして撒いてしまわないか）で、3者マージの元が
正しくなるかが決まる。小さい実験では正しく動いた（背景3）が、本物でも元が正しいか（例: 両側で同じ行を
変えたところだけに衝突の印が付き、テンプレート側だけで変えたところはそのまま取り込まれるか）を確かめる。
**成立しなかった場合は、孫1 は止めて司令官に報告する**（代替案——たとえば最初の1回だけ `copier recopy`
相当で撒き直して差分を人が解く——を決めるのは司令官と持ち主）。

## 決定的な制約（孫は全部守ること）

- dotfiles の `AGENTS.md` に従う。特に:
  - **`master` を書き換える操作は人間だけ**（孫 → 傘のマージは承認済み PR に限り AI）
  - **deploy スクリプトを AI が実オペレーションで実行しない**（スキルの配布は、マージ後に持ち主の指示で
    行う。確かめは `./deploy-all.sh --dry-run` と `tests/deploy_smoke.sh`）
  - linter の抑制・除外・閾値緩和を AI の判断で足さない
- **ルートに `copier.yml` を置いても、dotfiles の他の働き（deploy・各ツール）に影響しないこと**を確かめる
- **入口は1つにする**（設計1.1）
- `copier copy` のときの元は、**他のマシンでも使えるよう git の URL を推奨する**（設計1.2）
- **本物の modeldex・pixidex・sheaf は触らない。** 確かめは複製（`mktemp -d` で作った場所への
  `git clone` 等）で行う。複製から push しない
- **このリポジトリは公開リポジトリである。** 他のリポジトリの中身を転載しない（設計1.5）
- 指示された範囲外の機能を先回りして実装しない（スコープ外の節を参照）

## スコープ外

- **既存のリポジトリ（modeldex・pixidex・sheaf）の実際の移行。** この傘は手順書まで。移行はそれぞれの
  リポジトリで、手順書ができてから行う。**modeldex は、今動いている RSpec 移行の傘（`rspec-rubocop`）が
  終わってから**（両方が `.pre-commit-config.yaml`・`AGENTS.md` を触るため）
- テンプレートを独立したリポジトリに切り出すこと（持ち主が案 A を選んだ）
- 確認系の道具を pre-commit のリモートフックで配ること、modeldex の namecheck をテンプレートへ取り込むこと
  （持ち主が頼んでいない）
- テンプレートにタグを打つ運用（設計1.2）

## 必須の検証ステップ（省略しない）

- dotfiles の `AGENTS.md`「コミット前の必須ステップ」に従う:
  - 新規ファイルを足した・大きく変えたら、その時点で `pre-commit run --files <path>`
  - まとめて確かめるときは `pre-commit run --all-files`
  - **`templates/repo-baseline/` 配下・ルートの `copier.yml` を変えたら `tests/template_smoke.sh`**
  - スキル・deploy に関わる変更なら `./deploy-all.sh --dry-run` と `tests/deploy_smoke.sh`（サンドボックス）
  - `docs/` に新規ファイルを足すときは `DOC-DOCID_PLACEHOLDER_<説明的ファイル名>.md` で作り、
    `./tools/doc-id/doc-id assign <path>` で採番する。`docs/README.md` の索引も更新する
- **本物のテンプレートで、使い捨てのディレクトリ（`mktemp -d`）に対して確かめる**（撒く先では `git init` して
  から `copier copy`）:
  1. 新しい入口（dotfiles のルート）から撒き、`_commit` が記録されること（Ruby・Ruby 以外の両方）。
     撒いた結果にルートの `AGENTS.md`・`opencode.json` 等、テンプレートの外のファイルが紛れ込まないこと
  2. テンプレート側を変えて `copier update` が通り、変えたところが取り込まれること（テンプレート側の変更は、
     dotfiles のクローンを使い捨ての場所に作り、そこでコミットして試す。傘や孫のブランチに試しのコミットを
     積まない）
  3. **既に撒いたリポジトリの移行を模擬する**: 古い形で撒いた（`_commit` 無し・`_src_path` 伏せ）コピーに、
     手順書どおり `_commit` と `_src_path` を書き、`language` を決めて update が通ること。**本物の modeldex・
     pixidex・sheaf は触らない**（その複製で行う）
- `.copier-answers.yml` が namecheck の許可リストで通ること（namecheck を持つリポジトリの複製で）
- `--trust` が要るかを確かめ、要らないなら手順・スキルに `--trust` を書かない
- **CI の課金エラーは無視して、手元の `pre-commit` と上記のスモークで判定する**（持ち主の方針）

## テスト方針（AGENTS.md「テスト方針」に従う）

- **入口の移動で壊れうるのは、撒いた結果（生成物）と update できること。** 生成物の出し分けは既存の
  `tests/template_smoke.sh` が守っているので、入口を移したあともそれが通ることで守る（スモークの
  `TEMPLATE_DIR` をルートへ向け直す）
- **`_commit` が記録されること**は、入口を古い場所へ戻す・`_subdirectory` を壊すといった現実的な
  regression で黙って失われ、撒いた先で update しようとして初めて気づく。`tests/template_smoke.sh` の
  既存の `.copier-answers.yml` の検査に「`_commit` がある」を足す程度で守ることを推奨する（孫1 が実行時間と
  比べて決める）
- `copier update` の3者マージそのものをスモークに入れるかは、孫1 が実行時間とリスクを比べて決め、PR 説明に
  書く。入れないなら、手で確かめた結果を PR 説明に残す
- 移行の手順書（孫3）は文書であり、新しい自動テストは原則足さない。模擬の結果を PR 説明に残す

## 司令官の運用メモ（持ち主の方針）

- マージ済みの孫のワークツリーは `ocw rm` で片付け、孤児の Herdr ワークスペースは `herdr workspace close`
  まで面倒を見る
- 孫の停止を数分で検知する見張り（cron の巡回）を常に持つ

---

## 孫1用プロンプト:

````markdown
# 傘ブランチ: copier-update
# 孫ブランチ: cpu-01-root-entry
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/copier-update/docs/planning/DOC-2610110426_copier-update_計画.md`

**まず計画書の「概要」「背景1〜6」「設計1」「孫分割の判断」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」を全部読むこと。** 以下はその上での作業指示である。

## 実装開始前の必須手順

作業ブランチは**必ず `copier-update`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout copier-update
git fetch origin
git merge --ff-only origin/copier-update
git checkout -b cpu-01-root-entry
```

（`ocw` で作られたワークツリーで既に `cpu-01-root-entry` にいる場合は、`git fetch origin` のあと
`git log origin/copier-update -1` が自分のブランチの祖先にあることを確かめればよい）

## やること

1. `templates/repo-baseline/copier.yml` をルートの `copier.yml` へ `git mv` し、`_subdirectory` を
   `templates/repo-baseline/template` にする。冒頭のコメントを足す（計画書 設計1.1）
2. answers の雛形（`templates/repo-baseline/template/{{ _copier_conf.answers_file }}.jinja`）の冒頭の
   コメントを直す（設計1.3）
3. 入口を参照している箇所を追随させる（計画書 背景6 の1項目め。`git grep` で洗い直す）:
   `tests/template_smoke.sh` の `TEMPLATE_DIR`、`templates/repo-baseline/README.md`（使い方の
   `copier copy` の例・「使い方: 更新」・「検証結果」・「自己完結」の説明）、ルート `AGENTS.md`・
   ルート `README.md` の該当箇所。**`skills/repo-baseline/SKILL.md` は孫2 の受け持ち**なので、この孫では
   `copier copy` の例のパスが壊れないための最小限の修正にとどめる（§2 の書き換えはしない）
4. `tests/template_smoke.sh` の検査に「`.copier-answers.yml` に `_commit` がある」を足すか決める
   （計画書「テスト方針」）
5. ADR を1本書く（設計1.4）。`docs/adr/DOC-DOCID_PLACEHOLDER_<説明的な名前>.md` で作り
   `./tools/doc-id/doc-id assign` で採番、`docs/README.md` のクイックナビゲーションと全 DOC-ID 索引に足す。
   既存の ADR（例: `docs/adr/DOC-2610110216_ruby-defaults-in-repo-baseline.md`）の構成に倣う
6. 計画書「必須の検証ステップ」の本物のテンプレートでの確かめのうち **1・2 と、3 の最小の形**を行う:
   - 1: ルートから撒いて `_commit` が記録される（`language=ruby`・`other` の両方）。テンプレートの外の
     ファイルが紛れ込まない。`--trust` が要るか
   - 2: 使い捨ての場所の dotfiles のクローンでテンプレートを変えてコミットし、`copier update` で取り込まれる
   - 3 の最小の形: 古い形で撒いた複製（今の `master` の `templates/repo-baseline` から撒き、answers の
     `_src_path` を伏せた状態を作る。本物の modeldex 等は使わない）に、`_commit`（撒いた版）と `_src_path`
     （ルート）を手で書いて update が通るか。**3者マージの元が正しいか**（計画書「孫分割の判断」の
     「旧形からの移行で司令官が気にしている点」）を、テンプレート側だけの変更が取り込まれること・両側の
     変更にだけ衝突の印が付くことで確かめる。**成立しなければ止めて司令官に報告する**
   - 撒く元が git の URL（`https://github.com/manemone/dotfiles.git`）のときに、古いタグ
     `v20130702_00` ではなく HEAD が版に使われること（計画書 背景6。まだ `master` にルートの `copier.yml`
     が無いので、URL で撒く確かめは、dotfiles のクローンに同じ古いタグがある状態で代用してよい）
7. `./deploy-all.sh --dry-run` と `tests/deploy_smoke.sh` で、ルートの `copier.yml` が deploy に影響しない
   ことを確かめる

確かめた結果（撒いた版の表記・`--trust` の要否・update の出力・3者マージの元が正しかった根拠）は
PR 説明と ADR に書く。**孫2・孫3 がこれを読む。**

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 新しい入口から撒いた生成物が、入口を移す前と同じである（既存の `template_smoke.sh` の検査が
  そのまま通る）
- 新しい入口から撒くと `.copier-answers.yml` に `_commit` が記録される
- ルートの `copier.yml` が deploy の世代の中身・`$HOME` 側のリンクに影響しない（既存の
  `deploy_smoke.sh` と `deploy-all.sh --dry-run`）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files <変更・追加したファイル>
tests/template_smoke.sh
./deploy-all.sh --dry-run
tests/deploy_smoke.sh
pre-commit run --all-files
```

## 実装完了後

計画書末尾の「実装完了後の流れ（全孫共通・必須）」に従い、PR 作成・レビュー・傘へのマージまで
自律的にやりきること。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

---

## 孫2用プロンプト:

````markdown
# 傘ブランチ: copier-update
# 孫ブランチ: cpu-02-skill
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/copier-update/docs/planning/DOC-2610110426_copier-update_計画.md`

**まず計画書の「概要」「背景1〜6」「設計1」「孫分割の判断」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」を全部読むこと。** 次に、孫1 の PR
（`gh pr list --base copier-update --state merged` で `cpu-01-root-entry` を探す）の説明と、孫1 が書いた
ADR を読むこと。`--trust` の要否・撒いた版の表記・旧形からの移行が成立した根拠は、そこで確定している。
以下はその上での作業指示である。

## 実装開始前の必須手順

作業ブランチは**必ず `copier-update`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout copier-update
git fetch origin
git merge --ff-only origin/copier-update
git checkout -b cpu-02-skill
```

（`ocw` で作られたワークツリーで既に `cpu-02-skill` にいる場合は、`git fetch origin` のあと
`origin/copier-update` の最新（孫1 のマージを含む）が自分のブランチの祖先にあることを確かめればよい）

## やること

`skills/repo-baseline/SKILL.md` を、update できる前提に書き直す。

1. §2「新規導入」: 撒く元をルートにし、**推奨は git の URL**（計画書 設計1.2）。ローカルの絶対パスは
   マージ前のテンプレートを試すときだけ、相対パスは使わない、を理由とともに書く
2. **`_src_path` を伏せない**ことを書く（伏せると update できない）。namecheck を持つリポジトリでは
   `tools/namecheck/allowlist.txt` に `.copier-answers.yml` を足すこと、行末の `namecheck:allow-line` では
   だめな理由（update のたびに copier が書き直す）を書く（計画書 背景2）。namecheck を持たない
   リポジトリでは何もしない
3. §2「既存導入の更新」を書き直す: `copier update` の手順（作業ツリーをきれいにしてから・ブランチを切って・
   `--trust` の要否は孫1 の結果に従う）、増えた質問への答え方（既定値に流されず実態を見て答える。
   `--defaults` で回すと新しい質問は既定値になる）、**衝突の解き方**（`<<<<<<< before updating` 〜
   `>>>>>>> after updating` の印の意味・`.rej` が出る場合の扱い・解いたあとの確かめ）、`_skip_if_exists` の
   ファイルの扱い。update の結果は人間に差分を見せてからコミットする
4. **既に撒いたリポジトリ（`_commit` が無い・`_src_path` が伏せてある）を見つけたとき**は、移行の手順書
   （孫3 が `docs/reference/` に書く。まだ無いので、この孫では「手順書に従う」とだけ書き、パスは孫3 が
   埋める。リンク切れを作らないよう、DOC-ID の無いパスを書かない）に従う、と書く
5. 古い記述（「現時点では `copier update` は使えない」・独立リポジトリへの切り出しを待つ話・Ruby の既定を
   手で持ってくる段落のうち update で置き換わる部分）を消すか書き換える
6. `templates/repo-baseline/README.md` とスキルの記述が矛盾しないこと（README の二層構造）

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- スキルが全エージェント分配布される（既存の `deploy_smoke.sh` と `deploy-all.sh --dry-run`）
- スキルに書いた update の手順が、本物のテンプレートで実際に動く（使い捨てのディレクトリで、スキルの
  手順どおりに撒いて・テンプレート側を変えて・update して確かめ、結果を PR 説明に書く）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

この孫は主に文書の変更であり、新しい自動テストは原則として追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files <変更したファイル>
./deploy-all.sh --dry-run
tests/deploy_smoke.sh
pre-commit run --all-files
```

## 実装完了後

計画書末尾の「実装完了後の流れ（全孫共通・必須）」に従い、PR 作成・レビュー・傘へのマージまで
自律的にやりきること。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

---

## 孫3用プロンプト:

````markdown
# 傘ブランチ: copier-update
# 孫ブランチ: cpu-03-migration
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/copier-update/docs/planning/DOC-2610110426_copier-update_計画.md`

**まず計画書の「概要」「背景1〜6」「設計1」「孫分割の判断」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」を全部読むこと。** 次に、孫1・孫2 の PR
（`gh pr list --base copier-update --state merged`）の説明と、孫1 が書いた ADR、孫2 が書き直した
`skills/repo-baseline/SKILL.md` §2 を読むこと。以下はその上での作業指示である。

## 実装開始前の必須手順

作業ブランチは**必ず `copier-update`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout copier-update
git fetch origin
git merge --ff-only origin/copier-update
git checkout -b cpu-03-migration
```

（`ocw` で作られたワークツリーで既に `cpu-03-migration` にいる場合は、`git fetch origin` のあと
`origin/copier-update` の最新（孫1・孫2 のマージを含む）が自分のブランチの祖先にあることを確かめればよい）

## やること

既に撒いたリポジトリ（modeldex・pixidex・sheaf）を update できる形へ移す手順書を `docs/reference/` に書く
（計画書 設計1.5）。**移行そのものはしない。本物のリポジトリは読むだけで、書き込み・push をしない。**

1. **各リポジトリの撒いた版（`_commit` に書く値）を割り出す。** 計画書 背景5 の司令官の下調べを叩き台に、
   その版の dotfiles のテンプレートを、そのリポジトリの `.copier-answers.yml` の答えで使い捨ての場所に
   撒き直し、そのリポジトリ側の撒いたコミット（背景5 の表）の中身と突き合わせて確かめる。一致しない
   ときは、`master` 以外から撒いた可能性を含めて候補を探し、確かめられた範囲と根拠を手順書に書く
2. **各リポジトリの `language`・`ruby_version` の答え方を決める**（計画書 背景4 の最終項）。modeldex・
   pixidex は Ruby で `.rubocop.yml` 等を自前で持ち、Ruby は 4.0.5。sheaf は Rust。`ruby` と答えたときに
   `_skip_if_exists` が update で効くか（計画書 背景6）を確かめ、その結果に基づいて決める。決めきれない
   ものは持ち主に判断を仰ぐ点として手順書に明記する（AI が推測で決めない）
3. **手順書に書くこと**: 共通の手順（answers に `_commit` と `_src_path` を書く・`language` 等を答える・
   update・衝突を解く・namecheck の許可リスト）と、リポジトリごとの表（撒いた版・答え・最初の update で
   衝突しやすいファイルとその理由・namecheck の有無・移行してよい時期——modeldex は `rspec-rubocop` の傘が
   終わってから）。update の一般的な手順はスキル（孫2）を参照し、手順書には移行に固有のことだけを書く
4. **複製で模擬する**（計画書「必須の検証ステップ」の3と namecheck の項）: 3つのリポジトリそれぞれの
   複製（`mktemp -d` に `git clone`。push しない）で、手順書どおりに `_commit` と `_src_path` を書き、
   update が通ること・衝突の出方が手順書の記述と合うことを確かめる。namecheck を持つ複製では、許可リストに
   `.copier-answers.yml` を足して namecheck が通ることを確かめる。撒く元は dotfiles のこの傘の作業ツリー
   （ルートの `copier.yml` がまだ `master` に無いため。ローカルの絶対パス）で代用し、移行の本番では git の
   URL を書くことを手順書に明記する
5. 孫2 のスキルに、手順書の DOC-ID とパスを足す（孫2 が残した「手順書に従う」の箇所）。模擬で update の
   一般的な手順に足りないところが見つかったら、スキルも直す（計画書「孫分割の判断」）
6. 手順書は `docs/reference/DOC-DOCID_PLACEHOLDER_<説明的な名前>.md` で作り `./tools/doc-id/doc-id assign`
   で採番、`docs/README.md` のクイックナビゲーションと全 DOC-ID 索引に足す。**他のリポジトリの中身を転載
   しない**（計画書 設計1.5）

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 手順書どおりに移行すると、3つのリポジトリの複製すべてで update が通る（手で確かめ、結果を PR 説明に書く）
- namecheck を持つリポジトリの複製で、`.copier-answers.yml` が許可リストで通る
- スキルが全エージェント分配布される（既存の `deploy_smoke.sh` と `deploy-all.sh --dry-run`）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

この孫は主に文書の変更であり、新しい自動テストは原則として追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files <変更・追加したファイル>
./deploy-all.sh --dry-run
tests/deploy_smoke.sh
pre-commit run --all-files
```

## 実装完了後

計画書末尾の「実装完了後の流れ（全孫共通・必須）」に従い、PR 作成・レビュー・傘へのマージまで
自律的にやりきること。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

---

## 実装完了後の流れ（全孫共通・必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `copier-update` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）
5. （Herdr あり・司令官が宛先を渡したときだけ）マージを終えたら司令官へ完了を通知する。
   宛先は、司令官が spawn の送信文で渡した司令官の Herdr ペイン（渡されていなければ通知しない）。
   送り方は umbrella-orchestrator スキル §5「AI間送信手順（二段構え）」に従う。本文は
   「孫N `<孫ブランチ名>` の PR #<番号> を copier-update へマージしました。」だけにする
   （「〜とだけ返事して」のような指示は付けない）。通知は1回だけ。送れなくても止まらず
   （司令官の巡回が拾う）、送れなかったことを最終報告に1行書く

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `copier-update` から切ること**。
master から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
各孫用プロンプトの「実装開始前の必須手順」を、連結せず別々のコマンドとして実行すること
（`git pull` は使わない）。
