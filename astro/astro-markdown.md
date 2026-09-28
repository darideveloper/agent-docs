---
created: 2026-09-09
tags:
  - astro
  - markdown
  - documentation
type: resource
status: active
source: templates://astro/astro-markdown.md
version: 2026-09-27+57b0fd3

---

# Markdown Rendering System for Astro

> **Opt-in layer.** Precondition: [Base config](./astro-base-config.md) (`@/` alias). Skip if all strings are plain text.

One build-time markdown pipeline for every prose surface: CMS/API long text, blog content, and markdown authored inside translation files. Single engine (`marked` + GFM + `breaks: true`), two render modes (block atom vs inline helper), plain-text SEO fallback, optional code-copy button, fail-build check (warn-only variant for live CMS feeds).

This doc is generic: copy it into any Astro project. Every section states its precondition. Pick one variant per section — they compose independently.

> Convention in this doc: `@/` means `./src/*` (see §1). `example.com` is your site. `en`/`es` are example languages — the pattern scales to any set.

> See also: `[astro-i18n](./astro-i18n.md)` (translation files, `t()` lookup, localized routing) and `[astro-seo](./astro-seo.md)` (SEO component hierarchy, canonical/OG wiring) — this doc assumes one of those systems (or an equivalent) wherever a variant lists it as a precondition.

## 0. Prerequisites + decision tree

You need this system if **any** of these are true:

- CMS or API returns raw markdown (`bio`, `description`, `content` fields).
- Translation JSON contains markdown (`**bold**`, links, lists).
- Blog posts are stored as markdown.

You do **not** need it if all strings are plain text — keep rendering `{t("…")}` directly.

### Block vs inline — the only decision that matters

```
Is the output going into a standalone prose block (<div>/<section>/<article>)?
├── YES → block atom (§4): <Markdown content={…} />
└── NO (inside <p>, <h1>, <span>, <a>, card title, slot text)
    └── use renderInline() + parent set:html (§7)
```

