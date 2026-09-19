# 計画書: doc-id の参照書き換え・検証の不具合修正

傘ブランチ: `doc-id-link-integrity`
ターゲット: `master`

## 概要

`tools/doc-id`（と、その配布元の複製 `templates/repo-baseline/template/tools/doc-id`）には、
未採番文書（ファイル名が `DOC-DOCID_PLACEHOLDER_...`）どうしが互いにリンクしている状態で
1本ずつ `assign` すると**リンク切れを作り、しかも `verify` がそれを見逃す**不具合がある。
repo-baseline で `tools/doc-id` を配った iosci リポジトリで実際に 22 件のリンク切れが起き、
`verify` も pre-commit もすべて通っていた。

この傘では、原因となっている3つの穴（`assign` の書き換えすぎ・`spec` ディレクトリの
除外しすぎ・`verify` の見落とし）を、孫3本に分けて塞ぐ。

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。既に削除済みで参照
> できない前提で書く）を material として司令官が起草したものである。** ブリーフに書かれて
> いた問題意識・決定事項・実測値・制約・叩き台は、**すべて本計画書へ転記済み**であり、
> 以降はこの計画書が正典である。ブリーフの記述のうち司令官が実コードで裏取りして
> 訂正したもの（穴3の中身）は「背景3」に明記した。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `doc-id-link-integrity-01-assign-self-ref` | `assign` が採番するファイル自身の中の他文書へのプレースホルダ参照を書き換えないようにする | ⬜ 待機中 |
| 2 | `doc-id-link-integrity-02-docs-spec-scan` | `docs/` 配下の `spec` `test` `tests` ディレクトリを参照更新・検証の対象から外さないようにする | ⬜ 待機中 |
| 3 | `doc-id-link-integrity-03-verify-path` | `verify` が Markdown インラインリンク以外の書き方のパスも実在確認するようにする | ⬜ 待機中 |

順番に1本ずつ進める（1 → 2 → 3）。1 と 2 は論理的には独立だが、2 と 3 はどちらも
`scanner.rb` を触るため並行させると競合する。3 は 1 の再発検知にもなるので最後に置く。

## ワークスペースラベル

- 傘: `dotfiles :: doc-idリンク整合`（既に付いている。上書きしない）
- 孫1: `dotfiles :: doc-idリンク整合 孫1 assign自己参照限定`
- 孫2: `dotfiles :: doc-idリンク整合 孫2 docs配下spec走査`
- 孫3: `dotfiles :: doc-idリンク整合 孫3 verifyパス実在`

---

## 背景1: 人間の問題意識（逐語）

相談AI（iosci リポジトリの作業セッション）が、doc-id の不具合を「dotfiles は範囲外なので
記録だけにする」と報告したときの人間の発言:

> 5: は？なんだそれは。なぜ直さない

相談AIが確認を取らずに dotfiles で修正作業を始めてしまい、中断・撤去した後の人間の発言:

> マージした。dotfiles のほうは消して。やってほしいが、傘ブランチで司令官を置くべきだ。

## 背景2: 人間が確定させた決定事項（覆さないこと）

- doc-id の不具合は直す。作業は dotfiles の傘ブランチ（`doc-id-link-integrity`）で、
  司令官の下で進める
- `master` へのマージは人間が行う（`AGENTS.md` の最重要ルール）

## 背景3: 既存の穴（再現済み・原因特定済み）

発生状況: iosci リポジトリ（repo-baseline テンプレートで `tools/doc-id` を配布済み）で、
`docs/` 配下に未採番の文書を十数本作り、互いに Markdown リンクで参照した状態で1本ずつ
`doc-id assign` したところ、リンク切れが 22 件発生した。`doc-id verify` と pre-commit は
すべて通っていた。

司令官が 2026-09-20 に、この傘ブランチの `tools/doc-id` を一時ディレクトリの合成
リポジトリへコピーして再現を取った（再現手順は「背景4」）。

### 穴1: 採番するファイル自身の中にある、他の未採番文書へのリンクまで書き換える

