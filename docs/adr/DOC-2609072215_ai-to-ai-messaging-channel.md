# ADR: AI間の受け渡しを SendMessage 優先の二段構えにする

## ステータス

確定（2026-09-07）。改訂（2026-10-11）: herdr 0.9.0 で `herdr agent prompt` が新設されたため、
フォールバックを `herdr pane run` + `send-keys Enter` から `herdr agent prompt` に置き換えた
（§6）。§1〜§5 は当時の記録であり、旧フォールバックの記述は 0.9.0 より前の手順としてそのまま
残す。

## 1. 背景

傘ブランチ運用（`skills/umbrella-orchestrator`）と PR レビュー往復
（`skills/pr-review-loop`）は、司令官／実装AI／レビューAI 間の指示の受け渡しを
`herdr pane run`（ターミナルへ1文字ずつ打ち込むキーストローク注入）だけに依存してきた。
両スキルの SKILL.md には、実測に基づく以下の事故が記録されている。

- 本文だけ打ち込まれて Enter が送られない（`umbrella-orchestrator/SKILL.md` §3.2:
  1つの傘で8回送って8回とも発生）
- 長文プロンプトが途中で止まる（1文字ずつ打ち込むため）
- 同じ本文を再送するとプロンプト欄に2重に積まれる

一方、Claude Code には `ListAgents` / `SendMessage` というテキストボックスを介さない
送信経路がある。`SendMessage({to: "<セッション名>", message: "..."})` はキーストローク
注入ではないため、上記3つの事故は原理的に発生しない。

### 1.1 判明していた壁 — 名前空間の不一致

`ListAgents` はセッション名（`<ブランチ名>-<ランダム2文字>` 形式）で宛先を要求するが、
`ocw -H` が返すのは Herdr の pane ID（`w9K:p1` 形式）であり、セッション名からは
Herdr 上の役割（commander / implementer / reviewer）が判別できない。同一プレフィックスの
3セッションが起動時刻もほぼ同時になるため、名前や順序からの当てずっぽうは使えない。

### 1.2 実測で解けた橋渡し（2026-09-07）

`herdr pane list` の各ペインは次の2フィールドを返す。

- `agent`: そのペインで動いているエージェント種別（`claude` / `codex` / `opencode` など）
- `agent_session`: `{ "agent": "claude", "kind": "id", "source": "herdr:claude",
  "value": "<Claude Code のセッション UUID>" }`

Claude Code はさらに `~/.claude/sessions/<pid>.json` に稼働中セッションの索引を書いており、
各レコードは `sessionId`（`agent_session.value` と同じ UUID）と `name`
（`ListAgents` の宛先名）を同じオブジェクトに持つ。

実測（傘 `agent-handoff` の司令官ワークスペース `w9K`）:

| pane_id | label | agent_session.value | セッション名 |
|---|---|---|---|
| `w9K:p1` | commander | `19715e72-…` | `agent-handoff-0d` |
| `w9K:p2` | implementer | `ba407543-…` | `agent-handoff-dd` |
| `w9K:p3` | reviewer | `fc6b2648-…` | `agent-handoff-97` |

`agent-handoff-dd`（implementer）へ実際に `SendMessage` したところ、`herdr pane get w9K:p2`
の `agent_status` が `idle` → `done` へ遷移した（フォーカスされていないペインが完了する
ときの正常な状態遷移。§5 参照）。**`send-keys Enter` は不要で、本文が途中で切れることも
なかった。**

## 2. 決定

AI 間の受け渡しは、**相手が Claude Code だと判別できるときは `SendMessage` を使い、
そうでなければ `herdr pane run` + `send-keys Enter` へ落ちる二段構え**とする
（2026-10-11 改訂: フォールバックは `herdr agent prompt`。§6）。

### 2.1 これは既存 ADR の方針に対する但し書きである

ADR [DOC-2608272128](DOC-2608272128_skills-multi-agent-distribution.md) §2.4 は
「配布側でエージェントを絞るのではなく、スキル自身がエージェント非依存に書かれること」を
定めており、`pr-review-loop` はコミット `0b399a7`「pr-review-loop の Claude Code 依存を
剥がす」で実際にその依存（レビュワー再起動コマンドの `claude` 決め打ち・
`agent_status=None` 時の Claude Code 画面表示決め打ち・`Co-Authored-By` の Claude 固定）を
剥がしたばかりである。

