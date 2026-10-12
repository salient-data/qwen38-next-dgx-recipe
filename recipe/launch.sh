#!/usr/bin/env bash
# Start the server with the exact arguments this recipe was measured with.
#   ./launch.sh               run it in this terminal: you watch it load (10-12 minutes), Ctrl-C stops and removes it
#   ./launch.sh --detach, -d  run it in the background (production); follow with docker logs -f, stop with ./stop.sh
#   ./launch.sh --print       print the docker command, run nothing (combine with --detach to see that form)
# Before starting it checks that every checkpoint file resolves inside the folder the container mounts, that about
# 98 GiB of memory is free (MIN_FREE_GIB) and that no container of the same name exists, and lists other GPU
# containers and processes; FORCE=1 skips the memory check and the list.
# Binds 127.0.0.1 by default. BIND=0.0.0.0 exposes it on every interface WITHOUT authentication unless you
# also set VLLM_API_KEY (passed to the container as an environment variable, which vLLM reads).
set -euo pipefail
cd "$(dirname "$0")"; source ./pins.env
DETACH=0; PRINT=0
for a in "$@"; do
  case "$a" in
    --detach|-d) DETACH=1 ;;
    --print) PRINT=1 ;;
    -h|--help) sed -n '2,10p' "$(basename "$0")"; exit 0 ;;
    *) echo "unknown argument: $a (see ./launch.sh --help)" >&2; exit 2 ;;
  esac
done
# The Hugging Face cache: HF_HUB_CACHE if set (hf download writes there), else $HF_HOME/hub, else ~/.cache/huggingface/hub.
HUB="${HF_HUB_CACHE:-${HF_HOME:-$HOME/.cache/huggingface}/hub}"
MODEL_DIR="${MODEL_DIR:-$HUB/models--${MODEL_ID//\//--}}"
CACHE_DIR="${CACHE_DIR:-$HOME/.cache/qwen38-next-dgx-recipe}"
BIND="${BIND:-127.0.0.1}"; PORT="${PORT:-8000}"; NAME="${NAME:-qwen38-flash-next}"
mapfile -t ARGS < <(grep -v '^#' serve.args | sed '/^$/d')
mapfile -t ENVS < <(grep -v '^#' serve.env | sed '/^$/d')
if (( DETACH )); then mode=(-d --restart no)
else mode=(--rm -i); [[ -t 0 && -t 1 ]] && mode+=(-t); fi
cmd=(docker run "${mode[@]}" --name "$NAME" --gpus all --network host --ipc host --shm-size 32g --ulimit memlock=-1:-1
     --memory "$MEMORY_CAP" --memory-swap "$MEMORY_CAP"
     -v "$MODEL_DIR:/hfrepo:ro" -v "$CACHE_DIR:/root/.cache")
