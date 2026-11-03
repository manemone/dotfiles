# 計画書: claude-ds（DeepSeek）の費用を下げる

傘ブランチ: `ds-cost-down`
ターゲット: `master`

## 概要

claude-ds（Claude Code を DeepSeek の API で動かすラッパ `bin/claude-ds`）の費用が、している仕事のわりに高い。
2026-11-03 の実測では、費用の約8割が文脈 10万超の呼び出しから出ており、文脈が大きいまま何百回も呼び出していることが
主因だった。この傘で次の3つの手を打つ（人間が確定させた。背景2）。

1. **claude-ds の自動圧縮の位置を下げる（孫1）。** `CLAUDE_CODE_AUTO_COMPACT_WINDOW` を 786,432 から 20〜25万へ。
   self-compact を取りこぼしたときの安全網を、実際に効く位置へ置き直す
2. **self-compact の決まりを直す（孫2）。** 「1 PR につき多くて 3 回」の読み違えを無くし、回数で止める形・区切りの
   足りなさ・閾値を DeepSeek の実測で見直す。この規則は Claude の会話と共通なので、どこまで変えるかは人間に確かめる
3. **UI 確認のやり方を変える（孫3・孫4）。** deepseek-flash が画像を本当に読めているかを確かめたうえで、確認役を
   サブエージェントではなく別の会話（ペイン）として立てる仕組みを dotfiles に作り（孫3）、pixidex 側の頼み方を
   それに合わせる（孫4、他リポの孫）

> **本計画書は、相談の会話から渡された引き継ぎブリーフ（一時ファイル。転記後に削除済みで
> 参照できない前提で書く）を material として司令官が起草したものである。** ブリーフに
> 書かれていた問題意識・決定事項・既存の穴・実測値・制約・スコープ外・必須の検証ステップ・
> 孫分割の叩き台・分析に使ったスクリプト（付録A）は本計画書へ転記済みであり、以降はこの計画書が正典である。

## 孫ブランチ進捗

| 孫 | リポ | ブランチ | 内容 | 状況 |
|---|---|---|---|---|
| 1 | dotfiles | `dcd-01-autocompact-window` | `bin/claude-ds` の `CLAUDE_CODE_AUTO_COMPACT_WINDOW` を 20〜25万へ下げ、README の理由を実測に合わせて直す。サブエージェントに効くかを確かめる | ✅ PR #208 マージ済 |
| 2 | dotfiles | `dcd-02-self-compact-rules` | self-compact の決まり（pr-review-loop・umbrella-orchestrator の自動付与指示・`compact-reminder.sh`・ADR）を DeepSeek の実測で見直す。Claude にも効かせるかは人間に確かめる | ✅ PR #207 マージ済 |
| 3 | dotfiles | `dcd-03-ui-checker-pane` | deepseek-flash の画像読み取りを確かめ、UI 確認役を別の会話（ペイン）として立てる仕組みを作る | 🔄 実装中 |
| 4 | pixidex | `dcd-04-checker-request` | pixidex の「確かめ役」の頼み方（規約・現役の計画書の型・ADR）を孫3 の仕組みに合わせる | ⬜ 待機中 |

依存:

- 孫1・孫2・孫3 は**並列**（最初に同時に spawn する）。孫1 は `bin/claude-ds` と `bin/README.md`、孫2 は
  `skills/pr-review-loop/` `skills/umbrella-orchestrator/` `claude/hooks/compact-reminder.sh` とそのテスト・ADR、
  孫3 は `bin/ocw`（または `skills/pr-review-loop/`）と新しい ADR を主に触る。ぶつかりうるのは `bin/README.md` §3.2 の
  compact の閾値に触れる1文と `skills/pr-review-loop/SKILL.md` 程度。後からマージされる側が傘へ rebase で追随する
- 孫2 の閾値の見直しは孫1 の自動圧縮の位置と関係する（自動圧縮は self-compact より後に来る安全網であるべき。設計2）。
  孫2 は孫1 の完了を待たないが、孫1 が先にマージされていればその値を前提にし、まだなら「20〜25万のどこか」を前提にする
- 孫4 は**孫3 が傘にマージされてから** spawn する（孫3 の仕組みの使い方に合わせるため）。孫4 は pixidex の既定ブランチ
  `main` へ PR を出し、マージは人間が行う

## 関係するリポ

| 名前 | メインワークツリー | owner/name | 既定ブランチ |
|---|---|---|---|
| dotfiles | `/home/manemone/projects/dotfiles/master` | `manemone/dotfiles` | `master` |
| pixidex | `/home/manemone/projects/pixidex/main` | メインワークツリーで `gh repo view --json nameWithOwner -q .nameWithOwner` を叩いた値 | `main` |

pixidex は private のため、owner/name は値ではなく解決方法を書いた。状況の値も `pixidex#XX` と短い名前で書く。
規約の在処: dotfiles は `AGENTS.md`（作業別の索引の DOC を含む）、pixidex はそのリポの `AGENTS.md` / `CLAUDE.md`。

## ワークスペースラベル

接頭辞は `ocw label-prefix`（dotfiles では `dotfiles`、pixidex では `pixidex`）。

- 傘: `dotfiles :: claude-ds 費用削減`
- 孫1: `dotfiles :: claude-ds 費用削減 孫1 自動圧縮の位置を下げる`
- 孫2: `dotfiles :: claude-ds 費用削減 孫2 self-compact 規則の改訂`
- 孫3: `dotfiles :: claude-ds 費用削減 孫3 UI 確認役のペイン`
- 孫4: `pixidex :: claude-ds 費用削減 孫4 確かめ役の頼み方`

## 背景1: 問題意識（要約）

相談は ocw-meter の使用量の傾向から始まり、次の順で深まった（発言は要約。逐語は載せない）。

- DeepSeek が、している仕事のわりに費用がかさんでいる気がする。内訳を探ってほしい
- self-compact が効いていないのではないか。UI の確認が無駄に食っている気もする
- サブエージェントは self-compact できないので、UI 確認は確認役を別の会話として立てるのがよいのではないか
- UI 確認は全体の何割か、それ以外のセッションは何で食っているか、安くできるか
- Sonnet とドル単価で比べても意味がない（サブスクの枠内で使うため）。`[1m]` を外せるのかも疑問
- 自動圧縮を self-compact と同じように効かせればよいのでは。self-compact の回数制限がなぜあるのか分からない
- 打つべき手をまとめた結果のうち、自動圧縮の位置を下げる手は通常の Claude の会話にも影響するのではと確認し、
  claude-ds だけにしか効かないことを確かめたうえで、手1〜3をやると決めた（手4〔混む時間帯を避ける運用〕は対象外）

## 背景2: 人間が確定させた決定事項（覆さないこと）

1. **claude-ds の自動圧縮の位置を下げる。** `bin/claude-ds` の `CLAUDE_CODE_AUTO_COMPACT_WINDOW="786432"` を 20〜25万程度へ。
   `bin/README.md` §3.2 の「DeepSeek はキャッシュヒットが安く長い文脈のコストが響きにくいため公式値をそのまま採る」という
   理由も実測に合わせて直す。この環境変数は `bin/claude-ds` の `exec env` の中にしか無く、通常の `claude` の会話には
   影響しないことを相談中に確認済み（`claude/` 配布物・`settings.machine.json` にも無い）
2. **self-compact の決まり（`skills/pr-review-loop/SKILL.md`「区切りでの自己 compact」と ADR DOC-2610142337、
   `claude/hooks/compact-reminder.sh`）を直す。** 相談で挙がった中身:
   - 「1 PR につき多くて 3 回」が数えるのは実装途中（区切り(3)）の compact だけであることを、読み違えようのない書き方にする
   - 回数で止めるのをやめ、増分（前回の compact から文脈が○万増えたら可）等に変える案
   - 承認後に追加の直しが来たとき・指摘対応が長引いたときにも compact できる区切りを足す案
   - 閾値 200k → 150k の案（ただし 200k は Claude のログからの試算で決めた値なので、DeepSeek のログで測り直してから決める）
   - **この規則は Claude の会話と共通。** DeepSeek のときだけ変えるのか Claude も含めて変えるのかは未決。設計時に人間に確認する
