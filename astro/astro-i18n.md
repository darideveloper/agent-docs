---
created: 2026-04-17
tags:
  - astro
  - i18n
  - validation
  - documentation
type: resource
status: active
source: templates://astro/astro-i18n.md
version: 2026-09-27+57b0fd3

---

# Internationalization (i18n) System Documentation


> Domain tokens (Home/Blog/Portfolio/COMPONENT_MAP) are illustrative examples — replace with project routes.
> **Opt-in layer.** Precondition: [Base config](./astro-base-config.md). Skip if single-language.

This document describes the custom i18n system used in this project, designed for Astro with localized routing and centralized translation management.

**Build-time validation is mandatory within this system** — see section 9.

> **Note:** The examples use two languages (`en`, `es`), but the pattern scales to
> N languages. Define `SUPPORTED_LANGS` + `DEFAULT_LANG` once and derive everything
> (routing, `LOCALE_MAP`, hreflang, validation) from it — adding a 3rd language is a
> 3-line diff (entry in `ui.ts`, path in `routes.ts`, message file). The default
> language is unprefixed (`/`), every other language is prefixed (`/es/`, `/fr/`).

## 1. Directory Structure

- `src/messages/`: Contains JSON translation files (e.g., `en.json`, `es.json`).
- `src/lib/i18n/`: Core logic and configuration.
  - `ui.ts`: Language definitions and message loading.
  - `utils.ts`: Utility functions for translation and routing.
  - `routes.ts`: Localized path mapping.
- `src/pages/[...path].astro`: Central dynamic router for localized pages.
- `scripts/validate-i18n.ts`: **Mandatory** build-time validation script.
- `scripts/validate-imports.ts`: **Optional** build-time script enforcing `@/` path aliases.
- `package.json`: Scripts wiring validation into the build pipeline.

## 2. Translation Files (`src/messages/`)

Translations are stored in JSON files, organized by nested keys. One file per language.

Example (`en.json`):
```json
{
  "global": {
    "nav": {
      "services": "Services"
    }
  },
  "pages": {
    "home": {
      "title": "Home",
      "description": "Official business services.",
      "keywords": "service, area, business"
    }
  }
}
```

## 3. Configuration (`src/lib/i18n/ui.ts`)

Defines supported languages and the default language. Imports JSON files directly.

```typescript
import en from '@/messages/en.json';
import es from '@/messages/es.json';

export const languages = {
  en: 'English',
  es: 'Español',
};

export const defaultLang = 'en';

export const supportedLangs = Object.keys(languages) as Array<keyof typeof languages>;
// N-lang rule: defaultLang is unprefixed, every other lang is prefixed.
// Adding `fr: 'Français'` here + paths in routes.ts + fr.json is the whole diff.

export const ui = {
  en,
  es,
} as const;
```

## 4. Localized Routing (`src/lib/i18n/routes.ts`)

Instead of creating separate folders for each language, we map "Page Keys" to localized slugs using a single object.

```typescript
export const routes = {
  home: {
    en: "",
    es: "es",
  },
  // ... more routes
} as const;

export type PageKey = keyof typeof routes;
```

Key pattern: English paths have **no language prefix** (the home page is `""` → root), Spanish paths use the `/es/` prefix (`es` → `/es`). The home page English path is `""` (root).

### 4.1 Legacy Redirects

When switching from prefixed English URLs (`/en/path`) to unprefixed (`/path`), add redirects to preserve SEO authority:

```ts
// astro.config.ts
const legacyRedirects = Object.values(routes).reduce<Record<string, string>>((acc, route) => {
  if (route.en === "") {
    acc['/en'] = '/';
  } else {
    acc[`/en/${route.en}`] = `/${route.en}`;
  }
  return acc;
}, {});

export default defineConfig({
  redirects: { ...legacyRedirects }
})
```

This maps `/en/<path>` → `/<path>` for every route automatically.

> **Note:** The Astro config file is loaded directly by Node (not through Vite aliases), so the `@/` alias does not resolve there. Import `routes` with a relative path — e.g. `import { routes } from "./src/lib/i18n/routes.ts"`. If the config is `.mjs` (plain JS, not TS), drop the `reduce<...>` generic and type the accumulator with a JSDoc `/** @type {Record<string, string>} */` annotation instead.

## 5. Dynamic Router (`src/pages/[...path].astro`)

A single catch-all file handles all localized routes using `getStaticPaths`.

