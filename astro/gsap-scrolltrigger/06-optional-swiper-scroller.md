---
created: 2026-08-11
updated: 2026-08-11
tags:
  - gsap
  - scrolltrigger
  - swiper
  - animation
  - astro
  - documentation
type: resource
status: active
source: templates://astro/gsap-scrolltrigger/06-optional-swiper-scroller.md
version: 2026-09-17+unreleased

---

# 06 · Optional: Swiper Horizontal Scroller

A free-mode horizontal scroller that coexists with the section-reveal pattern.
Powered by **Swiper 12**, not GSAP. Used for horizontal image galleries, platform
cards, or any horizontal content strip — scrolled with mouse drag, mousewheel, and
optional pagination bullets.

**Prerequisite:** `pnpm add swiper` (Swiper 12+, used in the reference
implementation).

---

## The pattern: Swiper init + GSAP section reveal

Swiper initializes immediately (no gate). The GSAP section-reveal timeline triggers
on scroll and covers the header, the swiper container, and any cards below — just
like any other section.

```astro
---
// frontmatter: import Swiper CSS
import "swiper/css"
import "swiper/css/pagination"
import "swiper/css/free-mode"
---

<section class="js-my-section container py-24">
  <!-- Header (revealed by the GSAP timeline) -->
  <div class="mb-24 js-my-header js-my-reveal js-reveal">
    <h2>Section Headline</h2>
    <p>Section description.</p>
  </div>

  <!-- Swiper Gallery (also revealed by the timeline) -->
  <div class="mb-24 js-my-gallery js-my-reveal js-reveal">
    <div class="swiper my-swiper">
      <div class="swiper-wrapper cursor-grab active:cursor-grabbing select-none">
        <div class="swiper-slide w-auto! js-my-slide">
          <!-- slide content (image, card, etc.) -->
        </div>
        <div class="swiper-slide w-auto! js-my-slide">
          <!-- ... -->
        </div>
      </div>

      <!-- Pagination bullets -->
      <div class="swiper-pagination static! mt-8 flex justify-center gap-3"></div>
    </div>
  </div>

  <!-- Cards / content below the swiper -->
  <div class="grid grid-cols-1 @3xl:grid-cols-3 gap-8">
    <div class="js-my-card js-my-reveal js-reveal">Card 1</div>
    <div class="js-my-card js-my-reveal js-reveal">Card 2</div>
    <div class="js-my-card js-my-reveal js-reveal">Card 3</div>
  </div>
</section>

<script>
  import Swiper from "swiper"
  import { FreeMode, Pagination, Mousewheel } from "swiper/modules"
  import { gsap, ScrollTrigger } from "@/lib/gsap"

  gsap.registerPlugin(ScrollTrigger)

  function initSwiper() {
    const swiperElement = document.querySelector(".my-swiper")
    if (!swiperElement) return

    new Swiper(swiperElement as HTMLElement, {
      modules: [FreeMode, Pagination, Mousewheel],
      slidesPerView: "auto",
      spaceBetween: 24,
      freeMode: {
        enabled: true,
        momentumBounce: false,
      },
      mousewheel: {
        forceToAxis: true,
      },
      pagination: {
        el: ".swiper-pagination",
        clickable: true,
        renderBullet: function (_index, className) {
          return `<span class="${className} custom-bullet"></span>`
        },
      },
    })
  }

  function initAnimations() {
    const section = document.querySelector(".js-my-section")
    if (!section) return

    const mm = gsap.matchMedia()

    mm.add("(prefers-reduced-motion: no-preference)", () => {
      gsap.set(section.querySelectorAll(".js-my-reveal"), { autoAlpha: 1, force3D: true })

      const tl = gsap.timeline({
        scrollTrigger: {
          trigger: section,
          start: "top 75%",
          toggleActions: "play none none none",
        },
      })

      tl.from(".js-my-header", { autoAlpha: 0, y: 40, duration: 1.2, delay: 0.3, ease: "power4.out" })
        .from(".js-my-slide", { autoAlpha: 0, scale: 0.95, duration: 1.0, stagger: 0.1, ease: "power3.out" }, "-=0.4")
        .from(".js-my-card", { autoAlpha: 0, y: 30, duration: 1.0, stagger: 0.15, ease: "power2.out" }, "-=0.5")
    })

    mm.add("(prefers-reduced-motion: reduce)", () => {
      gsap.set(section.querySelectorAll(".js-my-reveal"), { autoAlpha: 0 })

      ScrollTrigger.create({
        trigger: section,
        start: "top 75%",
        onEnter: () => {
          gsap.to(section.querySelectorAll(".js-my-reveal"), { autoAlpha: 1, duration: 0.8, stagger: 0.1 })
        },
      })
    })
  }

  initSwiper()
  initAnimations()
</script>

<style is:global>
  .my-swiper .swiper-pagination {
    display: flex;
    justify-content: center;
    gap: 0.75rem;
  }

  .my-swiper .custom-bullet {
    width: 2rem;
    height: 0.25rem;
    border-radius: 9999px;
    background: var(--color-brand-outline-variant, #4d4355);
    opacity: 0.3;
    transition: all 0.3s ease;
    cursor: pointer;
    display: block;
  }

  .my-swiper .swiper-pagination-bullet-active {
    background: var(--color-brand-primary, #9b30ff);
    opacity: 1;
  }
</style>
```

---

## Config explained

| Option | Value | Why |
| :--- | :--- | :--- |
| `slidesPerView: "auto"` | Each slide takes its natural width | Free-form horizontal gallery, not forced grid |
| `spaceBetween: 24` | 24px gap between slides | Visual breathing room |
| `freeMode.enabled: true` | Slides move freely, no snap-to-slide | Smooth, native-feel scroll |
| `freeMode.momentumBounce: false` | No bouncing at edges | Avoids rubber-band feedback loop with mousewheel |
| `mousewheel.forceToAxis: true` | Turns diagonal mousewheel into pure X-axis | Prevents jerky vertical movement during horizontal scroll |
| `pagination.clickable: true` | Bullets are clickable | Users can jump to sections |

The `renderBullet` function adds a `custom-bullet` class so you can override the
default Swiper pill styling with branded pills (the CSS above: 32px × 4px rounded
bars, accented color on active).

---

## How it coexists with GSAP

1. **Swiper inits immediately** — no animation gate, no conflict. It's just a DOM
   wrapper that adds scroll tracking to the container.
2. **The GSAP timeline reveals the swiper container** (`.js-my-gallery`) and each
   slide (`.js-my-slide`) inside it. Swiper already has the slides laid out; the
   `.from()` tween just fades/zooms them in.
3. **Reduced motion:** the fallback fades everything in; Swiper itself still works
   (the scroll interaction is user-driven, not auto-animated).
4. **Multiple instance support:** prefix your swiper class (`.my-swiper`) so you can
   have more than one swiper on a page.
5. **`w-auto!` on slides:** in Tailwind v4 this forces `width: auto !important`,
   preventing Swiper from smashing slides to 100% width.
6. **`static!` on pagination:** overrides Swiper's absolute positioning so the bullets
   flow naturally below the gallery in the document flow.

---

## When NOT to use this

- You only have 2–3 horizontal items → a CSS flex row with `overflow-x: auto` is
  lighter.
- You want scroll-snapping (no free-form drift) → configure `spaceBetween: 0` and
  `slidesPerView: 1` for a full carousel, or use CSS `scroll-snap-type: x mandatory`.
- You don't have any Swiper dependency budget → this is the only non-GSAP dependency
  in the animation system; skip it and use CSS scroll.

---

Back to [README.md](./README.md).