- `tools/doc-id/lib/doc_id/tool.rb` の `rename_with_content_replacement` が
  `content.gsub(/#{Regexp.escape old_doc_id}(?!-[\da-z])/, doc_id)` で、採番するファイルの
  中にある `DOC-DOCID_PLACEHOLDER` を**すべて**置換している
- iosci での例: `店舗情報.md` を採番すると、その中の「未確定事項」文書へのリンク（まだ
  プレースホルダのまま）が、店舗情報の新しい DOC-ID に化けて存在しないファイルを指す:

  ```text
  採番前: [未確定事項](../tracking/DOC-DOCID_PLACEHOLDER_未確定事項.md)
  採番後: [未確定事項](../tracking/DOC-2609200234-i_未確定事項.md)   ← 店舗情報の ID。実在しない
  ```

- **期待**: 自己参照（`<旧ID>_<自分の説明的ファイル名>`、`.md` 付き・無しの両方）だけを
  置換し、他文書へのプレースホルダ参照は残す。残した参照は、その文書を採番したときに
  `replace_all_doc_id_refs` が更新する
- 司令官の再現で確認済み。**化け方は1種類ではない**: 「説明的ファイル名を伴わない裸の
  `DOC-DOCID_PLACEHOLDER`」（例: 「採番前は `DOC-DOCID_PLACEHOLDER` のまま」のような地の文、
  `DOC-DOCID_PLACEHOLDER_<説明的ファイル名>.md` のような命名規則の説明）も、採番する
  ファイル自身の中にあれば今は書き換わる。これも自己参照ではないので残すのが正しい
  （このリポジトリの `docs/README.md` やテンプレートの `docs/README.md.jinja` には
  実際にこの種の記述がある）
- 既存テスト `test_placeholder_file_renamed_and_content_replaced` は、ファイル自身の
  自己参照（`DOC-DOCID_PLACEHOLDER_計画`。`.md` 無し）が置換されることを確かめている。
  これは修正後も満たし続けなければならない

### 穴2: パスのどこかに `spec` ディレクトリがあると、参照更新・検証の対象から外れる

- `tools/doc-id/lib/doc_id/tool.rb` の `EXCLUDED_DIR_NAMES = %w[test tests spec]` を、
  `scanner.rb` の `excluded_path?` がパスの**全セグメント**に適用している。テストコード
  （テストフィクスチャに意図的な壊れ参照が含まれうる）を除外するつもりが、iosci の
  仕様書ディレクトリ `docs/spec/` にも効いた
- 結果: `docs/spec/` 内の文書にある参照が、`assign` の参照更新（`replace_all_doc_id_refs`）
  から漏れた（同じ文書で2回再現）。`verify`（`find_broken_refs`）の検査からも漏れる
- 司令官の再現で、`docs/spec/` 内の文書のリンクが `assign` 後もプレースホルダのまま
  残ること、`docs/spec/` 内に実在しないパスへのリンクを置いても `verify` が 0 を返す
  ことを確認済み
- 既存テスト `test_does_not_update_references_inside_excluded_test_directory`
  （リポジトリ直下の `test/` は参照更新しない）と
  `test_verify_still_detects_broken_refs_when_repo_root_contains_excluded_segment`
  （リポジトリ自体が `test` を含むパスに置かれていても誤爆しない）は、修正後も
  満たし続けなければならない

### 穴3: `verify` が、Markdown インラインリンク以外の書き方のパスを実在確認しない

**ブリーフの記述（「`verify` が DOC-ID の存在しか見ず、リンク先のパスの実在を見ない」）は
コードと一部食い違っていたため、司令官が実コードと再現で訂正した。**

- `scanner.rb` の `check_md_links` は、**Markdown のインラインリンク
  `[text](path)` についてはパスの実在を既に確認している**（`File.exist?`。既存テスト
  `test_detects_broken_markdown_link_paths` もある）。司令官の再現でも、穴1で化けた
  インラインリンクは `verify` が正しく検出した
