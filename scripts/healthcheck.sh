#!/usr/bin/env bash
set -euo pipefail

if curl --fail --silent --show-error --max-time 5 http://127.0.0.1:8080/health >/dev/null; then
    exit 0
fi

logger -t infrapulse-health "HTTP health check failed; requesting service restart"
systemctl restart infrapulse.service
exit 1
