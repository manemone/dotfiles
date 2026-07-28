# dotfiles リニューアル計画

傘ブランチ: `ai/housekeeping`
ターゲット: `master`

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `ai/ai-repo-housekeeping` | 土台整理: .gitignore更新 + LICENSE追加 + サブモジュール整理 | 🔄 実装中 |
| 2 | `ai/mise-env-pinning` | miseによる環境固定化 + Brewfile + apt-packages | ⬜ 待機中 |
| 3 | `ai/zsh-antidote` | zsh: zplug→Antidote移行 + クロスプラットフォーム + バグ修正 | ⬜ 待機中 |
| 4 | `ai/global-deploy` | 全体デプロイシステム + helpers.sh拡充 | ⬜ 待機中 |
| 5 | `ai/tmux-cross-platform` | tmux: クロスプラットフォーム + 設定モダン化 | ⬜ 待機中 |
| 6 | `ai/nvim-lazy` | nvim: dein.vim→lazy.nvim移行 + built-in優先 + Lua化 | ⬜ 待機中 |
| 7 | `ai/remove-legacy-vim` | 古いVim設定を削除しNeoVimに一本化 | ⬜ 待機中 |
| 8 | `ai/docs-overhaul` | 全README書き直し | ⬜ 待機中 |

## 孫1用プロンプト:

```
## タスク: リポジトリ構造自体を整理する

### 現状
- `.gitignore`: `/home/k.hamada/` の個人パスがコメントに残っている
- ライセンスファイルなし
- `.gitmodules` に死んだ neobundle.vim サブモジュール参照あり

### やること

#### 1. .gitignore を更新
- `/home/k.hamada/.gitignore-boilerplates/` の参照コメント行を削除
- セクションコメントを "Global" → シンプルに
- mise関連のエントリを追加（必要なら）
- `.claude/` を ignore に追加（AIツールの作業ディレクトリ）

#### 2. LICENSE ファイル追加
MITライセンスを追加

#### 3. .gitmodules の neobundle エントリを削除
- neobundle.vim のサブモジュールを完全に除去（gitlink + .gitmodules）
- vim/ ディレクトリを削除（NeoBundleが使えなくなったため孫7から前倒し）
- トップレベルREADMEからVimを削除

### 検証
- `git status` がクリーン
- `git submodule status` が正常終了（exit 0）
- `.gitignore` に個人パス参照がない
- `LICENSE` ファイルが存在する
```

## 孫2用プロンプト:

```
## タスク: miseによる環境固定化を導入する

### 現状
- 前提ソフトウェア（Python, Node, Ruby等）のバージョン指定が一切ない
- macOSのHomebrew前提で、Linux向けのパッケージリストがない
- 各ツールのdeploy.shが個別にソフトウェア存在チェックをしているが非統一

### やること

#### 1. .mise.toml 作成
リポジトリのルートに `.mise.toml` を作成:
```toml
[tools]
python = "3.12"
node = "22"
ruby = "3.3"
rust = "latest"
neovim = "latest"
ripgrep = "latest"
fd = "latest"
lazygit = "latest"
```

#### 2. Brewfile 作成 (macOS用)
リポジトリのルートに `Brewfile` を作成:
```
tap "homebrew/bundle"
brew "mise"
brew "zsh"
brew "tmux"
brew "neovim"
brew "ripgrep"
brew "fd"
brew "lazygit"
brew "git"
brew "curl"
```

#### 3. apt-packages.txt 作成 (Linux/WSL用)
リポジトリのルートに `apt-packages.txt` を作成:
```
zsh
tmux
ripgrep
fd-find
lazygit
git
curl
build-essential
```

#### 4. 各deploy.shにmiseチェック追加
- `ensure_command mise` 的なチェック
- miseがない場合はインストール手順を表示

#### 5. READMEにmiseインストール手順追加
- curl https://mise.run | sh
- または brew install mise / apt install mise

### 重要なファイル（新規作成）
- `.mise.toml`
- `Brewfile`
- `apt-packages.txt`
```

## 孫3用プロンプト:

