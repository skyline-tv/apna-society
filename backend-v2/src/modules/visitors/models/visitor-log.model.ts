import { Schema, model, type Document, type Types } from 'mongoose';

export const VISITOR_TYPES = [
  'GUEST',
  'DELIVERY',
  'CAB',
  'COURIER',
  'SERVICE_PROVIDER',
  'OTHER',
] as const;
export type VisitorType = (typeof VISITOR_TYPES)[number];

export const APPROVAL_STATUSES = [
  'PENDING',
  'APPROVED',
  'REJECTED',
  'EXPIRED',
  'CANCELLED',
] as const;
export type ApprovalStatus = (typeof APPROVAL_STATUSES)[number];

export const ENTRY_STATUSES = ['NOT_ENTERED', 'ENTERED', 'EXITED'] as const;
export type EntryStatus = (typeof ENTRY_STATUSES)[number];

export interface VisitorLogDocument extends Document {
  societyId: Types.ObjectId;
  flatId: Types.ObjectId;
  wingId?: Types.ObjectId;
  visitorName: string;
  visitorPhone: string;
  /** Optional; used for entry OTP email delivery when present. */
  visitorEmail?: string;
  visitorType: VisitorType;
  purpose: string;
  vehicleNumber?: string;
  numberOfVisitors: number;
  requestedByGuardId: Types.ObjectId;
  assignedResidentUserId: Types.ObjectId;
  assignedResidentRole: 'OWNER' | 'TENANT';
  approvalStatus: ApprovalStatus;
  entryStatus: EntryStatus;
  entryOtpHash?: string;
  entryOtpExpiresAt?: Date;
  otpAttempts: number;
  approvedAt?: Date;
  rejectedAt?: Date;
  entryAt?: Date;
  exitAt?: Date;
  checkedInBy?: Types.ObjectId;
  checkedOutBy?: Types.ObjectId;
  rejectionReason?: string;
  notes?: string;
  flatNumberSnapshot: string;
  wingCodeSnapshot: string;
  expiredAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

const visitorLogSchema = new Schema<VisitorLogDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    flatId: { type: Schema.Types.ObjectId, ref: 'Flat', required: true },
    wingId: { type: Schema.Types.ObjectId, ref: 'Wing' },
    visitorName: { type: String, required: true, trim: true, maxlength: 120 },
    visitorPhone: { type: String, required: true, trim: true, maxlength: 32 },
    visitorEmail: { type: String, trim: true, lowercase: true, maxlength: 254 },
    visitorType: { type: String, enum: VISITOR_TYPES, required: true },
    purpose: { type: String, required: true, trim: true, maxlength: 500 },
    vehicleNumber: { type: String, trim: true, maxlength: 32 },
    numberOfVisitors: { type: Number, required: true, min: 1, max: 50, default: 1 },
    requestedByGuardId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    assignedResidentUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    assignedResidentRole: { type: String, enum: ['OWNER', 'TENANT'], required: true },
    approvalStatus: {
      type: String,
      enum: APPROVAL_STATUSES,
      required: true,
      default: 'PENDING',
    },
    entryStatus: {
      type: String,
      enum: ENTRY_STATUSES,
      required: true,
      default: 'NOT_ENTERED',
    },
    entryOtpHash: { type: String },
    entryOtpExpiresAt: { type: Date },
    otpAttempts: { type: Number, required: true, default: 0, min: 0 },
    approvedAt: { type: Date },
    rejectedAt: { type: Date },
    entryAt: { type: Date },
    exitAt: { type: Date },
    checkedInBy: { type: Schema.Types.ObjectId, ref: 'User' },
    checkedOutBy: { type: Schema.Types.ObjectId, ref: 'User' },
    rejectionReason: { type: String, trim: true, maxlength: 500 },
    notes: { type: String, trim: true, maxlength: 2000 },
    flatNumberSnapshot: { type: String, required: true },
    wingCodeSnapshot: { type: String, required: true },
    expiredAt: { type: Date },
  },
  { timestamps: true },
);

visitorLogSchema.index({ societyId: 1, createdAt: -1 });
visitorLogSchema.index({ societyId: 1, approvalStatus: 1, createdAt: -1 });
visitorLogSchema.index({ societyId: 1, entryStatus: 1, createdAt: -1 });
visitorLogSchema.index({ societyId: 1, flatId: 1, createdAt: -1 });
visitorLogSchema.index({ societyId: 1, assignedResidentUserId: 1, approvalStatus: 1 });
visitorLogSchema.index({ societyId: 1, requestedByGuardId: 1, createdAt: -1 });
visitorLogSchema.index({ societyId: 1, visitorPhone: 1, createdAt: -1 });
visitorLogSchema.index({ societyId: 1, visitorName: 'text' });
visitorLogSchema.index({
  societyId: 1,
  approvalStatus: 1,
  entryStatus: 1,
  entryOtpExpiresAt: 1,
});
// Wing-scoped history + entry timeline
visitorLogSchema.index({ societyId: 1, wingId: 1, createdAt: -1 });
visitorLogSchema.index({ societyId: 1, entryAt: -1 });

export const VisitorLogModel = model<VisitorLogDocument>('VisitorLog', visitorLogSchema);
