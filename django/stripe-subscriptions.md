---
created: 2026-08-20
updated: 2026-08-29
tags:
  - stripe
  - subscriptions
  - architecture
  - documentation
type: resource
status: active
source: templates://django/stripe-subscriptions.md
version: 2026-09-17+unreleased

---

# Stripe Subscriptions — Worked Example (NOT part of template)

> Worked example — do not copy as template. Placeholders used throughout: `<MODEL>` (billed model, e.g. `Artist`), `<MODEL>Subscription` (e.g. `ArtistSubscription`), `<MODEL>Admin`, `<APP_LABEL>`, `<CURRENCY>` (e.g. `MXN`). Requires `stripe>=12.0.0` (see setup extras).

How paid membership gating works in a Django dashboard. The worked example:
a `<MODEL>` record (e.g. an `Artist`) that must hold a paying subscription to appear on the public
site.

## Overview

Each `<MODEL>` has at most one `<MODEL>Subscription` (1:1). Stripe is the source
of truth for the subscription lifecycle; the dashboard mirrors the minimal
state it needs and derives `<MODEL>.is_active` from it. The public API
(`/api/<resource>/`) keeps filtering on `<MODEL>.is_active` — it does not
know about subscriptions at all.

Layers:

```
stripe SDK  ──► subscriptions/services/stripe_client.py   (only file that imports `stripe`)
webhooks / views  ──► services/subscription_state.compute_is_active()
`<MODEL>Subscription` / StripeEvent  (subscriptions/models.py)
`<MODEL>Admin` buttons (`<APP_LABEL>/admin.py` + change_form template)
```

## Step-by-Step Subscription Flow

### 1. Setup Phase
1. **Operator creates a `<MODEL>`** in Django admin with a required email address
2. **Configure BillingPlan** singleton (django-solo) with:
   - Stripe price ID (`price_xxx`, i.e. `<PRICE_ID>`)
   - Currency (default: `<CURRENCY>`, e.g. `MXN`)
   - Grace period (default: 3 days)
   - "Accept new signups" toggle

### 2. Payment Link Generation
1. Operator clicks **"Generate subscription link"** on the `<MODEL>` change page
2. System creates:
   - Stripe Customer (if not exists)
   - Stripe Checkout Session with `metadata.artist_id`
   - `<MODEL>Subscription(status="pending", signup_url="...")`
3. Once the link exists, a **"Copy link"** button appears on the change page;
   the operator clicks it to copy the Checkout URL to the clipboard and share
   it via email/WhatsApp

### 3. <MODEL> Payment
1. Customer opens Checkout Session URL in incognito browser
2. Completes payment (card: `4242 4242 4242 4242` for testing)
3. Stripe sends `checkout.session.completed` webhook

### 4. Webhook Processing
Webhook endpoint `POST /webhooks/stripe/` processes events:
1. **Signature verification** using `stripe.Webhook.construct_event`
2. **Idempotency** via `StripeEvent.event_id` unique constraint
3. **Atomic transaction** updates both:
   - `<MODEL>Subscription.status` (mirrors Stripe state)
   - `<MODEL>.is_active` (via `compute_is_active()` helper)

### 5. Subscription States & Visibility

| Subscription Status | `<MODEL>.is_active` | Behavior |
|---------------------|-------------------|----------|
| `active` | `True` | <MODEL> visible on public site |
| `pending` | `False` | Unpaid link does NOT make artist visible |
| `canceling` | `True` until period end | Friendly cancellation - visible until paid period ends |
| `past_due` | `True` for 3 days grace | Payment failed but within grace period |
| `canceled` | `False` | <MODEL> disappears from public site |

### 6. Admin Controls
From the `<MODEL>` change page, the header buttons depend on the subscription state:

| State                        | Buttons shown |
|------------------------------|---------------|
| No link (no subscription / empty `signup_url`) | **Generate link**, Sync from Stripe |
| Expired link                 | **Regenerate link**, Open Customer Portal, Sync from Stripe |
| Valid (non-expired) link     | **Copy link**, Regenerate link, Open Customer Portal, Sync from Stripe |

