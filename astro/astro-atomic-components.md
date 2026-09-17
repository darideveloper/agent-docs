---
created: 2026-07-26
updated: 2026-08-05
tags:
  - astro
  - react
  - architecture
  - components
  - atomic-design
  - documentation
type: resource
status: active
source: templates://astro/astro-atomic-components.md
version: 2026-09-17+unreleased

---

# Atomic Component Hierarchy

Organise components in a 4-tier atomic hierarchy. Each tier has strict import rules that prevent circular dependencies and keep the architecture predictable.

The hierarchy works whether you use **vanilla components** (plain Astro/React + Tailwind) or a **UI library** (shadcn, Radix, etc.).

> ## ⚠️ AI AGENT / READER — READ THIS FIRST (two mutually exclusive approaches)
>
> This document describes **TWO different, mutually exclusive ways** to build atoms.
> You MUST select **exactly one** for a project and use it consistently. Do **not** mix
> them, and do **not** treat one as the default for the other's case.
>
> 1. **Vanilla atoms (self-bound)** — hand-written components with Tailwind that bind the
>    Zustand store directly (see `src/components/atoms/Input.tsx`). No `ui/` dir, no wrapper tier.
> 2. **UI-library atoms (wrapper tier)** — generated primitives in `ui/` (shadcn, Radix) that
>    must not be edited, wrapped by presentation re-exports + stateful `Validated*` atoms.
>
> **Decision rule:**
> - If the project **uses a UI library that installs generated components** (`ui/` present) → use **approach 2**.
> - If the project is **vanilla only** (hand-written Tailwind atoms, no `ui/`) → use **approach 1**.
>
> **If you are an AI agent setting up a new project and it is NOT obvious which applies,
> STOP and ask the user before choosing.** Guessing wrong produces duplicated components
> (`Input` + `ValidatedInput`) and an architecture that contradicts this doc.
>
> **Applying to your project:** Determine whether your project is vanilla-only
> (hand-written Tailwind atoms, no `ui/`) or uses a UI library (`ui/` dir present)
> before reading further. This document covers both approaches — pick one and follow
> it consistently. Do not guess. If you are an AI agent setting up a new project and
> it's not obvious which applies, stop and ask the user before choosing.

## The Hierarchy

```
src/components/
  ui/          (optional) Raw UI library primitives — only present when using shadcn, Radix, etc.
  atoms/       Smallest standalone components — either self-contained vanilla or wrappers around ui/
  molecules/   Combinations of atoms
  organisms/   Complex sections (maps to screen regions)
```

**Without UI library (vanilla only):**

```
┌──────────────────────────────────────────────────┐
│                    Organisms                       │
│  ┌────────────────────────────────────────────┐  │
│  │              Molecules                      │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐   │  │
│  │  │  Atom    │ │  Atom    │ │  Atom    │   │  │
│  │  │(vanilla) │ │(vanilla) │ │(vanilla) │   │  │
│  │  └──────────┘ └──────────┘ └──────────┘   │  │
│  │   All atoms = self-contained components    │  │
│  └────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
```

**With UI library (e.g. shadcn):**

```
┌──────────────────────────────────────────────────┐
│                    Organisms                       │
│  ┌────────────────────────────────────────────┐  │
│  │              Molecules                      │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐   │  │
│  │  │  Atom    │ │  Atom    │ │  Atom    │   │  │
│  │  │(stateful)│ │(wrapper) │ │(stateful)│   │  │
│  │  └────┬─────┘ └────┬─────┘ └────┬─────┘   │  │
│  │       │            │            │          │  │
│  │       └────────────┼────────────┘          │  │
│  │               ui/ (shadcn)                  │  │
│  └────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
```

## Import Rules

**Vanilla only (no `ui/`):**

| Tier | Can import from |
|---|---|
| `atoms/*` | `atoms/*`, `store/*`, `lib/*` |
| `molecules/*` | `atoms/*`, `store/*`, `lib/*` |
| `organisms/*` | `molecules/*`, `atoms/*`, `store/*`, `lib/*` |

Atoms are self-contained — they import from store/lib directly and build their own markup with Tailwind. Vanilla atoms MAY also import sibling atoms; imports between atoms must stay acyclic.

**With UI library (`ui/` present):**

| Tier | Can import from |
|---|---|
| `ui/*` | Nothing from `components/` (raw primitives only) |
| `atoms/*` | `ui/*`, `store/*`, `lib/*` |
| `molecules/*` | `atoms/*`, `store/*`, `lib/*` |
| `organisms/*` | `molecules/*`, `atoms/*`, `store/*`, `lib/*` |

**Golden rule:** `atoms/*` is the only tier that imports from `ui/*`. Molecules and organisms import from atoms, never from ui.

## 1. `ui/` — Raw UI Library Primitives (Optional)

Only exists when using a third-party component library. Never import from `ui/` outside of `atoms/`.

### shadcn

```bash
pnpx shadcn init
pnpx shadcn add button checkbox input label radio-group select textarea
```

