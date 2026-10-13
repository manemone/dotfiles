#!/usr/bin/env bash
# 再現実験のブランチ作り（使い捨て）。使い方: replay_build.sh <傘番号> <scratch の親ディレクトリ>
# 環境変数: REVIEW_DATA, REVIEW_OWNER
# - 傘の孫 PR を merge 順に、「最初のレビュー前の head」の差分で順に当てた replay ブランチを作る
# - clone は fetch だけに使い、作り終えたら origin を外す（push 先を残さない）
# - 衝突したファイルは、その孫のマージ後の版（merge commit）で埋め、記録する
set -euo pipefail
# gh の認証を一時的な環境変数で git に渡す（git の設定ファイルは書き換えない）
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0="!gh auth git-credential"
n=${1:?傘番号}
parent=${2:?scratch の親ディレクトリ}
meta="$REVIEW_DATA/derived/replay/umbrella$n.json"
repo=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['repo'])" "$meta")
upr=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['umbrella_pr'])" "$meta")
dir="$parent/u$n"
git clone -q --no-checkout "https://github.com/$REVIEW_OWNER/$repo.git" "$dir"
cd "$dir"
python3 - "$meta" >"$parent/u$n.prs.tsv" <<'P'
import json,sys
d=json.load(open(sys.argv[1]))
for p in sorted(d["prs"],key=lambda p:p["mergedAt"] or ""):
    print(p["n"],p["pre_review_head"] or "-",p["merge_oid"] or "-",p["final_head"],sep="\t")
P
git fetch -q origin "+refs/pull/$upr/head:refs/replay/umbrella"
while IFS=$'\t' read -r pr pre merge final; do
  git fetch -q origin "+refs/pull/$pr/head:refs/replay/pr$pr" || true
  [ "$merge" = "-" ] || git cat-file -e "$merge" 2>/dev/null || git fetch -q origin "$merge" 2>/dev/null || true
done <"$parent/u$n.prs.tsv"
git remote remove origin
git -c core.hooksPath=/dev/null config user.email replay@example.invalid
git config user.name replay
git config core.quotePath false
log="$parent/u$n.build.log"
: >"$log"
# 傘の first-parent の履歴を古い順にたどる。孫 PR のマージ点は「最初のレビュー前の head」の差分に差し替え、
# それ以外の直コミット（司令官の計画書更新など）はそのまま当てる
# 起点は、最初に取り込まれた孫 PR のマージ点の親（傘の履歴がすでに main に入っていても同じ起点が取れる）
git rev-list --first-parent --reverse refs/replay/umbrella >"$parent/u$n.allcommits"
firstc=$(grep -Fxf <(cut -f3 "$parent/u$n.prs.tsv") "$parent/u$n.allcommits" | head -1 || true)
legacy=0
if [ -n "$firstc" ]; then
  base=$(git rev-parse "$firstc^1")
else
  # 傘の履歴に孫 PR のマージ点が無い（傘が書き換えられた等）。孫 PR のマージ順に当て、直コミットは扱えない
  legacy=1
  read -r _ pre0 merge0 final0 <"$parent/u$n.prs.tsv"
  [ "$pre0" = "-" ] && pre0=$final0
  base=$(git merge-base "$pre0" "$merge0^1")
fi
git checkout -q -b replay "$base"
git branch -f replay-start "$base"
if [ $legacy = 1 ]; then
  cut -f3 "$parent/u$n.prs.tsv" | grep -v '^-$' >"$parent/u$n.commits"
else git rev-list --first-parent --reverse "$base..refs/replay/umbrella" >"$parent/u$n.commits"; fi
apply_patch() { # $1=パッチ $2=埋め元のコミット $3=fork $4=used。結果を status に入れる
  if git apply --3way --index "$1" 2>/dev/null; then
    status=ok
    return
  fi
  conflicted=$(git diff --name-only --diff-filter=U)
  [ -n "$conflicted" ] || conflicted=$(git diff --name-only "$3" "$4")
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if git cat-file -e "$2:$f" 2>/dev/null; then git checkout "$2" -- "$f"; else git rm -qf --ignore-unmatch -- "$f"; fi
  done <<EOF
$conflicted
EOF
  status="conflict:$(printf '%s' "$conflicted" | grep -c .)files"
}
while read -r c; do
  line=$(awk -F'\t' -v m="$c" '$3==m' "$parent/u$n.prs.tsv")
  if [ -n "$line" ]; then
    IFS=$'\t' read -r pr pre merge final <<EOF
$line
EOF
    used=$pre
    fill=0
    if [ "$pre" = "-" ]; then
      used=$final
      fill=1
    fi
    fork=$(git merge-base "$used" "$c^1")
    git diff "$fork" "$used" >"$parent/p$n-$pr.patch"
    apply_patch "$parent/p$n-$pr.patch" "$c" "$fork" "$used"
    git commit -q --allow-empty -m "replay pr$pr ($([ $fill = 1 ] && echo 'final-head-fill' || echo 'pre-review'))" || true
    printf "pr%s\t%s\tfill=%s\ttotal_files=%s\n" "$pr" "$status" "$fill" "$(git diff --name-only "$fork" "$used" | grep -c .)" >>"$log"
  elif git log -1 --format=%s "$c" | grep -qiE 'レビュー|review'; then
    # 孫 PR のレビュー指摘への対応を傘へ直接入れた直コミットは、レビューの成果なので当てない
    printf "direct %s\tSKIPPED(review-fix)\n" "$(git rev-parse --short "$c")" >>"$log"
  else
    git diff "$c^1" "$c" >"$parent/d$n-$c.patch"
    apply_patch "$parent/d$n-$c.patch" "$c" "$c^1" "$c"
    git commit -q --allow-empty -m "replay direct $(git rev-parse --short "$c")" || true
    printf "direct %s\t%s\n" "$(git rev-parse --short "$c")" "$status" >>"$log"
  fi
done <"$parent/u$n.commits"
while IFS=$'\t' read -r pr pre merge final; do
  grep -q "^pr$pr	" "$log" || printf "pr%s\tNOT-APPLIED\n" "$pr" >>"$log"
done <"$parent/u$n.prs.tsv"
git diff --shortstat replay-start replay >>"$log"
cat "$log"
