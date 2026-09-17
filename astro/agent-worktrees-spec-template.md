---
created: 2026-09-17
updated: 2026-09-17
tags:
  - astro
  - git
  - worktrees
  - openspec
  - documentation
type: resource
status: active
source: templates://astro/agent-worktrees-spec-template.md
version: 2026-09-17+4cf710f

---

# `agent-worktrees` Spec Template (copy-paste)

Copy this file to `openspec/specs/agent-worktrees/spec.md` in each new
project, substituting `<project>` for the repo name. The headings and
`SHALL` keywords are load-bearing — keep them verbatim so the spec stays
enforceable.

```markdown
## ADDED Requirements

### Requirement: Sibling worktree layout
Worktrees SHALL live as siblings of the main checkout at `../<project>-<branch>` (e.g. `../<project>-feature-auth`). They SHALL never be nested inside the main checkout and SHALL never live under the plugin central store (`~/.local/share/opencode/worktree/...`). The opencode-worktree plugin cannot produce this layout (its path is always `<base>/<project-hash>/<branch>`), so `worktree_create` SHALL NOT be used in this project.

#### Scenario: Sibling checkout visible from main
- **WHEN** an operator runs `git worktree add ../<project>-<branch> -b <branch> main` from the main checkout
- **THEN** `git worktree list` shows the main checkout plus the sibling path, in the same terminal session with no new terminal opened

### Requirement: Same-session manual lifecycle
The operator SHALL create, work in, and delete worktrees in the same session: `git worktree add` → bootstrap → work → stop dev → `git worktree remove` → `git worktree prune`. `worktree_create`/`worktree_delete` SHALL NOT be used (both always fork a session and open a new terminal, which is forbidden here, and deletion auto-commits a snapshot that this flow does not want).

#### Scenario: Full cycle without a new terminal
- **WHEN** the operator follows the lifecycle above for branch `<branch>`
- **THEN** no new terminal or tmux window opens, no `chore(worktree): session snapshot` commit is produced, and `git worktree list` is clean afterward

### Requirement: Manual bootstrap (real install)
Each new sibling SHALL be bootstrapped by hand: `cp ../<project>/.env .env` (missing `.env.local`/`.env.production` tolerated) and a real `pnpm install` (no `node_modules` symlink). `SITE_URL` copied from main is harmless: the `PORTLESS_URL → SITE_URL → prod` chain resolves each checkout's own URL first.

#### Scenario: Sibling serves its own URL
- **WHEN** the operator runs `pnpm run dev` in `../<project>-<branch>`
- **THEN** Portless serves it at `https://<branch>.<project>.localhost` alongside main with no extra config

### Requirement: Manual archive-only openspec sharing
No openspec directory SHALL cross checkouts automatically (there are no hooks in this flow). When archive context is needed, the operator MAY copy it explicitly by hand (`cp -rn` of `openspec/changes/archive/`), in either direction. Active `openspec/changes/*` proposals SHALL stay isolated per checkout.

#### Scenario: Agent sees decisions but not sibling proposals
- **WHEN** a sibling is created while other active proposals exist
- **THEN** it contains none of them unless the operator explicitly copies the archive; active proposals never move on their own

### Requirement: Teammate-branch review precondition
The operator SHALL run `git fetch origin` and ensure a local branch exists (e.g. `git branch <name> origin/<name>` for a remote-only branch) BEFORE `git worktree add ../<project>-<name> <name>`. A remote-only name without a local branch SHALL NOT be used directly.

#### Scenario: Reviewing a teammate's branch
- **WHEN** local `<name>` tracks `origin/<name>`, then `git worktree add ../<project>-<name> <name>` runs
- **THEN** the sibling HEAD equals the teammate's branch tip

### Requirement: Agent worktree operating rules
The system SHALL follow one dev server per checkout, `portless list` as the URL source of truth (branch `/` names are sanitized in subdomains), stop-before-remove (Ctrl+C first, then `remove`), review-before-delete, and squash-on-merge.

#### Scenario: Second server on a served checkout fails fast
- **WHEN** a second `pnpm run dev` targets an already-served checkout URL
- **THEN** it fails with the "already registered by PID" signal and the operator opens the existing URL instead of starting a duplicate server
```

## `scripts/` note (reference-only default)

`validate-imports` / `validate-i18n` / `validate-markdown` are documented in
[astro-base-config](./astro-base-config.md) §3 as an opt-in `tsx` chain.
Their bodies are per-project (they scan that project's `src/` layout) and
are intentionally **not** templated here — keep the chain reference, write
bodies when the layer lands. `check:palette` is project-specific (token
setup), not worktree core — same rule.
