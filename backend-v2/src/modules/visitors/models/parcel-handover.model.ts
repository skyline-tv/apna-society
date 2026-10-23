import { Schema, model, type Document, type Types } from 'mongoose';

export const PARCEL_STATUSES = [
  'AWAITING_HANDOVER',
  'RECEIVED_BY_GUARD',
  'DELIVERED_TO_RESIDENT',
  'COLLECTED_BY_RESIDENT',
  'CANCELLED',
] as const;
export type ParcelStatus = (typeof PARCEL_STATUSES)[number];

export interface ParcelHandoverDocument extends Document {
  societyId: Types.ObjectId;
  flatId: Types.ObjectId;
  wingId?: Types.ObjectId;
  visitorLogId?: Types.ObjectId;
  recipientUserId: Types.ObjectId;
  courierName: string;
  courierPhone?: string;
  visitorType?: string;
  purpose?: string;
  requestedByGuardId: Types.ObjectId;
  authorizedByUserId: Types.ObjectId;
  receivedByGuardId?: Types.ObjectId;
  status: ParcelStatus;
  requestedAt: Date;
  authorizedAt: Date;
  receivedAt?: Date;
  deliveredAt?: Date;
  collectedAt?: Date;
  cancelledAt?: Date;
  cancellationReason?: string;
  notes?: string;
  flatNumberSnapshot: string;
  wingCodeSnapshot: string;
  createdAt: Date;
  updatedAt: Date;
}

const parcelHandoverSchema = new Schema<ParcelHandoverDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    flatId: { type: Schema.Types.ObjectId, ref: 'Flat', required: true },
    wingId: { type: Schema.Types.ObjectId, ref: 'Wing' },
    visitorLogId: { type: Schema.Types.ObjectId, ref: 'VisitorLog' },
    recipientUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    courierName: { type: String, required: true, trim: true, maxlength: 120 },
    courierPhone: { type: String, trim: true, maxlength: 32 },
    visitorType: { type: String, trim: true, maxlength: 40 },
    purpose: { type: String, trim: true, maxlength: 500 },
    requestedByGuardId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    authorizedByUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    receivedByGuardId: { type: Schema.Types.ObjectId, ref: 'User' },
    status: {
      type: String,
      enum: PARCEL_STATUSES,
      required: true,
      default: 'AWAITING_HANDOVER',
    },
    requestedAt: { type: Date, required: true },
    authorizedAt: { type: Date, required: true },
    receivedAt: { type: Date },
    deliveredAt: { type: Date },
    collectedAt: { type: Date },
    cancelledAt: { type: Date },
    cancellationReason: { type: String, trim: true, maxlength: 500 },
    notes: { type: String, trim: true, maxlength: 2000 },
    flatNumberSnapshot: { type: String, required: true },
    wingCodeSnapshot: { type: String, required: true },
  },
  { timestamps: true },
);

parcelHandoverSchema.index({ societyId: 1, createdAt: -1 });
parcelHandoverSchema.index({ societyId: 1, recipientUserId: 1, createdAt: -1 });
parcelHandoverSchema.index({ societyId: 1, requestedByGuardId: 1, status: 1 });
parcelHandoverSchema.index({ societyId: 1, status: 1, createdAt: -1 });
parcelHandoverSchema.index({ societyId: 1, flatId: 1, createdAt: -1 });
parcelHandoverSchema.index(
  { visitorLogId: 1 },
  { unique: true, sparse: true },
);

export const ParcelHandoverModel = model<ParcelHandoverDocument>(
  'ParcelHandover',
  parcelHandoverSchema,
);
