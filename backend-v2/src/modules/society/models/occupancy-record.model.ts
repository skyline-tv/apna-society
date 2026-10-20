import { Schema, model, type Document, type Types } from 'mongoose';

export type OccupancyRole = 'OWNER' | 'TENANT';
export type OccupancyRecordStatus = 'ACTIVE' | 'ENDED';

export interface OccupancyRecordDocument extends Document {
  societyId: Types.ObjectId;
  flatId: Types.ObjectId;
  userId: Types.ObjectId;
  role: OccupancyRole;
  status: OccupancyRecordStatus;
  startsAt: Date;
  endsAt?: Date;
  endReason?: string;
  notes?: string;
  createdAt: Date;
  updatedAt: Date;
}

const occupancyRecordSchema = new Schema<OccupancyRecordDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    flatId: { type: Schema.Types.ObjectId, ref: 'Flat', required: true },
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    role: { type: String, enum: ['OWNER', 'TENANT'], required: true },
    status: { type: String, enum: ['ACTIVE', 'ENDED'], required: true, default: 'ACTIVE' },
    startsAt: { type: Date, required: true, default: Date.now },
    endsAt: { type: Date },
    endReason: { type: String, trim: true, maxlength: 500 },
    notes: { type: String, trim: true, maxlength: 1000 },
  },
  { timestamps: true },
);

occupancyRecordSchema.index({ societyId: 1, flatId: 1, status: 1, role: 1 });

// One active owner/tenant per flat.
occupancyRecordSchema.index(
  { flatId: 1, role: 1, status: 1 },
  {
    unique: true,
    partialFilterExpression: { status: 'ACTIVE' },
  },
);

// One active assignment per user/role within a society.
occupancyRecordSchema.index(
  { societyId: 1, userId: 1, role: 1, status: 1 },
  {
    unique: true,
    partialFilterExpression: { status: 'ACTIVE' },
  },
);

occupancyRecordSchema.index({ societyId: 1, userId: 1, status: 1 });
occupancyRecordSchema.index({ flatId: 1, startsAt: -1 });
occupancyRecordSchema.index({ societyId: 1, status: 1, role: 1, startsAt: -1 });

export const OccupancyRecordModel = model<OccupancyRecordDocument>(
  'OccupancyRecord',
  occupancyRecordSchema,
);
