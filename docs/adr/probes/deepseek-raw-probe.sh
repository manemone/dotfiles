#!/bin/bash
# DeepSeek 生リクエスト probe — 孫0 P2
# 課金あり（$0.01未満）。人間が手動実行すること。
# APIキーを一切出力しない。
#
# 使用方法:
#   chmod +x docs/adr/probes/deepseek-raw-probe.sh
#   ./docs/adr/probes/deepseek-raw-probe.sh
#
# 出力:
#   /tmp/ds-probe-nonstreaming.txt  — 非streamingのヘッダキー名一覧 + usage
#   /tmp/ds-probe-streaming.txt     — streamingのSSEイベント（usage部分のみ）

set -euo pipefail

API_KEY_FILE="${DEEPSEEK_API_KEY_FILE:-$HOME/.config/deepseek/api_key}"
if [ ! -f "$API_KEY_FILE" ]; then
  echo "ERROR: API key file not found: $API_KEY_FILE"
  echo "Set DEEPSEEK_API_KEY_FILE or create ~/.config/deepseek/api_key"
  exit 1
fi
API_KEY=$(tr -d '\r\n' < "$API_KEY_FILE")
if [ -z "$API_KEY" ]; then
  echo "ERROR: API key is empty. Check $API_KEY_FILE"
  exit 1
fi

BASE_URL="https://api.deepseek.com/anthropic/v1/messages"
MODEL="deepseek-v4-pro[1m]"

# Minimal request body (max_tokens: 16 for minimal cost)
BODY='{"model":"'"$MODEL"'","max_tokens":16,"messages":[{"role":"user","content":"say hi"}]}'

echo "=== DeepSeek Raw Request Probe ==="
echo "Model: $MODEL"
echo "Output files: /tmp/ds-probe-nonstreaming.txt, /tmp/ds-probe-streaming.txt"
echo 'Estimated cost: < $0.01'
echo ""

# ── Non-streaming ──
echo "--- Non-streaming request ---"
NONSTREAM_OUT="/tmp/ds-probe-nonstreaming.txt"
{
  echo "=== Non-streaming probe ==="
  echo "Timestamp: $(date -Iseconds)"
  echo "Model requested: $MODEL"
  echo ""

  # Round-1 review finding 7: pass the API key through a temporary header
  # file so it never appears in `ps` output. The header file is removed on
  # script exit (both requests share the same temp file, so it cannot be
  # deleted before the streaming request completes).
  AUTH_HDR=$(mktemp)
  trap 'rm -f "$AUTH_HDR"' EXIT
  printf 'Authorization: Bearer %s\r\n' "$API_KEY" > "$AUTH_HDR"

  # Make request, capture response headers and body separately
  # -D - dumps headers to stdout, --trace-ascii would include body but we avoid that
  RESPONSE=$(curl -s -i \
    -X POST "$BASE_URL" \
    -H @"$AUTH_HDR" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d "$BODY" 2>&1)

  # Extract header names only (no values — security)
  echo "--- Response header keys (names only, no values) ---"
  echo "$RESPONSE" | sed -n '/^\r$/q; s/^\([A-Za-z][-A-Za-z0-9]*\):.*/\1/p' | sort -u

  echo ""
  echo "--- HTTP status ---"
  echo "$RESPONSE" | head -1

  echo ""
  echo "--- Response body (usage + model fields only, no text content) ---"
  # Extract JSON body (after blank line)
  BODY_JSON=$(echo "$RESPONSE" | sed -n '/^\r$/,$p' | tail -n +2)
  if [ -n "$BODY_JSON" ]; then
    # Only show model, usage, stop_reason — NOT content/text
    echo "$BODY_JSON" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    # Only extract safe fields
    safe = {}
    for key in ['id', 'model', 'stop_reason', 'type', 'role']:
        if key in d:
            safe[key] = d[key]
    if 'usage' in d:
        safe['usage'] = d['usage']
    print(json.dumps(safe, indent=2))
except Exception as e:
    print(f'JSON parse error: {e}')
    print('(Raw body not shown for security)')
" 2>&1 || echo "(Failed to parse response body)"
  fi

  echo ""
  echo "--- Probe complete ---"
} > "$NONSTREAM_OUT" 2>&1

echo "Non-streaming result: $NONSTREAM_OUT"

# ── Streaming ──
echo "--- Streaming request ---"
STREAM_OUT="/tmp/ds-probe-streaming.txt"
{
  echo "=== Streaming probe ==="
  echo "Timestamp: $(date -Iseconds)"
  echo "Model requested: $MODEL"
  echo ""

  # Build streaming body
  STREAM_BODY='{"model":"'"$MODEL"'","max_tokens":16,"stream":true,"messages":[{"role":"user","content":"say hi"}]}'

  # Capture headers + first few SSE events
  # -N disables buffering, critical for streaming
  curl -s -N -X POST "$BASE_URL" \
    -H @"$AUTH_HDR" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d "$STREAM_BODY" 2>&1 | python3 -c "
import sys, json

print('--- SSE event summary (usage-bearing events only) ---')
for line in sys.stdin:
    line = line.rstrip('\n')
    if not line.startswith('data: '):
        continue
    data = line[6:]
    if data == '[DONE]':
        print('[DONE]')
        break
    try:
        d = json.loads(data)
        etype = d.get('type', '?')
        # Only show events that carry usage or metadata (NOT content)
        if etype in ('message_start', 'message_delta', 'message_stop', 'error', 'ping'):
            safe = {'type': etype}
            if 'message' in d:
                m = d['message']
                safe['message'] = {}
                for k in ('id', 'model', 'type', 'role'):
                    if k in m:
                        safe['message'][k] = m[k]
                if 'usage' in m:
                    safe['message']['usage'] = m['usage']
            if 'usage' in d:
                safe['usage'] = d['usage']
            if 'delta' in d:
                dd = d['delta']
                safe['delta'] = {}
                if 'stop_reason' in dd:
                    safe['delta']['stop_reason'] = dd['stop_reason']
                if 'usage' in dd:
                    safe['delta']['usage'] = dd['usage']
            if 'error' in d:
                safe['error'] = {'type': d['error'].get('type', '?'), 'message': d['error'].get('message', '?')}
            print(json.dumps(safe))
        # Skip content_block_start, content_block_delta — they contain text
    except json.JSONDecodeError:
        pass
" 2>&1

  echo ""
  echo "--- Probe complete ---"
} > "$STREAM_OUT" 2>&1

echo "Streaming result: $STREAM_OUT"
echo ""
echo "=== Done ==="
echo "Please share the contents of:"
echo "  $NONSTREAM_OUT"
echo "  $STREAM_OUT"
echo ""
echo "NOTE: These files contain header KEY NAMES and usage numbers only."
echo "      No API keys, no response text content, no Authorization values."
