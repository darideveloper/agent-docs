---
created: 2026-08-20
updated: 2026-09-04
tags:
  - stripe
  - subscriptions
  - testing
  - documentation
type: guide
status: active
source: templates://django/testing-stripe.md
version: 2026-09-17+4cf710f

---

# Testing Stripe Subscriptions (Worked Example)

This document covers how to configure the Stripe Dashboard, run the local
webhook bridge, and exercise the subscription lifecycle end-to-end against a
test (dev) environment first, then how to validate the same flow in live
(production) mode.

> No secrets belong here. Every credential is referenced only by its
> environment-variable name; actual values live in your gitignored `.env` files
> or the Stripe Dashboard.

## Prerequisites

- Stripe CLI installed and logged in (`stripe login`).
- `.env.dev` with `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`,
  `STRIPE_WEBHOOK_SECRET` and `STRIPE_PRICE_ID` populated with **test-mode**
  values.
- The dashboard running locally (`python manage.py runserver`, port 8000).
- Tests run via `python manage.py test` per [[django-testing-contract|Testing Contract (Django-only Runner)]] — do not use `pytest`.

> **Testing runner:** This project uses the Django-only contract ([[django-testing-contract|Testing Contract (Django-only Runner)]]). If you add subscription tests, use `django.test.TestCase` / `rest_framework.test.APITestCase` and `venv/bin/python manage.py test <APP_LABEL>.tests --verbosity=2`.

## 1. Stripe Dashboard product setup

1. Open the Stripe Dashboard → **Products** → **Add product**.
2. Name it (e.g. `<PRODUCT_NAME>`) and add a recurring price
   (`Recurring`) in the plan currency (default `<CURRENCY>`, e.g. `MXN`).
3. Copy the price ID (`price_xxx`, i.e. `<PRICE_ID>`) from the price row.
4. Set `STRIPE_PRICE_ID=<PRICE_ID>` in `.env.dev` (default for the BillingPlan
   singleton) — or paste it directly into **Suscripciones → Plan de suscripción
   → ID de precio en Stripe** to override. Make sure **Aceptar nuevas
   suscripciones** is checked.

## 2. Webhook bridge for local development

Stripe cannot reach `localhost`, so run the Stripe CLI bridge:

```bash
stripe listen --forward-to http://localhost:8000/webhooks/stripe/
```

The CLI prints a `whsec_...` signing secret (i.e. `<WEBHOOK_SECRET>`). Copy it into
`STRIPE_WEBHOOK_SECRET` in `.env.dev` and restart the dev server. The bridge
also prints every event it forwards, which is your live debug log.

