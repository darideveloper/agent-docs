---
created: 2026-04-18
tags:
  - django
  - admin
  - unfold
  - documentation
type: resource
status: active
source: templates://django/django-unfold-admin.md
version: 2026-09-27+57b0fd3

---

# Django Unfold Integration Guide (Reusable Template, English Default)

> English by default. For Spanish admin, see [Spanish Django Admin](./django-i18n-es-admin.md) opt-in (do not include `range_date_filter_es.js` in English projects). Canonical admin base `project/admin_base.py::ModelAdminUnfoldBase` is defined here (§7.2) — [Project Setup](./django-project-setup.md) imports from it. The excel-export guide intentionally defines a separate export flavor (same class name + bulk actions) — two flavors, see excel §5.

This document describes how `django-unfold` is integrated into this project to provide a modern, responsive, and customizable Django Admin interface.

## 0. Prerequisites

Before proceeding, ensure the core infrastructure (Environment Variables, Static Files, and Templates) has been set up following the [Project Setup Guide](./django-project-setup.md).

## 1. Dependencies

Add the following package to your `requirements.txt`:

```text
django-unfold==0.77.1
```

## 2. Configuration in `settings.py`

### 2.1 Installed Apps

Ensure `unfold` and its optional components are placed **before** `django.contrib.admin`:

```python
INSTALLED_APPS = [
    "unfold",
    "unfold.contrib.filters",
    "unfold.contrib.forms",
    "unfold.contrib.inlines",
    "rest_framework.authtoken",
    # ... other apps
    "django.contrib.admin",
    "django.contrib.auth",
    # ...
]
```

### 2.2 Static Files & Templates

Ensure root static and templates directories are configured in `settings.py` to allow overriding admin assets, as described in the [Project Setup Guide](./django-project-setup.md) §6.

## 3. UNFOLD Settings Dictionary

Key logic:
- **SITE_ICON**: When used, the **SITE_HEADER** and **SITE_SUBHEADER** remain visible in the sidebar.
- **SITE_FAVICONS**: When used, it replaces the **SITE_ICON**, but the **SITE_HEADER** and **SITE_SUBHEADER** remain visible.
- **SITE_LOGO**: When used, it replaces the **SITE_FAVICONS**, **SITE_HEADER**, and **SITE_SUBHEADER** in the sidebar.
- **COLORS**: Defined using OKLCH for modern browser support and consistent shading.
- **SIDEBAR**: `show_all_applications: True` with an empty `navigation: []` switches the sidebar to **auto-render mode**: every registered `ModelAdmin` in `INSTALLED_APPS` is listed, filtered by the request user's per-model permissions. The sidebar body is rendered by a project-level template override at `project/templates/unfold/helpers/navigation.html` (Unfold's bundled template falls back to Django's classic `admin/app_list.html` when `navigation` is empty, which is not Unfold-styled; the override is required to get an Unfold-styled auto sidebar). See §3.1 below.

