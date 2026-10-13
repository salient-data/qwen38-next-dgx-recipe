# Sourced by pull.sh, launch.sh and qfn (not run on its own): is an image or container the published prod image?
# pins.env records two digests for it: PROD_IMAGE pins the registry manifest digest (what docker pulls) and
# PROD_IMAGE_ID is the image's config digest. Docker reports an image's ID differently by image store: the classic
# store (overlay2) reports the config digest, the containerd image store (the default for new Docker 29 installs)
# reports the manifest digest. Any of these matches: ID == config digest, ID == manifest digest, or RepoDigests
# containing PROD_IMAGE.
prod_digest() { [[ -n "${PROD_IMAGE:-}" ]] && echo "${PROD_IMAGE##*@}"; }
is_prod_id() {        # is_prod_id ID: an image ID (from docker image inspect or a container's .Image)
  [[ -n "$1" && -n "${PROD_IMAGE:-}" ]] || return 1
  [[ "$1" == "${PROD_IMAGE_ID:-none}" || "$1" == "$(prod_digest)" ]]
}
is_prod_image() {     # is_prod_image REF: the local image REF is the published prod image
  local id rd
  id="$(docker image inspect -f '{{.Id}}' "$1" 2>/dev/null)" || return 1
  is_prod_id "$id" && return 0
  rd="$(docker image inspect -f '{{join .RepoDigests " "}}' "$1" 2>/dev/null || true)"
  [[ " $rd " == *" ${PROD_IMAGE} "* ]]
}
