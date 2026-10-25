# Google Play review — isolated demo environment

This document is for Play Console reviewers and the SkyLine operator who deploys the **demo API**. It does **not** contain production credentials.

**Label shown in the app:** `DEMO MODE — SAMPLE DATA`

## What this is

A dedicated review environment with fictional Maple Grove Residences data. It is not a copy of any real society.

- Separate Mongo database (`apna_society_demo` or any name other than `apna_society`)
- Separate API process (`DEMO_MODE=true`)
- Mock payments only — no Razorpay, no live charges
- Receipts watermarked as simulated sample data
- Role-based access still enforced

The production API **rejects** `DEMO_MODE` and reserved demo usernames (`demo_admin`, `demo_owner`, `demo_tenant`, `demo_guard`).

## Reviewer sign-in (English)

You do **not** need a personal email, a real mobile number, a new registration, an expiring OTP, or a real payment.

1. Open Apna Society.
2. Tap **Explore sample data**.
3. Wait until the amber bar reads `DEMO MODE — SAMPLE DATA`.
4. Tap a role chip (Admin, Owner, Tenant, Security Guard) or type a username below.
5. Tap **Login**.

If **Explore sample data** cannot reach the demo server, use the same usernames against the demo API host provided by the developer. Do not use these accounts on the production login screen; they will fail there on purpose.

### Accounts

| Role | Username | Password |
| --- | --- | --- |
| Admin | `demo_admin` | `demo@12345` |
| Owner | `demo_owner` | `demo@12345` |
| Tenant | `demo_tenant` | `demo@12345` |
| Security Guard | `demo_guard` | `demo@12345` |

Optional mobile login OTP (does not expire in demo): `123456`  
Visitor entry OTP (reusable, does not expire in demo): `246810`

Society: **Maple Grove Residences** (fictional, Pune). Owner lives in A-101. Tenant lives in A-102.

## What to try

- **Admin:** dashboard, wings/flats, generate bills (pick a due date), additional services, one-time collections, vehicles, visitors, reports, receipts.
- **Owner:** bills, balances, payment history, receipts, additional services, pay a simulated collection.
- **Tenant:** permitted resident/visitor screens only. Admin billing is denied.
- **Guard:** register a visitor, verify OTP `246810`, confirm entry, record exit, view history.

Every checkout is simulated. Receipts show `SIMULATED PAYMENT - SAMPLE DATA - NOT A REAL TRANSACTION`.

## Operator: VPS (pull and start)

Do **not** edit production `.env`. The `demo-api` Compose service uses a separate database (`apna_society_demo`) and seeds on startup.

```bash
cd /path/to/apna_society/backend-v2
git pull
docker compose up -d --build demo-api
```

Add this Caddy site (also in `backend-v2/caddy/demo-apiapnasociety.skylinetv.in.caddy`) and point DNS at the VPS:

```
demo-apiapnasociety.skylinetv.in {
  encode gzip
  reverse_proxy apna-society-demo-api:4000
}
```

Then check:

```bash
curl https://demo-apiapnasociety.skylinetv.in/api/v1/public/environment
```

## Local demo process (do not use production `.env`)

```bash
cd backend-v2
export NODE_ENV=development
export DEMO_MODE=true
export PORT=4001
export MONGODB_URI=mongodb://127.0.0.1:27017/apna_society_unused
export DEMO_MONGODB_URI=mongodb://127.0.0.1:27017/apna_society_demo
export PAYMENT_GATEWAY_PROVIDER=mock
export PAYMENTS_LIVE_ENABLED=false
export DEMO_PAYMENTS_ENABLED=true
# Distinct JWT secrets, >=32 characters each
npx tsx scripts/seed-demo.ts
npm run dev
```

Flutter debug default demo host: `http://192.168.1.130:4001`  
Release default: `https://demo-apiapnasociety.skylinetv.in`  
Override with `--dart-define=DEMO_API_URL=https://…`

Confirm isolation:

```
GET /api/v1/public/environment
→ { "demoMode": true, "label": "DEMO MODE — SAMPLE DATA", "simulatedPayments": true }
```

Production `/api/v1/public/environment` returns `demoMode: false`. The app refuses to open sample data against that host.

## Features not available in demo

- Live Razorpay / real money
- SMS delivery of login or visitor OTPs (fixed demo codes are used instead)
- Push notifications to real devices, unless a demo Firebase project is configured
- Production resident records, receipts, or societies