```python
from django.templatetags.static import static
from django.urls import reverse_lazy
from django.utils.translation import gettext_lazy as _

UNFOLD = {
    "SITE_TITLE": "My Project Dashboard",
    "SITE_HEADER": "My Project Admin", # Fallback when logo is missing
    "SITE_SUBHEADER": "My Project Dashboard", # Visible below logo
    "SITE_URL": "/",
    "SITE_ICON": lambda request: static("favicon.png"),
    "SITE_LOGO": lambda request: static("logo.webp"),
    "SITE_SYMBOL": "directions_car",
    "SITE_FAVICONS": [
        {
            "rel": "icon",
            "sizes": "32x32",
            "type": "image/png",
            "href": lambda request: static("favicon.png"),
        },
    ],
    "SHOW_HISTORY": True,
    "SHOW_VIEW_ON_SITE": True,
    "ENVIRONMENT": "utils.callbacks.environment_callback",
    "THEME": "light",
    # Generic blue primary derived from FALLBACK_COLOR #2563EB.
    # Purple oklch scale below kept as commented alternative.
    "COLORS": {
        "primary": {
            "50": "oklch(0.97 0.02 256)",
            "100": "oklch(0.92 0.04 256)",
            "200": "oklch(0.85 0.08 256)",
            "300": "oklch(0.75 0.12 256)",
            "400": "oklch(0.68 0.16 256)",
            "500": "oklch(0.62 0.19 256)",  # ~#2563EB
            "600": "oklch(0.55 0.17 256)",
            "700": "oklch(0.47 0.14 256)",
            "800": "oklch(0.38 0.11 256)",
            "900": "oklch(0.30 0.08 256)",
            "950": "oklch(0.22 0.06 256)",
        },
    },
    "SIDEBAR": {
        # Canonical default is auto-render mode (see §3.1): show_all_applications True + navigation [].
        # The manual navigation example below is OPTIONAL — use it only if you need hand-ordered sections.
        "show_search": True,
        "show_all_applications": True,
        "navigation": [],
        # Manual example (optional):
        # "navigation": [
        #     {
        #         "title": _("Authentication"),
        #         "separator": True,
        #         "collapsible": False,
        #         "items": [{"title": _("Users"), "icon": "person", "link": reverse_lazy("admin:auth_user_changelist")}],
        #     },
        #     {
        #         "title": _("Catalog"),
        #         "separator": True,
        #         "collapsible": True,
        #         "items": [{"title": _("Articles"), "icon": "article", "link": reverse_lazy("admin:catalog_article_changelist")}],
        #     },
        # ],
    },
}
```

> **Note**: canonical default is **auto-render mode** (`navigation: []`, `show_all_applications: True` + override in §3.1) so adding a `ModelAdmin` needs no settings change and the list is permission-filtered. The commented manual `navigation` above is optional hand-ordering only. 

### 3.1. Permission-aware auto sidebar

`UNFOLD["SIDEBAR"]` has no setting that auto-populates the sidebar body from registered `ModelAdmin` classes. The `show_all_applications` flag adds a single "All applications" **modal button** at the bottom of the sidebar — it does not render apps inline. An empty `navigation` causes Unfold's bundled `unfold/helpers/navigation.html` to fall back to Django's classic `admin/app_list.html` (boxed table markup, not Unfold styling).

To get an Unfold-styled, permission-filtered auto sidebar, this project overrides Unfold's helper at `project/templates/unfold/helpers/navigation.html`. The override iterates `available_apps` (Django's permission-filtered app list, provided by `AdminSite.get_app_list(request)`) using Unfold's group/link DOM, applies the `active` class set when a model's `admin_url` matches the request path, and falls back to the `unfold/helpers/messages/error.html` partial for users with no admin permissions.

Resulting `SIDEBAR` block in `project/settings.py`:

```python
"SIDEBAR": {
    "show_search": True,
    "show_all_applications": True,
    "navigation": [],
},
# No `permission` callback, no Python helper, no custom `AdminSite` subclass,
# and no `<MAIN_APP>/admin.py` changes are required.
```

### 3.2. Override template: `project/templates/unfold/helpers/navigation.html`

Minimal override (verified against `django-unfold==0.77.1` — re-check class names after any Unfold bump). Iterates `available_apps` (permission-filtered by `AdminSite.get_app_list(request)`), renders each model with Unfold's group/link DOM, marks the link `active` when its `admin_url` matches the request path, and falls back to the error partial for users with no model permissions. Icon per model comes from `ModelAdminUnfoldBase.sidebar_icon` via the icon map (see §7.2); models without a mapped icon use `"database"`.

