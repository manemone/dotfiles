# docs/ — 文書索引

`docs/` 配下の全設計文書・計画書のナビゲーションと索引です。

## クイックナビゲーション

目的別に、最初に読むべきファイルを案内します。

| 目的 | 最初に読むべきファイル | 備考 |
|---|---|---|
| このリポジトリのルールを知る | [../AGENTS.md](../AGENTS.md) | 最重要ルール・ディレクトリ構成・デプロイの仕組みなど |
| PR を出す前に読む | [design/README.md](design/README.md) の「プルリクエストの作法」 | 説明文の構成・コメントのプレフィクス・ブランチ構成 |
| シェルを書く前に読む | [design/README.md](design/README.md) の「シェルスクリプトコーディング方針」 | POSIX sh / bash の使い分け、bashism の回避 |
| デプロイを検証する | [design/README.md](design/README.md) の「テスト方針」 | 実 HOME を汚さずに検証する4層の方法 |
| 傘ブランチの計画を確認する | [planning/](planning/) 配下の各計画書 | 進行中・完了した傘ブランチの計画書 |

## フォルダ構成

| フォルダ | 役割 |
|---|---|
| `design/` | 設計書・仕様・規約。実装の指針となる現役の文書 |
| `planning/` | ロードマップ・傘ブランチ計画書 |
| `archive/` | 過去の経緯・履歴。現在の開発判断には使わない |

> **注**: `docs/` 直下には索引（本ファイル）のみを置き、それ以外の文書は `design/` `planning/` `archive/`
> のいずれかに配置します。`archive/` は現時点で対象文書が無く空のため、ディレクトリ自体は作っていません
> （git は空ディレクトリを追跡できません）。アーカイブすべき文書ができた時点で作成してください。

## 全 DOC-ID 索引

### design/ — 設計書・仕様・規約

| DOC-ID | ファイル | 概要 |
|---|---|---|
| DOC-DOCID_PLACEHOLDER | [プルリクエストの作法.md](design/DOC-DOCID_PLACEHOLDER_プルリクエストの作法.md) | PR説明文の構成・コメントのプレフィクス・ブランチ構成の規約 |
| DOC-DOCID_PLACEHOLDER | [シェルスクリプトコーディング方針.md](design/DOC-DOCID_PLACEHOLDER_シェルスクリプトコーディング方針.md) | POSIX sh / bash の使い分け・bashism・エラーハンドリングの規約 |
| DOC-DOCID_PLACEHOLDER | [テスト方針.md](design/DOC-DOCID_PLACEHOLDER_テスト方針.md) | 実 HOME を汚さずにデプロイを検証する方法の定義 |

### planning/ — ロードマップ・計画

| DOC-ID | ファイル | 概要 |
|---|---|---|
| DOC-001 | [ai-housekeeping_計画.md](planning/DOC-001_ai-housekeeping_計画.md) | dotfiles リニューアル計画（旧連番形式。タイムスタンプ形式への移行待ち） |
| DOC-002 | [ai-dotfiles-add-tools_計画.md](planning/DOC-002_ai-dotfiles-add-tools_計画.md) | 自作ツールの dotfiles への移行計画（旧連番形式。タイムスタンプ形式への移行待ち） |
| DOC-2608020558 | [repo-baseline_計画.md](planning/DOC-2608020558_repo-baseline_計画.md) | AI エージェント支援基盤の整備と汎用テンプレート化の傘ブランチ計画書 |

## 新規ファイル追加時のルール

`docs/` 配下に新しい `.md` ファイルを追加する際は、以下の3ステップを必ず実行してください。
いずれかを省略すると索引から漏れ、発見不能なファイルが生まれます。

1. **DOC-ID の割り当て**: `tools/doc-id assign docs/path/to/new_file.md` を実行する
2. **全 DOC-ID 索引への追記**: このファイル（`docs/README.md`）の該当フォルダの表に、
   DOC-ID・ファイル名・1行説明を追記する
3. **フォルダ README への追記**: ファイルを追加したフォルダの `README.md`（`design/README.md` など）
   の表にも同様に追記する

### DOC-ID 命名規則

```
DOC-YYMMDDHHMM_<説明的ファイル名>.md
```

- `YYMMDDHHMM` はファイルの作成日時（git 履歴から自動取得される）
- DOC-ID は **不変**。ファイルの移動・リネームがあっても変更しない
- 衝突時は `DOC-YYMMDDHHMM-a`、`DOC-YYMMDDHHMM-b` のようにサフィックスが付与される
- 採番前のファイルは `DOC-DOCID_PLACEHOLDER_<説明的ファイル名>.md` という名前で作成してよい。
  採番ツールがプレースホルダをタイムスタンプに一括置換し、リポジトリ内の参照も同時に更新する

### 検証コマンド

```bash
tools/doc-id check    # 命名規則違反を検出
tools/doc-id verify   # 全 DOC-ID 参照先の実在確認
```

> **注意**: `README.md` は `doc-id check` の対象外です。DOC-ID の割り当ては不要です。
