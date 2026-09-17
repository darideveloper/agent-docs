---
created: 2026-08-11
updated: 2026-08-11
tags:
  - gsap
  - scrolltrigger
  - animation
  - preloader
  - astro
  - documentation
type: resource
status: active
source: templates://astro/gsap-scrolltrigger/02-loader-and-entrance-orchestration.md
version: 2026-09-17+4cf710f

---

# 02 · Loader & Entrance Orchestration

How to build a **branded preloader** that coordinates the page entrance so the hero
animation never plays behind the loader. This is the most bespoke pattern in the
system — everything else (section reveals) is self-contained.

---

## The idea

```
Page loads → Loader overlay plays its reveal + progress bar
          → window "load" fires
          → Loader plays its EXIT animation (fade out + wipe)
          → Loader dispatches "loader:complete"
          → AnimationManager flushes its queue
          → Hero entrance timeline plays
```

The **hero entrance timeline is built `paused`** and handed to the
`animationManager`. If the loader is still showing, it sits in a queue. When the
loader finishes, the queue is played. If there's no loader at all, the manager plays
entrances immediately.

This file requires the `animation-manager.ts` helper introduced in
[01-setup-and-mandatory-files.md](./01-setup-and-mandatory-files.md#6-optional-helpers).

---

## 1. The Loader component — `src/components/organisms/Loader.astro`

Full, copy-paste implementation. Note the **3 hard-wired IDs** the rest of the
system relies on: `#loader`, `#loader-bar`, `#loader-wipe`, and the **event name
`loader:complete`**.

```astro
<div id="loader" class="fixed inset-0 z-[999] bg-background flex flex-col items-center justify-center overflow-hidden">
  <div class="relative flex flex-col items-center">
    <!-- Signature Mark -->
    <div class="mb-8 overflow-hidden px-2">
      <span id="loader-text" class="text-center display-lg text-primary tracking-tighter opacity-0 translate-y-full block">
        YOUR <span class="text-accent italic">BRAND</span>
      </span>
    </div>

    <!-- Progress Container -->
    <div class="w-64 h-px bg-surface/20 relative overflow-hidden">
      <div id="loader-bar" class="absolute inset-0 bg-accent origin-left scale-x-0"></div>
    </div>

    <div class="mt-4 overflow-hidden">
      <span id="loader-status" class="label-md text-secondary opacity-0 translate-y-full block">
        A MOTTO OR TAGLINE
      </span>
    </div>
  </div>

  <!-- Background Layer for Wipe Effect -->
  <div id="loader-wipe" class="absolute inset-0 bg-accent translate-y-full"></div>
</div>

<script>
  import { gsap } from "@/lib/gsap"

  function initLoader() {
    const loader = document.getElementById("loader")
    if (!loader) return

    // ── Reduced motion: show instantly, no animation ──
    const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    if (prefersReducedMotion) {
      gsap.set(["#loader-text", "#loader-status"], { autoAlpha: 1, y: 0 })
      gsap.set("#loader-bar", { scaleX: 1 })
      window.addEventListener("load", () => {
        loader.style.display = "none"
        document.dispatchEvent(new Event("loader:complete"))
      })
      return
    }

    const tl = gsap.timeline()

    // 1. Initial Reveal
    tl.to(["#loader-text", "#loader-status"], {
      autoAlpha: 1,
      y: 0,
      duration: 1,
      stagger: 0.2,
      ease: "power4.out"
    })
    .to("#loader-bar", {
      scaleX: 1,
      duration: 2.5,
      ease: "power1.inOut"
    }, "-=0.5")

    // 2. Exit Coordination
    window.addEventListener("load", () => {
      // Ensure the progress bar completes if it hasn't
      gsap.to("#loader-bar", {
        scaleX: 1,
        duration: 0.4,
        ease: "none",
        onComplete: () => {
          // Final Exit Timeline
          const exitTl = gsap.timeline({
            onComplete: () => {
              loader.style.display = "none"
              document.dispatchEvent(new Event("loader:complete"))
            }
          })

          exitTl.to("#loader-text, #loader-status, #loader-bar", {
            autoAlpha: 0,
            y: -20,
            duration: 0.6,
            ease: "power2.in"
          })
          .to("#loader-wipe", {
            y: "-100%",
            duration: 1,
            ease: "expo.inOut"
          }, "-=0.2")
          .to(loader, {
            autoAlpha: 0,
            duration: 0.5
          }, "-=0.8")
        }
      })
    })

    // Fallback timeout for safety (6 seconds)
    setTimeout(() => {
      if (loader.style.display !== "none") {
        window.dispatchEvent(new Event("load"))
      }
    }, 6000)
  }

  // Run on page load
  initLoader()
</script>

<style>
  #loader {
    pointer-events: none;
  }
</style>
```

> **Theme tokens:** the markup uses `bg-background`, `bg-surface/20`, `bg-accent`,
> `text-primary`, `text-secondary`, `text-accent`, `display-lg`, `label-md`. Replace
> these with your own theme classes or Tailwind utilities. The IDs `#loader`,
> `#loader-bar`, `#loader-wipe` and the event name `loader:complete` are hard-wired
> and must stay.

### What each piece does

| Piece | Role |
| :--- | :--- |
| `#loader` | The fixed overlay. `pointer-events: none` so it never blocks clicks while covering the screen |
| `prefers-reduced-motion` guard | Checks the media query at the top of `initLoader()` and **skips all animation** — text is shown instantly, the progress bar is full, and the loader hides immediately on `load` |
| Reveal timeline | Text/status slide up (staggered) while the progress bar scales `0 → 1` |
| `window "load"` handler | Waits for the real page load, then force-finishes the bar and runs the exit |
| `#loader-wipe` | A full-size panel that translates up (`y: "-100%"`) during the exit — the "wipe" reveal |
| `onComplete` | Hides the loader, then dispatches **`loader:complete`** — the handoff to the AnimationManager |
| 6s `setTimeout` | Safety net: force-dispatch `load` if the real load event never arrives |

---

## 2. Registering a hero entrance with the manager

The hero builds a **paused** timeline with `.from()` tweens (so it animates elements
from a hidden state to their natural layout), then hands it to the manager.

The critical detail is the **"unhide first"** step: `gsap.set(elements, { autoAlpha: 1 })`
must run *before* the `.from()` tweens are created, otherwise GSAP can't measure the
elements' natural position/opacity and the reveal is wrong.

```ts
import { gsap } from "@/lib/gsap"
import { animationManager } from "@/lib/animation-manager"

function initHeroAnimations() {
  const hero = document.querySelector(".js-hero-section")
  if (!hero) return

  // Ensure elements are visible to GSAP before defining .from() destination
  gsap.set(hero.querySelectorAll(".js-reveal"), { autoAlpha: 1 })

  // 1. Entrance Timeline (paused!)
  const tl = gsap.timeline({
    paused: true,
    defaults: {
      force3D: true,
      ease: "power4.out",
      duration: 1.2,
    }
  })

  tl.from(hero.querySelector(".js-hero-portrait"), {
    scale: 1.15,
    autoAlpha: 0,
    duration: 1.4,
  })
    .from(
      [
        hero.querySelector(".js-hero-headline"),
        hero.querySelector(".js-hero-subheadline"),
      ],
      {
        y: 40,
        autoAlpha: 0,
        stagger: 0.1,
        duration: 1.4,
      },
      "-=1", // overlaps the portrait animation
    )
    .from(
      hero.querySelector(".js-hero-eyebrow"),
      { y: 20, autoAlpha: 0 },
      "-=1",
    )
    .from(
      hero.querySelectorAll(".js-hero-badge"),
      { x: -20, autoAlpha: 0, stagger: 0.1 },
      "-=0.8",
    )
    .from(
      hero.querySelector(".js-hero-description"),
      { y: 30, autoAlpha: 0 },
      "-=0.6",
    )
    .from(
      hero.querySelector(".js-hero-cta"),
      { y: 20, autoAlpha: 0 },
      "-=0.4",
    )
    .from(
      hero.querySelectorAll(".js-hero-stat"),
      { y: 20, autoAlpha: 0, stagger: 0.1 },
      "-=0.4",
    )
    .from(
      hero.querySelector(".js-hero-scroll-wrapper"),
      { y: 10, autoAlpha: 0 },
      "-=0.2",
    )

  // Register with the orchestrator — plays after the loader finishes
  animationManager.registerEntrance(tl)
}

initHeroAnimations()
```

### The `-=` position parameter (how the choreography overlaps)

> Timeline positions: `-=1` overlaps 1s, `+=` delays, `<` aligns to previous start. Official GSAP docs for the rest.

Below is the overlap timing used in this hero entrance:

| Tween | Overlap | Effect |
| :--- | :--- | :--- |
| portrait | — | starts immediately |
| headline+subheadline | `-=1` | starts 1s before portrait ends |
| eyebrow | `-=1` | overlapping headline |
| badges | `-=0.8` | |
| description | `-=0.6` | |
| CTA | `-=0.4` | |
| stats | `-=0.4` | |
| scroll wrapper | `-=0.2` | |

---

## 2b. The `animation-manager.ts` helper (copy verbatim, loader projects only)

```ts
// src/lib/animation-manager.ts — gates entrances behind the loader.
// No loader in the DOM (#loader missing) → treated as already complete.
type Playable = { play: () => void; progress: (v: number) => void }

class AnimationManager {
  private queue: Playable[] = []
  private loaderDone = typeof document !== "undefined" && !document.getElementById("loader")

  constructor() {
    if (typeof document === "undefined") return
    document.addEventListener("loader:complete", () => {
      this.loaderDone = true
      this.flush()
    })
    // View Transitions reset the queue on route change (inert without <ClientRouter />).
    document.addEventListener("astro:after-swap", () => {
      this.queue = []
      this.loaderDone = !document.getElementById("loader")
    })
  }

  registerEntrance(item: Playable) {
    if (this.loaderDone) this.playEntrance(item)
    else this.queue.push(item)
  }

  private playEntrance(item: Playable) {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) item.progress(1)
    else item.play()
  }

  private flush() {
    this.queue.forEach((item) => this.playEntrance(item))
    this.queue = []
  }
}

export const animationManager = new AnimationManager()
```

## 3. The wiring in the layout

The loader must be present in the page for the orchestration to matter:

```astro
<!-- Layout.astro body -->
<body>
  <Loader />          <!-- from src/components/organisms/Loader.astro -->
  <Hero id="home" />  <!-- registers its entrance with animationManager -->
  <slot />
</body>
```

Order is not critical — the manager handles "loader already finished" vs "loader
still showing" either way.

---

## 4. What happens for reduced-motion users

The manager checks `prefers-reduced-motion` when it plays the queue:

- **Reduced motion:** `item.progress(1)` — the timeline jumps to its end state.
  Content is instantly visible, no movement.
- **No preference:** `item.play()` — normal animation.

The hero *also* gates its scroll-driven effects behind
`gsap.matchMedia()("(prefers-reduced-motion: no-preference)")` so parallax and
scrubbed fades don't run for reduced-motion users. More on that in
[05-accessibility-and-pitfalls.md](./05-accessibility-and-pitfalls.md).

---

## 5. Skipping the loader entirely

No loader in your project? Then you don't need the `animation-manager` at all.
The manager's constructor detects that `#loader` is missing and treats the loader
as "already complete," so `registerEntrance()` plays immediately — but it's dead
weight. Just drop it and call `tl.play()` yourself:

```ts
const tl = gsap.timeline({ paused: true })
// ...build tweens...
tl.play()
```

Next: the pattern you'll use on **every** section — [03-section-reveal-pattern.md](./03-section-reveal-pattern.md).
