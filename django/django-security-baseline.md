---
created: 2026-10-28
tags:
  - django
  - security
  - cve
  - deployment
  - documentation
type: resource
status: active
source: templates://django/django-security-baseline.md
version: 2026-10-28+28a9c8d

---

# Django Security Baseline — what "patched" means and how it stays that way

> Companion to [Project Setup](./django-project-setup.md). That guide creates a
> project at this baseline; this page defines the baseline, who owns each layer,
> how to refresh it, and what a new project still needs outside the repository.

Distilled from the 2026-10 CVE work on the Hetzner/Coolify fleet: 11 Django
projects audited against the Node.js/CPython/certifi advisories of 2026-10-01 →
2026-10-21, then hardened. Everything here is the state those 11 reached.

---

## 1. Baseline (as of 2026-10-28)

| Layer | Target | Why |
|---|---|---|
| Django | **5.2.18 LTS** | 4.2 reached EOL in 2026-04. 5.2 is supported until 2028-04. |
| CPython | **3.12.15** (`FROM python:3.12-slim`) | Same minor as every deployed project. The patch level follows the base tag — `apt upgrade` cannot bump CPython. |
| `certifi` | **2026.10.19** | Drops the compromised emSign roots (GHSA-6q48-6c7w-9gw2). Pin it explicitly; it arrives transitively through `requests`. |
| Debian packages | **0 pending** | `apt-get upgrade` in the Dockerfile is the only thing that closes this. The audit found 17–32 pending packages per image. |
| Security settings | `SECURE_SSL_REDIRECT`, `SECURE_PROXY_SSL_HEADER`, `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE` | Env-driven, prod-safe defaults (Project Setup §6). |
| Migrations | 0 pending after `migrate` | `showmigrations --plan` must print nothing. |
| Dependencies | exact pins, OSV-clean | Ranges are how a CVE re-enters on a patch day. |

Anything below that table (Apache/Nginx config, PHP, Node) is out of scope for a
Django project.

---

## 2. Who owns what

| Concern | Owner | Notes |
|---|---|---|
| TLS termination, HSTS, redirects at the edge | **Traefik / Coolify proxy** | Django must **not** set `SECURE_HSTS_SECONDS`; two sources publish two policies. Verified with `curl -sI https://<host> \| grep -i strict-transport-security`. |
| `X-Forwarded-Proto` trust | **Django settings** | `SECURE_PROXY_SSL_HEADER` is mandatory behind any HTTPS-terminating proxy. Without it, `SECURE_SSL_REDIRECT` loops. |
| Secure/HttpOnly cookies | **Django settings** | `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE` via env vars. |
| OS packages | **Dockerfile** | `apt-get update && apt-get upgrade -y` at every build. |
| CPython patch level | **base image tag** | `python:3.12-slim` moves; a cached layer does not. Re-pull on patch days. |
| Database exposure | **Coolify** | DB reachable by container name (`postgresql-<id>:5432`), never a published `90xx` port. |
| Backups | **pgBackWeb / Databasus** | Per-database job + one restore test. Not created automatically. |
| Uptime | **Uptime Kuma** | Add the project to `platform-health` or its own monitor. |

---

## 3. Patch day (the only procedure that keeps the baseline true)

Pins are a snapshot. Repeat this whenever an advisory lands — the 2026-10 cycle
took one afternoon for the whole fleet.

1. **Bump the pins** in `requirements.txt` (`Django`, `certifi`, `pillow`, `requests`, …).
   Never widen a range to "let pip figure it out".
2. **Rebuild without cache** so the base tag is re-resolved:
   `docker build --no-cache -t <app>:<date> .`
   Note the digest — rebuilds of the same commit are *not* byte-identical, because
   Debian packages move under `apt upgrade`.
3. **Verify inside the container** (not on the host):

   ```bash
   python3 -V
   dpkg -s python3.12 | grep ^Version                      # distro backports
   python3 -c "import certifi; print(certifi.__version__)"
   apt-get update -qq && apt-get -s upgrade | grep -c ^Inst  # expect 0
   python manage.py check --deploy                           # expect W004 only
   python manage.py check_prod_security                      # expect OK
   python manage.py showmigrations --plan | grep '\[ \]'     # expect empty
   ```

