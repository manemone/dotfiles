# 計画書: tmuxのクリップボードをSSH越しでも動くようにする

傘ブランチ: `tmux-remote-clipboard`
ターゲット: `master`

## 概要

人間がmacOSのローカル端末（Warp）から、Herdr管理下のLinuxリモートマシン（AWS上のsandbox環境等）へ
SSH経由で入ってtmuxセッションを操作している構成で、tmuxのマウスドラッグによるコピーがローカルの
実クリップボードへ反映されない不具合を修正する。原因は `tmux/tmux.conf` のコピー設定が
「tmuxプロセスが実行されているマシン自身」のクリップボード（Linux側の`xclip`/`wl-copy`、
macOS側の`pbcopy`）を直接叩く実装になっており、SSH越しのリモート操作を想定していないこと。
OSC 52エスケープシーケンス経由でローカル（手元の端末）のクリップボードへ転送する方式へ
書き換える。

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。既に参照できない前提で
> 書く）を material として司令官が起草したものである。** ブリーフに書かれていた問題意識・
> 決定事項・実測値・制約は、**すべて本計画書へ転記済み**であり、以降はこの計画書が正典である。

このタスクは「`tmux.conf`の設定変更＋動作確認」という単一の関心事であり、複数のPRに
自然に分割できる規模ではない（実装と検証が強く依存し合っており、動作確認の結果次第で
実装を再調整する必要が生じうる）。孫は1本に収める。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `tmux-remote-clipboard-01-osc52` | tmux.confのコピー設定をOSC 52経由に書き換え、README.mdへ人間向け案内を追記 | ✅ PR #83 マージ済 |

## ワークスペースラベル

- 傘: `dotfiles :: tmuxクリップボード`
- 孫1: `dotfiles :: tmuxクリップボード 孫1 OSC52化`

---

## 背景1: 人間の問題意識（逐語）

> なんかさっきからこの環境でターミナルにでてるテキストのコピーがうまくいかないんだけどなぜだろう。herdr on linux だから？いまこっちの端末は macOS なんだが。

上記の発言を受けて、相談AI（引き継ぎブリーフの起草者）が `tmux/tmux.conf` を調査し、原因を
人間に説明した。人間はその説明を受けて次のように依頼した。

> ~/projects/dotfiles の中身を直すことになるんで、傘にハンドオフしておいて。

## 背景2: 人間が確定させた決定事項（覆さないこと）

- `~/projects/dotfiles`（このdotfilesリポジトリ）の中身を直す方針で確定している。他リポジトリ側の変更ではない。
- 傘ブランチへのハンドオフが明示的に指示されている。
- ターゲットブランチは `master`（このリポジトリのメインブランチ）。
- 人間が使っているローカル端末は **Warp** であることが確定している（人間の発言、逐語）:

  > ちなみに今こっちで使ってる端末は warp

## 背景3: 既存の穴（司令官が実ファイルで裏取り済み）

`tmux/tmux.conf` 68〜71行目（司令官が実ファイルを確認して裏取り済み。以下は現物の引用）:

```
# Copy to system clipboard (macOS: pbcopy, Linux: xclip/wl-copy fallback)
if-shell 'test "$(uname)" = Darwin' \
  'bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "reattach-to-user-namespace pbcopy"' \
  'bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "xclip -in -selection clipboard 2>/dev/null || wl-copy 2>/dev/null || true"'
```

これは「**tmuxプロセスが実行されているマシン自身**のクリップボードにコピーする」設定であり、
次のケースを想定していない:

- 人間はmacOSのターミナル（ローカル端末）から、Herdr管理下のtmuxセッションが動く**Linux側の
  リモートマシン（AWS上のsandbox環境等）**へSSH経由で入って作業している
- この構成では、マウスドラッグによるコピー操作は Linux 側の `xclip`/`wl-copy` を叩くことになり、
  **ローカル(macOS)側の実クリップボードには一切反映されない**
- さらに、Linux側がヘッドレス環境（Xサーバー無し）の場合、`xclip`/`wl-copy` 自体が機能しない
  可能性もある（現に相談時点の作業環境では `xclip` の導入有無すら未確認）

すなわち、現状の `tmux.conf` は「ローカルマシン上で直接tmuxを使う」ケースのみを想定した記述に
なっており、**SSH越しにリモートのtmux(Herdr)を操作するケース**をカバーしていない。

## 背景4: 事前調査結果（司令官が確認済み。実装方針の前提として使ってよい）

ブリーフの指示（「Warp が OSC 52 によるクリップボード連携に対応しているかどうかは
相談AI側では未確認。司令官・孫は実装方針を固める前にこの点を確認すること」）に従い、
司令官がWarp公式ドキュメントを確認した。

**Warpは OSC 52 に対応している。ただし既定では無効。**

- 設定ファイル `settings.toml` の `[terminal]` セクションに `osc52_clipboard_access` という
  設定項目がある
