import { Schema, model, type Document, type Types } from 'mongoose';
import { VEHICLE_TYPES, type VehicleType } from './vehicle.model';

export interface ParkingSlotDocument extends Document {
  societyId: Types.ObjectId;
  slotNumber: string;
  parkingType: VehicleType;
  locationDescription?: string;
  isActive: boolean;
  deactivatedAt?: Date;
  deactivationReason?: string;
  createdAt: Date;
  updatedAt: Date;
}

const parkingSlotSchema = new Schema<ParkingSlotDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    slotNumber: { type: String, required: true, trim: true, uppercase: true, maxlength: 32 },
    parkingType: { type: String, enum: VEHICLE_TYPES, required: true },
    locationDescription: { type: String, trim: true, maxlength: 200 },
    isActive: { type: Boolean, required: true, default: true },
    deactivatedAt: { type: Date },
    deactivationReason: { type: String, trim: true, maxlength: 500 },
  },
  { timestamps: true },
);

parkingSlotSchema.index(
  { societyId: 1, slotNumber: 1 },
  {
    unique: true,
    partialFilterExpression: { isActive: true },
  },
);
parkingSlotSchema.index({ societyId: 1, parkingType: 1, isActive: 1 });

export const ParkingSlotModel = model<ParkingSlotDocument>('ParkingSlot', parkingSlotSchema);
