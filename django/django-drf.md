---
created: 2026-08-10
tags:
  - django
  - drf
  - api
  - rest
  - documentation
type: resource
status: active
source: templates://django/django-drf.md
version: 2026-09-27+57b0fd3

---

# Django REST Framework (DRF) Implementation Guide (Optional, English Default)

> Optional — adopt only if the project exposes a REST API. DRF-only sections (Token auth, `TokenAdmin`) are guarded; omit if no DRF. Canonical API prefix is `/api/` (router root). `project/urls.py` snippet here merges with [Project Setup](./django-project-setup.md) §10 — do not overwrite the admin redirect.

This document is a reusable blueprint for wiring **Django REST Framework** into any Django project using a consistent, production-ready set of patterns: global pagination, a custom exception handler, dual authentication, viewsets with dynamic serializers, and public proxy endpoints.

All code snippets use a sample `Article` model so they can be copied and adapted to any domain.

---

## 1. Dependencies

Add the following packages to `requirements.txt`:

```text
# drf & filtering
djangorestframework>=3.16.1
django-filter>=24.3
```

`django-filter` is optional, but it is included here because it is commonly enabled later (see [Section 12](#12-filtering-optional)).

Install them:

```sh
pip install -r requirements.txt
```

---

## 2. Installed Apps

Add `rest_framework` to `INSTALLED_APPS` in `settings.py`. Add `rest_framework.authtoken` only if you want the bundled Token model for API authentication (recommended when using Token auth):

```python
INSTALLED_APPS = [
    # ... your apps
    "rest_framework",
    "rest_framework.authtoken",  # only if using Token authentication
]
```

After adding an app, run migrations:

```sh
python manage.py migrate
```

---

## 3. Global DRF Settings

All global behaviour is configured through the `REST_FRAMEWORK` dictionary in `settings.py`:

```python
REST_FRAMEWORK = {
    "DEFAULT_PERMISSION_CLASSES": ("rest_framework.permissions.IsAuthenticated",),
    "DEFAULT_PAGINATION_CLASS": "project.pagination.CustomPageNumberPagination",
    "PAGE_SIZE": 12,
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework.authentication.TokenAuthentication",
        "rest_framework.authentication.SessionAuthentication",
    ),
    "EXCEPTION_HANDLER": "project.handlers.custom_exception_handler",
}
```

| Setting | Purpose |
| --- | --- |
| `DEFAULT_PERMISSION_CLASSES` | Fallback permission applied to **every** endpoint unless a view overrides it. `IsAuthenticated` locks everything down by default. |
| `DEFAULT_PAGINATION_CLASS` | Global pagination class. Every list endpoint inherits it automatically. |
| `PAGE_SIZE` | Default number of items per page (used when the pagination class does not define its own). |
| `DEFAULT_AUTHENTICATION_CLASSES` | Ordered list of authentication schemes tried on each request. Token auth is tried first, then session auth. |
| `EXCEPTION_HANDLER` | Global function that reshapes every DRF error response into a consistent format. |

---

## 4. Global Pagination

A custom pagination class gives every list endpoint the same paginated envelope and lets clients control page size per request.

Create `project/pagination.py`:

```python
from rest_framework.pagination import PageNumberPagination
from rest_framework.response import Response


class CustomPageNumberPagination(PageNumberPagination):
    page_size = 12
    page_size_query_param = "page_size"
    max_page_size = 100

    def get_paginated_response(self, data):
        return Response(
            {
                "count": self.page.paginator.count,
                "next": self.get_next_link(),
                "previous": self.get_previous_link(),
                "page": self.page.number,
                "page_size": self.get_page_size(self.request),
                "total_pages": self.page.paginator.num_pages,
                "results": data,
            }
        )
```

- `page_size` — default items per page (overrides the `PAGE_SIZE` setting).
- `page_size_query_param` — client-side override parameter name (`?page_size=50`).
- `max_page_size` — hard cap so clients cannot request huge pages.
- `get_paginated_response` — enriches the envelope with `page`, `page_size` and `total_pages` metadata. (Identical to the class shipped in the [Project Setup Guide](./django-project-setup.md), so both docs stay in sync.)

### Response shape

All paginated list endpoints return:

```json
{
  "count": 37,
  "next": "http://example.com/api/articles/?page=3",
  "previous": "http://example.com/api/articles/?page=2",
  "page": 2,
  "page_size": 12,
  "total_pages": 4,
  "results": [ ... ]
}
```

Requests:

```
GET /api/articles/            # page 1, 12 items
GET /api/articles/?page=3     # page 3
GET /api/articles/?page_size=50   # 50 items per page (≤ 100)
```

---

## 5. Custom Exception Handler

A global exception handler guarantees that **all** errors — validation errors, not-found, permission denied, etc. — share the same JSON envelope.

Create `project/handlers.py`:

```python
from rest_framework.views import exception_handler


def custom_exception_handler(exc, context):
    # Call DRF's default handler first to get the standard error response.
    response = exception_handler(exc, context)

    # Now reshape the response into a consistent format.
    if response is not None:
        original_data = response.data
        response.data = {}
        response.data["status"] = "error"

        details = original_data.get("detail", None)
        if details:
            del original_data["detail"]
            response.data["message"] = str(details)
        else:
            response.data["message"] = "Invalid data"

        response.data["data"] = original_data

    return response
```

### Sample error responses

Authentication error:

```json
{
  "status": "error",
  "message": "Authentication credentials were not provided.",
  "data": {}
}
```

Validation error:

```json
{
  "status": "error",
  "message": "Invalid data",
  "data": {
    "title": ["This field is required."]
  }
}
```

---

## 6. Authentication

Two authentication schemes are enabled globally:

- **TokenAuthentication** — for API clients (e.g. another backend, a landing page server). The client sends a token in the `Authorization` header:

  ```
  Authorization: Token <your-token>  # e.g. Token $CATALOG_API_TOKEN
  ```

- **SessionAuthentication** — for browser-based clients already logged into Django (e.g. the admin or the browsable API).

Because `rest_framework.authtoken` is installed, DRF provides the `Token` model. Tokens are **not** exposed through a login endpoint by default; create them in the Django admin, via a management command, or in a shell:

```sh
python manage.py shell
```

```python
from rest_framework.authtoken.models import Token
from django.contrib.auth.models import User

user = User.objects.get(username="admin")
token, created = Token.objects.get_or_create(user=user)
print(token.key)
```

### Build / API client credential (SSG / static build)

Every endpoint requires authentication (`IsAuthenticated`); a build-time client (static-site generator, cron job, another backend) authenticates with a DRF Token sent as an API key.

The build fetches data by paginating the per-model read-only endpoints instead of a single monolithic catalog:

- `GET /api/<model-a>/`
- `GET /api/<model-b>/`
- …
- `GET /api/<model-n>/`

Each list response is paginated (`page_size` query param, max 100); translations are nested as `{language: {field: value}}` dicts, related models are referenced via `{id, slug}` objects, and media (e.g. images) use absolute URLs.

To provision the build credential in the Django admin:

1. Create a dedicated machine user (e.g. `catalog-ssg`) — non-staff, not a superuser, with an unusable password (no need for login).
2. Under **Auth tokens → Add token**, select that user and save; copy the generated key once.
3. The frontend sends it on every build:

   ```
   Authorization: Token ${CATALOG_API_TOKEN}
   ```

   The key lives only in the build environment (e.g. `CATALOG_API_TOKEN`); never commit it.

Revocation: delete the token in the Django admin (Auth tokens), or from a shell:

```python
from rest_framework.authtoken.models import Token
Token.objects.get(user__username="catalog-ssg").delete()
```

---

## 7. Permissions

The global default is `IsAuthenticated`, so every endpoint requires a logged-in user or a valid token.

Override on a per-view basis for public endpoints:

```python
from rest_framework.permissions import AllowAny
from rest_framework.views import APIView


class PublicEndpointView(APIView):
    permission_classes = [AllowAny]
```

Common permissions available in `rest_framework.permissions`:

- `AllowAny` — no authentication required.
- `IsAuthenticated` — any logged-in user.
- `IsAdminUser` — only superusers/staff.
- `IsAuthenticatedOrReadOnly` — reads allowed anonymously, writes require auth.

---

## 8. Serializers

Serializers define how model data maps to/from JSON and where validation happens.

### 8.1 Base `ModelSerializer`

Sample model:

```python
from django.db import models


class Article(models.Model):
    class Lang(models.TextChoices):
        EN = "en", "English"
        ES = "es", "Spanish"

    title = models.CharField(max_length=255)
    slug = models.SlugField(max_length=255, unique=True, blank=True, null=True)
    lang = models.CharField(max_length=2, choices=Lang.choices, default=Lang.EN)
    banner_image_url = models.CharField(max_length=255, blank=True, null=True)
    description = models.TextField()
    author = models.CharField(max_length=255)
    content = models.TextField()
    related_article = models.ForeignKey(
        "self",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
```

> The sample model omits admin-visible texts (`verbose_name` on every field,
> `Meta.verbose_name`/`verbose_name_plural`, content-based `__str__`) for
> brevity. Real models in this ecosystem must follow the
> [Model Definitions](./django-model-definitions.md) convention.

#### 8.1.1 List/Summary serializer — explicit field list

Only expose the fields a list view needs:

```python
from rest_framework import serializers
from . import models


class ArticleListSerializer(serializers.ModelSerializer):
    class Meta:
        model = models.Article
        fields = (
            "id",
            "title",
            "slug",
            "lang",
            "banner_image_url",
            "description",
            "author",
            "created_at",
            "updated_at",
        )
```

#### 8.1.2 Detail serializer — full model + extra fields

Inherit the list serializer (so field order/behaviour stays consistent), then switch to `"__all__"` for the full payload and add computed fields:

```python
class ArticleDetailSerializer(ArticleListSerializer):
    related_article = serializers.SerializerMethodField()

    class Meta:
        model = models.Article
        fields = "__all__"

    def get_related_article(self, obj):
        """Return the related article's slug (or None)."""
        if not obj.related_article:
            return None
        return obj.related_article.slug
```

`SerializerMethodField` lets you add read-only computed values to the payload. The `get_<field_name>` method receives the model instance and returns the value.

### 8.2 Sample output

List item:

```json
{
  "id": 1,
  "title": "Airport Transfers 101",
  "slug": "airport-transfers-101",
  "lang": "en",
  "banner_image_url": "https://example.com/media/articles/banner.jpg",
  "description": "A short summary.",
  "author": "Jane Doe",
  "created_at": "2026-01-10T12:00:00Z",
  "updated_at": "2026-02-01T09:30:00Z"
}
```

Detail (adds fields like `content` and `related_article`):

```json
{
  "id": 1,
  "title": "Airport Transfers 101",
  "slug": "airport-transfers-101",
  "lang": "en",
  "banner_image_url": "https://example.com/media/articles/banner.jpg",
  "description": "A short summary.",
  "author": "Jane Doe",
  "content": "Full body text...",
  "related_article": "airport-transfers-202",
  "created_at": "2026-01-10T12:00:00Z",
  "updated_at": "2026-02-01T09:30:00Z"
}
```

---

## 9. Viewsets

A viewset groups list/detail logic for a model. `ReadOnlyModelViewSet` exposes only `GET` (list + retrieve); write methods automatically return `405 Method Not Allowed`.

Create `myapp/views.py`:

```python
from rest_framework import viewsets

from . import models, serializers


class ArticleViewSet(viewsets.ReadOnlyModelViewSet):
    """Read-only API for the Article model."""

    queryset = models.Article.objects.all()
    serializer_class = serializers.ArticleListSerializer
    lookup_field = "slug"

    def get_queryset(self):
        """Customize filtering and ordering of the base queryset."""
        queryset = models.Article.objects.all().order_by("-updated_at")

        # Simplified example: filter by language from the Accept-Language header.
        # Takes the first tag and strips quality values (e.g. "es-419;q=0.9" -> "es-419").
        # Real projects may need full parsing per RFC 7231.
        lang = self.request.META.get("HTTP_ACCEPT_LANGUAGE", "")
        if lang:
            queryset = queryset.filter(lang=lang.split(",")[0].strip())

        return queryset

    def get_serializer_class(self):
        """Pick the serializer based on query parameters."""
        if "details" in self.request.query_params:
            return serializers.ArticleDetailSerializer
        return self.serializer_class
```

Key points:

- `lookup_field = "slug"` — URL lookups use the slug instead of the primary key: `/api/articles/<slug>/`.
- `get_queryset()` — override to filter by request context (headers, query params, user) and set ordering.
- `get_serializer_class()` — return a different serializer per request, driven by query parameters:

  ```
  GET /api/articles/                  # list serializer (default)
  GET /api/articles/?details          # detail serializer on the whole list
  GET /api/articles/my-article-slug/?details   # detail serializer for one item
  ```

---

## 10. Routing

Use a DRF router so the viewset maps to RESTful URLs automatically, including a browsable API-root listing.

Create `project/urls.py` (merge with [django-project-setup](./django-project-setup.md) §10 — keep the admin redirect and `import project.admin`):

```python
from django.urls import path, include
from rest_framework import routers

from myapp import views as myapp_views

router = routers.DefaultRouter()

# Model endpoints
router.register(r"articles", myapp_views.ArticleViewSet, basename="articles")

urlpatterns = [
    # ... admin, other routes ...
    path("api/", include(router.urls)),
    # Additional hand-written API endpoints
    # path("api/", include("myapp.api_urls")),
]
```

Generated routes:

```
GET  /api/                             -> API root (lists all registered endpoints)
GET  /api/articles/                    -> list
POST /api/articles/                    -> create (405 for read-only viewsets)
GET  /api/articles/<slug>/             -> retrieve
PUT/PATCH/DELETE /api/articles/<slug>/ -> write operations (405 for read-only)
```

---

## 11. Public Proxy Endpoints (APIView pattern)

For endpoints that must be anonymous and/or proxy to an external system, use plain `APIView` classes. A shared base class keeps authentication, error mapping, and retry logic in one place.

Create `myapp/api_views.py`:

```python
import requests
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework import status


class BasePublicView(APIView):
    """Common handling for public endpoints that call an upstream API."""

    permission_classes = [AllowAny]

    def call_upstream(self, request):
        try:
            response = requests.post(
                "https://api.example.com/v1/external",
                json=request.data,
                timeout=10,
            )
        except requests.RequestException:
            return Response(
                {"error": "Upstream service unreachable"},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        try:
            data = response.json()
        except ValueError:
            return Response(
                {"error": "Malformed upstream response"},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        if response.status_code >= 500:
            return Response(
                {"error": "Upstream service error"},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        return Response(data, status=response.status_code)


class ExternalQuoteView(BasePublicView):
    """POST /api/external/quote/ — proxies a payload upstream."""

    def post(self, request, *args, **kwargs):
        return self.call_upstream(request)
```

Recommended patterns for proxy endpoints:

- Return upstream `4xx` responses as-is, so client validation errors (e.g. a `422`) keep their status and body.
- Map upstream `5xx`/connection errors to `502 Bad Gateway` so the client knows the problem is upstream.
- Return a clear `502` when the upstream body is malformed or not JSON.
- Never leak upstream credentials to the client.

---

## 12. Filtering (Optional)

`django-filter` is installed but **not required**. Enable generic query-param filtering per viewset when needed:

```python
from django_filters.rest_framework import DjangoFilterBackend
from rest_framework import viewsets


class ArticleViewSet(viewsets.ReadOnlyModelViewSet):
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ["lang", "author"]
```

This enables:

```
GET /api/articles/?lang=en&author=Jane%20Doe
```

---

## 13. Testing

DRF ships `APITestCase`, which provides a `client` with handy helpers. A base class keeps auth and read-only checks consistent across viewsets. If [Fixtures](./django-fixtures.md) is adopted, call `base_loaddata` in `setUp` for required reference rows.

```python
from django.contrib.auth.models import User
from rest_framework import status
from rest_framework.test import APITestCase

from . import models


class ArticleApiTestCase(APITestCase):
    endpoint = "/api/articles/"

    def setUp(self):
        User.objects.create_superuser(username="tester", password="secret12")
        self.client.login(username="tester", password="secret12")

        models.Article.objects.create(
            title="First", slug="my-article-slug", lang="en",
            description="First article", author="Jane Doe", content="Body",
        )
        models.Article.objects.create(
            title="Second", slug="second-article", lang="en",
            description="Second article", author="John Roe", content="Body",
        )

    def test_requires_authentication(self):
        self.client.logout()
        response = self.client.get(self.endpoint)
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_list_is_paginated(self):
        response = self.client.get(self.endpoint)
        json_data = response.json()
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn("count", json_data)
        self.assertIn("results", json_data)

    def test_custom_page_size(self):
        response = self.client.get(f"{self.endpoint}?page_size=1")
        self.assertEqual(len(response.json()["results"]), 1)

    def test_detail_route_by_slug(self):
        response = self.client.get(f"{self.endpoint}my-article-slug/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_write_methods_not_allowed(self):
        response = self.client.post(self.endpoint)
        self.assertEqual(response.status_code, status.HTTP_405_METHOD_NOT_ALLOWED)
```

To test the token path instead of the session login, create a token for the user and set the `Authorization` header on the client:

```python
from rest_framework.authtoken.models import Token

user = User.objects.get(username="tester")
token = Token.objects.create(user=user)
self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
```

---

## 14. Quick Reference

| Piece | Where it lives | Purpose |
| --- | --- | --- |
| `REST_FRAMEWORK` dict | `project/settings.py` | Global permissions, pagination, auth, exception handler |
| `CustomPageNumberPagination` | `project/pagination.py` | Consistent paginated envelope for all lists |
| `custom_exception_handler` | `project/handlers.py` | Uniform `{status, message, data}` error format |
| Serializers | `myapp/serializers.py` | Field mapping, validation, computed fields |
| Viewsets | `myapp/views.py` | Grouped list/detail logic, read-only by default |
| Router | `project/urls.py` | Auto-generates RESTful URLs under `/api/` |
| Public `APIView` classes | `myapp/api_views.py` | Anonymous endpoints, upstream proxying |
| `APITestCase` base | `myapp/tests/` | Auth + pagination + serializer coverage |

---

## 15. Checklist for a New Project

1. Add DRF (+ `django-filter`) to `requirements.txt` and install.
2. Add `rest_framework` (and `rest_framework.authtoken`) to `INSTALLED_APPS`; run `migrate`.
3. Configure the `REST_FRAMEWORK` dict in `settings.py`.
4. Create the global pagination class.
5. Create the custom exception handler.
6. Set up authentication (Token + Session) and create tokens for API clients.
7. Decide permissions: keep `IsAuthenticated` global; use `AllowAny` only on genuinely public views.
8. Write serializers (list/summary + detail/"__all__") and the viewset.
9. Register the viewset with a router under `/api/`.
10. Add tests covering auth, pagination, and serializer switching.

---

## See also

- [Project Setup Guide](./django-project-setup.md) — project scaffolding; the canonical
  `REST_FRAMEWORK` dict, pagination and exception handler blocks this guide reuses.
- [Model Definitions](./django-model-definitions.md) — admin-visible texts for the
  models your serializers expose.
- [Unfold Admin Theme](./django-unfold-admin.md) — the admin where DRF Tokens are managed.