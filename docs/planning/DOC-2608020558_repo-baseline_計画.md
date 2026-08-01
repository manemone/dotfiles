# 計画書: AI エージェント支援基盤の整備と汎用テンプレート化

傘ブランチ: `ai/repo-baseline`
ターゲット: `master`

## 概要

このリポジトリには AI エージェント向けの支援ファイルがほぼ無い。同一マシンの
`lora-dataset-forge`（以下 LDF）には十分に整備された一式があるため、これを参考実装として
dotfiles にも同等の基盤を作る。さらに **その汎用部分を copier テンプレートとして抽出し、
今後増えるリポジトリ（業務リポジトリを含む）へ再利用可能にする** ところまでを範囲とする。

大きく2段階:

1. **孫1〜5**: dotfiles 自身を LDF 相当のレベルまで整備する
2. **孫6**: dotfiles と LDF の2例を突き合わせ、汎用部分を copier テンプレートに抽出する

抽象化は2例目からしか妥当に行えないため、孫1〜5 の時点で汎用化を先回りしない。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `ai/rb-01-agents-md` | ルート `AGENTS.md` + `CLAUDE.md`（`@AGENTS.md` 1行）の二層構造 | ✅ PR #29 マージ済 |
| 2 | `ai/rb-02-docs` | `docs/` 基盤: 索引 README・フォルダ規約・PR の作法・シェルコーディング方針・テスト方針 | ✅ PR #31 マージ済 |
| 3 | `ai/rb-03-doc-id` | DOC-ID ツール移植（Ruby, 自己完結）＋ 既存 `DOC-001/002` のタイムスタンプ形式への移行 | 🔄 実装中 |
| 4 | `ai/rb-04-quality-gate` | pre-commit framework 導入 + shellcheck/shfmt + デプロイスモークテスト + CI | ⬜ 待機中 |
| 5 | `ai/rb-05-ai-config` | リポジトリ用 `.claude/settings.json` + `opencode.json` + `.gitignore` 修正 | ⬜ 待機中 |
| 6 | `ai/rb-06-copier-template` | ★ 汎用部分の抽出と copier テンプレート化 + 適用スキル | ⬜ 待機中 |

## 依存関係と実行順序

**全孫が直列**。並列化できる箇所が無いわけではないが、各孫が `AGENTS.md` の同じ節を触るため
コンフリクトのコストが並列化の利益を上回る。

```
孫1 (AGENTS.md)
  ↓ 他孫はすべて AGENTS.md の該当節を追記していくため、土台が先
孫2 (docs/)
  ↓ AGENTS.md から docs/ の規約文書を参照する。参照先が先に要る
孫3 (doc-id)
  ↓ doc-id の check/verify は docs/ が整備済みであることが前提。
    既存 DOC-001/002 の形式移行も doc-id ツールが無いとできない
孫4 (品質ゲート)
  ↓ pre-commit に doc-id フックを組み込むため、孫3 が先。
    テスト方針（孫2）に基づいてスモークテストを実装する
孫5 (AI 設定ファイル)
  ↓ opencode.json の instructions 配列が docs/ の DOC-ID を参照するため、孫2・孫3 が先
孫6 (copier テンプレート)  ← 孫1〜5 全マージ後
```

---

## 確定事項（孫の判断で覆さないこと）

以下は傘レベルで議論・決定済み。実装時に蒸し返さない。

| 領域 | 決定 | 理由 |
|---|---|---|
| テンプレート配布・更新 | **copier** | `copier update` の3-wayマージで撒き先のカスタムを保ったまま上流更新を取り込める。質問機能でプレースホルダを埋められる。git URL 指定でき独立リポジトリ化と相性が良い。**自前の init/check/diff CLI は書かない** |
| 参照の不変性 | **DOC-ID 維持**（LDF 方式） | 「検出」ではなく「予防」。プレースホルダ運用で採番が自動化され、AI に採番を考えさせずに済む。リンクチェッカー（lychee 等）は検出のみで修復できないため採用しない |
| doc-id の実装言語 | **Ruby** | LDF の実装を移植でき、フルスクラッチ不要 |
| フック管理 | **pre-commit framework** | 隔離環境の自動構築・バージョン固定・差分ファイルのみ実行・CI との一致。自前 `.githooks/` は採用しない |
| pre-commit の参照方式 | **当面 `repo: local`** | フック配布元にするにはリポジトリルートに `.pre-commit-hooks.yaml` が必要。独立リポジトリ化した時点で `repo: <URL>` に切り替える |
| 規約文書 | **自作** | 代替なし。ここが本質的な資産 |
| 傘ブランチ運用 | **既存 umbrella-orchestrator スキル** | 再実装しない |
| 開発者が入れるもの | **uv だけ** | `uv tool install copier pre-commit`。uv は単一バイナリで管理者権限不要 |

### 検討して却下した案（蒸し返さないこと）

- 自前 `bin/repo-baseline` CLI + `baseline.version` → copier で足りる。3-wayマージの自前実装は無駄
- lychee 等のリンクチェッカーで DOC-ID を代替 → 検出のみで修復できない
- doc-id を bash + awk で実装 → pre-commit が隔離環境を作るので依存最小の制約は不要
- doc-id を dotfiles の `bin/` に置いて PATH 経由で共有 → 業務リポジトリ・CI・他人のマシンで動かない
- doc-id を Python で実装 → LDF に Ruby 実装があり移植のほうが安い

---

## 傘レベルの判断（この計画書で新たに決めたこと）

### 判断1: DOC-ID 形式は **タイムスタンプ式（`DOC-YYMMDDHHMM`）に統一する**

既存の `DOC-001` / `DOC-002` 形式は廃止し、LDF と同じ `DOC-YYMMDDHHMM_<説明的ファイル名>.md`
に移行する。

理由:

1. **連番は中央カウンタを必要とする。** 「次の番号」を知るには既存ファイル全走査で max+1 を
   求めることになり、傘ブランチ + 複数孫の並列開発（このリポジトリの標準ワークフロー）では
   同じ番号が別ブランチで同時に払い出される。タイムスタンプは git log の作成日時から導出され、
   衝突時もサフィックス（`-a`, `-b`）で自動回避できる。
2. **移植する doc-id ツールがタイムスタンプ形式を前提としている。** 連番を維持するなら
   ツールを別実装するか大改造する必要があり、LDF からの移植という前提が崩れる。
3. **プレースホルダ運用（`DOC-DOCID_PLACEHOLDER_<説明>.md`）がタイムスタンプ形式でしか成立しない。**
   これは「AI に採番を考えさせない」という DOC-ID 運用の中核。
4. **テンプレートは撒き先ごとの状態を持てない。** 連番だと撒き先ごとにカウンタ相当の状態管理が
   要る。タイムスタンプは撒き先の git 履歴だけで自己完結する。

移行対象は既存2件（`DOC-001_ai-housekeeping_計画.md` / `DOC-002_ai-dotfiles-add-tools_計画.md`）。
孫3 で `tools/doc-id assign` により改名し、リポジトリ全体の参照も同時に更新する。

