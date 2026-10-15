---
created: 2026-10-15
tags:
  - django
  - admin
  - unfold
  - filters
type: resource
status: active
source: templates://django/django-admin-filters.md
version: 2026-10-15+5e5a02d

---

# Django Admin Filters (Reusable Template, English Default)

> English by default. The Spanish-admin variant [Spanish Django Admin](./django-i18n-es-admin.md) owns the
> placeholder script `static/js/range_date_filter_es.js` — an English-default project omits it (see §10).
> The canonical admin base `project/admin_base.py::ModelAdminUnfoldBase` is defined in
> [Unfold Admin Theme](./django-unfold-admin.md) §7.2 and is **not** redefined here; neither is the Excel
> export flavor ([Excel Export](./django-excel-export.md) §5). Filters work identically on both flavors,
> because `list_filter` is inherited from `unfold.admin.ModelAdmin` either way.

**Stack:** Django 5.2.x, `django-unfold==0.77.1` (pinned). The Unfold filter classes listed in §4 and §9
are verified against that exact version — re-check class names, templates and form fields after any
Unfold bump (same policy as [Unfold Admin Theme](./django-unfold-admin.md) §5).

**How to use this doc:** read §2 to pick a filter class, drop the canonical module from §6 into the app,
wire it with §7, test it with §11. §13 is a complete worked example. §12 is the copy-paste checklist.

## 0. Prerequisites & scope

This layer assumes the [Unfold Admin Theme](./django-unfold-admin.md) layer is adopted, because a filter
class can only run inside an Unfold-styled admin.

- **No settings change is required.** The canonical `INSTALLED_APPS` of
  [Project Setup](./django-project-setup.md) already ships `unfold.contrib.filters` (before
  `django.contrib.admin`), which is where the filter classes in §4 and §9 live.
- **`list_filter_sheet` is already handled.** `ModelAdminUnfoldBase` sets `list_filter_sheet = False`,
  so the filter panel renders as a permanent sidebar column instead of Unfold's slide-over sheet.
  Unfold's own default is `True`; a raw `unfold.admin.ModelAdmin` keeps the sheet.
- **Scope:** changelist filtering — `list_filter` entries, custom filter classes, and the wiring around
  them. Out of scope: DRF query-parameter filtering (see [DRF](./django-drf.md) §12), the internals of
  `search_fields`, and the permission model.
- **Placeholders:** `project` (project package), `<APP_LABEL>` (domain app), `<MODEL>` (model class).
- **Adopting this layer:** `./pull.sh --stack django --layers admin-filters` — the base stack alone does
  **not** include this file. Then: create `<APP_LABEL>/admin_filters.py` from §6, declare the
  `list_filter` entries on the admin (§2), copy the CSS fence if a date input is involved (§7.2), and
  add the tests (§11). §13 is that whole sequence end to end.

### 0.1 Without Unfold

`unfold.contrib.filters` supplies §4 (range filters) and §9 (dropdowns, checkboxes, radios, numeric
sliders, autocomplete, facets), and `list_filter_submit` / `list_filter_sheet` are Unfold-only
attributes. A plain `django.contrib.admin` project can still use everything else:

| Works with the stock Django admin | Needs Unfold |
|---|---|
| §1 resolution, §2 decision table, §3 stock filters (including `RelatedOnlyFieldListFilter`) | §4 `RangeDateFilter`, `RangeDateTimeFilter`, `RangeNumericFilter`, `SliderNumericFilter`, `SingleNumericFilter` |
| §5 custom `SimpleListFilter` recipes — all of them | §9 dropdown / checkbox / radio / autocomplete classes and facets |
| §7.4 custom changelist context, §7.5 `list_editable`, §7.6 scoping and hiding | §7.1 `list_filter_submit`, §7.2 `list_filter_sheet` and the overlay it creates |
| §8 security & performance, §11 tests, §12 checklist | §10 the popup z-index fix (a stock admin has no overlay to escape) |

## 1. How `list_filter` resolves

`ModelAdmin.list_filter` accepts three shapes, and a single list may mix all of them:

```python
list_filter = [
    "status",                                   # 1. bare string → class chosen by field type
    ("published_at", RangeDateFilter),          # 2. (field, filter class) → field-bound filter
    HasItemsFilter,                             # 3. class → SimpleListFilter (model-bound)
]
```

| Shape | Django calls | Bind to | Identity |
|---|---|---|---|
| `"field"` | `FieldListFilter.create()` picks a class from the field type | a model field | the field path |
| `("field", Class)` | `Class(field, request, params, model, model_admin, field_path)` | a model field | the field path |
| `Class` | `Class(request, params, model, model_admin)` | the model | `parameter_name` |

The changelist pipeline for every filter:

```
request.GET ──► ChangeList(params)
             ──► filter.expected_parameters()    # which query-string keys this filter consumes
             ──► filter.used_parameters          # those keys, popped with their values
changelist_view ──► ChangeList.get_queryset()
                └► for each filter: qs = filter.queryset(request, qs)   # the actual narrowing
choices() ──► yields {"form": <unfold form>} ──► Unfold renders the sidebar entry
```

Three rules follow from that pipeline and drive the rest of this document:

1. **A filter must never raise.** Django calls `filter.queryset()` from `ChangeList.get_queryset()`
   *outside* any `try/except` — an exception in a filter is a `500` on the whole changelist. Bad or
   unparseable input must degrade to "no filtering" (§4.4, §8.5).
2. **`parameter_name` is the filter's identity.** Two filters in the same changelist sharing a
   `parameter_name` (or binding the same field path) collide. Keep it unique per admin.
3. **List order is sidebar order.** Put the filters people use first.

## 2. Decision table

Find the row that matches the data, then jump to the section that implements it. Anything a bare string
can express needs no class at all (§3).

| Situation | Use | Query string | Where |
|---|---|---|---|
| enum / `choices` field | bare string | `?status__exact=draft` | §3.1 |
| boolean flag | bare string | `?is_active__exact=1` | §3.1 |
| plain date (single) | bare string | `?created_at__year=2026&…__month=2` (hierarchy) or the presets via `__gte`/`__lt` | §3.1 |
| date **range** (from/to) | `("field", RangeDateFilter)` + `list_filter_submit` | `?field_from=&field_to=` | §4.1 |
| datetime range, whole days | `RangeDateFilter` subclass (`__date` lookups) | `?field_from=&field_to=` | §4.3 |
| datetime range, exact timestamps | `("field", RangeDateTimeFilter)` | `?field_from_0=&field_from_1=…` | §4.1 |
| numeric range | `("price", RangeNumericFilter)` / `SliderNumericFilter` | `?price_from=&price_to=` | §4.1 |
| FK / M2M, narrow to referenced rows | `("fk", RelatedOnlyFieldListFilter)` | `?fk__id__exact=` | §3.2 |
| FK / M2M, searchable or multi-select | `("fk", RelatedDropdownFilter)` (Unfold) | `?fk__id__exact=` (repeated) | §9 |
| free text "contains" | `FieldTextFilter` (Unfold) | `?field__icontains=` | §9 |
| "has any related rows" (with/without) | custom `SimpleListFilter` + `Exists` | `?param=with|without` | §5.1, §5.2 |
| "has a related row matching a condition" | custom `SimpleListFilter` + `Exists` (conditional) | `?param=with|without` | §5.7 |
| "related row is active/truthy" | custom `SimpleListFilter` + `Exists` | `?param=1|0` | §5.3 |
| options derived from the data (buckets) | custom `SimpleListFilter` + `aggregate()` | `?param=<bucket>` | §5.4 |
| computed bucket (hour of day, etc.) | custom `SimpleListFilter` + `annotate()` | `?param=<bucket>` | §5.5 |
| lifecycle by null/not-null | custom `SimpleListFilter` | `?param=open|closed` | §5.6 |
| high-cardinality column | **exclude** it; rely on `search_fields` + a query-string drill-down | `?field__exact=` | §8.2 |

