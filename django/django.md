---
created: 2026-04-21
tags:
  - django
  - python
  - backend
  - hub
type: area-note
status: active
source: templates://django/django.md
version: 2026-09-27+57b0fd3

---

# Django

Django is a high-level Python web framework that encourages rapid development and clean, pragmatic design. It handles much of the complexity of web development, allowing you to focus on writing your app without needing to reinvent the wheel.

Reusable template — English default (`en-us`, `America/Mexico_City`). Placeholders: `project` package, `<APP_LABEL>`, `<MODEL>`. Canonical API prefix `/api/`.

### **Core (copy for every project)**
*   [Project Setup Guide](./django-project-setup.md) — scaffolding; links out for storage/tests/fixtures/admin bases
*   [Model Definitions](./django-model-definitions.md) — English admin-visible texts
*   [Unfold Admin Theme](./django-unfold-admin.md) — canonical `project/admin_base.py`, auto sidebar, `base_site.html`
*   [DRF Implementation Guide](./django-drf.md) — default ON; `/api/` router (use minimal non-DRF urls variant if no API)
*   [Media Storage Configuration](./django-media-storage.md) — canonical `STORAGES` + `IS_TESTING`
*   [Testing Contract (Django-only Runner)](./django-testing-contract.md) — test runner (STORAGES canonical lives in media-storage)
*   [Fixed Data Loading with Django Fixtures](./django-fixtures.md) — loader in `<APP_LABEL>` main app

### **Optional (opt-in)**
*   [Redis in Django Integration Guide](./django-redis.md) — caching/Celery, full `REDIS_URL`
*   [Excel Export Integration](./django-excel-export.md) — openpyxl, separate export flavor `ModelAdminUnfoldExportBase`
*   [Bruno API Client Guide](./django-bruno.md) — `/api/` collections
*   [Local Development & Subdomain Setup](./django-local-subdomain-setup.md) — portless + `dev.sh`
*   [Git Worktrees + Portless (Django)](./django-worktrees.md) — one checkout per branch, sibling `.localhost` URLs, `worktree-new/done.sh`
*   [Cloudflare Tunnel Setup](./django-cloudflare-tunnel.md) — dev exposure, merged hosts
*   [Spanish Django Admin](./django-i18n-es-admin.md) — OPT-IN Spanish variant, skip for English default
*   [Image Copy Link Utility](./django-image-copy-link.md) — English `Copy link`, per-model `Media`

### **Worked examples (do not copy as template)**
*   [Stripe Subscriptions Architecture](./stripe-subscriptions.md)
*   [Stripe Account Setup & Checklist](./stripe-account-setup.md)
*   [Testing Stripe Subscriptions](./testing-stripe.md)
*   [Artwork Room Mockups (Design Exploration)](./django-artworks-mockups.md)

Mermaid Diagram Generation — see https://github.com/darideveloper/agent-docs (vault pointer, no vendored doc).

### **Links & Portability**

These docs use relative Markdown links `[label](./file.md)`. When copying them into a new Django
project, the agent MUST handle links as follows:

1. Relative links (`[label](./django-project-setup.md)`) point to sibling docs in
   the same folder — keep them as-is.
2. Links to external resources not included in the project (e.g.
   `Redis (external)`) have NO local equivalent — replace the
   link with a plain text label (e.g. `Redis (external)`).

This keeps a project copy self-contained so team members without the vault do
not see broken wikilinks.
