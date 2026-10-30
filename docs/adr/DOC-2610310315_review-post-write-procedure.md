# ADR: PR への書き込みを「許可ルールに当たる単体コマンド」に固定する

## ステータス

決定（2026-10-31）。傘 `review-post-classifier`（計画書 DOC-2610310309）の孫1 で決めた。

## 1. 背景

2026-10-29 から、`pr-review-loop` のレビュー投稿・返信・スレッド解決が auto mode の分類器に
止められることが増えた。止められた操作はすべて複合コマンド（ヒアドキュメント・`cd …;`・
`--input` に ruby で組んだ JSON を渡す形）で、レビュー依頼が別セッションのメッセージで届いた
セッションに多かった。`skills/pr-review-loop/SKILL.md` には書き込みの手順が無く、AI が毎回その場で
コマンドを組み立てていた。gh の許可ルールはこのマシンの生成物にしか無く、配布物には無かった。

## 2. 決定

1. **書き込みの形を固定する。** `skills/pr-review-loop/SKILL.md` に「GitHub への書き込み手順」の節を
   新設し、レビュー指示テンプレートと Phase 6 から参照させる。本文・JSON はファイル書き込み機能で作り、
   投稿は値をそのまま書いた単体コマンド1つで打つ。形は次の3つ。

   | 用途 | コマンド | 当たる許可ルール |
   |---|---|---|
   | review | `gh api -X POST repos/<owner>/<repo>/pulls/<n>/reviews --input <絶対パス>` | `Bash(gh api -X POST repos/manemone/*/pulls/*/reviews --input *)` |
   | 返信 | `gh api -X POST repos/<owner>/<repo>/pulls/<n>/comments/<id>/replies --input <絶対パス>` | `Bash(gh api -X POST repos/manemone/*/pulls/*/comments/*/replies --input *)` |
   | 会話コメント | `gh pr comment <n> -R <owner>/<repo> --body-file <絶対パス>` | `Bash(gh pr comment * -R manemone/* --body-file *)` |

   review の `event` は `COMMENT` 固定。
2. **許可ルールを配布物 `claude/settings.json` の `permissions.allow` に入れる。** 許可ルールに当たった
   コマンドは分類器を通らないので、依頼の届き方に関係なく投稿が通る。対象は `manemone/*` に絞り、
   `--input` / `--body-file` まで前置に含めて形を固定する。`gh pr review`・`gh pr comment *`
   のような広いルール（`--approve` や他の形まで通る）は足さない。
   ただし許可ルールの `*` は空白や `/` も含む任意の文字列に当たるため、前置が合うだけで形が
   固定されるわけではない（例: 前置の後ろに別の API パスや `-X PUT` を連ねた単体コマンドも
   当たる）。そこで `permissions.ask` に `gh api` のマージ API（`*merge*`）と、
   `-X PUT` / `DELETE` / `PATCH`・`--method` を足し、許可より優先して確認が出るようにした
   （ask は allow に勝つ）。git-guard フック（ADR DOC-2609121719）は変えず、`gh pr merge` の
   判定とは別に、`gh api` 経由のマージも確認に落とす。
   **`event` の値は JSON の中身で、コマンド文字列に現れないため、ルールでは `APPROVE` /
   `REQUEST_CHANGES` を防げない。** 承認 review を出さないことは、手順（`event` は `COMMENT`
   固定）と「レビュワーに代わって承認マーカーを投稿しない」という既存の安全制約が受け持つ。
3. **スレッドの解決は手順から外す。** `resolveReviewThread` は分類器の既定規則で PR 作業の範囲の外と
   名指しされている。絞ったルールで通す案（(b)）は、デプロイ前の実機で分類器を通ることを確かめられない
   ため採らなかった。対応は返信とコミット SHA で示し、レビュー AI はスレッドの解決状態ではなく、
   前回レビュー以降の返信と差分で対応済みかを判断する。SKILL.md の読み方の節（ラウンド2以降の読み方・
   蒸し返し禁止・Phase 5 の指摘収集）をそれに合わせた。
4. **止められたら形を変えて試し直さない。** 回避と見なされうるうえ、分類器は3回連続または累計20回
   止めると auto mode を一時停止する（ADR DOC-2609121719 §3.5）。投稿しようとしたファイルのパスと
   コマンドを控え、人間に伝えて止まる。

## 3. 却下案

- **レビュー依頼の届け方を `herdr agent prompt` に戻し、人間の入力のように見せて分類器を通す案。**
  同意の基準をすり抜ける形であり、分類器の意図に反する。`umbrella-orchestrator` §5 の `SendMessage`
  優先の方針は変えない。
- **広い許可（`Bash(gh api *)`・`Bash(gh pr review *)` など）。** auto mode に入るとき捨てられうるうえ、
  承認の review まで通る（本案の絞ったルールも `event` の値は防げない。§2 のとおり手順が受け持つ）。
- **スレッド解決を絞ったルールで通す案。** 上の決定3のとおり、実機で確かめられなかった。

## 4. 影響と残余

- 許可ルールが効くのは、人間が傘を `master` にマージしてデプロイした後。それまでは、このマシンの
  生成物に残っている既存の gh のルール（`reviews *` など）に当たる。
- このマシンの生成物には、より広い gh の許可ルールが残っている。`claude/deploy.sh` が既存の
  `permissions.allow` を引き継ぐためで、整理するかは人間が決める。
- 他の owner のリポは許可ルールに当たらず、通常の承認の流れになる。
- 配布物にルールを足す前後で、生成のしくみ（DOC-2610150520-b）は変わらない。
