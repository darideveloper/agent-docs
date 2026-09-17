---
created: 2026-07-26
updated: 2026-07-26
tags:
  - astro
  - api
  - fetch
  - error-handling
  - pattern
  - documentation
type: resource
status: active
source: templates://astro/astro-fetch-wrapper.md
version: 2026-09-17+4cf710f

---

# Fetch Wrapper Pattern

> **Opt-in layer.** Precondition: [Base config](./astro-base-config.md) (`PUBLIC_API_BASE_URL`). Skip if the project has no API (e.g. i18n-only content site).

A typed fetch client with retry logic, timeout, and structured error classes. All API calls go through this wrapper — never raw `fetch()`.

## Architecture

```
safeFetch<T>(url, options, timeout, retries)
  └── attemptFetch<T>(url, options, timeout)
        ├── AbortSignal.timeout(timeoutMs)
        ├── url → fetch()
        ├── ok? → empty/JSON body (204 + non-JSON guarded)
        └── fail? → FetchError { type, message, status }
              ├── "network"   → retry (exponential backoff)
              ├── "timeout"   → retry (exponential backoff)
              ├── "http"      → throw immediately
              ├── "parse"     → throw immediately
              └── "abort"     → throw immediately
```

## 1. The Client

```ts
// src/lib/api/client.ts
export class FetchError extends Error {
  constructor(
    public type: "network" | "timeout" | "http" | "parse" | "abort",
    message: string,
    public status?: number,
  ) {
    super(message)
    this.name = "FetchError"
  }
}

async function attemptFetch<T>(
  url: string,
  options: RequestInit,
  timeoutMs: number,
): Promise<T> {
  const signal = options.signal
    ? AbortSignal.any([options.signal, AbortSignal.timeout(timeoutMs)])
    : AbortSignal.timeout(timeoutMs)

  let response: Response
  try {
    response = await fetch(url, { ...options, signal })
  } catch (err) {
    if (err instanceof DOMException && err.name === "TimeoutError") {
      throw new FetchError("timeout", "Request timed out")
    }
    if (err instanceof DOMException && err.name === "AbortError") {
      throw new FetchError("abort", "Request was cancelled")
    }
    throw new FetchError("network", err instanceof Error ? err.message : "Network error")
  }

  if (!response.ok) {
    throw new FetchError("http", `HTTP ${response.status} ${response.statusText}`, response.status)
  }

  // 204 No Content (or empty body) has no JSON to parse.
  if (response.status === 204 || response.headers.get("content-length") === "0") {
    return undefined as T
  }
  const contentType = response.headers.get("content-type") ?? ""
  if (contentType && !contentType.includes("application/json")) {
    throw new FetchError("parse", `Expected JSON, got ${contentType}`)
  }

  let data: unknown
  try {
    const text = await response.text()
    data = text ? JSON.parse(text) : undefined
  } catch {
    throw new FetchError("parse", "Failed to parse response as JSON")
  }

  return data as T
}

export async function safeFetch<T>(
  url: string,
  options: RequestInit = {},
  timeoutMs = 30_000,
  maxRetries = 2,
): Promise<T> {
  let lastError: FetchError | undefined

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await attemptFetch<T>(url, options, timeoutMs)
    } catch (err) {
      if (!(err instanceof FetchError)) throw err

      lastError = err

      // Only retry transient errors
      if (err.type === "timeout" || err.type === "network") {
        if (attempt < maxRetries) {
          const delay = Math.min(1000 * Math.pow(2, attempt) + Math.random() * 500, 5000)
          await new Promise((r) => setTimeout(r, delay))
          continue
        }
      }

      // HTTP errors, parse errors, aborts — throw immediately
      throw err
    }
  }

  throw lastError ?? new FetchError("network", "Unknown error")
}
```

## 2. API Endpoint Modules

Each backend endpoint gets its own file in `src/lib/api/`. The files are thin — they import `safeFetch` and define the request shape + response type.

