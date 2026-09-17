---
created: 2026-08-05
updated: 2026-08-05
tags:
  - astro
  - components
  - architecture
  - documentation
  - template
type: template
status: active
source: templates://astro/component-dependencies-template.md
version: 2026-09-17+unreleased

---

# Component Dependency Map

> **How to use this template.** Copy this file into the project as `component-dependencies.md`
> and replace every `[…]` placeholder. Delete this callout and the italic fill-in hints when done.
> Read [[component-dependencies-guide]] for the method behind each section.

Living reference of how pages compose components (and subcomponents) in this project.

> **Keep this in sync.** Whenever pages or components are added, removed, renamed, or
> their imports change, regenerate the diagram below and update the Notes section.
> Re-run `rg "^import" src --glob "*.{astro,ts,tsx,jsx}"` to list imports, then redraw.

## Pages layer

*List every route in `src/pages/` and what it renders. State the routing mechanism
(file-based, catch-all `[...path]` + `getStaticPaths()` + `COMPONENT_MAP`, content collections).*

```
src/pages/
├── […].astro        ← what it renders, how it's driven
└── […].ts           ← API routes, no components
```

## Full dependency diagram

*One overview diagram: pages → page components → shared shell (Layout) → shared leaf layer.
Optional if pages are few — per-page trees below may suffice.*

```
┌──────────────┐
│  <Page>.astro │
└──────┬───────┘
       ▼
┌─────────────────────────┐
│     Layout.astro        │
│  styles/global.css      │
│  <slot/> = page content │
└─────────────────────────┘
```

## Per-page trees

*One subsection per real page. Walk each page top-down until every branch hits a leaf.*

### <Page>.astro tree

```
<Page>.astro
├── <Component>.astro ────► lib/… (leaf)
└── <Component>.astro
    └── <Sub>.astro
```

## Shared shell (Layout)

*The tree every page shares: Layout, Header, Footer, `<slot/>`, global styles.*

```
Layout.astro
├── styles/global.css
├── Header.astro
│   └── <components…>
├── <slot/> = page content
└── Footer.astro
    └── <components…>
```

## Optional chains

*Only include subsections this project actually has.*

### SEO chain

```
<Page>SEO.astro ─► BaseSEO.astro
                  ├── consts.ts (SITE_TITLE, SITE_DESCRIPTION, …)
                  ├── data/site-config.ts
                  └── lib/… 
```

### Islands (React/Vue/Svelte)

*List the framework components embedded in `.astro` files and what they bind to (props, stores).*

### Design-system / showcase page

*Standalone, noindex, imports the component library directly — not part of the runtime page tree.*

### i18n

*Catch-all routing, locale paths, translation dictionaries.*

## Shared leaf layer

*Terminal dependencies imported by multiple components:*

- `lib/utils.ts` — helper (`cn()`, …)
- `lib/i18n/…` — translations, routes, localize helpers
- `data/site-config.ts` — site/business data
- `consts.ts` — site constants
- `styles/global.css` — design tokens
- `store/…` — state (zustand, …)
- `lib/api/…` — api client, types

## Notes

*Project history, architecture decisions and tradeoffs, and anything worth revisiting.*

- **Orphaned / not reachable from any page** (candidates for cleanup): *list dead components here.*

## Related

- [[component-dependencies-guide]]
- [[astro-atomic-components]]
- [[astro-react-islands]]
- [[astro-i18n]]
- [[astro-site-config]]
- [[astro-seo]]
