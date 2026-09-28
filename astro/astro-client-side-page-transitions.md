---
created: 2026-08-11
tags:
  - astro
  - transitions
  - view-transitions
  - client-router
  - gsap
  - documentation
type: resource
status: active
source: templates://astro/astro-client-side-page-transitions.md
version: 2026-09-27+57b0fd3

---

# Astro Client-Side Page Transitions — Implementation Guide

> **Base layer, default ON.** Every Base project ships `<ClientRouter />` in the shared layout. This doc is therefore required reading even for static sites.
>
> **No-router escape:** delete `<ClientRouter />` from the layout, drop all `astro:*-swap`/`astro:page-load` listeners, and call each `init()` directly once. GSAP/Markdown scripts then run a single time (V0 mode below). Only do this if you have a reason (strict MPA, third-party scripts incompatible with swapping).

A functional, reusable guide for adding SPA-like client-side page transitions to an Astro project using `<ClientRouter />` from `astro:transitions`.

This guide is generic: it does not reference any particular project. Every section applies to any Astro project that uses a shared layout. Sample code uses placeholder names and sample data — adapt them to your own codebase.

---

## 1. What this achieves

Enabling client-side page transitions turns your multi-page Astro site into a Single-Page-App-like experience:

- Clicking an internal link does **not** reload the browser page.
- The target page's HTML is fetched and swapped in-place using the [View Transitions API](https://developer.mozilla.org/en-US/docs/Web/API/View_Transitions_API), with an animated transition between the old and new page.
- Elements shared across pages (layout shell, headers, footers) render inside the new document; JavaScript state is re-initialized per navigation.
- Browsers that do not support the View Transitions API get a graceful full-navigation fallback.

The cost is that **all client-side JavaScript which runs "once on load" will no longer run on navigation**, so it must be re-triggered after every page swap. Section 5 is the most important part of this guide.

---

## 2. Requirements

- **Astro 6** — `<ClientRouter />` is the modern API for client-side transitions.
  - Older versions (Astro 3.x / 4.x / 5.x) used `<ViewTransitions />`. If you are on an older major version, upgrade or use the equivalent legacy component of your version.
- The View Transitions API works in all modern browsers. Older browsers are handled by the automatic fallback (see Section 7).
- No extra pnpm packages are required for the core functionality.

---

## 3. Minimal setup

### 3.1 Add `<ClientRouter />` to a shared layout

Astro enables transitions on **each individual page**, so the easiest approach is to put `<ClientRouter />` inside the `<head>` of the shared layout that all your pages use.

`src/layouts/Layout.astro`:

```astro
---
import { ClientRouter } from 'astro:transitions';
---
<html lang={lang}>
  <head>
    <meta name="viewport" content="width=device-width" />
    <title>My site</title>
    <ClientRouter />
  </head>
  <body>
    <slot />
  </body>
</html>
```

### 3.2 (Recommended) Keep a persistent layout shell

To get the full SPA feel, keep the repeated page furniture (header / footer / navigation) inside the shared layout rather than inside each page. This way it is re-rendered consistently on every page and only the page-specific content in `<slot />` changes between navigations.

```astro
---
import { ClientRouter } from 'astro:transitions';
import Header from '../components/Header.astro';
import Footer from '../components/Footer.astro';
---
<html lang={lang}>
  <head>
    <meta name="viewport" content="width=device-width" />
    <title>My site</title>
    <ClientRouter />
  </head>
  <body>
    <Header />
    <main><slot /></main>
    <Footer />
  </body>
</html>
```

### 3.3 Make all pages use the layout

Every page (`src/pages/**`) should wrap its content in the shared layout so every page enables transitions:

```astro
---
import Layout from '../layouts/Layout.astro';
---
<Layout>
  <h1>Home</h1>
  <p>Welcome.</p>
</Layout>
```

That's it — navigation between your pages is now animated and client-side.

> Note: internal links like `<a href="/about">` are automatically intercepted by the router. There is nothing extra to add. External links and links with `target="_blank"` or `download` are not intercepted.

