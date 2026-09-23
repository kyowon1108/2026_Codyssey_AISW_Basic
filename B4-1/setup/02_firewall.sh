#!/usr/bin/env bash
# [요구사항 1-2] 방화벽(UFW) 설정
#   - 인바운드 기본 차단, 아웃바운드 허용
#   - TCP 20022(SSH), TCP 15034(APP) 만 허용
# 주의: 정책(default deny) -> 허용 규칙 -> enable 순서를 지켜야
#       원격 접속이 끊기지 않는다.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"
require_root

section "UFW 방화벽 설정"

# 이전 실행 흔적을 지우고 항상 동일한 상태에서 시작 (멱등성 확보)
step "기존 규칙 초기화"
ufw --force reset >/dev/null

step "기본 정책: incoming deny / outgoing allow"
ufw default deny incoming  >/dev/null
ufw default allow outgoing >/dev/null

step "허용 규칙 추가: ${SSH_PORT}/tcp (SSH), ${APP_PORT}/tcp (APP)"
ufw allow "${SSH_PORT}/tcp" comment 'SSH (changed port)' >/dev/null
ufw allow "${APP_PORT}/tcp" comment 'Agent APP'          >/dev/null

step "방화벽 활성화"
ufw --force enable >/dev/null

section "monitor.sh 용 최소 권한 sudo 규칙"
# 'ufw status' 는 root 권한을 요구한다. monitor.sh 는 일반 계정(agent-admin)으로
# 실행되므로, 상태 조회 명령 하나만 NOPASSWD 로 허용한다.
# (방화벽을 변경하는 권한은 주지 않는다 = 최소 권한 원칙)
cat > /etc/sudoers.d/agent-monitor <<EOF
# monitor.sh 및 운영 점검용 (조회 전용, 상태 변경 불가)
%${GRP_CORE} ALL=(root) NOPASSWD: /usr/sbin/ufw status, /usr/sbin/ufw status verbose, /usr/sbin/ufw status numbered
EOF
chmod 440 /etc/sudoers.d/agent-monitor
visudo -cf /etc/sudoers.d/agent-monitor
step "/etc/sudoers.d/agent-monitor 작성 (%${GRP_CORE} -> ufw status 조회만 허용)"

section "검증 결과"
ufw status verbose

echo
if ufw status | grep -qE '^22/tcp'; then
    warn "기본 SSH 포트(22/tcp)가 허용되어 있습니다."
else
    ok "22/tcp 허용 규칙 없음"
fi
ufw status | grep -qE "^${SSH_PORT}/tcp" && ok "${SSH_PORT}/tcp 허용 확인"
ufw status | grep -qE "^${APP_PORT}/tcp" && ok "${APP_PORT}/tcp 허용 확인"

# 허용 목록이 정확히 2개(v4)인지 확인
allowed=$(ufw status | awk '/ALLOW/ && !/\(v6\)/ {print $1}' | sort -u | tr '\n' ' ')
echo "허용된 인바운드 포트: ${allowed}"
