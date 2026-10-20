# Flutter Phase 12 — Full Integration Audit (Read-Only)

**Date:** 2026-10-20  
**Scope:** Flutter app (`app/`) vs `backend-v2`  
**Mode:** Audit only — no application code changes  
**Automated checks:** `flutter test` (221 passed), `flutter analyze` (0 errors; 3 warnings; 114 infos), `flutter pub deps`  
**Backend live suite:** Not executed — nothing listening on `:4000` (`/api/v1/health` unreachable)

---

## 1. Executive summary

Phases 1–11 delivered a largely API-backed Flutter client. Core request contracts for auth, society, billing, visitors, vehicles, complaints, staff, facilities, announcements, notifications, and reports **match** backend-v2 routes and validators. Role home routing follows `/me` (not the login dropdown). Tenant financial denial is enforced in Flutter UI and backend. Razorpay settlement is server-verified.

**No P0 (critical security / payment integrity / cross-role data exposure) defects were confirmed.**

Confirmed issues cluster around:

1. **Session integrity** (AuthGate clearing tokens on non-auth restore failures; OTP verify leaving tokens after failed context load; logout vs in-flight refresh race).
2. **Incorrect display of society maintenance rate totals** on the live Reports dashboard (`moneyPaise` on rupee integers → 100× under-display).
3. **Active Admin UI still opening SQLite demo** for Security Staff (and demo late-interest settings).
4. **Cache / Socket.IO** gaps after occupancy assign, token refresh, and `clearLocal`.

**Overall integration status:** Suitable for **controlled end-to-end device testing** after awareness of the P1 items below. **Not** ready for production release until P1 session and reports-display issues are fixed and active SQLite admin paths are retired or replaced.

---

## 2. Overall integration status

| Area | Status |
|------|--------|
| Live API modules (billing, visitors, vehicles, complaints, staff, facilities, announcements, notifications, reports, society/flats/occupancy, residents) | **API-backed** |
| Flutter ↔ backend request contracts | **Aligned** (no confirmed path/method/field mismatches) |
| Role shells (Admin / Owner-Tenant / Guard) | **Correct routing**; enforcement primarily backend |
| SQLite / demo | **Still bootstrapped**; some Admin More paths **still active** |
| Automated Flutter tests | **221 passed** |
| Real device / backend E2E | **Not run** (audit only) |

---

## 3. Authentication audit

### Strengths

- Email OTP request/verify via `AuthApi`; access token memory-only; refresh in `FlutterSecureTokenStore`.
- Concurrent refresh coalesced (`_refreshInFlight`); single 401 retry (`ApiClient`).
- Traffic logging is method/path/status; secret keys redacted (`api/http/redact.dart`). No Flutter `print` of tokens found.
- Login dropdown is UX-only; actual role from `resolveAppRole(profile)` / `HomeResolver`.
- `performLogout` disconnects Socket.IO, clears live repos, calls logout API, clears legacy `SessionStore`.

### Confirmed findings

See **F-AUTH-01 … F-AUTH-03** in §14.

### Notes (not defects)

- Refresh-token rotation on success is implemented and covered by unit tests.
- Terminal refresh failures clear local session; transient failures rethrow from `restore()` (but AuthGate then clears — see F-AUTH-01).

---

## 4. Role-based access matrix

| Capability | ADMIN | OWNER | TENANT | GUARD |
|------------|-------|-------|--------|-------|
| Society / wings / flats | Yes (live) | — | — | — |
| Resident provisioning / occupancy | Yes (live) | — | — | — |
| Billing / payments / receipts | Yes (live) | If `canFinance` | No (`canFinance` false) | No |
| Visitors | Yes (live admin) | Residential if assigned | Residential if assigned | Gate live |
| Vehicles / parking | Yes (live) | Yes | Yes | Gate logs live |
| Complaints | Yes (live) | Yes | Yes | No |
| Staff / attendance / shifts | Yes (live) | — | — | — |
| Facilities / bookings | Yes (live) | Yes | Yes | — |
| Announcements | Yes (live admin) | Resident feed | Resident feed | — |
| Notifications | — | Yes | Yes | — |
| Reports & analytics | Yes (live) | No nav | No nav | No nav |
| Security staff CRUD | **SQLite demo UI** | — | — | — |

