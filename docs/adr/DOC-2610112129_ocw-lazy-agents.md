# ADR: `ocw -H` はエージェントを要るペインだけ起動し、残りは `ocw agent` で後から起動する

## ステータス

確定（2026-10-11）

## 1. 背景

herdr のサイドバーの agents の欄は、ワークツリーのグループに合わせた並べ替え・折りたたみが
できず、`ocw -H` が3ペイン（傘）／2ペイン（孫）すべてで claude を起動するため、待機している
だけのエージェントが並んで混雑した。agents の欄に効く設定は `ui.agent_panel_sort` /
`ui.sidebar.agents.rows` / `row_gap` 等だけで、待機中のエージェントを隠す設定は無い
（herdr 0.9.3 の設定リファレンスと 0.9.1〜0.9.3 のリリースノートで確認）。計画書
DOC-2610111927（herdr のサイドバーで傘と孫のワークスペースを自動でまとめる）の背景6・設計1.6 が
出どころ。

## 2. 実測（2026-10-11、herdr 0.9.0、使い捨てのリポと名前付きの別セッション `hwg6x`）

別セッションを `tmux` 上の `herdr --session hwg6x` で立て、`claude` の代わりに
`exec -a claude sleep` で居座る偽物の `claude` を `OCW_*_COMMAND` に絶対パスで渡した
（実物の `claude` を使うと信頼確認の画面が出るため。ペインのシェルは PATH を組み直すので、
PATH の差し替えでは偽物に当たらなかった）。

| 確かめた点 | 結果 |
|---|---|
| `ocw -H` の既定 | 3ペインとも作られ、起動したのは commander だけ（`herdr pane get` の `agent`: commander=`claude`、implementer / reviewer=`None`） |
| `ocw -H --no-commander` | 2ペインとも作られ、起動したのは implementer だけ |
| 後から `ocw agent`（reviewer ペイン、`OCW_ROLE` から役割を引く） | `OCW_ROLE=reviewer`・作成時の `OCW_RUN_ID`・`--name '検証 :: A / レビュー'` で起動し、`agent` が `claude` になった |
| 後から `ocw agent implementer`（`OCW_IMPLEMENTER_COMMAND="FOO=1 <claude> --model x"` で作成） | 上書きが効き（`--model x`）、`--name '… / 実装'` が末尾に付いた |
| agents の欄（`agent_panel_sort = "spaces"`） | 傘A の commander → 傘A の implementer → 傘A の reviewer → 孫B の implementer → 孫B の reviewer の順。A の2つ目・3つ目を B より**後に**起動しても A のまとまりは崩れなかった（計画書 6.2 の実測と一致） |

後始末: ワークスペース・セッションを閉じて削除し、使い捨てのリポと一時ファイルも消した。
残骸は無い。

## 3. 決定

- **ペインは今までどおり全部作る**（label・`OCW_ROLE` / `OCW_RUN_ID` も同じ）。エージェントを
  起動するのは、既定（司令官のワークスペース）では commander、`--no-commander` では
  implementer だけ。残りは使うときに起動する
- **後から起動する手段は `ocw agent [commander|implementer|reviewer]`。** ペインのシェルで
  打つと、そのペインの役割のエージェントにシェルを置き換える（`exec bash -c`）。役割の既定は
  `$OCW_ROLE`（ペインのシェルは作成時に `--env` か起動前の `export` で持っている）。
  呼ぶ側は `herdr pane run <pane> "ocw agent"`
- **起動行は作成時に決めて、ワークツリーの git dir に `ocw-agent-<role>` として書き残す。**
  `ocw agent` はそれを読んで走らせるだけ。会話の名前（`--name '<ラベル> / <役割>'`、claude の
  ときだけ。ADR DOC-2610111939）と `OCW_*_COMMAND` の上書きは作成時に確定した値が入るので、
  後から起動しても即時起動と同じになる。`OCW_RUN_ID` も同じ場所（`ocw-run-id`）が正典なので、
  ペインの環境に無くても補える。書き残す場所は `ocw-run-id` / `ocw-base-ref` と同じ git dir
  （ブランチと一緒に消える・コミットされない）。書けなかったら、後から起動できなくなるので
  作成を失敗させる（`ocw-run-id` と違い fail-open にしない）
- **今までどおり全部起動する手段は足さない。** 既存の利用者を読んだ結果、要らない:
  `task-intake` の軽いハンドオフと `umbrella-handoff` の送信先はそれぞれ implementer・
  commander（起動する側）で、reviewer / implementer が要るのは `pr-review-loop` と
  `/finalize` だけであり、どちらも使う直前に起動できる
- **`pr-review-loop`**: reviewer ペインがシェルだけのとき、`ocw` が PATH にあり起動行が
  残っていれば `ocw agent reviewer` で起動する（会話の名前が付く）。使えなければ今までの
  `herdr agent start` / `pane run` の手順に落ちる。`ocw` の無い環境（他人のリポ・Codex 等）や
  `ocw agent` ができる前に作ったワークスペースがあるため、このフォールバックは残す。
  「起動前のシェルだけのペイン」と「終了したエージェントのペイン」は、どちらも
  `agent_status` が `unknown` でシェルプロンプトだけが見え、取る行動（起動してよい）が同じなので
  区別しない。区別が要るのは「エージェントがいるのに `unknown`」のときだけで、これは既存の
  目視確認の手順が受け持つ
- **`/finalize`（umbrella-orchestrator §3.4 手順2）と §3.5 手順9**: implementer / reviewer に
  エージェントがいなければ `ocw agent` で起動してから送る。`ocw agent` が使えないときは
  `herdr agent start` で起動する
- 既存の外部契約（`workspace:` / `commander:` / `implementer:` / `reviewer:` の出力行、
  `--no-commander`、`OCW_*_COMMAND`、`OCW_ROLE` / `OCW_RUN_ID`）は変えていない。変わったのは
  「ペインに入ったエージェントがいつ起動するか」だけ

## 4. 却下した案

- **`herdr agent start <NAME> --kind claude --pane <pane> -- --name '<ラベル> / <役割>'` を
  各スキルに書く**: `ocw` の内側にある `--name` の組み立て（claude だけに足す判定・クォート）と
  `OCW_*_COMMAND` の上書きを、スキルの側で作り直すことになる。人間の上書きが漏れる／
  ラベルを呼び出し側が知る必要がある。`ocw agent` なら起動行は1か所
- **`ocw agent` が実行時に `OCW_*_COMMAND` を読み直す**: ペインのシェルの環境は herdr
  サーバー由来で、作成時に `ocw` を叩いた人の環境変数ではない。読み直すと上書きが効かない
- **全ペインを今までどおり起動し、待機中を隠すよう herdr に要望する**: 手元で直せない。
  要望は別途出してよい
- **ペインを要るときに初めて作る**: agents の欄で、1つの傘・孫のエージェントが連続しなく
  なる（人間の懸念。計画書 6.1）。ペインを先に作れば連続する（§2）

## 5. 人間に見てほしい点

- 実際の sidebar の agents の欄で、待機のエージェントが減って読みやすくなったか
- 最終 PR の `/finalize` で、implementer / reviewer が自動で起動するか（初回の実運用）