## 3. Stock Django filters first (YAGNI)

Do not write a class for something a bare string already does — a hand-rolled filter is a permanent
maintenance cost.

### 3.1 Bare strings

`FieldListFilter.create()` walks its `_field_list_filters` table and returns the first class whose
predicate matches the field:

| Field type | Class chosen | Renders | Lookup key |
|---|---|---|---|
| `BooleanField` | `BooleanFieldListFilter` | Yes / No | `?field__exact=` |
| `DateField` / `DateTimeField` | `DateFieldListFilter` | Any date, Today, Past 7 days, This month, This year (plus No date / Has date when the field is nullable) | `?field__gte=` / `?field__lt=`, or the date-hierarchy drill-down `?field__year=` / `__month=` / `__day=` |
| field with `choices` | `ChoicesFieldListFilter` | one option per choice | `?field__exact=` |
| `ForeignKey` / `ManyToManyField` | `RelatedFieldListFilter` | one option per related row | `?field__<target>__exact=` (usually `?field__id__exact=`) |
| anything else — including plain `CharField`, `IntegerField`, `DecimalField` | `AllValuesFieldListFilter` | one option per distinct value | `?field=` |

> **The `choices` trap.** The parameter shape does not follow the field *type*, it follows the presence
> of `choices`: a `CharField(choices=…)` resolves to `ChoicesFieldListFilter` and therefore needs
> `?field__exact=value`, while the same field without `choices` needs `?field=value`. A hand-typed or
> bookmarked URL built with the wrong one is silently ignored (the changelist renders unfiltered, no
> error), which makes this the most common "the filter does nothing" report. Note also that
> `IntegerField`/`DecimalField` land in `AllValuesFieldListFilter` — a dropdown of every distinct
> number, not a range; use §4.1 for numeric ranges.

> `AllValuesFieldListFilter` builds its options from the admin's own `get_queryset(request)` — so a
> permission-scoped admin does not leak other users' values through it (§7.6).

### 3.2 `RelatedOnlyFieldListFilter` (FK / M2M)

A bare FK string (`"owner"`) renders **every** row of the related table. `RelatedOnlyFieldListFilter`
renders only the related rows actually referenced by the current queryset — the correct default for any
relation that can grow:

```python
from django.contrib.admin import RelatedOnlyFieldListFilter

list_filter = [
    ("owner", RelatedOnlyFieldListFilter),
]
```

Lookup key is `owner__id__exact` for a FK and, for a M2M, the field path followed by the target field
(e.g. `tags__id__exact`). That is also the URL you use for "drill-down" links from a change form
(§8.2). For searchable/multi-select versions see §9.

The entry may also be a **path through an intermediate model** — useful when the M2M has an explicit
`through` model and you want to filter on the far end:

```python
list_filter = [("links__target", RelatedOnlyFieldListFilter)]
```

The lookup key becomes the full path (`links__target__id__exact`), and only rows whose
*intermediate* record resolves to a referenced target are offered.

### 3.3 `date_hierarchy`

`date_hierarchy = "published_at"` is a filter, not a column: it renders a breadcrumb of years/months and
emits its own query-string keys (`?published_at__year=2026&published_at__month=2`). It is independent of
`list_filter`, may target the same field as a `RangeDateFilter`, and it composes with the other filters.
Django preserves the whole query string (filters included) across post-save redirects via
`add_preserved_filters`, so `list_editable` bulk edits return to the filtered view (§7.5).

### 3.4 `search_fields`

The complement to §8.2: for columns you deliberately keep out of the sidebar, `search_fields` is the
supported way in. It requires no filter class and is covered by [Unfold Admin Theme](./django-unfold-admin.md)
§7.2's base behavior.

## 4. Unfold range filters

### 4.1 Classes and parameter shapes

| Class | Binds to | Widget | Consumes | Emits |
|---|---|---|---|---|
| `RangeDateFilter` | `DateField` | from/to date inputs | `field_from`, `field_to` | `field__gte`, `field__lte` |
| `RangeDateTimeFilter` | `DateTimeField` | from/to date **and** time inputs | `field_from_0`, `field_from_1`, `field_to_0`, `field_to_1` | `field__gte`, `field__lte` |
| `RangeNumericFilter` | `Integer`/`Float`/`Decimal`/`AutoField` | from/to number inputs | `field_from`, `field_to` | `field__gte`, `field__lte` |
| `SliderNumericFilter` | same as above | slider bounded by `MIN`/`MAX` of the queryset | `field_from`, `field_to` | `field__gte`, `field__lte` |
| `SingleNumericFilter` | same as above | one number input | `field` | `field=` |
| `RangeNumericListFilter` | `SimpleListFilter` (no field) | from/to number inputs | `field_from`, `field_to` | `field__gte`, `field__lte` |

`parameter_name` defaults to the field path, so a tuple entry is all you need:

```python
from unfold.contrib.filters.admin import RangeDateFilter, RangeNumericFilter

list_filter = [
    ("published_at", RangeDateFilter),
    ("price", RangeNumericFilter),
]
```

A range filter bound to the wrong field type raises `TypeError` at admin-registration time
(`RangeDateFilter` requires a `DateField`, the numeric ones require a numeric field). That is a
fail-fast, not a runtime surprise — the error message names the class and the field.

### 4.2 `list_filter_submit` is mandatory for from/to filters

Unfold's `ModelAdmin.list_filter_submit` defaults to `False`, which reloads the changelist on every
input change. A from/to pair has two inputs, so without an explicit Apply button the first keystroke
triggers a reload and the second input is never reached. Set it whenever any filter in the list has more
than one input:

```python
class <MODEL>Admin(ModelAdminUnfoldBase):
    list_filter_submit = True
```

Filters with a single input (bare strings, dropdowns, radio) keep the default auto-submit behavior.

### 4.3 `RangeDateFilter` on a `DateTimeField`: make the end day inclusive

