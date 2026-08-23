#!/usr/bin/env bash
# SSH 보안 설정 실제 접속 검증 (호스트에서 실행)
#   1) 20022 포트로 일반 계정 로그인 성공
#   2) 기존 22 포트 접속 불가
#   3) root 원격 로그인 차단 (올바른 비밀번호를 줘도 거부되는지)
set -uo pipefail

CONTAINER="${CONTAINER:-agent-lab}"
PASS="${LAB_PASSWORD:-Codyssey!2026}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR"

dex()  { docker exec "${CONTAINER}" bash -lc "$1"; }
run()  { printf '\n$ %s\n' "$1"; dex "$1" 2>&1; printf '(exit code: %s)\n' "$?"; }
title(){ printf '\n================================================================\n%s\n================================================================\n' "$1"; }

title "[설정] 적용된 SSH 설정"
run "sshd -T | grep -iE '^(port|permitrootlogin|passwordauthentication) '"

title "[검증 1] 변경된 포트(20022)로 일반 계정 로그인"
run "sshpass -p '${PASS}' ssh ${SSH_OPTS} -p 20022 agent-admin@127.0.0.1 'echo 로그인 성공: \$(whoami)@\$(hostname); id'"

title "[검증 2] 기존 포트(22)로는 접속되지 않음"
run "sshpass -p '${PASS}' ssh ${SSH_OPTS} -p 22 agent-admin@127.0.0.1 'whoami'"

title "[검증 3] Root 원격 로그인 차단"
echo "  -> 비밀번호가 틀려서 거부되는 것이 아님을 보이기 위해 root 비밀번호를 임시로 설정한다"
run "echo 'root:${PASS}' | chpasswd && echo 'root 비밀번호 임시 설정 완료'"
echo "  -> 올바른 비밀번호를 주더라도 PermitRootLogin no 때문에 거부되어야 한다"
run "sshpass -p '${PASS}' ssh ${SSH_OPTS} -p 20022 root@127.0.0.1 'whoami'"
echo "  -> 검증 후 root 계정을 다시 잠근다"
run "passwd -l root >/dev/null && passwd -S root"

title "[참고] 호스트 -> 컨테이너 포트 도달 확인"
printf '\n$ nc -z -v 127.0.0.1 20022 (호스트에서 실행)\n'
nc -z -v 127.0.0.1 20022 2>&1
printf '(exit code: %s)\n' "$?"
printf '\n$ nc -z -v 127.0.0.1 15034 (호스트에서 실행)\n'
nc -z -v 127.0.0.1 15034 2>&1
printf '(exit code: %s)\n' "$?"
