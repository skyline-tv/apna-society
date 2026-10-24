# Apna Society Backend V2

Fresh Node.js / TypeScript / Express / MongoDB foundation for Apna Society.

This project is independent of the previous PostgreSQL/Prisma backend. Product behavior is reused only as a functional reference.

## Stack

- Node.js 20+, TypeScript, Express
- MongoDB + Mongoose (replica-set ready for transactions)
- JWT access + rotating refresh tokens
- Email OTP via Resend
- Zod validation, Helmet, CORS, rate limiting
- Pino logging, Swagger at `/api/docs`
- Socket.IO infrastructure (notifications later)
- Vitest, Docker Compose

## Project structure

```text
backend-v2/
  src/
    config/           # env + constants
    database/         # mongoose connection + health
    modules/
      auth/           # OTP, sessions, audit
      users/          # user + membership models
      society/        # society, wing, flat + admin management APIs
      billing/        # bills, payments, receipts, interest, gateway provider
      visitors/       # guards, visitor logs, OTP, expiry, socket events
    middleware/       # auth, roles, admin society context, validation, errors
    shared/           # errors, shared types
    utils/            # crypto, logger, async handler
    docs/             # OpenAPI
    workers/          # Socket.IO attach point
  scripts/            # seed + admin provisioning
  tests/              # unit + integration
  docs/               # ops docs (replica set)
```

## Installation

```bash
cd backend-v2
cp .env.example .env
# edit secrets (JWT_*, RESEND_API_KEY, MONGODB_URI)
npm install
```

## Environment

| Variable | Purpose |
| --- | --- |
| `PORT` | HTTP port (default `4000`) |
| `NODE_ENV` | `development` / `test` / `production` |
| `MONGODB_URI` | Mongo connection string (never hardcode in code) |
| `JWT_ACCESS_SECRET` | Access token secret (≥32 chars) |
| `JWT_REFRESH_SECRET` | Refresh token secret (≥32 chars) |
| `ACCESS_TOKEN_EXPIRY` | e.g. `15m` |
| `REFRESH_TOKEN_EXPIRY` | e.g. `30d` |
| `RESEND_API_KEY` | Resend API key |
| `EMAIL_FROM` | From address for OTP emails |
| `CORS_ORIGINS` | Comma-separated allowed origins |
| `BILLING_ANNUAL_INTEREST_BPS` | Annual late interest in basis points (default `2400` = 24%) |
| `OFFLINE_PAYMENTS_ENABLED` | Compatibility flag. Admin cash/cheque recording is always allowed. |
| `PAYMENT_GATEWAY_PROVIDER` | `mock` (default) or `razorpay` |
| `PAYMENTS_LIVE_ENABLED` | `true` only when ready for live Razorpay charges (explicit opt-in) |
| `DEMO_PAYMENTS_ENABLED` | Simulated in-app checkout. Default `false`. Forbidden in production. |
| `RAZORPAY_KEY_ID` | Razorpay key id — never commit real values |
| `RAZORPAY_KEY_SECRET` | Razorpay key secret for order/payment signatures |
| `RAZORPAY_WEBHOOK_SECRET` | Webhook HMAC secret (required for live) |
| `VISITOR_OTP_TTL_MS` | Entry OTP validity (default 10 minutes) |
| `VISITOR_OTP_MAX_ATTEMPTS` | Max OTP verify attempts (default 5) |
| `VISITOR_PENDING_TTL_MS` | Pending approval expiry (default 30 minutes) |
| `VISITOR_EXPIRY_WORKER_ENABLED` | `true` to run in-process expiry ticker |
| `VISITOR_EXPIRY_WORKER_INTERVAL_MS` | Expiry poll interval (default 60s) |
| `FACILITY_BOOKING_WORKER_ENABLED` | `true` to expire pending bookings in background |
| `ANNOUNCEMENT_WORKER_ENABLED` | `true` for scheduled announcement publication |
| `COMPLAINT_STORAGE_PROVIDER` / `ANNOUNCEMENT_STORAGE_PROVIDER` | `local` \| `memory` \| `s3` (`memory` forbidden in production) |
| `S3_*` | Endpoint, bucket, keys when using S3-compatible storage |
| `REDIS_ENABLED` | `true` to use Redis cache-aside (fail-open when unavailable) |
| `REDIS_URL` | e.g. `redis://127.0.0.1:6379/0` or `redis://redis:6379/0` in Compose |
| `REDIS_PASSWORD` | Redis AUTH password (required when Compose Redis uses `requirepass`) |
| `REDIS_KEY_PREFIX` | Key prefix (default `apna:`) |
| `CACHE_TTL_*_SECONDS` | Dashboard / reports / wings / facilities / announcements TTLs |