`RangeDateFilter` builds `field__gte` / `field__lte` from the parsed date. On a `DateTimeField` the
`__lte` value is midnight of the end date, so every row recorded **during** the end day is silently
dropped — the classic "date range that loses the last day" bug.

`DateTimeField` subclasses `DateField`, so `RangeDateFilter` accepts it (the `isinstance` guard passes);
overriding `queryset()` to filter on `__date` is the fix:

```python
from django.core.validators import EMPTY_VALUES
from unfold.contrib.filters.admin import RangeDateFilter
from unfold.utils import parse_date_str


class DayRangeFilter(RangeDateFilter):
    """RangeDateFilter for a DateTimeField: inclusive end day, bad input degrades.

    ``__date`` boundaries are whole days in the active timezone, so a row at
    14:00 on the end date is inside the range. Invalid input parses to ``None``
    and is skipped instead of raising.
    """

    def queryset(self, request, queryset):
        filters = {}
        value_from = self.used_parameters.get(f"{self.parameter_name}_from")
        value_to = self.used_parameters.get(f"{self.parameter_name}_to")

        if value_from not in EMPTY_VALUES and isinstance(value_from, str):
            parsed = parse_date_str(value_from)
            if parsed is not None:
                filters[f"{self.field_path}__date__gte"] = parsed

        if value_to not in EMPTY_VALUES and isinstance(value_to, str):
            parsed = parse_date_str(value_to)
            if parsed is not None:
                filters[f"{self.field_path}__date__lte"] = parsed

        return queryset.filter(**filters)
```

Use it exactly like `RangeDateFilter`: `("published_at", DayRangeFilter)`.

> Need exact timestamps instead of whole days? Use Unfold's `RangeDateTimeFilter`, which keeps the
> date and time as separate inputs. For "a day" semantics, prefer the subclass above.

### 4.4 Failure modes to respect

- **Unparseable input.** Unfold parses with `settings.DATE_INPUT_FORMATS`; a value that matches nothing
  becomes `None`. `queryset.filter(field__gte=None)` raises
  `ValueError: Cannot use None as a query value`, so a filter that passes the parsed value straight
  through must either pre-validate (§4.3) or be wrapped in `try/except`. Unfold's built-in classes do
  the latter; a hand-rolled `queryset()` must do one of the two.
- **Field type.** A `TypeError` at import/registration is better than a silent mismatch — keep the
  binding honest rather than writing a filter that "works" on the wrong type.
- **Timezone.** `__date` lookups use the active timezone (`settings.TIME_ZONE` by default). Keep that
  consistent with how the application groups by day.

## 5. Custom `SimpleListFilter` recipes

Use a custom class when the condition is semantic rather than a field comparison. The recurring shape is
"does this row have (any / no) matching related rows" — with or without conditions on those rows — which
is an **anti-join**.

### 5.1 With / without, via `Exists` / `~Exists`

```python
from django.contrib import admin
from django.db.models import Exists, OuterRef


class HasItemsFilter(admin.SimpleListFilter):
    title = "Items"
    parameter_name = "has_items"
    related = "items"  # reverse accessor or field path on <MODEL>

    def lookups(self, request, model_admin):
        return (("with", "With items"), ("without", "Without items"))

    def queryset(self, request, queryset):
        def matching():
            return queryset.model.objects.filter(
                pk=OuterRef("pk"), **{f"{self.related}__isnull": False}
            )

        if self.value() == "with":
            return queryset.filter(Exists(matching()))
        if self.value() == "without":
            return queryset.filter(~Exists(matching()))
        return queryset  # no value selected → untouched
```

Why not `queryset.filter(items__isnull=False)`?

- The JOIN fans out: one output row per related row, so the changelist shows duplicates and needs
  `.distinct()` — which costs more than the subquery.
- `~Q(items__isnull=False)` only "works" by accident on a single-valued relation. On a multi-valued one
  the JOIN produces one row per related object, and negating a JOIN condition is not the same as negating
  existence: the `NOT` applies to the joined rows, so a parent that has *some* matching and *some*
  non-matching related rows can still be excluded (or included) by the wrong branch. `~Exists(...)`
  compiles to `NOT EXISTS`, which is exactly "no matching row" — unconditionally.

Existence alone is often not enough — "has an **available** item" is the same shape with conditions on
the related rows. See §5.7.

### 5.2 A factory for the repeated case

When the same with/without filter is needed on several models, generate the concrete classes instead of
copy-pasting them. The only thing that must differ per call site is `parameter_name` (§1, rule 2):

```python
def has_related_filter(related, title, parameter_name):
    """Build a concrete HasItemsFilter subclass for one related accessor."""

    class _HasRelatedFilter(HasItemsFilter):
        pass

    _HasRelatedFilter.related = related
    _HasRelatedFilter.title = title
    _HasRelatedFilter.parameter_name = parameter_name
    return _HasRelatedFilter
```

```python
list_filter = [
    has_related_filter("items", "Items", "has_items"),
    has_related_filter("children", "Children", "has_children"),
]
```

Reusing the *same* class for two entries on one changelist is not possible: they would share
`parameter_name` and the second would overwrite the first's state.

### 5.3 "Related row is active" (cross-relation truthiness)

The correlated subquery can reference a different table, so a truthiness flag on a FK is a normal
`Exists`:

```python
class OwnerIsActiveFilter(admin.SimpleListFilter):
    title = "Owner active"
    parameter_name = "owner_is_active"

    def lookups(self, request, model_admin):
        return (("1", "Active"), ("0", "Inactive"))

    def queryset(self, request, queryset):
        active = Owner.objects.filter(pk=OuterRef("owner_id"), is_active=True)

        if self.value() == "1":
            return queryset.filter(Exists(active))
        if self.value() == "0":
            return queryset.filter(~Exists(active))
        return queryset
```

`OuterRef("owner_id")` uses the already-present FK column, avoiding one extra join compared with
`OuterRef("owner__pk")`.

### 5.4 Options derived from the data

When a numeric field has no `choices`, the option list can be computed from the table itself — e.g.
decade buckets from min/max:

```python
from django.db.models import Max, Min


class DecadeFilter(admin.SimpleListFilter):
    title = "Decade"
    parameter_name = "decade"
    field = "year"
    span = 10

    def lookups(self, request, model_admin):
        stats = model_admin.model.objects.aggregate(
            low=Min(self.field), high=Max(self.field)
        )
        if stats["low"] is None:  # empty table → no options, filter renders demoted
            return []
        start = (stats["low"] // self.span) * self.span
        end = (stats["high"] // self.span) * self.span
        return [
            (str(d), f"{d}–{d + self.span - 1}")
            for d in range(start, end + self.span, self.span)
        ]

    def queryset(self, request, queryset):
        if not self.value():
            return queryset
        low = int(self.value())
        return queryset.filter(**{f"{self.field}__gte": low, f"{self.field}__lt": low + self.span})
```

