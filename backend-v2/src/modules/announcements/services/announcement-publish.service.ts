import { createNotification } from '../../notifications/services/notification.service';
import { NotificationModel } from '../../notifications/models/notification.model';
import { AnnouncementModel } from '../models/announcement.model';
import { resolveAnnouncementRecipients } from './audience.service';
import { emitAnnouncementPublished } from './announcement-events.service';

/**
 * Deliver notifications for a PUBLISHED announcement with deliveryState PENDING.
 * Idempotent via notification idempotency keys; safe across worker restarts.
 */
export async function deliverAnnouncementNotifications(announcementId: string): Promise<{
  eligible: number;
  created: number;
}> {
  const announcement = await AnnouncementModel.findById(announcementId);
  if (!announcement) return { eligible: 0, created: 0 };
  if (announcement.status !== 'PUBLISHED') return { eligible: 0, created: 0 };

  const recipients = await resolveAnnouncementRecipients({
    societyId: String(announcement.societyId),
    audienceType: announcement.audienceType,
    targetWingIds: announcement.targetWingIds.map(String),
    targetFlatIds: announcement.targetFlatIds.map(String),
  });

  let createdThisPass = 0;
  for (const userId of recipients) {
    const result = await createNotification({
      societyId: String(announcement.societyId),
      recipientUserId: userId,
      type: 'ANNOUNCEMENT',
      title: announcement.title,
      body: announcement.body.slice(0, 500),
      relatedEntityType: 'Announcement',
      relatedEntityId: String(announcement._id),
      idempotencyKey: `ANNOUNCEMENT:${String(announcement._id)}:${userId}`,
      emitSocket: true,
    });
    if (result.created) createdThisPass += 1;
  }

  const totalPersisted = await NotificationModel.countDocuments({
    societyId: announcement.societyId,
    type: 'ANNOUNCEMENT',
    relatedEntityType: 'Announcement',
    relatedEntityId: String(announcement._id),
  });

  announcement.eligibleRecipientCount = recipients.length;
  announcement.notificationCreatedCount = totalPersisted;
  announcement.deliveryState = 'COMPLETE';
  await announcement.save();

  emitAnnouncementPublished(
    {
      announcementId: String(announcement._id),
      societyId: String(announcement.societyId),
      title: announcement.title,
      category: announcement.category,
      priority: announcement.priority,
      publishedAt: (announcement.publishedAt ?? new Date()).toISOString(),
    },
    recipients,
  );

  return { eligible: recipients.length, created: createdThisPass };
}

/**
 * Atomically claim a SCHEDULED announcement for publication (multi-instance safe).
 */
export async function claimAndPublishScheduled(now = new Date()) {
  const claimed = await AnnouncementModel.findOneAndUpdate(
    {
      status: 'SCHEDULED',
      scheduledAt: { $lte: now },
      $and: [
        {
          $or: [{ expiresAt: null }, { expiresAt: { $exists: false } }, { expiresAt: { $gt: now } }],
        },
      ],
    },
    {
      $set: {
        status: 'PUBLISHED',
        publishedAt: now,
        deliveryState: 'PENDING',
      },
    },
    { new: true },
  );

  if (!claimed) return null;

  await deliverAnnouncementNotifications(String(claimed._id));
  return claimed;
}

/** Resume incomplete deliveries after crash (PUBLISHED + PENDING). */
export async function resumePendingDeliveries() {
  const pending = await AnnouncementModel.find({
    status: 'PUBLISHED',
    deliveryState: 'PENDING',
  })
    .select('_id')
    .limit(20)
    .lean();

  let resumed = 0;
  for (const row of pending) {
    await deliverAnnouncementNotifications(String(row._id));
    resumed += 1;
  }
  return resumed;
}