```django
{% load i18n sidebar_extras %}

{% if available_apps %}
  {% for app in available_apps %}
    <div class="flex flex-col gap-1">
      <span class="px-3 pt-4 text-xs font-medium uppercase text-base-500">
        {{ app.name }}
      </span>
      {% for model in app.models %}
        <a href="{{ model.admin_url }}"
           class="{% if request.path == model.admin_url %}active{% endif %} flex items-center gap-2 rounded-md px-3 py-2 text-sm">
          <span class="material-symbols-outlined text-lg">{% sidebar_icon_for model %}</span>
          <span>{{ model.name }}</span>
        </a>
      {% endfor %}
    </div>
  {% endfor %}
{% else %}
  {% include "unfold/helpers/messages/error.html" %}
{% endif %}
```

Notes:

- Template path must be exactly `project/templates/unfold/helpers/navigation.html` and `TEMPLATES[0]["DIRS"]` must include `BASE_DIR / "project" / "templates"` so it wins over Unfold's bundled helper.
- `sidebar_extras` provides two tiny filters used above: `{% sidebar_icon_for model %}` (reads the icon map via `get_item`, default `"database"`) and the stock `get_item` lookup. Copy them from your scaffold (see §7.2) or inline a default icon and drop the tag.
- `request` must be in template context (stock admin context processors already provide it).


## 4. Custom Callbacks (`utils/callbacks.py`)

Provides environment-specific badges in the admin header.

```python
import os

def environment_callback(request):
    env = os.getenv("ENV", "dev")
    env_mapping = {
        "prod": ["Production", "danger"],
        "staging": ["Staging", "warning"],
        "dev": ["Development", "info"],
        "local": ["Local", "success"],
    }
    return env_mapping.get(env, ["Unknown", "info"])
```

## 5. Static Assets (Unfold Enhancements)

These scripts enhance the Unfold interface with custom styling and functionality.

### static/css/style.css — `.img-preview`

Image preview thumbnails (e.g. `<MODEL>Admin.display_image`, `<MODEL>ImageInline.display_preview`) and form previews are styled by the `.img-preview` classes defined in `static/css/style.css` — **not** by inline `style=` attributes. Emit `class="img-preview"` and add a variant only when a non-default size or layout is needed:

```css
.img-preview { height: 50px; border-radius: 6px; object-fit: cover; }
.img-preview--sm { height: 40px; width: 40px; object-fit: cover; }
.img-preview--lg { height: 64px; width: 64px; object-fit: cover; }
.img-preview--banner { max-height: 180px; max-width: 100%; border-radius: 8px; object-fit: cover; }
.img-preview--form { max-height: 240px; max-width: 100%; border-radius: 8px; object-fit: cover; }
```

Use `img-preview img-preview--sm` for small square thumbnails (e.g. changelist columns), plain `img-preview` for regular inlines, `img-preview--banner` for wide header banner previews in changeforms, and `img-preview--form` for large image detail previews. Previews must not use inline styles.

### static/js/load_markdown.js
Integrates SimpleMDE for all text areas within Unfold.
```javascript
document.addEventListener("DOMContentLoaded", () => {
  const textAreasSelector = "div > textarea"
  const textAreas = document.querySelectorAll(textAreasSelector)

  setTimeout(() => {
    textAreas.forEach((textArea) => {
      new SimpleMDE({
        element: textArea,
        toolbar: [
          "bold",
          "italic",
          "heading",
          "|",
          "quote",
          "code",
          "link",
          "image",
          "|",
          "unordered-list",
          "ordered-list",
          "|",
          "undo",
          "redo",
          "|",
          "preview",
        ],
        spellChecker: false,
      })
    })
  }, 100)
})
```

### static/js/range_date_filter_es.js — Spanish-only (OPT-IN, skip in English default)
Localizes placeholder text for Unfold's range date filters. Only include when [django-i18n-es-admin](./django-i18n-es-admin.md) is adopted.
```javascript
document.addEventListener("DOMContentLoaded", function () {
  const texts = [
    { names: ["created_at_from", "updated_at_from"], text: "Desde" },
    { names: ["created_at_to", "updated_at_to"], text: "Hasta" },
  ]

  texts.forEach((text) => {
    text.names.forEach((name) => {
      const elem = document.querySelector(`[name="${name}"]`)
      if (!elem) return
      elem.placeholder = text.text
    })
  })
})
```

