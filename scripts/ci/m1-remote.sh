#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/ci/m1-remote.sh [options]

Options:
  --repo-url URL         Git URL to test (default: current origin)
  --ref REF              Branch, tag, or commit (default: HEAD)
  --agent-e2e            Run Codex acceptance after deterministic checks
  --out-dir DIR          Local artifact directory
  --host USER@HOST       SSH target (default: M1_HOST)
  --identity FILE        SSH private key (default: M1_IDENTITY)
  --known-hosts FILE     SSH known-hosts file (default: M1_KNOWN_HOSTS)
  -h, --help             Show this help
EOF
}

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
REPO_URL="${REPO_URL:-$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)}"
REF="${REF:-HEAD}"
AGENT_E2E=0
OUT_DIR=""
M1_HOST="${M1_HOST:-}"
M1_IDENTITY="${M1_IDENTITY:-}"
M1_KNOWN_HOSTS="${M1_KNOWN_HOSTS:-}"

while (($#)); do
  case "$1" in
    --repo-url) REPO_URL="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    --agent-e2e) AGENT_E2E=1; shift ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --host) M1_HOST="$2"; shift 2 ;;
    --identity) M1_IDENTITY="$2"; shift 2 ;;
    --known-hosts) M1_KNOWN_HOSTS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$REPO_URL" || -z "$M1_HOST" || -z "$M1_IDENTITY" || -z "$M1_KNOWN_HOSTS" ]]; then
  printf 'repo URL, M1 host, identity, and known-hosts are required\n' >&2
  usage >&2
  exit 2
fi

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$ROOT/ci-artifacts/remote-$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p "$OUT_DIR"

run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
remote_root="\$HOME/.m1-ci/runs/$run_id"
ssh_args=(
  -o BatchMode=yes
  -o IdentitiesOnly=yes
  -o ConnectTimeout=10
  -i "$M1_IDENTITY"
  -o UserKnownHostsFile="$M1_KNOWN_HOSTS"
)

printf 'run_id=%s\n' "$run_id"
printf 'repo=%s\n' "$REPO_URL"
printf 'ref=%s\n' "$REF"
printf 'agent_e2e=%s\n' "$AGENT_E2E"

ssh "${ssh_args[@]}" "$M1_HOST" \
  "REPO_URL=$(printf %q "$REPO_URL") REF=$(printf %q "$REF") AGENT_E2E=$AGENT_E2E RUN_ROOT=\"$remote_root\" bash -s" <<'REMOTE'
set -euo pipefail

mkdir -p "$RUN_ROOT"
repo_dir="$RUN_ROOT/repo"
artifact_dir="$RUN_ROOT/artifacts"

git clone --quiet "$REPO_URL" "$repo_dir"
git -C "$repo_dir" checkout --quiet "$REF"

printf 'resolved_commit=%s\n' "$(git -C "$repo_dir" rev-parse HEAD)"
(
  cd "$repo_dir"
  ARTIFACT_DIR="$artifact_dir" AGENT_E2E="$AGENT_E2E" ./scripts/ci/m1-job.sh
)
REMOTE

rsync -az -e "ssh -o BatchMode=yes -o IdentitiesOnly=yes -i $M1_IDENTITY -o UserKnownHostsFile=$M1_KNOWN_HOSTS" \
  "$M1_HOST:$remote_root/artifacts/" "$OUT_DIR/"

ssh "${ssh_args[@]}" "$M1_HOST" "rm -rf \"$remote_root\""

printf 'artifacts=%s\n' "$OUT_DIR"
printf 'status=%s\n' "$(jq -r .status "$OUT_DIR/summary.json")"

