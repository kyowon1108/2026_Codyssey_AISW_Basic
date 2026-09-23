#!/usr/bin/env bash
# [요구사항 2-1] 역할 기반 계정 / 그룹 생성
#   계정: agent-admin(운영, cron 실행자) / agent-dev(개발) / agent-test(QA)
#   그룹: agent-common = admin+dev+test   (공유 영역 접근)
#         agent-core   = admin+dev        (보안 영역 접근)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"
require_root

section "그룹 생성"
for g in "${GRP_COMMON}" "${GRP_CORE}"; do
    if getent group "${g}" >/dev/null; then
        step "그룹 이미 존재: ${g}"
    else
        groupadd "${g}"
        ok "그룹 생성: ${g}"
    fi
done

section "계정 생성"
for u in "${ADMIN_USER}" "${DEV_USER}" "${TEST_USER}"; do
    if id -u "${u}" >/dev/null 2>&1; then
        step "계정 이미 존재: ${u}"
    else
        useradd -m -s /bin/bash "${u}"
        ok "계정 생성: ${u}"
    fi
    # 실습 환경 SSH 접속 검증용 비밀번호
    echo "${u}:${LAB_PASSWORD}" | chpasswd
done

section "그룹 멤버십 부여"
# agent-common: 3명 전원 / agent-core: admin, dev 만
usermod -aG "${GRP_COMMON}" "${ADMIN_USER}"
usermod -aG "${GRP_COMMON}" "${DEV_USER}"
usermod -aG "${GRP_COMMON}" "${TEST_USER}"
usermod -aG "${GRP_CORE}"   "${ADMIN_USER}"
usermod -aG "${GRP_CORE}"   "${DEV_USER}"
ok "멤버십 설정 완료"

# agent-dev 가 $AGENT_HOME/bin/monitor.sh 까지 도달하려면
# agent-admin 홈 디렉토리를 통과(x)할 수 있어야 한다.
step "홈 디렉토리 통과 권한 확인: /home/${ADMIN_USER} -> 755"
chmod 755 "/home/${ADMIN_USER}"

section "검증 결과"
echo "--- id ---"
for u in "${ADMIN_USER}" "${DEV_USER}" "${TEST_USER}"; do id "${u}"; done
echo
echo "--- getent group ---"
getent group "${GRP_COMMON}"
getent group "${GRP_CORE}"
echo
# agent-test 가 agent-core 에 포함되면 최소 권한 원칙 위반
if id -nG "${TEST_USER}" | tr ' ' '\n' | grep -qx "${GRP_CORE}"; then
    warn "${TEST_USER} 가 ${GRP_CORE} 에 포함되어 있습니다 (최소 권한 위반)."
else
    ok "${TEST_USER} 는 ${GRP_CORE} 에 포함되지 않음 (최소 권한 준수)"
fi