3. **UI 確認のやり方を変える。**
   - まず deepseek-flash が画像を本当に読めているかを確かめる（背景4 の実測参照。疑いの段階）
   - 確認役をサブエージェントではなく別の会話（ペイン）として立てる案。Claude（Sonnet で十分）で起動できる・self-compact
     できる・人間が横から見られる、が利点
   - 確認は試行錯誤させず、撮影スクリプトと確認項目を渡して流させる形にする
   - 確認役の仕組みは dotfiles（`ocw` / `pr-review-loop` 等）、頼み方は pixidex 側の規約・計画書

あわせて確定していること:

- **Sonnet と DeepSeek をドル単価で比べない。** Sonnet はサブスクの枠内で使うので、比べるなら週の上限の減り方
- `[1m]` サフィックスは外さない方向（効くのは `CLAUDE_CODE_AUTO_COMPACT_WINDOW` のほう、と相談中に整理済み）

## 背景3: 既存の穴（相談の AI が 2026-11-03 に調べた事実）

- `bin/claude-ds` は自動 compact を約 786k に置いており、self-compact を取りこぼすと 30〜48万まで伸びる。サブエージェント
  （`CLAUDE_CODE_SUBAGENT_MODEL="deepseek-flash"`、`[1m]` なし）も 48万まで一度も圧縮されずに伸びた（786k の設定に
  掛からなかっただけと推測。未確認）
- ADR DOC-2610142337 §2.3 の上限 3 回は「compact 後は 60〜90k で、次に 200k を超えるまで間があくため通常は 3 回に届かない」が
  前提。DeepSeek は 5万→35万へ 30〜60分で戻るので前提が崩れている
- `pr-review-loop` は「指摘対応の修正の途中は行わない」「Phase 7（承認後）では行わない」ため、承認後に持ち主の感想で追加の
  直しが入った局面で区切りが無い
- `ocw self-compact` は実装役のペインにしか打てず、サブエージェントには届かない
- UI 確認役の使い方は pixidex の計画書・ADR にあり（「確かめ役」の記述。下の一覧）、dotfiles 側に確認役の仕組みは無い。
  一覧は pixidex（別リポ）の DOC-ID なので、dotfiles の doc-id の検査に掛からないようコードブロックに置く:

  ```text
  pixidex docs/planning/   DOC-2610290939 DOC-2611012121 DOC-2610200307 DOC-2610290943 DOC-2611012120
  pixidex docs/adr/        DOC-2610291230
  pixidex docs/reference/  DOC-2610200344
  ```

## 背景4: 実測値

### 4.1 ブリーフに書かれていた実測

測定日 2026-11-03。データ源は ocw-meter のストア（`~/.local/state/ocw-meter/events/*.jsonl`）と会話ログ
（`~/.claude/projects/*/<session>.jsonl` とその `subagents/`）。費用は価格表 `bin/prices/deepseek-2026-09-10.json`
（混む時間帯 UTC 01–04・06–10 は 2倍）からの見積もりで請求額ではない。「今日」は 2026-11-02T15:00Z（JST 11/03 0時）以降。
再現手順は付録A。

**全体（今日、DeepSeek 22セッション、約 $9.1〜9.5）**

- 種類別: キャッシュ読み直し $4.80（53%）、出力 $2.98（33%）、キャッシュミス入力 $1.32（14%）
- API 呼び出し 7,734回、1回の平均文脈 約17万。出力 300トークン未満の呼び出しが 4,048回
- 文脈 10万超の呼び出しが費用の約8割。混む時間帯の分 $2.82
- 役割別: DeepSeek の費用はすべて implementer
- 作業別: コードを読む $3.52（37%・3,433回）、書く $1.91（20%）、UI 確認 $1.75（18〜19%）、待ち・連絡 $0.74（8%）、
  テスト・lint $0.68（7%）、git・PR $0.48（5%）。1回あたりの費用はどれも $0.001 前後で、差は回数
- 直近1週間（26セッション $11.80）では UI 確認 $1.93（16%）
- Read のうち 43% は同じセッションで既に開いたファイルの再読（`gen_trial.js` 29回など）
- 実装役セッション1本あたりの呼び出し回数の中央値（10/14以降）: Sonnet 80回（209本）、deepseek-flash 257回（41本）。
  1回の平均文脈はどちらも 13.5〜14万（仕事の大きさの違いを揃えていない荒い比較）

**最も高かった pixidex `dp-08-qa`（セッション c7d0dc27、$2.90）**

- 本体は self-compact を 3回（370k→52k、254k→49k、372k→63k）。3回目はレビュー待ちの compact
- その後 JST 19:30〜20:14 にフックの差し込みが6回あったが、本人が見送った: 修正の途中だから（3回）、「1 PR につき多くて
  3 回」に達したから（3回。うち2回はレビュー依頼直後で上限の対象外＝読み違え。本人は「計画書の上限」と書いており、
  pixidex の計画書側の書き方は未確認）。JST 20:16 に人間の指示で compact（364k→56k）
- 06:19Z に一度承認 → 持ち主の感想で 2回目の直し → その間ずっと伸びた
- UI 確認のサブエージェント（`general-purpose`、総当たりの独立した確かめ役）1本が 464回・$1.12、文脈 0→48万で圧縮ゼロ。
  node で撮影 78回、curl 74回、grep 106回、スクショ Read 37回。JST 11:04〜12:36（料金 2倍の時間帯）
- **スクショ1枚の Read で増えた文脈は中央値 約1,073トークン**（1280幅で約777）。deepseek-flash が画像を実際に見ていない
  疑い（未確認）

**試算（今日の分、圧縮後 55k に戻り、要約出力 8k を加算する単純モデル。圧縮後の読み直し増は含めないので甘め）**

- 今のまま $9.53 → 250k で圧縮 $8.51（11%減）、200k $8.09（15%減）、150k $7.63（20%減）、120k $7.53（21%減）
- 混む時間帯を全部避ける $8.12（15%減）。150k 圧縮＋時間帯回避 $6.58（31%減）

**週の上限（Claude サブスク）**: 10/04〜 100%、10/11〜 90%、10/18〜 61%、10/25〜 98%。今週（11/01〜）52時間時点 28%、
リセット時点の見込み 約86%

### 4.2 司令官が確かめたこと（2026-11-03、master 86943bc、このマシン）

- `bin/claude-ds` の `exec env` に `ANTHROPIC_MODEL="deepseek-flash[1m]"`（OPUS / SONNET の既定も同じ）、
  `CLAUDE_CODE_SUBAGENT_MODEL="deepseek-flash"`、`CLAUDE_CODE_AUTO_COMPACT_WINDOW="786432"` がある。`bin/README.md` §3.2 の
  箇条（`CLAUDE_CODE_AUTO_COMPACT_WINDOW=786432` の行）に、問題の理由の文がある
- 「1 PR につき多くて 3 回」の書き写しは dotfiles では `skills/pr-review-loop/SKILL.md`「区切りでの自己 compact（実装側のみ）」、
  `skills/umbrella-orchestrator/SKILL.md` §3.2 の自動付与指示（同じリポ用・他リポ用の2か所）、ADR DOC-2610142337 にある。
  pixidex では過去の計画書の孫用プロンプト（例: 背景3 の一覧の先頭の計画書や、LoRA の始動の計画書）が自動付与指示をそのまま写している。
  dp-08-qa の実装AIが「計画書の上限」と書いたのはこの写しを読んだためと思われる
- `claude/hooks/compact-reminder.sh` は `OCW_ROLE=implementer` のときだけ動き、閾値 `THRESHOLD = 200000`、区切り
  （`git commit` / `git push` / `gh pr create` / `herdr agent prompt` / `SendMessage`）の直後に1回、それ以外は閾値超えの
  最初と 50k 増えるごとに差し込む。差し込みの文面に「承認後の報告は区切りでない」「指摘対応の修正の途中は区切りでない」が
  入っている。テストは `tests/compact_reminder_test.sh`
- このマシンの実装役・レビュー役の既定は `OCW_IMPLEMENTER_COMMAND`=Sonnet、`OCW_REVIEWER_COMMAND`=Opus（dotfiles の孫は
  Claude で動く）。DeepSeek の費用が出ているのは主に pixidex の実装役

## 決定的な制約（孫は全部守ること）

