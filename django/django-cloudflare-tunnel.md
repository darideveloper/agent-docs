---
created: 2026-08-30
tags:
  - django
  - dev-ops
  - cloudflare
  - tunnel
  - documentation
type: resource
status: active
source: templates://django/django-cloudflare-tunnel.md
version: 2026-09-27+57b0fd3

---

# Django + Cloudflare Tunnel (Development Only, Optional)

Expose your local Django development server to the internet through a secure Cloudflare Tunnel — no port forwarding, no firewall changes, no public IP. This guide is for **development workflows only** and is designed to coexist with the [portless-based local development setup](./django-local-subdomain-setup.md).

## 🚀 Overview

Cloudflare Tunnel uses the `cloudflared` daemon to establish an outbound-only connection from your machine to Cloudflare's edge network. It assigns a random public URL (e.g. `https://random-words.trycloudflare.com`) that proxies traffic back to your `localhost`.

**When to use it:**

- Sharing a dev build with a client or remote teammate
- Testing webhooks (Stripe, PayPal, GitHub, etc.) that need a public HTTPS URL
- Testing OAuth redirects from third-party providers
- Mobile device testing on a LAN (phone on the same Wi-Fi visits the tunnel URL)
- Previewing media uploads or external integrations before deploying

**Scope:** This document covers **temporary quick tunnels** only. For named/persistent tunnels with custom subdomains, see the [Cloudflare Tunnel documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/).

**Prerequisite:** You should already have a working Django project following the [Project Setup Guide](./django-project-setup.md) conventions (env-driven settings, `python-dotenv`, `ALLOWED_HOSTS`/`CSRF_TRUSTED_ORIGINS` from env). For the local subdomain part, this guide assumes [portless](./django-local-subdomain-setup.md) is already configured.

---

## 📦 Step 1: Prerequisites

### Install `cloudflared`

**Linux (Debian/Ubuntu):**
```bash
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update && sudo apt install cloudflared
```

**macOS (Homebrew):**
```bash
brew install cloudflared
```

**Windows (winget):**
```bash
winget install --id Cloudflare.cloudflared
```

**Verify installation:**
```bash
cloudflared --version
```

> **Note:** A Cloudflare account is **not required** for the temporary quick tunnel described in Step 2. `cloudflared tunnel --url` works without login.

---

## ⚡ Step 2: Quick Start (Temporary Tunnel)

The fastest way to expose your running Django dev server:

```bash
# In one terminal — start Django
python manage.py runserver 8000

# In another terminal — start the tunnel
cloudflared tunnel --url http://localhost:8000
```

After a few seconds, `cloudflared` prints a public URL:

```
+-----------------------------------------------------------+
|  Your free tunnel has started! Visit it:                  |
|    https://random-words.trycloudflare.com                 |
+-----------------------------------------------------------+
```

Open that URL in any browser — traffic flows through Cloudflare's edge back to your local Django server on port 8000.

**Stop the tunnel:** `Ctrl+C` in the `cloudflared` terminal.

**Limitation:** The random URL changes every time you restart `cloudflared`. For persistent URLs, you'd need a named tunnel (out of scope here).

---

## ⚙️ Step 3: Django Settings — Detailed Explanations

When Django runs behind Cloudflare Tunnel, two subtle problems appear unless you configure these settings. They look similar but solve different problems.

### `SECURE_PROXY_SSL_HEADER`

**What it does:** Tells Django to trust the `X-Forwarded-Proto` header that Cloudflare sets, so Django can detect that the original request was HTTPS (not HTTP).

**Why it's needed:** Cloudflare Tunnel terminates TLS at the edge and forwards the request to your local Django over plain HTTP. By default, Django sees `http://` and behaves as if the user is on an insecure connection:
- `request.is_secure()` returns `False`
- CSRF cookies won't be marked `Secure` (breaks login in modern browsers)
- `SECURE_SSL_REDIRECT` would cause an infinite redirect loop
- `SECURE_HSTS_SECONDS` headers are never sent

**When to use it:** Always when Django is behind **any** HTTPS-terminating proxy (Cloudflare Tunnel, nginx reverse proxy, load balancer, Heroku-style PaaS).

