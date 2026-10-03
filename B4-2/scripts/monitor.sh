#!/usr/bin/env bash
# Include launcher descendants (e.g. PyInstaller); RSS sum may count shared pages twice.
set -euo pipefail
pid="${1:?PID required}"
out="${2:?Output directory required}"
[[ "$pid" =~ ^[1-9][0-9]*$ ]] || exit 2
mkdir -p "$out"
hz=$(getconf CLK_TCK)
read -r previous_time _ < /proc/uptime
previous_ticks=0
initialized=false
sample=0
printf 'utc,pid,state,cpu_one_core_percent,cpu_lifetime_percent,rss_sum_kib,threads,app_log_bytes\n' > "$out/monitor.csv"
while [[ -r "/proc/$pid/stat" ]]; do
    stat=$(cat "/proc/$pid/stat" 2>/dev/null) || break
    # Remove PID and parenthesized comm, which may contain whitespace.
    fields="${stat##*) }"
    read -ra values <<< "$fields"
    state="${values[0]}"
    [[ "$state" != Z ]] || break
    pids=("$pid")
    for (( i=0; i<${#pids[@]}; i++ )); do
        children=$(cat "/proc/${pids[i]}/task/${pids[i]}/children" 2>/dev/null || true)
        read -ra child_pids <<< "$children"
        pids+=("${child_pids[@]}")
    done
    ticks=0
    for target in "${pids[@]}"; do
        child_stat=$(cat "/proc/$target/stat" 2>/dev/null) || continue
        read -ra child_values <<< "${child_stat##*) }"
        ticks=$(( ticks + child_values[11] + child_values[12] ))
    done
    read -r now _ < /proc/uptime
    cpu=0
    if [[ "$initialized" == true ]]; then
        cpu=$(awk -v delta="$((ticks - previous_ticks))" -v t="$now" -v p="$previous_time" -v hz="$hz" 'BEGIN {if(t>p && delta>=0) printf "%.2f",100*delta/hz/(t-p); else print 0}')
    fi
    pid_list=$(IFS=,; echo "${pids[*]}")
    metrics=$(ps -p "$pid_list" -o pcpu=,rss=,nlwp= | awk '{cpu+=$1;rss+=$2;n+=$3} END {print cpu,rss,n}')
    read -r lifetime rss threads <<< "$metrics"
    bytes=0
    [[ ! -f "$out/application.log" ]] || bytes=$(stat -c %s "$out/application.log")
    printf '%s,%s,%s,%s,%s,%s,%s,%s\n' "$(date -u +%FT%TZ)" "$pid" "$state" "$cpu" "$lifetime" "$rss" "$threads" "$bytes" >> "$out/monitor.csv"
    if (( sample % 5 == 0 )); then
        {
            date -u +%FT%TZ
            printf '$ ps -fp %s\n' "$pid_list"
            ps -fp "$pid_list" || true
            printf '$ ps -L -p %s -o pid,tid,stat,pcpu,rss,wchan:32,comm\n' "$pid_list"
            ps -L -p "$pid_list" -o pid,tid,stat,pcpu,rss,wchan:32,comm || true
            printf '$ ss -ltn\n'
            ss -ltn
        } >> "$out/process.txt" 2>&1
    fi
    if (( sample % 10 == 0 )); then
        top -b -H -n 1 -p "$pid_list" >> "$out/top-threads.txt" 2>&1 || true
    fi
    previous_time=$now
    previous_ticks=$ticks
    initialized=true
    sample=$(( sample + 1 ))
    sleep 1
done
printf '%s,%s,EXIT,0,0,0,0,0\n' "$(date -u +%FT%TZ)" "$pid" >> "$out/monitor.csv"
