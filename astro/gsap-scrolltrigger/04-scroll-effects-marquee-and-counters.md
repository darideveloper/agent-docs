---
created: 2026-08-11
tags:
  - gsap
  - scrolltrigger
  - animation
  - marquee
  - astro
  - documentation
type: resource
status: active
source: templates://astro/gsap-scrolltrigger/04-scroll-effects-marquee-and-counters.md
version: 2026-09-27+57b0fd3

---

# 04 · Scroll Effects, Kinetic Marquee & Counters

The three "extra" animation techniques: **scroll-linked effects** (parallax,
scrubbed fades), the **infinite kinetic marquee**, and **animated stat counters**.

---

## 1. Scroll-linked effects (parallax & scrubbed fades)

> Scrub inline: `scrub: true` (1:1 scroll-linked) or `scrub: 0.8` (0.8s lag); `start`/`end` define the range (e.g. `"top top"` → `"bottom top"`); `pin: true` pins the trigger. `ease: "none"` required for scrubbed motion.

These differ from section reveals because the animation is **driven by the scroll
position** — you scrub back and forth as you scroll, not one-shot play.

The two ingredients:

- `scrub: true` (or `scrub: 0.8`) — the animation progress is tied to scroll position
- `start` / `end` — define the scroll range the effect spans

Both examples are wrapped in `gsap.matchMedia()("(prefers-reduced-motion: no-preference)")`
so reduced-motion users get nothing.

### A. Parallax ambient glows

Two decorative blurred circles drift at **opposite** speeds for depth, scrubbed
smoothly with a 0.8s lag:

```ts
const mm = gsap.matchMedia()

mm.add("(prefers-reduced-motion: no-preference)", () => {
  // Parallax for ambient glows
  gsap.to(hero.querySelectorAll(".js-hero-glow"), {
    y: (i) => (i === 0 ? 80 : -80),
    x: (i) => (i === 0 ? 40 : -40),
    ease: "none",
    scrollTrigger: {
      trigger: hero,
      start: "top top",
      end: "bottom top",
      scrub: 0.8,
    },
  })
})
```

| Key | Meaning |
| :--- | :--- |
| `y: (i) => (i === 0 ? 80 : -80)` | Function-based value — element 0 drifts down 80px, element 1 up 80px |
| `start: "top top"` | Range begins when the hero's top hits the viewport top |
| `end: "bottom top"` | Range ends when the hero's bottom hits the viewport top |
| `scrub: 0.8` | Smooth scrubbing with 0.8s lag — feels weighty, not robotic |
| `ease: "none"` | Linear — required for scrubbed motion so progress maps 1:1 to scroll |

### B. Scrubbed fade-out of a scroll indicator

Fades and pushes the "Scroll" hint away as the user scrolls the hero out:

```ts
mm.add("(prefers-reduced-motion: no-preference)", () => {
  gsap.to(hero.querySelector(".js-hero-scroll"), {
    autoAlpha: 0,
    y: 30,
    ease: "power1.in",
    scrollTrigger: {
      trigger: hero,
      start: "top top",
      end: "20% top",
      scrub: true,
    },
  })
})
```

### Parallax cheat sheet

| Effect | Tween target | Range |
| :--- | :--- | :--- |
| Fade element out on scroll | `autoAlpha: 0` | `top top` → `20% top` |
| Move element slower than scroll | `y` with `scrub` | `top top` → `bottom top` |
| Pinned section (see below) | `scrollTrigger: { pin: true }` | `top top` → `bottom top` |

### Pinning (bonus — same API as regular ScrollTrigger)

```ts
gsap.to(".my-panel", {
  scrollTrigger: {
    trigger: ".my-panel",
    start: "top top",
    end: () => "+=" + window.innerHeight,
    pin: true,
  },
})
```

> Animate only `transform`/`opacity` (`x`, `y`, `scale`, `autoAlpha`, `rotation`) — GPU-composited, no layout thrash. Avoid `top`/`left`/`margin`.

Animate only `transform` properties (`y`, `x`, `scale`, `autoAlpha`) — avoid `top`/`left`/`margin`.

---

## 2. Kinetic marquee (infinite background text)

