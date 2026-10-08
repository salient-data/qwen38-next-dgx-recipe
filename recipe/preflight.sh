#!/usr/bin/env bash
# Read-only checks before anything is downloaded or built. Changes nothing. Exit 1 if a hard requirement fails.
set -uo pipefail
cd "$(dirname "$0")"; source ./pins.env
ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  warn  %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; FAILED=1; }
FAILED=0
echo "preflight for $RECIPE_NAME ($RECIPE_BUILD)"
[[ "$(uname -m)" == aarch64 ]] && ok "aarch64" || bad "architecture $(uname -m): this recipe is for DGX Spark (aarch64)"
gpu="$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | head -1)"
[[ "$gpu" == "NVIDIA GB10,"* ]] && ok "GPU: $gpu" || bad "GPU: '${gpu:-none}' (needs NVIDIA GB10)"
drv="${gpu##*, }"; [[ "$drv" == "$TESTED_DRIVER" ]] && ok "driver $drv (tested)" || warn "driver ${drv:-?}; tested with $TESTED_DRIVER ($TESTED_DRIVER_FLAVOUR)"
grep -q "Open Kernel Module" /proc/driver/nvidia/version 2>/dev/null && ok "open kernel module driver" || warn "not the open kernel module driver (tested with it)"
docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q nvidia && ok "docker with the nvidia runtime" || bad "docker with the NVIDIA container runtime is required"
mem_gib=$(( $(awk '/MemAvailable/{print $2}' /proc/meminfo) / 1048576 ))
(( mem_gib >= 100 )) && ok "MemAvailable ${mem_gib} GiB" || warn "MemAvailable ${mem_gib} GiB: the server needs about 100 GiB; stop other GPU workloads first (see docs/memory-budget.md)"
disk_gib=$(( $(df --output=avail -B1G "${HF_HOME:-$HOME/.cache/huggingface}" 2>/dev/null | tail -1 || echo 0) ))
(( disk_gib >= 200 )) && ok "${disk_gib} GB free for the checkpoint and image" || warn "${disk_gib} GB free: the checkpoint is about 135 GB and the image about 25 GB"
( ! ss -ltn 2>/dev/null | grep -q ":${PORT:-8000} " ) && ok "port ${PORT:-8000} free" || warn "port ${PORT:-8000} is in use"
exit $FAILED
