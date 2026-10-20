# Performance, Redis & Load Testing (Phase 13)

## Redis architecture

- Client: `ioredis`
- Config: `REDIS_ENABLED`, `REDIS_URL`, `REDIS_PASSWORD`, `REDIS_KEY_PREFIX`
- Pattern: cache-aside for read-heavy society-scoped summaries
- Fail-open: if Redis is down/disabled, loaders hit MongoDB; authZ unchanged
- Keys: `society:{societyId}:{domain}:{…}` — no raw user strings as key roots
- Invalidation: **after** MongoDB transaction commit only

### Default TTLs (env-overridable)

| Domain | Env | Default |
| --- | --- | --- |
| Dashboard | `CACHE_TTL_DASHBOARD_SECONDS` | 45s |
| Reports / billing summary | `CACHE_TTL_REPORTS_SECONDS` | 45s |
| Wings | `CACHE_TTL_WINGS_SECONDS` | 300s |
| Facilities | `CACHE_TTL_FACILITIES_SECONDS` | 120s |
| Announcement feed meta | `CACHE_TTL_ANNOUNCEMENTS_SECONDS` | 45s |

### Never cached

Auth tokens, OTPs, passwords, payment settlement decisions, Razorpay webhook payloads, visitor OTP secrets, user-specific sensitive blobs without isolation.

### Metrics

Admin: `GET /api/v1/admin/ops/metrics` — HTTP counts/latency, cache hits/misses/errors/invalidations, Redis status, Mongo readyState/pool hint.

## Docker Redis

- Service `redis` on private `apna-internal` network (no host ports)
- AOF persistence volume `redis_data`
- `requirepass` via `REDIS_PASSWORD`
- `maxmemory` default 256mb, policy `allkeys-lru`
- Healthcheck via `redis-cli ping`

Production: keep Redis private, rotate password, set memory/eviction from observed working set, monitor evictions and hit ratio.

## Query optimizations

- Billing summary rewritten from in-memory bill scan → Mongo aggregation
- Resident announcements: projection + `societyId+status+publishedAt` index
- Reports/dashboard/wings/facilities: cache-aside wrappers

## Load testing (k6)

Profiles: `smoke`, `normal`, `stress`, `spike`, `soak` (see `load/k6/config.js`).

```bash
# Install k6 separately: https://k6.io/docs/get-started/installation/
npm run load:smoke          # PROFILE=smoke SCENARIO=health
npm run load:normal
npm run load:stress
npm run load:spike
npm run load:soak

# Authenticated staging (never production):
BASE_URL=http://127.0.0.1:4000 \
LOAD_TEST_ACCESS_TOKEN=... \
PROFILE=normal SCENARIO=admin-reads \
npm run load:k6
```

If k6 is missing, scripts fall back to `scripts/load-smoke.sh` (Node fetch against `/health` + `/ready`).

**Do not** run destructive or live-payment load against production. Payment scenario uses mock gateway only.

## Benchmark methodology

1. Seed isolated staging DB.
2. Capture baseline: `SCENARIO=health PROFILE=smoke` then `admin-reads` with token.
3. Record k6 `http_reqs`, `http_req_duration` p50/p95/p99, `http_req_failed`.
4. Note admin `/ops/metrics` cache hit ratio and Mongo explain stats.
5. Re-run after changes; compare only same profile/seed.

Claimed capacity must come from these reproducible runs — not estimates.
