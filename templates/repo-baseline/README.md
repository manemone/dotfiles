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
このディレクトリを別リポジトリへそのまま移動するだけで copier テンプレートとして成立します。

## 前提

- 展開先が git リポジトリであること（DOC-ID の採番が `git log` に依存し、pre-commit が git フックを使うため）
- [uv](https://docs.astral.sh/uv/) がインストールされていること
- 初回セットアップ時のみネットワーク（`copier copy` と `pre-commit install-hooks`）

**要求しないもの**: Ruby 等の特定の言語ランタイム（pre-commit の隔離環境が用意する）、
mise/rbenv 等のバージョンマネージャ、Docker、Claude Code であること、GitHub であること
（CI は `use_ci` で無効化できる）。

## 使い方: 新規展開

```bash
cd <展開先リポジトリのルート>
uv tool run copier copy <このリポジトリへのパスまたはURL>/templates/repo-baseline .
```

質問に答えると、選んだ内容に応じて以下が生成されます。

| 質問 | 型 | 既定値 | 効果 |
|---|---|---|---|
| `default_branch` | 文字列 | `master` | プルリクエストの作法のブランチ構成節に埋め込む |
| `lint_cmd` | 文字列 | `""` | pre-commit の local フックと AGENTS.md に埋め込む lint コマンド。空欄なら生成しない |
| `test_cmd` | 文字列 | `""` | 同上（test コマンド） |
| `use_doc_id` | bool | `true` | DOC-ID 運用一式（`docs/`・`tools/doc-id/`・関連 pre-commit フック）を生成するか |
| `use_ci` | bool | `true` | `.github/workflows/ci.yml` を生成するか |
| `has_long_running_commands` | bool | `false` | AGENTS.md にバックグラウンド実行 + ポーリングの規約節を追加するか |
| `use_adr` | bool | `false` | `docs/README.md` に adr/ フォルダの説明を含めるか（`use_doc_id` が true の場合のみ質問） |
| `use_reference` | bool | `false` | `docs/README.md` に reference/ フォルダの説明を含めるか（同上） |

生成直後、まだ手を付けていない状態でやること:

```bash
# DOC-ID の採番（プレースホルダのままのファイルがある場合）
./tools/doc-id/doc-id assign docs/design/DOC-DOCID_PLACEHOLDER_プルリクエストの作法.md
./tools/doc-id/doc-id assign docs/design/DOC-DOCID_PLACEHOLDER_コーディング方針.md

# pre-commit の有効化
uv tool install pre-commit
pre-commit install
pre-commit run --all-files
```

`doc-id assign` はファイル名とファイル内・他ファイルからの参照は自動更新しますが、
`docs/README.md`（および `use_doc_id` 選択時に生成される `docs/design/README.md`）の
索引表にある **DOC-ID 列の値は更新しません**（`doc-id check` / `doc-id verify` もこの列までは
検証しないため、放置しても気づけません）。assign 実行後は、採番された実際の DOC-ID を
この2つの索引表に手で反映してください。

**ここで終わりではありません。** `AGENTS.md` の「概要」「ディレクトリ構成」など、このリポジトリ固有の
判断が要る部分は空欄・TODO のままです。埋め方の判断ガイドは
`claude/skills/repo-baseline/SKILL.md`（dotfiles から配布され `~/.claude/skills/` に置かれるスキル）
に従ってください。

## 使い方: 更新

```bash
uv tool run copier update
```

`copier copy` 実行時に生成される `.copier-answers.yml` を元に、テンプレート側の更新を
3-way マージで取り込みます。展開先で加えたカスタマイズ（AGENTS.md の記入内容等）は保たれます。

## 分業の原則

- **決定論的に配れるもの**（規約文書の骨組み・pre-commit 設定・doc-id ツール・CI）は
  この copier テンプレートが撒きます
- **判断が要るもの**（このリポジトリ固有のルール、コーディング方針の中身、AGENTS.md の
  「概要」等）は、撒いた後に `claude/skills/repo-baseline/SKILL.md` を読んだ AI が埋めます

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

以下を実施し、確認しました（実施日: 2026-08-02）。

- 空の git リポジトリに `uv tool run copier copy templates/repo-baseline <展開先>` で展開できること
- 展開直後に `./tools/doc-id/doc-id assign` を実行すると、プレースホルダが実際のタイムスタンプへ
  採番され、`AGENTS.md` / `docs/README.md` / `docs/design/README.md` / `opencode.json` 内の
  参照が自動更新されること
- 展開先で `ruby tools/doc-id/test/doc_id_test.rb` が全緑（24 runs / 0 failures）
- 展開先で `git init` 後、`pre-commit install && pre-commit run --all-files` が全緑
- `use_doc_id=false` / `use_ci=false` の組み合わせで `docs/` `tools/` `.github/` が
  生成されないこと（`_exclude` による制御）
- `use_doc_id=false` かつ `lint_cmd` / `test_cmd` が空欄の場合、`.pre-commit-config.yaml` には
  `pre-commit-hooks` 由来の基本フックのみが残り、有効な YAML であること
