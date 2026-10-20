import { Schema, model, type Document, type Types } from 'mongoose';

export const STAFF_CATEGORIES = [
  'SECURITY',
  'HOUSEKEEPING',
  'MAINTENANCE',
  'ELECTRICIAN',
  'PLUMBER',
  'GARDENER',
  'LIFT_OPERATOR',
  'OTHER',
] as const;
export type StaffCategory = (typeof STAFF_CATEGORIES)[number];

export const EMPLOYMENT_TYPES = ['PERMANENT', 'CONTRACT', 'TEMPORARY'] as const;
export type EmploymentType = (typeof EMPLOYMENT_TYPES)[number];

export const EMPLOYMENT_STATUSES = ['ACTIVE', 'INACTIVE', 'TERMINATED'] as const;
export type EmploymentStatus = (typeof EMPLOYMENT_STATUSES)[number];

export interface StaffDocument extends Document {
  societyId: Types.ObjectId;
  fullName: string;
  phone: string;
  phoneNormalized: string;
  email?: string;
  category: StaffCategory;
  employmentType: EmploymentType;
  joiningDate: string; // YYYY-MM-DD society local
  employmentStatus: EmploymentStatus;
  address?: string;
  emergencyContactName?: string;
  emergencyContactPhone?: string;
  notes?: string; // admin only
  linkedUserId?: Types.ObjectId;
  createdBy: Types.ObjectId;
  deactivatedAt?: Date;
  terminatedAt?: Date;
  statusReason?: string;
  /** Internal lock counter for concurrent shift overlap serialization. */
  __shiftLock?: number;
  createdAt: Date;
  updatedAt: Date;
}

const staffSchema = new Schema<StaffDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    fullName: { type: String, required: true, trim: true, maxlength: 120 },
    phone: { type: String, required: true, trim: true, maxlength: 32 },
    phoneNormalized: { type: String, required: true, trim: true, maxlength: 32 },
    email: { type: String, trim: true, lowercase: true, maxlength: 254 },
    category: { type: String, enum: STAFF_CATEGORIES, required: true },
    employmentType: { type: String, enum: EMPLOYMENT_TYPES, required: true },
    joiningDate: { type: String, required: true },
    employmentStatus: {
      type: String,
      enum: EMPLOYMENT_STATUSES,
      required: true,
      default: 'ACTIVE',
    },
    address: { type: String, trim: true, maxlength: 500 },
    emergencyContactName: { type: String, trim: true, maxlength: 120 },
    emergencyContactPhone: { type: String, trim: true, maxlength: 32 },
    notes: { type: String, trim: true, maxlength: 4000 },
    linkedUserId: { type: Schema.Types.ObjectId, ref: 'User' },
    createdBy: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    deactivatedAt: { type: Date },
    terminatedAt: { type: Date },
    statusReason: { type: String, trim: true, maxlength: 1000 },
    __shiftLock: { type: Number, default: 0, select: false },
  },
  { timestamps: true },
);

staffSchema.index(
  { societyId: 1, phoneNormalized: 1 },
  { unique: true, partialFilterExpression: { employmentStatus: 'ACTIVE' } },
);
staffSchema.index({ societyId: 1, employmentStatus: 1, category: 1 });
staffSchema.index({ societyId: 1, linkedUserId: 1 });
staffSchema.index({ societyId: 1, joiningDate: 1 });

export const StaffModel = model<StaffDocument>('Staff', staffSchema);