- dotfiles `AGENTS.md` の最重要ルール（`master` を書き換える操作は人間だけ、など）
- `claude/CLAUDE.md`（配布物）は指示が無い限り編集しない
- deploy スクリプトを人間の指示なしに実行しない。配るのは人間（マージ後に `deploy-all.sh`）
- **PUBLIC リポ: リポの文書・PR 本文に人間の発言を逐語で書かない（要約する）**
- `docs/` 新規は `DOC-DOCID_PLACEHOLDER_<名前>.md` で作り `./tools/doc-id/doc-id assign` で採番。地の文で文書に触れるときは
  DOC-ID を明示
- self-compact 規則の変更は Claude の会話にも効く（範囲は未決。孫2 が人間に確認する）
- 確認役を Claude で動かす場合、Sonnet の消費は週の上限に効く（ドルでは比べない）
- pixidex（private）の内容を dotfiles（public）の文書・PR に必要以上に書き写さない（pixidex の文書は DOC-ID とパスで指す）

## スコープ外

- 手4: 混む時間帯を避ける運用（仕組み化しない）
- `[1m]` サフィックスを外すこと
- deepseek-flash の手数（呼び出し回数）そのものを減らすこと（再読 43% もこの傘では扱わない）
- 待ち・連絡（8%）の削減
- ocw-meter の残高表示（#206 でマージ済み）

## 必須の検証ステップ

- 変更したファイルに `pre-commit run --files <path>`（新規・大幅変更の時点で）
- `bin/` を変えたら `python3 -m unittest discover -s bin/tests -v`
- デプロイ関連のシェルを変えたら `tests/deploy_smoke.sh`
- `claude/hooks/compact-reminder.sh` を変えたら `bash tests/compact_reminder_test.sh`（bash 用。`sh` で呼ぶと `pipefail` で落ちる）
- `docs/` 新規は doc-id 採番、`./tools/doc-id/doc-id verify`
- pixidex 側はそのリポの `AGENTS.md` の手順に従う
- **全孫のマージと人間の配布のあと**、ocw-meter で 1日分を見比べ、試算どおり下がったか確かめる（試算は甘め。付録A の
  `sim.py` / `breakdown.py` / `ui_share.py` を同じ条件で回す）。これは傘の最終 PR の後の宿題として進行記録に残す

## テスト方針（dotfiles AGENTS.md「テスト方針」と DOC-2610150520-a に従う）

- 孫1 は設定値と文書の変更で、新しい自動テストは要らない（既存の `bin/tests` と pre-commit が通ればよい）
- 孫2 は `compact-reminder.sh` の振る舞い（閾値・区切り・間引き・対象の役割）を変えるなら、変えた振る舞いを
  `tests/compact_reminder_test.sh` の既存 scenario に足す形で固定する。スキル本文の文言だけの変更にテストは要らない
- 孫3 は `bin/ocw` にサブコマンドや引数を足すなら、その引数解釈と、他のペインに誤って送らないこと（宛先の取り違え）を
  既存のテストの流儀で守る。画像読み取りの確認は手で行う実験で、自動テストにしない

## 設計0: 全孫に共通の方針（司令官が決めた）

1. **測ってから決める。** 閾値・位置の値は、付録A のスクリプト（または同等のもの）で DeepSeek のログから測り、値と測り方を
   ADR に残す。Claude のログからの試算だけで決めた値（200k など）を DeepSeek にそのまま当てはめない
2. **費用の比べ方。** DeepSeek はドル、Claude は週の上限の減り方で見る。両者をドルで比べない
3. **通常の Claude の会話に効くかを、変更ごとに明記する。** PR 本文と ADR に「Claude の会話に効く／効かない」を書く

## 設計1: 自動圧縮の位置を下げる（孫1）

- 値は 20〜25万の範囲で、孫が付録A の `sim.py` の考え方（圧縮後に戻る大きさ・要約出力）と、self-compact の閾値（今は 200k。
  孫2 が見直す）との関係から決める。**自動圧縮は self-compact より後に来る安全網**であり、区切りで self-compact する機会を
  奪うほど低くしない（例: self-compact が 200k なら、自動圧縮は 200k ちょうどより少し上）。孫2 の見直し後に値の再調整が
  要るなら、孫2 側で行う
- `CLAUDE_CODE_AUTO_COMPACT_WINDOW` の意味（ウィンドウの大きさとして扱われ、その一定割合で圧縮が始まるのか、値そのもので
  始まるのか）を公式の文書・変更履歴で確かめ、狙った位置で圧縮が始まる値を入れる
- **サブエージェントに効くか**: 公式の文書で分かる範囲を確かめる。分からなければ「未確認」と書き、配布後に会話ログの
  `subagents/` の圧縮の有無で確かめる手順を ADR に残す（高い実験はしない）
- `bin/README.md` §3.2 の理由の文を、背景4 の実測（費用の約8割が 10万超の呼び出し、キャッシュ読み直しが 53%）に合わせて直す
- 以前の判断（公式値をそのまま採る）を覆すので、ADR を1本足す

## 設計2: self-compact の決まりを直す（孫2）

1. **まず測る。** 付録A の `sim.py` を土台に、DeepSeek の実装役の会話ログで、閾値（120k / 150k / 200k / 250k）と回数の扱い
   （上限 3 回 / 上限なし＋増分制）ごとの費用を試算する。Claude（Sonnet）の実装役のログでも同じ形で、週の上限への効き方の
   目安を出す（ドルで比べない）
2. **人間に確かめる（必須）。** 測った結果を添えて、次を人間に聞く（実装AIのペインで質問すれば人間が答える）。
   答えを待たずに規則を書き換えない:
   - 規則の変更を Claude の会話にも効かせるか、DeepSeek のときだけにするか
   - DeepSeek だけにする場合の見分け方（例: `bin/claude-ds` が渡す環境変数をフックが読む。フックは Claude Code の子プロセス
     なので `exec env` の値を受け継ぐはず。確かめてから提案する）
3. **直す中身**（人間の答えの範囲で）:
   - 「1 PR につき多くて 3 回」が数えるのは区切り(3)だけであることを、読み違えようのない書き方にする（書き写し先すべて:
     `skills/pr-review-loop/SKILL.md`、`skills/umbrella-orchestrator/SKILL.md` §3.2 の自動付与指示2か所、フックの文面）
   - 回数で止める形を、増分（前回の compact から文脈が一定以上増えたら可）などに変えるか
   - 承認後に追加の直しが来たとき・指摘対応が長引いたときの区切りを足すか（例: 追加の直しを push して再レビューを依頼した直後）
   - 閾値（200k を据え置くか、150k などへ）
   - `claude/hooks/compact-reminder.sh` の文面・閾値を合わせ、`tests/compact_reminder_test.sh` を直す
4. ADR を1本足し、ADR DOC-2610142337（と関係するなら DOC-2610131214・DOC-2610142359）との関係（どこを置き換えたか）を書く。
   旧 ADR の扱いは `docs/README.md` の ADR の約束に従う
5. 孫1 の自動圧縮の位置と矛盾しないこと（設計1）。閾値を変えたら `bin/README.md` §3.2 の閾値に触れる文も合わせる

## 設計3: UI 確認役を別の会話として立てる（孫3）

1. **画像読み取りの確認（最初にやる）。** 文字や図形の中身を推測できない画像（例: ランダムな英数字と色の付いた図形）を作り、
   claude-ds（deepseek-flash）と Claude の両方に Read させて説明させ、正しく読めたかを比べる。あわせて DeepSeek の
   Anthropic 互換 API の公式の文書で、画像の入力が扱われるかを確かめる。費用は小さく抑える（短い会話で1〜2枚）。
   結果は ADR に残す
2. **仕組み。** 実装役が UI 確認を、サブエージェントではなく別の会話（ペイン）の確認役に頼めるようにする。要件:
   - 確認役は Claude（既定は Sonnet）で起動でき、起動コマンドは環境変数で上書きできる（`OCW_*_COMMAND` の流儀）
   - 確認役は self-compact できる（ペインを持つ会話なので `ocw self-compact` が届く）。必要なら確認役にも self-compact の
     区切りを決める（孫2 の規則と矛盾しないように。孫2 が未マージなら現行の規則に合わせ、PR 本文に書く）
   - 人間が横から見られる（実装役と同じ Herdr ワークスペースにペインを足す、など）
   - **試行錯誤させない。** 実装役が「撮影スクリプト」と「確認項目」をファイルで渡し、確認役はそれを流して結果をファイルと
     短い報告で返す。確認役が自分で撮影方法を探し回らない形にする
   - 置き場所（`ocw` のサブコマンド／`pr-review-loop` の節／新しいスキル）は孫が比べて選び、ADR に理由を残す。既存の
     `ocw -H` のペイン構成・`ocw agent` の起動行の仕組みを流用できるならそれを優先する
   - 新しいツールディレクトリ・スキル・配布先を足すなら DOC-2610150520-c に従う（`links_for_tool()` / `skill_links()` の足し忘れ）