**Security caveat:** Only enable this setting if you **control** the proxy. The `X-Forwarded-Proto` header can be spoofed by a malicious client if your proxy doesn't strip and re-set it. Cloudflare Tunnel correctly sets this header, so it's safe behind it.

**How Django uses it internally** (from `django/http/request.py`):
```python
@property
def scheme(self):
    if settings.SECURE_PROXY_SSL_HEADER:
        header, secure_value = settings.SECURE_PROXY_SSL_HEADER
        header_value = self.META.get(header)
        if header_value is not None:
            return "https" if header_value.strip() == secure_value else "http"
    return self._get_scheme()
```

**Env-driven configuration** (add to `settings.py`):
```python
import os

# Only enable when behind a reverse proxy (Cloudflare Tunnel, nginx, etc.)
# Set USE_SECURE_PROXY_SSL_HEADER=True in .env.dev when using the tunnel
USE_SECURE_PROXY_SSL_HEADER = os.getenv("USE_SECURE_PROXY_SSL_HEADER") == "True"
if USE_SECURE_PROXY_SSL_HEADER:
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
```

### `USE_X_FORWARDED_HOST`

**What it does:** Tells Django to prefer the `X-Forwarded-Host` header over its own server name when constructing URLs.

**Why it's needed:** Without this setting, Django constructs URLs (redirects, password reset links, admin URLs, absolute URLs in emails) using `request.get_host()`, which returns the *internal* host — `localhost:8000`. The user then gets redirected to `http://localhost:8000/...` instead of `https://your-project.trycloudflare.com/...`, breaking the session.

**When to use it:** Whenever a proxy changes the `Host` header (Cloudflare Tunnel, nginx, load balancers). The proxy sets `X-Forwarded-Host` to the original public hostname, and Django uses that instead.

**What it affects:**
- `redirect()` calls
- Password reset email links
- Admin "View on site" links
- `request.build_absolute_uri()` output
- Any code that uses `request.get_host()`

**Security caveat:** Only enable if you **control** the proxy. A spoofed `X-Forwarded-Host` can enable cache poisoning and password reset poisoning attacks. Cloudflare Tunnel correctly sets this header, so it's safe behind it.

**Env-driven configuration** (add to `settings.py`):
```python
# Set USE_X_FORWARDED_HOST=True in .env.dev when using the tunnel
USE_X_FORWARDED_HOST = os.getenv("USE_X_FORWARDED_HOST") == "True"
```

---

## 📋 Step 4: Environment Variables

Add the following lines to your existing `.env.dev` (the file the project loads when `ENV=dev` — keep `.env` containing only `ENV=dev` per the [django-project-setup](./django-project-setup.md) convention). These are **additions**, not replacements.

```env
# Cloudflare Tunnel (dev only — leave False when working on localhost)
USE_SECURE_PROXY_SSL_HEADER=True
USE_X_FORWARDED_HOST=True

# Toggle the tunnel itself in dev.sh (see Step 6)
USE_CLOUDFLARE_TUNNEL=False

# The tunnel domain printed by `cloudflared tunnel --url`.
# Update this each time you start a new temporary tunnel,
# or use a wildcard if your project supports it.
ALLOWED_HOSTS=localhost,127.0.0.1,project-name.localhost,your-project.trycloudflare.com  # merged with subdomain setup
CSRF_TRUSTED_ORIGINS=https://your-project.trycloudflare.com
CORS_ALLOWED_ORIGINS=https://your-project.trycloudflare.com
```

> **Tip:** To avoid editing `ALLOWED_HOSTS`/`CSRF_TRUSTED_ORIGINS` every time the random URL changes, use a wildcard: `ALLOWED_HOSTS=localhost,127.0.0.1,.trycloudflare.com` and `CSRF_TRUSTED_ORIGINS=https://*.trycloudflare.com`. This is a **dev-only convenience** — wildcards weaken security and must never appear in `.env.prod`.

> **Recommendation:** Keep `USE_CLOUDFLARE_TUNNEL=False` on most days and only flip it to `True` when you need internet exposure. This avoids leaking the dev server when you don't need it.

---

## 🏗️ Step 5: Three Modes of Operation

You can run the tunnel in three different configurations depending on what your project needs.

