# 計画書: herdr 0.9.0 の CLI へスキルを追随させる

傘ブランチ: `herdr-09-cli-migration`
ターゲット: `master`

## 概要

herdr を使う配布スキル（`skills/`）に、herdr 0.9.0 で消えた旧コマンドの使い方が残っている。
特に `herdr wait agent-status` はトップレベルの `wait` サブコマンドごと消えており、
`umbrella-orchestrator` と `pr-review-loop` の待機手順が**そのままでは動かない**。

この傘では次の2つを行う。

- **壊れた旧コマンドの置き換え**（`herdr wait agent-status` → `herdr agent wait`）
- **新しいコマンドで便利・効率的になる箇所の検討と反映**（`herdr agent prompt` による送信、
  `herdr agent start` によるレビュワー再起動、`$HERDR_WORKSPACE_ID` による自分の
  workspace の特定 など）
- **孫の完了を司令官へ通知する仕組みの追加**（司令官セッションで人間から追加で依頼された。
  背景1・設計1.5）

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。転記後に削除済みで
> 参照できない前提で書く）を material として司令官が起草したものである。** ブリーフに
> 書かれていた問題意識・決定事項・実測値・制約・未決事項は本計画書へ転記済みであり、
> 以降はこの計画書が正典である。ブリーフが未決のまま残していた判断（送信の主経路など）は、
> 司令官が実測したうえで「設計1」で確定させた。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `herdr09-01-agent-wait` | `herdr wait agent-status` → `herdr agent wait` の置き換え、done/idle を両方見る回避ループの削除、`agent_status=None` の記述を `unknown` へ直す | 🔄 実装中 |
| 2 | `herdr09-02-agent-prompt` | AI間送信のフォールバックを `herdr pane run` + `send-keys Enter` から `herdr agent prompt` へ移行し、ADR DOC-2609072215 を更新する | ⬜ 待機中 |
| 3 | `herdr09-03-done-notify` | 孫が傘へのマージを終えたら、セッション間の送信で司令官へ通知する（巡回は保険として残す） | ⬜ 待機中 |
| 4 | `herdr09-04-agent-start` | 終了したレビュワーの再起動を `herdr agent start` へ移行し、自分の workspace の特定を `$HERDR_WORKSPACE_ID` へ置き換える | ⬜ 待機中 |

依存: 孫1 → 孫2 → 孫3 → 孫4 の順に**直列**で進める。4本とも `skills/pr-review-loop/SKILL.md` と
`skills/umbrella-orchestrator/SKILL.md` の近い箇所を触るため、並列にするとコンフリクトする。
孫1 は壊れている箇所の修正なので最優先にする。孫3 は孫2 で決まる送信のフォールバック
（`herdr agent prompt`）を使うので孫2 の後に置く。

## ワークスペースラベル

- 傘: `dotfiles :: herdr0.9追随`
- 孫1: `dotfiles :: herdr0.9追随 孫1 agent wait移行`
- 孫2: `dotfiles :: herdr0.9追随 孫2 agent prompt移行`
- 孫3: `dotfiles :: herdr0.9追随 孫3 完了通知`
- 孫4: `dotfiles :: herdr0.9追随 孫4 agent start移行`

---

## 背景1: 問題意識（人間の発言の逐語）

> herdr を使うスキルで、どうも古い herdr のコマンドの使い方になってる部分がありそう。その辺を更新しておいてくれない。

> 新しいコマンドで今までのやり方より便利あるいは効率的にできる場合や、新しい使い方ができそうなところも検討しておいてよ

> いや、傘を切ってくれ。ハンドオフして。

相談していた AI は「Markdown だけの変更なので傘は大げさ。壊れている箇所を先に単独の PR で
直す」と提案したが、人間は傘を選んだ。

計画書の起草中に、人間から司令官セッションへ次の依頼が追加された（逐語）:

> あと、umbrella-orchestrator で、孫が実装完了したとき、巡回で司令官が気づくまでにラグがあってもったいないから、終わったらセッション間会話使って、孫側から司令官に通知するようにしてよ。孫が止まることもあるから巡回は今まで通りやってほしいけど。

## 背景2: 人間が確定させた決定事項（覆さないこと）

- 傘ブランチ方式で進める（`herdr-09-cli-migration`、ターゲット `master`）
- 対象は「壊れた旧コマンドの更新」に加え、「新コマンドで便利・効率的になる箇所や新しい使い方」の
  検討と反映まで含む
- 孫が終わったら、孫の側からセッション間の送信で司令官へ通知する。**巡回（cron）は今までどおり
  続ける**（孫が止まることがあるため）

## 背景3: 既存の穴（2026-10-11、herdr 0.9.0 で実測）

環境: `herdr 0.9.0`（client/server とも。`herdr status server` で `private_protocol: 22`）。

### 3.1 壊れている箇所（旧コマンドが消えた）

- **`herdr wait agent-status <id> --status X` は、トップレベルの `wait` サブコマンドごと消えた**
  （`herdr wait --help` → unknown command）。後継は次のとおり（`herdr agent` で出る一覧より）:

  ```
  herdr agent wait <target> [--until STATUS]... [--timeout MS]
  ```

  STATUS は `idle` / `working` / `blocked` / `done` / `unknown`。`--until` を省略すると
  `idle` / `done` / `blocked` のどれかで成立する。`--timeout` を省略すると無期限に待つ。
- 該当箇所（`git grep -n -e "herdr wait" -e "wait agent-status"`。2026-10-11 時点の行番号）:
  - `skills/pr-review-loop/SKILL.md`: 711, 732, 797, 812, 823, 829, 831 行付近
  - `skills/umbrella-orchestrator/SKILL.md`: 1003, 1029, 1036, 1059 行付近
- **この傘を回している司令官（`umbrella-orchestrator`）と孫（`pr-review-loop`）が使うスキル自体が、
  この壊れたコマンドを含んでいる。** しかも `~/.claude/skills/` 配下は配布済みの世代を指すため、
  この傘の変更は master マージと人間による deploy まで反映されない。**傘を回している間は、
  スキル本文の `herdr wait agent-status X --status S` を `herdr agent wait X --until S` へ
  読み替えて使う**（孫用プロンプトにも書いてある）。

