# Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| `build.sh`: `manifest unknown` on the base image | Docker Hub pruned the nightly tag | Use the newest build in the CHANGELOG, or the source-build fallback in the README |
| `build.sh`: a patch does not apply | The base is not the pinned commit, or the patch was edited | Use the pinned digest; `sha256sum -c recipe/patches.sha256` must pass |
| `FileNotFoundError: /hfrepo/snapshots/.../model-00001-of-00010.safetensors`, or `launch.sh` reports a file "outside" the model folder | The container mounts only the model folder (`models--nvidia--Qwen3.8-Flash-Next-NVFP4`); its snapshot files are links into `blobs/`, and a link that leaves the folder (a cache moved to another disk behind a symlink) does not resolve in the container. Or `HF_HUB_CACHE` points elsewhere | Keep `snapshots/` and `blobs/` under one folder and run `MODEL_DIR=/path/to/models--nvidia--Qwen3.8-Flash-Next-NVFP4 ./launch.sh`; `launch.sh` honors `HF_HUB_CACHE` and checks every file before it starts |
| Container exits during load, `out of memory` / killed | Not enough free memory at start | Stop other GPU and memory-heavy work; check `free -g` shows about 100 GiB available (`launch.sh` refuses below 98 GiB, `MIN_FREE_GIB`, and lists other GPU containers and processes); see docs/memory-budget.md |
| Load takes much longer than 11 minutes | Slow or busy disk under the Hugging Face cache | Keep the checkpoint on local NVMe |
| `verify.sh` fails with fluent but wrong answers | The PLE tables are read without their FP8 scale (a broken or different build) | Rebuild from the pinned base and patches; do not mix images |
| `verify.sh` cannot connect | Still loading, or bound elsewhere | `docker logs -f qwen38-flash-next`; check `BIND`/`PORT` |
| HTTP 400 when setting `reasoning_effort` | The chat template accepts only `low`, `medium`, `xhigh` | Use one of those values |
| Slower than the results table | Other load on the box, thinking on, non-English text (the drafter covers token ids below 65,536), or a different driver | Compare with `./recipe/launch.sh --print` and the pins; report with the issue template |

Reporting a reproduction or a problem: open an issue with the
[reproduction report template](../.github/ISSUE_TEMPLATE/reproduction-report.md).
