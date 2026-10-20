import { Schema, model, type Document, type Types } from 'mongoose';

export const ALLOCATION_STATUSES = ['ACTIVE', 'ENDED'] as const;
export type AllocationStatus = (typeof ALLOCATION_STATUSES)[number];

export interface ParkingAllocationDocument extends Document {
  societyId: Types.ObjectId;
  flatId: Types.ObjectId;
  vehicleId: Types.ObjectId;
  parkingSlotId: Types.ObjectId;
  startsAt: Date;
  endsAt?: Date;
  status: AllocationStatus;
  createdBy: Types.ObjectId;
  endedBy?: Types.ObjectId;
  endReason?: string;
  createdAt: Date;
  updatedAt: Date;
}

const parkingAllocationSchema = new Schema<ParkingAllocationDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    flatId: { type: Schema.Types.ObjectId, ref: 'Flat', required: true },
    vehicleId: { type: Schema.Types.ObjectId, ref: 'Vehicle', required: true },
    parkingSlotId: { type: Schema.Types.ObjectId, ref: 'ParkingSlot', required: true },
    startsAt: { type: Date, required: true, default: Date.now },
    endsAt: { type: Date },
    status: { type: String, enum: ALLOCATION_STATUSES, required: true, default: 'ACTIVE' },
    createdBy: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    endedBy: { type: Schema.Types.ObjectId, ref: 'User' },
    endReason: { type: String, trim: true, maxlength: 500 },
  },
  { timestamps: true },
);

parkingAllocationSchema.index(
  { societyId: 1, parkingSlotId: 1 },
  {
    unique: true,
    partialFilterExpression: { status: 'ACTIVE' },
  },
);
parkingAllocationSchema.index(
  { societyId: 1, vehicleId: 1 },
  {
    unique: true,
    partialFilterExpression: { status: 'ACTIVE' },
  },
);
parkingAllocationSchema.index({ societyId: 1, flatId: 1, status: 1 });
parkingAllocationSchema.index({ societyId: 1, status: 1, createdAt: -1 });

export const ParkingAllocationModel = model<ParkingAllocationDocument>(
  'ParkingAllocation',
  parkingAllocationSchema,
);
