---
created: 2026-08-11
updated: 2026-08-11
tags:
  - gsap
  - scrolltrigger
  - animation
  - accessibility
  - astro
  - documentation
type: resource
status: active
source: templates://astro/gsap-scrolltrigger/05-accessibility-and-pitfalls.md
version: 2026-09-17+4cf710f

---

# 05 · Accessibility & Pitfalls

How the system stays accessible (`prefers-reduced-motion`, no-JS) and the failure
modes you'll hit when porting it — with fixes.

---

## 1. Reduced motion — three layers of defense

> `gsap.matchMedia()` inline: two branches (`no-preference` full animation, `reduce` fade-only); cleanup via `mm.revert()`. Official GSAP docs for condition objects.

The system respects `prefers-reduced-motion` at three levels. You should keep all
three:

### Layer 1 — Entrance orchestrator (loader-gated entrances only)

`animation-manager.ts` checks the media query when it plays a registered entrance
and **fast-forwards it to the end state** (`item.progress(1)`) instead of playing:

```ts
private playEntrance(item: gsap.core.Timeline | gsap.core.Tween) {
  const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
  if (prefersReducedMotion) {
    if ("progress" in item) {
      item.progress(1)
    } else {
      item.play()
    }
  } else {
    item.play()
  }
}
```

### Layer 2 — `gsap.matchMedia()` in every section

Each section registers two branches. The `reduce` branch fades content in **without
movement**:

```ts
mm.add("(prefers-reduced-motion: reduce)", () => {
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
```

### Layer 3 — CSS (`@media (prefers-reduced-motion)`)

For **pure-CSS** hover/transition effects (not GSAP), add the standard guard so
your Tailwind/CSS transitions also honor the preference:

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    transition-duration: 0.01ms !important;
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
  }
}
```

**Why the fallback still uses GSAP instead of just CSS:** the elements start at
`opacity-0` (from the CSS fallback) — without *some* JS they'd stay invisible.
So the reduced-motion branch is a JS-driven **fade-in** that honors the user's
preference while still revealing content.

---

## 2. No-JS fallback (progressive enhancement)

The `no-js` class is the mechanism. Timeline:

1. `<html class="no-js">` in the layout markup.
2. An `is:inline` script swaps it to `js` **before** anything renders.
3. CSS rule makes `.js-reveal` elements visible when `no-js` is still present:

```css
.no-js .js-reveal {
  opacity: 1 !important;
  visibility: visible !important;
}
```

With JS: elements with `.js-reveal` start hidden and GSAP reveals them.
Without JS: `no-js` never gets removed → the override wins → content is fully
visible and static. **No JS, no broken hidden content.**

> **Critical:** Tailwind's `opacity-0` is **not** covered by this override.
> If you hide elements with `opacity-0` alone (without `.js-reveal`), no-JS users
> get an invisible page. Always pair section marker classes with `.js-reveal` for
> the initial hidden state. See Pitfall P9 below.

---

## 3. Common pitfalls & fixes

### P1. Reveals animate wrong / flash / jump

**Cause:** the "unhide then `.from()`" step was skipped.
**Fix:** always run `gsap.set(elements, { autoAlpha: 1, force3D: true })` *before*
building `.from()` tweens.

```ts
// WRONG — element is opacity:0 when .from() measures it
tl.from(".js-my-header", { autoAlpha: 0, y: 40 })

// RIGHT — unhide first so GSAP measures the natural end state
gsap.set(section.querySelectorAll(".js-my-reveal"), { autoAlpha: 1 })
tl.from(".js-my-header", { autoAlpha: 0, y: 40 })
```

### P2. Content stays invisible (never animates in)

Check, in order:

1. Is the section's `start` value reached? If the section is taller than the
   viewport, `"top 80%"` may never fire because the section top is *above* the
   viewport top when it's scrolled into view. Use `"top bottom"` (fires the moment
   the section top enters the viewport bottom) or `start: "top 75%"`.
2. Is there an ancestor with `overflow-x: hidden` (or `overflow: hidden`) between
   the trigger and the viewport? That breaks ScrollTrigger's position calculations
   — add `scrollerProxy` or remove the overflow.
3. Did the reduced-motion branch set `autoAlpha: 0` while the OS is actually in
   reduced-motion mode? Check with DevTools → Rendering → "Emulate CSS media feature
   prefers-reduced-motion: reduce".

### P3. Elements animate while off-screen / below the fold

That's normal for `start: "top 80%"` on very tall pages — the trigger fires when
the section reaches 80% down the viewport, which for a tall section means it starts
before it's fully visible. Lower the number (`"top 90%"` fires later) or switch to
`"top bottom"` + `toggleActions`.

### P4. Layout shift / reflow when scrolling

> Animate only `transform`/`opacity` (`x`, `y`, `scale`, `autoAlpha`, `rotation`). Add `will-change: transform` if you see jank.

Key: animate only `transform`/`opacity` properties (`x`, `y`, `scale`, `autoAlpha`, `rotation`). Add `will-change: transform` to elements you animate if you see jank.

### P5. ScrollTrigger offsets are wrong after images/fonts load

ScrollTrigger measures positions once at init. Late-loading images, custom fonts,
or lazy-loaded content shift the layout below the triggers → reveals fire too early
or not at all. Fixes:

```ts
// After images/fonts settle:
ScrollTrigger.refresh()

