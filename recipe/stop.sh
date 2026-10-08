#!/usr/bin/env bash
# Stop and remove the recipe's container (the checkpoint and the image stay).
set -uo pipefail
docker rm -f "${NAME:-qwen38-flash-next}" > /dev/null && echo "stopped ${NAME:-qwen38-flash-next}"
