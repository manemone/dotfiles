# docs/ — 文書索引

`docs/` 配下の全設計文書・計画書・ADR・運用リファレンスのナビゲーションと索引です。

## クイックナビゲーション

目的別に、最初に読むべきファイルを案内します。

| 目的 | 最初に読むべきファイル | 備考 |
|---|---|---|
| このリポジトリのルールを知る | [../AGENTS.md](../AGENTS.md) | 最重要ルール・ディレクトリ構成・デプロイの仕組みなど |
| PR を出す前に読む | [design/DOC-2608020715_プルリクエストの作法.md](design/DOC-2608020715_プルリクエストの作法.md) | 説明文の構成・コメントのプレフィクス・ブランチ構成 |
| シェルを書く前に読む | [design/DOC-2608020715-a_シェルスクリプトコーディング方針.md](design/DOC-2608020715-a_シェルスクリプトコーディング方針.md) | POSIX sh / bash の使い分け、bashism の回避 |
| デプロイを検証する | [design/DOC-2608020715-b_テスト方針.md](design/DOC-2608020715-b_テスト方針.md) | 実 HOME を汚さずに検証する4層の方法 |
| なぜ配布方式を今の形にしたかを知る | [adr/DOC-2608040229_deploy-distribution-method.md](adr/DOC-2608040229_deploy-distribution-method.md) | 世代ディレクトリ + `current` を採用した理由と、却下した案 |
| デプロイの運用手順（世代確認・ロールバック・dev モード等）を調べる | [reference/DOC-2608040805_配布実体運用ガイド.md](reference/DOC-2608040805_配布実体運用ガイド.md) | canonical prefix の構造・manifest 全フィールド・移行手順 |
| なぜ `ocw` の命名・レイアウトを今の形にしたかを知る | [adr/DOC-2608062258_ocw-worktree-naming-and-layout.md](adr/DOC-2608062258_ocw-worktree-naming-and-layout.md) | `ai/` 接頭辞の廃止・ディレクトリのネスト・git config `ocw.*` によるレイアウト表現・squash マージ検出の決定と、却下した案 |
| なぜ `ocw-meter` をこの設計にしたかを知る | [adr/DOC-2608021229_llm-cost-observability-collection-method.md](adr/DOC-2608021229_llm-cost-observability-collection-method.md) | feasibility probe の実測結果に基づく収集方式の決定記録 |
| なぜスキルを複数の AI エージェントへ配るようにしたかを知る | [adr/DOC-2608272128_skills-multi-agent-distribution.md](adr/DOC-2608272128_skills-multi-agent-distribution.md) | `skills/` の切り出し・配布先エージェントの決め方・却下した案 |
| `ocw-meter` のイベントスキーマを調べる | [reference/DOC-2608021229-c_ocw-meterイベントスキーマ.md](reference/DOC-2608021229-c_ocw-meterイベントスキーマ.md) | 全 event_type・全フィールド・費用計算式の一次情報源 |
| LLM費用のベースラインを測る手順を知る | [reference/DOC-2608021229-b_LLM費用観測ベースライン計測手順.md](reference/DOC-2608021229-b_LLM費用観測ベースライン計測手順.md) | 実PR 5〜10本での計測手順 |
| 傘ブランチの計画を確認する | [planning/](planning/) 配下の各計画書 | 進行中・完了した傘ブランチの計画書 |
| このリポジトリの AI 支援基盤を他のリポジトリへ配布する | [../templates/repo-baseline/README.md](../templates/repo-baseline/README.md) | copier テンプレート。dotfiles 本体とは独立・自己完結 |

## フォルダ構成

