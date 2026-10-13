#!/usr/bin/env bash
# Collect what we need to help with a problem into one report you can paste into a forum post or a GitHub issue.
#   ./diagnose.sh                 read-only: host, driver, Docker, memory, disk, checkpoint, preflight, the launch
#                                 command and, if the container still exists, the server log
#   ./diagnose.sh LOGFILE         also read a saved server log, for a start that failed in the foreground (the
#                                 container is removed when it exits):  ./launch.sh 2>&1 | tee -i launch.log
# Prints the report and saves it as qfn-diagnose-<time>.txt in the current folder. Changes nothing, starts nothing,
# sends nothing. It replaces your user name, home folder and host name with placeholders and prints no environment
# variables or tokens; read it before you post it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; source "$HERE/pins.env"
LOG=""
for a in "$@"; do
  case "$a" in
    -h|--help) awk 'NR > 1 && !/^#/ {exit} NR > 1' "$HERE/$(basename "$0")"; exit 0 ;;
    -*) echo "unknown argument: $a (see ./diagnose.sh --help)" >&2; exit 2 ;;
    *) [[ -r "$a" ]] || { echo "cannot read $a" >&2; exit 2; }; LOG="$a" ;;
  esac
done
NAME="${NAME:-qwen38-flash-next}"
HUB="${HF_HUB_CACHE:-${HF_HOME:-$HOME/.cache/huggingface}/hub}"
MDIR="${MODEL_DIR:-$HUB/models--${MODEL_ID//\//--}}"
CDIR="${CACHE_DIR:-$HOME/.cache/qwen38-next-dgx-recipe}"
OUT="qfn-diagnose-$(date +%Y%m%d-%H%M%S).txt"
sec() { printf '\n## %s\n' "$*"; }
redact() {   # longest first, so /home/<user> becomes ~ before the user name alone is replaced
  local u h; u="$(id -un)"; h="$(hostname 2>/dev/null || echo)"
  sed -e "s#$HOME#~#g" -e "s#\b$u\b#<user>#g" ${h:+-e "s#\b$h\b#<host>#g"} \
      -e 's#\(hf_\)[A-Za-z0-9]\{20,\}#\1<token>#g' -e 's#\(Bearer \)[^ "]*#\1<token>#g'
}
report() {
  echo "qfn diagnose for $RECIPE_NAME, generated $(date -u +%FT%TZ)"
  sec "Recipe"
  echo "build $RECIPE_BUILD, image $IMAGE, model $MODEL_ID @ ${MODEL_REVISION:0:8}"
  git -C "$HERE" log -1 --format='commit %h (%cs) %s' 2>/dev/null
  ch="$(git -C "$HERE/.." status --porcelain 2>/dev/null)"; [[ -z "$ch" ]] && echo "no local changes" || { echo "local changes:"; echo "$ch"; }
  [[ -n "$ch" ]] && git -C "$HERE/.." diff --stat 2>/dev/null | tail -20
  sec "Host"
  echo "$(uname -m), kernel $(uname -r), $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown OS}")"
  [[ -r /etc/dgx-release ]] && { grep -E '^DGX_(NAME|SWBUILD_VERSION)=' /etc/dgx-release; grep '^DGX_OTA_VERSION=' /etc/dgx-release | tail -1; }
  echo "uptime: $(uptime -p 2>/dev/null)"
  sec "GPU and driver"
  nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>&1 | head -2
  head -1 /proc/driver/nvidia/version 2>/dev/null
  nvidia-smi 2>/dev/null | grep -o 'CUDA Version: [0-9.]*'
  echo "GPU processes:"; nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>&1 | sed '/^$/d;s/^/  /' | head -10
  sec "Docker"
  docker version --format 'client {{.Client.Version}}, server {{.Server.Version}}' 2>&1 | head -2
  docker info --format 'runtimes: {{range $k, $v := .Runtimes}}{{$k}} {{end}}; default {{.DefaultRuntime}}' 2>&1 | head -1
  echo "recipe images:"; docker images --format '  {{.Repository}}:{{.Tag}} {{.ID}} {{.CreatedSince}} {{.Size}}' 2>/dev/null | grep -E 'qwen38-next-dgx|vllm' | head -10
  docker image inspect "$IMAGE" --format "pinned image $IMAGE present: {{.Id}}" 2>/dev/null || echo "pinned image $IMAGE not present"
  echo "containers:"; docker ps -a --format '  {{.Names}} {{.Image}} {{.Status}}' 2>/dev/null | head -10
  sec "Memory"
  free -h
  grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|Shmem|AnonPages|Mlocked|Unevictable|HugePages_Total|Hugepagesize|CmaTotal|CmaFree):' /proc/meminfo
  echo "swappiness $(cat /proc/sys/vm/swappiness 2>/dev/null), overcommit $(cat /proc/sys/vm/overcommit_memory 2>/dev/null)"
  echo "largest processes (RSS):"; ps -eo rss=,comm= --sort=-rss | head -8 | awk '{printf "  %6.1f GiB  %s\n", $1/1048576, $2}'
  sec "Checkpoint and disk"
  echo "Hugging Face cache: $HUB"; echo "model folder: $MDIR -> $(readlink -f "$MDIR" 2>/dev/null || echo missing)"
  snap="$MDIR/snapshots/$MODEL_REVISION"
  if [[ -d "$snap" ]]; then
    echo "pinned snapshot: $(find "$snap" -maxdepth 1 | tail -n +2 | wc -l) entries, $(du -shL "$snap" 2>/dev/null | cut -f1) resolved"
    echo "snapshots present: $(ls "$MDIR/snapshots" 2>/dev/null | cut -c1-8 | tr '\n' ' ')"
  else echo "pinned snapshot $MODEL_REVISION not found"; fi
  for d in "$MDIR" "$CDIR"; do [[ -e "$d" ]] && echo "$d: $(df -h --output=source,fstype,size,avail "$(readlink -f "$d")" | tail -1 | tr -s ' '), $(findmnt -no OPTIONS -T "$(readlink -f "$d")" 2>/dev/null)"; done
  sec "preflight.sh"
  ( cd "$HERE" && MODEL_DIR="$MDIR" timeout 120 ./preflight.sh 2>&1 )
  sec "launch.sh --print"
  ( cd "$HERE" && MODEL_DIR="$MDIR" timeout 30 ./launch.sh --print 2>&1 ) | head -5
  sec "Kernel messages about memory (last 2 hours, if readable)"
  k="$({ journalctl -k --since "-2h" --no-pager 2>/dev/null || dmesg 2>/dev/null; } | grep -iE 'oom|out of memory|killed process|NVRM|Xid' | tail -15)"
  echo "${k:-none found (or not readable without sudo)}"
  sec "Server log"
  local src=""
  if [[ -n "$LOG" ]]; then src="file $(basename "$LOG")"; logtext() { cat "$LOG"; }
  elif docker container inspect "$NAME" > /dev/null 2>&1; then src="docker logs $NAME"; logtext() { docker logs "$NAME" 2>&1; }
  fi
  if [[ -z "$src" ]]; then
    echo "no log: the container $NAME does not exist (a foreground start removes it when it exits)."
    echo "to capture one, from the repo root: ./recipe/launch.sh 2>&1 | tee -i launch.log   then   ./recipe/diagnose.sh launch.log"
  else
    echo "from $src: key lines"
    clean() { logtext | tr '\r' '\n' | sed 's/\x1b\[[0-9;]*m//g' | grep -v 'it/s]' | cut -c1-700; }
    clean | grep -E 'Model loading took|Available KV cache memory|Free memory on device|GPU KV cache size|CUDA graph pool memory|estimated maximum model length|Error|ERROR|Traceback|out of memory|Killed' | head -60
    echo; echo "last 60 lines:"; clean | tail -60
  fi
}
{ echo '```'; report; echo '```'; } | redact > "$OUT"
cat "$OUT"
echo
echo "saved: $PWD/$OUT ($(wc -c < "$OUT") bytes). Read it, then paste all of it into your post (it is already wrapped in a code block)." >&2
