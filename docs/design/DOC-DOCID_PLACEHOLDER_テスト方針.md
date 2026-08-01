# テスト方針

この文書は「実 `$HOME` を汚さずに dotfiles のデプロイ処理を検証する方法」を定義します。

## 前提となる事実

- すべての deploy スクリプト（`deploy-all.sh` `uninstall.sh` `*/deploy.sh`）は `$HOME` 環境変数を
  参照しており、`~` のハードコードは無い。**ただし `HOME` の差し替えだけでは実 `$HOME` を汚さない
  保証にはならない。** 以下のツールは `$HOME` 以外の環境変数を優先参照するため、これらも一時ディレクトリ
  配下へ差し替えるか unset した状態でサンドボックスを構築する必要がある。
  - `nvim/deploy.sh`: `XDG_CONFIG_HOME`（既定 `$HOME/.config`）/ `XDG_DATA_HOME`（既定 `$HOME/.local/share`）
    / `XDG_CACHE_HOME`（既定 `$HOME/.cache`）
  - `zsh/deploy.sh`: `ANTIDOTE_HOME`（既定 `$HOME/.antidote`）。既存インストールがある場合
    `rm -rf "$ANTIDOTE_HOME"` を実行することがあるため、実環境で `ANTIDOTE_HOME` が export
    されていると読み取りだけでは済まない実害が起きる
- 副作用の性質はツールごとに異なる。サンドボックス実行の対象を決める際は、**ネットワークの要否**と
  **副作用が `$HOME` 配下に閉じるか**の2軸で分類する。
  - `bin/deploy.sh`: 純粋な symlink のみ。ネットワーク不要、副作用は `$HOME` 配下に閉じる
  - `claude/deploy.sh`: symlink ではなく設定ファイルをマージして実ファイルとして生成する。
    `claude/skills/` は個別に symlink を張り、バックアップ先も他ツールと異なる
    （`~/.claude/skills-backup/<名前>.<日時>.<PID>`）。ネットワーク不要、副作用は `$HOME` 配下に閉じる
  - `tmux/deploy.sh`: symlink を張るだけでなく、**tmux が未インストールの場合は
    `sudo apt-get install`（Linux）や `brew install`（macOS）を実行してシステムにパッケージを
    インストールする。** `HOME` を一時ディレクトリに差し替えてもこのインストールはサンドボックスの外
    （実システム）で起きるため、無条件でサンドボックス実行の対象にはできない
  - `zsh/deploy.sh`: Antidote を git clone する（ネットワーク必須）
  - `nvim/deploy.sh`: lazy.nvim を git clone する（ネットワーク必須）

## 検証の4層

| 層 | 手段 | 対象 | 実行タイミング |
|---|---|---|---|
| 構文検査 | `sh -n` / `bash -n` | 全シェルスクリプト | 毎コミット |
| ドライラン | `./deploy-all.sh --dry-run` | 全ツール | 毎コミット |
| サンドボックス実行 | `HOME`（および該当する場合は `XDG_CONFIG_HOME` / `XDG_DATA_HOME` / `XDG_CACHE_HOME` / `ANTIDOTE_HOME`）を一時ディレクトリに差し替えて実際に deploy | 副作用が `$HOME` 配下に閉じるツール（`bin` `claude`） | ローカル（CI導入後は CI でも実行） |
| 実マシン検証 | 実 `$HOME` に対する `--dry-run` → 人間の確認 → 人間による実行 | 全ツール（特に `tmux` のパッケージインストール、`zsh` `nvim` のネットワーク処理） | リリース前に人間が行う |

構文検査とドライランはコストが低く副作用も無いため毎コミットで行う。`shellcheck` / `shfmt` および CI
（`.github/workflows/`）は、このリポジトリにまだ導入されていない（pre-commit framework と CI の導入は
別タスクの担当）。導入されるまでは `AGENTS.md`「コミット前の必須ステップ」のとおり `sh -n` / `bash -n`
とドライランのみを毎コミット必須とし、サンドボックス実行は人間がローカルで随時行う。

サンドボックス実行は、副作用がすべて一時 `$HOME` 配下で完結するツール（`bin` `claude`）に限定する。
`tmux` はシステムへのパッケージインストールを伴い、`zsh` `nvim` はネットワーク経由の git clone を伴うため、
これら3ツールの動作確認は実マシン検証層で人間が行う。この分類は自動化の範囲を広げたくなった場合でも、
「副作用が `$HOME` の外（システムパッケージ）または外部ネットワークに及ぶかどうか」を基準に見直すこと。

実マシンへの適用は、必ず人間が `--dry-run` の出力を確認したうえで人間自身が実行する。

## サンドボックス実行の検証項目

`HOME`（および該当する環境変数）を一時ディレクトリに差し替えて
`./deploy-all.sh --force --only <対象ツール>` を実行し、以下をチェックリストとして確認する。

- [ ] 期待した symlink が張られているか（リンク先のパスが正しいか）
- [ ] 既存ファイルがある状態で実行したとき、上書き前に `.backup` へ退避されるか
- [ ] `claude/skills/` のバックアップは `symlink_backup` を通らず、
      `~/.claude/skills-backup/<名前>.<日時>.<PID>` に退避されるか（他ツールと異なる例外）
- [ ] `--no-backup`（`BACKUP=0`）指定時は `.backup` へ退避されず `rm -f` されるか
- [ ] `--only` フィルタで指定したツールだけがデプロイされ、他のツールは触られないか
- [ ] 同じ内容で2回実行しても壊れないか（冪等性。2回目は「既にリンク済み」として扱われるか）
- [ ] `./uninstall.sh --force` を実行すると symlink が削除され、`.backup` があれば元のファイルに戻るか
- [ ] `claude/settings.json` が symlink ではなく実ファイルとして生成されているか

この文書は「何をどう検証するか」を定義するところまでとし、検証を自動化するスクリプトの実装は別のタスクの
担当とします。

## AI が守るべきこと

**AI はこの検証（特にサンドボックス実行と実マシン検証）を人間の実 `$HOME` に対して実行してはならない。**
サンドボックス実行の前には、`HOME` に加えて対象ツールが参照する `XDG_CONFIG_HOME` / `XDG_DATA_HOME` /
`XDG_CACHE_HOME` / `ANTIDOTE_HOME` が一時ディレクトリを指しているか（または unset されているか）を
必ず確認すること。実マシンへの適用が必要な場面では、`--dry-run` の結果を人間に提示し、
実行そのものは人間に委ねる。