Cost note: `lookups()` runs on every changelist render. Two aggregates over one indexed column is
cheap; a `lookups()` that loads or counts large sets is not. Prefer a fixed list of buckets over a
"distinct values" query (§8.2).

#### Scope the option list to the requester

`lookups()` receives the `request`, so any option list built from the database must be narrowed to what
that user is allowed to see. An unscoped list enumerates values the user cannot otherwise reach — a
privacy leak that looks like a feature (see §8.1, and §7.6 for hiding the filter entirely):

```python
def lookups(self, request, model_admin):
    values = (
        model_admin.model.objects.order_by("owner_id")
        .values_list("owner_id", flat=True)
        .distinct()
    )
    if not request.user.is_superuser:
        values = values.filter(owner_id=request.user.get_username())
    return [(value, value) for value in values]
```

Hiding the filter (§7.6) is still required for a scoped admin — an option list that happens to contain
only one value tells the user which value it is.

### 5.5 Computed buckets, via `annotate()`

Derived buckets (hour of day, day of week, size class) need an annotation and a filter on it:

```python
from django.db.models.functions import ExtractHour


class ShiftFilter(admin.SimpleListFilter):
    title = "Shift"
    parameter_name = "shift"
    field = "started_at"
    # Arbitrary example buckets — define the app's own here and reuse the same
    # definition wherever the rest of the code groups by shift.
    bounds = {"early": (0, 8), "core": (8, 16), "late": (16, 24)}

    def lookups(self, request, model_admin):
        return (
            ("early", "Early 00–08"),
            ("core", "Core 08–16"),
            ("late", "Late 16–24"),
        )

    def queryset(self, request, queryset):
        if self.value() not in self.bounds:
            return queryset
        low, high = self.bounds[self.value()]
        return queryset.annotate(_bucket=ExtractHour(self.field)).filter(
            _bucket__gte=low, _bucket__lt=high
        )
```

Timezone note: `ExtractHour` uses the active timezone, consistent with `settings.TIME_ZONE` — keep the
buckets aligned with whatever logic the rest of the application uses for "day" boundaries.

### 5.6 Lifecycle states from null / not-null

Open vs closed, published vs draft-in-progress, resolved vs pending: a state that is implied by a
timestamp needs no extra column.

```python
class StateFilter(admin.SimpleListFilter):
    title = "State"
    parameter_name = "state"

    def lookups(self, request, model_admin):
        return (("open", "Open"), ("closed", "Closed"))

    def queryset(self, request, queryset):
        if self.value() == "open":
            return queryset.filter(ended_at__isnull=True)
        if self.value() == "closed":
            return queryset.filter(ended_at__isnull=False)
        return queryset
```

### 5.7 Related rows matching a condition

§5.1 answers "has any related row"; the frequent follow-up is "has a related row that **satisfies
something**" — with available works, with an unpaid invoice, with a published revision. Same anti-join,
conditions added inside the subquery:

```python
class HasAvailableItemsFilter(admin.SimpleListFilter):
    title = "Available items"
    parameter_name = "has_available_items"
    related = "items"                                    # reverse accessor or field path
    conditions = {"is_active": True, "status": "available"}

    def lookups(self, request, model_admin):
        return (("with", "With available items"), ("without", "Without available items"))

    def queryset(self, request, queryset):
        def matching():
            return queryset.model.objects.filter(
                pk=OuterRef("pk"),
                **{
                    f"{self.related}__{name}": value
                    for name, value in self.conditions.items()
                },
            )

        if self.value() == "with":
            return queryset.filter(Exists(matching()))
        if self.value() == "without":
            return queryset.filter(~Exists(matching()))
        return queryset
```

`~Exists(matching())` is where this recipe is usually got wrong. It means:

- ✅ "no related row satisfies **all** the conditions" — what the label promises;
- ❌ **not** "has no row with `is_active=True` **and** has no row with `status='available'`.

`NOT EXISTS (a ∧ b)` is not `¬a ∧ ¬b`. For the second reading, use two separate filters. The same trap
applies to the positive case when you negate a `Q` object instead of wrapping the whole subquery.

The condition value may also come from the selected option — same shape, parametrized:

```python
class RelatedMethodFilter(admin.SimpleListFilter):
    title = "Payment method"
    parameter_name = "related_method"

    def lookups(self, request, model_admin):
        return (("online", "Online"), ("cash", "Cash"), ("none", "No subscription"))

    def queryset(self, request, queryset):
        def with_method():
            return Related.objects.filter(parent=OuterRef("pk"), method=self.value())

        if self.value() in ("online", "cash"):
            return queryset.filter(Exists(with_method()))
        if self.value() == "none":
            return queryset.filter(~Exists(Related.objects.filter(parent=OuterRef("pk"))))
        return queryset
```

Note the `"none"` branch: it asks about existence *at all*, not about a matching value, so it uses a
different subquery than the value branches.

> If the same condition also feeds a displayed column, a conditional aggregate may beat a second
> subquery — `queryset.annotate(available=Count("items", filter=Q(items__is_active=True, items__status="available"), distinct=True)).filter(available__gt=0)`
> (`Count` and `Q` from `django.db.models`), or `.filter(available=0)` for the negation. Same semantics,
> and the count is reusable in `list_display`. `distinct=True` is required when the annotation joins a
> multi-valued relation.

### 5.8 Contract checklist for every custom filter

- `title` is a human label; it is the sidebar heading.
- `parameter_name` is unique within the changelist (§1, rule 2) and stable — it appears in URLs people
  bookmark and in drill-down links.
- `value()` (the `SimpleListFilter` default) returns the raw query-string value; compare against it,
  never against `request.GET` directly, so the filter keeps working when Django strips its own keys.
- Return `queryset` **untouched** when no value is selected — do not return `queryset.none()`, and do
  not return `None` unless you mean "leave the queryset alone" (Unfold's numeric mixin uses `None` for
  that).
- Never raise from `queryset()`: validate, or wrap in `try/except` (§1, rule 1; §4.4).
- A `lookups()` built from the database must be scoped to `request.user` (§5.4) — an option list is
  still data the user can read.
- If a filter needs a permission hidden, handle it in `get_list_filter()` (§7.6), not here.

## 6. Canonical `<APP_LABEL>/admin_filters.py` (copy-paste)

Filter classes live next to the app that owns the model, one module per app. This is the canonical
skeleton — paste it and keep what the app needs:

```python
"""Changelist filters for <APP_LABEL>.

Reusable pieces first (with/without, its factory, and the condition matcher),
then the app's concrete filters. Imported by <APP_LABEL>/admin.py; never
imported by models.
"""

from django.contrib import admin
from django.core.validators import EMPTY_VALUES
from django.db.models import Exists, OuterRef

from unfold.contrib.filters.admin import RangeDateFilter
from unfold.utils import parse_date_str


class HasRelatedFilter(admin.SimpleListFilter):
    """With / without related rows, implemented as EXISTS / NOT EXISTS.

    Subclasses set ``related`` (reverse accessor or field path), ``title`` and a
    unique ``parameter_name`` — prefer the ``has_related_filter`` factory below.
    """

    related = None

    def lookups(self, request, model_admin):
        return (("with", "With related"), ("without", "Without related"))

    def queryset(self, request, queryset):
        def matching():
            return queryset.model.objects.filter(
                pk=OuterRef("pk"), **{f"{self.related}__isnull": False}
            )

        if self.value() == "with":
            return queryset.filter(Exists(matching()))
        if self.value() == "without":
            return queryset.filter(~Exists(matching()))
        return queryset


def has_related_filter(related, title, parameter_name):
    """Build a concrete HasRelatedFilter subclass (unique parameter_name per use)."""

    class _HasRelatedFilter(HasRelatedFilter):
        pass

    _HasRelatedFilter.related = related
    _HasRelatedFilter.title = title
    _HasRelatedFilter.parameter_name = parameter_name
    return _HasRelatedFilter


class HasMatchingRelatedFilter(admin.SimpleListFilter):
    """With / without related rows that satisfy ``conditions`` (§5.7).

    ``conditions`` maps related-field lookups to values; an empty dict means
    "any related row", the same semantic as HasRelatedFilter. ``parameter_name``
    must be unique per changelist (§5.8).
    """

    related = None
    conditions = {}

    def lookups(self, request, model_admin):
        return (("with", "With matching"), ("without", "Without matching"))

    def queryset(self, request, queryset):
        lookups = {
            f"{self.related}__{name}": value
            for name, value in self.conditions.items()
        }
        if not lookups:
            lookups = {f"{self.related}__isnull": False}

        def matching():
            return queryset.model.objects.filter(pk=OuterRef("pk"), **lookups)

        if self.value() == "with":
            return queryset.filter(Exists(matching()))
        if self.value() == "without":
            return queryset.filter(~Exists(matching()))
        return queryset


class DayRangeFilter(RangeDateFilter):
    """RangeDateFilter for a DateTimeField — end day inclusive, bad input ignored."""

    def queryset(self, request, queryset):
        filters = {}
        value_from = self.used_parameters.get(f"{self.parameter_name}_from")
        value_to = self.used_parameters.get(f"{self.parameter_name}_to")

        if value_from not in EMPTY_VALUES and isinstance(value_from, str):
            parsed = parse_date_str(value_from)
            if parsed is not None:
                filters[f"{self.field_path}__date__gte"] = parsed

        if value_to not in EMPTY_VALUES and isinstance(value_to, str):
            parsed = parse_date_str(value_to)
            if parsed is not None:
                filters[f"{self.field_path}__date__lte"] = parsed

        return queryset.filter(**filters)


class RelatedIsActiveFilter(admin.SimpleListFilter):
    """Rows whose FK ``lookup`` points at an active related row."""

    title = "Related active"
    parameter_name = "related_is_active"
    lookup = "owner"          # FK name on the model
    target = None             # related model (set in the app's module)
    target_flag = "is_active"

    def lookups(self, request, model_admin):
        return (("1", "Active"), ("0", "Inactive"))

    def queryset(self, request, queryset):
        active = self.target.objects.filter(
            pk=OuterRef(f"{self.lookup}_id"), **{self.target_flag: True}
        )
        if self.value() == "1":
            return queryset.filter(Exists(active))
        if self.value() == "0":
            return queryset.filter(~Exists(active))
        return queryset
```

`RelatedIsActiveFilter` above is a skeleton: `target` is `None`, so binding it is not optional. Set it
in the same module, with the model imported at the top:

```python
class OwnerActiveFilter(RelatedIsActiveFilter):
    """Rows whose ``owner`` FK points at an active user."""

    target = Owner            # from <APP_LABEL>.models import Owner
```

Putting the unbound base class itself in `list_filter` registers fine and then fails on the first
changelist load (`None.objects`) — bind it or leave it out.

Wire it in `<APP_LABEL>/admin.py` — filter *classes* live in `admin_filters.py`, the `list_filter`
*entry* stays on the admin:

```python
from <APP_LABEL>.admin_filters import has_related_filter
from <APP_LABEL>.models import <MODEL>
from project.admin_base import ModelAdminUnfoldBase


@admin.register(<MODEL>)
class <MODEL>Admin(ModelAdminUnfoldBase):
    list_filter = [
        "status",
        has_related_filter("items", "Items", "has_items"),
    ]
```

Conventions:

- One `admin_filters.py` per app; it holds only filter classes and the factory. Shared helpers that two
  apps need belong to the app that owns the model, and the other app imports from there.
- Keep `admin_filters.py` free of side effects and registration — importing it must never register a
  model.
- Names are label-carrying (`HasRelatedFilter`, `DayRangeFilter`) so tests can assert on the classes
  rather than on strings.

## 7. Wiring & interactions

### 7.1 `list_filter_submit`

Unfold's default is `False` (auto-apply on change). Set `True` on the admin as soon as one filter has
two inputs — range date, range numeric, slider (§4.2):

```python
class <MODEL>Admin(ModelAdminUnfoldBase):
    list_filter_submit = True
```

### 7.2 Sheet vs sidebar, and the popup z-index fix

`ModelAdminUnfoldBase` sets `list_filter_sheet = False`, so filters are a permanent sidebar column.
On narrow viewports Unfold collapses the panel into a fixed `z-60` overlay, which traps the date/clock
popups *underneath* it. If any filter uses a date/datetime input (or the changelist has
`date_hierarchy`), add the stylesheet:

```css
/* static/css/admin_filters.css
   Keep the changelist filter date/time popups above Unfold's filter overlay
   (#changelist-filter is a fixed z-60 layer on narrow viewports). */
.calendarbox,
.clockbox {
    z-index: 100;
}
```

Inject it from the admin that needs it, so the rest of the admin does not pay for it:

```python
from django import forms


class <MODEL>Admin(ModelAdminUnfoldBase):
    @property
    def media(self):
        return super().media + forms.Media(css={"all": ["css/admin_filters.css"]})
```

### 7.3 Filters next to `date_hierarchy`

Both may target the same field and neither replaces the other: the hierarchy emits
`?field__year=&field__month=`, a range filter emits `?field_from=&field_to=`. They compose (AND), and the
hierarchy breadcrumb stays visible above the filtered list. Do not remove `date_hierarchy` because a
range filter was added — they serve different navigation speeds.

### 7.4 Filters feeding custom changelist context

`ChangeList` exposes the filtered queryset (`cl.queryset`) and the unfiltered baseline
(`cl.root_queryset`). Reading both in `changelist_view()` lets a header show "this view" next to
"whole table" — the totals follow the active filters without an extra query per filter:

```python
from django.db.models import Count, Q, Sum


def _totals(queryset):
    """Per-currency income / expenses / net for a ledger queryset."""
    rows = []
    for row in (
        queryset.values("currency")
        .annotate(
            income=Sum("amount", filter=Q(amount__gt=0)),
            expenses=Sum("amount", filter=Q(amount__lt=0)),
            net=Sum("amount"),
            count=Count("id"),
        )
        .order_by("currency")
    ):
        rows.append({**row, **{key: row[key] or 0 for key in ("income", "expenses", "net")}})
    return rows


def changelist_view(self, request, extra_context=None):
    response = super().changelist_view(request, extra_context)
    context = getattr(response, "context_data", None)
    if context is None or "cl" not in context:
        return response  # e.g. a redirect after a bulk action
    cl = context["cl"]
    context["totals"] = {
        "filtered": _totals(cl.queryset),       # respects every active filter
        "full": _totals(cl.root_queryset),      # pre-filter baseline
    }
    return response
```

> `Sum(..., filter=Q(...))` assumes a signed amount (income positive, expenses negative). For another
> sign convention, swap the two `Q` objects — the shape of the helper does not change.

Render it with `list_after_template = "admin/<app>/<model>/totals.html"`. The template only reads
`totals`; the two scopes are the keys set above:

```html
{# <APP_LABEL>/templates/admin/<app>/<model>/totals.html #}
{% if totals %}
    <table>
        <thead>
            <tr>
                <th>View</th><th>Currency</th><th>Count</th>
                <th>Income</th><th>Expenses</th><th>Net</th>
            </tr>
        </thead>
        <tbody>
            {% for scope, rows in totals.items %}
                {% for row in rows %}
                    <tr>
                        <td>{% if scope == "filtered" %}Current view{% else %}Whole table{% endif %}</td>
                        <td>{{ row.currency }}</td>
                        <td>{{ row.count }}</td>
                        <td>{{ row.income|floatformat:2 }}</td>
                        <td>{{ row.expenses|floatformat:2 }}</td>
                        <td>{{ row.net|floatformat:2 }}</td>
                    </tr>
                {% empty %}
                    <tr><td colspan="6">No rows for this scope.</td></tr>
                {% endfor %}
            {% endfor %}
        </tbody>
    </table>
{% endif %}
```

> An app-local `templates/` directory resolves through `APP_DIRS=True`, which the canonical `TEMPLATES`
> setup enables — no extra `DIRS` entry needed.

Always guard for `context_data`/`"cl"` being absent — bulk actions and delete confirmations go through
the same view method.

### 7.5 Filters and `list_editable`

Bulk edits from the changelist are safe with filters: Django's `add_preserved_filters` re-attaches the
query string on the post-save redirect, so the user lands back on the same filtered view. No extra work
is required — but it is the reason filter query-string keys must be stable (§5.8).

### 7.6 Scoping and hiding are two different things

`get_queryset()` is the enforcement; `get_list_filter()` is only presentation/privacy. A scoped admin
should do both:

```python
def get_queryset(self, request):
    queryset = super().get_queryset(request)
    if request.user.is_superuser:
        return queryset
    return queryset.filter(owner=request.user)  # the real boundary


def get_list_filter(self, request):
    if request.user.is_superuser:
        return self.list_filter

    def key(entry):
        if isinstance(entry, (tuple, list)):
            return entry[0]                                  # ("field", FilterClass) → field
        return getattr(entry, "parameter_name", entry)        # SimpleListFilter → parameter_name
    return [entry for entry in self.list_filter if key(entry) != "owner"]
```

Hiding a filter that enumerates other users' values is a privacy control, not a permission: the
query-string key remains guessable, and `get_queryset()` is what makes a tampered `?owner=…` harmless.
The `key()` helper must handle both shapes because `list_filter` mixes them (§1).

### 7.7 The Excel export flavor

`ModelAdminUnfoldExportBase` ([Excel Export](./django-excel-export.md) §5) inherits from the same
Unfold `ModelAdmin`, so everything in this doc applies unchanged. Bulk exports respect the active
filters because they receive the filtered `queryset` from the changelist action.

## 8. Security & performance

### 8.1 Never let a filter decide access

All filtering happens **after** `get_queryset()` in the changelist pipeline, so a filter can only
narrow what the user could already see. Keep it that way: do not move scoping logic into a filter
"for convenience", and do not use a filter's absence as a security gate (§7.6).

One leak survives row scoping: the **option lists**. A `lookups()` built from the database returns values
as data, independent of the filtered rows, so it must be scoped to `request.user` too (§5.4) — otherwise
a scoped staff member sees every other user's values in the sidebar even though the list shows only their
own rows.

### 8.2 High-cardinality columns: exclude, don't render

An `AllValuesFieldListFilter` builds one option per distinct value from the admin queryset. For a
column with thousands of values that is a slow render and an unusable dropdown (and it enumerates
data). Exclude it and give the user two purposeful ways in instead:

```python
list_filter = ["status"]                  # "<high_card_field>" deliberately excluded
search_fields = ["title", "<high_card_field>"]
```

and link to the filtered changelist from wherever the value is known (a related change form, a report):

```python
url = reverse("admin:<app>_<model>_changelist") + "?" + urlencode({"title__exact": value})
```

`?field__exact=` works even when the field has no sidebar entry, because a query-string filter does not
require a registered filter class.

### 8.3 Prefer correlated `EXISTS` over JOIN + `distinct()`

The with/without, conditional and truthiness recipes (§5.1–§5.3, §5.7) compile to correlated subqueries:
one row per parent, no `DISTINCT`, and an index-friendly `NOT EXISTS` for the negative case. A JOIN-based
equivalent fans out rows, needs deduplication, and changes semantics for negations. Reach for `Exists`
whenever the question is "does a matching row exist".

### 8.4 Know what runs on every render

Two methods run on every changelist load — keep them cheap:

- `lookups()` — the option list. Fixed tuples are free; aggregates are one query (§5.4); `distinct()`
  over a big table is not. Any list built from the database must also be scoped to `request.user` (§5.4).
