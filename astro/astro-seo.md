---
created: 2026-04-18
updated: 2026-07-26
tags:
  - astro
  - seo
  - documentation
type: resource
status: active
source: templates://astro/astro-seo.md
version: 2026-09-27+2a98280

---

# SEO Implementation & Best Practices

This document outlines the SEO strategy and implementation details for Astro-based projects. It covers metadata rendering, multimedia optimization, accessibility, and performance best practices to be used as a standard.

## 0. Prerequisites

Before proceeding, ensure the following infrastructure is in place:
- **Layout Shell:** Standard `Layout.astro` setup with `<slot name="seo" />` in `<head>`.
- **i18n (if applicable):** If your project has multiple languages, the i18n system is defined in [[astro-i18n]]. Skip this section if your project is single-language.
- **Markdown (if applicable):** If meta descriptions come from markdown sources, strip them via `stripMarkdown()` → see [[astro-markdown#8-seo-variant]]. Skip if all strings are plain text.
- **Centralized config:** Business data (name, URLs, contact) comes from a single config file → see [[astro-site-config]].
  Brand truth: `src/data/site-config.ts` (`BUSINESS_DATA`) is authoritative; `src/consts.ts` (`SITE_TITLE`/`SITE_DESCRIPTION`) is only the final SEO fallback re-export when no prop/i18n value resolves.

## 1. Dependencies

Install:

```text
@astrojs/sitemap                       # Automatic sitemap generation
sharp                                  # Image optimization (bundled with Astro)
```

`sharp` is a dependency (image pipeline), not an integration — no config entry. Then set `site` and `inlineStylesheets` in config:

```ts
export default defineConfig({
  site: 'https://example.com',
  build: {
    inlineStylesheets: "always",       // inline critical CSS, reduces HTTP requests
  },
  integrations: [
    sitemap(),
    react(), // only if React islands layer is used
  ],
})
```

Full merged config (Base + opt-ins) lives in [astro-base-config](./astro-base-config.md) — that file is the single source of truth; the snippet above is SEO-relevant excerpt only. This guide uses `marked` via the Markdown layer for markdown sources, not MDX.

## 2. Favicons & Icons

The project includes multiple favicon formats to ensure compatibility across all browsers and devices, prioritizing vector formats for modern displays.

### 2.1 Implementation

All brand icons are located in the `public/` directory for reliable root access:
- `favicon.svg`: **Primary icon.** Scalable vector icon for modern browsers.
- `favicon.ico`: **Legacy fallback.** A 32x32 MS Windows icon resource.
- `favicon.png`: **Standard PNG.** A 32x32 PNG version of the icon.
- `apple-touch-icon.png`: **iOS Home Screen.** A 180x180 PNG version optimized for iOS.
- `og-image.jpg`: **Open Graph image.** 1200x630px branded image for social sharing.

**Snippet (`Layout.astro`):**
```html
<link rel="icon" href="/favicon.ico" sizes="32x32" />
<link rel="icon" href="/favicon.svg" type="image/svg+xml" />
<link rel="apple-touch-icon" href="/apple-touch-icon.png" />
```

## 3. The SEO Component Hierarchy

All SEO metadata is handled by a **4-layer component hierarchy**. Each layer adds specificity while the base handles all the common work.

```
BaseSEO.astro (core engine)
├── Resolves title/desc/keywords: prop → i18n(pageKey) → SITE_TITLE constant → default
├── Auto-tagline: appends " | Business Name" for non-home pages (controlled by useTagLine)
├── Canonical URL: computed from routes.ts via getLocalizedPath()
├── hreflang alternates: auto-generated for all supported languages
├── Dynamic JSON-LD: switches @type based on jsonType prop
│   ├── LocalBusiness / TravelAgency → address, geo, openingHours, sameAs, areaServed
│   ├── TouristDestination → touristType, containedInPlace
│   ├── Service → provider, serviceType
│   ├── Blog → minimal blog schema
│   └── BlogPosting → headline, author, datePublished, image, url
├── extraJson prop: merges arbitrary schema extensions
├── OG / Twitter: og:locale from LOCALE_MAP, og:type mapped from jsonType
└── Robots: noIndex prop, sitemap link
│
├── PageSEO.astro (thin wrapper)
│   └── Props: currentPage, jsonType?, extraJson?, ogImage?
│
├── BlogSEO.astro (thin wrapper)
│   └── Props: currentPage
│   └── jsonType fixed to "Blog"
│
└── BlogPostSEO.astro (full wrapper)
    └── Props: postTitle, postExcerpt, postAuthor, postDate, postImageUrl, slug, alternateUrls
    └── Constructs extraJson for BlogPosting schema
```

### 3.1 BaseSEO.astro — The Core Engine

Every SEO component delegates to this one. It handles:

**Title Resolution Chain:**
```
1. Explicit title prop
2. i18n translation (pages.{currentPage}.title)
3. SITE_TITLE constant from consts.ts
4. Default fallback
```

**Description Resolution Chain:**
```
1. Explicit description prop
2. baseDescription prop
3. i18n translation (pages.{currentPage}.description)
4. SITE_DESCRIPTION constant
```
Strip the resolved value once via `stripMarkdown()` so markdown sources never leak `**`/links into `<meta>` → see [[astro-markdown#8-seo-variant]].

**Auto-Tagline Logic:**
```astro
{useTagLine && resolvedTitle !== BUSINESS_DATA.name && currentPage !== 'home'
  ? `${resolvedTitle} | ${BUSINESS_DATA.name}`
  : resolvedTitle}
```

Controlled by the `useTagLine` prop (defaults to `true`). Set to `false` for blog posts where the title already includes branding.

**Dynamic JSON-LD Generation (`@type` polymorphism):**
```astro
---
const isLocalBusiness = jsonType === "LocalBusiness" || jsonType === "TravelAgency"
const isTouristDestination = jsonType === "TouristDestination"
const isService = jsonType === "Service"

const baseSchema = {
  "@context": "https://schema.org",
  "@type": jsonType,
  "@id": `${BUSINESS_DATA.url}#${jsonType.toLowerCase()}`,
  name: pageTitle,
  description: resolvedDescription,
  url: canonicalUrl,
  image: socialImageUrl,
  inLanguage: lang,
}

if (isLocalBusiness) {
  baseSchema.logo = `${BUSINESS_DATA.url}${BUSINESS_DATA.logo}`
  baseSchema.telephone = BUSINESS_DATA.contact.phone
  baseSchema.address = BUSINESS_DATA.contact.address
  baseSchema.geo = BUSINESS_DATA.contact.geo
  baseSchema.priceRange = "$$-$$$"
  baseSchema.openingHoursSpecification = { "@type": "OpeningHoursSpecification", ... }
  baseSchema.sameAs = [facebook, instagram, ...]
  baseSchema.areaServed = [{ "@type": "AdministrativeArea", name: "[Your Region]" }]
}

if (isTouristDestination) {
  baseSchema.touristType = "[Audience]"
  baseSchema.containedInPlace = { "@type": "AdministrativeArea", name: "[Your Area]" }
}

if (isService) {
  baseSchema.provider = { "@type": "LocalBusiness", name: BUSINESS_DATA.name, ... }
  baseSchema.serviceType = "[Your Service Category]"
}

const jsonLd = { ...baseSchema, ...extraJson }
---
<script type="application/ld+json" set:html={JSON.stringify(jsonLd)} />
```

The `extraJson` prop allows any consumer to extend the schema — `BlogPostSEO` uses it to add `headline`, `author`, `datePublished`, `image`, `url`.

**Hreflang Alternates (auto-generated):**
```astro
---
const canonicalPath = currentPage
  ? getLocalizedPath(currentPage, lang)
  : Astro.url.pathname
const canonicalUrl = `${BUSINESS_DATA.url}${canonicalPath}`

const alternateUrls = {
  en: `${BUSINESS_DATA.url}${getLocalizedPath(currentPage, "en")}`,
  es: `${BUSINESS_DATA.url}${getLocalizedPath(currentPage, "es")}`,
}
---
<link rel="canonical" href={canonicalUrl} />
<link rel="alternate" hreflang="en" href={alternateUrls.en} />
<link rel="alternate" hreflang="es" href={alternateUrls.es} />
```

**Open Graph / Twitter:**
```astro
---
const ogTypeMap = {
  LocalBusiness: "website",
  TravelAgency: "website",
  Blog: "website",
  BlogPosting: "article",
}
const ogType = ogTypeMap[jsonType] || "website"
---
<meta property="og:type" content={ogType} />
<meta property="og:locale" content={LOCALE_MAP[lang]} />
<meta name="twitter:card" content="summary_large_image" />
```

### 3.2 PageSEO.astro — Standard Pages

The simplest wrapper — used by almost every page.

```astro
---
import BaseSEO from "./base/BaseSEO.astro"

const { currentPage, jsonType = "LocalBusiness", extraJson = {}, ogImage } = Astro.props
---
<BaseSEO currentPage={currentPage} jsonType={jsonType} extraJson={extraJson} ogImage={ogImage} />
```

**Usage in a page component:**
```astro
<Layout>
  <PageSEO currentPage={pageKey} slot="seo" />
  <!-- page content -->
</Layout>
```

### 3.3 BlogSEO.astro — Blog Listing

```astro
---
import BaseSEO from "./base/BaseSEO.astro"
---
<BaseSEO currentPage={currentPage} jsonType="Blog" />
```

### 3.4 BlogPostSEO.astro — Individual Blog Post

Full implementation showing how `extraJson` extends the base schema:

```astro
---
import { BUSINESS_DATA } from '@/data/site-config'
import { getLocalizedPath } from '@/lib/i18n/utils'

const localizedPath = getLocalizedPath(currentPage, lang) // respects unprefixed default lang
const extraJson = {
  headline: postTitle,
  description: postExcerpt,
  author: { "@type": "Person", name: postAuthor },
  datePublished: postDate,
  image: postImageUrl,
  url: `${BUSINESS_DATA.url}${localizedPath}`,
}
---
<BaseSEO
  title={postTitle}
  description={postExcerpt}
  baseKeywords={postKeywords}
  jsonType="BlogPosting"
  extraJson={extraJson}
  ogImage={postImageUrl}
  useTagLine={false}
  alternateUrls={alternateUrls}
/>
```

Note `useTagLine={false}` — blog post titles are standalone and shouldn't have " | Brand Name" appended.

## 4. The Slot Pattern

SEO components use the **Astro slot pattern** (`slot="seo"`) to inject metadata into `<head>` from any page component.

```
Layout.astro                    Page Component
┌──────────────────────┐       ┌────────────────┐
│ <head>               │       │ <Layout>       │
│   <slot name="seo" />│ ◄──── │   <PageSEO     │
│ </head>              │       │     slot="seo" │
│ <body>               │       │   />           │
│   <slot />           │       │   ...          │
│ </body>              │       │ </Layout>      │
└──────────────────────┘       └────────────────┘
```

This keeps the Layout framework-agnostic about SEO — any page can inject its own metadata without modifying the layout.

## 5. Sitemap & Robots.txt

### 5.1 Sitemap

Automatically generated by `@astrojs/sitemap`. Accessible at `/sitemap-index.xml`. The `site` URL in `astro.config.mjs` must be set correctly for the sitemap to use proper absolute URLs.

```ts
export default defineConfig({
  site: 'https://example.com',
  integrations: [sitemap()],
})
```

### 5.2 Dynamic robots.txt

Generate robots.txt dynamically via an Astro API endpoint:

```ts
// src/pages/robots.txt.ts
import type { APIRoute } from 'astro';

const getRobotsTxt = (sitemapURL: URL) => `\
User-agent: *
Allow: /

Sitemap: ${sitemapURL.href}
`;

export const GET: APIRoute = ({ site }) => {
    const sitemapURL = new URL('sitemap-index.xml', site);
    return new Response(getRobotsTxt(sitemapURL));
};
```

This approach ensures the sitemap URL is always correct, even when the `site` config changes.

## 6. Performance & Environment Logic

### 6.1 Environment-Based Indexing

Prevent dev/staging environments from appearing in search results:

```astro
---
const isProd = import.meta.env.PROD;
---
{!isProd && <meta name="robots" content="noindex, nofollow" />}
```

### 6.2 Multimedia Optimization

For the **full** SSG image-optimization pattern (remote CDN/API re-optimization, AVIF + WebP `<picture>` output, `IMAGE_SLOTS` widths↔sizes invariant, LCP srcset preload, React-island byte parity, and the `image.remotePatterns` allowlist gate) → **[[astro-images]]**. This section is the quick-start for simple local images only.

Use `astro:assets` `Image` component for automatic optimization (WebP/AVIF conversion, resizing).

**Best Practices:**
- **Eager Loading:** Use `loading="eager"` and `fetchpriority="high"` for hero banners.
- **Lazy Loading:** Use `loading="lazy"` and `decoding="async"` for everything else.

**Responsive images example (from Home.astro):**
```astro
---
import { Image } from 'astro:assets'
---
<Image
  src={image}
  alt={alt}
  widths={[400, 800, image.width]}
  sizes="(max-width: 768px) 400px, 800px"
  quality={60}
  format="avif"
  loading="lazy"
  decoding="async"
  class="h-full w-full rounded-xl object-cover"
/>
```

The `widths` + `sizes` pattern generates multiple resolutions for responsive displays, but for a shared atom with format negotiation and remote-src support, prefer the `Image.astro` atom in [[astro-images]].

## 7. Core Web Vitals Optimization

Key optimizations for page speed:

### 7.1 Critical Font Preloading
```html
<link rel="preload" href="/fonts/inter-latin-wght-normal.woff2" as="font" type="font/woff2" crossorigin />
<link rel="preload" href="/fonts/metropolis-latin-400-normal.woff2" as="font" type="font/woff2" crossorigin />
```

### 7.2 Preconnect to Third-Party Origins
```html
<link rel="preconnect" href="https://maps.googleapis.com" />
<link rel="preconnect" href="https://maps.gstatic.com" />
```

### 7.3 Hero Image Preload

For the responsive `imagesrcset`/`imagesizes` preload that matches the rendered variant (LCP priority), follow `lcpPreload()` in **[[astro-images]]**. The plain-href form below is the minimal fallback.

```astro
---
{preloadImage && <link rel="preload" as="image" href={preloadImage} fetchpriority="high" />}
---
```

Pass `preloadImage` as a prop to `Layout.astro`:
```astro
<Layout preloadImage={heroImage.src}>
```

### 7.4 Inline CSS
```ts
export default defineConfig({
  build: { inlineStylesheets: "always" }
})
```

Eliminates render-blocking CSS requests for small-to-medium sites.

## 8. Island Architecture + SEO

To maintain SEO excellence while using interactive React components, use the [[astro-react-islands#8-the-slot-pattern|Slot Pattern]]. Content inside Astro slots is rendered as static HTML — crawlers see it immediately without waiting for JavaScript hydration.

**Benefits:**
- **Search Visibility:** Core content is visible to crawlers without JS execution.
- **Single Source of Truth:** Shared atoms (buttons, links) remain Astro components with consistent SEO attributes (alt text, titles, ARIA labels).

## 9. Internationalization (i18n) + SEO

### 9.1 Canonical Links & Hreflang

Handled automatically by `BaseSEO.astro` — every page gets:
```html
<link rel="canonical" href="https://example.com/path" />
<link rel="alternate" hreflang="en" href="https://example.com/path" />
<link rel="alternate" hreflang="es" href="https://example.com/es/ruta" />
```

The SEO component calls `getLocalizedPath(pageKey, lang)` from the i18n system to compute the correct URL for each language.

### 9.2 Internal Linking Strategy

All internal links use localized paths from [[astro-i18n]]. The `LangLink` atom ensures every link points to the correct language version.

### 9.3 Legacy Redirects

Handle old URL patterns via `astro.config.ts` to preserve SEO authority:

```ts
const legacyRedirects = Object.values(routes).reduce((acc, route) => {
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

## 10. Headings & Hierarchy

The project follows a strict heading hierarchy:
- **H1:** Unique per page.
- **H2-H6:** Used for section titles and subsections. Never skip levels (e.g., don't jump from H2 to H4).

## 11. Accessibility (ARIA)

Interactive elements like buttons must use `aria-label` to provide context for screen readers when the text content is not descriptive enough.

```astro
<ButtonCta
  aria-label={`Book now - Private Transportation`}
  ...
/>
```

## 12. 404 Page

- Include links to primary site sections to reduce bounce rate.
- Use clear messaging about the page not being found.
- Consider a search box for larger sites.

## 13. Analytics & Tracking

Track SEO performance using Google Tag Manager (GTM) and/or GA4.

### Layout Pattern
```html
<!-- Google Tag Manager -->
<script is:inline>
  (function(w,d,s,l,i){w[l]=w[l]||[];w[l].push({'gtm.start':
  new Date().getTime(),event:'gtm.js'});var f=d.getElementsByTagName(s)[0],
  j=d.createElement(s),dl=l!='dataLayer'?'&l='+l:'';j.async=true;j.src=
  'https://www.googletagmanager.com/gtm.js?id='+i+dl;f.parentNode.insertBefore(j,f);
  })(window,document,'script','dataLayer','GTM-XXXXXXX')
</script>
<!-- Google tag (gtag.js) -->
<script is:inline async src="https://www.googletagmanager.com/gtag/js?id=AW-XXXXXXXXX"></script>
<!-- GTM (noscript) - placed after <body> opening -->
<noscript><iframe src="https://www.googletagmanager.com/ns.html?id=GTM-XXXXXXX"
height="0" width="0" style="display:none;visibility:hidden"></iframe></noscript>
```

Use the `is:inline` directive — Astro will not process or bundle these scripts.

## 14. RSS Feed

Standardized feed for search engines and aggregators:

```js
// src/pages/rss.xml.js
import rss from '@astrojs/rss'

export async function GET(context) {
  const posts = await getPosts()
  return rss({
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
    site: context.site,
    items: posts.map(post => ({
      title: post.title,
      description: post.description,
      pubDate: new Date(post.created_at),
      author: post.author,
      link: `/blog/${post.slug}/`,
    })),
  })
}
```

## 15. SEO Validation Checklist

Before every deployment, verify the following:

- [ ] **Google PageSpeed Insights:** Score > 90 for Mobile and Desktop.
- [ ] **Schema Markup Validator:** No errors in JSON-LD.
- [ ] **Lighthouse:** Run accessibility and SEO audits.
- [ ] **Canonical/Hreflang:** Ensure correct cross-linking between languages.
- [ ] **i18n Sync:** Run `pnpm run validate-i18n` (see [[astro-i18n#9-build-time-validation-mandatory]]) to ensure all translation keys (titles/descriptions) are present in all languages.
- [ ] **Favicons:** Verify all icons and manifest load correctly with no 404s.
- [ ] **Robots.txt:** Verify it exists and points to the correct sitemap URL.
- [ ] **og:image:** Verify the Open Graph image renders correctly on social media preview tools.
