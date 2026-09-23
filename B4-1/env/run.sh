#!/usr/bin/env bash
# B1-1 실습 컨테이너 빌드 및 기동 스크립트 (호스트에서 실행)
#
#   --init            : PID 1 이 종료된 자식을 회수(reap)하도록. 없으면 앱이
#                       죽어도 좀비 프로세스가 남아 헬스체크가 오탐한다.
#   --privileged      : UFW(iptables/netfilter) 조작에 필요
#   -p 20022:20022    : 변경한 SSH 포트를 호스트에서 접속 검증하기 위함
#   -p 15034:15034    : 앱(APP) 포트
#   -v .../B1-1 (ro)  : setup 스크립트와 제공 앱 바이너리를 컨테이너로 전달
set -euo pipefail

IMAGE_NAME="agent-lab:22.04"
CONTAINER_NAME="agent-lab"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
B1_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "[*] 이미지 빌드: ${IMAGE_NAME}"
docker build -t "${IMAGE_NAME}" "${SCRIPT_DIR}"

if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
    echo "[*] 기존 컨테이너 제거: ${CONTAINER_NAME}"
    docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

echo "[*] 컨테이너 기동: ${CONTAINER_NAME}"
docker run -d \
    --name "${CONTAINER_NAME}" \
    --hostname agent-lab \
    --init \
    --privileged \
    -p 20022:20022 \
    -p 15034:15034 \
    -v "${B1_DIR}:/mnt/B1-1:ro" \
    "${IMAGE_NAME}"

echo "[*] 완료. 접속: docker exec -it ${CONTAINER_NAME} bash"
docker ps --filter "name=${CONTAINER_NAME}" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