| フォルダ | 役割 |
|---|---|
| `design/` | 設計書・仕様・規約。**実装の指針となる規範**（「〜する」「〜しない」）を記す現役の文書 |
| `adr/` | **Architecture Decision Record** — 実測・調査結果に基づいて確定した技術的決定の記録。一度確定した決定の経緯を後から追うための文書。原則変更しない（新しい決定は新しい ADR を追加する）。決定の根拠となった実測用スクリプト等は `adr/probes/` のようなサブディレクトリに置く |
| `reference/` | **運用中に繰り返し引く文書** — 一度作って終わりではなく、日々の運用・デバッグ・拡張のたびに開く文書（イベントスキーマ、計測手順等）。man page 的な位置づけ。確定した仕様の**事実の記録**（「〜である」）を記す調べ物用の文書で、design/ のような行動規範は含まない |
| `planning/` | **傘ブランチ計画書** — 傘ブランチ着手時に書く、目的・調査結果・設計・孫ブランチ分割・実装完了条件をまとめた文書。傘のマージが完了すると現役の指針ではなく歴史的記録になる（現在の実装がどうなっているかは常にコードと reference/ を見る） |
| `archive/` | 過去の経緯・履歴。現在の開発判断には使わない |

4つの現役フォルダの使い分け:

- **`design/` と `adr/` の違い**: どちらも「決定・規範」を記しますが、`design/` は今も従うべき**現在進行形のルール**（コードを書く・PR を出すときに参照し、変わりうる）です。`adr/` は**過去に確定した1回きりの技術選定の記録**（実測・調査結果に基づき、原則変更しない。新しい決定は新しい ADR を追加する）です
- **`design/` と `reference/` の違い**: `design/` はコードを書く・PR を出すときに**従うべきルール**を書く場所、`reference/` は「このコマンドのオプション一覧」「このイベントのフィールド一覧」のように、**すでに確定している仕様を調べるための記述**を書く場所です。迷ったら「読んだ人の行動を変えるか」を基準にし、変えるなら `design/`、変えず事実を確認するだけなら `reference/` に置きます
- **`adr/` と `reference/` の違い**: `adr/` は「なぜその方式に決めたか」という**決定の経緯**を記録し、`reference/` は「その結果として今の仕様がどうなっているか」という**現在の事実**を記録します。実装が変わっても ADR は書き換えず、reference/ を更新します
- **`planning/` と他フォルダの違い**: `planning/` は傘ブランチ単位の**計画と経緯**の記録です。傘の完了後は歴史的記録として残り、現在の設計判断の根拠が知りたい場合は `design/` や `adr/` を、現在の仕様を調べたい場合は `reference/` を見てください

> **注**: `docs/` 直下には索引（本ファイル）のみを置き、それ以外の文書は `design/` `adr/` `reference/`
> `planning/` `archive/` のいずれかに配置します。`archive/` は現時点で対象文書が無く空のため、
> ディレクトリ自体は作っていません（git は空ディレクトリを追跡できません）。該当する文書ができた時点で
> 作成してください。

## 全 DOC-ID 索引

### design/ — 設計書・仕様・規約

| DOC-ID | ファイル | 概要 |
|---|---|---|
| DOC-2608020715 | [プルリクエストの作法.md](design/DOC-2608020715_プルリクエストの作法.md) | PR説明文の構成・コメントのプレフィクス・ブランチ構成の規約 |
| DOC-2608020715-a | [シェルスクリプトコーディング方針.md](design/DOC-2608020715-a_シェルスクリプトコーディング方針.md) | POSIX sh / bash の使い分け・bashism・エラーハンドリングの規約 |
| DOC-2608020715-b | [テスト方針.md](design/DOC-2608020715-b_テスト方針.md) | 実 HOME を汚さずにデプロイを検証する方法の定義 |

### adr/ — Architecture Decision Records

