---
created: 2026-05-30
updated: 2026-05-30
tags:
  - django
  - redis
  - celery
  - cache
type: resource
status: active
source: templates://django/django-redis.md
version: 2026-09-17+4cf710f

---

# Redis in Django Integration Guide (Optional)

> Optional — adopt only for caching/background tasks. Env loader is `python-dotenv` (see [[django-project-setup|Project Setup]]); set `REDIS_URL` to the full URL including DB index.

This guide details how to implement Redis (external) in a Django project for caching and background tasks.

## 📦 Dependencies

Add these to your `requirements.txt` (see [[django-project-setup|Django Project Setup]]):

```text
django-redis>=5.4.0
celery[redis]>=5.4.0
```

## ⚙️ Configuration (`settings.py`)

### 1. Cache Backend
Using `django-redis` allows for persistent connections and advanced features.

```python
# settings.py — REDIS_URL must include the DB index (e.g. redis://127.0.0.1:6379/0).
CACHES = {
    "default": {
        "BACKEND": "django_redis.cache.RedisCache",
        "LOCATION": os.getenv("REDIS_URL", "redis://127.0.0.1:6379/0"),
        "OPTIONS": {
            "CLIENT_CLASS": "django_redis.client.DefaultClient",
        }
    }
}
```

### 2. Celery Broker
Configure Redis as the message broker for background workers.

```python
# settings.py — separate DB index for Celery (e.g. redis://127.0.0.1:6379/1).
CELERY_BROKER_URL = os.getenv("REDIS_URL", "redis://127.0.0.1:6379/0").rsplit("/", 1)[0] + "/1"
CELERY_RESULT_BACKEND = CELERY_BROKER_URL
```

> **Pro Tip:** Use database index `/0` for caching and `/1` for Celery to avoid collisions during cache clears.

## 🚀 Use Cases

### A. View Caching
Cache entire views to avoid hitting PostgreSQL (external).

```python
from django.views.decorators.cache import cache_page

@cache_page(60 * 15) # Cache for 15 minutes
def my_expensive_view(request):
    ...
```

### B. Background Tasks
Offload heavy work with Celery shared tasks (see Celery docs for broker setup; cache config above).

```python
from celery import shared_task

@shared_task
def process_media_upload(file_id):
    # Logic for processing files (see [[django-media-storage|Media Storage Configuration]])
    ...
```

### C. Manual Caching
```python
from django.core.cache import cache

def get_data():
    data = cache.get('my_key')
    if not data:
        data = ExpensiveModel.objects.all()
        cache.set('my_key', data, 3600)
    return data
```

## 🔑 Environment Variables

| Variable | Description | Example |
| :--- | :--- | :--- |
| `REDIS_URL` | Full Redis URL including DB index | `redis://127.0.0.1:6379/0` (cache; Celery derives `/1`) |

---
**Related:**
- Redis (external)
- [[django-project-setup|Django Project Setup]]
- Coolify (external)
