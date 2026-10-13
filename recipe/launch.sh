#!/usr/bin/env bash
# Start the server with the exact arguments this recipe was measured with.
#   ./launch.sh               run it in this terminal: you watch it load (10-12 minutes), Ctrl-C stops and removes it
#                             (during the weight load vLLM acts on Ctrl-C only once the load ends; ./stop.sh is at once)
#   ./launch.sh --detach, -d  run it in the background (production); follow with docker logs -f, stop with ./stop.sh
#   ./launch.sh --print       print the docker command, run nothing (combine with --detach to see that form)
#   ./launch.sh [-d] -- ARGS  change or add vLLM arguments for this run, e.g. -- --max-model-len 131072: a flag already
#                             in serve.args gets the new value, any other is added; the run is then not the measured setup
# Before starting it checks that every checkpoint file resolves inside the folder the container mounts, that about
# 98 GiB of memory is free (MIN_FREE_GIB) and that no container of the same name exists, and lists other GPU
# containers and processes; FORCE=1 skips the memory check and the list.
# Once the server answers, a helper sends two short requests so first-request kernels compile now (WARMUP=0 skips).
# Binds 127.0.0.1 by default. BIND=0.0.0.0 exposes it on every interface WITHOUT authentication unless you
# also set VLLM_API_KEY (passed to the container as an environment variable, which vLLM reads).
set -euo pipefail
cd "$(dirname "$0")"; source ./pins.env
DETACH=0; PRINT=0
EXTRA=()
while (( $# )); do
  case "$1" in
    --detach|-d) DETACH=1 ;;
    --print) PRINT=1 ;;
    -h|--help) awk 'NR > 1 && !/^#/ {exit} NR > 1' "$(basename "$0")"; exit 0 ;;
    --) shift; EXTRA=("$@"); break ;;
    *) echo "unknown argument: $1 (see ./launch.sh --help; vLLM arguments go after --)" >&2; exit 2 ;;
  esac
  shift
