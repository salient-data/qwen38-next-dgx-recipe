#!/usr/bin/env bash
# Checks before anything is downloaded, built or started. Exit 1 if a hard requirement fails.
#   ./preflight.sh            read-only: changes nothing, deletes nothing; prints the command that fixes each problem
#   ./preflight.sh --verify   also hash every checkpoint file against the hub (hf cache verify; reads all ~135 GB)
#   ./preflight.sh --fix      also re-run ./download.sh, which resumes partial downloads and recreates missing links
#                             (it only adds files; it never deletes anything from your cache)
set -uo pipefail
cd "$(dirname "$0")"; source ./pins.env
VERIFY=0; FIX=0
for a in "$@"; do
  case "$a" in
    --verify) VERIFY=1 ;; --fix) FIX=1 ;;
    -h|--help) sed -n '2,6p' "$(basename "$0")"; exit 0 ;;
    *) echo "unknown argument: $a (see ./preflight.sh --help)" >&2; exit 2 ;;
  esac
done
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
(( mem_gib >= ${MIN_FREE_GIB:-98} )) && ok "MemAvailable ${mem_gib} GiB" || warn "MemAvailable ${mem_gib} GiB: the server needs about 98 GiB (launch.sh refuses below MIN_FREE_GIB); stop other GPU workloads first (see docs/memory-budget.md)"
disk_gib=$(( $(df --output=avail -B1G "$(d="${HF_HUB_CACHE:-${HF_HOME:-$HOME/.cache/huggingface}/hub}"; while [[ ! -d "$d" ]]; do d="$(dirname "$d")"; done; echo "$d")" 2>/dev/null | tail -1 || echo 0) ))
(( disk_gib >= 200 )) && ok "${disk_gib} GB free for the checkpoint and image" || warn "${disk_gib} GB free: the checkpoint is about 135 GB and the image about 25 GB"
# Hugging Face CLI and cache. Nothing here deletes anything: each problem prints the command that fixes it.
HUB="${HF_HUB_CACHE:-${HF_HOME:-$HOME/.cache/huggingface}/hub}"
src="default"; [[ -n "${HF_HOME:-}" ]] && src="HF_HOME"; [[ -n "${HF_HUB_CACHE:-}" ]] && src="HF_HUB_CACHE"
MDIR="${MODEL_DIR:-$HUB/models--${MODEL_ID//\//--}}"
if command -v hf > /dev/null; then
  hv="$(hf version 2>/dev/null | sed -n 's/^ *version *[=:] *//p' | head -1)"   # 'version=X' or, in some environments, 'version: X'
  if hf cache verify --help > /dev/null 2>&1 && hf cache prune --help > /dev/null 2>&1; then ok "hf CLI ${hv:-?}"
  else warn "hf CLI ${hv:-?} has no 'hf cache verify' or 'hf cache prune'; upgrade: pip install -U huggingface_hub"; fi
else warn "hf CLI not found (download.sh needs it): pip install -U huggingface_hub"; fi
snap="$MDIR/snapshots/$MODEL_REVISION"
ok "Hugging Face cache: $HUB (from $src); model folder: $MDIR"
if (( FIX )); then echo "  ...   --fix: running ./download.sh"; ./download.sh || bad "./download.sh failed"; fi
if [[ ! -d "$snap" ]]; then
  warn "checkpoint not downloaded at the pinned revision: run ./download.sh"
