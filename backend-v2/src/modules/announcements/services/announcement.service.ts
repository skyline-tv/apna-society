import { Types } from 'mongoose';
import { invalidateAnnouncementCaches } from '../../../cache/cache-invalidation';
import { CacheKeys } from '../../../cache/cache-keys';
import { cacheSet } from '../../../cache/cache.service';
import { getEnv } from '../../../config/env';
import { badRequest, conflict, forbidden, notFound } from '../../../shared/errors/app-error';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { AnnouncementReadModel } from '../models/announcement-read.model';
import {
  AnnouncementModel,
  type AnnouncementCategory,
  type AnnouncementPriority,
  type AnnouncementStatus,
  type AudienceType,
} from '../models/announcement.model';
import { getAnnouncementStorage } from '../storage/announcement-storage';
import { assertAnnouncementFileBuffer } from '../storage/file-validation';
import { resolveAnnouncementRecipients, userCanViewAnnouncement } from './audience.service';
import { deliverAnnouncementNotifications } from './announcement-publish.service';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

function serializeAttachment(att: {
  _id: { toString(): string };
  mimeType: string;
  sizeBytes: number;
  originalFilename: string;
  uploadedByUserId: { toString(): string };
  createdAt: Date;
}) {
  return {
    id: String(att._id),
    mimeType: att.mimeType,
    sizeBytes: att.sizeBytes,
    originalFilename: att.originalFilename,
    uploadedByUserId: String(att.uploadedByUserId),
    createdAt: new Date(att.createdAt).toISOString(),
  };
}

function serializeAnnouncement(
  doc: {
    _id: { toString(): string };
    societyId: { toString(): string };
    title: string;
    body: string;
    category: string;
    priority: string;
    audienceType: string;
    targetWingIds: { toString(): string }[];
    targetFlatIds: { toString(): string }[];
    attachments?: Array<{
      _id: { toString(): string };
      mimeType: string;
      sizeBytes: number;
      originalFilename: string;
      uploadedByUserId: { toString(): string };
      createdAt: Date;
    }>;
    status: string;
    publishedByUserId?: { toString(): string };
    publishedAt?: Date;
    scheduledAt?: Date;
    expiresAt?: Date;
    deliveryState?: string;
    eligibleRecipientCount?: number;
    notificationCreatedCount?: number;
    createdBy: { toString(): string };
    adminNotes?: string;
    createdAt: Date;
    updatedAt: Date;
  },
  options: { includeAdmin?: boolean; isRead?: boolean } = {},
) {
  return {
    id: String(doc._id),
    societyId: String(doc.societyId),
    title: doc.title,
    body: doc.body,
    category: doc.category,
    priority: doc.priority,
    audienceType: doc.audienceType,
    targetWingIds: options.includeAdmin
      ? doc.targetWingIds.map((id) => String(id))
      : undefined,
    targetFlatIds: options.includeAdmin
      ? doc.targetFlatIds.map((id) => String(id))
      : undefined,
    attachments: (doc.attachments ?? []).map((a) => serializeAttachment(a)),
    status: doc.status,
    publishedByUserId: doc.publishedByUserId ? String(doc.publishedByUserId) : undefined,
    publishedAt: doc.publishedAt?.toISOString(),
    scheduledAt: doc.scheduledAt?.toISOString(),
    expiresAt: doc.expiresAt?.toISOString(),
    deliveryState: options.includeAdmin ? doc.deliveryState : undefined,
    eligibleRecipientCount: options.includeAdmin ? doc.eligibleRecipientCount : undefined,
    notificationCreatedCount: options.includeAdmin ? doc.notificationCreatedCount : undefined,
    createdBy: options.includeAdmin ? String(doc.createdBy) : undefined,
    adminNotes: options.includeAdmin ? doc.adminNotes : undefined,
    isRead: options.isRead,
    createdAt: new Date(doc.createdAt).toISOString(),
    updatedAt: new Date(doc.updatedAt).toISOString(),
  };
}