### 3.2 新コマンドで改善できそうな箇所

1. **`agent wait` の `--until` は複数回指定できる。** 現状は「`--status` が1つしか取れないので、
   短く区切って done と idle の両方を見る」ループを書いている（`pr-review-loop` Phase 3a、
   `umbrella-orchestrator` §5「状態確認」）。`--until` なしの
   `herdr agent wait <id> --timeout 600000` の1行で置き換えられる。
2. **`herdr agent prompt <target> <text> [--wait] [--until STATUS]... [--timeout MS]` が新設された。**
   公式スキル（`herdr --skill` の出力）の記述:
   - 「`agent prompt` honors the pane's live bracketed-paste mode and sends text followed by
     encoded Enter as one ordered submission.」（貼り付けモードを守り、本文と Enter を
     順序どおり1回の送信として送る）
   - 送信先が承認待ちや質問ダイアログ（`blocked`）なら、何も送らず `agent_blocked` で拒否する
   - `--wait` 付きで非 working 状態から送ると、5秒以内に `working` か `blocked` が観測され
     なければ `agent_prompt_stalled` を返す
   - 「A timeout or stalled response does not prove the prompt was never delivered; do not
     blindly submit it again.」（タイムアウトや stalled は未達の証明にならない。やみくもに
     再送しない）
   - 現行スキルのフォールバック送信（`herdr pane run` → `agent_status` 確認 →
     `send-keys Enter` → 再確認、再送禁止）が対策している「Enter が飛ばない・長文が途中で
     止まる・再送で2重に積まれる」に直接効く仕様である
   - 公式スキルは `pane run` を「ordinary command」（シェルで普通のコマンドを走らせる）用、
     エージェントへの指示は `agent prompt` と使い分けている
   - 該当: `umbrella-orchestrator` §3.2 注意点3「herdr pane run の最重要注意点」・
     §5「AI間送信手順（二段構え）」のフォールバック・「レビュー待ちデッドロック」の復帰指示・
     §3.4 `/finalize` の手順・§3.5 cron 本文の手順8/9、`pr-review-loop` Phase 2 Step 3/4・
     Phase 3「作業開始を待つ」・Phase 6 Step 4/5、`umbrella-handoff` §6
3. **`herdr agent start <name> --kind KIND --pane ID [--timeout MS] [-- <agent-args...>]` が新設された。**
   エージェントが検出され入力可能になってから戻る（既定のタイムアウトは30秒）。起動時に
   `blocked` なら `agent_not_ready` ですぐ戻る。`--pane` には「シェルが前面にいてプロンプトで
   待っている」ペインが要る。`pr-review-loop` Phase 2 Step 2 のレビュワー再起動
   （`herdr pane run "$REVIEWER_PANE" "$REVIEWER_CMD"` + 起動待ち）を置き換えられる。
   ただし `.claude/pr-review.yml` の `reviewer_cmd` は自由形式のコマンド文字列なので、
   `--kind` と `--` 以降の引数への写像を設計する必要がある。KIND の一覧は `herdr agent` の
   出力に載っている（`claude` / `codex` / `opencode` などを含む）。
4. **`agent_status` が `None` になることは今はない。** エージェントのいないペインは
   `"unknown"` を返す（シェルだけのペインはすべて `agent_status: "unknown"` だった）。
   `pr-review-loop` Phase 2 Step 2 の「`unknown` / `None` または空」「None時の確認手順」の
   記述が古い。診断用に `herdr agent explain <target>` もある（検出ルールと根拠を表示する）。
5. ほかに出てきたコマンド: `herdr agent read/get/send-keys/list`（pane 版のエージェント向け版）、
   `herdr pane wait-output --match/--regex`、`herdr pane current --current`、`herdr pane layout`。
   使いどころの判断は「設計1」に書いた。

### 3.3 互換が保たれていると確認済みのもの

- `herdr pane get/list` の JSON の形（`result.pane.agent`、`agent_status`、
  `agent_session.value`、`label`、`cwd`、`workspace_id`）は変わっていない。python で値を
  取り出している既存のスニペットはそのまま動く
- `herdr pane run/read/send-keys/split/rename`、`herdr workspace rename/list/get`、
  `herdr worktree list --cwd`、`herdr integration status`、`herdr status server` は存続
- `herdr pane read <id> --source detection` は、0.9.0 の `herdr pane` の一覧には `detection`
  が載っていない（`herdr agent read` には載っている）が、実測では動いた（司令官が 2026-10-11 に
  確認）。エージェントが終了したペインでは `agent read` が使えない（target は「現在
  エージェントがいるペイン」に限られる）ため、**`pane read --source detection` は置き換えない**
- 公式スキルは `pane run` を「atomically sends command text and Enter」と説明している。
  スキル側の「Enter が送られないことがある」という実測は 0.9.0 より前のもので、食い違っている

### 3.4 司令官の追加実測（2026-10-11）

- **`herdr agent wait <target>`（`--until` なし）は、対象がすでに `idle` / `done` なら即座に
  戻る**（`idle` の implementer ペインに対して実行し、0.002秒で終了コード0）。つまり
  **送信直後に `--until` なしで待つと、相手がまだ動き出す前の `idle` で成立してしまう**。
  完了待ちの前には「動き出したこと」（`working` の観測、または `agent prompt --wait` の
  活動ゲート）を確かめる必要がある
- `herdr agent wait <target> --until working --timeout 2000` は、`idle` の相手に対しては
  2秒後に `{"error":{"code":"timeout",...}}` を返して終了コード1で終わる（エラーは JSON）