## Local development

Start MongoDB locally (single node is fine for non-transactional local work; use replica set for transactions):

```bash
# example: local mongod without public bind
mongod --dbpath ./data --bind_ip 127.0.0.1
```

Or use Docker Compose (includes single-node replica set + private Redis; Mongo/Redis ports not published):

```bash
docker compose up -d mongo mongo-init-replica redis
# Full stack:
# docker compose up -d
```

Then:

```bash
npm run dev
```

API:

- Health: `GET /health`, `GET /api/v1/health`
- Swagger: `http://localhost:4000/api/docs`

## Seed data

Idempotent society seed (no residents/users/bills):

```bash
npm run seed
```

Creates **Monarch Solitaire A to E**:

- 5 wings (A–E), 7 floors, 4 flats/floor → **140 flats**
- Flat numbers `A-101` … `E-704`
- Maintenance: **112 × ₹4,000** + **28 × ₹5,000** = **₹5,88,000 / month**

Re-running seed does not overwrite existing society configuration or existing flat rates.

## Admin provisioning

Public registration is disabled. Create a login-capable admin:

```bash
npm run prepare:admin -- --email admin@example.com --name "Society Admin"
```

## Authentication flow

1. `POST /api/v1/auth/request-otp` `{ "email": "..." }`
   - Email normalized (trim + lowercase)
   - OTP hashed at rest, 5-minute expiry, max 5 attempts
   - Resend cooldown + request window limits
   - Same response whether or not the account exists (anti-enumeration)
   - OTP only emailed for active users with `canLogin: true`
2. `POST /api/v1/auth/verify-otp` `{ "email", "otp" }` → access + refresh tokens
3. `POST /api/v1/auth/refresh` `{ "refreshToken" }` → rotated pair (reuse revokes family)
4. `POST /api/v1/auth/logout` / `POST /api/v1/auth/logout-all`
5. `GET /api/v1/auth/me` (Bearer access token)

OTP values are never logged. OTP/refresh hashes are never returned in API responses.

## Admin society / wing / flat management

