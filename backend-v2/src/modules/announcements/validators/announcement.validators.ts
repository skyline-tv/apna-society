import { z } from 'zod';
import { isObjectId } from '../../../utils/object-id';
import {
  ANNOUNCEMENT_CATEGORIES,
  ANNOUNCEMENT_PRIORITIES,
  ANNOUNCEMENT_STATUSES,
  AUDIENCE_TYPES,
} from '../models/announcement.model';
import { NOTIFICATION_TYPES } from '../../notifications/models/notification.model';

const objectId = z.string().refine(isObjectId, 'Must be a valid ObjectId');

export const createAnnouncementSchema = z
  .object({
    title: z.string().trim().min(3).max(200),
    body: z.string().trim().min(3).max(10_000),
    category: z.enum(ANNOUNCEMENT_CATEGORIES),
    priority: z.enum(ANNOUNCEMENT_PRIORITIES).optional(),
    audienceType: z.enum(AUDIENCE_TYPES),
    targetWingIds: z.array(objectId).max(100).optional(),
    targetFlatIds: z.array(objectId).max(500).optional(),
    expiresAt: z.coerce.date().optional(),
    adminNotes: z.string().trim().max(4000).optional(),
  })
  .strict()
  .superRefine((data, ctx) => {
    if (data.audienceType === 'WING' && !(data.targetWingIds?.length)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'targetWingIds required for WING audience',
        path: ['targetWingIds'],
      });
    }
    if (data.audienceType === 'SELECTED_FLATS' && !(data.targetFlatIds?.length)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'targetFlatIds required for SELECTED_FLATS audience',
        path: ['targetFlatIds'],
      });
    }
  });

export type CreateAnnouncementInput = z.infer<typeof createAnnouncementSchema>;

export const updateAnnouncementSchema = z
  .object({
    title: z.string().trim().min(3).max(200).optional(),
    body: z.string().trim().min(3).max(10_000).optional(),
    category: z.enum(ANNOUNCEMENT_CATEGORIES).optional(),
    priority: z.enum(ANNOUNCEMENT_PRIORITIES).optional(),
    audienceType: z.enum(AUDIENCE_TYPES).optional(),
    targetWingIds: z.array(objectId).max(100).optional(),
    targetFlatIds: z.array(objectId).max(500).optional(),
    expiresAt: z.coerce.date().nullable().optional(),
    adminNotes: z.string().trim().max(4000).optional(),
  })
  .strict();

export type UpdateAnnouncementInput = z.infer<typeof updateAnnouncementSchema>;

export const announcementIdParamSchema = z.object({ announcementId: objectId });

export const announcementAttachmentParamSchema = z.object({
  announcementId: objectId,
  attachmentId: objectId,
});

export const scheduleAnnouncementSchema = z
  .object({
    scheduledAt: z.coerce.date(),
  })
  .strict();

export const listAdminAnnouncementsQuerySchema = z.object({
  status: z.enum(ANNOUNCEMENT_STATUSES).optional(),
  category: z.enum(ANNOUNCEMENT_CATEGORIES).optional(),
  priority: z.enum(ANNOUNCEMENT_PRIORITIES).optional(),
  audienceType: z.enum(AUDIENCE_TYPES).optional(),
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export const listResidentAnnouncementsQuerySchema = z.object({
  category: z.enum(ANNOUNCEMENT_CATEGORIES).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export const listNotificationsQuerySchema = z.object({
  isRead: z
    .enum(['true', 'false'])
    .optional()
    .transform((v) => (v === undefined ? undefined : v === 'true')),
  type: z.enum(NOTIFICATION_TYPES).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export const notificationIdParamSchema = z.object({ notificationId: objectId });
