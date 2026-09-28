---
created: 2026-09-17
tags:
  - django
  - git
  - worktrees
  - portless
  - tmux
  - documentation
type: resource
status: active
source: templates://django/django-worktrees.md
version: 2026-09-27+57b0fd3

---

# Git Worktrees + Portless (Django)

One checkout per branch, all runnable at once. Each sibling gets its own
stable `.localhost` URL automatically — no port juggling, no stash/checkout
cycles. Placeholders: `<project>` = directory/repo name, `<branch>` = branch
name, `<PROJECT_PACKAGE>` = Django settings package, `DB_NAME=<project>`.

This builds on [Local Development & Subdomain Setup](./django-local-subdomain-setup.md)
(`dev.sh` + tmux + portless). Read that guide first for the single-checkout base.

## Why

Parallel branches share a single checkout by default, allowing only one dev
server at a time. Git worktrees give every branch its own directory sharing
one `.git`, and `dev.sh` (tmux + portless) gives every directory its own
domain: `main` and any number of branches run side by side.

## Prerequisites

- git, tmux, portless (`npm install -g portless`), Python 3.12, local Postgres
  (or `DB_ENGINE=django.db.backends.sqlite3` in `.env.dev` to bypass it).

## URL model

`dev.sh` derives everything from the directory basename:

```
main checkout (dir `<project>`):          https://<project>.localhost
sibling (dir `<project>-<branch>`):       https://<project>-<branch>.localhost
```

Each sibling also gets its own tmux session (`<basename>_dev`) and its own
port (portless-injected `$PORT` first, else auto-scanned from 8000).
`portless list` is the source of truth for live routes.

> Django note: unlike branch-subdomain setups, the branch goes in the
> directory name (`<project>-<branch>`), not as a subdomain prefix. A copied
> `.env.dev` keeps main's `HOST` — harmless: settings resolve
> `PORTLESS_URL → HOST → fallback` and accept the checkout's own `.localhost`
> domain in dev (see Step 1 below).

## Layout

Siblings only, in the same session. Never nest a worktree inside the main
checkout. Manual siblings only — never use agent `worktree_create` /
`worktree_delete` plugin tools (they open a new terminal and nest under a
central store).

```bash
<projects-root>/
  <project>/              # main checkout
  <project>-<branch>/     # sibling worktree (e.g. <project>-feature-auth)
```

## Lifecycle

Pre-flight in main: `git status --short --branch`. Commit or stash first —
siblings start from committed `HEAD` only.

```bash
git fetch origin
./worktree-new.sh ../<project>-<branch> <branch>            # existing branch
./worktree-new.sh ../<project>-feature feature/xyz main     # new branch
git worktree list
cd ../<project>-<branch> && ./dev.sh   # -> https://<project>-<branch>.localhost
# ... after merge, stop the dev server first, then:
git worktree remove ../<project>-<branch>
git worktree prune
```

`worktree-new.sh` performs the full bootstrap per sibling: fresh `venv`,
`pip install -r requirements.txt`, `.env`/`.env.dev` copy (from main, else
`.env.example`), `migrate`, and `.opencode` openspec skills/commands sync.

## Finish (merge + delete)

When the sibling's work is done and committed, merge it back with
`worktree-done.sh` — one command, same session:

```bash
./worktree-done.sh ../<project>-<branch>            # into current branch
./worktree-done.sh ../<project>-<branch> main       # into main explicitly
```

What it does, in order:

1. Copies the sibling's `openspec/changes/archive/` back (active proposals
   are gitignored and never cross on their own).
2. Refuses to start unless work is committed: the sibling fully clean
   (untracked included — everything must travel via the branch), main
   tracked-clean. Commit or stash first on both sides.
3. Merges the sibling branch with `git merge --no-ff` (keeps every commit
   from both sides; no squash, no rebasing).
4. **On any conflict or failed migration it stops**: nothing is resolved,
   nothing is deleted. It lists the conflicted files (merge stays open) and
   the agent asks you how to proceed. Fix, then re-run the same command to
   resume — it completes the merge and continues cleanup.
5. Only after a correct merge: stops the sibling dev server, `worktree
   remove`, `prune`, and `branch -d` (`-d` still refuses if anything ended
   up unmerged).

Never `worktree remove` a sibling with unmerged/unreviewed work, and never
resolve a conflicted merge without being asked.

### Merge policy