3. 画像読み取りの結果が「deepseek-flash は画像を見ていない」なら、確認役を Claude で動かすことは必須であり、ADR にその根拠を
   書く。「見えている」なら、確認役を DeepSeek で動かす選択肢も残し、既定をどちらにするかを理由とともに書く

## 設計4: pixidex の確かめ役の頼み方を合わせる（孫4、他リポ）

- 孫3 の仕組みの使い方（ADR と使い方の文書）を読み、pixidex の現役の規約・計画書の型・ADR のうち、UI 確認を
  サブエージェントの確かめ役に頼む書き方をしている箇所を、孫3 の仕組みで頼む形に直す。対象の候補は背景3 の一覧（pixidex の DOC-ID）。**完了済みの計画書は記録なので書き換えない**（現役のもの・
  これから使う型・規約だけ）
- 確かめ役に渡す「撮影スクリプト」と「確認項目」の置き場所と書き方を pixidex 側で決める
- pixidex に「1 PR につき多くて 3 回」の書き写しが現役の規約・テンプレートにあれば、孫2 の新しい書き方に合わせる
  （孫2 が未マージなら触らず、PR 本文にそう書く）
- PR 本文に、この計画書（dotfiles の `docs/planning/` の本計画書の DOC-ID）と孫3 の PR へのリンクを書く

## 孫ブランチ分割の叩き台（ブリーフより転記。採った分割は上の進捗テーブル）

ブリーフの叩き台（相談の AI が出したもので、司令官が再設計してよいとされていた）:

- 孫A（dotfiles）: `bin/claude-ds` の `CLAUDE_CODE_AUTO_COMPACT_WINDOW` を下げ、README の理由を直す。サブエージェントにも効くかを確かめる
- 孫B（dotfiles）: `pr-review-loop` の self-compact 規則・`compact-reminder.sh`・ADR の改訂（上限の文言、増分制、区切りの追加、
  閾値の再測定）。Claude にも効くかの判断を人間に仰ぐ
- 孫C（dotfiles）: deepseek-flash の画像読み取りの確認 → 結果に応じて確認役ペインの仕組み（`ocw` / `pr-review-loop` 等）
- 孫D（pixidex）: 確かめ役の頼み方を孫C の仕組みに合わせる（計画書・ADR・規約）。孫C に依存

司令官の判断: A→孫1、B→孫2、C→孫3、D→孫4 とそのまま採った。孫3 の画像読み取りの確認は独立の PR にするほど大きくなく、
仕組みの既定（Claude で動かすか）を決める材料なので、同じ孫の最初の手順にした。順序は孫1〜3 を並列、孫4 は孫3 の後。

## 進行記録

（司令官が運用中に分かったこと・人間の決定をここに追記する）

- 2026-11-03: 計画書を起草した。傘は `origin/master`（86943bc）から切られている。孫1〜3 を並列で spawn する。孫4 は孫3 のマージ後
- 2026-11-03: 孫1〜3 を spawn した（`ocw -H --no-commander`、base-ref は `ds-cost-down`）。ブリーフと分析スクリプトは転記後に削除した（スクリプトは付録A）
- 2026-11-03: 人間の決定: self-compact の回数上限の緩和は、DeepSeek だけでなく通常の Claude の会話にも適用してよい（設計2 の2 の「Claude にも効かせるか」への回答）。閾値の変更と区切りの追加はこの回答の範囲外で、孫2 が測定結果を添えて改めて確かめる。孫2 へ中継済み
- 2026-11-03: 孫2 の PR #207 を司令官がマージした。閾値 200k→150k、実装途中の回数上限を増分制に置き換え、Claude の会話にも効く（ADR DOC-2611032102。閾値の変更も孫2 が人間に確認済み）。傘で unittest（465件）・`pre-commit run --all-files`・`bash tests/compact_reminder_test.sh`・`doc-id verify` が通った。孫1 の自動圧縮の位置は 150k より上に置くこと
- 2026-11-03: 訂正: 人間が Claude にも効かせてよいとしたのは回数の上限（増分制）だけだった。閾値 150k は claude-ds のときだけにし、それ以外の Claude は 200k に戻した（フックは `ANTHROPIC_BASE_URL` で見分ける。司令官が傘へ直接コミット。ADR DOC-2611032102 §3 の 4 を訂正）
- 2026-11-03: 孫1 の PR #208 を司令官がマージした。claude-ds の `CLAUDE_CODE_AUTO_COMPACT_WINDOW` を 786432→233000（ADR DOC-2611032100）。傘で unittest・`pre-commit run --all-files`・`bash tests/compact_reminder_test.sh`・`doc-id verify` が通った

## 孫1用プロンプト:

````markdown
# 傘ブランチ: ds-cost-down
# 孫ブランチ: dcd-01-autocompact-window
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/ds-cost-down/docs/planning/DOC-2611032048_ds-cost-down_計画.md`

**まず計画書の「概要」「背景2」「背景3」「背景4」「決定的な制約」「スコープ外」「必須の検証ステップ」「テスト方針」「設計0」「設計1」
「進行記録」を読むこと。** 続けて dotfiles の `AGENTS.md` の作業別の索引から、コミット前（DOC-2610150520）・実装時の注意
（DOC-2610150520-c）を読む。

## 実装開始前の必須手順

`ocw` がすでに `dcd-01-autocompact-window` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/ds-cost-down` の
先端から切られていることを確かめる（`git pull` は使わない）。

## やること

1. Claude Code の公式の文書・変更履歴で `CLAUDE_CODE_AUTO_COMPACT_WINDOW` の意味（どの位置で自動圧縮が始まるか）と、
   サブエージェントに効くかを確かめる（計画書 設計1）
2. 値を 20〜25万の範囲で決め、`bin/claude-ds` を直す。self-compact の閾値（いまは 200k）との関係を考える（設計1）
3. `bin/README.md` §3.2 の該当の箇条（理由の文）を、計画書 背景4 の実測に合わせて直す。通常の `claude` の会話には効かない
   ことも1文で残す
4. ADR を `docs/adr/` に足す（`DOC-DOCID_PLACEHOLDER_<名前>.md` で作って `./tools/doc-id/doc-id assign <path>`）。
   書くこと: 以前の判断（公式値をそのまま採る）と、それを覆す実測（背景4 の要約。費用の約8割が 10万超の呼び出し等）、
   選んだ値と比べた値（付録A の試算）、環境変数の意味の出典、サブエージェントに効くか（分からなければ未確認とし、配布後に
   会話ログの `subagents/` で確かめる手順）、Claude の会話に効かないこと