function dedupeIds(ids: string[] | undefined): string[] {
  return [...new Set((ids ?? []).map((id) => String(id)))];
}

export async function createDraftAnnouncement(
  societyId: string,
  input: {
    title: string;
    body: string;
    category: AnnouncementCategory;
    priority?: AnnouncementPriority;
    audienceType: AudienceType;
    targetWingIds?: string[];
    targetFlatIds?: string[];
    expiresAt?: Date;
    adminNotes?: string;
  },
  actor: Actor,
) {
  // Validates wing/flat ownership; zero current residents is allowed for drafts.
  await resolveAnnouncementRecipients({
    societyId,
    audienceType: input.audienceType,
    targetWingIds: dedupeIds(input.targetWingIds),
    targetFlatIds: dedupeIds(input.targetFlatIds),
  });

  const [doc] = await AnnouncementModel.create([
    {
      societyId,
      title: input.title.trim(),
      body: input.body.trim(),
      category: input.category,
      priority: input.priority ?? 'NORMAL',
      audienceType: input.audienceType,
      targetWingIds: dedupeIds(input.targetWingIds),
      targetFlatIds: dedupeIds(input.targetFlatIds),
      status: 'DRAFT',
      expiresAt: input.expiresAt,
      adminNotes: input.adminNotes?.trim(),
      createdBy: actor.userId,
      deliveryState: 'NOT_STARTED',
    },
  ]);

  await writeAuditLog({
    action: 'ANNOUNCEMENT_CREATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Announcement',
    targetId: String(doc._id),
    metadata: { category: input.category, audienceType: input.audienceType },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeAnnouncement(doc, { includeAdmin: true });
}

export async function updateDraftAnnouncement(
  societyId: string,
  announcementId: string,
  input: Partial<{
    title: string;
    body: string;
    category: AnnouncementCategory;
    priority: AnnouncementPriority;
    audienceType: AudienceType;
    targetWingIds: string[];
    targetFlatIds: string[];
    expiresAt: Date | null;
    adminNotes: string;
  }>,
  actor: Actor,
) {
  const doc = await AnnouncementModel.findOne({
    _id: parseObjectId(announcementId, 'announcementId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Announcement not found');
  if (doc.status !== 'DRAFT') {
    throw conflict('Only DRAFT announcements can be edited this way', 'ANNOUNCEMENT_NOT_EDITABLE');
  }

  if (input.title !== undefined) doc.title = input.title.trim();
  if (input.body !== undefined) doc.body = input.body.trim();
  if (input.category !== undefined) doc.category = input.category;
  if (input.priority !== undefined) doc.priority = input.priority;
  if (input.audienceType !== undefined) doc.audienceType = input.audienceType;
  if (input.targetWingIds !== undefined) doc.targetWingIds = dedupeIds(input.targetWingIds).map(
    (id) => parseObjectId(id, 'wingId'),
  ) as never;
  if (input.targetFlatIds !== undefined) doc.targetFlatIds = dedupeIds(input.targetFlatIds).map(
    (id) => parseObjectId(id, 'flatId'),
  ) as never;
  if (input.expiresAt !== undefined) doc.expiresAt = input.expiresAt ?? undefined;
  if (input.adminNotes !== undefined) doc.adminNotes = input.adminNotes.trim();

  await resolveAnnouncementRecipients({
    societyId,
    audienceType: doc.audienceType,
    targetWingIds: doc.targetWingIds.map(String),
    targetFlatIds: doc.targetFlatIds.map(String),
  });

  await doc.save();

  await writeAuditLog({
    action: 'ANNOUNCEMENT_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Announcement',
    targetId: announcementId,
    metadata: { fields: Object.keys(input) },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeAnnouncement(doc, { includeAdmin: true });
}

async function publishNow(
  doc: InstanceType<typeof AnnouncementModel>,
  societyId: string,
  actor: Actor,
) {
  const now = new Date();
  if (doc.expiresAt && doc.expiresAt.getTime() <= now.getTime()) {
    throw badRequest('Cannot publish an already expired announcement', 'ANNOUNCEMENT_EXPIRED');
  }

  doc.status = 'PUBLISHED';
  doc.publishedAt = now;
  doc.publishedByUserId = parseObjectId(actor.userId, 'userId');
  doc.deliveryState = 'PENDING';
  doc.scheduledAt = undefined;
  await doc.save();

  await writeAuditLog({
    action: 'ANNOUNCEMENT_PUBLISHED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Announcement',
    targetId: String(doc._id),
    metadata: {},
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  await deliverAnnouncementNotifications(String(doc._id));
  // Post-commit: bump feed meta + clear announcement pattern keys.
  await invalidateAnnouncementCaches(societyId);
  await cacheSet(
    CacheKeys.announcementsFeedMeta(societyId),
    { publishedAt: new Date().toISOString() },
    getEnv().CACHE_TTL_ANNOUNCEMENTS_SECONDS,
  );
  return AnnouncementModel.findById(doc._id);
}

export async function publishAnnouncement(
  societyId: string,
  announcementId: string,
  actor: Actor,
) {
  const doc = await AnnouncementModel.findOne({
    _id: parseObjectId(announcementId, 'announcementId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Announcement not found');
  if (doc.status !== 'DRAFT' && doc.status !== 'SCHEDULED') {
    throw conflict('Only DRAFT or SCHEDULED announcements can be published', 'INVALID_STATUS');
  }
  const updated = await publishNow(doc, societyId, actor);
  return serializeAnnouncement(updated!, { includeAdmin: true });
}

export async function scheduleAnnouncement(
  societyId: string,
  announcementId: string,
  scheduledAt: Date,
  actor: Actor,
) {
  if (scheduledAt.getTime() <= Date.now()) {
    throw badRequest('scheduledAt must be in the future', 'INVALID_SCHEDULE');
  }
  const doc = await AnnouncementModel.findOne({
    _id: parseObjectId(announcementId, 'announcementId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Announcement not found');
  if (doc.status !== 'DRAFT' && doc.status !== 'SCHEDULED') {
    throw conflict('Only DRAFT or SCHEDULED announcements can be scheduled', 'INVALID_STATUS');
  }
  if (doc.expiresAt && doc.expiresAt.getTime() <= scheduledAt.getTime()) {
    throw badRequest('expiresAt must be after scheduledAt', 'INVALID_EXPIRY');
  }

  doc.status = 'SCHEDULED';
  doc.scheduledAt = scheduledAt;
  doc.deliveryState = 'NOT_STARTED';
  await doc.save();

  await writeAuditLog({
    action: 'ANNOUNCEMENT_SCHEDULED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Announcement',
    targetId: announcementId,
    metadata: { scheduledAt: scheduledAt.toISOString() },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeAnnouncement(doc, { includeAdmin: true });
}

export async function cancelAnnouncement(
  societyId: string,
  announcementId: string,
  actor: Actor,
) {
  const doc = await AnnouncementModel.findOne({
    _id: parseObjectId(announcementId, 'announcementId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Announcement not found');
  if (doc.status !== 'DRAFT' && doc.status !== 'SCHEDULED') {
    throw conflict('Only DRAFT or SCHEDULED announcements can be cancelled', 'INVALID_STATUS');
  }
  doc.status = 'CANCELLED';
  await doc.save();

  await writeAuditLog({
    action: 'ANNOUNCEMENT_CANCELLED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Announcement',
    targetId: announcementId,
    metadata: {},
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeAnnouncement(doc, { includeAdmin: true });
}

export async function archiveAnnouncement(
  societyId: string,
  announcementId: string,
  actor: Actor,
) {
  const doc = await AnnouncementModel.findOne({
    _id: parseObjectId(announcementId, 'announcementId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Announcement not found');
  if (doc.status !== 'PUBLISHED') {
    throw conflict('Only PUBLISHED announcements can be archived', 'INVALID_STATUS');
  }
  doc.status = 'ARCHIVED';
  await doc.save();

  await writeAuditLog({
    action: 'ANNOUNCEMENT_ARCHIVED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Announcement',
    targetId: announcementId,
    metadata: {},
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeAnnouncement(doc, { includeAdmin: true });
}

export async function listAdminAnnouncements(
  societyId: string,
  query: {
    status?: AnnouncementStatus;
    category?: AnnouncementCategory;
    priority?: AnnouncementPriority;
    audienceType?: AudienceType;
    from?: Date;
    to?: Date;
    page?: number;
    limit?: number;
  },
) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (query.status) filter.status = query.status;
  if (query.category) filter.category = query.category;
  if (query.priority) filter.priority = query.priority;
  if (query.audienceType) filter.audienceType = query.audienceType;
  if (query.from || query.to) {
    filter.createdAt = {};
    if (query.from) (filter.createdAt as Record<string, Date>).$gte = query.from;
    if (query.to) (filter.createdAt as Record<string, Date>).$lte = query.to;
  }

  const [total, rows] = await Promise.all([
    AnnouncementModel.countDocuments(filter),
    AnnouncementModel.find(filter)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((r) => serializeAnnouncement(r, { includeAdmin: true })),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function getAdminAnnouncement(societyId: string, announcementId: string) {
  const doc = await AnnouncementModel.findOne({
    _id: parseObjectId(announcementId, 'announcementId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!doc) throw notFound('Announcement not found');
  return serializeAnnouncement(doc, { includeAdmin: true });
}

export async function getAnnouncementRecipientSummary(
  societyId: string,
  announcementId: string,
) {
  const doc = await AnnouncementModel.findOne({
    _id: parseObjectId(announcementId, 'announcementId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!doc) throw notFound('Announcement not found');

  const eligible = await resolveAnnouncementRecipients({
    societyId,
    audienceType: doc.audienceType,
    targetWingIds: doc.targetWingIds.map(String),
    targetFlatIds: doc.targetFlatIds.map(String),
  });

  const reads = await AnnouncementReadModel.countDocuments({
    announcementId: doc._id,
    isRead: true,
  });

  return {
    announcementId: String(doc._id),
    status: doc.status,
    deliveryState: doc.deliveryState,
    eligibleRecipientCount: eligible.length,
    notificationCreatedCount: doc.notificationCreatedCount ?? 0,
    readCount: reads,
    note: 'notificationCreatedCount is persistence count, not confirmed push delivery',
  };
}

export async function announcementSummary(societyId: string) {
  const match = { societyId: parseObjectId(societyId, 'societyId') };
  const byStatus = await AnnouncementModel.aggregate<{ _id: string; count: number }>([
    { $match: match },
    { $group: { _id: '$status', count: { $sum: 1 } } },
  ]);
  return {
    total: byStatus.reduce((n, r) => n + r.count, 0),
    byStatus: Object.fromEntries(byStatus.map((r) => [r._id, r.count])),
  };
}

export async function listResidentAnnouncements(
  societyId: string,
  userId: string,
  query: { page?: number; limit?: number; category?: AnnouncementCategory },
) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const now = new Date();

  // Uses societyId+status+publishedAt index; projection avoids loading unused admin fields.
  // Not cache-aside'd: audience filtering is user-specific; ObjectIds are not JSON-safe.
  const candidates = await AnnouncementModel.find({
    societyId: parseObjectId(societyId, 'societyId'),
    status: 'PUBLISHED',
    $or: [{ expiresAt: null }, { expiresAt: { $exists: false } }, { expiresAt: { $gt: now } }],
    ...(query.category ? { category: query.category } : {}),
  })
    .sort({ publishedAt: -1, createdAt: -1 })
    .select({
      audienceType: 1,
      targetWingIds: 1,
      targetFlatIds: 1,
      category: 1,
      priority: 1,
      title: 1,
      body: 1,
      publishedAt: 1,
      publishedByUserId: 1,
      createdAt: 1,
      updatedAt: 1,
      expiresAt: 1,
      attachments: 1,
      societyId: 1,
      status: 1,
      createdBy: 1,
    })
    .lean();

  const visible = [];
  for (const row of candidates) {
    const ok = await userCanViewAnnouncement({
      societyId,
      userId,
      audienceType: row.audienceType,
      targetWingIds: row.targetWingIds.map(String),
      targetFlatIds: row.targetFlatIds.map(String),
    });
    if (ok) visible.push(row);
  }

  const slice = visible.slice((page - 1) * limit, page * limit);
  const reads = await AnnouncementReadModel.find({
    userId,
    announcementId: { $in: slice.map((r) => r._id) },
  }).lean();
  const readMap = new Map(reads.map((r) => [String(r.announcementId), r.isRead]));

  return {
    items: slice.map((r) =>
      serializeAnnouncement(r, { isRead: readMap.get(String(r._id)) ?? false }),
    ),
    pagination: {
      page,
      limit,
      total: visible.length,
      totalPages: visible.length === 0 ? 0 : Math.ceil(visible.length / limit),
    },
  };
}

export async function getResidentAnnouncement(
  societyId: string,
  userId: string,
  announcementId: string,
) {
  const doc = await AnnouncementModel.findOne({
    _id: parseObjectId(announcementId, 'announcementId'),
    societyId: parseObjectId(societyId, 'societyId'),
    status: 'PUBLISHED',
  }).lean();
  if (!doc) throw notFound('Announcement not found');

  const now = new Date();
  if (doc.expiresAt && doc.expiresAt.getTime() <= now.getTime()) {
    throw notFound('Announcement not found');
  }

  const ok = await userCanViewAnnouncement({
    societyId,
    userId,
    audienceType: doc.audienceType,
    targetWingIds: doc.targetWingIds.map(String),
    targetFlatIds: doc.targetFlatIds.map(String),
  });
  if (!ok) throw forbidden('Announcement access denied', 'ANNOUNCEMENT_ACCESS_DENIED');

  const read = await AnnouncementReadModel.findOne({
    announcementId: doc._id,
    userId,
  }).lean();

  return serializeAnnouncement(doc, { isRead: read?.isRead ?? false });
}

export async function setAnnouncementReadState(
  societyId: string,
  userId: string,
  announcementId: string,
  isRead: boolean,
) {
  // Authorize via get
  await getResidentAnnouncement(societyId, userId, announcementId);

  const now = new Date();
  const existing = await AnnouncementReadModel.findOne({
    announcementId: parseObjectId(announcementId, 'announcementId'),
    userId: parseObjectId(userId, 'userId'),
  });

  if (!existing) {
    if (!isRead) {
      return { isRead: false };
    }
    await AnnouncementReadModel.create({
      societyId,
      announcementId,
      userId,
      isRead: true,
      firstReadAt: now,
      lastReadAt: now,
    });
    return { isRead: true };
  }

  if (isRead) {
    existing.isRead = true;
    if (!existing.firstReadAt) existing.firstReadAt = now;
    existing.lastReadAt = now;
  } else {
    existing.isRead = false;
  }
  await existing.save();
  return { isRead: existing.isRead };
}

export async function unreadAnnouncementCount(societyId: string, userId: string) {
  const list = await listResidentAnnouncements(societyId, userId, { page: 1, limit: 500 });
  const unread = list.items.filter((i) => !i.isRead).length;
  return { unreadCount: unread };
}

export async function addAnnouncementAttachment(
  societyId: string,
  announcementId: string,
  userId: string,
  file: { buffer: Buffer; originalname: string },
  actor: Actor,
) {
  const env = getEnv();
  const doc = await AnnouncementModel.findOne({
    _id: parseObjectId(announcementId, 'announcementId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Announcement not found');
  if (doc.status !== 'DRAFT' && doc.status !== 'SCHEDULED') {
    throw conflict('Attachments can only be added to DRAFT or SCHEDULED announcements', 'INVALID_STATUS');
  }
  if (doc.attachments.length >= env.ANNOUNCEMENT_ATTACHMENT_MAX_COUNT) {
    throw badRequest('Attachment limit reached', 'ATTACHMENT_LIMIT');
  }
  if (file.buffer.length > env.ANNOUNCEMENT_ATTACHMENT_MAX_BYTES) {
    throw badRequest('Attachment too large', 'ATTACHMENT_TOO_LARGE');
  }

  const mimeType = assertAnnouncementFileBuffer(
    file.buffer,
    env.ANNOUNCEMENT_ALLOWED_MIME_TYPES.split(',').map((s) => s.trim()),
  );

  const storage = getAnnouncementStorage();
  const stored = await storage.put({
    societyId,
    announcementId,
    buffer: file.buffer,
    mimeType,
  });

  const attachmentId = new Types.ObjectId();
  doc.attachments.push({
    _id: attachmentId,
    storageKey: stored.storageKey,
    mimeType,
    sizeBytes: stored.sizeBytes,
    originalFilename: file.originalname.slice(0, 255),
    uploadedByUserId: parseObjectId(userId, 'userId'),
    createdAt: new Date(),
  } as never);
  try {
    await doc.save();
  } catch (error) {
    await storage.delete(stored.storageKey).catch(() => undefined);
    throw error;
  }

  await writeAuditLog({
    action: 'ANNOUNCEMENT_ATTACHMENT_ADDED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Announcement',
    targetId: announcementId,
    metadata: { attachmentId: String(attachmentId), mimeType },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return {
    announcement: serializeAnnouncement(doc, { includeAdmin: true }),
    attachment: { id: String(attachmentId), mimeType, sizeBytes: stored.sizeBytes },
  };
}

export async function removeAnnouncementAttachment(
  societyId: string,
  announcementId: string,
  attachmentId: string,
  actor: Actor,
) {
  const doc = await AnnouncementModel.findOne({
    _id: parseObjectId(announcementId, 'announcementId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Announcement not found');
  if (doc.status !== 'DRAFT' && doc.status !== 'SCHEDULED') {
    throw conflict(
      'Attachments can only be removed from DRAFT or SCHEDULED announcements',
      'INVALID_STATUS',
    );
  }

  const idx = doc.attachments.findIndex((a) => String(a._id) === attachmentId);
  if (idx < 0) throw notFound('Attachment not found');
  const [removed] = doc.attachments.splice(idx, 1);
  await doc.save();
  if (removed?.storageKey) {
    await getAnnouncementStorage().delete(removed.storageKey).catch(() => undefined);
  }

  await writeAuditLog({
    action: 'ANNOUNCEMENT_ATTACHMENT_REMOVED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Announcement',
    targetId: announcementId,
    metadata: { attachmentId },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeAnnouncement(doc, { includeAdmin: true });
}

export async function getAnnouncementAttachmentFile(
  societyId: string,
  announcementId: string,
  attachmentId: string,
  userId: string,
  options: { asAdmin?: boolean } = {},
) {
  const doc = await AnnouncementModel.findOne({
    _id: parseObjectId(announcementId, 'announcementId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Announcement not found');

  if (!options.asAdmin) {
    await getResidentAnnouncement(societyId, userId, announcementId);
  }

  const att = doc.attachments.find((a) => String(a._id) === attachmentId);
  if (!att) throw notFound('Attachment not found');
  const buffer = await getAnnouncementStorage().get(att.storageKey);
  return {
    buffer,
    mimeType: att.mimeType,
    originalFilename: att.originalFilename,
  };
}