**Home resolution:** `ADMIN → AdminHome`, `OWNER|TENANT → OwnerHome`, `GUARD → GuardHome` (`home_resolver.dart`). Multi-role priority: ADMIN > OWNER > TENANT > GUARD (`app_role.dart`) — secondary roles unreachable in-app (product limitation, P3).

**Flutter-side role assumption risk:** Shell widgets do not re-assert `appRole` before rendering; unauthorized APIs return 403. No confirmed privilege escalation via navigation alone.

---

## 5. API contract findings

**Confirmed path / method / body / query / multipart / header mismatches: none.**

| Module | Flutter | Backend |
|--------|---------|---------|
| Auth | `auth_api.dart` | `auth.routes.ts` |
| Society / flats / occupancy | `society_api.dart` | `society` admin + society routes |
| Admin users / residents | `admin_user_api.dart`, `resident_api.dart` | users + resident routes |
| Billing | `billing_api.dart` | admin + resident billing routes |
| Visitors | `visitor_api.dart` | admin / resident / guard visitor routes |
| Vehicles | `vehicle_api.dart` | admin / resident / guard vehicle routes |
| Complaints | `complaint_api.dart` | admin + resident complaint routes |
| Staff | `staff_api.dart` | admin staff routes |
| Facilities | `facility_api.dart` | admin + resident facility routes |
| Announcements | `announcement_api.dart` | admin + resident announcement routes |
| Notifications | `notification_api.dart` | resident notification routes |
| Reports | `report_api.dart` | admin report routes |

- Society header: Flutter `x-society-id` ↔ backend society middleware.
- Multipart field: `file` ↔ `.single('file')` on complaints and announcements.
- Backend-only routes Flutter never calls (e.g. `POST /admin/wings`, `/admin/guards`, ops metrics) are **coverage gaps**, not contract bugs.

---

## 6. Feature-by-feature results

### 6.1 Authentication

- **Routes:** OTP request/verify, refresh, logout, `/me`.
- **API-backed:** Yes.
- **SQLite:** Legacy `SessionStore` cleared on AuthGate; residual reads in unused/demo paths.
- **Loading/error:** Login shows errors; AuthGate shows startup error UI.
- **Cache:** `clearLiveRepositories` on logout / `clearLocal`.
- **Missing:** Mobile push not implemented (by design).
- **Bugs:** F-AUTH-01, F-AUTH-02, F-AUTH-03.

### 6.2 Society, wings, flats

- **Routes:** Society config, dashboard, wings, flats list/detail, occupancy assign/end.
- **API-backed:** Admin flats and dashboard live.
- **SQLite:** DB still initialized at bootstrap (`_initializeLocalDatabase`); flat editor demo not on live nav.
- **Bugs:** None confirmed on contracts.

### 6.3 Resident management and occupancy

- **Routes:** Admin user create/list; assign owner/tenant; end occupancy.
- **API-backed:** Yes (`admin_residents_module`, flat occupancy UI).
- **Cache:** End occupancy uses full `invalidateAfterResidentMutation`; **assign** only partial clear — **F-OCC-01**.
- **Bugs:** F-OCC-01; multi-flat UX gap F-OCC-02.

### 6.4 Billing, payments, receipts

- **Routes:** Admin/resident bills, generate, offline pay, Razorpay create/verify, receipts/PDF bytes.
- **API-backed:** Active tabs use `LiveAdmin*` / `LiveOwner*`.
- **SQLite:** Dead `AdminBillsPage` / `OwnerBillsPage` / `CollectPaymentPage` remain in tree but not on live IndexedStack.
- **Stale copy:** Admin dashboard InfoNote still claims bills/payments are demo — **F-UX-01**.
- **Financial:** Paise integers; interest from server; verify before treating payment settled — see §7.
- **Bugs:** F-PAY-01 (empty Razorpay success payload).

### 6.5 Visitors and security

