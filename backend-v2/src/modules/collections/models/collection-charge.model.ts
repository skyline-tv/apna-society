import { Schema, model, type Document, type Types } from 'mongoose';

export const COLLECTION_CHARGE_STATUSES = [
  'PENDING',
  'PARTIALLY_PAID',
  'PAID',
  'CANCELLED',
] as const;
export type CollectionChargeStatus = (typeof COLLECTION_CHARGE_STATUSES)[number];

export interface CollectionChargeDocument extends Document {
  societyId: Types.ObjectId;
  collectionId: Types.ObjectId;
  flatId: Types.ObjectId;
  ownerUserId?: Types.ObjectId;
  amountPaise: number;
  adjustmentsPaise: number;
  amountPaidPaise: number;
  outstandingPaise: number;
  status: CollectionChargeStatus;
  dueDate: Date;
  wingCodeSnapshot: string;
  flatNumberSnapshot: string;
  occupancyStatusSnapshot: string;
  ownerNameSnapshot: string;
  createdAt: Date;
  updatedAt: Date;
}

const collectionChargeSchema = new Schema<CollectionChargeDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    collectionId: { type: Schema.Types.ObjectId, ref: 'SpecialCollection', required: true },
    flatId: { type: Schema.Types.ObjectId, ref: 'Flat', required: true },
    ownerUserId: { type: Schema.Types.ObjectId, ref: 'User' },
    amountPaise: { type: Number, required: true, min: 1 },
    adjustmentsPaise: { type: Number, required: true, default: 0 },
    amountPaidPaise: { type: Number, required: true, default: 0, min: 0 },
    outstandingPaise: { type: Number, required: true, min: 0 },
    status: { type: String, enum: COLLECTION_CHARGE_STATUSES, required: true, default: 'PENDING' },
    dueDate: { type: Date, required: true },
    wingCodeSnapshot: { type: String, required: true, trim: true },
    flatNumberSnapshot: { type: String, required: true, trim: true },
    occupancyStatusSnapshot: { type: String, required: true, trim: true },
    ownerNameSnapshot: { type: String, required: true, trim: true, default: 'Unassigned' },
  },
  { timestamps: true },
);

collectionChargeSchema.index({ collectionId: 1, flatId: 1 }, { unique: true });
collectionChargeSchema.index({ societyId: 1, collectionId: 1, status: 1 });
collectionChargeSchema.index({ societyId: 1, ownerUserId: 1, status: 1 });
collectionChargeSchema.index({ societyId: 1, flatId: 1, createdAt: -1 });
collectionChargeSchema.index({ societyId: 1, wingCodeSnapshot: 1, status: 1 });

export const CollectionChargeModel = model<CollectionChargeDocument>(
  'SpecialCollectionCharge',
  collectionChargeSchema,
);
