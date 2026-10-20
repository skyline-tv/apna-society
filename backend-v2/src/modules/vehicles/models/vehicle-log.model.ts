import { Schema, model, type Document, type Types } from 'mongoose';
import { VEHICLE_TYPES, type VehicleType } from './vehicle.model';

export const VEHICLE_LOG_STATUSES = ['INSIDE', 'EXITED'] as const;
export type VehicleLogStatus = (typeof VEHICLE_LOG_STATUSES)[number];

export interface VehicleLogDocument extends Document {
  societyId: Types.ObjectId;
  vehicleId?: Types.ObjectId;
  flatId?: Types.ObjectId;
  registrationNumber: string;
  vehicleType: VehicleType;
  status: VehicleLogStatus;
  entryAt: Date;
  exitAt?: Date;
  guardUserId: Types.ObjectId;
  checkedOutBy?: Types.ObjectId;
  notes?: string;
  createdAt: Date;
  updatedAt: Date;
}

const vehicleLogSchema = new Schema<VehicleLogDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    vehicleId: { type: Schema.Types.ObjectId, ref: 'Vehicle' },
    flatId: { type: Schema.Types.ObjectId, ref: 'Flat' },
    registrationNumber: { type: String, required: true, trim: true, uppercase: true },
    vehicleType: { type: String, enum: VEHICLE_TYPES, required: true },
    status: { type: String, enum: VEHICLE_LOG_STATUSES, required: true, default: 'INSIDE' },
    entryAt: { type: Date, required: true, default: Date.now },
    exitAt: { type: Date },
    guardUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    checkedOutBy: { type: Schema.Types.ObjectId, ref: 'User' },
    notes: { type: String, trim: true, maxlength: 1000 },
  },
  { timestamps: true },
);

vehicleLogSchema.index(
  { societyId: 1, registrationNumber: 1 },
  {
    unique: true,
    partialFilterExpression: { status: 'INSIDE' },
  },
);
vehicleLogSchema.index({ societyId: 1, entryAt: -1 });
vehicleLogSchema.index({ societyId: 1, vehicleId: 1, entryAt: -1 });
vehicleLogSchema.index({ societyId: 1, status: 1, entryAt: -1 });

export const VehicleLogModel = model<VehicleLogDocument>('VehicleLog', vehicleLogSchema);
