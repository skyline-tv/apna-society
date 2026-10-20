import mongoose from 'mongoose';
import { getCacheMetrics } from '../../cache/cache-metrics';
import { getRedisStatus } from '../../cache/redis.client';
import { getDatabaseHealth } from '../../database/connection';
import { getEnv } from '../../config/env';
import { getHttpMetrics } from '../../middleware/http-metrics';

export function getOpsMetricsSnapshot() {
  const env = getEnv();
  const db = getDatabaseHealth();
  const pool = mongoose.connection.getClient()?.options;

  return {
    timestamp: new Date().toISOString(),
    http: getHttpMetrics(),
    cache: getCacheMetrics(),
    redis: getRedisStatus(),
    mongodb: {
      ...db,
      // mongoose pool sizing from connect options (best-effort)
      maxPoolSize: (pool as { maxPoolSize?: number } | undefined)?.maxPoolSize ?? null,
    },
    workers: {
      visitorExpiry: env.VISITOR_EXPIRY_WORKER_ENABLED,
      announcements: env.ANNOUNCEMENT_WORKER_ENABLED,
      facilityBookings: env.FACILITY_BOOKING_WORKER_ENABLED,
    },
  };
}
