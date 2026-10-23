import { Schema, model, type Document, type Types } from 'mongoose';

export interface CollectionAdjustmentDocument extends Document {
  societyId: Types.ObjectId;
  collectionId: Types.ObjectId;
  chargeId: Types.ObjectId;
  deltaPaise: number;
  reason: string;
  amountBeforePaise: number;
  amountAfterPaise: number;
  createdBy: Types.ObjectId;
  createdAt: Date;
  updatedAt: Date;
}

const collectionAdjustmentSchema = new Schema<CollectionAdjustmentDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    collectionId: { type: Schema.Types.ObjectId, ref: 'SpecialCollection', required: true },
    chargeId: { type: Schema.Types.ObjectId, ref: 'SpecialCollectionCharge', required: true },
    deltaPaise: { type: Number, required: true },
    reason: { type: String, required: true, trim: true, maxlength: 500 },
    amountBeforePaise: { type: Number, required: true },
    amountAfterPaise: { type: Number, required: true, min: 1 },
    createdBy: { type: Schema.Types.ObjectId, ref: 'User', required: true },
  },
  { timestamps: true },
);

collectionAdjustmentSchema.index({ societyId: 1, chargeId: 1, createdAt: -1 });
collectionAdjustmentSchema.index({ societyId: 1, collectionId: 1, createdAt: -1 });

export const CollectionAdjustmentModel = model<CollectionAdjustmentDocument>(
  'SpecialCollectionAdjustment',
  collectionAdjustmentSchema,
);
