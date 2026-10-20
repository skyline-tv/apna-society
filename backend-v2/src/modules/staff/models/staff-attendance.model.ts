import { Schema, model, type Document, type Types } from 'mongoose';

export const ATTENDANCE_STATUSES = ['PRESENT', 'ABSENT', 'HALF_DAY', 'ON_LEAVE'] as const;
export type AttendanceStatus = (typeof ATTENDANCE_STATUSES)[number];

export interface StaffAttendanceDocument extends Document {
  societyId: Types.ObjectId;
  staffId: Types.ObjectId;
  localDate: string; // YYYY-MM-DD society timezone
  checkInAt?: Date;
  checkOutAt?: Date;
  status: AttendanceStatus;
  recordedByUserId: Types.ObjectId;
  notes?: string;
  correctionHistory: Array<{
    correctedByUserId: Types.ObjectId;
    correctedAt: Date;
    previous: Record<string, unknown>;
    reason: string;
  }>;
  createdAt: Date;
  updatedAt: Date;
}

const correctionSchema = new Schema(
  {
    correctedByUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    correctedAt: { type: Date, required: true },
    previous: { type: Schema.Types.Mixed, required: true },
    reason: { type: String, required: true, maxlength: 1000 },
  },
  { _id: false },
);

const staffAttendanceSchema = new Schema<StaffAttendanceDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    staffId: { type: Schema.Types.ObjectId, ref: 'Staff', required: true },
    localDate: { type: String, required: true },
    checkInAt: { type: Date },
    checkOutAt: { type: Date },
    status: { type: String, enum: ATTENDANCE_STATUSES, required: true },
    recordedByUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    notes: { type: String, trim: true, maxlength: 1000 },
    correctionHistory: { type: [correctionSchema], default: [] },
  },
  { timestamps: true },
);

staffAttendanceSchema.index({ societyId: 1, staffId: 1, localDate: 1 }, { unique: true });
staffAttendanceSchema.index({ societyId: 1, localDate: 1, status: 1 });
staffAttendanceSchema.index({ societyId: 1, staffId: 1, createdAt: -1 });

export const StaffAttendanceModel = model<StaffAttendanceDocument>(
  'StaffAttendance',
  staffAttendanceSchema,
);