Generated files live in `src/components/ui/`. Do not edit directly — reinstall from shadcn if you need updates.

Contains: `button.tsx`, `checkbox.tsx`, `input.tsx`, `label.tsx`, `radio-group.tsx`, `select.tsx`, `textarea.tsx`.

### Other libraries

Same pattern — put their re-exported/adapted primitives in `ui/`:
- Radix UI primitives
- Headless UI
- Ark UI
- Custom primitive library

## 2. `atoms/` — Two Approaches

> **⚠️ PICK ONE.** The two approaches below are mutually exclusive. Choose based on the
> decision rule at the top of this doc (UI library installed → wrapper tier; vanilla only →
> self-bound). When in doubt, ask the user. Never scaffold both.

### Vanilla Atoms (no UI library) — self-bound by default

Self-contained components that use Tailwind directly and manage their own Zustand data. No wrapper layer needed — the atom IS the primitive and binds the store itself. The store hook is injectable via props so a consumer can point the atom at whichever store it needs.

```tsx
// src/components/atoms/Input.tsx (vanilla, store-bound)
import * as React from "react"
import { cn } from "@/lib/utils"
import { useField as defaultUseField } from "@/store/useField"

interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  field: string
  useField?: (field: string) => {
    value: unknown
    error?: string
    setValue: (v: unknown) => void
    mounted: boolean
  }
  label?: string
}

export function Input({ field, useField = defaultUseField, label, className, ...props }: InputProps) {
  const { value, error, setValue, mounted } = useField(field)

  return (
    <div className="flex flex-col gap-2 p-2">
      {label && (
        <label className={cn("text-sm font-medium", error ? "text-red-500" : "text-foreground")}>
          {label}
        </label>
      )}
      <input
        className={cn(
          "h-8 w-full rounded-2xl border border-transparent bg-input/50 px-2.5 py-1 text-base transition-colors outline-none",
          "focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/30",
          error ? "border-red-500" : "",
          className
        )}
        {...props}
        value={mounted ? (value as string) || "" : ""}
        onChange={(e) => setValue(e.target.value)}
      />
      {error && <span className="text-xs text-red-500 font-medium italic">{error}</span>}
    </div>
  )
}
```

Consumed directly — no separate stateful wrapper:

```tsx
<Input field="email" label="Email" />
```

The `useField` prop defaults to the project hook but may be overridden to bind a different store (e.g. prefs/filters), as long as the provided hook keeps the same shape.

### UI Library Atoms (with `ui/`)

In projects that install generated local UI-library primitives (shadcn, Radix), the primitives in `ui/` are reinstalled and never edited directly. Two sub-tiers are required: **presentation wrappers** (thin re-exports from `ui/`) and **stateful atoms** (bind wrappers + store).

**Presentation wrapper** — creates a stable import path so molecules never touch `ui/` directly:

```tsx
// src/components/atoms/Input.tsx
export { Input } from "@/components/ui/input"
```

One-liners. Every `ui/` component gets a matching wrapper in `atoms/`.

**Stateful atom** — wraps a presentation wrapper + Zustand binding (UI-library projects only):

```tsx
// src/components/atoms/ValidatedInput.tsx (with shadcn)
import * as React from "react"
import { Label } from "@/components/atoms/Label"
import { Input } from "@/components/atoms/Input"
import { useField } from "@/store/useField"
import { cn } from "@/lib/utils"

export function ValidatedInput({ field, label, className, ...props }: ValidatedInputProps) {
  const { value, error, setValue, mounted } = useField(field)
  return (
    <div className="flex flex-col gap-2 p-2">
      <Label htmlFor={field} className={cn(error ? "text-red-500" : "")}>{label}</Label>
      <Input
        id={field}
        value={mounted ? (value as string) || "" : ""}
        onChange={(e) => setValue(e.target.value)}
        className={cn(error ? "border-red-500" : "", className)}
        {...props}
      />
      {error && <span className="text-xs text-red-500 font-medium italic">{error}</span>}
    </div>
  )
}
```

Common stateful atoms in UI-library projects: `ValidatedInput`, `ValidatedRadioGroup`, `ValidatedSelect`, `ValidatedTextarea`, `ValidatedCheckboxGroup`, `ContinueButton`, `ProgressBar`, `DisclaimerCheckbox`.

### Which approach to pick?

| Vanilla atoms (self-bound) | UI library atoms (wrapper) |
|---|---|
| No extra dependency | Richer primitives (accessible by default) |
| Full control over markup | Faster to build complex UIs |
| Atom manages its own Zustand data | Wrapper tier required (primitives are reinstalled) |
| Best for small projects or custom design | Best for large projects with design systems |

**The golden rule:** vanilla projects bind atoms directly to the store — no `Validated*` wrapper tier. The wrapper tier exists only for projects with a `ui/` directory (generated primitives that must not be edited). The two **approaches** (self-bound vs wrapper tier) remain mutually exclusive — pick one per project. Within the **UI-library approach** you can mix primitives — shadcn for complex inputs (select, radio, checkbox) and hand-written Tailwind atoms for simple ones.