4. **Smoke test** the app (see §6) and the S3 static upload (see §5).
5. **Record** the new digest and the audit output in the project's tracking note.

> `certifi` deserves its own line in the checklist: the emSign removal was a
> *removal*, so a stale pin keeps trusting a CA that a later advisory revokes.

---

## 4. New project onboarding (outside the repository)

Creating the project from the template gives you §1. It does **not** give you these:

- [ ] Database backup job created (pgBackWeb / Databasus) and one restore tested.
- [ ] Uptime monitor created (and added to `platform-health` if the project is critical).
- [ ] `DB_HOST` / `DB_PORT` set to the container name and `5432` — no published port.
- [ ] `STORAGE_AWS` present as a **build-time** variable, exactly `True`.
- [ ] HSTS header confirmed on the real domain.
- [ ] `check --deploy` + `check_prod_security` run inside the container.
- [ ] Image digest recorded in the deploy log.

---

## 5. Coolify rules that bite

| Rule | Failure it prevents |
|---|---|
| Security vars are editable in the UI; defaults are safe if deleted | A deleted variable must fail **closed** (`str(not DEBUG)`), never open. |
| `STORAGE_AWS` must reach the **build**, not just the runtime | Static files compile locally and the CDN keeps the old CSS/JS. Signature: `N static files copied to '/app/staticfiles'` (wrong) vs `N static files copied.` (right). If recreating the variable in place does not work, delete and recreate it. |
| `DEBUG` must be exactly `False` in production | `DEBUG=True` serves the URLconf and tracebacks; a 404 grows from ~179 B to ~4.8 KB. |
| The HSTS flag lives in the proxy compose, which Coolify regenerates | HSTS disappears silently from every host. Re-check the header after any proxy operation. |
| Coolify passes all env vars as build args, but Docker only exposes declared `ARG`s | A value used by `collectstatic` must be declared in the Dockerfile or it is simply absent at build time. |

---

## 6. Verification one-liners

```bash
# Login: from /admin/login/ without ?next= must land on /admin/, not /accounts/profile/
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' https://<host>/admin/
# Unknown URL: ~179 B generic 404 proves DEBUG=False (a 4.8 KB body leaks the URLconf)
curl -s -o /dev/null -w '%{http_code} %{size_download}\n' https://<host>/ruta-inexistente/
# HSTS present at the edge
curl -sI https://<host>/ | grep -i strict-transport-security
# Admin renders: every registered model's changelist returns 200 (the 2026-10 audit checked 386 pages)
```

Inside the container: `python manage.py check --deploy`,
`check_prod_security`, `showmigrations --plan`.

---

## 7. Accepted warnings (do not "fix" these)

| Warning | Reason |
|---|---|
| `security.W004` | HSTS is the proxy's job. Django cannot see it. Setting it in Django creates a second policy. |
| `security.W009` | Should not appear with a ≥50-char key. Locally it is a reminder; in production it is a defect. |
| `security.W019` | Only when the project overrides `X_FRAME_OPTIONS`; Traefik already sends `DENY`. |
| `staticfiles.W004` | **Not** acceptable — `STATICFILES_DIRS` points at a missing folder. Fix it. |

---

## 8. Explicitly out of scope

This baseline is about **runtime CVEs and configuration**, not application
security review. A new project still starts without:

- **Application-level review** — the 2026-10 audit left real findings in one
  project (IDOR in a public progress endpoint, an over-broad serializer, a
  `requests.get` without timeout). Those need a per-project review, not a template.
- **CSP and rate limiting** — no Content-Security-Policy, no brute-force
  protection on admin login.
- **Non-root container user** — only one of the 11 projects runs as non-root.
- **Legacy Django 4.2 apps** — 14 repositories remain on 4.2 EOL, stopped and
  documented. Never copy one of those as a starting point; start from §1 here.
- **PHP / Node / vendor images** — separate guides.

---

## Related

- [Project Setup Guide](./django-project-setup.md) — creates the project at this baseline
- [Testing Contract](./django-testing-contract.md) — `IS_TESTING` override + dependency audit job
- [Media Storage](./django-media-storage.md) — S3, build args and the `STORAGE_AWS` trap
- [Cloudflare Tunnel](./django-cloudflare-tunnel.md) — dev exposure, proxy header already trusted
