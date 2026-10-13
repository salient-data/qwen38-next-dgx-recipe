#!/usr/bin/env bash
# Pull the published image of this build (the prod path) and check it is the build this recipe measured.
#   ./pull.sh           check the signature (if cosign is installed), then docker pull PROD_IMAGE, pinned by digest
#   ./pull.sh --print   show the commands only
# PROD_IMAGE (pins.env) pins the registry digest of the exact image our nightly gates measured; PROD_IMAGE_ID is that
# image's ID, checked after the pull. The image is signed with the key in cosign.pub. Without cosign this warns and
# pulls; a signature that does not verify refuses. The dev path builds the same image yourself: ./build.sh.
set -euo pipefail
cd "$(dirname "$0")"; source ./pins.env
case "${1:-}" in -h|--help) awk 'NR > 1 && !/^#/ {exit} NR > 1' "$(basename "$0")"; exit 0 ;; esac
[[ -n "${PROD_IMAGE:-}" ]] || { echo "this build has no published image (no PROD_IMAGE in pins.env); use the dev path: ./build.sh" >&2; exit 1; }
[[ "$PROD_IMAGE" =~ ^[a-z0-9][a-z0-9./_-]*@sha256:[0-9a-f]{64}$ ]] || { echo "PROD_IMAGE is not pinned by digest: $PROD_IMAGE" >&2; exit 1; }
pull=(docker pull "$PROD_IMAGE")
verify=(cosign verify --key cosign.pub "$PROD_IMAGE")
if [[ "${1:-}" == "--print" ]]; then echo "${verify[*]}"; echo "${pull[*]}"; exit 0; fi
[[ -z "${1:-}" ]] || { echo "unknown argument: $1 (see ./pull.sh --help)" >&2; exit 2; }
if command -v cosign > /dev/null; then
  [[ -f cosign.pub ]] || { echo "recipe/cosign.pub is missing; git checkout recipe/cosign.pub restores it" >&2; exit 1; }
  "${verify[@]}" > /dev/null || { echo "signature check FAILED for $PROD_IMAGE: do not run it, and please report it on the recipe's forum thread" >&2; exit 1; }
  echo "signature ok (recipe/cosign.pub)"
else
  echo "warning: cosign is not installed, so the image's signature is not checked (install: https://docs.sigstore.dev/cosign/system_config/installation/)" >&2
fi
"${pull[@]}"
id="$(docker image inspect -f '{{.Id}}' "$PROD_IMAGE")"
[[ -z "${PROD_IMAGE_ID:-}" || "$id" == "$PROD_IMAGE_ID" ]] \
  || { echo "the pulled image's ID $id is not $PROD_IMAGE_ID, the build this recipe measured" >&2; exit 1; }
echo "pulled $PROD_IMAGE (image $id, build $RECIPE_BUILD)"