- **Routes:** Admin / resident / guard visitor APIs + Socket.IO events.
- **API-backed:** Live guard/resident/admin visitor pages.
- **SQLite still reachable:** Admin → Security Staff → `AdminSecurityStaffPage` / `db.securityGuards()` — **F-DEMO-01**.
- **Bugs:** F-DEMO-01; socket JWT staleness F-SOCK-01.

### 6.6 Vehicles and parking

- **API-backed:** Live admin/resident/guard vehicle modules.
- **SQLite:** Legacy `vehicle_module.dart` not on live guard/admin nav.
- **Bugs:** None confirmed.

### 6.7 Maintenance and complaints

- **API-backed:** Live admin/resident complaints + attachments.
- **Socket:** Complaint events registered and invalidate caches.
- **Bugs:** Attachment MIME default P3 (F-FILE-01).

### 6.8 Staff, attendance, shifts

- **API-backed:** Live admin staff/attendance/shifts.
- **Socket:** Backend `staff:shift_assigned` not listened — **F-SOCK-02**.
- **Bugs:** F-SOCK-02.

### 6.9 Facilities and bookings

- **API-backed:** Live admin + resident facility modules.
- **Socket:** Facility booking events registered.
- **Bugs:** Resident create uses `primaryResidentFlat` only (F-OCC-02 related).

### 6.10 Announcements and notifications

- **API-backed:** Live admin/resident announcements; resident notifications; Socket.IO invalidation.
- **Deep links:** In-app notification detail navigates by type for resident announcement/visitor/complaint/facility; BILL/STAFF/SYSTEM show toast only.
- **Bugs:** PDF attach not reachable via ImagePicker-only UI (F-FILE-02).

### 6.11 Reports and analytics

- **API-backed:** `LiveAdminReportsPage` + `ReportApi` / repository; CSV via `getBytes` + `share_plus`.
- **Money display bug:** Society inventory “Monthly maintenance (rate sum)” uses `moneyPaise` on rupee totals — **F-RPT-01**.
- **Payments report:** CSV export only (matches backend; no JSON payments report screen).

---

## 7. Financial integrity findings

| Check | Result |
|-------|--------|
| Integer paise for bills/payments/reports | Yes (`requireInt`, `moneyPaise`) |
| Flutter recalculating interest totals | No for live bill UI (server fields) |
| Razorpay success before verify | Settlement only after `verifyPayment` |
| Tenant finance | Tabs gated by `canFinance`; API `TENANT_BILLING_DENIED` |
| Offline payment amount | `int.tryParse` paise path |
| CSV | Server bytes; type allowlist; no Flutter regeneration |

**Confirmed issues:** F-RPT-01 (wrong formatter on society rate sum), F-PAY-01 (empty paymentId/signature still treated as checkout success → verify call fails server-side).

**Not confirmed:** Silent mark-as-paid without backend verification.

---

## 8. Occupancy and data isolation findings

| Check | Result |
|-------|--------|
| Multi-flat from `/resident/flats` | Loaded; primary used for create flows |
| Flat switcher UI | Missing — F-OCC-02 |
| Owner finance during tenant occupancy | Backend flags + Flutter tabs aligned |
| Logout cleanup | `performLogout` clears repos + tokens + socket |
| Assign occupancy invalidation | Incomplete — F-OCC-01 |
| `clearLocal` without socket disconnect | F-SOCK-01 / related |

---

## 9. Socket.IO findings

| Topic | Evidence |
|-------|----------|
| Auth handshake | `setAuth({'token': accessToken})` at connect |
| Join rooms | `join:guards` / `join:resident` by role |
| Visitor/complaint/facility/announcement/notification events | Registered; cache invalidation on payload |
| Token refresh | Socket **not** reconnected with new JWT — F-SOCK-01 |
| `clearLocal` | Does **not** call `disconnectVisitorSocket` (only `performLogout`) |
| `staff:shift_assigned` | Not registered — F-SOCK-02 |
| Mobile push | **Not implemented** |

---

## 10. Attachment and file handling findings

| Asset | Behavior |
|-------|----------|
| Complaint / announcement upload | Multipart `file`; size/type errors from API |
| Authenticated download | `getBytes` paths |
| Receipt PDF | Server bytes + share |
| Report CSV | Server bytes + share; empty bytes rejected in UI |
| MIME guess on attach | Defaults to `image/jpeg` if picker omits MIME — F-FILE-01 |
| Announcement PDF | Allowed by constants; UI is ImagePicker-only — F-FILE-02 |
| Platform permissions | Rely on image_picker / share_plus / secure storage plugins; no separate custom permission audit performed on device |