---

## 4. How it works under the hood

1. `<ClientRouter />` injects a small client runtime into every page that uses it.
2. When a user clicks an internal `<a>` link, the runtime intercepts the click and:
   - fires transition lifecycle events (see below),
   - fetches the target page's HTML,
   - captures a "before" snapshot of the current page,
   - swaps the new page's `<head>` and `<body>` content into the current document,
   - captures an "after" snapshot and animates between them,
   - updates the browser history and restores/scrolls appropriately.
3. Because the browser document is never reloaded, the swapped document re-runs Astro's hydration for any client island components found in the new page's markup.
4. A `document` event `astro:page-load` is dispatched once the swap completes so your own code can re-run setup logic.

### Lifecycle events

All events are `document` events (detail `event.detail`):

| Event | When it fires |
|---|---|
| `astro:before-preparation` | Navigation begins, before the request is made |
| `astro:after-preparation` | Target page has been loaded/parsed |
| `astro:before-swap` | Before content is swapped (gives access to the active `ViewTransition` and the `swap()` function) |
| `astro:after-swap` | Content swapped, history + scroll already updated |
| `astro:page-load` | New page is fully ready — **replaces `DOMContentLoaded` for code you want on every page** |

---

## 5. The critical part: re-initializing client-side JavaScript

With transitions enabled, `DOMContentLoaded` fires **only once, on the first visit**. Every subsequent navigation swaps the DOM without a page load, so any script that initialized on `DOMContentLoaded` will not run again on the new page.

**Rule of thumb:** anything that used to live in `DOMContentLoaded` (or a `useEffect(() => {...}, [])` mount hook) should instead run on `astro:page-load` if the new page depends on it.

**Lifecycle rule (V0 vs V1):**

- **V1 — router ON (Base default):** section-presence guard + `init()` immediately (first paint) + `astro:page-load` re-init + `astro:after-swap` cleanup (`mm?.revert()`). Immediate call covers first paint; listeners cover navigations.
- **V0 — router OFF (escape only):** call `init()` directly once, no listeners. Never mix: V0 with listeners double-initializes; V1 without the immediate call misses first paint in some GSAP patterns.

### 5.1 Plain `<script>` setup (e.g. a carousel)

```astro
<script>
  function initCarousel() {
    // ... instantiate your carousel, build the DOM, attach listeners
  }

  // First load
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initCarousel);
  } else {
    initCarousel();
  }

  // Re-init after every client-side navigation
  document.addEventListener('astro:page-load', initCarousel);
</script>
```

### 5.2 Hydrated framework components (React, Vue, Svelte, etc.)

A `client:*` island is **re-mounted and re-hydrated** on every navigation (because the new HTML contains a fresh instance of the island). This means:

- `useEffect(() => {...}, [])` mount hooks **do** re-run per navigation — good for libraries (scroll animations, counters, AOS, Swiper) that need to attach to the new page's elements.
- **Do not** rely on server-rendered props (e.g. `currentPath`) for things that change per route — the island renders fresh server HTML on each navigation, but the browser URL is the source of truth on the client. Prefer reading `window.location` inside the component/client to derive route-dependent state such as the active navigation link.

Example — active link highlighting that updates after each navigation:

```jsx
import { useEffect, useState } from 'react';

export default function Header({ items = [] }) {
  const [activePath, setActivePath] = useState('/');

  const pathFromLocation = () => {
    // derive the active route from the browser URL, not from server props
    return window.location.pathname;
  };

  // On first load and on every page transition, recompute the active link
  useEffect(() => {
    const update = () => setActivePath(pathFromLocation());
    update();

    document.addEventListener('astro:page-load', update);
    window.addEventListener('popstate', update);
    return () => {
      document.removeEventListener('astro:page-load', update);
      window.removeEventListener('popstate', update);
    };
  }, []);

  return (
    <nav>
      {items.map((item) => (
        <a
          key={item.href}
          href={item.href}
          className={activePath === item.href ? 'active' : ''}
        >
          {item.label}
        </a>
      ))}
    </nav>
  );
}
```

