#!/usr/bin/env bash
# [요구사항 3] 애플리케이션 실행 환경 구성
#   - 환경 변수 5종 정의 (로그인 셸용 + 스크립트/cron 용)
#   - API 키 파일 생성
#   - 제공 앱 바이너리 배치
#
# 환경 변수를 두 곳에 두는 이유:
#   /etc/profile.d/agent-env.sh -> 로그인 셸에서만 읽힌다. cron 은 읽지 않는다.
#   $AGENT_HOME/agent.env       -> monitor.sh 및 cron 이 명시적으로 source 한다.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"
require_root

section "환경 변수 정의"

# 1) 로그인 셸용
cat > /etc/profile.d/agent-env.sh <<EOF
# Agent App 실행 환경 변수 (로그인 셸)
export AGENT_HOME="${AGENT_HOME}"
export AGENT_PORT="${APP_PORT}"
export AGENT_UPLOAD_DIR="${AGENT_UPLOAD_DIR}"
export AGENT_KEY_PATH="${AGENT_KEY_PATH}"
export AGENT_LOG_DIR="${AGENT_LOG_DIR}"
EOF
chmod 644 /etc/profile.d/agent-env.sh
step "/etc/profile.d/agent-env.sh 작성"

# 2) 스크립트 / cron 용 (export 없는 KEY=VALUE 형태)
cat > "${AGENT_ENV_FILE}" <<EOF
# Agent App 실행 환경 변수 (스크립트/cron 용)
# cron 은 로그인 셸이 아니므로 /etc/profile.d 를 읽지 않는다.
AGENT_HOME=${AGENT_HOME}
AGENT_PORT=${APP_PORT}
AGENT_UPLOAD_DIR=${AGENT_UPLOAD_DIR}
AGENT_KEY_PATH=${AGENT_KEY_PATH}
AGENT_LOG_DIR=${AGENT_LOG_DIR}
EOF
chown "${ADMIN_USER}:${GRP_COMMON}" "${AGENT_ENV_FILE}"
chmod 644 "${AGENT_ENV_FILE}"
step "${AGENT_ENV_FILE} 작성"

section "API 키 파일 생성"
# 과제 명세 파일명(t_secret.key) 으로 실제 키를 만든다.
printf '%s\n' "${AGENT_KEY_STRING}" > "${AGENT_KEY_FILE}"
chown "${ADMIN_USER}:${GRP_CORE}" "${AGENT_KEY_FILE}"
chmod 640 "${AGENT_KEY_FILE}"
step "${AGENT_KEY_FILE} (640, ${ADMIN_USER}:${GRP_CORE})"

# 제공 바이너리는 같은 디렉토리에서 'secret.key' 를 찾는다.
# 키를 이중으로 두면 관리 지점이 둘로 갈라지므로 심볼릭 링크로 연결한다.
ln -sfn "$(basename "${AGENT_KEY_FILE}")" "${AGENT_KEY_DIR}/${AGENT_KEY_APP_NAME}"
chown -h "${ADMIN_USER}:${GRP_CORE}" "${AGENT_KEY_DIR}/${AGENT_KEY_APP_NAME}"
step "${AGENT_KEY_DIR}/${AGENT_KEY_APP_NAME} -> $(basename "${AGENT_KEY_FILE}") (앱 호환용 심볼릭 링크)"

section "앱 바이너리 배치"
case "$(uname -m)" in
    aarch64|arm64) APP_SRC="${REPO_MOUNT}/agent-app/agent-app-linux-arm64" ;;
    x86_64|amd64)  APP_SRC="${REPO_MOUNT}/agent-app/agent-app-linux-x86"   ;;
    *) echo "[ERROR] 지원하지 않는 아키텍처: $(uname -m)" >&2; exit 1 ;;
esac
[[ -f "${APP_SRC}" ]] || { echo "[ERROR] 앱 바이너리를 찾을 수 없습니다: ${APP_SRC}" >&2; exit 1; }

APP_BIN="${AGENT_HOME}/$(basename "${APP_SRC}")"
install -o "${ADMIN_USER}" -g "${GRP_CORE}" -m 750 "${APP_SRC}" "${APP_BIN}"
step "$(uname -m) 감지 -> ${APP_BIN} (750, ${ADMIN_USER}:${GRP_CORE})"

section "검증 결과"
echo "--- 환경 변수 (agent-admin 로그인 셸) ---"
runuser -l "${ADMIN_USER}" -c 'env | grep ^AGENT_ | sort'
echo
echo "--- 키 파일 ---"
ls -l "${AGENT_KEY_DIR}"
echo "내용: $(cat "${AGENT_KEY_FILE}")"
[[ "$(cat "${AGENT_KEY_FILE}")" == "${AGENT_KEY_STRING}" ]] && ok "키 문자열 일치"
[[ "$(cat "${AGENT_KEY_DIR}/${AGENT_KEY_APP_NAME}")" == "${AGENT_KEY_STRING}" ]] && ok "앱 참조 경로(${AGENT_KEY_APP_NAME})에서도 동일 키 확인"
echo
echo "--- 앱 바이너리 ---"
ls -l "${APP_BIN}"
echo
echo "--- 디렉토리 트리 ---"
ls -lR "${AGENT_HOME}" | head -30
