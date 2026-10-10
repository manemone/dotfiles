# ADR: repo-baseline の copier.yml をリポジトリのルートに置き、copier update を使えるようにする

## ステータス

確定（2026-10-11）

## 1. 背景

repo-baseline テンプレートの `copier.yml` は `templates/repo-baseline/` というリポジトリの
サブディレクトリにあった。この形だと、撒いた先の `.copier-answers.yml` に撒いた版 `_commit` が
記録されず、`copier update` は `Updating is only supported in git-tracked templates.` で使えない
（[ADR DOC-2610110216](DOC-2610110216_ruby-defaults-in-repo-baseline.md) 等はこの時点の事実を記録している）。
テンプレートの直しが、既に撒いたリポジトリへ自動では届かなかった。

## 2. 決定

### 2.1 案 A: ルートに `copier.yml` を置き、`_subdirectory` で中身を指す

dotfiles のルートの `copier.yml` に `_subdirectory: templates/repo-baseline/template` を書く。
これで元（`_src_path`）が git リポジトリのルートになり、`_commit` が記録され、`copier update` が
使える。リポジトリの他のフォルダ（`AGENTS.md`・`opencode.json` 等）は撒かれない。

案 B（テンプレートを独立したリポジトリへ切り出す）は採らなかった。持ち主が A を選んだ。
B ではテンプレートとそれを使うスキル（`skills/repo-baseline/`）が別のリポジトリになり、
両者を同時に直せなくなる。

入口は1つだけにする。古い場所（`templates/repo-baseline/copier.yml`）には残さない。
2つあるとどちらで撒いたかで update できるかが変わるため。

`templates/repo-baseline/` の「自己完結」は、`copier.yml` だけが外に出る形に変わる。切り出すときは
`copier.yml` を一緒に移し、`_subdirectory` を `template` に戻す。

将来の課題: dotfiles に2つ目のテンプレートを足したくなったら、ルートの入口は1つしか置けない。
そのときは切り出し等を改めて決める。

### 2.2 撒く元の推奨と `_src_path`

- 推奨は公開の HTTPS の git URL（`https://github.com/manemone/dotfiles.git`）。どのマシンでも update できる。
  URL から撒くとリモートの既定ブランチ（`master`）の HEAD が撒かれる。マージ前の直しを試すときは
  ローカルの絶対パス（必要なら `--vcs-ref`）を使う。ただし元の作業ツリーに未コミットの変更があると、
  copier は変更を一時クローンの中でコミットして撒くため、`_commit` にどのリポジトリにも存在しない
  コミットが記録され、撒いた先は `copier update` できなくなる（レビューで再現）。試すときは元の変更を
  コミットしてから撒き、`_commit` が本物のコミットであることを確かめる。
- 相対パスは使わない（update が失敗する）。
- **`_src_path` を伏せない。** 伏せると update できない。namecheck を持つリポジトリでは、許可リスト
  （`tools/namecheck/allowlist.txt`）に `.copier-answers.yml` を足す（持ち主が許可。2026-10-11）。
  copier は update のたびに `.copier-answers.yml` を書き直すので、行末の `namecheck:allow-line` は
  消えてしまい、ファイル単位の許可しか手が無い。
- タグは打たない。copier は PEP 440 として読めるタグを優先するため、打つなら運用ごと決める必要がある。
  dotfiles の古いタグ `v20130702_00` は PEP 440 として読めず無視され、版は HEAD
  （`0.0.0.postN.devM+<sha>`）になる。`_commit` は `git describe` 形式
  （`v20130702_00-189-g<sha>`）で記録されるが、`g<sha>` で一意に解決され 2013 年のコミットにはならない。

## 3. 確かめた結果（copier 9.18.2、使い捨てのディレクトリ）

- ルートの入口から `language=ruby`・`other` の両方で撒くと `_commit` が記録され、テンプレートの外の
  ファイルは紛れ込まない。`--trust` は不要。`tests/template_smoke.sh` が `_commit` を検査する。
- テンプレート側を変えてコミットすると `copier update` が通り、変更が取り込まれる。両側が同じ行を
  変えた `AGENTS.md` にだけ `<<<<<<< before updating` の衝突の印が付く。`_skip_if_exists` のファイル
  （`Rakefile`・`.rubocop.yml` 等）は update でも既存のものが残る。
- スモークに update の3者マージは入れなかった（実行時間とクローンの準備が見合わない）。手で確かめた。

## 4. 旧形からの移行

旧形（`_commit` 無し）で撒いたリポジトリは、answers に `_commit` を手で書けば update できるが、
**ルートの `copier.yml` が無い版を `_commit` に書くと成立しない。** copier はその版に
`_subdirectory` を読めず、リポジトリ全体をテンプレートとして撒いて3者マージの元にし、
非 ASCII のファイル名で `FileNotFoundError` を出して落ちる（`_commit` = ルート移動の前のコミットで再現）。

`_commit` を「ルートの `copier.yml` を含む最初のコミット」にすれば通るが、3者マージの元が撒いた版より
新しくなり、撒いた版からそのコミットまでのテンプレートの直しが update で届かない。

そこで**橋渡しのコミット**を使う（成立を確認した）:

1. 使い捨てのクローンで、撒いた版 V から一時ブランチを切り、V の `copier.yml` をルートへ写して
   `_subdirectory` を付けてコミットする（S。入口だけルートにある V のテンプレートそのもの）。**push しない**
2. 移行先の answers に `_commit: S`・`_src_path: <そのクローンの絶対パス>` を書き、
   `copier update --vcs-ref <ルートの copier.yml を含む本物のコミット>` を実行する。
3. 3者マージの元が V になるので、V 以降のテンプレートの直しが届き、両側で変えた行にだけ衝突の印が付く
   （V = ルート移動前の版で確認。V 以降の `tools/doc-id/` の修正・`AGENTS.md` の追記が取り込まれ、
   手元の変更とは衝突しなかった）。
4. update 後、answers の `_commit` は本物のコミットになる。`_src_path` を git の URL に書き換える。

橋渡しが成立しない場合のフォールバック（`_commit` を最初のコミットにし、V と最初のコミットのテンプレートを
同じ答えで撒いた差分を人が手で取り込む）は、手順書で扱う。

## 5. 影響

- 追随: `tests/template_smoke.sh`・`templates/repo-baseline/README.md`・`AGENTS.md`・`README.md`。
  スキルと移行の手順書は別の孫で扱う。
- deploy は `AVAILABLE_TOOLS` と `shared/` だけを世代へコピーするため、ルートの `copier.yml` の影響を受けない。