```astro
---
import { routes } from '@/lib/i18n/routes'
// Import all page components
import Home from '@/components/pages/Home.astro'
import Blog from '@/components/pages/Blog.astro'
import Portfolio from '@/components/pages/Portfolio.astro'
import Contact from '@/components/pages/Contact.astro'
// ... more page imports

export async function getStaticPaths() {
  const paths = []
  for (const [key, langPaths] of Object.entries(routes)) {
    // English: path is undefined for home, the slug otherwise.
    // Astro 6 rest route: split nested slugs into segments.
    const toParam = (slug: string | undefined) =>
      slug === '' || slug === undefined ? undefined : slug.split("/")
    paths.push({
      params: { path: toParam(langPaths.en) },
      props: { pageKey: key, lang: 'en' },
    })
    // Spanish: path always has the slug
    paths.push({
      params: { path: toParam(langPaths.es) },
      props: { pageKey: key, lang: 'es' },
    })
  }
  return paths
}

// COMPONENT_MAP — maps page keys to page components
const COMPONENT_MAP = {
  home: Home,
  blog: Blog,
  portfolio: Portfolio,
  contact: Contact,
  // ... one entry per route
}

const { pageKey, lang } = Astro.props
const PageComponent = COMPONENT_MAP[pageKey as keyof typeof COMPONENT_MAP]
---

{PageComponent && <PageComponent lang={lang} pageKey={pageKey} />}
```

This generates 2 × N pages, where N is the number of route entries. Every page receives `lang` and `pageKey` as props.

## 6. Utility Functions (`src/lib/i18n/utils.ts`)

The core i18n logic — URL parsing, path resolution, and the translation function.

### getLangFromUrl
```typescript
import { defaultLang, supportedLangs } from './ui'

export function getLangFromUrl(url: URL) {
  const [, firstSegment] = url.pathname.split("/");
  if ((supportedLangs as string[]).includes(firstSegment) && firstSegment !== defaultLang) return firstSegment;
  return defaultLang;
}
```

Simple rule: if the URL starts with a non-default supported prefix (`/es`, `/fr`), it's that language. Everything else is the default language. Works because default-language paths have no prefix.

### getLocalizedPath
```typescript
export function getLocalizedPath(pageKey: string, lang: keyof typeof ui) {
  const path = routes[pageKey as keyof typeof routes]?.[lang];
  return path === undefined ? "/" : `/${path}`;
}
```

Looks up the route for the given page and language. Returns `"/"` for undefined paths (the English home page).

### getTranslations — The `t()` Function
```typescript
export function getTranslations(lang: keyof typeof ui) {
  return function t(key: string, vars?: Record<string, string>) {
    const keys = key.split(".");
    let value: any = ui[lang];

    // Walk the nested JSON structure
    for (const k of keys) {
      value = value?.[k];
      if (value === undefined) break;
    }

    // Fallback to default language
    if (value === undefined) {
      let fallbackValue: any = ui[defaultLang];
      for (const k of keys) {
        fallbackValue = fallbackValue?.[k];
        if (fallbackValue === undefined) break;
      }
      value = fallbackValue;

      if (value === undefined) {
        if (import.meta.env.DEV) {
          console.error(`[i18n] Missing translation key: "${key}"`);
          return `MISSING: ${key}`;
        }
      }
    }

    // Variable interpolation: replaces {name} with provided values
    if (typeof value === "string" && vars) {
      Object.entries(vars).forEach(([k, v]) => {
        value = value.replace(new RegExp(`{${k}}`, "g"), v);
      });
    }

    return value;
  };
}
```

### Reusable Helper for Static Paths

For pages outside the catch-all router (e.g., blog pages, API routes):

```typescript
// src/lib/utils.ts
export async function getStaticPathsLangs() {
  return [{ params: { lang: "es" } }, { params: { lang: "en" } }];
}
```

## 7. Usage in Components

