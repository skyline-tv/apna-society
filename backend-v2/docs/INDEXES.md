# MongoDB Index Audit (Phase 13)

Audit date: implementation of Phase 13. Indexes are defined in Mongoose schemas and applied via `syncIndexes()` in tests / app boot migrations.

## Principles

- Prefer compound indexes matching real filter + sort patterns.
- Preserve all unique and partial-unique constraints.
- Do not drop existing indexes automatically.
- Society isolation: nearly all tenant queries lead with `societyId`.

## Collections

| Collection | Key indexes | Notes |
| --- | --- | --- |
| users | email unique; phone+isActive; roles+isActive; text name/email/phone | Auth lookups |
| societies | isActive+name | Admin listing |
| wings | societyId+code unique; societyId+sortOrder; societyId+isActive+sortOrder | Wing list |
| flats | societyId+number unique; societyId+wingId+floor+position unique; occupancy/type compounds | Dashboard aggs |
| occupancyrecords | partial unique active owner/tenant; societyId+flatId+status+role | Lifecycle |
| memberships | partial unique active role; societyId+role+isActive | AuthZ |
| bills | societyId+billNumber unique; partial unique period per flat; status/dueDate; **societyId+wingCodeSnapshot+billingPeriodStart** (new) | Reports + summary |
| payments | societyId+paymentNumber unique; partial unique gatewayPaymentId / idempotencyKey; **gatewayOrderId partial unique** (new); **societyId+createdAt** (new) | Settlement + lists |
| receipts | societyId+receiptNumber unique; owner/flat + generatedAt | History |
| principalledgers | societyId+billId+effectiveAt; idempotency partial unique | Ledger integrity |
| visitorlogs | approval/entry compounds; **societyId+wingId+createdAt** (new); **societyId+entryAt** (new) | History |
| vehicles / parkingslots / parkingallocations / vehiclelogs | plate unique partial; slot unique; allocation partial unique | Parking |
| complaints | societyId+complaintNumber unique; status/category compounds; **societyId+createdAt** (new) | Analytics |
| complainthistories | complaintId+createdAt | Timeline |
| staff / staffattendances / staffshifts | employeeCode unique; attendance unique per day | HR |
| facilities / facilitybookings | societyId+name unique; booking overlap helpers | Booking |
| announcements | status/scheduled; **societyId+status+publishedAt** (new) | Feeds |
| announcementreads | announcementId+userId unique | Read state |
| notifications | idempotencyKey unique; recipient+isRead | Inbox |
| refreshesessions / otpchallenges | TTL expiresAt | Auth |

## Redundant / overlapping (not dropped)

- `bills.societyId+billingPeriodStart` overlaps partially with wing+period compound; kept for period-only filters.
- `complaints.societyId+status+createdAt` vs `societyId+createdAt`: both useful; status filter uses the former.
- `payments.societyId+status+paidAt` vs `societyId+createdAt`: different sort fields.

## Query verification

```bash
npm run indexes:verify
```

Uses `explain("executionStats")` on representative filters. Interpret `docsExamined` vs `docsReturned` and `COLLSCAN` flags. Empty local DBs may show low doc counts; re-run after seeding staging data.
