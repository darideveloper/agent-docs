---
created: 2026-09-09
updated: 2026-09-17
tags:
  - astro
  - configuration
  - documentation
type: resource
status: active
source: templates://astro/astro-base-config.md
version: 2026-09-17+4cf710f

---

# Astro Base Config (single source of truth)

Precondition: none. This is Base — every project copies this, then adds opt-in layers.

Baseline: **pnpm + Astro 6 + Tailwind v4.** All other docs point here instead of repeating fragments.

## 1. Merged `astro.config.mjs`

Base includes `sitemap()` and port handling. Add `react()`, `vitePwa()`, `redirects` only with the matching layer.

```ts
// astro.config.mjs — Base (Transitions are Base: Layout ships <ClientRouter />)
import { defineConfig } from 'astro/config'
import tailwindcss from '@tailwindcss/vite'
import react from '@astrojs/react' // opt-in: only if React islands layer is used
import sitemap from '@astrojs/sitemap'
import vitePwa from '@vite-pwa/astro' // opt-in: only if PWA layer is used

// Config files can't use import.meta.env for .env values, and bare
// process.env can't see .env either — Node 22 loadEnvFile fills CLI-unset
// vars from .env (no new dependency; CLI env wins). Missing .env (e.g.
// Docker, where the value arrives as ENV) falls through to the fallback.
try {
  if (typeof process.loadEnvFile === 'function') process.loadEnvFile('.env')
} catch {
  // No .env — process.env / fallback below apply.
}

export default defineConfig({
  // Origin chain: per-checkout Portless URL wins in dev (each worktree gets
  // its own branch-subdomain URL), explicit SITE_URL covers Docker/CI builds.
  // Fallback is the prod domain: dev never reaches it (Portless always injects
  // PORTLESS_URL), and a build without env must emit prod — never localhost —
  // into sitemap/canonicals. Full pattern → see ./astro-worktrees.md.
  site: process.env.PORTLESS_URL ?? process.env.SITE_URL ?? 'https://<prod-domain>',
  build: {
    inlineStylesheets: 'always',
  },
  server: {
    port: process.env.PORT ? parseInt(process.env.PORT) : 4321, // portless injects PORT; fallback for plain `pnpm dev`
    strictPort: true, // fail fast if the assigned port is taken
  },
  vite: {
    plugins: [tailwindcss()],
    server: {
      port: process.env.PORT ? parseInt(process.env.PORT) : 4321,
      strictPort: true,
    },
  },
  integrations: [
    react(), // delete this line if no React islands
    sitemap(),
    // vitePwa({ ... }) — only if PWA layer is used, see ./astro-pwa.md
  ],
  // redirects: { ...legacyRedirects } — only if i18n layer is used, see ./astro-i18n.md §4.1
})
```

With i18n, import `routes` with a **relative** path (config runs under Node, `@/` alias does not resolve there):
`import { routes } from "./src/lib/i18n/routes.ts"`.

## 2. `tsconfig.json` alias (Base-owned)

```json
{
  "extends": "astro/tsconfigs/strict",
  "compilerOptions": {
    "baseUrl": ".",
    "paths": { "@/*": ["./src/*"] },
    "jsx": "react-jsx",
    "jsxImportSource": "react"
  }
}
```

`@/` means `./src/*`. All docs assume this alias.

## 3. `package.json` scripts (canonical)

```json
{
  "packageManager": "pnpm@latest",
  "engines": { "node": ">=22" },
  "scripts": {
    "dev": "portless run pnpm astro dev",
    "build": "pnpm validate-imports && astro build",
    "build:i18n": "pnpm validate-i18n && pnpm validate-imports && astro build",
    "build:full": "pnpm validate-i18n && pnpm validate-imports && astro build && pnpm validate-markdown",
    "validate-i18n": "tsx scripts/validate-i18n.ts",
    "validate-imports": "tsx scripts/validate-imports.ts",
    "validate-markdown": "tsx scripts/validate-markdown.ts",
    "preview": "astro preview",
    "generate-pwa-assets": "pwa-assets-generator --config vite-pwa-assets-generator.config.ts"
  }
}
```

Rules:

- `dev` runs through `portless run`, which derives the app name automatically and prepends the branch inside worktrees (see `./astro-worktrees.md`). Behind a MITM corporate proxy, prefix with `NODE_OPTIONS=--use-openssl-ca`.
- Validators are conditional: `validate-i18n` only if i18n layer present; `validate-markdown` only if Markdown layer present (it scans `dist/`, so it runs **after** `astro build`). `validate-imports` always runs (enforces `@/` alias; Astro config file is the one allowed relative-import exception).
- Requires `tsx` as a devDependency (`pnpm add -D tsx`) for any validator you use.
- `pnpm` exclusively — never npm. Dockerfile uses `pnpm install --frozen-lockfile`.
- Minimal instance note: projects without i18n/markdown layers may ship a bare `build: astro build` (no validators) plus project-specific scripts (e.g. `check:palette` for token setups). That is a layer-absent instance, not the canonical — keep the validator chain above as the template.
- `packageManager` keeps a `pnpm@<version>` placeholder in the template; instantiated projects pin the exact version in use.

## 4. Environment truth table