```
## タスク: zshをzplugからAntidoteに移行し、クロスプラットフォーム対応する

### 現状
- `zsh/.zshrc`: zplugでプラグイン管理。zplugはメンテナンス停止済み
- `zsh/deploy.sh`: zplugを `curl ... | zsh` でインストール（セキュリティアンチパターン）
- `zsh/README.md`: macOSのみの手順、typoあり

### やること

#### 1. .zshrc をAntidote形式に書き換え
- `source ~/.zplug/init.zsh` → `source /path/to/antidote/antidote.zsh` に
- zplugプラグイン宣言 → `$HOME/.zsh_plugins.txt` にbundleファイル形式で列挙:
  ```
  # Theme
  sindresorhus/pure
  # Syntax highlighting
  zsh-users/zsh-syntax-highlighting
  # History search
  zsh-users/zsh-history-substring-search
  # Completion
  zsh-users/zsh-autosuggestions
  zsh-users/zsh-completions
  chrissicool/zsh-256color
  ```
- `zplug check; zplug install; zplug load` → `antidote load`
- zsh-async は削除（zsh本体にマージ済み）
- zplug/zplug の自己管理行も削除

#### 2. バグ修正
- **GCloud SDK**: `if [ ! -f ... ]; then source ...` → `if [ -f ... ]; then source ...` （条件反転バグ）
- GCloud SDKパスを新しいHomebrewに合わせる: `$(brew --prefix google-cloud-sdk)` をベースに、非brew環境のフォールバック追加

#### 3. クロスプラットフォーム対応
- `shared/helpers.sh` に `is_wsl()` 関数追加
- `/usr/local/bin` のハードコード → OS条件分岐:
  - macOS: `/opt/homebrew/bin` (Apple Silicon) または `/usr/local/bin` (Intel)
  - Linux: `/home/linuxbrew/.linuxbrew/bin`
- rbenv, pyenv, n (node), PostgreSQL の設定に存在チェックを追加 → ない場合はスキップ
- WSLでは一部のmacOS専用設定をスキップ

#### 4. deploy.sh 更新
- zplugのcurlパイプインストール削除 → Antidoteのgit cloneインストールに
- `helpers.sh` をsourceして使う
- 各ツール（rbenv, pyenv, n, mise）の存在チェックと警告表示

#### 5. README.md 書き直し
- macOS / Linux / WSL の3パターン手順
- 前提: zsh, git, curl, mise（オプション）
- Antidoteの説明とセットアップ手順

### 重要なファイル
- `zsh/.zshrc` — メイン設定ファイル
- `zsh/deploy.sh` — デプロイスクリプト
- `zsh/README.md` — ドキュメント
- `shared/helpers.sh` — 共有ヘルパー
```

## 孫4用プロンプト:

```
## タスク: リポジトリ全体を統一的にセットアップできる仕組みを作る

### 現状
- 各ツールのdeploy.shを個別に実行する必要がある
- `shared/helpers.sh` は最低限のプラットフォーム判定のみ
- バックアップやドライラン機能がない
- deployスクリプト間でコードの重複が多い

### やること

#### 1. shared/helpers.sh を拡充
以下の関数を追加:
- `log_info()`, `log_warn()`, `log_error()` — カラー付きログ出力
- `is_macos()`, `is_linux()`, `is_wsl()` — プラットフォーム判定（WSL追加）
- `ensure_command <cmd> [hint]` — コマンド存在チェック、なければインストール方法表示
- `symlink_backup <src> <dst>` — 既存ファイルを .backup に退避してからシンボリックリンク
- `get_brew_prefix()` — OSに応じたbrewプレフィックスを返す

#### 2. 各ツールのdeploy.shを helpers.sh を使う形に統一
すべてのdeploy.shが以下をsourceする:
```bash
SCRIPT_DIR=$(cd $(dirname $0); pwd)
source "$SCRIPT_DIR/../shared/helpers.sh"
```

#### 3. トップレベル deploy-all.sh 新規作成
- `--dry-run`: 実際の変更なしで実行計画を表示
- `--only <tools>`: カンマ区切りで特定ツールのみ（例: `--only zsh,nvim`）
- `--backup`: 既存設定を自動バックアップ
- `--force`: 確認なしで実行
- デフォルトでは対話的に進行
- カラーログ出力で進行状況を表示

#### 4. (オプション) uninstall.sh 作成
- 作成したシンボリックリンクを削除
- バックアップから復元（可能なら）

### 重要なファイル
- `shared/helpers.sh` — 拡充
- `deploy-all.sh` — 新規作成（リポジトリルート）
- 各ツールの `deploy.sh` — helpers.shを使う形に統一
```

