---
created: 2026-04-18
tags:
  - django
  - storage
  - aws
  - s3
  - documentation
type: resource
status: active
source: templates://django/django-media-storage.md
version: 2026-10-28+28a9c8d

---

# Media File Storage Integration Guide (AWS S3 & DigitalOcean Spaces) — Optional

> Optional — adopt only if the project needs S3-compatible storage. CANONICAL `STORAGES` + `IS_TESTING` block lives here. [Project Setup](./django-project-setup.md) and [Testing Contract](./django-testing-contract.md) link here instead of duplicating — do not copy their snippets as canonical.

This document provides a detailed breakdown of how to integrate and configure cloud storage for media and static files in a Django project, using **AWS S3** or **DigitalOcean Spaces**.

## 🚀 Overview

The integration relies on two primary libraries:
- **`django-storages`**: A collection of custom storage backends for Django.
- **`boto3`**: The AWS SDK for Python, which allows Django to communicate with S3-compatible APIs.

---

## 📦 Dependencies

Add the following to your `requirements.txt`:

```text
django-storages==1.14.6
boto3==1.35.36
```

---

## 🛠️ Storage Backends

To maintain separation between **Static Files**, **Public Media**, and **Private Media**, we use custom storage classes. These are defined in `project/storage_backends.py`.

### Definition File: `project/storage_backends.py`

```python
from django.conf import settings
from storages.backends.s3boto3 import S3Boto3Storage

class StaticStorage(S3Boto3Storage):
    """
    Handles static files (CSS, JS, images).
    Stored in: bucket/project_folder/static/
    """
    location = settings.STATIC_LOCATION
    default_acl = "public-read"

class PublicMediaStorage(S3Boto3Storage):
    """
    Handles public uploads (user avatars, post images).
    Stored in: bucket/project_folder/media/
    """
    location = settings.PUBLIC_MEDIA_LOCATION
    default_acl = "public-read"
    file_overwrite = False

class PrivateMediaStorage(S3Boto3Storage):
    """
    Handles sensitive files (documents, private videos).
    Stored in: bucket/project_folder/private/
    """
    location = settings.PRIVATE_MEDIA_LOCATION
    default_acl = "private"
    file_overwrite = False
    # Crucial: Private files must bypass the CDN to use Signed URLs
    custom_domain = False
```

---

## ⚙️ Django Settings Configuration

The storage logic is toggled via an environment variable `STORAGE_AWS`. 

### Configuration in `settings.py`

```python
# Storage settings
STORAGE_AWS = os.getenv("STORAGE_AWS", "").strip().lower() == "true"

if STORAGE_AWS:
    # 1. Credentials
    AWS_ACCESS_KEY_ID = os.getenv("AWS_ACCESS_KEY_ID")
    AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY")
    AWS_STORAGE_BUCKET_NAME = os.getenv("AWS_STORAGE_BUCKET_NAME")

    # 2. Regional Settings
    # For AWS: Usually None or s3.region.amazonaws.com
    # For DigitalOcean Spaces: https://region.digitaloceanspaces.com
    AWS_S3_ENDPOINT_URL = os.getenv("AWS_S3_ENDPOINT_URL")
    AWS_S3_REGION_NAME = os.getenv("AWS_S3_REGION_NAME")

    # 3. Domain/CDN settings
    # For AWS: bucket.s3.amazonaws.com
    # For DO: bucket.region.cdn.digitaloceanspaces.com (if using CDN)
    AWS_S3_CUSTOM_DOMAIN = os.getenv("AWS_S3_CUSTOM_DOMAIN")

    # 4. Folder isolation
    # Allows multiple projects to share one bucket. Guard the empty case: without
    # it the keys become "None/static/..." — and note that this variable must be
    # declared as a build ARG, or collectstatic never sees it (see the Docker note).
    _folder = os.getenv("AWS_PROJECT_FOLDER", "")
    AWS_PROJECT_FOLDER = _folder

    # 5. File Locations
    STATIC_LOCATION = f"{_folder}/static" if _folder else "static"
    PUBLIC_MEDIA_LOCATION = f"{_folder}/media" if _folder else "media"
    PRIVATE_MEDIA_LOCATION = f"{_folder}/private" if _folder else "private"

    # 6. Django-Storages Engine Mapping (Django 4.2+)
    STORAGES = {
        "default": {
            "BACKEND": "project.storage_backends.PublicMediaStorage",
        },
        "staticfiles": {
            "BACKEND": "project.storage_backends.StaticStorage",
        },
        "private": {
            "BACKEND": "project.storage_backends.PrivateMediaStorage",
        },
    }

    # 7. Optimization & Security
    AWS_S3_OBJECT_PARAMETERS = {"CacheControl": "max-age=86400"}
    # None lets S3 Object Ownership (Bucket owner enforced) work; with legacy ACL buckets use "public-read".
    AWS_DEFAULT_ACL = None
else:
    # Fallback to local storage for development — IS_TESTING avoids Whitenoise manifest during `manage.py test`
    # (see [django-testing-contract](./django-testing-contract.md) §2.2; both Path/os.path variants there).
    import sys
    IS_TESTING = len(sys.argv) > 1 and sys.argv[1] == "test"
    staticfiles_backend = "django.contrib.staticfiles.storage.StaticFilesStorage" if IS_TESTING else "whitenoise.storage.CompressedManifestStaticFilesStorage"
    STORAGES = {
        "default": {
            "BACKEND": "django.core.files.storage.FileSystemStorage",
        },
        "staticfiles": {
            "BACKEND": staticfiles_backend,
        },
        # only if you use private media — otherwise omit this key
        # "private": {
        #     "BACKEND": "django.core.files.storage.FileSystemStorage",
        #     "OPTIONS": {"location": os.path.join(MEDIA_ROOT, "private-media")},
        # },
    }
```

