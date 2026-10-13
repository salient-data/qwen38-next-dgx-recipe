#!/usr/bin/env bash
# Collect what we need to help with a problem into one report you can paste into a forum post or a GitHub issue.
#   ./diagnose.sh                 read-only: host, driver, Docker, memory, disk, checkpoint, preflight, the launch
#                                 command and, if the container still exists, the server log
#   ./diagnose.sh LOGFILE         also read a saved server log, for a start that failed in the foreground (the
#                                 container is removed when it exits):
#                                   WARMUP=0 ./launch.sh 2>&1 | tee -i launch.log; ./diagnose.sh launch.log
#   ./diagnose.sh --issue [LOG]   then, only if you answer y, file the report as a PUBLIC issue on the recipe's GitHub
#                                 repo (with the gh CLI if you are signed in, else it prints a link to paste it into)
# Saves the report as qfn-diagnose-<time>.txt (in this folder, else $TMPDIR), already wrapped in a code block.
# Changes nothing, starts nothing, and sends nothing unless you confirm --issue. It replaces your user name, home
# folder and host name with placeholders, and API keys and tokens with <redacted>; read it before you share it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; source "$HERE/pins.env"
LOG=""; ISSUE=0
for a in "$@"; do
  case "$a" in
    -h|--help) awk 'NR > 1 && !/^#/ {exit} NR > 1' "$HERE/$(basename "$0")"; exit 0 ;;
    --issue) ISSUE=1 ;;
    -*) echo "unknown argument: $a (see ./diagnose.sh --help)" >&2; exit 2 ;;
    *) [[ -r "$a" ]] || { echo "cannot read $a" >&2; exit 2; }; LOG="$a" ;;
  esac
done
if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
  echo "note: run this without sudo (as your own user) so it finds your Hugging Face cache; to use Docker without sudo: sudo usermod -aG docker $SUDO_USER, then log in again" >&2
fi
NAME="${NAME:-qwen38-flash-next}"
HUB="${HF_HUB_CACHE:-${HF_HOME:-$HOME/.cache/huggingface}/hub}"
MDIR="${MODEL_DIR:-$HUB/models--${MODEL_ID//\//--}}"
CDIR="${CACHE_DIR:-$HOME/.cache/qwen38-next-dgx-recipe}"
MAX_BYTES=30000   # Discourse's default post limit is 32,000 characters
sec() { printf '\n## %s\n' "$*"; }
T() { timeout 20 "$@"; }   # a hung Docker daemon or driver must not hang the report

# Redaction. Values are escaped for sed; empty or trivial values are skipped (HOME=/ must not rewrite every /).
escb() { printf '%s' "$1" | sed 's/[][\.*^$#/]/\\&/g'; }          # for basic regexes (sed without -E)
esc() { printf '%s' "$1" | sed 's/[][\.*^$#/+?(){}|]/\\&/g'; }     # for extended regexes (sed -E)
RED=(-e 's#\(hf_\)[A-Za-z0-9]\{20,\}#\1<redacted>#g' -e 's#\(Bearer \)[^ "]*#\1<redacted>#g'
     -e 's#\(--api-key[ =]\)[^ ]*#\1<redacted>#g' -e "s#\(api_key['\"]\{0,1\}[:=] *\)\[[^]]*\]#\1<redacted>#Ig" -e "s#\(api_key['\"]\{0,1\}[:=] *\)[^ }]*#\1<redacted>#Ig"
     -e 's#\([A-Z_]*\(KEY\|TOKEN\|SECRET\|PASSWORD\)=\)[^ ]*#\1<redacted>#g')
