# Results for build 2026-10-22-8e2beaa3

Measured 2026-10-22 on one DGX Spark with the server bound to localhost and nothing else running.

| metric (tonyd2wild `bench_categories.py` @ 6ad1c8f, unchanged) | this recipe | published by tonyd2wild (their Spark) |
|---|---|---|
| 1 stream, median decode tok/s over 40 prompts | **69.3** (runs 66.8 / 69.5 / 69.3) | 43.9 |
| 1 stream, prose median tok/s | **41.0** (runs 39.7 / 41.1 / 41.0) | 29.0 |
| 6 streams, median batch aggregate tok/s | **91.9** (1 run) | 68.8 |
| 6 streams, total output tok/s over the run (all prompts, all 7 batches; same run) | 85.1 | - |
| harness auto-score (format and length), 1 / 6 streams | 0.876 / 0.86 | 0.88 / 0.827 |
| GSM8K, fixed 100-problem subset (temperature 0.6, top-p 0.95, thinking on, max 3072 tokens) | **99/100** (Wilson 95% 94.55-99.82%) | - |
| fixed checks: arithmetic, ten tasks, ~131K needle, prefix-cache canary | 12/12, 9/10, pass, pass | - |
| measured again on 2026-10-25 on a fresh boot of the same image, 1 stream median / prose / 6 streams aggregate / 6 streams total output | 69.3 (runs 67.2 / 69.4 / 69.3) / 40.5 / 92.4 / 87.9 | - |

For scale: tonyd2wild's own recipe, which we reran on our Spark on 2026-10-03 with the same harness, measured 42.6 / 28.4 / 64.2 tok/s on the three speed rows. Caveats: to load checkpoint fc694b54 we added an FP8_PB_WO alias to their stack and built its image from source; one run; the 1-stream figure pools three partial runs; prefix caching off. Its raw data is not in this repo.

Raw harness output: `harness/` (byte-identical to the run; its `lane` field reads `nightly`); the second measurement of the same build, taken on 2026-10-25 on a fresh boot of the same image: `harness-confirm/`. Quality: `quality.json` and the raw records in `quality/` (from `quality/gsm8k.json` we removed three reference fields that pointed at another quantization's model card). Build identity: `identity.json`.
KV pool on this boot: 1,088,467 tokens (aggregate capacity, not one request's context).
