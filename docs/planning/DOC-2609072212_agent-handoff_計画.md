# 計画書: 人間→AI・AI→AI の受け渡しを仕組み化する

傘ブランチ: `agent-handoff`
ターゲット: `master`

## 概要

「相談で問題意識が固まってから、傘の司令官が計画書を書き始めるまで」の工程が、現状どの
スキルの担当でもなく**人間が毎回口頭で指示している**。この傘はその空白地帯を埋める。
併せて、AI 同士の受け渡しがキーストローク注入（`herdr pane run`）に依存している点を、
より事故りにくい経路（Claude Code の `SendMessage`）へ置き換える。

3つの論点を扱う。

1. **AI間通信の作法**（`skills/umbrella-orchestrator` / `skills/pr-review-loop`）— キーストローク
   注入をやめ、相手が Claude Code だと判別できるときは `SendMessage` を使う二段構えにする
2. **引き継ぎスキルの新設**（`skills/umbrella-handoff`）— ブリーフ起草 → 傘ブランチ作成 →
   `ocw -H` → ラベル改名 → commander への引き渡し → 到達確認 を自動化する
3. **発動条件の配布**（`claude/` ほか）— 「複数PRに分かれる規模だと判断したら自分で実装せず
   傘への引き継ぎを提案する」を Claude Code / Codex / OpenCode の3エージェントすべてに効かせる

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。既に参照できない前提で
> 書く）を material として司令官が起草したものである。** ブリーフに書かれていた問題意識・
> 決定事項・実測値・制約は、**すべて本計画書へ転記済み**であり、以降はこの計画書が正典である。

## 孫ブランチ進捗

| 孫 | ブランチ | 内容 | 状況 |
|---|---|---|---|
| 1 | `agent-handoff-01-ai-messaging` | AI間通信を `SendMessage` 二段構えへ。ADR 起票 + `umbrella-orchestrator` / `pr-review-loop` の SKILL.md 更新 | ✅ PR #71 マージ済 |
| 2 | `agent-handoff-02-handoff-skill` | 引き継ぎスキル `skills/umbrella-handoff/` の新設 | 🔄 実装中 |
| 3 | `agent-handoff-03-trigger-distribution` | 発動条件を Claude Code / Codex / OpenCode の3エージェントへ配布 | ⬜ 待機中 |

## ワークスペースラベル

- 傘: `dotfiles :: AI引き継ぎの仕組み化`
- 孫1: `dotfiles :: AI引き継ぎの仕組み化 孫1 AI間通信の作法見直し`
- 孫2: `dotfiles :: AI引き継ぎの仕組み化 孫2 引き継ぎスキル新設`
- 孫3: `dotfiles :: AI引き継ぎの仕組み化 孫3 発動条件を全AIへ配布`

## 依存関係と実行順序

```
孫1 (AI間通信の作法を確定させる: SendMessage 二段構え + ADR)
  ↓ 「引き渡しをどう送るか」が確定して初めて、孫2 が引き渡し手順を書ける
孫2 (umbrella-handoff スキル新設。孫1 で確定した作法を使って commander へ渡す)
  ↓ 「何を提案させるか」= スキル名と発動条件が確定して初めて、孫3 が配る文面を書ける
孫3 (発動条件を3エージェントへ配布)
```

**直列。** 触るファイルは孫1（既存2スキルの SKILL.md）・孫2（新規ディレクトリ）・
孫3（`claude/` と配布経路）で重ならないが、**後段が前段の成果物を参照する**ため並列にできない。
孫2 は孫1が確定した「二段構えの送信手順」を自分のスキル文書に書く必要があり、孫3 は
孫2 が決めた実際のスキル名と発動条件を文面に埋め込む必要がある。

> スキル名 `umbrella-handoff` は本計画書で固定する（孫2 が勝手に変えない）。孫3 がこの名前に
> 依存するため、変えたくなったら孫2 は実装前に司令官へ報告すること。

---

## 背景1: 人間の問題意識（逐語）

### 1.1 引き継ぎを毎回手打ちしている

> こういうふうに、なんか問題意識を持ってこれをなんとかしようと思ったとき、今のように
> ocw で傘を切ってそこの司令官に umbrella-orchestrator でやらせて、と指示することが
> 多いんだが、これを毎回打ち込むの面倒なんだよね（AIが自分の会話で修正しようとしたり、
> 計画書まで書こうとしたりする。文脈、問題意識、解決方向性、そのた場合場合の制約や指示
> などを示してあとはまかせてほしいのに、そうならないこと多くていちいち訂正してる）。
> なんとかしたいが、これもスキルにすべきなのかな

**求めている状態**: 文脈・問題意識・解決方向性・制約を人間が示したら、あとは傘へ引き継いで
任せられること。相談していた会話の AI が、その場で実装を始めたり計画書を書き始めたりしないこと。

### 1.2 AI 同士の会話がキーストローク注入になっている

> pr-review-loop とかのスキルもそうなんだが、herdr でAI同士が会話するとき、直接
> テキストボックスに文字打って送信させるように書いてあるけど、こないだ、なんか herdr
> 組み込みなのか、Claudeの機能かわからんが、テキストボックス飛び越えて直接話しかけてる
> ような挙動を見かけた。これができるならそれを使うように行ったほうが効率的だし事故らなそう
> とおもうんで、それも計画にいれてほしい

## 背景2: 人間が確定させた決定事項（覆さないこと）

