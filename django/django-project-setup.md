---
created: 2026-04-18
tags:
  - django
  - setup
  - documentation
type: resource
status: active
source: templates://django/django-project-setup.md
version: 2026-10-28+28a9c8d

---

# Project Setup Guide (Reusable Template, English Default)

> Reusable template for any Django project. Placeholders: `project` = project package, `{app_name}` = domain app. English by default (`LANGUAGE_CODE='en-us'`, `TIME_ZONE="America/Mexico_City"`). For Spanish admin, see [Spanish Django Admin](./django-i18n-es-admin.md) opt-in. Conventions: `project/admin_base.py` holds admin bases (plain flavor in [Unfold Admin Theme](./django-unfold-admin.md) §7.2; separate export flavor in excel guide §5), changelist filtering in [Admin Filters](./django-admin-filters.md), storage options in [Media Storage](./django-media-storage.md), tests canonical in [Testing Contract](./django-testing-contract.md), fixtures in [Fixtures](./django-fixtures.md), CVE/patch baseline in [Security Baseline](./django-security-baseline.md).

Follow these steps to set up a new Django project from scratch.

### 1. Add requirements.txt
Create a `requirements.txt` file in the root directory with the following dependencies:

```text
# core — PINNED. A range lets a patch day silently reintroduce a CVE; bump the
# pin explicitly and rebuild (see [Security Baseline](./django-security-baseline.md)).
Django==5.2.18             # Core web framework (LTS until 2028-04)
whitenoise==6.12.0         # Static file serving for production
gunicorn==26.2.0           # Production WSGI server
django-cors-headers==4.9.0 # CORS handling for API access
python-dotenv==1.2.4       # Environment variable management (only loader — do not add python-decouple)
certifi==2026.10.19        # CA bundle — drops the compromised emSign roots (GHSA-6q48-6c7w-9gw2)

# db
psycopg==3.3.6             # PostgreSQL database adapter

# images
pillow==13.0.0             # Image processing library

# --- optional extras (install only if the corresponding guide is adopted) ---
# drf & jwt (see [django-drf](./django-drf.md)):
# djangorestframework==3.18.3 # REST API toolkit
# django-filter==26.2        # Dynamic API filtering
# admin (see [django-unfold-admin](./django-unfold-admin.md)):
# django-unfold==0.77.1      # Modern Django admin theme (pinned — CSS selectors depend on it)
# django-solo==2.5.1         # Singleton models for configuration (only if singletons)
# storage (see [django-media-storage](./django-media-storage.md)):
# django-storages==1.14.6    # Custom storage backends (S3, etc.)
# boto3==1.35.36             # AWS SDK for Python
# testing (see [django-testing-contract](./django-testing-contract.md)):
# selenium==4.51.0           # Browser automation for E2E tests (only testing extra, never pytest)
# tools:
# requests==2.34.2           # HTTP library for external API calls
# excel export (see excel-export guide):
# openpyxl==3.1.5            # Excel xlsx with styling
# redis/celery (see redis guide):
# django-redis==6.0.0
# celery[redis]==5.6.3
# stripe (see stripe guides — worked example only):
# stripe==15.6.1
```

> **`certifi` is pinned on purpose** even though `requests` pulls it transitively: an
> unconstrained build fetches whatever CA bundle is newest (or keeps the old one in the
> base image), so the emSign fix is not applied deterministically.

### 2. Initial Commands
Run the following commands to initialize the environment and install dependencies:

```bash
# Create virtual environment
python -m venv venv

# Activate virtual environment (Linux/macOS)
source venv/bin/activate

# Activate virtual environment (Windows)
# venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Start Django project
django-admin startproject project .
```

### 3. Create Initial App
Once the project is initialized, create the main application. 

> **Important:** The `{app_name}` should **ALWAYS** be prompted/requested from the user before executing this command.

```bash
python manage.py startapp {app_name}
```

> **Models:** every model created in this project (or replicated later) must
> follow the [Model Definitions](./django-model-definitions.md) convention:
> `Meta.verbose_name`/`verbose_name_plural`, `verbose_name` on every field,
> `help_text` when needed, and a content-based `__str__`.

### 4. Git Initialization
Initialize a Git repository to track your changes and commit the initial project state.

**Rule: every new project MUST create its `.gitignore` from the block below at setup.** Agents: run it verbatim (project-specific ignores go below, clearly marked).