Rule: never put the block atom inside a `<p>`. Never use `renderInline` for multi-paragraph bodies (lists/headings pass through un-unwrapped — that's by design, use the atom instead).

### Variant picker

| Your project has… | Read |
|---|---|
| Pages authored as local `.md` files (Content Collections) | §2 + §4 + §6 Variant F |
| No API, no i18n — just markdown strings | §2 + §4 + one of §3 |
| Translation files (JSON) | + §6 Variant B |
| API with `{ es: {…}, en: {…} }` dicts | + §6 Variant C |
| API with flat `title_es` / `title_en` columns | + §6 Variant D |
| SEO meta descriptions from markdown sources | + §8 |
| Fenced code blocks in content | + §9 |
| Want CI guard against stray `**` | + §10 |

## 1. Global setup variants

### 1.1 Dependencies

```bash
pnpm add marked
```

`marked` v15 uses a **token-object** renderer API (`renderer.heading = (token) => …` where `token = { text, raw, depth, href, … }`). Older tutorials show the string-args form — do not mix them.

### 1.2 Variant A — minimal (no layout changes)

Works if you only need markdown in one or two components:

- No layout edit needed.
- Style with Tailwind `prose-*` classes inline in the atom (§4) — no shared CSS file required.

### 1.3 Variant B — standard (recommended for 3+ prose surfaces)

1. Path alias so `@/lib/markdown` resolves. In `tsconfig.json`:

```json
{
  "extends": "astro/tsconfigs/strict",
  "compilerOptions": {
    "baseUrl": ".",
    "paths": { "@/*": ["./src/*"] }
  }
}
```

2. Import global CSS once in your layout (`src/layouts/Layout.astro`):

```astro
---
import "@/styles/global.css"
---
<html>
  <head>
    <meta charset="utf-8" />
    <slot name="seo" />
  </head>
  <body>
    <slot />
  </body>
</html>
```

The `<slot name="seo" />` in `<head>` is only needed if you use §8 (SEO component). Otherwise a plain `<slot />` body is enough.

3. Set `site` in `astro.config.mjs` if you emit canonical/OG URLs (needed only for §8):

```ts
export default defineConfig({
  site: "https://example.com",
})
```

## 2. Core engine: `src/lib/markdown.ts`

Create this file verbatim. It is the **only** place that imports `marked`. Everything else imports from here.

```ts
// Shared build-time markdown rendering. Trusted content — no sanitization,
// raw HTML passes through. See §11 before reusing with untrusted input.
import { marked } from "marked"

export interface MarkdownOptions {
  copyLabel?: string
  copiedLabel?: string
}

function buildRenderer(copyLabel: string, copiedLabel: string) {
  // Custom renderer — ids, lazy images, external link affordance,
  // code lang badge + copy button (marked 15 token API)
  const renderer = new marked.Renderer() as any
  renderer.heading = (token: any) => {
    const text: string = token.text ?? ""
    const depth: number = token.depth ?? 1
    const lvl = depth === 1 ? 2 : depth // h1 → h2: page owns the single h1
    // Slugify parsed text (not raw: raw includes `##` + markdown syntax).
    const slug =
      String(text).toLowerCase().replace(/<[^>]*>/g, "").replace(/[^\w]+/g, "-").replace(/^-|-$/g, "") ||
      `h-${lvl}`
    return `<h${lvl} id="${slug}" class="scroll-mt-24"><a href="#${slug}" class="no-underline hover:text-[YOUR_ACCENT] transition-colors">${text}</a></h${lvl}>\n`
  }
  renderer.image = (token: any) => {
    const href: string = token.href ?? ""
    const text: string = token.text ?? ""
    const titleAttr: string | null = token.title ?? null
    const titlePart = titleAttr ? ` title="${titleAttr}"` : ""
    const img = `<img src="${href}" alt="${text}"${titlePart} loading="lazy" decoding="async" />`
    if (text && text.length > 12) {
      return `<figure>${img}<figcaption>${text}</figcaption></figure>`
    }
    return img
  }
  renderer.link = (token: any) => {
    const href: string | null = token.href ?? null
    const titleAttr: string | null = token.title ?? null
    const text: string = token.text ?? ""
    const isExternal = href?.startsWith("http")
    const attrs = isExternal ? ` target="_blank" rel="noopener noreferrer"` : ""
    const titlePart = titleAttr ? ` title="${titleAttr}"` : ""
    const ext = isExternal ? ` <span aria-hidden="true">↗</span>` : ""
    return `<a href="${href ?? "#"}"${titlePart}${attrs}>${text}${ext}</a>`
  }
  renderer.code = (token: any) => {
    const code: string = token.text ?? ""
    const langCode: string = (token.lang ?? "").trim().split(/\s+/)[0] ?? ""
    const escaped = code.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    const badge = langCode ? `<span class="code-lang">${langCode}</span>` : ""
    return `<div class="code-block"><pre><code class="language-${langCode}">${escaped}</code></pre>${badge}<button type="button" class="code-copy" data-copy data-copy-label="${copyLabel}" data-copied-label="${copiedLabel}" aria-label="${copyLabel}">${copyLabel}</button></div>`
  }
  return renderer
}

/** Block markdown → HTML (GFM, single `\n` → `<br>`). */
export function renderMarkdown(
  md: string | null | undefined,
  opts: MarkdownOptions = {},
): string {
  const { copyLabel = "Copy", copiedLabel = "Copied!" } = opts
  const renderer = buildRenderer(copyLabel, copiedLabel)
  return marked.parse(md ?? "", { renderer, gfm: true, breaks: true }) as string
}

/** Inline markdown → HTML without the outer `<p>`, for `<h1>`/`<span>`/card contexts. */
export function renderInline(
  md: string | null | undefined,
  opts: MarkdownOptions = {},
): string {
  const html = renderMarkdown(md, opts).trim()
  const m = html.match(/^<p>([\s\S]*)<\/p>$/)
  return m ? m[1] : html
}

