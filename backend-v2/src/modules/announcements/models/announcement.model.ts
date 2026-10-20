import { Schema, model, type Document, type Types } from 'mongoose';

export const ANNOUNCEMENT_CATEGORIES = [
  'GENERAL',
  'MAINTENANCE',
  'WATER_SUPPLY',
  'ELECTRICITY',
  'SECURITY',
  'EVENT',
  'EMERGENCY',
  'MEETING',
  'PARKING',
  'OTHER',
] as const;
export type AnnouncementCategory = (typeof ANNOUNCEMENT_CATEGORIES)[number];

export const ANNOUNCEMENT_PRIORITIES = ['NORMAL', 'IMPORTANT', 'URGENT'] as const;
export type AnnouncementPriority = (typeof ANNOUNCEMENT_PRIORITIES)[number];

export const ANNOUNCEMENT_STATUSES = [
  'DRAFT',
  'SCHEDULED',
  'PUBLISHED',
  'ARCHIVED',
  'CANCELLED',
] as const;
export type AnnouncementStatus = (typeof ANNOUNCEMENT_STATUSES)[number];

export const AUDIENCE_TYPES = ['ALL_RESIDENTS', 'WING', 'SELECTED_FLATS'] as const;
export type AudienceType = (typeof AUDIENCE_TYPES)[number];

export const DELIVERY_STATES = ['NOT_STARTED', 'PENDING', 'COMPLETE', 'FAILED'] as const;
export type DeliveryState = (typeof DELIVERY_STATES)[number];

export interface AnnouncementAttachment {
  _id: Types.ObjectId;
  storageKey: string;
  mimeType: string;
  sizeBytes: number;
  originalFilename: string;
  uploadedByUserId: Types.ObjectId;
  createdAt: Date;
}

export interface AnnouncementDocument extends Document {
  societyId: Types.ObjectId;
  title: string;
  body: string;
  category: AnnouncementCategory;
  priority: AnnouncementPriority;
  audienceType: AudienceType;
  targetWingIds: Types.ObjectId[];
  targetFlatIds: Types.ObjectId[];
  attachments: AnnouncementAttachment[];
  status: AnnouncementStatus;
  publishedByUserId?: Types.ObjectId;
  publishedAt?: Date;
  scheduledAt?: Date;
  expiresAt?: Date;
  deliveryState: DeliveryState;
  eligibleRecipientCount?: number;
  notificationCreatedCount?: number;
  createdBy: Types.ObjectId;
  /** Admin-only internal note — never exposed to residents. */
  adminNotes?: string;
  createdAt: Date;
  updatedAt: Date;
}

const attachmentSchema = new Schema<AnnouncementAttachment>(
  {
    storageKey: { type: String, required: true },
    mimeType: { type: String, required: true },
    sizeBytes: { type: Number, required: true },
    originalFilename: { type: String, required: true, maxlength: 255 },
    uploadedByUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    createdAt: { type: Date, required: true, default: Date.now },
  },
  { _id: true },
);

const announcementSchema = new Schema<AnnouncementDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    title: { type: String, required: true, trim: true, maxlength: 200 },
    body: { type: String, required: true, trim: true, maxlength: 10_000 },
    category: { type: String, enum: ANNOUNCEMENT_CATEGORIES, required: true },
    priority: { type: String, enum: ANNOUNCEMENT_PRIORITIES, required: true, default: 'NORMAL' },
    audienceType: { type: String, enum: AUDIENCE_TYPES, required: true },
    targetWingIds: { type: [{ type: Schema.Types.ObjectId, ref: 'Wing' }], default: [] },
    targetFlatIds: { type: [{ type: Schema.Types.ObjectId, ref: 'Flat' }], default: [] },
    attachments: { type: [attachmentSchema], default: [] },
    status: { type: String, enum: ANNOUNCEMENT_STATUSES, required: true, default: 'DRAFT' },
    publishedByUserId: { type: Schema.Types.ObjectId, ref: 'User' },
    publishedAt: { type: Date },
    scheduledAt: { type: Date },
    expiresAt: { type: Date },
    deliveryState: {
      type: String,
      enum: DELIVERY_STATES,
      required: true,
      default: 'NOT_STARTED',
    },
    eligibleRecipientCount: { type: Number, min: 0 },
    notificationCreatedCount: { type: Number, min: 0 },
    createdBy: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    adminNotes: { type: String, trim: true, maxlength: 4000 },
  },
  { timestamps: true },
);

announcementSchema.index({ societyId: 1, status: 1, createdAt: -1 });
announcementSchema.index({ societyId: 1, status: 1, scheduledAt: 1 });
announcementSchema.index({ societyId: 1, category: 1, status: 1 });
announcementSchema.index({ societyId: 1, priority: 1, status: 1 });
announcementSchema.index({ status: 1, scheduledAt: 1, deliveryState: 1 });
announcementSchema.index({ status: 1, deliveryState: 1, publishedAt: 1 });
// Resident / admin published feeds sorted by publishedAt
announcementSchema.index({ societyId: 1, status: 1, publishedAt: -1 });

export const AnnouncementModel = model<AnnouncementDocument>('Announcement', announcementSchema);
