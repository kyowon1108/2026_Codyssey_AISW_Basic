#!/usr/bin/env bash
#===============================================================================
# 제출용 화면 캡처 진행 스크립트 (호스트에서 실행)
#
#   ./docs/capture_scenes.sh          1번 컷부터 진행
#   ./docs/capture_scenes.sh 5        5번 컷부터 진행 (다시 찍을 때)
#   ./docs/capture_scenes.sh --list   컷 목록만 출력
#
# 한 컷씩 화면을 띄우고 멈춘다. 캡처한 뒤 Enter 를 누르면 다음 컷으로 넘어간다.
# 캡처 파일은 docs/evidence/img/ 에 안내된 파일명으로 저장하면
# 수행내역서의 이미지 자리에 그대로 들어간다.
#===============================================================================
set -uo pipefail

CONTAINER="${CONTAINER:-agent-lab}"
PASS="${LAB_PASSWORD:-Codyssey!2026}"
TOTAL=13
START="${1:-1}"

SHOTS=(
  "01_env.png|실습 환경 (컨테이너 기동 상태, 포트 매핑)|필수 아님"
  "02_ssh_config.png|SSH 설정: 포트 20022 / PermitRootLogin no / 리슨 상태|체크리스트 1"
  "03_ssh_login.png|SSH 접속 검증: 일반 계정 성공 / 22번 거부 / root 거부|체크리스트 1"
  "04_firewall.png|방화벽: UFW 활성화, 20022 와 15034 만 허용|체크리스트 2"
  "05_users.png|계정 3개 / 그룹 2개 생성 확인|체크리스트 3"
  "06_dirs_acl.png|디렉토리 구조, 권한, ACL|체크리스트 4"
  "07_access_test.png|계정별 접근 테스트 (공유 허용 / 보안 차단)|체크리스트 4"
  "08_app_boot.png|앱 Boot Sequence 5단계 [OK] 및 Agent READY|체크리스트 5"
  "09_app_listen.png|앱 실행 계정과 0.0.0.0:15034 LISTEN|체크리스트 5"
  "10_monitor_run.png|monitor.sh 권한(750, agent-dev:agent-core)과 실행 결과|체크리스트 6"
  "11_cron.png|crontab 매분 등록과 monitor.log 자동 누적|체크리스트 7, 8"
  "12_threshold_cpu.png|CPU 임계값 초과 경고 동작|추가"
  "13_health_fail.png|앱 중지 시 Health Check 실패와 exit 1|추가"
)

if [[ "${START}" == "--check" ]]; then
    IMG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/evidence/img"
    printf '\n캡처 파일 확인: %s\n\n' "${IMG_DIR}"
    missing=0
    n=1
    for s in "${SHOTS[@]}"; do
        IFS='|' read -r f d t <<< "${s}"
        base="${f%.png}"
        found="$(ls "${IMG_DIR}/${base}".* 2>/dev/null | head -1)"
        if [[ -n "${found}" ]]; then
            printf '  [있음] %2s. %s\n' "${n}" "$(basename "${found}")"
        else
            printf '  [없음] %2s. %-22s %s\n' "${n}" "${f}" "${d}"
            missing=$((missing + 1))
        fi
        n=$((n + 1))
    done
    if (( missing == 0 )); then
        printf '\n13컷 모두 준비되었습니다.\n\n'
    else
        printf '\n%s컷이 비어 있습니다. 다시 찍으려면: ./docs/capture_scenes.sh <컷번호>\n\n' "${missing}"
    fi
    exit 0
fi

if [[ "${START}" == "--list" ]]; then
    printf '\n제출용 캡처 목록 (총 %s컷)\n\n' "${TOTAL}"
    n=1
    for s in "${SHOTS[@]}"; do
        IFS='|' read -r f d t <<< "${s}"
        printf '  %2s. %-22s %-52s [%s]\n' "${n}" "${f}" "${d}" "${t}"
        n=$((n + 1))
    done
    printf '\n저장 위치: docs/evidence/img/\n\n'
    exit 0
fi