| DOC-ID | ファイル | 概要 |
|---|---|---|
| DOC-2608021229 | [llm-cost-observability-collection-method.md](adr/DOC-2608021229_llm-cost-observability-collection-method.md) | LLM費用・Claude利用枠の収集方式決定。孫0のfeasibility probe実測結果（transcriptのmessage.id重複問題、statusLineのrate_limits取得可否、Herdrのrole↔session紐付け等）に基づき、「事後読み取り + 軽量イベント刻み」方式を確定した（旧ID: `ADR-001`） |
| DOC-2608040229 | [deploy-distribution-method.md](adr/DOC-2608040229_deploy-distribution-method.md) | dotfiles の配布方式の決定。作業ツリーへの直接 symlink をやめ、世代ディレクトリ + `current` シンボリックリンクによる配布実体を1段挟む方式を採用した。実体コピー配布・世代を持たない方式・警告のみの最小案などの却下理由も記録 |
| DOC-2608062258 | [ocw-worktree-naming-and-layout.md](adr/DOC-2608062258_ocw-worktree-naming-and-layout.md) | `ocw` のワークツリー命名とリポジトリレイアウトの外部化の決定。`ai/` 接頭辞の廃止、スラッシュ入りブランチ名のネストディレクトリ化、git config `ocw.*` によるフルパス雛形1本でのレイアウト表現、squash マージ検出を含むマージ済み判定の再定義を確定した。フラット化・enum によるレイアウト表現・`gh` 依存の判定などの却下理由も記録 |
| DOC-2608272128 | [skills-multi-agent-distribution.md](adr/DOC-2608272128_skills-multi-agent-distribution.md) | スキルの配布方式の決定。`claude/skills/` を `skills/` へ切り出して独立したツールとし、Claude Code だけでなく Codex・OpenCode のスキルディレクトリへも同じ実体を symlink する方式を採用した。3者が同じ SKILL.md 形式を読むという実機調査が根拠。`claude/deploy.sh` の拡張・スキルごとの配布先指定などの却下理由も記録 |

### planning/ — ロードマップ・計画

| DOC-ID | ファイル | 概要 |
|---|---|---|
| DOC-2607281430 | [ai-housekeeping_計画.md](planning/DOC-2607281430_ai-housekeeping_計画.md) | dotfiles リニューアル計画（傘 `ai/housekeeping`、全孫マージ済） |
| DOC-2607291400 | [ai-dotfiles-add-tools_計画.md](planning/DOC-2607291400_ai-dotfiles-add-tools_計画.md) | 自作ツールの dotfiles への移行計画（傘 `ai/dotfiles-add-tools`、全孫マージ済） |
| DOC-2608020558 | [repo-baseline_計画.md](planning/DOC-2608020558_repo-baseline_計画.md) | AI エージェント支援基盤の整備と汎用テンプレート化の傘ブランチ計画書（傘 `ai/repo-baseline`） |
| DOC-2608021229-a | [ai-llm-cost-observability_計画.md](planning/DOC-2608021229-a_ai-llm-cost-observability_計画.md) | LLM費用・Claude利用枠の観測基盤（`ocw-meter`）構築計画（傘 `ai/llm-cost-observability`、全孫マージ済。旧ID: `DOC-003`） |
| DOC-2608040234 | [ai-deploy-stability_計画.md](planning/DOC-2608040234_ai-deploy-stability_計画.md) | デプロイ配布方式の安定化の傘ブランチ計画書（傘 `ai/deploy-stability`）。ADR DOC-2608040229 で確定した配布実体方式を6本の孫へ分解したもの |
| DOC-2608062259 | [ai-ocw-naming-and-layout_計画.md](planning/DOC-2608062259_ai-ocw-naming-and-layout_計画.md) | `ocw` のワークツリー命名とリポジトリレイアウト外部化の傘ブランチ計画書（傘 `ai/ocw-naming-and-layout`）。ADR DOC-2608062258 で確定した方式を4本の孫へ分解したもの |
| DOC-2608081456 | [ocw-meter-accuracy_計画.md](planning/DOC-2608081456_ocw-meter-accuracy_計画.md) | `ocw-meter` の計測精度是正の傘ブランチ計画書（傘 `ocw-meter-accuracy`）。実ストア突合で判明した6件の計測ズレ（ingest 欠測・費用メトリクスの空洞化・帰属不能・テストによるストア汚染・価格表のズレ・退避キャッシュのプルーニング漏れ）を6本の孫へ分解したもの |
| DOC-2609031400 | [ocw-pane-roles-and-workspace-labels_計画.md](planning/DOC-2609031400_ocw-pane-roles-and-workspace-labels_計画.md) | `ocw -H` のペイン構成切り替えと Herdr ワークスペースラベル日本語化の傘ブランチ計画書（傘 `ai/ocw-pane-roles`）。commander を省いた2ペインモードの追加、`umbrella-orchestrator` の孫 spawn とラベル付けの更新、スキル文書に残る `ai/` 接頭辞前提の除去を2本の孫へ分解したもの |

