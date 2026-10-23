import { Schema, model, type Document, type Types } from 'mongoose';

export const NOTIFICATION_TYPES = [
  'ANNOUNCEMENT',
  'BILL_GENERATED',
  'BILL_OVERDUE',
  'PAYMENT_SUCCESS',
  'PAYMENT_FAILED',
  'VISITOR_REQUEST',
  'VISITOR_APPROVED',
  'VISITOR_REJECTED',
  'VISITOR_ENTERED',
  'VISITOR_EXPIRED',
  'PARCEL_AWAITING_HANDOVER',
  'PARCEL_RECEIVED',
  'COMPLAINT_ASSIGNED',
  'COMPLAINT_STATUS_CHANGED',
  'FACILITY_BOOKING_APPROVED',
  'FACILITY_BOOKING_REJECTED',
  'FACILITY_BOOKING_CANCELLED',
  'STAFF_SHIFT_ASSIGNED',
  'SYSTEM',
] as const;
export type NotificationType = (typeof NOTIFICATION_TYPES)[number];

export const PUSH_DELIVERY_STATUSES = [
  'PENDING',
  'SENT',
  'PARTIAL',
  'FAILED',
  'SKIPPED',
  'NOT_CONFIGURED',
] as const;
export type PushDeliveryStatus = (typeof PUSH_DELIVERY_STATUSES)[number];

export interface NotificationDocument extends Document {
  societyId: Types.ObjectId;
  recipientUserId: Types.ObjectId;
  type: NotificationType;
  title: string;
  body: string;
  relatedEntityType?: string;
  relatedEntityId?: string;
  isRead: boolean;
  readAt?: Date;
  /** Unique per recipient event to prevent duplicates on retries. */
  idempotencyKey: string;
  metadata?: Record<string, unknown>;
  pushStatus: PushDeliveryStatus;
  pushAttemptCount: number;
  pushLastAttemptAt?: Date;
  pushSentAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

const notificationSchema = new Schema<NotificationDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    recipientUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    type: { type: String, enum: NOTIFICATION_TYPES, required: true },
    title: { type: String, required: true, trim: true, maxlength: 200 },
    body: { type: String, required: true, trim: true, maxlength: 2000 },
    relatedEntityType: { type: String, trim: true, maxlength: 80 },
    relatedEntityId: { type: String, trim: true, maxlength: 64 },
    isRead: { type: Boolean, required: true, default: false },
    readAt: { type: Date },
    idempotencyKey: { type: String, required: true, maxlength: 200 },
    metadata: { type: Schema.Types.Mixed },
    pushStatus: {
      type: String,
      enum: PUSH_DELIVERY_STATUSES,
      required: true,
      default: 'PENDING',
    },
    pushAttemptCount: { type: Number, required: true, default: 0, min: 0 },
    pushLastAttemptAt: { type: Date },
    pushSentAt: { type: Date },
  },
  { timestamps: true },
);

notificationSchema.index({ idempotencyKey: 1 }, { unique: true });
notificationSchema.index({ societyId: 1, recipientUserId: 1, createdAt: -1 });
notificationSchema.index({ societyId: 1, recipientUserId: 1, isRead: 1, createdAt: -1 });
notificationSchema.index({ societyId: 1, type: 1, createdAt: -1 });
notificationSchema.index({ pushStatus: 1, pushAttemptCount: 1, pushLastAttemptAt: 1 });

export const NotificationModel = model<NotificationDocument>('Notification', notificationSchema);
