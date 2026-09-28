---
created: 2026-07-26
tags:
  - astro
  - zustand
  - zod
  - state-management
  - validation
  - documentation
type: resource
status: active
source: templates://astro/astro-zustand-zod.md
version: 2026-09-27+57b0fd3

---

# Zustand + Persist + Zod

> **Opt-in layer.** Precondition: [Base config](./astro-base-config.md) (+ React islands if atoms are React). Skip if no forms, filters, or cross-island state.

Zustand is the **primary state sharing layer** for all React islands in the project. Every component connects directly to Zustand — no prop drilling, no React context, no Redux. Zod handles all validation at the field level. `persist` middleware writes to localStorage so data survives page reloads and across Astro page navigations.

> **⚠️ READER / AI AGENT — two component approaches.** This doc describes the **store** (shared
> everywhere). The **components** that read it come in two mutually exclusive forms — see
> [astro-atomic-components](./astro-atomic-components.md):
> 1. **Vanilla self-bound atoms** (this project): `Input` binds `useField()` directly; the hook is
>    injectable via props. This is the default here — `src/components/atoms/Input.tsx`.
> 2. **UI-library wrapper atoms** (`ui/` projects): a presentation re-export + a `Validated*` atom
>    wraps the store hook.
>
> Pick ONE per project (UI library installed → 2; vanilla only → 1). If you are an AI agent
> setting up a new project and unsure which applies, ask the user before choosing.

## Architecture

```
┌────────────────────────────────────────────────────────┐
│                    Astro Pages                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
│  │  Page A  │  │  Page B  │  │  Page C  │             │
│  │ (page)   │  │ (page)   │  │ (page)   │             │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘             │
│       │              │              │                    │
│  ┌────┴──────────────┴──────────────┴────┐              │
│  │         Zustand Stores (persisted)      │             │
│  │  ┌──────────┐  ┌──────────┐           │             │
│  │  │ FormState│  │ Prefs    │           │             │
│  │  │ (form.ts)│  │(prefs.ts)│           │             │
│  │  └──────────┘  └──────────┘           │             │
│  └──────────────────┬────────────────────┘             │
│                     │                                    │
│  ┌──────────────────┴────────────────────┐              │
│  │          React Islands                  │             │
│  │   Each atom reads/writes via useField() │             │
│  └─────────────────────────────────────────┘             │
└──────────────────────────────────────────────────────────┘
```

## 1. Store Pattern

A single Zustand store holds all form data, errors, and loading state. `persist` middleware writes to localStorage. Every field has a Zod schema — validation runs automatically on each `setField` call.

