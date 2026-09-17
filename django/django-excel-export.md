---
created: 2026-09-03
updated: 2026-09-03
tags:
  - django
  - admin
  - unfold
  - excel
  - openpyxl
type: resource
status: active
source: templates://django/django-excel-export.md
version: 2026-09-17+unreleased

---

# Django Excel Export Integration (Optional, English Default)

> **Purpose:** Reusable, app-agnostic guide for integrating Excel export into **any** Django project / **any** app. Replace placeholders `<APP_LABEL>`, `<APP_MIXIN>`, `<APP_BASE>` and `project` throughout. Covers architecture, files, dependencies, admin wiring, workbook logic, formatting, permissions, and required fixes.

**Placeholders:**

| Placeholder | Meaning |
|-------------|---------|
| `<APP_LABEL>` | Django `app_label` to export (e.g. `store`) |
| `<APP_MIXIN>` | Header-action mixin class (e.g. `StoreExportMixin`) |
| `<APP_BASE>` | App base class = mixin + bulk base (e.g. `StoreModelAdminBase`) |
| `project` | Project package (e.g. `project`, `myproject`) |

---

## 1. Overview

The integration adds **three admin export modes** to a Django project using `django-unfold` + `openpyxl`:

| Mode | UI | Route | Data |
|------|----|-------|------|
| **Export to Excel** | Bulk action `Actions` dropdown (changelist) | `POST …/changelist/ {action: export_selected}` | Selected rows, single sheet |
| **Export to Excel (with related)** | Bulk action (same dropdown) | `POST …/changelist/ {action: export_selected_with_related}` | Selected rows + one sheet per forward FK target (referenced rows only) |
| **Export all app data** | Header button (changelist + changeform) | `GET …/export_all/` (list) and `GET …/<id>/export_all/` (detail) | All rows of every model in one `app_label` (deterministic order) |

**Stack:** Django 5.2, `django-unfold==0.77.1` (pinned), `openpyxl>=3.1,<3.2`, `django-solo` only if singletons.

**Outputs:** `.xlsx` with `Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` and RFC 5987 `filename*=utf-8''` disposition, header styling (generic blue, bold, frozen `A2`), banded rows, auto-sized columns (cap 50, scale 1.2), Decimal `#,##0.00`, Excel sheet-name sanitization.

---

## 2. Architecture

```
┌──────────────────────────────┐
│  project/admin_base.py  │  Export flavor of admin bases (separate from unfold plain flavor)
│  ├─ ModelAdminUnfoldBase     │  Export flavor: Unfold ModelAdmin + edit row action + bulk exports
│  ├─ <APP_MIXIN>              │  Header action: export_all
│  └─ <APP_BASE>               │  Mixin + base, actions_list/detail
└──────────────┬───────────────┘
               │ inherits
     ┌─────────┴──────────┐
     │ <APP_LABEL>/admin.py │  ModelAdmins: regular + singleton
     │                     │  (Singleton = SingletonModelAdmin + mixin + base)
     └─────────┬──────────┘
               │ calls
     ┌─────────┴──────────┐
     │ utils/excel_export.py│  Pure utils, no admin coupling
     │ ├─ columns_for_model │  FK → 2 cols, else 1 col
     │ ├─ serialize_value   │  Excel-native primitives
     │ ├─ build_workbook…   │  select_related + iterator, sheet reuse
     │ ├─ build_full_app…   │  apps.get_models() sorted discovery by <APP_LABEL>
     │ ├─ style_sheet       │  header/banded/freeze
     │ ├─ autosize_columns  │
     │ ├─ sanitize_sheet…   │
     │ └─ _primary_color    │  Generic blue fallback, OperationalError guard
     └─────────┬──────────┘
               │ HttpResponse
     ┌─────────┴──────────┐
     │ utils/test_…       │  Sanitization, serialization, workbook, permissions, admin POST
     └────────────────────┘

Header rendering (Unfold):
change_form.html nav-global → change_form_object_tools → userlinks.html action_list → tab_actions.html <ul> (nav_global + actions_detail)
changelist.html object-tools → tab_actions.html <ul> (actions_list)
```

**File map (local copy, no external source):**