**この計画書自身は最初からタイムスタンプ形式で作成してある**（`DOC-2608020558`）。
これにより傘の進行中に計画書のパスが変わることがなく、spawn プロンプトの参照が壊れない。

### 判断2: 孫の分割を BATON 提案の5本から **6本** に変更

BATON の孫C（品質ゲート）は「pre-commit 導入 + shellcheck/shfmt + doc-id 移植」を1本に
まとめていたが、これを孫3（doc-id）と孫4（pre-commit + linter）に分割する。

理由:

- **差分の性質が違う。** doc-id 移植は Ruby 約700行の新規追加。shfmt 導入は既存シェルスクリプト
  全ファイルの整形差分。混ぜるとレビュー不能になる。
- **DOC-ID 形式移行（判断1）は doc-id ツールと不可分**であり、BATON では孫D に置かれていたが
  ツールと同じ孫に置くのが自然。結果として孫D の残りは AI 設定ファイルのみになり、独立した1本になる。

### 判断3: pre-commit の Ruby は `language_version: default`

BATON の孫C では `language_version: '3.3'` が提案されていたが、`default` を採用する。

理由: バージョンを固定すると、システムに Ruby 3.3 が無い**すべての**環境で pre-commit が
毎回 ruby-build によるビルドを走らせる（数分〜十数分、ビルドツールとネットワークが必要）。
`default` ならシステム Ruby があればそれを使い、無い場合のみ pre-commit が用意する。
移植する doc-id は stdlib（`open3` / `fileutils`）しか使わないため、Ruby 3.0 以降なら
どのバージョンでも動く。バージョン固定の利益が薄く、コストが大きい。

### 判断4: `.gitignore` の `/.claude/` を狭める

現状 `.gitignore` に `/.claude/` があり、リポジトリ用の `.claude/settings.json` を
コミットできない。孫5 でこれを `/.claude/settings.local.json` に狭め、`settings.json`
のみ追跡する。

---

## 孫6 で撒かれる成果物の依存条件（傘レベルの設計判断）

「撒き先の環境に何を要求してよいか」は傘レベルの決定であり、孫の実装判断に委ねない。

### 撒き先に要求してよいもの

| 要求 | 根拠 |
|---|---|
| **git** | テンプレートは git リポジトリを前提とする（DOC-ID の採番が `git log` に依存、pre-commit が git フック） |
| **uv** | 開発者が入れる唯一のもの。単一バイナリ・管理者権限不要・macOS/Linux/WSL2 すべてで動く |
| **`uv tool install copier pre-commit`** | 上記から導出。Python 本体すら uv が持ってくる |
| **ネットワーク**（初回セットアップ時のみ） | `copier copy` と `pre-commit install-hooks` に必要。日常の commit 時には不要 |
| **POSIX シェル環境** | 撒くスクリプトは `#!/bin/sh` または `#!/usr/bin/env bash` の範囲に収める |

### 撒き先に要求してはならないもの

| 要求してはならないもの | 理由・代替 |
|---|---|
| **Ruby がシステムに入っていること** | pre-commit の `language: ruby` が隔離環境を用意する。ただし `language_version` は固定せず `default`（判断3） |
| **特定の言語ランタイム（Node / Go / Rust など）** | 撒き先の言語は不明。lint/test コマンドは copier の質問で受け取り、テンプレート側は中身を知らない |
| **mise / rbenv / asdf などのバージョンマネージャ** | 環境依存。pre-commit の隔離環境で代替する |
| **Docker** | 業務環境で使えないことがある |
| **この dotfiles リポジトリ、およびそこから配布される一切のもの** | `templates/repo-baseline/` は自己完結。特に `shared/helpers.sh` を source しない |
| **Claude Code であること** | ルールの本体は `AGENTS.md` に置く。`CLAUDE.md` は `@AGENTS.md` の1行のみ |
| **GitHub であること** | CI 設定（GitHub Actions）は copier の質問で ON/OFF できるようにし、既定では生成するが必須にはしない |

### 独立リポジトリ化に備えた制約（必須・受け入れ条件）

- `templates/repo-baseline/` は dotfiles の他の部分に**一切依存しない自己完結**とする
- dotfiles 固有のパス・前提・命名を埋め込まない
- **受け入れ条件**: このディレクトリを別リポジトリへそのまま移動するだけで copier テンプレートとして成立すること
- 現時点では事例が2件（dotfiles / LDF）しかなく抽象化が未成熟なため、
  **リポジトリ分割は行わず「いつでも切り出せる状態」に留める**

---

## 全孫共通の注意（プロンプトにも再掲するが、ここが正）

### 1. `claude/` と `.claude/` と ルート `AGENTS.md` を絶対に混同しないこと

| 対象 | 正体 | 誰が読むか |
|---|---|---|
| `claude/CLAUDE.md`, `claude/settings.json`, `claude/skills/` | **配布される成果物。** deploy.sh がユーザーの `~/.claude/` へ symlink する | このリポジトリを使う人間のマシンの Claude Code |
| ルート `AGENTS.md` / `CLAUDE.md` | **このリポジトリを開発するためのルール** | このリポジトリで作業する AI |
| `.claude/settings.json` | **このリポジトリで作業する時の permissions** | このリポジトリで作業する Claude Code |

`claude/CLAUDE.md`（配布物、個人の口調設定などが入っている）を編集する孫はいない。触らないこと。

### 2. 丸コピはしない

LDF は Ruby CLI + LoRA 学習。dotfiles は「シェルスクリプト + symlink デプロイ +
クロスプラットフォーム（macOS / Linux / WSL2）」。**構造とお作法を移植し、中身は
dotfiles 用に書き下ろす。** LDF 固有の記述（`raw/` 保護、canon レシピ、VLM mock 罠、
rubocop、学習コマンド）は持ち込まない。

### 3. AI 不問で書く

ルール本体は `AGENTS.md`。`CLAUDE.md` は `@AGENTS.md` の1行のみ。
Claude 固有の機能名・書式に閉じない。

### 4. 他リポジトリの DOC-ID を地の文に書かない（孫3 マージ後は必須）

`tools/doc-id verify` は追跡下の全 `.md` を走査し、`DOC-` + 10桁数字の**裸の参照**が
このリポジトリに実在するかを検証する。LDF の文書 ID をそのまま地の文に書くと切れ参照になり
コミットがブロックされる。参照が必要な場合はコードブロック内に書くか、ID を使わず文書名で書く。

### 5. 破壊的操作の禁止

**人間の明示的指示がない限り、`git merge` / `git pull` / `git reset --hard` /
`git push --force` / `gh pr merge` は実行しない。** 例外はない。

---

## 孫1用プロンプト:

````
## タスク: ルート AGENTS.md と CLAUDE.md を作る

このリポジトリ（manemone/dotfiles）で作業する AI エージェント向けのルールブックを作る。
参考実装として /home/manemone/projects/lora-dataset-forge/main/AGENTS.md を読むこと。
ただし**丸コピはしない**。あちらは Ruby CLI + LoRA 学習、こちらは
シェルスクリプト + symlink デプロイ + クロスプラットフォーム。構造だけ借りて中身は書き下ろす。

計画書 docs/planning/DOC-2608020558_repo-baseline_計画.md の
「全孫共通の注意」を必ず読んでから着手すること。