else
  real="$(readlink -f "$MDIR")"; broken=0; outside=0
  for f in "$snap"/*; do
    t="$(readlink -f "$f" || true)"
    if [[ -z "$t" || ! -e "$t" ]]; then broken=$((broken+1)); elif [[ "$t" != "$real"/* ]]; then outside=$((outside+1)); fi
  done
  missing=0; idx_ok=1
  if ! command -v python3 > /dev/null; then idx_ok=0
  elif [[ -f "$snap/model.safetensors.index.json" ]]; then
    for w in $(python3 -c 'import json,sys; print("\n".join(sorted(set(json.load(open(sys.argv[1]))["weight_map"].values()))))' "$snap/model.safetensors.index.json" 2>/dev/null); do
      [[ -e "$snap/$w" ]] || missing=$((missing+1))
    done
  else missing=1; fi
  (( idx_ok )) || warn "python3 not found: could not check the weight files named by the index"
  if (( broken + missing > 0 )); then bad "checkpoint incomplete: $missing weight files missing, $broken broken links; run ./download.sh (or ./preflight.sh --fix): hf download resumes and repairs links"
  elif (( idx_ok )); then ok "checkpoint files all present at $MODEL_REVISION"; fi
  (( outside == 0 )) && ok "every checkpoint file resolves inside the model folder (the container mounts only that folder)" \
    || bad "$outside checkpoint files resolve outside $real, so the container cannot read them: keep snapshots/ and blobs/ under one folder and set MODEL_DIR (docs/troubleshooting.md)"
  inc=$(find "$MDIR/blobs" -maxdepth 1 -name '*.incomplete' 2>/dev/null | wc -l)
  (( inc == 0 )) || warn "$inc partial downloads in $MDIR/blobs: ./download.sh resumes them; 'hf cache prune' discards them"
  revs=$(find "$MDIR/snapshots" -mindepth 1 -maxdepth 1 -type d ! -name "$MODEL_REVISION" 2>/dev/null | wc -l)
  (( revs == 0 )) || warn "$revs other revisions of this model in the cache; 'hf cache ls --revisions' shows their size, 'hf cache prune' removes detached ones"
  if (( VERIFY )); then
    echo "  ...   --verify: hashing every file against the hub (reads all ~135 GB)"
    hf cache verify "$MODEL_ID" --revision "$MODEL_REVISION" --fail-on-missing-files ${HF_HUB_CACHE:+--cache-dir "$HF_HUB_CACHE"} \
      && ok "hf cache verify: every file matches the hub" || bad "hf cache verify failed: run ./download.sh, then verify again"
  fi
fi
( ! ss -ltn 2>/dev/null | grep -q ":${PORT:-8000} " ) && ok "port ${PORT:-8000} free" || warn "port ${PORT:-8000} is in use"
# Anything already holding GPU (that is, unified) memory shrinks the KV pool the server can size at boot.
apps="$(nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null | sed '/^$/d')"
[[ -z "$apps" ]] && ok "no other GPU processes" || warn "GPU processes already running (each one takes memory from the KV pool): $(echo "$apps" | tr '\n' ';')"
others="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -vx "${NAME:-qwen38-flash-next}" | tr '\n' ' ')"
[[ -z "$others" ]] && ok "no other containers running" || warn "other containers running: ${others}(stop the memory-heavy ones for the full KV pool)"
# Read-ahead on the checkpoint's disk: the distro default is 128 KB; 8192 loads the weights about 100 s faster.
MODEL_DIR="${MODEL_DIR:-${HF_HUB_CACHE:-${HF_HOME:-$HOME/.cache/huggingface}/hub}}"
dev="$(lsblk -no pkname "$(df --output=source "$MODEL_DIR" 2>/dev/null | tail -1)" 2>/dev/null | head -1)"
ra="$(cat "/sys/block/$dev/queue/read_ahead_kb" 2>/dev/null || true)"
if [[ "$ra" =~ ^[0-9]+$ ]]; then
  (( ra >= 8192 )) && ok "read-ahead ${ra} KB on $dev" || warn "read-ahead ${ra} KB on $dev; for a faster load: sudo sh -c 'echo 8192 > /sys/block/$dev/queue/read_ahead_kb' (resets at reboot; docs/troubleshooting.md)"
fi
# A sparse draft head's token map (named in serve.args) must ship in draft-token-maps/ and hash to its name.
tm="$(grep -o '"draft_token_map": *"[^"]*"' serve.args 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
if [[ -n "$tm" ]]; then
  h="$(basename "$tm" .json)"
  if [[ "$tm" != /root/.cache/draft-token-maps/*.json || ! "$h" =~ ^[0-9a-f]{64}$ ]]; then bad "serve.args names a draft token map launch.sh cannot install: $tm"
  elif [[ "$(sha256sum "draft-token-maps/$h.json" 2>/dev/null | cut -d' ' -f1)" == "$h" ]]; then ok "draft token map recipe/draft-token-maps/$h.json present and intact"
  else bad "draft token map recipe/draft-token-maps/$h.json missing or not hashing to its name: git checkout recipe/draft-token-maps"; fi
fi
exit $FAILED