- 見落とすのは次の書き方である（いずれも司令官の再現で `verify` が 0 を返した）:
  1. **インラインコード・地の文に書いたパス**（例: `` `docs/tracking/DOC-<ID>_未確定事項.md` ``）。
     `check_bare_refs` が DOC-ID 部分（`DOC-<ID>`）しか見ず、その ID のファイルが何か1つ
     実在すれば通す。穴1で「ID は実在するがファイル名が違う」参照ができると素通りする
  2. **参照スタイルのリンク定義**（`[label]: ../tracking/DOC-<ID>_未確定事項.md`）。
     `check_md_links` の正規表現はインラインリンクしか拾わず、残りは 1 と同じ扱いになる
  3. **`docs/spec/` 等、穴2で除外されたディレクトリの中の参照**（穴2の修正で解消する）
- **iosci の 22 件が上のどの書き方だったかは未確認である**（iosci のリポジトリはこの
  マシンに無く、司令官は現物を見られない）。「インラインリンクで書いていたのに
  `verify` が通った」のなら別の原因がありうるが、手元のコードと再現ではその経路を
  見つけられなかった。孫3は上の 1・2 を塞ぐ。インラインリンクなのに見逃す経路を
  孫3の実装中に見つけたら、それも同じ孫で塞いでよい

## 背景4: 実測値

- 2026-09-20、iosci の `docs/` 配下で発生。リンク切れ 22 件（穴1による）、参照更新漏れ
  2 回（穴2による。いずれも次の同じ文書）:

  ```text
  docs/spec/DOC-2609200234-g_技術方針.md
  ```

- 2026-09-20 時点で `tools/doc-id/` と `templates/repo-baseline/template/tools/doc-id/` は
  `diff -r` で完全一致（pre-commit の `doc-id-template-sync` フックが一致を検査している）
- 司令官の再現手順（2026-09-20。この傘ブランチの `tools/doc-id` を一時ディレクトリへ
  コピーし `git init` した合成リポジトリで実施）:

  ```text
  docs/design/DOC-DOCID_PLACEHOLDER_店舗情報.md   → 未確定事項へインラインリンク
  docs/tracking/DOC-DOCID_PLACEHOLDER_未確定事項.md → 店舗情報へインラインリンク
  docs/spec/DOC-DOCID_PLACEHOLDER_技術方針.md      → 店舗情報へインラインリンク
  git add + commit → doc-id assign docs/design/DOC-DOCID_PLACEHOLDER_店舗情報.md

  結果:
    店舗情報.md 内のリンク   → ../tracking/DOC-2609200523_未確定事項.md（穴1。実在しない）
    未確定事項.md 内のリンク → 正しく更新された
    技術方針.md 内のリンク   → プレースホルダのまま（穴2）
    verify                   → 穴1のインラインリンクは検出した（rc=1）

  続けて店舗情報.md に次を書いて verify:
    `docs/tracking/DOC-2609200523_未確定事項.md`（インラインコード）
    docs/tracking/DOC-2609200523_未確定事項.md（地の文）
    [未確定事項][u] + [u]: ../tracking/DOC-2609200523_未確定事項.md（参照スタイル）
    技術方針.md に [x](../design/DOC-2609200523_存在しない.md)
  → verify rc=0（すべて見逃し）
  ```

## 設計（司令官が確定。孫はこれに従う）

### 設計1: 孫1 — `assign` の自己参照限定

- 採番するファイル自身の内容の置換を、`replace_all_doc_id_refs` と**同じ規則**
  （`<旧ID>_<説明的ファイル名>` の `.md` 付きと `.md` 無しの2形だけを置換）に揃える。
  置換規則を2か所に別々に書かず、共通化できるなら共通化する
- 採番するファイル自身を `replace_all_doc_id_refs` の走査が改めて拾うかどうか（改名前の
  パスは `Errno::ENOENT` で飛ばされている）は実装で確かめ、二重置換や取りこぼしが
  起きないようにする

