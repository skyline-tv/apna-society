import { Schema, model, type Document, type Types } from 'mongoose';

export const FACILITY_CATEGORIES = [
  'CLUBHOUSE',
  'GYM',
  'SWIMMING_POOL',
  'COMMUNITY_HALL',
  'GARDEN',
  'SPORTS_COURT',
  'INDOOR_GAMES',
  'OTHER',
] as const;
export type FacilityCategory = (typeof FACILITY_CATEGORIES)[number];

export const WEEKDAYS = [
  'MONDAY',
  'TUESDAY',
  'WEDNESDAY',
  'THURSDAY',
  'FRIDAY',
  'SATURDAY',
  'SUNDAY',
] as const;
export type Weekday = (typeof WEEKDAYS)[number];

export interface FacilityDocument extends Document {
  societyId: Types.ObjectId;
  name: string;
  description?: string;
  category: FacilityCategory;
  location?: string;
  capacity: number;
  bookingRequired: boolean;
  /** When true, new bookings start PENDING until admin approval. */
  requiresApproval: boolean;
  maxBookingDurationMinutes: number;
  openingTime: string; // HH:mm
  closingTime: string; // HH:mm
  availableDays: Weekday[];
  isActive: boolean;
  bookingFeePaise: number;
  createdBy: Types.ObjectId;
  deactivatedAt?: Date;
  /** Internal optimistic lock counter for concurrent booking capacity serialization. */
  __bookingLock?: number;
  createdAt: Date;
  updatedAt: Date;
}

const facilitySchema = new Schema<FacilityDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    name: { type: String, required: true, trim: true, maxlength: 120 },
    description: { type: String, trim: true, maxlength: 2000 },
    category: { type: String, enum: FACILITY_CATEGORIES, required: true },
    location: { type: String, trim: true, maxlength: 200 },
    capacity: { type: Number, required: true, min: 1, max: 10_000 },
    bookingRequired: { type: Boolean, required: true, default: true },
    requiresApproval: { type: Boolean, required: true, default: true },
    maxBookingDurationMinutes: { type: Number, required: true, min: 15, max: 24 * 60 },
    openingTime: { type: String, required: true },
    closingTime: { type: String, required: true },
    availableDays: {
      type: [{ type: String, enum: WEEKDAYS }],
      required: true,
      validate: [(v: string[]) => v.length > 0, 'At least one available day'],
    },
    isActive: { type: Boolean, required: true, default: true },
    bookingFeePaise: { type: Number, required: true, default: 0, min: 0 },
    createdBy: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    deactivatedAt: { type: Date },
    __bookingLock: { type: Number, default: 0, select: false },
  },
  { timestamps: true },
);

facilitySchema.index({ societyId: 1, name: 1 }, { unique: true });
facilitySchema.index({ societyId: 1, isActive: 1, category: 1 });

export const FacilityModel = model<FacilityDocument>('Facility', facilitySchema);
