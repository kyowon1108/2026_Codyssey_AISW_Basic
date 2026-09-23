#!/usr/bin/env bash
# [요구사항 4] monitor.sh 배치 및 권한 설정
#   경로   : $AGENT_HOME/bin/monitor.sh
#   소유자 : agent-dev (작성자)
#   그룹   : agent-core
#   권한   : 750 (rwxr-x---)  -> agent-admin 은 agent-core 소속이라 실행 가능,
#                                agent-test 는 접근 불가
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"
require_root

SRC="${REPO_MOUNT}/scripts/monitor.sh"
DST="${AGENT_BIN_DIR}/monitor.sh"

section "monitor.sh 배치"
[[ -f "${SRC}" ]] || { echo "[ERROR] 원본을 찾을 수 없습니다: ${SRC}" >&2; exit 1; }

step "문법 검사 (bash -n)"
bash -n "${SRC}"
ok "문법 정상"

install -o "${DEV_USER}" -g "${GRP_CORE}" -m 750 "${SRC}" "${DST}"
step "${DST} (750, ${DEV_USER}:${GRP_CORE})"

section "검증 결과 - 권한"
ls -l "${DST}"

section "검증 결과 - 계정별 실행 권한"
check_exec() {
    local expect="$1" user="$2"
    if runuser -u "${user}" -- test -x "${DST}" 2>/dev/null; then
        result="allow"
    else
        result="deny"
    fi
    if [[ "${result}" == "${expect}" ]]; then
        printf '[OK]       %-11s 실행 권한 -> %s (기대값 일치)\n' "${user}" "${result}"
    else
        printf '[MISMATCH] %-11s 실행 권한 -> %s (기대값: %s)\n' "${user}" "${result}" "${expect}"
        return 1
    fi
}
check_exec allow "${DEV_USER}"    # 작성자
check_exec allow "${ADMIN_USER}"  # cron 실행자 (agent-core 소속)
check_exec deny  "${TEST_USER}"   # agent-core 미소속