| Path | Role |
|------|------|
| `requirements.txt` | `openpyxl>=3.1,<3.2` |
| `project/admin_base.py` | Export flavor: `ModelAdminUnfoldBase` (+ bulk exports), `<APP_MIXIN>`, `<APP_BASE>` + `_excel_response` |
| `utils/excel_export.py` | All workbook logic |
| `utils/test_excel_export.py` | Covers helpers + admin + permissions |
| `<APP_LABEL>/admin.py` | Singleton MRO, app ModelAdmins |
| `project/templates/admin/solo/change_form.html` | Override solo raw history → `tab_action.html` — only if `django-solo` used |
| `project/templates/unfold/helpers/tab_actions.html` | Override stock `<ul>` + `gap-2` / `lg:gap-2` |
| `openspec/specs/excel-export/spec.md` | Spec — 5 requirements, scenarios (optional, create per project) |
| `AGENTS.md` | Convention: inherit correct base to get export |

---

## 3. Dependencies

Add to `requirements.txt`:

```
openpyxl>=3.1,<3.2  # Excel xlsx with styling; pin minor to avoid breakage (Unfold is pinned)
# already required: Django>=5.2,<5.3, django-unfold==0.77.1, django-solo>=2.3.0 if singletons
```

Install (manual step): `pip install -r requirements.txt` or `pip install "openpyxl>=3.1,<3.2"`.

---

## 4. Core Utility — `utils/excel_export.py`

### 4.1 Header color + fallback (generic)

```python
FALLBACK_COLOR = "#2563EB"  # generic blue (blue-600); replace with your brand hex if needed

def _primary_color():
    # Option A: fixed brand color (simplest, no DB) — default
    # return FALLBACK_COLOR
    # Option B: dynamic from your model (uncomment and replace import)
    try:
        from <YOUR_BRAND_APP>.models import <YourBrand>  # e.g. core.models.Brand
        brand = <YourBrand>.get_or_create_default()     # or .objects.first() / settings.HEADER_COLOR
        color = getattr(brand, "primary_color", None)
        if color:
            return color
    except (OperationalError, ProgrammingError):
        pass  # table missing during migrate/collectstatic — fallback required
    except Exception:
        pass
    return FALLBACK_COLOR
```

**Reuse:** Default is generic blue constant. If your project has a brand/theming table, uncomment Option B and adapt the import. The `OperationalError`/`ProgrammingError` guard is critical — without it `migrate`/`collectstatic` fails when the color table does not yet exist.

### 4.2 Sheet name sanitization

- Replaces `:\/?*[]` → `_`, strips leading/trailing `'`, fallback `"Sheet"`, truncates to 31, deduplicates via `_2`, `_3` (preserving 31-char limit).
- API: `sanitize_sheet_name(name, existing=set())`.

### 4.3 Value serialization — `serialize_value(field, obj)`

| Field type | Excel value |
|------------|-------------|
| File/ImageField | `value.name` or `value.url` |
| JSONField | `json.dumps(value)` |
| BooleanField | `bool` |
| DecimalField | `float(value)` + `cell.number_format = '#,##0.00'` in `style_sheet` |
| Integer/AutoField variants | `int` |
| DateTimeField | `datetime` (tz stripped) |
| DateField/TimeField | native |
| Char/Text/Slug/URL/Email | `str` |
| `None`/empty | blank cell |

### 4.4 Columns for a model — `columns_for_model(model)`

For `model._meta.concrete_fields`:

- **FK/OneToOne (not auto_created):** two columns
  `f"{field.name}__str__"` → `str(getattr(obj, field.name))` (blank if `None`)
  `field.attname` (e.g. `project_id`) → `getattr(obj, field.attname)`
- **Else:** one column header = `verbose_name` fallback `field.name`, value = `serialize_value`.

Each entry is `(header, getter, field)` where `getter(obj)` is closure.

### 4.5 Related targets — `get_related_targets(model)`

Distinct forward `ForeignKey`/`OneToOneField` targets (single hop, no reverse/M2M). Used to decide related sheets.

### 4.6 Styling

`style_sheet(ws)`:
- Header fill `argb = FFG{primary_color}` (invalid → `FF2563EB`), font `FFFFFF bold 11pt`, `Alignment(center)`, `Border(bottom thin #D1D5DB)`.
- Banded rows: `#F9FAFB`/`#FFFFFF`, floats → `#,##0.00`.
- `ws.freeze_panes = "A2"`.

`autosize_columns(ws)`: `width = clamp(10, 50, max_len*1.2 + 2)`.

### 4.7 Workbook building

