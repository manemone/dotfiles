#!/usr/bin/env python3
# Stop hook の試作（調査用。配布しない）。直前の返事に、和語に開いた言い換えか全面禁止の宣言があれば、
# 書き直しを促す。stdin は Stop hook の JSON（last_assistant_message, stop_hook_active を使う）。
# 判定の語と正規表現は wh.py と同じものを使う（計測と点検の食い違いを避ける）。
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wh  # noqa: E402

# 同じ意味の漢語（促すときに添える。語の対応は計画書の背景2 の例）
HINT = {'確かめ': '確認', '直し': '修正', '測り': '計測', '割り出し': '切り分け', '控え': 'キャッシュ',
        '写し': 'コピー', '焼いた指示': '説明のある呼び方'}


def check(text):
    body = wh.clean(text, keep_quotes=False)
    found = [k for k, v in wh.OPEN.items() if wh.re.search(v, body)]
    bans = [k for k, v in wh.BAN.items() if wh.re.search(v, body)]
    return found, bans


def main():
    d = json.load(sys.stdin)
    if d.get('stop_hook_active'):  # 書き直しの結果は再点検しない（ループ防止）
        return 0
    found, bans = check(d.get('last_assistant_message') or '')
    if not found and not bans:
        return 0
    msg = []
    if found:
        msg.append('直前の返事に、ふだん漢語で言う物事を和語に開いた言い換えがある: '
                   + '、'.join(f'{k}（→{HINT[k]}）' for k in found)
                   + '。普通に通じる和語（引く・探す・立てる・止める・回す）はそのままでよい。該当箇所だけ漢語に直して送り直す。')
    if bans:
        msg.append('直前の返事に、今回の指摘を全面禁止に広げる言い回しがある（' + '、'.join(bans)
                   + '）。指摘された場面でだけ何が悪かったかを述べ、以後の方針を宣言しない形に直して送り直す。')
    print(json.dumps({'decision': 'block', 'reason': ' '.join(msg)}, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    sys.exit(main())