### 設計2: 孫2 — 除外ディレクトリの適用範囲

- **`docs/` 配下のパスには `EXCLUDED_DIR_NAMES` を適用しない。** `docs/` は文書置き場で
  あり、そこに `spec` `test` `tests` という名前のディレクトリがあっても、それは仕様書や
  テスト計画の文書であってテストコードではない
- `docs/` の外（リポジトリ直下の `test/` `spec/`、`tools/doc-id/test/` など）は従来どおり
  除外する。**RSpec の `spec/` 等、`docs/` の外にあるテストコードを誤って検査対象に
  しないこと**（人間からの制約）
- 判定は `excluded_path?`（`@repo_root` からの相対パスのセグメント単位）の中で行い、
  参照更新（`replace_all_doc_id_refs`）と検証（`find_broken_refs`）の両方が同じ判定を
  通るようにする。`EXCLUDED_DIR_NAMES` のコメントと `find_broken_refs` 内のコメントも
  実態に合わせて直す

### 設計3: 孫3 — `verify` のパス実在確認の拡張

- **`.md` で終わる `DOC-<ID>_<説明的ファイル名>.md` 形のトークン**が、インラインリンク
  以外（インラインコード・地の文・参照スタイルのリンク定義）に現れたら、その
  **ファイル名（basename）が `docs/` 配下のどこかに実在するか**を確認する。書かれた
  パスの解決（相対か、リポジトリルート起点か）は書き方によって揺れるため、basename の
  実在で判定する。ID だけ一致してファイル名が違うものを検出するのが目的
- **参照スタイルのリンク定義**（行頭の `[label]: path`）は、インラインリンクと同じく
  参照元ファイルからの相対パスとして解決して実在確認してよい。basename 判定で済ませても
  よい。どちらにするかは孫3が決め、PR 説明に理由を書く
- `.md` で終わらない DOC-ID の言及（`DOC-<ID>` 単体、`DOC-<ID>_計画` のような拡張子無し）は
  従来どおり ID の実在だけを見る。日本語の地の文では説明的ファイル名の終わりを機械的に
  切り出せず、誤検知を出すため
- インラインリンクの既存の検査（`check_md_links`）と二重報告しないこと（既存テスト
  `test_does_not_double_report_broken_markdown_link_with_filename_suffix` がある）
- コードフェンスの中は従来どおり検査しない（既存の `each_outside_fence`）
- **このリポジトリ自身の既存文書で新しい検査が引っかかるもの**が出たら、本物のリンク
  切れなら同じ PR で直す。誤検知なら検査側の設計を見直す。どちらか判断できなければ
  抑制せず人間に報告する（`verify` の除外設定を足して黙らせない）

### 3本共通

- `tools/doc-id/` を直し、**同じ変更を `templates/repo-baseline/template/tools/doc-id/` へ
  そのまま複製する**（テストファイルも含む。`diff -r` で完全一致を保つ。pre-commit の
  `doc-id-template-sync` フックが検査する）
- 各不具合に regression test を追加する（`tools/doc-id/test/doc_id_test.rb`。テンプレート
  側は複製なので同じファイル）

## 決定的な制約（AGENTS.md 由来。孫は全部守ること）

- **`master` を書き換える操作（マージ・push・force push）は人間だけが行う。**
  孫 → 傘のマージは、レビューで承認済みの PR に限り AI が行ってよい
- `git pull` は使わない。`git reset --hard` / `git clean` / lease なしの force push は
  人間の承認が要る
- deploy スクリプト（`deploy-all.sh` / `uninstall.sh` / `*/deploy.sh`）を実オペレーションで
  実行しない（この傘は deploy 系を触らない想定）
- linter の抑制ディレクティブ・除外設定の追加・閾値緩和を AI の判断で行わない。
  指摘は原則リファクタで対応する
- 新規ファイルの追加時・大幅変更時点で、対象ファイル単位の lint
  （`pre-commit run --files <path>`）を実行する
