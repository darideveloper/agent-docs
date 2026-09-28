---
created: 2026-08-11
tags:
  - gsap
  - scrolltrigger
  - animation
  - astro
  - documentation
type: resource
status: active
source: templates://astro/gsap-scrolltrigger/01-setup-and-mandatory-files.md
version: 2026-09-27+57b0fd3

---

# 01 · Setup & Mandatory Files

Everything you need to bootstrap the animation system in an **Astro project**.

> **GSAP API cheat sheet (inline):** `registerPlugin`, `gsap.defaults({ease, duration})`, `timeline` positions (`-=`, `+=`, `<`), `matchMedia()` branches + `mm.revert()` cleanup, `ScrollTrigger` `trigger/start/toggleActions/scrub`, `refresh()`. This guide covers Astro-specific integration only.

---

## 1. Install the dependency

The system is built on **GSAP 3** (including the optional **ScrollTrigger** plugin,
which ships inside the `gsap` package — no extra dependency).

```bash
pnpm add gsap
```

If you also want the Swiper-powered horizontal scroller:

```bash
pnpm add swiper
```

Versions used (examples): `gsap@^3.12.7`, `swiper@^12.1.3`, `astro@^5 || ^6`.

---

## 2. Shared module — `src/lib/gsap.ts`

The single file every component imports from. It registers plugins **SSR-safe**
(guarded with `typeof window !== "undefined"`), configures `ScrollTrigger` global
options, sets tween defaults, and wires a `load`-event `ScrollTrigger.refresh()`.

**Create `src/lib/gsap.ts`. Copy verbatim:**

```ts
import { gsap } from "gsap"
import { ScrollTrigger } from "gsap/ScrollTrigger"

// SSR-safe plugin registration + config (GSAP touches `window` —
// keep everything inside the guard; Astro imports this module during SSR)
if (typeof window !== "undefined") {
  gsap.registerPlugin(ScrollTrigger)

  // ScrollTrigger performance tuning
  ScrollTrigger.config({
    limitCallbacks: true,
    ignoreMobileResize: true,
  })

  // Global tween defaults
  gsap.defaults({
    ease: "power4.out",
    duration: 1.2,
  })

  // Re-measure triggers when images, fonts, and lazy content settle
  window.addEventListener("load", () => ScrollTrigger.refresh())
}

export { gsap, ScrollTrigger }
```

### What each line does

| Setting | Effect |
| :--- | :--- |
| `typeof window !== "undefined"` guard | Prevents `registerPlugin` from running during Astro's server-side render — GSAP is browser-only |
| `ScrollTrigger.config({ limitCallbacks: true })` | Fire callbacks only near the threshold — reduces work during fast scrolls |
| `ScrollTrigger.config({ ignoreMobileResize: true })` | Skip refresh on mobile URL bar show/hide |
| `gsap.defaults({ ease, duration })` | Every tween inherits these unless it overrides `ease`/`duration` |
| `window.addEventListener("load", ...)` | Re-measures trigger positions after images/fonts/lazy content settle |

> GSAP API cheat sheet (inline): `registerPlugin` / `gsap.defaults` / `ease`,
> `ScrollTrigger.config` / `refresh()`, `timeline` positions, `matchMedia()` + `mm.revert()`.

> **Per-section `registerPlugin` calls are harmless** and can be kept or removed — the shared module's registration is sufficient.

---

## 3. Wiring it into your components

Import `@/lib/gsap` in each component's `<script>` block — **not** in the Layout's
`<head>`. Astro bundles the import into a shared chunk that every page caches, and
tree-shakes subpath imports (`gsap/ScrollTrigger`). Never use `is:inline` for GSAP.

```astro
---
// MyComponent.astro
---
<section class="js-my-section">
  <!-- markup -->
</section>

<script>
  import { gsap, ScrollTrigger } from "@/lib/gsap"

  const initAnimations = () => {
    if (!document.querySelector(".js-my-section")) return // section-presence guard (V1)
    // animations here (use mm.revert()/ctx.revert() cleanup per §5)
  }

  initAnimations() // immediate init for first paint (V1)
  document.addEventListener("astro:page-load", initAnimations) // re-init on VT nav
  document.addEventListener("astro:after-swap", () => ScrollTrigger.refresh()) // cleanup/refresh (V1)
</script>
```

