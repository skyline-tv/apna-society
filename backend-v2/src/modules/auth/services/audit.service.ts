import type { ClientSession, Types } from 'mongoose';
import { AuditLogModel, type AuditAction } from '../models/audit-log.model';
import { getLogger } from '../../../utils/logger';

export async function writeAuditLog(
  input: {
    action: AuditAction;
    actorUserId?: Types.ObjectId | string;
    societyId?: Types.ObjectId | string;
    targetType?: string;
    targetId?: string;
    metadata?: Record<string, unknown>;
    ipAddress?: string;
    userAgent?: string;
  },
  session?: ClientSession,
): Promise<void> {
  try {
    await AuditLogModel.create(
      [
        {
          action: input.action,
          actorUserId: input.actorUserId,
          societyId: input.societyId,
          targetType: input.targetType,
          targetId: input.targetId,
          metadata: input.metadata,
          ipAddress: input.ipAddress,
          userAgent: input.userAgent,
        },
      ],
      session ? { session } : undefined,
    );
  } catch (error) {
    getLogger().error({ err: error, action: input.action }, 'Failed to write audit log');
    // Inside a transaction, audit failure must fail the unit of work.
    if (session) {
      throw error;
    }
  }
}
