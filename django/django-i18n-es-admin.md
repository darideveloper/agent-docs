---
created: 2026-08-09
tags:
  - django
  - admin
  - i18n
  - spanish
  - unfold
  - documentation
type: resource
status: active
source: templates://django/django-i18n-es-admin.md
version: 2026-09-27+57b0fd3

---

# Spanish Django Admin — OPT-IN Variant

> OPT-IN Spanish variant — skip for English-default projects. English default is `LANGUAGE_CODE = "en-us"` + `TIME_ZONE = "America/Mexico_City"` (see [Project Setup](./django-project-setup.md)). This recipe sets `LANGUAGE_CODE = "es"` (replace `TIME_ZONE` with your zone).

> Scope **admin only**: nothing here touches public web pages. The public-site
> translation differs; this note only covers the Django Admin.

This guide is a portable recipe to give the **Django Admin** of **any project
whose admin runs on django-unfold** a fully Spanish UI. Every example uses
**sample data** (a fictional "production" domain), so nothing project-specific
leaks in. Replicate it as-is in any project that uses Unfold as its admin theme;
§9 covers the strings that are specific to Unfold itself.

The whole system is **`LANGUAGE_CODE` plus hard-coded Spanish strings** — no
custom translation catalog, no `gettext`/`_()`, no `.po`/`.mo` files (the only
exception is the unfold-only strings in §9).

---

## 1. Architecture — the four sources of a Spanish admin

Everything you see rendered in the admin comes from **one of these**:

| #   | What you see                                                                   | Where it comes from                                                                              | You need to change it?                         |
| --- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ | ---------------------------------------------- |
| A   | Generic chrome: buttons, pagination, login, delete confirmations, date widgets | Django's **shipped** `es` catalog (`django/conf/locale/es/` + `django/contrib/admin/locale/es/`) | **No** — automatic once `LANGUAGE_CODE = "es"` |
| B   | Model field labels, model names, choices                                       | your model `verbose_name` / `help_text` / `Meta` **Spanish literals**                            | Yes — in `models.py`                           |
| C   | App section names, fieldset titles, list column headers, custom view copy      | your `apps.py` / `admin.py` **Spanish literals**                                                 | Yes — in `apps.py` / `admin.py`                |
| D   | Custom admin screens you wrote yourself (imports, previews, extra buttons)     | your own **admin templates** with literal Spanish                                                | You write them in Spanish to begin with        |

There is **no layer 0 custom catalog** — that's the whole trick: Django's own
ES catalog does the generic chrome (A), and the project hard-codes Spanish for
everything else (B–D).

---

## 2. Step 0 — global settings (the ONLY mandatory change)

`project/settings.py` (your project's settings module):

```python
LANGUAGE_CODE = "es"
USE_I18N = True
USE_TZ = True
TIME_ZONE = "Europe/Madrid"   # optional, admin date rendering
```

Minimal requirements:

- `LANGUAGE_CODE = "es"` — activates the Spanish translations bundled with Django.
- `USE_I18N = True` — enables the translation mechanism (already default-true; keep it).

### Deliberately NOT configured (and why)

| Setting | Result | Do it when |
|---|---|---|
| `LOCALE_PATHS` | A custom translation catalog (`.po`/`.mo`). | **Almost never.** Only to translate strings that have no Spanish shipped (see §9, django-unfold case). |
| `LocaleMiddleware` | Per-user / per-request language switching (URL prefix, `Cookie`). | Only if the site must be **multi-language**. A fixed-Spanish admin doesn't need it. |
| `LANGUAGES` | The set of allowed languages (es / en / …) for the whole project. | Only if a language selector is wanted. |

None of these are needed for a fully Spanish admin. Adding any is extra moving
parts — skip them unless you explicitly need language switching.

---

## 3. Step 1 — the generic chrome comes for free

Once `LANGUAGE_CODE = "es"`, this list renders in Spanish **with zero code**:

- Buttons: **Guardar**, **Guardar y continuar editando**, **Guardar y añadir otro**, **Eliminar**
- Change-list: the action drop-down (label **Acción:**, tooltip **Ejecutar la acción seleccionada**), the selection counter (**0 de 0 seleccionado**), **Buscar**, and pagination as page numbers + **Mostrar todo**
- Delete confirmation: **¿Está seguro?**, plus **¿Está seguro de que quiere borrar los "…"? Se borrarán los siguientes objetos relacionados:**
- Login/logout page, date/time widgets, filter drop-downs
- Built-in `auth` labels on the `User` admin (field labels, permission names), coming from the shipped catalogs

These come from `django/conf/locale/es/LC_MESSAGES/django.po` (core + auth) and
`django/contrib/admin/locale/es/LC_MESSAGES/django.po` (admin). They're shipped
inside the Django wheel — your project doesn't ship any `.mo` of its own.

---

## 4. Step 2 — your own labels (models)

Write the Spanish text **directly** in the model definition. Sample domain:

```python
# books/models.py
from django.db import models


class Author(models.Model):
    name = models.CharField(max_length=120, verbose_name="Nombre")

    class Meta:
        verbose_name = "Autor"
        verbose_name_plural = "Autores"

    def __str__(self):
        return self.name


class Book(models.Model):
    class Status(models.TextChoices):
        DRAFT = "draft", "Borrador"
        PUBLISHED = "published", "Publicado"

    title = models.CharField(max_length=200, verbose_name="Título")
    author = models.ForeignKey(
        Author, on_delete=models.CASCADE, related_name="books",
        verbose_name="Autor",
    )
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.DRAFT,
        verbose_name="Estado",
    )
    published_at = models.DateTimeField(null=True, blank=True, verbose_name="Publicado el")

    class Meta:
        verbose_name = "Libro"
        verbose_name_plural = "Libros"
```

Rules:

1. **Always `verbose_name` on fields** and **`Meta.verbose_name`/`verbose_name_plural`** in Spanish.
2. `help_text` in Spanish too: `verbose_name="Precio", help_text="Precio de venta sin IVA"`.
3. Choices: **Spanish label, English value**. `DRAFT = "draft", "Borrador"` keeps DB
   values language-free while the dropdown and badges show Spanish.

Same pattern for every model of the project (users, products, orders, …).

### Translated content — `__str__` with a Spanish-first lookup

When a model's display name lives in **translation rows** (its own `*Translation`
model instead of a direct `name`/`title` column), return the translated value
from `__str__` so related dropdowns, M2M widgets and inline rows show Spanish
too. The convention: **prefer `es`, fall back to any available language, then to
the slug**. Prefer a shared abstract mixin so every translated model reuses the
lookup:

