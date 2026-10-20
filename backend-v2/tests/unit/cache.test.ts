import { afterEach, describe, expect, it } from 'vitest';
import { CacheKeys, CachePatterns, hashFilters, societyKey } from '../../src/cache/cache-keys';
import {
  getCacheMetrics,
  recordCacheHit,
  recordCacheInvalidation,
  recordCacheMiss,
  resetCacheMetrics,
} from '../../src/cache/cache-metrics';
import { cacheAside, cacheGet, cacheSet } from '../../src/cache/cache.service';
import { resetRedisClientForTests } from '../../src/cache/redis.client';
import { resetEnvCache, loadEnv } from '../../src/config/env';

const societyId = '507f1f77bcf86cd799439011';

describe('cache keys', () => {
  it('builds society-scoped keys', () => {
    expect(CacheKeys.dashboardOverview(societyId)).toBe(
      `society:${societyId}:dashboard:overview`,
    );
    expect(CacheKeys.financialReport(societyId, 'abcd')).toBe(
      `society:${societyId}:reports:financial:abcd`,
    );
    expect(CachePatterns.societyReports(societyId)).toBe(`society:${societyId}:reports:*`);
  });

  it('rejects unsafe key segments', () => {
    expect(() => societyKey(societyId, 'bad key')).toThrow();
    expect(() => societyKey('not-an-objectid', 'dashboard')).toThrow();
  });

  it('hashes filters stably', () => {
    expect(hashFilters({ a: 1, b: 'x' })).toBe(hashFilters({ a: 1, b: 'x' }));
    expect(hashFilters({ a: 1 })).not.toBe(hashFilters({ a: 2 }));
  });
});

describe('cache fail-open', () => {
  afterEach(() => {
    resetCacheMetrics();
    resetRedisClientForTests();
    process.env.REDIS_ENABLED = 'false';
    process.env.REDIS_URL = '';
    resetEnvCache();
    loadEnv();
  });

  it('falls through to loader when Redis disabled', async () => {
    process.env.REDIS_ENABLED = 'false';
    process.env.REDIS_URL = '';
    resetEnvCache();
    loadEnv();
    resetRedisClientForTests();

    let calls = 0;
    const value = await cacheAside('society:507f1f77bcf86cd799439011:dashboard:overview', 30, async () => {
      calls += 1;
      return { ok: true };
    });
    expect(value).toEqual({ ok: true });
    expect(calls).toBe(1);
    expect(await cacheGet('society:507f1f77bcf86cd799439011:dashboard:overview')).toBeNull();
    expect(await cacheSet('society:507f1f77bcf86cd799439011:dashboard:overview', { a: 1 }, 30)).toBe(
      false,
    );
  });

  it('records hit/miss/invalidation metrics', () => {
    resetCacheMetrics();
    recordCacheHit(1.5);
    recordCacheMiss(2);
    recordCacheInvalidation(3);
    const m = getCacheMetrics();
    expect(m.hits).toBe(1);
    expect(m.misses).toBe(1);
    expect(m.invalidations).toBe(3);
    expect(m.hitRatio).toBeCloseTo(0.5);
  });
});
