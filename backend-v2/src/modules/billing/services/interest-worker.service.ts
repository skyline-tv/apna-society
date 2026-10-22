import { getEnv } from '../../../config/env';
import { isDuplicateKeyError } from '../../../utils/mongo-errors';
import { getLogger } from '../../../utils/logger';
import { SocietyModel } from '../../society/models/society.model';
import { InterestJobRunModel } from '../models/interest-job-run.model';
import { civilDateKey } from '../utils/billing-calendar';
import { refreshSocietyInterestSummaries } from './interest.service';

const STALE_RUNNING_MS = 15 * 60 * 1000;
const WAIT_POLL_MS = 50;
const WAIT_TIMEOUT_MS = 30_000;

export type InterestJobClaimReason = 'already_completed' | 'in_progress' | 'race';

export async function claimSocietyInterestJob(
  societyId: string,
  civilDate: string,
  now = new Date(),
): Promise<{ claimed: true; runId: string } | { claimed: false; reason: InterestJobClaimReason }> {
  const existing = await InterestJobRunModel.findOne({ societyId, civilDate });
  if (existing?.status === 'COMPLETED') {
    return { claimed: false, reason: 'already_completed' };
  }
  if (
    existing?.status === 'RUNNING' &&
    now.getTime() - existing.startedAt.getTime() < STALE_RUNNING_MS
  ) {
    return { claimed: false, reason: 'in_progress' };
  }

  if (!existing) {
    try {
      const run = await InterestJobRunModel.create({
        societyId,
        civilDate,
        status: 'RUNNING',
        asOf: now,
        startedAt: now,
      });
      return { claimed: true, runId: String(run._id) };
    } catch (error) {
      if (isDuplicateKeyError(error)) {
        return { claimed: false, reason: 'race' };
      }
      throw error;
    }
  }

  const taken = await InterestJobRunModel.findOneAndUpdate(
    {
      _id: existing._id,
      status: { $in: ['FAILED', 'RUNNING'] },
    },
    {
      $set: { status: 'RUNNING', startedAt: now, asOf: now },
      $unset: { error: 1, finishedAt: 1 },
    },
    { new: true },
  );
  if (!taken) {
    return { claimed: false, reason: 'race' };
  }
  return { claimed: true, runId: String(taken._id) };
}

async function waitForInterestJob(societyId: string, civilDate: string): Promise<void> {
  const deadline = Date.now() + WAIT_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const run = await InterestJobRunModel.findOne({ societyId, civilDate }).lean();
    if (run?.status === 'COMPLETED') return;
    if (run?.status === 'FAILED') {
      throw new Error(run.error || 'Interest accrual failed');
    }
    await new Promise((resolve) => setTimeout(resolve, WAIT_POLL_MS));
  }
  throw new Error('Timed out waiting for interest accrual');
}

/**
 * Recompute stored interest for one society as of `asOf`.
 * Safe after downtime: totals are derived from the ledger + civil days, not incremented.
 */
export async function ensureSocietyInterestCurrent(
  societyId: string,
  asOf = new Date(),
): Promise<{ updated: number; skipped: boolean; reason?: InterestJobClaimReason }> {
  const society = await SocietyModel.findById(societyId).lean();
  const timeZone = society?.config?.timezone ?? 'Asia/Kolkata';
  const civilDate = civilDateKey(asOf, timeZone);
  const claim = await claimSocietyInterestJob(societyId, civilDate, asOf);
  if (!claim.claimed) {
    if (claim.reason !== 'already_completed') {
      await waitForInterestJob(societyId, civilDate);
    }
    return { updated: 0, skipped: true, reason: claim.reason };
  }

  try {
    const result = await refreshSocietyInterestSummaries(societyId, asOf);
    await InterestJobRunModel.updateOne(
      { _id: claim.runId },
      {
        $set: {
          status: 'COMPLETED',
          finishedAt: new Date(),
          billsUpdated: result.updated,
          billsSkipped: result.skipped,
        },
      },
    );
    return { updated: result.updated, skipped: false };
  } catch (error) {
    await InterestJobRunModel.updateOne(
      { _id: claim.runId },
      {
        $set: {
          status: 'FAILED',
          finishedAt: new Date(),
          error: error instanceof Error ? error.message : String(error),
        },
      },
    );
    throw error;
  }
}

export async function runInterestAccrualPass(now = new Date()): Promise<{
  societiesProcessed: number;
  billsUpdated: number;
  skipped: number;
}> {
  const societies = await SocietyModel.find({ isActive: { $ne: false } })
    .select('_id')
    .lean();

  let societiesProcessed = 0;
  let billsUpdated = 0;
  let skipped = 0;

  for (const society of societies) {
    const societyId = String(society._id);
    try {
      const result = await ensureSocietyInterestCurrent(societyId, now);
      if (result.skipped) {
        skipped += 1;
      } else {
        societiesProcessed += 1;
        billsUpdated += result.updated;
      }
    } catch (error) {
      skipped += 1;
      getLogger().error({ err: error, societyId }, 'Interest accrual pass failed for society');
    }
  }

  return { societiesProcessed, billsUpdated, skipped };
}

let timer: NodeJS.Timeout | undefined;

export function startInterestWorker(): void {
  const env = getEnv();
  if (!env.INTEREST_WORKER_ENABLED) return;
  if (timer) return;
  const tick = () => {
    void runInterestAccrualPass().catch((error) => {
      getLogger().error({ err: error }, 'Interest accrual worker pass failed');
    });
  };
  tick();
  timer = setInterval(tick, env.INTEREST_WORKER_INTERVAL_MS);
  timer.unref?.();
  getLogger().info(
    { intervalMs: env.INTEREST_WORKER_INTERVAL_MS },
    'Interest accrual worker started',
  );
}

export function stopInterestWorker(): void {
  if (timer) {
    clearInterval(timer);
    timer = undefined;
  }
}
