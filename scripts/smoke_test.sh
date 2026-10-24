#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log_file="$(mktemp)"
python3 "${repo_root}/app/server.py" >"${log_file}" 2>&1 &
server_pid=$!
cleanup() {
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
    rm -f "${log_file}"
}
trap cleanup EXIT

for _ in {1..30}; do
    if curl --fail --silent --max-time 2 http://127.0.0.1:8080/health >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

actual="$(curl --fail --silent --show-error --max-time 2 http://127.0.0.1:8080/health)"
if [[ "${actual}" != '{"status":"ok"}' ]]; then
    echo "Unexpected health response: ${actual}" >&2
    exit 1
fi
printf 'Smoke test passed: %s\n' "${actual}"
