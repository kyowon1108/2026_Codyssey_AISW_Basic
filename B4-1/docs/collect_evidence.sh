#!/usr/bin/env bash
# 제출용 증거 자료 수집 스크립트 (호스트에서 실행)
#   docs/evidence/ 아래에 체크리스트 항목별 명령어 출력을 저장한다.
#   컨테이너 상태를 바꾸지 않는 조회 명령만 사용한다.
set -euo pipefail

CONTAINER="${CONTAINER:-agent-lab}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${HERE}/evidence"
mkdir -p "${OUT}"

dex() { docker exec "${CONTAINER}" bash -lc "$1"; }

# 실행한 명령어와 그 출력을 함께 남긴다 (재현 가능하도록)
run() {
    printf '\n$ %s\n' "$1"
    dex "$1" 2>&1 || printf '(exit code: %s)\n' "$?"
}

header() { printf '================================================================\n%s\n================================================================\n' "$1"; }

#--- 1. SSH -------------------------------------------------------------------
{
    header "[증거 1] SSH 포트 변경(20022) 및 Root 원격 접속 차단"
    run "grep -nE '^[[:space:]]*(Port|PermitRootLogin)' /etc/ssh/sshd_config"
    run "sshd -T | grep -iE '^(port|permitrootlogin) '"
    run "ss -tulnp | grep -i sshd"
} > "${OUT}/01_ssh.txt" 2>&1
echo "[OK] 01_ssh.txt"

#--- 2. 방화벽 ----------------------------------------------------------------
{
    header "[증거 2] UFW 활성화 및 20022/tcp, 15034/tcp 만 허용"
    run "ufw status verbose"
    run "ufw status numbered"
    run "cat /etc/sudoers.d/agent-monitor"
} > "${OUT}/02_firewall.txt" 2>&1
echo "[OK] 02_firewall.txt"

#--- 3. 계정 / 그룹 -----------------------------------------------------------
{
    header "[증거 3] 계정(agent-admin/dev/test) 및 그룹(agent-common/core) 생성"
    run "id agent-admin"
    run "id agent-dev"
    run "id agent-test"
    run "getent group agent-common agent-core"
    run "getent passwd agent-admin agent-dev agent-test"
} > "${OUT}/03_users_groups.txt" 2>&1
echo "[OK] 03_users_groups.txt"

#--- 4. 디렉토리 / 권한 / ACL --------------------------------------------------
{
    header "[증거 4] 디렉토리 구조 및 권한(ACL 포함)"
    run "ls -ld /home/agent-admin/agent-app /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /home/agent-admin/agent-app/bin /var/log/agent-app"
    run "ls -l /home/agent-admin/agent-app /home/agent-admin/agent-app/api_keys /home/agent-admin/agent-app/bin"
    run "getfacl -p /home/agent-admin/agent-app/upload_files"
    run "getfacl -p /home/agent-admin/agent-app/api_keys"
    run "getfacl -p /var/log/agent-app"

    printf '\n--- 실제 접근 테스트 (기대값: common=공유 허용 / core 외 보안영역 차단) ---\n'
    run "runuser -u agent-test -- touch /home/agent-admin/agent-app/upload_files/from_test && echo 'agent-test: upload_files 쓰기 성공' && runuser -u agent-test -- rm -f /home/agent-admin/agent-app/upload_files/from_test"
    run "runuser -u agent-test -- cat /home/agent-admin/agent-app/api_keys/t_secret.key"
    run "runuser -u agent-test -- ls /var/log/agent-app"
    run "runuser -u agent-dev -- cat /home/agent-admin/agent-app/api_keys/t_secret.key"
    run "runuser -u agent-test -- /home/agent-admin/agent-app/bin/monitor.sh"
} > "${OUT}/04_dirs_acl.txt" 2>&1
echo "[OK] 04_dirs_acl.txt"

#--- 5. 앱 실행 ---------------------------------------------------------------
{
    header "[증거 5] 앱 Boot Sequence 5단계 [OK] 및 Agent READY"
    run "sed -n '1,15p' /var/log/agent-app/agent-app.console.log"
    printf '\n--- 환경 변수 ---\n'
    run "runuser -l agent-admin -c 'env | grep ^AGENT_ | sort'"
    run "cat /home/agent-admin/agent-app/agent.env"
    printf '\n--- 실행 계정 / 리슨 상태 ---\n'
    run "ps -eo pid,user,args | grep '[a]gent-app-linux'"
    run "ss -tlnp | grep 15034"
} > "${OUT}/05_app_boot.txt" 2>&1
echo "[OK] 05_app_boot.txt"

#--- 6. monitor.sh 실행 -------------------------------------------------------
{
    header "[증거 6] monitor.sh 실행 결과 (프로세스/포트/리소스/경고)"
    run "ls -l /home/agent-admin/agent-app/bin/monitor.sh"
    printf '\n--- cron 실행 계정(agent-admin)으로 직접 실행 ---\n'
    run "runuser -l agent-admin -c /home/agent-admin/agent-app/bin/monitor.sh"
} > "${OUT}/06_monitor_run.txt" 2>&1
echo "[OK] 06_monitor_run.txt"

#--- 7. cron ------------------------------------------------------------------
{
    header "[증거 7-1] crontab 매분 실행 등록"
    run "crontab -u agent-admin -l"
    run "ps -eo pid,user,args | grep '[c]ron'"
    printf '\n'
    header "[증거 7-2] /var/log/agent-app/monitor.log 누적 기록 (최근 라인)"
    run "wc -l /var/log/agent-app/monitor.log"
    run "tail -15 /var/log/agent-app/monitor.log"
    run "ls -l /var/log/agent-app/"
} > "${OUT}/08_cron_and_log.txt" 2>&1
echo "[OK] 08_cron_and_log.txt"

echo
echo "증거 파일 위치: ${OUT}"
ls -l "${OUT}"