All routes require `Authorization: Bearer <accessToken>` and an **ADMIN** membership.
Society context is resolved from membership (`primarySocietyId` or first admin membership).
Optional header `x-society-id` is accepted only when the admin belongs to that society.
`societyId` in request bodies is ignored.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/v1/admin/society` | View society profile |
| PATCH | `/api/v1/admin/society` | Update allowed fields (code/id immutable) |
| GET | `/api/v1/admin/society/configuration` | Society + wing/flat configuration totals |
| GET/POST | `/api/v1/admin/wings` | List / create wings |
| GET/PATCH | `/api/v1/admin/wings/:wingId` | Get / update wing (includes flat count) |
| GET/POST | `/api/v1/admin/flats` | List (filters/pagination) / create flats |
| GET/PATCH | `/api/v1/admin/flats/:flatId` | Get / update flat (occupancy fields forbidden) |
| GET | `/api/v1/admin/flats/:flatId/residents` | Active resident summaries |
| GET/POST | `/api/v1/admin/users` | Search / provision OWNER or TENANT |
| GET/PATCH | `/api/v1/admin/users/:userId` | View / update resident |
| POST | `/api/v1/admin/users/:userId/deactivate` | Deactivate resident |
| POST | `/api/v1/admin/flats/:flatId/assign-owner` | VACANT → OWNER_OCCUPIED |
| POST | `/api/v1/admin/flats/:flatId/assign-tenant` | OWNER_OCCUPIED → TENANT_OCCUPIED |
| POST | `/api/v1/admin/flats/:flatId/end-tenant-occupancy` | TENANT_OCCUPIED → OWNER_OCCUPIED |
| POST | `/api/v1/admin/flats/:flatId/end-owner-occupancy` | OWNER_OCCUPIED → VACANT |
| GET | `/api/v1/admin/flats/:flatId/occupancy-history` | Full occupancy history |
| GET | `/api/v1/admin/occupancies` | Society occupancy list |
| GET | `/api/v1/admin/dashboard` | DB-derived dashboard statistics |
| GET | `/api/v1/resident/profile` | Resident profile |
| GET | `/api/v1/resident/flats` | Accessible flats |
| GET | `/api/v1/resident/flats/:flatId` | Flat detail (access-filtered) |
| GET | `/api/v1/resident/flats/:flatId/occupancy` | Permitted occupancy view |
| POST | `/api/v1/admin/billing/generate` | Generate 1- or 3-month bills |
| GET | `/api/v1/admin/billing/bills` | List bills (filters) |
| GET | `/api/v1/admin/billing/bills/:billId` | Bill detail |
| GET | `/api/v1/admin/billing/bills/:billId/interest` | Interest as-of date |
| GET | `/api/v1/admin/billing/summary` | Collection dashboard |
| GET | `/api/v1/admin/billing/eligible-flats` | Flats eligible for billing |
| POST | `/api/v1/admin/payments/offline` | Record offline payment (config-gated) |
| GET | `/api/v1/admin/payments` | List payments |
| GET | `/api/v1/admin/payments/:paymentId` | Payment detail |
| GET | `/api/v1/admin/receipts/:receiptId` | Immutable receipt + PDF |
| GET | `/api/v1/resident/billing/bills` | Owner bills only |
| POST | `/api/v1/resident/billing/bills/:billId/payment-order` | Create UPI order |
| POST | `/api/v1/resident/billing/verify-payment` | Verify signature + settle |
| GET | `/api/v1/resident/billing/payments` | Owner payments |
| GET | `/api/v1/resident/billing/receipts` | Owner receipts |
| POST | `/api/v1/webhooks/payments` | Gateway webhook |

### Occupancy state machine

```text
VACANT → OWNER_OCCUPIED → TENANT_OCCUPIED
                ↓                ↓
             VACANT      OWNER_OCCUPIED → VACANT
```

- Tenant departure preserves the owner and returns `OWNER_OCCUPIED`.
- Owner departure requires tenant occupancy to end first.
- Only the occupancy lifecycle service may change `occupancyStatus` / active user refs.
- Generic flat PATCH rejects occupancy fields.

### Access matrix

| Actor | Financial | Residential |
| --- | --- | --- |
| Admin | yes | yes |
| Owner (owner-occupied) | yes | yes |
| Owner (tenant-occupied) | yes | no |
| Active tenant | no | yes |
| Previous tenant | no | no (own history only) |
| Guard | no | no |

### Provisioning / assignment examples

```bash
# Provision owner (no flat access yet)
curl -X POST "$API/api/v1/admin/users" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Ravi","email":"ravi@example.com","role":"OWNER"}'

# Assign owner to vacant flat
curl -X POST "$API/api/v1/admin/flats/$FLAT_ID/assign-owner" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"userId":"USER_ID","effectiveFrom":"2026-10-19T00:00:00.000Z"}'

# Assign tenant
curl -X POST "$API/api/v1/admin/flats/$FLAT_ID/assign-tenant" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"userId":"TENANT_ID","effectiveFrom":"2026-10-20T00:00:00.000Z"}'

