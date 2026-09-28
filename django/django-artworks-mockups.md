---
created: 2026-08-29
tags:
  - django
  - artworks
  - mockups
  - image-generation
  - pil
  - design
  - exploration
type: design
status: active
source: templates://django/django-artworks-mockups.md
version: 2026-09-27+57b0fd3

---

# Artwork Room Mockups — Design Investigation (Example, NOT core template)

> Exploration note — not part of the reusable template. Requires `numpy` in addition to `pillow` if ever adopted; Astro landing references are out of Django scope.

Auto-generated mockup images that place each artwork inside a realistic interior
(kitchen, dining room, etc.), mounted on a wall at physically-proportional size,
with a subtle 3D canvas/frame treatment.

This doc captures the full exploration: the problem, the approaches considered,
the chosen architecture, the realism strategy, and the open decisions.

## Goals

For each artwork, produce a second image that shows:

1. A realistic domestic interior scene (kitchen, dining room, living room…).
2. The artwork's **primary image** mounted on one of the walls.
3. The artwork at **physically-proportional size** (a 50×70 cm piece reads as 50×70 cm).
4. A convincing **canvas/frame** treatment (3D-looking, not a specific branded frame).

Constraints that shaped the decision:

| Constraint | Value |
|---|---|
| Output format | **Static files** — shareable (download / og:image / WhatsApp) |
| Backend control | **Django dashboard is editable** (fields + endpoints possible) |
| Realism bar | **Photo-real, "fool a viewer"** |
| Dimensions source | Only the free-text `dimensions` string today |

## Chosen architecture (verdict)

The feature lives in the **Django backend** (PIL compositing), with the realism
gap closed by a **layered strategy** that keeps the artwork pixel-exact. The
Astro landing repo barely changes.

```
┌─────────────────────────── D J A N G O   B A C K E N D ───────────────────────────┐
│                                                                                    │
│  Artwork saved ──► 1. width_cm/height_cm (new structured fields, backfilled)        │
│                        └─ from free-text `dimensions` parser                        │
│                  2. Load artwork primary image (already in media)                   │
│                  3. For each configured room:                                       │
│                       ├─ room bg = AI-generated photo (curated ONCE, static asset)  │
│                       ├─ homography: wall quad (px) ↔ real cm   ← proportionality  │
│                       ├─ PIL PERSPECTIVE warp of artwork (exact, aspect preserved)  │
│                       ├─ procedural canvas frame (wood/black bevel)                 │
│                       ├─ contact shadow (blurred mask under frame)                  │
│                       ├─ per-room lighting overlay (numpy multiply)                 │
│                       ├─ [opt] margin-inpaint (AI blends frame/wall = realism 5%)   │
│                       └─ save mockup-<room>.webp (cached in media)                  │
│                  4. API exposes  artwork.mockups: [{room, image_url}]               │
│                                                                                    │
│  QC gate: SSIM(source_artwork, rendered_artwork_region) > θ  → retry, else reject  │
└────────────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────── A S T R O   L A N D I N G ─────────────────────────────┐
│  ArtworkDetailView gains `mockups[]`   │   Artwork page: room switcher tabs        │
│  og:image can point at primary mockup  │   ("Cocina" / "Comedor" swap the image)   │
│  (no math, no deps, no canvas)         │                                          │
└────────────────────────────────────────────────────────────────────────────────────┘
```

### Why this shape

- Source images already live in the backend's media storage → no CORS problem, no
  cross-domain fetching, natural caching.
- Static `.webp` files work for og:image, WhatsApp, gallery cards, downloads.
- The artwork is **composited exactly** (never regenerated) — fidelity is
  structurally guaranteed. AI is reserved for *rooms* (one-time cost) and
  *blending* (optional).
- The landing repo stays thin — it just renders URLs returned by the API.

## Realism strategy (the "fool a viewer" ladder)

Photo-realism is a ladder; each rung is independently optional:

| Rung | Technique | Realism gain | Cost |
|---|---|---|---|
| 1 | AI-generated room backgrounds (empty walls, soft light, no people) | huge | one-time |
| 2 | Per-room **lighting overlay** (soft exposure/color map over the wall quad, multiplied onto the warped artwork) | high — kills "pasted on" flatness | zero runtime |
| 3 | **Contact shadow** + subtle frame bevel/glare | high | zero |
| 4 | **Margin-inpaint** — composite artwork exactly, then AI-inpaint *only a ~20px ring around the frame* to blend lighting/edges | last 5% | per-image $ |

Key detail for rung 4: the mask covers only the artwork's frame edges, **never
the artwork itself** — the model hallucinates shadows/bloom/wall-grain while the
artwork stays 100% authentic. An automated QC gate (SSIM diff between the source
artwork and the rendered artwork region; retry/reject below threshold) makes
drift structurally impossible to ship silently.

Recommendation: rungs 1–3 are the default. Rung 4 is a per-room flag behind a
cost budget.

## Proportionality (core math)

The requirement "render in the image in a proportional size" needs **calibrated
room data**, not eyeballing.

### Room calibration record

Each room background is a static photo + a calibration record:

