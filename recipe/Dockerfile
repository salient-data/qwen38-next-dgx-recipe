# The serving image: a pinned vLLM nightly plus the patches named in patches/series, applied in order with
# patch --fuzz=0 (a patch that does not apply exactly fails the build). Each patch's sha256 is stamped under
# /opt/recipe/patches/ so a running container can be traced to the exact patch bytes. build.sh passes BASE.
# build.sh passes the pinned digest from pins.env; a build without it fails at FROM with this placeholder name.
ARG BASE=pass-base-via-build.sh
FROM ${BASE}
COPY patches/ /tmp/recipe-patches/
RUN set -e; cd "$(python3 -c 'import vllm, os; print(os.path.dirname(os.path.dirname(vllm.__file__)))')"; \
    mkdir -p /opt/recipe/patches; \
    for p in $(grep -v '^#' /tmp/recipe-patches/series); do \
      patch -p1 --fuzz=0 --dry-run < /tmp/recipe-patches/$p.patch > /dev/null; \
      patch -p1 --fuzz=0 --no-backup-if-mismatch < /tmp/recipe-patches/$p.patch > /dev/null; \
      sha256sum /tmp/recipe-patches/$p.patch | cut -d' ' -f1 > /opt/recipe/patches/$p.sha256; \
      for f in $(grep -E '^\+\+\+ b/.*\.py$' /tmp/recipe-patches/$p.patch | sed 's#^+++ b/##'); do python3 -m py_compile "$f"; done; \
    done; \
    rm -rf /tmp/recipe-patches
