# Username & password authentication migration

## What changed

- Primary login is `POST /api/v1/auth/login` with `{ username, password }`.
- Passwords are hashed with **bcrypt** (cost 12). Hashes are never returned in API responses.
- Users gain `username` (unique, sparse), `passwordHash` (select:false), `mustChangePassword`, lockout fields.
- Admin provision issues a one-time temporary password (or accepts an admin-chosen password).
- Admin reset: `POST /api/v1/admin/users/:userId/password`.
- Authenticated change: `POST /api/v1/auth/change-password` (revokes all refresh sessions).
- Legacy SMS OTP login routes remain for transitional rollback only. **Visitor entry OTP is unchanged.**

## Existing production users (safe procedure)

1. Deploy backend with the new schema (additive fields; no data deletion).
2. Dry-run username assignment:
   ```bash
   npm run migrate:password-auth -- --dry-run
   ```
3. Apply usernames:
   ```bash
   npm run migrate:password-auth
   ```
4. For each user (or in batches), admin issues a password via the app/API:
   `POST /api/v1/admin/users/:id/password`
5. Deliver username + temporary password out-of-band (never from application logs).
6. User signs in and is forced to change password.

Accounts without passwords remain active but cannot log in until credentials are issued. Nothing is auto-disabled.

## Admin bootstrap

```bash
npm run prepare:admin -- --email admin@example.com --username admin \
  --password 'YourSecurePass1' --name "Society Admin"
```

## Rollback

- Keep OTP routes temporarily; do not remove visitor OTP.
- Rollback deploy to previous backend build if needed (new fields are ignored by old code).
- Do **not** drop `username` / `passwordHash` indexes without a plan.

## Security notes

- Generic `INVALID_CREDENTIALS` responses (no username enumeration).
- Account lockout after 5 failed attempts (15 minutes).
- Auth rate limiter on login/refresh.
- Refresh token rotation + reuse detection preserved.
- Passwords never logged.
