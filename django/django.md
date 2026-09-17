---
created: 2026-04-21
updated: 2026-09-17
tags:
  - django
  - python
  - backend
  - hub
type: area-note
status: active
source: templates://django/django.md
version: 2026-09-17+4cf710f

---

# Django

Django is a high-level Python web framework that encourages rapid development and clean, pragmatic design. It handles much of the complexity of web development, allowing you to focus on writing your app without needing to reinvent the wheel.

Reusable template — English default (`en-us`, `America/Mexico_City`). Placeholders: `project` package, `{app_name}`/`<APP_LABEL>`, `<MODEL>`, `<MAIN_APP>` loader app. Canonical API prefix `/api/`.

### **Core (copy for every project)**
*   [[django-project-setup|Project Setup Guide]] — scaffolding; links out for storage/tests/fixtures/admin bases
*   [[django-model-definitions|Model Definitions]] — English admin-visible texts
*   [[django-unfold-admin|Unfold Admin Theme]] — canonical `project/admin_base.py`, auto sidebar, `base_site.html`
*   [[django-drf|DRF Implementation Guide]] — optional only if REST API; `/api/` router
*   [[django-media-storage|Media Storage Configuration]] — canonical `STORAGES` + `IS_TESTING`
*   [[django-testing-contract|Testing Contract (Django-only Runner)]] — canonical test runner + `STORAGES`
*   [[django-fixtures|Fixed Data Loading with Django Fixtures]] — loader in `<MAIN_APP>`

### **Optional (opt-in)**
*   [[django-redis|Redis in Django Integration Guide]] — caching/Celery, full `REDIS_URL`
*   [[django-excel-export|Excel Export Integration]] — openpyxl, imports base from unfold doc
*   [[django-bruno|Bruno API Client Guide]] — `/api/` collections
*   [[django-local-subdomain-setup|Local Development & Subdomain Setup]] — portless + `dev.sh`
*   [[django-worktrees|Git Worktrees + Portless (Django)]] — one checkout per branch, sibling `.localhost` URLs, `worktree-new/done.sh`
*   [[django-cloudflare-tunnel|Cloudflare Tunnel Setup]] — dev exposure, merged hosts
*   [[django-i18n-es-admin|Spanish Django Admin]] — OPT-IN Spanish variant, skip for English default
*   [[django-image-copy-link|Image Copy Link Utility]] — English `Copy link`, per-model `Media`

### **Worked examples (do not copy as template)**
*   [[stripe-subscriptions|Stripe Subscriptions Architecture]]
*   [[stripe-account-setup|Stripe Account Setup & Checklist]]
*   [[testing-stripe|Testing Stripe Subscriptions]]
*   [[django-artworks-mockups|Artwork Room Mockups (Design Exploration)]]
*   [[mermaid-diagram-generation|Mermaid Diagram Generation]]

### **Wikilinks & Portability**

These docs use Obsidian `[[wikilinks]]`. When copying them into a new Django
project, the agent MUST handle links as follows:

1. Short-form links (`[[django-project-setup|label]]`) point to sibling docs in
   the same folder — keep them as-is.
2. Vault-path links to sibling docs (e.g. `[[django-foo]]`)
   → convert to short-form `[[django-foo|label]]`.
3. Vault-path links to external resources not included in the project (e.g.
   `Redis (external)`) have NO local equivalent — replace the
   link with a plain text label (e.g. `Redis (external)`).

This keeps a project copy self-contained so team members without the vault do
not see broken wikilinks.