- **この傘は単独で切る。** 並走する傘 `ocw-usage-discovery`（`ocw` の使い方を AI に効率的に
  教える傘）とはテーマが違うので混ぜない
- **発動条件は Claude Code だけでなく Codex / OpenCode にも効く形にする。**
  `claude/CLAUDE.md` に1行入れるだけでは Claude Code にしか効かない
- **計画書は司令官が書く**（本計画書がそれである）

## 背景3: 既存スキルの「穴」

`skills/umbrella-orchestrator/SKILL.md` は **計画書が既にある地点からしか始まらない**。

- §3.5 `/autopilot` の前提: 「計画書が作成済みで、全孫のプロンプトが記述済みであること」
- §3.5 補足: 「計画書の作成・レビューは人間が行う前提」

つまり次の工程が**誰の担当でもない**。人間が毎回口頭で指示している範囲がここである。

```
相談で問題意識が固まる
  → 傘ブランチ名を決める
  → 傘ブランチを master から切る
  → ocw -H（--no-commander を付けない = 3ペイン）で司令官ワークスペースを作る
  → herdr workspace rename で日本語ラベル化（既定形のときだけ上書き）
  → commander に「ブリーフを読んで計画書を書き、umbrella-orchestrator で進めろ」と渡す
  → 送信が届いたか確認する
  ↑↑↑ ここまでが空白地帯 = 孫2 の担当範囲 ↑↑↑
  → （ここから umbrella-orchestrator の担当範囲）
```

この工程は機械的だが間違えやすい。`umbrella-orchestrator/SKILL.md` に実測付きで記録されている罠:

- `herdr pane run` は本文だけ打ち込んで Enter を送らないことがある（同スキルの実測: 1つの傘で
  8回送って8回とも）。送信後に `herdr pane send-keys <pane-id> Enter` を撃ち、`agent_status` が
  `working` になるまで確認する
- 同じ本文を `herdr pane run` で再送してはいけない（プロンプト欄に2重に積まれる）
- プロンプト全文を打ち込まない（1文字ずつ打つため長文は途中で止まる）。計画書/ブリーフの
  絶対パスとセクション名だけを渡す
- 「〜とだけ返事してください」のようなメタ指示を付けない（実装 AI がそれを実行して停止する）

**これらは本来スキルが担うべき手順であって、人間が毎回口頭で言う内容ではない。**

### 3.1 ただし「Enter が飛ばない」の再現性は疑わしい（実測が食い違った）

`umbrella-orchestrator/SKILL.md` §3.2 注意点3 は「**8回送って8回とも** Enter が送られなかった」
「届かないのが既定だと思って手順に組み込め」と書いている。

**しかしブリーフを渡した送信では、2回中2回とも Enter が飛んだ。**
`herdr pane run <pane-id> "<本文>"` の直後に `herdr pane get` で確認したところ、どちらの
commander も `agent_status: working` になっており、`send-keys Enter` は不要だった。

- 実測日: 2026-09-07
- 対象: `w9J:p1`（傘 `ocw-usage-discovery` の commander）、`w9K:p1`（傘 `agent-handoff` の commander）
- 本文長: 約200文字の日本語1行（改行なし）

**「送信後に必ず確認する」という手順自体は残す**（失敗したときのコストが大きい）が、
**「届かないのが既定」という前提は現状と合っていない可能性がある。** 孫1 の担当範囲に含める。

## 背景4: AI間通信の代替経路（司令官が実測。橋渡しは解けている）

1.2 で人間が見た「テキストボックスを飛び越える挙動」は **Claude Code の `ListAgents` /
`SendMessage` ツール**である。

### 4.1 ブリーフ時点での実測（未解決だった点）

- `ListAgents` は同一マシンの他 Claude Code セッションを列挙する（実測で118件見えた。
  `interactive` と `Remote Control` の両方が混ざる）
- `SendMessage({to: "<name>", message: "..."})` でセッション名を宛先に送れる。キーストローク
  注入ではないので、**背景3 に挙げた罠（Enter が飛ばない、長文が途中で止まる、2重に積まれる）は
  原理的に発生しない**
- **しかし名前空間が herdr と一致しない。** `ocw -H` が返すのは herdr の pane ID（`w9K:p1` 形式）、
  `SendMessage` が要求するのはセッション名。しかもセッション名は `<ブランチ名>-<ランダム2文字>`
  で、3ペインが同じプレフィックスで並び **役割が名前から一切判別できない**:

  ```
  agent-handoff-0d [799904]  · interactive · idle · started 57s ago
  agent-handoff-97 [794133]  · interactive · idle · started 56s ago
  agent-handoff-dd [eed716]  · interactive · idle · started 57s ago
  ```

  起動時刻も 56〜57s で差が無く、順序でも当てられない。`bin/ocw` は各ペインへ
  `--env "OCW_ROLE=commander"` 等で役割を渡している（`bin/ocw:495` 付近）が、
  **その情報が `ListAgents` 側に出てこない**のがブリーフ時点での行き詰まりだった。

### 4.2 司令官による追加実測 — 橋渡しは解けた（2026-09-07）

**`herdr pane list` の各ペインは `agent_session.value` として Claude Code のセッション UUID を
返しており、`label` として役割名（`commander` / `implementer` / `reviewer`）を持っている。**

