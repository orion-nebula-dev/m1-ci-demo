#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf 'Usage: %s OWNER/REPO RUNNER_NAME\n' "$0" >&2
  exit 2
fi

repo_slug="$1"
runner_name="$2"
runner_root="${RUNNER_ROOT:-$HOME/actions-runner}"
runner_version="${RUNNER_VERSION:-2.338.0}"
label="${RUNNER_LABEL:-m1-ci}"
archive="actions-runner-osx-arm64-${runner_version}.tar.gz"
service_label="actions.runner.$(printf '%s' "$repo_slug" | tr '/' '.').$runner_name"
plist="$HOME/Library/LaunchAgents/$service_label.plist"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  printf 'This installer expects an Apple Silicon macOS host\n' >&2
  exit 1
fi

if [[ ! -x "$runner_root/run.sh" ]]; then
  mkdir -p "$runner_root"
  curl --fail --location --retry 3 \
    "https://github.com/actions/runner/releases/download/v${runner_version}/${archive}" \
    | tar -xz -C "$runner_root"
fi

if ! command -v gh >/dev/null; then
  printf 'GitHub CLI (gh) is required to request a registration token\n' >&2
  exit 1
fi

token="$(gh api --method POST "repos/$repo_slug/actions/runners/registration-token" --jq .token)"

if [[ -f "$runner_root/.runner" ]]; then
  "$runner_root/config.sh" remove --token "$token"
fi

(
  cd "$runner_root"
  ./config.sh \
    --unattended \
    --url "https://github.com/$repo_slug" \
    --token "$token" \
    --name "$runner_name" \
    --labels "$label,macOS,ARM64" \
    --work _work \
    --replace
)
unset token

mkdir -p "$HOME/Library/LaunchAgents" "$runner_root/_diag"
cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$service_label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$runner_root/run.sh</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$runner_root</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.npm-global/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>HOME</key>
    <string>$HOME</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>StandardOutPath</key>
  <string>$runner_root/_diag/launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>$runner_root/_diag/launchd.err.log</string>
</dict>
</plist>
PLIST

plutil -lint "$plist"
launchctl bootout "gui/$(id -u)/$service_label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
launchctl enable "gui/$(id -u)/$service_label"
launchctl kickstart -k "gui/$(id -u)/$service_label"

printf 'Runner installed: %s\n' "$service_label"
printf 'Check status: launchctl print gui/%s/%s\n' "$(id -u)" "$service_label"
