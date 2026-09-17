---
created: 2026-07-26
updated: 2026-07-26
tags:
  - astro
  - pwa
  - service-worker
  - offline
  - setup
  - documentation
type: resource
status: active
source: templates://astro/astro-pwa.md
version: 2026-09-17+unreleased

---

# PWA Out of the Box

> **Opt-in layer.** Precondition: [Base config](./astro-base-config.md) + Docker nginx. Skip if plain website suffices (API `runtimeCaching` block requires the Fetch layer).

Progressive Web App support via `@vite-pwa/astro`. Service worker, install prompt, offline fallback, and asset caching with minimal config.

## Architecture

```
@vite-pwa/astro
  ├── Service Worker (Workbox) → cached assets, API caching
  ├── Web App Manifest → install prompt, splash screen
  ├── Offline fallback → custom offline page
  └── PWA Assets → icons, maskable icons
```

## 1. Dependencies

```json
{
  "dependencies": {
    "@vite-pwa/astro": "^1.2.0"
  },
  "devDependencies": {
    "@vite-pwa/assets-generator": "^1.0.2"
  }
}
```

## 2. Astro Config

```js
// astro.config.mjs
import { defineConfig } from 'astro/config'
import vitePwa from '@vite-pwa/astro'

export default defineConfig({
  integrations: [
    vitePwa({
      registerType: 'autoUpdate',     // SW updates silently in background
      manifest: {
        name: 'Your App',
        short_name: 'App',
        description: 'Description',
        theme_color: '#fe676e', // <-- replace with your brand color
        background_color: '#ffffff', // <-- replace with your brand surface
        display: 'standalone',         // full-screen app, no browser chrome
        orientation: 'portrait',
        start_url: '/?source=pwa', // i18n projects: point to the default-lang home (`/`) or a localized entry; keep unprefixed for the default language
        icons: [
          { src: '/icons/icon-192x192.png', sizes: '192x192', type: 'image/png' },
          { src: '/icons/icon-512x512.png', sizes: '512x512', type: 'image/png' },
          { src: '/icons/icon-maskable-192x192.png', sizes: '192x192', type: 'image/png', purpose: 'maskable' },
          { src: '/icons/icon-maskable-512x512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        globPatterns: ['**/*.{js,css,woff2,png,svg,jpg,ico,html}'],
        // API caching — include ONLY if the Fetch/API layer is present.
        // No-API projects (e.g. i18n-only content site): delete runtimeCaching entirely.
        runtimeCaching: [
          {
            urlPattern: /\/api\/.*/i,
            handler: 'NetworkFirst',
            options: {
              networkTimeoutSeconds: 10,
              cacheName: 'api-cache',
            },
          },
        ],
        navigateFallback: '/offline/',
      },
    }),
  ],
})
```

## 3. Offline Page

> Routing note: with the i18n `[...path].astro` catch-all, static `src/pages/offline.astro` still wins (Astro prioritizes static files). Keep the offline page outside localized routing — no `lang`/`pageKey` props.

Create `src/pages/offline.astro` — shown when the user has no connection and the page isn't cached:

```astro
---
import OfflineLayout from '@/layouts/OfflineLayout.astro'
---
<OfflineLayout>
  <div class="min-h-dvh flex flex-col items-center justify-center px-4 text-center">
    <h1 class="text-3xl font-bold mb-4">You're Offline</h1>
    <p class="text-lg text-muted-foreground mb-8">Check your connection and try again.</p>
    <button type="button" id="offline-retry-btn" class="...">
      Try Again
    </button>
  </div>
  <script>
    document.getElementById('offline-retry-btn')?.addEventListener('click', () => {
      window.location.reload()
    })
  </script>
</OfflineLayout>
```

Create a minimal `OfflineLayout.astro` (no service worker, no heavy scripts):

```astro
---
import '@/styles/global.css'
---
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>You're Offline</title>
  </head>
  <body class="font-sans text-foreground bg-background">
    <slot />
  </body>
</html>
```

## 4. PWA Assets Generator

Configure icon generation from a source image:

```ts
// vite-pwa-assets-generator.config.ts
import { defineConfig } from '@vite-pwa/assets-generator'

export default defineConfig({
  preset: {
    transparent: { sizes: [192, 512], favicons: [[48, 'favicon.ico']] },
    maskable: { sizes: [192, 512] },
    apple: { sizes: [180] },
  },
  images: ['public/icon-source.png'],
})
```

```bash
# Generate all icon sizes from source image
pnpm generate-pwa-assets
```

Add to `package.json`:
```json
{
  "scripts": {
    "generate-pwa-assets": "pwa-assets-generator --config vite-pwa-assets-generator.config.ts"
  }
}
```

## 5. PWA Meta Tags in Layout

```html
<meta name="theme-color" content="#fe676e" />
<meta name="mobile-web-app-capable" content="yes" />
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
<meta name="apple-mobile-web-app-title" content="Your App" />
<link rel="icon" type="image/svg+xml" href="/favicon.svg" />
<link rel="icon" href="/favicon.ico" />
<link rel="apple-touch-icon" href="/icons/apple-touch-icon.png" />
```

## 6. Production Nginx Caching (for SW files)

The nginx caching rules for the service worker, manifest, and `/_astro/` assets
live in [astro-docker-deployment.md](./astro-docker-deployment.md) (see the nginx
config there) — that is the single source of truth. Service worker files must
never be cached by the CDN.

## 7. New Project Setup

```bash
pnpm add @vite-pwa/astro
pnpm add -D @vite-pwa/assets-generator

# Create icon source
# Place a 512x512 PNG at public/icon-source.png

# Generate all icon sizes
pnpm generate-pwa-assets

# Create offline page
mkdir -p src/pages
touch src/pages/offline.astro
```

Then:
1. Copy the `vitePwa()` config from section 2 into `astro.config.mjs`
2. Create the offline page (section 3)
3. Add meta tags to your layout (section 5)
4. Configure nginx caching rules (section 6)

## 8. Key Notes

- Icon mapping: SEO favicons live at `public/` root (`favicon.svg/.ico`, `apple-touch-icon.png`, `og-image.jpg`); PWA icons live at `public/icons/` (`icon-192/512`, maskable) generated from `public/icon-source.png` via `pnpm generate-pwa-assets`. Keep both sets; they serve different consumers (browser chrome vs install prompt).
- `autoUpdate` means the SW updates silently when a new version is detected — no "Update available" prompt
- API endpoints use `NetworkFirst` with a 10s timeout — good UX for intermittent connections
- The offline page is a simple static page — no React/JS needed
- All build assets (`/_astro/*`) get immutable cache — they're content-hashed by Astro
- Never cache the service worker file itself