A full-bleed row of giant words that scrolls forever. Built on the
`initKineticMarquee` factory from
[01-setup-and-mandatory-files.md](./01-setup-and-mandatory-files.md#6-optional-helpers).

### The factory (recap)

```ts
export const initKineticMarquee = (container: HTMLElement) => {
  if ((container as any)._marqueeInit) return () => {}
  ;(container as any)._marqueeInit = true
  const wordsContainer = container.querySelector(".js-marquee-content") as HTMLElement
  if (!wordsContainer) return () => {}

  const ctx = gsap.context(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    // Duplicate content for a seamless loop
    const children = Array.from(wordsContainer.children)
    children.forEach((child) => wordsContainer.appendChild(child.cloneNode(true)))

    const totalWidth = wordsContainer.scrollWidth / 2

    gsap.to(wordsContainer, {
      x: -totalWidth,
      duration: 30,
      ease: "none",
      repeat: -1,
      modifiers: {
        x: (x) => `${parseFloat(x) % totalWidth}px`,
      },
    })
  }, container)

  return () => {
    ctx.revert()
    ;(container as any)._marqueeInit = false
  }
}
```

**How the seamless loop works:** content is duplicated once, so the row is exactly
2× the original width. GSAP tweens `x` from `0` to `-totalWidth` (one copy's width).
The `modifiers.x` wrapper keeps the value modulo `totalWidth`, so when it wraps
around the jump is invisible — the first copy's start matches the second copy's
end exactly.

### A. Standalone usage in a section

```astro
<div class="js-marquee">
  <div class="js-marquee-content whitespace-nowrap">
    <span>YOUR</span><span>KEYWORDS</span><span>HERE</span>
  </div>
</div>

<script>
  import { initKineticMarquee } from "@/lib/kinetic-marquee"

  const section = document.querySelector(".js-my-section")
  const marqueeContainer = section?.querySelector(".js-marquee") as HTMLElement
  if (marqueeContainer) initKineticMarquee(marqueeContainer)
</script>
```

### B. Full component: background marquee + foreground reveal (FeatureCTA)

The complete production pattern: the marquee fades in behind the content while the
headline/button reveal over it. Requires the `initKineticMarquee` factory.

```astro
<script>
  import { gsap, ScrollTrigger } from "@/lib/gsap"
  import { initKineticMarquee } from "@/lib/kinetic-marquee"

  gsap.registerPlugin(ScrollTrigger)

  function initFeatureCTAAnimations() {
    const instances = gsap.utils.toArray(".js-feature-cta") as HTMLElement[]

    instances.forEach((container) => {
      const reveals = container.querySelectorAll(".js-fcta-reveal")
      const background = container.querySelector(".js-marquee") as HTMLElement
      const label = container.querySelector(".js-fcta-label")
      const headline = container.querySelector(".js-fcta-headline")
      const button = container.querySelector(".js-fcta-button")

      // Initialize Marquee if present
      if (background) initKineticMarquee(background)

      const mm = gsap.matchMedia()

      mm.add("(prefers-reduced-motion: no-preference)", () => {
        gsap.set(reveals, { autoAlpha: 1 }) // unhide before .from()

        const tl = gsap.timeline({
          scrollTrigger: {
            trigger: container,
            start: "top 85%",
            toggleActions: "play none none none",
          },
        })

        if (background) {
          tl.to(background, {
            opacity: 0.05,        // marquee is a faint watermark behind content
            duration: 1.5,
            ease: "power2.out",
            startAt: { scale: 0.95 }, // gentle zoom-in as it fades
          })
        }

        if (label) tl.from(label, { y: 20, autoAlpha: 0, duration: 0.8, ease: "power2.out" }, background ? "-=1.2" : "0")
        if (headline) tl.from(headline, { y: 40, autoAlpha: 0, duration: 1.2, ease: "power4.out" }, "-=0.8")
        if (button) tl.from(button, { y: 20, autoAlpha: 0, duration: 1.0, ease: "power3.out" }, "-=0.6")
      })

      mm.add("(prefers-reduced-motion: reduce)", () => {
        gsap.to(reveals, {
          autoAlpha: 1,
          duration: 0.8,
          stagger: 0.1,
          scrollTrigger: {
            trigger: container,
            start: "top 85%",
            toggleActions: "play none none none",
          },
        })
      })
    })
  }

  initFeatureCTAAnimations()
</script>
```

**Markup requirements** for the above:

```astro
<div class="js-feature-cta relative">
  <div class="js-marquee absolute opacity-0 pointer-events-none">
    <div class="js-marquee-content flex gap-4 whitespace-nowrap">
      <!-- big words here -->
    </div>
  </div>
  <p class="js-fcta-label js-fcta-reveal js-reveal">Label</p>
  <h2 class="js-fcta-headline js-fcta-reveal js-reveal">Headline</h2>
  <a class="js-fcta-button js-fcta-reveal js-reveal">CTA</a>
</div>
```

Notes:
- The marquee element carries `opacity-0` inline — the timeline's `gsap.to(background, { opacity: 0.05 })` targets it directly (the `startAt` prevents a flash).
- The foreground elements use the standard `.js-fcta-reveal` + `.js-reveal` pattern (`.js-fcta-reveal` for GSAP grouping, `.js-reveal` for the hidden state + no-JS override).
- `gsap.utils.toArray(".js-feature-cta")` supports **multiple instances** of the component on one page.
- **Accessibility:** add `aria-hidden="true"` to the marquee container — it's purely decorative background noise.

---

## 3. Animated stat counters

Counts up from `0` to a target number with the suffix preserved (`100+`, `400+`).
Data is read from a `data-value` attribute, so markup stays declarative.

### The helper (copy-paste)

> **⚠️ Convenience-only, not the reference implementation.** `animateCounters` is
> optional sugar for stat counters. The reference implementation duplicates the
> per-component tween pattern (see `03-section-reveal-pattern.md`) by design; this
> helper only saves copy-paste when you have many counters.

```ts
// src/lib/animate-counters.ts
import { gsap } from "@/lib/gsap"

/**
 * Animates every `.js-stat-value` element inside `container`.
 * Reads the target number + suffix from `data-value` (e.g. "100+").
 * If `tl` is provided, appends the counter tweens to that timeline at the
 * current end position; otherwise plays them immediately.
 */
export function animateCounters(container: Element, tl?: gsap.core.Timeline) {
  const counters = container.querySelectorAll(".js-stat-value")
  counters.forEach(counter => {
    const targetValueAttr = counter.getAttribute("data-value") || ""
    const numericMatch = targetValueAttr.match(/(\d+)/)
    if (!numericMatch) return

    const targetValue = parseInt(numericMatch[0], 10)
    const suffix = targetValueAttr.replace(numericMatch[0], "")
    const obj = { value: 0 }

    const tweenParams = {
      value: targetValue,
      duration: 1.2,
      ease: "power4.out",
      onUpdate: () => {
        counter.textContent = Math.round(obj.value) + suffix
      },
    }

    if (tl) {
      tl.to(obj, tweenParams, "<")
    } else {
      gsap.to(obj, tweenParams)
    }
  })
}
```

### Markup

```astro
<div class="js-hero-stat">
  <span
    class="js-stat-value"
    data-value="100+"
  >100+</span>
  <span>Episodios</span>
</div>
```

### Usage — standalone

```ts
animateCounters(container)
```

### Usage — synced into an entrance timeline

Appending at position `"<"` means "start right after whatever is currently last"
— so the counters tick up exactly as the stats slide in:

```ts
import { animationManager } from "@/lib/animation-manager"

const tl = gsap.timeline({ paused: true })
// ...hero reveal tweens...

// Zero the counters immediately so they don't show the target before animating
container.querySelectorAll(".js-stat-value").forEach(counter => {
  const attr = counter.getAttribute("data-value") || ""
  const num = attr.match(/(\d+)/)
  if (num) counter.textContent = "0" + attr.replace(num[0], "")
})

animateCounters(container, tl) // appends at "<"

animationManager.registerEntrance(tl)
```

> The initial zero-out is important: without it, the counters flash the final value
> for one frame before the tween starts.

---

Next: [05-accessibility-and-pitfalls.md](./05-accessibility-and-pitfalls.md).


> V1 lifecycle ([Transitions](../astro-client-side-page-transitions.md) §5): section-presence guard + immediate init() + astro:page-load re-init + astro:after-swap cleanup + ScrollTrigger.refresh(). Do not call init once without listeners when <ClientRouter /> is ON.
