# docs/INDEX — Vendor + Local Precedence

> This project uses vendored docs from `agent-docs`.

## Precedence
1. Read `X.md` first (generic, vendored — READ-ONLY).
2. Then read `X.local.md` if it exists (project-specific override — **wins on conflict**).
3. Never edit `X.md` to add project-specific content — use `X.local.md`.

## Rules for Agents & Humans
- **Vendor is read-only:** do not edit `*.md` except to flag `PROMOTE-CANDIDATE` when the fix is generic and should be proposed upstream.
- **Project content goes to `*.local.md`:** project-specific slugs, business keys, language lists, client conventions, etc.
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

# propose generic improvements upstream
./promote.sh              # TUI: pick DIVERGED file → show diff → write .patch
```

Placeholder until first public release — raw URL will be `https://raw.githubusercontent.com/darideveloper/agent-docs/main/pull.sh`.

## Mapping (from manifest.json)
- **Stack** = `django` or `astro`
- **Base** = always included (pre-checked, un-uncheckable in TUI)
- **Layers** = opt-in toggles (e.g. `astro:i18n`, `django:redis`)

## Before Committing docs/
- `grep -R "sk_live\|sk_test\|SECRET_KEY=\|PASSWORD" docs/` should show only placeholders.
- `pull.sh --check` should be `UP-TO-DATE` or you must note `PROMOTE-CANDIDATE` in the PR description.