// or automatically on window load (already wired in src/lib/gsap.ts):
window.addEventListener("load", () => ScrollTrigger.refresh())
```

Also `ScrollTrigger.config({ ignoreMobileResize: true })` (from setup) prevents
pointless refreshes when the mobile URL bar collapses.

### P6. Duplicated content with `initKineticMarquee`

The factory duplicates its children **every time it runs**. The in-doc factory guards with `_marqueeInit` and resets it in the returned cleanup — always use the returned cleanup on unmount/remount, and never call init twice on the same container without reverting first.

### P7. Dead code from View Transitions

`animation-manager.ts` listens for `astro:after-swap` — that only fires if you add
Astro's `<ClientRouter />`. If you don't use View Transitions, the listener is inert;
either delete it or remember it's there when you add a router later (it correctly
resets the entrance queue on route changes).

### P8. `registerPlugin(ScrollTrigger)` repeated everywhere

`src/lib/gsap.ts` already registers it globally. The per-file `registerPlugin` calls in
each component are redundant but **harmless** (idempotent). You can delete them.

### P9. Content invisible for no-JS users

**Cause:** elements hidden with Tailwind's `opacity-0` (or any class other than
`.js-reveal`) are not unhidden by the `.no-js .js-reveal` override.
**Fix:** every revealable element must carry the `.js-reveal` class, which is the
exact class the `no-js` override targets. Use section-specific classes
(`.js-my-header`, `.js-my-card`) only for GSAP grouping, never as the sole hiding
mechanism. See [02 · No-JS fallback](#2-no-js-fallback-progressive-enhancement).

---

## 4. Final checklist when porting to a new Astro project

- [ ] `pnpm add gsap` (+ `swiper` if using the optional horizontal scroller appendix)
- [ ] `src/lib/gsap.ts` created and imported in each component's `<script>` block (not globally in the Layout `<head>`)
- [ ] `src/lib/animation-manager.ts` created **only if** you use the loader
- [ ] `src/lib/kinetic-marquee.ts` created **only if** you use marquees
- [ ] CSS fallback `.js-reveal` + `.no-js .js-reveal` rules added
- [ ] `no-js` → `js` class-swap inline script in the layout
- [ ] Every section's script: section-scoped root, `gsap.set(autoAlpha:1)` before `.from()`, `matchMedia` reduce branch
- [ ] All reveal elements carry `.js-reveal` (not just `opacity-0` alone)
- [ ] `ScrollTrigger.refresh()` after late-loading images/fonts
- [ ] Test in: reduced-motion emulation, no-JS (disable JS in DevTools), mobile, and a tall-viewport desktop

---

## Reference: the complete file map

| File | Mandatory? | Used for |
| :--- | :--- | :--- |
| `src/lib/gsap.ts` | **Yes** | Global config, ScrollTrigger registration |
| `src/lib/animation-manager.ts` | Loader only | Gated hero entrance orchestration |
| `src/lib/kinetic-marquee.ts` | Marquee only | Infinite marquee factory |
| `src/lib/animate-counters.ts` * | Counters only | Stat counter helper |
| `src/lib/reveal-helper.ts` * | Optional | DRY section-reveal helper |
| `src/styles/global.css` (fallback rules) | **Yes** | No-JS + initial hidden state |

> **\*** These are guide-provided helpers (optional, not part of the reference
> implementation). Create them only if you want the convenience shortcuts from
> [03](./03-section-reveal-pattern.md#reducing-the-copy-paste) and
> [04](./04-scroll-effects-marquee-and-counters.md#animated-stat-counters).

That's the whole system. Start at [README.md](./README.md) to revisit the
architecture, or [01-setup-and-mandatory-files.md](./01-setup-and-mandatory-files.md)
to begin porting.

---

## Appendix: Swiper horizontal scroller

See [06-optional-swiper-scroller.md](./06-optional-swiper-scroller.md) for the
optional companion: a free-mode horizontal scroller with branded bullets that
coexists with the section-reveal pattern.
