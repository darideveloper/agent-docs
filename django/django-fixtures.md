---
created: 2026-08-09
updated: 2026-08-09
tags:
  - django
  - fixtures
  - loaddata
  - base-data
  - seed-data
  - documentation
type: resource
status: active
source: templates://django/django-fixtures.md
version: 2026-09-17+4cf710f

---

# Fixed Data Loading with Django Fixtures (Core, English Default)

## Goal

This document explains a reusable pattern for loading **fixed (read-only reference) data**
into a Django project using fixtures. The pattern was designed so it can be ported to any
other Django project with **different models and different data**.

It covers:

- Where fixture files live and how they are formatted.
- The `FIXTURE_DIRS` settings hook.
- Thin management commands that wrap Django's `loaddata`.
- Load ordering and dependency resolution (FK / M2M relations).
- Where to invoke the load in tests, builds, and deploys.
- A full worked example with sample (non-project-specific) data.

---

## 1. Concept

Django's `loaddata` management command reads one or more JSON (or XML/YAML) files —
*fixtures* — and inserts/updates rows using explicit primary keys and explicit
timestamps, regardless of any `auto_now` / `auto_now_add` on the model fields.

The pattern used here consists of:

1. One JSON file **per model**, grouped inside a directory.
2. A `FIXTURE_DIRS` setting pointing at that directory.
3. Small wrapper commands, located in the loader app `<MAIN_APP>` (example `core`), that auto-discover and load **all** fixtures from **every** installed
   app — no per-app commands, no list to maintain.
4. Splitting the data into **two tiers** with different lifecycle rules:

   | Tier | Command | Lifecycle |
   |------|---------|-----------|
   | **Base data** | `base_loaddata` | Reference/lookup rows the app needs to function (categories, grades, statuses). **Always loaded** — at every container startup / deploy, in every new environment, and in tests. |
   | **Seed data** | `seed_loaddata` | Optional one-time data (sample users, demo records). **Loaded once**, manually, per environment. Never in the production build. |

   Dependency considerations still apply within each tier: a fixture that references
   another model's PKs must load after its dependencies. Seed data frequently
   references base PKs, so `base_loaddata` also always runs first.

---

## 2. Project structure

```
<project_root>/
├── core/                       # main project app — the loader commands live here
│   └── management/
│       └── commands/
│           ├── base_loaddata.py    # loads ALL base fixtures from ALL apps
│           └── seed_loaddata.py    # loads ALL seed fixtures from ALL apps
│
└── catalog/                    # a domain app (any number of apps)
    └── fixtures/
        └── catalog/
            ├── Category.json        # base data
            ├── Grade.json           # base data
            └── seed/                # one-time seed data
                ├── 00_Author.json       # numeric prefix: loads before dependents
                ├── 01_Book.json         # references Author PKs
                ├── images/              # committed sample media, synced to storage
                │   └── covers/
                │       └── book-1.jpg
                └── User.json
```

The pattern uses **two** commands. Both live in the main project app (`core`) and
each one automatically loads **all** fixtures from **every** installed app, split
by data lifecycle:

| Command | Location | When it runs | What it loads |
|---------|----------|-------------|---------------|
| `base_loaddata` | `<MAIN_APP>/management/commands/` | Always — every deploy / container startup and test run | All `<app>/fixtures/<app>/` base files (reference/lookup rows) |
| `seed_loaddata` | `<MAIN_APP>/management/commands/` | Once — manually, per environment | All `<app>/fixtures/<app>/seed/` files (sample users, demo records) |

Because the commands live in one place and scan every installed app, adding a new
app (or a new fixture file) requires **no changes** to the loader. The base/seed
split also guarantees dependency order: seed rows that reference base PKs are
loaded after them.

---

## 3. Settings

Add your fixture directory to `FIXTURE_DIRS`:

```python
# project/settings.py — OPTIONAL. Django auto-discovers `<app>/fixtures/`, so this is explicit-only.
FIXTURE_DIRS = [
    os.path.join(BASE_DIR, "<APP_LABEL>", "fixtures", "<APP_LABEL>"),
]
```

Notes:

- By default, Django already searches `<each_app>/fixtures/` for fixture files, so
  `<APP_LABEL>/fixtures/<APP_LABEL>/<Model>.json` is found even without `FIXTURE_DIRS`.
  Setting `FIXTURE_DIRS` explicitly is optional but makes the location explicit.

---

## 4. Fixture file format

Standard Django fixture JSON: a list of objects with `model`, `pk`, and `fields`.

```json
[
  {
    "model": "catalog.Book",
    "pk": 1,
    "fields": {
      "title": "Example Book",
      "category": 1,
      "available": true,
      "created_at": "2026-01-01T00:00:00Z",
      "updated_at": "2026-01-01T00:00:00Z"
    }
  }
]
```

Rules observed in the reference implementation:

- **One file per model** named `<ModelName>.json` (Django convention: camel-case
  class name).
- **Explicit PKs** (`pk`). AutoField would normally generate PKs, but explicit PKs
  let other fixtures reference them (`FK`, `M2M`) and make the data reproducible.
- **Timestamps explicitly set.** Even if the model uses `auto_now`/`auto_now_add`,
  `loaddata` honors explicit values, so the fixture rows get deterministic dates.
- **M2M fields as a list of PKs:** ManyToMany fields are stored as a list of PKs:
  ```json
  { "grades": [1, 2] }
  ```
- FKs are just the referenced PK (e.g. `"author": 1`).
- `null`/`blank` JSON fields are omitted or set to `null`/`{}` as required.
- File contents are **JSON only** (no comments allowed).

---

## 5. Wrapper commands

The two commands are intentionally small and nearly identical.

### `base_loaddata.py` (always-loaded reference data)

Both commands live in the main project app and scan **every** installed app. There
is no fixed list to maintain — files are discovered.

```python
# <MAIN_APP>/management/commands/base_loaddata.py
import os

from django.apps import apps
from django.core.management.base import BaseCommand
from django.core.management import call_command

BASE_FILE = os.path.basename(__file__)


class Command(BaseCommand):
    help = "Load ALL base fixtures from ALL apps (run in every build, deploy, test)"

    def handle(self, *args, **options):
        for app_config in apps.get_app_configs():
            fixture_dir = os.path.join(app_config.path, "fixtures", app_config.label)
            for fixture in self._find_fixtures(fixture_dir):
                try:
                    call_command("loaddata", f"{app_config.label}/{fixture}")
                except Exception as exc:  # noqa: BLE001
                    print(f"Error in {BASE_FILE}: {exc}")  # fail-soft for deploys; use --failfast/CI strict mode when debugging
                    continue

    def _find_fixtures(self, fixture_dir):
        if not os.path.isdir(fixture_dir):
            return []
        return sorted(
            name[:-5] for name in os.listdir(fixture_dir) if name.endswith(".json")
        )
```

### `seed_loaddata.py` (one-time sample/seed data)

```python
# <MAIN_APP>/management/commands/seed_loaddata.py
import os

from django.apps import apps
from django.core.files.storage import default_storage
from django.core.management.base import BaseCommand
from django.core.management import call_command

BASE_FILE = os.path.basename(__file__)


class Command(BaseCommand):
    help = "Load ALL seed fixtures from ALL apps (run once per environment)"

    def handle(self, *args, **options):
        for app_config in apps.get_app_configs():
            self._sync_seed_media(app_config)
            fixture_dir = os.path.join(
                app_config.path, "fixtures", app_config.label, "seed"
            )
            for fixture in self._find_fixtures(fixture_dir):
                try:
                    call_command("loaddata", f"{app_config.label}/seed/{fixture}")
                except Exception as exc:  # noqa: BLE001
                    print(f"Error in {BASE_FILE}: {exc}")  # fail-soft for deploys; use --failfast/CI strict mode when debugging
                    continue

    def _find_fixtures(self, fixture_dir):
        if not os.path.isdir(fixture_dir):
            return []
        return sorted(
            name[:-5] for name in os.listdir(fixture_dir) if name.endswith(".json")
        )

    def _sync_seed_media(self, app_config):
        images_dir = os.path.join(
            app_config.path, "fixtures", app_config.label, "seed", "images"
        )
        if not os.path.isdir(images_dir):
            return
        for root, _, files in os.walk(images_dir):
            for name in files:
                source_path = os.path.join(root, name)
                relative_path = os.path.relpath(source_path, images_dir)
                if default_storage.exists(relative_path):
                    continue
                with open(source_path, "rb") as source_file:
                    default_storage.save(relative_path, source_file)
```

