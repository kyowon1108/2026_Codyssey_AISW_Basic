#!/usr/bin/env bash
# 공통 설정값 및 헬퍼 (다른 setup 스크립트에서 source 한다)

# --- 네트워크 ---
SSH_PORT=20022
APP_PORT=15034

# --- 계정 / 그룹 ---
ADMIN_USER=agent-admin      # 운영/관리, cron 실행자
DEV_USER=agent-dev          # 개발/운영, monitor.sh 작성자
TEST_USER=agent-test        # QA/테스트
GRP_COMMON=agent-common     # admin + dev + test
GRP_CORE=agent-core         # admin + dev

# 실습 환경 전용 초기 비밀번호 (SSH 접속 검증용).
# 운영 환경이라면 키 기반 인증을 사용하고 비밀번호 인증은 비활성화하는 것이 맞다.
LAB_PASSWORD="${LAB_PASSWORD:-Codyssey!2026}"

# --- 디렉토리 / 환경 변수 ---
AGENT_HOME="/home/${ADMIN_USER}/agent-app"
AGENT_UPLOAD_DIR="${AGENT_HOME}/upload_files"
AGENT_KEY_DIR="${AGENT_HOME}/api_keys"
AGENT_KEY_FILE="${AGENT_KEY_DIR}/t_secret.key"   # 과제 명세상의 키 파일명
AGENT_KEY_APP_NAME="secret.key"                  # 제공 앱이 실제로 찾는 파일명
AGENT_KEY_STRING="agent_api_key_test"

# [주의] 제공 바이너리는 AGENT_KEY_PATH 를 "파일 경로"가 아니라
#        "키 디렉토리 경로"로 검증한다. (Boot [2/5] Key Path Mismatch)
#        자세한 내용은 docs/수행내역서.md 의 '명세와 실제 앱 동작 차이' 참고.
AGENT_KEY_PATH="${AGENT_KEY_DIR}"
AGENT_LOG_DIR="/var/log/agent-app"
AGENT_BIN_DIR="${AGENT_HOME}/bin"
AGENT_ENV_FILE="${AGENT_HOME}/agent.env"

# --- 리포지토리 마운트 경로 (컨테이너 기준) ---
REPO_MOUNT="${REPO_MOUNT:-/mnt/B1-1}"

require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        echo "[ERROR] 이 스크립트는 root 권한이 필요합니다. sudo 로 실행하세요." >&2
        exit 1
    fi
}

section() { printf '\n===== %s =====\n' "$*"; }
step()    { printf '[*] %s\n' "$*"; }
ok()      { printf '[OK] %s\n' "$*"; }
warn()    { printf '[WARNING] %s\n' "$*"; }