## 3. `molecules/` — Combinations of Atoms

Combine multiple atoms (vanilla or library-based) into a reusable unit. They never import from `ui/` — only from `atoms/`.

> The molecule example below uses the **UI-library (wrapper)** variant — `ValidatedRadioGroup`
> (approach 2). In a **vanilla-only** project the equivalent self-bound atom is `RadioGroup`
> (approach 1), the same shape as `Input`. Pick one approach per project and keep it consistent.

```tsx
// src/components/molecules/DynamicLabelRadioGroup.tsx
import * as React from "react"
import { ValidatedRadioGroup } from "@/components/atoms/ValidatedRadioGroup"
import { useFormStore } from "@/store/form"
import type { FormValues } from "@/store/form"

interface Option {
  value: string
  label: string
}

interface DynamicLabelRadioGroupProps {
  field: keyof FormValues | string
  options: Option[]
  labelTemplate: string
  labelFields: (keyof FormValues)[]
  fallbackLabel: string
}

export function DynamicLabelRadioGroup({
  field,
  options,
  labelTemplate,
  labelFields,
  fallbackLabel,
}: DynamicLabelRadioGroupProps) {
  const fieldValues = useFormStore((state) => {
    const subset: Record<string, unknown> = {}
    for (const f of labelFields) subset[f as string] = state[f]
    return subset
  })

  const label = React.useMemo(() => {
    const allPresent = labelFields.every(f => fieldValues[f as string])
    if (!allPresent) return fallbackLabel
    let result = labelTemplate
    for (const f of labelFields) result = result.replace(`{${String(f)}}`, String(fieldValues[f as string]))
    return result
  }, [fieldValues, labelTemplate, labelFields, fallbackLabel])

  return <ValidatedRadioGroup field={field} label={label} options={options} />
}
```

Common molecules: `DynamicLabelRadioGroup`, `GlobalLoader`, `LoadingOverlay`, `GenerationProgressBar` (add project-specific ones like repeaters/guards here; auth guards live outside this pattern).

## 4. `organisms/` — Complex Sections

Used for screen regions that compose multiple molecules. Only when a page needs more structure than a single molecule provides.

> **⚠️ READER NOTE on this example:** this organism composes **vanilla self-bound atoms**
> (approach 1) — `Input`, `RadioGroup`, and `CheckboxGroup` each bind the store directly
> (e.g. via the injectable `useField` hook, as `Input` does). In a **UI-library** project
> (with `ui/`) these would instead be `ValidatedInput`, `ValidatedRadioGroup`,
> `ValidatedCheckboxGroup` wrapper atoms (approach 2). Pick ONE approach per project; do
> not mix them.

```tsx
// src/components/organisms/Step3Form.tsx (example: conditional fields)
import * as React from "react"
import { RadioGroup } from "@/components/atoms/RadioGroup"
import { CheckboxGroup } from "@/components/atoms/CheckboxGroup"
import { Input } from "@/components/atoms/Input"
import { useFormStore } from "@/store/form"

export function Step3Form() {
  const completed = useFormStore(state => state.completed)

  return (
    <div className="flex flex-col gap-6 w-full max-w-lg mx-auto">
      <RadioGroup field="plan_type" label="Plan type?" options={planTypeOptions} />
      <RadioGroup field="completed" label="Completed onboarding?" options={yesNoOptions} />
      {completed === "yes" && (
        <CheckboxGroup field="topic_flags" label="Topics of interest?" options={topicOptions} />
      )}
      <Input field="notes" label="Notes?" placeholder="e.g., prefer morning contact" />
    </div>
  )
}
```

## 5. New Project Setup

### Vanilla only

```bash
mkdir -p src/components/{atoms,molecules,organisms}
```

Each atom is a self-contained component with Tailwind styles that binds the Zustand store directly via `useField`. No `ui/` directory and no `Validated*` wrapper tier needed.

### With shadcn

```bash
mkdir -p src/components/{ui,atoms,molecules,organisms}
pnpx shadcn init
pnpx shadcn add button checkbox input label radio-group select textarea
```

For each shadcn component, create a matching presentation wrapper in `atoms/`.

## 6. Consistency Rules

- Vanilla atoms in `atoms/*` are self-bound: they MAY import from `store/*` and `lib/*` and manage their own Zustand data via `useField`
- In a vanilla project there is no `Validated*` wrapper tier — the atom binds the store directly
- Molecules MUST NOT import from `ui/*` — only from `atoms/*`
- Organisms MUST NOT import from `ui/*` — only from `molecules/*` and `atoms/*`
- `ui/*` imports nothing from `components/` — it's the bottom of the dependency tree
- If you remove the UI library, only `atoms/*` needs changes — everything above stays the same

## 7. Connection to Other Patterns

- Vanilla atoms use `useField()` from the Zustand store → see [[astro-zustand-zod]]
- Astro pages host organisms → see [[astro-react-islands]]
