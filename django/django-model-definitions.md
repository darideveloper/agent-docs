---
created: 2026-08-10
updated: 2026-08-10
tags:
  - django
  - models
  - admin
  - i18n
  - documentation
type: resource
status: active
source: templates://django/django-model-definitions.md
version: 2026-09-17+4cf710f

---

# Django Model Definitions — Admin-Visible Texts (English Default)

> English by default. For the Spanish-literal variant see [[django-i18n-es-admin|Spanish Django Admin]] opt-in.

> Scope **models only**: this note covers the strings that live on the model and
> show up in the Django Admin — field labels, help text, model names, and the
> `__str__` used by dropdowns, M2M widgets and inline rows. Admin-layer strings
> (fieldsets, columns, custom views) are covered by [[django-unfold-admin|Unfold
> Admin Theme]] and the admin guides.

This guide is a portable recipe to define the admin-visible text of **every
model** of **any Django project**. Replicate it as-is: the same rules apply no
matter the domain.

## Language rule

**English by default.** Write `verbose_name`, `help_text`, `Meta.verbose_name`
and `__str__` content in English unless the project follows the Spanish admin
recipe ([[django-i18n-es-admin|Spanish Django Admin]]) — in that case write the
literals in Spanish instead. Nothing else changes; the shape of the code is
identical.

## 1. The always-populate rule

Every model MUST define, at creation time:

1. **`Meta.verbose_name`** and **`Meta.verbose_name_plural`** — the model's name
   in the admin sidebar, change-list and delete screens.
2. **`verbose_name` on every field** — the field label in forms and columns.
3. **`help_text` on non-obvious fields** — inline guidance under the input
   (units, formats, business meaning). Skip it only when the label is
   self-explanatory.
4. **A content-based `__str__`** — what dropdowns, M2M `filter_horizontal`
   widgets, FK columns and inline rows display. Never leave Django's default
   `"Model object (N)"`.

These are not optional extras. Django renders them everywhere in the admin, so
a model without them produces a broken-looking admin.

## 2. Canonical example (direct `name` / `title` columns)

```python
# catalog/models.py
from django.db import models


class Author(models.Model):
    name = models.CharField(max_length=120, verbose_name="Name")

    class Meta:
        verbose_name = "Author"
        verbose_name_plural = "Authors"

    def __str__(self):
        return self.name


class Book(models.Model):
    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        PUBLISHED = "published", "Published"

    title = models.CharField(max_length=200, verbose_name="Title")
    price = models.DecimalField(
        max_digits=10, decimal_places=2,
        verbose_name="Price",
        help_text="Selling price without tax",
    )
    author = models.ForeignKey(
        Author, on_delete=models.CASCADE, related_name="books",
        verbose_name="Author",
    )
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.DRAFT,
        verbose_name="Status",
    )
    published_at = models.DateTimeField(null=True, blank=True, verbose_name="Published at")

    class Meta:
        verbose_name = "Book"
        verbose_name_plural = "Books"
```

Rules:

1. **Always `verbose_name` on fields** and **`Meta.verbose_name`/`verbose_name_plural`**.
2. `help_text` only when the field needs it: `verbose_name="Price", help_text="Selling price without tax"`.
3. Choices: **display label, code value**. `DRAFT = "draft", "Draft"` keeps DB
   values language-free while the dropdown shows the label.

## 3. Translated content — `__str__` with an English-first lookup

When a model's display name lives in **translation rows** (its own `*Translation`
model instead of a direct `name`/`title` column), return the translated value
from `__str__` so related dropdowns, M2M widgets and inline rows show the
display name too. The convention: **prefer `en`, fall back to any available
language, then to the slug** (Spanish opt-in projects prefer `es`). Prefer a shared abstract mixin so every translated
model reuses the lookup:

```python
# common/models.py
from django.db import models


class BaseModel(models.Model):
    slug = models.SlugField(max_length=200, unique=True)
    class Meta:
        abstract = True


class TranslatableName(BaseModel):
    class Meta:
        abstract = True

    def translated_name(self, language="en"):
        t = self.translations.filter(language=language).first() or self.translations.first()
        return t.name if t else self.slug

    def __str__(self):
        return self.translated_name()


class Genre(TranslatableName):
    class Meta:
        verbose_name = "Genre"
        verbose_name_plural = "Genres"
    # slug and __str__ come from the bases


class GenreTranslation(models.Model):
    language = models.CharField(max_length=5, choices=[("en", "English"), ("es", "Spanish")])
    genre = models.ForeignKey(Genre, on_delete=models.CASCADE, related_name="translations")
    name = models.CharField(max_length=200, verbose_name="Name")
    class Meta:
        verbose_name = "Genre translation"
        verbose_name_plural = "Genre translations"
        constraints = [
            models.UniqueConstraint(fields=["genre", "language"], name="unique_genre_language")
        ]

    def __str__(self):
        return f"{self.genre} ({self.language})"   # e.g. "Fiction (en)"
```

Models whose translated field has a **different name** (e.g. `title` instead of
`name`) define the same lookup on the class itself:

```python
class Book(TranslatableName):
    def translated_title(self, language="en"):
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
    language = models.CharField(max_length=5, choices=[("en", "English"), ("es", "Spanish")])
    title = models.CharField(max_length=200, verbose_name="Title")
    class Meta:
        verbose_name = "Book translation"
        verbose_name_plural = "Book translations"
        constraints = [
            models.UniqueConstraint(fields=["book", "language"], name="unique_book_language")
        ]

    def __str__(self):
        return f"{self.book} ({self.language})"   # e.g. "Dune (en)"
```

## 4. Checklist — every model

- [ ] `Meta.verbose_name` and `Meta.verbose_name_plural` in the project's language
- [ ] `verbose_name` on every field
- [ ] `help_text` on non-obvious fields
- [ ] content-based `__str__` (direct name, or `TranslatableName` / `translated_title` for translated models)
- [ ] join / M2M-through models also get a content-based `__str__`
- [ ] translation rows return `"{parent} ({language})"`

## See also

- [[django-i18n-es-admin|Spanish Django Admin]] — the Spanish-literal variant of
  this rule (`LANGUAGE_CODE = "es"` + Spanish `verbose_name`/`help_text`/`__str__`).
- [[django-fixtures|Fixed Data Loading with Django Fixtures]] — reference data
  for models defined under these rules.
- [[django-unfold-admin|Unfold Admin Theme]] — admin-layer strings that build on
  the model texts.