5. deploy はしない（配るのは人間）。PR 本文に「マージ後に人間が `deploy-all.sh` で配ると効く」と書く

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- `bin/claude-ds` がシェルとして正しく、既存の pre-commit の検査（shellcheck / shfmt）を通る
- `bin/claude-ds` の他の環境変数を消したり変えたりしていない

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。
この孫では新しい自動テストは要らない（計画書「テスト方針」）。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --all-files
python3 -m unittest discover -s bin/tests -v
./tools/doc-id/doc-id verify
```

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `ds-cost-down` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** `/pr-review-loop` の手順にマージへ進む記述があっても実行しない
   （孫が人間のフィードバック前に勝手にマージするのを防ぐため。マージは傘の司令官が行う）
5. 最終報告を書き終えたら、最後の行動として、司令官が spawn の送信文で渡した司令官の Herdr ペインへ
   承認を報告する（渡されていなければ報告せず、人間に「承認済み。マージは司令官（または人間）が行う」と伝えて止まる）。
   送り方は umbrella-orchestrator スキル §5「AI間送信手順（二段構え）」に従う。本文は
   「孫1 `dcd-01-autocompact-window` の PR #<番号> が HEAD <短縮SHA> で承認されました。マージをお願いします。」
   だけにする。報告は1回だけ。送れなくても再送せず、送れなかったことを人間に1行伝えて止まる

なお `/pr-review-loop` は、レビューを依頼した直後の区切りで文脈が大きければ `ocw self-compact` で
自分を compact する（その手順は pr-review-loop 側。使えなければ何もしない）。compact の後は、
復帰メモに従ってレビュー待ちに戻り、この「実装完了後の流れ」を最後まで続けること。
実装の途中でも、検証が通ってコミットした直後の区切りで、文脈が
200,000 トークンを超えていれば `ocw self-compact` で自分を compact してよい（WIP のコミットは
区切りでない。指摘対応の修正の途中は対象外。1 PR につき多くて 3 回。ADR DOC-2610142337）。
測り方は `/pr-review-loop` の「区切りでの自己 compact（実装側のみ）」の手順1のコマンドと同じ（その節の (3) の項だけを読めばよい。
手順の「Phase 3 へ進む」は実装途中には当てはまらない）。復帰メモ（リポの外の一時ファイル）には、計画書のパスと孫の節・
済んだこと（コミットの一覧）・作業中に下した判断とその理由・残り・次の一手・検証コマンド・実装途中の compact の回数を書き、
先頭に「計画書の続きから実装を再開する。レビュー待ちではない」と書く。コマンドを実行したらそのターンを終える。
使えない・拒否・失敗なら何もせず実装を続ける（人間に提案もしない）。
実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## 大きい出力を文脈へ流し込まない（実装中ずっと）

文脈の膨張は、1k〜20k字級の出力の積み重ねと、自分で書く長い出力で起きる。次を守ること:
- ファイルを `cat` / `sed -n` で丸ごと読まず、`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む
- 約100行・5,000字を超えそうな出力（テスト・分析・ログ・`git diff`・JSON）は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る
- 既存の長いファイルや、繰り返し直して実行するスクリプトを Write / heredoc で丸ごと書き直さない。一度ファイルに置き、変更は Edit の差分で行う（新規ファイルを最初に1回書くのは構わない）

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `ds-cost-down` から切ること**。master から切ると PR の diff に傘ブランチ全体が
混入してレビュー不能になる。`ocw` が `origin/ds-cost-down` から切ったワークツリーを用意済みなので、
上の「実装開始前の必須手順」で確かめるだけでよい（`git pull` は使わない）。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
人間の発言を逐語で書かない（PUBLIC リポ。要約する）。
````

## 孫2用プロンプト:

````markdown
# 傘ブランチ: ds-cost-down
# 孫ブランチ: dcd-02-self-compact-rules
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/ds-cost-down/docs/planning/DOC-2611032048_ds-cost-down_計画.md`

**まず計画書の「概要」「背景2」「背景3」「背景4」「決定的な制約」「スコープ外」「必須の検証ステップ」「テスト方針」「設計0」「設計1」
「設計2」「進行記録」「付録A」を読むこと。** 続けて dotfiles の `AGENTS.md` の作業別の索引から、テストを足す判断基準
（DOC-2610150520-a）・コミット前（DOC-2610150520）・実装時の注意（DOC-2610150520-c）・シェルスクリプトコーディング方針
（DOC-2608020715-a）を読む。ADR DOC-2610142337・DOC-2610131214・DOC-2610142359 も読む。

## 実装開始前の必須手順

`ocw` がすでに `dcd-02-self-compact-rules` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/ds-cost-down` の
先端から切られていることを確かめる（`git pull` は使わない）。

## やること

1. **測る（設計2 の1）。** 付録A の `sim.py` を土台に、閾値と回数の扱いごとの試算を DeepSeek の実装役の会話ログで出す。
   Claude（Sonnet）の実装役のログでも同じ形で、週の上限への効き方の目安を出す（ドルで比べない）。スクリプトは
   リポの外（`mktemp -d`）に置き、結果だけを ADR に残す
2. **人間に確かめる（設計2 の2。必須）。** 測った結果を短くまとめ、次を人間に質問する。答えが来るまで規則を書き換えない:
   - 規則の変更を Claude の会話にも効かせるか、DeepSeek のときだけにするか
   - DeepSeek だけにするなら、その見分け方（実際に確かめた案を添える）
   - 閾値・回数の扱い・区切りの追加について、測った結果からの提案
3. 人間の答えの範囲で、設計2 の3 の中身を直す（書き写し先すべて。フックとそのテストも）
4. ADR を `docs/adr/` に足す（`DOC-DOCID_PLACEHOLDER_<名前>.md` で作って `./tools/doc-id/doc-id assign <path>`）。測り方・結果・
   人間の決定（要約）・旧 ADR のどこを置き換えたか・Claude の会話に効くか
5. 孫1（自動圧縮の位置）がマージ済みならその値と矛盾しないことを確かめ、閾値を変えたら `bin/README.md` §3.2 の
   閾値に触れる文も合わせる

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- `compact-reminder.sh` が、変えた閾値・区切り・回数の扱いのとおりに差し込む／差し込まない（変えた振る舞いだけ）
- `compact-reminder.sh` が、対象外の役割（司令官・レビュワー・未設定）・壊れた入力でエージェントを止めない（既存のまま）
- DeepSeek のときだけにすると決まった場合、Claude の会話では従来どおりに振る舞う

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --all-files
bash tests/compact_reminder_test.sh
./tools/doc-id/doc-id verify
```

デプロイ関連のシェル（`shared/helpers.sh` など）を変えた場合は `sh tests/deploy_smoke.sh` も。

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `ds-cost-down` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** `/pr-review-loop` の手順にマージへ進む記述があっても実行しない
   （孫が人間のフィードバック前に勝手にマージするのを防ぐため。マージは傘の司令官が行う）
5. 最終報告を書き終えたら、最後の行動として、司令官が spawn の送信文で渡した司令官の Herdr ペインへ
   承認を報告する（渡されていなければ報告せず、人間に「承認済み。マージは司令官（または人間）が行う」と伝えて止まる）。
   送り方は umbrella-orchestrator スキル §5「AI間送信手順（二段構え）」に従う。本文は
   「孫2 `dcd-02-self-compact-rules` の PR #<番号> が HEAD <短縮SHA> で承認されました。マージをお願いします。」
   だけにする。報告は1回だけ。送れなくても再送せず、送れなかったことを人間に1行伝えて止まる

なお `/pr-review-loop` は、レビューを依頼した直後の区切りで文脈が大きければ `ocw self-compact` で
自分を compact する（その手順は pr-review-loop 側。使えなければ何もしない）。compact の後は、
復帰メモに従ってレビュー待ちに戻り、この「実装完了後の流れ」を最後まで続けること。
実装の途中でも、検証が通ってコミットした直後の区切りで、文脈が
200,000 トークンを超えていれば `ocw self-compact` で自分を compact してよい（WIP のコミットは
区切りでない。指摘対応の修正の途中は対象外。1 PR につき多くて 3 回。ADR DOC-2610142337）。
測り方は `/pr-review-loop` の「区切りでの自己 compact（実装側のみ）」の手順1のコマンドと同じ（その節の (3) の項だけを読めばよい。
手順の「Phase 3 へ進む」は実装途中には当てはまらない）。復帰メモ（リポの外の一時ファイル）には、計画書のパスと孫の節・
済んだこと（コミットの一覧）・作業中に下した判断とその理由・残り・次の一手・検証コマンド・実装途中の compact の回数を書き、
先頭に「計画書の続きから実装を再開する。レビュー待ちではない」と書く。人間に確かめた答えも復帰メモに必ず書く。
コマンドを実行したらそのターンを終える。使えない・拒否・失敗なら何もせず実装を続ける（人間に提案もしない）。
実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## 大きい出力を文脈へ流し込まない（実装中ずっと）

文脈の膨張は、1k〜20k字級の出力の積み重ねと、自分で書く長い出力で起きる。次を守ること:
- ファイルを `cat` / `sed -n` で丸ごと読まず、`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む
- 約100行・5,000字を超えそうな出力（テスト・分析・ログ・`git diff`・JSON）は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る
- 既存の長いファイルや、繰り返し直して実行するスクリプトを Write / heredoc で丸ごと書き直さない。一度ファイルに置き、変更は Edit の差分で行う（新規ファイルを最初に1回書くのは構わない）

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `ds-cost-down` から切ること**。master から切ると PR の diff に傘ブランチ全体が
混入してレビュー不能になる。`ocw` が `origin/ds-cost-down` から切ったワークツリーを用意済みなので、
上の「実装開始前の必須手順」で確かめるだけでよい（`git pull` は使わない）。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
人間の発言を逐語で書かない（PUBLIC リポ。要約する）。
````