## 孫5用プロンプト:

```
## タスク: tmux設定をクロスプラットフォーム対応しモダン化する

### 現状
- `tmux/tmux.conf`: macOSハードコード（`/usr/local/bin/zsh`, `reattach-to-user-namespace`, `#(wifi)`, `#(battery --tmux)`）
- `tmux/deploy.sh`: macOSのみbrewインストール
- `tmux/README.md`: Qiitaリンクのみの簡素な内容

### やること

#### 1. tmux.conf の修正
- `default-shell /usr/local/bin/zsh` → `default-shell "#{SHELL}"` で動的解決
- `default-terminal screen-256color` → `default-terminal "tmux-256color"`
- `reattach-to-user-namespace pbcopy` → `if-shell 'test "$(uname)" = Darwin'` でmacOSのみ
- `#(wifi)` と `#(battery --tmux)` → OS判定付きフォールバック（macOSのみ、Linuxでは非表示）
- マウスホイールバインディングをtmux 3.3+構文に更新
- ステータスバー: 使えないコマンドを除去、シンプルに
- `C-q` prefixは維持（既存ユーザーのため）

#### 2. deploy.sh の修正
- `helpers.sh` のプラットフォーム判定を使う
- macOS: `brew install tmux`
- Linux: `sudo apt install -y tmux` または brew
- WSL向けヒント表示

#### 3. README.md 書き直し
- 前提: tmux 3.3+
- macOS / Linux / WSL のインストール手順
- キーバインド一覧表

### 重要なファイル
- `tmux/tmux.conf` — メイン設定
- `tmux/deploy.sh` — デプロイスクリプト
- `tmux/README.md` — ドキュメント
```

## 孫6用プロンプト:

```
## タスク: NeoVimをdein.vimからlazy.nvimに移行し、NeoVim組み込み機能を最大限活用する

### 現状
- `nvim/init.vim`: Vimscriptでdein.vim管理。Python 2参照あり
- `nvim/dein.toml`: プラグインリスト。vim-coffee-script等死んだプラグイン多数
- `nvim/dein_lazy.toml`: coc.nvim + neosnippetベース。設定が古い
- `nvim/deploy.sh`: deinインストール + Python 2.7/3.8仮想環境構築

### 設計方針（最重要）
- **NeoVim built-in 優先**: 組み込みで十分な機能はプラグインを入れない
- **mini.nvim 活用**: 小さな機能はmini.nvimファミリーで（軽量・lazy不要）
- **lazy.nvimは糊役**: 遅延読み込みとロックファイルだけに使う

### NeoVim組み込みで代替するもの（プラグイン不要）
| 旧プラグイン | 組み込み代替 |
|---|---|
| nerdcommenter | `vim.comment` (NeoVim 0.10+ built-in commenting) |
| lexima.vim (auto-pairs) | シンプルなLuaキーマッピングで対応 |
| vim-easy-align | `=`, `gw`, `gq` built-in + 必要なら mini.align |
| coc.nvim | nvim-lspconfig + mason.nvim（built-in LSP） |
| neosnippet | LuaSnip |
| vim-surround | mini.surround |

### プラグイン構成（必要最小限）
- lazy.nvim（プラグイン管理）
- telescope.nvim（ファジーファインダー）
- nvim-treesitter + 主要言語パーサー
- nvim-lspconfig + mason.nvim + mason-lspconfig
- LuaSnip + スニペットコレクション
- gitsigns.nvim（Gitガター）
- lualine.nvim（ステータスライン）
- mini.surround（括弧操作）
- tokyonight.nvim（カラースキーム）
- which-key.nvim（キーマップ表示）