### Markdown Preview Styling (`static/css/style.css`)
To ensure the Markdown preview is readable within the Unfold theme, custom typography styles are applied to `.editor-preview`. These styles re-introduce headings, lists, and other formatting that are otherwise stripped by Tailwind's reset, while using dynamic CSS variables for brand consistency.

```css
.editor-preview, .editor-preview-side {
    font-family: inherit;
    color: inherit;
    line-height: 1.6;
}

.editor-preview h1, .editor-preview-side h1 {
    font-size: 1.875rem;
    font-weight: 700;
    margin-top: 1.5rem;
    margin-bottom: 1rem;
    border-bottom: 1px solid var(--color-base-200);
    padding-bottom: 0.5rem;
}

.editor-preview h2, .editor-preview-side h2 {
    font-size: 1.5rem;
    font-weight: 700;
    margin-top: 1.25rem;
    margin-bottom: 0.75rem;
    border-bottom: 1px solid var(--color-base-100);
    padding-bottom: 0.25rem;
}

.editor-preview h3, .editor-preview-side h3 {
    font-size: 1.25rem;
    font-weight: 600;
    margin-top: 1rem;
    margin-bottom: 0.5rem;
}

.editor-preview p, .editor-preview-side p {
    margin-bottom: 1rem;
}

.editor-preview ul, .editor-preview-side ul {
    list-style-type: disc !important;
    padding-left: 1.5rem !important;
    margin-bottom: 1rem;
}

.editor-preview ol, .editor-preview-side ol {
    list-style-type: decimal !important;
    padding-left: 1.5rem !important;
    margin-bottom: 1rem;
}

.editor-preview li, .editor-preview-side li {
    display: list-item !important;
    margin-bottom: 0.25rem;
}

.editor-preview strong, .editor-preview-side strong {
    font-weight: 700;
}

.editor-preview em, .editor-preview-side em {
    font-style: italic;
}

.editor-preview blockquote, .editor-preview-side blockquote {
    border-left: 4px solid var(--color-base-200);
    padding-left: 1rem;
    color: var(--color-font-subtle-light);
    font-style: italic;
    margin-bottom: 1rem;
}

.editor-preview code, .editor-preview-side code {
    background-color: var(--color-base-100);
    padding: 0.2rem 0.4rem;
    border-radius: 0.25rem;
    font-family: monospace;
    font-size: 0.875em;
}

.editor-preview pre, .editor-preview-side pre {
    background-color: var(--color-base-100);
    padding: 1rem;
    border-radius: 0.5rem;
    overflow-x: auto;
    margin-bottom: 1rem;
}

.editor-preview pre code, .editor-preview-side pre code {
    background-color: transparent;
    padding: 0;
}

.editor-preview a, .editor-preview-side a {
    color: var(--brand-primary-600, var(--color-primary-600));
    text-decoration: underline;
}
```

### File Upload Widget Width (`static/css/style.css`) — Unfold 0.77.1 pinned
Unfold's file/image upload widgets render a fake, disabled text input to show the filename or the "Select file to upload" placeholder. That input carries `grow` (`flex-grow: 1`) and `min-w-0` (`min-width: 0`) classes, but they are inert because its wrapping `<label class="grow relative">` is not a flex container, so the input stays at its intrinsic width and the label text is not fully visible. Making the label a flex container activates those classes and the input fills the widget width. Pinned to `django-unfold==0.77.1` — re-verify selectors after any Unfold bump:

```css
label.grow.relative {
    display: flex;
}
```

The `label.grow.relative` selector matches only the two Unfold file-input widget templates (`clearable_file_input.html` and `clearable_file_input_small.html`), so it covers both the change-form widget and the small inline widget without touching other inputs. Do **not** use `width: 100%` on the input instead: it regresses the small inline widget (a circular flex/percentage sizing collapses the label and truncates the text).

### M2M FilterWidget Helptext Removal (`static/css/style.css`) — English default hides hints; Spanish catalog wording differs (see ES opt-in)