---

## 🔑 Environment Variables

| Variable | Description | Example (DigitalOcean) |
| :--- | :--- | :--- |
| `STORAGE_AWS` | Toggle switch (`True`/`False`) | `True` |
| `AWS_ACCESS_KEY_ID` | Your API access key | `DO00xxxxxxxxxxxxxxxxxx` |
| `AWS_SECRET_ACCESS_KEY` | Your API secret key | `QR0mj22q...` |
| `AWS_STORAGE_BUCKET_NAME`| The name of the bucket/space | `my-project-storage` |
| `AWS_PROJECT_FOLDER` | Subfolder inside the bucket | `my-project` |
| `AWS_S3_REGION_NAME` | Cloud region | `sfo3` |
| `AWS_S3_ENDPOINT_URL` | API endpoint | `https://sfo3.digitaloceanspaces.com` |
| `AWS_S3_CUSTOM_DOMAIN` | CDN or Custom domain | `bucket.sfo3.cdn.digitaloceanspaces.com` |

---

## 🐳 Docker / CI/CD Considerations

Since `collectstatic` is typically executed during the Docker build process to prepare the application for production, you must ensure the container has access to S3 credentials **during the build**.

In your `Dockerfile`, ensure the following build arguments are defined before the `RUN python manage.py collectstatic` command:

```dockerfile
# Declare them as ARGs — Coolify passes every env var, but Docker only exposes
# the ones the Dockerfile names.
ARG AWS_ACCESS_KEY_ID
ARG AWS_SECRET_ACCESS_KEY
ARG AWS_STORAGE_BUCKET_NAME
ARG AWS_S3_REGION_NAME
ARG AWS_S3_ENDPOINT_URL
ARG AWS_S3_CUSTOM_DOMAIN
ARG AWS_PROJECT_FOLDER
ARG STORAGE_AWS=False

# Values are scoped to this layer: nothing stays baked into the image.
RUN SECRET_KEY=change-me-build-only-000000000000000000000000000000 \
    DEBUG=False \
    STORAGE_AWS=${STORAGE_AWS} \
    AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
    AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
    AWS_STORAGE_BUCKET_NAME=${AWS_STORAGE_BUCKET_NAME} \
    AWS_S3_REGION_NAME=${AWS_S3_REGION_NAME} \
    AWS_S3_ENDPOINT_URL=${AWS_S3_ENDPOINT_URL} \
    AWS_S3_CUSTOM_DOMAIN=${AWS_S3_CUSTOM_DOMAIN} \
    AWS_PROJECT_FOLDER=${AWS_PROJECT_FOLDER} \
    python manage.py collectstatic --noinput
```

> **Canonical Dockerfile:** [Project Setup](./django-project-setup.md) §14 owns the full
> build; the snippet above is only the storage slice of it.

> [!warning] `STORAGE_AWS` must reach the **build**, not just the runtime
> Coolify passes every environment variable as `--build-arg`, but Docker only exposes the
> ones the Dockerfile declares. If `STORAGE_AWS` is absent at build time (or is not `True`;
> the reader is case-insensitive, but the value still has to be there), `collectstatic`
> compiles locally and the bucket keeps serving the old CSS/JS forever.
> The fingerprint is in the build log:
> - `253 static files copied to '/app/staticfiles'` → **local, wrong**
> - `253 static files copied.` (no path) → **S3, correct**
>
> If recreating the variable in the Coolify UI does not fix it, delete it and create it
> again from scratch with the bare value `True`; editing in place did not take in
> `cakestoremommy` (2026-10-23).

---

## 🔄 Replicating in Another Project

To replicate this setup in a new Django project (see [django-project-setup](./django-project-setup.md)):

1.  **Install dependencies**: `pip install "django-storages==1.14.6" "boto3==1.35.36"` (already pinned in `requirements.txt`).
2.  **Create `storage_backends.py`**: Copy the class definitions provided above into your project's main module.
3.  **Update `settings.py`**:
    - Add `storages` to `INSTALLED_APPS`.
    - Copy the storage logic block.
    - Ensure `load_dotenv()` is correctly fetching variables.
4.  **Configure the Cloud Provider**:
    - Create a Bucket (S3) or Space (DO).
    - If using DigitalOcean, enable the **CDN** to get your custom domain.
    - Generate an Access Key and Secret Key.
5.  **Set Environment Variables**: Populate `.env.dev` and `.env.prod` with the correct credentials (the `.env` file is a pure selector carrying only `ENV=dev` or `ENV=prod`).

### 💡 Pro Tip: Subdirectory Isolation
Using `AWS_PROJECT_FOLDER` is highly recommended. It allows you to use a single bucket for production, staging, and development files by simply changing the folder name in the relevant `.env.<ENV>` file!
