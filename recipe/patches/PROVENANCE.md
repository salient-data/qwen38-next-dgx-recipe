# Patch provenance

All patches apply, in `series` order, with `patch --fuzz=0` to vLLM `8e2beaa3bff595577a069d49d96bde9074294ec2`.

| Patch | Upstream | Author | State | Ported head | Local change |
|---|---|---|---|---|---|
| `0001-vllm58815-ple-host-file-gather.patch` | [vllm#58815](https://github.com/vllm-project/vllm/pull/58815) | @Trosfy | open | a7ebbe5f | adds the parallel preadv pool (VLLM_PLE_FILE_GATHER_WORKERS) |
| `0002-fp8-dense-and-draft-vocab.patch` | none | this repo and tonyd2wild | - | - | FP8-dense cast and indexer handling written for this recipe; the reduced-vocabulary drafting ports tonyd2wild's mtp_draft_vocab.py (Tony DeAngelo, Tech2Wild / 2Wild, Apache-2.0; https://github.com/tonyd2wild/Qwen3.8-Flash-Next-NVFP4-DGX-Spark @ 6ad1c8f), credited in the code as 'Kai / 2Wild' |
| `0003-vllm59973-nvfp4-draft-lm-head.patch` | [vllm#59973](https://github.com/vllm-project/vllm/pull/59973) | @stecasta | merged | e037067e (PR now at 65148fb4) | adds the reduced-vocabulary draft-rows hook |
| `0004-vllm58681-restore-sm12x-alignment-behavior-for.patch` | [vllm#58681](https://github.com/vllm-project/vllm/pull/58681) | @dajiaohuang | open | 6da79884 (PR now at 828e936c) | cherry-picked unchanged |
| `0005-quiet-boot.patch` | none | this repo | - | - | written for this recipe |
| `0006-mtp-shard-filter.patch` | none | this repo | - | - | written for this recipe |
| `0007-vllm54912-widen-the-qsa-raw-key-ring.patch` | [vllm#54912](https://github.com/vllm-project/vllm/pull/54912) | @jschmied | open | 77b5ae7e | ported by hand onto this series (context only) |
| `0008-vllm60068-confidence-stop-for-autoregressive-drafting.patch` | [vllm#60068](https://github.com/vllm-project/vllm/pull/60068) | @stecasta | open | 029a811e (PR now at 8ae78cca) | applied from the PR head (tests dropped) |
| `0009-skinny-gemm-rows.patch` | none | this repo | - | - | written for this recipe |
| `0010-vllm58863-recoverssm-for-qwen-gdn-and.patch` | [vllm#58863](https://github.com/vllm-project/vllm/pull/58863) | @jschmied | open | 95ba23f5 (PR now at 3694757f) | ported by hand onto this series |
| `0011-vllm59740-context-aware-sparse-lm-head.patch` | [vllm#59740](https://github.com/vllm-project/vllm/pull/59740) | @stecasta | open | 3ed5c097 (PR now at 6160ed72) | ported by hand onto this series, plus a hook that hands the sparse draft head a BF16 copy of the block-FP8 shared head, which the PR's head refuses |
| `0012-moe-batched-load.patch` | none | this repo | - | - | written for this recipe |
| `0013-vllm62841-avoid-re-marking-committed-prompt-tail-boundaries.patch` | [vllm#62841](https://github.com/vllm-project/vllm/pull/62841) | @khyun1109 | merged after this build's base | eca59b6b (PR now at e1e0221d) | cherry-picked unchanged (test files dropped) |
| `0014-draft-head-per-batch.patch` | none | this repo | - | - | written for this recipe |

When an upstream PR merges into vLLM main, the next build drops its patch and carries upstream's version.

Code check: the patches here differ from the bytes that were built only in comments and docstrings (internal task references removed); applying both to `8e2beaa3bff595577a069d49d96bde9074294ec2` gives identical Python ASTs, docstring text aside, for every touched file (53 files).
