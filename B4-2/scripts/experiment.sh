#!/usr/bin/env bash
# Linux only: launch the supplied application without inspecting its internals.
set -euo pipefail
[[ "$(id -u)" != 0 ]] || { echo 'Non-root execution required.' >&2; exit 2; }
: "${RUN_ID:?}" "${APP_BIN:?}" "${SECONDS_PER_CASE:?}"
EVIDENCE="/work/docs/evidence/$RUN_ID"
mkdir -p "$EVIDENCE"
{
    date -u +%FT%TZ
    id
    uname -a
    cat /etc/os-release
    sha256sum "$APP_BIN" /work/scripts/*.sh
    printf 'max_case_seconds=%s\n' "$SECONDS_PER_CASE"
    cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max
} > "$EVIDENCE/environment.txt"
app_pid=''
monitor_pid=''
cleanup() {
    if [[ -n "$app_pid" ]]; then
        kill -TERM -- "-$app_pid" 2>/dev/null || true
        sleep 1
        kill -KILL -- "-$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
    fi
    if [[ -n "$monitor_pid" ]]; then
        kill "$monitor_pid" 2>/dev/null || true
        wait "$monitor_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ "${1:-all}" == all ]]; then
    cases=(oom-before oom-after cpu-before cpu-after deadlock-before deadlock-after)
else
    cases=("$1")
fi
for case_name in "${cases[@]}"; do
    case "$case_name" in
        oom-before) MEMORY_LIMIT=50; CPU_MAX_OCCUPY=100; MULTI_THREAD_ENABLE=false ;;
        oom-after) MEMORY_LIMIT=100; CPU_MAX_OCCUPY=100; MULTI_THREAD_ENABLE=false ;;
        cpu-before) MEMORY_LIMIT=512; CPU_MAX_OCCUPY=100; MULTI_THREAD_ENABLE=false ;;
        cpu-after) MEMORY_LIMIT=512; CPU_MAX_OCCUPY=10; MULTI_THREAD_ENABLE=false ;;
        deadlock-before) MEMORY_LIMIT=512; CPU_MAX_OCCUPY=10; MULTI_THREAD_ENABLE=true ;;
        deadlock-after) MEMORY_LIMIT=512; CPU_MAX_OCCUPY=10; MULTI_THREAD_ENABLE=false ;;
        *) echo "Unknown case: $case_name" >&2; exit 2 ;;
    esac
    out="$EVIDENCE/$case_name"
    export AGENT_HOME="/work/runtime/$RUN_ID/$case_name"
    export AGENT_PORT=15034
    export AGENT_UPLOAD_DIR="$AGENT_HOME/upload_files"
    export AGENT_KEY_PATH="$AGENT_HOME/api_keys"
    export AGENT_LOG_DIR="$out/app-logs"
    export MEMORY_LIMIT CPU_MAX_OCCUPY MULTI_THREAD_ENABLE
    mkdir -p "$AGENT_UPLOAD_DIR" "$AGENT_KEY_PATH" "$AGENT_LOG_DIR"
    printf 'agent_api_key_test\n' > "$AGENT_KEY_PATH/secret.key"
    chmod 600 "$AGENT_KEY_PATH/secret.key"
    env | sort | sed -n '/^AGENT_/p;/^MEMORY_LIMIT=/p;/^CPU_MAX_OCCUPY=/p;/^MULTI_THREAD_ENABLE=/p' > "$out/config.txt"
    cat /sys/fs/cgroup/memory.events > "$out/cgroup-before.txt"
    printf 'Launching %s\n' "$case_name"
    start=$(date +%s)
    # A PTY preserves unflushed terminal messages preceding self-termination.
    setsid script -q -e -c "$APP_BIN" /dev/null > "$out/application.log" 2>&1 &
    app_pid=$!
    printf 'pid=%s\nstarted_utc=%s\ncommand=%s\n' "$app_pid" "$(date -u +%FT%TZ)" "$APP_BIN" > "$out/result.txt"
    bash /work/scripts/monitor.sh "$app_pid" "$out" &
    monitor_pid=$!
    termination=application_exit
    while kill -0 "$app_pid" 2>/dev/null; do
        state=$(ps -o stat= -p "$app_pid" || true)
        [[ -n "$state" && "$state" != *Z* ]] || break
        if (( $(date +%s) - start >= SECONDS_PER_CASE )); then
            termination=experiment_timeout
            break
        fi
        sleep 1
    done
    elapsed=$(( $(date +%s) - start ))
    printf 'observation_end_utc=%s\n' "$(date -u +%FT%TZ)" >> "$out/result.txt"
    if [[ "$termination" == experiment_timeout ]]; then
        kill "$monitor_pid" 2>/dev/null || true
        wait "$monitor_pid" 2>/dev/null || true
        monitor_pid=''
        printf '\n[HARNESS] observation ended; sending SIGTERM\n' >> "$out/application.log"
        kill -TERM -- "-$app_pid" 2>/dev/null || true
        sleep 2
        kill -KILL -- "-$app_pid" 2>/dev/null || true
    fi
    exit_code=0
    wait "$app_pid" || exit_code=$?
    app_pid=''
    if [[ -n "$monitor_pid" ]]; then wait "$monitor_pid" || true; fi
    monitor_pid=''
    printf 'observed_seconds=%s\ntermination=%s\nexit_code=%s\n' "$elapsed" "$termination" "$exit_code" >> "$out/result.txt"
    cat /sys/fs/cgroup/memory.events > "$out/cgroup-after.txt"
    awk -F, 'NR>1 && $3!="EXIT" {if(n++==0) first=$6; last=$6; if($6>rss)rss=$6; if($4>cpu)cpu=$4} END {printf "samples=%d\nfirst_rss_kib=%d\nlast_rss_kib=%d\npeak_rss_kib=%d\npeak_cpu_one_core_percent=%.2f\n", n,first,last,rss,cpu}' "$out/monitor.csv" >> "$out/result.txt"
    cat "$out/result.txt"
done
