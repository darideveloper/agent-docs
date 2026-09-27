# AGENTS.md — agent-docs (upstream source of truth)

Canonical repo: https://github.com/darideveloper/agent-docs

This repo IS upstream. `astro/` + `django/` files here are vendored OUT to projects via `pull.sh`. There are no `*.local.md` files here — those live only in downstream projects.

## Layout
- `astro/` / `django/` — canonical templates (each file has `source:` + `version:` header).
- `manifest.json` — stack → base + layers map. `pull.sh` reads it; keep in sync when adding/removing files.
- `pull.sh` — vendors selected files into a project's `docs/` + writes `docs/INDEX.md` from `INDEX-template.md`.
- `promote.sh` — downstream helper: classifies docs/ (UP-TO-DATE/DIVERGED/NEW), gates secrets, emits .patch (updates) or full copy + manifest snippet (new files) for a PR back here.
- `INDEX-template.md` — precedence + pull/promote contract copied into each project.
- `README.md` — human overview + pull/promote usage.

## Rules for agents
1. Edit canonicals directly here (this is the exception to the downstream "vendor is read-only" rule).
2. Keep `source: templates://<stack>/<file>` + `version: YYYY-MM-DD+<short-hash>` headers intact; bump version on edit.
3. When adding/removing a template file, update `manifest.json` (base vs layer, description) in the same change.
4. Generic improvements only — never commit project-specific content, client data, or secrets. Example keys use placeholders (`sk_test_placeholder`, `SECRET_KEY=change-me`).
5. Before committing `docs/`-adjacent changes: `grep -R "sk_live\|sk_test\|SECRET_KEY=\|PASSWORD" astro/ django/` should show placeholders only.
6. Pull smoke test after manifest changes: `./pull.sh --stack astro --layers i18n,react-islands --yes --dest /tmp-pull/docs` (or `--stack django --yes` for base-only).
7. Promote smoke after promote.sh changes: clean pull → `--check` all UP-TO-DATE; touch one vendor file → DIVERGED + patch; header-stamped new file → NEW + copy/snippet; `*.local.md` edits ignored.