- **Generar / Regenerate link** - Create new Checkout Session
- **Copy link** - Client-side button that copies the preloaded `signup_url` to the clipboard on click
- **Open Customer Portal** - Stripe-hosted self-service (cancel, update card, invoices)
- **Sync from Stripe** - Manual state re-sync escape hatch

### 7. Public API
`/api/<resource>/` filters on `<MODEL>.is_active` - unchanged API, only the driver of `is_active` changes.

## The `compute_is_active` rule

`subscriptions/services/subscription_state.compute_is_active(subscription)` is
the **single source of truth** for `<MODEL>.is_active`. No webhook handler or
admin action derives the boolean inline.

| Subscription status            | `<MODEL>.is_active`                          |
|--------------------------------|---------------------------------------------|
| `active`                       | `True`                                      |
| `pending`                      | `False` (unpaid link does NOT make the artist visible) |
| `canceling`                    | `True` until `current_period_end`           |
| `past_due`                     | `True` until `current_period_end + grace`   |
| `canceled`                     | `False`                                     |
| no subscription row            | artist's current value, untouched           |

`grace_period_days` comes from the `BillingPlan` singleton. The grace boundary
is re-evaluated on every webhook that touches the row (there is no background
job in v1); the next event that crosses the boundary performs the flip.

## Webhook idempotency model

`POST /webhooks/stripe/` is the only endpoint outside the admin; its security
boundary is the `Stripe-Signature` header (`stripe.Webhook.construct_event`,
`@csrf_exempt`).

1. The event is INSERTed into `StripeEvent` inside its own savepoint, keyed by
   the unique `event_id`. A duplicate INSERT raises `IntegrityError` and the
   endpoint returns `200` immediately — **no** side effects (the unique index
   is the lock; the savepoint keeps an enclosing transaction healthy).
2. Handled events run inside one `transaction.atomic()` block:
   `<MODEL>Subscription` mirror + `<MODEL>.is_active` commit together.
3. If the handler raises, the transaction rolls back, the `error` is persisted
   on the `StripeEvent` row **outside** the atomic block, and the endpoint
   returns `500` so Stripe retries.

Dispatch table: `checkout.session.completed`,
`customer.subscription.created/updated/deleted`, `invoice.payment_succeeded`,
`invoice.payment_failed`. Unhandled event types are still recorded and return
`200`.

Correlation is by `stripe_subscription_id` first, then `stripe_customer_id`;
`checkout.session.completed` correlates via `metadata.artist_id` (set on the
Checkout Session) before the customer id is stored locally.

## Admin controls

From the `<MODEL>` change page the operator can:

- **Generate subscription link** — shown only when no link exists. Creates a
  Stripe Customer + Checkout Session, stores the `signup_url`, and marks the
  subscription `pending`.
- **Copy link** — a client-side `<button>` (rendered through Unfold's button
  component) with the `signup_url` preloaded in `data-copy-url`; clicking it
  copies the URL via the Clipboard API (no server round-trip, no cookie).
- **Regenerate link** — shown when a link exists (valid or expired). Reuses a
  still-valid Checkout Session or creates a fresh one when expired.
- **Open Customer Portal** — Stripe-hosted self-service page for the artist
  (update card, cancel, invoices). Its `return_url` points at the neutral
  landing page `/subscriptions/portal-return/` (generic message) so an artist
  who just cancelled does not land on the "subscription active" success text.
- **Sync from Stripe** — manual salvavidas: re-fetches customer and
  latest subscription from the API and re-derives `is_active`. When the
  customer exists but has **zero subscriptions** (all deleted), the local
  status is set to `canceled` — the artist holds no paying subscription and
  stops appearing on the public site.

All of these are Unfold `actions_detail` buttons on the change-form header,
gated by `admin.site.admin_view` (redirect to admin login for anonymous users,
forbidden for non-staff).

## Adding more billing plans later (without breaking the migration)

Today there is exactly one canonical plan (`BillingPlan` django-solo singleton)
used unconditionally — there is no "select plan" dropdown anywhere. To support
tiers later:

1. Keep `BillingPlan` for the default/legacy plan or migrate it to a plain
   model; the `<MODEL>Subscription.<model>` 1:1 **does not change**, so no
   subscription rows are affected.
2. Add an optional `plan` FK to `<MODEL>Subscription` (nullable) and create
   extra `BillingPlan` rows. Existing rows keep pointing at the default plan.
3. Make the link-generation endpoints read the plan from the artist
   (e.g. a future `plan` FK on `<MODEL>`), passing its `stripe_price_id` to
   `stripe_client.create_checkout_session`.
4. `compute_is_active` stays unchanged — grace comes from each row's own plan
   (`subscription.plan.grace_period_days`) instead of `BillingPlan.get_solo()`.

This keeps the migration additive (new nullable column), never requiring a
data rewrite of existing subscriptions.

## Environment variables

- `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET`,
  `STRIPE_API_VERSION`, `STRIPE_PRICE_ID`
- Derived: `STRIPE_SUCCESS_URL` / `STRIPE_CANCEL_URL` (from `HOST`, defaulting
  to `/subscriptions/success/` and `/subscriptions/cancel/`).

## Deployment notes

- Configure the production webhook endpoint at
  `https://<host>/webhooks/stripe/` and set `STRIPE_WEBHOOK_SECRET`.
- Until `BillingPlan.stripe_price_id` is set, link generation refuses with an
  admin message and existing `<MODEL>.is_active=True` behavior is unchanged.
  `stripe_price_id` defaults to `STRIPE_PRICE_ID` (env) via
  `default_stripe_price_id()`; the admin can still override per-plan.
- The migration that makes `<MODEL>.email` required backfills existing rows with
  `""` and prints a console warning listing affected artists for follow-up.

## Testing

### Prerequisites
1. Install Stripe CLI and login: `stripe login` (full flow canonical in [[testing-stripe|Testing Stripe]] — summary only here)
2. Configure `.env.dev` with test-mode keys:
   - `STRIPE_SECRET_KEY` (test `sk_test_...`)
   - `STRIPE_PUBLISHABLE_KEY` (test `pk_test_...`)
   - `STRIPE_PRICE_ID` (from Stripe Dashboard)
3. Start webhook bridge:
   ```bash
   stripe listen --forward-to http://localhost:8000/webhooks/stripe/
   ```
4. Copy `whsec_...` (i.e. `<WEBHOOK_SECRET>`) from CLI output to `STRIPE_WEBHOOK_SECRET` in `.env.dev`
5. Start dev server: `python manage.py runserver`

### Test Flow

#### Subscribe (Happy Path)
1. Create `<MODEL>` with real email in admin
2. Click **Generate subscription link**
3. Open Checkout URL in incognito, pay with `4242 4242 4242 4242`
4. Verify:
   - `stripe listen` shows `checkout.session.completed` + `customer.subscription.created`
   - `<MODEL>Subscription.status == "active"`
   - `<MODEL>.is_active == True`
   - <MODEL> appears in `/api/<resource>/`

#### Cancel (Friendly Cancellation)
1. Click **Open Customer Portal** → cancel subscription
2. `customer.subscription.updated` arrives with `cancel_at_period_end=true`
3. Verify `status == "canceling"` and `is_active == True` (still visible)
4. When period ends, `customer.subscription.deleted` arrives
5. Verify `status == "canceled"` and `is_active == False` (artist disappears)

#### Payment Failure (Grace Period)
1. Subscribe with `4000 0000 0000 0002` (declined card)
2. Verify `status == "past_due"` and artist stays visible for 3 days
3. After grace period, next event flips `is_active` to `False`

#### Resume
1. Update payment method in Customer Portal to `4242...`
2. Trigger retry: `stripe trigger invoice.payment_succeeded`
3. Verify `status == "active"` and `is_active == True` again

### Useful CLI Triggers
```bash
stripe trigger customer.subscription.created
stripe trigger customer.subscription.updated
stripe trigger customer.subscription.deleted
stripe trigger invoice.payment_succeeded
stripe trigger invoice.payment_failed
stripe trigger checkout.session.completed
```

All received events appear in **Suscripciones → Eventos de Stripe** audit log.