```python
def build_workbook_for_queryset(model, queryset, include_related=False, existing_workbook=None):
def build_full_app_workbook(app_label="<APP_LABEL>"):  # pass your app_label or use constant APP_LABEL = "<APP_LABEL>"
```

- `_get_or_create_sheet(wb, title, existing_names)` reuses default empty `Sheet` on fresh `Workbook()`, else creates sanitized sheet.
- `_write_sheet_for_model(wb, model, queryset, existing_names)` writes headers, `select_related(*fk_names)` if available, iterates via `qs.iterator()` (or `iter(qs)`), appends rows, calls `style_sheet` + `autosize_columns`.
- `include_related=True`: groups FK fields by target `label`, collects `distinct_ids` via `queryset.values_list(attname, flat=True)` (fallback iterates), then `target.objects.filter(pk__in=distinct_ids)` (or `.none()` if empty) → `_write_sheet_for_model` per target (single hop, no transitive).
- Removes placeholder `Sheet` if other sheets exist.
- `build_full_app_workbook(app_label="<APP_LABEL>")` discovers `m for m in apps.get_models() if m._meta.app_label == app_label` sorted by `model_name`, calls `_write_sheet_for_model` per model with `model.objects.all()`.

**Perf:** `select_related` avoids N+1 for FK `__str__`; `.iterator()` streams.

---

## 5. Admin Bases — `project/admin_base.py` (one file, separate export flavor of `ModelAdminUnfoldBase`)

### 5.1 Response helper

```python
def _excel_response(workbook, filename):
    buf = BytesIO(); workbook.save(buf); buf.seek(0)
    quoted = quote(filename)
    response = HttpResponse(buf.getvalue(),
        content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    response["Content-Disposition"] = f'attachment; filename="{filename}"; filename*=utf-8\'\'{quoted}'
    return response
```

RFC 5987 `filename*` required for non-ASCII file names.

### 5.2 Base for all models — `ModelAdminUnfoldBase`

```python
from unfold.admin import ModelAdmin
from unfold.decorators import action

class ModelAdminUnfoldBase(ModelAdmin):
    sidebar_icon = "database"
    compressed_fields = True
    warn_unsaved_form = True
    list_filter_sheet = False
    change_form_show_cancel_button = True
    actions_row = ["edit"]
    actions = ["export_selected", "export_selected_with_related"]

    @action(description="Edit", permissions=["change"])
    def edit(self, request, object_id):
        return redirect(reverse(f"admin:{self.model._meta.app_label}_{self.model._meta.model_name}_change", args=[object_id]))

    @action(description="Export to Excel", icon="download", permissions=["view"])
    def export_selected(self, request, queryset):
        if not queryset.exists(): 
            self.message_user(request, "Select at least one row to export.", messages.WARNING)
            return None
        from utils.excel_export import build_workbook_for_queryset
        wb = build_workbook_for_queryset(self.model, queryset, include_related=False)
        ts = datetime.now().strftime("%Y%m%d_%H%M")
        filename = f"{self.model._meta.model_name}_{ts}.xlsx"
        return _excel_response(wb, filename)

    def has_export_selected_permission(self, request, obj=None):
        return self.has_view_permission(request, obj)

    @action(description="Export to Excel (with related)", icon="download", permissions=["view"])
    def export_selected_with_related(self, request, queryset):
        # same guard, with include_related=True
        ...

    def has_export_selected_with_related_permission(self, request, obj=None):
        return self.has_view_permission(request, obj)
```

**Why `view` not `change`:** keeps export visible on read-only models (e.g. models with `has_change_permission=False` but `view` allowed).

**Why bulk `actions` not header:** bulk actions receive checkbox-selected `queryset`; header actions don't.

### 5.3 Full-app header action — mixins (generic)

```python
class <APP_MIXIN>:
    @action(description="Export all app data", icon="download", variant="default", permissions=["export_all"])
    def export_all(self, request, object_id=None, *args, **kwargs):
        from utils.excel_export import build_full_app_workbook
        wb = build_full_app_workbook(app_label="<APP_LABEL>")
        ts = datetime.now().strftime("%Y%m%d_%H%M")
        filename = f"<APP_LABEL>_full_export_{ts}.xlsx"
        return _excel_response(wb, filename)

    def has_export_all_permission(self, request, obj=None, *args, **kwargs):
        user = getattr(request, "user", None)
        if not user or not getattr(user, "is_staff", False):
            return False
        return user.has_module_perms("<APP_LABEL>")  # Django's per-app perm; no object perm needed

class <APP_BASE>(<APP_MIXIN>, ModelAdminUnfoldBase):
    actions_list = ["export_all"]    # changelist header (Unfold)
    actions_detail = ["export_all"]  # changeform header — critical for SingletonModelAdmin (no changelist)
```

