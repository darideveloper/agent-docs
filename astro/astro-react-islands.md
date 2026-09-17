---
created: 2026-07-26
updated: 2026-08-05
tags:
  - astro
  - react
  - tailwind
  - setup
  - documentation
type: resource
status: active
source: templates://astro/astro-react-islands.md
version: 2026-09-17+unreleased

---

# Astro + React Islands + Tailwind CSS

> **Opt-in layer.** Precondition: [Base config](./astro-base-config.md). Skip if the site is static-only (Astro components suffice).

Astro's island architecture lets you use React for interactive widgets while keeping the rest of the page as static HTML. Tailwind CSS v4 handles all styling via the Vite plugin.

> **⚠️ READER / AI AGENT.** React islands here are the **vanilla self-bound atoms** of this project
> (e.g. `Input` binds the Zustand store directly). If you scaffold a new project that uses a
> **UI library** (shadcn, Radix), the island example would instead hydrate a `Validated*` wrapper
> atom. The two approaches are mutually exclusive — pick one per project, and ask the user if unsure
> (see [[astro-atomic-components]]).

## How It Works

Astro renders the full page on the server. React components opt in with `client:*` directives — they ship zero JS until the browser hydrates them.

```
┌──────────────────────────────────────────────┐
│              Astro Page (static)              │
│  ┌────────────────────────────────────────┐   │
│  │   React island <client:load>           │   │
│  │   ┌────────┐ ┌────────┐ ┌────────┐    │   │
│  │   │ Form   │ │ Button │ │ Widget │    │   │
│  │   │ input  │ │        │ │        │    │   │
│  │   └────────┘ └────────┘ └────────┘    │   │
│  └────────────────────────────────────────┘   │
│  Static content (headings, text, layout)      │
└──────────────────────────────────────────────┘
```

## 1. Dependencies

Versions below are examples — pin whatever is current when you set up a project:

```json
{
  "dependencies": {
    "@astrojs/react": "^6",
    "@tailwindcss/vite": "^4",
    "react": "^19",
    "react-dom": "^19",
    "tailwindcss": "^4",
    "tw-animate-css": "^1"
  },
  "devDependencies": {
    "@types/react": "^19",
    "@types/react-dom": "^19"
  }
}
```

## 2. Astro Config

```js
// astro.config.mjs
import { defineConfig } from 'astro/config'
import tailwindcss from '@tailwindcss/vite'
import react from '@astrojs/react'

export default defineConfig({
  vite: {
    plugins: [tailwindcss()]
  },
  integrations: [react()]
})
```

## 3. Tailwind Global CSS

```css
/* src/styles/global.css */
@import "tailwindcss";
@import "tw-animate-css";

@theme inline {
  --font-sans: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  --color-brand-500: oklch(0.62 0.18 20);
  /* ... custom theme tokens ... */
}
```

Import it in your layout:

```astro
---
import '@/styles/global.css'
---
```

## 4. React Island Directives

| Directive | When to use |
|---|---|
| `client:load` | Immediately on page load. Use for visible interactive elements (forms, buttons, inputs). |
| `client:idle` | After the browser is idle. Use for non-critical interactivity. |
| `client:visible` | When the element scrolls into viewport. Use for below-the-fold widgets. |
| `client:media` | Only on certain screen sizes. |
| `client:only` | Skip SSR entirely. Use when server rendering is impossible (browser-only APIs). |

**Rule of thumb:** Use `client:load` for form inputs and `client:visible` for everything else.

## 5. Astro Page Using React Islands

```astro
---
// pages/index.astro — static content + React islands
import Layout from '@/layouts/Layout.astro'
import { Input } from '@/components/atoms/Input'

const title = "Welcome"
---
<Layout>
  <main>
    <h1>{title}</h1>                      <!-- Static HTML -->
    <p>Fill in your details below.</p>     <!-- Static HTML -->

    <Input                             <!-- React island -->
      field="user_name"
      label="Your name"
      placeholder="e.g. Sarah"
      client:load
    />
  </main>
</Layout>
```

Key point: the `<h1>` and `<p>` are pure HTML. Only the `Input` ships React JS. This keeps bundles tiny for content-heavy pages.

## 6. New Project Setup

```bash
# Create Astro project
pnpm create astro@latest my-project -- --template basics

# Install React + Tailwind
pnpm add @astrojs/react @tailwindcss/vite react react-dom tailwindcss tw-animate-css
pnpm add -D @types/react @types/react-dom

# Install shadcn (optional, for UI primitives)
pnpm add shadcn@latest
pnpx shadcn init
```

Then configure `astro.config.mjs` as shown in section 2, add `global.css` as shown in section 3, and create your `tsconfig.json` with path aliases (canonical alias + merged config: see [astro-base-config](./astro-base-config.md) §1–§2):

```json
{
  "extends": "astro/tsconfigs/strict",
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"]
    },
    "jsx": "react-jsx",
    "jsxImportSource": "react"
  }
}
```

## 7. React Component Conventions

- `export function ComponentName(...)` — never arrow functions or `React.FC`
- `import * as React from "react"` — namespace import
- No semicolons
- Double quotes for all string literals
- No `"use client"` directive (Astro convention, not Next.js)
- Always use `@/` path aliases for project imports — including same-directory imports

## 8. The Slot Pattern (Astro + React Together)

React components cannot import `.astro` files. To embed Astro components inside React, use the slot pattern:

**React component** accepts `children` and/or named slots:
```tsx
export function Card({ children, footer }: { children: React.ReactNode; footer?: React.ReactNode }) {
  const [open, setOpen] = React.useState(false)
  return (
    <div>
      <button onClick={() => setOpen(!open)}>Toggle</button>
      {open && <div>{children}</div>}
      {footer && <div>{footer}</div>}
    </div>
  )
}
```

**Astro page** passes static Astro components as children:
```astro
<Card client:load>
  <p>This text is static HTML passed to React.</p>
  <Button slot="footer" text="Click me" />  <!-- Astro component -->
</Card>
```

React treats the Astro components as pre-rendered HTML — no extra JS cost.

## 9. Key Constraints

- React islands hydrate independently — they don't share React context across islands
- For cross-island state, use Zustand (see [[astro-zustand-zod]])
- Astro renders all React islands on the server too (SSR), except `client:only`
- Keep each island focused on one interactive unit — don't wrap entire pages in React
