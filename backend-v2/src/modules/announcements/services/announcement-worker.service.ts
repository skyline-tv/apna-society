import { getEnv } from '../../../config/env';
import { getLogger } from '../../../utils/logger';
import {
  claimAndPublishScheduled,
  resumePendingDeliveries,
} from './announcement-publish.service';

/**
 * Interval worker for scheduled announcement publication.
 * Multi-instance safe: publication uses atomic findOneAndUpdate claim.
 * Restart-safe: resumes PUBLISHED+PENDING deliveries.
 *
 * Enable with ANNOUNCEMENT_WORKER_ENABLED=true (same pattern as visitor expiry).
 */
export async function runAnnouncementWorkerPass(): Promise<{
  published: number;
  resumed: number;
}> {
  let published = 0;
  // Claim up to N scheduled items per tick.
  for (let i = 0; i < 10; i += 1) {
    const claimed = await claimAndPublishScheduled();
    if (!claimed) break;
    published += 1;
  }
  const resumed = await resumePendingDeliveries();
  return { published, resumed };
}

let timer: NodeJS.Timeout | undefined;

export function startAnnouncementWorker(): void {
  const env = getEnv();
  if (!env.ANNOUNCEMENT_WORKER_ENABLED) return;
  if (timer) return;
  timer = setInterval(() => {
    void runAnnouncementWorkerPass().catch((error) => {
      getLogger().error({ err: error }, 'Announcement worker pass failed');
    });
  }, env.ANNOUNCEMENT_WORKER_INTERVAL_MS);
  timer.unref?.();
  getLogger().info(
    { intervalMs: env.ANNOUNCEMENT_WORKER_INTERVAL_MS },
    'Announcement publication worker started',
  );
}

export function stopAnnouncementWorker(): void {
  if (timer) {
    clearInterval(timer);
    timer = undefined;
  }
}