# End tenant occupancy
curl -X POST "$API/api/v1/admin/flats/$FLAT_ID/end-tenant-occupancy" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"effectiveTo":"2026-11-01T00:00:00.000Z","reason":"Lease ended"}'
```

## MongoDB replica set

See [docs/mongodb-replica-set.md](./docs/mongodb-replica-set.md).

## Docker

Requires the Docker Compose plugin (`docker compose`).

```bash
cp .env.example .env
# set JWT secrets and RESEND_API_KEY
docker compose up -d --build
```

- API: host port `4000` (or `PORT`)
- MongoDB: internal network only (not published)

Image-only build (without Compose):

```bash
docker build -t apna-society-backend-v2 .
```

## Testing

Tests use an in-memory MongoDB replica set. They never touch production data.

```bash
npm test
npm run test:coverage
```

## Typecheck / lint / build

```bash
npm run typecheck
npm run lint
npm run build
```

## VPS deployment preparation

See **Production hardening (Phase 12)** below for the full checklist. Summary:

1. Provision a VPS with Docker + Compose.
2. Copy this project; create `.env` with strong secrets (do not commit). Production requires Resend + replica-set Mongo URI + non-placeholder JWTs.
3. Keep MongoDB off the public interface (Compose default).
4. Put TLS termination (Nginx example: `deploy/nginx.example.conf`) in front of the API.
5. Restrict `CORS_ORIGINS` to real app origins.
6. Run `docker compose up -d --build`.
7. Run seed + admin provisioning once (never on an already-seeded production DB unless intentional).
8. Schedule `npm run backup:mongo` and periodically restore-test into a separate database.
9. Monitor `/health`, `/api/v1/health`, and `/api/v1/ready`.

## API documentation

Interactive OpenAPI UI: `/api/docs`  
Raw spec: `/api/docs.json`

## Roles

`ADMIN` | `OWNER` | `TENANT` | `GUARD`

Role middleware is provided for coarse gates. Flat-level authorization must still use membership + `societyId` checks in services (not role middleware alone).

## Maintenance billing (Phase 4)

### Calendar and due dates

- Bills are generated for periods starting on the **1st** of a calendar month (society timezone, default `Asia/Kolkata`).
- Payment due date is the **10th** of that first month (end of day IST).
- Late interest begins on the **11th**.
- `numberOfMonths` is `1` or `3`. Three-month prepaid bills cover three consecutive calendar months (not 90 days).

### Amounts

- All money uses **integer paise** (₹1 = 100 paise). No floating-point arithmetic.
- Monthly rate comes from each flat’s configured `maintenanceRate` (integer rupees → paise). Clients cannot supply the maintenance amount during ordinary generation.
- Vacant / unassigned flats are skipped. Only the flat’s **active owner** is the financial party; tenants never receive financial access.

### Late interest

- Annual rate: **24%** (`BILLING_ANNUAL_INTEREST_BPS=2400`).
- Day-count: **actual/365**, simple (never compounded onto interest).
- Accrual starts on the civil day after the due date (**11th** when due is the **10th**), in the society timezone (`Asia/Kolkata` by default).
- Per-segment formula:

  `interestPaise = floor(principalPaise × annualRateBps × days / (10000 × 365))`

  Rounding: truncate toward zero via BigInt division (floor for non-negative amounts), applied **per principal segment**.
- **Principal ledger:** each bill has an immutable ledger (`OPENING`, `PAYMENT_ALLOCATION`, `REFUND_RESTORATION`, `ADJUSTMENT`). Interest is the sum of daily interest on each historical principal level.
- A successful payment reduces interest-bearing principal from **civil midnight of its settlement date** (society TZ). Earlier days keep the prior principal — partial payments are never back-applied.
- Failed/pending payments never write ledger reductions. Refunds append `REFUND_RESTORATION` effective on the refund civil day (future interest only; history unchanged).
- Historical `asOf` ignores ledger events after that civil day.
- Stored `interestAccruedPaise` is a refreshable summary derived from the ledger; recalculation is idempotent.

### Payments and receipts

- Provider abstraction with a Razorpay-compatible mock (`PAYMENT_GATEWAY_PROVIDER=mock` by default).
- Owner creates a payment order for **outstanding principal** (server-side amount). Signature verification or webhook is required before `SUCCESS`.
- Settlement is transactional: payment → bill balance → immutable receipt.
- Allocation: principal first; any remainder to interest is recorded explicitly (`allocatedToInterestPaise`).
- Offline admin recording (cash, cheque, bank transfer) is always available and requires a reference / idempotency key.
- Webhook: `POST /api/v1/webhooks/payments` with `x-razorpay-signature` (HMAC SHA256 of raw body).

### Example: generate April bills

```bash
curl -X POST "$API/api/v1/admin/billing/generate" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"billingPeriodStart":"2026-04-01T00:00:00.000+05:30","numberOfMonths":1}'
```

## Visitors & security (Phase 5)

### Guard provisioning

Admins provision guards via `POST /api/v1/admin/guards` (no public registration). Guards receive a society-scoped `GUARD` membership with `flatId: null`. Deactivation ends the membership immediately; guard APIs require an **active** GUARD membership. Guards cannot access billing/payment/receipt APIs.

### Approval routing

| Flat occupancy | Approver |
| --- | --- |
| `OWNER_OCCUPIED` | Active owner |
| `TENANT_OCCUPIED` | Active tenant (not the owner) |
| `VACANT` | Rejected (`NO_ACTIVE_RESIDENT`) |

### OTP & entry (email-only)

- After resident approval, a 6-digit OTP is generated, **hashed** (SHA-256), and **emailed** via Resend.
- Delivery address: `visitorEmail` on the visitor request if provided, otherwise the assigned resident’s email.
- If no usable email exists, approval fails with `VISITOR_EMAIL_REQUIRED` (no SMS fallback).
- Guard verifies OTP → `ENTERED`; checkout → `EXITED`.
- OTP never returned from list/detail APIs or Socket.IO events; never logged.

### Socket.IO

Connect with JWT (`auth.token` or `Authorization` bearer). Join:

- `join:resident` `{ societyId }` → room `society:{id}:resident:{userId}`
- `join:guards` `{ societyId }` → room `society:{id}:guards`

Events (after DB commit): `visitor:approval_requested`, `visitor:approved`, `visitor:rejected`, `visitor:entered`, `visitor:exited`.

### Expiry worker

Set `VISITOR_EXPIRY_WORKER_ENABLED=true` to start the in-process interval worker from `src/server.ts`. It expires pending approvals and unused OTPs idempotently; visitors with `entryStatus=ENTERED` are never expired/removed.

```bash
# Example guard visitor request
curl -X POST "$API/api/v1/guard/visitors" -H "Authorization: Bearer $GUARD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"flatId":"...","visitorName":"Ravi","visitorPhone":"+91 9000000000","visitorType":"GUEST","purpose":"Visit","numberOfVisitors":1}'
```

## Vehicles & parking (Phase 6)

### Resident vehicles

| Method | Path | Notes |
| --- | --- | --- |
| POST | `/api/v1/resident/vehicles` | Register (residential access required) |
| GET | `/api/v1/resident/vehicles` | List accessible vehicles + active parking ids |
| GET | `/api/v1/resident/vehicles/:vehicleId` | Detail |
| PATCH | `/api/v1/resident/vehicles/:vehicleId` | Update make/model/colour/type |
| POST | `/api/v1/resident/vehicles/:vehicleId/deactivate` | Soft-deactivate (history kept) |
| GET | `/api/v1/resident/parking` | Active allocations for residential flats |
| GET | `/api/v1/resident/parking/allocations/:allocationId` | Allocation + slot |

Access follows the occupancy matrix: owner residential only when `OWNER_OCCUPIED`; active tenant when `TENANT_OCCUPIED`; previous tenants and guards have no residential vehicle access. Registration numbers are normalized (uppercase, spaces/hyphens removed) and validated against practical Indian plate formats.

### Admin parking

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/api/v1/admin/vehicles` | Society vehicle list |
| POST | `/api/v1/admin/parking/slots` | Create slot |
| GET | `/api/v1/admin/parking/slots` | List + `availability` filter |
| GET | `/api/v1/admin/parking/slots/:slotId` | Detail |
| PATCH | `/api/v1/admin/parking/slots/:slotId` | Update |
| POST | `/api/v1/admin/parking/slots/:slotId/set-active` | Activate/deactivate |
| GET | `/api/v1/admin/parking/summary` | Occupancy summary |
| POST | `/api/v1/admin/parking/allocations` | Allocate slot |
| GET | `/api/v1/admin/parking/allocations` | List (incl. history) |
| GET | `/api/v1/admin/parking/allocations/:allocationId` | Detail |
| POST | `/api/v1/admin/parking/allocations/:allocationId/release` | End allocation |