```python
# common/models.py
from django.db import models


class TranslatableName(models.Model):
    class Meta:
        abstract = True

    def translated_name(self, language="es"):
        t = self.translations.filter(language=language).first() or self.translations.first()
        return t.name if t else self.slug

    def __str__(self):
        return self.translated_name()


class Genre(TranslatableName):
    slug = models.SlugField(max_length=200, unique=True)
    # ...direct fields...


class GenreTranslation(models.Model):
    language = models.CharField(max_length=5, choices=[("es", "Español"), ("en", "English")])
    genre = models.ForeignKey(Genre, on_delete=models.CASCADE, related_name="translations")
    name = models.CharField(max_length=200)
    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["genre", "language"], name="unique_genre_language")
        ]
```

If the project already has a shared abstract base that provides `slug` (and
other common fields), have `TranslatableName` extend **that** instead of
declaring `slug` on each model:

```python
# common/models.py
class BaseModel(models.Model):
    slug = models.SlugField(max_length=200, unique=True)
    class Meta:
        abstract = True


class TranslatableName(BaseModel):
    class Meta:
        abstract = True

    def translated_name(self, language="es"):
        t = self.translations.filter(language=language).first() or self.translations.first()
        return t.name if t else self.slug

    def __str__(self):
        return self.translated_name()


class Genre(TranslatableName):
    pass   # slug comes from BaseModel
```

Models whose translated field has a **different name** (e.g. `title` instead of
`name`) define the same lookup on the class itself:

```python
class Book(TranslatableName):
    # ...direct fields...
    def translated_title(self, language="es"):
        t = self.translations.filter(language=language).first() or self.translations.first()
        return t.title if t else self.slug

    def __str__(self):
        return self.translated_title()
```

Make **translation rows** self-describing too — Django admin inlines render them
through `__str__`:

```python
class BookTranslation(models.Model):
    book = models.ForeignKey(Book, on_delete=models.CASCADE, related_name="translations")
    language = models.CharField(...)
    title = models.CharField(max_length=200)
    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["book", "language"], name="unique_book_language")
        ]

    def __str__(self):
        return f"{self.book} ({self.language})"   # e.g. "Cien años (es)"
```

Django renders M2M `filter_horizontal` widgets, related dropdowns and FK columns
via `__str__`, so overriding it is what makes the **admin UI** — not just the
model — show `"Pintura"` / `"Óleo"` instead of raw slugs.

> The **language-neutral rule** for these texts (English by default, Spanish when
> this recipe is adopted) lives in [Model Definitions](./django-model-definitions.md);
> this section is its Spanish-literal variant.

---

## 5. Step 3 — the app's name in the admin

Set a Spanish `verbose_name` in the app config so the sidebar/index shows a nice name.

