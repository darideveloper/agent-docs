---
created: 2026-07-27
updated: 2026-09-17
tags:
  - astro
  - development
  - portless
  - documentation
type: resource
status: active
source: templates://astro/astro-portless.md
version: 2026-09-17+4cf710f

---

# Portless Dev Workflow

Replaces hardcoded port numbers with stable, named `.localhost` URLs. Eliminates port conflicts, cookie/storage clashes between projects, and the need to remember port numbers. Provides production-like HTTPS during development.

## How It Works

```
Browser ──> https://<project-name>.localhost
                   │
          Portless Proxy (port 443 / 1355)
          Local CA + auto-HTTPS
                   │
          Astro Dev Server (ephemeral port, e.g. 4737)
```

Portless runs a local HTTPS/2 proxy that routes named `.localhost` subdomains to ephemeral dev server ports. It assigns a random port (4000–4999) and injects it as the `PORT` environment variable into the child process.

The `astro.config.mjs` reads `process.env.PORT` to determine the listen port, falling back to `4321` when running outside portless:

```js
server: {
  port: process.env.PORT ? parseInt(process.env.PORT) : 4321,
  strictPort: true,
}
```

## Prerequisites

```bash
npm install -g portless
```

## Setup per Project

1. Install portless globally (see above)
2. Use the `dev` script below (canonical). `portless run` derives the app name automatically and prepends the branch inside worktrees — never pin a hardcoded app name:

```json
{
  "scripts": {
    "dev": "portless run pnpm astro dev"
  }
}
```

Behind a MITM corporate proxy, prefix with `NODE_OPTIONS=--use-openssl-ca`. Full merged scripts table lives in [astro-base-config](./astro-base-config.md) §3.

3. Configure `astro.config.mjs` to accept the `PORT` env var:

```js
export default defineConfig({
  server: {
    port: process.env.PORT ? parseInt(process.env.PORT) : 4321,
    strictPort: true,
  },
})
```

Full merged config lives in [astro-base-config](./astro-base-config.md) §1.

4. Create `.env` with the dev URL (used for redirects, canonical links, etc.):

```bash
SITE_URL=https://<project-name>.localhost
```

## Commands

| Action | Command |
|---|---|
| Start dev server | `pnpm run dev` |
| Stop a checkout | Ctrl+C in its own terminal (each route unregisters when its `portless run` parent exits) |
| Check status | `portless status` |
| List live routes | `portless list` |

> There is **no per-route stop command**. `portless stop <name>` parses `stop` as an app name and registers a bogus `stop.localhost` route instead of stopping anything. `portless proxy stop` stops the proxy itself. With worktrees, stop each checkout's server first, then remove the worktree — see [Git Worktrees + Portless](./astro-worktrees.md).

## Environment Variables

Portless injects the following into the child process:

- `PORT` — Ephemeral port the Astro dev server listens on
- `HOST` — Typically `127.0.0.1`
- `PORTLESS_URL` — Public URL (e.g. `https://<project-name>.localhost`; inside a worktree the branch is prepended, e.g. `https://<branch>.<project-name>.localhost` — `portless list` is the source of truth)

`SITE_URL` (`.env`, server-only) should resolve through the same chain: `PORTLESS_URL → SITE_URL → https://<prod-domain>` fallback — the fallback must be the prod domain, never localhost: dev never reaches it (Portless always injects `PORTLESS_URL`), and an env-less build must emit prod — never localhost — into sitemap/canonicals. See [Git Worktrees + Portless](./astro-worktrees.md) and [All Config in One Place](./astro-site-config.md).

## Running under AI agents

Astro ≥7.3 auto-backgrounds the dev server when it detects an agent environment (e.g. `OPENCODE` / `OPENCODE_PID` set): the `portless run` supervisor exits while the Astro child keeps the port, so the proxy route unregisters (proxy 404) while the direct port still answers. Default policy: servers are started manually — agents never autostart them.

Fix pattern — stop the orphan, relaunch foreground with agent vars stripped, kept under supervision in a persistent/detached session:

```bash
astro dev stop
env -u OPENCODE -u OPENCODE_PID pnpm run dev
portless list   # route present + proxy 200 before continuing
```

Never `--background` the portless-wrapped dev server — it orphans the proxy
route. Per-project agent contract (manual siblings, no autostart) lives in
the [AGENTS worktrees snippet](./astro-agents-worktrees-snippet.md).

## Troubleshooting

| Issue | Fix |
|---|---|
| `command not found: portless` | Run `npm install -g portless` |
| `.localhost` doesn't resolve (Safari, Firefox) | Run `portless hosts sync` to add entries to `/etc/hosts` |
| Port conflict on 443 | Portless falls back to 1355; check `portless status` |
| Dev server won't start | Ensure no other process is on the assigned port; stop that checkout's server (Ctrl+C) then retry |
| Proxy 404 but direct `http://127.0.0.1:<port>/` answers, route missing from `portless list` | Astro ≥7.3 auto-backgrounded under agent env (`OPENCODE`/`OPENCODE_PID` set) and orphaned the `portless run` supervisor — see "Running under AI agents" above |

## Key Rules

- Portless is installed globally, not in `package.json` dependencies
- The `strictPort: true` setting (in the snippet above) ensures the dev server fails fast if the assigned port is taken
- `.localhost` subdomains resolve natively in Chrome and Edge. Firefox and Safari need `portless hosts sync` to add entries to `/etc/hosts` — see the table above
- Portless stores its CA, TLS certs, and route state in `~/.portless/`

## Connection to Other Patterns

- `SITE_URL` env var is consumed by the app for form redirects and canonical links → see [[astro-site-config]]
- Worktrees (one checkout per branch, branch-subdomain URLs) → see [Git Worktrees + Portless](./astro-worktrees.md)
- In production, the app is served via Docker/nginx, not portless → see [[astro-docker-deployment]]
