import { getEnv } from '../../../config/env';
import { getLogger } from '../../../utils/logger';
import { FacilityBookingModel } from '../models/facility-booking.model';

/**
 * Expires PENDING facility bookings past expiresAt.
 * Multi-instance safe: idempotent updateMany on status filter.
 */
export async function runFacilityBookingExpiryPass(): Promise<number> {
  const result = await FacilityBookingModel.updateMany(
    {
      status: 'PENDING',
      expiresAt: { $lte: new Date() },
    },
    {
      $set: { status: 'CANCELLED', cancellationReason: 'Pending booking expired' },
    },
  );
  return result.modifiedCount;
}

let timer: NodeJS.Timeout | undefined;

export function startFacilityBookingWorker(): void {
  const env = getEnv();
  if (!env.FACILITY_BOOKING_WORKER_ENABLED) return;
  if (timer) return;
  timer = setInterval(() => {
    void runFacilityBookingExpiryPass().catch((error) => {
      getLogger().error({ err: error }, 'Facility booking expiry worker failed');
    });
  }, env.FACILITY_BOOKING_WORKER_INTERVAL_MS);
  timer.unref?.();
  getLogger().info(
    { intervalMs: env.FACILITY_BOOKING_WORKER_INTERVAL_MS },
    'Facility booking expiry worker started',
  );
}

export function stopFacilityBookingWorker(): void {
  if (timer) {
    clearInterval(timer);
    timer = undefined;
  }
}
