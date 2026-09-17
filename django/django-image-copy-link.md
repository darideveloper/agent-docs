---
created: 2026-04-18
updated: 2026-08-29
tags:
  - django
  - admin
  - documentation
type: resource
status: active
source: templates://django/django-image-copy-link.md
version: 2026-09-17+unreleased

---

# Image Copy Link Feature (Optional, English Default)

This document describes how the "Copy Link" feature for an image model (example `<APP_LABEL>/BlogImage` in `<APP_LABEL>/blog`) is implemented. Replace `<APP_LABEL>`/`<MODEL>` with your names.

## Overview

The feature allows administrators to copy the public URL of an uploaded image to their clipboard with a single click from the Django Admin interface, from the image's change form.

## Why a custom-injected button

The admin standardizes on Unfold-native button patterns (`actions_detail`, `actions_row`), but the **copy-link buttons are the deliberate exception**: the Clipboard API (`navigator.clipboard.writeText`) requires a user gesture on the same page, so a server-side Unfold action (a GET link that navigates) cannot perform the copy. Copy buttons are therefore custom-injected `<button>` elements rendered through Unfold's button component (`unfold/components/button.html`).

## Backend Implementation

The backend logic lives in `<MODEL>Admin` in `<APP_LABEL>/admin.py` (example `BlogImageAdmin`).

### `change_view` — preload the URL

`change_view` injects a ready-to-render `copy_button_extra_attrs` string (built with `mark_safe`) only when the image has a file:

```python
def change_view(self, request, object_id, form_url="", extra_context=None):
    extra_context = extra_context or {}
    obj = self.get_object(request, object_id)
    url = get_media_url(obj.image.url) if obj and obj.image else None
    extra_context["copy_button_extra_attrs"] = (
        mark_safe(f'type="button" data-copy-url="{url}"') if url else None
    )
    return super().change_view(request, object_id, form_url, extra_context)
```

**Key steps:**
1. **Retrieve Object:** Fetches the `<MODEL>` instance using `object_id`.
2. **Generate URL:** Uses `get_media_url` to get the absolute URL (handling both local storage and cloud providers).
3. **Only with a file:** If the image has no file, no attributes are injected and no button renders.
4. **`type="button"`:** keeps the button from submitting the surrounding POST form.
5. **`data-copy-url`:** carries the preloaded URL the JS reads on click. No cookie, no server round-trip.

### Utility: `get_media_url`

Located in `utils/media.py`, this utility ensures the URL is absolute and prefixed with the correct host if necessary.

## Frontend Implementation

### Template: `project/templates/admin/<app>/<model>/change_form.html` (example `admin/blog/blogimage/change_form.html`)

Overrides `object-tools-items` to prepend the copy button (Unfold button component) before the default tools:

```html
{% block object-tools-items %}
    {% if copy_button_extra_attrs %}
        <li>
            {% component "unfold/components/button.html" with extra_attrs=copy_button_extra_attrs %}
                <span class="material-symbols-outlined -ml-0.5">content_copy</span>
                <span data-copy-label>Copy link</span>
            {% endcomponent %}
        </li>
    {% endif %}
    {{ block.super }}
{% endblock %}
```

### JavaScript Handler: `copy_clipboard.js`

`static/js/copy_clipboard.js` (loaded via `<MODEL>Admin.Media`, e.g. `class Media: js = ("js/copy_clipboard.js",)`) finds every `[data-copy-url]` button and attaches a click handler. On click (a user gesture, so the browser allows the write) it copies the value to the clipboard and briefly shows "Copied!" on the label:

```javascript
document.querySelectorAll('[data-copy-url]').forEach((button) => {
  const url = button.dataset.copyUrl
  const label = button.querySelector('[data-copy-label]')
  // on click → navigator.clipboard.writeText(url) → label "Copied!" → revert
  // fallback → execCommand('copy') via a temp textarea → prompt() as last resort
})
```

**Workflow:**
1. **Find buttons:** on `DOMContentLoaded`, locate every `[data-copy-url]` element.
2. **Click to copy:** within the click handler, `navigator.clipboard.writeText(url)` — the user gesture satisfies the Clipboard API requirement.
3. **Feedback:** the label span flips to "Copied!" for ~2s; the icon stays intact.
4. **Fallback:** if the Clipboard API is unavailable (non-secure context), a temp textarea + `execCommand('copy')` is used; if that also fails, a `prompt()` shows the URL for manual copy.

## Summary of Files Involved

- `<APP_LABEL>/admin.py`: `<MODEL>Admin.change_view` + `Media` including the JS.
- `project/templates/admin/blog/blogimage/change_form.html`: the copy-button override.
- `utils/media.py`: provides the URL generation logic.
- `static/js/copy_clipboard.js`: handles the actual clipboard interaction on the client-side.
- `project/settings.py`: provides the `HOST` setting used for absolute URL generation.

> The same pattern is used by any other change form that needs a copy-to-clipboard button — e.g. a subscription "Copy link" button on a `change_form.html` override wired from the model admin's `change_view`.