### 作るもの

#### 1. ルート `AGENTS.md`（新規）

以下の節を持つこと。節の粒度と順序は LDF の AGENTS.md に倣う。

- **概要**: クロスプラットフォーム dotfiles。mise でランタイムを固定し、
  各ツールディレクトリの deploy.sh がユーザーの HOME に symlink を張る、という一文で伝わる説明
- **最重要ルール**:
  - 人間の明示的指示がない限り `git merge` / `git pull` / `git reset --hard` /
    `git push --force` / `gh pr merge` を実行しない。例外はない。すべての不可逆操作の前に
    このルールを照合する
  - **deploy スクリプトを実オペレーションで実行しない。** symlink 先はユーザーの実 HOME であり、
    `~/.zshrc` `~/.tmux.conf` `~/.claude/settings.json` `~/bin/*` を実際に置き換える。
    動作確認は `--dry-run`、または `HOME` を一時ディレクトリに差し替えたサンドボックスで行う
  - 指示された範囲外の機能を先回りして実装しない
  - linter の抑制ディレクティブ（`# shellcheck disable=...` 等）や
    linter 設定の除外・閾値緩和を、AI の判断で追加しない。違反が設計上不合理だと判断した場合は、
    抑制せず違反内容・対象ファイル・判断理由を人間に報告する
- **ディレクトリ構成**: `zsh/` `nvim/` `tmux/` `bin/` `claude/` `shared/` `docs/` の役割を表で。
  各ツールディレクトリは「設定ファイル本体 + `deploy.sh` + `README.md`」という共通構造であること
- **3つの領域（混同しないこと）**: 計画書「全孫共通の注意」の1番の表をここに書く。
  `claude/`（配布物）/ ルート `AGENTS.md`（開発ルール）/ `.claude/`（このリポジトリの permissions）
  ※ `.claude/settings.json` は孫5 で追加されるので「予定」と書かず、
  「リポジトリで作業する AI 向けの permissions を置く場所」とだけ書けばよい
- **デプロイの仕組み**:
  - `deploy-all.sh` が `shared/helpers.sh` を source し、`AVAILABLE_TOOLS` を解決して
    各 `<tool>/deploy.sh` を呼ぶ
  - `--dry-run` / `--force` / `--only <tools>` / `--backup` / `--no-backup`
  - symlink は `shared/helpers.sh` の `symlink_backup` 経由で張る。既存ファイルは
    `.backup` に退避される。`symlink_restore` が uninstall 側
  - `claude/settings.json` だけは symlink ではなく、ベース設定と `settings.machine.json` を
    マージした**実ファイル**を生成する（理由も1行で）
- **クロスプラットフォーム制約**:
  - `shared/helpers.sh` は POSIX sh。bashism を書かない
  - `deploy-all.sh` `uninstall.sh` `*/deploy.sh` も `#!/bin/sh`
  - `bin/ocw` `bin/claude-ds` は bash
  - 分岐は `is_macos` / `is_linux` / `is_wsl` / `get_brew_prefix` を使い、直接 `uname` を叩かない
  - macOS の BSD 版コマンドと GNU 版の差異（`sed -i`、`date`、`readlink -f` など）に注意
- **コミット前の必須ステップ**: この時点では「変更したシェルスクリプトが
  `sh -n` / `bash -n` で構文エラーにならないこと」「`--dry-run` で意図した動作になること」程度でよい。
  **孫4 で pre-commit が入った時点でこの節が更新される**旨を1行書いておく
- **PR 作成時の注意**: PR を作る前に `docs/design/` の「プルリクエストの作法」を読むこと。
  ※ その文書は孫2 で作られる。ここでは**文書名で参照し、DOC-ID を書かない**
  （まだ存在しないため。孫2 がリンクを張り直す）
- **実装時の注意**:
  - 新しいツールディレクトリを足すときは `shared/helpers.sh` の `AVAILABLE_TOOLS` にも追加する
  - README は「ルート README.md（全体）」と「各ツールの README.md（詳細）」の二層。
    片方だけ更新しない

#### 2. ルート `CLAUDE.md`（新規）

中身は以下の1行のみ。

```
@AGENTS.md
```

ルール本体を CLAUDE.md 側に書かないこと。AI 不問設計の要。

#### 3. ルート `README.md`（更新）

「Directory Structure」のツリーに `AGENTS.md` と `CLAUDE.md` を追加する。
それ以外は触らない。

### やらないこと

- `claude/CLAUDE.md`（配布物）を触ること。別物
- `docs/` の新規文書作成（孫2 の担当）
- pre-commit / linter / CI の設定（孫4 の担当）
- `.claude/` `opencode.json`（孫5 の担当）

### 検証

- `AGENTS.md` に LDF 固有の記述（raw/、canon、VLM、rubocop、bundle exec）が残っていないこと
- `CLAUDE.md` が1行であること
- 記述したパス・関数名（`symlink_backup` 等）が実在すること
````

## 孫2用プロンプト:

````
## タスク: docs/ の基盤を作る

`docs/` を「索引 + フォルダ規約 + 規約文書」の構造にする。
参考実装として以下を読むこと（丸コピはしない）:

- /home/manemone/projects/lora-dataset-forge/main/docs/README.md
- /home/manemone/projects/lora-dataset-forge/main/docs/design/DOC-2606281852_プルリクエストの作法.md
- /home/manemone/projects/lora-dataset-forge/main/docs/design/DOC-2606282001_コーディング方針.md

計画書 docs/planning/DOC-2608020558_repo-baseline_計画.md の
「全孫共通の注意」と「判断1: DOC-ID 形式」を必ず読んでから着手すること。

### 重要: ファイル名の DOC-ID について

このリポジトリは DOC-ID をタイムスタンプ形式（`DOC-YYMMDDHHMM_<説明>.md`）に統一する
（計画書の判断1）。ただし採番ツールは孫3 で入る。

**この孫で新規作成する docs/ 配下のファイルは、ファイル名を
`DOC-DOCID_PLACEHOLDER_<説明的ファイル名>.md` にすること。**
孫3 で `tools/doc-id assign` を実行すると実際のタイムスタンプに一括置換され、
リポジトリ全体の参照も自動更新される。プレースホルダのまま参照を書いてよい。

既存の `docs/planning/DOC-001_*` `DOC-002_*` は**この孫では触らない**（孫3 の担当）。

### 作るもの

#### 1. `docs/README.md`（新規） — 索引

- 目的別クイックナビゲーション（「PR を出す前に読む」「シェルを書く前に読む」
  「デプロイを検証する」など、目的 → 最初に読むファイル の表）
- フォルダ構成の表:
  | フォルダ | 役割 |
  |---|---|
  | `design/` | 設計書・仕様・規約。実装の指針となる現役の文書 |
  | `planning/` | ロードマップ・傘ブランチ計画書 |
  | `archive/` | 過去の経緯・履歴。現在の開発判断には使わない |
  `docs/` 直下には索引（本ファイル）のみを置き、他は design/planning/archive のいずれかに置く旨を明記
  ※ LDF の `training/` は LDF 固有なので作らない
  ※ `archive/` は現時点で空になる。空ディレクトリは git で追跡できないので、
    ディレクトリは作らず「必要になったら作る」と README に書くだけでよい