```json
{
  "agent": "claude",
  "agent_session": { "agent": "claude", "kind": "id", "source": "herdr:claude",
                     "value": "ba407543-43f8-4b06-a28d-0a26182f3c7c" },
  "agent_status": "idle",
  "cwd": "/home/manemone/projects/dotfiles/agent-handoff",
  "label": "implementer",
  "pane_id": "w9K:p2",
  "workspace_id": "w9K"
}
```

**そのセッション UUID から `SendMessage` の宛先名を引ける。** Claude Code は
`~/.claude/sessions/<pid>.json` に稼働中セッションの索引を書いており、`sessionId` と `name`
（＝ `ListAgents` に出る宛先名）が同じレコードに入っている:

```json
{ "pid": 59652, "sessionId": "19715e72-285e-4d21-8640-1f3ce29757a5",
  "cwd": "/home/manemone/projects/dotfiles/agent-handoff",
  "kind": "interactive", "name": "agent-handoff-0d", "nameSource": "derived",
  "status": "busy" }
```

**実測で得られた対応**（傘 `agent-handoff` の司令官ワークスペース `w9K`）:

| pane_id | label | agent_session.value | セッション名 |
|---|---|---|---|
| `w9K:p1` | commander | `19715e72-…` | `agent-handoff-0d` |
| `w9K:p2` | implementer | `ba407543-…` | `agent-handoff-dd` |
| `w9K:p3` | reviewer | `fc6b2648-…` | `agent-handoff-97` |

**さらに、この宛先へ実際に `SendMessage` して到達を確認した。**
`agent-handoff-dd`（implementer）へ送ったところ、`herdr pane get w9K:p2` の `agent_status` が
`idle` → `done` へ遷移した（フォーカスされていないペインが処理を完了した状態。
`umbrella-orchestrator/SKILL.md` §5「レビュー待ちデッドロック」で説明されている `done` の意味）。
**`send-keys Enter` は不要で、本文が途中で切れることもなかった。**

つまり橋渡しの手順は次の3ステップに確定する。

```
herdr pane list → label で役割を選び agent_session.value（UUID）を取る
  → ~/.claude/sessions/*.json を UUID で引いて name を取る
  → SendMessage({to: name, message: ...})
```

### 4.3 残る論点（孫1 が設計・検証すること）

1. **`~/.claude/sessions/` は Claude Code の内部実装であり、公開インターフェースではない。**
   フォーマットが変わったり、パスが移動したりする可能性がある。**索引が引けなかったら黙って
   失敗するのではなく、従来の `herdr pane run` + `send-keys Enter` へ落ちる設計**にすること
2. **判別子の設計。** herdr pane の `agent` フィールドが `claude` であること、かつ
   `~/.claude/sessions/` にその UUID の生きたレコードがあること、の AND が自然な判別条件に
   見える（`pr-review-loop` は既に `agent` フィールドを `$REVIEWER_AGENT` の解決に使っている）。
   最終判断は孫1
3. `ListAgents` に出るのは Claude Code のセッションだけ（Codex / OpenCode のペインは
   列挙されない）と推定される。上記の判別子はこの推定に依存しない形になっている（`agent` が
   `claude` でなければそもそも索引を引かない）が、確認できるなら確認する
4. `Remote Control` 経由や `offline` のセッションが大量に混ざる。上記の手順は UUID からの
   逆引きなので原理的に混ざらないが、`ListAgents` を直接使う書き方を残すなら絞り込みが要る

### 4.4 最大の制約 — エージェント非依存の原則（最重要）

**ADR DOC-2608272128 §2.4 は「配布側でエージェントを絞るのではなくスキル側を非依存にする」
方針を定めている。**

> 全スキルを全エージェントへ一律に配る。特定のエージェントでしか意味を持たないスキルは、
> 配布側で絞るのではなく、**スキル自身がエージェント非依存に書かれること**で解決する
> （この決定に伴い `pr-review-loop` の Claude Code 依存を除去した）。

`skills/` は Claude Code / Codex / OpenCode の3エージェントへ同じ実体が配られるため、
Claude Code でしか成立しない書き方が残っていると配った先で使えない。そして `pr-review-loop` は
コミット `0b399a7`「pr-review-loop の Claude Code 依存を剥がす」で**つい先日その依存を3点
はがしたばかり**である（レビュワー再起動コマンドの `claude` 決め打ち、`agent_status=None` 時の
Claude Code 画面表示決め打ち、`Co-Authored-By` の Claude 固定）。

**`SendMessage` は Claude Code 専用機能なので、素朴に置き換えると剥がしたばかりの依存が
復活する。** したがって設計は二段構えでなければならない:

- 相手が Claude Code だと判別できるときは `SendMessage`
- そうでなければ従来どおり `herdr pane run` + `send-keys Enter`

**この判断は ADR DOC-2608272128 §2.4 の方針に対する重要な但し書きなので、孫1 は ADR を
新規に起票して記録する**（詳細は孫1のプロンプト参照）。

## 背景5: 発動条件をどこに置くか（人間の要求: 全AI対応）

**スキルは呼ばれないと発動しない。** `/`+スキル名を人間が打つ運用のままだと、1.1 の
「AI が勝手に自分の会話で実装し始める」問題は消えない。恒久的な指示を配る必要がある。

現状の配布経路（`shared/helpers.sh` で確認済み）:

| 経路 | 配布先 | 対象エージェント |
|---|---|---|
| `claude/deploy.sh` | `~/.claude/CLAUDE.md`（symlink） | **Claude Code のみ** |
| `skills/deploy.sh` | `skill_dir_for_agent()` が返す各ディレクトリ | claude / codex / opencode の**3つ全部** |

`skill_agents()` = `claude` `codex` `opencode`、`skill_agent_home()` = それぞれ
`$HOME/.claude` / `${CODEX_HOME:-$HOME/.codex}` / `${XDG_CONFIG_HOME:-$HOME/.config}/opencode`、
`skill_dir_for_agent()` = いずれも `<home>/skills`。

**現状、3エージェント共通で配れる経路は `skills/` しか無い。**

司令官による実測（2026-09-07）:

- `~/.claude/CLAUDE.md` は配布実体への symlink（`~/.local/share/dotfiles/current/claude/CLAUDE.md`）
- `~/.codex/AGENTS.md` は**実ファイルで存在するが symlink ではない**。内容は
  `claude/CLAUDE.md` と同じ個人指示（口調設定）で、**手で複製されたまま dotfiles の管理外に
  ある**。つまり Codex 向けグローバル指示の置き場所自体は既に判明している
- `~/.config/opencode/` は本セッションの権限で読めなかった。**OpenCode がどのファイルを
  グローバル指示として読むかは孫3 が調査すること**

## スコープ外

- `ocw` の使い方を AI に教える件（並走する傘 `ocw-usage-discovery` の担当）
- `herdr` 本体への機能追加要望
- `bin/ocw` 本体の変更。孫1 の橋渡しは `herdr pane list` が既に返している情報だけで
  成立するため、`ocw` 側に pane ID → セッション名の対応を書き出す仕組みは不要である
  （ブリーフ段階では解法候補に挙がっていたが、4.2 の実測で不要と判明した）

## ADR の扱い

- **孫1 は ADR を書く。** 「エージェント非依存の原則（DOC-2608272128 §2.4）に対して、
  Claude Code 専用機能を条件付きで使う二段構えを許す」は、既存 ADR の方針に但し書きを
  足す技術決定であり、記録が要る
- 孫2・孫3 は原則 ADR 不要。ただし孫3 が「Codex / OpenCode 向けグローバル指示の新しい
  配布経路を新設する」と判断した場合は、`$HOME` への配布先が増える＝ ADR DOC-2608040229 の
  配布方式に関わるため、ADR を起票するか司令官へ報告してから進めること

## 共通の必須検証（全孫が省略しない）

AGENTS.md「コミット前の必須ステップ」に従う。

- `pre-commit run --all-files`
- `skills/` にディレクトリを追加する、または `shared/helpers.sh` / deploy スクリプト /
  `claude/` を触るなら `tests/deploy_smoke.sh`
- `shared/helpers.sh` や deploy スクリプトを触るなら `./deploy-all.sh --dry-run`
- `docs/` に新規ファイルを追加したら `./tools/doc-id/doc-id assign docs/path/to/file.md`

**実オペレーションの deploy（`deploy-all.sh` の素の実行）は禁止。** 検証は
`--dry-run` か `tests/deploy_smoke.sh` のサンドボックス経由で行う。

**linter の抑制ディレクティブ（`# shellcheck disable=...` 等）や `.pre-commit-config.yaml` の
除外追加を AI の判断で入れない**（AGENTS.md 最重要ルール）。指摘が不合理だと判断したら
抑制せず人間へ報告する。

---

## 孫1用プロンプト:

````markdown
# 孫1: AI間通信を `SendMessage` 二段構えへ

## 背景

AI 同士の受け渡しが `herdr pane run`（ターミナルへ1文字ずつ打ち込むキーストローク注入）に
依存しており、次の事故が起きている（`skills/umbrella-orchestrator/SKILL.md` に実測付きで記録）。

- 本文だけ打ち込まれて Enter が送られない
- 長文が途中で止まる
- 同じ本文を再送するとプロンプト欄に2重に積まれる

人間の要望は「テキストボックスを飛び越えて直接話しかける経路があるならそれを使え」である。
その経路は Claude Code の `ListAgents` / `SendMessage` ツールで、**司令官が橋渡しの手順まで
実測で確定させてある。** 計画書 `docs/planning/DOC-2609072212_agent-handoff_計画.md` の
「背景4: AI間通信の代替経路」を必ず読むこと。実測値・JSON の実物・対応表がそこにある。

## やること

### 1. ADR を起票する

**これが最初。** 判断を記録してから文書を直す。

`docs/adr/DOC-2609072212_ai-to-ai-messaging-channel.md` として新規作成し、
`./tools/doc-id/doc-id assign` で採番する。

書くべき内容:

- **決定**: AI 間の受け渡しは、相手が Claude Code だと判別できるときは `SendMessage` を使い、
  そうでなければ `herdr pane run` + `send-keys Enter` へ落ちる二段構えとする
- **背景**: ADR DOC-2608272128 §2.4 は「スキル自身がエージェント非依存に書かれること」を
  定めており、`pr-review-loop` はコミット `0b399a7` でその依存を剥がしたばかりである。
  今回の決定は**その原則に対する但し書き**であり、「Claude Code 専用機能を使ってよいのは、
  非 Claude 環境で確実にフォールバックする実装になっているときだけ」という形に限定される
- **橋渡しの手順**（計画書 背景4.2 の内容を ADR にも書く。計画書は傘のマージ後も残るが、
  ADR は恒久的な技術決定の記録なので、手順の要点は自己完結させる）