dex() { docker exec "${CONTAINER}" bash -lc "$1" 2>&1; }

header() {
    local n="$1"
    IFS='|' read -r f d t <<< "${SHOTS[$((n - 1))]}"
    clear
    printf '════════════════════════════════════════════════════════════════════\n'
    printf ' [컷 %s/%s]  %s\n' "${n}" "${TOTAL}" "${f}"
    printf ' %s\n' "${d}"
    printf '════════════════════════════════════════════════════════════════════\n\n'
}

pause() {
    local n="$1"
    IFS='|' read -r f d t <<< "${SHOTS[$((n - 1))]}"
    printf '\n────────────────────────────────────────────────────────────────────\n'
    printf ' 지금 화면을 캡처하세요  →  저장 파일명: %s\n' "${f}"
    printf '────────────────────────────────────────────────────────────────────\n'
    read -rp " Enter = 다음 컷 / q = 종료 : " ans
    [[ "${ans}" == "q" ]] && { printf '\n중단했습니다. 이어서 하려면: ./docs/capture_scenes.sh %s\n\n' "$((n + 1))"; exit 0; }
}

run() { printf '$ %s\n' "$1"; dex "$1"; printf '\n'; }

#--- 컷 1 ----------------------------------------------------------------------
if (( START <= 1 )); then
    header 1
    printf '$ docker ps --filter name=%s\n' "${CONTAINER}"
    docker ps --filter "name=${CONTAINER}" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    printf '\n'
    run "cat /etc/os-release | grep PRETTY_NAME; uname -m"
    pause 1
fi

#--- 컷 2 ----------------------------------------------------------------------
if (( START <= 2 )); then
    header 2
    run "grep -nE '^[[:space:]]*(Port|PermitRootLogin)' /etc/ssh/sshd_config"
    run "sshd -T | grep -iE '^(port|permitrootlogin) '"
    run "ss -tulnp | grep -i sshd"
    pause 2
fi

#--- 컷 3 ----------------------------------------------------------------------
if (( START <= 3 )); then
    header 3
    O="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR"
    printf '[1] 일반 계정으로 20022 포트 접속\n'
    run "sshpass -p '${PASS}' ssh ${O} -p 20022 agent-admin@127.0.0.1 'echo 접속 성공: \$(whoami)@\$(hostname)'"
    printf '[2] 기존 22 포트 접속 시도\n'
    run "sshpass -p '${PASS}' ssh ${O} -p 22 agent-admin@127.0.0.1 'whoami'"
    printf '[3] root 원격 접속 시도 (비밀번호는 정확히 입력)\n'
    dex "echo 'root:${PASS}' | chpasswd" >/dev/null
    run "sshpass -p '${PASS}' ssh ${O} -p 20022 root@127.0.0.1 'whoami'"
    dex "passwd -l root" >/dev/null
    printf '  → 비밀번호가 맞아도 거부된다. PermitRootLogin no 가 동작한다는 뜻.\n'
    pause 3
fi

#--- 컷 4 ----------------------------------------------------------------------
if (( START <= 4 )); then
    header 4
    run "ufw status verbose"
    pause 4
fi

#--- 컷 5 ----------------------------------------------------------------------
if (( START <= 5 )); then
    header 5
    run "id agent-admin; id agent-dev; id agent-test"
    run "getent group agent-common agent-core"
    printf '  → agent-test 는 agent-core 에 없다 (최소 권한).\n'
    pause 5
fi

#--- 컷 6 ----------------------------------------------------------------------
if (( START <= 6 )); then
    header 6
    run "ls -ld /home/agent-admin/agent-app /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /home/agent-admin/agent-app/bin /var/log/agent-app"
    run "getfacl -p /home/agent-admin/agent-app/api_keys"
    pause 6
fi