Django's `filter_horizontal`/`filter_vertical` widgets inject a `<p class="helptext">` into each side's title bar referencing labelled Choose/Remove buttons that don't exist (move controls are arrows). The widget is self-explanatory, so both hints are removed:

```css
.selector-available-title .helptext,
.selector-chosen-title .helptext {
    display: none;
}
```

`display:none` also drops the hints from the accessibility tree. The selectors match only the two hint paragraphs `SelectFilter2.js` injects; no other element in the admin uses `class="helptext"` inside `.selector-*-title`.

## 6. Admin Interface Overrides

Override `project/templates/admin/base_site.html` (canonical name — never `base.html`) to inject SimpleMDE and other custom assets. To ensure Unfold's sticky bottom bar and responsive layout logic are preserved, always extend `"admin/base.html"` instead of the internal layout directly. Load `range_date_filter_es.js` here only for Spanish opt-in projects.

### project/templates/admin/base_site.html
```html
{% extends "admin/base.html" %} {% load static %} {% block extrahead %}
{{ block.super }}
<!-- Load markdown libraries -->
<link rel="stylesheet" href="https://cdn.jsdelivr.net/simplemde/latest/simplemde.min.css" />
<script src="https://cdn.jsdelivr.net/simplemde/latest/simplemde.min.js"></script>

<!-- Load Unfold custom scripts -->
<script src="{% static 'js/load_markdown.js' %}"></script>
<script src="{% static 'js/range_date_filter_es.js' %}"></script>
{% endblock %}
```

## 7. Admin Implementation

### 7.1 Customizing Auth Models (`project/admin.py`)

> **CRITICAL: `project/admin.py` is NOT auto-discovered** because `project` is not in `INSTALLED_APPS`. Django's admin autodiscovery only finds `admin.py` inside installed apps. You must explicitly import the module in `urls.py` for the custom admin classes to register:
> ```python
> # project/urls.py
> import project.admin  # ← required so UserAdmin, GroupAdmin, TokenAdmin are registered
> ```
> Without this import, Django's default admin classes are used silently — `sidebar_icon`, Unfold forms, and all other customisations are ignored.

All auth model admin classes SHALL use `ModelAdminUnfoldBase` (not raw `ModelAdmin`) to inherit `compressed_fields`, `warn_unsaved_form`, `sidebar_icon`, and the `edit` row action.

> **DRF-only**: `TokenAdmin` / `TokenProxy` (from `rest_framework.authtoken`) are only required if the project uses DRF's `TokenAuthentication`. If not using DRF or not using Token auth, omit those imports, the `unregister(TokenProxy)` call, and the `TokenAdmin` class.

```python
from django.contrib import admin
from django.contrib.auth.admin import GroupAdmin as BaseGroupAdmin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.models import Group, User
from rest_framework.authtoken.admin import TokenAdmin as BaseTokenAdmin
from rest_framework.authtoken.models import TokenProxy

from project.admin_base import ModelAdminUnfoldBase
from unfold.forms import AdminPasswordChangeForm, UserChangeForm, UserCreationForm

admin.site.unregister(User)
admin.site.unregister(Group)
admin.site.unregister(TokenProxy)


@admin.register(User)
class UserAdmin(BaseUserAdmin, ModelAdminUnfoldBase):
    sidebar_icon = "person"
    form = UserChangeForm
    add_form = UserCreationForm
    change_password_form = AdminPasswordChangeForm
    list_display = ("username", "email", "first_name", "is_staff")
    list_display_links = ("username", "email")


@admin.register(Group)
class GroupAdmin(BaseGroupAdmin, ModelAdminUnfoldBase):
    sidebar_icon = "group"


@admin.register(TokenProxy)
class TokenAdmin(BaseTokenAdmin):
    # DRF-only. Does not inherit ModelAdminUnfoldBase because it extends DRF's TokenAdmin;
    # for third-party admins needing base behavior use `class X(ModelAdminUnfoldBase, BaseX)`.
    sidebar_icon = "key"
```
### 7.2 Plain flavor (ModelAdminUnfoldBase) — export flavor ModelAdminUnfoldExportBase lives separately in [Excel Export](./django-excel-export.md) §5. To combine: class ModelAdminCombined(ModelAdminUnfoldExportBase): actions_row = ["edit"] (export base already includes edit row + bulk exports).