`SendMessage` は Claude Code 専用機能であり、素朴に置き換えるとこの依存が復活する。
したがって本決定は §2.4 の原則そのものを覆すのではなく、**「Claude Code 専用機能を
使ってよいのは、非 Claude 環境で確実にフォールバックする実装になっているときだけ」**
という限定付きの例外を追加するものである。二段構えの手順自体は Claude / Codex /
OpenCode のいずれのペインに対しても同じコードパスで動作し、判別に失敗した場合は
常に従来の `herdr pane run` 経路へ落ちるため、非 Claude エージェントの送信手段が
失われることはない。

### 2.2 橋渡しの手順

送信元が次の4ステップで宛先を解決する。

```
1. 判別（送信元・送信先の両方）。
   - 送信元: 自分が SendMessage を呼べる Claude Code セッションか。呼べなければ
     即座にフォールバックへ落ちる。
   - 送信先: herdr pane list（または対象1件なら herdr pane get）で対象ペインの
     agent が "claude" か確認する。"claude" でなければ即座にフォールバックへ落ちる。

2. agent_session.value（UUID）を取り出し、~/.claude/sessions/*.json を
   走査してその UUID を sessionId に持つレコードを探す。status フィールドは
   生存の指標にならない（§4 参照）ため、各レコードの pid が実際に存命かを
   kill -0 相当で確認し、存命レコードがちょうど1件のときだけ name を採用する。
   該当レコードが無い／ファイルが読めない／存命レコードが0件または2件以上
   （一意に決まらない）場合も、即座にフォールバックへ落ちる。

3. SendMessage({ to: <name>, message: <計画書やレビュー指示の絶対パスと
   セクション名。プロンプト全文は送らない> }) で送信する。

4. 送信直前の agent_status を控えておき、送信後に herdr pane get <pane-id> で
   再取得して変化したか（idle → working/done、working → done 等）を確認する。
   変化していなければ（特に送信前がすでに done だった場合）herdr pane read で
   画面を目視し、新しい応答が出ているかで判断する。動いていなければ
   フォールバック（herdr pane run + send-keys Enter）に切り替える。
```

**フォールバック（従来手順。herdr 0.9.0 より前。現行は §6）**: `herdr pane run <pane-id> "<本文>"` → 送信後
`herdr pane get <pane-id>` で `agent_status` を確認 → `idle` のままなら
`herdr pane send-keys <pane-id> Enter` → 再確認、を `working` になるまで繰り返す。
それでも `working` にならない場合は `herdr pane read` で画面を確認する（無人ペインは
`working` を経ず直接 `done` になりうるため、上記ステップ4と同じ扱い）。同じ本文を
`herdr pane run` で再送しない（プロンプト欄に2重に積まれる）。

この手順の正典は `skills/umbrella-orchestrator/SKILL.md` の
「AI間送信手順（二段構え）」節に置き、`skills/pr-review-loop/SKILL.md` はそこを参照する
（全文の二重管理を避けるため。理由は `AGENTS.md` が `links_for_tool()` の一元化で
繰り返し述べている「同じ情報を2箇所に書くと片方だけ更新される」事故の再発防止と同じ）。

**`SendMessage` 経路でも、送るのは「計画書やレビュー指示の絶対パスとセクション名」であって
プロンプト全文ではない。** 長さの制約が消えても、正典を1箇所に保つ・受け手にメタ指示で
停止させない、という既存方針は変わらない。

## 3. 却下した案と却下理由

### 3.1 `bin/ocw` に pane ID → セッション名の対応を書き出させる

ブリーフ段階では解法候補に挙がっていたが、`herdr pane list` が既に
`agent_session.value`（UUID）を返しており、そこから `~/.claude/sessions/` を引くだけで
橋渡しが成立することが実測で判明した（§1.2）。`ocw` 側に新しい状態を持たせる必要は無い。

