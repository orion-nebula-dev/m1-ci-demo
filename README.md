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

## Security boundary

Never send untrusted fork pull requests to a persistent self-hosted runner. The agent
job is restricted to the trusted `main` branch and uses `--ephemeral`.
