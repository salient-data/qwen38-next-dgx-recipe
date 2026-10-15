# Patch provenance

All patches apply, in `series` order, with `patch --fuzz=0` to vLLM `77154ca6116ae34cbfe314beef1016bde9b63989`.

| Patch | Upstream | Author | State | Ported head | Local change |
|---|---|---|---|---|---|
| `0001-vllm58815-ple-host-file-gather.patch` | [vllm#58815](https://github.com/vllm-project/vllm/pull/58815) | @Trosfy | open | a7ebbe5f | adds the parallel preadv pool (VLLM_PLE_FILE_GATHER_WORKERS) |
| `0002-fp8-dense-and-draft-vocab.patch` | none | this repo and tonyd2wild | - | - | FP8-dense cast and indexer handling written for this recipe; the reduced-vocabulary drafting ports tonyd2wild's mtp_draft_vocab.py (Tony DeAngelo, Tech2Wild / 2Wild, Apache-2.0; https://github.com/tonyd2wild/Qwen3.8-Flash-Next-NVFP4-DGX-Spark @ 6ad1c8f), credited in the code as 'Kai / 2Wild' |
| `0003-vllm59973-nvfp4-draft-lm-head.patch` | [vllm#59973](https://github.com/vllm-project/vllm/pull/59973) | @stecasta | open | e037067e (PR now at 65148fb4) | adds the reduced-vocabulary draft-rows hook |
| `0004-vllm58681-restore-sm12x-alignment-behavior-for.patch` | [vllm#58681](https://github.com/vllm-project/vllm/pull/58681) | @dajiaohuang | open | 6da79884 (PR now at 828e936c) | cherry-picked unchanged |
| `0005-vllm58737-fuse-the-mamba-align-block-table.patch` | [vllm#58737](https://github.com/vllm-project/vllm/pull/58737) | @fululi12 | open | 88ee2624 (PR now at e4facc10) | cherry-picked unchanged (test files dropped) |
| `0006-vllm59260-warm-up-top-k-top-p-and-greedy.patch` | [vllm#59260](https://github.com/vllm-project/vllm/pull/59260) | @zixi-qi | merged | 5509dd5f (PR now at d817114f) | cherry-picked unchanged (test files dropped) |
| `0007-quiet-boot.patch` | none | this repo | - | - | written for this recipe |
| `0008-mtp-shard-filter.patch` | none | this repo | - | - | written for this recipe |
| `0009-vllm54912-widen-the-qsa-raw-key-ring.patch` | [vllm#54912](https://github.com/vllm-project/vllm/pull/54912) | @jschmied | open | 77b5ae7e | ported by hand onto this series (context only) |
| `0010-vllm60068-confidence-stop-for-autoregressive-drafting.patch` | [vllm#60068](https://github.com/vllm-project/vllm/pull/60068) | @stecasta | open | 029a811e (PR now at 8ae78cca) | applied from the PR head (tests dropped) |
| `0011-skinny-gemm-rows.patch` | none | this repo | - | - | written for this recipe |
| `0012-vllm58863-recoverssm-for-qwen-gdn-and.patch` | [vllm#58863](https://github.com/vllm-project/vllm/pull/58863) | @jschmied | open | 95ba23f5 (PR now at 7f7b3295) | ported by hand onto this series |
| `0013-vllm59740-context-aware-sparse-lm-head.patch` | [vllm#59740](https://github.com/vllm-project/vllm/pull/59740) | @stecasta | open | 3ed5c097 (PR now at 6160ed72) | ported by hand onto this series, plus a hook that hands the sparse draft head a BF16 copy of the block-FP8 shared head, which the PR's head refuses |
| `0014-moe-batched-load.patch` | none | this repo | - | - | written for this recipe |

When an upstream PR merges into vLLM main, the next build drops its patch and carries upstream's version.

Code check: the patches here differ from the bytes that were built only in comments (internal task references removed); applying both to `77154ca6116ae34cbfe314beef1016bde9b63989` gives identical Python ASTs for every touched file (56 files).
