# github-runner

Public runner shell for the **github-claw** lobster platform. This repo is
intentionally minimal and contains **no secrets and no business logic** — just a
workflow that proves its identity to the platform and runs whatever the platform
sends back.

## How it works

1. The github-claw platform dispatches `agent.yml` (`workflow_dispatch`) on behalf
   of a Lark user — using *their* GitHub OAuth token. Only collaborators with write
   access can dispatch, which is the access-control mechanism.
2. `scripts/exchange.sh` requests a GitHub Actions OIDC token and exchanges it at
   `POST $PLATFORM_URL/api/runner/exchange`. The platform verifies the OIDC claims
   (repo, workflow, ref, github-hosted) before returning a one-time credential
   bundle and a fresh session token.
3. The runner then downloads its actual scripts from
   `GET $PLATFORM_URL/api/runner/payload` (bootstrap, agent driver, the `claw` CLI,
   etc.) and executes them. Updating the runner's behaviour is a platform-side
   change — this repo rarely needs to move.
4. The bootstrap sets up SSH/VNC over bore tunnels, mounts the shared memory folder,
   and runs a Codex agent that talks to the Lark chat through the platform.

## Setup (one-time, by the platform operator)

- Make this repo **public**.
- Add collaborators who are allowed to launch machines (write access = dispatch
  permission).
- Set a repo **variable** `PLATFORM_URL` to your deployed worker URL, e.g.
  `https://github-claw.<account>.workers.dev`.

## Security

- Triggers are `workflow_dispatch` only — no `push` / `pull_request`, so forks can't
  run it or steal credentials.
- All secrets arrive at runtime from the platform after OIDC verification and are
  masked with `::add-mask::`. Nothing is ever written to artifacts or the step
  summary.
