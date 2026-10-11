# ADR: `ocw -H` がペインの claude を herdr のラベルと役割から作った名前で起動する

## ステータス

確定（2026-10-11）

## 1. 背景

Claude アプリ（Remote Control）で見る会話のタイトルが、`<ホスト名>-<ランダム語>` の自動の名前に
なっていて、外から進捗を見るときにどの会話がどの傘・孫か分からなかった。`ocw -H` は素の `claude`
で各ペインを起動し、ワークスペースのラベルは作成後に `herdr workspace rename` で付けていたため、
名前が claude に渡っていなかった。計画書 DOC-2610111927（herdr のサイドバーで傘と孫のワークスペースを
自動でまとめる）の背景5・設計1.5 が出どころ。

## 2. 実測（2026-10-11、claude 2.1.296・herdr 0.9.0、使い捨てのリポと自作の使い捨てワークスペース）

`claude --name "probe :: 実測 孫2 / 実装"`（日本語・空白・`::`・`/` を含む）を `herdr pane run` で起動した。

| 確かめた点 | 結果 |
|---|---|
| (a) `~/.claude/sessions/<pid>.json` | `name` がそのまま入り、`nameSource` は `"user"`（自動の名前は `"derived"`）。`bridgeSessionId` も入り、`remoteControlAtStartup: true` のマシンで Remote Control に接続していた |
| ペインのタイトル | `herdr pane get` の `terminal_title_stripped` が同じ名前になる |
| (b) `SendMessage` | その名前を `to` に指定して届いた（受信側が返信した） |
| (c) 宛先の解決 | `herdr pane get` の `agent_session.value` が `sessions/*.json` の `sessionId` と一致し、`name` を一意に引けた。umbrella-orchestrator §5 の手順は今のまま動く |
| 本物の `ocw -H --label ...` | 3ペインとも `<ラベル> / 司令官`・`/ 実装`・`/ レビュー` で `nameSource: "user"`。`--no-commander` では `/ 実装`・`/ レビュー` の2つ |

Claude アプリの画面上のタイトルそのものは CLI から見えないため未確認（`name` が `user` 由来で
`bridgeSessionId` が付くところまでを確認）。人間に見てほしい点として PR に書く。

## 3. 決定

- **`ocw` に `--label <text>` を足す。** `-H` と併用し、`-H` なしなら `--no-commander` と同じく
  `--label requires -H/--herdr` で die する。`new` の前後どちらの位置でも受ける。指定が無ければ今までどおり
  `<repo_name> :: <slug>`。作成後の `herdr workspace rename` も引き続き動く（後方互換。スキル側の手順の
  書き換えは別の孫）
- **名前の形は `"<ラベル> / <役割>"`。** 役割は `commander`→`司令官`、`implementer`→`実装`、
  `reviewer`→`レビュー`。役割は常に最後の ` / ` の後ろにある（`--label` で渡すラベル自体が ` / ` を含みうるため、名前から役割を取り出すときは最後の ` / ` で切る）。
  同じワークスペースのペイン同士で名前は重ならない
- **`--name` を足すのは、起動コマンドが claude のときだけ。** 先頭の `VAR=値` を読み飛ばした最初の語の
  ディレクトリ部を除いた名前が `claude` のとき（`OCW_*_COMMAND` に `FOO=1 claude --model x` や
  `/usr/bin/claude --permission-mode auto` を入れた形を壊さない）。Codex・OpenCode や
  `env X=1 claude` のようなラッパー、すでに `--name` / `-n` を持つ claude は何も足さない
- 名前は単引用符で自前クォートする（`printf %q` は C ロケールで `$'\ooo'` になり読みにくい）
- いま動いている会話は移行しない。必要なら人間が `/rename` で変える

## 4. 却下した案

- **`--remote-control <名前>` でタイトルだけ付ける**: 実測 (a)〜(c) が `--name` で成り立ったので不要。
  `--name` は宛先名も兼ねるため、1つの名前で足りる
- **コマンドに常に `--name` を足す**: `OCW_*_COMMAND` で claude 以外が指定されると壊れる
- **名前を環境変数で渡す（`OCW_SESSION_NAME` 等）**: claude は環境変数を見ないので意味が無い
- **役割を英語（commander 等）のまま使う**: ペインの名前は英語だが、アプリで見る人間には日本語の
  ほうが読みやすい（ラベルも日本語で付けるため）

## 5. 人間に見てほしい点

- Claude アプリのセッション一覧で、タイトルが `<ラベル> / 司令官` などになっているか