- `tools/doc-id/` と `templates/repo-baseline/template/tools/doc-id/` の一致を保つ
- `docs/` の文書に地の文で言及するときは DOC-ID を明示する

## スコープ外（孫が勝手に入れないこと）

- iosci など、repo-baseline を配布済みのリポジトリの `tools/doc-id` への反映（各リポジトリ
  側で別途行う。copier update が使えないため手動）
- 傘のスキル（`umbrella-handoff` / `umbrella-orchestrator`）の変更
- `doc-id` の新しいサブコマンドやオプションの追加（例: 壊れたリンクを自動修復する機能）

## 必須の検証ステップ（AGENTS.md「コミット前の必須ステップ」より。省略しない）

```bash
ruby tools/doc-id/test/doc_id_test.rb
ruby templates/repo-baseline/template/tools/doc-id/test/doc_id_test.rb
./tools/doc-id/doc-id check
./tools/doc-id/doc-id verify
pre-commit run --all-files
tests/template_smoke.sh
```

- `tests/template_smoke.sh` は、`templates/repo-baseline/` 配下の**どのファイルを変更した
  場合も**実行が要る（`AGENTS.md`「コミット前の必須ステップ」）。この傘の孫は3本とも
  テンプレート側の複製を変えるので、3本とも実行する
- `tests/deploy_smoke.sh` は deploy 関連のシェルスクリプトを変えたときに要る。この傘では
  触らない想定なので不要（触った場合は実行する）
- `bin/` 配下は触らない想定なので `python3 -m unittest discover -s bin/tests -v` は不要

## テスト方針（AGENTS.md「テスト方針」に従う）

- 3つの穴はどれも**実際に起きたバグ**なので、それぞれを再現する regression test を必ず
  追加する
- テストは `tools/doc-id/test/doc_id_test.rb` の既存のクラス（`DocIdVerifyTest`・
  `DocIdAssignTest` 相当。実ファイルで確認すること）と既存ヘルパー（一時ディレクトリ +
  `git init` + `git add`）の書き方に合わせる
- 受け入れ条件と test example は1対1対応でなくてよい。1つの scenario で複数の条件を
  検証してよい。既存テストが同じ regression を検出できるなら新規に足さない

---

## 孫1用プロンプト:

````markdown
# 傘ブランチ: doc-id-link-integrity
# 孫ブランチ: doc-id-link-integrity-01-assign-self-ref
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/doc-id-link-integrity/docs/planning/DOC-2609200524_doc-id-link-integrity_計画.md`

**まず計画書の「背景1〜4」「設計」「決定的な制約」「スコープ外」「必須の検証ステップ」
「テスト方針」を全部読むこと。** 以下はその上での作業指示である。

## 実装開始前の必須手順

作業ブランチは**必ず `doc-id-link-integrity`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout doc-id-link-integrity
git fetch origin
git merge --ff-only origin/doc-id-link-integrity
git checkout -b doc-id-link-integrity-01-assign-self-ref
```

（`ocw` がこのブランチ名のワークツリーを作成済みで、既にこのブランチにいる場合は、
`git fetch origin` と `git merge --ff-only origin/doc-id-link-integrity` だけを行う）

## やること

計画書「背景3 穴1」と「設計1」の修正を行う。

1. `tools/doc-id/lib/doc_id/tool.rb` の `rename_with_content_replacement` を、採番する
   ファイル自身の中の**自己参照だけ**（`<旧ID>_<説明的ファイル名>` の `.md` 付き・無し）を
   置換するように直す。他文書へのプレースホルダ参照と、説明的ファイル名を伴わない裸の
   `DOC-DOCID_PLACEHOLDER` は残す。置換規則は `replace_all_doc_id_refs` と揃え、
   共通化できるなら共通化する