- **却下した案と却下理由**: `bin/ocw` に pane ID → セッション名の対応を書き出させる案は、
  `herdr pane list` が既に `agent_session.value` を返しているため不要（実測で確認済み）。
  `SendMessage` への全面置き換えは、非 Claude エージェントで通信手段が消えるため却下
- **既知のリスク**: `~/.claude/sessions/` は Claude Code の内部実装であり公開インター
  フェースではない。フォーマット変更やパス移動で引けなくなりうる。**引けなかったら
  フォールバックする**設計であることを明記する

### 2. 共通レシピの置き場所を決める

`umbrella-orchestrator` と `pr-review-loop` の両方が同じ送信手順を使う。**同じ手順を
2つの SKILL.md へ全文コピーしない**（片方だけ更新される事故が起きる。AGENTS.md が
`links_for_tool()` の一元化で繰り返し警告している型の事故と同じ）。

置き場所は自分で設計してよい。候補:

- どちらか一方の SKILL.md に正典を置き、もう一方は節を名指しで参照する
- `skills/` 配下に共有の参照文書を1つ置き、両方から参照する（ただし新しいディレクトリを
  作ると `skills/deploy.sh` がスキルとして配ってしまう可能性があるので、`skills/deploy.sh` が
  何をスキルとして検出するかを**実際に読んでから**決めること）

**選んだ理由を PR 説明に書くこと。**

### 3. 送信手順を二段構えで書く

正典となる場所に、次を含む手順を書く。

- **判別**: `herdr pane get <pane-id>` の `agent` が `claude` か。`claude` でなければ
  即座に従来手順へ落ちる
- **宛先の解決**: `agent_session.value`（UUID）→ `~/.claude/sessions/*.json` を UUID で引いて
  `name` を取る。**該当レコードが無い / 読めない / `status` が生きていない場合は従来手順へ落ちる**
- **送信**: `SendMessage({to: <name>, message: ...})`
- **到達確認**: `herdr pane get <pane-id>` の `agent_status` が `idle` から動くこと
  （フォーカスされていないペインは完了時に `working` を経ず `done` になりうる。
  `umbrella-orchestrator/SKILL.md` §5「レビュー待ちデッドロック」参照）
- **フォールバック**: 従来どおり `herdr pane run` + `send-keys Enter` + `agent_status` 確認

**`SendMessage` 経路でも、送るのは「計画書の絶対パスとセクション名」であって
プロンプト全文ではない**という既存方針は維持する（長さの制約が消えても、正典を1箇所に
保つという理由は消えないため）。同様に「〜とだけ返事してください」のようなメタ指示を
付けない方針も維持する。

### 4. 両スキルの呼び出し箇所を更新する

- `skills/umbrella-orchestrator/SKILL.md`: §3.2 `/spawn`、§3.4 `/finalize`、
  §5「`/spawn` の Herdr ありフロー」、§5「レビュー待ちデッドロック」の復帰指示
- `skills/pr-review-loop/SKILL.md`: reviewer への依頼・再レビュー依頼の送信箇所

**既存の実測記録（デッドロックの発生回数の表など）を消さないこと。** それらは
フォールバック経路の根拠として引き続き有効である。

### 5. 「Enter が飛ばないのが既定」という記述を実態に合わせる

`umbrella-orchestrator/SKILL.md` §3.2 注意点3 は「1つの傘で **8回送って8回とも**
Enter が送られなかった」「届かないのが既定だと思って手順に組み込め」と書いている。

**しかし 2026-09-07 の実測では、2回中2回とも Enter が飛んだ**（計画書 背景3.1 に条件を
記載。約200文字・改行なしの日本語1行を commander ペインへ送信）。

- 手元で `herdr pane run` の挙動を実際に確認し、条件差（本文長・改行の有無・送信先の
  `agent_status`）を切り分けられるなら切り分ける
- 切り分けられなくても構わない。**「届かないのが既定」という断定を、両方の実測を併記した
  記述へ改める**こと。手順としての「送信後に必ず `agent_status` を確認する」は残す
  （失敗時のコストが大きいため）
- **過去の実測を消して新しい実測で上書きしない。** どちらも実際に起きたことなので併記する

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。ただし本孫の成果物は主に Markdown 文書であり、シェルコードを
追加しない場合は自動テストの追加が適さない。**その場合はテストを追加せず、下記を
手で確認した結果を PR 説明に書くこと。**

- `pre-commit run --all-files` が通る（`doc-id check` / `verify` を含む）
- 新規 ADR に DOC-ID が採番されている
- 共通レシピが1箇所にあり、両スキルから参照できている（全文重複が無い）
- 二段構えの記述が、非 Claude エージェント（Codex / OpenCode）で読んでも実行可能な
  手順になっている（`SendMessage` が存在しない前提でフォールバックへ落ちられる）

各項目と test example を1対1対応させる必要はない。

## 必須の検証コマンド

```bash
pre-commit run --all-files
./tools/doc-id/doc-id check
./tools/doc-id/doc-id verify
```

`shared/helpers.sh` や deploy スクリプトを触った場合のみ追加で:

```bash
./deploy-all.sh --dry-run
tests/deploy_smoke.sh
```

**実オペレーションの deploy（`deploy-all.sh` の素の実行）は禁止。**

## 注意