### Mode A — Portless only (local development)

| Property | Value |
|---|---|
| Access | `https://myapp.localhost` |
| Visibility | Your machine only |
| Tools | `portless` |
| Best for | Daily development, OAuth, cookie/session testing |

This is the default in the [Local Development & Subdomain Setup](./django-local-subdomain-setup.md) guide. No internet exposure needed.

### Mode B — Cloudflare Tunnel only (internet exposure)

| Property | Value |
|---|---|
| Access | `https://random-words.trycloudflare.com` |
| Visibility | Anyone with the URL (unlisted but discoverable) |
| Tools | `cloudflared` |
| Best for | Quick client demos, webhook testing, mobile testing |

Django runs on port 8000, `cloudflared` tunnels it directly:
```bash
python manage.py runserver 8000
cloudflared tunnel --url http://localhost:8000
```

### Mode C — Portless + Cloudflare Tunnel (local + internet)

| Property | Value |
|---|---|
| Access | `https://myapp.localhost` (local) + `https://*.trycloudflare.com` (internet) |
| Visibility | Local + internet |
| Tools | `portless` + `cloudflared` |
| Best for | Full-stack dev where you need both a stable local URL and external access |

Portless handles `https://myapp.localhost` locally. Cloudflare Tunnel then exposes the **same** app to the internet by pointing at the portless proxy (not Django directly):

```bash
# One-time prerequisites (already done in django-local-subdomain-setup)
portless proxy start
portless trust

# Portless routes https://myapp.localhost -> Django on $PORT
portless myapp --app-port $PORT -- python manage.py runserver $PORT

# Cloudflare exposes https://myapp.localhost to the internet
cloudflared tunnel --url http://localhost:443  # verify against your portless proxy port
```

Both URLs serve the same Django process. The only thing to remember: the tunnel URL changes every restart; the local `https://myapp.localhost` is stable.

> **Note:** `portless trust` only needs to run **once per machine** — it installs the local CA into your system trust store. After that, you can forget it.

---

## 📜 Step 6: `dev.sh` Integration

Add the tunnel to your existing `dev.sh` (from [django-local-subdomain-setup](./django-local-subdomain-setup.md)) as an opt-in background process. The snippet below is the **complete base template** (port detection, venv, portless, tmux) plus the **tunnel addition** at the end. Copy the whole block as your starting point.

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

# 4. Dynamic Port Detection (starts at 8000)
PORT=8000
while ss -tuln | grep -q ":$PORT " ; do
    PORT=$((PORT+1))
done

# 5. Virtual Env Detection
VENV_CMD=""
[ -d "venv" ] && VENV_CMD="source venv/bin/activate && "
[ -d ".venv" ] && VENV_CMD="source .venv/bin/activate && "

# 6. Start Django through portless (local URL: https://$PROJECT_NAME.localhost)
tmux new-session -d -s $SESSION_NAME -n 'django' -c "$PWD" \
    "bash -c '${VENV_CMD}portless $PROJECT_NAME --app-port $PORT -- python manage.py runserver $PORT; read'"

# 7. Optional: launch cloudflared in another tmux window
#    Set USE_CLOUDFLARE_TUNNEL=True in .env.dev to enable
set -a; [ -f .env.dev ] && source .env.dev; set +a  # .env.dev is not auto-sourced by the shell
if [ "$USE_CLOUDFLARE_TUNNEL" = "True" ]; then
    tmux new-window -n 'tunnel' -c "$PWD" \
        "bash -c 'cloudflared tunnel --url http://localhost:$PORT; read'"
    echo "Cloudflare Tunnel started in window 'tunnel'."
    echo "Watch the tunnel window for your *.trycloudflare.com URL."
fi

