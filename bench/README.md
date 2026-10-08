# How the numbers were measured

All results come from one DGX Spark with the recipe's server bound to localhost and nothing else sending
requests. Each results directory (`results/<build>/`) holds the raw files, the build identity and a summary.

## Third-party harness (speed)

`./run-third-party.sh` fetches tonyd2wild's `single-spark-vllm-tp1/tools/bench_categories.py` at commit
`6ad1c8f15cbab1ababd2048e8e5f94094dbfc4a0` (sha256-checked) and runs it unchanged:

- 40 fixed prompts in 8 categories (coding, reasoning, JSON, HTML, prose, narrative, summary, format).
- Thinking off, temperature 0 (hard-coded in the harness), max_tokens 900, streaming.
- Decode speed per prompt = (completion tokens - 1) / (time of last token - time of first token).
- 1 stream: three runs (tags a, b, c); the figure is the median of the three runs' 40-prompt medians.
- 6 streams: one run; the figure is the median over its 7 batches of (completion tokens / batch wall time).
- Before the harness, the same server had run about 30 minutes of other load in the same session (a 12-check
  endpoint suite, a 68-prompt probe in two modes, and throughput cells at 1, 2 and 4 requests). Prefix caching is on:
  runs b and c at 1 stream, and the 6-stream run, hit the prefix cache for the harness prompts. That does not change
  the decode-speed metric; it shortens time to first token, which the 6-stream aggregate includes.
- Its auto-score checks format and length (word ranges, bullet counts, JSON fields) and executes returned code
  against unit tests; it is not a general accuracy measure.

Statistic and spread are reported as measured; there is no noise floor for these cells.

## Quality

`quality/gsm8k.py` scores a fixed 100-problem GSM8K subset (`quality/gsm8k-subset.jsonl`, seeded selection in
`quality/gsm8k-subset.provenance.json`) at temperature 0.6, top-p 0.95, thinking on, with answers capped at 3072
tokens (an answer that hits the cap is wrong and is counted as truncated). The 0.6 / 0.95 setting follows the
Qwen3.8-Flash-Next NVFP4 evaluations published by other quantizers; NVIDIA's card for this checkpoint publishes no
GSM8K figure. A score in the high 90s says the build is not broken; it does not resolve one-point differences.

```bash
python3 quality/gsm8k.py --json gsm8k.json      # about 7-10 minutes on one Spark
```

Our results also list fixed checks run with the same build: 12 no-chain-of-thought arithmetic items, 10 short
tasks with checkable answers, a needle retrieved from about 131K tokens of context, and a prefix-cache canary
(the same answer cold and warm). Those tools are not in this repo yet.

Planned: `lm_eval` GSM8K 5-shot with its standard error, the format vLLM's own recipes use.