2. regression test を `tools/doc-id/test/doc_id_test.rb` に追加する
3. 同じ変更を `templates/repo-baseline/template/tools/doc-id/` へそのまま複製する
   （`diff -r tools/doc-id templates/repo-baseline/template/tools/doc-id` が空になること）

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 未採番の文書 A・B が互いにリンクしている状態で A を採番しても、A の中の B への
  プレースホルダリンクは書き換わらず、その後 B を採番すると A・B 双方のリンクが
  正しい新ファイル名を指す（**iosci で 22 件のリンク切れを出した実バグ。この regression は
  必ず自動テストで固定する**）
- 採番するファイル自身の中の自己参照（`.md` 付き・無し）は従来どおり新 ID に置換される
- 採番するファイル自身の中の、説明的ファイル名を伴わない裸の `DOC-DOCID_PLACEHOLDER` は
  書き換わらない

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files tools/doc-id/lib/doc_id/tool.rb tools/doc-id/test/doc_id_test.rb
ruby tools/doc-id/test/doc_id_test.rb
ruby templates/repo-baseline/template/tools/doc-id/test/doc_id_test.rb
./tools/doc-id/doc-id check
./tools/doc-id/doc-id verify
pre-commit run --all-files
tests/template_smoke.sh
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `doc-id-link-integrity` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewer は done 状態で完了し完了通知は来ないので、待機して停止せず `gh pr view` を
ポーリングしてレビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

## 孫2用プロンプト:

````markdown
# 傘ブランチ: doc-id-link-integrity
# 孫ブランチ: doc-id-link-integrity-02-docs-spec-scan
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/doc-id-link-integrity/docs/planning/DOC-2609200524_doc-id-link-integrity_計画.md`

**まず計画書の「背景1〜4」「設計」「決定的な制約」「スコープ外」「必須の検証ステップ」
「テスト方針」を全部読むこと。** 以下はその上での作業指示である。孫1（`assign` の
自己参照限定）は傘へマージ済みの前提で、その上に積む。

## 実装開始前の必須手順

作業ブランチは**必ず `doc-id-link-integrity`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout doc-id-link-integrity
git fetch origin
git merge --ff-only origin/doc-id-link-integrity
git checkout -b doc-id-link-integrity-02-docs-spec-scan
```

（`ocw` がこのブランチ名のワークツリーを作成済みで、既にこのブランチにいる場合は、
`git fetch origin` と `git merge --ff-only origin/doc-id-link-integrity` だけを行う）

## やること

計画書「背景3 穴2」と「設計2」の修正を行う。

1. `scanner.rb` の `excluded_path?` を、`docs/` 配下のパスには `EXCLUDED_DIR_NAMES` を
   適用しないように直す。`docs/` の外（リポジトリ直下の `test/` `spec/` 等）は従来どおり
   除外する。参照更新（`replace_all_doc_id_refs`）と検証（`find_broken_refs`）の両方が
   この判定を通ることを確かめる
2. `tool.rb` の `EXCLUDED_DIR_NAMES` のコメントと、`find_broken_refs` 内のコメントを実態に
   合わせて直す
3. regression test を `tools/doc-id/test/doc_id_test.rb` に追加する
4. 同じ変更を `templates/repo-baseline/template/tools/doc-id/` へそのまま複製する

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- `docs/spec/` 配下の文書にある参照が、`assign` の参照更新の対象になり、`verify` の
  検査対象にもなる（**iosci で参照更新漏れを2回出した実バグ。この regression は必ず
  自動テストで固定する**）
- `docs/` の外にある `test/` `tests/` `spec/`（テストコード・フィクスチャ）は、従来どおり
  参照更新からも検証からも除外される（既存テスト
  `test_does_not_update_references_inside_excluded_test_directory` が守っているなら
  それでよい。検証側も既存テストで守られているか確認し、無ければ足す）
- リポジトリ自体が `test` 等を含むパスに置かれていても誤爆しない（既存テスト
  `test_verify_still_detects_broken_refs_when_repo_root_contains_excluded_segment`）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files tools/doc-id/lib/doc_id/scanner.rb tools/doc-id/lib/doc_id/tool.rb tools/doc-id/test/doc_id_test.rb