Rules: same-society vehicle/flat/slot; active vehicle + slot; slot type must match vehicle type; one active allocation per slot and per vehicle (partial unique indexes + transactions). Occupied slots cannot be deactivated until released.

### Guard vehicle logs

| Method | Path | Notes |
| --- | --- | --- |
| POST | `/api/v1/guard/vehicles/entry` | Entry (registered or visitor plate) |
| POST | `/api/v1/guard/vehicles/exit` | Exit by `logId` or registration |
| GET | `/api/v1/guard/vehicles/logs` | Society logs |

Visitor/unregistered plates are never auto-created as resident `Vehicle` records. Guards cannot create slots or allocations.

```bash
curl -X POST "$API/api/v1/resident/vehicles" -H "Authorization: Bearer $TOKEN" \
  -H "x-society-id: $SOCIETY_ID" -H "Content-Type: application/json" \
  -d '{"flatId":"...","vehicleType":"FOUR_WHEELER","registrationNumber":"MH12AB1234"}'
```

## Complaints & maintenance (Phase 7)

### Lifecycle

`OPEN → ASSIGNED → IN_PROGRESS → RESOLVED → CLOSED`

Also: `OPEN → CANCELLED`; `ASSIGNED → OPEN` (unassign); `IN_PROGRESS → ASSIGNED` (reassign).  
`CLOSED` and `CANCELLED` are terminal. Invalid transitions return `409 INVALID_STATUS_TRANSITION`.