/** Markdown → plain text, for `<meta name="description">` so `**`/links never leak into SEO. */
export function stripMarkdown(md: string | null | undefined): string {
  return (md ?? "")
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/(\*\*|__)(.*?)\1/g, "$2")
    .replace(/~~(.*?)~~/g, "$1")
    .replace(/`([^`]*?)`/g, "$1")
    .replace(/(^|\s)[*_]([^*_]+?)[*_](?=\s|$)/g, "$1$2")
    .replace(/^#{1,6}\s+/gm, "")
    .replace(/^>\s?/gm, "")
    .replace(/^(\s*)[-*+]\s+/gm, "$1")
    .replace(/\s+/g, " ")
    .trim()
}
```

Key behaviors to know:

- `breaks: true` — a single newline becomes `<br>`. Changing this later reflows all existing content; decide once.
- `md ?? ""` — `null`/`undefined`/empty all render as `""`, never crash. Plain text without syntax returns a safe `<p>…</p>` wrapper.
- `renderInline` strips **one** outer `<p>`. Multi-block input (headings, lists) is returned whole — put those through the block atom instead.
- No sanitization. Raw HTML in the source passes through to `set:html` untouched (§11).

## 3. Renderer variants (pick one)

All variants live in `buildRenderer` above. Delete what you don't need.

### 3.1 Minimal — plain `marked`, no custom renderer

Precondition: no heading anchors, no figure captions, no copy buttons needed.

```ts
export function renderMarkdown(md: string | null | undefined): string {
  return marked.parse(md ?? "", { gfm: true, breaks: true }) as string
}
```

Skip §9 entirely with this variant.

### 3.2 Standard — anchors + lazy images + external `↗`

Precondition: editorial content with headings/images/links, but no fenced code blocks.

Keep `renderer.heading`, `renderer.image`, `renderer.link` from §2. Delete `renderer.code` and the `MarkdownOptions` interface (no labels needed).

### 3.3 Full — add code badge + copy button

Precondition: fenced code blocks appear in content. This is §2 verbatim, plus §9 (copy handler) and `.code-block` CSS (§5). Labels come from `MarkdownOptions` so each page can localize them:

```astro
---
import { renderMarkdown } from "@/lib/markdown"
const html = renderMarkdown(content, { copyLabel: "Copy", copiedLabel: "Copied!" })
---
```

## 4. Block atom: `src/components/atoms/Markdown.astro`

Precondition: §2 exists. Use for every standalone prose block.

```astro
---
import { renderMarkdown } from "@/lib/markdown"

export interface Props {
  content?: string | null
  class?: string
  variant?: "default" | "compact" | "on-dark"
  dropcap?: boolean
  copyLabel?: string
  copiedLabel?: string
}

const {
  content,
  class: className,
  variant = "default",
  dropcap = false,
  copyLabel,
  copiedLabel,
} = Astro.props
const html = renderMarkdown(content ?? "", { copyLabel, copiedLabel })
// Sizing/width/color stay with the caller via `class` —
// only `prose-*` element styles are baked in here.
// NOTE: chain trimmed for brevity — expand spacing/typography from your
// design system (the full chain also covers h2/h3/h4 sizes, blockquote
// margins, pre/code surfaces, table headers/cells, figcaptions, list markers).
const prose = "prose-headings:font-serif prose-p:leading-[1.85] prose-p:mb-6 prose-a:underline prose-a:underline-offset-4 prose-strong:font-semibold prose-em:italic prose-blockquote:border-l-2 prose-blockquote:pl-5 prose-blockquote:italic prose-img:my-10 prose-img:mx-auto prose-img:block prose-code:text-[12px] prose-code:px-1.5 prose-code:py-0.5 prose-pre:p-0 prose-pre:overflow-hidden prose-ul:list-disc prose-ul:pl-6 prose-ul:my-6 prose-ol:list-decimal prose-ol:pl-6 prose-ol:my-6 prose-li:my-2 prose-table:w-full prose-table:border-collapse prose-table:my-8 prose-th:text-left prose-th:px-4 prose-th:py-3 prose-td:px-4 prose-td:py-3 prose-td:align-top"
---

<div
  class:list={["markdown-prose", prose, variant !== "default" && `markdown-prose--${variant}`, dropcap && "markdown-prose--dropcap", className]}
  set:html={html}
/>

<script>
  import { attachCodeCopy } from "@/lib/code-copy"
  attachCodeCopy()
  document.addEventListener("astro:page-load", () => attachCodeCopy())
</script>
```

