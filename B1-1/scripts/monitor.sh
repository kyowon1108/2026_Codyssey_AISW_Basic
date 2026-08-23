#!/bin/bash
#===============================================================================
# monitor.sh - Agent App 시스템 관제 자동화 스크립트
#
#   작성자   : agent-dev
#   실행 계정 : agent-admin (crontab, 매분)
#   배치 경로 : $AGENT_HOME/bin/monitor.sh   (750, agent-dev:agent-core)
#
#   1) Health Check  : 프로세스 / 포트 (실패 시 exit 1)
#   2) 상태 점검      : 방화벽 활성화 여부 (경고만, 종료하지 않음)
#   3) 자원 수집      : CPU / MEM / DISK 사용률
#   4) 임계값 경고    : CPU>20%, MEM>10%, DISK>80% (경고만)
#   5) 로그 기록      : /var/log/agent-app/monitor.log (10MB 초과 시 로테이션)
#
#   exit 0 : 정상 (경고 포함)
#   exit 1 : Health Check 실패
#   exit 2 : 로그 디렉토리 접근 불가 등 실행 환경 오류
#===============================================================================

# -e 는 사용하지 않는다. 각 점검의 실패를 직접 판정해서 종료 코드를 통제해야 한다.
set -uo pipefail

# cron 의 기본 PATH 는 /usr/bin:/bin 뿐이라 ufw(/usr/sbin) 등을 찾지 못한다.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