```python
# books/apps.py
from django.apps import AppConfig


class BooksConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "books"
    verbose_name = "Biblioteca"   # <-- the name the admin index shows
```

> No `verbose_name` → Django falls back to the app's module name (`books`). Give
> every `AppConfig` one if you want a clean sidebar.

---

## 6. Step 4 — the admin layer: fieldsets, columns, custom screens

`ModelAdmin` defines the strings that aren't in the model: fieldset groups,
column headers for custom methods, and ad-hoc view copy.

```python
# books/admin.py
from django.contrib import admin
from .models import Author, Book


@admin.register(Book)
class BookAdmin(admin.ModelAdmin):
    list_display = ("title", "author", "status", "published_at")
    list_filter = ("status",)
    search_fields = ("title", "author__name")

    fieldsets = (
        (None, {"fields": ("title", "author")}),
        ("Publicación", {          # fieldset header in Spanish
            "fields": ("status", "published_at"),
        }),
    )

    # Custom column with a Spanish header
    def cover_badge(self, obj):
        return "Sí" if obj.published_at else "-"
    cover_badge.short_description = "En portada"


@admin.register(Author)
class AuthorAdmin(admin.ModelAdmin):
    list_display = ("name",)
    search_fields = ("name",)
```

Also in Spanish, for custom admin views you write (`admin.site.admin_view`
endpoints, JSON APIs configured in `ModelAdmin.get_urls()`):

```python
class ImportViewMixin:
    def get_urls(self): ...

    def import_view(self, request):  # example custom admin screen
        context = {
            **self.admin_site.each_context(request),
            "title": "Importar libros desde Excel",
        }
        return render(request, "admin/books/import.html", context)
```

---

## 7. Step 5 (optional, reusable trick) — rename just for the admin

When a model's meaningful name differs from how it appears in menus, without
changing the model itself, patch **`_meta.verbose_name` at import time on the admin**:

```python
# books/admin.py
from .models import Author


# Administration should call it "Escritor", the model stays "Author"
Author._meta.verbose_name = "Escritor"
Author._meta.verbose_name_plural = "Escritores"


@admin.register(Author)
class AuthorAdmin(admin.ModelAdmin):
    list_display = ("name",)
```

Use this sparingly and consciously:

- It **mutates the class `_meta`** — every consumer reading `verbose_name`
  (admin UI, migrations, forms) sees the patched value after import.
- It depends on import order (`admin.py` is imported because
  `django.contrib.admin` is installed).
- Prefer **changing the model** when the business name *is* the model name; use
  the patch only for a genuine admin-only rename, where the model name is fixed
  by the domain and must stay as-is for code/references.

---

## 8. Step 6 — custom admin screens in Spanish (if you write any)

Any template you write under `templates/admin/…` is just literal Spanish — you
don't need `{% load i18n %}` at all:

```html
{% extends "admin/change_list.html" %}
{% block object-tools-items %}
  <li><a class="addlink" href="{% url 'admin:books_book_import' %}">Importar libro (.docx)</a></li>
  {{ block.super }}
{% endblock %}
```

```html
<!-- templates/admin/books/import.html -->
{% extends "admin/base_site.html" %}
{% block content %}
  <p>El archivo debe tener las columnas <code>titulo</code>, <code>autor</code>…</p>
  <input type="file" id="file-input" accept=".xlsx">
  <input type="submit" value="Importar">
{% endblock %}
```

Note `{% load i18n %}` is available but **not required** — there's no catalog to
look anything up in.

---

## 9. django-unfold — the strings Unfold adds

**django-unfold** is a theme over `django.contrib.admin`. The admin it renders
is still Django admin, so everything in steps 2–6 and the shipped catalogs
applies unchanged:

- **Installation order matters**: `unfold` must be placed **before**
  `django.contrib.admin` in `INSTALLED_APPS`, because Unfold's templates must
  win over the default admin's.
- **Unfold is still Django admin**: the model `verbose_name`s, fieldsets,
  `short_description`s, example `_meta` patches, and admin templates (steps 2–6)
  all work identically — Unfold only skins the chrome; the strings are the plain
  Django ones.
- The **generic chrome** (Guardar / Eliminar / …) is translated by the same shipped
  Django catalogs (`django/contrib/admin/locale/es/…`), because Unfold's
  templates call `{% trans "Save" %}` etc. with the same message IDs. No extra
  work.