- `herdr agent wait --help` などのサブコマンドに `--help` を付けても、トップレベルの
  ヘルプが出るだけで役に立たない。**構文の確認は `herdr agent` / `herdr pane` のように
  グループ名だけを叩いて一覧を出す**（引数なしの `herdr agent wait` も usage 行だけを
  出して終わる）。公式スキルの注意どおり、**作成・変更系のコマンドを引数なしで叩いて
  構文を探らない**（`herdr workspace create` などは既定値で実行されてしまう）
- herdr は各ペインへ呼び出し元の文脈を環境変数で渡している:
  `$HERDR_WORKSPACE_ID`（例 `wE5`）、`$HERDR_TAB_ID`（例 `wE5:t1`）、`$HERDR_PANE_ID`
  （例 `wE5:p1`）。`herdr pane current --current` でも自分のペインの JSON が取れる。
  `pr-review-loop` Phase 0 はすでに `$HERDR_WORKSPACE_ID` を使っている
- エージェント名（`agent start` の NAME、`agent rename`）は
  「Names must match `[a-z][a-z0-9_-]{0,31}` and be unique among live agents」
  （サーバー全体で一意）。エージェントが終了すると名前は外れる

### 3.5 試して不採用とした案（ブリーフより）

- **エージェント名（`agent start` の NAME / `agent rename`）を `reviewer` などの役割の識別に
  使う案**: 名前はサーバー全体で一意でなければならず、ワークスペースごとに reviewer がいる
  今の構成では衝突する。役割の識別はペインの `label` 方式を続ける

---

## 設計1: 司令官が確定させた判断（孫はこれに従う）

### 1.1 孫の分割と順序

ブリーフの叩き台（3本）を基本的にそのまま採用し、次の点だけ動かした。

- **`agent_status=None` → `unknown` の修正（3.2-4）は孫1に入れる。** 叩き台では孫3だったが、
  「None時の確認手順」の節自体が `herdr wait agent-status ... --status idle` を含んでおり、
  孫1 が必ず触る箇所だから
- **`$HERDR_WORKSPACE_ID` による自分の workspace の特定は孫4に入れる**（ブリーフ外の追加。
  3.4 の実測で見つけた改善）
- **人間が追加で依頼した完了通知（設計1.5）を孫3として足し、叩き台の孫3（`agent start`）を
  孫4へ送る。** 完了通知は孫2 で決まる送信手順を使うので孫2 の後に置き、待ち時間の短縮という
  効果が大きいので `agent start` より先にする

### 1.2 待機（孫1）

- 完了待ちは `herdr agent wait <target> --timeout <MS>`（`--until` なし）の1行にする。
  done/idle を両方見るためのループは削除する
- 「作業開始を待つ」は `herdr agent wait <target> --until working --timeout <MS>`
- 特定の状態だけを待つ場面は `--until` を明示する（複数回指定できる）
- **3.4 の「すでに `idle` / `done` なら即座に戻る」を本文に書く。** 送信前の状態のまま
  完了待ちに入って空振りしないよう、完了待ちの前に作業開始（`working`）を確かめる手順は残す
- `herdr wait` の挙動を前提に書かれた説明文（「`--status` を1つしか取れない」等）も直す。
  `idle` と `done` の意味（同じ「完了」を「見られたか」で呼び分けている）の説明は今も正しい
  ので残す
- `agent wait` の target は「エージェントがいるペイン」でなければならない。エージェントが
  終了していると使えない点を、`unknown` の扱いと合わせて書く

### 1.3 送信経路（孫2）— ブリーフの未決事項

**判断: `SendMessage` を優先する二段構えは維持し、フォールバックを `herdr pane run` +
`send-keys Enter` から `herdr agent prompt` に置き換える。** `agent prompt` を主経路へ
昇格させることはこの傘ではしない。

理由:

- `agent prompt` は herdr 公式の「エージェントへ指示する」経路で、フォールバックが抱えていた
  3つの事故（Enter が飛ばない・長文が途中で止まる・再送で2重に積まれる）に仕様として
  手当てがある。`blocked` の相手には送らずに拒否するので、承認ダイアログに本文を流し込む
  事故も防げる。フォールバックに使わない理由がない
- 一方、`SendMessage` は数多くの傘で実績があり、相手のターミナル入力欄に書き込まないので、
  人間がそのペインで手入力していても衝突しない。`agent prompt` はまだ実測していない。
  実績のある主経路を、未実測の経路と入れ替える理由がない
- 主経路の入れ替えを検討する価値はある（`~/.claude/sessions/*.json` という Claude Code の
  内部実装に頼る宛先解決をやめられる。どの AI からでも同じ手順になる）。ADR には
  「検討したが今回は見送った案」として、見送った理由と、再検討の条件（例: `agent prompt` の
  実測が溜まった、`~/.claude/sessions/` の形式が変わった）を記録する

フォールバックの手順の要点（孫2が正典 `umbrella-orchestrator` §5 に書く）:

- `herdr agent prompt <pane-id> "<本文>" --wait --timeout <MS>` で送る。
  公式スキルどおり `--wait` には `--until` を重ねない
- 成功すれば、送信と「動き出し」の確認が1回で済む。`send-keys Enter` の手順は不要になる
- `agent_blocked` → 相手の画面を `herdr agent read` で読み、判断が要るなら人間に伝える
- `agent_prompt_stalled` / `timeout` → **届いていないとは限らない。再送しない。**
  `herdr agent get` / `herdr agent read` で状態と画面を確かめてから次の手を決める
- **長い待機に `--wait` を使わない。** 実装AIへの指示は何十分も続くので、`--wait` に
  長いタイムアウトを付けて司令官をブロックしない。動き出しの確認だけなら短めのタイムアウトで
  よい（`--wait` は「動き出し」を観測したあと完了まで待ち続けるため、タイムアウト到達で
  `timeout` が返る。それを失敗と取り違えない書き方にする。具体的な形は孫2が実測で決める）
- 「本文に計画書のパスとセクション名だけを書く」「『〜とだけ返事して』のようなメタ指示を
  付けない」という方針は変えない