| Variable | Scope | Read via | Purpose |
|---|---|---|---|
| `BUSINESS_DATA.url` (`src/data/site-config.ts`) | build-time constant | import | prod canonical origin for SEO/OG/sitemap |
| `SITE_URL` (`.env`, server-only) | dev / SSR | `process.env.SITE_URL` | dev canonical origin, redirects |
| `PUBLIC_API_BASE_URL` | build-time inlined, client-safe | `import.meta.env.PUBLIC_API_BASE_URL` | API origin for Fetch layer |
| `PORT` / `HOST` / `PORTLESS_URL` | portless-injected | `process.env.*` | dev server wiring only |

Rules:

- Never hardcode origins in components — import `BUSINESS_DATA`.
- `PUBLIC_*` is the only prefix exposed to client bundles. Non-`PUBLIC_` vars are server-only (`process.env`).
- Pass every `PUBLIC_*` var as a Docker build arg (see `./astro-docker-deployment.md`) since Astro inlines them at build time.

```ts
// env.d.ts (project root) — default: no-backend projects (no PUBLIC_* readers yet)
/// <reference types="astro/client" />

// Client-exposed env must use the PUBLIC_ prefix. Declare each one here
// when its first reader lands. (SITE_URL is server-only and intentionally
// absent: it is read via process.env, never import.meta.env.)
interface ImportMetaEnv {
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
```

With-backend opt-in — add one entry per `PUBLIC_*` reader (Fetch layer):

```ts
// env.d.ts — with-backend addition
interface ImportMetaEnv {
  readonly PUBLIC_API_BASE_URL: string
  readonly PUBLIC_ANALYTICS_ID?: string
}
```

Server-only vars (injected or `.env`) keep their Node-side typing:

```ts
declare namespace NodeJS {
  interface ProcessEnv {
    readonly SITE_URL?: string
    readonly PORT?: string
    readonly HOST?: string
    readonly PORTLESS_URL?: string
  }
}
```

Only declare `PUBLIC_API_BASE_URL` as required if the Fetch layer is present; otherwise keep the empty default above.

## `.gitignore` template (worktree-required)

```gitignore
# build output
dist/

# generated types
.astro/

# dependencies
node_modules/

# environment variables
.env
.env.production

# Ignore proposals
openspec/changes/*

# Do not ignore archived proposals
!openspec/changes/archive/

# ignore by default all hidden folders (like agents folders)
.*/
```

Caution: the `.*/` line ignores every dotfolder, so nothing under
`.opencode/` / `.vscode/` crosses worktrees on its own — that is why the
manual `.opencode` hand-sync in [astro-worktrees](./astro-worktrees.md)
Bootstrap exists. The `openspec/changes/*` + `!archive/` pair is what makes
archive-only sharing possible. Project-specific ignores (e.g. design scratch
dirs) go below, clearly marked.

## `.env.example` template (conditional backend block)

```bash
SITE_URL=https://<project>.localhost
# Only if the project has a backend contract — omit otherwise:
# API_BASE_URL=https://<backend>.localhost
# API_TOKEN=<paste-token-here>
```

## 5. Routing precedence (Base + opt-ins)

Astro resolves static files before the `[...path]` catch-all (i18n layer). Keep this map in mind:

```
src/pages/
├── 404.astro            ← custom not-found (Base)
├── offline.astro        ← PWA offline fallback (only with PWA layer; standalone, no catch-all props)
├── robots.txt.ts        ← dynamic robots (Base SEO)
├── rss.xml.js           ← feed (Base SEO, only if blog)
└── [...path].astro      ← i18n catch-all (only with i18n layer; must not swallow the above)
```

PWA `workbox.navigateFallback: '/offline/'` and nginx `error_page 404 /offline/index.html` are two faces of the same fallback — keep both only with the PWA layer; Base nginx has no offline `error_page`.

## 6. Verification matrix (all layers)

- [ ] Base: `pnpm build` clean, 404 page, robots.txt + sitemap, no `[[wikilink]]` leftovers
- [ ] Router ON: nav without reload, back/forward, hash anchors, embeds, analytics on `astro:page-load`
- [ ] i18n (if present): `pnpm validate-i18n`, lang switch on unknown URLs stays put
- [ ] Markdown (if present): `pnpm validate-markdown` post-build, no `<Markdown>` inside `<p>`
- [ ] PWA (if present): SW never cached, offline page, icons/manifest no 404s
- [ ] Orphan-hunt: `rg "^import" src --glob "*.{astro,ts,tsx,jsx}"` + `rg --files src/components | sort` (see dependency guide)

## Related

- [Hub](./astro.md)
- [Worktrees](./astro-worktrees.md) (sibling layout, bootstrap, `.opencode` sync) + [AGENTS snippet](./astro-agents-worktrees-snippet.md) + [spec template](./agent-worktrees-spec-template.md)
- [Site config](./astro-site-config.md) (BUSINESS_DATA truth; `consts.ts` is the SEO fallback re-export)
- [Transitions (Base, default on)](./astro-client-side-page-transitions.md)
- [Docker](./astro-docker-deployment.md) (build args per `PUBLIC_*`)
- [i18n](./astro-i18n.md) (redirects, catch-all)
- [PWA](./astro-pwa.md) (offline page, manifest caching)