- **linter の抑制ディレクティブや `.pre-commit-config.yaml` の除外追加を自分の判断で
  入れない**（AGENTS.md 最重要ルール）。不合理だと思ったら人間へ報告する
- `docs/` の文書に地の文で言及するときは DOC-ID を明示する（AGENTS.md）
- README は「ルート `README.md`」と「各ツールの `README.md`」の二層構造。片方だけ
  更新しない。`skills/README.md` にスキル一覧があるので、内容が変わったら追随する
````

## 孫2用プロンプト:

````markdown
# 孫2: 引き継ぎスキル `skills/umbrella-handoff/` の新設

## 背景

人間の不満（逐語）:

> こういうふうに、なんか問題意識を持ってこれをなんとかしようと思ったとき、今のように
> ocw で傘を切ってそこの司令官に umbrella-orchestrator でやらせて、と指示することが
> 多いんだが、これを毎回打ち込むの面倒なんだよね（AIが自分の会話で修正しようとしたり、
> 計画書まで書こうとしたりする。文脈、問題意識、解決方向性、そのた場合場合の制約や指示
> などを示してあとはまかせてほしいのに、そうならないこと多くていちいち訂正してる）。
> なんとかしたいが、これもスキルにすべきなのかな

`skills/umbrella-orchestrator/SKILL.md` は**計画書が既にある地点からしか始まらない**
（§3.5 の前提「計画書が作成済みで、全孫のプロンプトが記述済みであること」、
補足「計画書の作成・レビューは人間が行う前提」）。その手前の工程が誰の担当でもない。

計画書 `docs/planning/DOC-2609072212_agent-handoff_計画.md` の「背景3: 既存スキルの穴」に、
埋めるべき工程の一覧と、既知の罠が実測付きで書いてある。**必ず読むこと。**

## やること

`skills/umbrella-handoff/SKILL.md` を新設する。**スキル名は `umbrella-handoff` で固定**
（孫3 がこの名前に依存する。変えたくなったら実装前に司令官へ報告すること）。

### 1. スキルが担う範囲

「相談で問題意識が固まってから、傘の司令官が計画書を書き始めるまで」を自動化する。

```
相談で問題意識が固まる
  → ブリーフを起草する（相談側 AI の仕事。テンプレートはこのスキルが持つ）
  → 傘ブランチ名を決める
  → 傘ブランチをターゲットブランチから切る
  → ocw -H（--no-commander を付けない = 3ペイン）で司令官ワークスペースを作る
  → herdr workspace rename で日本語ラベル化（既定形のときだけ上書き）
  → commander へ「ブリーフを読んで計画書を書き、umbrella-orchestrator で進めろ」を渡す
  → 到達を確認する
  → ここで相談側 AI は手を引く（計画書は書かない・実装しない）
```

### 2. 線引きを明示する（最重要）

人間の不満の核心は「**相談側の AI が、その場で実装を始めたり計画書を書き始めたりする**」
ことである。スキルは次を明示的に禁止すること。

- 相談側の会話で実装を始めない
- 相談側の会話で計画書（`docs/planning/DOC-*_計画.md`）を書かない
- 孫の分割・順序・孫用プロンプトの起草をしない（すべて司令官の仕事）

**ブリーフはあくまで material であり、計画書ではない。** ブリーフの冒頭に
「これは計画書ではない。計画書は司令官が本ブリーフを material として書くこと」と
明記させる（実際にこの傘のブリーフがそう書かれており、機能した）。

### 3. ブリーフのテンプレートを持たせる

この傘を起こしたブリーフ自体が仕様例になっている。その構成は次のとおりだった。

- 問題意識（**人間の発言の逐語引用**。要約しない）
- 人間が確定させた決定事項（覆さないこと、と明記）
- 既存の穴（何がどのスキルの担当外なのか）
- 実測値（測った日・対象・条件を添える）
- 決定的な制約（既存 ADR との衝突など）
- スコープ外
- 必須の検証ステップ
- 孫分割の叩き台（**叩き台であり司令官が再設計してよい、と明記**）

**逐語引用を要約に置き換えないこと**を強く書く。司令官は人間と直接話していないので、
要約されると人間が本当に困っている点が失われる。

**ブリーフの置き場所も設計対象**である。今回は相談側セッションの scratchpad に置いたが、
scratchpad はセッション固有の一時ディレクトリで、司令官が読んだ後に消える。
「一時ファイルなので必要な内容は計画書に全部落とし込め」と人間が口頭で補ったことで
救われた。**この補足を人間が毎回言わなくて済む形**にすること（引き渡しプロンプトに
その指示を含める / 傘ブランチのワークツリー内へ置く / など。設計は任せる）。

### 4. 引き渡しの送信手順

**孫1 が確定させた二段構え**（相手が Claude Code だと判別できるときは `SendMessage`、
そうでなければ `herdr pane run` + `send-keys Enter`）を使う。**手順を全文コピーせず、
孫1 が置いた正典を参照すること。** 孫1 のマージ後に spawn されているので、
`skills/` 配下を実際に読んで正典の場所を確認すること。

引き渡しプロンプトに必ず含める要素:

- ブリーフの**絶対パス**
- 「ブリーフを material として `docs/planning/` に計画書を作成し、`umbrella-orchestrator`
  の作法に従って孫の spawn まで自律的に進めろ」
- 「ブリーフは一時ファイルなので、必要な内容は計画書に全部落とし込め」
- **「〜とだけ返事してください」のようなメタ指示を付けない**（受け手がそれを実行して停止する）

