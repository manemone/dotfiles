---
name: ocw
description: "Gitワークツリー（worktree）の作成・削除・Herdr連携を1コマンドで行う `ocw` CLI。ワークツリー作成、`ocw` コマンド、Herdr連携について尋ねられたら発動。使い方は `ocw help <topic>` を叩いて調べる — bin/ocw の実体や bin/README.md を読みに行かない。"
---

# ocw — Git worktree 管理 CLI

`ocw` は Git worktree の作成・削除を自動化し、オプションで Herdr の
commander/implementer/reviewer マルチペイン環境をセットアップする CLI。
`$HOME/bin/ocw`（このリポジトリの `bin/ocw`）としてインストールされる。

## 使い方は `ocw help` で調べる

**`bin/ocw` の実体（60 KB 超）や `bin/README.md` を読みに行くな。**
どちらも高コストで、しかも `bin/README.md` は `$HOME` に配布されないため、他プロジェクトで
作業しているあなたからはそもそも読めない（`bin/` から `$HOME` に配布されるのは実行ファイル
`ocw` / `claude-ds` / `ocw-meter` のみで、`README.md` は含まれない）。

```bash
ocw help          # コマンド構文（synopsis）+ topic 一覧
ocw help <topic>  # 特定 topic の詳細
ocw help all      # 全 topic をまとめて読む
```

`ocw help` は Git リポジトリの外でも動く。

## topic 一覧

**正確な一覧の一次情報源は `ocw help` が出力する `topics:` 節。** 下表は執筆時点の写しであり、
古くなっていても構わない（`ocw help` を叩けば常に正しい一覧と説明が手に入る）。

| topic | 答える問い |
|---|---|
| `config` | ワークツリーはどこに作られるか。`git config ocw.*` の4キー |
| `naming` | 入力した名前がどうブランチ名・ディレクトリ名になるか |
| `rm` | `ocw rm` は何を消すか。マージ済み判定の意味論 |
| `herdr` | `-H` / `--no-commander` のペイン構成 |
| `meter` | `ocw-meter` 連携（run_id の発行・伝搬） |
| `env` | `ocw` が読む環境変数・設定する環境変数 |

## このスキルが答えないこと

設定キー名・プレースホルダ・解決規則・マージ判定の意味論・環境変数・ペイン構成といった
**挙動の事実は一切書かない。** すべて `ocw help <topic>` が一次情報源であり、ここに答えを
書き写すと `ocw` を直す人がここも直さねばならなくなり、いずれ食い違う。