`--no-ff` keeps every commit from both sides plus one merge commit, so
per-side migrations and the `archive/` sync stay visible and `branch -d`
remains a meaningful guard. Squash compresses the branch to one commit on
`main` and hides which side added which migration — not used for Django.

## What doesn't transfer

| Path | Why | Action per sibling |
|---|---|---|
| `venv/` / `.venv/` | gitignored | fresh `python3 -m venv venv` + `pip install` (never symlink) |
| `.env`, `.env.dev` | gitignored (secrets) | copied by `worktree-new.sh` (`$MAIN/.env.dev` → `.env.example` fallback) |
| `db.sqlite3`, `testing.sqlite3` | gitignored | recreated; tests always use sqlite |
| `media/`, `staticfiles/` | gitignored | recreated |
| Dotfolders (`.opencode/`, …) | gitignored via `.*/` | openspec skills/commands synced by script |
| Active `openspec/changes/*` proposals | gitignored, isolated per sibling | never copied; only `archive/` synced back by `worktree-done.sh` |
| Uncommitted changes | siblings start from `HEAD` | commit or stash first |

## Database

All siblings share Postgres `DB_NAME=<project>` (project decision). Migrate
from one sibling at a time; test runs are isolated (forced sqlite).
Escape hatch for full isolation:

```bash
# in the sibling's .env.dev:
DB_ENGINE=django.db.backends.sqlite3
```

## Openspec per sibling

Active proposals under `openspec/changes/*` stay isolated per sibling (only
`openspec/changes/archive/` is tracked — ignore pair defined in
[django-project-setup](./django-project-setup.md) §4). New siblings get the workflow via
the `.opencode/skills/openspec-*` + `commands/opsx-*.md` markdown sync in
`worktree-new.sh`. Before merge, copy back only `archive/`.

## Stopping

- One dev server per checkout: detach or `tmux kill-session -t <name>_dev`.
- There is **no per-route stop command** (`portless stop <name>` registers a
  bogus route). The route unregisters when its dev process exits.
- Deleting a worktree does **not** stop its server — stop it first. A killed
  parent can orphan the `runserver` child — kill the child
  `venv/bin/python manage.py runserver <port>` too.
- Agents never autostart servers; start `./dev.sh` manually and confirm with
  `portless list`.

## Troubleshooting

| Issue | Fix |
|---|---|
| `DisallowedHost` in a sibling | Pull latest `main` (URL chain lives in `settings.py`), restart `./dev.sh` |
| Second `./dev.sh` attaches unexpectedly | Session `<basename>_dev` already exists — attach is intended; kill it to restart |
| Proxy 404 but direct `http://127.0.0.1:<port>/` answers | Parent process died, route unregistered — restart `./dev.sh` |
| Killed the parent but the port is still bound | `kill` on the portless parent orphans the `runserver` child — kill the child `venv/bin/python manage.py runserver <port>` too, then remove |
| `.localhost` doesn't resolve (Safari, Firefox) | `portless hosts sync` |
| Branch names with `/` | Sanitized in the domain — check `portless list` after first boot |

## Copy-paste: `AGENTS.md` block for target projects

Add after existing conventions (agents load this on session start):

```markdown
## Git Worktrees

One checkout per branch, all runnable at once (`main` → `https://<project>.localhost`,
sibling `../<project>-<branch>` → `https://<project>-<branch>.localhost`).
Full runbook: `docs/django-worktrees.md`.

- Manual siblings only, same session. Never `worktree_create` / `worktree_delete`
  plugin tools; never nest a worktree inside the main checkout.
- Lifecycle: `git status` clean first, then `./worktree-new.sh ../<project>-<branch> [branch] [base]`,
  `cd` in, `./dev.sh`. Stop the dev server before `git worktree remove`; `prune` after.
- Finish: `./worktree-done.sh ../<project>-<branch> [into]` merges keeping both sides
  (`--no-ff`), stops + asks on any conflict (never auto-resolve), then full cleanup
  (stop server, remove, prune, `branch -d`). Sibling must be fully committed clean,
  main tracked-clean first.
- Bootstrap per sibling is fresh `venv` + `pip install` (never symlink), `.env` copy
  (harmless — settings resolve `PORTLESS_URL → HOST`), `migrate`, openspec skills sync.
- Gotchas: shared Postgres `DB_NAME=<project>` (migrate from one sibling at a time;
  `DB_ENGINE=django.db.backends.sqlite3` escape hatch); openspec active proposals stay
  isolated (only `archive/` synced back by `worktree-done.sh`); agents never autostart servers
   (verify with `portless list`).
