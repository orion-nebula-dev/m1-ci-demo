# M1 CI Demo

Reference pipeline for a Mac mini M1 acting as a private CI and agent E2E host.

## Pipeline

- `ci.yml`: lint, unit test, HTTP smoke test, and artifact upload on the M1 runner.
- `agent-e2e.yml`: a trusted-branch-only Codex acceptance agent in an isolated checkout.
- Runner labels: `self-hosted`, `macOS`, `ARM64`, `m1-ci`.

## Local verification

```bash
npm run lint
npm test
./scripts/e2e.sh
```

## SSH-driven CI from the development Mac

The development Mac can test an exact Git ref on the M1 without relying on
GitHub Actions:

```bash
M1_HOST=user@m1-host \
M1_IDENTITY=/path/to/ssh-key \
M1_KNOWN_HOSTS=/path/to/known-hosts \
scripts/ci/m1-remote.sh --ref main --agent-e2e
```

The orchestrator clones into an isolated directory on the M1, runs
`scripts/ci/m1-job.sh`, copies artifacts back, and removes the remote checkout.
Set `AGENT_E2E=1` only for a trusted branch because the Codex acceptance job
requires full local access.

## GitHub Actions runner

On the M1, after authenticating `gh` and enabling Actions for the repository:

```bash
scripts/ci/runner-install.sh OWNER/REPO m1-ci
```

Alternatively, pass a short-lived registration token without installing `gh`:

```bash
RUNNER_TOKEN=... scripts/ci/runner-install.sh OWNER/REPO m1-ci
```

The installer requests a short-lived registration token, configures the
`self-hosted,macOS,ARM64,m1-ci` labels, and installs a launchd service.

## Security boundary

Never send untrusted fork pull requests to a persistent self-hosted runner. The agent
job is restricted to the trusted `main` branch and uses `--ephemeral`.