## 7.2 Base Admin Class (`project/admin_base.py::ModelAdminUnfoldBase`)

Plain-flavor canonical base. `[django-project-setup](./django-project-setup.md)` imports from here. NOTE: the excel-export guide defines its own export flavor (same class name + `export_selected` bulk actions) — intentional separate flavor, see excel §5. Provides common UI enhancements like row actions and compressed fields.

```python
from unfold.admin import ModelAdmin
...
from unfold.decorators import action
from django.shortcuts import redirect
from django.urls import reverse

class ModelAdminUnfoldBase(ModelAdmin):
    sidebar_icon = "database"
    compressed_fields = True
    warn_unsaved_form = True
    list_filter_sheet = False
    change_form_show_cancel_button = True

    actions_row = ["edit"]

    @action(description="Edit", permissions=["change"])
    def edit(self, request, object_id):
        return redirect(reverse(f"admin:{self.model._meta.app_label}_{self.model._meta.model_name}_change", args=[object_id]))
```

**Custom sidebar icon per model.** The auto-rendered sidebar (`project/templates/unfold/helpers/navigation.html`) uses the `ModelAdminUnfoldBase.sidebar_icon` class attribute as the Material symbol for each model link. Default is `"database"`. Override per admin:

```python
@admin.register(Client)
class ClientAdmin(ModelAdminUnfoldBase):
    sidebar_icon = "directions_car"
```

The icon map is built by `utils.admin_icons.build_sidebar_icon_map()` and injected into every template via `utils.context_processors.user_palette`. The template reads the map through a `get_item` filter defined in `utils.templatetags.sidebar_extras`. No per-model wiring is needed; setting the attribute on the admin is sufficient. These three helpers are project-specific scaffolding — copy them from your scaffold or omit icon mapping (defaults to `"database"`).

### 7.3 Changeform actions and copy-link buttons

Use Unfold-native button patterns everywhere; **custom-inject a button only for copy links**, which the Clipboard API forces to be a real `<button>` on the same page (a server-side action cannot copy).

- **Server actions** → declare them in `actions_detail` (change-form header) or `actions_row` (changelist rows) with `@action(description=..., url_path=..., permissions=[...])`. Conditional visibility is enforced only when `permissions=[...]` is passed, which wires the `has_<action>_permission` method.
- **Copy-link buttons** → the only exception. Inject `copy_button_extra_attrs` (a `mark_safe` attribute string: `type="button" data-copy-url="<url>"`) from a `change_view` override, then render the button in an `object-tools-items` override through `{% component "unfold/components/button.html" %}` with `extra_attrs=copy_button_extra_attrs`. `static/js/copy_clipboard.js` (loaded via the admin's `Media`) wires the click-to-copy.

Any model admin with header buttons (`<app>/admin.py` + `admin/<app>/<model>/change_form.html`) and a change-form copy button (`<app>/admin.py` + `admin/<app>/<model>/change_form.html`) follows this pattern. See [Image Copy Link](./django-image-copy-link.md).

## 8. Layout Constraints

To ensure the "bottom bar" (sticky action buttons) and responsive containers work correctly:
- **Inheritance**: Do not extend `unfold/layouts/base.html` in your `base_site.html` overrides; always extend `admin/base.html`.
- **Custom CSS**: Avoid applying `position: absolute` or `position: fixed` to the main page containers (`#page`, `#main`, etc.), as this interferes with Unfold's native sticky positioning logic.
- **Admin Base**: Use `ModelAdminUnfoldBase` for all application models to ensure consistent button availability and unsaved form warnings.
```