## 孫3用プロンプト:

````markdown
# 傘ブランチ: ds-cost-down
# 孫ブランチ: dcd-03-ui-checker-pane
# ターゲット: master（傘経由）

計画書: `/home/manemone/projects/dotfiles/ds-cost-down/docs/planning/DOC-2611032048_ds-cost-down_計画.md`

**まず計画書の「概要」「背景2」「背景3」「背景4」「決定的な制約」「スコープ外」「必須の検証ステップ」「テスト方針」「設計0」「設計3」
「設計4」「進行記録」を読むこと。** 続けて dotfiles の `AGENTS.md` の作業別の索引から、テストを足す判断基準
（DOC-2610150520-a）・コミット前（DOC-2610150520）・実装時の注意（DOC-2610150520-c）・シェルスクリプトコーディング方針
（DOC-2608020715-a）を読む。`ocw` の使い方は `ocw help <topic>` で調べる。

## 実装開始前の必須手順

`ocw` がすでに `dcd-03-ui-checker-pane` ブランチのワークツリーを用意しているので、
`git fetch origin` と `git log --oneline -3` で、そのブランチが `origin/ds-cost-down` の
先端から切られていることを確かめる（`git pull` は使わない）。

## やること

1. **画像読み取りの確認（設計3 の1。最初にやる）。** 中身を推測できない画像を作り、claude-ds（deepseek-flash）と Claude の
   両方に読ませて比べる。DeepSeek の Anthropic 互換 API の公式の文書で画像の扱いも確かめる。費用は小さく（短い会話で1〜2枚）。
   実験の会話は使い捨て（`claude -p` など）にし、結果（読めたか・根拠・試した手順）をメモに残す
2. **仕組みの設計（設計3 の2・3）。** 置き場所の候補を比べて選ぶ。pixidex の確かめ役の使われ方（計画書 背景3 の一覧の文書を
   `/home/manemone/projects/pixidex/main` で読むだけ。書き換えない）を読み、何を渡し何を返せば足りるかを確かめる
3. 仕組みを実装する。使い方の文書（README またはスキル本文）を書く
4. ADR を `docs/adr/` に足す（`DOC-DOCID_PLACEHOLDER_<名前>.md` で作って `./tools/doc-id/doc-id assign <path>`）。画像読み取りの
   結果、置き場所の比較と選択、既定のモデル（Claude で動かす根拠）、Sonnet の消費が週の上限に効くこと、Claude の会話に効くか
5. 孫4（pixidex 側の頼み方）が読む前提で、使い方の文書に「実装役から頼む手順」「渡すファイルの形」「返ってくるもの」を
   具体的に書く。pixidex のことは dotfiles の文書に必要以上に書き写さない（private のため）

## 検証方針

以下の重要な behavior / regression risk が、自動テストまたは既存テストによって
保護されていること。

- 足した `ocw` のサブコマンド・引数（足した場合）が、想定どおりに解釈され、誤った引数で既存の動作を壊さない
- 確認役への依頼が、意図しないペイン（実装役自身・別のワークスペース）へ送られない
- 新しいスキル・配布物を足した場合、`uninstall.sh` / `--status` から漏れない（`links_for_tool()` / `skill_links()`）

各項目と test example を1対1対応させる必要はない。
複数の条件を1つの scenario で検証してよい。
既存テストで同じ regression を検出できる場合、新規テストは追加しない。
画像読み取りの確認は手で行う実験で、自動テストにしない。

## 実行すべき検証コマンド（省略しない）

```bash
pre-commit run --all-files
python3 -m unittest discover -s bin/tests -v
./tools/doc-id/doc-id verify
```

デプロイ関連のシェル（`shared/helpers.sh`・`*/deploy.sh` など）を変えた場合は `sh tests/deploy_smoke.sh` も。

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は必ず `ds-cost-down` にすること。master には絶対に出さない。**
2. `/pr-review-loop` を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** `/pr-review-loop` の手順にマージへ進む記述があっても実行しない
   （孫が人間のフィードバック前に勝手にマージするのを防ぐため。マージは傘の司令官が行う）
5. 最終報告を書き終えたら、最後の行動として、司令官が spawn の送信文で渡した司令官の Herdr ペインへ
   承認を報告する（渡されていなければ報告せず、人間に「承認済み。マージは司令官（または人間）が行う」と伝えて止まる）。
   送り方は umbrella-orchestrator スキル §5「AI間送信手順（二段構え）」に従う。本文は
   「孫3 `dcd-03-ui-checker-pane` の PR #<番号> が HEAD <短縮SHA> で承認されました。マージをお願いします。」
   だけにする。報告は1回だけ。送れなくても再送せず、送れなかったことを人間に1行伝えて止まる

なお `/pr-review-loop` は、レビューを依頼した直後の区切りで文脈が大きければ `ocw self-compact` で
自分を compact する（その手順は pr-review-loop 側。使えなければ何もしない）。compact の後は、
復帰メモに従ってレビュー待ちに戻り、この「実装完了後の流れ」を最後まで続けること。
実装の途中でも、検証が通ってコミットした直後の区切りで、文脈が
200,000 トークンを超えていれば `ocw self-compact` で自分を compact してよい（WIP のコミットは
区切りでない。指摘対応の修正の途中は対象外。1 PR につき多くて 3 回。ADR DOC-2610142337）。
測り方は `/pr-review-loop` の「区切りでの自己 compact（実装側のみ）」の手順1のコマンドと同じ（その節の (3) の項だけを読めばよい。
手順の「Phase 3 へ進む」は実装途中には当てはまらない）。復帰メモ（リポの外の一時ファイル）には、計画書のパスと孫の節・
済んだこと（コミットの一覧）・作業中に下した判断とその理由・残り・次の一手・検証コマンド・実装途中の compact の回数を書き、
先頭に「計画書の続きから実装を再開する。レビュー待ちではない」と書く。画像読み取りの確認の結果も復帰メモに必ず書く。
コマンドを実行したらそのターンを終える。使えない・拒否・失敗なら何もせず実装を続ける（人間に提案もしない）。
実装が終わったタイミングで止まらず、必ずここまでやりきってください。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## 大きい出力を文脈へ流し込まない（実装中ずっと）