**Unfold generates URLs** from `actions_list` → `export_all/` (no id) and `actions_detail` → `<path:object_id>/export_all/` (with id), wrapped in `admin_site.admin_view`. Do **not** add manual `get_urls`.

### 5.4 ModelAdmin wiring

```python
from project.admin_base import <APP_BASE>, ModelAdminUnfoldBase, <APP_MIXIN>
from solo.admin import SingletonModelAdmin  # only if the app has a singleton model

# Regular app member — gets bulk exports + header export
@admin.register(Project)
class ProjectAdmin(<APP_BASE>):
    sidebar_icon = "folder"
    list_display = ("name", "description")
    # ...

# Singleton example — header only (no changelist for bulk)
@admin.register(AppSettings)
class AppSettingsAdmin(SingletonModelAdmin, <APP_MIXIN>, ModelAdminUnfoldBase):
    actions_list = ["export_all"]
    actions_detail = ["export_all"]
    # SingletonModelAdmin must be first in MRO; mixin supplies header action

# Non-app models: keep ModelAdminUnfoldBase so header button never appears outside <APP_LABEL>
@admin.register(Brand)
class BrandAdmin(ModelAdminUnfoldBase): ...
```

If a third-party admin already inherits a base (e.g. `BaseTokenAdmin`), put `ModelAdminUnfoldBase` first in MRO: `class TokenAdmin(ModelAdminUnfoldBase, BaseTokenAdmin):`.

**Convention (`AGENTS.md`):** New models → inherit `ModelAdminUnfoldBase` (auto bulk exports); `<APP_LABEL>` members → inherit `<APP_BASE>` (also header export). `build_full_app_workbook(app_label="<APP_LABEL>")` discovers via `apps.get_models()` filtered by `app_label`, sorted — no per-model wiring, new `<APP_LABEL>` models appear automatically after registration. Keep all bases/mixins in single file `project/admin_base.py`.

---

## 6. Required Fixes (include when reusing)

### Fix A — Header overlap: History vs Export on singleton

> **Note:** Only needed if you use `django-solo` + `django-unfold` together. If you have no solo singleton, skip the `admin/solo/change_form.html` override and keep only the `unfold/helpers/tab_actions.html` gap fix if you want the spacing.

**Symptom:** At singleton changeform header shows `History` + `Export all app data` overlapping (buttons touching, text colliding).

**Root cause:** `solo/templates/admin/solo/change_form.html` overrides `object-tools-items` with raw `<li><a class="historylink">History</a></li>` (no Unfold `action_item_classes`). Unfold's `tab_actions.html` renders `nav_global` (History) and `actions_detail` (Export) in same flex `<ul>`; Export's `min-lg:-ml-px` expects styled sibling, so it collapses over History.

**Fix:** Two template overrides (both in `project/templates`, taking precedence via `TEMPLATES[0].DIRS = [BASE_DIR / "project" / "templates"]`):

1. `project/templates/admin/solo/change_form.html` — copy of solo stock, but replace `object-tools-items` with Unfold helper:
   ```django
   {% extends "admin/change_form.html" %}
   {% load i18n admin_urls %}
   {% block breadcrumbs %}
   {% if skip_object_list_page %}<div class="breadcrumbs">…{{ opts.app_config.verbose_name }}…{{ opts.verbose_name|capfirst }}</div>{% else %}{{ block.super }}{% endif %}
   {% endblock %}
   {% block object-tools-items %}
     {% if show_history %}
       {% url opts|admin_urlname:'history' original.pk|admin_urlquote as history_url %}
       {% trans 'History' as title %}{% add_preserved_filters history_url as link %}
       {% include "unfold/helpers/tab_action.html" with title=title link=link icon="history" %}
     {% endif %}
     {% if has_absolute_url and show_view_on_site %}
       {% trans 'View on site' as title %}
       {% include "unfold/helpers/tab_action.html" with title=title link=absolute_url blank=1 icon="open_in_new" %}
     {% endif %}
   {% endblock %}
   ```
   Matches `unfold/templates/admin/change_form_object_tools.html`.

