#!/usr/bin/env bash
# [요구사항 5] cron 자동 실행 등록
#   agent-admin 계정의 crontab 에 monitor.sh 를 매분 실행하도록 등록한다.
#
#   cron 은 로그인 셸이 아니라 환경 변수가 거의 없다.
#   -> monitor.sh 가 $AGENT_HOME/agent.env 를 직접 source 하고 PATH 를 재설정한다.
#   표준출력은 버리고 표준에러만 별도 파일에 남겨 실패를 추적한다.
#   (monitor.log 에는 규정된 포맷의 한 줄만 남아야 하므로 섞지 않는다)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"
require_root

CRON_ERR_LOG="${AGENT_LOG_DIR}/monitor.cron.log"
MONITOR="${AGENT_BIN_DIR}/monitor.sh"

section "cron 데몬 기동"
if pgrep -x cron >/dev/null; then
    step "cron 이미 실행 중"
else
    service cron start >/dev/null
    sleep 1
    pgrep -x cron >/dev/null && ok "cron 기동 완료" || { echo "[ERROR] cron 기동 실패" >&2; exit 1; }
fi

section "crontab 등록 (${ADMIN_USER}, 매분)"
: > "${CRON_ERR_LOG}"
chown "${ADMIN_USER}:${GRP_CORE}" "${CRON_ERR_LOG}"
chmod 660 "${CRON_ERR_LOG}"

crontab -u "${ADMIN_USER}" - <<EOF
# Agent App 시스템 관제 - 매분 실행
MAILTO=""
* * * * * ${MONITOR} >/dev/null 2>>${CRON_ERR_LOG}
EOF
ok "등록 완료"

section "검증 결과 - crontab -l"
crontab -u "${ADMIN_USER}" -l

section "검증 결과 - cron 프로세스"
ps -eo pid,user,args | grep -E '[c]ron' || true