文脈の膨張は、1k〜20k字級の出力の積み重ねと、自分で書く長い出力で起きる。次を守ること:
- ファイルを `cat` / `sed -n` で丸ごと読まず、`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む
- 約100行・5,000字を超えそうな出力（テスト・分析・ログ・`git diff`・JSON）は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る
- 既存の長いファイルや、繰り返し直して実行するスクリプトを Write / heredoc で丸ごと書き直さない。一度ファイルに置き、変更は Edit の差分で行う（新規ファイルを最初に1回書くのは構わない）

## ブランチ作成時の注意（最重要）

作業ブランチは**必ず `ds-cost-down` から切ること**。master から切ると PR の diff に傘ブランチ全体が
混入してレビュー不能になる。`ocw` が `origin/ds-cost-down` から切ったワークツリーを用意済みなので、
上の「実装開始前の必須手順」で確かめるだけでよい（`git pull` は使わない）。

## PR作成時の注意

PR を作る前に `docs/design/DOC-2608020715_プルリクエストの作法.md` を読むこと。
人間の発言を逐語で書かない（PUBLIC リポ。要約する）。pixidex（private）の中身は DOC-ID とパスで指すに留める。
````

## 孫4用プロンプト:

````markdown
# 傘ブランチ: ds-cost-down（dotfiles）
# 孫ブランチ: dcd-04-checker-request（pixidex）
# ターゲット: pixidex の main（他リポの孫。マージは人間）

計画書（dotfiles 側）: `/home/manemone/projects/dotfiles/ds-cost-down/docs/planning/DOC-2611032048_ds-cost-down_計画.md`

**まず計画書の「概要」「背景2」「背景3」「背景4」「決定的な制約」「スコープ外」「設計3」「設計4」「進行記録」を読むこと。**
続けて、孫3 がマージした仕組みの使い方の文書と ADR（計画書の進行記録に PR 番号がある。dotfiles の `origin/ds-cost-down` に
入っている）を読む。最後に、このリポ（pixidex）の `AGENTS.md` / `CLAUDE.md` を読み、その規約に従う。

## 実装開始前の必須手順

`ocw` がすでに `dcd-04-checker-request` ブランチのワークツリーを用意している。
`git fetch origin` と `git log --oneline -1 origin/main` で、作業ブランチが既定ブランチの先端を含んでいることだけを
確かめる（`git pull` は使わない。既定ブランチはメインワークツリーで checkout 済みのため、ここで `git checkout` しない）。

## やること

1. 計画書 設計4 の対象の候補（背景3 の一覧）を読み、UI 確認をサブエージェントの確かめ役に頼む書き方をしている
   **現役の**規約・計画書の型・ADR・リファレンスを洗い出す（完了済みの計画書は記録なので書き換えない）
2. それらを孫3 の仕組みで頼む形に直す。確かめ役に渡す「撮影スクリプト」と「確認項目」の置き場所と書き方を決め、
   pixidex の規約に書く
3. 「1 PR につき多くて 3 回」の書き写しが現役の規約・テンプレートにあれば、dotfiles 孫2 の新しい書き方に合わせる
   （孫2 が未マージなら触らず、PR 本文にそう書く）
4. 新しい判断（置き場所・書き方）は pixidex の ADR の作法に従って残す

## 検証方針

このリポの `AGENTS.md` の検証手順（lint・doc-id など）に従う。文書の変更が中心なので、新しい自動テストは
原則として要らない。

## 大きい出力を文脈へ流し込まない（実装中ずっと）

文脈の膨張は、1k〜20k字級の出力の積み重ねと、自分で書く長い出力で起きる。次を守ること:
- ファイルを `cat` / `sed -n` で丸ごと読まず、`grep -n` / `wc -l` / `head` で当たりをつけて必要な行範囲だけ読む
- 約100行・5,000字を超えそうな出力（テスト・分析・ログ・`git diff`・JSON）は `mktemp -d` の一時ファイルへ書き出し、`tail` / `grep` / 件数だけ見る
- 既存の長いファイルや、繰り返し直して実行するスクリプトを Write / heredoc で丸ごと書き直さない。一度ファイルに置き、変更は Edit の差分で行う（新規ファイルを最初に1回書くのは構わない）

## 実装完了後の流れ（必須）

実装が完了したら、以下を**自律的に**実行してください:

1. PRを作成する。**PRの向き先は main（このリポの既定ブランチ）。**
   PR 本文に、傘の計画書（dotfiles の `docs/planning/` にあるこの計画書。DOC-ID で示す）と、関係する傘側の PR
   （孫3 の PR）へのリンクを書く（複数リポにまたがる作業の継ぎ目）
2. /pr-review-loop を起動する（PRがない場合は自動で作成し、そのままレビューを開始する）
3. レビュー指摘があれば修正し、承認されるまで繰り返す
4. **承認されてもマージしない。** base が既定ブランチなので、マージは人間の仕事である。
   人間に「承認済みです。マージしてください」と依頼して止まる

なお `/pr-review-loop` は、レビューを依頼した直後の区切りで文脈が大きければ `ocw self-compact` で
自分を compact する。compact の後は、復帰メモに従ってレビュー待ちに戻り、この流れを最後まで続けること。
実装の途中でも、検証が通ってコミットした直後の区切りで、文脈が
200,000 トークンを超えていれば `ocw self-compact` で自分を compact してよい（WIP のコミットは
区切りでない。指摘対応の修正の途中は対象外。1 PR につき多くて 3 回。ADR DOC-2610142337。
dotfiles 孫2 がこの決まりを改訂済みなら、改訂後の pr-review-loop の書き方を優先する）。
測り方は `/pr-review-loop` の「区切りでの自己 compact（実装側のみ）」の手順1のコマンドと同じ（その節の (3) の項だけを読めばよい。
手順の「Phase 3 へ進む」は実装途中には当てはまらない）。復帰メモ（リポの外の一時ファイル）には、計画書のパスと孫の節・
済んだこと・作業中に下した判断とその理由・残り・次の一手・検証コマンド・実装途中の compact の回数を書き、
先頭に「計画書の続きから実装を再開する。レビュー待ちではない」と書く。コマンドを実行したらそのターンを終える。
使えない・拒否・失敗なら何もせず実装を続ける。
実装が終わったタイミングで止まらず、必ずここまでやりきってください。
このリポ自身の AGENTS.md 等の規約（ブランチ名・PR の作法・検証コマンド）に従うこと。
reviewerはdone状態で完了し完了通知は来ないので、待機して停止せず gh pr view をポーリングして
レビューの有無を確認してください。

## ブランチ作成時の注意（最重要）

作業ブランチは傘ブランチではなく、**このリポの既定ブランチ（origin/main）から切られている。**
ocw が既に `dcd-04-checker-request` を作って checkout 済みなので、
`git fetch origin` と `git log --oneline -1 origin/main` で、作業ブランチが
既定ブランチの先端を含んでいることだけを確認すればよい（git pull は使わない。
既定ブランチはメインワークツリーで checkout 済みのため、ここで git checkout しない）
````

## 付録A: 分析に使ったスクリプト（ブリーフの一時スクリプトの転記）

相談の AI が背景4.1 の数字を出すのに使った Python。元は一時ディレクトリに置かれていた。再現するときは4本を同じ
一時ディレクトリ（`mktemp -d`）に置いて cd し、`python3 -I <name>.py [SINCE]` で実行する（`SINCE` は ISO 形式の UTC。
省略時は 2026-11-02T15:00）。ただし `breakdown.py` `sim.py`（と `breakdown.py` を読む `reads.py`）は `ui_share.py` の先頭を読み込んで使い、そのとき `SINCE` を既定値に固定する（引数は効かない）。期間を変えるときは `ui_share.py` の既定値を書き換える。単価は `bin/prices/deepseek-2026-09-10.json` の値をそのまま埋め込んだ見積もりである
（混む時間帯 2倍）。入れたあとの見比べ（必須の検証ステップ）でも同じスクリプトを使う。

- `ui_share.py`: DeepSeek のセッションの費用のうち UI 確認（撮影・スクショの Read・ブラウザ操作など）の割合
- `breakdown.py`: 作業別（読む・書く・UI 確認・待ち・テスト・git）の内訳
- `reads.py`: 同じセッション内での再読の割合
- `sim.py`: 圧縮位置ごとの費用の試算（圧縮後 55k に戻り、要約出力 8k を足す単純モデル）

### A.1 `ui_share.py`

```python
import json,glob,collections,os,re,sys
SINCE=sys.argv[1] if len(sys.argv)>1 else "2026-11-02T15:00"
sess=set()
for fn in glob.glob(os.path.expanduser("~/.local/state/ocw-meter/events/2026-1*.jsonl")):
  for l in open(fn):
    e=json.loads(l)
    if e.get("event_type")=="usage.message" and e.get("provider")=="deepseek" and e["ts"]>=SINCE: sess.add(e["session_id"])
UIPAT=re.compile(r"127\.0\.0\.1|localhost|playwright|puppeteer|screenshot|chromium|chrome|\.png|powershell|curl ")
def is_ui(x):
  n=x["name"]; i=x["input"]
  if n=="Read" and str(i.get("file_path","")).lower().endswith((".png",".jpg",".jpeg",".webp")): return True
  if n=="Bash": return bool(UIPAT.search(i.get("command","")))
  if n.startswith("mcp__") and ("browser" in n or "chrome" in n or "playwright" in n): return True
  return False
def usd(u,ts):
  h=int(ts[11:13]); mul=2 if (1<=h<4 or 6<=h<10) else 1
  return mul*((u.get("cache_read_input_tokens") or 0)*0.003e-6+(u.get("input_tokens") or 0)*0.15e-6+(u.get("output_tokens") or 0)*0.6e-6)
def load(path):
  msgs={}
  first=None
  for l in open(path):
    e=json.loads(l); m=e.get("message",{})
    if first is None and e.get("type")=="user":
      c=m.get("content"); first=c if isinstance(c,str) else json.dumps(c,ensure_ascii=False)
    if e.get("type")=="assistant" and m.get("id"):
      r=msgs.setdefault(m["id"],{"u":None,"ts":e["timestamp"],"tools":[]})
      r["u"]=m.get("usage") or r["u"]; r["tools"]+=[x for x in m.get("content",[]) if x.get("type")=="tool_use"]
  return msgs,first or ""