### Resident APIs

| Method | Path | Notes |
| --- | --- | --- |
| POST | `/api/v1/resident/complaints` | Create (residential access; default priority `MEDIUM`) |
| GET | `/api/v1/resident/complaints` | List authorized complaints |
| GET | `/api/v1/resident/complaints/:complaintId` | Detail + public history |
| POST | `/api/v1/resident/complaints/:complaintId/cancel` | Cancel own `OPEN` only |
| POST | `/api/v1/resident/complaints/:complaintId/attachments` | Multipart field `file` (images) |
| GET | `/api/v1/resident/complaints/:complaintId/attachments/:attachmentId` | Authorized download |

Residents cannot PATCH priority/status/assignment. `internalNotes` are never returned.

### Admin APIs

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/api/v1/admin/complaints` | List + filters/sort |
| GET | `/api/v1/admin/complaints/summary` | Dashboard counts |
| GET | `/api/v1/admin/complaints/categories` | Supported categories |
| GET | `/api/v1/admin/complaints/:complaintId` | Detail + full history |
| PATCH | `/api/v1/admin/complaints/:complaintId/priority` | Admin-only priority |
| POST | `.../assign` | INTERNAL (ADMIN/OWNER member) or EXTERNAL vendor |
| POST | `.../unassign` | ASSIGNED → OPEN |
| POST | `.../start` | ASSIGNED → IN_PROGRESS |
| POST | `.../resolve` | Requires `resolutionNotes` |
| POST | `.../close` | RESOLVED → CLOSED (keeps resolution) |
| POST | `.../cancel` | Requires `reason` |
| POST/GET | `.../attachments` | Upload / download |

### Attachments / storage

- Provider: `COMPLAINT_STORAGE_PROVIDER=local|memory` (default `local`)
- Local dir: `COMPLAINT_STORAGE_LOCAL_DIR` (default `./storage/complaints`)
- Limits: `COMPLAINT_ATTACHMENT_MAX_BYTES` (5MB), `COMPLAINT_ATTACHMENT_MAX_COUNT` (5)
- MIME allow-list validated via magic bytes (not client Content-Type alone)
- MongoDB stores metadata + opaque `storageKey` only; keys are never returned to clients
- Production: use durable disk or replace the adapter with an object-store implementation; keep the private-key download path

### Socket.IO

After DB commit: `complaint:assigned`, `complaint:reassigned`, `complaint:status_changed` to raiser (and internal assignee) resident rooms. External vendors are not notified. Payloads exclude internal notes and phone numbers.

```bash
curl -X POST "$API/api/v1/resident/complaints" -H "Authorization: Bearer $TOKEN" \
  -H "x-society-id: $SOCIETY_ID" -H "Content-Type: application/json" \
  -d '{"flatId":"...","category":"PLUMBING","title":"Leak","description":"Kitchen sink leak"}'