```bash
# Initialize git
git init

# Create .gitignore file (minimal canonical — see [django-testing-contract](./django-testing-contract.md) §2.3;
# worktree/openspec additions see [Git Worktrees](./django-worktrees.md))
cat <<EOF > .gitignore
__pycache__/
*.pyc
venv/
.venv/
*.sqlite3
testing.sqlite3
.env
.env.dev
.env.prod
!.env.example
!.env.dev.example
!.env.prod.example
/media/
staticfiles/
.*.temp
*.log
# Ignore proposals
openspec/changes/*

# Do not ignore archived proposals
!openspec/changes/archive/

# ignore by default all hidden folders (like agents folders)
.*/

# Client delivery doc (internal, not shipped)
CLIENT.md

# Docs are ignored except the worktree runbook (tracked per [django-worktrees](./django-worktrees.md))
/docs/*
!/docs/django-worktrees.md
EOF

**`.dockerignore`** — required, and it is a *correctness* rule, not only a leak guard:

```gitignore
.git
venv
.venv
.env
.env.*
media
staticfiles
*.sqlite3
testing.sqlite3
__pycache__
*.pyc
*.log
.*.temp
node_modules
docs
```

Settings call `load_dotenv(..., override=True)`, so a populated `.env.prod` copied
into the image would **beat Coolify's runtime variables**; and `SECRET_KEY`,
the database password or AWS keys must never sit in a layer. Coolify builds from a git
clone (where `.env*` is already gitignored), so this protects local
`docker build` runs — the ones that actually have the files on disk.

Caution: the `.*/` line ignores every dotfolder, so nothing under
`.opencode/` / `.github/` crosses worktrees on its own — that is why
`worktree-new.sh` hand-syncs `.opencode/skills/openspec-*` (commit the
guard with `git add -f`). The `openspec/changes/*` + `!archive/` pair is
what makes archive-only sharing possible (active proposals stay isolated
per checkout; only `archive/` is tracked).

# Add all files and commit
git add .
git commit -m "initial project"
```

### 5. Environment Infrastructure
Establish the foundation for environment-variable-first configuration by creating the following files in the project root.

The `.env` file is a **pure selector**: it contains ONLY the `ENV` variable. All other configuration (secrets, debug, hosts, DB, storage, email, AWS) lives in `.env.dev` and `.env.prod` and is duplicated per environment as required. `HOST` uses the `https://project-name.localhost` literal — a copied `.env.dev` is harmless across worktree siblings because settings resolve `PORTLESS_URL → HOST` first (see [Git Worktrees](./django-worktrees.md)).

> **Note:** If the project does not require email functionality, skip the optional email block below (moved to optional — SMTP is NOT part of core).
> **Note:** The `SECRET_KEY` must be a randomly generated string of **at least 50 characters**. Define it in BOTH `.env.dev` and `.env.prod` (the prod value is a placeholder that gets filled at deploy time). The 50-char floor is not cosmetic: Django's `security.W009` warns below it regardless of real entropy, so a shorter key leaves a permanent `check --deploy` warning nobody can act on.

**`.env`** (Environment selector — only this)
```env
ENV=dev
```

**`.env.dev`** (Local development defaults)
```env
SECRET_KEY=change-me-min-50-random-chars-0000000000000000000000
DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1,project-name.localhost
CORS_ALLOWED_ORIGINS=https://project-name.localhost
CSRF_TRUSTED_ORIGINS=https://project-name.localhost
HOST=https://project-name.localhost
DB_ENGINE=django.db.backends.postgresql
DB_NAME=
DB_USER=db_user
DB_PASSWORD=
DB_HOST=localhost
DB_PORT=5432
STORAGE_AWS=False
# Security switches. They are already implied by DEBUG=True, but the parity rule
# (§5b) requires every settings reader to exist in both env files and both .examples.
SECURE_SSL_REDIRECT=False
SESSION_COOKIE_SECURE=False
CSRF_COOKIE_SECURE=False

# --- optional blocks (uncomment only if the guide is adopted) ---
# email (optional — SMTP is NOT core):
# EMAIL_HOST=
# EMAIL_PORT=
# EMAIL_HOST_USER=
# EMAIL_HOST_PASSWORD=
# EMAIL_USE_SSL=
# EMAILS_NOTIFICATIONS=
# redis (see redis guide):
# REDIS_URL=redis://127.0.0.1:6379/0
# stripe (worked example only):
# STRIPE_SECRET_KEY=
# STRIPE_PUBLISHABLE_KEY=
# STRIPE_WEBHOOK_SECRET=
# STRIPE_API_VERSION=
# STRIPE_PRICE_ID=
# cloudflare tunnel (dev only, see tunnel guide):
# USE_X_FORWARDED_HOST=False
# USE_CLOUDFLARE_TUNNEL=False

```

**`.env.prod`** (Production-ready placeholders)
```env
SECRET_KEY=
DEBUG=False
# Never `*`, never `localhost` — Coolify's UI is the source of truth for these
# values at runtime; this file is the checklist the deployment must match.
ALLOWED_HOSTS=your-domain.com,www.your-domain.com
CORS_ALLOWED_ORIGINS=https://your-domain.com
CSRF_TRUSTED_ORIGINS=https://your-domain.com
HOST=https://your-domain.com
DB_ENGINE=django.db.backends.postgresql
DB_NAME=
DB_USER=db_user
DB_PASSWORD=
# Coolify: the DB *container* name (e.g. postgresql-abc123) and port 5432.
# Never a published 90xx port — those were the exposure fixed on 2026-10-25.
DB_HOST=
DB_PORT=5432
STORAGE_AWS=True
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_STORAGE_BUCKET_NAME=
AWS_PROJECT_FOLDER=
AWS_S3_REGION_NAME=
AWS_S3_ENDPOINT_URL=
AWS_S3_CUSTOM_DOMAIN=
# Security switches — editable from the Coolify UI. The defaults in settings.py
# are already prod-safe when DEBUG=False; these make the intent explicit.
SECURE_SSL_REDIRECT=True
SESSION_COOKIE_SECURE=True
CSRF_COOKIE_SECURE=True

```

### 5b. Env lifecycle rule (atomic — no drift, no leaks)

Any add / rename / delete of `os.getenv("X")` / `os.environ.get("X")` / `os.environ["X"]` in `project/settings.py` MUST update `.env.dev.example` + `.env.prod.example` in the same change. Delete removes the key from both `.example`s. Rename = add + delete. Literals only — dynamic `os.getenv(name)` is banned.

`.example` derivation: copy the key structure from `.env.dev` / `.env.prod`, replace every value with empty or placeholder (`SECRET_KEY=change-me-min-50-random-chars-0000000000000000000000`, URLs `https://<...>.localhost`, tokens `sk_test_placeholder`). Never copy a real credential. Strict parity: every `settings.py` key MUST exist in both `.example`s (empty if unused in that env — e.g. copy the full AWS block into `.env.dev.example` with empty values when `STORAGE_AWS=False`). Commented `# OPTIONAL` blocks stay commented in `.example` until the guide is adopted (uncommenting = adoption, then the key becomes required in both files). Denylist (fail): `sk_live_`, `AKIA`, `BEGIN PRIVATE`; allowlist: `change-me`, `placeholder`, `<...>`, empty. Verify: `grep -R "sk_live_\|AKIA\|BEGIN PRIVATE" .env.*.example` must be empty.

**`check_env` management command** (copy into target projects — stdlib only). Replace `project` below with your real project package. Assumes `<APP_LABEL>` is top-level (so `parents[3]` is the repo root); adapt if apps live under `apps/`. Compares literal `os.getenv` / `os.environ.get` keys in `project/settings.py` against both `.example` files. Fails on: code key missing from either `.example`, `.example` key with no reader (stale, ignoring still-commented optionals), denylist hit.

```python
# <APP_LABEL>/management/commands/check_env.py
import re
from pathlib import Path
from django.core.management.base import BaseCommand, CommandError

DENY = re.compile(r"sk_(?:live|test)_|AKIA|BEGIN PRIVATE|xoxb-")
READER = re.compile(r'os\.(?:getenv|environ\.get)\(\s*["\']([A-Z_][A-Z0-9_]*)["\']')
SUBSCRIPT = re.compile(r'os\.environ\[\s*["\']([A-Z_][A-Z0-9_]*)["\']\s*\]')

class Command(BaseCommand):
    help = "Fail if settings env readers drift from .env.*.example (no real values)."

    def handle(self, *args, **opts):
        base = Path(__file__).resolve().parents[3]
        settings_src = (base / "project" / "settings.py").read_text()
        code = set(READER.findall(settings_src)) | set(SUBSCRIPT.findall(settings_src)) - {"ENV"}
        failures = []
        for example in (".env.dev.example", ".env.prod.example"):
            p = base / example
            if not p.exists():
                failures.append(f"missing {example}")
                continue
            keys = set()
            for line in p.read_text().splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                keys.add(line.split("=")[0].strip())
            for k in sorted(code - keys):
                failures.append(f"{example}: missing {k}")
            for k in sorted(keys - code):
                failures.append(f"{example}: stale {k}")
            if DENY.search(p.read_text()):
                failures.append(f"{example}: denylist hit (real secret?)")
        if failures:
            raise CommandError("\n".join(failures))
        self.stdout.write("check_env OK")
```

Wire: run `python manage.py check_env` after `check` locally; CI `env-contract-guard` job runs it (required check, mirrors `test-contract-guard` — extend the same workflow file):

```yaml
# .github/workflows/test-contract.yml — add second job
jobs:
  env-contract-guard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - run: python manage.py check_env
``` Verify: add `os.getenv("NEW_KEY")` without `.example` → fails `missing`; remove reader, leave `.example` → fails `stale`; put `sk_live_<fake>` in `.example` → fails `denylist`.

**`check_prod_security` management command** (copy into target projects — stdlib + Django only). `check_env` guards *env parity*; this one guards *production values*. It is intentional that it is **not** wired at import time and **not** run in CI: it needs the real production environment, and a boot-time raise would break image builds (where secrets are absent) and the `env-contract-guard` job.

```python
# <APP_LABEL>/management/commands/check_prod_security.py
from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

BAD_HOSTS = {"*", ""}
DEV_HOSTS = {"localhost", "127.0.0.1", "0.0.0.0"}


class Command(BaseCommand):
    help = "Fail when production settings are dev-unsafe. Run it inside the container."

    def handle(self, *args, **opts):
        failures, warnings = [], []
        if settings.DEBUG:
            failures.append("DEBUG is True in production")
        if len(settings.SECRET_KEY or "") < 50:
            failures.append("SECRET_KEY is missing or shorter than 50 chars")

        hosts = settings.ALLOWED_HOSTS
        if BAD_HOSTS.intersection(hosts):
            failures.append(f"ALLOWED_HOSTS contains a wildcard/empty entry: {hosts}")
        warnings += [f"ALLOWED_HOSTS dev entry: {h}" for h in hosts if h in DEV_HOSTS]

        for name in ("CSRF_TRUSTED_ORIGINS", "CORS_ALLOWED_ORIGINS"):
            for origin in getattr(settings, name, []):
                if not origin.startswith("https://"):
                    failures.append(f"{name} has a non-https origin: {origin}")

        for warning in warnings:
            self.stderr.write(f"WARN: {warning}")
        if failures:
            raise CommandError("\n".join(failures))
        self.stdout.write("check_prod_security OK")
```

Run it **inside the container** (or with `.env.prod` loaded), never in CI. It runs
unconditionally — there is deliberately no "skip if ENV=dev" escape hatch, because a
deployment that lost `ENV=prod` would then skip the check silently. In dev it fails by
design (`DEBUG=True`), which is exactly why it does not belong in CI. It is also the only
place the `SECRET_KEY` length is enforced; settings stay importable with an empty key so
image builds and `check_env` keep working.

### 6. Core Settings & App Integration
Refactor `project/settings.py` to initialize `python-dotenv`, load environment files, and register apps/middleware.

**Initialize Dotenv at the top of `settings.py`:**
```python
import os
from pathlib import Path
from urllib.parse import urlparse
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent

# Load .env first to get ENV value
load_dotenv(BASE_DIR / '.env')
ENV = os.getenv('ENV', 'dev')

# Load environment-specific file (override=True so project config wins over shell-injected vars)
load_dotenv(BASE_DIR / f'.env.{ENV}', override=True)

# SECURITY WARNING: keep the secret key used in production secret!
SECRET_KEY = os.getenv("SECRET_KEY")

# SECURITY WARNING: don't run with debug turned on in production!
# Compare case-insensitively: `DEBUG=true` under a literal `== "True"` silently
# means False — the same trap that kept `STORAGE_AWS=true` from reaching S3.
DEBUG = os.getenv("DEBUG", "False").strip().lower() == "true"

ALLOWED_HOSTS = [h.strip() for h in os.getenv("ALLOWED_HOSTS", "").split(",") if h.strip()]

# Worktree dev loop: portless injects PORTLESS_URL per checkout, so a copied
# .env.dev resolves each sibling's own domain without edits (see [django-worktrees](./django-worktrees.md)).
HOST = (os.getenv("PORTLESS_URL", "") or os.getenv("HOST", "")).rstrip("/")

# --- Security hardening ---------------------------------------------------
# Values live in env vars (editable from the Coolify UI); the defaults are
# prod-safe because DEBUG=False flips all of them on.
#
# SECURE_PROXY_SSL_HEADER is mandatory behind Traefik/Coolify: the proxy
# terminates TLS and sets X-Forwarded-Proto, and without this header
# request.is_secure() is False, so SECURE_SSL_REDIRECT becomes a redirect loop.
# It requires a proxy that sets the header — on a direct-gunicorn deployment,
# set SECURE_SSL_REDIRECT=False instead.
#
# HSTS is NOT configured here: the proxy already sends it. Two sources would
# mean two policies (this is why fastjob had to set its own HSTS to 0).
SECURE_SSL_REDIRECT = os.getenv("SECURE_SSL_REDIRECT", str(not DEBUG)).strip().lower() == "true"
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SESSION_COOKIE_SECURE = os.getenv("SESSION_COOKIE_SECURE", str(not DEBUG)).strip().lower() == "true"
CSRF_COOKIE_SECURE = os.getenv("CSRF_COOKIE_SECURE", str(not DEBUG)).strip().lower() == "true"
```

> In dev, each checkout also accepts its own portless domain into
> `ALLOWED_HOSTS`/`CORS`/`CSRF` from the resolved `HOST` — full block in
> [Local Development & Subdomain Setup](./django-local-subdomain-setup.md) Step 1
> (required when [Git Worktrees](./django-worktrees.md) siblings are used).

**Update `INSTALLED_APPS` and `MIDDLEWARE`:**
```python
INSTALLED_APPS = [
    "unfold",  # only if [django-unfold-admin](./django-unfold-admin.md) adopted — must be before django.contrib.admin
    "unfold.contrib.filters",  # optional unfold extras
    "unfold.contrib.forms",
    "unfold.contrib.inlines",
    # ... your apps
    "django.contrib.admin",
    "django.contrib.auth",
    "corsheaders",  # core
    # "rest_framework",  # DRF-only (see [django-drf](./django-drf.md))
    # "rest_framework.authtoken",  # DRF Token auth only
    # "solo",  # only if singletons
    # "storages",  # only if [django-media-storage](./django-media-storage.md) adopted
    # "{app_name}",  # your domain app from Step 3
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    # ... default middleware (keep order: Security, Session, Common, Csrf, Auth, Messages, Clickjacking; CorsMiddleware first, WhiteNoise right after SecurityMiddleware)
    "whitenoise.middleware.WhiteNoiseMiddleware",
]
```
- Add your local application `{app_name}` to `INSTALLED_APPS`.
- **Admin Theme:** The project uses [Django Unfold](./django-unfold-admin.md) for a modern admin interface (optional but recommended).

### 7. Database & Storage Strategy
Implement dynamic logic in `settings.py` to switch backends based on the environment. Canonical storage block lives in [Media Storage Configuration](./django-media-storage.md) — do not duplicate it here; the snippet below is the minimal core shape (local + IS_TESTING fallback, see [django-testing-contract](./django-testing-contract.md) §2.2).

**Dynamic Database Selection:**
```python
import sys
IS_TESTING = len(sys.argv) > 1 and sys.argv[1] == "test"

if IS_TESTING:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": os.path.join(BASE_DIR, "testing.sqlite3"),
        }
    }
else:
    options = {}
    if os.environ.get("DB_ENGINE") == "django.db.backends.mysql":
        options = {
            "init_command": "SET sql_mode='STRICT_TRANS_TABLES'",
            "charset": "utf8mb4",
        }
    
    DATABASES = {
        "default": {
            "ENGINE": os.environ.get("DB_ENGINE", "django.db.backends.sqlite3"),
            "NAME": os.environ.get("DB_NAME", os.path.join(BASE_DIR, "db.sqlite3")),
            "USER": os.environ.get("DB_USER", ""),
            "PASSWORD": os.environ.get("DB_PASSWORD", ""),
            "HOST": os.environ.get("DB_HOST", "localhost"),
            "PORT": os.environ.get("DB_PORT", ""),
            "OPTIONS": options,
        }
    }
```

**Internationalization:**
> **Note:** Prompt the user for their preferred time zone. Default is `America/Mexico_City`.

```python
LANGUAGE_CODE = 'en-us'
TIME_ZONE = "America/Mexico_City"
USE_I18N = True
USE_TZ = True
```

**Static & Media Management:**
```python
STATIC_URL = 'static/'
MEDIA_URL = "/media/"

STATICFILES_DIRS = [
    BASE_DIR / "static",
]
STATIC_ROOT = os.path.join(BASE_DIR, "staticfiles")
MEDIA_ROOT = os.path.join(BASE_DIR, "media")
```

**Conditional Storage (AWS S3 vs Local):**
> Full storage configuration details are available in the
> [Media Storage Configuration](./django-media-storage.md) guide.
```python
STORAGE_AWS = os.getenv("STORAGE_AWS", "").strip().lower() == "true"

if STORAGE_AWS:
    # AWS S3 Configuration
    AWS_ACCESS_KEY_ID = os.getenv("AWS_ACCESS_KEY_ID")
    AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY")
    AWS_STORAGE_BUCKET_NAME = os.getenv("AWS_STORAGE_BUCKET_NAME")
    AWS_S3_REGION_NAME = os.getenv("AWS_S3_REGION_NAME")
    AWS_S3_ENDPOINT_URL = os.getenv("AWS_S3_ENDPOINT_URL")
    # Guard the empty case: without it the keys become "None/static/...".
    # This variable must also be a build ARG or collectstatic never sees it (§14).
    _folder = os.getenv("AWS_PROJECT_FOLDER", "")
    AWS_PROJECT_FOLDER = _folder

    # Folder isolation inside the shared bucket
    STATIC_LOCATION = f"{_folder}/static" if _folder else "static"
    PUBLIC_MEDIA_LOCATION = f"{_folder}/media" if _folder else "media"
    PRIVATE_MEDIA_LOCATION = f"{_folder}/private" if _folder else "private"

    STORAGES = {
        "default": {
            "BACKEND": "project.storage_backends.PublicMediaStorage",
        },
        "staticfiles": {
            "BACKEND": "project.storage_backends.StaticStorage",
        },
        "private": {
            "BACKEND": "project.storage_backends.PrivateMediaStorage",
        },
    }
else:
    # Local Storage Configuration — IS_TESTING fallback avoids Whitenoise manifest during `manage.py test`
    # See [django-testing-contract](./django-testing-contract.md) §2.2 for the full contract (both Path/os.path variants)
    staticfiles_backend = "django.contrib.staticfiles.storage.StaticFilesStorage" if IS_TESTING else "whitenoise.storage.CompressedManifestStaticFilesStorage"
    STORAGES = {
        "default": {
            "BACKEND": "django.core.files.storage.FileSystemStorage",
        },
        "staticfiles": {
            "BACKEND": staticfiles_backend,
        },
        # only if you use private media — otherwise omit this key; Path variant: MEDIA_ROOT / "private-media"
        "private": {
            "BACKEND": "django.core.files.storage.FileSystemStorage",
            "OPTIONS": {
                "location": os.path.join(MEDIA_ROOT, "private-media"),
            },
        },
    }
```

### 8. Security, API & Email Configuration
Finalize the configuration with security headers and DRF defaults. Email SMTP is OPTIONAL (not core) — see the optional email block in Step 5.

> **Note:** Prompt the user to confirm if the project needs to send emails. If emails are not required, skip this subsection entirely.

**CORS & CSRF Configuration:**
```python
cors_allowed = os.getenv("CORS_ALLOWED_ORIGINS")
if cors_allowed and cors_allowed != "None":
    CORS_ALLOWED_ORIGINS = [
        origin.strip().rstrip("/") for origin in cors_allowed.split(",") if origin.strip()
    ]

csrf_trusted = os.getenv("CSRF_TRUSTED_ORIGINS")
if csrf_trusted and csrf_trusted != "None":
    CSRF_TRUSTED_ORIGINS = [
        origin.strip().rstrip("/") for origin in csrf_trusted.split(",") if origin.strip()
    ]
```

> Origins are **scheme + host** pairs, not bare domains: `http://` and `https://` of the same
> domain are different entries. Production must be all-`https` (a leftover `http://` entry is
> dead weight, and 14 `localhost` entries were removed from the production apps on 2026-10-23).

**Login redirects:**
```python
# Django's default is /accounts/profile/, which no project implements → 404
# after opening /admin/login/ without ?next=. This bug hit 9 projects in 2026-10.
LOGIN_REDIRECT_URL = "/admin/"
LOGOUT_REDIRECT_URL = "/admin/"
```

**Django REST Framework Setup:**
```python
REST_FRAMEWORK = {
    "DEFAULT_PERMISSION_CLASSES": ("rest_framework.permissions.IsAuthenticated",),
    "DEFAULT_PAGINATION_CLASS": "project.pagination.CustomPageNumberPagination",
    "PAGE_SIZE": 12,
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework.authentication.TokenAuthentication",
        "rest_framework.authentication.SessionAuthentication",
    ),
    "EXCEPTION_HANDLER": "project.handlers.custom_exception_handler",
}
```

**Global DateTime Formatting:**

```python
DATE_FORMAT = "d/m/Y"
TIME_FORMAT = "H:i"
DATETIME_FORMAT = f"{DATE_FORMAT} {TIME_FORMAT}"
```

**Email SMTP Configuration (OPTIONAL — not core):**
> **Note:** Skip this subsection if the project does not require email functionality. Uncomment the email env block in Step 5 first.

```python
EMAIL_BACKEND = "django.core.mail.backends.smtp.EmailBackend"
EMAIL_HOST = os.getenv("EMAIL_HOST")
EMAIL_PORT = os.getenv("EMAIL_PORT")
EMAIL_HOST_USER = os.getenv("EMAIL_HOST_USER")
EMAIL_HOST_PASSWORD = os.getenv("EMAIL_HOST_PASSWORD")
EMAIL_USE_SSL = os.getenv("EMAIL_USE_SSL", "").strip().lower() == "true"
EMAIL_FROM = EMAIL_HOST_USER
EMAILS_NOTIFICATIONS = os.getenv("EMAILS_NOTIFICATIONS", "").split(",")
```

**Test overrides (MUST be the last block of `settings.py`):**
```python
# The Django test client speaks plain HTTP: the production HTTPS redirect turns
# every request into a 301 and Secure cookies cannot be set at all. Because the
# security block in §6 assigns these earlier, this override only works at the END
# of the file — putting it anywhere else silently does nothing.
# ALLOWED_HOSTS comes from the environment, so the client hosts are added here.
if IS_TESTING:
    SECURE_SSL_REDIRECT = False
    SESSION_COOKIE_SECURE = False
    CSRF_COOKIE_SECURE = False
    for _test_host in ("localhost", "127.0.0.1", "testserver"):
        if _test_host not in ALLOWED_HOSTS:
            ALLOWED_HOSTS.append(_test_host)
```

### 9. Validation
Verify the project configuration and ensure that the test environment is correctly isolated. Canonical runner is `python manage.py test` (see [django-testing-contract](./django-testing-contract.md) — do not use `pytest`).

```bash
# Verify the complete configuration
python manage.py check

# Verify env readers match .env.*.example (see §5b)
python manage.py check_env

# Production values only — run it INSIDE the container (or with .env.prod loaded).
# It fails by design on dev settings, so it must never be part of CI.
python manage.py check_prod_security

# Deploy checks — meaningful ONLY with production settings. With ENV=dev/DEBUG=True
# it always reports W008/W012/W016; that is expected, not a defect.
python manage.py check --deploy

# Migrations must be fully applied after `migrate` (never at build time)
python manage.py showmigrations --plan | grep '\[ \]'   # expect empty

# Run tests to ensure test-specific database isolation (canonical — see [django-testing-contract](./django-testing-contract.md))
python manage.py test --verbosity=2
```

**Expected `check --deploy` output** — everything else must be silent:

| Warning | Why it stays |
|---|---|
| `security.W004` | HSTS is sent by Traefik. Django cannot know it. **Do not** set `SECURE_HSTS_SECONDS` in Django — two sources would publish two policies (fastjob had to zero its own for this reason). |
| `security.W009` | Must **not** appear in production: the 50-char rule in §5 guarantees it. If it does, fix the key — do not silence it. Locally it is only a reminder. |
| `security.W019` | Only if the project overrides `X_FRAME_OPTIONS`; the proxy already sends `DENY`. |
| `staticfiles.W004` | `STATICFILES_DIRS` points at a folder that does not exist. This one is real — create the folder or delete the entry. |

### 10. Required Project Wiring
These files are essential for the infrastructure and global behaviors defined in `settings.py`.

#### project/urls.py
Global URL configuration featuring DRF router, root redirects, and static/media file serving.
```python
import project.admin  # required: `project` is not in INSTALLED_APPS, so Django does not auto-discover its admin module; without this import the custom UserAdmin/GroupAdmin/TokenAdmin are silently ignored

from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from django.views.generic import RedirectView
from rest_framework import routers

# Initialize DRF Router
router = routers.DefaultRouter()

urlpatterns = [
    # Admin Interface
    path("admin/", admin.site.urls),
    
    # Root Redirect to Admin
    path("", RedirectView.as_view(url="/admin/"), name="home-redirect-admin"),
    
    # API Endpoints
    path("api/", include(router.urls)),
]

# Serve Media Files in Development
urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
```

#### project/pagination.py
Custom pagination logic for metadata-rich API responses.
```python
from rest_framework.pagination import PageNumberPagination
from rest_framework.response import Response

class CustomPageNumberPagination(PageNumberPagination):
    page_size = 12
    page_size_query_param = 'page_size'
    max_page_size = 100

    def get_paginated_response(self, data):
        return Response({
            'count': self.page.paginator.count,
            'next': self.get_next_link(),
            'previous': self.get_previous_link(),
            'page': self.page.number,
            'page_size': self.get_page_size(self.request),
            'total_pages': self.page.paginator.num_pages,
            'results': data
        })
```

#### project/storage_backends.py
Defines custom storage backends for S3 integration.
```python
from django.conf import settings
from storages.backends.s3boto3 import S3Boto3Storage

class StaticStorage(S3Boto3Storage):
    """Handles static files (CSS, JS, images)."""
    location = settings.STATIC_LOCATION
    default_acl = "public-read"

class PublicMediaStorage(S3Boto3Storage):
    """Handles public uploads."""
    location = settings.PUBLIC_MEDIA_LOCATION
    default_acl = "public-read"
    file_overwrite = False

class PrivateMediaStorage(S3Boto3Storage):
    """Handles sensitive files."""
    location = settings.PRIVATE_MEDIA_LOCATION
    default_acl = "private"
    file_overwrite = False
    custom_domain = False
```

#### project/handlers.py
Custom exception handler for standardized API error responses.
```python
from rest_framework.views import exception_handler

def custom_exception_handler(exc, context):
    response = exception_handler(exc, context)

    if response is not None:
        original_data = response.data
        response.data = {}
        response.data['status'] = "error"
        details = original_data.get('detail', None)
        if details:
            del original_data['detail']
            response.data['message'] = str(details)
        else:
            response.data['message'] = "Invalid data"
        response.data['data'] = original_data
            
    return response
```

#### project/admin.py
Customizes the Django Admin for User and Group models using Unfold's components. Admin bases live canonically in `project/admin_base.py::ModelAdminUnfoldBase` (see [Unfold Admin Theme](./django-unfold-admin.md) §7.2) — do not redefine the base here.

The full `UserAdmin`/`GroupAdmin`/`TokenAdmin` code lives in the
[Unfold Admin Theme](./django-unfold-admin.md) guide (§7.1), which also documents
the required `import project.admin` in `urls.py`. Keep it there — this guide
does not duplicate it.

> **DRF-only**: `TokenAdmin` / `TokenProxy` (from `rest_framework.authtoken`) are only required if the project uses DRF's `TokenAuthentication`. If not using DRF, omit those imports, the `unregister(TokenProxy)` call, and the `TokenAdmin` class.

#### project/admin_base.py
Plain-flavor `ModelAdminUnfoldBase` (+ `edit` row action). Canonical plain definition in [django-unfold-admin](./django-unfold-admin.md) §7.2. NOTE: the excel-export guide defines its own export flavor (same name + `export_selected` bulk actions) — intentional separate flavor, not an import.

#### project/templates/admin/base_site.html
Customizes the Django Unfold admin theme. Canonical override is `project/templates/admin/base_site.html` extending `"admin/base.html"` — never extend `unfold/layouts/base.html` directly and never use `base.html` as the override name (see [django-unfold-admin](./django-unfold-admin.md) §6).
```html
{% extends "admin/base.html" %}
{% load static %}

{% block extrahead %}
{{ block.super }}
<!-- Load markdown libraries -->
<link rel="stylesheet" href="https://cdn.jsdelivr.net/simplemde/latest/simplemde.min.css" />
<link rel="stylesheet" href="{% static 'css/style.css' %}" />
<script src="https://cdn.jsdelivr.net/simplemde/latest/simplemde.min.js"></script>

<!-- Load Unfold custom scripts -->
<script src="{% static 'js/load_markdown.js' %}"></script>
{% endblock %}
```

### 11. Optional Reusable Utilities
Standalone helpers that can be imported by any app to extend functionality.

#### utils/admin_helpers.py
Logic for validating admin and support group permissions.
```python
from django.contrib.auth.models import User

def is_user_admin(user: User):
    user_grups = user.groups.all()
    user_in_admin_group = False
    for group in user_grups:
        if group.name in ["admins", "supports"]:
            user_in_admin_group = True
            break
    return user_in_admin_group or user.is_superuser
```

#### utils/automation.py
Selenium-based web automation and element selection helpers.
```python
from selenium import webdriver
from selenium.webdriver.remote.webelement import WebElement
from selenium.webdriver.common.by import By

def get_selenium_elems(driver: webdriver, selectors: dict) -> dict[str, WebElement]:
    fields = {}
    for key, value in selectors.items():
        try:
            fields[key] = driver.find_element(By.CSS_SELECTOR, value)
        except Exception:
            fields[key] = None
    return fields
```

#### utils/media.py
Image processing and media URL resolution helpers. `get_test_image` requires a committed `media/test.webp` fixture.
```python
import os
from django.conf import settings
from django.core.files.uploadedfile import SimpleUploadedFile

def get_media_url(object_or_url: object) -> str:
    url_str = ""
    if type(object_or_url) is str:
        url_str = object_or_url
    else:
        url_str = object_or_url.url

    if "s3.amazonaws.com" not in url_str and "digitaloceanspaces" not in url_str:
        host = getattr(settings, "HOST", None)
        if not host:
            return url_str
        if "://" not in host:
            return url_str
        return f"{host}{url_str}"
    return url_str

def get_test_image(image_name: str = "test.webp") -> SimpleUploadedFile:
    app_path = os.path.dirname(os.path.abspath(__file__))
    project_path = os.path.dirname(app_path)
    media_path = os.path.join(project_path, "media")

    image_path = os.path.join(media_path, image_name)
    with open(image_path, "rb") as f:
        content = f.read()
    image_file = SimpleUploadedFile(
        name=image_name,
        content=content,
        content_type="image/webp",
    )
    return image_file
```

#### static/js/ Custom Scripts
The project includes several dynamic scripts in `static/js/`.

**static/js/copy_clipboard.js**
Utility for click-to-copy on elements carrying a `data-copy-url` attribute (e.g. the admin copy-link buttons). Full implementation in [Image Copy Link](./django-image-copy-link.md) — per-model JS is loaded via `Admin.Media`, not globally in `base_site.html`.
```javascript
// See [django-image-copy-link](./django-image-copy-link.md) for the full file.
```

**static/js/script.js**
General-purpose logic.
```javascript
// Add custom project-wide JavaScript here
```

#### Other Required Files
- **static/css/style.css**: Create an empty file for custom CSS.
- **static/logo.webp** and **static/favicon.png**: Add your project's logo and favicon. 
  > **Note:** Prompt the user to check if they have specific logo and favicon files to use, or if they would like to create placeholders or new ones now.
- **media/**: Create an empty directory in the root for local file uploads.

### 12. Database Initialization
Prepare and apply the initial database migrations, then create an administrative user.

```bash
# Create migration files for all apps
python manage.py makemigrations

# Apply migrations to the database
python manage.py migrate

# Create an administrative user
# Note: You will be prompted to enter a username, email, and password.
python manage.py createsuperuser
```

### 13. OpenSpec Setup (Gemini CLI) — OPTIONAL
Initialize and configure OpenSpec to manage project context and change proposals with Gemini CLI.

```bash
openspec init
```

After initialization, run the following command in Gemini CLI to populate your project context:

> "Please read openspec/project.md and help me fill it out with details about my project, tech stack, and conventions"

> Worktree rule: active proposals under `openspec/changes/*` stay isolated per
> sibling (only `openspec/changes/archive/` is tracked and copied back on merge).
> Full rule + `.opencode` skills sync → see [Git Worktrees](./django-worktrees.md).

### 14. Deployment (Coolify / Docker)
The project is configured for containerized deployment using Docker, targeting Coolify. Only core vars are passed as build args below — add optional blocks (email, redis, stripe) only if adopted.

#### Dockerfile
The `Dockerfile` defines the environment, installs dependencies, and prepares the application for production.

```dockerfile
# Python 3.12 — same minor as every deployed Django project (parity over novelty).
# The *patch* level (e.g. 3.12.15) comes from this tag: docker-library builds
# CPython, so `apt upgrade` cannot bump it. Re-pull the base on patch days.
FROM python:3.12-slim

# Debian security updates — the floating base tag lags behind *-security.
# This is the OS half of the CVE baseline; without it a new build ships the
# 17-32 pending packages the 2026-10 audit found in existing images.
RUN apt-get update && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*

# Set environment variables for Python
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Set the working directory in the container
WORKDIR /app

# Copy the current directory contents into the container
COPY . /app/

# Ensure start script is executable
RUN chmod +x /app/start.sh

# Build-time ARGs. Only what `collectstatic` genuinely needs is declared here:
# everything else (SECRET_KEY, DB_*, CORS/CSRF, DEBUG, ALLOWED_HOSTS) belongs
# to the runtime and comes from Coolify's environment, NOT the image.
ARG STORAGE_AWS=False
ARG AWS_ACCESS_KEY_ID
ARG AWS_SECRET_ACCESS_KEY
ARG AWS_STORAGE_BUCKET_NAME
ARG AWS_S3_REGION_NAME
ARG AWS_S3_ENDPOINT_URL
ARG AWS_S3_CUSTOM_DOMAIN
ARG AWS_PROJECT_FOLDER

# Install system dependencies (e.g., for PostgreSQL support)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev gcc \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies (pinned in requirements.txt — do not upgrade
# pip/setuptools/wheel here: that reintroduces unversioned build tooling)
RUN pip install --no-cache-dir -r requirements.txt

# Collect static files. Values are scoped to this single layer on purpose:
#   - a throwaway SECRET_KEY keeps settings importable without baking the real one;
#   - DEBUG=False makes the image build behave like production;
#   - storage vars must be visible HERE or collectstatic writes locally and the
#     CDN/S3 copy silently never updates (2026-10 CVE tracker, gap #3).
RUN SECRET_KEY=change-me-build-only-000000000000000000000000000000 \
    DEBUG=False \
    STORAGE_AWS=${STORAGE_AWS} \
    AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
    AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
    AWS_STORAGE_BUCKET_NAME=${AWS_STORAGE_BUCKET_NAME} \
    AWS_S3_REGION_NAME=${AWS_S3_REGION_NAME} \
    AWS_S3_ENDPOINT_URL=${AWS_S3_ENDPOINT_URL} \
    AWS_S3_CUSTOM_DOMAIN=${AWS_S3_CUSTOM_DOMAIN} \
    AWS_PROJECT_FOLDER=${AWS_PROJECT_FOLDER} \
    python manage.py collectstatic --noinput

# Expose the port that Django/Gunicorn will run on
EXPOSE 80

# Command to run the start script
CMD ["./start.sh"]
```

> **No security ARG is needed.** The block in §6 reads its variables at request
> time and defaults to the safe value when they are absent, which is exactly why
> it can be adopted without touching the build.

**Runtime variables (Coolify UI → Environment, NOT build args).** Nothing else is
baked into the image, so the container only works if these exist at runtime:

| Variable | Value in production |
|---|---|
| `SECRET_KEY` | ≥50 random chars (same value as the local `.env.prod`) |
| `DEBUG` | `False` |
| `ENV` | `prod` (the `.env` selector is excluded by `.dockerignore`, so this cannot be read from a file) |
| `ALLOWED_HOSTS` | your real domains — never `*`, never `localhost` |
| `CORS_ALLOWED_ORIGINS` / `CSRF_TRUSTED_ORIGINS` | `https://…` only |
| `DB_*` | container name + `5432` (see §5) |
| `SECURE_SSL_REDIRECT`, `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE` | `True` (optional — the defaults are already safe when `DEBUG=False`) |

**Storage variables need both scopes.** `STORAGE_AWS`, `AWS_*` and
`AWS_PROJECT_FOLDER` are declared as `ARG` for the build **and** read again at
runtime by `settings.py`/`django-storages`. If they exist only as build args,
uploads silently land on the container filesystem and disappear on the next
deploy.

#### start.sh
The `start.sh` script handles database migrations and starts the Gunicorn server.

```bash
#!/bin/sh

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Running migrations..."
# Validate that migrations are committed (fail loudly if any are missing).
# Run `makemigrations` locally before building the image and commit the files.
python manage.py makemigrations --check --noinput
python manage.py migrate --noinput

# Base data (reference/lookup rows) is required for the system to work.
# NOTE: base_loaddata exists only if [Fixtures](./django-fixtures.md) is adopted
# (loader lives in <MAIN_APP>/management/commands/). Do NOT run seed_loaddata
# here — it is environment-specific and should be loaded once manually.
# python manage.py base_loaddata

echo "Starting Gunicorn..."
exec gunicorn --bind 0.0.0.0:80 project.wsgi:application
```