Usage:

```astro
---
import Markdown from "@/components/atoms/Markdown.astro"
---
<Markdown content={description} class="text-[15px] leading-[1.85] max-w-[560px]" />
```

Variants:

| `variant` | When | CSS hook (§5) |
|---|---|---|
| `default` | light surfaces | none |
| `compact` | optional, reserved for dense contexts (cards, banners) — omit if unused | `.markdown-prose--compact` tightens p/ul/figure |
| `on-dark` | dark surfaces | `.markdown-prose--on-dark` flips headings/body to light |
| `dropcap` | editorial article openers only | `.markdown-prose--dropcap` styles `p:first-of-type::first-letter` |

Sizing, width, and color always come from the caller's `class` — the atom owns element typography only.

## 5. Styles variant

### 5.1 Variant A — Tailwind-only (no CSS file)

The `prose-*` chain in §4 is the whole styling. It requires the Tailwind Typography plugin:

```bash
pnpm add -D @tailwindcss/typography
```

Without the plugin the `prose-*` classes do nothing — use §5.2 shared CSS or your own equivalents instead. Sufficient for short bios/descriptions once the plugin is present.

### 5.2 Variant B — shared `markdown-prose` CSS (recommended for 3+ surfaces)

Gives blog bodies, bios, and descriptions one style source, including things `prose-*` doesn't cover: `h2::before` accent bar, `figure/figcaption`, nested lists, `hr::after` ornament, table scrollbars, `blockquote cite`, `.code-block/.code-lang/.code-copy`, responsive `iframe/video`, drop-cap.

Adapt every color/spacing value below to your own design tokens (e.g. `[YOUR_ACCENT]` → your accent color, margins → your scale) — the values shown are illustrative.

In `src/styles/global.css` (imported once per §1.3):

```css
/* Shared prose. `.blog-prose` is a migration-only legacy alias — delete it
   unless a blog template still uses it. New code uses `markdown-prose` only. */
.blog-prose h2, .markdown-prose h2 { /* size, tracking, margins */ }
.blog-prose h2::before, .markdown-prose h2::before {
  content: ""; display: block; width: 28px; height: 2px; background: [YOUR_ACCENT];
}
.blog-prose figure, .markdown-prose figure { margin: 2.5rem auto; }
.blog-prose figcaption, .markdown-prose figcaption {
  text-align: center; font-size: 11px; text-transform: uppercase;
  letter-spacing: 0.08em; padding: 0.75rem 1rem;
}
.blog-prose ul ul, .markdown-prose ul ul { margin: 0.5rem 0; }
.blog-prose hr, .markdown-prose hr { border: 0; border-top: 1px solid; margin: 2.5rem 0; }
.blog-prose table, .markdown-prose table { width: 100%; border-collapse: collapse; }
.blog-prose .code-block, .markdown-prose .code-block { position: relative; }
.blog-prose .code-lang, .markdown-prose .code-lang {
  position: absolute; top: 0; right: 0; font-size: 11px; padding: 0.25rem 0.5rem;
}
.blog-prose .code-copy, .markdown-prose .code-copy {
  position: absolute; bottom: 0.5rem; right: 0.5rem; font-size: 11px;
}
.blog-prose iframe, .blog-prose video,
.markdown-prose iframe, .markdown-prose video { width: 100%; aspect-ratio: 16/9; }

/* Variants */
.markdown-prose--compact p,
.markdown-prose--compact ul,
.markdown-prose--compact ol { margin-top: 0.75rem; margin-bottom: 0.75rem; }
.markdown-prose--compact figure,
.markdown-prose--compact .code-block { margin-top: 1rem; margin-bottom: 1rem; }
.markdown-prose--on-dark h1, .markdown-prose--on-dark h2,
.markdown-prose--on-dark h3, .markdown-prose--on-dark h4,
.markdown-prose--on-dark p, .markdown-prose--on-dark li,
.markdown-prose--on-dark strong, .markdown-prose--on-dark em { color: white; }
.markdown-prose--on-dark blockquote { opacity: 0.85; }
.blog-prose > p:first-of-type::first-letter,
.markdown-prose--dropcap > p:first-of-type::first-letter {
  font-size: 3.2em; float: left; line-height: 1; padding-right: 0.1em;
}
```