- 既定値は `"deny"`（拒否）
- 選択肢は `"deny"` / `"write_only"`（書き込みのみ許可）/ `"read_write"`（読み書き両方許可）
- 有効化するには次のように設定する:
  ```toml
  [terminal]
  osc52_clipboard_access = "write_only"
  ```
  （tmux→ローカルクリップボードへの書き込みのみが目的なら `write_only` で足りる）

**したがって、`tmux.conf` 側をOSC 52対応に書き換えるだけでは不十分で、人間がWarp側の設定も
変更する必要がある。** これはリポジトリ側の変更ではないため（決定的な制約・スコープ外を参照）、
`tmux/README.md` へ案内を追記するに留める。

参考: [All settings reference - Warp docs](https://docs.warp.dev/terminal/settings/all-settings/)

## 決定的な制約

- AGENTS.md「最重要ルール」: 人間の明示的指示がない限り `git merge` / `git pull` /
  `git reset --hard` / `git push --force` / `gh pr merge` を実行しない。deploy スクリプト
  （`deploy-all.sh` / `uninstall.sh` / `*/deploy.sh`）を実オペレーションで実行しない。
  動作確認は `deploy-all.sh --dry-run` を基本とする。
- AGENTS.md「コミット前の必須ステップ」: `tmux` は「副作用が `$HOME` の外（システムパッケージの
  インストール）や外部ネットワークに及ぶツール」として、サンドボックスでの自動テスト
  （`tests/deploy_smoke.sh`）の対象外に分類されている（詳細は
  `docs/design/DOC-2608020715-b_テスト方針.md` 参照）。したがって `tmux.conf` の修正は、
  サンドボックスでの自動検証だけでは動作保証にならず、**実際にSSH越しの環境で手動確認する**
  ことが実質的な検証手段になる可能性が高い。
- linter抑制ディレクティブや `.pre-commit-config.yaml` の除外・閾値緩和をAIの判断で
  追加しない（AGENTS.md最重要ルール）。`tmux.conf` はシェルスクリプトではないため
  shellcheck/shfmt自体の対象外だが、もし `tmux/deploy.sh`（`#!/bin/sh` の POSIX sh）側にも
  手を入れる場合はこのルールが直接かかる。
- 指示された範囲外の機能を先回りして実装しない（AGENTS.md最重要ルール）。今回のスコープは
  「コピーがSSH越しでも動くようにする」ことであり、それ以外のtmux設定の見直しは含まれない。

## スコープ外

- dotfilesリポジトリの他ツール（`zsh/` `nvim/` `bin/` `claude/` `skills/` 等）の変更は対象外。
- ユーザーのターミナルアプリ（Warp）側の設定変更そのものは、リポジトリ側の変更ではないため、
  リポジトリへの変更は行わない。`tmux/README.md` への人間向け案内の追記に留める（背景4参照）。
- 実際にどのターミナルアプリを使っているかの再確認やOSC 52対応状況の追加調査（Warp以外の
  ターミナルアプリの対応状況等）はスコープ外。人間の端末はWarpであることが確定している
  （背景2）。

## 必須の検証ステップ

AGENTS.md「コミット前の必須ステップ」のうち、この傘に関係するもの:

- `.pre-commit-config.yaml` のフック一式（`pre-commit run --all-files`）
- `tmux/deploy.sh`（シェルスクリプト）を変更した場合は追加で `tests/deploy_smoke.sh`
  （`HOME` をサンドボックスへ差し替えた検証。ただし前述のとおり `tmux` はこのスモークテストの
  対象外ツールに分類されている点に注意。`tmux.conf` の内容そのものの動作確認は別途、
  実環境での手動確認が必要になる可能性が高い）

---

## 孫1用プロンプト:

````markdown
# 傘ブランチ: tmux-remote-clipboard
# 孫ブランチ: tmux-remote-clipboard-01-osc52
# ターゲット: master（傘経由）

## 実装開始前の必須手順

```bash
git checkout tmux-remote-clipboard && git pull --rebase origin tmux-remote-clipboard
git checkout -b tmux-remote-clipboard-01-osc52
```

## やること

計画書 `docs/planning/DOC-*_tmux-remote-clipboard_計画.md`（このリポジトリの
`docs/planning/` 配下、ファイル名の `*` 部分は実際のDOC-IDに置き換わっている）を読み、
以下を実装する。

### 1. `tmux/tmux.conf` のコピー設定をOSC 52経由に書き換える

現状（68〜71行目、計画書の背景3を参照）は、tmuxプロセスが動いているマシン自身の
クリップボード（Linux: `xclip`/`wl-copy`、macOS: `pbcopy`）を直接叩く実装になっており、
SSH越しにリモートのtmux(Herdr)を操作するケースで、コピーした内容がローカル（手元の端末）の
クリップボードへ届かない。

OSC 52エスケープシーケンス経由でローカルのクリップボードへ転送する方式に書き換えること。
設計判断は以下を踏まえること:

- tmux 3.3+ の `set-clipboard` オプション（`set -s set-clipboard on`）を使うと、tmuxの
  内部コピーバッファへの書き込みが自動的にOSC 52として親端末（SSH越しでも、SSHクライアント側が
  対応していれば手元の端末まで）へ転送される。これが素直な実装経路になる可能性が高いが、
  **実機で検証してから確定させること**（当てずっぽうで実装しない）。
- 既存のmacOS/Linux分岐（`if-shell`によるOS判定）を維持するか、OSC 52方式に一本化して
  分岐自体を削除するかは設計判断に委ねる。ただし「ローカル（SSHを介さない）で直接tmuxを使う
  ケースとの後方互換をどう扱うか」（既存の`pbcopy`/`xclip`フォールバックを完全に置き換えるか、
  両対応にするか）は自分で決めて、PR説明に理由を明記すること。
- 計画書の背景4に、人間が使っている端末Warpの OSC 52 対応状況（既定は無効。
  `settings.toml` の `[terminal]` セクションで `osc52_clipboard_access` を
  `"write_only"` または `"read_write"` に変更する必要がある）を書いてある。実装方針を
  決める前に必ず読むこと。

### 2. `tmux/README.md` へ人間向け案内を追記する

- 既存のREADMEは英語で書かれているため、同じスタイル（英語）で追記すること。
- 追記内容: SSH越しにリモートのtmuxを操作する場合、コピーはOSC 52経由でローカルの
  クリップボードへ転送される旨、およびWarpを使っている場合は `settings.toml` で
  `osc52_clipboard_access` を `write_only` または `read_write` に設定する必要がある旨
  （具体的なtoml例を含める）。
- 既存の「Requirements」節・「Install tmux」節（`xclip`/`wl-clipboard`/`reattach-to-user-namespace`
  のインストール案内）の扱いは、1.の実装判断（既存フォールバックを残すかどうか）に合わせて
  更新すること。不要になった記述は削除し、残す記述と矛盾しないようにする。

### 3. `tmux/deploy.sh` は変更が必要な場合のみ触る

コピー設定は `tmux.conf` の記述のみで完結する見込みが高い。`tmux/deploy.sh`
（POSIX sh）を変更する必要が生じた場合のみ、AGENTS.md「クロスプラットフォーム制約」
（POSIX sh、bashism禁止）に従うこと。

## 検証方針

以下の重要な behavior / regression risk が保護されていること。

- `tmux.conf` の文法が壊れていない（`tmux -f tmux/tmux.conf -L <一時ソケット名> new-session -d`
  のような形で、実際にtmuxへ読み込ませて起動エラーが出ないことを確認する。CI/pre-commitには
  tmux文法チェックの仕組みが無いため、自分で確認すること）
- ローカル（SSHを介さない）でtmuxを直接使うケースが、1.の設計判断に従って壊れていない
  （後方互換を維持する設計を選んだ場合はそのケースを、一本化する設計を選んだ場合は
  README側の案内が矛盾しないことを確認する）
- README.mdの追記が、実際にWarpの設定変更をしないと動作しないという実態を正確に反映している

`tmux.conf`はシェルスクリプトではないためshellcheck/shfmtの対象外。`tmux`はAGENTS.md
「テスト方針（DOC-2608020715-b）」上、`tests/deploy_smoke.sh`の対象外ツールに分類されている
ため、このスモークテストによる自動検証は成立しない。**実環境（実際にSSH越しでHerdr上のtmux
セッションを操作できる環境）での手動確認が実質的な検証手段になる。** 自分の実行環境で
SSH越しの検証が可能であれば実施し、PR説明に検証結果（できたか、できなかった場合はその理由）を
明記すること。実施できない場合は、PR説明にその旨と、人間に依頼したい手動確認手順
（「Warp側で`osc52_clipboard_access`を有効化した上で、SSH越しのtmuxでマウスドラッグコピーを
試し、ローカルのクリップボードにペーストできるか確認してください」等）を明記すること。

コミット前に以下を実行すること（AGENTS.md「コミット前の必須ステップ」）:

```bash
pre-commit run --all-files
```

`tmux/deploy.sh` を変更した場合は追加で:

```bash
tests/deploy_smoke.sh
```

linter/shellcheckの指摘を抑制ディレクティブで黙らせない。指摘が設計上不合理だと判断した
場合は、抑制せず違反内容・対象ファイル・判断理由をPR説明に書くこと。

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `tmux-remote-clipboard` にすること。main/masterには絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
**reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず `gh pr view` を
ポーリングしてレビューの有無を確認してください。**

## ブランチ作成時の注意（最重要・再掲）

作業ブランチは**必ず `tmux-remote-clipboard` から切ること**。
main/masterから切るとPRのdiffに傘ブランチ全体が混入してレビュー不能になる。
上の「実装開始前の必須手順」を必ず実行すること。

## PR作成時の注意

PRを作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````