- 全 DOC-ID 索引（フォルダごとの表: DOC-ID / ファイル / 概要）
- 新規ファイル追加時のルール（3ステップ: DOC-ID 割当 → 索引に追記 → 該当フォルダの README に追記）
- DOC-ID 命名規則の説明（`DOC-YYMMDDHHMM_<説明的ファイル名>.md`、不変であること、
  衝突時のサフィックス、プレースホルダ運用）
- 検証コマンドの案内（`tools/doc-id check` / `tools/doc-id verify`）
  ※ ツール実体は孫3。「孫3 で入る」とは書かず、そういうコマンドがある前提で書いてよい
  ※ ここでは `README.md` は doc-id check の対象外であることも明記

#### 2. `docs/design/README.md`（新規）

design/ フォルダの文書一覧（DOC-ID / ファイル / 概要 の表）。

#### 3. `docs/design/DOC-DOCID_PLACEHOLDER_プルリクエストの作法.md`（新規）

LDF 版をベースにするが、以下を dotfiles 用に書き換える:

- **説明文の構成**（背景・目的・実装内容・レビューで見てほしいところ・テスト結果・今後の予定）
  と基本ルール（ですます調・平易な言葉・セッション内の固有名詞を入れない）は**そのまま流用**。
  ここは完全汎用な資産
- **コメントのプレフィクス**（🤖🔍 / 🤖💬 / 🤖❓ / 🤖✅ / 👤🔍 / 👤💬 / 👤❓ と
  `[モデル名 | エフォート]` メタデータ）も**そのまま流用**
- **テスト結果の例**を dotfiles のものに差し替える（`bundle exec rubocop` ではなく
  `pre-commit run --all-files` 相当。孫4 で確定するので「lint とテストが緑であることの確認のみ」
  という書き方に留め、具体コマンド例は最小限にする）
- **ブランチ構成**の節は LDF の MVP 固有の例を消し、
  「`master` = 本番、`ai/<topic>` = 傘ブランチ、`ai/<prefix>-NN-<slug>` = 孫ブランチ。
  孫は傘に PR を出し、全部マージ後に傘から `master` へ PR を出す」という一般形で書く
- **傘ブランチの運用手順そのものは書かない。** umbrella-orchestrator スキルの領分であり、
  二重管理になる。「運用は umbrella-orchestrator スキルに従う」と一行参照するに留める

#### 4. `docs/design/DOC-DOCID_PLACEHOLDER_シェルスクリプトコーディング方針.md`（新規）

LDF の「コーディング方針」の**構造**（機械的に検出できることは linter に委ね、
ここでは linter が判定できない思想を書く）を借りて、シェルスクリプト版を書き下ろす。
Ruby の内容は一切持ち込まない。以下を含めること:

- **方言の使い分け（このリポジトリの既存慣行。ここが最重要）**
  | 対象 | 方言 | 理由 |
  |---|---|---|
  | `shared/helpers.sh` | POSIX sh | 全 deploy スクリプトから source される。最大公約数 |
  | `deploy-all.sh` / `uninstall.sh` / `*/deploy.sh` | POSIX sh (`#!/bin/sh`) | ブートストラップ時点で bash があるとは限らない |
  | `bin/ocw` / `bin/claude-ds` | bash | デプロイ後のユーザー向けツール。bash 前提でよい |
  実際のファイルの shebang を読んで確認してから書くこと
- **POSIX sh で避けるべき bashism の具体列挙**: 配列、`[[ ]]`、`local`（※既存コードの実態を
  確認して判断すること）、`${var,,}` `${var^^}`、`function` キーワード、`$'...'`、
  `<<<`（herestring）、`source`（`.` を使う）、`==`（`=` を使う）
- **エラーハンドリング**: bash スクリプトは `set -euo pipefail`。POSIX sh は
  `set -eu`（`pipefail` は POSIX にない）。既存コードは `set -u` のみで、各コマンドの
  終了コードを個別に取って集約する方針の箇所がある。**既存の方針を読んでから書くこと。
  実態と違うルールを書かない**
- **クォート**: 変数展開は原則 `"$var"`。意図的に単語分割させる箇所（`AVAILABLE_TOOLS` の
  ループなど）はコメントで意図を明示する
- **未定義変数**: `${VAR:-default}` を使う。`set -u` 下で裸の `$VAR` を書かない
- **関数の命名と副作用**: `shared/helpers.sh` の関数はプレフィクス付きローカル変数
  （`_rt_` `_bd_` など）で名前空間衝突を避ける既存慣行がある。踏襲すること
- **移植性**: `sed -i` / `date` / `readlink -f` / `mktemp` / `stat` の BSD/GNU 差異。
  `echo` より `printf`
- **ユーザーの HOME を壊さない**: 破壊的操作の前に必ずバックアップ（`symlink_backup` を使う）。
  `rm -rf` を変数展開込みで書かない
- **linter 抑制を AI の判断で追加しない**（`# shellcheck disable=` / 設定の除外・閾値緩和）。
  違反が設計上不合理なら、抑制せず人間に報告する

#### 5. `docs/design/DOC-DOCID_PLACEHOLDER_テスト方針.md`（新規）

**この孫で最も設計判断が要る文書。** 「実 HOME を汚さずにデプロイを検証する方法」を設計すること。

調査済みの事実（前提として使ってよい）:
- すべての deploy スクリプトは `$HOME` 環境変数を参照しており、`~` のハードコードは無い。
  したがって `HOME` を一時ディレクトリに差し替えれば実 HOME を汚さずに実行できる
- ただし副作用のあるツールが存在する:
  - `zsh/deploy.sh` は `$ANTIDOTE_HOME`（既定 `$HOME/.antidote`）へ git clone する（ネットワーク）
  - `nvim/deploy.sh` は lazy.nvim を clone する（ネットワーク）
  - `claude/deploy.sh` は symlink ではなく設定ファイルをマージ生成する
  - `bin/deploy.sh` / `tmux/deploy.sh` は純粋な symlink のみ

これを踏まえ、以下の層を定義すること:

| 層 | 手段 | 対象 | 実行タイミング |
|---|---|---|---|
| 構文検査 | `sh -n` / `bash -n`、shellcheck | 全シェルスクリプト | 毎コミット |
| ドライラン | `./deploy-all.sh --dry-run` | 全ツール | 毎コミット |
| サンドボックス実行 | `HOME=$(mktemp -d)` で実際に deploy | ネットワーク不要なツール | CI・ローカル |
| 実マシン検証 | 実 HOME に対する `--dry-run` → 人間の確認 → 実行 | 全ツール | リリース前に人間が |

サンドボックス実行の検証項目（symlink が張られたか、バックアップが作られたか、
`--only` フィルタが効くか、冪等か＝2回実行しても壊れないか、`uninstall.sh` で戻るか）を
チェックリストとして書く。**スクリプトの実装は孫4 の担当**。この文書は「何をどう検証するか」
を定義するところまで。

「AI はこの検証を人間の実 HOME に対して実行してはならない」を明記すること。

