#!/usr/bin/env bash
# Verify saved runs; never substitute expected numbers for measured evidence.
# 2026-10-03: Read-only Docker verification of run 20261002T054757Z-69135 passed.
# This checks saved evidence consistency, not actual OS CPU saturation.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
run="${1:?Usage: bash scripts/verify.sh RUN_ID}"
[[ "$run" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9]+$ ]] || exit 2
base="$root/docs/evidence/$run"
for name in oom-before oom-after cpu-before cpu-after deadlock-before deadlock-after; do
    test -s "$base/$name/result.txt"
    test -s "$base/$name/process.txt"
    test -s "$base/$name/top-threads.txt"
    grep -q 'All Boot Checks Passed' "$base/$name/application.log"
    awk -F, 'NR>1 && $3!="EXIT" {n++} END {exit(n<2)}' "$base/$name/monitor.csv"
    cmp "$base/$name/cgroup-before.txt" "$base/$name/cgroup-after.txt"
done
echo 'PASS: six runs have boot, metrics, process/thread evidence; cgroup memory.events unchanged'
for name in oom-before oom-after; do
    grep -q 'SELF-TERMINATED' "$base/$name/application.log"
    grep -q '^exit_code=137$' "$base/$name/result.txt"
    awk -F, 'NR==2 {first=$6} NR>1 && $3!="EXIT" {last=$6} END {exit(last<=first)}' "$base/$name/monitor.csv"
done
before=$(sed -n 's/^observed_seconds=//p' "$base/oom-before/result.txt")
after=$(sed -n 's/^observed_seconds=//p' "$base/oom-after/result.txt")
(( after > before ))
echo "PASS: MemoryGuard shutdown; lifetime $before -> $after seconds"
grep -q 'WATCHDOG.*SIGTERM' "$base/cpu-before/application.log"
grep -q '^exit_code=143$' "$base/cpu-before/result.txt"
grep -q '^termination=experiment_timeout$' "$base/cpu-after/result.txt"
if grep -q 'WATCHDOG' "$base/cpu-after/application.log"; then exit 1; fi
echo 'PASS: CPU watchdog shutdown; reduced cap survives observation window'
grep -q 'BLOCKED' "$base/deadlock-before/application.log"
grep -q '^termination=experiment_timeout$' "$base/deadlock-before/result.txt"
if grep -q 'BLOCKED' "$base/deadlock-after/application.log"; then exit 1; fi
grep -q 'Task Completed' "$base/deadlock-after/application.log"
# Exclude harness cleanup using recorded start time and observation duration.
started=$(sed -n 's/^started_utc=//p' "$base/deadlock-before/result.txt")
duration=$(sed -n 's/^observed_seconds=//p' "$base/deadlock-before/result.txt")
cutoff=$(date -u -d "@$(($(date -d "$started" +%s) + duration))" +%FT%TZ)
awk -F, -v cutoff="$cutoff" '$1<cutoff && $3!="EXIT" && NR>1 {lines[++n]=$0} END {if(n<10)exit 1; split(lines[n-9],a,","); for(i=n-9;i<=n;i++){split(lines[i],b,","); if(b[4]>1 || b[6]!=a[6] || b[8]!=a[8])exit 1}}' "$base/deadlock-before/monitor.csv"
echo 'PASS: blocked process remains alive with stable final samples; single-thread tasks complete'
echo 'LIMITATION: application Current Load is not OS CPU usage; assess CPU spike separately in report'
