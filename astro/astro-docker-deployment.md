---
created: 2026-07-26
updated: 2026-09-17
tags:
  - astro
  - docker
  - deployment
  - pnpm
  - nginx
  - documentation
type: resource
status: active
source: templates://astro/astro-docker-deployment.md
version: 2026-09-17+4cf710f

---

# Dockerized Deployment

Multi-stage Docker build for Astro projects: node builds the static site, nginx serves it. Uses **pnpm** exclusively — never npm.

## Dockerfile

```dockerfile
# syntax=docker/dockerfile:1.7

# === Stage 1: Build ===
FROM node:lts-alpine AS build
RUN corepack enable && corepack prepare pnpm@<latest> --activate
WORKDIR /app

# Build-time environment variables — Pattern B (default): SITE_URL is a
# server-only Docker build arg so production canonicals resolve per
# environment. Pass --build-arg SITE_URL=https://<prod-domain>.
ARG SITE_URL
ENV SITE_URL=$SITE_URL

# Only if the project has a backend contract — omit otherwise (add one
# ARG/ENV pair per PUBLIC_* var):
# ARG PUBLIC_API_BASE_URL
# ENV PUBLIC_API_BASE_URL=$PUBLIC_API_BASE_URL

# Install dependencies (cached layer — only invalidates on lockfile change)
COPY package.json pnpm-lock.yaml ./
# If your project uses pnpm workspaces, also copy (projects without
# workspaces omit this line):
# COPY pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

# Build the static site
COPY . .
RUN pnpm build

# === Stage 2: Serve ===
FROM nginx:alpine AS serve
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```

## Nginx Config

```nginx
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    ## PWA: remove this block if not using PWA
    error_page 404 /offline/index.html;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json
               application/javascript application/rss+xml
               application/atom+xml image/svg+xml application/manifest+json;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    ## PWA: remove this block if not using PWA
    # Service worker — never cache
    location ~* ^/(sw\.js|workbox-.*\.js)$ {
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
    }

    ## PWA: remove this block if not using PWA
    # PWA manifest
    location = /manifest.webmanifest {
        add_header Cache-Control "no-cache" always;
        add_header Content-Type "application/manifest+json" always;
    }

    # Content-hashed assets — immutable cache
    location ~* ^/_astro/ {
        expires 1y;
        add_header Cache-Control "public, max-age=31536000, immutable" always;
        access_log off;
    }

    # Static assets
    location ~* \.(?:ico|gif|jpe?g|png|woff2?|svg|webp)$ {
        expires 1y;
        add_header Cache-Control "public, max-age=31536000, immutable" always;
        access_log off;
    }

    # HTML pages — no cache (SPA routing)
    location / {
        try_files $uri $uri/index.html =404;
        add_header Cache-Control "no-cache" always;
    }
}
```

The template works for both PWA and non-PWA projects. Delete every section marked `## PWA: remove this block if not using PWA` (the offline `error_page`, the service worker block, and the manifest block) to get the non-PWA variant.

## Build & Run Commands

```bash
# Build image (always pass SITE_URL; add a --build-arg per PUBLIC_* var only if the project has a backend contract)
docker build \
  --build-arg SITE_URL=https://<prod-domain> \
  -t your-app:latest .

# With backend contract, append:
#   --build-arg PUBLIC_API_BASE_URL=https://api.example.com \

# Run container
docker run -d -p 8080:80 your-app:latest
```

## Deployment Platforms

### Coolify / Any Docker Host

1. Point to your Git repo
2. Set build pack to **Dockerfile**
3. Add `SITE_URL=https://<prod-domain>` as a **Build Time** var; add `PUBLIC_*` vars the same way only if the project has a backend contract
4. The Dockerfile uses `node:lts-alpine` — ensure the platform supports `corepack`

### CI/CD (GitHub Actions)

```yaml
name: Build & Deploy
on:
  push:
    branches: [main]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build Docker image
        run: |
          docker build \
            --build-arg SITE_URL=${{ secrets.SITE_URL }} \
            -t your-app:${{ github.sha }} .
      # With backend contract, append:
      #   --build-arg PUBLIC_API_BASE_URL=${{ secrets.API_URL }} \
      - name: Push to registry
        run: |
          docker tag your-app:${{ github.sha }} registry.example.com/your-app:latest
          docker push registry.example.com/your-app:latest
```

## Important: pnpm Lockfile

```bash
# Always commit pnpm-lock.yaml
git add pnpm-lock.yaml

# Never use npm install — pnpm only
pnpm install    # correct
npm install     # wrong — will fail because no package-lock.json
```

Ensure `package.json` has the pnpm engines constraint:

```json
{
  "packageManager": "pnpm@<latest>",
  "engines": {
    "node": ">= LTS"
  }
}
```

## Environment Variables

| Pattern | When available | Example |
|---|---|---|
| `PUBLIC_*` | Build-time + runtime | `PUBLIC_API_BASE_URL` |
| Build ARGs | Build-time only | API keys, secrets for build |
| `import.meta.env.PUBLIC_*` | Client-side code | Front-end API URLs |

Astro inlines `PUBLIC_*` variables at build time. Pass them as Docker build args so they're available during `pnpm build`.

> `SITE_URL` canonicals in production come from `site:` / `BUSINESS_DATA.url`. Two valid patterns:
> - **Pattern B (default):** `SITE_URL` is a server-only Docker build arg (`ARG SITE_URL` / `ENV SITE_URL` in the `Dockerfile`; pass `--build-arg SITE_URL=https://<prod-domain>`) — use whenever the hosting setup injects the canonical per environment.
> - **Pattern A:** `SITE_URL` is dev-only (Portless worktree URLs) and is **not** a Docker build arg — `.dockerignore` excludes `.env*`, so the build never reads the dev `.env`. Use only when the host provides the canonical by other means.
> See [Git Worktrees + Portless](./astro-worktrees.md).

## New Project Setup

```bash
# 1. Create Dockerfile (content from section 1)
# 2. Create nginx.conf (content from section 2)
# 3. Add .dockerignore
```

**.dockerignore:**
```
node_modules/
dist/
.git/
.env
.env.*
*.md
.gitignore
```

## Key Rules

- Always use `pnpm install --frozen-lockfile` in Docker builds — fails if lockfile is out of sync
- Always pass `SITE_URL` as a build arg (Pattern B default); add new build ARGs for every `PUBLIC_*` env var only if the project has a backend contract
- `/_astro/*` assets can have immutable cache — Astro content-hashes filenames
- PWA only: service worker JS must have no-cache headers, and use `error_page 404 /offline/index.html` for SPA/PWA offline navigation
