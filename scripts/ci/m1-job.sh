#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT/ci-artifacts}"
AGENT_E2E="${AGENT_E2E:-0}"
CODEX_BIN="${CODEX_BIN:-/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex}"
MIN_FREE_GB="${MIN_FREE_GB:-5}"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.npm-global/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
mkdir -p "$ARTIFACT_DIR/logs"

run_step() {
  local name="$1"
  shift

  printf '\n==> %s\n' "$name"
  if "$@" 2>&1 | tee "$ARTIFACT_DIR/logs/$name.log"; then
    printf 'PASS: %s\n' "$name"
  else
    printf 'FAIL: %s\n' "$name" >&2
    exit 1
  fi
}

printf 'commit=%s\n' "$(git -C "$ROOT" rev-parse HEAD)"
printf 'host=%s\n' "$(hostname)"
printf 'arch=%s\n' "$(uname -m)"

free_gb="$(df -Pk "$ROOT" | awk 'NR == 2 { print int($4 / 1024 / 1024) }')"
printf 'free_disk_gb=%s\n' "$free_gb"
if (( free_gb < MIN_FREE_GB )); then
  printf 'ERROR: at least %s GiB free is required, found %s GiB\n' "$MIN_FREE_GB" "$free_gb" >&2
  exit 1
fi

for command in git node npm jq curl; do
  command -v "$command" >/dev/null
  printf '%s=%s\n' "$command" "$("$command" --version 2>&1 | head -1)"
done

if [[ -f "$ROOT/package-lock.json" ]]; then
  run_step install npm ci
else
  run_step install npm install
fi

run_step lint npm run lint
run_step test npm test

if npm pkg get scripts.build | jq -e 'type == "string"' >/dev/null; then
  run_step build npm run build
fi

if npm pkg get scripts.e2e | jq -e 'type == "string"' >/dev/null; then
  run_step e2e npm run e2e
fi

if [[ "$AGENT_E2E" == "1" ]]; then
  if [[ ! -x "$CODEX_BIN" ]]; then
    printf 'ERROR: Codex CLI is missing at %s\n' "$CODEX_BIN" >&2
    exit 1
  fi

  run_step agent-e2e "$CODEX_BIN" exec \
    --ephemeral \
    --skip-git-repo-check \
    -s danger-full-access \
    -C "$ROOT" \
    --output-schema "$ROOT/.github/ci/agent-result.schema.json" \
    -o "$ARTIFACT_DIR/agent-result.json" \
    "Act as the CI acceptance agent for this trusted commit. Inspect the repository, run its documented end-to-end checks, and independently probe the resulting service or artifact. Do not edit tracked files. Return the structured acceptance result required by the schema; set status=pass only if every check passes."

  if ! jq -e '.status == "pass" and all(.checks[]; .result == "pass")' "$ARTIFACT_DIR/agent-result.json"; then
    printf 'FAIL: agent acceptance result is not pass\n' >&2
    exit 1
  fi

  if ! git -C "$ROOT" diff --exit-code HEAD --; then
    printf 'FAIL: agent changed tracked files\n' >&2
    exit 1
  fi
fi

jq -n \
  --arg status pass \
  --arg commit "$(git -C "$ROOT" rev-parse HEAD)" \
  --arg host "$(hostname)" \
  --arg arch "$(uname -m)" \
  --arg finished_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson agent_e2e "$([[ "$AGENT_E2E" == "1" ]] && printf true || printf false)" \
  '{status: $status, commit: $commit, host: $host, arch: $arch, agent_e2e: $agent_e2e, finished_at: $finished_at}' \
  > "$ARTIFACT_DIR/summary.json"

printf '\nCI PASS: %s\n' "$ARTIFACT_DIR/summary.json"

