import { getRedisStatus } from '../../cache/redis.client';
import { getEnv, isLivePaymentsEnabled } from '../../config/env';
import { getDatabaseHealth, pingDatabase, supportsTransactions } from '../../database/connection';

export async function getReadinessSnapshot() {
  const env = getEnv();
  const db = getDatabaseHealth();
  const reachable = db.status === 'up' ? await pingDatabase() : false;
  const redis = getRedisStatus();

  const workers = {
    visitorExpiry: env.VISITOR_EXPIRY_WORKER_ENABLED,
    announcementPublication: env.ANNOUNCEMENT_WORKER_ENABLED,
    facilityBookingExpiry: env.FACILITY_BOOKING_WORKER_ENABLED,
  };

  const emailConfigured = Boolean(env.RESEND_API_KEY);
  const paymentsLive = isLivePaymentsEnabled();
  const storage = {
    complaints: env.COMPLAINT_STORAGE_PROVIDER,
    announcements: env.ANNOUNCEMENT_STORAGE_PROVIDER,
  };

  const healthy = db.status === 'up' && reachable;
  // Redis is optional (fail-open); absence does not mark the API unavailable.
  const readyForProductionTraffic =
    healthy &&
    (env.NODE_ENV !== 'production' ||
      (emailConfigured && supportsTransactions() && storage.complaints !== 'memory'));

  return {
    status: healthy ? (readyForProductionTraffic ? 'ready' : 'degraded') : 'unavailable',
    database: { ...db, reachable, transactionsLikely: supportsTransactions() },
    redis,
    workers,
    emailConfigured,
    paymentsLive,
    storage,
    timestamp: new Date().toISOString(),
  };
}
