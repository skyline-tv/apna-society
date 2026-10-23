import { getLogger } from '../../../utils/logger';
import type { NotificationType } from '../models/notification.model';
import { createNotification } from './notification.service';

/**
 * Persist a business-event notification after the primary transaction commits.
 * Failures are logged and do not roll back the business operation.
 * Idempotency keys prevent duplicates on webhook/worker retries.
 */
export async function notifyBusinessEvent(input: {
  societyId: string;
  recipientUserId: string;
  type: NotificationType;
  title: string;
  body: string;
  relatedEntityType?: string;
  relatedEntityId?: string;
  idempotencyKey: string;
  metadata?: Record<string, unknown>;
}): Promise<{ created: boolean }> {
  if (!input.recipientUserId) return { created: false };
  try {
    const result = await createNotification({
      societyId: input.societyId,
      recipientUserId: input.recipientUserId,
      type: input.type,
      title: input.title,
      body: input.body,
      relatedEntityType: input.relatedEntityType,
      relatedEntityId: input.relatedEntityId,
      idempotencyKey: input.idempotencyKey,
      metadata: input.metadata,
      emitSocket: true,
      deliverPush: true,
    });
    return { created: result.created };
  } catch (error) {
    getLogger().error(
      { err: error, type: input.type, idempotencyKey: input.idempotencyKey },
      'Failed to persist business notification',
    );
    return { created: false };
  }
}
