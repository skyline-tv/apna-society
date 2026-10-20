import { Schema, model, type Document, type Types } from 'mongoose';

export const SHIFT_STATUSES = ['SCHEDULED', 'CANCELLED', 'COMPLETED'] as const;
export type ShiftStatus = (typeof SHIFT_STATUSES)[number];

export interface StaffShiftDocument extends Document {
  societyId: Types.ObjectId;
  staffId: Types.ObjectId;
  shiftDate: string; // local YYYY-MM-DD (start date)
  startTime: string; // HH:mm
  endTime: string; // HH:mm
  startAt: Date;
  endAt: Date;
  dutyLocation?: string;
  notes?: string;
  status: ShiftStatus;
  createdBy: Types.ObjectId;
  cancelledAt?: Date;
  cancelReason?: string;
  createdAt: Date;
  updatedAt: Date;
}

const staffShiftSchema = new Schema<StaffShiftDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    staffId: { type: Schema.Types.ObjectId, ref: 'Staff', required: true },
    shiftDate: { type: String, required: true },
    startTime: { type: String, required: true },
    endTime: { type: String, required: true },
    startAt: { type: Date, required: true },
    endAt: { type: Date, required: true },
    dutyLocation: { type: String, trim: true, maxlength: 200 },
    notes: { type: String, trim: true, maxlength: 2000 },
    status: { type: String, enum: SHIFT_STATUSES, required: true, default: 'SCHEDULED' },
    createdBy: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    cancelledAt: { type: Date },
    cancelReason: { type: String, trim: true, maxlength: 1000 },
  },
  { timestamps: true },
);

staffShiftSchema.index({ societyId: 1, staffId: 1, startAt: 1, endAt: 1 });
staffShiftSchema.index({ societyId: 1, shiftDate: 1, status: 1 });
staffShiftSchema.index({ societyId: 1, staffId: 1, status: 1, startAt: 1 });

export const StaffShiftModel = model<StaffShiftDocument>('StaffShift', staffShiftSchema);