---

## 11. Navigation and stability findings

- Admin IndexedStack: Dashboard, Flats, Bills (live), Payments (live), More (live modules + SQLite Security Staff + Settings).
- Owner/Tenant: finance tabs conditional; residential tabs conditional.
- Guard: Live gate flows only.
- Session expiry mid-screen: 401 → one refresh → clear on terminal failure; open screens rely on next API call / LoadFailure.
- Dead routes: SQLite bill/payment/report pages exist but are not on live nav.
- Stale InfoNotes misdescribe billing as demo — F-UX-01.

---

## 12. Code quality and dependency findings

| Item | Notes |
|------|-------|
| Duplicate live clients | Single `ApnaApi` + `LiveRepositories` process-wide |
| Legacy demo screens | Present; mostly unreachable; **Security Staff + Settings late interest still reachable** |
| SQLite/Drift | Still dependency + bootstrap seed |
| Secrets in repo | No API secrets in Flutter; `kDemoOtp = '123456'` shown in demo Security Staff copy |
| Config | `API_BASE_URL` / flavor via `ApiConfig` |
| Analyze | 0 errors; 3 warnings (incl. unused field in generated drift, unused test local, unused element param); 114 infos (mostly curly braces / deprecated Dropdown `value`) |
| Deps (key) | dio 5.11.1, flutter_secure_storage 9.2.4, razorpay_flutter 1.4.7, share_plus 12.0.2, socket_io_client 3.1.6, drift 2.31.0, image_picker 1.2.4 |

---

## 13. Automated test results

| Check | Result |
|-------|--------|
| `flutter test` | **221 passed** |
| `flutter analyze` | **0 errors**; 3 warnings; 114 infos (exit non-zero due to warnings/infos under project lint config) |
| `flutter pub deps` | Resolved successfully (see §12) |
| Backend Vitest / live API integration | **Not run** — API not reachable on `127.0.0.1:4000` |
| Real device workflow | **Not tested** (audit only) |

---

## 14. P0 / P1 / P2 / P3 findings

### P0 — Critical

*None confirmed.*

---

### P1 — High

#### F-AUTH-01 — AuthGate clears session on non-auth restore failures

- **Module:** Authentication  
- **Where:** `app/lib/main.dart` ~197–212 (`AuthGate._resolveHome`)  
- **Evidence:** `catch` always `await session.clearLocal()` then rethrows. `AuthSession.restore()` already clears only on terminal refresh failures; network errors after a successful refresh rotation, or `StateError` (“no flat access”), also wipe storage.  
- **Expected:** Clear local credentials only on terminal auth failure; show recoverable error otherwise.  
- **Actual:** Transient / context failures destroy refresh token (and may leave server rotation already consumed).  
- **Fix:** Narrow catch; distinguish `ApiException` terminal codes vs network / `StateError`.

#### F-AUTH-02 — verifyOtp persists tokens before context load; login UI does not rollback

- **Module:** Authentication  
- **Where:** `app/lib/api/auth/auth_session.dart` ~79–88; `app/lib/main.dart` ~335–374  
- **Evidence:** `_applyTokens` runs before `loadProfileAndContext()`. On failure, login only sets `error` — no `clearLocal()`.  
- **Expected:** Failed post-OTP context load leaves no usable session.  
- **Actual:** Half-authenticated state (memory access token + stored refresh).  
- **Fix:** `clearLocal()` (or transactional apply) when context load fails after verify.

#### F-AUTH-03 — Logout vs in-flight refresh can re-seed secure storage

- **Module:** Authentication  
- **Where:** `app/lib/api/auth/auth_session.dart` ~136–171, 193–206  
- **Evidence:** `_refreshLocked` is only held during `clearLocal()`. An in-flight `_performRefresh` past the lock check can still `_applyTokens` after logout cleared storage.  
- **Expected:** Logout wins; no token write after clear.  
- **Actual:** Possible ghost session on next launch.  
- **Fix:** Keep refresh locked until logout completes; discard refresh results if cleared mid-flight.