### 5.3 Anchor links / hash scrolling

Links like `/services/#testimonials` navigate to a page *and* a hash. After the transition the hash element may need to be scrolled into view. Listen for `astro:page-load` (and `hashchange`) and trigger `scrollIntoView`:

```jsx
useEffect(() => {
  const scrollToHash = () => {
    const hash = window.location.hash;
    if (!hash) return;
    const el = document.getElementById(hash.replace('#', ''));
    if (el) {
      // small delay lets the new page's content/layout settle before scrolling
      setTimeout(() => el.scrollIntoView({ behavior: 'smooth' }), 200);
    }
  };

  document.addEventListener('astro:page-load', scrollToHash);
  window.addEventListener('hashchange', scrollToHash);
  return () => {
    document.removeEventListener('astro:page-load', scrollToHash);
    window.removeEventListener('hashchange', scrollToHash);
  };
}, []);
```

---

### 5.4 Client Router + GSAP

> Cross-reference: `gsap-scrolltrigger/01-setup-and-mandatory-files.md` §5 for the GSAP-side VT documentation.

GSAP components (`fromTo` + `ScrollTrigger` + `matchMedia`) need a lifecycle that handles VT navigations correctly: cleanup stale triggers from the previous page, re-init on the new page, prevent the VT cross-fade from competing with GSAP fromTo reveals, and guard against stale event listeners.

**Canonical GSAP + VT pattern:**

```js
import { gsap, ScrollTrigger } from "@/lib/gsap"

let mm

const init = () => {
  // Guard: bail if this component isn't on the current page
  if (!document.querySelector(".js-my-section")) return

  // Kill stale tweens/triggers from the previous page
  mm?.revert()
  mm = gsap.matchMedia()

  mm.add("(prefers-reduced-motion: no-preference)", () => {
    // fromTo + ScrollTrigger tweens
  })
  mm.add("(prefers-reduced-motion: reduce)", () => {
    // fade-only or no-op fallback
  })
}

// Cleanup early — kills old triggers before the new page's init runs
document.addEventListener("astro:after-swap", () => mm?.revert())
// Re-init after every client-side navigation
document.addEventListener("astro:page-load", init)
// First paint — works even without ClientRouter
init()
```

**Why `mm.revert()` not `gsap.context()`:** Do not nest `gsap.context()` inside matchMedia — matchMedia creates a context internally; use `mm.revert()` only.

**Section-presence guard:** Stale event listeners from a previous page persist on `document` after VT DOM swap. Without the `if (!document.querySelector(...)) return` guard, a page that had the same component fires `init()` again on the new page, creating duplicate `matchMedia` contexts and competing ScrollTriggers.

**`transition:animate="none"` on animated sections:** The VT cross-fade shows the new page before GSAP runs `fromTo` with `immediateRender` — the user sees content at natural state, then it disappears and animates in (flash). Add `transition:animate="none"` to every section root that has GSAP entrances:

```astro
<section class="js-hero-section" transition:animate="none">
<div id="banner-bar" transition:animate="none">
```

**`ScrollTrigger.refresh()` on navigation:** After a VT swap, new images/fonts load asynchronously. `window.load` fires only once. Add to `src/lib/gsap.ts`:

```ts
document.addEventListener("astro:page-load", () => ScrollTrigger.refresh())
```

**Hero/above-fold entrance guard:** Above-fold GSAP entrances replay on every VT return visit — annoying. Guard with `sessionStorage`:

```js
if (sessionStorage.getItem("hero-entered")) {
  // jump to final visible state, no animation
  mm.add("(prefers-reduced-motion: no-preference)", () => {
    gsap.set("...", { clearProps: "transform,opacity" })
  })
  return
}
sessionStorage.setItem("hero-entered", "1")
// full entrance timeline
```

---

### 5.5 Client Router + i18n

When the project uses route-based i18n (`/<lang>/path`), Client Router works seamlessly with localized links. No special router configuration is needed.

