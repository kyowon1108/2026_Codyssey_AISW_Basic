#!/usr/bin/env bash
# monitor.sh 예외 동작 검증 (호스트에서 실행)
#
#   [검증 1] 로그 10MB 초과   -> 로테이션 동작
#   [검증 2] 방화벽 비활성    -> [WARNING] 만 출력하고 계속 진행 (exit 0)
#   [검증 3] 앱 중지          -> Health Check 실패, exit 1
#   [검증 4] 좀비 프로세스    -> 죽은 프로세스를 살아있다고 오탐하지 않음
#
# 검증이 끝나면 원래 상태(앱 실행 + 방화벽 활성 + 기존 로그)로 복구한다.
set -uo pipefail

CONTAINER="${CONTAINER:-agent-lab}"
MON=/home/agent-admin/agent-app/bin/monitor.sh
LOG=/var/log/agent-app/monitor.log

dex()  { docker exec "${CONTAINER}" bash -lc "$1"; }
run()  { printf '\n$ %s\n' "$1"; dex "$1" 2>&1; printf '(exit code: %s)\n' "$?"; }
title(){ printf '\n================================================================\n%s\n================================================================\n' "$1"; }

# monitor.sh 는 cron 과 동일하게 agent-admin 계정으로 실행한다.
run_monitor() {
    printf '\n$ runuser -l agent-admin -c %s\n' "${MON}"
    docker exec "${CONTAINER}" bash -lc "runuser -l agent-admin -c ${MON} 2>&1"
    printf '(exit code: %s)\n' "$?"
}

title "[사전] 정상 상태 확인"
run "ps -eo pid,user,stat,args | grep '[a]gent-app-linux'"
run "ss -ltn | grep 15034"

#--- [검증 1] 로그 로테이션 -----------------------------------------------------
title "[검증 1] 로그 파일 10MB 초과 시 로테이션 (최대 10MB / 10개 파일)"
run "cp ${LOG} /tmp/monitor.log.backup && wc -l < /tmp/monitor.log.backup"
echo "  -> 10MB 를 초과한 상태를 인위적으로 만든다"
run "head -c 11534336 /dev/zero | tr '\\0' 'x' > ${LOG}; chown agent-admin:agent-core ${LOG}; ls -lh ${LOG}"
run_monitor
run "ls -l /var/log/agent-app/"
echo "  -> 검증 전 로그로 복구"
run "cp /tmp/monitor.log.backup ${LOG} && rm -f ${LOG}.1 /tmp/monitor.log.backup && chown agent-admin:agent-core ${LOG} && ls -l /var/log/agent-app/"

#--- [검증 2] 방화벽 비활성 -----------------------------------------------------
title "[검증 2] 방화벽 비활성 시 경고만 출력하고 계속 진행"
run "ufw --force disable && ufw status"
run_monitor
echo "  -> 방화벽 복구"
run "bash /mnt/B1-1/setup/02_firewall.sh >/dev/null 2>&1; ufw status | head -2"

#--- [검증 3] 앱 중지 -----------------------------------------------------------
title "[검증 3] 앱 프로세스 부재 시 Health Check 실패 (exit 1)"
run "bash /mnt/B1-1/setup/06_run_app.sh stop"
run "ps -eo pid,stat,args | grep '[a]gent-app-linux' || echo '(관련 프로세스 없음)'"
run_monitor

#--- [검증 4] 좀비 프로세스 오탐 방지 -------------------------------------------
title "[검증 4] 좀비(<defunct>) 프로세스를 살아있다고 오탐하지 않음"
echo "  -> 앱과 같은 이름의 프로세스를 만든 뒤 부모를 SIGSTOP 시켜 좀비로 남긴다"
dex "cp -f /bin/sleep /tmp/agent-app-linux-zombie" >/dev/null 2>&1
docker exec -d "${CONTAINER}" bash -c \
  'setsid bash -c "echo \$\$ > /tmp/zombie_parent.pid; /tmp/agent-app-linux-zombie 1 & kill -STOP \$\$"' >/dev/null 2>&1
sleep 3
run "ps -eo pid,stat,comm,args | grep '[a]gent-app-linux'"
echo "  -> pgrep 은 좀비를 '살아있는 프로세스'로 반환한다"
run "pgrep -af agent-app-linux | grep -v 'bash -lc'"
echo "  -> monitor.sh 는 상태 Z 를 걸러내고 실패로 판정해야 한다"
run_monitor
echo "  -> 좀비 정리"
run "p=\$(cat /tmp/zombie_parent.pid 2>/dev/null); [ -n \"\$p\" ] && { kill -CONT \$p 2>/dev/null; kill -9 \$p 2>/dev/null; }; sleep 1; rm -f /tmp/agent-app-linux-zombie /tmp/zombie_parent.pid; ps -eo pid,stat,args | grep '[a]gent-app-linux' || echo '(관련 프로세스 없음)'"

#--- 복구 ----------------------------------------------------------------------
title "[복구] 앱 재기동 및 정상 동작 확인"
run "bash /mnt/B1-1/setup/06_run_app.sh start 2>&1 | tail -6"
run_monitor
