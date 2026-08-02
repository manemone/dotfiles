# docs/ — dotfiles 文書索引

`docs/`配下の全設計文書・計画・ADR・運用リファレンスのナビゲーションと索引。

## クイックナビ

| 目的 | 最初に読むべきファイル | 備考 |
|---|---|---|
| `ocw-meter`のイベントスキーマを調べる | [reference/DOC-005_ocw-meterイベントスキーマ.md](reference/DOC-005_ocw-meterイベントスキーマ.md) | 全event_type・全フィールド・費用計算式の一次情報源 |
| LLM費用のベースラインを測る手順を知る | [reference/DOC-004_LLM費用観測ベースライン計測手順.md](reference/DOC-004_LLM費用観測ベースライン計測手順.md) | 実PR 5〜10本での計測手順 |
| なぜ`ocw-meter`をこの設計にしたかを知る | [planning/DOC-003_ai-llm-cost-observability_計画.md](planning/DOC-003_ai-llm-cost-observability_計画.md) | 傘ブランチ計画書。完了後は歴史的記録 |
| feasibility probeの実測結果を見る | [adr/ADR-001_llm-cost-observability-collection-method.md](adr/ADR-001_llm-cost-observability-collection-method.md) | 収集方式決定の根拠データ |
| 自作ツール（ocw/claude-ds/skills）の統合経緯を知る | [planning/DOC-002_ai-dotfiles-add-tools_計画.md](planning/DOC-002_ai-dotfiles-add-tools_計画.md) | bin/・claude/ディレクトリ新設の計画書 |
| dotfiles全体のリニューアル経緯を知る | [planning/DOC-001_ai-housekeeping_計画.md](planning/DOC-001_ai-housekeeping_計画.md) | リポジトリ構造整理・deploy統一化の計画書 |

## フォルダ構成

| フォルダ | 役割 |
|---|---|
| `adr/` | **Architecture Decision Record** — 実測・調査結果に基づいて確定した技術的決定の記録。一度確定した決定の経緯を後から追うための文書。原則変更しない（新しい決定は新しいADRを追加する） |
| `planning/` | **傘ブランチ計画書** — 傘ブランチ着手時に書く、目的・調査結果・設計・孫ブランチ分割・実装完了条件をまとめた文書。傘のマージが完了すると現役の指針ではなく歴史的記録になる（現在の実装がどうなっているかは常にコードとreference/を見る） |
| `reference/` | **運用中に繰り返し引く文書** — 一度作って終わりではなく、日々の運用・デバッグ・拡張のたびに開く文書（イベントスキーマ、計測手順等）。man page的な位置づけ |

> **注**: `docs/`直下には索引ファイル（本ファイル）のみを置き、それ以外の文書は
> `adr/`/`planning/`/`reference/`のいずれかに配置する。

### `planning/`と`reference/`の使い分け（本リポジトリ独自の判断）

`~/projects/lora-dataset-forge`の`docs/`には`design/`（実装の指針となる現役の設計文書）という
フォルダがあるが、本リポジトリには無い語彙として`reference/`を採用した:

- `planning/`（≒他リポジトリの`design/`に近いが、性質は「計画書」）は**作るとき**に読む文書
  （設計判断とその根拠。傘完了後は経緯を追うための副次的な参照になる）
- `reference/`は**運用中に繰り返し引く**文書。「`completeness: partial`とは何か」をデータを
  読むたびに引くイベントスキーマ文書や、月次のベースライン計測手順がこれにあたる。
  実装完了後も参照され続ける点で`planning/`と性質が違う

## 全DOC-ID索引

### 📐 adr/ — Architecture Decision Records

| ID | ファイル | 概要 |
|---|---|---|
| ADR-001 | [llm-cost-observability-collection-method.md](adr/ADR-001_llm-cost-observability-collection-method.md) | LLM費用・Claude利用枠の収集方式決定。孫0のfeasibility probe実測結果（transcriptのmessage.id重複問題、statusLineのrate_limits取得可否、Herdrのrole↔session紐付け等）に基づき、「事後読み取り + 軽量イベント刻み」方式を確定した |

