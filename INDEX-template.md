# docs/INDEX — Vendor + Local Precedence

> This project uses vendored docs from `agent-docs`.

## Precedence
1. Read `X.md` first (generic, vendored — agents: never auto-edit; edit only on the user's explicit request for a generic fix or reusable feature).
2. Then read `X.local.md` if it exists (project-specific override — **wins on conflict**).
3. Never edit `X.md` to add project-specific content — use `X.local.md`.

## Rules for Agents & Humans
- **Generic fixes go in `X.md` ONLY on explicit user request:** typos, better patterns, reusable features — and only when the user asked for it. Agents never auto-edit `X.md` unasked. `promote.sh` diffs it, blocks secrets, and emits the PR artifact.
- **Project content goes to `*.local.md`:** project-specific slugs, business keys, language lists, client conventions, etc. Never promoted.
- **Never commit secrets:** no API keys, tokens, passwords, or private URLs in `docs/` (vendor or local). Secrets belong in `.env*` (gitignored). If a doc needs an example key, use a placeholder (`sk_test_placeholder`, `SECRET_KEY=change-me`).
- **Re-pull safety:** `pull.sh --update` overwrites `*.md` but never touches `*.local.md`.

## Pull / Promote
```bash
# pull correct docs interactively (bash select TUI, needs Node for degit; curl fallback if missing)
curl -sL https://raw.githubusercontent.com/darideveloper/agent-docs/main/pull.sh | bash
# or locally if you have the repo:
./pull.sh                 # TUI: pick stack → toggle layers → preview → copy
./pull.sh --check         # report UP-TO-DATE / BEHIND / DIVERGED
./pull.sh --stack astro --layers i18n,react-islands --yes  # non-interactive (for agents/CI)

# propose generic improvements upstream (updates + brand-new files; *.local.md never promoted)
./promote.sh              # TUI grouped by state: DIVERGED → .patch, NEW → full copy + manifest snippet
./promote.sh --check      # read-only STATE table (UP-TO-DATE/DIVERGED/NEW)
./promote.sh --all --yes --out ./patches/  # batch for agents/CI
# after upstream merge: re-pull to clean (upstream stamps version on merge)
curl -sL https://raw.githubusercontent.com/darideveloper/agent-docs/main/pull.sh | bash -s -- --stack astro --layers <yours> --yes --dest ./docs
```

## Mapping (from manifest.json)
- **Stack** = `django` or `astro`
- **Base** = always included (pre-checked, un-uncheckable in TUI)
- **Layers** = opt-in toggles (e.g. `astro:i18n`, `django:redis`)

## Before Committing docs/
- `grep -R "sk_live\|sk_test\|SECRET_KEY=\|PASSWORD" docs/` should show only placeholders.
- `promote.sh --check` should show no unexpected DIVERGED (generic fixes go via PR, then re-pull).