`herdr pane run` はシェルでコマンドを走らせる用途（レビュワーの再起動のフォールバックなど）
にだけ残る。§3.2 注意点3「herdr pane run の最重要注意点」は、エージェントへの送信の話としては
役目を終えるので、歴史的な実測を ADR 側へ寄せ、スキル本文は新しい手順を中心に書き直す。

**孫2は移行の前に実測する。** 少なくとも次を実際に送って確かめ、ADR に記録する:

- `idle` の Claude Code ペインに、改行を含む日本語の数百文字を `agent prompt --wait` で送る
- `done` のペイン（前回の結果が未読のまま）に送る
- `working` のペインに送る（キューに積まれるか、`--wait` が何を返すか）

**実測で `agent prompt` が届かない・2重に積まれるなどの事象が出たら、移行せずに作業を止め、
実装AIは PR の説明とレビューでそれを報告する。**（判断を変えるのは司令官と人間）

### 1.4 レビュワー再起動（孫4）

- 終了したレビュワー（ペインがシェルプロンプトに戻っている）の再起動を `herdr agent start`
  へ移す。`agent start` は「シェルが前面でプロンプト待ち」のペインを要求し、検出されて
  入力可能になってから戻るので、起動待ちの手順が要らなくなる
- **`reviewer_cmd`（自由形式）から `--kind` と引数への写像**: 先頭の語が `herdr agent` の
  KIND 一覧に含まれていれば、それを `--kind` に、残りを `--` の後ろへ渡す。先頭が環境変数の
  代入やラッパー（`env ...` など）で KIND が決まらないときは、従来どおり `herdr pane run` で
  起動するフォールバックに落ちる。`reviewer_cmd` が無ければ Phase 0 で記録した
  `$REVIEWER_AGENT` を KIND に使う（引数なし）。どちらも無ければ従来どおり推測せずに止まる。
  `.claude/pr-review.yml` に新しいキーは足さない
- **NAME はサーバー全体で一意な名前を機械的に作る**（例: ペインIDを小文字化し `:` を `-` に
  した `rv-we5-p3`）。役割の識別は `label` のまま（3.5）。名前の衝突などで `agent start` が
  失敗したら `pane run` のフォールバックへ落ちる。`--timeout` の既定（30秒）で足りるかは
  実測で決める
- `pane run` で起動した場合、エージェントが検出されるまでは `agent wait` の target に
  ならない。検出を待つ手順（`herdr pane get` の `agent` が入るまでの確認など）は孫4が決める
- **自分の workspace の特定**（`umbrella-orchestrator` §5「自分のworkspaceの見つけ方」・
  §3.4 手順1・§3.5 cron 本文の手順9）を `$HERDR_WORKSPACE_ID` に置き換える。
  空のとき（herdr の外など）は今の `cwd` 突き合わせへ落ちる、という形で今の方式を
  フォールバックに残す。ペインを別の workspace へ移すと ID が変わる（公式スキル）点を
  注意書きに入れる
- `umbrella-handoff` の司令官 workspace 特定にも同じ方式が使われていれば揃える

### 1.5 孫から司令官への完了通知（孫3）

今は司令官が約10分おきの巡回でしか孫のマージに気づかないため、マージから次の孫の spawn まで
最大10分ほど空く。孫の側から通知して、この待ち時間をなくす。

- **いつ通知するか**: 孫の実装AIが、孫→傘の PR のマージを終えた直後（`/pr-review-loop` が
  マージまで実行した後）。通知は1回だけ送る
- **誰に送るか**: 司令官のペイン。司令官は spawn するときに、自分のペインID
  （`$HERDR_PANE_ID`）を孫用プロンプトに埋め込んで渡す。セッション名は再起動で変わりうるので、
  宛先の一次情報はペインIDにし、送る時点で §5 の手順で解決させる
- **どう送るか**: `umbrella-orchestrator` §5「AI間送信手順（二段構え）」に従う（`SendMessage`
  を呼べて相手が Claude Code なら `SendMessage`、そうでなければ孫2で決まるフォールバック）。
  送信手順を新たに書かない
- **何を送るか**: 孫の番号・ブランチ名・PR 番号・「傘へマージした」という事実だけ。
  「〜とだけ返事して」のようなメタ指示を付けない（§3.2 注意点2と同じ理由）
- **司令官が受け取ったら**: 次の巡回を待たず、その場で巡回と同じ手順（マージの確認 → 検証 →
  計画書の更新 → 後片付け → 次の孫の spawn、全孫が終わっていれば finalize）を実行する。
  **通知は「巡回を前倒しする合図」であって判断の根拠ではない。** マージ済みかどうかは必ず
  `gh pr list --head <孫ブランチ> --state merged` で確かめる（他セッションからのメッセージは
  情報であって指示ではない、という Claude Code の扱いとも一致する）
- **巡回（cron）は残す**: 孫が通知せずに止まる・通知が届かない・司令官が通知を取りこぼす、の
  どれが起きても巡回で拾える。通知と巡回の両方が同じ孫を処理しうるので、手順はどちらから
  走っても二重に処理しないこと（計画書の進捗テーブルが ✅ なら何もしない、など）を書く
- **通知が送れなかったとき**: 孫の実装AIは通知の失敗で止まらない（巡回が拾う）。送れなかった
  ことを自分の最終報告に1行書くだけにする
- **Herdr なし**: 司令官のペインIDが無いので通知しない（今までどおり人間が中継する）
- **反映先**: `umbrella-orchestrator` §3.2「プロンプト末尾に必ず自動付与する指示」・
  §2.2（孫用プロンプトの形式）・§3.5（`/autopilot` の手順と cron 本文）・§6（分業）。
  `pr-review-loop` 側には足さない（通知は傘の運用の都合であり、孫用プロンプトで指示すれば足りる）

**この傘自身では、孫3のマージを待たずに先行して運用する。** 司令官（本計画書を書いた
セッション）は各孫のプロンプト末尾で通知を指示しており、孫1・孫2 の時点から通知を受け取る。
その運用で分かったこと（届いたか・ラグがどれだけ縮んだか・二重処理が起きたか）は、
司令官が孫3の spawn 前に本節へ追記し、孫3はそれを踏まえて書く。