### Why `astro:page-load`?

`astro:page-load` fires on initial page load and after every View Transition
navigation. Base projects ship `<ClientRouter />` (default ON), so use the V1
lifecycle from `../astro-client-side-page-transitions.md` §5: section-presence
guard + immediate `init()` (first paint) + `astro:page-load` re-init +
`astro:after-swap` cleanup. Router-OFF (escape only) is V0: call `init()` once,
no listeners. Never use V0 + listeners together (double-init).

### For projects with View Transitions

When you enable `<ClientRouter />`, add cleanup so stale tweens and ScrollTriggers
don't leak across navigations. Inline API: `gsap.context(() => {...}, scope)` scopes
selector text + `ctx.revert()` kills scoped tweens/ScrollTriggers:

```ts
let ctx: ReturnType<typeof gsap.context>

const init = () => {
  ctx?.revert()
  ctx = gsap.context(() => {
    // tweens and ScrollTriggers go here
  }, section)
}

document.addEventListener("astro:page-load", init)
document.addEventListener("astro:after-swap", () => ctx?.revert())
```

> **Two cleanup approaches, pick per component.** Use the §5 `mm?.revert()` pattern (matchMedia + guard + immediate init) for anything with reduced-motion branches (recommended default). Use the bare `gsap.context()` snippet above only for tiny components with no `matchMedia`. Never nest
> `gsap.context()` inside `gsap.matchMedia()` — matchMedia creates a context
> internally; use `mm.revert()` only (see §5).

### Bundling & performance notes

- Astro processes `<script>` blocks (no attributes) as bundled modules. Shared
  dependencies like `gsap` go into a single cacheable chunk; each page only loads
  the chunk once the browser caches it.
- `gsap/ScrollTrigger` is tree-shaken per page — only pages whose components import
  it pay the cost.
- `<script>` modules are automatically deferred (non-render-blocking) — they don't
  delay First Contentful Paint.

---

## 4. SEO-safe reveal strategies

Three approaches. All are indexable by crawlers and degrade gracefully without
JS. Pick whichever fits your project — they are alternatives, not mutually
exclusive combinations.

### A. `fromTo` + `clearProps`

No CSS pre-hiding. Content is visible by default. GSAP's `immediateRender` applies
the hidden from-state only when JS runs; `clearProps` restores the natural CSS
state after completion. Crawlers see the raw HTML text; no-JS users see everything.

```ts
import { gsap, ScrollTrigger } from "@/lib/gsap"

document.addEventListener("astro:page-load", () => {
  gsap.fromTo(".my-el",
    { y: 30, opacity: 0 },
    {
      y: 0,
      opacity: 1,
      duration: 0.7,
      ease: "power2.out",
      clearProps: "transform,opacity",
      scrollTrigger: {
        trigger: ".my-section",
        start: "top 85%",
      },
    }
  )
})
```

### B. CSS `js-reveal` fallback (progressive enhancement)

Elements start hidden via a CSS class; the `.no-js` override on `<html>` makes
them visible if JS never runs.

**CSS** (add to `src/styles/global.css`):

```css
@utility js-reveal {
  opacity: 0;
  visibility: hidden;
}

.no-js .js-reveal {
  opacity: 1 !important;
  visibility: visible !important;
}
```

**Layout markup**:

```astro
<html lang="en" class="no-js">
  <head>
    <script is:inline>
      document.documentElement.classList.remove("no-js")
      document.documentElement.classList.add("js")
    </script>
  </head>
</html>
```

With this approach, unhide elements in JS before building `.from()` tweens so
GSAP can measure their natural positions:

```ts
gsap.set(section.querySelectorAll(".js-my-reveal"), { autoAlpha: 1 })
// ...then build .from() tweens
```

