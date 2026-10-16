# Memory on one DGX Spark

Measured on build `2026-10-14-77154ca6` (see `results/`), on two boots of the same image.

| | |
|---|---|
| Checkpoint on disk | 123.6 GiB (vLLM's own count at load) |
| PLE n-gram embedding tables inside it | 51.2 GB, FP8 E4M3 with a per-table scale |
| Spark memory, CPU and GPU together | 121 GiB, one unified pool |
| Weights resident after load (vLLM's "Model loading took") | 73.51 GiB |
| KV cache after load, at `--gpu-memory-utilization 0.80` | 14.97-15.85 GiB = 981,604-1,039,008 tokens on two boots (fp8; aggregate across requests) |
| Container memory cap (`--memory`) | 112 GiB |

## Why it fits

The checkpoint is larger than the machine, and no offload flag helps: on GB10 "host" and "GPU" memory are the
same pool, so moving a tensor from GPU to CPU frees nothing. The recipe fits because the largest single piece,
the PLE n-gram tables, is never loaded. Patch `0001` (a port of open vLLM PR #58815) reads only the rows each step
needs, straight from the checkpoint's safetensors files, with 64 parallel `pread` workers. Those reads are served
from the page cache when they repeat, and the page cache is reclaimable memory, not committed memory.

Patch `0002` also casts the checkpoint's BF16 dense layers to FP8 at load, which lowers the bytes read per decode
step; it does not change what fits.

## The scale trap

The PLE tables are FP8 with a per-table `weight_scale`. A loader that reads the bytes without applying the scale
produces wrong embeddings, and the model still writes fluent text. Only scored checks catch it, which is why every
result in this repo carries a GSM8K score and `verify.sh` asks two questions with known answers.

## Practical notes

- Start from a quiet machine: about 100 GiB free (`free -g`). Other GPU work, a desktop session with large
  browser tabs, or another inference server will make the load fail or the KV pool smaller.
- Loading took about 5-6 minutes on our Spark, from the first log line to a server that answers: the weight load
  about 120 s ("Loading weights took 124.52 seconds"; "Model loading took 73.51 GiB memory and 153.07 seconds",
  drafter included), then the KV cache profile, CUDA graph capture and warm-up. Patch `0014` reads the routed experts
  in large parallel reads; with it off (`QWEN38_BATCHED_LOAD=0`) the weight load runs on one CPU core and takes about
  450-540 s. A larger disk read-ahead (8192 KB rather than the distro's 128 KB) shortened cold loads on earlier
  builds; it has not been re-measured with patch `0014`.
- NVIDIA's DGX Spark playbooks suggest flushing the page cache if you hit memory errors that should not happen:
  `sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'`. The first load after that is slower.
- `nvidia-smi --query-gpu=memory.*` reports N/A on GB10; use `free -g` and the vLLM log lines above.
- The KV pool is shared by all running requests. One request can use up to `--max-model-len` (262,144 tokens);
  we have measured prompts up to about 131K tokens.