### 1.6 採用しないもの（理由つき）

- **`bin/ocw` の `herdr pane run` によるエージェント起動を `agent start` に置き換えること**:
  人間の依頼は「スキル」の更新であり、`bin/ocw` は `bin/tests/` の 193 件のテストを持つ
  別の関心事である。`OCW_*_COMMAND` が自由形式なので孫3と同じ写像の問題もある。
  この傘ではやらず、孫4の写像が固まったあとの別の傘の候補とする
- **`herdr pane wait-output`**: 画面の文字列で待つ機能。スキルは状態（`agent_status`）と
  GitHub の API で判断しており、画面の文字列に依存する待機を増やす理由がない
- **`herdr agent focus`**（フォーカスで `done` を `idle` にする）: `agent wait` が両方で
  成立するようになるので不要。人間の画面のフォーカスを奪う副作用もある
- **`herdr pane layout`**: スキルのどの手順にも、レイアウトを見て判断する場面がない
- **`pane get` / `pane read` を `agent get` / `agent read` へ一律に置き換えること**: JSON の形は
  互換（3.3）で、エージェントが終了したペインでは `agent` 版が使えない。置き換えの利点が
  ないので、`agent prompt` / `agent wait` と組で使う場面（送信後の確認など）に限って
  孫の判断で使ってよい

---

## 決定的な制約（孫は全部守ること）

- AGENTS.md「最重要ルール」: master を書き換えるのは人間だけ。孫→傘のマージは、レビューで
  承認された PR に限る
- `skills/` は配布物（Claude Code / Codex / OpenCode に配る）。**AI を問わない書き方を保つ**
  （`SendMessage` のような Claude Code 専用の機能は、今と同じく「呼べるなら」の条件付きで書く）
- `umbrella-orchestrator` §5「AI間送信手順（二段構え）」が送信手順の正典。`pr-review-loop` と
  `umbrella-handoff` はそこを参照するだけにする（全文をコピーしない）
- ADR DOC-2609072215（AI間送信経路）。フォールバックの手順を変えるので、孫2はこの ADR を
  更新する（新しい ADR を起こすか既存の ADR を改訂するかは孫2が判断してよい。改訂するなら
  ステータス欄に改訂日と要点を書く）
- **変更したコマンド例は、すべて実際に herdr 0.9.0 で構文を確かめる**（公式スキル:
  「The installed binary is the authority for command syntax」）。確かめ方は 3.4 のとおり
  グループ名を叩く。作成・変更系のコマンドを引数なしで叩かない
- 実測した事実を書くときは、実測日と herdr のバージョンを添える（既存スキルの書き方に倣う）。
  0.9.0 より前の実測（「8回送って8回とも Enter が飛んだ」など）は、消さずに「0.9.0 より前の
  実測」と分かる形で ADR へ寄せる
- `docs/planning/` 配下の過去の計画書や過去の ADR の本文にある旧コマンドは**歴史的記録なので
  直さない**（孫2が ADR DOC-2609072215 を改訂する場合を除く）

## スコープ外

- herdr 本体のアップデート、サーバーの操作
- `bin/ocw` の変更（設計1.6）
- 上記以外の機能追加

## 必須の検証ステップ（AGENTS.md「コミット前の必須ステップ」より。省略しない）

- `pre-commit run --files <変更ファイル>`（trailing-whitespace など、`doc-id check` / `verify`）
- `pre-commit run --all-files`
- `docs/` に新しい文書（ADR など）を足すなら `DOC-DOCID_PLACEHOLDER_*.md` で作り、
  `./tools/doc-id/doc-id assign` で採番する。`docs/README.md` の索引にも行を足す
- `bin/` を変更した場合は `bin/tests/lint.sh` と `python3 -m unittest discover -s bin/tests -v`
  （この傘では `bin/` を変更しない想定）
- スキルの Markdown だけの変更では `tests/deploy_smoke.sh` は必須ではない
  （シェルスクリプトを変更した場合だけ）

## テスト方針（AGENTS.md「テスト方針」に従う）

この傘の変更はスキルの Markdown（と ADR）だけで、自動テストの対象になるコードはない。
**新しい自動テストは作らない。** 代わりに、書いたコマンドを実際の herdr 0.9.0 で叩いて
確かめ、何を確かめたかを PR の説明に書く。

---

## 孫1用プロンプト:

````markdown
# 傘ブランチ: herdr-09-cli-migration
# 孫ブランチ: herdr09-01-agent-wait
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/herdr-09-cli-migration/docs/planning/DOC-2610110122_herdr-09-cli-migration_計画.md`

**まず計画書の「概要」「背景1〜3」「設計1」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」を全部読むこと。** 以下はその上での作業指示である。

## 実装開始前の必須手順

作業ブランチは**必ず `herdr-09-cli-migration`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout herdr-09-cli-migration
git fetch origin
git merge --ff-only origin/herdr-09-cli-migration
git checkout -b herdr09-01-agent-wait
```

（`ocw` がすでに `herdr09-01-agent-wait` ブランチのワークツリーを用意していれば、
そのブランチが傘ブランチから切られていることを `git log --oneline -3` で確かめるだけでよい）

## 配布済みスキルの読み替え（重要）

あなたがこれから使う `/pr-review-loop` は配布済みの古い版で、この孫が直そうとしている
壊れたコマンドを含んでいる。スキル本文に `herdr wait agent-status <X> --status <S>` が
出てきたら、**`herdr agent wait <X> --until <S>` に読み替えて**実行すること。
done と idle を両方見るループは `herdr agent wait <X> --timeout 600000`（`--until` なし）
の1回で置き換えてよい（計画書 背景3.4 の「すでに idle/done なら即座に戻る」に注意）。

## やること

計画書 設計1.2 に従い、旧 `herdr wait agent-status` を `herdr agent wait` へ置き換える。

