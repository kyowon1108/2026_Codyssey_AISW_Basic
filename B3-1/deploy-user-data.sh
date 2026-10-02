#!/bin/bash
set -euo pipefail

dnf install -y nginx git
git clone --depth 1 https://github.com/kyowon1108/2026_Codyssey_AISW_Basic.git /tmp/codyssey-source
cp -a /tmp/codyssey-source/B1-1/. /usr/share/nginx/html/
printf 'OK\n' > /usr/share/nginx/html/health
systemctl enable --now nginx
curl --fail --silent --show-error http://localhost/health
