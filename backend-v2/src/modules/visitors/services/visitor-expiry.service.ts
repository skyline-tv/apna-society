import { getEnv } from '../../../config/env';
import { writeAuditLog } from '../../auth/services/audit.service';
import { notifyBusinessEvent } from '../../notifications/services/business-notify.service';
import { formatFlatLabel } from '../../../utils/flat-label';
import { VisitorLogModel, type VisitorLogDocument } from '../models/visitor-log.model';
import { emitVisitorEvent, visitorEventPayloadFromDoc } from './visitor-events.service';

function extraResidentIds(
  visitor: { assignedResidentUserId: { toString(): string }; notifiedResidentUserIds?: { toString(): string }[] },
): string[] {
  const assigned = String(visitor.assignedResidentUserId);
  return (visitor.notifiedResidentUserIds ?? [])
    .map((id) => String(id))
    .filter((id) => id !== assigned);
}

async function notifyExpired(visitor: VisitorLogDocument, reason: string) {
  const societyId = String(visitor.societyId);
  const flatLabel = formatFlatLabel(visitor.wingCodeSnapshot, visitor.flatNumberSnapshot);
  const recipients = [
    String(visitor.assignedResidentUserId),
    ...extraResidentIds(visitor),
    String(visitor.requestedByGuardId),
  ];
  emitVisitorEvent('visitor:expired', visitorEventPayloadFromDoc(visitor), {
    extraResidentUserIds: extraResidentIds(visitor),
  });
  for (const recipientUserId of [...new Set(recipients)]) {
    await notifyBusinessEvent({
      societyId,
      recipientUserId,
      type: 'VISITOR_EXPIRED',
      title: 'Visitor request expired',
      body: `The request for ${visitor.visitorName} at ${flatLabel} expired without a decision.`,
      relatedEntityType: 'VisitorLog',
      relatedEntityId: String(visitor._id),
      idempotencyKey: `VISITOR_EXPIRED:${String(visitor._id)}:${recipientUserId}`,
      metadata: {
        visitorName: visitor.visitorName,
        flatLabel,
        entryMode: visitor.entryMode ?? 'OTP',
        ...(visitor.entryMode === 'WALK_IN'
          ? { callAction: 'stop', priority: 'high' }
          : {}),
      },
    });
  }
  await writeAuditLog({
    action: 'VISITOR_EXPIRED',
    societyId,
    targetType: 'VisitorLog',
    targetId: String(visitor._id),
    metadata: { reason, flatId: String(visitor.flatId) },
  });
}

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

  const walkInPending = await VisitorLogModel.find({
    approvalStatus: 'PENDING',
    entryStatus: 'NOT_ENTERED',
    entryMode: 'WALK_IN',
    pendingExpiresAt: { $lte: now },
  });

  let pendingExpired = 0;
  for (const row of walkInPending) {
    const updated = await VisitorLogModel.findOneAndUpdate(
      {
        _id: row._id,
        approvalStatus: 'PENDING',
        entryStatus: 'NOT_ENTERED',
      },
      {
        $set: {
          approvalStatus: 'EXPIRED',
          expiredAt: now,
          resolution: 'EXPIRED',
        },
        $unset: { entryOtpHash: 1, entryOtpExpiresAt: 1 },
      },
      { new: true },
    );
    if (updated) {
      pendingExpired += 1;
      await notifyExpired(updated, 'WALK_IN_TTL');
    }
  }

  const otpPending = await VisitorLogModel.find({
    approvalStatus: 'PENDING',
    entryStatus: 'NOT_ENTERED',
    entryMode: { $ne: 'WALK_IN' },
    createdAt: { $lt: pendingCutoff },
  });

  for (const row of otpPending) {
    const updated = await VisitorLogModel.findOneAndUpdate(
      {
        _id: row._id,
        approvalStatus: 'PENDING',
        entryStatus: 'NOT_ENTERED',
        entryMode: { $ne: 'WALK_IN' },
      },
      {
        $set: {
          approvalStatus: 'EXPIRED',
          expiredAt: now,
          resolution: 'EXPIRED',
        },
        $unset: { entryOtpHash: 1, entryOtpExpiresAt: 1 },
      },
      { new: true },
    );
    if (updated) {
      pendingExpired += 1;
      await notifyExpired(updated, 'PENDING_TTL');
    }
  }

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
          resolution: 'EXPIRED',
        },
        $unset: { entryOtpHash: 1, entryOtpExpiresAt: 1 },
      },
      { new: true },
    );
    if (updated) {
      otpExpired += 1;
      await notifyExpired(updated, 'OTP_EXPIRED');
    }
  }

  return {
    pendingExpired,
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
