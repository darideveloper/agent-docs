---
created: 2026-05-02
updated: 2026-09-17
tags:
  - django
  - dev-ops
  - portless
  - tmux
  - documentation
type: resource
status: active
source: templates://django/django-local-subdomain-setup.md
version: 2026-09-17+unreleased

---

# Unified Local Development & Subdomain Setup (Optional)

This document describes how to implement a unified development script (`dev.sh`) that uses `tmux` and `portless` to provide a seamless, port-free local development environment with subdomains.

## 🚀 Overview

The goal is to start all project services (Django, Celery, Frontend, Proxies) with a single command and access the application via a persistent, secure URL like `https://project-name.localhost`.

## 📦 Prerequisites

Ensure the following are installed on the development machine:
- **`tmux`**: Terminal multiplexer for managing background processes.
- **`portless`**: Manages local proxying and TLS trust.
- **`python-dotenv`**: For managing environment-based settings in Django (only loader — see [[django-project-setup|Project Setup]]).

---

## 🛠️ Step 1: Django Configuration

To allow traffic from the portless subdomain, update `settings.py`. These settings should strictly read from environment variables.

### `project/settings.py`

```python
import os
from urllib.parse import urlparse

# ALLOWED_HOSTS must include the portless domain
ALLOWED_HOSTS = os.getenv("ALLOWED_HOSTS", "").split(",")

# Worktree dev loop: portless injects PORTLESS_URL per checkout, so a copied
# .env.dev resolves each sibling's own domain without edits.
HOST = (os.getenv("PORTLESS_URL", "") or os.getenv("HOST", "")).rstrip("/")

# CORS & CSRF Configuration
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

# Worktree dev loop: a copied .env.dev must work in any sibling, so in dev
# accept this checkout's own portless domain (already resolved into HOST).
if DEBUG and HOST:
    _dev_host = urlparse(HOST).hostname or ""
    if _dev_host and _dev_host not in ALLOWED_HOSTS:
        ALLOWED_HOSTS.append(_dev_host)
    if _dev_host.endswith(".localhost") and ".localhost" not in ALLOWED_HOSTS:
        ALLOWED_HOSTS.append(".localhost")
    if "CORS_ALLOWED_ORIGINS" in globals() and HOST not in CORS_ALLOWED_ORIGINS:
        CORS_ALLOWED_ORIGINS.append(HOST)
    if "CSRF_TRUSTED_ORIGINS" in globals() and HOST not in CSRF_TRUSTED_ORIGINS:
        CSRF_TRUSTED_ORIGINS.append(HOST)
```

---

## ⚙️ Step 2: Environment Variables

Update `.env.dev` to provide the correct defaults for team members. (`.env` only carries `ENV=dev`; all per-environment config — including the `localhost` subdomain hosts — lives in `.env.dev` / `.env.prod`.)

```env
# Merged with [[django-project-setup]] §5 — keep localhost entries and append the subdomain.
ALLOWED_HOSTS=localhost,127.0.0.1,project-name.localhost
CORS_ALLOWED_ORIGINS=https://project-name.localhost
CSRF_TRUSTED_ORIGINS=https://project-name.localhost
HOST=https://project-name.localhost
```

> A copied `.env.dev` keeps main's `HOST` — harmless: settings resolve
> `PORTLESS_URL → HOST` first, so each sibling (see [[django-worktrees|Git Worktrees]])
> accepts its own `https://<project>-<branch>.localhost` domain in dev.

---

## 📜 Step 3: The Unified `dev.sh` Script

Create a `dev.sh` file in the project root. This script handles `portless` initialization, virtual environment detection, port conflict resolution, and service orchestration.

### Basic Template (Port Detection + Portless Logic)

