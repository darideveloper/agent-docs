# agent-docs — Single Source of Truth for Django + Astro Templates

> Public, sanitized templates. This repo is the **single source of truth**. The Obsidian vault keeps only pointer stubs.

## Stacks

- **django/** — 20 files incl. hub (project setup, model definitions, unfold, DRF default-ON, media canonical STORAGES, testing runner, fixtures, optional layers, stripe worked examples)
- **astro/** — 27 files incl. hub: 20 top-level + `gsap-scrolltrigger/` 7 files (base config, atomic components, site-config, transitions, SEO, docker, portless, worktrees, dependency map + opt-in layers: react-islands, zustand-zod, fetch-wrapper, i18n, markdown, images, pwa, gsap-scrolltrigger)

See `manifest.json` for the machine-readable stack → base + layers map. Descriptions mirror the hub docs (hub is vendored as base).

## Pull (projects)

Interactive TUI (bash 4+ `select`, needs Node/npx for `degit`; falls back to `curl` per-file if missing):

```bash
# bootstrap without cloning (works in an empty project, non-interactive)
curl -sL https://raw.githubusercontent.com/darideveloper/agent-docs/main/pull.sh | bash -s -- --stack astro --layers i18n,react-islands --yes --dest ./docs

# or from a checkout
./pull.sh                  # TUI: pick stack → toggle layers → preview → copy
./pull.sh --check          # header dump (states: see promote.sh --check)
./pull.sh --stack astro --layers i18n,react-islands --yes  # non-interactive (agents/CI, --yes skips TUI)
```

What it does: one `degit` fetch to tmp, copy only selected files per `manifest.json`, keep upstream `source: templates://…` + `version:` untouched, refresh `docs/INDEX.md` (from `INDEX-template.md`), create empty `X.local.md` stubs (never overwrites existing). Pull always overwrites `*.md`, never `*.local.md`.

Project layout after pull:

```text
docs/
  astro-i18n.md         # vendored, READ-ONLY, overwritten by every pull
  astro-i18n.local.md   # project-only, never overwritten, never auto-promoted
  INDEX.md              # precedence + rules + pull/promote usage (refreshed every pull)
```

## Promote (generic improvements → PR)

```bash
./promote.sh                              # TUI grouped by state
./promote.sh --check                      # read-only: UP-TO-DATE/DIVERGED/NEW
./promote.sh --all --yes --out ./patches/ # batch for agents/CI
```

Updates (`DIVERGED`) emit `<name>.patch` (strip `#` comments before `git apply`); brand-new header-stamped files (`source: templates://<stack>/<file>`, upstream 404) emit a full copy outside `docs/` + `<name>.manifest.json.snippet` (`files:[]` schema) + hub-row hint. Secrets gate runs first (`sk_live_placeholder`/`sk_test_placeholder`/`SECRET_KEY=change-me` pass, real keys block). After merge, projects re-`pull.sh` to clean — upstream stamps `version:` on merge.

Only generic fixes are promoted. Project-specific content stays in `*.local.md` and is never promoted wholesale.

## Precedence & Rules

1. Read `X.md` then `X.local.md` — local wins on conflict.
2. Never edit `X.md` for project-specific content.
3. Never commit secrets (keys, tokens, passwords) to `docs/` — vendor or local. Secrets live in `.env*` (gitignored). Example keys use placeholders.
4. Track both `*.md` and `*.local.md` in project git (unless local holds client secrets — then ignore `*.local.md` explicitly).

See `INDEX-template.md` for the full text vendored into each project.

## Contributing

- PRs welcome for generic improvements (validation scripts, new opt-in layers, doc fixes).
- Include the `source:` + `version:` of the file you edited and a before/after note.
- Do not include secrets, client PDFs, or vault-private notes.

## Vault Relationship

The Obsidian vault (`daridev`) no longer holds canonicals. Its `20-areas/work/django/django.md` and `20-areas/work/astro/astro.md` are pointer stubs linking here. The 3 inbound references (`30-resources/redis/redis.md`, `20-areas/work/vercel-labs/portless.md`, `20-areas/work/mermaid/mermaid-diagram-generation.md`) point to this repo via plain-text URLs.
