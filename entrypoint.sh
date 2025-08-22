#!/usr/bin/env bash
set -euo pipefail

# control socket용 그룹/디렉토리
if ! getent group ziti >/dev/null 2>&1; then
  groupadd --system ziti || true
fi
mkdir -p /run/ziti && chgrp ziti /run/ziti || true && chmod 770 /run/ziti || true

IDENTITY_SRC="${IDENTITY_FILE:-/etc/ziti/web-host.json}"
IDENTITY_DST="/run/ziti/web-host.json"

if [[ ! -f "$IDENTITY_SRC" ]]; then
  echo "ERROR: identity file not found: $IDENTITY_SRC" >&2
  exit 1
fi

# 읽기전용 바인드 문제 방지: 내부 경로로 사본 떠서 사용
cp -f "$IDENTITY_SRC" "$IDENTITY_DST"

exec /usr/local/bin/ziti-edge-tunnel run-host -i "$IDENTITY_DST"