### reference/ — 運用リファレンス

| DOC-ID | ファイル | 概要 |
|---|---|---|
| DOC-2608021229-b | [LLM費用観測ベースライン計測手順.md](reference/DOC-2608021229-b_LLM費用観測ベースライン計測手順.md) | `ocw-meter` 導入後、実PR 5〜10本でLLM費用・Claude利用枠のベースラインを計測する手順書（旧ID: `DOC-004`） |
| DOC-2608021229-c | [ocw-meterイベントスキーマ.md](reference/DOC-2608021229-c_ocw-meterイベントスキーマ.md) | `ocw-meter` が書く全イベント型の恒久リファレンス。共通エンベロープの全フィールド、全 `event_type`、`idempotency_key` の生成規則、費用計算式、`completeness` の判定基準を実データで検証した上でまとめたもの（旧ID: `DOC-005`） |
| DOC-2608040805 | [配布実体運用ガイド.md](reference/DOC-2608040805_配布実体運用ガイド.md) | 世代ディレクトリ + `current` 配布方式の日常運用手順。canonical prefix のディレクトリ構造・manifest の全フィールド・世代確認・ロールバック・dev モードの出入り・リンク切れ対処・旧方式からの移行手順 |

## 新規ファイル追加時のルール

`docs/` 配下に新しい `.md` ファイルを追加する際は、以下の3ステップを必ず実行してください。
いずれかを省略すると索引から漏れ、発見不能なファイルが生まれます。

1. **DOC-ID の割り当て**: `./tools/doc-id/doc-id assign docs/path/to/new_file.md` を実行する
   （`DOC-DOCID_PLACEHOLDER_<説明的ファイル名>.md` という名前で作成しておけば、
   このコマンドが実際のタイムスタンプへ置換し、リポジトリ内の参照も更新する。
   **プレースホルダを使わずに作ったファイルへ `assign` した場合、改名は行われるが
   既存の参照は更新されないため、`git grep` で旧ファイル名を検索して手作業で直すこと**）
2. **全 DOC-ID 索引への追記**: このファイル（`docs/README.md`）の該当フォルダの表に、
   DOC-ID・ファイル名・1行説明を追記する
3. **フォルダ README への追記**: ファイルを追加したフォルダに `README.md` が存在する場合は、
   その表にも同様に追記する（`design/README.md` など）。`adr/` `planning/` `reference/` には
   現時点で `README.md` を置いておらず、これらの索引はこのファイルの表のみで管理する
   （各フォルダの本数が少なく、専用の索引ファイルを設けるほどの規模になっていないため）

配置先は「フォルダ構成」節の使い分けを参照して `design/` / `adr/` / `planning/` / `reference/` /
`archive/` のいずれかから選んでください。`docs/` 直下には置きません。

### DOC-ID 命名規則

```
DOC-YYMMDDHHMM_<説明的ファイル名>.md
```

- `YYMMDDHHMM` はファイルの作成日時（git 履歴から自動取得される）
- DOC-ID は **不変**。ファイルの移動・リネームがあっても変更しない
- 衝突時は `DOC-YYMMDDHHMM-a`、`DOC-YYMMDDHHMM-b` のようにサフィックスが付与される
- 採番前のファイルは `DOC-DOCID_PLACEHOLDER_<説明的ファイル名>.md` という名前で作成してよい。
  採番ツールがプレースホルダをタイムスタンプに一括置換し、リポジトリ内の参照も同時に更新する
- ADR も含め、`docs/` 配下の全文書がこの形式に統一されています。「ADR であること」は
  `adr/` フォルダへの配置と文書内の見出しで表現し、`ADR-NNN` という別名前空間は使いません

### 検証コマンド

以下のコマンドで検証できます。

```bash
./tools/doc-id/doc-id check    # 命名規則違反を検出
./tools/doc-id/doc-id verify   # 全 DOC-ID 参照先の実在確認
```

> **注意**: `README.md` は `doc-id check` の対象外です。DOC-ID の割り当ては不要です。