#### F-RPT-01 — Reports dashboard formats society rate-sum with moneyPaise (100× under-display)

- **Module:** Reports  
- **Where:** `app/lib/features/reports/live_reports_module.dart` ~338–341  
- **Evidence:** Backend `maintenanceRate` / `monthlyMaintenanceTotal` are **rupee** integers (`admin-dashboard.service.ts` `$sum: '$maintenanceRate'`). Admin home uses `money(...)`. Reports use `moneyPaise(soc.monthlyMaintenanceTotal)`.  
- **Expected:** Same display as admin dashboard for rate totals.  
- **Actual:** e.g. 4000 rupees shown as ₹40.00.  
- **Fix:** Use `money(...)` for society inventory rate sum; keep `moneyPaise` for `*Paise` report fields.

#### F-DEMO-01 — Live Admin Security Staff still mutates SQLite demo guards

- **Module:** Visitors / Security  
- **Where:** `app/lib/main.dart` ~1270–1271, ~1580–1585; `app/lib/features/security/security_module.dart` ~2192–2206  
- **Evidence:** More → Security Staff → `AdminSecurityStaffPage` → `db.securityGuards()`; shows demo OTP copy. Live guard login is backend-only.  
- **Expected:** Admin security staff management against `/admin/guards` (or hide until live).  
- **Actual:** On-device SQLite CRUD presented as admin security management.  
- **Fix:** Replace with live API or remove from Admin More until ready.

---

### P2 — Medium

#### F-PAY-01 — Razorpay empty paymentId/signature treated as checkout success

- **Module:** Billing  
- **Where:** `app/lib/features/billing/razorpay_checkout.dart` ~71–76, ~35–39; verify at `live_billing_module.dart` ~1105–1109  
- **Evidence:** Nulls replaced with `''`; `isSuccess` does not require non-empty ids. UI still calls `verifyPayment`.  
- **Expected:** Require non-empty order/payment/signature before verify.  
- **Actual:** Broken success path → failed verify / confusing UX (settlement still server-side).  
- **Fix:** Validate non-empty credentials; surface payment failure otherwise.

#### F-OCC-01 — Occupancy assign skips full live cache invalidation

- **Module:** Occupancy  
- **Where:** `app/lib/main.dart` ~1943–1945 vs ~1991  
- **Evidence:** Assign clears users/resident only; end occupancy calls `invalidateAfterResidentMutation`.  
- **Expected:** Assign invalidates visitors/facilities/announcements/notifications similarly.  
- **Actual:** Stale residential caches possible after assign.  
- **Fix:** Call `invalidateAfterResidentMutation(flatId: …)` after assign.

#### F-SOCK-01 — Socket JWT not rotated; clearLocal does not disconnect

- **Module:** Socket.IO  
- **Where:** `visitor_socket.dart` ~53–91; `auth_session.dart` `refreshSession` / `clearLocal`; disconnect only in `performLogout`  
- **Evidence:** Auth token fixed at connect; HTTP refresh does not reconnect socket; failed restore/`clearLocal` can leave socket up.  
- **Expected:** Reconnect on token refresh; disconnect on any full session wipe.  
- **Actual:** Live events may stop after access expiry; orphan socket after some clears.  
- **Fix:** `connectForSession` after refresh; `disconnectVisitorSocket` inside `clearLocal`.

#### F-DEMO-02 — Admin Settings still writes demo late-interest to SQLite

- **Module:** Settings / Billing  
- **Where:** `app/lib/main.dart` ~4243–4254, ~4371–4374  
- **Evidence:** “Local demo billing settings” / `db.setLateInterestAnnualRate`. Live bills state interest is server-only.  
- **Expected:** Society interest config via API or remove demo editor from live settings.  
- **Actual:** Demo rate editor still presented in live Admin Settings.  
- **Fix:** Remove or gate behind explicit demo flag; wire API when available.

#### F-OCC-02 — No multi-flat selector; create flows bind primary flat only

