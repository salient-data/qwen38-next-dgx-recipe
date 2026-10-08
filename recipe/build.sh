#!/usr/bin/env bash
# Build the serving image: the pinned vLLM nightly plus recipe/patches (applied in order with --fuzz=0).
#   ./build.sh            build $IMAGE from the pinned base digest
#   ./build.sh --print    show the commands only
# The pinned nightly tag is pruned by Docker Hub after about two weeks; if the digest no longer resolves, see
# "If the base image is gone" in the README (build the base from source at VLLM_COMMIT).
set -euo pipefail
cd "$(dirname "$0")"; source ./pins.env
pull=(docker pull "vllm/vllm-openai@$BASE_DIGEST")
build=(docker build -f Dockerfile --build-arg "BASE=vllm/vllm-openai@$BASE_DIGEST" -t "$IMAGE" .)
if [[ "${1:-}" == "--print" ]]; then echo "${pull[*]}"; echo "${build[*]}"; exit 0; fi
(cd patches && sha256sum -c ../patches.sha256)
"${pull[@]}"; "${build[@]}"
echo "built $IMAGE: $(docker image inspect "$IMAGE" --format '{{.Id}}')"
