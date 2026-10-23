import { getEnv } from '../../../config/env';
import { getLogger } from '../../../utils/logger';
import { formatFlatLabel } from '../../../utils/flat-label';
import { notifyBusinessEvent } from '../../notifications/services/business-notify.service';
import { SocietyModel } from '../../society/models/society.model';
import { BillModel } from '../models/bill.model';
import { civilDateKey } from '../utils/billing-calendar';
import { billOutstandingPayablePaise, unpaidInterestPaise } from '../utils/bill-totals';
import { ensureSocietyInterestCurrent } from './interest-worker.service';

function billingMonthLabel(start: Date, timeZone: string): string {
  return new Intl.DateTimeFormat('en-IN', {
    month: 'long',
    year: 'numeric',
    timeZone,
  }).format(start);
}

/**
 * One overdue reminder per bill per civil day per recipient.
 * Uses stored interest (refreshed first) — does not compute a second interest engine.
 */
export async function runOverdueReminderPass(now = new Date()): Promise<{
  societiesProcessed: number;
  remindersCreated: number;
}> {
  const societies = await SocietyModel.find({ isActive: { $ne: false } })
    .select('_id config')
    .lean();

  let societiesProcessed = 0;
  let remindersCreated = 0;

  for (const society of societies) {
    const societyId = String(society._id);
    const timeZone = society.config?.timezone ?? 'Asia/Kolkata';
    try {
      await ensureSocietyInterestCurrent(societyId, now);
      const civilDate = civilDateKey(now, timeZone);
      const bills = await BillModel.find({
        societyId,
        status: { $nin: ['CANCELLED', 'PAID', 'DRAFT'] },
        dueDate: { $lt: now },
        ownerUserId: { $exists: true, $ne: null },
        $or: [
          { outstandingPrincipalPaise: { $gt: 0 } },
          { interestAccruedPaise: { $gt: 0 } },
        ],
      })
        .select(
          '_id ownerUserId billNumber billingPeriodStart dueDate outstandingPrincipalPaise interestAccruedPaise interestPaidPaise totalAmountPaise flatNumberSnapshot wingCodeSnapshot status',
        )
        .lean();

      for (const bill of bills) {
        if (!bill.ownerUserId) continue;
        const outstandingPrincipal = bill.outstandingPrincipalPaise ?? 0;
        const interest = unpaidInterestPaise(bill);
        const totalPayable = billOutstandingPayablePaise(bill);
        if (totalPayable <= 0) continue;

        const month = billingMonthLabel(bill.billingPeriodStart, timeZone);
        const flatLabel = formatFlatLabel(bill.wingCodeSnapshot, bill.flatNumberSnapshot);
        const result = await notifyBusinessEvent({
          societyId,
          recipientUserId: String(bill.ownerUserId),
          type: 'BILL_OVERDUE',
          title: 'Maintenance Bill Overdue',
          body: 'Your maintenance bill is overdue. Late-payment interest is increasing daily.',
          relatedEntityType: 'Bill',
          relatedEntityId: String(bill._id),
          idempotencyKey: `BILL_OVERDUE:${String(bill._id)}:${civilDate}`,
          metadata: {
            flatLabel,
            billingMonth: month,
            outstandingPrincipalPaise: outstandingPrincipal,
            accruedInterestPaise: interest,
            totalPayablePaise: totalPayable,
            dueDate: new Date(bill.dueDate).toISOString(),
            dueStatus: bill.status,
            deepLink: `apnasociety://bill/${String(bill._id)}`,
          },
        });
        if (result.created) remindersCreated += 1;
      }
      societiesProcessed += 1;
    } catch (error) {
      getLogger().error({ err: error, societyId }, 'Overdue reminder pass failed for society');
    }
  }

  getLogger().debug({ societiesProcessed, remindersCreated }, 'Overdue reminder pass finished');

  return { societiesProcessed, remindersCreated };
}

let timer: NodeJS.Timeout | undefined;

export function startOverdueReminderWorker(): void {
  const env = getEnv();
  if (!env.OVERDUE_REMINDER_WORKER_ENABLED) return;
  if (timer) return;
  const tick = () => {
    void runOverdueReminderPass().catch((error) => {
      getLogger().error({ err: error }, 'Overdue reminder worker pass failed');
    });
  };
  tick();
  timer = setInterval(tick, env.OVERDUE_REMINDER_WORKER_INTERVAL_MS);
  timer.unref?.();
  getLogger().info(
    { intervalMs: env.OVERDUE_REMINDER_WORKER_INTERVAL_MS },
    'Overdue reminder worker started',
  );
}

export function stopOverdueReminderWorker(): void {
  if (timer) {
    clearInterval(timer);
    timer = undefined;
  }
}