> Production: create the endpoint in the Dashboard
> (https://<host>/webhooks/stripe/) and copy the signing secret into
> `STRIPE_WEBHOOK_SECRET`.

## 3. End-to-end test script

Use a staff admin account. Placeholders: `<MODEL>` (e.g. `Artist`). Cards: `4242 4242 4242 4242` (success),
`4000 0000 0000 0002` (declined).

### 3.1 Subscribe

1. Create a customer record (e.g. a `<MODEL>` instance) with a real email (`/admin/<app>/<model>/add/`).
2. Open the artist change page and click **Generate subscription link**.
   - A **Copy link** button then appears in the header; click it to copy the
     Checkout URL to the clipboard and share it in an incognito browser.
   - Until the customer pays, `<MODEL>Subscription.status == "pending"` and
     `<MODEL>.is_active == False` — a generated-but-unpaid link does **not**
     make the artist appear on the public site.
3. Complete checkout with `4242 4242 4242 4242`.
4. Verify:
   - The `stripe listen` log shows `checkout.session.completed` and
     `customer.subscription.created`.
   - `<MODEL>Subscription.status == "active"` in the admin and
     `<MODEL>.is_active == True`.
   - `/api/<resource>/` includes the artist.

### 3.2 Cancel (friendly cancellation)

1. In the artist change page click **Open Customer Portal** and share the
   portal URL, or cancel from the Stripe Dashboard under the customer.
2. The `customer.subscription.updated` event arrives with
   `cancel_at_period_end=true`.
3. Verify `<MODEL>Subscription.status == "canceling"` and
   `<MODEL>.is_active` is **still True** (visible through period end).
4. When the period ends, `customer.subscription.deleted` arrives.
   Verify `status == "canceled"` and `<MODEL>.is_active == False` — the record
   disappears from `/api/<resource>/`.

### 3.3 Grace (payment failure)

1. Generate a link, then subscribe using `4000 0000 0000 0002` (declined) —
   or use `stripe trigger invoice.payment_failed`.
2. Verify `invoice.payment_failed` sets `status == "past_due"` while
   `current_period_end + grace_period_days` is in the future: the artist stays
   visible.
3. Wait for the grace window (or shorten `BillingPlan.grace_period_days`) and
   confirm the next event flips `<MODEL>.is_active` to False.

### 3.4 Resume

1. Update the payment method in the Customer Portal to `4242 ...`.
2. Trigger the retry: `stripe trigger invoice.payment_succeeded` (or wait for
   Stripe's automatic retry).
3. Verify `status` returns to `"active"`, `current_period_end` refreshes, and
   `<MODEL>.is_active == True` again.

## 4. Useful CLI triggers

```bash
stripe trigger customer.subscription.created
stripe trigger customer.subscription.updated
stripe trigger customer.subscription.deleted
stripe trigger invoice.payment_succeeded
stripe trigger invoice.payment_failed
stripe trigger checkout.session.completed
```

Each trigger returns 200 if the signature verifies and the handler succeeds.
Every received event appears in **Suscripciones → Eventos de Stripe** (audit
log); failed processing persists the error on the row and Stripe retries.

## 5. Live testing (production cutover)

Run the sandbox flow (sections 1–4) first and get it green. Live charges move
**real money** — plan a single, small, reversible test (e.g. one real card for
one artist) and refund it from the Dashboard afterwards.

### 5.1 Prerequisites (before touching live)

- The app deployed and publicly reachable at `https://<host>/webhooks/stripe/`
  (HTTPS required; Stripe will not POST to plain HTTP).
- Production environment variables populated (names, not values, shown here):
  `STRIPE_SECRET_KEY` (live `sk_live_...`), `STRIPE_PUBLISHABLE_KEY`
  (`pk_live_...`), `STRIPE_WEBHOOK_SECRET` (`whsec_...`), `STRIPE_API_VERSION`
  (pin a fixed version, matching the SDK's default), `STRIPE_PRICE_ID`
  (`price_...`), and `HOST=https://<host>`. Keep these in your gitignored
  production env file — never in the repository or docs.
- `BillingPlan` in the admin: **Aceptar nuevas suscripciones** checked and
  **ID de precio en Stripe** set to the live recurring `price_...`.
- Every `<MODEL>` you will bill has a real email.

### 5.2 Verify the live webhook endpoint

1. Stripe Dashboard → **Developers → Webhooks** (live mode): confirm an
   endpoint points at `https://<host>/webhooks/stripe/` with events:
   `checkout.session.completed`, `customer.subscription.created`,
   `customer.subscription.updated`, `customer.subscription.deleted`,
   `invoice.payment_succeeded`, `invoice.payment_failed`.
2. The signing secret shown at creation went into `STRIPE_WEBHOOK_SECRET`.
   (It is only displayed once — if it was lost, create a new endpoint and
   rotate the secret.)
3. Use **Send test webhook** from the Dashboard to fire a sample event and
   confirm your endpoint returns 200 and the event appears in
   **Suscripciones → Eventos de Stripe**.

### 5.3 Verify the Customer Portal

1. Stripe Dashboard → **Settings → Billing → Customer Portal**: a live
   configuration must exist (cancel subscription, update payment method, view
   invoices) with the default return URL pointing at
   `https://<host>/subscriptions/portal-return/`.
2. Without it, the **Open Customer Portal** admin action fails.

### 5.4 Live smoke test

1. Create one real test `<MODEL>` (real email) in the admin.
2. **Generate subscription link**, open the Checkout URL, and pay with a
   **real card** — a real charge for the plan price is created.
3. Verify in the admin / audit log:
   - `checkout.session.completed` → `customer.subscription.created` →
     `invoice.payment_succeeded` recorded.
   - `<MODEL>Subscription.status == "active"`, `<MODEL>.is_active == True`.
   - `GET /api/<resource>/` includes the artist.
4. **Open Customer Portal** → cancel. Verify `status == "canceling"` and the
   artist stays visible until `current_period_end`, then `status == "canceled"`
   and the artist disappears after `customer.subscription.deleted`.
5. Refund the test charge from the Dashboard if it was only for validation.

### 5.5 Rollback

- If something misbehaves: set **Aceptar nuevas suscripciones** off in the
  `BillingPlan` singleton (blocks new links), or clear `STRIPE_PRICE_ID` /
  unset the `BillingPlan` price. Disabling the webhook endpoint in the
  Dashboard pauses all subscription state updates. `<MODEL>.is_active` only
  changes via webhooks, so with the endpoint disabled nothing flips.