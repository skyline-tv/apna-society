import { getEnv } from '../../../config/env';
import { writeAuditLog } from '../../auth/services/audit.service';
import { VisitorLogModel } from '../models/visitor-log.model';

/**
 * Idempotent expiry of pending approvals and unused OTPs.
 * Never expires or removes visitors who are currently inside (ENTERED).
 */
export async function runVisitorExpiryPass(now = new Date()): Promise<{
  pendingExpired: number;
  otpExpired: number;
}> {
  const env = getEnv();
  const pendingCutoff = new Date(now.getTime() - env.VISITOR_PENDING_TTL_MS);

  const pendingResult = await VisitorLogModel.updateMany(
    {
      approvalStatus: 'PENDING',
      entryStatus: 'NOT_ENTERED',
      createdAt: { $lt: pendingCutoff },
    },
    {
      $set: {
        approvalStatus: 'EXPIRED',
        expiredAt: now,
      },
      $unset: { entryOtpHash: 1, entryOtpExpiresAt: 1 },
    },
  );

  const otpCandidates = await VisitorLogModel.find({
    approvalStatus: 'APPROVED',
    entryStatus: 'NOT_ENTERED',
    entryOtpExpiresAt: { $lt: now },
  }).select('_id societyId flatId');

  let otpExpired = 0;
  for (const row of otpCandidates) {
    const updated = await VisitorLogModel.findOneAndUpdate(
      {
        _id: row._id,
        approvalStatus: 'APPROVED',
        entryStatus: 'NOT_ENTERED',
        entryOtpExpiresAt: { $lt: now },
      },
      {
        $set: {
          approvalStatus: 'EXPIRED',
          expiredAt: now,
        },
        $unset: { entryOtpHash: 1, entryOtpExpiresAt: 1 },
      },
      { new: true },
    );
    if (updated) {
      otpExpired += 1;
      await writeAuditLog({
        action: 'VISITOR_EXPIRED',
        societyId: String(updated.societyId),
        targetType: 'VisitorLog',
        targetId: String(updated._id),
        metadata: {
          reason: 'OTP_EXPIRED',
          flatId: String(updated.flatId),
        },
      });
    }
  }

  // Audit pending expiries in batch (avoid N writes when many).
  if (pendingResult.modifiedCount > 0) {
    await writeAuditLog({
      action: 'VISITOR_EXPIRED',
      targetType: 'VisitorLog',
      metadata: {
        reason: 'PENDING_TTL',
        count: pendingResult.modifiedCount,
      },
    });
  }

  return {
    pendingExpired: pendingResult.modifiedCount,
    otpExpired,
  };
}

let timer: NodeJS.Timeout | undefined;

export function startVisitorExpiryWorker(): void {
  const env = getEnv();
  if (!env.VISITOR_EXPIRY_WORKER_ENABLED) {
    return;
  }
  if (timer) return;
  timer = setInterval(() => {
    void runVisitorExpiryPass().catch(() => {
      // Errors are non-fatal; next tick retries.
    });
  }, env.VISITOR_EXPIRY_WORKER_INTERVAL_MS);
  timer.unref?.();
}

export function stopVisitorExpiryWorker(): void {
  if (timer) {
    clearInterval(timer);
    timer = undefined;
  }
}
