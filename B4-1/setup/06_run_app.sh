#!/usr/bin/env bash
# [요구사항 3] 앱 실행 보조 스크립트  (start | stop | status)
#
# 과제상 앱은 포그라운드 실행 후 Ctrl+C 로 종료하지만, cron 모니터링(매분)을
# 검증하려면 앱이 여러 분 동안 살아 있어야 한다. 그래서 동일한 실행을
# agent-admin 권한으로 백그라운드에 띄우는 용도로만 사용한다.
# (루트로 실행하지 않는다는 원칙은 그대로 지킨다: runuser 로 권한을 낮춘다)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"
require_root

ACTION="${1:-start}"
APP_BIN="$(ls "${AGENT_HOME}"/agent-app-linux-* 2>/dev/null | head -1 || true)"
APP_PATTERN='agent-app-linux'
CONSOLE_LOG="${AGENT_LOG_DIR}/agent-app.console.log"

# 좀비(<defunct>) 프로세스는 pgrep 에 잡히지만 실제로는 죽은 상태다.
# 프로세스 상태가 Z 인 것은 제외해야 헬스체크가 오탐하지 않는다.
app_pid() {
    local p st
    for p in $(pgrep -f "${APP_PATTERN}" 2>/dev/null); do
        st="$(ps -o stat= -p "${p}" 2>/dev/null | tr -d ' ')"
        [[ "${st}" == Z* ]] && continue
        echo "${p}"
        return 0
    done
    return 0
}

case "${ACTION}" in
  start)
    if [[ -z "${APP_BIN}" ]]; then
        echo "[ERROR] 앱 바이너리가 없습니다. 05_app_env.sh 를 먼저 실행하세요." >&2
        exit 1
    fi
    if [[ -n "$(app_pid)" ]]; then
        warn "이미 실행 중입니다 (PID: $(app_pid))"
        exit 0
    fi
    section "앱 백그라운드 기동 (실행 계정: ${ADMIN_USER})"
    : > "${CONSOLE_LOG}"
    chown "${ADMIN_USER}:${GRP_CORE}" "${CONSOLE_LOG}"
    runuser -l "${ADMIN_USER}" -c \
        "setsid nohup '${APP_BIN}' </dev/null >>'${CONSOLE_LOG}' 2>&1 &"

    # 부팅 시퀀스가 끝나고 포트가 열릴 때까지 최대 15초 대기
    for _ in $(seq 1 15); do
        ss -ltn 2>/dev/null | grep -q ":${APP_PORT}" && break
        sleep 1
    done

    section "부팅 시퀀스 출력"
    sed -n '1,20p' "${CONSOLE_LOG}"

    section "검증 결과"
    if ss -ltnp | grep -q ":${APP_PORT}"; then
        ok "TCP ${APP_PORT} LISTEN 확인"
        ss -ltnp | grep ":${APP_PORT}"
    else
        echo "[ERROR] ${APP_PORT} 포트가 열리지 않았습니다." >&2
        exit 1
    fi
    echo "실행 계정 / PID:"
    ps -o pid,user,args -p "$(app_pid)" | sed 's/^/  /'
    ;;

  stop)
    pid="$(app_pid)"
    if [[ -z "${pid}" ]]; then
        warn "실행 중인 앱이 없습니다."
        exit 0
    fi

    # 앱은 워커 자식 프로세스를 함께 띄운다. 부모 PID 에만 시그널을 보내면
    # 자식이 살아남아 포트를 계속 점유하므로, 프로세스 그룹 전체에 보낸다.
    # (setsid 로 띄웠기 때문에 앱이 자기 프로세스 그룹의 리더다)
    pgid="$(ps -o pgid= -p "${pid}" 2>/dev/null | tr -d ' ')"
    section "앱 종료 (PID: ${pid}, PGID: ${pgid:-N/A})"

    stopped=0
    # 포그라운드 Ctrl+C 와 동일한 SIGINT 부터 시도하고, 응답이 없으면 단계적으로 강화한다.
    for sig in INT TERM KILL; do
        if [[ -n "${pgid}" ]]; then
            kill -"${sig}" -- "-${pgid}" 2>/dev/null || kill -"${sig}" "${pid}" 2>/dev/null || true
        else
            kill -"${sig}" "${pid}" 2>/dev/null || true
        fi
        for _ in $(seq 1 5); do
            sleep 1
            if [[ -z "$(app_pid)" ]]; then
                ok "SIG${sig} 로 종료 완료 (PID: ${pid})"
                stopped=1
                break
            fi
        done
        (( stopped )) && break
        warn "SIG${sig} 로 종료되지 않아 다음 시그널을 시도합니다."
    done

    if (( ! stopped )); then
        echo "[ERROR] 앱을 종료하지 못했습니다 (PID: ${pid})" >&2
        exit 1
    fi
    ss -ltn | grep -q ":${APP_PORT}" && warn "포트 ${APP_PORT} 가 아직 열려 있습니다." || ok "포트 ${APP_PORT} 해제 확인"
    ;;

  status)
    pid="$(app_pid)"
    if [[ -n "${pid}" ]]; then
        ok "실행 중 (PID: ${pid})"
        ps -o pid,user,etime,args -p "${pid}"
        ss -ltnp | grep ":${APP_PORT}" || warn "포트 ${APP_PORT} 미개방"
    else
        warn "실행 중이 아닙니다."
    fi
    ;;

  *)
    echo "usage: $0 {start|stop|status}" >&2; exit 1 ;;
esac