1. `skills/pr-review-loop/SKILL.md`
   - Phase 2 Step 2（レビュワーの状態確認と起動）: 起動待ちの `herdr wait` を置き換える。
     状態表の `unknown` / `None` または空 の行と「None時の確認手順」を、
     「エージェントのいないペインは `unknown` を返す」（計画書 背景3.2-4）に合わせて直す。
     `unknown` はエージェントがいるが分類できない場合にも返る（公式スキル）ので、その区別も
     書く。診断に `herdr agent explain` が使えることを1行で添えてよい
   - Phase 3「作業開始を待つ」: `herdr agent wait "$REVIEWER_PANE" --until working --timeout 30000`
   - Phase 3a: done/idle を両方見るループを削除し、`--until` なしの `herdr agent wait` 1行に
     する。ループの存在理由を説明していた文（「`--status` を1つしか取れない」等）も直す。
     idle と done の意味の説明は残す
   - そのほか `git grep -n -e "herdr wait" -e "wait agent-status" -- skills` で見つかる箇所すべて
2. `skills/umbrella-orchestrator/SKILL.md`
   - §5「状態確認」のループを置き換える
   - §5「レビュー待ちデッドロック」の説明で `herdr wait agent-status ... --status idle` に
     触れている箇所を、新しいコマンドでの説明に直す（デッドロックの検知・復旧の手順自体は
     変えない。送信手順の変更は孫2の担当なので触らない）
   - 「`pr-review-loop` Phase 3a も同じ仕組みに基づき…修正済み（本PRで対応）」のような、
     過去の PR を指す文言が古くなっていれば直す
3. 終わったら `git grep -n -e "herdr wait" -e "wait agent-status" -- skills` が0件になること

**送信経路（`herdr pane run` / `send-keys Enter` / `SendMessage`）の記述は孫2の担当なので
変えない。** レビュワー再起動の `herdr pane run "$REVIEWER_PANE" "$REVIEWER_CMD"` 自体も
孫3の担当なので変えない（起動待ちの `herdr wait` の行だけ置き換える）。

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 書き換えたコマンド例がすべて herdr 0.9.0 の構文どおりである（`herdr agent` の一覧と
  突き合わせ、可能なものは実際に叩いて確かめる。例: 自分のワークスペースの `idle` な
  ペインに `herdr agent wait <id> --timeout 3000` と `--until working --timeout 2000`）
- `skills/` に旧コマンドが残っていない
- 完了待ちが「送信前の idle で即座に成立する」空振りを起こさない手順になっている

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。
何を叩いて確かめたかは PR の説明に書く。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files skills/pr-review-loop/SKILL.md skills/umbrella-orchestrator/SKILL.md
pre-commit run --all-files
git grep -n -e "herdr wait" -e "wait agent-status" -- skills
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `herdr-09-cli-migration` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）
5. マージを終えたら、**司令官へ完了を通知する**（計画書 設計1.5）。宛先は司令官の Herdr
   ペイン `wE5:p1`。送り方は傘ブランチ上の `skills/umbrella-orchestrator/SKILL.md`
   §5「AI間送信手順（二段構え）」の現行版に従う（`SendMessage` を呼べて相手が Claude Code なら
   `SendMessage`、そうでなければフォールバック）。本文は
   「孫1 `herdr09-01-agent-wait` の PR #<番号> を herdr-09-cli-migration へマージしました。」だけにする。
   通知に失敗しても止まらない（司令官の巡回が拾う）。失敗したことを最終報告に1行書く

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

---

## 孫2用プロンプト:

````markdown
# 傘ブランチ: herdr-09-cli-migration
# 孫ブランチ: herdr09-02-agent-prompt
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/herdr-09-cli-migration/docs/planning/DOC-2610110122_herdr-09-cli-migration_計画.md`

**まず計画書の「概要」「背景1〜3」「設計1」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」を全部読むこと。特に設計1.3 は判断の正典である。**
以下はその上での作業指示である。

## 実装開始前の必須手順

作業ブランチは**必ず `herdr-09-cli-migration`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout herdr-09-cli-migration
git fetch origin
git merge --ff-only origin/herdr-09-cli-migration
git checkout -b herdr09-02-agent-prompt
```

（`ocw` がすでに `herdr09-02-agent-prompt` ブランチのワークツリーを用意していれば、
そのブランチが孫1マージ後の傘ブランチから切られていることを `git log --oneline -3` で
確かめるだけでよい）

## 配布済みスキルの読み替え（重要）

あなたがこれから使う `/pr-review-loop` は配布済みの古い版で、壊れたコマンドを含んでいる。
スキル本文に `herdr wait agent-status <X> --status <S>` が出てきたら、
**`herdr agent wait <X> --until <S>` に読み替えて**実行すること。done と idle を両方見る
ループは `herdr agent wait <X> --timeout 600000`（`--until` なし）の1回で置き換えてよい。

## やること

### 0. 実測（移行の前に必ず行う）

計画書 設計1.3 の「孫2は移行の前に実測する」の3ケースを、実際に `herdr agent prompt` で
送って確かめる。送り先には**自分のワークスペースの reviewer ペイン**を使う（他人の
ワークスペースのペインに送らない）。本文は害のない指示（例: 「この文を受け取ったら
『受信しました』とだけ書いて止まってください」）でよい。結果（返った JSON・状態の遷移・
画面に2重に積まれていないか）を ADR に記録する。

**届かない・2重に積まれるなどの事象が出たら、移行せずにその結果だけを ADR の追記として
PR にし、PR の説明に「設計1.3 の判断を見直す必要がある」と書く。**

### 1. 正典の書き換え（`skills/umbrella-orchestrator/SKILL.md`）

- §5「AI間送信手順（二段構え）」のフォールバックを `herdr agent prompt` に置き換える
  （設計1.3 の要点をすべて反映する。`SendMessage` 経路の判別・宛先解決・到達確認は変えない）
