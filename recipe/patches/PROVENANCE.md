# Patch provenance

All patches apply, in `series` order, with `patch --fuzz=0` to vLLM `81198e97ba7eee2a22540caaa756b7fdddcb4d93`.

| Patch | Upstream | Author | State | Ported head | Local change |
|---|---|---|---|---|---|
| `0001-vllm58815-ple-host-file-gather.patch` | [vllm#58815](https://github.com/vllm-project/vllm/pull/58815) | @Trosfy | open | a7ebbe5f | adds the parallel preadv pool (VLLM_PLE_FILE_GATHER_WORKERS) |
| `0002-fp8-dense-and-draft-vocab.patch` | none | this repo and tonyd2wild | - | - | FP8-dense cast and indexer handling written for this recipe; the reduced-vocabulary drafting ports tonyd2wild's mtp_draft_vocab.py (Tony DeAngelo, Tech2Wild / 2Wild, Apache-2.0; https://github.com/tonyd2wild/Qwen3.8-Flash-Next-NVFP4-DGX-Spark @ 6ad1c8f), credited in the code as 'Kai / 2Wild' |
| `0003-vllm59973-nvfp4-draft-lm-head.patch` | [vllm#59973](https://github.com/vllm-project/vllm/pull/59973) | @stecasta | open | e037067e (PR now at 0c2ed06a) | adds the reduced-vocabulary draft-rows hook |
| `0004-vllm58681-restore-sm12x-alignment-behavior-for.patch` | [vllm#58681](https://github.com/vllm-project/vllm/pull/58681) | @dajiaohuang | open | 6da79884 (PR now at 828e936c) | cherry-picked unchanged |
| `0005-vllm58737-fuse-the-mamba-align-block-table.patch` | [vllm#58737](https://github.com/vllm-project/vllm/pull/58737) | @fululi12 | open | 88ee2624 | cherry-picked unchanged (test files dropped) |
| `0006-vllm59528-keep-the-glm-5-3-kpool-tail.patch` | [vllm#59528](https://github.com/vllm-project/vllm/pull/59528) | @ivanium | open | b96ce880 | cherry-picked unchanged (test files dropped) |

When an upstream PR merges into vLLM main, the next build drops its patch and carries upstream's version.

Code check: the patches here differ from the bytes that were built only in comments (internal task references removed); applying both to `81198e97ba7eee2a22540caaa756b7fdddcb4d93` gives identical Python ASTs for every touched file (18 files).