ruby tools/doc-id/test/doc_id_test.rb
ruby templates/repo-baseline/template/tools/doc-id/test/doc_id_test.rb
./tools/doc-id/doc-id check
./tools/doc-id/doc-id verify
pre-commit run --all-files
tests/template_smoke.sh
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `doc-id-link-integrity` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewer は done 状態で完了し完了通知は来ないので、待機して停止せず `gh pr view` を
ポーリングしてレビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

## 孫3用プロンプト:

````markdown
# 傘ブランチ: doc-id-link-integrity
# 孫ブランチ: doc-id-link-integrity-03-verify-path
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/doc-id-link-integrity/docs/planning/DOC-2609200524_doc-id-link-integrity_計画.md`

**まず計画書の「背景1〜4」「設計」「決定的な制約」「スコープ外」「必須の検証ステップ」
「テスト方針」を全部読むこと。** 特に「背景3 穴3」は、引き継ぎブリーフの記述を司令官が
訂正した箇所なので注意して読むこと。孫1・孫2は傘へマージ済みの前提で、その上に積む。

## 実装開始前の必須手順

作業ブランチは**必ず `doc-id-link-integrity`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout doc-id-link-integrity
git fetch origin
git merge --ff-only origin/doc-id-link-integrity
git checkout -b doc-id-link-integrity-03-verify-path
```

（`ocw` がこのブランチ名のワークツリーを作成済みで、既にこのブランチにいる場合は、
`git fetch origin` と `git merge --ff-only origin/doc-id-link-integrity` だけを行う）

## やること

計画書「背景3 穴3」と「設計3」の修正を行う。

1. `scanner.rb` の `verify` 系（`check_md_links` / `check_bare_refs`）を拡張し、
   インラインリンク以外に現れる `.md` で終わる `DOC-<ID>_<説明的ファイル名>.md` 形の
   トークン（インラインコード・地の文・参照スタイルのリンク定義）について、その
   basename が `docs/` 配下に実在するかを確認する。参照スタイルのリンク定義を相対パス
   解決にするか basename 判定にするかは自分で決め、PR 説明に理由を書く
2. `.md` で終わらない DOC-ID の言及は従来どおり ID の実在だけを見る。インラインリンクの
   既存の検査と二重報告しない。コードフェンスの中は検査しない
3. regression test を `tools/doc-id/test/doc_id_test.rb` に追加する
4. このリポジトリで `./tools/doc-id/doc-id verify` を実行し、新しい検査で引っかかる既存
   文書があれば、本物のリンク切れは同じ PR で直す。誤検知なら検査側の設計を見直す。
   判断できなければ抑制せず PR 説明に書いて人間の判断を仰ぐ（除外設定を足して黙らせない）
5. 同じ変更を `templates/repo-baseline/template/tools/doc-id/` へそのまま複製する

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- ID は実在するが説明的ファイル名が違う `DOC-<ID>_<名前>.md` を、インラインコードや
  地の文に書くと `verify` が検出する（**iosci で `verify` が 22 件のリンク切れを見逃した
  実バグ。この regression は必ず自動テストで固定する**）
- 参照スタイルのリンク定義の壊れたパスを `verify` が検出する
- 正しい参照（インラインコード・地の文・参照スタイル・インラインリンク）は検出しない
- インラインリンクの壊れたパスを二重報告しない（既存テストで守られているならそれでよい）
- `.md` で終わらない ID だけの言及は、ID が実在すれば通る（既存の挙動）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files tools/doc-id/lib/doc_id/scanner.rb tools/doc-id/test/doc_id_test.rb
ruby tools/doc-id/test/doc_id_test.rb
ruby templates/repo-baseline/template/tools/doc-id/test/doc_id_test.rb
./tools/doc-id/doc-id check
./tools/doc-id/doc-id verify
pre-commit run --all-files
tests/template_smoke.sh
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `doc-id-link-integrity` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewer は done 状態で完了し完了通知は来ないので、待機して停止せず `gh pr view` を
ポーリングしてレビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````