for e in "${ENVS[@]}"; do cmd+=(-e "$e"); done
[[ -n "${VLLM_API_KEY:-}" ]] && cmd+=(-e VLLM_API_KEY)   # the value stays in this shell's environment, not on the command line
cmd+=(--entrypoint vllm "$IMAGE" serve "/hfrepo/snapshots/$MODEL_REVISION" --host "$BIND" --port "$PORT" "${ARGS[@]}")
if (( PRINT )); then printf '%q ' "${cmd[@]}"; echo; exit 0; fi
[[ -d "$MODEL_DIR/snapshots/$MODEL_REVISION" ]] || { echo "checkpoint not found in $MODEL_DIR; run ./download.sh, or set MODEL_DIR to the folder holding snapshots/ and blobs/" >&2; exit 1; }
# The container sees only MODEL_DIR, so every file of the snapshot must resolve inside it. A link that leaves it (for
# example blobs/ moved to another disk behind a symlink) works on the host but not in the container.
real="$(readlink -f "$MODEL_DIR")"; bad=0
for f in "$MODEL_DIR/snapshots/$MODEL_REVISION"/*; do
  t="$(readlink -f "$f" || true)"
  if [[ -z "$t" || ! -e "$t" ]]; then echo "missing or broken link: $f" >&2; bad=1
  elif [[ "$t" != "$real"/* ]]; then echo "outside $real, so the container cannot read it: $f -> $t" >&2; bad=1; fi
done
if command -v python3 > /dev/null && [[ -f "$MODEL_DIR/snapshots/$MODEL_REVISION/model.safetensors.index.json" ]]; then
  while read -r w; do
    [[ -z "$w" || -e "$MODEL_DIR/snapshots/$MODEL_REVISION/$w" ]] || { echo "missing weight file: $w" >&2; bad=1; }
  done < <(python3 -c 'import json,sys; print("\n".join(sorted(set(json.load(open(sys.argv[1]))["weight_map"].values()))))' "$MODEL_DIR/snapshots/$MODEL_REVISION/model.safetensors.index.json")
fi
(( bad == 0 )) || { echo "re-run ./download.sh for missing files; keep snapshots/ and blobs/ under one folder and set MODEL_DIR to it (docs/troubleshooting.md)" >&2; exit 1; }
docker image inspect "$IMAGE" > /dev/null 2>&1 || { echo "image $IMAGE not built; run ./build.sh" >&2; exit 1; }
if docker container inspect "$NAME" > /dev/null 2>&1; then
  echo "a container named $NAME already exists ($(docker inspect -f '{{.State.Status}}' "$NAME")); ./stop.sh removes it" >&2; exit 1
fi
# One Spark holds one server: vLLM asks for 0.80 of the 121.7 GiB that CPU and GPU share (97.4 GiB) at start. List
# other GPU containers and processes, and refuse with less than MIN_FREE_GIB (98) available. FORCE=1 skips both.
if [[ "${FORCE:-0}" != 1 ]]; then
  others="$(docker ps -q | xargs -r docker inspect --format '{{.Name}} {{.HostConfig.DeviceRequests}}' 2>/dev/null | awk '/gpu/ {sub("^/", "", $1); print $1}' | tr '\n' ' ')"
  [[ -z "$others" ]] || echo "warning: GPU containers already running: $others(they share the same memory)" >&2
  if command -v nvidia-smi > /dev/null; then
    procs="$(nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader 2>/dev/null | sed '/^$/d' | tr '\n' ';')"
    [[ -z "$procs" ]] || echo "warning: GPU processes already running: $procs (they share the same memory)" >&2
  fi
  avail=$(awk '/^MemAvailable:/ {printf "%d", $2/1048576}' /proc/meminfo); need="${MIN_FREE_GIB:-98}"
  if (( avail < need )); then
    echo "only $avail GiB of memory available; the server needs about $need GiB (MIN_FREE_GIB). Largest processes:" >&2
    ps -eo rss=,comm= --sort=-rss | head -5 | awk '{printf "  %6.1f GiB  %s\n", $1/1048576, $2}' >&2
    echo "stop them, or run sync; echo 3 | sudo tee /proc/sys/vm/drop_caches if page cache is the cause (or FORCE=1)" >&2; exit 1
  fi
fi
ra="$(cat /sys/block/"$(lsblk -no pkname "$(df --output=source "$MODEL_DIR" | tail -1)" 2>/dev/null | head -1)"/queue/read_ahead_kb 2>/dev/null || true)"
if [[ "$ra" =~ ^[0-9]+$ && "$ra" -lt 8192 ]]; then
  echo "note: read-ahead on the checkpoint's disk is ${ra} KB; 8192 takes a cold load from about 12 to about 10 minutes (see docs/troubleshooting.md)." >&2
fi
mkdir -p "$CACHE_DIR"
if (( DETACH )); then
  "${cmd[@]}"
  echo "started $NAME in the background; follow: docker logs -f $NAME ; ready when ./verify.sh passes; stop: ./stop.sh"
else
  echo "starting $NAME in this terminal; it answers when the log says 'Application startup complete'."
  echo "from another terminal: ./verify.sh checks it, ./stop.sh (or Ctrl-C here) stops it."
  exec "${cmd[@]}"
fi
