#!/usr/bin/env bash
# Start the server with the exact arguments this recipe was measured with.
#   ./launch.sh --print       print the docker command, run nothing
#   ./launch.sh               start it (about 11 minutes until it answers)
# Binds 127.0.0.1 by default. BIND=0.0.0.0 exposes it on every interface WITHOUT authentication unless you
# also set VLLM_API_KEY (passed to the container as an environment variable, which vLLM reads).
set -euo pipefail
cd "$(dirname "$0")"; source ./pins.env
MODEL_DIR="${MODEL_DIR:-${HF_HOME:-$HOME/.cache/huggingface}/hub/models--${MODEL_ID//\//--}}"
CACHE_DIR="${CACHE_DIR:-$HOME/.cache/qwen38-next-dgx-recipe}"
BIND="${BIND:-127.0.0.1}"; PORT="${PORT:-8000}"; NAME="${NAME:-qwen38-flash-next}"
mapfile -t ARGS < <(grep -v '^#' serve.args | sed '/^$/d')
mapfile -t ENVS < <(grep -v '^#' serve.env | sed '/^$/d')
cmd=(docker run -d --name "$NAME" --gpus all --network host --ipc host --shm-size 32g --ulimit memlock=-1:-1
     --memory "$MEMORY_CAP" --memory-swap "$MEMORY_CAP"
     -v "$MODEL_DIR:/hfrepo:ro" -v "$CACHE_DIR:/root/.cache")
for e in "${ENVS[@]}"; do cmd+=(-e "$e"); done
[[ -n "${VLLM_API_KEY:-}" ]] && cmd+=(-e VLLM_API_KEY)   # the value stays in this shell's environment, not on the command line
cmd+=(--entrypoint vllm "$IMAGE" serve "/hfrepo/snapshots/$MODEL_REVISION" --host "$BIND" --port "$PORT" "${ARGS[@]}")
if [[ "${1:-}" == "--print" ]]; then printf '%q ' "${cmd[@]}"; echo; exit 0; fi
[[ -d "$MODEL_DIR/snapshots/$MODEL_REVISION" ]] || { echo "checkpoint not found; run ./download.sh" >&2; exit 1; }
docker image inspect "$IMAGE" > /dev/null 2>&1 || { echo "image $IMAGE not built; run ./build.sh" >&2; exit 1; }
mkdir -p "$CACHE_DIR"; "${cmd[@]}"
echo "started $NAME; follow: docker logs -f $NAME ; ready when ./verify.sh passes"