homes=("$HOME"); users=("$(id -un)")
if [[ -n "${SUDO_USER:-}" ]]; then users+=("$SUDO_USER"); homes+=("$(getent passwd "$SUDO_USER" | cut -d: -f6)"); fi
for d in "${homes[@]}"; do [[ ${#d} -gt 1 && "$d" == /* ]] && RED+=(-e "s#$(escb "$d")\([/:]\|\$\)#~\1#g"); done
for u in "${users[@]}"; do   # only in paths (/name/ or /name:), and never names that are also common words here
  case "$u" in ''|root|nvidia|docker|vllm|dgx|spark|ubuntu|admin|user|cuda) continue ;; esac
  RED+=(-e "s#/$(escb "$u")\([/:]\|\$\)#/<user>\1#g")
done
h="$(hostname 2>/dev/null || true)"; HOSTRED=(-e 's/^//')
[[ ${#h} -ge 4 ]] && HOSTRED=(-e "s#(^|[^[:alnum:]._-])$(esc "$h")([^[:alnum:]_-]|\$)#\1<host>\2#g")
redact() { sed "${RED[@]}" | sed -E "${HOSTRED[@]}"; }

DOCKER_OK=1; DOCKER_ERR=""
T docker info > /dev/null 2>&1 || { DOCKER_OK=0; DOCKER_ERR="$(T docker info 2>&1 | tail -1)"; }

main_report() {
  echo "qfn diagnose for $RECIPE_NAME, generated $(date -u +%FT%TZ)"
  sec "Recipe"
  echo "build $RECIPE_BUILD, image $IMAGE, model $MODEL_ID @ ${MODEL_REVISION:0:8}"
  git -C "$HERE" log -1 --format='commit %h (%cs) %s' 2>/dev/null
  ch="$(git -C "$HERE/.." status --porcelain --untracked-files=no 2>/dev/null | head -20)"
  [[ -z "$ch" ]] && echo "no local changes to tracked files" || { echo "local changes:"; echo "$ch"; git -C "$HERE/.." diff --stat 2>/dev/null | tail -20; }
  sec "Host"
  echo "$(uname -m), kernel $(uname -r), $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown OS}")"
  [[ -r /etc/dgx-release ]] && { grep -E '^DGX_(NAME|SWBUILD_VERSION)=' /etc/dgx-release; grep '^DGX_OTA_VERSION=' /etc/dgx-release | tail -1; }
  echo "uptime: $(uptime -p 2>/dev/null)"
  sec "GPU and driver"
  T nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>&1 | head -2
  head -1 /proc/driver/nvidia/version 2>/dev/null
  T nvidia-smi 2>/dev/null | grep -o 'CUDA Version: [0-9.]*'
  echo "GPU processes:"; T nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>&1 | sed '/^$/d;s/^/  /' | head -10
  sec "Docker"
  if (( DOCKER_OK )); then
    T docker version --format 'docker client {{.Client.Version}}, server {{.Server.Version}}' 2>&1 | head -1
    T docker buildx version 2>&1 | head -1
    command -v nvidia-ctk > /dev/null && nvidia-ctk --version 2>&1 | head -1
    T docker info --format 'runtimes: {{range $k, $v := .Runtimes}}{{$k}} {{end}}; default {{.DefaultRuntime}}' 2>&1 | head -1
    echo "recipe images:"; T docker images --format '  {{.Repository}}:{{.Tag}} {{.ID}} {{.CreatedSince}} {{.Size}}' 2>&1 | grep -E 'qwen38-next-dgx' | head -10
    T docker image inspect "$IMAGE" --format "pinned image present: {{.Id}}" 2>/dev/null || echo "pinned image $IMAGE not present"
    echo "running containers:"; T docker ps --format '  {{.Names}} {{.Image}} {{.Status}}' 2>&1 | head -10
    T docker ps -a --filter "name=^${NAME}\$" --format "  $NAME: {{.Status}}" 2>&1
  else echo "docker not accessible: $DOCKER_ERR"; fi
  sec "Memory"
  free -h
  grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|Shmem|AnonPages|Mlocked|Unevictable|HugePages_Total|Hugepagesize|CmaTotal|CmaFree):' /proc/meminfo
  echo "swappiness $(cat /proc/sys/vm/swappiness 2>/dev/null), overcommit $(cat /proc/sys/vm/overcommit_memory 2>/dev/null)"
  echo "largest processes (RSS):"; ps -eo rss=,comm= --sort=-rss | head -8 | awk '{printf "  %6.1f GiB  %s\n", $1/1048576, $2}'
  sec "Checkpoint and disk"
  echo "Hugging Face cache: $HUB"; echo "model folder: $MDIR -> $(readlink -f "$MDIR" 2>/dev/null || echo missing)"
  snap="$MDIR/snapshots/$MODEL_REVISION"
  if [[ -d "$snap" ]]; then
    echo "pinned snapshot: $(find "$snap" -maxdepth 1 | tail -n +2 | wc -l) entries, $(timeout 60 du -shL "$snap" 2>/dev/null | cut -f1) resolved"
    echo "snapshots present: $(ls "$MDIR/snapshots" 2>/dev/null | cut -c1-8 | tr '\n' ' ')"
  else echo "pinned snapshot $MODEL_REVISION not found"; fi
  for d in "$MDIR" "$CDIR"; do [[ -e "$d" ]] && echo "$d: $(df -h --output=source,fstype,size,avail "$(readlink -f "$d")" | tail -1 | tr -s ' '), $(findmnt -no OPTIONS -T "$(readlink -f "$d")" 2>/dev/null)"; done
  sec "preflight.sh"
  ( cd "$HERE" && MODEL_DIR="$MDIR" timeout 120 ./preflight.sh 2>&1 )
  sec "launch.sh --print"
  ( cd "$HERE" && MODEL_DIR="$MDIR" timeout 30 ./launch.sh --print 2>&1 ) | head -5
  sec "Kernel messages about memory and the GPU (this boot, if readable)"
  k="$({ journalctl -k -b --no-pager 2>/dev/null || dmesg 2>/dev/null; } | grep -iE 'oom|out of memory|killed process|NVRM|Xid' | tail -15)"
  echo "${k:-none found (or not readable without sudo)}"
}
# The server log: key lines from the boot, then the last lines. Progress bars, blank lines and access-log lines
# (client addresses) are dropped; every line is cut to 400 characters.
clean() { tr '\r' '\n' | sed 's/\x1b\[[0-9;]*m//g' | grep -vE '(it/s|s/it)\]|\| *[0-9]+/[0-9]+ \[|^(\(APIServer[^)]*\) )?INFO: +\[?[0-9.:a-f]+\]?:[0-9]+ - "| Route: /' | sed '/^[[:space:]]*$/d' | cut -c1-400; }
KEY='version [0-9]|non-default args|Available RAM|Resolved Engram|Model loading took|Available KV cache memory|Free memory on device|GPU KV cache size|CUDA graph pool memory|Graph capturing finished|estimated maximum model length|out of memory'
LOGSRC=""; LOGHEAD=""; LOGTAIL=""
if [[ -n "$LOG" ]]; then
  LOGSRC="file $(basename "$LOG")"; LOGHEAD="$(head -3000 "$LOG" | clean)"; LOGTAIL="$(tail -400 "$LOG" | clean | tail -40)"
elif (( DOCKER_OK )) && T docker container inspect "$NAME" > /dev/null 2>&1; then
  LOGSRC="docker logs $NAME"; LOGHEAD="$(timeout 60 docker logs "$NAME" 2>&1 | head -3000 | clean)"
  LOGTAIL="$(timeout 60 docker logs --tail 400 "$NAME" 2>&1 | clean | tail -40)"
fi
log_head() {
  sec "Server log"
  if [[ -z "$LOGSRC" ]]; then
    echo "no log: the container $NAME does not exist (a foreground start removes it when it exits)."
    echo "to capture one, from the repo root: WARMUP=0 ./recipe/launch.sh 2>&1 | tee -i launch.log; ./recipe/diagnose.sh launch.log"
    return
  fi
  echo "from $LOGSRC"; echo "key lines:"; grep -E "$KEY" <<< "$LOGHEAD" | head -25
}

OUTDIR="$PWD"; [[ -w "$OUTDIR" ]] || OUTDIR="${TMPDIR:-/tmp}"
OUT="$OUTDIR/qfn-diagnose-$(date +%Y%m%d-%H%M%S).txt"
# The log's last lines hold the error, so when the report is too long for a forum post, its tail keeps its end.
body="$({ main_report; log_head; } 2>&1 | redact)"
if [[ -n "$LOGSRC" ]]; then
  tl="$(redact <<< "$LOGTAIL")"; budget=$(( MAX_BYTES - ${#body} - 300 ))
  if (( ${#tl} > budget )); then
    tl="[earlier lines cut to fit a forum post]"$'\n'"$(tail -c "$(( budget > 0 ? budget : 0 ))" <<< "$tl" | sed 1d)"
    echo "note: the log's last lines were shortened to fit a forum post" >&2
  fi
  body+=$'\n\n'"last lines:"$'\n'"$tl"
fi
printf '```\n%s\n```\n' "$body" > "$OUT"
cat "$OUT"
echo >&2
echo "saved: $OUT ($(wc -c < "$OUT") bytes). Read it, then paste all of it into your post (it is already a code block)." >&2

# --issue: nothing is sent without a "y" typed at a terminal.
file_issue() {
  local repo="${QFN_ISSUE_REPO:-salient-data/qwen38-next-dgx-recipe}" ans line title url
  [[ -t 0 ]] || { echo "--issue asks before it sends anything; run it in a terminal" >&2; return 2; }
  read -r -p "File this report as a PUBLIC issue on github.com/$repo (anyone can read it)? [y/N] " ans
  [[ "$ans" =~ ^[Yy]([Ee][Ss])?$ ]] || { echo "not sent; the report is in $OUT" >&2; return 0; }
  read -r -p "One line describing the problem (Enter to skip): " line
  title="Help: ${line:-diagnose report ($RECIPE_BUILD)}"; title="${title:0:120}"
  if command -v gh > /dev/null && gh auth status -h github.com > /dev/null 2>&1; then
    TMPF="$(mktemp)"; trap 'rm -f "$TMPF"' EXIT INT TERM
    { echo "Filed with \`./recipe/diagnose.sh --issue\`."; [[ -n "$line" ]] && printf '\n%s\n' "$line"; echo; cat "$OUT"; } > "$TMPF"
    if gh issue create --repo "$repo" --title "$title" --body-file "$TMPF"; then rm -f "$TMPF"; return 0; fi
    rm -f "$TMPF"; echo "gh could not create the issue (see above); use the link below instead" >&2
  fi
  url="https://github.com/$repo/issues/new"
  command -v python3 > /dev/null && url+="?$(python3 -c 'import sys,urllib.parse as u; print(u.urlencode({"title":sys.argv[1],"body":sys.argv[2]}))' "$title" "Paste the contents of $(basename "$OUT") here.")"
  echo "open this link while signed in to GitHub, paste the contents of $OUT into the box, and submit:" >&2
  echo "$url"
}
if (( ISSUE )); then file_issue; exit $?; fi
exit 0
