import { getLogger } from '../utils/logger';
import {
  recordCacheError,
  recordCacheHit,
  recordCacheInvalidation,
  recordCacheMiss,
  recordCacheSet,
} from './cache-metrics';
import { getRedisClient, isRedisConfigured } from './redis.client';

const logger = () => getLogger();

function prefixedScanMatch(pattern: string, keyPrefix: string): string {
  // ioredis keyPrefix is applied to commands but SCAN MATCH is against the real keyspace.
  return `${keyPrefix}${pattern}`;
}

export async function cacheGet<T>(key: string): Promise<T | null> {
  if (!isRedisConfigured()) {
    recordCacheMiss(0);
    return null;
  }

  const start = performance.now();
  try {
    const redis = await getRedisClient();
    if (!redis) {
      recordCacheMiss(performance.now() - start);
      return null;
    }
    const raw = await redis.get(key);
    const latency = performance.now() - start;
    if (raw == null) {
      recordCacheMiss(latency);
      return null;
    }
    recordCacheHit(latency);
    return JSON.parse(raw) as T;
  } catch (error) {
    recordCacheError();
    recordCacheMiss(performance.now() - start);
    logger().warn(
      { err: error instanceof Error ? error.message : 'unknown', key },
      'cacheGet failed',
    );
    return null;
  }
}

export async function cacheSet(key: string, value: unknown, ttlSeconds: number): Promise<boolean> {
  if (!isRedisConfigured() || ttlSeconds <= 0) {
    return false;
  }

  const start = performance.now();
  try {
    const redis = await getRedisClient();
    if (!redis) return false;
    await redis.set(key, JSON.stringify(value), 'EX', ttlSeconds);
    recordCacheSet(performance.now() - start);
    return true;
  } catch (error) {
    recordCacheError();
    logger().warn(
      { err: error instanceof Error ? error.message : 'unknown', key },
      'cacheSet failed',
    );
    return false;
  }
}

export async function cacheDelete(...keys: string[]): Promise<number> {
  if (!keys.length || !isRedisConfigured()) return 0;
  try {
    const redis = await getRedisClient();
    if (!redis) return 0;
    const deleted = await redis.del(...keys);
    if (deleted > 0) recordCacheInvalidation(deleted);
    return deleted;
  } catch (error) {
    recordCacheError();
    logger().warn(
      { err: error instanceof Error ? error.message : 'unknown' },
      'cacheDelete failed',
    );
    return 0;
  }
}

/**
 * SCAN + DEL by pattern. Pattern must be society-scoped (see CachePatterns).
 * Never pass unsanitized user input.
 */
export async function cacheDeleteByPattern(pattern: string): Promise<number> {
  if (!isRedisConfigured()) return 0;

  try {
    const redis = await getRedisClient();
    if (!redis) return 0;

    const envPrefix = redis.options.keyPrefix ?? '';
    const match = prefixedScanMatch(pattern, envPrefix);
    let cursor = '0';
    let deleted = 0;

    do {
      const [next, keys] = await redis.scan(cursor, 'MATCH', match, 'COUNT', 100);
      cursor = next;
      if (keys.length) {
        // Keys from SCAN include the keyPrefix; DEL via ioredis would double-prefix.
        // Use the underlying connection with unprefixed keys.
        const bare = keys.map((k) => (envPrefix && k.startsWith(envPrefix) ? k.slice(envPrefix.length) : k));
        const n = await redis.del(...bare);
        deleted += n;
      }
    } while (cursor !== '0');

    if (deleted > 0) recordCacheInvalidation(deleted);
    return deleted;
  } catch (error) {
    recordCacheError();
    logger().warn(
      { err: error instanceof Error ? error.message : 'unknown', pattern },
      'cacheDeleteByPattern failed',
    );
    return 0;
  }
}

/**
 * Cache-aside helper: return cached value or load from DB and store.
 * On Redis failure, always falls through to `loader` (authorization stays in loader callers).
 */
export async function cacheAside<T>(
  key: string,
  ttlSeconds: number,
  loader: () => Promise<T>,
): Promise<T> {
  const cached = await cacheGet<T>(key);
  if (cached !== null) {
    return cached;
  }
  const value = await loader();
  await cacheSet(key, value, ttlSeconds);
  return value;
}
