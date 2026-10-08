#!/usr/bin/env python3
"""Score the fixed 100-problem GSM8K subset against a served endpoint.

Reference protocol: temperature 0.6, top-p 0.95, thinking on, as published for other Qwen3.8-Flash-Next NVFP4
quantizations (full 1319-problem split, max 8192 tokens). NVIDIA's card for nvidia/Qwen3.8-Flash-Next-NVFP4 publishes
no GSM8K figure. This scores 100 of the test problems (gsm8k-subset.jsonl: a seeded sample, see
gsm8k-subset.provenance.json) at that temperature and top-p. Differences, all recorded in the output:

  * 100 problems, not 1319: a binomial 95% interval of about +/-3.3 points near 97%. It detects a collapse (for
    example the PLE scale trap), not a one-point drift.
  * --max-tokens defaults to 3072. An answer that hits the cap scores as wrong and is counted as `truncated`.
  * Sampling is on, so a rerun moves the score; --temperature 0 is available for tighter comparisons.

Scoring: the gold answer is the integer after '####'. The model is asked to end with '#### <number>'; the parser
takes that if present, otherwise the last number (the usual lenient rule). Answers and parses land in the JSON.

USAGE
    python3 gsm8k.py --json gsm8k.json                  # against http://localhost:8000
    python3 gsm8k.py --n 10 --concurrency 2             # a quick pilot
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import math
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).parent
SUBSET = HERE / "gsm8k-subset.jsonl"

# The reference GSM8K protocol (see the docstring). Not this checkpoint's generation_config profile
# (temperature 1.0, top_p 0.95, top_k 20), which is the serving profile.
REF_TEMPERATURE = 0.6
REF_TOP_P = 0.95
REF_MAX_TOKENS = 8192

INSTRUCTION = (
    "Solve the problem. Show your working, then end your reply with the final "
    "numeric answer on its own last line in exactly this form:\n"
    "#### <number>"
)

_NUM = re.compile(r"-?\d[\d,]*\.?\d*")


def parse_answer(text: str) -> str | None:
    """The number the model settled on: after the last '####' if it obeyed the
    format, otherwise the last number anywhere in the reply."""
    if not text:
        return None
    tail = text.rsplit("####", 1)[1] if "####" in text else text
    nums = _NUM.findall(tail)
    if not nums and "####" in text:
        nums = _NUM.findall(text)
    if not nums:
        return None
    return nums[-1].replace(",", "")


def same_number(got: str | None, want: str) -> bool:
    if got is None:
        return False
    try:
        a, b = float(got), float(want.replace(",", ""))
    except ValueError:
        return got.strip() == want.strip()
    return abs(a - b) < max(1e-6, abs(b) * 1e-9)


def wilson(k: int, n: int) -> tuple[float, float]:
    """95% Wilson interval, in percent. Wilson rather than the normal
    approximation because at 97% of 100 the normal interval runs past 100."""
    if n == 0:
        return (0.0, 0.0)
    z = 1.959963985
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (round(100 * max(0.0, c - h), 2), round(100 * min(1.0, c + h), 2))


def ask(url: str, model: str, item: dict, args) -> dict:
    body = {
        "model": model,
        "messages": [{"role": "user",
                      "content": f"{item['question']}\n\n{INSTRUCTION}"}],
        "max_tokens": args.max_tokens,
        "temperature": args.temperature,
        "chat_template_kwargs": {"enable_thinking": not args.no_thinking},
    }
    if args.temperature > 0:
        body["top_p"] = args.top_p
    req = urllib.request.Request(
        url, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json",
                 **({"Authorization": "Bearer " + os.environ["VLLM_API_KEY"]} if os.environ.get("VLLM_API_KEY") else {})},
        method="POST")
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=args.timeout) as fh:
        d = json.load(fh)
    elapsed = time.time() - t0
    choice = d["choices"][0]
    msg = choice["message"]
    content = msg.get("content") or ""
    # With --reasoning-parser qwen3 the chain of thought arrives in `reasoning`
    # and `content` holds only the conclusion. When the cap lands inside the
    # think block, `content` is empty and the answer, if any, is in `reasoning`.
    reasoning = msg.get("reasoning") or msg.get("reasoning_content") or ""
    got = parse_answer(content) or parse_answer(reasoning)
    usage = d.get("usage", {})
    finish = choice.get("finish_reason")
    truncated = finish == "length"
    # A truncated reply is not an answer, even when the last number in the
    # unfinished chain of thought happens to be the right one. Scoring those as
    # correct would let a length regression — which is a real failure mode on
    # this checkpoint (long generations run longer than BF16, per its card) —
    # hide behind a lucky parse. `lucky_parse` keeps the case visible.
    ok = same_number(got, item["answer"]) and not truncated
    return {
        "source_index": item["source_index"],
        "want": item["answer"],
        "got": got,
        "pass": ok,
        "lucky_parse": truncated and same_number(got, item["answer"]),
        "finish_reason": finish,
        "truncated": truncated,
        "completion_tokens": usage.get("completion_tokens"),
        "prompt_tokens": usage.get("prompt_tokens"),
        "elapsed_s": round(elapsed, 2),
        "answer": content.strip()[:600],
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default="localhost")
    ap.add_argument("--port", type=int, default=8000)
    ap.add_argument("--model", default="qwen3.8-flash-next")
    ap.add_argument("--subset", default=str(SUBSET))
    ap.add_argument("--n", type=int, default=0,
                    help="score only the first N problems of the subset "
                         "(0 = all); use for a pilot that sizes the budget")
    ap.add_argument("--concurrency", type=int, default=2,
                    help="requests in flight (default 2). The server's "
                         "--max-num-seqs is the real cap; more only queues.")
    ap.add_argument("--temperature", type=float, default=REF_TEMPERATURE)
    ap.add_argument("--top-p", type=float, default=REF_TOP_P)
    ap.add_argument("--max-tokens", type=int, default=3072,
                    help=f"the reference protocol used {REF_MAX_TOKENS}; the default "
                         f"here is lower to bound the run time. Answers that hit "
                         f"the cap are counted as `truncated` as well as wrong.")
    ap.add_argument("--no-thinking", action="store_true",
                    help="send enable_thinking: false. Much cheaper and not the "
                         "reference protocol: compare only with other "
                         "--no-thinking runs.")
    ap.add_argument("--timeout", type=float, default=1800.0)
    ap.add_argument("--label", default="")
    ap.add_argument("--json", dest="json_out", default="")
    args = ap.parse_args()

    items = [json.loads(line) for line in
             pathlib.Path(args.subset).read_text().splitlines() if line.strip()]
    if args.n:
        items = items[:args.n]
    url = f"http://{args.host}:{args.port}/v1/chat/completions"

    print(f"host={args.host}:{args.port} model={args.model} "
          f"n={len(items)} concurrency={args.concurrency} "
          f"temperature={args.temperature} top_p={args.top_p} "
          f"max_tokens={args.max_tokens} "
          f"thinking={'off' if args.no_thinking else 'on'}")

    t0 = time.time()
    results: list[dict] = [None] * len(items)   # type: ignore[list-item]
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        futures = {pool.submit(ask, url, args.model, item, args): i
                   for i, item in enumerate(items)}
        done = 0
        for fut in concurrent.futures.as_completed(futures):
            i = futures[fut]
            results[i] = fut.result()
            done += 1
            r = results[i]
            mark = "PASS" if r["pass"] else ("TRUNC" if r["truncated"] else "FAIL")
            print(f"  [{done:>3}/{len(items)}] {mark:<5} "
                  f"#{r['source_index']:<5} want={r['want']:<10} "
                  f"got={str(r['got']):<10} {r['completion_tokens']} tok "
                  f"{r['elapsed_s']}s")
    elapsed = time.time() - t0

    passed = sum(r["pass"] for r in results)
    truncated = sum(r["truncated"] for r in results)
    comp = [r["completion_tokens"] or 0 for r in results]
    lo, hi = wilson(passed, len(results))
    accuracy = round(100 * passed / len(results), 2)

    print(f"\n  GSM8K subset: {passed}/{len(results)} = {accuracy}%  "
          f"(95% Wilson {lo}-{hi})")
    lucky = sum(r["lucky_parse"] for r in results)
    print(f"  truncated at the {args.max_tokens}-token cap: {truncated} "
          f"(scored wrong; {lucky} of them parsed to the right number anyway)")
    print(f"  completion tokens: total {sum(comp)}, mean {round(sum(comp)/len(comp), 1)}, "
          f"max {max(comp)}")
    print(f"  wall clock: {round(elapsed, 1)}s at concurrency {args.concurrency}")

    record = {
        "probe": "GSM8K fixed subset",
        "label": args.label,
        "endpoint": f"http://{args.host}:{args.port}",
        "model": args.model,
        "subset": str(pathlib.Path(args.subset).name),
        "n": len(results),
        "protocol": {
            "temperature": args.temperature,
            "top_p": args.top_p if args.temperature > 0 else None,
            "max_tokens": args.max_tokens,
            "thinking": not args.no_thinking,
            "concurrency": args.concurrency,
            "reference_protocol": "full 1319, temperature 0.6, top_p 0.95, max_tokens 8192, thinking on",
            "deviation_from_reference": [
                d for d in [
                    f"{len(results)} problems, not 1319",
                    (f"max_tokens {args.max_tokens}, not {REF_MAX_TOKENS}"
                     if args.max_tokens != REF_MAX_TOKENS else ""),
                    ("thinking disabled" if args.no_thinking else ""),
                    (f"temperature {args.temperature}, not {REF_TEMPERATURE}"
                     if args.temperature != REF_TEMPERATURE else ""),
                ] if d
            ],
        },
        "passed": passed,
        "accuracy_percent": accuracy,
        "wilson95_percent": [lo, hi],
        "truncated": truncated,
        "truncated_but_right_number": lucky,
        "completion_tokens": {"total": sum(comp),
                              "mean": round(sum(comp) / len(comp), 1),
                              "max": max(comp)},
        "elapsed_s": round(elapsed, 1),
        "trials": results,
    }
    if args.json_out:
        pathlib.Path(args.json_out).write_text(json.dumps(record, indent=2) + "\n")
        print(f"  wrote {args.json_out}")

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except urllib.error.URLError as exc:
        print(f"server unreachable: {exc}", file=sys.stderr)
        sys.exit(2)