### 5. frontmatter と発動方式

既存3スキルの frontmatter に倣う。`description` は日本語で、**孫3 がこのスキルを名指しで
呼ばせる**ので、何をするスキルなのかが description だけで判別できるように書くこと。

自動発動させるか `/umbrella-handoff` の明示起動だけにするかは設計対象。
`pr-review-loop` / `repo-baseline` は description に「自動発動はしない。`/xxx` で明示的に
起動」と書いている。**この傘の目的は「人間が毎回打ち込まなくて済むこと」なので、
明示起動のみにするなら孫3 の発動条件と組み合わせて成立することを確認すること**
（孫3 は「複数PRに分かれる規模だと判断したら自分で実装せず傘への引き継ぎを提案する」を
配る。提案された人間が `/umbrella-handoff` と打つ流れなら成立する）。

### 6. エージェント非依存

`skills/` は Claude Code / Codex / OpenCode の3エージェントへ同じ実体が配られる
（ADR DOC-2608272128 §2.4）。**Claude Code でしか成立しない書き方を残さないこと。**
`SendMessage` を使う部分は必ず孫1 のフォールバック手順とセットで書く。

### 7. README の追随

`skills/README.md` にスキル一覧がある。ルート `README.md` にも言及があれば追随する
（README は二層構造。片方だけ更新しない）。

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- **新しいスキルディレクトリが3エージェント全部へ配布される**こと。`skills/deploy.sh` は
  ディレクトリを自動検出するので新規コードは不要なはずだが、`tests/deploy_smoke.sh` の
  既定対象に `skills` が含まれているため、**このスモークテストが実際に新スキルの symlink を
  検証していることを確認する**（していなければ、そこを埋める価値がある）
- `pre-commit run --all-files` が通る

Markdown 文書中心の成果物なので、シェルコードを追加しないなら自動テストは追加しない。
手で確認した結果を PR 説明に書くこと。各項目と test example を1対1対応させる必要はない。

## 必須の検証コマンド

```bash
pre-commit run --all-files
tests/deploy_smoke.sh
```

`tests/deploy_smoke.sh` は `HOME` を一時ディレクトリへ差し替えたサンドボックスで動く。
**実オペレーションの deploy（`deploy-all.sh` の素の実行）は禁止。**

## 注意

- **linter の抑制ディレクティブや `.pre-commit-config.yaml` の除外追加を自分の判断で
  入れない**（AGENTS.md 最重要ルール）
- `docs/` の文書に地の文で言及するときは DOC-ID を明示する
- **`claude/CLAUDE.md`（配布物）はこの孫では触らない。** 孫3 の担当
````

## 孫3用プロンプト:

````markdown
# 孫3: 発動条件を Claude Code / Codex / OpenCode の3エージェントへ配布する

## 背景

人間の要求（計画書 背景2 の確定事項）:

> **発動条件は Claude Code だけでなく他のAI（Codex / OpenCode）にも効く形にする。**
> `claude/CLAUDE.md` に1行入れるだけでは Claude Code にしか効かない

**スキルは呼ばれないと発動しない。** 孫2 が `skills/umbrella-handoff/` を新設したが、
`/umbrella-handoff` を人間が打つ運用のままだと、元の不満（AI が勝手に自分の会話で
実装や計画書作成を始める）は消えない。恒久的な指示を配る必要がある。

計画書 `docs/planning/DOC-2609072212_agent-handoff_計画.md` の「背景5: 発動条件をどこに置くか」に
配布経路の現状と司令官の実測が書いてある。**必ず読むこと。**

## 配る内容

趣旨は次のとおり。**文面は自分で起草してよい**が、この趣旨から外れないこと。

> 相談された課題が、複数のPRに分かれる規模だと判断したら、その会話で実装を始めたり
> 計画書を書き始めたりせず、傘ブランチへの引き継ぎ（`umbrella-handoff` スキル）を
> 人間に提案する。

**スキル名 `umbrella-handoff` は孫2 が実装済みの実際の名前である。** 実装を読んで
名前と発動方法（`/umbrella-handoff` なのか自動発動なのか）を確認してから文面を書くこと。

## やること

### 1. 各エージェントのグローバル指示ファイルを調べる

司令官が実測した範囲（2026-09-07）:

| エージェント | グローバル指示ファイル | dotfiles の管理下か |
|---|---|---|
| Claude Code | `~/.claude/CLAUDE.md` | ✅ `claude/deploy.sh` が symlink を張る |
| Codex | `~/.codex/AGENTS.md` | ❌ **実ファイルで存在するが symlink ではない**。内容は `claude/CLAUDE.md` と同じ個人指示（口調設定）で、手で複製されたまま管理外 |
| OpenCode | **未調査** | ❌ 司令官の権限で `~/.config/opencode/` を読めなかった |

**OpenCode がどのファイルをグローバル指示として読むかを調査すること。**
`shared/helpers.sh` の `skill_agent_home()` は OpenCode のホームを
`${XDG_CONFIG_HOME:-$HOME/.config}/opencode` と定義している。

### 2. 配布方式を決める

選択肢（自分で設計してよい）:

- **A**: `claude/` と同じ要領で、各エージェント向けのグローバル指示を dotfiles から配る
  新しい経路を作る。`~/.codex/AGENTS.md` が既に手で複製されている（＝管理下に無い）現状も
  同時に解消できる