```json
{
  "src": "/rooms/cocina-01.webp",
  "label": { "es": "Cocina", "en": "Kitchen" },
  "wall": {
    "quad":   [[520,120],[1820,90],[1880,910],[560,980]],
    "widthCm":  300,
    "heightCm": 220
  }
}
```

- `quad`: the 4 corners (px) of the usable wall area.
- `widthCm` / `heightCm`: the real-world width/height of that wall area.

### Placement algorithm

1. `ppm = wallQuadPixelWidth / wallWidthCm` (pixels per meter).
2. Artwork display size = `width_cm × ppm` by `height_cm × ppm` (aspect preserved).
3. Clamp: if the display size exceeds ~90% of the wall quad, scale down to fit
   (huge pieces on small walls get clamped — realistic anyway).
4. Hang the artwork centered on the wall at **eye level ≈ 145–150 cm from the
   floor** (per-room `eyeLevelCm`, or derived from quad proportions).
5. Compute the **homography** (8-coefficient, ~40 lines) mapping a unit rectangle
   onto the 4 target corners; apply via `PIL.Image.transform(size, PERSPECTIVE, coeffs)`.

## Approaches compared (why the others lost)

| | A. CSS 3D (client React) | B. Build-time (Astro) | C. Django/PIL (chosen) | D. AI generation |
|---|---|---|---|---|
| Where | client React island | Astro build script | Django backend | any |
| Output | interactive render | static files | static files | static files |
| og:image/shareable | ✗ | ✓ | ✓ | ✓ |
| Artwork fidelity | exact | exact | exact | drifts |
| Realism ceiling | composite ("nice mockup") | composite | composite (+ AI rungs) | photo-real |
| New deps/infra | **none** | 1 (canvas) | Pillow + numpy | $ per image + latency |
| Refresh cadence | instant | on deploy | on artwork save | on demand |
| Works from this repo | ✓ | ✓ | ✗ (other repo) | ✓ |

Notes:

- **A. CSS 3D** — zero-dependency, impressive interactive mockup via `matrix3d`
  homography, but produces no static file and needs CORS for canvas export.
  Rejected here because static shareable files are required. The calibration
  format remains reusable if a client renderer is ever wanted.
- **B. Astro build-time** — `sharp` has no perspective transform; would need
  `@napi-rs/canvas` or ImageMagick `-distort Perspective`. Mockups go stale until
  the next deploy when the dashboard adds art. Viable fallback if backend edits
  were impossible.
- **D. AI generation** — fights the fidelity requirement (drift, garbled text,
  cost, latency, non-determinism). Only sensible use: AI-generated *backgrounds*
  (rung 1) and *margin blending* (rung 4), never the artwork itself.

## Blocking prerequisites

1. **Structured dimensions.** `Artwork.dimensions` is a free-text string
   (`src/lib/api/types.ts:117`). Add nullable `width_cm`/`height_cm` to the
   Django model + admin + serializer; backfill via a one-off parser over existing
   rows. Missing values fall back to a default (e.g. 60×80 cm).
2. **Room calibration format** — the `{quad, widthCm, heightCm, eyeLevelCm}`
   contract above (shared, reusable by any future client renderer).
3. **AI provider + key** for rooms (and optionally rung 4). Replicate / OpenAI /
   Stability — pick + budget number.
4. **Background task infra** — sync-on-save is fine for a handful of artworks; at
   N×M generations (~1–3 s/image) use Celery or the provider's async jobs.

## Landing (Astro) side — expected change

- `src/lib/api/types.ts` — `Artwork` / `ArtworkImage` gains `mockups`:
  `[{ room: string; image: string }]` (mirrors backend serializer).
- `src/data/api.ts` — `toArtworkDetailView` passes `mockups` through.
- `src/components/molecules/ArtworkImageViewer.astro` (or a small React island) —
  room-switcher tabs ("Cocina" / "Comedor") that swap the shown image to the
  corresponding mockup URL. No math, no canvas, no new dependencies.
- `og:image` may point at the primary mockup.
- Per AGENTS.md: keep `docs/component-dependencies.md` in sync.

## Open decisions (resolve before formalizing a proposal)

- **Scale:** how many artworks today, how fast does the catalog grow? (Cost
  ceiling + sync-vs-async + build strategy.)
- **Room set:** which rooms; one mockup per artwork or all rooms? (Storage ×3–5.)
- **Dimension formats:** what does `dimensions` actually look like in the DB
  (`"50 x 70 cm"`, `"50x70"`, mixed)? (Designs the parser/backfill.)
- **AI provider preference**, or compositing-only for now with AI rooms later.

## Suggested OpenSpec change shape

- Capability: `artwork-mockups`.
- Specs:
  - Backend: structured dimensions, mockup generation pipeline, API exposure.
  - Frontend: room switcher UI, mockup URLs in detail view, og:image wiring.
- Design: homography math, calibration format, realism rung selection, QC gate.
- Tasks: structured dimensions + backfill → room asset production → generation
  pipeline (rungs 1–3) → optional rung 4 → API + serializer → frontend switcher.