## 6. Data-source variants (pick what your project has)

Language selection always happens **before** markdown parsing: resolve the string for the active language first, then call `renderMarkdown`/`renderInline`/`Markdown` on the result. Titles and names stay plain text — only `bio`/`description`/`content`/`hint` prose fields go through markdown.

### Variant A — plain string (no i18n, no API)

```astro
---
import Markdown from "@/components/atoms/Markdown.astro"
const description = "Our studio works in **small batches**.\nVisit us [here](https://example.com)."
---
<Markdown content={description} />
```

### Variant B — translation files (JSON)

Precondition: `src/messages/{en,es}.json` + a `t(key)` lookup returning a string (any i18n helper works — dotted lookup, fallback language, `{var}` interpolation).

Author long prose keys as markdown, keep short keys plain:

```json
{
  "global": {
    "banner": {
      "certified": "**Certified** with each work",
      "shipping": "**Insured shipping** worldwide"
    }
  },
  "pages": {
    "blog": {
      "description": "News and stories from the studio",
      "noPostsHint": "Check back soon — **new stories** are on the way."
    }
  }
}
```

Render short banner proofs inline (§7), long hints inline or as blocks depending on context:

```astro
---
import { renderInline } from "@/lib/markdown"
---
<p set:html={renderInline(t("pages.blog.description"))} />
<p set:html={renderInline(t("pages.blog.noPostsHint"))} />
```

Rule of thumb: keys named `description`/`hint`/`body`/`content`/`bio` → markdown path. Keys named `nav.*`, `cta`, `eyebrow`, `label`, `title` → plain `{t("…")}`, no markdown call.

Fallback pattern (API-first, JSON-second) for pages that work with or without a backend:

```astro
---
const description = hero?.description ?? t("pages.home.hero.description")
---
<Markdown content={description} />
```

### Variant C — API with language-dict shape (`{ es: {…}, en: {…} }`)

Precondition: backend returns e.g. `translations: { es: { bio: "…" }, en: { bio: "…" } }`. Type it as `Partial<Record<Lang, T>>` so either side may be missing.

```ts
export type Lang = "es" | "en"
export type Translations<T> = Partial<Record<Lang, T>>

export function pickTranslation<T extends Record<string, string>>(
  translations: Translations<T> | undefined,
  lang: Lang,
  field: keyof T,
): string {
  const direct = translations?.[lang]?.[field]
  if (direct != null && direct !== "") return direct
  const fallback = translations?.[lang === "es" ? "en" : "es"]?.[field]
  if (fallback != null && fallback !== "") return fallback
  return ""
}
```

Usage — resolve per language, then render as a block:

```astro
---
import Markdown from "@/components/atoms/Markdown.astro"
import { pickTranslation } from "@/lib/i18n/utils"
const bio = pickTranslation(artist.translations, lang, "bio")
---
{bio && <Markdown content={bio} class="max-w-[560px]" />}
```

Typical fields: `bio`, `description`. Never markdown-render `name`/`title` through this path.

### Variant D — API with flat bilingual columns (`title_es`, `title_en`)

Precondition: backend returns flat fields (`title_es`, `title_en`, `description_es`, …). Do **not** model these as `Translations<T>` — the accessor is different and there is intentionally no cross-language fallback (empty stays empty).

```ts
import type { Lang } from "@/lib/api/types"

export function pickPostField(
  post: Record<string, string>,
  lang: Lang,
  key: string,
): string {
  return post[`${key}_${lang}`] ?? ""
}
```

```astro
---
import { pickPostField } from "@/lib/api/posts"
import { renderInline } from "@/lib/markdown"
const title = pickPostField(post, lang, "title")
const description = pickPostField(post, lang, "description")
---
<h3>{title}</h3>
{description && <p set:html={renderInline(description)} />}
```