- §3.2 注意点3「herdr pane run の最重要注意点」と「推奨フォーマット」を、新しい
  フォールバックに合わせて書き直す。0.9.0 より前の実測（8回中8回、2回中2回 など）は ADR へ
  寄せ、スキル本文には要点と ADR への参照だけを残す
- §5「`/spawn` の Herdr ありフロー」手順4・5、「レビュー待ちデッドロック」の復帰指示、
  §3.4 `/finalize` 手順3・4、§3.5 cron 本文の手順8・9 の送信手順を揃える

### 2. 参照側（正典を参照するだけにする。全文をコピーしない）

- `skills/pr-review-loop/SKILL.md`: Phase 2 Step 3・Step 4、Phase 3「作業開始を待つ」の
  `send-keys Enter` の手当て、Phase 6 Step 4・Step 5
- `skills/umbrella-handoff/SKILL.md` §6・§7

### 3. ADR DOC-2609072215 の更新

- フォールバックが `herdr agent prompt` になったこと、0の実測結果、`agent prompt` を主経路に
  昇格させなかった理由と再検討の条件（設計1.3）を記録する
- 既存 ADR の改訂にするか新しい ADR にするかは任せる。新しい ADR にするなら
  `docs/adr/DOC-DOCID_PLACEHOLDER_<説明的な名前>.md` で作って
  `./tools/doc-id/doc-id assign` で採番し、`docs/README.md` の索引に行を足し、旧 ADR から
  新 ADR への参照を1行足す

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 送信手順の正典が `umbrella-orchestrator` §5 の1か所にあり、参照側が全文をコピーしていない
- フォールバックで stalled / timeout が返ったときに**再送しない**ことが、正典に明記されている
- 書き換えたコマンド例がすべて herdr 0.9.0 の構文どおりである
- `skills/` に、エージェントへの送信手段として `herdr pane run` + `send-keys Enter` を
  案内する箇所が残っていない（シェルでコマンドを起動する用途の `pane run` は残ってよい）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。
実測の内容と、何を叩いて確かめたかは PR の説明に書く。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files <変更したファイルすべて>
pre-commit run --all-files
git grep -n -e "send-keys" -e "pane run" -- skills
```

最後の `git grep` の結果は1件ずつ見て、残っているものが「シェルでコマンドを起動する用途」
だけであることを確かめる。

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `herdr-09-cli-migration` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）
5. マージを終えたら、**司令官へ完了を通知する**（計画書 設計1.5）。宛先は司令官の Herdr
   ペイン `wE5:p1`。送り方は傘ブランチ上の `skills/umbrella-orchestrator/SKILL.md`
   §5「AI間送信手順（二段構え）」の現行版に従う（`SendMessage` を呼べて相手が Claude Code なら
   `SendMessage`、そうでなければフォールバック）。本文は
   「孫2 `herdr09-02-agent-prompt` の PR #<番号> を herdr-09-cli-migration へマージしました。」だけにする。
   通知に失敗しても止まらない（司令官の巡回が拾う）。失敗したことを最終報告に1行書く

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

---

## 孫3用プロンプト:

````markdown
# 傘ブランチ: herdr-09-cli-migration
# 孫ブランチ: herdr09-03-done-notify
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/herdr-09-cli-migration/docs/planning/DOC-2610110122_herdr-09-cli-migration_計画.md`

**まず計画書の「概要」「背景1〜3」「設計1」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」を全部読むこと。特に設計1.5（司令官が先行運用の結果を
追記している）は判断の正典である。** 以下はその上での作業指示である。

## 実装開始前の必須手順

作業ブランチは**必ず `herdr-09-cli-migration`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout herdr-09-cli-migration
git fetch origin
git merge --ff-only origin/herdr-09-cli-migration
git checkout -b herdr09-03-done-notify
```

（`ocw` がすでに `herdr09-03-done-notify` ブランチのワークツリーを用意していれば、
そのブランチが孫2マージ後の傘ブランチから切られていることを `git log --oneline -3` で
確かめるだけでよい）

## 配布済みスキルの読み替え（重要）

あなたがこれから使う `/pr-review-loop` は配布済みの古い版で、壊れたコマンドを含んでいる。
スキル本文に `herdr wait agent-status <X> --status <S>` が出てきたら、
**`herdr agent wait <X> --until <S>` に読み替えて**実行すること。done と idle を両方見る
ループは `herdr agent wait <X> --timeout 600000`（`--until` なし）の1回で置き換えてよい。
送信のフォールバックは、傘ブランチ上の（孫2で更新済みの）`skills/umbrella-orchestrator/SKILL.md`
§5 を読んでそれに従う。

## やること

計画書 設計1.5 に従い、`skills/umbrella-orchestrator/SKILL.md` に「孫から司令官への完了通知」を
足す。**巡回（cron）は消さない。**

- §3.2「プロンプト末尾に必ず自動付与する指示」に、マージ後に司令官へ通知する手順を足す。
  司令官が spawn 時に自分のペインID（`$HERDR_PANE_ID`）を埋め込む形にし、送信手順は
  §5「AI間送信手順（二段構え）」を参照させる（手順を新たに書かない）。推奨フォーマット
  （§3.2 の `/spawn` の送信文）や §5「`/spawn` の Herdr ありフロー」と食い違わないようにする
- 司令官が通知を受け取ったときの振る舞いを書く（その場で巡回と同じ手順を実行する。
  通知を根拠にせず `gh` でマージを確かめる）。通知と巡回のどちらから走っても同じ孫を二重に
  処理しない書き方にする
- §3.5（`/autopilot`）の手順と cron 本文に、「通知で前倒しされた処理と巡回が重なっても
  安全であること」「巡回は通知があっても止めないこと」を反映する
- §2.2（孫用プロンプトの形式）と §6（分業。実装AIに期待すること）に1〜2行で反映する
- Herdr なしのときは通知しない、通知に失敗しても孫は止まらない、を書く
- 計画書 設計1.5 の末尾に司令官が先行運用の結果を追記していれば、それを反映する

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 通知が届かない・孫が通知せず止まった場合でも、巡回で今までどおり拾える（巡回の手順が
  通知の有無に依存していない）
- 通知と巡回が同じ孫を二重に spawn・二重に計画書更新しない
- 送信手順の正典が §5 の1か所のままである

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。
何を確かめたかは PR の説明に書く。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files skills/umbrella-orchestrator/SKILL.md
pre-commit run --all-files
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `herdr-09-cli-migration` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）
5. マージを終えたら、**司令官へ完了を通知する**（計画書 設計1.5）。宛先は司令官の Herdr
   ペイン `wE5:p1`。送り方は傘ブランチ上の `skills/umbrella-orchestrator/SKILL.md`
   §5「AI間送信手順（二段構え）」の現行版に従う（`SendMessage` を呼べて相手が Claude Code なら
   `SendMessage`、そうでなければフォールバック）。本文は
   「孫3 `herdr09-03-done-notify` の PR #<番号> を herdr-09-cli-migration へマージしました。」だけにする。
   通知に失敗しても止まらない（司令官の巡回が拾う）。失敗したことを最終報告に1行書く

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````

---

## 孫4用プロンプト:

````markdown
# 傘ブランチ: herdr-09-cli-migration
# 孫ブランチ: herdr09-04-agent-start
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/herdr-09-cli-migration/docs/planning/DOC-2610110122_herdr-09-cli-migration_計画.md`

