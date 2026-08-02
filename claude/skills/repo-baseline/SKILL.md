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
uv tool run copier copy <dotfilesへのパスまたはURL>/templates/repo-baseline .
```

copier が対話式に質問してくる。答え方の判断は「4. 質問への答え方」を参照。
`--defaults` を付けると全質問が既定値になるが、**AI が代わりに答える場合も既定値に
流されず、対象リポジトリの実態を見て個別に判断すること。**

### 既存導入の更新

```bash
uv tool run copier update
```

`.copier-answers.yml`（新規導入時に自動生成される）を元に3-wayマージで更新を取り込む。
対象リポジトリ側の編集（AGENTS.md の記入内容等）は保たれる。

## 3. 既存ファイルとの衝突

`copier copy` は、生成先に同名ファイルが既にある場合、上書きするかどうかを1ファイルずつ聞いてくる。

- 既に `AGENTS.md` がある場合: 中身を比較し、テンプレートが生成する骨組みとの差分が
  大きいなら上書きせず、テンプレート側の節構成（最重要ルール・ディレクトリ構成・
  AI 支援ツールの設定・コミット前の必須ステップ 等）を参考に既存ファイルへ手動で
  節を足す方が安全。丸ごと上書きして既存のルールを失わないこと
- `.pre-commit-config.yaml` が既にある場合: 既存のフックを消さず、DOC-ID 関連フック
  （`use_doc_id` を選んだ場合）を追記する形にする
- 判断に迷う場合は上書きせず、人間に差分を提示して判断を仰ぐ

## 4. 質問への答え方

`templates/repo-baseline/README.md` に質問の一覧と既定値がある。対象リポジトリを見て答える。

- `default_branch`: `git symbolic-ref refs/remotes/origin/HEAD` や `git branch` で確認する
- `lint_cmd` / `test_cmd`: 既存の `package.json` / `Rakefile` / `Makefile` / CI 設定等から
  実際に使われているコマンドを探して答える。無ければ空欄のままでよい（後で追加できる）
- `use_doc_id`: 迷ったら true。複数人・複数 AI が並行して `docs/` に文書を書く前提があるなら
  特に有効
- `use_ci`: GitHub を使っていなければ false
- `has_long_running_commands`: 学習・大量データ処理・長時間バッチ等を扱うリポジトリなら true
- `use_adr` / `use_reference`: そのリポジトリで「一度確定した技術決定を記録する」文化や
  「運用中に繰り返し引くリファレンス文書」の需要があるかで判断する。無ければ false のままで良い
  （後から `docs/README.md` を手で拡張することもできる）

## 5. 撒いた後に埋めるべきもの（チェックリスト）

生成直後の状態は骨組みに過ぎない。以下を対象リポジトリの実態を調べたうえで埋める。

- [ ] `AGENTS.md` の「概要」: このリポジトリが何をするものかを1〜3文で
- [ ] `AGENTS.md` の「ディレクトリ構成」: 主要ディレクトリの役割を表にする
- [ ] `AGENTS.md` の「最重要ルール」: このリポジトリ固有の破壊的操作があれば追記
      （本番環境への反映、課金の発生する外部 API 呼び出し 等）
- [ ] `AGENTS.md` の「コミット前の必須ステップ」: `lint_cmd` / `test_cmd` を空欄のまま
      進めた場合、実際のコマンドが定まった時点で埋める
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
`./tools/doc-id/doc-id assign <file>` で採番してから中身を埋めること。

## 6. 傘ブランチ運用について

このスキルは傘ブランチの spawn・マージ検出・進捗管理を扱わない。それらは
**umbrella-orchestrator スキル**の領分であり、再実装しない。導入作業自体を
傘ブランチで進める場合は umbrella-orchestrator スキルに従うこと。

PR を作成しレビューを回す場合は **pr-review-loop スキル**に従うこと（Herdr 環境が前提）。