tot=collections.Counter()
for sid in sess:
  for p in glob.glob(os.path.expanduser(f"~/.claude/projects/*/{sid}.jsonl")):
    msgs,_=load(p)
    for r in msgs.values():
      if r["ts"]<SINCE or not r["u"]: continue
      c=usd(r["u"],r["ts"]); tot["all"]+=c; tot["main"]+=c
      if r["tools"] and any(is_ui(x) for x in r["tools"]): tot["ui_main"]+=c*sum(is_ui(x) for x in r["tools"])/len(r["tools"])
    for sp in glob.glob(p[:-6]+"/subagents/*.jsonl"):
      msgs,first=load(sp)
      uisub=bool(re.search(r"確かめ役|UI|画面|スクショ|screenshot|127\.0\.0\.1|localhost|ブラウザ",first[:600]))
      for r in msgs.values():
        if r["ts"]<SINCE or not r["u"]: continue
        c=usd(r["u"],r["ts"]); tot["all"]+=c; tot["sub"]+=c
        if uisub: tot["ui_sub"]+=c
        elif r["tools"] and any(is_ui(x) for x in r["tools"]): tot["ui_main"]+=c*sum(is_ui(x) for x in r["tools"])/len(r["tools"])
  tot["sessions"]+=1
a=tot["all"]; ui=tot["ui_main"]+tot["ui_sub"]
print(f"since {SINCE} sessions={tot['sessions']} total=${a:.2f} main=${tot['main']:.2f} sub=${tot['sub']:.2f}")
print(f"UI確認: ${ui:.2f} ({ui/a:.0%})  内訳 本人がやった分 ${tot['ui_main']:.2f} / 確認用サブエージェント ${tot['ui_sub']:.2f}")
```

### A.2 `breakdown.py`

```python
import json,glob,collections,os,re,sys
exec(open("ui_share.py").read().split("tot=collections.Counter()")[0].replace("SINCE=sys.argv[1] if len(sys.argv)>1 else","SINCE="))
def cat(x):
  n=x["name"]; i=x["input"]
  if is_ui(x): return "UI確認"
  if n in("Read","Grep","Glob"): return "コードを読む"
  if n in("Edit","Write","MultiEdit","NotebookEdit"): return "コードを書く"
  if n in("SendMessage","ListAgents","Monitor","ScheduleWakeup","TaskStop","CronCreate","CronList"): return "待ち・連絡"
  if n=="Skill" or n=="ToolSearch": return "スキル読み込み"
  if n=="Agent": return "サブエージェント起動"
  if n=="Bash":
    c=i.get("command","")
    if re.search(r"\bsleep\b|gh pr (view|checks)|gh api .*(reviews|comments)|herdr (pane|agent) (get|read|list|wait)|gh run (view|watch)",c): return "待ち・連絡"
    if re.search(r"herdr|SendMessage",c): return "待ち・連絡"
    if re.search(r"bundle|rspec|pytest|unittest|npm (run|test)|pre-commit|shellcheck|rubocop|\btest\b|lint",c): return "テスト・lint"
    if re.search(r"^\s*(cd [^;&]*&&\s*)?git |gh pr (create|edit|comment)|gh ",c): return "git・PR"
    if re.search(r"\b(grep|sed -n|cat|head|tail|ls|find|wc|rg)\b",c): return "コードを読む"
    return "その他コマンド"
  return "その他:"+n
cost=collections.Counter(); calls=collections.Counter(); ctxw=collections.Counter(); textonly=0
for sid in sess:
  for p in glob.glob(os.path.expanduser(f"~/.claude/projects/*/{sid}.jsonl")):
    for path in [p]+glob.glob(p[:-6]+"/subagents/*.jsonl"):
      msgs,first=load(path)
      uisub = path!=p and bool(re.search(r"確かめ役|UI|画面|スクショ|screenshot|127\.0\.0\.1|localhost|ブラウザ",first[:600]))
      for r in msgs.values():
        if r["ts"]<SINCE or not r["u"]: continue
        c=usd(r["u"],r["ts"])
        ts=["UI確認"] if uisub else ([cat(x) for x in r["tools"]] or ["返事・考えるだけ"])
        for t in ts: cost[t]+=c/len(ts); calls[t]+=1/len(ts); ctxw[t]+=(r["u"].get("cache_read_input_tokens") or 0)/len(ts)
a=sum(cost.values())
for t,v in cost.most_common(): print(f"{t}: ${v:.2f} ({v/a:.0%}) {calls[t]:.0f}回 平均文脈{ctxw[t]/calls[t]/1e3:.0f}k ${v/calls[t]*1000:.2f}/千回")
print(f"total ${a:.2f}")
```

### A.3 `reads.py`

```python
import json,glob,collections,os,re
exec(open("breakdown.py").read().split("cost=collections.Counter()")[0])
SINCE="2026-11-02T15:00"
files_total=0; files_rep=0; cmd_total=0; cmd_rep=0; per_sess=[]; compacted=0
rep_examples=collections.Counter()
for sid in sess:
  for p in glob.glob(os.path.expanduser(f"~/.claude/projects/*/{sid}.jsonl")):
    msgs,_=load(p)
    seenf=collections.Counter(); seenc=set(); n=0
    for r in sorted(msgs.values(),key=lambda r:r["ts"]):
      if r["ts"]<SINCE: continue
      for x in r["tools"]:
        if cat(x)!="コードを読む": continue
        n+=1
        if x["name"]=="Read":
          f=x["input"].get("file_path"); files_total+=1
          if seenf[f]: files_rep+=1
          seenf[f]+=1
        else:
          c=x["input"].get("command") or json.dumps(x["input"])
          fs=re.findall(r"[\w./-]+\.(?:rb|js|ts|md|py|sh|yml|json|erb|css|html)\b",c)
          cmd_total+=1
          if c in seenc: cmd_rep+=1
          seenc.add(c)
          for f in set(fs): seenf[f]+=1
    top=seenf.most_common(1)
    per_sess.append((n,os.path.basename(os.path.dirname(p))[-40:],top))
print(f"Read: {files_total}回中 同じファイルの再読 {files_rep}（{files_rep/max(files_total,1):.0%}）")
print(f"grep/sed等: {cmd_total}回中 まったく同じコマンドの再実行 {cmd_rep}（{cmd_rep/max(cmd_total,1):.0%}）")
for n,s,t in sorted(per_sess,reverse=True)[:8]: print(n,s,t)
```

### A.4 `sim.py`

```python
import json,glob,os
exec(open("ui_share.py").read().split("tot=collections.Counter()")[0].replace("SINCE=sys.argv[1] if len(sys.argv)>1 else","SINCE="))
SINCE="2026-11-02T15:00"
BASE=55000
def sim(T, offpeak=False):
  cache=0; other=0
  for sid in sess:
    for p in glob.glob(os.path.expanduser(f"~/.claude/projects/*/{sid}.jsonl")):
      for path in [p]+glob.glob(p[:-6]+"/subagents/*.jsonl"):
        msgs,_=load(path); prev=None; cur=None
        for r in sorted(msgs.values(),key=lambda r:r["ts"]):
          if r["ts"]<SINCE or not r["u"]: continue
          u=r["u"]; h=int(r["ts"][11:13]); mul=1 if offpeak else (2 if (1<=h<4 or 6<=h<10) else 1)
          ctx=(u.get("cache_read_input_tokens") or 0)
          if prev is None: cur=ctx
          else:
            d=ctx-prev
            cur = cur+d if d>=0 else ctx   # 実際に圧縮が入ったらその値に合わせる
          if T and cur>T: cur=BASE; other+=mul*8000*0.6e-6  # 圧縮1回: 要約の出力ぶん
          prev=ctx
          cache+=mul*cur*0.003e-6
          other+=mul*((u.get("input_tokens") or 0)*0.15e-6+(u.get("output_tokens") or 0)*0.6e-6)
  return cache+other, cache
b,bc=sim(None)
print(f"今のまま: ${b:.2f}（うち読み直し ${bc:.2f}）")
for T in (250000,200000,150000,120000):
  t,c=sim(T); print(f"文脈{T//1000}kで圧縮: ${t:.2f}（{1-t/b:.0%}減）")
t,_=sim(None,True); print(f"混む時間帯を全部避けた場合: ${t:.2f}（{1-t/b:.0%}減）")
t,_=sim(150000,True); print(f"150kで圧縮＋混む時間帯を避ける: ${t:.2f}（{1-t/b:.0%}減）")
```