```ts
// src/store/form.ts
import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import { z } from 'zod'

// 1. Define Zod schemas for your data
const userSchema = z.object({
  name: z.string().min(1, "Name is required"),
  email: z.string().email("Invalid email"),
  role: z.enum(["admin", "editor", "viewer"]),
})

const settingsSchema = z.object({
  theme: z.enum(["light", "dark", "system"]),
  notifications: z.boolean(),
  tags: z.array(z.string()),
})

// 2. Build union type
export type FormValues = z.infer<typeof userSchema> & z.infer<typeof settingsSchema>

// 3. Auto-build field → schema map (enforces unique field names across all schemas)
export const fieldSchemaMap = buildFieldSchemaMap([userSchema, settingsSchema])

export interface FormStore extends FormValues {
  errors: Record<string, string>
  isLoading: boolean
  setField: (field: string, value: unknown) => void
  validateAll: () => boolean
  reset: () => void
}

export const initialState: FormValues & { isLoading: boolean } = {
  name: "",
  email: "",
  role: "viewer",
  theme: "system",
  notifications: false,
  tags: [],
  isLoading: false,
}

export function getNestedValue(obj: Record<string, unknown>, path: string): unknown {
  return path.split(".").reduce<unknown>((acc, key) => {
    if (acc == null || typeof acc !== "object") return undefined
    return (acc as Record<string, unknown>)[key]
  }, obj)
}

export function setNestedValue(obj: Record<string, unknown>, path: string, value: unknown): void {
  const keys = path.split(".")
  const last = keys.pop() as string
  let target = obj
  for (const key of keys) {
    if (typeof target[key] !== "object" || target[key] === null) target[key] = {}
    target = target[key] as Record<string, unknown>
  }
  target[last] = value
}

// 4. Create store
export const useFormStore = create<FormStore>()(
  persist(
    (set, get) => ({
      ...initialState,
      errors: {},

      setField: (field: string, value: unknown) => {
        const fieldSchema = fieldSchemaMap.get(field)
        // Zod v3 API (z.object / .shape / safeParse) — see buildFieldSchemaMap below.
        set((state) => {
          const newErrors = { ...state.errors }
          if (fieldSchema) {
            const validation = fieldSchema.safeParse(value)
            if (!validation.success) {
              newErrors[field] = validation.error.issues[0]?.message
            } else {
              delete newErrors[field]
            }
          }
          if (field.includes(".")) {
            // Dotted path (e.g. "tags.0", "members.0.name"): deep-clone via
            // structuredClone (stdlib, no dep) so nested writes stay immutable.
            const next = structuredClone(state)
            setNestedValue(next as unknown as Record<string, unknown>, field, value)
            return { ...next, errors: newErrors }
          }
          return { ...state, [field]: value, errors: newErrors }
        })
      },

      validateAll: () => {
        const state = get()
        const allErrors: Record<string, string> = {}
        for (const [fieldName, schema] of fieldSchemaMap) {
          const value = fieldName.includes(".")
            ? getNestedValue(state as unknown as Record<string, unknown>, fieldName)
            : state[fieldName as keyof typeof state]
          const result = schema.safeParse(value)
          if (!result.success) {
            allErrors[fieldName] = result.error.issues[0]?.message
          }
        }
        set({ errors: allErrors })
        return Object.keys(allErrors).length === 0
      },

      reset: () => set({ ...initialState, errors: {} }),
    }),
    {
      name: 'app-form-storage',
      partialize: (state) => {
        const { errors, isLoading, ...rest } = state  // don't persist transient state
        return rest
      },
    }
  )
)
```

### `buildFieldSchemaMap` helper

```ts
export function buildFieldSchemaMap(schemas: z.ZodObject<any>[]): Map<string, z.ZodTypeAny> {
  const map = new Map<string, z.ZodTypeAny>()
  for (const schema of schemas) {
    for (const [field, fieldSchema] of Object.entries(schema.shape)) {
      if (map.has(field)) {
        throw new Error(`Field "${field}" appears in multiple schemas. Field names must be unique.`)
      }
      map.set(field, fieldSchema as z.ZodTypeAny)
    }
  }
  return map
}
```

Field names are **automatically enforced as unique** across all schemas. If `name` appears in two schemas, the function throws at module load.

## 2. The `useField()` Hook

Every store-bound atom uses this hook by default to connect to the store. It handles:
- Reading the current value
- Reading validation errors
- Setting new values
- Hydration safety (prevents SSR/CSR mismatches)

```ts
// src/store/useField.ts
import * as React from "react"
import { useFormStore, getNestedValue, initialState } from "./form"

export function useField(field: string) {
  const [mounted, setMounted] = React.useState(false)
  React.useEffect(() => setMounted(true), [])

  const isDotted = field.includes(".")  // e.g. "tags.0"
  const setField = useFormStore((state) => state.setField)

  // Selectors close over `field`, so memoize them on `field` — otherwise
  // Zustand resubscribes on every render. `field` is stable per component
  // instance, so this subscribes once.
  const flatSelector = React.useCallback(
    (state: FormStore) => (!field.includes(".") ? state[field as keyof typeof state] : undefined),
    [field],
  )
  const dottedSelector = React.useCallback(
    (state: FormStore) =>
      field.includes(".") ? getNestedValue(state as unknown as Record<string, unknown>, field) : undefined,
    [field],
  )
  const flatValue = useFormStore(flatSelector)
  const dottedSnapshot = useFormStore(dottedSelector)
  const value = isDotted ? dottedSnapshot : flatValue
  const errorSelector = React.useCallback(
    (state: FormStore) => state.errors[field],
    [field],
  )
  const error = useFormStore(errorSelector)

  const setValue = React.useCallback((v: unknown) => setField(field, v), [field, setField])

  // Return initial/default before hydration to avoid undefined flashes
  let safeValue: unknown
  if (mounted) {
    safeValue = value
  } else if (isDotted) {
    safeValue = getNestedValue(initialState, field) ?? ""
  } else {
    safeValue = initialState[field as keyof typeof initialState]
  }

  return { value: safeValue, error, setValue, mounted }
}
```