```

> The runbook itself must be tracked: keep the `.gitignore` exception
> `/docs/*` + `!/docs/django-worktrees.md` (see [django-project-setup](./django-project-setup.md) §4)
> and save this doc as `docs/django-worktrees.md` in the target project.

## Copy-paste: `worktree-new.sh`

Save the block below as `worktree-new.sh`, then `chmod +x worktree-new.sh
worktree-done.sh dev.sh` (the scripts must be executable — the source repo
commits them with `+x`).

```bash
#!/bin/bash
# Bootstrap a sibling git worktree ready to run: venv, deps, env, migrate,
# openspec skills. Usage: ./worktree-new.sh ../<project>-<branch> [branch] [base]
set -e

MAIN=$(cd "$(dirname "$0")" && pwd)
DIR=$1
BRANCH=$2
BASE=$3

if [ -z "$DIR" ]; then
    echo "Usage: $0 <sibling-dir> [branch] [base]"
    exit 1
fi

if [ -n "$(git -C "$MAIN" status --porcelain)" ]; then
    echo "Warning: $MAIN has uncommitted changes; the sibling starts from HEAD without them."
fi

# 1. Worktree (sibling layout, never nested)
if [ -n "$BRANCH" ]; then
    if git -C "$MAIN" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null; then
        git -C "$MAIN" worktree add "$DIR" "$BRANCH"
    else
        git -C "$MAIN" worktree add "$DIR" -b "$BRANCH" "${BASE:-HEAD}"
    fi
else
    git -C "$MAIN" worktree add "$DIR"
fi

cd "$DIR"

# 2. Fresh venv + deps per sibling (never symlinked)
[ -d "venv" ] || python3 -m venv venv
venv/bin/pip install -r requirements.txt

# 3. Env: copy from main checkout, else template (copied HOST is harmless:
# settings resolve PORTLESS_URL first, then HOST)
[ -f ".env" ] || { [ -f "$MAIN/.env" ] && cp "$MAIN/.env" .env || echo "ENV=dev" > .env; }
[ -f ".env.dev" ] || { [ -f "$MAIN/.env.dev" ] && cp "$MAIN/.env.dev" .env.dev || cp .env.example .env.dev; }

# 4. Migrate (shared Postgres per project decision; tests always use sqlite)
venv/bin/python manage.py migrate --noinput

# 5. Openspec skills/commands sync (markdown only; active proposals stay isolated)
if [ -d "$MAIN/.opencode" ]; then
    mkdir -p .opencode/skills .opencode/commands
    cp -rn "$MAIN"/.opencode/skills/openspec-* .opencode/skills/ 2>/dev/null || true
    cp -rn "$MAIN"/.opencode/commands/opsx-*.md .opencode/commands/ 2>/dev/null || true
fi

NAME=$(basename "$PWD")
echo "Ready: $DIR (branch: $(git branch --show-current))"
echo "Next: cd $DIR && ./dev.sh   # -> https://$NAME.localhost (verify with: portless list)"
```

## Copy-paste: `worktree-done.sh`

```bash
#!/bin/bash
# Merge a sibling worktree branch into the current branch (keeping both sides),
# then fully clean up the sibling. Conflicts stop the script for the user.
# Usage: ./worktree-done.sh <sibling-dir> [into-branch]
set -e

MAIN=$(cd "$(dirname "$0")" && pwd)
cd "$MAIN"
DIR=$1
INTO=${2:-$(git branch --show-current)}

if [ -z "$DIR" ]; then
    echo "Usage: $0 <sibling-dir> [into-branch]"
    exit 1
fi
DIR_ABS=$(cd "$DIR" 2>/dev/null && pwd) || { echo "Not a directory: $DIR"; exit 1; }
if [ "$DIR_ABS" = "$MAIN" ]; then
    echo "Refusing to finish the main checkout itself."
    exit 1
fi
BRANCH=$(git -C "$DIR_ABS" branch --show-current 2>/dev/null) || BRANCH=""
if [ -z "$BRANCH" ]; then
    echo "Sibling is on a detached HEAD; create a branch there first."
    exit 1
fi
if [ "$BRANCH" = "$INTO" ]; then
    echo "Sibling branch ($BRANCH) is the target branch; nothing to merge."
    exit 1
fi

# 1. Openspec archive sync (active proposals are gitignored and don't transfer)
if [ -d "$DIR_ABS/openspec/changes/archive" ]; then
    mkdir -p "$MAIN/openspec/changes/archive"
    cp -rn "$DIR_ABS"/openspec/changes/archive/. "$MAIN/openspec/changes/archive/" 2>/dev/null || true
fi

# 2. Pre-flight: sibling fully committed (everything must travel via the
# branch); main tracked-clean (untracked files can't be affected by a merge)
if [ -n "$(git -C "$DIR_ABS" status --porcelain)" ]; then
    echo "Sibling has uncommitted changes; commit or stash there first."
    exit 1
fi
RESUME=""
if git -C "$MAIN" rev-parse --verify --quiet MERGE_HEAD >/dev/null; then
    RESUME=1
elif ! git -C "$MAIN" diff --quiet || ! git -C "$MAIN" diff --cached --quiet; then
    echo "Main checkout has uncommitted tracked changes; commit or stash first."
    exit 1
fi

# 3. Merge keeping both sides (re-runs resume an in-progress merge)
if [ -z "$RESUME" ]; then
    git -C "$MAIN" checkout --quiet "$INTO"
    if ! git -C "$MAIN" merge --no-ff --no-edit "$BRANCH"; then
        echo "Merge conflicts — nothing resolved, nothing cleaned up."
        echo "Conflicted files:"
        git -C "$MAIN" diff --name-only --diff-filter=U | sed 's/^/  /'
        echo "Resolve them, then re-run: $0 $DIR $INTO"
        exit 1
    fi
else
    if [ -n "$(git -C "$MAIN" diff --name-only --diff-filter=U)" ]; then
        echo "Merge still conflicted — nothing cleaned up. Conflicted files:"
        git -C "$MAIN" diff --name-only --diff-filter=U | sed 's/^/  /'
        echo "Resolve them, then re-run: $0 $DIR $INTO"
        exit 1
    fi
    git -C "$MAIN" commit --no-edit --quiet
fi

# 4. Migrate merged tree (shared Postgres; both sides may add migrations)
VENV="venv"
[ -d ".venv" ] && VENV=".venv"
if ! $VENV/bin/python manage.py migrate --noinput; then
    echo "Migration failed after merge; branch and worktree kept for inspection."
    exit 1
fi

# 5. Full cleanup (branch -d refuses unmerged work as a last guard)
NAME=$(basename "$DIR_ABS")
tmux kill-session -t "${NAME}_dev" 2>/dev/null || true
if ! git -C "$MAIN" worktree remove "$DIR_ABS"; then
    echo "Could not remove worktree (a live server may hold it); stop it and re-run."
    exit 1
fi
git -C "$MAIN" worktree prune
git -C "$MAIN" branch -d "$BRANCH"
echo "Merged $BRANCH into $INTO and removed $DIR."
```

## Copy-paste: `dev.sh` (worktree-aware)

See [Local Development & Subdomain Setup](./django-local-subdomain-setup.md) for
the full guide with Cases A/B/C. The worktree-aware core is:

```bash
#!/bin/bash

# 1. Project Identity
PROJECT_NAME=$(basename "$PWD")
SESSION_NAME="${PROJECT_NAME}_dev"

# 2. Check for existing session
if tmux has-session -t $SESSION_NAME 2>/dev/null; then
    echo "Session $SESSION_NAME already exists. Attaching..."
    tmux attach -t $SESSION_NAME
    exit 0
fi

# 3. Portless Initialization
portless proxy start
portless trust

# 4. Dynamic Port Detection (prefers portless-injected $PORT, else starts at 8000)
PORT=${PORT:-8000}
while ss -tuln | grep -q ":$PORT " ; do
    PORT=$((PORT+1))
done

# 5. Virtual Env Detection
VENV_CMD=""
[ -d "venv" ] && VENV_CMD="source venv/bin/activate && "
[ -d ".venv" ] && VENV_CMD="source .venv/bin/activate && "

# 6. Launch Django via portless in a tmux session (Case A: vanilla)
tmux new-session -d -s $SESSION_NAME -n 'django' -c "$PWD" \
    "bash -c '${VENV_CMD}portless $PROJECT_NAME --app-port $PORT -- python manage.py runserver $PORT; read'"
tmux select-window -t $SESSION_NAME:0
tmux attach -t $SESSION_NAME
```

Each sibling basename yields its own `https://<project>-<branch>.localhost`.
