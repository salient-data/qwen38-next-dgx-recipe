# Qwen3.8-Flash-Next (NVFP4) on one DGX Spark: a reproducible vLLM recipe

This recipe serves [`nvidia/Qwen3.8-Flash-Next-NVFP4`](https://huggingface.co/nvidia/Qwen3.8-Flash-Next-NVFP4)
on **one NVIDIA DGX Spark** (GB10, 121 GiB unified memory). It uses a pinned vLLM nightly image, a short series
of patches applied with `patch --fuzz=0`, and one `docker run`. The model is a ~180B multimodal MoE with a
51.2 GB PLE n-gram table; the recipe fits it on one Spark by never making that table resident (see
[docs/memory-budget.md](docs/memory-budget.md)). Every number below names its harness, settings and run count, and
says where its raw data is.

## Status and disclaimer

<!-- generated:verified -->
Last verified: **2026-10-08**, build `2026-10-08-81198e97`.
<!-- /generated:verified -->

- **Community recipe.** Not affiliated with or endorsed by NVIDIA, Qwen or the vLLM project.
- **Outside the model card's support statement.** The card lists B200 and B300 only; GB10 is not listed. This
  recipe is what we run and measure on our own Spark.
- **Built on vLLM nightly.** We rebuild nightly against vLLM main and update this repo only when a build passes
  our gates; each update is a [CHANGELOG](CHANGELOG.md) entry with its own results directory. Results are this
  host's numbers, not promises.

## Results

<!-- generated:results -->
Build `2026-10-08-81198e97` (vLLM `81198e97` + 6 patches), measured 2026-10-08:

| metric (tonyd2wild `bench_categories.py` @ 6ad1c8f, unchanged) | this recipe | published by tonyd2wild (their Spark) |
|---|---|---|
| 1 stream, median decode tok/s over 40 prompts | **67.5** (runs 65.2 / 67.5 / 67.5) | 43.9 |
| 1 stream, prose median tok/s | **38.5** (runs 38.0 / 38.5 / 38.6) | 29.0 |
| 6 streams, median batch aggregate tok/s | **90.7** (1 run) | 68.8 |
| harness auto-score (format and length), 1 / 6 streams | 0.91 / 0.83 | 0.88 / 0.827 |
| GSM8K, fixed 100-problem subset (temperature 0.6, top-p 0.95, thinking on, max 3072 tokens) | **99/100** (Wilson 95% 94.55-99.82%) | - |
| fixed checks: arithmetic, ten tasks, ~131K needle, prefix-cache canary | 12/12, 9/10, pass, pass | - |

For scale: tonyd2wild's own recipe, which we reran on our Spark on 2026-10-03 with the same harness, measured 42.6 / 28.4 / 64.2 tok/s on the three speed rows. Caveats: to load checkpoint fc694b54 we added an FP8_PB_WO alias to their stack and built its image from source; one run; the 1-stream figure pools three partial runs; prefix caching off. Its raw data is not in this repo.

Raw data, identity and quality: [`results/2026-10-08-81198e97/`](results/2026-10-08-81198e97/).
<!-- /generated:results -->

How to read this table:
- The speed rows are a **recipe comparison** with tonyd2wild's published figures, measured on two different Sparks
  on different dates. Our recipe and theirs differ in vLLM build, how the PLE rows are read (per step in the forward
  pass here, a staged gather in theirs), speculation settings (we draft 4 tokens with one request and 3 with two to
  six), dense-layer precision (we cast BF16 dense layers to FP8 block-128), draft head (NVFP4 here), KV dtype of the
  MTP layer (BF16 here) and **prefix caching (on here, off in theirs)**. Prefix
  caching does not change the 1-stream decode metric; it shortens time to first token, which the 6-stream
  aggregate includes (we estimate at most 1-2% of it).
- Their README does not state the checkpoint revision of their run; ours is pinned below.
- No noise floor exists for these cells. The 6-stream figure is a single run; the 1-stream runs spread as shown.
- The harness auto-score checks format and length (word counts, bullet counts, a 900-token cap) and runs the
  coding answers against unit tests; it is not a general accuracy measure. The GSM8K and fixed-check rows are.
- Raw data: the harness output files and the GSM8K, arithmetic, needle and canary records are in `results/`. The
  tools for the fixed checks are not published yet.

## What you need

| Requirement | Check |
|---|---|
| One NVIDIA DGX Spark (GB10, aarch64) | `nvidia-smi` shows `NVIDIA GB10` |
| NVIDIA driver; tested with the open kernel module driver (version in the pins table) | `cat /proc/driver/nvidia/version` |
| Docker with the NVIDIA container runtime | `docker info \| grep -i nvidia` |
| About 100 GiB free memory when nothing else runs | `free -g` |
| About 200 GB free disk (checkpoint ~135 GB, image ~25 GB) | `df -h ~/.cache/huggingface` |
| A Hugging Face token with access to the model | `hf auth whoami` |

`./recipe/preflight.sh` runs these checks without changing anything. It also checks the Hugging Face CLI and cache:
which cache is in use (`HF_HUB_CACHE`, `HF_HOME`), that every checkpoint file is present and readable from the
container, and leftover partial downloads or old revisions. It never deletes anything; it prints the command that fixes
each problem. `--verify` hashes every checkpoint file against the hub (`hf cache verify`; it reads all ~135 GB), and
`--fix` re-runs `download.sh`, which resumes partial downloads and only adds files.

## Quick start

```bash
git clone https://github.com/salient-data/qwen38-next-dgx-recipe && cd qwen38-next-dgx-recipe
./recipe/preflight.sh            # read-only checks
./recipe/download.sh             # hf download at the pinned revision, then verifies file hashes
./recipe/build.sh                # pulls the pinned base by digest (~10 GB download, ~25 GB on disk), applies the patches
./recipe/launch.sh --print       # shows the exact docker command
./recipe/launch.sh               # runs it in this terminal so you watch it load (10-12 minutes, below); Ctrl-C stops it
./recipe/verify.sh               # from a second terminal: two known-answer requests
./recipe/stop.sh                 # stop and remove the container
```

When the server answers, `launch.sh` sends it two short warm-up requests so the first real answer is not slowed by
kernel compilation (`warm-up done` in the foreground; `WARMUP=0` skips it).

In the foreground, Ctrl-C during the weight load takes effect only when the load ends; `./recipe/stop.sh` (from another
terminal) stops and removes the container at once.

Once you trust it, `./recipe/launch.sh --detach` runs the same command in the background (follow it with
`docker logs -f qwen38-flash-next`).

To change a vLLM argument for one run, put it after `--`: `./recipe/launch.sh -- --max-model-len 131072`. A flag
`serve.args` already has gets the new value, and any other flag is added; `launch.sh` prints each change. Leave
`serve.args` itself unedited, so `git pull` stays clean, and say what you changed when you report numbers.

On a cold disk most of the load is reading weights; raising the disk's
read-ahead from the distro default of 128 KB to 8192 KB takes a cold load from about 12 minutes to about 10
(707 to 606 s on our Spark; `preflight.sh` checks it; see
[troubleshooting](docs/troubleshooting.md)).

The server binds `127.0.0.1:8000` and serves an OpenAI-compatible API with the model name `qwen3.8-flash-next`.
`BIND=0.0.0.0` exposes it on every interface **without authentication** unless you also set `VLLM_API_KEY`
(passed to the container as an environment variable; clients then send `Authorization: Bearer <key>`).
Thinking is off by default; turn it on per request with `"chat_template_kwargs": {"enable_thinking": true}`.

## Upgrading to a newer build

Each build is one [CHANGELOG](CHANGELOG.md) entry and one git tag, `build-<date>-<vllm sha8>` (the first,
`build-2026-10-08-81198e97`, is tagged after the fact); `main` is always the newest build that passed our gates.
Changes to the scripts alone (like this section) land on `main` between builds and are listed in the CHANGELOG
under "Recipe tooling". To move to the newest build:

```bash
./recipe/stop.sh
git checkout main && git pull    # or: git checkout build-<date>-<sha8> for a specific build
./recipe/preflight.sh
./recipe/download.sh             # downloads only if the model revision changed; verifies the small config and tokenizer files (the hub checks the weights as they download)
./recipe/build.sh                # builds the new image; the old one stays until you remove it
./recipe/launch.sh --detach      # in the background, so the next line can run (or run launch.sh in its own terminal)
./recipe/verify.sh               # once it answers, 10-12 minutes later
```

To go back, `git checkout` the previous tag and run `build.sh` and `launch.sh` again; its image is still on disk
unless you removed it (`docker images qwen38-next-dgx`). A build's speed and quality numbers are in its results
directory and do not carry over to another build.

## What is pinned

<!-- generated:pins -->
| Pinned | Value |
|---|---|
| Base image | `vllm/vllm-openai@sha256:a83c7f976879e0c6101f734fd5b84a098d12d6d8d12baa41e31eb323b84b0802` (nightly of vLLM `81198e97ba7eee2a22540caaa756b7fdddcb4d93`) |
| vLLM | `0.31.1rc1.dev88+g81198e97b`, torch `2.13.0+cu130`, FlashInfer `0.7.0.post1` |
| Model | `nvidia/Qwen3.8-Flash-Next-NVFP4` @ `fc694b54fb0174e0913e6adf86691ef85a4ead47` |
| Patches | 6, listed in [`recipe/patches/PROVENANCE.md`](recipe/patches/PROVENANCE.md) |
| Tested driver | 580.178.04 (open kernel module), kernel `7.0.0-1019-nvidia`, Docker 29.6.2 |
| Launch | [`recipe/serve.args`](recipe/serve.args), [`recipe/serve.env`](recipe/serve.env), `./recipe/launch.sh --print` |
<!-- /generated:pins -->

The full specification is [`recipe/recipe.yaml`](recipe/recipe.yaml). Changing any pinned value makes a different
recipe whose speed and quality must be measured again.

### If the base image is gone

Docker Hub prunes `vllm/vllm-openai:nightly-<sha>` tags after about two weeks, so a digest pin can stop resolving.
The pins name the vLLM commit the image was built from. To rebuild the base from source at that commit:

```bash
git clone https://github.com/vllm-project/vllm && cd vllm && git checkout "$VLLM_COMMIT"   # from recipe/pins.env
DOCKER_BUILDKIT=1 docker build -f docker/Dockerfile --target vllm-openai -t vllm-base:"$VLLM_COMMIT" .
# then: docker build -f ../recipe/Dockerfile --build-arg BASE=vllm-base:"$VLLM_COMMIT" -t qwen38-next-dgx:local ../recipe
# and launch it with: IMAGE=qwen38-next-dgx:local ../recipe/launch.sh
```

We have not tested this fallback: building vLLM from source on a Spark takes hours, and an aarch64 CUDA 13 build may
need build arguments (see vLLM's Docker build docs). The simpler path is the newest build in this repo's CHANGELOG.

## The patches

<!-- generated:patches -->
- `0001-vllm58815-ple-host-file-gather.patch`: Reads the 51.2 GB PLE n-gram table's rows from the checkpoint's safetensors file each step (pread with a 64-worker pool), so the table is never resident and the model fits in 121 GiB. ([vllm#58815](https://github.com/vllm-project/vllm/pull/58815), open)
- `0002-fp8-dense-and-draft-vocab.patch`: QWEN38_FP8_DENSE casts the checkpoint's BF16 dense linears (GDN, QSA, shared experts, MTP dense, lm_head) to 128x128 block FP8 at load (197 linears); QWEN4EXP_DRAFT_VOCAB limits MTP drafting to token ids below 65,536; keeps the QSA indexer projection unfused so its rows stay BF16.
- `0003-vllm59973-nvfp4-draft-lm-head.patch`: Quantizes the MTP drafter's lm_head (the 65,536 reduced-vocabulary rows) to NVFP4. ([vllm#59973](https://github.com/vllm-project/vllm/pull/59973), open)
- `0004-vllm58681-restore-sm12x-alignment-behavior-for.patch`: Restore SM12x alignment behavior for grouped GEMMs ([vllm#58681](https://github.com/vllm-project/vllm/pull/58681), open)
- `0005-vllm58737-fuse-the-mamba-align-block-table.patch`: Fuse the mamba align block-table gather into one Triton kernel, 7 kernels -> 1, 6x speedup on all shapes for this kernel ([vllm#58737](https://github.com/vllm-project/vllm/pull/58737), open)
- `0006-vllm59528-keep-the-glm-5-3-kpool-tail.patch`: Keep the GLM-5.3 kpool tail and Qwen4 QSA ring out of the null block ([vllm#59528](https://github.com/vllm-project/vllm/pull/59528), open)
<!-- /generated:patches -->

Authors, upstream state and the exact commits ported are in
[`recipe/patches/PROVENANCE.md`](recipe/patches/PROVENANCE.md). When an upstream PR merges, the next build drops
its patch and uses upstream's version.

## Memory on one Spark

The checkpoint is about 135 GB and the Spark has 121 GiB, shared by CPU and GPU. It fits because the PLE n-gram
table is read from the checkpoint file per step instead of being loaded. Details, the measured footprint and the
unified-memory notes are in [docs/memory-budget.md](docs/memory-budget.md).

## Reproduce the numbers

See [bench/README.md](bench/README.md): the third-party harness (`bench/run-third-party.sh`), the GSM8K subset
(`bench/quality/`), and the protocol (warm-up, runs, which statistic, prefix cache state).

## Known limits

- One host. No noise floor across hosts; numbers on your Spark will differ.
- Not tested here: a single request near the 262,144-token maximum (the longest prompt measured is about 131K),
  vision and video inputs, more than 6 concurrent sequences, thinking-on throughput.
- The MTP drafter only proposes token ids below 65,536, so non-English text drafts less well and runs slower.
- The KV pool (about 1.0M tokens) is aggregate capacity across requests, not one request's context.

## Troubleshooting

[docs/troubleshooting.md](docs/troubleshooting.md): slow loads, out-of-memory at boot, fluent but wrong answers
(the PLE scale trap), and how to report a reproduction ([issue template](.github/ISSUE_TEMPLATE/reproduction-report.md)).

**Asking for help.** Run one command and paste its output into your forum post or issue:

```bash
./recipe/diagnose.sh            # host, driver, Docker, memory, disk, checkpoint, preflight, launch command
# if the server fails to start, save its log and include it:
WARMUP=0 ./recipe/launch.sh 2>&1 | tee -i launch.log; ./recipe/diagnose.sh launch.log
./recipe/diagnose.sh --issue     # same report; then, only if you answer y, filed as a public GitHub issue
```

It is read-only and sends nothing unless you confirm `--issue` (which uses the `gh` CLI if you are signed in, or
prints a link to a new issue to paste the report into). It saves the report as `qfn-diagnose-<time>.txt`, already
wrapped in a code block, with your user name, home folder, host name, API keys and tokens replaced by placeholders.
Read it before you share it.

## How builds are updated

We rebuild every night on vLLM main with the same patch series (and drop a patch once vLLM contains it). A build
replaces the one in this repo only if, against the build it would replace and in the same session on our Spark, it
passes: the server boots with at least 90% of the KV pool; a 12-check endpoint suite; the quality checks above
(GSM8K at least 98/100, arithmetic 11/12, ten tasks 9/10, needle and canary pass); decode speed over 68 prompts at one
request at least 0.97x; aggregate throughput at 2 and 4 requests at least 0.95x per workload; and a healthcheck once
it serves. It must also beat the published harness figures on two nights in a row (the first build here,
2026-10-08, was published after one night, before that rule existed).

## Credits and licence

Apache-2.0 ([LICENSE](LICENSE), [NOTICE](NOTICE)). The patches modify vLLM (Apache-2.0); ports of open vLLM pull
requests credit their authors in [PROVENANCE.md](recipe/patches/PROVENANCE.md); patch 0002's reduced-vocabulary
drafting is ported from tonyd2wild's `mtp_draft_vocab.py` (see [NOTICE](NOTICE)). The benchmark harness is
tonyd2wild's ([repository](https://github.com/tonyd2wild/Qwen3.8-Flash-Next-NVFP4-DGX-Spark), Apache-2.0), fetched at a
pinned commit. The GSM8K subset is drawn from OpenAI's [grade-school-math](https://github.com/openai/grade-school-math)
(MIT). Model weights are not distributed here; they are under the licences on the
[model card](https://huggingface.co/nvidia/Qwen3.8-Flash-Next-NVFP4).
