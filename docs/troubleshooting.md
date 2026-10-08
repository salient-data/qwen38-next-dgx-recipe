# Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| `build.sh`: `manifest unknown` on the base image | Docker Hub pruned the nightly tag | Use the newest build in the CHANGELOG, or the source-build fallback in the README |
| `build.sh`: a patch does not apply | The base is not the pinned commit, or the patch was edited | Use the pinned digest; `sha256sum -c recipe/patches.sha256` must pass |
| Container exits during load, `out of memory` / killed | Not enough free memory at start | Stop other GPU and memory-heavy work; check `free -g` shows about 100 GiB available; see docs/memory-budget.md |
| Load takes much longer than 11 minutes | Slow or busy disk under the Hugging Face cache | Keep the checkpoint on local NVMe |
| `verify.sh` fails with fluent but wrong answers | The PLE tables are read without their FP8 scale (a broken or different build) | Rebuild from the pinned base and patches; do not mix images |
| `verify.sh` cannot connect | Still loading, or bound elsewhere | `docker logs -f qwen38-flash-next`; check `BIND`/`PORT` |
| HTTP 400 when setting `reasoning_effort` | The chat template accepts only `low`, `medium`, `xhigh` | Use one of those values |
| Slower than the results table | Other load on the box, thinking on, non-English text (the drafter covers token ids below 65,536), or a different driver | Compare with `./recipe/launch.sh --print` and the pins; report with the issue template |

Reporting a reproduction or a problem: open an issue with the
[reproduction report template](../.github/ISSUE_TEMPLATE/reproduction-report.md).