- **Module:** Occupancy / Complaints / Facilities / Vehicles  
- **Where:** `auth_session.primaryResidentFlat`; complaints/facilities/vehicles init  
- **Evidence:** Dashboard acknowledges multi-flat without switcher; create uses primary only.  
- **Expected:** User can choose flat when multiple assigned.  
- **Actual:** Actions may target wrong flat for multi-flat owners/tenants.  
- **Fix:** Flat picker shared across residential create flows.

---

### P3 — Low

#### F-SOCK-02 — `staff:shift_assigned` not registered

- **Where:** `visitor_socket.dart` listeners vs backend staff events  
- **Impact:** Staff shift live invalidation missing; REST refresh still works.

#### F-FILE-01 — Attachment MIME defaults to `image/jpeg`

- **Where:** complaint/announcement attach when picker omits MIME  
- **Impact:** Possible incorrect Content-Type on some devices.

#### F-FILE-02 — Announcement PDF attach not reachable

- **Where:** ImagePicker-only UI vs PDF in allowed MIME constants  
- **Impact:** Incomplete attach UX for PDF announcements.

#### F-UX-01 — Stale Admin dashboard copy claims bills/payments are demo

- **Where:** `main.dart` ~1604–1605  
- **Impact:** Misleading; tabs already live.

#### F-ROLE-01 — Multi-role accounts only get highest-priority shell

- **Where:** `app_role.dart` priority  
- **Impact:** OWNER+GUARD cannot reach guard desk without separate account — by design today.

#### F-LEGACY-01 — Large SQLite demo surface remains in tree / bootstrap

- **Where:** `LocalDatabase` init; unused `AdminBillsPage`, `OwnerBillsPage`, etc.  
- **Impact:** Dead code risk if re-linked; not on live nav except F-DEMO-01/02.

---

## 15. Recommended correction order

1. **F-RPT-01** — Correct `money` vs `moneyPaise` on society rate sum (display integrity).  
2. **F-AUTH-01 / F-AUTH-02 / F-AUTH-03** — Session integrity (restore wipe, OTP rollback, logout/refresh race).  
3. **F-DEMO-01 / F-DEMO-02** — Remove or replace active SQLite Admin Security Staff + demo interest settings.  
4. **F-SOCK-01** — Socket reconnect on refresh + disconnect on `clearLocal`.  
5. **F-OCC-01** — Full cache invalidation on occupancy assign.  
6. **F-PAY-01** — Guard empty Razorpay success payloads.  
7. **F-OCC-02** — Multi-flat selector for residential creates.  
8. P3 items (staff socket, MIME, PDF attach, copy, legacy cleanup) as capacity allows.

---

## 16. Manual device tests still required

- [ ] Fresh OTP login for ADMIN / OWNER / TENANT / GUARD on real devices  
- [ ] Kill app and restore session (online + offline airplane mode)  
- [ ] Force-expire access token; confirm single refresh and continued use  
- [ ] Logout during background refresh; confirm next launch stays logged out  
- [ ] Tenant: no bills/payments tabs; API 403 if forced  
- [ ] Owner of tenant-occupied flat: finance yes / residential no  
- [ ] Admin offline payment + Razorpay happy path + cancel/fail  
- [ ] Guard entry/exit + vehicle log; confirm no admin menus  
- [ ] Reports: verify monthly maintenance rate sum matches admin dashboard  
- [ ] CSV export share on Android and iOS  
- [ ] Complaint/announcement image attach + download  
- [ ] Notification tap → linked screens  
- [ ] Occupancy assign/end then refresh visitor/announcement lists  
- [ ] Multi-flat owner create complaint on non-primary flat (expect gap until F-OCC-02)  
- [ ] Confirm Security Staff SQLite page behavior vs backend guards (known demo)

---

## 17. Ready for end-to-end device testing?

**Yes — with caveats.**

The app is appropriate for **structured E2E device testing** against a running `backend-v2` instance. Live modules and API contracts are sufficiently aligned; automated Flutter tests pass.

**Not production-ready** until at least P1 items (session integrity, reports rupee display, active SQLite Security Staff path) are corrected and re-audited.

---

*End of Phase 12 audit. No application fixes were applied. Awaiting review approval before any remediation phase.*