#### 6. ルート `AGENTS.md`（更新）

- 「PR 作成時の注意」の参照を、作成した「プルリクエストの作法」への
  **プレースホルダ DOC-ID 付きの相対リンク**に張り替える
- 「コードの書き方」節を追加し、「シェルスクリプトコーディング方針」を参照させる
- 「コミット前の必須ステップ」に「`docs/` 配下に新規ファイルを追加する場合は
  `DOC-DOCID_PLACEHOLDER_<説明>.md` で作り、`tools/doc-id assign` で採番する」を追加
- 「実装時の注意」に「docs/ の文書を参照するときは DOC-ID を使う」を追加

#### 7. ルート `README.md`（更新）

Directory Structure の `docs/` の内訳を実態に合わせる（現在 `planning/` のみの記載）。

### 検証

- 作成した全 md ファイル名が `DOC-DOCID_PLACEHOLDER_` で始まること（README.md を除く）
- 文書内のリンクがすべて解決すること（相対パスで実ファイルを指しているか目視確認）
- LDF 固有の記述（Ruby、rubocop、raw/、canon、VLM、学習）が混入していないこと
- **他リポジトリの DOC-ID（`DOC-` + 10桁数字）を地の文に書いていないこと。**
  参考文献としてどうしても示す必要があればコードブロック内に書く
````

## 孫3用プロンプト:

````
## タスク: DOC-ID ツールを移植し、既存 DOC-ID をタイムスタンプ形式へ移行する

計画書 docs/planning/DOC-2608020558_repo-baseline_計画.md の
「判断1: DOC-ID 形式」「全孫共通の注意」を必ず読んでから着手すること。

### 移植元

- /home/manemone/projects/lora-dataset-forge/main/bin/doc-id （208行）
- /home/manemone/projects/lora-dataset-forge/main/lib/doc_id/scanner.rb （141行）
- /home/manemone/projects/lora-dataset-forge/main/spec/doc_id/tool_spec.rb （346行）

いずれも Ruby stdlib（`open3` / `fileutils` / `tmpdir`）しか使っていない。

### 配置（重要: 孫6 でそのままテンプレートへ移す）

```
tools/doc-id/
├── doc-id              # 実行可能スクリプト（エントリポイント）
├── lib/doc_id/
│   ├── tool.rb         # DocId::Tool
│   └── scanner.rb      # DocId::Scanner
└── test/
    └── doc_id_test.rb  # minitest
```

- 移植元は `bin/doc-id` + `lib/doc_id/scanner.rb` という **リポジトリのトップレベルに
  散らばった配置**だが、テンプレートとして撒くには1ディレクトリに自己完結している必要がある。
  `tools/doc-id/` 配下に閉じること
- `require_relative` で解決すること。`$LOAD_PATH` をいじったり、リポジトリルートからの
  相対パスを前提にしたりしない
- エントリポイントは `chmod +x` して `./tools/doc-id/doc-id` で直接実行できること
- リポジトリルートの解決は移植元と同じく `git rev-parse --show-toplevel` で行う
  （スクリプトの設置場所に依存しないため。これは維持する）

### 汎用化（dotfiles 固有・LDF 固有の前提を埋め込まないこと）

移植元を読み、以下を確認・対処すること:

1. **`LEGACY_REF`（`docs/\d{2}` の旧参照検出）は LDF 固有。** LDF が過去に使っていた
   `docs/14` 形式の名残であり、このリポジトリには存在しない。**削除する**。
   関連する `check_legacy_refs` と `type: :legacy` の分岐も含めて落とす
2. **`spec/` の除外がハードコードされている**（`reject { |f| f.include? "/spec/" }`）。
   これは「テストフィクスチャに意図的な壊れ参照が含まれる」ための除外。
   `test/` `spec/` `tests/` を除外対象にする、あるいは除外パスを定数に切り出すなど、
   撒き先の慣習に依存しない形にすること
3. **`searchable_files` の拡張子リスト**（`.md .rb .py .json .yml .yaml`）は Ruby/Python
   プロジェクト寄り。`.md` は必須として、それ以外は「参照を書きうる設定・スクリプト」として
   妥当な範囲に整理する。ここは判断してよい。判断理由を PR に書くこと
4. **`docs/` ディレクトリ名の前提**。移植元は `docs/` 固定。当面 `docs/` 固定でよいが、
   ハードコードを1箇所（定数）に集約し、孫6 でテンプレート変数化しやすくしておくこと
5. 日本語のメッセージはそのまま維持してよい（この運用の利用者は日本語話者）。
   ただし「`bin/doc-id assign`」のようなパスを含むメッセージは新しい配置に合わせる

### テスト

移植元は RSpec だが、このリポジトリに Ruby プロジェクトは無く、Gemfile も RSpec も無い。
**minitest（stdlib）に書き換える**こと。`ruby tools/doc-id/test/doc_id_test.rb` だけで
走ること（bundler 不要）。

移植元 spec のカバー範囲（`check` の違反検出、`verify` の切れ参照検出、
`assign` のプレースホルダ置換とリポジトリ全体の参照更新、衝突時サフィックス、
コードフェンス内の参照を無視すること）を落とさないこと。
`legacy` 関連のテストは仕様ごと削除するので不要。

### 既存 DOC-ID の移行

1. 孫2 が作成した `DOC-DOCID_PLACEHOLDER_*.md` に `./tools/doc-id/doc-id assign <file>` で採番する
2. 既存の `docs/planning/DOC-001_ai-housekeeping_計画.md` と
   `docs/planning/DOC-002_ai-dotfiles-add-tools_計画.md` を移行する
   - **移植元の `assign` は `DOC-001` 形式を「DOC-ID 未付与」とみなして採番するが、
     旧 ID からの参照更新はしない**（プレースホルダ経由でないため）。
     `DOC-001` `DOC-002` への参照がリポジトリ内にあるか `git grep` で確認し、
     あれば手作業で更新すること
   - タイムスタンプは `git log --follow --diff-filter=A` から自動取得される。
     手で日付を決めない
3. **この計画書（`DOC-2608020558_repo-baseline_計画.md`）は既に正しい形式なので触らない。**
   `assign` は「すでに適切な DOC-ID が付与されています」でスキップするはず。スキップされることを確認する
4. 移行後、`docs/README.md` と `docs/design/README.md` の索引を実際の DOC-ID に更新する
5. `./tools/doc-id/doc-id check` と `./tools/doc-id/doc-id verify` が両方 0 で終わることを確認する

### AGENTS.md の更新

- 「コミット前の必須ステップ」の DOC-ID 関連の記述を、実際のコマンドパス
  （`./tools/doc-id/doc-id assign <file>`）に更新する
- `docs/README.md` の検証コマンド案内も実パスに合わせる

### やらないこと

- pre-commit への組み込み（孫4 の担当）。この孫では手動実行できるところまで
- CI 設定（孫4 の担当）
- テンプレート化（孫6 の担当）。**今は dotfiles の中で動くものを作る。
  ただし上記「汎用化」の観点は今のうちに潰しておく**

### 検証

