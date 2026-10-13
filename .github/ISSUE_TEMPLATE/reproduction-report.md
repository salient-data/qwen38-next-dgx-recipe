---
name: Reproduction report
about: You ran the recipe on your Spark; tell us what you got (it helps everyone)
---

**`./recipe/diagnose.sh` output** (paste the whole report; it covers the build, host, driver, Docker, memory,
disk, checkpoint and launch command below, so you can skip those):

**Build** (from `recipe/pins.env`, `RECIPE_BUILD`):

**Host**: DGX OS version, kernel (`uname -r`), driver (`cat /proc/driver/nvidia/version`, open or proprietary),
Docker version:

**What you ran** (paste `./recipe/launch.sh --print`, with any changes you made):

**Results** (paste the harness `overall` blocks, or attach the JSON files; say how many runs):

**`./recipe/verify.sh` output**:

**Anything that went wrong** (logs: `docker logs qwen38-flash-next 2>&1 | tail -100`):
