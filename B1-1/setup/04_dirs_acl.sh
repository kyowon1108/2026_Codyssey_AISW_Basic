#!/usr/bin/env bash
# [요구사항 2-2] 디렉토리 구조 및 접근 권한(ACL) 설정
#
#   $AGENT_HOME            agent-admin:agent-common  750   <- 3계정 모두 "통과"만 가능
#     ├─ upload_files      agent-admin:agent-common 2770   <- 공유 영역: common R/W
#     ├─ api_keys          agent-admin:agent-core   2770   <- 보안 영역: core ONLY
#     └─ bin               agent-dev:agent-core      750   <- monitor.sh 배치 위치
#   /var/log/agent-app     agent-admin:agent-core   2770   <- 보안 영역: core ONLY
#
#   setgid(2___) : 하위 생성 파일이 디렉토리 그룹을 상속하게 한다.
#   default ACL  : 이후 생성되는 파일에도 동일 권한이 자동 적용되게 한다.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"
require_root

section "디렉토리 생성"
mkdir -p "${AGENT_HOME}" "${AGENT_UPLOAD_DIR}" "${AGENT_KEY_DIR}" "${AGENT_BIN_DIR}" "${AGENT_LOG_DIR}"
ok "생성 완료"

section "소유권 / 권한 설정"

# 앱 루트: 세 계정 모두 하위로 진입할 수 있어야 하므로 그룹을 agent-common 으로 둔다.
chown "${ADMIN_USER}:${GRP_COMMON}" "${AGENT_HOME}"
chmod 750 "${AGENT_HOME}"
step "${AGENT_HOME} -> ${ADMIN_USER}:${GRP_COMMON} 750"

# 공유 업로드 영역: agent-common 읽기/쓰기
chown "${ADMIN_USER}:${GRP_COMMON}" "${AGENT_UPLOAD_DIR}"
chmod 2770 "${AGENT_UPLOAD_DIR}"
step "${AGENT_UPLOAD_DIR} -> ${ADMIN_USER}:${GRP_COMMON} 2770"

# 보안 영역(키): agent-core 만 읽기/쓰기
chown "${ADMIN_USER}:${GRP_CORE}" "${AGENT_KEY_DIR}"
chmod 2770 "${AGENT_KEY_DIR}"
step "${AGENT_KEY_DIR} -> ${ADMIN_USER}:${GRP_CORE} 2770"

# 스크립트 영역: 작성자 agent-dev 소유, agent-core 실행 가능
chown "${DEV_USER}:${GRP_CORE}" "${AGENT_BIN_DIR}"
chmod 750 "${AGENT_BIN_DIR}"
step "${AGENT_BIN_DIR} -> ${DEV_USER}:${GRP_CORE} 750"

# 보안 영역(로그): agent-core 만 읽기/쓰기
chown "${ADMIN_USER}:${GRP_CORE}" "${AGENT_LOG_DIR}"
chmod 2770 "${AGENT_LOG_DIR}"
step "${AGENT_LOG_DIR} -> ${ADMIN_USER}:${GRP_CORE} 2770"

section "ACL 설정"
# 공유 영역
setfacl -m    "g:${GRP_COMMON}:rwx" "${AGENT_UPLOAD_DIR}"
setfacl -d -m "g:${GRP_COMMON}:rwx" "${AGENT_UPLOAD_DIR}"
setfacl -m    "o::---"              "${AGENT_UPLOAD_DIR}"
setfacl -d -m "o::---"              "${AGENT_UPLOAD_DIR}"
step "${AGENT_UPLOAD_DIR}: g:${GRP_COMMON}:rwx (+default)"

# 보안 영역 (agent-common 에는 어떤 권한도 부여하지 않는다)
for d in "${AGENT_KEY_DIR}" "${AGENT_LOG_DIR}"; do
    setfacl -m    "g:${GRP_CORE}:rwx" "${d}"
    setfacl -d -m "g:${GRP_CORE}:rwx" "${d}"
    setfacl -m    "o::---"            "${d}"
    setfacl -d -m "o::---"            "${d}"
    step "${d}: g:${GRP_CORE}:rwx (+default)"
done

section "검증 결과 - 소유권/권한"
ls -ld "${AGENT_HOME}" "${AGENT_UPLOAD_DIR}" "${AGENT_KEY_DIR}" "${AGENT_BIN_DIR}" "${AGENT_LOG_DIR}"

section "검증 결과 - getfacl"
for d in "${AGENT_UPLOAD_DIR}" "${AGENT_KEY_DIR}" "${AGENT_LOG_DIR}"; do
    getfacl -p "${d}" 2>/dev/null
    echo
done

section "검증 결과 - 실제 접근 테스트"
# expect: allow | deny
check_access() {
    local expect="$1" user="$2" desc="$3"; shift 3
    if runuser -u "${user}" -- bash -c "$*" >/dev/null 2>&1; then
        result="allow"
    else
        result="deny"
    fi
    if [[ "${result}" == "${expect}" ]]; then
        printf '[OK]      %-11s %-46s -> %s (기대값 일치)\n' "${user}" "${desc}" "${result}"
    else
        printf '[MISMATCH] %-11s %-46s -> %s (기대값: %s)\n' "${user}" "${desc}" "${result}" "${expect}"
        return 1
    fi
}

check_access allow "${TEST_USER}"  "upload_files 파일 생성"  "touch ${AGENT_UPLOAD_DIR}/test_by_${TEST_USER} && rm -f ${AGENT_UPLOAD_DIR}/test_by_${TEST_USER}"
check_access allow "${DEV_USER}"   "upload_files 파일 생성"  "touch ${AGENT_UPLOAD_DIR}/test_by_${DEV_USER} && rm -f ${AGENT_UPLOAD_DIR}/test_by_${DEV_USER}"
check_access deny  "${TEST_USER}"  "api_keys 접근"           "ls ${AGENT_KEY_DIR}"
check_access allow "${DEV_USER}"   "api_keys 접근"           "ls ${AGENT_KEY_DIR}"
check_access deny  "${TEST_USER}"  "/var/log/agent-app 접근" "ls ${AGENT_LOG_DIR}"
check_access allow "${ADMIN_USER}" "/var/log/agent-app 쓰기" "touch ${AGENT_LOG_DIR}/.write_test && rm -f ${AGENT_LOG_DIR}/.write_test"