- `ruby tools/doc-id/test/doc_id_test.rb` が全緑
- `./tools/doc-id/doc-id check` が 0
- `./tools/doc-id/doc-id verify` が 0
- `docs/` 配下に `DOC-001` / `DOC-002` / `DOC-DOCID_PLACEHOLDER` が残っていないこと
- リポジトリ内に `tools/doc-id/` の外へ出る `require` や、dotfiles 固有のパスが無いこと
````

## 孫4用プロンプト:

````
## タスク: pre-commit framework を導入し、品質ゲートを整える

計画書 docs/planning/DOC-2608020558_repo-baseline_計画.md の
「確定事項」「判断3: pre-commit の Ruby は language_version: default」
「全孫共通の注意」を必ず読んでから着手すること。

参考実装として /home/manemone/projects/lora-dataset-forge/main/.githooks/pre-commit を読むこと。
**ただし LDF は自前 `.githooks/` 方式で、こちらは pre-commit framework を採用する。
骨格（lint → doc-id → test の順、どれか1つでも落ちたらコミットを止める）だけ借りる。**

### 作るもの

#### 1. `.pre-commit-config.yaml`（新規）

以下のフックを設定する。

**外部リポジトリのフック**（`pre-commit-hooks` 等の well-known なもの）:
- `trailing-whitespace`, `end-of-file-fixer`, `check-merge-conflict`,
  `check-added-large-files`, `check-yaml`, `check-json`
- `shellcheck`（shellcheck-py または公式の shellcheck-precommit）
- `shfmt`

**`repo: local` のフック**:
- `doc-id-check`: `./tools/doc-id/doc-id check`
- `doc-id-verify`: `./tools/doc-id/doc-id verify`
- `doc-id-test`: `ruby tools/doc-id/test/doc_id_test.rb`（`tools/doc-id/` 配下の変更時のみ）
- `deploy-dry-run`: `./deploy-all.sh --dry-run`（シェルスクリプト変更時のみ）

`repo: local` を使う理由: フック配布元になるにはリポジトリルートに
`.pre-commit-hooks.yaml` が必要で、現時点では独立リポジトリ化しない（計画書の確定事項）。
孫6 のテンプレートでも当面 `repo: local` のままにする。

**Ruby フックの設定**:
```yaml
language: ruby
# language_version は指定しない（= default）
```
バージョンを固定しない理由は計画書の判断3 を読むこと。**`'3.3'` 等を書かないこと。**

**shellcheck / shfmt の設定**:
- `shfmt` のオプションは既存コードの実態に合わせる。既存は2スペースインデント。
  `-i 2 -ci` あたりから始め、`shfmt -d` の差分が過大にならないオプションを選ぶこと
- POSIX sh のファイルと bash のファイルが混在する。shellcheck は shebang から
  方言を判定するので基本は任せてよいが、`shared/helpers.sh` は shebang が `#!/bin/sh` で
  source 専用。誤検出が出たら `.shellcheckrc` またはフックの `args` で対処し、
  **ファイル内に `# shellcheck disable=` を撒かないこと**

#### 2. 既存シェルスクリプトの是正

`pre-commit run --all-files` を通す。対象は
`deploy-all.sh` `uninstall.sh` `shared/helpers.sh` `*/deploy.sh` `bin/ocw` `bin/claude-ds`。

**コミットを分けること**（レビュー可能性のため）:
1. `.pre-commit-config.yaml` と設定ファイルの追加
2. shfmt による機械的な整形（差分が大きければ単独コミット）
3. shellcheck 指摘への対応（1件ずつ意味のある修正。**機械的な握りつぶしをしない**）

shellcheck の指摘のうち「直すと壊れる」ものがあれば、抑制せず PR の
「レビューで見てほしいところ」に列挙して人間の判断を仰ぐこと。

#### 3. デプロイスモークテスト（新規）

孫2 が作った `docs/design/DOC-XXXXXXXXXX_テスト方針.md`（実際の DOC-ID を確認すること）
の「サンドボックス実行」層を実装する。

配置: `tests/deploy_smoke.sh`（ディレクトリ名は既存慣行が無いので判断してよい。
ただし `tools/` は doc-id が使っているので別にすること）

要件:
- `HOME` を `mktemp -d` で作った一時ディレクトリに差し替えて `./deploy-all.sh --force --only <tools>` を実行
- **既定の対象はネットワーク不要なツールのみ**（`tmux,bin,claude`）。
  `zsh` は Antidote を、`nvim` は lazy.nvim を clone するため既定から外す。
  引数で対象を上書きできるようにする
- 検証項目（テスト方針の文書に書かれたチェックリストに従うこと）:
  - 期待した symlink が張られているか（リンク先が正しいか）
  - 既存ファイルがある状態で実行したとき `.backup` に退避されるか
  - 2回実行しても壊れないか（冪等性）
  - `claude/settings.json` が symlink ではなく実ファイルとして生成されるか
  - `./uninstall.sh --force` で元に戻るか
- **終了時に一時ディレクトリを必ず掃除する**（`trap` を使う）
- **実 HOME を絶対に触らないこと。** スクリプト冒頭で `HOME` が一時ディレクトリで
  あることをアサートし、そうでなければ即座に異常終了するガードを入れること。
  これは必須。ここが壊れると人間の環境が壊れる

#### 4. CI（新規）

`.github/workflows/ci.yml`:
- トリガー: `pull_request` と `push`（master のみ）
- ジョブ1: `pre-commit run --all-files`
- ジョブ2: `tests/deploy_smoke.sh`
- ランナーは `ubuntu-latest` を基本とする。macOS 検証は将来の課題として
  ワークフローにコメントで残す（有料枠を消費するため既定では回さない）
- `pre-commit` のキャッシュ（`actions/cache` で `~/.cache/pre-commit`）を入れること

#### 5. `AGENTS.md`（更新）— 「コミット前の必須ステップ」を確定させる

孫1 が「孫4 で更新される」と書き残した節を、実際のコマンドで置き換える:

```
pre-commit run --all-files
tests/deploy_smoke.sh
```

および:
- clone 後に `uv tool install pre-commit && pre-commit install` を一度だけ実行して有効化する手順
- 「AI はこのステップを省略しない。人間の指示でスキップする場合に限り例外とする」
- 「linter 抑制ディレクティブと設定の除外・閾値緩和を AI の判断で追加しない」を
  shellcheck / shfmt に即した具体的な表現に更新する
- 「デプロイの検証は必ずサンドボックスで行い、人間の実 HOME に対して実行しない」

#### 6. ルート `README.md`（更新）

「Quick Start」に開発者向けセットアップを追記する。
`uv tool install pre-commit` → `pre-commit install`。
**開発者に要求するのは uv だけ**であることを明記（計画書の確定事項）。

### 検証

- `pre-commit run --all-files` が全緑
- `tests/deploy_smoke.sh` が緑で、実行後に実 HOME に変化がないこと
  （実行前後で `ls -la ~` の差分を取って確認する）
- `pre-commit install` 後に実際にコミットしてフックが走ること
- CI ワークフローの YAML が `check-yaml` を通ること
````

## 孫5用プロンプト:

````
## タスク: リポジトリ用の AI 設定ファイルを整える

