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
source: templates://astro/gsap-scrolltrigger/README.md
version: 2026-09-27+57b0fd3

---

# GSAP + ScrollTrigger Animation System (Reusable Astro Guide)

A complete, copy-paste-ready guide for adding **GSAP + ScrollTrigger** animations to
**any Astro project**.

Everything here is plain TypeScript + Astro `<script>` blocks. No React required for animations (if a component needs both GSAP and React interactivity, keep GSAP logic in the Astro `<script>` and mount the React island inside it — islands hydrate independently).

> **GSAP API cheat sheet (inline, no external skills needed):** `gsap.to/from/fromTo` (tweens), `gsap.timeline()` + `-=` positions (sequencing), `gsap.matchMedia()` + `mm.revert()` (responsive/reduced-motion + cleanup), `ScrollTrigger.create` + `trigger/start/toggleActions/scrub/pin` (scroll), `ScrollTrigger.refresh()` (re-measure). Official GSAP docs remain the reference for the rest.

---

## What you get

Three reusable, independent animation capabilities:

| Capability | What it does | Where to read |
| :--- | :--- | :--- |
| **Loader-gated entrance** | A branded preloader that coordinates the page's hero/content entrance so it never plays behind the loader | [02-loader-and-entrance-orchestration.md](./02-loader-and-entrance-orchestration.md) |
| **Scroll-triggered section reveals** | The workhorse pattern: sections fade/slide their content in as they enter the viewport, with automatic `prefers-reduced-motion` fallback | [03-section-reveal-pattern.md](./03-section-reveal-pattern.md) |
| **Scroll effects + kinetic marquee + counters** | Parallax, scrubbed scroll fades, infinite background marquees, animated stat counters | [04-scroll-effects-marquee-and-counters.md](./04-scroll-effects-marquee-and-counters.md) |

Plus:

- **Accessibility & SEO** (reduced-motion + no-JS progressive enhancement + LCP tips): [05-accessibility-and-pitfalls.md](./05-accessibility-and-pitfalls.md)

---

---

## Skill map

| Local file | Requires skill(s) |
| :--- | :--- |
| `01-setup-and-mandatory-files.md` | gsap-core, gsap-scrolltrigger, gsap-performance |
| `02-loader-and-entrance-orchestration.md` | gsap-timeline |
| `03-section-reveal-pattern.md` | gsap-core, gsap-scrolltrigger |
| `04-scroll-effects-marquee-and-counters.md` | gsap-scrolltrigger, gsap-performance |
| `05-accessibility-and-pitfalls.md` | gsap-core, gsap-performance |

## Architecture at a glance

Two layers:

```
┌─────────────────────────────────────────────────────────────┐
│  LAYER 3 · Per-component <script> blocks                    │
│  (Hero, every section, Gallery)                             │
│  ─ each self-contained: imports from @/lib/gsap,            │
│    scopes selectors to its own section, builds tweens       │
│    init on astro:page-load                                   │
├─────────────────────────────────────────────────────────────┤
│  LAYER 2 · Shared module  (src/lib/gsap.ts)                 │
│  ─ SSR-safe plugin registration + ScrollTrigger config      │
│    + gsap.defaults + refresh-on-load                        │
│    + optional: animation-manager, kinetic-marquee           │
├─────────────────────────────────────────────────────────────┤
│  LAYER 1 · SEO-safe reveal (no CSS pre-hiding needed)      │
│  ─ fromTo + clearProps: content visible by default          │
│  ─ alternative: .js-reveal + .no-js CSS fallback            │
└─────────────────────────────────────────────────────────────┘
```

Key rules that keep it maintainable:

1. **Each component scopes its selectors** to its own root element so tweens never leak.
2. **`prefers-reduced-motion` is handled** via `gsap.matchMedia()` in every section — full animation for `no-preference`, no movement for `reduce`.
3. **Init once** on `astro:page-load` — never call tweens directly alongside the listener.

---

## Quick start (TL;DR)

1. Install the dependency:
   ```bash
   pnpm add gsap
   ```

2. Create `src/lib/gsap.ts` from [01-setup-and-mandatory-files.md](./01-setup-and-mandatory-files.md#2-shared-module--srclibgsapts).

3. Import it in each component's `<script>` block — **not** globally in Layout:
   ```astro
   <script>
     import { gsap, ScrollTrigger } from "@/lib/gsap"
     const init = () => { /* animations */ }
     document.addEventListener("astro:page-load", init)
   </script>
   ```

4. Pick a SEO-safe reveal strategy from [01-setup-and-mandatory-files.md](./01-setup-and-mandatory-files.md#4-seo-safe-reveal-strategies).

5. Pick a pattern and paste it into your components:
   - [02-loader-and-entrance-orchestration.md](./02-loader-and-entrance-orchestration.md) — preloader + gated hero entrance
   - [03-section-reveal-pattern.md](./03-section-reveal-pattern.md) — scroll reveals
   - [04-scroll-effects-marquee-and-counters.md](./04-scroll-effects-marquee-and-counters.md) — parallax, marquee, counters

---

## File map

| File in this repo | Purpose in the docs |
| :--- | :--- |
| `README.md` | This index + architecture + quick start |
| `01-setup-and-mandatory-files.md` | Shared module, wiring, SEO-safe reveal strategies, optional helpers |
| `02-loader-and-entrance-orchestration.md` | Preloader + `animation-manager` + hero entrance |
| `03-section-reveal-pattern.md` | The reusable section template + 6 real variations |
| `04-scroll-effects-marquee-and-counters.md` | Parallax, scrubbed fades, kinetic marquee, stat counters |
| `05-accessibility-and-pitfalls.md` | Reduced motion, no-JS, troubleshooting checklist |
| `06-optional-swiper-scroller.md` | Appendix: Swiper horizontal scroller (optional companion) |

---

## What this guide does NOT cover

- **GSAP API reference** — see the official GSAP documentation.
- **GSAP SplitText, ScrollSmoother, Flip, Draggable** — outside scope; they follow the same per-component pattern.
- **View Transitions / SPA routing integration** — the `gsap.context()` + `astro:after-swap` cleanup pattern is documented in [01](./01-setup-and-mandatory-files.md#for-projects-with-view-transitions).
- **CSS-only animations** — this guide is for GSAP timelines and ScrollTrigger specifically.

---

## When NOT to use this

- **Pure CSS needs:** a simple `transition` on hover/scroll is cheaper than GSAP.
  Reach for GSAP when you need sequencing (timelines), scroll scrubbing, staggering
  across many elements, or integration with a loader.
- **No-JS sites:** all the templates produce indexable content (raw HTML is visible),
  but animated entrances obviously need JS. For strict no-JS requirements, skip the
  loader and keep reveals subtle.

Continue to [01-setup-and-mandatory-files.md](./01-setup-and-mandatory-files.md).
