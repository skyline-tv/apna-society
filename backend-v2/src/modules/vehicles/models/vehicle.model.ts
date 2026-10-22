import { Schema, model, type Document, type Types } from 'mongoose';

export const VEHICLE_TYPES = ['TWO_WHEELER', 'FOUR_WHEELER', 'OTHER'] as const;
export type VehicleType = (typeof VEHICLE_TYPES)[number];

export interface VehicleDocument extends Document {
  societyId: Types.ObjectId;
  flatId: Types.ObjectId;
  registeredUserId: Types.ObjectId;
  vehicleType: VehicleType;
  registrationNumber: string;
  make?: string;
  /** Stored as vehicleModel to avoid clashing with Mongoose Document#model. */
  vehicleModel?: string;
  colour?: string;
  /** Free-text parking bay / slot label assigned by admin. */
  parkingNumber?: string;
  isActive: boolean;
  deactivatedAt?: Date;
  deactivationReason?: string;
  createdAt: Date;
  updatedAt: Date;
}

const vehicleSchema = new Schema<VehicleDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    flatId: { type: Schema.Types.ObjectId, ref: 'Flat', required: true },
    registeredUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    vehicleType: { type: String, enum: VEHICLE_TYPES, required: true },
    registrationNumber: { type: String, required: true, trim: true, uppercase: true, maxlength: 16 },
    make: { type: String, trim: true, maxlength: 80 },
    vehicleModel: { type: String, trim: true, maxlength: 80 },
    colour: { type: String, trim: true, maxlength: 40 },
    parkingNumber: { type: String, trim: true, maxlength: 32 },
    isActive: { type: Boolean, required: true, default: true },
    deactivatedAt: { type: Date },
    deactivationReason: { type: String, trim: true, maxlength: 500 },
  },
  { timestamps: true },
);

vehicleSchema.index(
  { societyId: 1, registrationNumber: 1 },
  {
    unique: true,
    partialFilterExpression: { isActive: true },
  },
);
vehicleSchema.index({ societyId: 1, flatId: 1, isActive: 1 });
vehicleSchema.index({ societyId: 1, registeredUserId: 1, isActive: 1 });

export const VehicleModel = model<VehicleDocument>('Vehicle', vehicleSchema);
