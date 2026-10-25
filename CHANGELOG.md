# Changelog

Newest first. Each entry is one build that passed our gates on our Spark: the vLLM nightly it is built on, the
patches it carries, its headline numbers and its results directory (never overwritten). Treat them as one host's
numbers, not promises.

## Recipe tooling (between builds)

- Two ways to run a build. **prod**: `./recipe/qfn up` pulls the exact image our nightly gates measured (pinned by
  registry digest in `recipe/pins.env` as `PROD_IMAGE`, signed with `recipe/cosign.pub`), starts it in the
  background, waits, warms it up and verifies it; `./recipe/launch.sh --prod` and `./recipe/pull.sh` are the steps.
  **dev**: `./recipe/qfn dev` rebuilds the same serving code (AST-identical Python, checked at publish time) from the
  pinned base and `recipe/patches` and runs it in your terminal; it is a different image from prod's. `./recipe/qfn` is one entry point for every script (`preflight`, `download`, `pull`, `build`, `start`,
  `verify`, `stop`, `status`, `upgrade`); the scripts still run on their own. A build gets a published image from
  its next release on; until then `qfn up` says so and `qfn dev` is the way to run it.
- `preflight.sh` no longer fails Docker hosts that run `--gpus` through the NVIDIA Container Toolkit's hook without
  an `nvidia` runtime in `/etc/docker/daemon.json` (as on at least one user's Spark); it accepts the hook, the runtime or a CDI spec.
  Thanks to rtamax on the NVIDIA forum.
- `launch.sh -- ARGS` changes or adds vLLM arguments for one run without editing `serve.args`, e.g.
  `./recipe/launch.sh -- --max-model-len 131072`: a flag already in `serve.args` gets the new value in place, any other
  is added, and each change is printed with a note that the run is no longer the measured configuration. In the
  foreground, `launch.sh` now says that Ctrl-C during the weight load takes effect only when the load ends, and that
  `./recipe/stop.sh` stops it at once. Troubleshooting covers the KV-cache-too-small error.
- `launch.sh` watches memory during the load: every 10 s it samples free memory, the server's own memory and every
  process outside the server container (CPU and GPU memory), warns when one grows by 2 GiB or more or holds GPU memory,
  and logs a summary to `CACHE_DIR/logs/memwatch-<time>.log`, which `diagnose.sh` includes. `MEMWATCH=0` skips it.
- `recipe/diagnose.sh` gathers what we need to help with a problem into one report to paste into a forum post or an
  issue: host, DGX OS, driver, Docker, memory, the checkpoint's disk and file system, `preflight.sh`, the exact launch
  command, kernel out-of-memory messages and, from the container or a saved log (`WARMUP=0 ./recipe/launch.sh 2>&1 |
  tee -i launch.log`), the server's memory lines and its last lines. It is read-only and sends nothing unless you
  confirm `--issue`, which files it as a public GitHub issue. It replaces your user name, home folder, host name,
  API keys and tokens with placeholders, and keeps the report under a forum post's size limit.
- `preflight.sh` checks versions: the driver, Docker, buildx and the NVIDIA Container Toolkit warn when older than
  the versions we tested and say how to update; a driver whose CUDA version is below what the image needs fails. It
  also tells a user who cannot reach Docker how to join the `docker` group, reports the DGX OS version, and warns
  when `curl`, `python3` or `git` is missing.
- `launch.sh` can serve a build with a sparse draft head (vllm#59740), whose drafter reads a token map at
  `/root/.cache/draft-token-maps/<sha256>.json`. When `serve.args` names one, `launch.sh` checks that
  `recipe/draft-token-maps/<sha256>.json` exists and hashes to its name, and copies it into `CACHE_DIR` (mounted at
  `/root/.cache`) before `docker run`; it refuses to start otherwise, and `--print` checks without copying.
  `preflight.sh` reports the same check. A build that names no map runs exactly as before.
- Once the server answers, `launch.sh` sends it two short requests (one greedy, one sampled), so the Triton kernels
  that otherwise compile during the first request (a slow first answer) compile before you send yours. In the
  foreground it prints `warm-up done`; `WARMUP=0` skips it. `preflight.sh` reads the hf CLI version in both forms
  `hf version` prints (`version=X` and `version: X`; it showed `?` before), and `docker build` no longer warns
  `InvalidDefaultArgInFrom`. Found by testing the recipe as a first-time user (fresh clone, empty cache, full
  download, no-cache build).
- `launch.sh` runs the server in your terminal by default, so you watch it load and Ctrl-C stops it;
  `--detach` keeps the old background behaviour (scripts that expect `launch.sh` to return must now add `--detach`).
  Thanks to whpthomas on the NVIDIA forum.
- `preflight.sh` checks the Hugging Face CLI (it needs `hf cache verify` and `prune`) and the cache: the cache in use,
  every checkpoint file present and inside the mounted folder, partial downloads and old revisions, with the command
  that fixes each; `--verify` hashes the checkpoint against the hub and `--fix` re-runs `download.sh`. It never deletes.
- `preflight.sh` reports other GPU processes and containers holding memory (they shrink the KV pool) and the
  checkpoint disk's read-ahead (8192 KB loads about 100 s faster than the 128 KB default).
- README: an "Upgrading to a newer build" section; builds are tagged `build-<date>-<vllm sha8>`.
- Troubleshooting: what each load-time warning means, and how to keep read-ahead across reboots.
- 2026-10-11: `launch.sh` finds the checkpoint the way `hf download` does (`HF_HUB_CACHE`, then `HF_HOME/hub`, then
  `~/.cache/huggingface/hub`) and, before starting, checks that every model file resolves inside the folder the
  container mounts, naming any that does not (a cache moved to another disk behind a symlink loaded on the host but
  failed in the container with `FileNotFoundError`; reported by rtamax on the NVIDIA forum). It also refuses to start
  with less than 98 GiB of memory available (`MIN_FREE_GIB`) or when a container of the same name exists, and lists
  other GPU containers and processes; `FORCE=1` skips the memory check and the list. `download.sh` verifies in the
  same cache.

<!-- generated:entries -->
## 2026-10-22-8e2beaa3

- Base: vLLM `8e2beaa3bff595577a069d49d96bde9074294ec2` (`vllm/vllm-openai@sha256:167ccd8696bc09f1b63301185134e04b883623f8adcbd8e3a0ec3140a193abcf`).
- Patches: 0001-vllm58815-ple-host-file-gather, 0002-fp8-dense-and-draft-vocab, 0003-vllm59973-nvfp4-draft-lm-head, 0004-vllm58681-restore-sm12x-alignment-behavior-for, 0005-quiet-boot, 0006-mtp-shard-filter, 0007-vllm54912-widen-the-qsa-raw-key-ring, 0008-vllm60068-confidence-stop-for-autoregressive-drafting, 0009-skinny-gemm-rows, 0010-vllm58863-recoverssm-for-qwen-gdn-and, 0011-vllm59740-context-aware-sparse-lm-head, 0012-moe-batched-load, 0013-vllm62841-avoid-re-marking-committed-prompt-tail-boundaries, 0014-draft-head-per-batch.
- Harness: 69.3 tok/s median at 1 stream, 91.9 aggregate at 6 (85.1 total output over the run); GSM8K subset 99/100.
- Measured again on 2026-10-25 on a fresh boot of the same image: 69.3 tok/s at 1 stream, 92.4 aggregate at 6 (87.9 total output).
- Results: `results/2026-10-22-8e2beaa3/`.
- Tag: `build-2026-10-22-8e2beaa3`.

## 2026-10-14-77154ca6

- Base: vLLM `77154ca6116ae34cbfe314beef1016bde9b63989` (`vllm/vllm-openai@sha256:a7deff2c216def98c193352aca50fb03a2ee29231355b3033dc3789009f6d23e`).
- Patches: 0001-vllm58815-ple-host-file-gather, 0002-fp8-dense-and-draft-vocab, 0003-vllm59973-nvfp4-draft-lm-head, 0004-vllm58681-restore-sm12x-alignment-behavior-for, 0005-vllm58737-fuse-the-mamba-align-block-table, 0006-vllm59260-warm-up-top-k-top-p-and-greedy, 0007-quiet-boot, 0008-mtp-shard-filter, 0009-vllm54912-widen-the-qsa-raw-key-ring, 0010-vllm60068-confidence-stop-for-autoregressive-drafting, 0011-skinny-gemm-rows, 0012-vllm58863-recoverssm-for-qwen-gdn-and, 0013-vllm59740-context-aware-sparse-lm-head, 0014-moe-batched-load.
- Harness: 71.3 tok/s median at 1 stream, 84.4 aggregate at 6; GSM8K subset 99/100.
- Measured again on 2026-10-15 after serving a day: 71.8 tok/s at 1 stream, 84.0 aggregate at 6.
- Results: `results/2026-10-14-77154ca6/`.
- Tag: `build-2026-10-14-77154ca6`.

## 2026-10-08-81198e97

- Base: vLLM `81198e97ba7eee2a22540caaa756b7fdddcb4d93` (`vllm/vllm-openai@sha256:a83c7f976879e0c6101f734fd5b84a098d12d6d8d12baa41e31eb323b84b0802`).
- Patches: 0001-vllm58815-ple-host-file-gather, 0002-fp8-dense-and-draft-vocab, 0003-vllm59973-nvfp4-draft-lm-head, 0004-vllm58681-restore-sm12x-alignment-behavior-for, 0005-vllm58737-fuse-the-mamba-align-block-table, 0006-vllm59528-keep-the-glm-5-3-kpool-tail.
- Harness: 67.5 tok/s median at 1 stream, 90.7 aggregate at 6; GSM8K subset 99/100.
- Results: `results/2026-10-08-81198e97/`.
<!-- /generated:entries -->
