#!/usr/bin/env bash
# 전체 서버 구성을 순서대로 수행한다 (root 로 실행).
#   sudo bash /mnt/B1-1/setup/run_all.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/00_env.sh"
require_root

STEPS=(
    "01_ssh.sh"
    "02_firewall.sh"
    "03_users_groups.sh"
    "04_dirs_acl.sh"
    "05_app_env.sh"
    "06_run_app.sh start"
    "07_monitor_deploy.sh"
    "08_cron.sh"
)

for s in "${STEPS[@]}"; do
    printf '\n\n############################################################\n'
    printf '# %s\n' "${s}"
    printf '############################################################\n'
    # shellcheck disable=SC2086
    bash "${HERE}/"${s}
done

printf '\n\n[OK] 전체 구성 완료\n'
