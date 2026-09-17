---
created: 2026-08-05
updated: 2026-08-05
tags:
  - astro
  - architecture
  - components
  - documentation
  - guide
type: resource
status: active
source: templates://astro/component-dependencies-guide.md
version: 2026-09-17+unreleased

---

# Component Dependency Map — Guide

How to produce and maintain the per-project `component-dependencies.md` (see [[component-dependencies-template]]).
The template is the copyable skeleton; this file is the method behind it.

Applies to any Astro project. The mechanics (pages → components → shared leaves) also transfer to other component frameworks.

## When to create it

- At project start, once the first few pages exist — cheap to write, anchors the architecture.
- At major refactors (new routing, added i18n, removed pages) — regenerate and update the Notes.

## How to extract the data

Hand-drawn ASCII trees, but fed by greps — never from memory:

```bash
# All imports across pages + components
rg "^import" src --glob "*.{astro,ts,tsx,jsx}"

# Every component file actually present (the nodes of your tree)
rg --files src/components | sort

# Every route
rg --files src/pages | sort
```

Then walk each page top-down: which component does it import, what do those import, until you hit a leaf (something importing only `lib/`, `data/`, or styles).

## What each section documents

| Section | Documents |
|---|---|
| Pages layer | Every route in `src/pages/` and what it renders; the routing mechanism (file-based, catch-all `[...path]`, content collections) |
| Full dependency diagram | One overview: pages → page components → Layout shell → shared leaves (optional if pages are few — per-page trees may suffice) |
| Per-page trees | One subsection per real page, with its full subtree |
| Shared shell (Layout) | `Layout.astro`, `Header`, `Footer`, `<slot/>`, global css — what every page shares |
| Optional chains | Subsections only if present: SEO chain, islands (React/Vue/Svelte), design-system showcase, i18n, auth guards, etc. |
| Shared leaf layer | Terminal deps imported by many components: `lib/utils`, i18n, `data/site-config`, `consts`, `global.css`, stores, api clients |
| Notes | Project history, orphaned/unreachable components, decisions and tradeoffs |

## Variants checklist

Tick what this project has, then document it:

- [ ] **Routing**: file-based vs single catch-all `[...path].astro` + `getStaticPaths()` + `COMPONENT_MAP`
- [ ] **i18n**: present or not (see [[astro-i18n]])
- [ ] **Islands**: React/Vue/Svelte components inside `.astro` files (see [[astro-react-islands]])
- [ ] **UI library**: vanilla components vs shadcn/Radix `ui/` layer (see [[astro-atomic-components]])
- [ ] **Content collections** / CMS-driven pages
- [ ] **Design-system / showcase page** (noindex, outside the runtime page tree)
- [ ] **SEO chain** (see [[astro-seo]])
- [ ] **Data layer**: `site-config`, `consts`, stores (see [[astro-site-config]], [[astro-zustand-zod]])
- [ ] **API routes** (`*.ts` in `src/pages/`) — no components, but part of the route map

## Keeping it in sync

Any page/component add, remove, rename, or import change invalidates the map. Re-run the greps and redraw only the affected trees. If a diff keeps creeping in, the map is a symptom — the project drifted from its architecture, which is what the Notes section is for.

## Orphan hunting

Leaves reachable from no page = dead code candidates. During a map pass, list them in Notes so cleanup is a decision, not a discovery.

## Related

- [[component-dependencies-template]]
- [[astro-atomic-components]]
- [[astro-react-islands]]
- [[astro-i18n]]
- [[astro-site-config]]
- [[astro-seo]]
