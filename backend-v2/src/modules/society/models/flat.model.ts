import { Schema, model, type Document, type Types } from 'mongoose';
import { FLAT_TYPES, OCCUPANCY_STATUSES, type FlatType, type OccupancyStatus } from '../../../config/constants';

export interface FlatParking {
  hasParking: boolean;
  slotLabel?: string;
}

export interface FlatDocument extends Document {
  societyId: Types.ObjectId;
  wingId: Types.ObjectId;
  number: string;
  floor: number;
  position: number;
  flatType: FlatType;
  maintenanceRate: number;
  isActive: boolean;
  occupancyStatus: OccupancyStatus;
  activeOwnerUserId?: Types.ObjectId;
  activeTenantUserId?: Types.ObjectId;
  parking?: FlatParking;
  notes?: string;
  deactivatedAt?: Date;
  deactivationReason?: string;
  createdAt: Date;
  updatedAt: Date;
}

const flatSchema = new Schema<FlatDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    wingId: { type: Schema.Types.ObjectId, ref: 'Wing', required: true },
    number: { type: String, required: true, trim: true, uppercase: true, maxlength: 32 },
    floor: { type: Number, required: true, min: 1 },
    position: { type: Number, required: true, min: 1 },
    flatType: { type: String, enum: FLAT_TYPES, required: true, default: '2BHK' },
    maintenanceRate: { type: Number, required: true, min: 0 },
    isActive: { type: Boolean, default: true },
    occupancyStatus: {
      type: String,
      enum: OCCUPANCY_STATUSES,
      required: true,
      default: 'VACANT',
    },
    activeOwnerUserId: { type: Schema.Types.ObjectId, ref: 'User' },
    activeTenantUserId: { type: Schema.Types.ObjectId, ref: 'User' },
    parking: {
      hasParking: { type: Boolean, default: false },
      slotLabel: { type: String, trim: true, maxlength: 64 },
    },
    notes: { type: String, trim: true, maxlength: 2000 },
    deactivatedAt: { type: Date },
    deactivationReason: { type: String, trim: true, maxlength: 500 },
  },
  { timestamps: true },
);

flatSchema.index({ societyId: 1, number: 1 }, { unique: true });
flatSchema.index({ societyId: 1, wingId: 1, floor: 1, position: 1 }, { unique: true });
flatSchema.index({ societyId: 1, wingId: 1, isActive: 1 });
flatSchema.index({ societyId: 1, maintenanceRate: 1 });
flatSchema.index({ societyId: 1, occupancyStatus: 1, isActive: 1 });
flatSchema.index({ societyId: 1, flatType: 1, isActive: 1 });
flatSchema.index({ societyId: 1, number: 'text' });
flatSchema.index({ societyId: 1, activeOwnerUserId: 1 });
flatSchema.index({ societyId: 1, activeTenantUserId: 1 });

export const FlatModel = model<FlatDocument>('Flat', flatSchema);
