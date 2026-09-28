---
created: 2026-09-17
tags:
  - astro
  - git
  - worktrees
  - agents
  - documentation
type: resource
status: active
source: templates://astro/astro-agents-worktrees-snippet.md
version: 2026-09-27+57b0fd3

---

# AGENTS.md Git Worktrees Snippet (canonical, copy-paste)

This file is the **single source of truth** for the per-project `AGENTS.md`
§ Git worktrees section. Copy it into each new Astro project, substituting
`<project>` / `<prod-domain>` / `<projects-root>`. `astro-worktrees.md`
references this file — never duplicate the ban text inline.

```markdown
## Development

Canonical dev start (Astro foreground under `portless run` — this is what serves the `.localhost` URL):

\`\`\`bash
pnpm run dev
\`\`\`

Never `--background` there — it orphans the proxy route. `astro dev --background` + `astro dev stop` / `status` / `logs` are reserved for direct non-portless runs (no `.localhost` URL). Servers are started manually — agents never autostart them (see `docs/astro-portless.md` § "Running under AI agents").

## Git worktrees

One checkout per branch, all runnable at once. `pnpm run dev` uses `portless run`, so each checkout gets its own URL automatically: main → `https://<project>.localhost`, a worktree on branch `<branch>` → `https://<branch>.<project>.localhost`.

This project uses **manual siblings only, in the same terminal session**. Never use the `worktree_create` / `worktree_delete` plugin tools here (they open a new terminal and nest under the central store). Never nest a worktree inside the main checkout.

\`\`\`bash
<projects-root>/
  <project>/              # main checkout
  <project>-<branch>/     # sibling worktree (e.g. <project>-feature-auth)
\`\`\`

Lifecycle:

\`\`\`bash
git fetch origin
git worktree add ../<project>-<branch> <branch>                  # existing branch
git worktree add ../<project>-feature -b feature/xyz main        # new branch
git worktree list
# ... after merge, stop dev first (Ctrl+C), then full clean:
git worktree remove ../<project>-<branch>
git worktree prune
git branch -d <branch>          # squash-merged branch; -D only with reviewed work
git fetch -p                    # drop stale remote-tracking refs
git worktree list               # verify clean — only main remains
\`\`\`

Bootstrap each new sibling (gitignored paths are per-checkout — `node_modules/`, `.env`, `.astro/`, `dist/` don't transfer):

\`\`\`bash
cd ../<project>-<branch>
cp ../<project>/.env .env
pnpm install
pnpm run dev   # → https://<branch>.<project>.localhost
\`\`\`

Gotchas:

- Real `pnpm install` per sibling (no `node_modules` symlink).
- A fresh `.env` copy keeps main's `SITE_URL` — harmless, the `PORTLESS_URL → SITE_URL → prod` chain resolves each checkout's own URL first.
- Openspec: nothing crosses automatically. Copy `openspec/changes/archive/` by hand (`cp -rn`) only when needed; active proposals stay isolated. New siblings also need `.opencode/skills/openspec-*` + `commands/opsx-*.md` synced by hand (markdown only); archive back to main before merge (only `archive/` is tracked).
- New siblings start from committed `HEAD` only — commit or stash uncommitted changes first.
- Teammate branches: `git fetch origin` and ensure a local branch exists (`git branch <name> origin/<name>`) BEFORE `git worktree add ../<project>-<name> <name>`.
- Branch names with `/` get sanitized in the subdomain — check `portless list` after first run.
- One dev server per checkout; review before deleting; squash on merge.
```

## Substitution table

| Placeholder | Example | Where it appears |
|---|---|---|
| `<project>` | `<project>` | checkout paths, URLs, `.env` copy source |
| `<prod-domain>` | `https://<project>comercial.mx` | only in the chain comment (`PORTLESS_URL → SITE_URL → prod`), not in commands |
| `<projects-root>` | `/path/to/project/` | layout block only |

## Connection to Other Patterns

- Full rationale, URL model, stopping, troubleshooting → see [Git Worktrees + Portless](./astro-worktrees.md)
- Agent-orphaned servers → see [Portless Dev Workflow](./astro-portless.md) § Running under AI agents
