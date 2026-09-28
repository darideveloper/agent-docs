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
source: templates://astro/gsap-scrolltrigger/03-section-reveal-pattern.md
version: 2026-09-27+57b0fd3

---

# 03 · The Section Reveal Pattern (the workhorse)

The most reused pattern in the system. **Any section of content fades/slides in
when it scrolls into the viewport**, with a built-in reduced-motion fallback.

It uses **approach C (hybrid)** from
[01-setup-and-mandatory-files.md](./01-setup-and-mandatory-files.md#4-seo-safe-reveal-strategies):
`.js-reveal` CSS hiding for no-JS safety, `gsap.set({ autoAlpha: 1 })` to unhide
before measuring, then `.from()` tweens.

It is fully self-contained per component — no shared code, no orchestrator. You
copy the template, change the `my` prefix to something unique per section, add the
classes to your markup, and you're done.

---

## The template (copy-paste, then rename `my`)

```astro
<!-- MySection.astro -->
<section class="js-my-section relative">
  <!--
    ⬇ Elements use TWO classes:
    1. js-reveal   → hides the element (CSS) + covered by the .no-js override
    2. js-my-*     → section-scoped grouping selectors for GSAP
  -->
  <div class="js-my-header js-my-reveal js-reveal">
    <h2>My Headline</h2>
  </div>

  <div class="grid">
    <div class="js-my-card js-my-reveal js-reveal">Card 1</div>
    <div class="js-my-card js-my-reveal js-reveal">Card 2</div>
    <div class="js-my-card js-my-reveal js-reveal">Card 3</div>
  </div>
</section>

<script>
  import { gsap, ScrollTrigger } from "@/lib/gsap"

  // Optional — src/lib/gsap.ts already registers it. Harmless either way.
  gsap.registerPlugin(ScrollTrigger)

  function initMyAnimations() {
    const section = document.querySelector(".js-my-section")
    if (!section) return

    const mm = gsap.matchMedia()

    mm.add("(prefers-reduced-motion: no-preference)", () => {
      // 1. Unhide so GSAP can measure the natural state BEFORE the .from()
      gsap.set(section.querySelectorAll(".js-my-reveal"), {
        autoAlpha: 1,
        force3D: true,
      })

      // 2. One timeline per section, triggered when its top hits 80% of viewport
      const tl = gsap.timeline({
        scrollTrigger: {
          trigger: section,
          start: "top 80%",
          toggleActions: "play none none none",
        },
      })

      tl.from(".js-my-header", {
        autoAlpha: 0,
        y: 40,
        duration: 1.2,
        ease: "power4.out",
      }).from(
        ".js-my-card",
        {
          autoAlpha: 0,
          y: 30,
          duration: 1.0,
          stagger: 0.15,
          ease: "power3.out",
        },
        "-=0.8",
      )
    })

    mm.add("(prefers-reduced-motion: reduce)", () => {
      // Fallback: no movement, just fade everything in
      gsap.set(section.querySelectorAll(".js-my-reveal"), { autoAlpha: 0 })

      ScrollTrigger.create({
        trigger: section,
        start: "top 80%",
        onEnter: () => {
          gsap.to(section.querySelectorAll(".js-my-reveal"), {
            autoAlpha: 1,
            duration: 0.8,
            stagger: 0.1,
          })
        },
      })
    })
  }

  initMyAnimations()
</script>
```

---

## How it works, step by step

### Step 1 — Naming conventions

| Selector | Purpose |
| :--- | :--- |
| `.js-my-section` | Root scope. The script queries **only within** this element so tweens never leak to other sections |
| `.js-reveal` | **The hiding mechanism.** Sets `opacity:0; visibility:hidden` in CSS. The `.no-js .js-reveal` override makes it visible for no-JS users. Every revealable element **must** carry this class |
| `.js-my-reveal` | *Collection* class. `gsap.set` + `.from()` target this for batch operations (unhide, prepare animation state) |
| `.js-my-header`, `.js-my-card` | *Group* classes. Everything in one `.from()` tweens together / staggers |

> **Why not `opacity-0` alone?** Tailwind's `opacity-0` is not covered by the
> `.no-js` override. If you use `opacity-0` instead of `.js-reveal`, no-JS users
> get blank content. Always pair your section-specific marker classes with
> `.js-reveal`.

Replace `my` with a unique short prefix per section (`hero`, `voice`, `plans`,
`social`...). If you use the same prefix in two sections on one page, the queries
will collide — that's why the root `.js-<prefix>-section` scope matters.

### Step 2 — `gsap.matchMedia()` branches

> `gsap.matchMedia()` inline: `mm.add("(prefers-reduced-motion: no-preference)", ...)` for animation, `mm.add("(prefers-reduced-motion: reduce)", ...)` for fade-only fallback; `mm.revert()` cleans up. Never nest `gsap.context()` inside `matchMedia`.

The template registers two branches:

- **`(prefers-reduced-motion: no-preference)`** — full animation.
- **`(prefers-reduced-motion: reduce)`** — fade-in only, no movement.

### Step 3 — The "unhide then `.from()`" trick (critical)

```ts
gsap.set(section.querySelectorAll(".js-my-reveal"), { autoAlpha: 1 })
```

The markup starts with `.js-reveal` (hidden). A `.from()` tween animates *from* a state *to*
the current state — but "current" is measured when the tween is created. If the
element is `opacity: 0` at that moment, GSAP measures a hidden element (typically
`autoAlpha` measuring a zero-height/zero-position layout) and the reveal breaks.

So: **make the elements visible first, then define the `.from()` destinations.**
The `autoAlpha: 0` *inside* the `.from()` re-hides them, and GSAP knows exactly
what the natural end-state looks like.

> Rule of thumb: if your reveal looks wrong/flashing, you forgot this `gsap.set(...autoAlpha: 1)` line.

### Step 4 — The ScrollTrigger config

> ScrollTrigger inline: `trigger` (controller), `start: "top 80%"` (trigger-top hits 80% viewport), `toggleActions: "play none none none"` (play once). Official GSAP docs for the rest.

| Key | Meaning |
| :--- | :--- |
| `trigger` | The element that controls the animation |
| `start: "top 80%"` | Play when the trigger's **top** reaches **80% down the viewport** (i.e. 20% from the bottom) |
| `toggleActions: "play none none none"` | Four actions for *enter / leave / enter-back / leave-back* — here: play once on enter, do nothing after |

**Start-position cheat sheet** (recommended values):

| `start` | Section appears when its top is at... | Recommended for |
| :--- | :--- | :--- |
| `"top 65%"` | 35% from the bottom of viewport | Hero/first sections, dramatic reveals |
| `"top 68%"` | 32% from bottom | Shorter CTAs |
| `"top 75%"` | 25% from bottom | Standard sections |
| `"top 80%"` | 20% from bottom | List/card-heavy sections, tall sections |
| `"top 85%"` | 15% from bottom | Sections near the page footer |

Lower number = the animation waits longer before firing = more dramatic timing.
Keep `toggleActions: "play none none none"` for one-shot reveals.

---

## Variations gallery

All of these are the same template with a different set of `.from()` groups and
easing. Pick the one closest to what you need.

### A. Header + staggered cards

```ts
tl.from(".js-gritones-header", {
  autoAlpha: 0, y: 40, duration: 1.2, ease: "power4.out",
}).from(
  ".js-gritones-card",
  { autoAlpha: 0, y: 30, duration: 1.0, stagger: 0.15, ease: "power3.out" },
  "-=0.8",
)
```

### B. Ambient glow + header + cards + footer

Shows a slow decorative glow fading/zooming in *before* the content:

```ts
tl.from(".js-plans-glow", {
  autoAlpha: 0, scale: 0.8, duration: 2, ease: "power2.out",
})
  .from(".js-plans-header", { autoAlpha: 0, y: 40, duration: 1.2, ease: "power4.out" }, "-=1.5")
  .from(".js-plans-card", { autoAlpha: 0, y: 60, duration: 1.2, stagger: 0.2, ease: "expo.out" }, "-=0.8")
  .from(".js-plans-footer", { autoAlpha: 0, y: 20, duration: 1, ease: "power3.out" }, "-=0.6")
```

> `scale` on the glow creates a gentle "zoom" reveal; `y: 60` with `expo.out` makes
> cards travel further and snap into place.

### C. Watermark scale-in

A giant background word scales from 103%→100% while fading in:

```ts
tl.from(watermark, {
  autoAlpha: 0, scale: 1.03, duration: 1.12, ease: "power2.out",
})
```

### D. Horizontal slide for list items

`x` moves items in from the right instead of the usual vertical `y`:

```ts
tl.from(".js-collab-header", { autoAlpha: 0, y: 40, duration: 1.2, ease: "power4.out" })
  .from(
    ".js-collab-item",
    { autoAlpha: 0, x: 30, y: 20, duration: 1.0, stagger: 0.1, ease: "power3.out" },
    "-=0.8",
  )
```

### E. "Pop" icons with a bounce

`scale: 0.9` + `back.out(1.7)` overshoots for a playful pop:

```ts
tl.from(".js-about-header", { autoAlpha: 0, y: 40, duration: 1.4, delay: 0.5, ease: "power4.out" })
  .from(".js-about-card", { autoAlpha: 0, y: 30, duration: 1.2, stagger: 0.15, ease: "power3.out" }, "-=1.0")
  .from(".js-about-quote", { autoAlpha: 0, y: 20, duration: 1.2, ease: "expo.out" }, "-=0.8")
  .from(".js-about-icon-item", { autoAlpha: 0, scale: 0.9, duration: 0.8, stagger: 0.1, ease: "back.out(1.7)" }, "-=0.6")
```

### F. Multi-part editorial reveal

A long chain (glows → header → quote → content → feature list → embed → proof),
each overlapping the last:

```ts
tl.from(section.querySelectorAll(".js-my-glow"), {
  autoAlpha: 0, duration: 2.0, ease: "power2.inOut",
})
  .from(section.querySelector(".js-my-header"), { autoAlpha: 0, y: 40, duration: 1.2, delay: 0.3, ease: "power4.out" }, 0)
  .from(section.querySelector(".js-my-quote"), { autoAlpha: 0, x: -20, duration: 1.2, ease: "power3.out" }, "-=0.8")
  .from(section.querySelector(".js-my-content"), { autoAlpha: 0, y: 20, duration: 1.0, ease: "power2.out" }, "-=0.6")
  .from(section.querySelectorAll(".js-my-feature"), { autoAlpha: 0, y: 10, stagger: 0.1, duration: 0.8, ease: "power2.out" }, "-=0.4")
  .from(section.querySelector(".js-my-embed"), { autoAlpha: 0, scale: 0.98, y: 20, duration: 1.2, ease: "expo.out" }, "-=0.5")
  .from(section.querySelector(".js-my-proof"), { autoAlpha: 0, y: 15, duration: 1.0, ease: "power2.out" }, "-=0.8")
```

---

## Easing cheat sheet (recommended)

> Easing inline: `power4.out` (cinematic default), `power3/2.out` (snappier), `expo.out` (dramatic snap), `back.out(1.7)` (playful pop), `power1.inOut` (progress bars).

Common picks for scroll reveals:

| Ease | Feel |
| :--- | :--- |
| `power4.out` | Default (from `gsap.defaults`). Long, smooth deceleration — cinematic |
| `power3.out` | Slightly quicker deceleration |
| `power2.out` | Snappier, good for cards |
| `power2.inOut` | Gentle ease both ends — good for ambient glows |
| `expo.out` | Fast start, dramatic snap — good for big distance (cards, CTAs) |
| `back.out(1.7)` | Overshoots past the target then settles — playful pop |
| `power1.inOut` | Slow progress bars |

## LCP tip

For above-the-fold / LCP-critical elements, avoid animating `opacity` — use only
`transform` (`y`, `scale`, `x`). Hiding an LCP element at `opacity: 0` delays the
LCP measurement. The hero template in [02](./02-loader-and-entrance-orchestration.md)
animates the banner via `scale` alone for this reason. See
[05-accessibility-and-pitfalls.md](./05-accessibility-and-pitfalls.md) for more
SEO-safe reveal patterns.

---

## Reducing the copy-paste

Every section repeats the same ~40 lines of `matchMedia` boilerplate. The reference
implementation intentionally keeps it duplicated per component (readable, zero indirection,
and each section is independently deletable). If you want less repetition, extract
a tiny helper:

> **⚠️ Convenience-only, not the reference implementation.** The helper below is
> optional sugar. The canonical (reference) implementation is the per-component
> template above — that is what the project ships. Only use the helper if it
> genuinely simplifies your project; it changes reveal behavior (see the trade-off
> below).

```ts
// src/lib/reveal-helper.ts
import { gsap, ScrollTrigger } from "@/lib/gsap"

gsap.registerPlugin(ScrollTrigger)

export function initSectionReveal(prefix: string, start = "top 80%") {
  const section = document.querySelector(`.js-${prefix}-section`)
  if (!section) return

  const mm = gsap.matchMedia()
  const reveals = section.querySelectorAll(`.js-${prefix}-reveal`)

  mm.add("(prefers-reduced-motion: no-preference)", () => {
    gsap.set(reveals, { autoAlpha: 1, force3D: true })

    const tl = gsap.timeline({
      scrollTrigger: { trigger: section, start, toggleActions: "play none none none" },
    })

    tl.from(reveals, { autoAlpha: 0, y: 40, duration: 1.2, stagger: 0.12, ease: "power4.out" })

    return () => {
      tl.kill()
      ScrollTrigger.getAll().forEach((st) => st.trigger === section && st.kill())
    }
  })

  mm.add("(prefers-reduced-motion: reduce)", () => {
    gsap.set(reveals, { autoAlpha: 0 })

    ScrollTrigger.create({
      trigger: section,
      start,
      onEnter: () => gsap.to(reveals, { autoAlpha: 1, duration: 0.8, stagger: 0.1 }),
    })
  })
}
```

Then each component's script becomes:

```ts
import { initSectionReveal } from "@/lib/reveal-helper"
initSectionReveal("plans", "top 75%")
```

> The reference implementation ships the verbose per-section version on
> purpose — it's more copy-paste but every section is self-contained and trivially
> tweakable. Only reach for the helper if you have 5+ sections that share the same
> reveal shape.
>
> **Trade-off:** the helper animates every `.js-<prefix>-reveal` element as a single
> staggered group with identical easing/duration. The verbose template lets each
> group (`.js-my-header`, `.js-my-card`, ...) get its own `.from()` with distinct
> timing. If your sections need per-group choreography, stick with the template —
> don't force them into the helper.

Next: [04-scroll-effects-marquee-and-counters.md](./04-scroll-effects-marquee-and-counters.md).


> V1 lifecycle ([Transitions](../astro-client-side-page-transitions.md) §5): section-presence guard + immediate init() + astro:page-load re-init + astro:after-swap cleanup + ScrollTrigger.refresh(). Do not call init once without listeners when <ClientRouter /> is ON.
