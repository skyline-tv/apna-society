import http from 'http';
import { disconnectRedis, getRedisClient, isRedisConfigured } from './cache/redis.client';
import { loadEnv } from './config/env';
import { connectDatabase, disconnectDatabase } from './database/connection';
import { createApp } from './app';
import { getLogger } from './utils/logger';
import { attachSocketServer } from './workers/socket';
import {
  startAnnouncementWorker,
  stopAnnouncementWorker,
} from './modules/announcements/services/announcement-worker.service';
import {
  startFacilityBookingWorker,
  stopFacilityBookingWorker,
} from './modules/facilities/services/facility-booking-worker.service';
import {
  startInterestWorker,
  stopInterestWorker,
} from './modules/billing/services/interest-worker.service';
import {
  startVisitorExpiryWorker,
  stopVisitorExpiryWorker,
} from './modules/visitors/services/visitor-expiry.service';
import {
  startOverdueReminderWorker,
  stopOverdueReminderWorker,
} from './modules/billing/services/overdue-reminder.service';
import {
  startPushRetryWorker,
  stopPushRetryWorker,
} from './modules/notifications/services/push-delivery.service';

async function bootstrap(): Promise<void> {
  const env = loadEnv();
  const logger = getLogger();

  await connectDatabase();
  if (isRedisConfigured()) {
    await getRedisClient();
  }

  const app = createApp();
  const server = http.createServer(app);
  const io = attachSocketServer(server);
  startVisitorExpiryWorker();
  startAnnouncementWorker();
  startFacilityBookingWorker();
  startInterestWorker();
  startOverdueReminderWorker();
  startPushRetryWorker();

  server.listen(env.PORT, env.HOST, () => {
    logger.info(
      {
        host: env.HOST,
        port: env.PORT,
        env: env.NODE_ENV,
        redis: isRedisConfigured() ? 'enabled' : 'disabled',
        workers: {
          visitorExpiry: env.VISITOR_EXPIRY_WORKER_ENABLED,
          announcements: env.ANNOUNCEMENT_WORKER_ENABLED,
          facilityBookings: env.FACILITY_BOOKING_WORKER_ENABLED,
          interestAccrual: env.INTEREST_WORKER_ENABLED,
          overdueReminders: env.OVERDUE_REMINDER_WORKER_ENABLED,
          pushRetry: env.PUSH_RETRY_WORKER_ENABLED,
          fcm: env.FCM_ENABLED,
        },
      },
      'HTTP server listening',
    );
  });

  let shuttingDown = false;
  const shutdown = async (signal: string) => {
    if (shuttingDown) return;
    shuttingDown = true;
    logger.info({ signal }, 'Shutting down');
    stopVisitorExpiryWorker();
    stopAnnouncementWorker();
    stopFacilityBookingWorker();
    stopInterestWorker();
    stopOverdueReminderWorker();
    stopPushRetryWorker();
    io.close();
    server.close(async () => {
      await disconnectRedis();
      await disconnectDatabase();
      process.exit(0);
    });
    setTimeout(() => {
      logger.error('Forced shutdown after timeout');
      process.exit(1);
    }, 10_000).unref();
  };

  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('SIGTERM', () => void shutdown('SIGTERM'));
}

bootstrap().catch((error: unknown) => {
  console.error('Fatal bootstrap error', error);
  process.exit(1);
});