> Never hide elements with Tailwind's `opacity-0` alone — the `.no-js` override
> only targets `.js-reveal`. See [05-accessibility-and-pitfalls.md](./05-accessibility-and-pitfalls.md#no-js-fallback).

### C. Hybrid — `.js-reveal` CSS hiding + `gsap.set(autoAlpha: 1)` + `.from()`

Uses approach B's CSS hiding (`.js-reveal` + `.no-js` fallback) for no-JS safety,
but unhides elements with `gsap.set({ autoAlpha: 1 })` before building `.from()`
tweens so GSAP can measure the natural state — exactly what the section-reveal
template in [03-section-reveal-pattern.md](./03-section-reveal-pattern.md) uses.

```ts
// unhide so GSAP can measure natural positions BEFORE the .from()
gsap.set(section.querySelectorAll(".js-reveal"), { autoAlpha: 1 })

tl.from(".js-reveal", {
  autoAlpha: 0,
  y: 40,
  duration: 1.2,
  ease: "power4.out",
})
```

Why this works: the CSS class keeps content visible for no-JS users (approach B's
benefit), while `gsap.set(autoAlpha: 1)` normalizes the state before the `.from()`
tween — avoiding the hidden-element measurement problem that would otherwise
break the reveal (see 03's "unhide then `.from()`" step).

**Choosing between them:** prefer A when you want zero CSS pre-hiding and the
simplest markup; prefer B when you want a strict CSS-first fallback; prefer C
(the template's choice) when you combine the `.js-reveal` no-JS safety with the
`.from()` measurement trick.

---

## 5. View Transitions + GSAP (Client Router)

> Cross-reference: `../astro-client-side-page-transitions.md` §5.4 for the Client Router side of this pattern.

When `<ClientRouter />` is enabled, GSAP components need a lifecycle that handles
VT navigations correctly: cleanup stale triggers from the previous page, re-init
on the new page, and prevent the VT cross-fade from competing with GSAP fromTo
reveals.

The full pattern — the triple-entry + guard setup, `transition:animate="none"`
on animated sections, the `ScrollTrigger.refresh()` on `astro:page-load`, and the
hero entrance guard — is owned by
[astro-client-side-page-transitions.md](../astro-client-side-page-transitions.md#54-client-router--gsap)
§5.4. Follow that document for the canonical implementation.

The one GSAP-side detail to keep inline for context: add a
`transition:animate="none"` attribute to every section root that has GSAP fromTo
entrances, or the VT cross-fade flashes the content at natural state before GSAP
hides and animates it.

```astro
<section class="js-hero-section" transition:animate="none">
<div id="salas-gallery" transition:animate="none">
```

---

## 6. Optional helpers

These are provided by the guide as convenience code. Create them only if your
project needs them.

### `animation-manager.ts` (for the preloader → [02](./02-loader-and-entrance-orchestration.md))

A singleton that gates hero entrances behind a GSAP preloader. If no loader is
present, entrances play immediately. Copy from [02-loader-and-entrance-orchestration.md](./02-loader-and-entrance-orchestration.md).

### `kinetic-marquee.ts` (for infinite marquees → [04](./04-scroll-effects-marquee-and-counters.md))

A factory that turns a horizontal content strip into a seamless looping marquee.
Copy from [04-scroll-effects-marquee-and-counters.md](./04-scroll-effects-marquee-and-counters.md).

### `animate-counters.ts` + `reveal-helper.ts`

Convenience shortcuts for stat counters and DRY section reveals.
Copy from [04](./04-scroll-effects-marquee-and-counters.md#3-animated-stat-counters)
and [03](./03-section-reveal-pattern.md#reducing-the-copy-paste).

---

## 7. Verify your setup

1. `pnpm run dev`, open the page.
2. In DevTools, import at the console: `const { gsap, ScrollTrigger } = await import("gsap")  # in browser console, or check window.gsap` → `ScrollTrigger` should be defined.
3. Scroll — sections using the reveal pattern should animate in.
4. DevTools → "Disable JavaScript" → all content should still be visible: approach A has no pre-hiding; approaches B/C rely on the `.no-js` override revealing `.js-reveal` elements.

Ready for the patterns. Next: [02-loader-and-entrance-orchestration.md](./02-loader-and-entrance-orchestration.md).