2. `project/templates/unfold/helpers/tab_actions.html` — copy stock with `gap-2` / `lg:gap-2` on header `<ul>`:
   ```html
   <ul class="bg-white container hidden flex-col gap-2 ... lg:flex lg:flex-row lg:gap-2 ...">
   ```
   Gives small spacing at desktop (`row`) and mobile (`flex-col` hamburger `max-lg:flex`), vertical centering via existing `flex flex-row items-center` parent. No custom CSS/JS.

### Fix B — `export_all` TypeError on detail route

**Symptom:** `GET /admin/<APP_LABEL>/model/<id>/export_all/` → `TypeError: got an unexpected keyword argument 'object_id'`; changelist header worked.

**Root cause:** Strict `export_all(self, request)`; Unfold's `actions_detail` wraps handler as `<path:object_id>/export_all/` and forwards `object_id` as kwarg (`unfold/decorators.py`, `unfold/admin.py`). `has_export_all_permission` similarly receives `object_id` for detail.

**Fix:** Permissive signature:

```python
def export_all(self, request, object_id=None, *args, **kwargs):  # body ignores object_id (app-wide)
def has_export_all_permission(self, request, obj=None, *args, **kwargs):
```

**When to apply:** Always when using `actions_detail` (needed for singleton changeform).

### Fix C — Related sheets referenced-only

Already implemented (design): `include_related=True` collects `distinct_ids` per target via `values_list(attname, flat=True)`, then `target.objects.filter(pk__in=distinct_ids)` — not all target rows, not transitive. Main sheet retains `__str__`+`_id`.

### Fix D — `_primary_color` DB guard

Already implemented: `except (OperationalError, ProgrammingError): return FALLBACK_COLOR`. Without, `migrate`/`collectstatic` fails when color table missing.

---

## 7. Reuse Checklist — Another Django Project

### 7.1 Minimal steps

1. **Dependencies**
   ```bash
   pip install "openpyxl>=3.1,<3.2"
   # pip install django-unfold django-solo  # if not already
   # Pin: django-unfold==0.77.1 (match stock tab_actions.html gap diff)
   ```

2. **Copy utils**
   - Copy `utils/excel_export.py` → `project/utils/excel_export.py` (replace `_primary_color()` with generic blue constant or adapt brand import).
   - Copy `utils/test_excel_export.py` → adapt `from <APP_LABEL>.models import …` to your models, update `get_related_targets` expectations if FK graph differs.

3. **Create admin bases** — single file, e.g. `project/admin_base.py` (keep one source):
   - Copy `_excel_response`, `ModelAdminUnfoldBase`, `<APP_MIXIN>`, `<APP_BASE>` from `project/admin_base.py`.
   - Replace string `"<APP_LABEL>"` in `has_export_all_permission` and `build_full_app_workbook(app_label="<APP_LABEL>")`, filename prefix `"<APP_LABEL>_full_export_"`, and class names `<APP_MIXIN>`/`<APP_BASE>` to your app (e.g. `StoreExportMixin` / `StoreModelAdminBase`).
   - Keep `FALLBACK_COLOR = "#2563EB"` generic blue or set your brand hex; adapt or remove `_primary_color()` DB block if no brand table.

4. **Wire ModelAdmins**
   - Bulk-only (non-`<APP_LABEL>`): `class MyModelAdmin(ModelAdminUnfoldBase): …`
   - `<APP_LABEL>` member: `class YourAppMemberAdmin(<APP_BASE>): …` — header on both changelist + changeform.
   - Singleton (if any): `class SingletonAdmin(SingletonModelAdmin, <APP_MIXIN>, ModelAdminUnfoldBase): actions_list = ["export_all"]; actions_detail = ["export_all"]`.
   - Read-only: keep `has_change_permission=False` — bulk actions still work via `view`.

5. **Templates**
   > Only if `django-solo` singleton + `django-unfold` together — otherwise skip `admin/solo/change_form.html`.

   - Copy `project/templates/admin/solo/change_form.html` (history via `tab_action.html`) if solo used.
   - Copy `project/templates/unfold/helpers/tab_actions.html` (with `gap-2` / `lg:gap-2` on `<ul>`) — small spacing + vertical centering.
   - Ensure `settings.TEMPLATES[0]["DIRS"] = [BASE_DIR / "project" / "templates"]` precedes app templates so your override wins. Verify via `get_template("admin/solo/change_form.html").origin.name` and `manage.py check`.