#--- 컷 7 ----------------------------------------------------------------------
if (( START <= 7 )); then
    header 7
    printf '[공유 영역] agent-test 가 upload_files 에 파일 생성\n'
    run "runuser -u agent-test -- touch /home/agent-admin/agent-app/upload_files/ok && echo '성공' && rm -f /home/agent-admin/agent-app/upload_files/ok"
    printf '[보안 영역] agent-test 가 api_keys 접근\n'
    run "runuser -u agent-test -- cat /home/agent-admin/agent-app/api_keys/t_secret.key"
    printf '[보안 영역] agent-test 가 로그 디렉토리 접근\n'
    run "runuser -u agent-test -- ls /var/log/agent-app"
    printf '[보안 영역] agent-dev 는 접근 가능\n'
    run "runuser -u agent-dev -- cat /home/agent-admin/agent-app/api_keys/t_secret.key"
    printf '[스크립트] agent-test 가 monitor.sh 실행\n'
    run "runuser -u agent-test -- /home/agent-admin/agent-app/bin/monitor.sh"
    pause 7
fi

#--- 컷 8 ----------------------------------------------------------------------
if (( START <= 8 )); then
    header 8
    run "sed -n '1,14p' /var/log/agent-app/agent-app.console.log"
    pause 8
fi

#--- 컷 9 ----------------------------------------------------------------------
if (( START <= 9 )); then
    header 9
    run "runuser -l agent-admin -c 'env | grep ^AGENT_ | sort'"
    run "ps -eo pid,user,args | grep '[a]gent-app-linux' | head -2"
    run "ss -tlnp | grep 15034"
    pause 9
fi

#--- 컷 10 ---------------------------------------------------------------------
if (( START <= 10 )); then
    header 10
    run "ls -l /home/agent-admin/agent-app/bin/monitor.sh"
    printf 'cron 실행 계정(agent-admin)으로 직접 실행\n'
    run "runuser -l agent-admin -c /home/agent-admin/agent-app/bin/monitor.sh"
    pause 10
fi

#--- 컷 11 ---------------------------------------------------------------------
if (( START <= 11 )); then
    header 11
    run "crontab -u agent-admin -l"
    run "date '+현재 시각: %F %T'; tail -8 /var/log/agent-app/monitor.log"
    printf '  → 1분 뒤 같은 명령을 다시 실행하면 줄이 늘어난다.\n'
    printf '  → cron 에러 로그 크기: %s bytes (0 이면 실패 없음)\n' "$(dex 'stat -c %s /var/log/agent-app/monitor.cron.log')"
    pause 11
fi

#--- 컷 12 ---------------------------------------------------------------------
if (( START <= 12 )); then
    header 12
    printf '  CPU 부하를 준 뒤 monitor.sh 를 실행한다 (약 8초 소요)\n\n'
    docker exec -d "${CONTAINER}" bash -c 'for i in $(seq 1 12); do (yes > /dev/null &); done' >/dev/null 2>&1
    sleep 4
    run "runuser -l agent-admin -c /home/agent-admin/agent-app/bin/monitor.sh"
    dex "pkill -x yes" >/dev/null
    pause 12
fi

#--- 컷 13 ---------------------------------------------------------------------
if (( START <= 13 )); then
    header 13
    printf '  앱을 중지한 뒤 monitor.sh 를 실행한다 (약 10초 소요)\n\n'
    dex "bash /mnt/B1-1/setup/06_run_app.sh stop" >/dev/null
    run "ps -eo pid,args | grep '[a]gent-app-linux' || echo '(앱 프로세스 없음)'"
    printf '$ monitor.sh 실행 후 종료 코드 확인\n'
    docker exec "${CONTAINER}" bash -lc 'runuser -l agent-admin -c /home/agent-admin/agent-app/bin/monitor.sh 2>&1; echo "exit code = $?"'
    pause 13

    clear
    printf '\n앱을 다시 기동합니다...\n\n'
    dex "bash /mnt/B1-1/setup/06_run_app.sh start" | tail -6
fi

printf '\n'
printf '════════════════════════════════════════════════════════════════════\n'
printf ' 캡처 완료. 파일을 docs/evidence/img/ 에 저장하세요.\n'
printf ' 파일명은 목록과 동일하게: ./docs/capture_scenes.sh --list\n'
printf '════════════════════════════════════════════════════════════════════\n\n'