Key points to keep when porting:

1. **One loader, centrally located.** Both commands sit in the loader app (`<MAIN_APP>`). Each app is responsible only for its own fixture files, never for
   loader code.
2. **Auto-discovery.** `apps.get_app_configs()` iterates all installed apps; the
   command loads every `*.json` file found in each app's fixture directory. Adding
   a new app or fixture requires **zero changes** here.
3. **`call_command("loaddata", f"{app_label}/{FixtureName}")`** — the `app_label/`
   prefix tells `loaddata` to look for the file in the app's fixture dirs
   (`<app>/fixtures/<app>/`), so `base` resolves base files and `.../seed/` resolves
   seed files.
4. **Fail-soft loop** — each fixture is loaded in a `try/except` and failures are
   printed and skipped. This lets partial loads succeed instead of aborting the
   whole chain (useful when a fixture already exists, e.g. re-running a seed).
5. **Ordering within an app** — files load in sorted (alphabetical) order. If one
   base fixture references another's PKs, prefix the filenames with a numeric
   index (`00_` , `01_`) so the referenced file loads first.
6. **Seed media** — sample media files (e.g. placeholder artwork images) are
   committed under each app's `<app>/fixtures/<app>/seed/images/` directory and
   written into the configured default storage (local `MEDIA_ROOT` or remote
   bucket) by `seed_loaddata` before the fixtures load, so seeded image records
   reference readable files. Files already present in storage are left untouched.

---

## 6. Ordering and dependencies

`loaddata` inserts rows in the order they appear. If a fixture references a PK that
does not exist yet, the command fails with a ForeignKey/M2M integrity error.

Ordering matters for **two** reasons:

1. **Dependency order within `loaddata`** — referenced PKs must be loaded first
   (FK / M2M resolution).
2. **Lifecycle order across tiers** — base data is always loaded first because
   seed rows frequently reference base PKs.

```
1st call: base_loaddata  → Category.json, Grade.json (reference/lookup data)
2nd call: seed_loaddata  → Book.json, User.json (sample/one-time data)
```

Base data is required by tests; seed data usually is not. Tests load only the base
tier unless a specific test needs sample users/rows:

```python
# in a TestCase setUp
call_command("base_loaddata")

# only if this test needs demo/seed records:
# call_command("seed_loaddata")
```

> Convention warning: because `loaddata` matches rows by their explicit PKs, a
> re-run **updates** the existing rows in place rather than inserting duplicates.
> The commands catch and continue on any unexpected per-fixture failure.
> `base_loaddata` is meant to run against fresh databases (fresh DB, test DB, new
> container) on every startup. `seed_loaddata` should be run **once** per
> environment — re-running it on a populated database is harmless but repeats the
> same row updates.

---

## 7. How to run it

```bash
# Base data — run on EVERY environment and EVERY deploy (required to work)
python manage.py base_loaddata

# Seed data — run ONCE per environment, only when sample/demo data is wanted
python manage.py seed_loaddata

# Or the underlying Django commands directly
python manage.py loaddata catalog/Category
python manage.py loaddata catalog/seed/Book
```

### In tests

Call `base_loaddata` in `setUp` or module-level fixture helpers so every test runs
against the required fixed data. Only load `seed_loaddata` in the tests that
specifically need the sample records. Tests run against whatever DB `IS_TESTING`
selects, so the fixture approach is data-agnostic.

### In Docker (container runtime)

`base_loaddata` must run **after `migrate`** and against a database the app can
reach. A Docker **image build** has no database yet, so the load cannot happen
with `RUN` inside the `Dockerfile` — it belongs in the **container entrypoint
script** (e.g. `start.sh` / `entrypoint.sh`), which runs on every container start:

```bash
# start.sh (or entrypoint.sh), run on every container start
python manage.py migrate
python manage.py base_loaddata
# NOTE: do NOT run seed_loaddata here. Base data is required for the system to
# work, so it is always applied. Seed data (sample users, demo records) is
# environment-specific and should be loaded once manually, per environment —
# never at startup and never in the image build.
```