#--- 설정 ----------------------------------------------------------------------
# cron 은 로그인 셸이 아니므로 /etc/profile.d 를 읽지 않는다.
# 환경 파일을 명시적으로 읽고, 없으면 기본값으로 동작한다.
ENV_FILE="${AGENT_ENV_FILE:-/home/agent-admin/agent-app/agent.env}"
if [[ -r "${ENV_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
fi

AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"

APP_PATTERN="${APP_PATTERN:-agent-app-linux}"   # 제공 앱 바이너리명 (arm64/x86 공통)
LOG_FILE="${AGENT_LOG_DIR}/monitor.log"

# 임계값 (기본값은 과제 명세 그대로. 환경 변수로 덮어쓸 수 있게 해서
# 개별 경고 분기를 실제로 검증할 수 있도록 한다)
CPU_THRESHOLD="${CPU_THRESHOLD:-20}"      # %
MEM_THRESHOLD="${MEM_THRESHOLD:-10}"      # %
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"    # %

MAX_LOG_SIZE="${MAX_LOG_SIZE:-$((10 * 1024 * 1024))}"   # 10MB
MAX_LOG_FILES="${MAX_LOG_FILES:-10}"                    # monitor.log + .1 ~ .9 = 총 10개

WARN_COUNT=0

#--- 헬퍼 ----------------------------------------------------------------------
warn() { printf '[WARNING] %s\n' "$*"; WARN_COUNT=$((WARN_COUNT + 1)); }
die()  { printf '[ERROR] %s\n' "$1" >&2; exit "${2:-1}"; }

# 앱 PID 조회.
#
# pgrep -f 는 '명령줄 전체'를 훑기 때문에 두 가지 오탐이 발생한다.
#   1) 패턴 문자열을 인자로 가진 무관한 프로세스
#      (예: 이 스크립트를 실행한 셸, grep, 편집기 등)
#   2) 좀비(<defunct>) 프로세스 - 이미 죽었지만 부모가 회수하지 않은 상태
#
# 그래서 후보를 두 번 걸러낸다.
#   - comm (실행 파일 이름) 이 앱 이름과 일치할 것
#   - 프로세스 상태가 Z(좀비) 가 아닐 것
get_app_pid() {
    local pid comm state
    for pid in $(pgrep -f "${APP_PATTERN}" 2>/dev/null); do
        [[ "${pid}" == "$$" || "${pid}" == "${PPID}" ]] && continue

        # comm 은 15자로 잘리므로 접두사 비교를 한다.
        comm="$(ps -o comm= -p "${pid}" 2>/dev/null | tr -d ' ')"
        [[ -n "${comm}" && "${comm}" == "${APP_PATTERN}"* ]] || continue

        state="$(ps -o stat= -p "${pid}" 2>/dev/null | tr -d ' ')"
        [[ -z "${state}" || "${state}" == Z* ]] && continue

        echo "${pid}"
        return 0
    done
    return 1
}

# /proc/stat 의 누적값을 1초 간격으로 두 번 읽어 그 차이로 사용률을 계산한다.
# (top -bn1 의 첫 샘플은 '부팅 이후 평균'이라 현재 부하를 반영하지 못한다)
get_cpu_usage() {
    local t1 i1 t2 i2 dt di
    read -r t1 i1 < <(awk '/^cpu /{idle=$5+$6; total=0; for(f=2;f<=NF;f++) total+=$f; print total, idle; exit}' /proc/stat)
    sleep 1
    read -r t2 i2 < <(awk '/^cpu /{idle=$5+$6; total=0; for(f=2;f<=NF;f++) total+=$f; print total, idle; exit}' /proc/stat)

    dt=$(( t2 - t1 ))
    di=$(( i2 - i1 ))
    if (( dt <= 0 )); then
        echo "0.0"
        return
    fi
    awk -v dt="${dt}" -v di="${di}" 'BEGIN { printf "%.1f", (dt - di) * 100 / dt }'
}

# 실제 사용 중인 메모리 = MemTotal - MemAvailable
# (free 의 buff/cache 는 회수 가능하므로 MemAvailable 기준이 정확하다)
get_mem_usage() {
    awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2}
         END { if (t > 0) printf "%.1f", (t - a) * 100 / t; else printf "0.0" }' /proc/meminfo
}

# 루트 파티션 사용률(Used %)
get_disk_usage() {
    df -P / | awk 'NR==2 { gsub(/%/, "", $5); print $5 }'
}

# 로그 파일이 10MB 를 넘으면 .1 ~ .9 로 순차 이동시키고 가장 오래된 것을 버린다.
rotate_log() {
    [[ -f "${LOG_FILE}" ]] || return 0

    local size
    size="$(stat -c %s "${LOG_FILE}" 2>/dev/null || echo 0)"
    (( size < MAX_LOG_SIZE )) && return 0

    local keep=$(( MAX_LOG_FILES - 1 ))   # 현재 파일을 제외한 보관 개수
    rm -f "${LOG_FILE}.${keep}"
    local i
    for (( i = keep - 1; i >= 1; i-- )); do
        [[ -f "${LOG_FILE}.${i}" ]] && mv -f "${LOG_FILE}.${i}" "${LOG_FILE}.$(( i + 1 ))"
    done
    mv -f "${LOG_FILE}" "${LOG_FILE}.1"
    printf '[INFO] Log rotated (%s bytes >= %s bytes), keeping %s files\n' \
           "${size}" "${MAX_LOG_SIZE}" "${MAX_LOG_FILES}"
}

#--- 1. Health Check -----------------------------------------------------------
echo "====== SYSTEM MONITOR RESULT ======"
echo
echo "[HEALTH CHECK]"

APP_PID="$(get_app_pid)"
if [[ -z "${APP_PID}" ]]; then
    printf "Checking process '%s'... [FAIL]\n" "${APP_PATTERN}"
    die "Agent application process not found. (pattern: ${APP_PATTERN})" 1
fi
printf "Checking process '%s'... [OK] (PID: %s)\n" \
       "$(ps -o comm= -p "${APP_PID}" 2>/dev/null || echo "${APP_PATTERN}")" "${APP_PID}"

if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${AGENT_PORT}$"; then
    printf 'Checking port %s... [OK]\n' "${AGENT_PORT}"
else
    printf 'Checking port %s... [FAIL]\n' "${AGENT_PORT}"
    die "TCP ${AGENT_PORT} is not in LISTEN state." 1
fi

#--- 2. 상태 점검 (경고만) ------------------------------------------------------
echo
echo "[SECURITY CHECK]"
# ufw status 는 root 권한이 필요하다. 일반 계정(agent-admin)으로 실행되므로
#   1) sudo -n (NOPASSWD 로 'ufw status' 만 허용) -> 2) 설정 파일 직접 확인
# 순서로 폴백한다.
ufw_state="unknown"
if [[ "$(id -u)" -eq 0 ]] && command -v ufw >/dev/null 2>&1; then
    ufw_state="$(ufw status 2>/dev/null | awk '/^Status:/{print $2}')"
elif command -v sudo >/dev/null 2>&1 && sudo -n ufw status >/dev/null 2>&1; then
    ufw_state="$(sudo -n ufw status 2>/dev/null | awk '/^Status:/{print $2}')"
elif [[ -r /etc/ufw/ufw.conf ]]; then
    grep -qi '^ENABLED=yes' /etc/ufw/ufw.conf && ufw_state="active" || ufw_state="inactive"
fi

case "${ufw_state}" in
    active)   echo "Checking firewall (ufw)... [OK] (active)" ;;
    inactive) echo "Checking firewall (ufw)... [FAIL]"
              warn "Firewall is INACTIVE. Inbound traffic is not filtered." ;;
    *)        echo "Checking firewall (ufw)... [SKIP]"
              warn "Firewall status could not be determined." ;;