6. **Convention doc**
   - Add to `AGENTS.md` / `README.md`: “New models inherit `ModelAdminUnfoldBase`; `<APP_LABEL>` members inherit `<APP_BASE>` to join full export via `apps.get_models()` sorted discovery by `<APP_LABEL>`.” Keep all bases/mixins in single file `project/admin_base.py`.

### 7.2 Settings to verify

- `INSTALLED_APPS`: `unfold`, `unfold.contrib.*` **before** `django.contrib.admin`.
- `TEMPLATES[0].DIRS` includes your templates dir.
- `UNFOLD["SHOW_HISTORY"] = True` (history button gated by this + `show_history` context).

### 7.3 App discovery

- `build_full_app_workbook(app_label="<APP_LABEL>")` filters `apps.get_models()` by `app_label` param. Sorted by `model_name` ensures stable sheet order; `sanitize_sheet_name` handles 31-char limit and duplicates. If you support multiple export apps, parameterize `build_workbooks_for_apps(["<APP_A>","<APP_B>"])`.

### 7.4 Permissions

- Bulk actions: `permissions=["view"]` + `has_export_*_permission → has_view_permission` (view-gated, works for read-only `has_change_permission=False`).
- Header: `permissions=["export_all"]` + `has_export_all_permission → is_staff and has_module_perms("<APP_LABEL>")`. Non-staff or without that app's module perms = button hidden. `admin_site.admin_view` still checks `is_active and is_staff`.

### 7.5 Testing your clone

- Run copied `test_excel_export.py` (adapt imports): `python manage.py test <your_tests>.test_excel_export -v2` only.
- Manual QA (as staff with `has_module_perms("<APP_LABEL>")`):
  1. Changelist `Actions` → `Export to Excel` (1 sheet, selected rows).
  2. `Export to Excel (with related)` (forward FKs, referenced rows only, no transitive — extra sheets per distinct target).
  3. Header `Export all app data` on changelist **and** changeform (`/<id>/export_all/` + `/export_all/`) → `<APP_LABEL>`-wide workbook, `Freeze A2`, generic blue header.
  4. Singleton header (if solo): `History` + `Export all app data` with `gap-2` / `lg:gap-2`, no overlap at `lg` (row) and `<lg` hamburger (col), vertically centered.
  5. Empty selection → `message_user(WARNING)` “Select at least one row to export.”, no file.
  6. Non-staff / no `has_module_perms("<APP_LABEL>")` → header button hidden.

---

## 8. Known Limitations & Future Extensions

- **Forward FK/OneToOne only:** reverse FK, M2M, transitive (A→B→C) excluded. Extend `get_related_targets` + `build_workbook_for_queryset` if needed.
- **In-memory workbook:** large querysets use `iterator()` but still build in memory. Switch to `StreamingHttpResponse` if >50k rows per sheet.
- **Decimal → float:** sub-cent loss possible; mitigated by `number_format`, authoritative DB values.
- **Sheet collisions:** dedup via `_2`, `_3`; empty `verbose_name` → `model_name` fallback.
- **Future singletons:** auto-inherit header fix via template overrides (desired).

---

## 9. References

- Unfold patterns: `unfold/templates/admin/change_form_object_tools.html`, `unfold/helpers/tab_actions.html`, `unfold/decorators.py`, `unfold/admin.py`
- Django files (local): `project/admin_base.py`, `utils/excel_export.py`, `utils/test_excel_export.py`

---

## 10. Checklist for Docs Review

- [ ] `<APP_LABEL>` replaced everywhere (app filter, `has_module_perms("<APP_LABEL>")`, filename `"<APP_LABEL>_full_export_"`, mixin/class names `<APP_MIXIN>`/`<APP_BASE>`)
- [ ] `project` templates path replaced
- [ ] `_primary_color()` kept as `FALLBACK_COLOR = "#2563EB"` generic blue or replaced with your brand hex
- [ ] `requirements.txt` `openpyxl>=3.1,<3.2` installed (manual step)
- [ ] Singleton MRO verified if solo used (`SingletonModelAdmin` first)
- [ ] Template overrides copied as needed: `admin/solo/change_form.html` (only if solo), `unfold/helpers/tab_actions.html` with `gap-2` / `lg:gap-2`
- [ ] `TEMPLATES[0].DIRS` precedence confirmed (`python manage.py check` + `get_template("admin/solo/change_form.html").origin.name` → your project)
