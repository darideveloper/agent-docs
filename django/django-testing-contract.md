---
created: 2026-09-04
tags:
  - django
  - testing
  - documentation
type: guide
status: active
source: templates://django/django-testing-contract.md
version: 2026-09-27+57b0fd3

---

# Django Testing Contract — Django-only Runner

> Drop-in guide to lock **any** Django project to `python manage.py test` and prevent `pytest`/`pytest-django` (or any alternative runner) from creeping back — via docs, settings, gitignore, and a mechanical CI guard. Copy-paste ready. `STORAGES` canonical lives in [Media Storage](./django-media-storage.md) — the snippet below (§2.2) is the test-only fallback shape, do not treat as canonical.

This is the generalized, vault-portable version of a real project pattern. It fixes the 3 root causes that invited pytest drift: **(1)** system `pytest` outside `venv`, **(2)** stale `conftest.py` reference, **(3)** LLMs defaulting to `pytest`.

> **Provenance:** distilled from a real project; vault-specific paths (archive dirs, vault `.gitignore` line numbers) are illustrative only — adapt to your target project. CI guard-only (no test run in CI) is the default opinion; run tests locally/prod.

> **Vault vs project:** This file was vendored from the vault and now lives in `agent-docs/django/` (formerly `20-areas/work/django/`). Do **not** create `.opencode/commands/guard.sh` or `.github/workflows/test-contract.yml` in the vault — copy them into your **target Django project** (the vault's `.gitignore:59` already has `.*/` which ignores hidden folders like `.opencode`).

---

## Placeholders

| Placeholder | Meaning | Example |
|-------------|---------|---------|
| `<PROJECT>` | Django project package | `project`, `config`, `myproject` |
| `venv` | Virtual environment folder | `venv`, `.venv` |
| `<APP_LABEL>` | Django app to test | `myapp`, `articles` |
| `<APP_LABEL>.tests.Case.test_foo` | Django test label | `myapp.tests.ArticleApiTestCase.test_list_is_paginated` |

When copying snippets, replace `<PROJECT>` and `<APP_LABEL>` with your names. Keep `venv/` inlined as shown — adapt to `.venv/` if that is your convention.

---

## 1. Rule

**Canonical runner:** `venv/bin/python manage.py test [--verbosity=2]` (or `python manage.py test` when venv active). Targeted: `venv/bin/python manage.py test <APP_LABEL>.tests.<Case>.<test> --verbosity=2`. Never `pytest`, `python -m pytest`, `pytest -k`.

Generic example:

```bash
venv/bin/python manage.py test --verbosity=2
venv/bin/python manage.py test myapp.tests.ArticleApiTestCase.test_list_is_paginated --verbosity=2
# do not use: pytest -k test_list_is_paginated (pytest nodeid)
```

**Allowed:** `django.test.TestCase`, `rest_framework.test.APITestCase`/`APIClient`, `RequestFactory`, `override_settings`, `SimpleUploadedFile`, `call_command`, stdlib (`unittest.mock`, `base64`, `hashlib`, `hmac`, `Decimal`, `json`), `selenium` only testing extra.

**Banned:** `pytest`, `pytest-django`, `conftest.py`, `pytest.ini`/`.pytest.ini`, `setup.cfg [tool:pytest]`, `pyproject.toml [tool.pytest]`/`[tool.pytest.ini_options]`, any `import pytest`/`from pytest`/`@pytest.*` in `*.py`. Do not create `pyproject.toml`/`setup.cfg` with `[tool.pytest]` to "disable" pytest — absence is the ban.

---

## 2. Replicate in 6 Steps (copy-paste)

### 2.1 `AGENTS.md` — single source for humans + agents

Add after existing conventions (agents load this on session start):

```markdown
## Testing — Django only

Canonical runner: `venv/bin/python manage.py test [--verbosity=2]` (or `python manage.py test` when venv is active). Use Django test labels for targeted runs, e.g. `venv/bin/python manage.py test myapp.tests.ArticleApiTestCase.test_list_is_paginated --verbosity=2` — do not use pytest nodeids (`-k`).

Allowed bases/helpers: `django.test.TestCase`, `rest_framework.test.APITestCase` / `APIClient`, `django.test.RequestFactory`, `django.test.override_settings`, `django.core.files.uploadedfile.SimpleUploadedFile`, `django.core.management.call_command`, and stdlib helpers (`unittest.mock`, `base64`, `hashlib`, `hmac`, `Decimal`, `json`). Only testing extra in `requirements.txt` is `selenium`.

**Banned:** `pytest`, `pytest-django`, `conftest.py`, `pytest.ini`/`.pytest.ini`, `setup.cfg` with `[tool:pytest]`, `pyproject.toml` with `[tool.pytest]` / `[tool.pytest.ini_options]`, and any `import pytest` / `from pytest` / `@pytest.*` in `*.py`. Do not add `conftest.py`, `pytest.ini`, or pytest config. The contract is enforced by `.opencode/commands/guard.sh` and CI job `test-contract-guard`. See this contract and [django-project-setup](./django-project-setup.md) §7 for `IS_TESTING` isolation.
```

Why `AGENTS.md` over `CONTRIBUTING.md`: lowest friction, already loaded by agents, versioned. A hook that rewrites `pytest` → `manage.py test` was rejected — it hides rather than teaches.

### 2.2 `<PROJECT>/settings.py` — DB + staticfiles isolation

Replace `<PROJECT>` with your project package. Two equivalent styles — pick the one matching your codebase:

**Variant A — `pathlib` (`BASE_DIR /`):**

```python
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

IS_TESTING = len(sys.argv) > 1 and sys.argv[1] == "test"

if IS_TESTING:
    DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": BASE_DIR / "testing.sqlite3"}}
else:
    # ... normal DB_ENGINE / DB_* logic per [django-project-setup](./django-project-setup.md) §7
    pass

# STORAGES: avoid Whitenoise manifest during tests
STORAGES = {
    "default": {"BACKEND": "<PROJECT>.storage_backends.PublicMediaStorage" if STORAGE_AWS else "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage" if IS_TESTING else (
        "<PROJECT>.storage_backends.StaticStorage" if STORAGE_AWS else "whitenoise.storage.CompressedManifestStaticFilesStorage"
    )},
    # only if you use private media — otherwise omit this key
    # "private": {"BACKEND": "<PROJECT>.storage_backends.PrivateMediaStorage" if STORAGE_AWS else "django.core.files.storage.FileSystemStorage",
    #             "OPTIONS": {"location": MEDIA_ROOT / "private-media"} if not STORAGE_AWS else {}},
}
```

**Variant B — `os.path` (`os.path.join`):**

```python
import sys, os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

IS_TESTING = len(sys.argv) > 1 and sys.argv[1] == "test"

if IS_TESTING:
    DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": os.path.join(BASE_DIR, "testing.sqlite3")}}
else:
    # ... normal DB logic
    pass

if STORAGE_AWS:
    STORAGES = {
        "default": {"BACKEND": "<PROJECT>.storage_backends.PublicMediaStorage"},
        "staticfiles": {"BACKEND": "<PROJECT>.storage_backends.StaticStorage"},
        "private": {"BACKEND": "<PROJECT>.storage_backends.PrivateMediaStorage"},  # only if you use private media
    }
else:
    staticfiles_backend = "django.contrib.staticfiles.storage.StaticFilesStorage" if IS_TESTING else "whitenoise.storage.CompressedManifestStaticFilesStorage"
    STORAGES = {
        "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
        "staticfiles": {"BACKEND": staticfiles_backend},
        # only if you use private media — otherwise omit this key
        # "private": {"BACKEND": "django.core.files.storage.FileSystemStorage", "OPTIONS": {"location": os.path.join(MEDIA_ROOT, "private-media")}},
    }
```

> No `conftest.py` fixture needed. Admin changelist/change/add views render 200 during `manage.py test` because `StaticFilesStorage` doesn't need `staticfiles.json`. Production stays on `CompressedManifestStaticFilesStorage`. No runtime change to existing `TestCase`/`APITestCase` suites. See also [django-media-storage](./django-media-storage.md) for S3 details.

### 2.3 `.gitignore` — minimal (Ponytail)

```gitignore
venv
.venv
/.venv/
# ... existing
.*/        # already covers .pytest_cache and any dotfile (e.g. .pytest.ini) — canonical
```

- Do **not** add explicit `/.pytest_cache/` or `/conftest.py` — `.*/` handles dotfiles; `conftest.py`/`pytest.ini` (no dot) intentionally not gitignored — blocked by the guard instead (fail-loud > silent ignore). Minimal-file decision.
- Full `.gitignore` (including `openspec/changes/*` + `!openspec/changes/archive/`) lives in [django-project-setup](./django-project-setup.md) §4 — this section owns only the `.*/` minimal rationale.
- Verification (proves `.*/` works, don't grep `.gitignore`):
  ```bash
  touch .hidden_test_file && git check-ignore -v .hidden_test_file  # → .gitignore:57:.*/
  touch .pytest_cache && git check-ignore -v .pytest_cache          # → .*/ (dotfile)
  touch .pytest.ini && git check-ignore -v .pytest.ini              # → .*/ (dotfile)
  touch .opencode/test && git check-ignore -v .opencode/test        # → .*/ (vault already at .gitignore:59)
  # conftest.py / pytest.ini (no dot) intentionally NOT ignored — guard.sh fails them
  ```

### 2.4 `requirements.txt` — no pytest deps

```text
# testing
selenium>=4.40.0   # only testing extra — no pytest/pytest-django
```

Ensure `grep -i pytest requirements.txt` is empty (also check `requirements-dev.txt` if it exists). Never add `pytest`/`pytest-django` even to `requirements-dev.txt` — it signals endorsement.

### 2.5 Mechanical guard — `.opencode/commands/guard.sh` (single source of truth)

> **Important:** In your Django project, `.gitignore` has `.*/` which ignores hidden folders (`.opencode`, `.github`). Commit guard + workflow with `git add -f`. Absence of `pyproject.toml`/`setup.cfg` **is** the ban — don't create an empty `[tool.pytest]` config to "disable" pytest. In this vault, do not create this file — it belongs in target projects only.

Create `chmod +x .opencode/commands/guard.sh` in your Django project (4 checks — strict, no Makefile/pre-commit):

```sh
#!/bin/sh
# guard.sh — testing-contract gate (single source of truth)
# Fails if pytest is reintroduced.
set -eu
fail=0
say_fail() { echo "FAIL: $1" >&2; fail=1; }
for f in requirements.txt requirements-dev.txt; do
  if [ -f "$f" ] && grep -qi "pytest" "$f" 2>/dev/null; then say_fail "pytest found in $f"; grep -in "pytest" "$f" >&2 || true; fi
done
pip_freeze=""
for cand in "venv/bin/pip freeze" ".venv/bin/pip freeze" "pip freeze" "python -m pip freeze" "python3 -m pip freeze"; do
  if echo "$cand" | grep -q "venv/bin/pip"; then bin=$(echo "$cand" | awk '{print $1}'); if [ -x "$bin" ]; then if pip_freeze=$($bin freeze 2>/dev/null); then break; fi; fi
  elif echo "$cand" | grep -q ".venv/bin/pip"; then bin=$(echo "$cand" | awk '{print $1}'); if [ -x "$bin" ]; then if pip_freeze=$($bin freeze 2>/dev/null); then break; fi; fi
  else if pip_freeze=$(sh -c "$cand" 2>/dev/null); then break; fi; fi
done
if echo "$pip_freeze" | grep -qi "pytest" 2>/dev/null; then say_fail "pytest found in pip freeze"; echo "$pip_freeze" | grep -i "pytest" >&2 || true; fi
found_files=$(find . \( -path "./.git/*" -o -path "./.venv/*" -o -path "./venv/*" -o -path "./openspec/changes/archive/*" -o -path "./.opencode/node_modules/*" \) -prune -o \( -name "conftest.py" -o -name "pytest.ini" -o -name ".pytest.ini" \) -print 2>/dev/null || true)
if [ -n "$found_files" ]; then say_fail "banned file found (conftest.py/pytest.ini/.pytest.ini)"; echo "$found_files" >&2; fi
if [ -f "setup.cfg" ] && grep -q "\[tool:pytest" setup.cfg 2>/dev/null; then say_fail "banned [tool:pytest] in setup.cfg"; grep -n "\[tool:pytest" setup.cfg >&2 || true; fi
if [ -f "pyproject.toml" ] && grep -q "\[tool.pytest" pyproject.toml 2>/dev/null; then say_fail "banned [tool.pytest] in pyproject.toml"; grep -n "\[tool.pytest" pyproject.toml >&2 || true; fi
import_hits=$(grep -R --include="*.py" -nE "^\s*(import pytest|from pytest|@pytest\.)" --exclude-dir=.git --exclude-dir=.venv --exclude-dir=venv --exclude-dir=node_modules . 2>/dev/null | grep -v "openspec/changes/archive/" || true)
if [ -n "$import_hits" ]; then say_fail "banned pytest import/decorator in *.py"; echo "$import_hits" >&2; fi
raw_task_hits=$(grep -R -nE "python -m pytest|pytest -k|(^| )pytest( [A-Za-z0-9_/\.-]|$)" openspec/changes --include="tasks.md" 2>/dev/null | grep -v "openspec/changes/archive/" || true)
task_hits=$(echo "$raw_task_hits" | grep -v -i "banning" | grep -v -i "banned" | grep -v "grep.*pytest" | grep -v "no pytest" | grep -v "import.*pytest" | grep -v "contains no instruction" || true)
if [ -n "$task_hits" ]; then say_fail "pytest command in openspec/changes/*/tasks.md (non-archive)"; echo "$task_hits" >&2; fi
if [ "$fail" -ne 0 ]; then echo "test-contract-guard FAILED" >&2; exit 1; fi
echo "test-contract-guard OK"
```

Local (in Django project): `./.opencode/commands/guard.sh` must exit 0. Negative test: `echo 'raise' > conftest.py && ./.opencode/commands/guard.sh` → `FAIL: banned file found ./conftest.py`, then `rm conftest.py && ./.opencode/commands/guard.sh` → `OK`. Also valid for nested `myapp/conftest.py`.

### 2.6 CI — `.github/workflows/test-contract.yml` (guard only, no test run)

Create in your Django project (not in vault):

```yaml
name: test-contract
on: [push, pull_request]
jobs:
  test-contract-guard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: chmod +x .opencode/commands/guard.sh && ./.opencode/commands/guard.sh
```

> Tests run **only** locally and in prod — not in GitHub. CI runs the contract guard only.

Set branch protection: `test-contract-guard` = **required** (PR cannot merge when red). Commit with `git add -f .opencode/commands/guard.sh .github/workflows/test-contract.yml` (otherwise `.*/` ignores them). No `Makefile`/`make test` or pre-commit wrapper — canonical remains `venv/bin/python manage.py test` only (local/prod).

---

## 3. Breaking & Migration

**Breaking:** Any local workflow that relied on `pytest` will now fail the gate intentionally. This is desired — the `Missing staticfiles manifest` failures under pytest are gone only under the Django runner.

| Before | After |
|--------|-------|
| `pytest` / `pytest -k test_foo` / `python -m pytest` | `venv/bin/python manage.py test --verbosity=2` / `venv/bin/python manage.py test myapp.tests.Case.test_foo --verbosity=2` |

**Migration Plan:**
1. Merge `AGENTS.md` + `.gitignore` + CI guard **only** in one PR — tests run only locally/prod (no `manage.py test` in CI) (no DB migration, no runtime code change to existing `TestCase` suites).
2. Clean local: `rm -rf .pytest_cache conftest.py pytest.ini .pytest.ini` (if present).
3. Subsequent PRs: agents copy-pasting `pytest <path>` will get CI red; fix is `venv/bin/python manage.py test <path> --verbosity=2`.
4. Rollback: revert the 4-file change; no stateful side effects.

---

## 4. Verification (run after copying — in Django project)

```bash
venv/bin/python manage.py test --verbosity=2  # expect Ran N tests OK — admin changelist/change/add views 200 via StaticFilesStorage

./.opencode/commands/guard.sh                 # expect test-contract-guard OK

# Import/file checks (all expect empty / no file)
grep -R --include="*.py" -nE "^\s*(import pytest|from pytest|@pytest\.)" --exclude-dir=.git --exclude-dir=.venv --exclude-dir=venv . | grep -v "openspec/changes/archive/" # expect empty
ls conftest.py pytest.ini 2>&1                # expect no such file
venv/bin/pip freeze | grep -qi pytest && echo "has pytest" || echo "clean"

# .gitignore — dotfiles via .*/
touch .pytest_cache && git check-ignore -v .pytest_cache  # → .gitignore:.*/ (dotfile)
touch .pytest.ini && git check-ignore -v .pytest.ini      # → .gitignore:.*/ (dotfile)
touch .opencode/test && git check-ignore -v .opencode/test # → .gitignore:.*/ (vault .gitignore:59)
# conftest.py / pytest.ini (no dot) intentionally NOT ignored — guard FAILs them instead
rm -rf .pytest_cache                          # stale cache from previous pytest runs

# .gitignore — openspec proposals (pair defined in [django-project-setup](./django-project-setup.md) §4)
mkdir -p openspec/changes/proposal-test openspec/changes/archive
touch openspec/changes/proposal-test/proposal.md && git check-ignore -v openspec/changes/proposal-test/proposal.md  # → .gitignore:openspec/changes/* (active, ignored)
touch openspec/changes/archive/keep.md && git check-ignore openspec/changes/archive/keep.md || echo "tracked"  # → not ignored (archived, tracked)
rm -rf openspec/changes/proposal-test && rm -f openspec/changes/archive/keep.md  # clean up proofs

# Negative proof
echo 'raise AssertionError("should not be importable")' > conftest.py
./.opencode/commands/guard.sh  # → FAIL: banned file found ./conftest.py
rm conftest.py && ./.opencode/commands/guard.sh  # → OK
```

---

## 5. Why This Works

| Layer | Teaches | Proves |
|-------|---------|--------|
| `AGENTS.md` | agents/humans at session start | — |
| `openspec/specs/testing-contract/spec.md` (if you use OpenSpec) | machine-readable spec for future changes | — |
| `guard.sh` + CI | — | fails PR on any pytest reintroduction (4 checks) |

False positives avoided: import check is anchored `^\s*(import pytest|from pytest|@pytest\.)` (comment `pytest` ok), docs narrative `pytest` allowed (`--include="*.py"` only), archive `openspec/changes/archive/**` allowlisted, task lint only flags command invocations (`pytest <path>`, `python -m pytest`, `pytest -k`) not `grep -i pytest`/`banning pytest` checks.

**Risks & mitigations:**
- Agent ignores `AGENTS.md` → CI gate is hard fail (spec is machine-readable fallback).
- System `pytest` remains on dev machines → guard uses fallback chain `venv/bin/pip` → `.venv/bin/pip` → `pip` → `python -m pip` (covers venv/.venv/system).
- CI image without `venv/` → same fallback chain; missing pip still passes file/import checks.
- Future `tasks.md` re-introduces `pytest` wording → gate task lint excludes `archive/**` but hard-fails new `tasks.md`.
- Guard bypass via branch protection → `test-contract-guard` required check.
- `CI adds ~5s` → negligible (shell only).

**Non-goals:** No dual runner, no change to test semantics/DB isolation/settings logic, no coverage/parallel tooling, no porting `TestCase` suites to pytest.

---

## 6. OpenSpec — Optional Appendix

> Only if your new project uses OpenSpec. Otherwise skip this section.

- Create `openspec/specs/testing-contract/spec.md` from delta `specs/testing-contract/spec.md`
- Update `openspec/specs/admin-list-performance/spec.md` Purpose + Requirement to `during Django tests via IS_TESTING fallback` and `SHALL use IS_TESTING → StaticFilesStorage` without fixture (production whitenoise unchanged). Archive specs keep pytest language for history.
- Run `openspec status --change <name> --json` and `openspec validate <name> --strict` → `valid:true`

---

## 7. Adoption Checklist for New Projects

- [ ] Copy `AGENTS.md` Testing section (§2.1)
- [ ] Copy `<PROJECT>/settings.py` `IS_TESTING` + `STORAGES` fallback (§2.2) — both `Path`/`os.path` variants, including `private` only if used
- [ ] Add `/.venv/` to `.gitignore` (keep `.*/` + `openspec/changes/*` pair — see [django-project-setup](./django-project-setup.md) §4; verify via `git check-ignore -v .pytest_cache` and `git check-ignore -v .opencode/test`)
- [ ] Ensure `requirements.txt` has no pytest (only `selenium>=4.40.0` if needed) — `grep -i pytest` empty
- [ ] Add `guard.sh` + workflow **in Django project** (force-add with `git add -f`), set `test-contract-guard` required in branch protection
- [ ] Update project docs (`django-project-setup.md` §9 etc.) — no `pytest` run instructions in `docs/**/*.md`
- [ ] **If using OpenSpec:** create `testing-contract` spec + update `admin-list-performance` Purpose+Requirement, `openspec validate --strict` valid
- [ ] Run verification above (including negative `conftest.py` test)
- [ ] `rm -rf .pytest_cache conftest.py pytest.ini .pytest.ini` locally

---

## 8. See Also

- [Project Setup Guide](./django-project-setup.md) §7 Database & Storage + §9 Validation — scaffolding + `IS_TESTING` canonical; this contract extends it
- [DRF Implementation Guide](./django-drf.md) §13 Testing — `APITestCase` base that runs under this contract
- [Media Storage Configuration](./django-media-storage.md) — S3 storage backends referenced in `STORAGES`
- [Testing Stripe Subscriptions](./testing-stripe.md) — end-to-end lifecycle tests that run via `manage.py test` under this contract
- [Unfold Admin Theme](./django-unfold-admin.md) — admin where `StaticFilesStorage` fallback prevents manifest failures

---

## 9. Reference

- Source pattern distilled from a real project — paths use `<PROJECT>` placeholders; original change archived as `openspec/changes/archive/<date>-enforce-django-test-only`
- Guard source (in target project): `.opencode/commands/guard.sh:1`, workflow: `.github/workflows/test-contract.yml:1`
- Vault conventions: [Django Hub](./django.md) — wikilinks portability; `.*/` at vault `.gitignore:59`