### 3.2 `SendMessage` への全面置き換え

`herdr pane run` を完全に廃止し `SendMessage` だけにする案。Codex / OpenCode など
非 Claude エージェントが動くペインでは `SendMessage` の宛先を解決できず、通信手段が
消える。ADR DOC-2608272128 §2.4 のエージェント非依存の原則に反するため却下。

## 4. 既知のリスク

`~/.claude/sessions/` は Claude Code の内部実装であり、公開インターフェースではない。
将来のバージョンでフォーマットが変わったり、パス自体が移動したりする可能性がある。

**このリスクへの対処は「引けなかったら黙って失敗するのではなく、必ず §2.2 のフォールバック
（`herdr pane run` + `send-keys Enter`）へ落ちる」という設計そのものである。** 索引が
読めない・レコードが見つからない・`agent` が `claude` でない、のいずれの場合も同じ
フォールバック経路に合流するため、`~/.claude/sessions/` の仕様変更は「速い経路が
使えなくなる」影響にとどまり、「送信そのものができなくなる」影響には至らない。

### 4.1 `status` は生存の指標にならない（実測で判明。2026-09-07）

当初案は `sessionId` が一致し `status` が truthy なレコードを1件見つけたら採用する
設計だったが、実測でこの前提が崩れていることが判明した。本セッション上の索引
893レコードのうち845レコードがすでに終了した `pid` を指しており、うち98個の
`sessionId` が複数レコードに重複していた（94個は `name` が全部別）。生存48セッション
のうち14セッションがこの重複の影響を受けていた。`status` フィールドは終了した
セッションのレコードにも残ったままになりうるため、生存確認には使えない。

**対処**: レコードの `pid` を実際に `kill -0` 相当（Python の `os.kill(pid, 0)`）で
存命確認し、`sessionId` が一致し、かつ存命レコードが**ちょうど1件**のときだけ
`name` を採用する。0件（該当セッションが既に終了している）でも2件以上（存命セッション
間で `sessionId` が衝突しており一意に決まらない）でも、推測せず §2.2 のフォールバックへ
落ちる。実測データに対してこの方式を適用すると、生存48セッションのうち一意に解決
できないケースは1件（`sessionId` 衝突）のみまで減った。

**残るリスク**: `pid` の再利用（プロセス終了後に別プロセスが同じ `pid` を得る）は
理論上 false positive になりうるが、レコードには `procStart`（プロセス開始時刻）も
含まれており、突き合わせればさらに強い確認ができる。ただし `procStart` の検証は
`/proc` 経由（Linux）が前提で macOS では別の手段が要り、このリポジトリは
macOS / Linux / WSL2 をクロスプラットフォームで対象とするため、今回は
`kill -0` 相当の確認のみを採用し、`pid` 再利用は許容する既知の残存リスクとした。
起きても即座に「送信できない」にはならず、フォールバックが働く設計内では影響が
限定的である。

## 5. 実測: 「Enter が飛ばないのが既定」という記述の再検証

`umbrella-orchestrator/SKILL.md` §3.2 は、従来「1つの傘で8回送って8回とも Enter が
送られなかった」ことから「届かないのが既定」と断定していた。しかし本傘のブリーフを
渡した送信では、約200文字・改行なしの日本語1行を2回送って**2回とも** Enter が届いた
（`herdr pane run` 直後の `herdr pane get` で両方とも `agent_status: working` に
遷移しており、`send-keys Enter` は不要だった。対象: 傘 `ocw-usage-discovery` /
`agent-handoff` それぞれの commander ペイン、実測日 2026-09-07）。

**どちらの実測も実際に起きたことであり、一方を他方で上書きしない。** 条件差
（本文長・改行の有無・送信先の `agent_status`）を切り分ける追加実測は行っていない。
「送信後に必ず `agent_status` を確認する」という手順自体は、失敗時のコストが大きいため
引き続き必須とする。詳細は `umbrella-orchestrator/SKILL.md` §3.2 の実測併記を参照。

## 6. 改訂（2026-10-11）: フォールバックを `herdr agent prompt` に置き換える

