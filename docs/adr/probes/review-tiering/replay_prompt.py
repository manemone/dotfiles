"""最終レビューの指示ファイルを作る（使い捨て）。
pr-review-loop の SKILL.md の Phase 2 Step 1 テンプレートから、レビューガイドライン・finding の判定基準・
譲れないレビュー基準・テスト不足の判定基準の本文を抜き、マーカーを埋め、GitHub への投稿だけをローカルのファイルへの
書き出しに差し替える。使い方: replay_prompt.py <SKILL.md> <傘番号> <scratch のクローン> <出力 md のパス> > 指示ファイル
"""
import re, sys

skill, n, clone, outpath = sys.argv[1:5]
t = open(skill).read()


def between(start, end):
    i = t.index(start)
    return t[i:t.index(end, i)]


gate = between("レビューで気づいたことは、", "## テストの判断基準（risk-based testing）").rstrip()
risk = between("テストは「コード・分岐・受け入れ条件」の数ではなく、", "## Phase 1.5").rstrip()
guide = between("- 以下の**全7次元を必ずチェック**", "## 承認・変更要求マーカー")
guide = guide.replace("- 指摘と承認は必ずGitHubに投稿（画面上だけでは不可）\n", "").replace(
    "- どのHEAD SHAを対象にしたレビューか明記\n", "")
rules = between("**1. 一発で網羅。小出し厳禁。**", "## テスト不足の判定基準")
rules = rules.replace("{{CHANGES_REQUESTED_MARKER}}", "変更要求").replace("{{APPROVED_MARKER}}", "承認")
print(f"""# 傘ブランチ全体の最終レビュー依頼（再現実験）

対象: `{clone}` の git リポジトリ。レビューする差分は `git diff replay-start replay`（`replay` ブランチの先端）。
これは 1 本の傘ブランチ（複数の孫 PR の変更を順に当てたもの）の差分全体で、**1 回だけ**レビューする。
PR 説明・既存コメント・過去のレビューは存在しない（GitHub へは接続しない。`gh` も使わない）。

## 最初のステップ
1. `cd {clone}` してリポジトリを確認（`git log --oneline replay-start..replay` で変更の単位が分かる）
2. AGENTS.md / README / docs に規約・計画があれば読む（`replay` の作業ツリーで読める。`git checkout replay` してよい）
3. `git diff replay-start replay` の全体と、diff が参照する周辺コードを読む
4. 以下のガイドラインでレビューする

## レビューガイドライン
{guide}
## 出力
- GitHub へは何も投稿しない。レビュー結果を **`{outpath}`** に Markdown で書く（このファイル以外は書かない。コード修正・コミットもしない）
- 各 finding に、番号・ファイル・行・要約・具体的な failure scenario を書く。最後に判定（承認 / 変更要求）を1行
- 実行コマンド（lint / test）は指定されていない。必要なら自分で判断して実行してよいが、時間をかけすぎない

## finding の判定基準

{gate}

## 譲れないレビュー基準

{rules}
## テスト不足の判定基準

{risk}
""")
