import { isDuplicateKeyError } from '../../../utils/mongo-errors';
import { parseObjectId } from '../../../utils/object-id';
import { forbidden, notFound } from '../../../shared/errors/app-error';
import {
  NotificationModel,
  type NotificationType,
} from '../models/notification.model';
import { emitNotificationCreated } from './notification-events.service';

export function serializeNotification(doc: {
  _id: { toString(): string };
  societyId: { toString(): string };
  recipientUserId: { toString(): string };
  type: string;
  title: string;
  body: string;
  relatedEntityType?: string;
  relatedEntityId?: string;
  isRead: boolean;
  readAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: String(doc._id),
    societyId: String(doc.societyId),
    recipientUserId: String(doc.recipientUserId),
    type: doc.type,
    title: doc.title,
    body: doc.body,
    relatedEntityType: doc.relatedEntityType,
    relatedEntityId: doc.relatedEntityId,
    isRead: doc.isRead,
    readAt: doc.readAt?.toISOString(),
    createdAt: new Date(doc.createdAt).toISOString(),
    updatedAt: new Date(doc.updatedAt).toISOString(),
  };
}

/**
 * Persist a notification idempotently, then emit a Socket.IO hint.
 * Safe to call after business transactions commit (or from workers).
 */
export async function createNotification(input: {
  societyId: string;
  recipientUserId: string;
  type: NotificationType;
  title: string;
  body: string;
  relatedEntityType?: string;
  relatedEntityId?: string;
  idempotencyKey: string;
  metadata?: Record<string, unknown>;
  emitSocket?: boolean;
}): Promise<{ created: boolean; notification: ReturnType<typeof serializeNotification> }> {
  try {
    const [doc] = await NotificationModel.create([
      {
        societyId: input.societyId,
        recipientUserId: input.recipientUserId,
        type: input.type,
        title: input.title.slice(0, 200),
        body: input.body.slice(0, 2000),
        relatedEntityType: input.relatedEntityType,
        relatedEntityId: input.relatedEntityId,
        idempotencyKey: input.idempotencyKey,
        metadata: input.metadata,
        isRead: false,
      },
    ]);
    const serialized = serializeNotification(doc);
    if (input.emitSocket !== false) {
      emitNotificationCreated(serialized);
    }
    return { created: true, notification: serialized };
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      const existing = await NotificationModel.findOne({
        idempotencyKey: input.idempotencyKey,
      }).lean();
      if (!existing) throw error;
      return { created: false, notification: serializeNotification(existing) };
    }
    throw error;
  }
}

export async function listNotifications(
  societyId: string,
  recipientUserId: string,
  query: {
    isRead?: boolean;
    type?: NotificationType;
    page?: number;
    limit?: number;
  },
) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
    recipientUserId: parseObjectId(recipientUserId, 'userId'),
  };
  if (query.isRead !== undefined) filter.isRead = query.isRead;
  if (query.type) filter.type = query.type;

  const [total, rows] = await Promise.all([
    NotificationModel.countDocuments(filter),
    NotificationModel.find(filter)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((r) => serializeNotification(r)),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function getNotification(
  societyId: string,
  recipientUserId: string,
  notificationId: string,
) {
  const doc = await NotificationModel.findOne({
    _id: parseObjectId(notificationId, 'notificationId'),
    societyId: parseObjectId(societyId, 'societyId'),
    recipientUserId: parseObjectId(recipientUserId, 'userId'),
  }).lean();
  if (!doc) throw notFound('Notification not found');
  return serializeNotification(doc);
}

export async function markNotificationRead(
  societyId: string,
  recipientUserId: string,
  notificationId: string,
  isRead: boolean,
) {
  const doc = await NotificationModel.findOne({
    _id: parseObjectId(notificationId, 'notificationId'),
    societyId: parseObjectId(societyId, 'societyId'),
    recipientUserId: parseObjectId(recipientUserId, 'userId'),
  });
  if (!doc) throw notFound('Notification not found');

  if (isRead) {
    if (!doc.isRead) {
      doc.isRead = true;
      doc.readAt = new Date();
      await doc.save();
    }
  } else if (doc.isRead) {
    doc.isRead = false;
    doc.readAt = undefined;
    await doc.save();
  }

  return serializeNotification(doc);
}

export async function markAllNotificationsRead(societyId: string, recipientUserId: string) {
  const result = await NotificationModel.updateMany(
    {
      societyId: parseObjectId(societyId, 'societyId'),
      recipientUserId: parseObjectId(recipientUserId, 'userId'),
      isRead: false,
    },
    { $set: { isRead: true, readAt: new Date() } },
  );
  return { updated: result.modifiedCount };
}

export async function unreadNotificationCount(societyId: string, recipientUserId: string) {
  const count = await NotificationModel.countDocuments({
    societyId: parseObjectId(societyId, 'societyId'),
    recipientUserId: parseObjectId(recipientUserId, 'userId'),
    isRead: false,
  });
  return { unreadCount: count };
}

/** Guard against IDOR when society context mismatches. */
export function assertOwnNotification(
  recipientUserId: string,
  authenticatedUserId: string,
): void {
  if (recipientUserId !== authenticatedUserId) {
    throw forbidden('Notification access denied', 'NOTIFICATION_ACCESS_DENIED');
  }
}