計画書 docs/planning/DOC-2608020558_repo-baseline_計画.md の
「全孫共通の注意」（特に `claude/` と `.claude/` の区別）と
「判断4: .gitignore の /.claude/ を狭める」を必ず読んでから着手すること。

参考実装:
- /home/manemone/projects/lora-dataset-forge/main/.claude/settings.json
- /home/manemone/projects/lora-dataset-forge/main/opencode.json

### 最重要: 触ってはいけないもの

`claude/CLAUDE.md` `claude/settings.json` `claude/skills/` は
**ユーザーのマシンへ配布される成果物**であり、この孫の対象ではない。絶対に触らないこと。

この孫で作るのは、**このリポジトリで作業する AI に効く設定**である。

### 作るもの

#### 1. `.gitignore`（更新）

現在 `/.claude/` がまるごと無視されており、リポジトリ用の `.claude/settings.json` を
追跡できない。以下に狭める:

```
# Repository-scoped AI settings: track settings.json, ignore local overrides
/.claude/settings.local.json
```

`/.claude/` を消して上記に置き換える。他の AI ツールがローカル状態を書き込む可能性も
考慮し、必要なら `/.claude/*.local.json` のような形も検討してよい。判断理由を PR に書くこと。

#### 2. `.claude/settings.json`（新規）

このリポジトリで作業する AI に許可すべき操作を `permissions.allow` に列挙する。

**入れるもの**（このリポジトリで頻出かつ安全な読み取り・検証系）:
- `Bash(pre-commit run:*)`
- `Bash(./tools/doc-id/doc-id check)` / `Bash(./tools/doc-id/doc-id verify)`
- `Bash(ruby tools/doc-id/test/doc_id_test.rb)`
- `Bash(./deploy-all.sh --dry-run:*)`
- `Bash(shellcheck:*)` / `Bash(shfmt:*)`
- `Bash(sh -n:*)` / `Bash(bash -n:*)`
- 実際に何が頻出かは、この孫の作業中に権限プロンプトが出たものを見て判断してよい

**入れてはいけないもの**:
- **マシン固有の絶対パス**（`/home/manemone/...` 等）。他人のマシン・CI で意味を成さない
- `Bash(./deploy-all.sh)` の **`--dry-run` 無し**。実 HOME を破壊する
- `Bash(tests/deploy_smoke.sh)` を入れるかは判断してよいが、入れるなら
  そのスクリプトの HOME ガード（孫4 が実装）が効いていることを確認してから
- `permissions.deny` / `permissions.ask` の全面的な再定義。ユーザーレベルの
  `~/.claude/settings.json`（`claude/` から配布されるもの）と二重管理になる。
  このリポジトリ固有に禁じたいものだけを最小限に書く

#### 3. `opencode.json`（新規）

```json
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": [
    "AGENTS.md",
    "<docs/design 配下の規約文書を実際の DOC-ID 付きパスで列挙>"
  ]
}
```

- `AGENTS.md` を先頭に置く
- 孫2 が作った「プルリクエストの作法」「シェルスクリプトコーディング方針」「テスト方針」を
  実際のファイルパスで列挙する。パスは `git ls-files docs/` で確認すること
- **ここに書くパスは実在すること。** 存在しないパスを書くと opencode が起動時に失敗する

#### 4. `AGENTS.md`（更新）

「3つの領域（混同しないこと）」の表に `.claude/settings.json` の実体が入ったことを反映する。
また「AI 支援ツールの設定」節を追加し、以下を書く:

- ルールの本体は `AGENTS.md` にあり、各 AI 製品の設定はそこへの参照に徹すること
- `CLAUDE.md` = `@AGENTS.md` の1行、`opencode.json` の `instructions` = パスの列挙、
  という対応表
- 新しい AI 製品を使い始めるときも、ルールを別ファイルに書き写さず `AGENTS.md` を指すこと

#### 5. `README.md` / `docs/README.md`（更新）

Directory Structure に `.claude/` と `opencode.json` を追加。
`claude/`（配布物）との違いが README を読むだけで分かるよう1行添えること。

### 検証

- `git status` で `.claude/settings.json` が追跡対象になっていること
- `.claude/settings.local.json` を手で作ってみて、無視されること（確認後に削除する）
- `.claude/settings.json` に絶対パスが含まれていないこと（`grep -n '/home/' .claude/settings.json` が空）
- `opencode.json` に列挙したパスがすべて実在すること
- `pre-commit run --all-files` が全緑（`check-json` を通ること）
````

## 孫6用プロンプト:

````
## タスク: ★ 汎用部分を copier テンプレートとして抽出する

**このスコープの本丸。** 孫1〜5 で dotfiles に作ったものと LDF の2例を突き合わせ、
汎用部分を copier テンプレートに抽出する。

計画書 docs/planning/DOC-2608020558_repo-baseline_計画.md を**全文**読んでから着手すること。
特に以下は必読:
- 「確定事項」と「検討して却下した案」
- 「孫6 で撒かれる成果物の依存条件」— **撒き先の環境に何を要求してよいかは傘レベルで
  決定済み。実装判断で変えないこと**

参考実装（2例目として突き合わせる）: /home/manemone/projects/lora-dataset-forge/main/

### 想定構成（詳細は設計してよい）

```
templates/repo-baseline/
├── copier.yml                 # 質問定義
├── template/
│   ├── AGENTS.md.jinja
│   ├── CLAUDE.md              # "@AGENTS.md" の1行（テンプレート変数なし）
│   ├── opencode.json.jinja
│   ├── .pre-commit-config.yaml.jinja
│   ├── .github/workflows/ci.yml.jinja
│   ├── docs/README.md.jinja
│   ├── docs/design/README.md.jinja
│   ├── docs/design/DOC-DOCID_PLACEHOLDER_プルリクエストの作法.md
│   └── tools/doc-id/          # 孫3 の成果をそのまま
└── README.md                  # 使い方

claude/skills/repo-baseline/SKILL.md   # 適用手順と判断ガイド（AI が読む）
```

### 分業の原則（これがテンプレート設計の中核）

- **決定論的に配れるもの**（規約文書・pre-commit 設定・doc-id ツール・CI）は **copier が撒く**
- **判断が要るもの**（そのリポジトリ固有のルール、除外すべき項目、AGENTS.md の中身）は
  **スキルを読んだ AI が埋める**
- 狙いは **AI に毎回ゼロから考えさせるのをやめて、穴埋めに格下げする**こと

### 汎用/固有の切り分け（出発点。孫1〜5 の実物と突き合わせて更新すること）

