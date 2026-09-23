#!/usr/bin/env bash
# [요구사항 1-1] SSH 기본 보안 설정
#   - 접속 포트를 22 -> 20022 로 변경
#   - Root 원격 로그인 차단 (PermitRootLogin no)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"
require_root

SSHD_CONFIG=/etc/ssh/sshd_config

section "SSH 설정 변경"

# 원본 백업 (최초 1회만)
if [[ ! -f "${SSHD_CONFIG}.orig" ]]; then
    cp -p "${SSHD_CONFIG}" "${SSHD_CONFIG}.orig"
    step "원본 백업 생성: ${SSHD_CONFIG}.orig"
fi

# 주석(#Port 22) / 기존 설정 라인을 모두 대상으로 치환하고, 없으면 추가한다.
set_directive() {
    local key="$1" value="$2"
    if grep -qE "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]+" "${SSHD_CONFIG}"; then
        sed -i -E "s|^[[:space:]]*#?[[:space:]]*${key}[[:space:]]+.*|${key} ${value}|" "${SSHD_CONFIG}"
    else
        printf '\n%s %s\n' "${key}" "${value}" >> "${SSHD_CONFIG}"
    fi
    step "${key} ${value}"
}

set_directive "Port" "${SSH_PORT}"
set_directive "PermitRootLogin" "no"

# sshd_config.d 드롭인이 위 설정을 덮어쓰지 않는지 확인
shopt -s nullglob
dropins=(/etc/ssh/sshd_config.d/*.conf)
shopt -u nullglob
if (( ${#dropins[@]} > 0 )); then
    if grep -qiE '^[[:space:]]*(Port|PermitRootLogin)' "${dropins[@]}"; then
        warn "sshd_config.d 드롭인이 Port/PermitRootLogin 을 재정의하고 있습니다: ${dropins[*]}"
    fi
fi

# 문법 검증 후 적용 (검증 실패 시 재시작하지 않는다)
step "sshd 설정 문법 검증"
sshd -t
ok "문법 정상"

step "sshd 재시작"
service ssh restart >/dev/null
sleep 1

section "검증 결과"
echo "--- sshd_config (Port / PermitRootLogin) ---"
grep -nE '^[[:space:]]*(Port|PermitRootLogin)' "${SSHD_CONFIG}"
echo
echo "--- sshd 리슨 상태 (ss -tulnp) ---"
ss -tulnp | grep -i sshd || { echo "[ERROR] sshd 가 리슨하지 않습니다." >&2; exit 1; }
echo
ss -tulnp | grep -q ":${SSH_PORT}" && ok "TCP ${SSH_PORT} 리슨 확인"
ss -tulnp | grep -q ":22 " && warn "22 번 포트가 아직 열려 있습니다." || ok "22 번 포트 리슨 없음"