esac

#--- 3. 자원 수집 --------------------------------------------------------------
CPU_USAGE="$(get_cpu_usage)"
MEM_USAGE="$(get_mem_usage)"
DISK_USAGE="$(get_disk_usage)"

echo
echo "[RESOURCE MONITORING]"
printf 'CPU Usage : %s%%\n'  "${CPU_USAGE}"
printf 'MEM Usage : %s%%\n'  "${MEM_USAGE}"
printf 'DISK Used : %s%%\n'  "${DISK_USAGE}"

#--- 4. 임계값 경고 (경고만) ----------------------------------------------------
echo
awk -v v="${CPU_USAGE}"  -v t="${CPU_THRESHOLD}"  'BEGIN { exit !(v > t) }' \
    && warn "CPU threshold exceeded (${CPU_USAGE}% > ${CPU_THRESHOLD}%)"
awk -v v="${MEM_USAGE}"  -v t="${MEM_THRESHOLD}"  'BEGIN { exit !(v > t) }' \
    && warn "MEM threshold exceeded (${MEM_USAGE}% > ${MEM_THRESHOLD}%)"
awk -v v="${DISK_USAGE}" -v t="${DISK_THRESHOLD}" 'BEGIN { exit !(v > t) }' \
    && warn "DISK threshold exceeded (${DISK_USAGE}% > ${DISK_THRESHOLD}%)"
(( WARN_COUNT == 0 )) && echo "[INFO] All metrics are within thresholds."

#--- 5. 로그 기록 --------------------------------------------------------------
if [[ ! -d "${AGENT_LOG_DIR}" ]]; then
    die "Log directory does not exist: ${AGENT_LOG_DIR}" 2
fi
if [[ ! -w "${AGENT_LOG_DIR}" ]]; then
    die "Log directory is not writable by $(id -un): ${AGENT_LOG_DIR}" 2
fi

rotate_log

LOG_LINE="$(printf '[%s] PID:%s CPU:%s%% MEM:%s%% DISK_USED:%s%%' \
            "$(date '+%Y-%m-%d %H:%M:%S')" "${APP_PID}" \
            "${CPU_USAGE}" "${MEM_USAGE}" "${DISK_USAGE}")"

if ! echo "${LOG_LINE}" >> "${LOG_FILE}"; then
    die "Failed to append log: ${LOG_FILE}" 2
fi

echo
echo "[INFO] Log appended: ${LOG_FILE}"
echo "${LOG_LINE}"

exit 0
