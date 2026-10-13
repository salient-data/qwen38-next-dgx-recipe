#!/usr/bin/env bash
# Rerun tonyd2wild's published harness against the served recipe, exactly as our results were measured:
# three runs at 1 stream, then one at 6 streams. Fetched at a pinned commit and verified by sha256 (not vendored).
# The server must be idle (nothing else sending requests; wait for launch.sh's warm-up, a few seconds after it answers). Writes bench/third-party/.../results/categories_recipe_*.json
# The harness sends no API key: run it against a server started without VLLM_API_KEY (the default, bound to localhost).
set -euo pipefail
cd "$(dirname "$0")"
REPO=https://github.com/tonyd2wild/Qwen3.8-Flash-Next-NVFP4-DGX-Spark
COMMIT=6ad1c8f15cbab1ababd2048e8e5f94094dbfc4a0
SHA256=5d9b6954d0c87be8226aca86297704ca8c968a3863353d5c267480bddf06e0d3
URL="http://${BIND:-127.0.0.1}:${PORT:-8000}"
[[ -d third-party ]] || git clone -q "$REPO" third-party
git -C third-party checkout -q "$COMMIT"
cd third-party/single-spark-vllm-tp1
echo "$SHA256  tools/bench_categories.py" | sha256sum -c --quiet || { echo "bench_categories.py does not match the pinned hash" >&2; exit 1; }
for t in a b c; do python3 tools/bench_categories.py "$URL" qwen3.8-flash-next recipe --thinking off --concurrency 1 --tag "$t"; done
python3 tools/bench_categories.py "$URL" qwen3.8-flash-next recipe --thinking off --concurrency 6
python3 - <<'PY'
import glob, json, statistics
c1 = [json.load(open(p)) for p in sorted(glob.glob("results/categories_recipe_off_c1_*.json"))]
c6 = json.load(open("results/categories_recipe_off_c6.json"))
print("1 stream median decode tok/s:", statistics.median(r["overall"]["decode_med_tok_s"] for r in c1), [r["overall"]["decode_med_tok_s"] for r in c1])
print("1 stream prose median tok/s:", statistics.median(r["summary"]["prose"]["decode_med_tok_s"] for r in c1))
print("6 streams median batch aggregate tok/s:", c6["overall"]["agg_tok_s_med"])
print("auto-score 1 / 6 streams:", statistics.median(r["overall"]["auto_score"] for r in c1), "/", c6["overall"]["auto_score"])
PY