```

## Phase status

**Phase 1:** auth, models/indexes, security middleware, seed, Docker, docs.  
**Phase 2:** admin society / wing / flat management, dashboard, occupancy foundation.  
**Phase 3:** owner/tenant provisioning, occupancy lifecycle, resident APIs, access matrix.  
**Phase 4 / 4.1:** maintenance billing, payments, receipts, late interest, ledger integrity.  
**Phase 5:** guard provisioning, visitor request/approval/OTP/entry-exit, Socket.IO rooms, expiry worker.  
**Phase 6:** resident vehicles, parking slots/allocations, guard vehicle entry/exit logs.  
**Phase 7:** complaints lifecycle, assignment, attachments, Socket.IO notifications.  
**Phase 8:** staff employment records, attendance, shifts, facilities and bookings.  
**Phase 9:** announcements, persistent notifications, scheduled publication worker.  
**Phase 11:** admin reports, analytics, and CSV exports.  
**Phase 12:** production hardening, email-only OTP, backups, deployment.  
**Phase 13 (this):** Mongo indexes, Redis cache-aside, query optimizations, k6 load profiles.

### Reports, analytics & exports (Phase 11)

Admin-only (`requireRoles('ADMIN')` + society isolation). Owners, tenants, and guards cannot access.

| Endpoint | Purpose |
| --- | --- |
| `GET /api/v1/admin/reports/dashboard` | Compact financial + collection + outstanding + complaint overview |
| `GET /api/v1/admin/reports/financial` | Billed/collected/outstanding/interest/refunds, online vs offline, monthly/yearly |
| `GET /api/v1/admin/reports/collections` | Collection %, wing-wise, monthly trends, bill status counts |
| `GET /api/v1/admin/reports/outstanding` | Flat-wise outstanding (paginated) |
| `GET /api/v1/admin/reports/complaints` | Complaint analytics + avg resolution time + workload |
| `GET /api/v1/admin/reports/export/:type` | Streaming CSV (`financial`, `collections`, `outstanding`, `payments`, `complaints`) |

**Money:** all totals are integer paise from Bill/Payment snapshots (never live flat rates).  
**Collection %:** `floor(collectedPaise * 10000 / billedPaise) / 100`; returns `0` when billed is `0`.  
**Date filters:** bill reports use `billingPeriodStart`; payments use `paidAt` (fallback `createdAt`); complaints use `createdAt`. Default lookback 365 days; max range 3 years.  
**CSV:** streamed via Mongo cursors; cells starting with `= + - @` are prefixed to prevent formula injection.

### Announcements & notifications (Phase 9)

**Announcements** are society notices with audience criteria (`ALL_RESIDENTS` | `WING` | `SELECTED_FLATS`). Recipients are resolved from **current** occupancy/membership at publication time — not from a stored stale recipient list.

Categories: `GENERAL`, `MAINTENANCE`, `WATER_SUPPLY`, `ELECTRICITY`, `SECURITY`, `EVENT`, `EMERGENCY`, `MEETING`, `PARKING`, `OTHER`.  
Priorities: `NORMAL`, `IMPORTANT`, `URGENT`.  
Lifecycle: `DRAFT → SCHEDULED → PUBLISHED → ARCHIVED` (also `DRAFT|SCHEDULED → CANCELLED`).

**Resident visibility** follows residential occupancy (tenant when `TENANT_OCCUPIED`; owner residential only when `OWNER_OCCUPIED`). Guards cannot use resident announcement APIs. Expired published notices leave the active feed. Admin notes and delivery metadata are never exposed to residents.

**Scheduled worker** — enable with `ANNOUNCEMENT_WORKER_ENABLED=true`. Interval: `ANNOUNCEMENT_WORKER_INTERVAL_MS` (default 30s). Multi-instance safe via atomic `findOneAndUpdate` claim (`SCHEDULED → PUBLISHED` + `deliveryState PENDING`). Restart-safe: resumes `PUBLISHED` + `PENDING` deliveries. Idempotent notification keys prevent duplicate delivery. Expired scheduled items are not published.

**Attachments** — image/PDF only (magic-byte validated). Storage: `ANNOUNCEMENT_STORAGE_PROVIDER` (`local`|`memory`), opaque keys, authorized download only.

**Notifications** are a separate persistent inbox per recipient (`Notification` model, unique `idempotencyKey`). Types include announcement, billing, visitor, complaint, facility, staff shift, and `SYSTEM`. Socket event `notification:created` emits **after** persistence. Existing Phase 5–8 Socket.IO event contracts are unchanged; `announcement:published` is additive.

**Production:** set `ANNOUNCEMENT_WORKER_ENABLED=true` on each API instance (or a dedicated worker process running the same binary). Use durable storage (`local` path on shared volume, or `s3`). Do not treat `notificationCreatedCount` as confirmed push delivery.

### Production hardening (Phase 12)

**Security / env**
- Production rejects placeholder JWT secrets, identical access/refresh secrets, missing `RESEND_API_KEY`, `memory` storage, and non-replica-set Mongo URIs (unless `mongodb+srv`).
- Live Razorpay requires `PAYMENT_GATEWAY_PROVIDER=razorpay`, `PAYMENTS_LIVE_ENABLED=true`, and all three Razorpay secrets. Online orders are refused until that opt-in.
- Simulated checkout (`DEMO_PAYMENTS_ENABLED`) is off by default and forbidden in production. Residents pay cash or cheque at the office until live Razorpay is enabled.
- Visitor OTP is **email-only** (no SMS packages, env vars, or fallback).
- Structured logs redact tokens, OTPs, payment/email/S3 secrets.

**Health**
- `GET /health` — liveness
- `GET /api/v1/health` — DB ping
- `GET /api/v1/ready` — readiness (DB, workers flags, email/payments/storage)

**Workers** (enable in production): visitor expiry, announcement publication, facility pending-booking expiry. All stop on SIGTERM; Socket.IO closed on shutdown.

**Backups**
```bash
MONGODB_URI='...' npm run backup:mongo
# Restore into a *separate* DB only:
RESTORE_CONFIRM=YES RESTORE_MONGODB_URI='mongodb://.../apna_society_restore?replicaSet=rs0' \
  npm run restore:mongo -- ./backups/<stamp>/apna_society.archive.gz