Valid `key` values are whatever your API provides (`title`, `description`, `keywords`, `content`).

### Variant E — full article body (direct `renderMarkdown`)

Precondition: long-form markdown body needing custom layout around it (hero, meta row, aside) rather than a plain atom. Resolve the field per §6C/§6D first, optionally normalize, then parse once:

```astro
---
import Markdown from "@/components/atoms/Markdown.astro"
import { renderMarkdown, renderInline } from "@/lib/markdown"
const content = pickPostField(post, lang, "content")
const description = pickPostField(post, lang, "description")
const html = renderMarkdown(content, { copyLabel: "Copy", copiedLabel: "Copied!" })
---
{description && <Markdown content={description} class="border-l-2 pl-5 mb-8" />}
<div class="article-body" set:html={html} />
<aside>{description && <p set:html={renderInline(description)} />}</aside>
```

### Variant F — local `.md` files via Astro Content Collections

Precondition: pages are authored as files (legal pages, docs, changelog) rather than living in an API or translation JSON. Uses Astro's built-in Content Collections — only this variant touches `astro:content` / `astro/loaders`.

**1. Define the collection** — `src/content.config.ts` (project root, next to `astro.config.mjs`). Use the `glob()` loader so IDs match your file naming, not the default github-slug:

```ts
// src/content.config.ts
import { defineCollection, z } from "astro:content"
import { glob } from "astro/loaders"

const legal = defineCollection({
  loader: glob({
    pattern: "**/*.md",
    base: "./src/content/legal",
    generateId: ({ entry }) => entry.replace(/\.md$/, ""), // "<slug>.<lang>"
  }),
  schema: z.object({
    title: z.string(),
    description: z.string(),
    updated: z.string(),
  }),
})
export const collections = { legal }
```

**2. Author the files** with frontmatter + markdown body:

```markdown
---
title: "Privacy Policy"
description: "How we collect, use, and protect your data."
---
## Data controller
…
```

**3. Render a page** — `getCollection("legal")`, then look up the exact entry for the current `pageKey`/`lang`. **Throw at build if a language file is missing** — no silent fallback (a missing translation is a bug worth failing on):

```astro
---
import { getCollection } from "astro:content"
import Markdown from "@/components/atoms/Markdown.astro"

const entries = await getCollection("legal")
const entry = entries.find((e) => e.id === `${pageKey}.${lang}`)
if (!entry) throw new Error(`Missing legal markdown file for ${pageKey}.${lang}`)
const { title, description, updated } = entry.data
---
<h1>{title}</h1>
<p>{description}</p>
<p class="text-sm text-muted">{updated}</p>
<Markdown content={entry.body} />
```

**4. Wire routing** — two options:

- **No i18n — standalone route component.** A route component emits one URL per entry (or per `${id}` pair) via `getStaticPaths()`. Because it already fetched the collection, pass the resolved `entry` down as a prop rather than re-querying in the page. The page component then accepts an `entry` prop and renders `entry.body` via `<Markdown>` (the step-3 snippet instead shows the fetch-by-id shape used when the page resolves its own entry from the catch-all):

```astro
---
// src/pages/legal/[slug].astro — one URL per localized markdown file.
import type { Page } from "astro"
import { getCollection } from "astro:content"
import LegalPage from "@/components/pages/legal/LegalPage.astro"

export const getStaticPaths: Page["getStaticPaths"] = async () => {
  const entries = await getCollection("legal")
  return entries.map((entry) => ({ params: { slug: entry.id }, props: { entry } }))
}

const { entry } = Astro.props
---
<LegalPage entry={entry} />
```

For a default-language-prefixed + unprefixed convention (e.g. `en/privacidad` and `privacidad` for the `es` default), emit **two** params per entry — one with the lang prefix, one without for the default language — or use a `getStaticPathsLangs`-style helper (see [astro-i18n](./astro-i18n.md) §5 for the mirror pattern).

- **With i18n** (multi-language): register the pageKey in your route map and let the catch-all `[...path].astro` / `getStaticPaths` handle it → [astro-i18n](./astro-i18n.md) §5. The schema above embeds `lang` in the ID (`<slug>.<lang>`), so each entry is the single source for one localized page.

