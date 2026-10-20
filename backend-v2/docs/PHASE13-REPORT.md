# Phase 13 — Verification Report

## What shipped

1. **Index audit** — documented in `docs/INDEXES.md`
2. **New indexes** — bill wing+period; payment gatewayOrderId (partial unique) + societyId+createdAt; announcement societyId+status+publishedAt; visitor wingId/entryAt; complaint societyId+createdAt
3. **Redundant indexes** — noted but **not dropped** (see INDEXES.md)
4. **Query optimization** — billing summary aggregation; announcement feed projection; lean lists unchanged elsewhere
5. **Redis** — `ioredis` cache-aside, society keys, fail-open, Docker private Redis + AOF + password + LRU
6. **TTL / invalidation** — post-commit for payments, bills, occupancy, facilities, announcements, complaints
7. **Load suite** — k6 profiles smoke/normal/stress/spike/soak under `load/k6/`
8. **Metrics** — `GET /api/v1/admin/ops/metrics`
9. **Docs** — README, INDEXES.md, PERFORMANCE.md

## Automated verification (this environment)

| Check | Result |
| --- | --- |
| Vitest | **141/141 passed** |
| Typecheck | **pass** |
| Lint | **pass** |
| Production build (`tsc`) | **pass** |
| Docker image build | **pass** (`apna-society-api-v2:phase13`) |
| k6 | **not installed** on this host |
| Load smoke against live API | **not run** — nothing listening on `:4000`; script exits 2 with “No benchmark numbers recorded” |
| Cache unit tests | **pass** (fail-open + key safety + metrics) |

## Benchmarks

No before/after latency or RPS numbers are claimed here. Reproduce on staging:

```bash
npm run dev   # or docker stack
npm run load:smoke
SCENARIO=admin-reads LOAD_TEST_ACCESS_TOKEN=... PROFILE=normal npm run load:k6
npm run indexes:verify
# Admin metrics after warm reads:
# GET /api/v1/admin/ops/metrics  → cache.hitRatio, http.slowestEndpoints
```

## Remaining limitations

- Resident announcement feeds are not document-cached (user-specific audience + ObjectId JSON safety).
- Outstanding report pages are not cached (pagination).
- Redis SCAN invalidation is best-effort under fail-open; short TTL bounds staleness.
- Concurrent write integrity still relies on MongoDB transactions/idempotency — Redis never replaces that.
- Capacity (e.g. “N concurrent users”) is **not** asserted without your own k6 runs on seeded staging.
