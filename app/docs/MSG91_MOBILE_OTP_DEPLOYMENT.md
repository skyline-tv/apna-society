# MSG91 Mobile OTP — Deployment Guide

**Scope: Login SMS OTP only** (SendOTP + Verify OTP + Resend).  
Email remains for notifications / visitor entry OTP — not for login.

Official MSG91 catalog: [MSG91 docs modules](https://docs.msg91.com/p/module.json?collectionId=C6NTmvei0Af4) → module **OTP** (`SendOTP`, `Verify OTP`, `Resend OTP`).

**Do not set `SMS_OTP_ENABLED=true` until DLT mapping is correct.**  
With `SMS_OTP_ENABLED=false`, backend uses the in-memory provider (local/dev/CI).

## Backend API mapping (already implemented)

| Step | App route | MSG91 OTP v5 |
| --- | --- | --- |
| Request code | `POST /api/v1/auth/request-otp` `{ "mobile" }` | `POST {MSG91_BASE_URL}/otp?template_id&mobile&otp_length&otp_expiry` + header `authkey` |
| Verify code | `POST /api/v1/auth/verify-otp` `{ "mobile", "otp" }` | `GET {MSG91_BASE_URL}/otp/verify?mobile&otp` + header `authkey` |
| Resend (server cooldown) | same as request | `POST {MSG91_BASE_URL}/otp/retry` (optional; app usually re-calls send) |

Default `MSG91_BASE_URL`: `https://control.msg91.com/api/v5`  
Code: `backend-v2/src/modules/auth/providers/msg91-sms.provider.ts`

Secrets stay on the server only. Flutter never holds `MSG91_AUTH_KEY`.

## Critical: fix `DLT Template id not found`

If MSG91 logs show **Pending** + **DLT Template id not found** (your case for template `6ad73ea2ecf35246430c9744` / sender `APNSOC`):

1. Open your **DLT portal** → Content templates → copy the approved **Template ID** (long numeric ID).  
   - Do **not** use Entity/PE ID  
   - Do **not** use Template Reference ID  
   - Do **not** use the MSG91 hex template id as the DLT id
2. MSG91 dashboard → **OTP → Templates** → open the template whose ID is in `MSG91_TEMPLATE_ID`.
3. Paste that value into the template’s **DLT Template Id** field.
4. Ensure SMS body matches DLT content:
   - DLT variables: `{#var#}`
   - MSG91 OTP placeholder: `##OTP##`
5. Ensure sender **APNSOC** is approved on DLT and linked to that template.
6. Save; wait until the template is active / default.
7. Wait 15+ seconds, request OTP **once**, confirm log is Delivered (not discarded / not DLT error).

Code cannot invent a DLT Template ID — mapping is done in the MSG91 panel.

## 1. MSG91 account configuration

1. Create / sign in to an MSG91 account.
2. Complete KYC as required by MSG91 for India SMS.
3. Note the **Auth Key** from the MSG91 dashboard (API section).
4. Do **not** put Auth Key, template ID, or sender ID in Flutter, APKs, or client configs.

## 2. DLT registration (India)

1. Register your entity and headers on a DLT platform (operator-specific).
2. Register the **Sender ID** (header) you will use for OTP SMS.
3. Register the **OTP content template** (DLT `{#var#}` for the OTP digit).
4. Wait for DLT approval, then complete the **Critical** mapping section above.

## 3. Sender ID approval

1. Request / map the approved DLT sender ID in MSG91.
2. Set `MSG91_SENDER_ID` only after approval (often also bound on the OTP template).

## 4. Template approval

1. Create an **OTP template** in MSG91 (OTP section), not a generic transactional SMS flow alone.
2. Map **DLT Template Id** on that template (required for India delivery).
3. Copy the MSG91 **Template ID** into `MSG91_TEMPLATE_ID`.
4. Confirm OTP length (6) and expiry match backend: `SMS_OTP_LENGTH=6`, `SMS_OTP_EXPIRY_MINUTES=5`.

## 5. Backend environment

Copy from `.env.example` into the server `.env` / Docker env:

```env
SMS_PROVIDER=msg91
SMS_OTP_ENABLED=false
MSG91_AUTH_KEY=
MSG91_TEMPLATE_ID=
MSG91_SENDER_ID=
MSG91_BASE_URL=https://control.msg91.com/api/v5
SMS_OTP_EXPIRY_MINUTES=5
SMS_OTP_LENGTH=6
```

When ready for live SMS (after DLT + template + sender):

```env
SMS_OTP_ENABLED=true
MSG91_AUTH_KEY=<from MSG91 dashboard>
MSG91_TEMPLATE_ID=<approved OTP template id>
MSG91_SENDER_ID=<approved sender>
```

Keep `SMS_PROVIDER=msg91`. Never commit real keys.

## 6. Database migration

No separate migration script is required. Mongoose applies schema indexes on startup:

- `User.mobileE164` — sparse unique
- `User.mobileVerifiedAt`
- `OtpChallenge.mobileE164` (login challenges are mobile-keyed)

Existing users keep IDs, memberships, roles, flats, bills, payments, visitors, and audit records. Mobile fields start empty / unverified.

**Admin workflow (required for each existing user):**

1. `PUT /api/v1/admin/users/:userId/mobile` with `{ "mobile": "9876543210" }` (or Flutter Residents → Set mobile).
2. Verify ownership offline.
3. `POST /api/v1/admin/users/:userId/mobile/confirm` (or Confirm mobile ownership).
4. Only then can that number request SMS OTP login.

Numbers are **not** auto-verified on migration.

Optional admin CLI:

```bash
cd backend-v2
npx tsx scripts/create-admin.ts --email admin@example.com --name "Admin" --mobile 9876543210
```

## 7. Docker rebuild and restart

```bash
cd backend-v2
# ensure .env has SMS_* vars as above (SMS_OTP_ENABLED=false until ready)
docker compose build api
docker compose up -d
docker compose logs -f api
```

Or local process:

```bash
cd backend-v2
npm install
npm run build
npm run start
# or: npm run dev
```

## 8. Flutter APK rebuild

```bash
cd app
flutter pub get
flutter test
flutter build apk --release
# install the APK on a device that can reach the API host
```

Point `API_BASE_URL` / compile-time API config at the production API. No MSG91 secrets in Flutter.

## 9. Production SMS testing checklist

1. Confirm admin has a **verified** mobile on their user record.
2. Set `SMS_OTP_ENABLED=true` with real MSG91 values; restart API.
3. From the Flutter login screen, enter that mobile and request OTP.
4. Confirm SMS arrives from the approved sender.
5. Enter OTP; confirm JWT session and role home (ADMIN / OWNER / TENANT / GUARD).
6. Confirm incorrect OTP, resend cooldown, and rate limits behave as expected.
7. Confirm API responses and logs never include OTP plaintext or `MSG91_AUTH_KEY`.

**Real SMS delivery is not claimed until a live MSG91 OTP has been sent and verified successfully.**

## 10. Rollback / local development

- Set `SMS_OTP_ENABLED=false` (memory provider; no external SMS).
- Or `SMS_PROVIDER=memory` for explicit local OTP (still never log OTP values in production logs).