herdr 0.9.0 で `herdr agent prompt <target> <text> [--wait] [--until STATUS]... [--timeout MS]`
が新設された。herdr 公式スキルの説明では、貼り付けモードを守り、本文と Enter を順序どおり
1回の送信として送る。相手が `blocked`（承認待ち・質問ダイアログ）なら何も送らず
`agent_blocked` で拒否する。`--wait` で非 working の相手へ送り、5秒以内に `working` か
`blocked` が観測されなければ `agent_prompt_stalled` を返す。また
「A timeout or stalled response does not prove the prompt was never delivered; do not blindly
submit it again.」と明記している。これは §1 の3つの事故（Enter が飛ばない・長文が途中で
止まる・再送で2重に積まれる）に、仕様として手当てがある。

### 6.1 決定

**`SendMessage` を優先する二段構えは維持し、フォールバックだけを `herdr agent prompt` に
置き換える。** 正典はこれまでどおり `skills/umbrella-orchestrator/SKILL.md` §5 の1か所で、
`pr-review-loop` と `umbrella-handoff` は参照するだけである。`herdr pane run` はシェルで
コマンドを走らせる用途（例: レビュワーエージェントの再起動）にだけ残り、エージェントへの
指示の送信には使わない。

### 6.2 実測（herdr 0.9.0、2026-10-11）

送り先は孫2の自ワークスペースの reviewer ペイン（Claude Code）。受け手の動きは
その Claude Code セッションの記録（transcript）で確かめた。

| ケース | 送ったもの | 結果 |
|---|---|---|
| `idle` の相手 | 改行を含む日本語284文字を `agent prompt --wait --timeout 8000` | 終了コード0、`"type":"agent_prompted"`、約3.6秒（相手が応答し終えた時点）で戻った。本文は欠けずに1回だけ受信され、画面に2重に積まれていない。`send-keys Enter` は不要だった |
| `working` の相手 | 相手が400行を出力している最中に `agent prompt --wait --timeout 3000` | 3秒後に `{"error":{"code":"timeout",...}}`、終了コード1。**それでも本文は相手のターン終了後に1回だけ処理された**（キューに積まれた）。つまり `timeout` は失敗ではない |
| `done` の相手 | — | **再現できなかった。** reviewer ペインは同じタブで常に可視のためか、応答後は毎回 `done` を経ず `idle` に戻った（`agent wait --until done` は何度もタイムアウト）。未実測として扱い、`idle` と同じ待機状態であるというスキル側の前提は変えない |
| `agent_prompt_stalled` / `agent_blocked` | — | どちらも再現していない。公式スキルの記述に基づいて手順に書いてある |

副次的な観察: 本文が長いほど `--wait` は長く待つ（相手が動き出したあとも完了まで待ち続ける）。
実装AIへの指示は何十分も続くため、`--wait` に長い `--timeout` を付けると司令官がブロック
される。フォールバックは短い `--timeout`（5000ms）で送り、`timeout` を失敗と取り違えないことを
正典に書いた。`--wait` に `--until` を重ねない（公式の使い方）。

### 6.3 `agent prompt` を主経路へ昇格させなかった理由と、再検討の条件

昇格の利点はある。`~/.claude/sessions/` という Claude Code の内部実装に頼る宛先解決
（§4）をやめられ、どの AI からでも同じ手順になる。それでも今回は見送る。

- `SendMessage` は数多くの傘で実績があり、相手のターミナル入力欄に書き込まないため、
  人間がそのペインで手入力していても衝突しない。`agent prompt` の実測は §6.2 の数回だけである
- 実績のある主経路を、実測の少ない経路と入れ替える理由がない

再検討の条件: `agent prompt` の実測が溜まり、`done` ケースや `stalled` / `blocked` も含めて
事故が起きていないと言えること、または `~/.claude/sessions/` の形式変更で §4 のリスクが
現実になったとき。

### 6.4 0.9.0 より前の実測の扱い

「8回送って8回とも Enter が飛んだ」「別の傘では2回中2回とも届いた」（§5）は、0.9.0 より前の
`herdr pane run` についての実測であり、消さずに残す。スキル本文からはこの実測を除き、
要点とこの ADR への参照だけを残した。
