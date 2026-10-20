import Redis from 'ioredis';
import { getEnv } from '../config/env';
import { getLogger } from '../utils/logger';

let client: Redis | null = null;
let connectAttempted = false;
let lastErrorAt = 0;

export function isRedisConfigured(): boolean {
  const env = getEnv();
  return Boolean(env.REDIS_ENABLED && env.REDIS_URL);
}

export function getRedisStatus(): {
  configured: boolean;
  connected: boolean;
  status: string;
} {
  return {
    configured: isRedisConfigured(),
    connected: Boolean(client && client.status === 'ready'),
    status: client?.status ?? (isRedisConfigured() ? 'disconnected' : 'disabled'),
  };
}

export async function getRedisClient(): Promise<Redis | null> {
  if (!isRedisConfigured()) {
    return null;
  }

  if (client && (client.status === 'ready' || client.status === 'connecting')) {
    return client;
  }

  if (connectAttempted && client) {
    return client.status === 'ready' ? client : null;
  }

  connectAttempted = true;
  const env = getEnv();
  const logger = getLogger();

  try {
    const redis = new Redis(env.REDIS_URL, {
      password: env.REDIS_PASSWORD || undefined,
      keyPrefix: env.REDIS_KEY_PREFIX,
      maxRetriesPerRequest: 1,
      enableReadyCheck: true,
      lazyConnect: true,
      connectTimeout: 3_000,
      retryStrategy(times) {
        if (times > 3) return null;
        return Math.min(times * 200, 1_000);
      },
    });

    redis.on('error', (err) => {
      const now = Date.now();
      if (now - lastErrorAt > 30_000) {
        lastErrorAt = now;
        logger.warn({ err: err.message }, 'Redis client error (cache fail-open)');
      }
    });

    redis.on('connect', () => {
      logger.info('Redis connected');
    });

    await redis.connect();
    client = redis;
    return client;
  } catch (error) {
    const message = error instanceof Error ? error.message : 'unknown';
    logger.warn({ err: message }, 'Redis unavailable; continuing without cache');
    client = null;
    return null;
  }
}

export async function disconnectRedis(): Promise<void> {
  if (client) {
    try {
      await client.quit();
    } catch {
      client.disconnect();
    }
    client = null;
  }
  connectAttempted = false;
}

/** Test helper: reset connection state without quitting an external client. */
export function resetRedisClientForTests(): void {
  client = null;
  connectAttempted = false;
  lastErrorAt = 0;
}
