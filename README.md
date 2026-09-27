# agent-docs — Single Source of Truth for Django + Astro Templates

> Public, sanitized templates. This repo is the **single source of truth**. The Obsidian vault keeps only pointer stubs.

## Stacks

- **django/** — 20 files (project setup, model definitions, unfold, DRF, media, testing, fixtures, optional layers, stripe worked examples)
- **astro/** — 19 files + `gsap-scrolltrigger/` subfolder (base config, atomic components, site-config, transitions, SEO, docker, portless, worktrees, dependency map + opt-in layers: react-islands, zustand-zod, fetch-wrapper, i18n, markdown, pwa, gsap)

See `manifest.json` for the machine-readable stack → base + layers map. Descriptions are copied verbatim from the hub docs.

## Pull (projects)

Interactive TUI (bash `select`, needs Node for `degit`; falls back to `curl` per-file if missing):

```bash
# bootstrap without cloning (works in an empty project)
curl -sL https://raw.githubusercontent.com/darideveloper/agent-docs/main/pull.sh | bash

# or from a checkout
./pull.sh                  # TUI: pick stack → toggle layers → preview → copy
./pull.sh --check          # report states
./pull.sh --stack astro --layers i18n,react-islands --yes  # non-interactive (agents/CI)
```

What it does: one `degit` fetch to tmp, copy only selected files per `manifest.json`, stamp `source: templates://…` + `version: YYYY-MM-DD+<short-hash>`, write `docs/INDEX.md` (from `INDEX-template.md`), create empty `X.local.md` stubs (never overwrites existing).

Project layout after pull:

```text
docs/
  astro-i18n.md         # vendored, READ-ONLY, overwritten by pull --update
  astro-i18n.local.md   # project-only, never overwritten, never auto-promoted
  INDEX.md              # precedence + rules + pull/promote usage
```

## Promote (generic improvements → PR)

```bash
./promote.sh                              # TUI grouped by state
./promote.sh --check                      # read-only: UP-TO-DATE/DIVERGED/NEW
./promote.sh --all --yes --out ./patches/ # batch for agents/CI
```

Updates (`DIVERGED`) emit `<name>.patch`; brand-new header-stamped files (`source: templates://<stack>/<file>`, upstream 404) emit a full copy + `<name>.manifest.json.snippet` + hub-row hint. Secrets gate runs first (placeholders pass, real keys block). After merge, projects re-`pull.sh` to clean — upstream stamps `version:` on merge, projects keep `+local` until then.

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