tmux select-window -t $SESSION_NAME:0
tmux attach -t $SESSION_NAME
```

**Key points:**

- `cloudflared` must start **after** Django is listening on the port.
- Running it in its own tmux window keeps the URL visible and easy to restart without killing Django.
- The `read` at the end of each bash command keeps the tmux window open if the process exits, so you can read errors.
- Set `USE_CLOUDFLARE_TUNNEL=True` in `.env.dev` only on days you actually need it — keep it `False` for normal dev work.

> **Cleanup:** Killing the tmux session (`tmux kill-session -t $SESSION_NAME`) automatically terminates all windows including the tunnel. No PID tracking needed.

---

## 🔧 Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `CSRF verification failed` (403) on POST | `CSRF_TRUSTED_ORIGINS` missing the tunnel domain | Add `https://your-project.trycloudflare.com` to `CSRF_TRUSTED_ORIGINS` in `.env.dev` |
| `DisallowedHost at / ... Invalid HTTP_HOST` | `ALLOWED_HOSTS` missing the tunnel domain | Add the tunnel domain (or `.trycloudflare.com` wildcard) to `ALLOWED_HOSTS` |
| Login loops / cookies not persisting | Django thinks the request is HTTP (not HTTPS) → `Secure` cookies rejected by the browser | Set `USE_SECURE_PROXY_SSL_HEADER=True` in `.env.dev` |
| Password reset email contains `http://localhost:$PORT/...` | Django is using the internal `Host` header | Set `USE_X_FORWARDED_HOST=True` in `.env.dev` |
| Admin redirects to `localhost` after login | Same as above | Same as above |
| Static files return 404 in the tunneled URL | `ALLOWED_HOSTS` missing the tunnel domain (Django refuses to serve them) | Add the tunnel domain to `ALLOWED_HOSTS` |
| CORS errors in browser console | `CORS_ALLOWED_ORIGINS` missing the tunnel origin | Add `https://your-project.trycloudflare.com` to `CORS_ALLOWED_ORIGINS` |
| `cloudflared` prints `failed to connect to origin` | Django isn't listening on the expected port | Confirm `python manage.py runserver` is running and matches the port in `cloudflared tunnel --url` |
| Tunnel URL changes every restart | Temporary quick tunnel has no persistence | This is expected behavior; copy the new URL into `ALLOWED_HOSTS`/`CSRF_TRUSTED_ORIGINS`, or use a wildcard |

**Quick diagnostic checklist:**

1. Is Django running? `curl http://localhost:$PORT` should return a response.
2. Is `cloudflared` running? Check its terminal for the URL line.
3. Is the tunnel domain in `ALLOWED_HOSTS`?
4. Is the tunnel origin in `CSRF_TRUSTED_ORIGINS` and `CORS_ALLOWED_ORIGINS`?
5. Is `USE_SECURE_PROXY_SSL_HEADER=True`?
6. Is `USE_X_FORWARDED_HOST=True`?

---

## 💡 Important Considerations

### Port Conflict Resolution
The `ss -tuln` loop in `dev.sh` ensures that if you are working on multiple Django projects at once, they won't fight for port 8000. Each will automatically pick the next free port (8001, 8002, etc.), while `portless` keeps the local URL stable. `cloudflared` always points to whatever port `$PORT` resolved to, so the tunnel follows the chosen port automatically.

### Toggle the Tunnel Off When Not Needed
Keep `USE_CLOUDFLARE_TUNNEL=False` on normal dev days. An active tunnel exposes your dev server to the internet, which is unnecessary for local-only work and increases the surface area for accidental leaks of debug data or test endpoints.

### Mode B (Cloudflare-only) Skips Portless
If you don't need a stable local URL, you can skip `portless` entirely in Mode B. `cloudflared` will tunnel `http://localhost:8000` (or whatever port Django runs on) directly. You still need the Django settings changes (`SECURE_PROXY_SSL_HEADER`, `USE_X_FORWARDED_HOST`) because Cloudflare terminates TLS the same way regardless of whether portless sits in front of Django.

### Tunnel URL Stability
The temporary quick tunnel URL changes every restart of `cloudflared`. For a stable URL across restarts, you'd need a named tunnel with Cloudflare account login (out of scope here). For most dev workflows — demos, webhooks, mobile testing — a fresh URL on each session is fine; just update the domain in `.env.dev` (or use the wildcard pattern documented in Step 4).

### Cloudflare Account Is Not Required
`cloudflared tunnel --url` works without any Cloudflare login. The tunnel is anonymous, unlisted, and removed when the process exits. This is ideal for dev but means the URL can't be branded or controlled. For branded subdomains (`tunnel.your-domain.com`), see the [named tunnel docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/).
