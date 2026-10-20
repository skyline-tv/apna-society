import { Schema, model, type Document, type Types } from 'mongoose';

export const BOOKING_STATUSES = [
  'PENDING',
  'CONFIRMED',
  'REJECTED',
  'CANCELLED',
  'COMPLETED',
] as const;
export type BookingStatus = (typeof BOOKING_STATUSES)[number];

export interface FacilityBookingDocument extends Document {
  societyId: Types.ObjectId;
  facilityId: Types.ObjectId;
  flatId: Types.ObjectId;
  bookedByUserId: Types.ObjectId;
  bookingDate: string; // local YYYY-MM-DD
  startTime: string;
  endTime: string;
  startAt: Date;
  endAt: Date;
  status: BookingStatus;
  feePaiseSnapshot: number;
  /** Never set true in Phase 8 without a verified payment flow. */
  feePaid: boolean;
  paymentReference?: string;
  adminNotes?: string;
  rejectionReason?: string;
  cancellationReason?: string;
  expiresAt?: Date; // for PENDING
  createdAt: Date;
  updatedAt: Date;
}

const facilityBookingSchema = new Schema<FacilityBookingDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    facilityId: { type: Schema.Types.ObjectId, ref: 'Facility', required: true },
    flatId: { type: Schema.Types.ObjectId, ref: 'Flat', required: true },
    bookedByUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    bookingDate: { type: String, required: true },
    startTime: { type: String, required: true },
    endTime: { type: String, required: true },
    startAt: { type: Date, required: true },
    endAt: { type: Date, required: true },
    status: { type: String, enum: BOOKING_STATUSES, required: true, default: 'PENDING' },
    feePaiseSnapshot: { type: Number, required: true, default: 0, min: 0 },
    feePaid: { type: Boolean, required: true, default: false },
    paymentReference: { type: String, trim: true, maxlength: 120 },
    adminNotes: { type: String, trim: true, maxlength: 4000 },
    rejectionReason: { type: String, trim: true, maxlength: 1000 },
    cancellationReason: { type: String, trim: true, maxlength: 1000 },
    expiresAt: { type: Date },
  },
  { timestamps: true },
);

facilityBookingSchema.index({ societyId: 1, facilityId: 1, startAt: 1, endAt: 1, status: 1 });
facilityBookingSchema.index({ societyId: 1, bookedByUserId: 1, createdAt: -1 });
facilityBookingSchema.index({ societyId: 1, flatId: 1, createdAt: -1 });
facilityBookingSchema.index({ societyId: 1, status: 1, expiresAt: 1 });
facilityBookingSchema.index({ societyId: 1, bookingDate: 1, status: 1 });

export const FacilityBookingModel = model<FacilityBookingDocument>(
  'FacilityBooking',
  facilityBookingSchema,
);