| 資産 | 判定 | 備考 |
|---|---|---|
| `AGENTS.md` + `CLAUDE.md`(`@AGENTS.md`) の二層構造 | 完全汎用 | 構造と見出し構成が資産。中身は固有 → `.jinja` で骨組みだけ撒く |
| 無断 merge/pull/push --force/gh pr merge 禁止ルール | 完全汎用 | 文面そのまま |
| PR の作法（説明文構成 + 🤖💬 等のプレフィクス） | 完全汎用 | 文面ほぼそのまま |
| DOC-ID 運用（採番・索引 README・切れ参照検証） | 完全汎用 | ツール実体ごと撒く |
| `docs/` フォルダ規約（design/planning/archive） | 完全汎用 | LDF の `training/` は固有 |
| pre-commit の枠組み | 汎用 | 「lint → doc-id → test」の骨格が汎用。コマンドは固有 → 質問で受け取る |
| `opencode.json` の instructions 配列 | 汎用 | AI 不問対応の一部 |
| linter 抑制を AI が勝手に足すな、のルール | 汎用 | linter 名を質問で受け取り一般化する |
| 傘ブランチ + 孫 + 計画書フォーマット | 完全汎用 | **既に umbrella-orchestrator スキル化済み。再実装しないこと** |
| 長時間コマンドのバックグラウンド実行 + 状態ポーリング規約 | 半汎用 | 該当するリポジトリ限定 → 質問で ON/OFF |
| コーディング方針（Ruby版 / シェル版） | 固有 | 言語ごとに全く別物。テンプレートは「この文書を置く場所と役割」だけ規定し、中身は AI が書く |
| デプロイ・symlink・クロスプラットフォーム | 固有（dotfiles） | 移植対象外 |
| raw/ 保護、canon レシピ、VLM mock 罠 | 固有（LDF） | 移植対象外 |

### copier.yml の質問（設計してよい。以下は出発点）

- `project_name` / `project_description`
- `primary_language`（AGENTS.md と .pre-commit-config.yaml の分岐に使う）
- `lint_cmd` / `test_cmd`（「コミット前の必須ステップ」と pre-commit の `repo: local` に埋める）
- `use_doc_id`（bool, 既定 true）
- `use_ci`（bool, 既定 true。GitHub Actions を生成するか）
- `has_long_running_commands`（bool, 既定 false。バックグラウンド実行規約の節を出すか）
- `default_branch`（PR の作法のブランチ構成に埋める）

**質問は増やしすぎないこと。** 埋められないものは AI が後から埋める前提（分業の原則）。

### DOC-ID プレースホルダとの連携（設計の妙所）

テンプレートが撒く `docs/design/` の文書は、ファイル名を
`DOC-DOCID_PLACEHOLDER_<説明>.md` のままにしておく。撒いた直後に撒き先で
`./tools/doc-id/doc-id assign` を回せば、撒き先の git 履歴に基づいて採番され、
参照も自動更新される。テンプレート側は撒き先の DOC-ID を知る必要がない。

この連携が成立することを実際に確認すること（下記「検証」参照）。

### `claude/skills/repo-baseline/SKILL.md`

**内容**: テンプレートを既存リポジトリへ適用するときの手順と判断ガイド。

- 前提の確認（uv があるか、git リポジトリか、既に AGENTS.md があるか）
- `copier copy` / `copier update` の実行手順
- 質問への答え方の判断ガイド（そのリポジトリを調べて何を答えるか）
- **撒いた後に AI が埋めるべきもの**のチェックリスト:
  - `AGENTS.md` の「概要」「ディレクトリ構成」「最重要ルール（リポジトリ固有分）」
    「コミット前の必須ステップ」「実装時の注意」
  - `opencode.json` の instructions に固有文書を追加
  - コーディング方針文書の中身（言語ごとに書き下ろす）
  - `.claude/settings.json` の permissions
- 既存ファイルとの衝突時の扱い（copier は上書きを聞いてくる。既存の AGENTS.md がある場合の方針）
- **umbrella-orchestrator と pr-review-loop を再実装せず、参照するに留めること。**
  「傘ブランチ運用は umbrella-orchestrator スキルに従う」と書くだけでよい

`claude/deploy.sh` はスキルディレクトリを自動検出して個別 symlink する実装になっているため、
`claude/skills/repo-baseline/` を置くだけでデプロイ対象に入る。deploy.sh の変更は不要なはず。
**実際にそうなっているか確認すること。**

### 自己完結の制約（受け入れ条件・必須）

- `templates/repo-baseline/` は dotfiles の他の部分に**一切依存しない**。
  特に `shared/helpers.sh` を source しない
- dotfiles 固有のパス・前提・命名を埋め込まない
- **受け入れ条件: このディレクトリを別リポジトリへそのまま移動するだけで
  copier テンプレートとして成立すること**
- 理由: 将来 業務リポジトリを含む他所へ持ち込む想定。個人 dotfiles への依存が
  実体として残ってはならない
- ただし現時点では事例が2件しかなく抽象化が未成熟なため、
  **リポジトリ分割は行わず「いつでも切り出せる状態」に留める**

### 検証（受け入れ条件）

1. **新規展開が通ること**
   - 一時ディレクトリに空の git リポジトリを作る
   - `uv tool run copier copy templates/repo-baseline <tmpdir>` で展開できる
   - 展開先で `./tools/doc-id/doc-id assign` がプレースホルダを採番できる
   - 展開先で `pre-commit install && pre-commit run --all-files` が通る
     （撒き先に lint/test コマンドが実在しない場合の挙動も確認し、README に書く）
   - この手順を `templates/repo-baseline/README.md` に手順として書き、
     実際に実行した結果を PR に貼ること

2. **LDF との差分検証（最重要）**
   - テンプレートから展開した結果と LDF の現状を突き合わせる
   - **出てくる差分がすべて「LDF 固有だから当然」と説明できること。**
     説明できない差分が出たら、テンプレート側の切り分けが間違っている
   - 差分の一覧と「なぜ LDF 固有か」の説明を PR の「レビューで見てほしいところ」に書くこと
   - LDF を実際に書き換える必要はない（このリポジトリのスコープ外）

3. **dotfiles 自身との突き合わせ**
   - dotfiles の現状（孫1〜5 の成果）とテンプレート展開結果の差分も同様に説明できること
   - 差分が「dotfiles 固有」で説明できない場合、それは孫1〜5 側の記述が
     汎用なのにテンプレートに入っていないということ。テンプレートに取り込む

4. `pre-commit run --all-files` が dotfiles 側でも全緑
5. `templates/repo-baseline/` 配下に `shared/helpers.sh` への参照や
   `/home/` を含む絶対パスが無いこと

### ルート README.md / docs/README.md の更新

`templates/` の存在と目的（「他リポジトリへ配布するテンプレート。dotfiles 本体とは独立」）を追記する。
````

---

## 全孫共通: 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PR を作成する。**PR の向き先は必ず `ai/repo-baseline` にすること。`master` には絶対に出さない。**
2. `/pr-review-loop` を起動する（PR がない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する

実装が終わったタイミングで止まらず、必ずここまでやりきってください。

### ブランチ作成時の注意（最重要）

作業ブランチは**必ず `ai/repo-baseline` から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:

```bash
git checkout ai/repo-baseline && git pull --rebase origin ai/repo-baseline
git checkout -b <新しいブランチ名>
```

### PR 説明文について

孫2 マージ後は `docs/design/` の「プルリクエストの作法」に従うこと。
孫1・孫2 の時点ではまだ存在しないため、以下の構成で書けばよい:
背景 / このプルリクエストの目的 / 実装内容 / レビューで見てほしいところ / テスト結果 / 今後の予定。
ですます調・平易な言葉で、セッション内の固有名詞や個人的な文脈を入れないこと。
