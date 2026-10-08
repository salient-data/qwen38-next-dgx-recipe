#!/usr/bin/env bash
# Is the server up and answering correctly? Two fixed checks with known answers. Fluent but wrong answers are the
# signature of a broken PLE path (the FP8 n-gram table read without its scale): see docs/troubleshooting.md.
set -uo pipefail
cd "$(dirname "$0")"; source ./pins.env
URL="http://${BIND:-127.0.0.1}:${PORT:-8000}"; AUTH=(); [[ -n "${VLLM_API_KEY:-}" ]] && AUTH=(-H "Authorization: Bearer $VLLM_API_KEY")
curl -fsS "${AUTH[@]}" "$URL/v1/models" > /dev/null || { echo "FAIL: $URL does not answer (still loading? docker logs -f qwen38-flash-next)"; exit 1; }
ask() { curl -fsS "${AUTH[@]}" "$URL/v1/chat/completions" -H 'content-type: application/json' -d "{\"model\":\"$SERVED_NAME\",\"messages\":[{\"role\":\"user\",\"content\":\"$1\"}],\"max_tokens\":64,\"temperature\":0}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["choices"][0]["message"]["content"])'; }
a1="$(ask 'What is 17 multiplied by 23? Reply with the number only.')"; [[ "$a1" == *391* ]] && echo "ok    17*23 -> $a1" || { echo "FAIL  17*23 -> $a1"; F=1; }
a2="$(ask 'What is the capital of Australia? Reply with one word.')"; [[ "$a2" == *Canberra* ]] && echo "ok    capital -> $a2" || { echo "FAIL  capital -> $a2"; F=1; }
exit ${F:-0}
