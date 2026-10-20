# Login SMS OTP (MSG91)

Scope: **login only** — SendOTP, Verify OTP, Resend. No WhatsApp / Email / Flow SMS for auth.

## Flow

```text
Flutter  →  POST /api/v1/auth/request-otp  →  MSG91 POST /api/v5/otp
Flutter  →  POST /api/v1/auth/verify-otp   →  MSG91 GET  /api/v5/otp/verify
```

Auth: header `authkey` = `MSG91_AUTH_KEY` (server-side only).

## Env

| Variable | Meaning |
| --- | --- |
| `SMS_OTP_ENABLED` | `true` = call MSG91; `false` = memory provider |
| `MSG91_AUTH_KEY` | Dashboard auth key |
| `MSG91_TEMPLATE_ID` | MSG91 OTP template id (hex), **not** the DLT numeric id |
| `MSG91_SENDER_ID` | e.g. `APNSOC` (must match DLT header) |
| `MSG91_BASE_URL` | default `https://control.msg91.com/api/v5` |

## India DLT

`MSG91_TEMPLATE_ID` must have an approved **DLT Template Id** filled in the MSG91 OTP template UI.  
If logs say `DLT Template id not found`, fix the panel mapping — see `app/docs/MSG91_MOBILE_OTP_DEPLOYMENT.md`.

## Implementation

- Provider: `src/modules/auth/providers/msg91-sms.provider.ts`
- Auth service: `src/modules/auth/services/auth.service.ts`
- Factory: `src/modules/auth/providers/sms-provider.factory.ts`
