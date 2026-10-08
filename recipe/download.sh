#!/usr/bin/env bash
# Download the checkpoint at the pinned revision into the Hugging Face cache and verify the small files' hashes.
# The weights are not redistributed here; their licence is on the model card. The hf CLI checks each weight file
# against the hub's own hashes as it downloads; model-files.sha256 pins the small config and tokenizer files.
set -euo pipefail
cd "$(dirname "$0")"; source ./pins.env
command -v hf > /dev/null || { echo "install the Hugging Face CLI: pip install -U huggingface_hub" >&2; exit 1; }
hf download "$MODEL_ID" --revision "$MODEL_REVISION"
snap="${HF_HOME:-$HOME/.cache/huggingface}/hub/models--${MODEL_ID//\//--}/snapshots/$MODEL_REVISION"
(cd "$snap" && sha256sum -c "$OLDPWD/model-files.sha256") && echo "verified: $snap"
