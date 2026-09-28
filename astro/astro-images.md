---
created: 2026-09-27
tags:
  - astro
  - images
  - seo
  - performance
  - documentation
type: resource
status: active
source: templates://astro/astro-images.md
version: 2026-09-27+57b0fd3

---

# SSG Image Optimization for Astro (best practices)

> **Opt-in layer.** Precondition: [Base config](./astro-base-config.md) (`@/` alias). Complements the multimedia/performance guidance in [astro-seo](./astro-seo.md) (this doc is the canonical source for the full optimization pattern; [astro-seo#6-2-multimedia-optimization](./astro-seo.md#6-2-multimedia-optimization) links here).

Build-time, source-agnostic image optimization via the `astro:assets` image service. Produces responsive, format-negotiated (AVIF + WebP) `<picture>` output from **local imports, remote CDN URLs, or API/dashboard strings** — with a graceful fallback so one unreachable remote never fails the build. Includes the smallest-common LCP (largest-contentful-paint) preload and byte-parity handling for React islands.

This doc is generic: copy it into any Astro project and substitute the host/quality/slot values for your content. Everything local (`src/assets`, `public/`) works with zero config; remote CDN/API images require the `remotePatterns` gate of §2.

> Convention: `@/` means `./src/*`. `example.com` is your site. `YOUR_ACCENT` and slot width/sizes values are illustrative — adapt to your design system.

## 0. Prerequisites + decision tree

Dependencies: none beyond Astro itself. `sharp` is bundled (see [astro-seo](./astro-seo.md) §1). `@astrojs/sitemap` only if you emit a sitemap (optional here).

You need the full pattern if **any** of these are true:

- Images arrive as **remote URLs** (CMS/CDN/API strings) and you want them re-optimized in the SSG.
- You have a **shared image atom** used across cards/grids/heroes and want one response-image source of truth.
- You care about LCP/hero preload or React-island byte parity.

You can strip it down if you only have a handful of local images → use `astro:assets` `Image` directly ([astro-seo](./astro-seo.md) §6.2) and skip §4–§8.

### Decision tree

```
Do remote images need build-time re-optimization?
├── YES → add image.remotePatterns gate (§2)
├── NO (local-only) → skip §2 (patterns don't apply to local imports)
└── Then decide how you render:
    ├── Astro components only → Image atom (§4) + optional LCP preload (§6)
    ├── React islands present → also slideSet() for byte parity (§7)
    └── Need hero/LCP warm-up → lcpPreload() (§6)
```

## 1. Storage split

Three source kinds, three behaviors:

| Source | Where | How referenced | Optimized? |
|---|---|---|---|
| Public assets (favicons, og-image) | `public/` | Root-absolute `/og-image.jpg` | **No** — copied verbatim, never through `getImage`. |
| Local source assets | `src/assets/` | Imported as `ImageMetadata`: `import logo from "@/assets/logo.png"` | **Yes** — passed to `<Image src={logoMetadata}>` → transformed + hashed. |
| Remote CDN / API strings | strings | Absolute `https://…` used as `src="string"` | **Yes, at build time** — but only if the host is `remotePatterns`-allowlisted (§2). |

The local-vs-remote distinction is a **string test**: `const isRemote = typeof src === "string" && /^https?:\/\//.test(src)`. Local imports (`ImageMetadata`) and remote strings both converge on the same `getImage()` transform — the only differences are the allowlist gate (remote) and fallback behavior.

## 2. The gate: `image.remotePatterns`

A remote URL is optimized **only** if its protocol **and** host match an allowlist entry in `astro.config.mjs`. Otherwise `getImage()` on a remote string returns the URL verbatim (untransformed).

The proven pattern derives the API/dashboard host at build time so dev (`.localhost`), Docker, and prod each allowlist their own backend with no code change, plus a static CDN host:

```js
// astro.config.mjs
function remoteImagePatterns() {
  const patterns = [
    { protocol: "https", hostname: "your-cdn.s3.example.com" }, // static CDN host
  ]
  const apiBase = process.env.PUBLIC_API_BASE_URL ?? ""
  try {
    const host = new URL(apiBase).hostname
    if (host) {
      patterns.push({ protocol: "https", hostname: host })
      patterns.push({ protocol: "http", hostname: host })
    }
  } catch {
    // No/invalid PUBLIC_API_BASE_URL — CDN host above still applies.
  }
  return patterns
}

export default defineConfig({
  image: {
    remotePatterns: remoteImagePatterns(),
  },
  // ...site origin chain + server/vite port, see astro-base-config.md
})
```

> If your project has **no remote images** (local-only), omit `image.remotePatterns` entirely — local `ImageMetadata` imports bypass pattern matching. The gate only exists to bound remote fetching.

## 3. `src/lib/images.ts` — slots, qualities, helpers

This module owns the transform constants and slot map. It is the only place that reasons about widths/qualities.

```ts
// src/lib/images.ts
import { getImage } from "astro:assets"

// Quality floor (max compression with QA on detail):
export const AVIF_QUALITY = 55
export const WEBP_QUALITY = 78

export interface ImageSlot {
  widths: number[]
  sizes: string
}

// Every slot pairs candidate pixel WIDTHS with a matching SIZES media-string.
// The invariant: `sizes` MUST match the rendered CSS slot, or the browser
// picks the wrong bytes. 100vw → 50vw → 25vw below are examples.
export const IMAGE_SLOTS = {
  grid:      { widths: [400, 800, 1200], sizes: "(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 25vw" },
  heroFull:  { widths: [960, 1600, 2400], sizes: "100vw" },
  portrait:  { widths: [360, 720, 1080], sizes: "(max-width: 1024px) 100vw, 360px" },
  logo:      { widths: [180, 360, 540], sizes: "180px" },
} satisfies Record<string, ImageSlot>

export type ImageSlotName = keyof typeof IMAGE_SLOTS

export interface LcpPreload { srcSet: string; sizes: string }
export interface SlideSet {
  avifSrcSet: string; webpSrcSet: string; fallbackSrc: string
  width: number; height: number; sizes: string
}
```

Two helpers reuse the **same transform the Image atom applies**, so preloaded bytes and React-island markup match rendered variants exactly (no double-download):

- `slideSet(src, slot)` → builds an AVIF+WebP set for a **React island** (which can't render `.astro` atoms). Returns `SlideSet | null`.
- `lcpPreload(src, slot)` → builds a single **AVIF responsive srcset** for an LCP/hero preload. Returns `LcpPreload | null`.

Both use the shared retry-with-backoff pattern (4 attempts, then null → caller falls back to the verbatim URL):

```ts
export async function lcpPreload(src: string, slot: ImageSlot): Promise<LcpPreload | null> {
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      const img = await getImage({ src, inferSize: true, widths: slot.widths, format: "avif", quality: AVIF_QUALITY })
      const srcSet = img.srcSet.attribute
      if (!srcSet) return null
      return { srcSet, sizes: slot.sizes }
    } catch {
      // transient remote-fetch flake — retry with backoff, then null
      if (attempt < 3) await new Promise((r) => setTimeout(r, 250 * (attempt + 1)))
    }
  }
  return null
}
```

## 4. The Image atom — `src/components/atoms/Image.astro`

One shared component, used for every prose/visual image (heroes, cards, logos, viewers, banners). Props defer rendering decisions to the caller:

| Prop | Default | Meaning |
|---|---|---|
| `src` | required | `string \| ImageMetadata` — remote string or local import |
| `alt` | required | alternative text |
| `loading` | `lazy` | `eager` only for above-the-fold/LCP |
| `decoding` | `async` | `sync`/`auto` rarely needed |
| `fetchpriority` | `auto` | `high` for LCP/hero |
| `widths` | `[640,1080,1600]` | candidate pixel widths |
| `sizes` | `100vw` | media string matching the CSS slot |
| `class` | — | sizing/object-fit from the caller |

Core transform logic — if remote **or** local metadata, try `getImage()` **twice in parallel** (AVIF + WebP, same widths): 

```astro
---
import { getImage, type ImageMetadata } from "astro:assets"
import { AVIF_QUALITY, WEBP_QUALITY } from "@/lib/images"

const isRemote = typeof src === "string" && /^https?:\/\//.test(src)

let optimized = null
if (isRemote || typeof src !== "string") {
  const base = typeof src === "string" ? { src, inferSize: true } : { src }
  for (let attempt = 0; attempt < 4 && !optimized; attempt++) {
    try {
      const [avif, webp] = await Promise.all([
        getImage({ ...base, widths, format: "avif", quality: AVIF_QUALITY }),
        getImage({ ...base, widths, format: "webp", quality: WEBP_QUALITY }),
      ])
      if (avif.srcSet.attribute && webp.srcSet.attribute) {
        optimized = { avifSrcSet: avif.srcSet.attribute, webpSrcSet: webp.srcSet.attribute,
                      fallbackSrc: webp.src, width: webp.attributes.width, height: webp.attributes.height }
      }
    } catch {
      // fall back to verbatim URL rather than fail the whole SSG build
      if (attempt < 3) await new Promise((r) => setTimeout(r, 250 * (attempt + 1)))
    }
  }
}
---
{optimized ? (
  <picture>
    <source type="image/avif" srcset={optimized.avifSrcSet} sizes={sizes} />
    <source type="image/webp" srcset={optimized.webpSrcSet} sizes={sizes} />
    <img src={optimized.fallbackSrc} alt={alt} width={optimized.width} height={optimized.height}
         loading={loading} decoding={decoding} fetchpriority={fetchpriority} sizes={sizes} class={imgClass} />
  </picture>
) : (
  <img src={typeof src === "string" ? src : src.src} alt={alt} loading={loading} decoding={decoding} fetchpriority={fetchpriority} class={imgClass} />
)}
```

**Resilience invariant:** a single failed remote transformation logs a warning and falls back to the verbatim URL — **never** crashes the build. Priorities: above-the-fold heroes use `loading="eager" fetchpriority="high"`; everything else defaults to `lazy`/`async`/`auto`.

## 5. LCP / preload priority (optional but recommended)

Pick **one** hero/LCP image per page type, map it to a slot, then preload the transformed srcset so the browser warms the biggest image early — and the preloaded bytes match the rendered variant (no double-download).

1. **Router** (your `getStaticPaths`/page component): resolve a single `preloadImage` (the hero/primary) + its `IMAGE_SLOTS.*` slot. If remote (`/^https?:\/\//`), `const set = await lcpPreload(preloadImage, slot)`.
2. **Layout** — emit in `<head>`:

```astro
{preloadSrcSet
  ? <link rel="preload" as="image" imagesrcset={preloadSrcSet} imagesizes={preloadSizes ?? "100vw"} fetchpriority="high" />
  : preloadImage && <link rel="preload" as="image" href={preloadImage} fetchpriority="high" />}
```

- Transformed srcset present → responsive preload with `imagesrcset`/`imagesizes`.
- Else plain `href` preload of the verbatim URL.
- Always `fetchpriority="high"` on the preload and on the rendered hero `<img>`.

## 6. og:image & sitemap

In your **SEO base component** (`BaseSEO.astro`), special-case the og image:

```astro
{/* absolute http(s) og images pass through; relative get the site-origin prefix */}
{ogImage?.startsWith("http")
  ? ogImage
  : `${BUSINESS_DATA.url}${ogImage}`}
```

- Absolute (remote CDN) og images pass through as-is.
- Relative ones get the `BUSINESS_DATA.url` prefix.
- Keep a default og image in `public/` (`/og-image.jpg`).
- Sitemap: use `@astrojs/sitemap`'s `filter` to drop paths you don't want indexed (e.g. checkout), as in [astro-seo](./astro-seo.md) §5.

## 7. React-island byte parity (only if you use React islands)

`.astro` atoms **cannot** be rendered inside React components. For island-carousel images, precompute the slide set in the `.astro` wrapper and pass it in, then render the identical `<picture>` markup by hand so output stays byte-identical to atom-rendered images:

```astro
---
import { slideSet, IMAGE_SLOTS } from "@/lib/images"
const slides = await Promise.all(
  items.map(async (it) => ({ ...it, set: await slideSet(it.image, IMAGE_SLOTS.slider) }))
)
---
<ArtworkSlider slides={slides} />
```

```tsx
// ArtworkSlider.tsx — in React:
{set ? (
  <picture>
    <source type="image/avif" srcSet={set.avifSrcSet} sizes={set.sizes} />
    <source type="image/webp" srcSet={set.webpSrcSet} sizes={set.sizes} />
    <img src={set.fallbackSrc} width={set.width} height={set.height} sizes={set.sizes} />
  </picture>
) : (
  <img src={verbatim} />
)}
```

## 8. Replication checklist

- [ ] `astro.config.mjs` — add `image.remotePatterns` (§2) only if you have remote images.
- [ ] `src/lib/images.ts` — `AVIF_QUALITY`/`WEBP_QUALITY`, `IMAGE_SLOTS` (adjust widths/sizes to your CSS slots), `lcpPreload()`, `slideSet()` (islands only).
- [ ] `src/components/atoms/Image.astro` — the shared atom; every visual image routes through it.
- [ ] LCP — single `preloadImage`+slot per page → `lcpPreload()` → `<link rel="preload" as="image" imagesrcset …>` in `<head>`.
- [ ] og-image — absolute pass-through + relative-prefix branch in the SEO base.
- [ ] React islands — precompute `SlideSet`s in the wrapper, render `<picture>` manually for byte parity.

### Patterns to adopt
- **Slot naming always pairs `widths` with `sizes`** — never pass widths without a matching `sizes` string, or the browser fetches the wrong bytes.
- **Graceful fallback** — wrap `getImage` in retry+backoff; on failure use the verbatim URL instead of crashing the build.
- **Quality as shared constants** — one place to tune compression (AVIF 55 / WebP 78).
- **Lazy/priority convention** — default `lazy`/`async`/`auto`; override to `eager`/`high` only for above-the-fold/LCP images.
- **Local vs remote converge** — `ImageMetadata` and remote strings take the same `getImage` path; only the allowlist gate and fallback differ.

### Gotchas
- Remote images are **not** optimized unless protocol+host match `remotePatterns` — they come back verbatim otherwise.
- `.astro` atoms can't render inside React islands — replicate the transform/`<picture>` markup manually (that's what `slideSet()` is for).
- `public/` assets are never transformed — move a locally-edited image to `src/assets/` and import it if you want optimization.

## Connection to Other Patterns

- Multimedia/performance best practices + the basic `astro:assets` `Image` → [astro-seo](./astro-seo.md) §6.2, §7
- `BUSINESS_DATA.url` origin chain → [astro-site-config](./astro-site-config.md)
- Merged `astro.config.mjs` (this doc's block slots in) → [astro-base-config](./astro-base-config.md)
- The shared atom lives in the atoms tier → [astro-atomic-components](./astro-atomic-components.md)