"""review-tiering 調査スクリプトの共通部分（使い捨て）。

生データの置き場は環境変数 REVIEW_DATA で渡す（リポ名・パスはハードコードしない）。
生データは PRIVATE リポの内容を含むため、リポには入れない。
"""
import json, os, re, sys

DATA = os.environ.get("REVIEW_DATA")
if not DATA:
    sys.exit("REVIEW_DATA（生データのディレクトリ）を環境変数で渡すこと")
DERIVED = os.path.join(DATA, "derived")
os.makedirs(DERIVED, exist_ok=True)

REVIEW_RE = re.compile(r"^\s*#*\s*🤖🔍")
APPROVE_RE = re.compile(r"^\s*#*\s*🤖✅")
REPORT_RE = re.compile(r"^\s*#*\s*🤖💬")
HEADER_MODEL_RE = re.compile(r"\[([^\]|]*)")


def load_rows():
    return json.load(open(os.path.join(DATA, "rows.json")))


def load_pr(repo, n):
    return json.load(open(os.path.join(DATA, "pr", f"{repo}-{n}.json")))


def header_model(body):
    """コメント先頭行の [モデル | 努力量] からモデル名を取る。無ければ None"""
    first = body.split("\n", 1)[0]
    m = HEADER_MODEL_RE.search(first)
    if not m:
        return None
    return re.sub(r"\s*\(.*?\)", "", m.group(1)).strip() or None


def normalize_model(name):
    """表記ゆれを寄せる。分類は『実装役のモデルの系統』に粗くする"""
    if not name:
        return "不明"
    n = name.lower()
    if "deepseek" in n:
        return "DeepSeek"
    if "qwen" in n:
        return "Qwen"
    if "kimi" in n:
        return "Kimi"
    if "opus" in n:
        return "Opus"
    if "sonnet" in n:
        return "Sonnet"
    if "fable" in n:
        return "Fable"
    if "gpt" in n or "codex" in n:
        return "GPT"
    return "不明"


def events(pr):
    """コメントとレビューを時刻順に並べた (時刻, 本文) の列。
    レビュー本文は reviews 側、対応報告は comments 側に入っている。
    指摘のインラインコメントは本文が空のレビューとして入っており、本文は取れない（限界）。"""
    ev = [(c.get("createdAt", ""), c["body"]) for c in pr["comments"]]
    ev += [(r.get("submittedAt", ""), r["body"]) for r in pr["reviews"]]
    return sorted(ev)


def umbrellas():
    """再現実験の対象の傘。環境変数 REVIEW_UMBRELLAS、無ければ derived/umbrellas.txt（並び順が傘の通し番号）"""
    v = os.environ.get("REVIEW_UMBRELLAS")
    if v is None:
        p = os.path.join(DERIVED, "umbrellas.txt")
        v = open(p).read().strip() if os.path.exists(p) else ""
    return [u for u in v.split(",") if u]


def model_group(impl):
    """表示用のモデル群。sample.py の層（弱いモデルと Fable/GPT を一緒にした『その他』）とは別に、
    集計では DeepSeek・Qwen・Kimi（弱いモデル）と Fable・GPT（その他の強いモデル）を分ける"""
    if impl in ("Sonnet", "Opus"):
        return impl
    if impl in ("DeepSeek", "Qwen", "Kimi"):
        return "弱いモデル(DeepSeek/Qwen/Kimi)"
    if impl in ("Fable", "GPT"):
        return "その他(Fable/GPT)"
    return "不明"
