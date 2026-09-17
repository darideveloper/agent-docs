---
created: 2026-04-21
updated: 2026-09-17
tags:
  - astro
  - frontend
  - hub
type: area-note
status: active
source: templates://astro/astro.md
version: 2026-09-17+unreleased

---

# Astro

Astro is a modern web framework designed for speed, focusing on content-driven websites. It allows for using various UI frameworks like React, Vue, and Svelte while delivering minimal JavaScript to the browser.

### **Base (every project)**

*   [Base config — merged astro.config + tsconfig + package.json + env](./astro-base-config.md)
*   [Atomic Component Hierarchy](./astro-atomic-components.md)
*   [All Config in One Place (site-config / consts / env)](./astro-site-config.md)
*   [Client-Side Page Transitions — default ON](./astro-client-side-page-transitions.md) — shared Layout ships `<ClientRouter />`; see "No-router escape" in that doc if you must disable
*   [Search Engine Optimization (SEO core)](./astro-seo.md)
*   [Dockerized Deployment (pnpm)](./astro-docker-deployment.md)
*   [Portless Dev Workflow](./astro-portless.md)
*   [Git Worktrees + Portless (Core)](./astro-worktrees.md) — one checkout per branch, branch-subdomain `.localhost` URLs (manual-siblings default, plugin opt-in)
*   [AGENTS.md worktrees snippet (copy-paste)](./astro-agents-worktrees-snippet.md) — canonical per-project agent contract
*   [agent-worktrees spec template (copy-paste)](./agent-worktrees-spec-template.md) — enforceable SHALL requirements
*   [Component Dependency Map — Guide](./component-dependencies-guide.md) + [Template](./component-dependencies-template.md)

### **Opt-in layers (pick per project)**

| Layer | Doc | Use when | Skip if |
|---|---|---|---|
| React islands + Tailwind v4 | [Astro + React Islands](./astro-react-islands.md) | interactive widgets needed | static-only site (Astro components suffice) |
| Forms state | [Zustand + Persist + Zod](./astro-zustand-zod.md) | forms / filters / prefs | no forms or cross-island state (static/content site) |
| API calls | [Fetch Wrapper Pattern](./astro-fetch-wrapper.md) | any backend/CMS fetch | no API (e.g. i18n-only content site) |
| i18n (N languages) | [Internationalization](./astro-i18n.md) | 2+ languages | single language |
| Markdown | [Markdown Rendering](./astro-markdown.md) | CMS/API prose, JSON markdown, blog | all strings plain text |
| PWA | [PWA Out of the Box](./astro-pwa.md) | installable/offline needed | plain website (API-cache block conditional on Fetch layer) |
| Animation | [GSAP + ScrollTrigger](./gsap-scrolltrigger/README.md) | sequenced/scroll/loader animation | CSS transitions suffice, strict no-JS |

Limited combos that work: i18n without API (skip Fetch + PWA API-cache), Markdown without i18n (§2+§4 only), static no-React (Base + Transitions still on).

### **Other Resources**
*   [[mermaid-diagram-generation|Mermaid Diagram Generation]]