- **B**: 配布経路は増やさず、`skills/umbrella-handoff/` の `description` を強く書くことで
  エージェントに自発的に選ばせる
- **C**: 上記の組み合わせ

**A を選ぶ場合の重み**（軽く見ないこと）:

`$HOME` への配布先が増えるということは、AGENTS.md「実装時の注意」の一連の作法が全部
発生するということである。

- `shared/helpers.sh` の `AVAILABLE_TOOLS` と `links_for_tool()`（または新しい一元化関数）
- `uninstall.sh` の撤去対象（`KNOWN_GENERATED_<tool>` / `_skills_src` の `case`）
- `deploy-all.sh --status` のリンク健全性スキャン
- `tests/deploy_smoke.sh` の検証対象
- ルート `README.md` と各ツールの `README.md`（二層構造。片方だけ更新しない）
- **ADR**: 配布方式に関わるので ADR DOC-2608040229 の延長線上の技術決定になる

**A を選び、かつ作業量が「この孫1本に収まらない」と判断したら、実装を始める前に司令官へ
報告すること。** 傘に孫を1本足す判断は司令官が行う。黙って肥大させない。

さらに注意: `~/.codex/AGENTS.md` は**既に人間の実ファイルが存在する**。symlink へ
置き換えるなら `shared/helpers.sh` の `symlink_backup` による退避が効くことを確認すること
（AGENTS.md「symlink の退避」参照。退避の前提が崩れる3条件がある）。

### 3. `claude/CLAUDE.md` の扱い

AGENTS.md は「`claude/CLAUDE.md`（配布物）は指示が無い限り編集しない」と定めているが、
**今回は人間が明示的に発動条件の設置を求めているので編集してよい。**

ただし:

- **既存内容（個人の口調設定）を壊さないこと。** 追記であって置換ではない
- ルート `CLAUDE.md` / `AGENTS.md`（このリポジトリを開発するためのルール）とは**別物**である。
  混同しない（AGENTS.md「3つの領域（混同しないこと）」参照）

### 4. 文面の書き方

- **エージェント非依存に書く。** Claude Code 固有の表現（`/` コマンドの綴りなど）が
  Codex / OpenCode 向けの文面に混ざらないようにする
- 「複数のPRに分かれる規模」の判断基準を、AI が実際に判断できる粒度で書く。抽象的すぎると
  発動しないし、具体的すぎると誤発動する
- **人間が「これは1本で済む」と言ったらそれに従う**ことを明記する（提案であって強制ではない）

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- **配布経路を新設した場合、その `$HOME` 側リンクが `deploy` で張られ `uninstall` で
  撤去されること。** 撤去漏れは過去に実際に起きた不具合（`uninstall.sh` から `ocw-meter` が
  漏れていた）であり、**この regression は必ず自動テストで固定する**
  （`tests/deploy_smoke.sh` に追加する）
- **既存ファイル（`~/.codex/AGENTS.md` のような人間の実ファイル）が退避されること。**
  配布経路を新設して既存の実ファイルを置き換える場合、**この regression は必ず自動テストで
  固定する**（`symlink_backup` の退避が効くこと）
- `claude/CLAUDE.md` の既存内容が保持されたまま追記されている
- `deploy-all.sh --dry-run` と `--status` が新しい配布先を正しく扱う

配布経路を新設せず文書の追記だけで済ませた場合は、上記のうち該当するものだけでよい。
各項目と test example を1対1対応させる必要はない。既存テストで同じ regression を
検出できる場合、新規テストは追加しない。

## 必須の検証コマンド

```bash
pre-commit run --all-files
./deploy-all.sh --dry-run
tests/deploy_smoke.sh
```

`tests/deploy_smoke.sh` は `HOME` を一時ディレクトリへ差し替えたサンドボックスで動く。
**実オペレーションの deploy（`deploy-all.sh` の素の実行）は禁止。**
`--rollback` と `--dev` も `--dry-run` 無しで実 `$HOME` に対して実行しない。

## 注意

- **linter の抑制ディレクティブや `.pre-commit-config.yaml` の除外追加を自分の判断で
  入れない**（AGENTS.md 最重要ルール）
- `docs/` に新規ファイルを追加したら `./tools/doc-id/doc-id assign` で採番し、
  地の文の言及にも DOC-ID を追記する
- 新しいツールディレクトリを足す場合は AGENTS.md「実装時の注意」の一元化の作法を
  全部踏むこと（`links_for_tool()` への arm 追加を忘れると `uninstall.sh` が静かに
  スキップする）
````

---

## 実装完了後の流れ（各孫共通・必須）

実装が完了したら、以下を**自律的に**実行すること:

1. PR を作成する。**PR の向き先は必ず `agent-handoff` にすること。`master` には絶対に出さない。**
2. `/pr-review-loop` を起動する（PR がない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. 承認されたら人間に「マージしてください」と依頼する

実装が終わったタイミングで止まらず、必ずここまでやりきること。

PR 説明の書き方は `docs/design/DOC-2608020715_プルリクエストの作法.md` に従うこと。

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `agent-handoff` から切ること**。
`master` から切ると PR の diff に傘ブランチ全体が混入してレビュー不能になる。
実装開始前に以下を必ず実行すること:

```
git checkout agent-handoff && git pull --rebase origin agent-handoff
git checkout -b <新しいブランチ名>
```