Keys named `description`/`hint`/`body`/`content`/`bio` render as markdown via [astro-markdown#6-data-source-variants](./astro-markdown.md#6-data-source-variants) (`Markdown` atom or `renderInline`); keys named `title`/`label`/`cta`/`nav.*` stay plain `{t("…")}`.

### Astro Components
```astro
---
import { getTranslations } from '@/lib/i18n/utils'
const { lang } = Astro.props
const t = getTranslations(lang)
---
<h1>{t('pages.home.title')}</h1>
<p>{t('pages.home.description')}</p>
```

### React Components

Translations are passed as props from the parent Astro component. React never imports the i18n system directly.

**Astro page passes translations:**
```astro
---
const t = getTranslations(lang)
---
<BookingForm translations={t('global.booking')} client:idle />
```

**React component receives them:**
```tsx
interface Props {
  translations: any;
}
export default function BookingForm({ translations }: Props) {
  return (
    <div>
      <h2>{translations.title}</h2>
      <label>{translations.labels.leavingFrom}</label>
    </div>
  );
}
```

This keeps React components pure — no dependency on the i18n system, simpler testing, and less JS shipped.

### Language Switcher
The language switcher toggles between the current language and its alternate. `LangBtns` is self-sufficient: it derives `lang` and `pageKey` from the current URL, so it needs no props forwarded from the page, layout, or header. Explicit props (e.g. on the design-system showcase) still override derivation:

```astro
---
import { getLangFromUrl, getLocalizedPath, getPageKeyFromUrl } from '@/lib/i18n/utils'

const lang = Astro.props.lang ?? getLangFromUrl(Astro.url)
const pageKey = Astro.props.pageKey ?? getPageKeyFromUrl(Astro.url)
// pageKey is null on non-localized URLs (showcase, offline): stay on the same
// pathname and only swap the lang prefix instead of linking home.
const esUrl = pageKey ? getLocalizedPath(pageKey, 'es') : `/es${Astro.url.pathname}`
const enUrl = pageKey ? getLocalizedPath(pageKey, 'en') : Astro.url.pathname.replace(/^\/es(?=\/|$)/, '') || '/'
---
```

### URL-Derived Page Context
`getPageKeyFromUrl(url)` in `src/lib/i18n/utils.ts` reverse-maps the current URL to its `pageKey` by iterating the `routes` table (data-driven, so new pages resolve with no code change). `Layout`, `Header`, `Footer`, and `LangBtns` receive no i18n props: each derives `lang` from `getLangFromUrl(Astro.url)` (and `LangBtns` also derives `pageKey`), so no page context flows through the `[...path].astro` → `Layout` → component prop chain. Only `[...path].astro` keeps `lang`/`pageKey` internally, passing them to the page component (`Home`) for translations and SEO.

```typescript
export function getPageKeyFromUrl(url: URL): PageKey | null {
  const lang = getLangFromUrl(url);
  const pathname = url.pathname.length > 1 ? url.pathname.replace(/\/$/, '') : url.pathname;
  for (const [key, localized] of Object.entries(routes)) {
    if (getLocalizedPath(key, lang) === pathname) return key as PageKey;
  }
  return null; // unknown URL (e.g. /design-system, /offline): caller stays on the same URL instead of linking home
}
```

## 8. SEO Localization (`BaseSEO.astro`)

The SEO component (see [astro-seo](./astro-seo.md)) automatically resolves metadata based on `pageKey` and `lang`:

```astro
---
const t = getTranslations(lang)
const i18nTitle = currentPage ? t(`pages.${currentPage}.title`) : undefined
const i18nDesc = currentPage ? t(`pages.${currentPage}.description`) : undefined
const i18nKeywords = currentPage ? t(`pages.${currentPage}.keywords`) : undefined
const canonicalPath = getLocalizedPath(currentPage, lang)
const canonicalUrl = `${BUSINESS_DATA.url}${canonicalPath}`
---
```

It also auto-generates `<link rel="alternate" hreflang="..." href="...">` tags using `getLocalizedPath(currentPage, "en")` and `getLocalizedPath(currentPage, "es")`.

## 9. Build-Time Validation (Mandatory)

Catches missing translation keys before deployment. Runs as part of the build pipeline — if translation files are out of sync, the build fails.

### Architecture

The validation script runs with `tsx`, so it must be installed first:

```bash
pnpm add -D tsx
```

```
pnpm run build
  ├── pnpm run validate-i18n
  │     └── tsx scripts/validate-i18n.ts
  │           ├── reads src/messages/en.json
  │           ├── reads src/messages/es.json
  │           ├── flattenKeys() — recursively extracts all dotted keys
  │           ├── compares sets (enKeys vs esKeys)
  │           ├── match? → exit 0, continue to astro build
  │           └── mismatch? → exit 1, fail build with report
  └── pnpm run validate-imports
        └── tsx scripts/validate-imports.ts
              ├── scans src/**/*.{astro,ts,tsx}
              ├── flags relative project imports (`from './'`, `from '../'`, `import('./')`, bare `import './'`)
              ├── clean? → exit 0, continue to astro build
              └── offenders? → exit 1, fail build with report
```

### The Validation Script

```ts
// scripts/validate-i18n.ts
import fs from "node:fs";
import path from "node:path";

const messagesDir = path.resolve("src/messages");

const readMessages = (lang: string) => {
  const filePath = path.join(messagesDir, `${lang}.json`);
  if (!fs.existsSync(filePath)) {
    console.error(`❌ Message file not found: ${filePath}`);
    process.exit(1);
  }
  const content = fs.readFileSync(filePath, "utf-8");
  try {
    return JSON.parse(content);
  } catch (e) {
    console.error(`❌ Invalid JSON in ${filePath}`);
    process.exit(1);
  }
};

const flattenKeys = (obj: any, prefix = ""): string[] => {
  return Object.keys(obj).reduce((acc: string[], key: string) => {
    const value = obj[key];
    const newKey = prefix ? `${prefix}.${key}` : key;
    if (typeof value === "object" && value !== null) {
      return [...acc, ...flattenKeys(value, newKey)];
    }
    return [...acc, newKey];
  }, []);
};

const en = readMessages("en");
const es = readMessages("es");

// N-lang directory scan — every `src/messages/*.json` must share the same key
// set. Adding `fr.json` (plus ui.ts + routes.ts entries) is the whole diff;
// no script change needed. The legacy en/es report below runs after the
// generic loop (kept intentionally for a focused two-language diff).
const messageFiles = fs.readdirSync(messagesDir).filter((f) => f.endsWith(".json"));
const keySets = new Map(messageFiles.map((f) => [f, new Set(flattenKeys(readMessages(f.replace(/\.json$/, ""))))]));
const reference = keySets.get("en.json") ?? [...keySets.values()][0];

for (const [file, keys] of keySets) {
  const missing = [...reference].filter((k) => !keys.has(k));
  const extra = [...keys].filter((k) => !reference.has(k));
  if (missing.length > 0 || extra.length > 0) {
    console.error(`❌ i18n validation failed! ${file} is out of sync.`);
    missing.forEach((k) => console.error(`  missing: ${k}`));
    extra.forEach((k) => console.error(`  extra: ${k}`));
    process.exit(1);
  }
}

const enKeys = keySets.get("en.json")!;
const esKeys = keySets.get("es.json") ?? new Set<string>();

const missingInEs = [...enKeys].filter((k) => !esKeys.has(k));
const missingInEn = [...esKeys].filter((k) => !enKeys.has(k));

if (missingInEs.length > 0 || missingInEn.length > 0) {
  console.error("❌ i18n validation failed! Translation files are out of sync.");

  if (missingInEs.length > 0) {
    console.error("\nMissing in es.json:");
    missingInEs.forEach((k) => console.error(`  - ${k}`));
  }

  if (missingInEn.length > 0) {
    console.error("\nMissing in en.json:");
    missingInEn.forEach((k) => console.error(`  - ${k}`));
  }

  process.exit(1);
}

console.log("✅ i18n validation passed!");
```

### What it checks
- **Structural match**: Every dotted key must exist in every `src/messages/*.json` (N-lang, not just en/es)
- **JSON validity**: Invalid JSON causes immediate failure
- **File existence**: Missing message file causes immediate failure

### What it does NOT check
- Content accuracy (automatic translation quality)
- Placeholder variable consistency (`{name}` in source, `{nombre}` in target — up to you)
- Runtime behavior (the fallback to default language still works at runtime)

### Build Pipeline Integration

```json
// package.json — canonical trio lives in astro-base-config §3; pick per layers present.
// Base: "build". +i18n: "build:i18n". +i18n+markdown: "build:full".
{
  "scripts": {
    "dev": "portless run pnpm astro dev"  # canonical: portless run (see base-config/portless docs),
    "build": "pnpm validate-imports && astro build",
    "build:i18n": "pnpm validate-i18n && pnpm validate-imports && astro build",
    "build:full": "pnpm validate-i18n && pnpm validate-imports && astro build && pnpm validate-markdown",
    "validate-i18n": "tsx scripts/validate-i18n.ts",
    "validate-imports": "tsx scripts/validate-imports.ts",
    "validate-markdown": "tsx scripts/validate-markdown.ts",
    "preview": "astro preview"
  }
}
```

`validate-markdown` runs post-build (scans `dist/`) → see [astro-markdown#10-validation-build-wiring](./astro-markdown.md#10-validation-build-wiring).

> Canonical scripts live in [astro-base-config](./astro-base-config.md) §3. Validators are conditional: `validate-i18n` only with this layer, `validate-markdown` only with the Markdown layer, `validate-imports` always.

The `build` command runs validation **before** the Astro build. This means:
- No partial build output if translations are broken
- No cross-directory relative imports reach the build
- CI/CD pipelines fail fast with a clear error
- Developers discover issues on `pnpm run build`, not in production

### What validate-imports checks

`validate-imports` enforces the `@/` path alias convention across `src/**/*.{astro,ts,tsx}`. It scans every source file for relative project imports — single-dot `from "./..."`, `import("./...")`, bare `import "./..."`, and parent `from "../..."` — and fails the build if any are found. This bans `./` and `../` imports in favor of the `@/` alias (e.g. `@/lib/utils`), keeping imports stable when files move directories. The one exception is the Astro config file (`astro.config.mjs`), which is loaded directly by Node and cannot resolve `@/` — it uses a relative import. Because it runs on `tsx`, install it first: `pnpm add -D tsx`.

### Example Output

**Success:**
```
✅ i18n validation passed!
```

**Failure:**
```
❌ i18n validation failed! Translation files are out of sync.

Missing in es.json:
  - pages.home.bannerTitle
  - global.footer.columns.destinations.links.5.text

Missing in en.json:
  - pages.home.bannerSubtitle
```

### CI/CD Integration

```yaml
# .github/workflows/deploy.yml
jobs:
  build:
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - run: pnpm install
      - run: pnpm validate-i18n  # explicit check
      - run: pnpm build           # will also run validate-i18n and validate-imports
```

## 10. New Project Setup

```bash
# 1. Create directory structure
mkdir -p src/messages
mkdir -p src/lib/i18n
mkdir -p scripts

# 2. Create translation files
touch src/messages/en.json
touch src/messages/es.json

# 3. Create core files
touch src/lib/i18n/ui.ts
touch src/lib/i18n/routes.ts
touch src/lib/i18n/utils.ts

# 4. Create catch-all router
touch src/pages/\[...path\].astro

# 5. Create validation script (mandatory)
touch scripts/validate-i18n.ts
pnpm add -D tsx
```

Then:
1. Write translation files with identical key structure across languages (section 2)
2. Configure languages in `ui.ts` (section 3)
3. Define routes in `routes.ts` (section 4)
4. Implement utilities in `utils.ts` (section 6)
5. Set up catch-all router with `COMPONENT_MAP` (section 5)
6. Add the validation scripts from section 9
7. Wire into `package.json`: `"build": "pnpm validate-i18n && pnpm validate-imports && astro build"`

## 11. Key Rules

- English paths have **no prefix** (home is root), Spanish has `/es/` prefix (e.g. `/es`)
- Home page English path is `""` (root), Spanish is `"es"`
- `Layout`, `Header`, `Footer`, and `LangBtns` derive page context from the URL (`getLangFromUrl`, `getPageKeyFromUrl`) — no i18n props flow through the `[...path].astro` → `Layout` → component chain
- `lang`/`pageKey` are passed only from `[...path].astro` to the page component (`Home`) for translations and SEO; the standalone page component is the translation boundary
- React components receive translations as **props**, never import i18n directly
- Build-time validation is **mandatory** — wire it into the build pipeline on day one
- Legacy redirects handle old `/en/...` URL patterns
- Enforce `@/` path aliases via `validate-imports` — bans `./` and `../` project imports, keeping imports stable when files move directories

## 12. Connection to Other Patterns

- SEO metadata uses i18n keys for page titles/descriptions/keywords → see [astro-seo](./astro-seo.md)
- React islands receive translations as props → see [astro-react-islands](./astro-react-islands.md)
- Language-specific business data (e.g. vehicle features) follows the same pattern → see [astro-site-config](./astro-site-config.md)
- i18n + Client Router (View Transitions) behavior — localized links, `<html lang>` updates, hreflang swaps → see [astro-client-side-page-transitions](./astro-client-side-page-transitions.md)