```bash
#!/bin/bash

# 1. Project Identity
PROJECT_NAME=$(basename "$PWD")
SESSION_NAME="${PROJECT_NAME}_dev"

# 2. Check for existing session
if tmux has-session -t $SESSION_NAME 2>/dev/null; then
    echo "Session $SESSION_NAME already exists. Attaching..."
    tmux attach -t $SESSION_NAME
    exit 0
fi

# 3. Portless Initialization
portless proxy start
portless trust

# 4. Dynamic Port Detection (prefers portless-injected $PORT, else starts at 8000)
PORT=${PORT:-8000}
while ss -tuln | grep -q ":$PORT " ; do
    PORT=$((PORT+1))
done

# 5. Virtual Env Detection
VENV_CMD=""
[ -d "venv" ] && VENV_CMD="source venv/bin/activate && "
[ -d ".venv" ] && VENV_CMD="source .venv/bin/activate && "  # .venv wins if both exist
```

---

## 🏗️ Case Studies

### Case A: Vanilla Django Project
Focuses strictly on the Django server and the portless proxy.

```bash
# Add to dev.sh
tmux new-session -d -s $SESSION_NAME -n 'django' -c "$PWD" \
    "bash -c '${VENV_CMD}portless $PROJECT_NAME --app-port $PORT -- python manage.py runserver $PORT; read'"
tmux select-window -t $SESSION_NAME:0
tmux attach -t $SESSION_NAME
```

### Case B: Complex Django (Celery + Redis + Stripe)
Ideal for projects with background tasks and external webhooks.

> Sibling note: Redis/Celery are shared across worktree siblings by default
> (same `REDIS_URL`). The `stripe listen --forward-to` must point at the
> sibling's own `$PORT` (each checkout picks its own port via the scan above).

```bash
# Add to dev.sh
tmux new-session -d -s $SESSION_NAME -n 'django' -c "$PWD" \
    "bash -c '${VENV_CMD}portless $PROJECT_NAME --app-port $PORT -- python manage.py runserver $PORT; read'"
tmux new-window -n 'worker' -c "$PWD" "${VENV_CMD}celery -A project worker -l info"
tmux new-window -n 'beat' -c "$PWD" "${VENV_CMD}celery -A project beat -l info --scheduler django_celery_beat.schedulers:DatabaseScheduler"
tmux new-window -n 'stripe' -c "$PWD" "stripe listen --forward-to localhost:$PORT/webhooks/stripe/"
```

### Case C: Monorepo (Frontend + Backend)
For projects with separate frontend (React/Astro/Next.js) and Django backend.

> Sibling note: run one backend checkout per worktree sibling; the frontend
> dev server points at the sibling backend's portless URL.

```bash
# Add to dev.sh
# Assume backend is in ./backend and frontend in ./frontend
tmux new-session -d -s $SESSION_NAME -n 'backend' -c "$PWD/backend" \
    "bash -c '${VENV_CMD}portless $PROJECT_NAME --app-port $PORT -- python manage.py runserver $PORT; read'"
tmux new-window -n 'frontend' -c "$PWD/frontend" "npm run dev"
```

---

## 🌳 Worktrees (one checkout per branch)

Django worktrees derive the URL from the directory basename (not a subdomain
prefix): main `https://<project>.localhost`, sibling
`https://<project>-<branch>.localhost` — each with its own tmux session and
port via the scan above. Full runbook, scripts (`worktree-new.sh`,
`worktree-done.sh`), and sibling rules → see
[[django-worktrees|Git Worktrees + Portless (Django)]].

---

## 💡 Important Considerations

### Port Conflict Resolution
The `ss -tuln` loop ensures that if you are working on multiple Django projects at once, they won't fight for port 8000. Each will automatically pick the next free port (8001, 8002, etc.), while `portless` ensures the public URL remains consistent.

### Single Domain Access
By using the project name as a subdomain, you avoid "Port Hunting" in your browser. Always access the app via `https://project-name.localhost`. This is critical for:
1. **OAuth2**: Google/Microsoft only allow redirects to authorized domains.
2. **Webhooks**: Services like Stripe need a public URL to send events.
3. **Cookies/Sessions**: Prevents cross-project session interference on `localhost`.

### Tmux Usage
- `Ctrl+b` then `n`: Next window.
- `Ctrl+b` then `p`: Previous window.
- `Ctrl+b` then `d`: Detach (keep processes running in background).
- `./dev.sh`: Re-attach to the session.
