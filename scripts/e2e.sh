#!/bin/bash
set -euo pipefail

PORT="${PORT:-3100}"
LOG_FILE="${LOG_FILE:-e2e-server.log}"
RESPONSE_FILE="${RESPONSE_FILE:-e2e-response.json}"

PORT="$PORT" node src/server.js >"$LOG_FILE" 2>&1 &
server_pid=$!
cleanup() {
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT

for _ in {1..30}; do
  if curl --fail --silent "http://127.0.0.1:${PORT}/health" >"$RESPONSE_FILE"; then
    break
  fi
  sleep 0.2
done

curl --fail --silent --show-error "http://127.0.0.1:${PORT}/health" >"$RESPONSE_FILE"
jq -e '.status == "ok" and .service == "m1-ci-demo"' "$RESPONSE_FILE"
printf 'E2E PASS: '
cat "$RESPONSE_FILE"