```
Retention: `BACKUP_RETENTION_DAYS` (default 14). Never restore onto production without an explicit outage plan.

**Deploy (VPS)**
1. Install Docker + Compose; copy `.env` with production secrets (never commit).
2. `docker compose up -d` (API healthcheck uses `/api/v1/ready`; storage volume `api_storage`).
3. Terminate TLS with Nginx (`deploy/nginx.example.conf`); set `CORS_ORIGINS` to the real app origin.
4. Cron `npm run backup:mongo` (or mount `mongo_backups` and run `mongodump` in the mongo container).
5. Smoke load (against staging only): `BASE_URL=http://127.0.0.1:4000 npm run load:smoke`.

### Database optimization, Redis & load testing (Phase 13)

**Indexes** — see [`docs/INDEXES.md`](docs/INDEXES.md). New compounds include bill wing+period, payment `gatewayOrderId` / `createdAt`, announcement `publishedAt`, visitor wing/entryAt, complaint `createdAt`. Verify plans:

```bash
npm run indexes:verify
```

**Redis** — optional cache-aside (`ioredis`). Society-scoped keys; post-commit invalidation after payments, bills, occupancy, facilities, announcements, complaint status. Disabled by default in `.env.example`; Compose sets `REDIS_ENABLED=true` with private Redis + password. Details: [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md).

**Cached reads (TTLs ~30–300s):** admin dashboard, reports dashboard/financial/collections/complaint analytics, billing summary, wings list, facilities list. Never caches tokens, OTPs, settlement decisions, or webhook payloads.

**Metrics (admin):** `GET /api/v1/admin/ops/metrics` — HTTP, cache hit/miss/error/invalidation, Redis status.

**Load tests (k6 preferred; falls back to Node smoke if k6 missing):**

```bash
npm run load:smoke    # PROFILE=smoke
npm run load:normal
npm run load:stress
npm run load:spike
npm run load:soak
# Authenticated staging example:
SCENARIO=admin-reads LOAD_TEST_ACCESS_TOKEN=... npm run load:k6
```

Profiles start at ~50 VUs for `normal` — these are test knobs, not guaranteed production capacity. Never run against production.

**Not claimed production-ready until:** live Razorpay credentials are installed and webhook endpoint is verified end-to-end; Resend domain is verified; backups have been restore-tested on a non-production database; TLS and firewall are configured on the VPS.

Not yet: Flutter integration, payroll.
