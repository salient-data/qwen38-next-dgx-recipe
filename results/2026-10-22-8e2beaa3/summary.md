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
| clean first-time run on 2026-10-25 (host rebooted, fresh clone, image and checkpoint downloaded), same columns | 69.8 (runs 68.5 / 69.8 / 70.0) / 41.5 / 82.6 / 81.4 | - |
| 6 streams, three more runs on a second boot that evening, aggregate / total output | 88.2 / 83.5, 90.3 / 85.7, 90.3 / 85.3 | - |

For scale: tonyd2wild's own recipe, which we reran on our Spark on 2026-10-03 with the same harness, measured 42.6 / 28.4 / 64.2 tok/s on the three speed rows. Caveats: to load checkpoint fc694b54 we added an FP8_PB_WO alias to their stack and built its image from source; one run; the 1-stream figure pools three partial runs; prefix caching off. Its raw data is not in this repo.

Raw harness output: `harness/` (byte-identical to the run; its `lane` field reads `nightly`); the second measurement of the same build, taken on 2026-10-25 on a fresh boot of the same image: `harness-confirm/`. The clean first-time run and the three later 6-stream runs: `harness-clean/`, with its GSM8K record (`harness-clean/gsm8k.json`, 99/100) and the boot lines (`harness-clean/boots.txt`). Quality: `quality.json` and the raw records in `quality/` (from `quality/gsm8k.json` we removed three reference fields that pointed at another quantization's model card). Build identity: `identity.json`.
KV pool on the 2026-10-22 boot: 1,088,467 tokens (aggregate capacity, not one request's context).

The first 6-stream run after a server start was slower both times we measured it. In the clean run (after a host reboot), batch 1 of 7 measured 76.6 tok/s against 96-101 in the warm runs. The headline is the median batch, so it fell 10% (91.9 to 82.6) while total output fell 4% (85.1 to 81.4). After a restart without a reboot, batch 1 measured 88.2, then 99.4 and 100.0 in the next two runs. Batches 2-7 stayed within 6% of the published run. The host for the clean run already had read-ahead at 8192, so its preflight did not warn about it.
