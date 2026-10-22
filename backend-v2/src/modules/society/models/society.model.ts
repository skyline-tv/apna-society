import { Schema, model, type Document, type Types } from 'mongoose';
import { DEFAULT_TIMEZONE } from '../../../config/constants';

export interface SocietyDocument extends Document {
  name: string;
  code: string;
  address?: string;
  city?: string;
  state?: string;
  pincode?: string;
  contactEmail?: string;
  contactPhone?: string;
  isActive: boolean;
  config: {
    currency: string;
    timezone: string;
    maintenanceDayOfMonth: number;
    /** Simple annual overdue interest in basis points. 2400 = 24% p.a. */
    annualInterestRateBps: number;
  };
  createdAt: Date;
  updatedAt: Date;
}

const societySchema = new Schema<SocietyDocument>(
  {
    name: { type: String, required: true, trim: true, maxlength: 200 },
    code: { type: String, required: true, unique: true, uppercase: true, trim: true, maxlength: 64 },
    address: { type: String, trim: true, maxlength: 500 },
    city: { type: String, trim: true, maxlength: 120 },
    state: { type: String, trim: true, maxlength: 120 },
    pincode: { type: String, trim: true, maxlength: 16 },
    contactEmail: { type: String, trim: true, lowercase: true, maxlength: 254 },
    contactPhone: { type: String, trim: true, maxlength: 32 },
    isActive: { type: Boolean, default: true },
    config: {
      currency: { type: String, default: 'INR' },
      timezone: { type: String, default: DEFAULT_TIMEZONE },
      maintenanceDayOfMonth: { type: Number, default: 1, min: 1, max: 28 },
      annualInterestRateBps: { type: Number, default: 2400, min: 0, max: 100_000 },
    },
  },
  { timestamps: true },
);

societySchema.index({ isActive: 1, name: 1 });

export const SocietyModel = model<SocietyDocument>('Society', societySchema);

export type SocietyId = Types.ObjectId;
