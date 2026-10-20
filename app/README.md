# ApnaSociety — Local-first Flutter demo

**ApnaSociety** · Society: **Monarch Solitaire A to E** · *Simplifying Society Management.*

A single Flutter app (Android & iOS) with Admin, Flat Owner, Flat Tenant, and Security Guard experiences. All society data stays on the device (SQLite via Drift). No backend is required for demo flows.

## Society inventory

- Wings **A–E**, 7 floors × 4 flats = **140** flats
- Monthly maintenance total **₹5,88,000** (wing-specific rates)
- Occupancy: **Owner Occupied** or **Tenant Occupied** (admin-managed)

## Demo access (OTP `123456` — simulated, no SMS)

| Role | Mobile | Notes |
|------|--------|--------|
| Owner (A-101, rented) | `9876510032` | Financial access only |
| Tenant (A-101) | `9876510101` | Residential access only |
| Owner (A-102, self) | `9876510033` | Full owner access |
| Admin | `9876500001` | Society admin |
| Security Guard | `9876500099` | Gate / visitors |

## Implemented flows

- Occupancy-based owner / tenant permissions
- Admin flats, bills, cash/cheque collection, reports
- Prepaid maintenance bills, other charges, late interest
- Oldest-first outstanding settlement + receipts (PDF)
- Guard visitor requests → owner/tenant approval
- Owner/tenant OTP invitations, entry/exit
- Voice visitor registration (Hinglish speech)
- Vehicle registration and gate verification

## Run locally

From this folder (`app/`):

```bash
flutter pub get
flutter run
```

Drift codegen (when schema annotations change):

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Build Android APK

```bash
flutter build apk --debug
# or, with signing configured:
flutter build apk --release
```

## Demo limitations

- OTP and payments are simulated locally.
- Data does not sync across devices.
- Demo credentials are intentional for presentation — not production authentication.
- Do not use this build to collect real maintenance payments without production security and signing.

## Production work still required

Secure OTP, real payment gateway verification, cross-device sync, backups, store release signing (`applicationId` / keystore), and privacy review.