- **Unfold-only strings** (e.g. "Search apps and models...", "Type to search",
  "Nothing matched your search", "Apply Filters") are *not* part of Django's
  Spanish catalog and **django-unfold ships no Spanish catalog of its own**. They
  stay in **English** unless you translate them yourself. Two options:

  1. **Override the template** — copy the relevant `unfold/…/*.html`
     template into `templates/`, replace the English literal. Very targeted, no
     dependencies.
  2. **A tiny custom catalog** (the only legitimate use of `LOCALE_PATHS` in this
     system):

     ```python
     # settings.py
     LOCALE_PATHS = [BASE_DIR / "locale"]
     ```

     ```bash
     python manage.py makemessages -l es      # creates locale/es/LC_MESSAGES/django.po
     # fill msgstr for the few Unfold-only msgids, e.g.
     #   msgid "Search apps and models..."
     #   msgstr "Buscar apps y modelos..."
     python manage.py compilemessages          # → .mo
     ```

     Django merges your catalog **with** the default admin catalogs — it does **not**
     replace them — so you only need to add the Unfold-only msgids, not retranslate
     the base system.

> To find the current Unfold-only msgids for your installed version, grep the
> package templates for `{% trans %}` / `{% translate %}` ids that are **not**
> in Django's Spanish catalog:
> `grep -rhoE "(trans|translate) ['\"][^'\"]+['\"]" $(python -c "import unfold,os;print(os.path.dirname(unfold.__file__))")/templates`.

- **Language selector (optional)**: if you want end users to *switch* language in
  the admin, walk the multi-language route:
  - add `LocaleMiddleware`,
  - define `LANGUAGES`,
  - add `UNFOLD = {"SHOW_LANGUAGES": True}`.
  But a Spanish-only admin skips all of that.

#### `range_date_filter_es.js` — Spanish placeholders for Unfold's range date filters

Unfold's range date filters render placeholder inputs with English text. The
`static/js/range_date_filter_es.js` script localizes them to Spanish:

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

Load it from your `project/templates/admin/base_site.html` override (Spanish admin
only — do not include it in an English-default project):

```html
<script src="{% static 'js/range_date_filter_es.js' %}"></script>
```

Extend the `texts` array with additional `[name]`→placeholder pairs as needed.

---

## 10. Checklist — replicating the system in your project

| Thing | File | What to write |
|---|---|---|
| Global settings | `settings.py` | `LANGUAGE_CODE = "es"`, keep `USE_I18N = True`. Don't add `LOCALE_PATHS` (unless §9). |
| Generic chrome | — | Nothing: comes from Django's shipped `es` catalogs |
| Model fields/help | each `models.py` | `verbose_name`/`help_text` in Spanish; choices Spanish label, English value; `Meta.verbose_name(_plural)` in Spanish |
| App name | `apps.py` | `verbose_name = "…"` on the `AppConfig` |
| Fieldset titles, custom headers | `admin.py` | Spanish `short_description` / `fieldsets` names / view `title`s |
| Admin-only rename (rare) | `admin.py` | `Model._meta.verbose_name = "…"` patch |
| Custom admin screens | `templates/admin/…` | literal Spanish, no `{% trans %}` needed |
| Architecture | — | **No** `LOCALE_PATHS` for the base system (only §9 unfold-only strings), no gettext, no `.po`, no `LocaleMiddleware` (single-language) |
| Unfold-only strings | `templates/unfold/…` or `locale/es/LC_MESSAGES/django.po` | template override, or a tiny `LOCALE_PATHS` catalog (see §9) |

### Pitfalls to avoid

- **Adding `LOCALE_PATHS`** — you don't need a custom catalog for the base system;
  the shipped `es` catalog is what matters. Adding one adds build/maintenance burden.
- **`LocaleMiddleware` in a Spanish-only site** — it gets in the way (redirects,
  cookie dependency).
- **English DB values inside Spanish choices** — keep it this way on purpose
  (values are only for display mapping). Don't translate the value string.
- **Forgetting `compilemessages`** (only if you add a catalog) — Django reads
  the `.mo` file, not the `.po`. Restart dev server / run `collectstatic` after.
- **Migrations**: `verbose_name` changes on a field still produce a zero-data migration.

---

## 11. Review — before you finish

- [ ] `LANGUAGE_CODE = "es"` — the admin, the login and the pagination render in Spanish **without** any custom catalog
- [ ] No `LocaleMiddleware` (unless language-switch is a requirement)
- [ ] Model labels, app names, fieldset titles, headers, custom screens all literal
- [ ] Choice/status drop-downs show Spanish, DB keeps English values
- [ ] If django-unfold: `unfold` in `INSTALLED_APPS` before `django.contrib.admin`;
      Unfold-only strings covered by either template override or a `LOCALE_PATHS` catalog.

---

## See also

- [Unfold Admin Theme](./django-unfold-admin.md) — django-unfold setup that this
  admin-translation system builds on.
- [Project Setup Guide](./django-project-setup.md) — project scaffolding where these
  settings live.