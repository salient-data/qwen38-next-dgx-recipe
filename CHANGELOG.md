# Changelog

Newest first. Each entry is one build that passed our gates on our Spark: the vLLM nightly it is built on, the
patches it carries, its headline numbers and its results directory (never overwritten). Treat them as one host's
numbers, not promises.

## Recipe tooling (between builds)

- 2026-10-11: `launch.sh` finds the checkpoint the way `hf download` does (`HF_HUB_CACHE`, then `HF_HOME/hub`, then
  `~/.cache/huggingface/hub`) and, before starting, checks that every model file resolves inside the folder the
  container mounts, naming any that does not (a cache moved to another disk behind a symlink loaded on the host but
  failed in the container with `FileNotFoundError`; reported by rtamax on the NVIDIA forum). It also refuses to start
  with less than 98 GiB of memory available (`MIN_FREE_GIB`) or when a container of the same name exists, and lists
  other GPU containers and processes; `FORCE=1` skips those. `download.sh` verifies in the same cache.

<!-- generated:entries -->
## 2026-10-08-81198e97

- Base: vLLM `81198e97ba7eee2a22540caaa756b7fdddcb4d93` (`vllm/vllm-openai@sha256:a83c7f976879e0c6101f734fd5b84a098d12d6d8d12baa41e31eb323b84b0802`).
- Patches: 0001-vllm58815-ple-host-file-gather, 0002-fp8-dense-and-draft-vocab, 0003-vllm59973-nvfp4-draft-lm-head, 0004-vllm58681-restore-sm12x-alignment-behavior-for, 0005-vllm58737-fuse-the-mamba-align-block-table, 0006-vllm59528-keep-the-glm-5-3-kpool-tail.
- Harness: 67.5 tok/s median at 1 stream, 90.7 aggregate at 6; GSM8K subset 99/100.
- Results: `results/2026-10-08-81198e97/`.
<!-- /generated:entries -->
