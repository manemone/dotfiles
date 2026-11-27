# ADR: 画面デザインの前後の工程を、独立したスキル `screen-design-lifecycle` にする

## ステータス

決定（2026-11-27）。

## 1. 背景

`figma-design-workflow`（ADR DOC-2611161826）は、Figma という外部の正本を書き換える作業の手順を持つ。
実際に画面を最初から作った傘の振り返りでは、その前後の工程に手順が無かった。

- 前: 新しい画面を始めるときに最初に作る文書の組・FB（会議やレビューの指摘）から決めへつなぐ手順・決めの文書と定義の文書・記録の番号の振り方
- 後: 実装への申し送りの文書の組・デモを触った後の気づきの受け口とボード

差分の洗い出しと分担ボードは、`figma-design-workflow` の `references/handoff-to-impl.md` に既にある。

## 2. 決定

### 2.1 別のスキルを1本足す

`skills/screen-design-lifecycle/` を新設する。前後の工程の手順を、このスキルが持つ。

- 自動発動しない。`/screen-design-lifecycle` で明示的に起動する
- 新しい画面を始める人が、このスキル1本を起動すれば、工程の順番・最初に作る文書・各工程で渡す先が分かる入口にする
- `SKILL.md` に工程の全体図と共通ルール、細部は `references/`（`start.md`・`intake-to-decisions.md`・`handoff-docs.md`・`after-demo.md`）に置く
- AI 不問の自然言語（ADR DOC-2608272128）。`skills/deploy.sh` が自動で拾うので、`shared/helpers.sh` は触らない
- 公開リポのため、案件を特定できる語を書かない。例は架空の画面にする（ADR DOC-2611161826 §2.4 と同じ）

### 2.2 既存スキルとの分担

| 関心 | 持ち主 |
|---|---|
| 工程の全体・新しい画面の始め方・FB から決めへ・番号の接頭辞・申し送りの文書の組・デモ後の受け口 | `screen-design-lifecycle` |
| Figma を書く作業・差分の洗い出し・分担ボードの issue | `figma-design-workflow` |
| 作業の振り分け | `task-intake` |
| 孫の spawn・マージ・巡回 | `umbrella-orchestrator` |

`figma-design-workflow` には、前後の工程は新しいスキルへ、という案内の1行と、実例の1行だけを足す。手順は書き換えない。

## 3. 却下した案

- **`figma-design-workflow` を前後の工程まで広げる。** スキルは1本で済むが、芯（外部の正本を戻せる形で書き換える）がぼけ、
  Figma を書かない工程（FB の整理・決めの文書・デモ後の受け口）が混ざって、名前と中身がずれる
- **工程ごとに別のスキルにする（3本以上）。** 起動の判断が増える。入口を1本にして、細部を `references/` に置くほうが迷わない