### 削除するプラグインと理由
- vim-coffee-script → CoffeeScriptは死んだ
- vim-vue → Treesitter + Volar LSPで代替
- vim-rails → 汎用dotfilesに不要
- denite.nvim → telescope.nvimに
- vim-airline → lualine.nvimに
- vim-easy-align → built-inに
- nerdcommenter → built-in vim.commentに
- lexima.vim → Lua keymapsに
- molokai → tokyonightに
- vim-expand-region → treesitter textobjectsに
- vim-gitgutter → gitsigns.nvimに
- coc.nvim + coc-tabnine → nvim-lsp + masonに
- neosnippet + neosnippet-snippets + context_filetype.vim → LuaSnipに

### やること
1. **init.lua 新規作成**
   - lazy.nvimのブートストラップ（自身を自動インストール）
   - 設定を分割:
     - `lua/config/options.lua` — vim.opt設定
     - `lua/config/keymaps.lua` — キーマッピング（既存を維持しつつLua化）
     - `lua/config/autocmds.lua` — 自動コマンド
   - プラグイン定義を `lua/plugins/` に分割

2. **既存設定のLua移植**
   - init.vimの全設定をLuaに翻訳
   - 既存キーマップを維持（Spaceリーダーキー、バッファ操作、クリップボード等）
   - dein.toml + dein_lazy.toml → lua/plugins/*.lua

3. **Pythonプロバイダー刷新**
   - Python 2参照を完全削除
   - python3_host_progを自動検出またはmise管理に

4. **deploy.sh更新**
   - dein.vimインストール削除
   - ~/.cache/deinクリーンアップ処理追加
   - 前提チェック: ripgrep, fd, node

5. **README.md書き直し**
   - 前提: mise, Node.js LTS, ripgrep, fd
   - LSPセットアップ手順（:Masonで追加）
   - built-in優先の設計思想を明記
```

## 孫7用プロンプト:

```
## タスク: 古いVim設定を削除しNeoVimに一本化する

### 現状
- `vim/` ディレクトリ: 孫1で削除済み
- deploy.bat 削除済み
- `.gitmodules` の neobundle サブモジュールは孫1で除去済み

### やること

1. **vim/ 削除の後始末**
   - 孫1で既に `git rm -r vim/` 済みのため、このステップはスキップ

2. **サブモジュール除去の後始末**
   - 孫1で `git rm --cached` + `.gitmodules` 削除済みのため、このステップはスキップ

3. **.gitignore 更新**
   - 孫1で `.gitignore` の vim セクションは維持（swapファイル等の除外パターンは引き続き有効）
   - `!.vim/bundle/neobundle.vim` の行は孫1で削除済み（vim/ごと消えたため）

4. **トップレベルREADMEの更新**
   - 孫1で Supported tools から Vim を削除済み
   - （READMEの完全リニューアルは孫8でやる）

### 検証
- `git status` で vim/ が存在しないこと
- `.gitmodules` が存在しないこと
- 作業ツリーがクリーンであること
```

## 孫8用プロンプト:

```
## タスク: READMEとドキュメントを全面的に書き直す

### 現状
- トップレベルREADME: typoあり（"Z Sehll"）、tmux未掲載、前提条件なし
- 各ツールREADME: 古い手順、macOS-only、不足前提条件
- ドキュメントフォーマットがバラバラ

### やること

#### 1. トップレベル README.md を全面リニューアル
以下の構成で:
```
# dotfiles
Easily deployable, cross-platform dotfiles managed with mise.

## Supported tools
- Zsh (with Antidote plugin manager)
- NeoVim (with lazy.nvim)
- tmux

## Supported platforms
- macOS (Apple Silicon / Intel)
- Linux (Ubuntu/Debian, WSL2)

## Prerequisites
- git, curl
- mise (https://mise.jdx.dev)

## Quick Start
git clone https://github.com/manemone/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./deploy-all.sh

## Directory structure
...
```

#### 2. 各ツール README.md を統一フォーマットに
全READMEを以下の構成に:
1. Requirements（前提ソフトウェアと推奨バージョン）
2. Quick Start（最小手順）
3. What's included（含まれる設定の概要）
4. Customization（カスタマイズ方法）
5. Troubleshooting（よくある問題と解決策）

#### 3. macOS / Linux / WSL の全パターン手順を記載
各ツールのREADMEにOS別のセットアップコマンドを明記

#### 4. 古い記述の削除
- Qiitaリンク（情報が古い）
- 死んだツールへの参照
- 間違ったコマンド（`source ./deploy.sh` 等）
```