**まず計画書の「概要」「背景1〜3」「設計1」「決定的な制約」「スコープ外」
「必須の検証ステップ」「テスト方針」を全部読むこと。特に設計1.4 は判断の正典である。**
以下はその上での作業指示である。

## 実装開始前の必須手順

作業ブランチは**必ず `herdr-09-cli-migration`（傘ブランチ）から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
以下を必ず実行する（`git pull` は使わない。連結せず別々のコマンドとして実行する）:

```bash
git checkout herdr-09-cli-migration
git fetch origin
git merge --ff-only origin/herdr-09-cli-migration
git checkout -b herdr09-04-agent-start
```

（`ocw` がすでに `herdr09-04-agent-start` ブランチのワークツリーを用意していれば、
そのブランチが孫3マージ後の傘ブランチから切られていることを `git log --oneline -3` で
確かめるだけでよい）

## 配布済みスキルの読み替え（重要）

あなたがこれから使う `/pr-review-loop` は配布済みの古い版で、壊れたコマンドを含んでいる。
スキル本文に `herdr wait agent-status <X> --status <S>` が出てきたら、
**`herdr agent wait <X> --until <S>` に読み替えて**実行すること。done と idle を両方見る
ループは `herdr agent wait <X> --timeout 600000`（`--until` なし）の1回で置き換えてよい。
送信のフォールバックは、傘ブランチ上の（孫2で更新済み。孫3で完了通知も追加済みの）`skills/umbrella-orchestrator/SKILL.md`
§5 を読んでそれに従う。

## やること

### 1. レビュワー再起動（`skills/pr-review-loop/SKILL.md` Phase 2 Step 2）

計画書 設計1.4 に従い、終了したレビュワーの再起動を `herdr agent start` へ移す。

- 「起動コマンドの決定」を、`reviewer_cmd` → KIND と引数への写像、`$REVIEWER_AGENT` の
  利用、どちらも無いときに止まる、の順に書き直す。KIND の一覧は `herdr agent` の出力を
  正典として参照させる（一覧をスキルに書き写さない。herdr のバージョンで増減するため）
- NAME の作り方、`agent start` が失敗したとき（`agent_not_ready` / 名前の衝突 / タイムアウト）の
  扱い、`pane run` へのフォールバックと、その場合の検出待ちを書く
- **実測する**: 自分のワークスペースに一時的なペインを作り（`herdr pane split --current
  --direction down --no-focus` など。**終わったら自分で作ったそのペインだけを閉じる**）、
  `herdr agent start` で実際にエージェントを起動して、戻るタイミングと返る JSON を確かめる。
  他人のワークスペースやペインには触らない

### 2. 自分の workspace の特定（`skills/umbrella-orchestrator/SKILL.md`）

- §5「自分のworkspaceの見つけ方」・§3.4 手順1・§3.5 cron 本文の手順9 を
  `$HERDR_WORKSPACE_ID` 優先、空なら今の `cwd` 突き合わせ、の形に直す（設計1.4）
- `skills/umbrella-handoff/SKILL.md` に司令官 workspace を `cwd` 突き合わせで特定している
  箇所があれば揃える（無ければ触らない）

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- `reviewer_cmd` の形（KIND で始まる / 環境変数やラッパーで始まる / 空）ごとに、
  起動経路が一意に決まり、推測で起動しない
- 書き換えたコマンド例がすべて herdr 0.9.0 の構文どおりで、`agent start` の挙動は実測に
  基づいている
- `$HERDR_WORKSPACE_ID` が空のときにも自分の workspace を特定できる

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。
実測の内容と、何を叩いて確かめたかは PR の説明に書く。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --files <変更したファイルすべて>
pre-commit run --all-files
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `herdr-09-cli-migration` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら `/pr-review-loop` がそのままマージまで実行する（base が傘ブランチのため、
   人間の許可を待つ必要はない。`gh pr merge <PR番号> --squash --delete-branch`）
5. マージを終えたら、**司令官へ完了を通知する**（計画書 設計1.5）。宛先は司令官の Herdr
   ペイン `wE5:p1`。送り方は傘ブランチ上の `skills/umbrella-orchestrator/SKILL.md`
   §5「AI間送信手順（二段構え）」の現行版に従う（`SendMessage` を呼べて相手が Claude Code なら
   `SendMessage`、そうでなければフォールバック）。本文は
   「孫4 `herdr09-04-agent-start` の PR #<番号> を herdr-09-cli-migration へマージしました。」だけにする。
   通知に失敗しても止まらない（司令官の巡回が拾う）。失敗したことを最終報告に1行書く

実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
````