## 7. Usage patterns

### 7.1 Block (default)

```astro
<Markdown content={bio} class="text-[15px] leading-[1.85] max-w-[560px]" />
```

### 7.2 Inline inside `<p>` / card / `<h1>` context

```astro
---
import { renderInline } from "@/lib/markdown"
---
<p class="line-clamp-2" set:html={renderInline(description)} />
```

The parent owns the element; the helper only supplies inner HTML. `**` → `<strong>` survives `line-clamp`.

### 7.3 Inline inside a slot (only when the child requires element children)

Some slot components reject raw strings. Then wrap in `<Fragment>`:

```astro
---
import { renderInline } from "@/lib/markdown"
---
<BannerText><Fragment set:html={renderInline(t("global.banner.certified"))} /></BannerText>
```

Prefer parent-level `set:html` (§7.2) everywhere else. Style both `b` and `strong` in the slot owner so legacy `<b>` content and new `<strong>` output match:

```css
.slot-owner strong, .slot-owner b { color: [YOUR_ACCENT]; font-weight: 600; }
```

## 8. SEO variant

### With SEO (recommended when meta descriptions come from markdown sources)

Strip markdown **once**, at the base SEO component, so no page can leak `**`/links into `<meta>`:

```astro
---
import { stripMarkdown } from "@/lib/markdown"
const resolvedDescription = stripMarkdown(description || fallbackDescription || SITE_DESCRIPTION)
---
<meta name="description" content={resolvedDescription} />
<meta property="og:description" content={resolvedDescription} />
```

Result: on-page quote shows `<strong>New</strong> workshop…` while meta contains `New workshop…`. Titles and keywords are passed through untouched.

### Without SEO

Skip this section. Nothing else in the system depends on `stripMarkdown`.

## 9. Code-copy variant

### With code blocks (§3.3)

Create `src/lib/code-copy.ts` (idempotent — safe to call on every navigation):

```ts
// Shared code-block copy handler. Idempotent: buttons are flagged after
// binding, safe to call on every navigation.
export function attachCodeCopy(root: ParentNode = document): void {
  root.querySelectorAll<HTMLButtonElement>(".code-copy[data-copy]").forEach((b) => {
    if ((b as any)._boundCopy) return
    ;(b as any)._boundCopy = true
    b.addEventListener("click", async () => {
      const block = b.closest(".code-block")
      const code = block?.querySelector("code")?.textContent ?? ""
      const copiedLabel = b.dataset.copiedLabel ?? "Copied!"
      try {
        await navigator.clipboard.writeText(code)
        const prev = b.textContent
        b.textContent = copiedLabel
        setTimeout(() => { b.textContent = prev }, 1200)
      } catch {
        // clipboard unavailable — leave label unchanged
      }
    })
  })
}
```

Both the atom (§4) and any direct-`renderMarkdown` page (§6E) include the same client script:

```astro
<script>
  import { attachCodeCopy } from "@/lib/code-copy"
  attachCodeCopy()
  document.addEventListener("astro:page-load", () => attachCodeCopy())
</script>
```

### Without code blocks (§3.1–3.2)

Delete `renderer.code`, skip this file and both script tags.

## 10. Validation + build wiring

Fail-build check for stray `**` (unmatched markdown renders verbatim per GFM). Default is strict (`exit 1`) so repo-owned translation JSON typos block deploy. Live-CMS/API projects should use the warn-only variant instead (keep `exit 0`) since that content is not repo-controlled. Must run AFTER `astro build` — it scans `dist/*.html`.

`scripts/validate-markdown.ts`:

```ts
import fs from "node:fs"
import path from "node:path"

// Flags leftover literal `**` markers in built HTML. Strict by default:
// fail-build (exit 1) for repo-owned content. For live CMS/API feeds,
// replace `process.exit(1)` with nothing (warn-only, exit 0).
const distDir = path.resolve("dist")

function listHtml(dir: string): string[] {
  if (!fs.existsSync(dir)) return []
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) return listHtml(full)
    return full.endsWith(".html") ? [full] : []
  })
}

function stripBlocks(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<style[\s\S]*?<\/style>/gi, "")
    .replace(/<pre[\s\S]*?<\/pre>/gi, "")
    .replace(/<code[\s\S]*?<\/code>/gi, "")
}

const flagged: string[] = []
for (const file of listHtml(distDir)) {
  const raw = fs.readFileSync(file, "utf-8")
  const text = stripBlocks(raw)
  const rel = path.relative(process.cwd(), file)
  const seen = new Set<string>()
  for (const m of text.matchAll(/\*\*/g)) {
    const i = m.index ?? 0
    const snip = text.slice(Math.max(0, i - 60), i + 60).replace(/\s+/g, " ").trim()
    if (!seen.has(snip)) {
      seen.add(snip)
      flagged.push(`${rel}  …${snip}…`)
      if (seen.size >= 3) break
    }
  }
}

if (flagged.length > 0) {
  console.error("Leftover literal `**` markers found in built HTML:")
  flagged.forEach((line) => console.error(`  - ${line}`))
  console.error("Fix the content source text (stray `**`), not the renderer.")
  process.exit(1)
} else {
  console.log("Markdown validation passed! No leftover `**` markers in built HTML.")
}
```

Wire into `package.json` (reuses `tsx` from the i18n system; must run after `astro build` since it scans `dist/`):

```json
{
  "scripts": {
    "build": "pnpm validate-i18n && pnpm validate-imports && astro build && pnpm validate-markdown",
    "validate-markdown": "tsx scripts/validate-markdown.ts"
  }
}
```

## 11. Content-authoring rules + pitfalls

Authoring rules (give these to editors, not just developers):

- `**bold**`, `*italic*`, `[links](https://…)`, lists, `## headings`, `> quotes`, tables, and fenced code blocks all render.
- A single newline becomes `<br>` (`breaks: true`). A blank line starts a new paragraph.
- Unmatched `**` renders literally — fix the source text, never the renderer (§10 flags these).
- Titles and names are plain text — no markdown there, even if the renderer would accept it.

Pitfalls (check before shipping):

- [ ] Every markdown output uses `set:html` (or `<Fragment set:html>` in slots). Without it, HTML shows escaped.
- [ ] No `<Markdown>` inside `<p>` — block-in-inline is invalid HTML and breaks hydration.
- [ ] `content ?? ""` everywhere — API `null` must render empty, never crash.
- [ ] `breaks: true` decided once — flipping it later reflows all content.
- [ ] Code-button labels localized per page (`copyLabel`/`copiedLabel`), not hardcoded in English.
- [ ] **Trusted content only.** This pipeline passes raw HTML through by design. If your source is untrusted (user comments, third-party feeds), sanitize `renderMarkdown` output with DOMPurify (or equivalent) before `set:html` — that variant is out of scope for this doc but is the required escape hatch.

## Appendix — optional blog-body extras (non-core)

Only needed for article pages with hero/meta/aside layouts. Skip for bios and descriptions.

**Leading-title dedupe:** CMS bodies sometimes repeat the page title as a first `# Heading`. Strip it before parsing so the title appears once (as the page `h1`):

```ts
function stripLeadingTitle(md: string, title: string): string {
  if (!md || !title) return md
  const norm = (s: string) => s.trim().toLowerCase().replace(/\s+/g, " ")
  if (!norm(title)) return md
  const stripped = md.replace(/^\s*(?:---\n[\s\S]*?---\n)?\s*/, "")
  const m = stripped.match(/^(#{1,6})\s+(.+?)\s*\n+/)
  if (!m) return md
  const headingText = m[2].replace(/\s*\{[^}]*\}\s*$/, "").trim()
  if (norm(headingText) === norm(title)) return stripped.slice(m[0].length)
  return md
}

const html = renderMarkdown(stripLeadingTitle(content, title), {
  copyLabel: "Copy",
  copiedLabel: "Copied!",
})
```

**Reading time:** `Math.max(1, Math.ceil(content.trim().split(/\s+/).length / 200))` (~200 wpm) over the raw markdown, before parsing.