done
# The Hugging Face cache: HF_HUB_CACHE if set (hf download writes there), else $HF_HOME/hub, else ~/.cache/huggingface/hub.
HUB="${HF_HUB_CACHE:-${HF_HOME:-$HOME/.cache/huggingface}/hub}"
MODEL_DIR="${MODEL_DIR:-$HUB/models--${MODEL_ID//\//--}}"
CACHE_DIR="${CACHE_DIR:-$HOME/.cache/qwen38-next-dgx-recipe}"
BIND="${BIND:-127.0.0.1}"; PORT="${PORT:-8000}"; NAME="${NAME:-qwen38-flash-next}"
mapfile -t ARGS < <(grep -v '^#' serve.args | sed '/^$/d')
mapfile -t ENVS < <(grep -v '^#' serve.env | sed '/^$/d')
# Arguments after --: a flag serve.args already has gets the new value in place (vLLM warns about repeated flags),
# any other flag is added. --flag value, --flag=value and bare flags (--enforce-eager) are accepted.
i=0
while (( i < ${#EXTRA[@]} )); do
  t="${EXTRA[i]}"; val=""; hasval=0
  [[ "$t" == --?* ]] || { echo "after --, expected a vLLM flag starting with --, got: $t" >&2; exit 2; }
  if [[ "$t" == *=* ]]; then flag="${t%%=*}"; val="${t#*=}"; hasval=1; i=$((i + 1))
  elif (( i + 1 < ${#EXTRA[@]} )) && [[ "${EXTRA[i+1]}" != --* ]]; then flag="$t"; val="${EXTRA[i+1]}"; hasval=1; i=$((i + 2))
  else flag="$t"; i=$((i + 1)); fi
  j=-1; for k in "${!ARGS[@]}"; do [[ "${ARGS[k]}" == "$flag" ]] && { j=$k; break; }; done
  if (( j >= 0 && hasval )) && (( j + 1 < ${#ARGS[@]} )) && [[ "${ARGS[j+1]}" != --* ]]; then
    echo "override: $flag ${val} (serve.args: ${ARGS[j+1]})" >&2; ARGS[j+1]="$val"
  elif (( j >= 0 && ! hasval )); then echo "override: $flag (already in serve.args)" >&2
  else
    if (( hasval )); then echo "override: adding $flag $val" >&2; else echo "override: adding $flag" >&2; fi; ARGS+=("$flag"); (( hasval )) && ARGS+=("$val")
  fi
done
(( ${#EXTRA[@]} == 0 )) || echo "note: these overrides change the measured configuration; say so when you report numbers" >&2
# A sparse draft head (vllm#59740) reads a token map at /root/.cache/draft-token-maps/<sha256>.json. The map ships in
# draft-token-maps/ under its own sha256; it is checked here (also for --print) and copied into CACHE_DIR, which the
# container mounts at /root/.cache, just before the container starts. A build whose serve.args names no map skips this.
TOKEN_MAP=""; tm_src=""
for a in "${ARGS[@]}"; do
  [[ "$a" == *'"draft_token_map"'* ]] || continue
  [[ "$a" =~ \"draft_token_map\":\ *\"/root/\.cache/draft-token-maps/([0-9a-f]{64})\.json\" ]] \
    || { echo "serve.args names a draft_token_map that is not /root/.cache/draft-token-maps/<sha256>.json; this launcher cannot install it" >&2; exit 1; }
  TOKEN_MAP="${BASH_REMATCH[1]}"; tm_src="draft-token-maps/$TOKEN_MAP.json"
  [[ -f "$tm_src" ]] || { echo "serve.args names the draft token map $TOKEN_MAP.json, but recipe/$tm_src is missing; git checkout recipe/draft-token-maps (or re-clone) restores it" >&2; exit 1; }
  [[ "$(sha256sum "$tm_src" | cut -d' ' -f1)" == "$TOKEN_MAP" ]] \
    || { echo "recipe/$tm_src does not hash to its name (edited or corrupted); git checkout recipe/draft-token-maps restores it" >&2; exit 1; }
done
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
if [[ -n "$TOKEN_MAP" ]]; then
  tm_dst="$CACHE_DIR/draft-token-maps/$TOKEN_MAP.json"
  if [[ "$(sha256sum "$tm_dst" 2>/dev/null | cut -d' ' -f1)" != "$TOKEN_MAP" ]]; then
    # Earlier containers run as root and may have left root-owned folders in CACHE_DIR, which this user cannot write.
    if ! { mkdir -p "${tm_dst%/*}" && cp "$tm_src" "$tm_dst.tmp.$$" && mv -f "$tm_dst.tmp.$$" "$tm_dst"; } 2> /dev/null; then
      rm -f "$tm_dst.tmp.$$" 2> /dev/null || true
      d="${tm_dst%/*}"; [[ -d "$d" ]] || d="$CACHE_DIR"
      echo "could not copy recipe/$tm_src into $d (owned by $(stat -c %U "$d" 2>/dev/null || echo '?'); you are $(id -un))." >&2
      echo "install it as root once: sudo install -D -m 0644 $PWD/$tm_src $tm_dst" >&2
      echo "or take the folder back: sudo chown -R $(id -un) $d" >&2; exit 1
    fi
  fi
  echo "draft token map $TOKEN_MAP.json installed in $CACHE_DIR/draft-token-maps/"
fi
# Warm-up: the first requests compile a few Triton kernels (the speculative-decoding rejection sampler, logits
# statistics), which the first user would see as a slow answer. A helper waits for the server, sends one greedy and
# one sampled request, and exits; it also exits if the container stops (Ctrl-C stops it with the server).
# WARMUP=0 skips it.
warmup() {
  local host="$BIND" auth=() i temp
  [[ "$host" == 0.0.0.0 ]] && host=127.0.0.1
  [[ -n "${VLLM_API_KEY:-}" ]] && auth=(-H "Authorization: Bearer $VLLM_API_KEY")
  running() { [[ "$(docker container inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" == true ]]; }
  for i in $(seq 1 60); do running && break; sleep 1; done
  until curl -fsS --max-time 3 "${auth[@]}" "http://$host:$PORT/v1/models" > /dev/null 2>&1; do
    running || return 0; sleep 5   # stopped, removed or crashed during load: nothing to warm
  done
  for temp in 0 1.0; do
    curl -fsS --max-time 300 "${auth[@]}" "http://$host:$PORT/v1/chat/completions" -H 'content-type: application/json' \
      -d "{\"model\":\"$SERVED_NAME\",\"messages\":[{\"role\":\"user\",\"content\":\"Count from 1 to 20.\"}],\"max_tokens\":64,\"temperature\":$temp}" \
      > /dev/null 2>&1 || { running && echo "warm-up: a request failed; ./verify.sh checks the server" >&2; return 0; }
  done
  echo "warm-up done: the server is ready and its first-request kernels are compiled" >&2
}
if (( DETACH )); then
  "${cmd[@]}"
  [[ "${WARMUP:-1}" == 0 ]] || { ( trap '' HUP; warmup ) > /dev/null 2>&1 & disown; }
  echo "started $NAME in the background; follow: docker logs -f $NAME ; ready when ./verify.sh passes; stop: ./stop.sh"
  [[ "${WARMUP:-1}" == 0 ]] || echo "a warm-up helper sends two requests once it answers (WARMUP=0 skips it)"
else
  [[ "${WARMUP:-1}" == 0 ]] || { warmup & }
  echo "starting $NAME in this terminal; it answers when the log says 'Application startup complete'."
  echo "from another terminal: ./verify.sh checks it, ./stop.sh (or Ctrl-C here) stops it."
  echo "while the weights load (about 10 minutes), vLLM acts on Ctrl-C only when the load ends; ./stop.sh stops it at once."
  exec "${cmd[@]}"
fi