If you prefer a separate `web`/`worker` role split, run `base_loaddata` in the
entrypoint of the role that owns first-boot (typically the web role), and keep
the other roles starting idempotently.

Common mistake: treating seed data like base data. Forgetting `base_loaddata` in
the entrypoint while the app code assumes fixed rows already exist breaks
the system; adding `seed_loaddata` to the entrypoint pollutes every instance with
sample data and fails on restarts (duplicate keys). Decide explicitly: **base =
always (every startup)**, **seed = once (manual)**.

---

## 8. Worked example (book store, sample data)

This example is fully generic — you can rename app/model and replace the data. It
shows both tiers: `Category` and `Grade` are **base data** (always loaded); `Book`
and a sample `auth.User` are **seed data** (loaded once, e.g. in a dev or demo
environment).

Models (`catalog/models.py`):

```python
# Worked example only (book store). Real models must follow [[django-model-definitions]].
class Category(models.Model):
    name = models.CharField(max_length=255, verbose_name="Name")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="Created at")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="Updated at")

    def __str__(self):
        return self.name

    class Meta:
        verbose_name = "Category"
        verbose_name_plural = "Categories"


class Grade(models.Model):  # lookups used by others
    name = models.CharField(max_length=255, verbose_name="Name")

    def __str__(self):
        return self.name

    class Meta:
        verbose_name = "Grade"
        verbose_name_plural = "Grades"


class Book(models.Model):
    title = models.CharField(max_length=255, verbose_name="Title")
    category = models.ForeignKey(Category, on_delete=models.CASCADE, verbose_name="Category")
    grades = models.ManyToManyField(Grade, blank=True, verbose_name="Grades")
    available = models.BooleanField(default=False, verbose_name="Available")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="Created at")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="Updated at")

    def __str__(self):
        return self.title

    class Meta:
        verbose_name = "Book"
        verbose_name_plural = "Books"
```

### Base data — `Category.json`, `Grade.json`

Reference/lookup rows the app needs at runtime.

Fixture `catalog/fixtures/catalog/Category.json`:

```json
[
  {
    "model": "catalog.Category",
    "pk": 1,
    "fields": {
      "name": "Science",
      "created_at": "2026-01-01T00:00:00Z",
      "updated_at": "2026-01-01T00:00:00Z"
    }
  },
  {
    "model": "catalog.Category",
    "pk": 2,
    "fields": {
      "name": "History",
      "created_at": "2026-01-01T00:00:00Z",
      "updated_at": "2026-01-01T00:00:00Z"
    }
  }
]
```

Fixture `catalog/fixtures/catalog/Grade.json`:

```json
[
  {
    "model": "catalog.Grade",
    "pk": 1,
    "fields": {"name": "Beginner"}
  }
]
```

### Seed data — `seed/00_Author.json`, `seed/01_Book.json`, `seed/User.json` (worked example)

Optional one-time rows, kept in a `seed/` subfolder. Sample books reference base
PKs (category, grades); a sample user uses Django's built-in `auth.User`. When a
seed fixture depends on another seed fixture's PKs, prefix the filenames with a
zero-padded numeric index so the alphabetical sort loads dependencies first
(e.g. `00_Author.json` before `01_Book.json` — the structure diagram above shows this naming). Sample media files are committed
under `seed/images/` and copied into the configured default storage by
`seed_loaddata`.

Fixture `catalog/fixtures/catalog/seed/01_Book.json` (numbered so `00_Author.json` loads first):

```json
[
  {
    "model": "catalog.Book",
    "pk": 1,
    "fields": {
      "title": "Planets of the Solar System",
      "category": 1,
      "grades": [1],
      "available": true,
      "created_at": "2026-01-02T00:00:00Z",
      "updated_at": "2026-01-02T00:00:00Z"
    }
  }
]
```