## 3. Using in Components

**Store-bound atom (vanilla default):**
```tsx
export function Input({ field, useField = defaultUseField, label }: {
  field: string
  useField?: (field: string) => { value: unknown; error?: string; setValue: (v: unknown) => void; mounted: boolean }
  label: string
}) {
  const { value, error, setValue, mounted } = useField(field)

  return (
    <div>
      <Label>{label}</Label>
      <input value={mounted ? (value as string) || "" : ""} onChange={e => setValue(e.target.value)} />
      {error && <span className="text-red-500 text-xs">{error}</span>}
    </div>
  )
}
```

The `useField` prop defaults to the project hook (see `src/store/useField.ts`) but may be overridden by a consumer to bind a different store — for example a prefs/filters store that follows the same single-hook-per-store pattern. The hook is always called unconditionally at the top level, so passing a custom hook reference is React-safe.

**Non-validated component** (reads store directly):
```tsx
export function Sidebar() {
  const theme = useFormStore((state) => state.theme)
  return <div className={`theme-${theme}`}>...</div>
}
```

## 4. Full Validation (on Submit)

Use `validateAll()` when the user submits the form — runs all schemas at once and returns true/false:

```tsx
async function handleSubmit() {
  const store = useFormStore.getState()
  if (!store.validateAll()) return  // errors already set in store, components will show them

  const { errors, isLoading, validateAll, reset, setField, ...formData } = store
  await myApi.submit(formData)
}
```

## 5. Nested Data (Arrays of Objects)

For fields like `tags: string[]` or repeated sub-objects, use dotted paths:

```ts
setField("tags", ["gardening", "music"])                    // set entire array
setField("tags.0", "cooking")                                // update single index
```

For arrays of objects, nest deeper:

```ts
setField("members.0.name", "John")
setField("members.0.role", "admin")
```

The `getNestedValue()` and `setNestedValue()` utilities in `form.ts` handle dotted path resolution. The `useField()` hook works transparently with them.

## 6. Validation Flow

```
User types → setField(field, value) → fieldSchema.safeParse(value)
  → success: clear error for this field
  → failure: set error message from Zod issue

User clicks Submit → validateAll() → all schemas parsed at once
  → success: submit data, clear errors
  → failure: set errors for all invalid fields
```

Per-field validation is immediate (on every keystroke). Full validation is on-demand (when the user tries to proceed).

## 7. New Project Setup

```bash
pnpm add zustand zod
```

```bash
mkdir -p src/store
```

Define separate stores for separate concerns:

| Store | Purpose | Persisted? |
|---|---|---|
| `form.ts` | Form data, errors | Yes |
| `prefs.ts` | Filters, prefs, theme | Yes (partial) |
| UI stores | Modals, toasts | Optional |

## 8. Key Rules

- Components read store directly — no prop drilling, no React context wrappers
- Vanilla atoms are store-bound by default and use `useField()`; use `useFormStore()` directly for non-validated reads
- The `useField` prop is injectable: a consumer may pass a custom hook/store, provided it keeps the same shape and is always called unconditionally
- Never re-implement hydration safety — `useField()` handles it
- `partialize` in persist config strips transient state (errors, loading flags) from localStorage
- Multiple stores for separate concerns (form, prefs/filters, UI) — each store exposes one shared hook; keep form data in one store for coherence
- Every `PUBLIC_*` field gets a Zod schema — validation is built into the store, not scattered across components

## 9. Connection to Other Patterns

- Store-bound atoms use `useField()` by default → see [astro-atomic-components](./astro-atomic-components.md)
- Fetch data in store actions using `safeFetch` → see [astro-fetch-wrapper](./astro-fetch-wrapper.md)
- Astro pages host React islands that read from this store → see [astro-react-islands](./astro-react-islands.md)