```ts
// src/lib/api/auth.ts
import { safeFetch } from "./client"
import type { LoginResponse } from "./types"

export function login(email: string, password: string) {
  const baseUrl = import.meta.env.PUBLIC_API_BASE_URL
  return safeFetch<LoginResponse>(`${baseUrl}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  })
}
```

```ts
// src/lib/api/items.ts
import { safeFetch } from "./client"
import type { ItemsResponse } from "./types"

export function getItems() {
  const baseUrl = import.meta.env.PUBLIC_API_BASE_URL
  return safeFetch<ItemsResponse>(`${baseUrl}/items`, {
    method: "GET",
    headers: { "Content-Type": "application/json" },
  })
}
```

## 3. Shared Types

```ts
// src/lib/api/types.ts
export interface LoginResponse {
  token: string
  user: { id: number; name: string; email: string }
}

export interface ItemsResponse {
  items: Array<{ id: number; name: string }>
  total: number
}
```

## 4. Constants

```ts
// src/lib/api/constants.ts
export const API_ERROR_MESSAGE =
  "Something went wrong. Please try again."
```

Store shared messages, error strings, or common defaults in this file instead of scattering them across components.

## 5. Usage in Components

```tsx
import { login } from "@/lib/api/auth"
import { FetchError } from "@/lib/api/client"
import { API_ERROR_MESSAGE } from "@/lib/api/constants"

async function handleLogin(email: string, password: string) {
  try {
    const response = await login(email, password)
    // response is typed: { token: string; user: { id: number; ... } }
  } catch (err) {
    if (err instanceof FetchError) {
      if (err.type === "timeout") {
        // show "Request timed out" message
      } else if (err.type === "http" && err.status === 401) {
        // show "Invalid credentials"
      } else if (err.type === "network") {
        // show "No connection" with retry button
      } else {
        // show generic error
      }
    }
  }
}
```

## 6. Error Handling Strategy

| Error type | Meaning | Action |
|---|---|---|
| `network` | No internet, DNS failure, connection refused | Show generic error, retry button |
| `timeout` | Server didn't respond in time | Show generic error, retry button |
| `http` | Server returned 4xx/5xx | Show status-specific message |
| `parse` | Response isn't valid JSON | Log error, show generic message |
| `abort` | Request was cancelled (e.g. component unmounted) | Do nothing (expected) |

## 7. New Project Setup

```bash
# Create API directory structure
mkdir -p src/lib/api

# Create files
touch src/lib/api/client.ts     # safeFetch + FetchError
touch src/lib/api/types.ts      # shared response types
touch src/lib/api/constants.ts  # shared messages
```

For each backend endpoint, create a module:
```ts
// src/lib/api/my-endpoint.ts
import { safeFetch } from "./client"
import type { MyResponse } from "./types"

export function myEndpoint(param: string) {
  const baseUrl = import.meta.env.PUBLIC_API_BASE_URL
  return safeFetch<MyResponse>(`${baseUrl}/endpoint`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ param }),
  })
}
```

## 8. Environment Variables

```env
PUBLIC_API_BASE_URL=https://api.example.com
```

`PUBLIC_*` prefix makes it available in client-side code via `import.meta.env`.

See [[astro-docker-deployment|Dockerized Deployment]] for how to pass build-time env vars in Docker.

## 9. Key Rules

- One file per API endpoint in `src/lib/api/`
- All calls go through `safeFetch` — never raw `fetch()`
- Use `FetchError` for typed error handling in components
- Retry logic is in the client — component code doesn't need retry loops
- Set reasonable timeouts (30s default) — infinite waits are the most common bug
- Base URL from `import.meta.env.PUBLIC_*` — never hardcode
- Requires Node 20+ / modern browsers (`AbortSignal.timeout` + `AbortSignal.any`)

## 10. Connection to Other Patterns

- Call API endpoints from Zustand store actions → see [[astro-zustand-zod]]
- Environment variables for base URL → see [[astro-docker-deployment]]