Fixture `catalog/fixtures/catalog/seed/User.json` (sample user, loaded once). The
`seed/` subfolder is what `seed_loaddata` scans, so no `auth/` prefix is needed
in the path. Verify resolution with `python manage.py loaddata catalog/seed/User --verbosity=2` after adding (the `app_label/seed/Name` form must resolve through the app's `fixtures/` dir):

```json
[
  {
    "model": "auth.User",
    "pk": 1,
    "fields": {
      "username": "demo",
      "password": "pbkdf2_sha256$720000$AbCdEf...",
      "is_active": true,
      "date_joined": "2026-01-03T00:00:00Z"
    }
  }
]
```

> Users carry a password **hash**, not a plaintext password. Generate a fixture the
> safe way: `python manage.py shell` → `user.set_password("...")` → `save()`, then
> `python manage.py dumpdata auth.User --pk 1` and copy the `password` hash. See
> section 9.

No load plan needs to be maintained — the commands in `<MAIN_APP>/management/commands/`
discover these files automatically.

Run order:

```console
$ python manage.py base_loaddata   # loads Category + Grade (required)
$ python manage.py seed_loaddata   # loads Book + sample User (once, optional)
```

---

## 9. Switching to your own data/model

To port this pattern to another project:

1. Create the directory structure: `<app>/fixtures/<app>/` for base data and
   `<app>/fixtures/<app>/seed/` for one-time seed data.
2. Create one JSON file per model that holds fixed data, with explicit `pk`s.
3. Reference FKs by their PK; write M2M fields as a list of PKs.
4. Put the two loader commands in the loader app (`<MAIN_APP>/management/commands/`, e.g. `core`).
   They auto-discover every installed app, so no list needs to be maintained.
5. Call `base_loaddata` in tests and in the deploy pipeline — at **container
   runtime** in the entrypoint script right after `migrate` (never during the
   Docker image build, since no database exists there). Run `seed_loaddata`
   **once**, manually, only where demo data is wanted — the fail-soft loop makes
   re-running it on a populated DB harmless.
6. Drop fixture files into the right folder and they are loaded automatically.

**Conventions observed in practice**

- Keep the fixture files **outside** the migrations path (they should not be applied
  when running `makemigrations`, only when you explicitly run loaddata).
- No `dumpdata` is used — fixtures are authored/versioned by hand. If you go that
  route, use `dumpdata app.Model` then review the output for non-repeatable fields
  (absolute paths, generated values).
- Keep timestamps explicit for determinism even when `auto_now` exists.
- When `JSONField` exists, provide it if mandatory (eg `data: {}`), or omit if
  blank/null.

---

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `No fixture named 'Category' found` | Wrong `app_label/` prefix or file not under an app `fixtures/` dir | Verify the file is at `<app>/fixtures/<app>/<Model>.json` and pass `f"{app_label}/{Model}"` |
| `duplicate key value violates unique constraint` | PKs already exist in DB | `loaddata` matches rows by explicit PK, so re-running updates them in place instead of failing; to force a clean reload, clear the existing rows first. Common when `seed_loaddata` is run twice — seeds are one-time but re-runs are harmless no-ops |
| `Foreign key constraint failed` / M2M ordering error | Referenced PK not loaded yet, or wrong order within an app | Run `base_loaddata` (dependencies) **before** `seed_loaddata`; within an app, prefix filenames numerically (`00_` before `01_`) so referenced files load first |
| Wrong PKs when referencing other fixtures | Explicit PK mismatch | Keep `pk` values coordinated across all referencing files |
| User cannot log in after `seed_loaddata` | Fixture stored a wrong/plaintext password | Regenerate the user fixture via `set_password()` + `dumpdata` (section 8) |
| Seed data appears in production | `seed_loaddata` added to the build/deploy pipeline | Remove it — seed data is per-environment and should run once manually |

---

## 11. Summary

- Each model has its own, hand-owned JSON fixture with explicit PKs.
- Two thin commands live in the loader app (`<MAIN_APP>`) and auto-discover
  every installed app:
  - `base_loaddata` — always-loaded reference data (every deploy / container
    startup, every new environment, tests), reading `<app>/fixtures/<app>/`.
  - `seed_loaddata` — one-time sample/seed data, run manually per environment,
    reading `<app>/fixtures/<app>/seed/`.
- Whether a row is **always** vs **once** determines which folder it belongs to.
- Adding an app or fixture requires no changes to the loader code.
- Ordering is the only real dependency requirement; base always runs first.
- Porting requires replacing model/file names and content; the loader code itself
  is model-agnostic.