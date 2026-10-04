#!/usr/bin/env bash
# Run isolated comparison experiments; persist all artifacts under B4-2.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECONDS_PER_CASE="${SECONDS_PER_CASE:-90}"
IMAGE="${LAB_IMAGE:-b4-2-lab:22.04}"
CASE="${1:-all}"
case "$CASE" in
    all|oom-before|oom-after|cpu-before|cpu-after|deadlock-before|deadlock-after) ;;
    *) echo 'Usage: bash scripts/run.sh [all|oom-before|oom-after|cpu-before|cpu-after|deadlock-before|deadlock-after]' >&2; exit 2 ;;
esac
if [[ ! "$SECONDS_PER_CASE" =~ ^[1-9][0-9]*$ ]] || (( SECONDS_PER_CASE > 3600 )); then
    echo 'SECONDS_PER_CASE must be 1..3600.' >&2; exit 2;
fi
ARCH="$(docker info --format '{{.Architecture}}')"
case "$ARCH" in
    aarch64|arm64) BIN=agent-leak-app-arm64 ;;
    x86_64|amd64) BIN=agent-leak-app-x86 ;;
    *) echo "Unsupported Docker architecture: $ARCH" >&2; exit 2 ;;
esac
[[ -f "$ROOT/agent-app/$BIN" && -x "$ROOT/agent-app/$BIN" ]] || {
    echo "Missing executable: $ROOT/agent-app/$BIN" >&2
    echo 'Place the provided binary here and chmod +x it. No substitute application is used.' >&2
    exit 2
}
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$ROOT/docs/evidence/$RUN_ID"
{
    date -u +%FT%TZ
    docker image inspect "$IMAGE" --format 'image={{.Id}}'
    printf 'case=%s seconds=%s memory=768m cpus=1 network=none user=%s:%s\n' \
        "$CASE" "$SECONDS_PER_CASE" "$(id -u)" "$(id -g)"
} > "$ROOT/docs/evidence/$RUN_ID/host-environment.txt"
docker run --rm --init --network none --read-only --cap-drop ALL \
    --security-opt no-new-privileges --memory 768m --memory-swap 768m --cpus 1 \
    --pids-limit 128 --user "$(id -u):$(id -g)" \
    --tmpfs /tmp:rw,exec,nosuid,nodev,size=128m \
    --mount "type=bind,src=$ROOT,dst=/work" --workdir /work \
    -e "RUN_ID=$RUN_ID" -e "APP_BIN=/work/agent-app/$BIN" \
    -e "SECONDS_PER_CASE=$SECONDS_PER_CASE" \
    "$IMAGE" bash scripts/experiment.sh "$CASE" \
    2>&1 | tee "$ROOT/docs/evidence/$RUN_ID/runner.log"
printf 'Evidence: %s/docs/evidence/%s\n' "$ROOT" "$RUN_ID"