**`<html lang>` attribute:** Updates automatically — Client Router swaps the entire `<head>` (including the `<html>` element's attributes) from the new page.

**Localized `<a href>` paths:** Links like `/es/salas/1` are regular internal `<a>` tags — intercepted by the router like any other link. External links and `target="_blank"` links are not intercepted.

**Alternate hreflang tags:** `<link rel="alternate" hreflang="...">` tags in `<head>` are swapped correctly on navigation via the `<head>` swap.

**Frontmatter i18n setup:** The Layout reads `const lang = getLangFromUrl(Astro.url)` and renders `<html lang={lang}>`. This works identically with and without Client Router — the only difference is that `<html>` attributes now update in-place rather than via full page reload.

---

### 5.6 Client Router + Zustand

Zustand stores (especially with `persist` middleware) survive VT navigations — the JS runtime and `localStorage` are never cleared between page swaps. The store instance is the same object across navigations.

**What this means:**
- Store state set on one page is visible on the next page immediately.
- `persist` middleware-backed stores sync to `localStorage` on write and hydrate from it on first load — after that, the in-memory store is the source of truth.
- Route-derived state (active link, current page metadata) should be derived from `window.location` or `astro:page-load`, not assumed to reset.

**If you need per-page store reset:** Subscribe to `astro:page-load` and call your store's reset action. Example with a form store:

```js
document.addEventListener("astro:page-load", () => {
  useFormStore.getState().reset()
})
```

---

## 6. Optional: customizing behavior per element

All of these are optional — with the default setup you already get animated transitions with no extra work.

### 6.1 `transition:animate`

Control the default animation for an element or a subtree:

```astro
<div transition:animate="fade">Fades in/out</div>
<div transition:animate="slide">Slides</div>
<div transition:animate="none">No animation</div>
<main transition:animate="only">Only this element animates</main>
```

### 6.2 `transition:name`

Give an element a shared identity so the browser morphs it between pages instead of cross-fading it (e.g. a hero image or logo that appears on multiple pages):

```astro
<!-- same value on both pages -->
<img src="/logo.webp" transition:name="logo" />
```

### 6.3 `transition:persist`

Keep a hydrated component **mounted across navigations** (its state survives; it is not re-hydrated). Use sparingly and only for genuinely stable UI (e.g. a media player, a chat widget).

```astro
<AudioPlayer client:load transition:persist />
```

> **Caveat:** with `transition:persist`, your component is *not* re-mounted on navigation, so `useEffect(() => {...}, [])` will **not** re-run. The component must update itself by listening to `astro:page-load`.

### 6.4 Custom `::view-transition-*` CSS

Style the snapshots rendered by the browser during the transition:

```css
::view-transition-old(root) {
  animation: fade-out 300ms ease both;
}
::view-transition-new(root) {
  animation: fade-in 300ms ease both;
}
```

### 6.5 The `fallback` prop

For browsers without View Transitions API support, choose the fallback strategy:

```astro
<ClientRouter fallback="animate" /> <!-- default -->
<ClientRouter fallback="swap" />   <!-- swap instantly, no animation -->
<ClientRouter fallback="none" />   <!-- full page load / no router -->
```

---

## 7. Edge cases and things to test

Transitions change browser behavior in ways that are easy to miss. Verify each of these:

1. **Third-party embeds that inject scripts** (maps, chat widgets, external badges). They often initialize on script load; after an in-place swap their elements may be blank or duplicated. Give them a stable `transition:name` or re-init on `astro:page-load`, or exclude them from the router.
2. **Scroll position / anchor deep-links** — confirm jumping to `https://site/page/#section` before and after transitions scrolls correctly.
3. **Persistence of state you actually want** — decide which islands should persist (`transition:persist`) vs. reset every navigation (default).
4. **Forms** — submitting a form via the router (a `<form>` navigation) behaves differently from a full load. Verify values/validation.
5. **Autoplay media** — a `<video>`/`<audio>` element being swapped may reset or keep playing unexpectedly.
6. **Analytics / page view trackers** — track on `astro:page-load` rather than `DOMContentLoaded`, otherwise you only record one page view.
7. **Accessibility** — confirm focus management and screen-reader announcements (Astro handles a lot, but your custom UI should not assume focus resets).
8. **Browser history** — back/forward buttons should re-render the previous page with animation.
9. **GSAP entrances competing with VT** — sections with GSAP `fromTo` reveals need `transition:animate="none"` on their root element, otherwise the VT cross-fade shows content at natural state before GSAP hides it and animates it in (flash). See §5.4.
10. **Stale scripting event listeners after swap** — `document` event listeners from the previous page persist after DOM swap. An `init()` registered on `astro:page-load` from the old page fires on the new page too, creating duplicate GSAP contexts or runaway initializations. Add a section-presence guard (`if (!document.querySelector(".my-root")) return`) as the first line of every init function. See §5.4.
11. **i18n `<html lang>` and hreflang** — `<html lang>` updates via `<head>` swap; localized `<a href>` paths are regular internal links; alternate hreflang `<link>` tags are swapped correctly. See §5.5.
12. **Zustand state across navigations** — stores with `persist` middleware survive VT navigations (same JS runtime + localStorage). Route-derived state should use `window.location`. See §5.6.
13. **Hero/above-fold entrances replaying** — entrance animations on the home page replay every time the user navigates back via VT — annoying. Guard with `sessionStorage` so they play once per session. See §5.4.

---

## 8. Troubleshooting cheatsheet

| Symptom | Likely cause / fix |
|---|---|
| Navigation still does a full reload | `<ClientRouter />` missing from that page's `<head>` (or the page doesn't use the shared layout). |
| Carousel / slider empty or broken after first navigation | Its init ran on `DOMContentLoaded` only. Move it to `astro:page-load` (see 5.1). |
| Active nav link wrong on a hydrated header | Component computed state from server props. Derive it from `window.location` on `astro:page-load` (see 5.2). |
| Hash anchor doesn't scroll (`/page/#section`) | Scroll logic runs only on mount. Add `astro:page-load` handler (see 5.3). |
| Third-party widget duplicated or blank | Widget script ran once against stale DOM. Re-init on `astro:page-load` or give the element `transition:name`/`transition:persist`. |
| Component with `transition:persist` shows stale data | It is not re-mounted. It must listen to `astro:page-load` and update itself. |
| Back/forward button breaks a widget | Missing `popstate` handling; combine with the `astro:page-load` listener (see 5.2). |
| Old browsers flash or miss animation | Default fallback is `animate`; you can set `<ClientRouter fallback="none" />` for a plain load. |
| GSAP animations flash on navigation | Add `transition:animate="none"` on the section with GSAP entrances (see 5.4). |
| GSAP animations create duplicates after navigation | Add section-presence guard `if (!document.querySelector(ROOT)) return` to init function (see 5.4). |
| Hero entrance replays on every visit | Add sessionStorage guard so it plays once per session (see 5.4). |
| i18n: language attribute doesn't change | Verify `<ClientRouter />` is in the shared layout `<head>` (see 3.1 and 5.5). |
| ScrollTrigger reveals fire at wrong position after navigation | Add `ScrollTrigger.refresh()` on `astro:page-load` (see 5.4). |

---

## 9. Summary

The full recipe is just four things:

1. **Add `<ClientRouter />` to the `<head>`** of your shared layout (Sections 2–3).
2. **Move one-time client-side logic from `DOMContentLoaded` to `astro:page-load`** (Section 5) — carousels, scroll animations, active-link state, hash scrolling.
3. **Integrate with project-specific features** — i18n (§5.5), GSAP (§5.4), and Zustand (§5.6) each have dedicated patterns.
4. **Test browser-behavior edge cases** (Section 7).

Optionally layer on `transition:animate`, `transition:name`, `transition:persist`, custom `::view-transition-*` CSS, and the `fallback` prop to fine-tune the experience (Section 6).