### 🗺️ planning/ — 傘ブランチ計画書

| DOC-ID | ファイル | 概要 |
|---|---|---|
| DOC-001 | [ai-housekeeping_計画.md](planning/DOC-001_ai-housekeeping_計画.md) | dotfilesリポジトリのリニューアル計画（傘`ai/housekeeping`、孫1〜8全マージ済）。.gitignore整理・LICENSE追加・mise環境固定・zsh Antidote移行・deploy統一・tmux/nvimクロスプラットフォーム化・vim/削除・README全面書き直し |
| DOC-002 | [ai-dotfiles-add-tools_計画.md](planning/DOC-002_ai-dotfiles-add-tools_計画.md) | マシン上に散在していた自作ツール（ocw、claude-ds、pr-review-loop/umbrella-orchestratorスキル）をdotfilesリポジトリへ統合する計画（傘`ai/dotfiles-add-tools`、孫0〜4全マージ済）。`bin/`・`claude/`ディレクトリを新設 |
| DOC-003 | [ai-llm-cost-observability_計画.md](planning/DOC-003_ai-llm-cost-observability_計画.md) | LLM費用・Claude利用枠の観測基盤（`ocw-meter`）構築計画（傘`ai/llm-cost-observability`、孫0〜5全マージ済）。既存transcript/statusLineの事後読み取りのみで、本番フローに一切割り込まずPR別・工程別・role別の費用とClaude利用枠を観測する設計 |

### 📖 reference/ — 運用リファレンス

| DOC-ID | ファイル | 概要 |
|---|---|---|
| DOC-004 | [LLM費用観測ベースライン計測手順.md](reference/DOC-004_LLM費用観測ベースライン計測手順.md) | `ocw-meter`導入後、実PR 5〜10本でLLM費用・Claude利用枠のベースラインを計測する手順書。DeepSeek管理画面との月末突合手順、計画書§15.3の「必ず答える5つの問い」、比較実験（計画書§16）の事前合格基準を含む |
| DOC-005 | [ocw-meterイベントスキーマ.md](reference/DOC-005_ocw-meterイベントスキーマ.md) | `ocw-meter`が書く全イベント型の恒久リファレンス。共通エンベロープの全フィールド、全`event_type`とそのペイロード（未実装の型も明記）、`idempotency_key`の生成規則、費用計算式、`completeness`の判定基準、`schema_version`の変更ルールを実データで検証した上でまとめたもの |

## 新規ファイル追加時のルール

1. **DOC-IDを割り当てる**: 本リポジトリは**連番**方式（`DOC-001`, `DOC-002`, ...）を採用している。
   `find docs -name 'DOC-*' -o -name 'ADR-*'`で既存の最大番号を確認し、次の空き番号を使うこと
2. **本ファイル（`docs/README.md`）の該当フォルダの表に追記する**: DOC-ID・ファイルへのリンク・
   1行概要（**中身を読まずにタイトルだけで書かない**）
3. **配置先を`adr/`/`planning/`/`reference/`のいずれかから選ぶ**: 上の「使い分け」節を参照。
   `docs/`直下には置かない

いずれかを省略すると索引から漏れ、発見不能な文書が生まれる。

### DOC-ID採番方式についての注記（重要・暫定）

現在のDOC-IDは連番（`DOC-001`, `DOC-002`, ...）だが、**この方式は並行ブランチで採番が衝突する**
（同時に2つの傘ブランチが新規文書を追加すると、両方が同じ次番号を狙ってしまう）。
`~/projects/lora-dataset-forge`と同じ**タイムスタンプ式**（`DOC-YYMMDDHHMM_タイトル.md`）への
移行を予定しているが、**移行そのものは独立したPRとして行う**（`docs/planning/DOC-003_...`
第16章「傘マージ後の残タスク T1」参照）。**それまでは連番の採番を継続すること。**
このPR（孫5、DOC-004/DOC-005追加）も連番のまま追加している。
