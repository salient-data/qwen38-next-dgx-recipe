# Security

- `recipe/launch.sh` binds `127.0.0.1` by default. `BIND=0.0.0.0` serves the API on every interface with no
  authentication unless `VLLM_API_KEY` is set (it is passed as an environment variable, not on the command line);
  put it behind your own network controls either way.
- The server runs with `--trust-remote-code`. At the pinned revision the model repository contains no Python files,
  so nothing from it is executed; a different revision could change that.
- The benchmark harness executes model-written Python to grade coding answers (in a subprocess with a 10 s
  timeout). Run it on a machine where that is acceptable.
- Report a security problem in this repository privately through GitHub's "Report a vulnerability" on this repo.