- `choices()` (Unfold's range classes) — `SliderNumericFilter` additionally aggregates `MIN`/`MAX` of the
  field to bound the slider.

### 8.5 Degrade, never 500

Given §1 rule 1, every `queryset()` must be total: valid input narrows, anything else returns the queryset
untouched. That covers a hand-typed URL, a bookmarked link from an older schema, and a value that no
longer parses.

## 9. Unfold filter catalog (reference)

Everything below is imported from `unfold.contrib.filters.admin` (verified against `django-unfold==0.77.1`).

| Group | Classes | Use when |
|---|---|---|
| Dropdown | `DropdownFilter`, `ChoicesDropdownFilter`, `MultipleChoicesDropdownFilter`, `RelatedDropdownFilter`, `MultipleRelatedDropdownFilter` | a `<select>` is preferred over a radio/checkbox list; the `Multiple*` variants accept repeated values |
| Checkbox / radio | `CheckboxFilter`, `ChoicesCheckboxFilter`, `AllValuesCheckboxFilter`, `RelatedCheckboxFilter`, `RadioFilter`, `ChoicesRadioFilter`, `BooleanRadioFilter` | 2–6 options that benefit from being always visible (no click to open) |
| Date / datetime | `RangeDateFilter`, `RangeDateTimeFilter` | from/to ranges (§4) |
| Numeric | `SingleNumericFilter`, `RangeNumericFilter`, `RangeNumericListFilter`, `SliderNumericFilter` | exact value, range, or a slider bounded by the data |
| Autocomplete | `AutocompleteSelectFilter`, `AutocompleteSelectMultipleFilter` | relations too large for a dropdown — requires the target admin's `search_fields` |
| Text | `TextFilter`, `FieldTextFilter` | user-typed "contains" matching without a `search_fields` round-trip |

Swap-in example — the same relation, Unfold-styled and searchable:

```python
from unfold.contrib.filters.admin import RelatedDropdownFilter

list_filter = [("owner", RelatedDropdownFilter)]   # instead of RelatedOnlyFieldListFilter (§3.2)
```

### Facets (result counts next to each option)

Django computes facet counts only when the changelist is asked for them, and Unfold's filter classes
already render them when present:

```
ChangeList.add_facets  ⇐  ModelAdmin.show_facets is ShowFacets.ALWAYS
                          or (ShowFacets.ALLOW and "?_facets=True" in the request)
```

- `ModelAdmin.show_facets` defaults to `ShowFacets.ALLOW` (counts offered, opt-in per request).
- `ShowFacets.ALWAYS` computes counts on every load; `ShowFacets.NEVER` disables the machinery.
- Counts come from `Filter.get_facet_queryset(changelist)`, which re-runs the changelist queryset with
  that filter's own parameters excluded — so facet counts are per-option, not per-current-selection, and
  they cost one aggregate per filter.

Enable per admin, not globally, and only where the extra queries buy something:

```python
from django.contrib.admin import ShowFacets


class <MODEL>Admin(ModelAdminUnfoldBase):
    show_facets = ShowFacets.ALWAYS
```

## 10. Assets

`pull.sh` vendors Markdown only — there is no asset copying — so every non-Markdown piece a project
needs must be reproduced from a fence in this doc:

| Asset | Where it lives | Needed when |
|---|---|---|
| `static/css/admin_filters.css` | §7.2 | any date/datetime filter input, or `date_hierarchy` |
| `static/js/range_date_filter_es.js` | [Spanish Django Admin](./django-i18n-es-admin.md) §`range_date_filter_es.js` | **Spanish only** — an English-default project omits it |

The placeholder script rewrites Unfold's English from/to placeholders by input `name`:

```js
{ names: ["created_at_from", "updated_at_from"], text: "Desde" }
```

It only covers the `[name]` values listed in its `texts` array. Any new range filter (e.g.
`published_at_from`) needs its pair added there, or it keeps the English placeholder — harmless in an
English admin, visible in a Spanish one.

## 11. Testing the filter layer

Runner and allowed bases: [Testing Contract (Django-only Runner)](./django-testing-contract.md) —
`TestCase` + `RequestFactory` + the test client. Four assertions cover a filter: composition, behavior
in isolation, behavior over HTTP, and the permission/scoping interaction.

```python
from django.contrib import admin
from django.contrib.admin import RelatedOnlyFieldListFilter
from django.test import RequestFactory, TestCase

from <APP_LABEL>.admin_filters import DayRangeFilter, has_related_filter
from <APP_LABEL>.models import <MODEL>


class <MODEL>FilterTests(TestCase):
    def setUp(self):
        self.request = RequestFactory().get("/admin/")
        self.model_admin = admin.site._registry[<MODEL>]

    def test_composition(self):
        """The admin declares the filters the changelist UI depends on."""
        self.assertIn("status", self.model_admin.list_filter)
        self.assertIn(("published_at", DayRangeFilter), self.model_admin.list_filter)
        self.assertIn(("owner", RelatedOnlyFieldListFilter), self.model_admin.list_filter)
        self.assertTrue(self.model_admin.list_filter_submit)   # range filters present ⇒ submit

    def test_with_without_isolated(self):
        """Drive queryset() directly with a hand-built params dict."""
        filter_class = has_related_filter("items", "Items", "has_items")
        instance = filter_class(
            self.request, {"has_items": ["with"]}, <MODEL>, self.model_admin
        )
        result = instance.queryset(self.request, <MODEL>.objects.all())
        self.assertIn(self.with_items, result)
        self.assertNotIn(self.without_items, result)

    def test_param_applies_over_http(self):
        """One end-to-end check that the query-string key is the real one.

        A ``choices`` field resolves to ChoicesFieldListFilter, so its key is
        ``<field>__exact`` (§3.1) — not the bare field name.
        """
        response = self.client.get(
            reverse("admin:<app>_<model>_changelist"), {"status__exact": "draft"}
        )
        self.assertEqual(response.status_code, 200)
        ids = {obj.pk for obj in response.context["cl"].result_list}
        self.assertIn(self.draft.pk, ids)

    def test_invalid_input_degrades(self):
        """A garbage value must not 500 the changelist."""
        response = self.client.get(
            reverse("admin:<app>_<model>_changelist"), {"published_at_from": "not-a-date"}
        )
        self.assertEqual(response.status_code, 200)
```

`response.context["cl"].result_list` is the filtered result list — assert against `pk` sets, not against
rendered HTML. For a scoped admin, add one test per view mode asserting the filter is absent from
`get_list_filter(request)` for a non-privileged user (§7.6).

## 12. Checklist

- [ ] Class chosen from §2 — and check §3 first: a bare string may already do it.
- [ ] Custom class ⇒ implemented in `<APP_LABEL>/admin_filters.py` (§6) with a unique `parameter_name`.
- [ ] "Has a related row matching X" ⇒ conditions **inside** the `Exists` subquery, never a negated `Q` (§5.7).
- [ ] Any `lookups()` built from the database ⇒ scoped to `request.user` (§5.4).
- [ ] Any from/to filter (or two-input control) ⇒ `list_filter_submit = True` (§7.1).
- [ ] Date/datetime input or `date_hierarchy` ⇒ `admin_filters.css` injected via `media` (§7.2).
- [ ] `DateTimeField` range ⇒ `DayRangeFilter`-style `__date` subclass, not the base range filter (§4.3).
- [ ] Filters that enumerate values ⇒ verify cardinality; exclude high-cardinality fields (§8.2).
- [ ] Scoped admin ⇒ scope in `get_queryset()` **and** hide the filter in `get_list_filter()` (§7.6).
- [ ] Every `queryset()` degrades on bad input — nothing raises (§4.4, §8.5).
- [ ] Tests: composition, isolation, over-HTTP, invalid input (§11).
- [ ] Run `<venv>/bin/python manage.py test <APP_LABEL>` (Django-only runner, §11).

## 13. Worked example: filters on `<MODEL>`

A complete, self-contained pass over the same model: a choices field, a `DateTimeField`, a decimal, a
FK, an M2M, and a condition on the related rows. Copy the four blocks in order.

### 13.1 The model

```python
# <APP_LABEL>/models.py
from django.conf import settings
from django.db import models


class Tag(models.Model):
    name = models.CharField(max_length=64, unique=True)
    is_active = models.BooleanField(default=True, db_index=True)

    def __str__(self):
        return self.name


class <MODEL>(models.Model):
    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        PUBLISHED = "published", "Published"

    title = models.CharField(max_length=200)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.DRAFT)
    published_at = models.DateTimeField(null=True, blank=True)
    price = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    tags = models.ManyToManyField(Tag, blank=True)

    def __str__(self):
        return self.title
```

> Minimal on purpose: only the fields the filters touch. For the full model convention
> (`Meta.verbose_name`, per-field `verbose_name`/`help_text`, content-based `__str__`) see
> [Model Definitions](./django-model-definitions.md).

### 13.2 The filters

Paste §6's module into `<APP_LABEL>/admin_filters.py`, then append the app-specific pieces: the
whole-day subclass (§4.3), the with/without tags filter from the factory (§5.2), and a
condition-on-the-related-rows filter (§5.7).

```python
# <APP_LABEL>/admin_filters.py  ← §6's module, then:

class PublishedDayRangeFilter(DayRangeFilter):
    """Whole-day range on published_at (DateTimeField) — §4.3."""


# Concrete subclass with its own parameter_name — §5.2.
HasTagsFilter = has_related_filter("tags", "Tags", "has_tags")


class HasActiveTagsFilter(HasMatchingRelatedFilter):
    """Tags that exist *and* are active — a condition, not mere existence (§5.7)."""

    related = "tags"
    title = "Active tags"
    parameter_name = "has_active_tags"
    conditions = {"is_active": True}
```

### 13.3 The admin

```python
# <APP_LABEL>/admin.py
from django import forms
from django.contrib import admin
from django.contrib.admin import RelatedOnlyFieldListFilter
from unfold.contrib.filters.admin import RangeNumericFilter

from project.admin_base import ModelAdminUnfoldBase
from <APP_LABEL>.admin_filters import (
    HasActiveTagsFilter,
    HasTagsFilter,
    PublishedDayRangeFilter,
)
from <APP_LABEL>.models import <MODEL>


@admin.register(<MODEL>)
class <MODEL>Admin(ModelAdminUnfoldBase):
    list_display = ("title", "status", "published_at", "price", "owner")
    list_filter = [
        "status",                                             # 1. bare string (§3.1)
        ("published_at", PublishedDayRangeFilter),            # 2. datetime range, whole days (§4.3)
        ("price", RangeNumericFilter),                        # 3. numeric range (§4.1)
        ("owner", RelatedOnlyFieldListFilter),                # 4. FK, only referenced rows (§3.2)
        HasTagsFilter,                                        # 5. with/without M2M (§5.1)
        HasActiveTagsFilter,                                  # 6. M2M with a condition (§5.7)
    ]
    list_filter_submit = True                                 # §4.2 — two-input filters present
    date_hierarchy = "published_at"                           # §3.3 — independent of the range filter
    search_fields = ("title",)
    autocomplete_fields = ("owner", "tags")                   # needs search_fields on their admins

    @property
    def media(self):
        # §7.2 — date inputs present, so the popup z-index fix is required
        return super().media + forms.Media(css={"all": ["css/admin_filters.css"]})

    def get_queryset(self, request):
        return (
            super()
            .get_queryset(request)
            .select_related("owner")
            .prefetch_related("tags")
        )
```

### 13.4 The test

```python
# <APP_LABEL>/tests.py
from datetime import datetime

from django.contrib import admin
from django.contrib.admin import RelatedOnlyFieldListFilter
from django.test import RequestFactory, TestCase
from django.urls import reverse
from django.utils import timezone

from <APP_LABEL>.admin_filters import HasActiveTagsFilter, PublishedDayRangeFilter
from <APP_LABEL>.models import <MODEL>, Tag


class <MODEL>AdminFilterTests(TestCase):
    def setUp(self):
        self.request = RequestFactory().get("/admin/")
        self.model_admin = admin.site._registry[<MODEL>]
        self.tag = Tag.objects.create(name="spring")
        self.tagged = <MODEL>.objects.create(
            title="Tagged",
            published_at=timezone.make_aware(datetime(2026, 3, 14, 14, 0)),
        )
        self.tagged.tags.add(self.tag)
        self.untagged = <MODEL>.objects.create(title="Untagged")
        self.url = reverse("admin:<app>_<model>_changelist")

    def test_composition(self):
        self.assertIn("status", self.model_admin.list_filter)
        self.assertIn(("published_at", PublishedDayRangeFilter), self.model_admin.list_filter)
        self.assertIn(("owner", RelatedOnlyFieldListFilter), self.model_admin.list_filter)
        self.assertIn(HasActiveTagsFilter, self.model_admin.list_filter)
        self.assertTrue(self.model_admin.list_filter_submit)

    def test_end_day_is_inclusive(self):
        response = self.client.get(
            self.url, {"published_at_from": "2026-03-14", "published_at_to": "2026-03-14"}
        )
        ids = {obj.pk for obj in response.context["cl"].result_list}
        self.assertIn(self.tagged.pk, ids)          # 14:00 row kept — the §4.3 fix
        self.assertNotIn(self.untagged.pk, ids)

    def test_with_without_tags(self):
        response = self.client.get(self.url, {"has_tags": "with"})
        ids = {obj.pk for obj in response.context["cl"].result_list}
        self.assertEqual(ids, {self.tagged.pk})

    def test_condition_on_related_rows(self):
        """§5.7 — the row has a tag, but not an *active* one.

        Existence and "matches the condition" are different questions: ``with``
        must exclude it while ``without`` includes it.
        """
        self.tag.is_active = False
        self.tag.save(update_fields=["is_active"])

        with_active = self.client.get(self.url, {"has_active_tags": "with"})
        without_active = self.client.get(self.url, {"has_active_tags": "without"})
        self.assertNotIn(
            self.tagged.pk, {o.pk for o in with_active.context["cl"].result_list}
        )
        self.assertIn(
            self.tagged.pk, {o.pk for o in without_active.context["cl"].result_list}
        )

    def test_invalid_date_degrades(self):
        response = self.client.get(self.url, {"published_at_from": "not-a-date"})
        self.assertEqual(response.status_code, 200)
        self.assertIn(self.untagged.pk, {o.pk for o in response.context["cl"].result_list})
```

Run it with the canonical runner:

```bash
venv/bin/python manage.py test <APP_LABEL> --verbosity=2
```
