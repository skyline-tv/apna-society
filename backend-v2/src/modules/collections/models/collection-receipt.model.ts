import { Schema, model, type Document, type Types } from 'mongoose';

export interface CollectionReceiptDocument extends Document {
  societyId: Types.ObjectId;
  collectionId: Types.ObjectId;
  chargeId: Types.ObjectId;
  paymentId: Types.ObjectId;
  flatId: Types.ObjectId;
  receiptNumber: string;
  ownerUserId?: Types.ObjectId;
  ownerNameSnapshot: string;
  flatNumberSnapshot: string;
  wingCodeSnapshot: string;
  societyNameSnapshot: string;
  collectionTitleSnapshot: string;
  collectionNumberSnapshot: string;
  amountPaise: number;
  paymentMethod: string;
  transactionReference?: string;
  paidAt: Date;
  generatedAt: Date;
  createdAt: Date;
  updatedAt: Date;
}

const collectionReceiptSchema = new Schema<CollectionReceiptDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    collectionId: { type: Schema.Types.ObjectId, ref: 'SpecialCollection', required: true },
    chargeId: { type: Schema.Types.ObjectId, ref: 'SpecialCollectionCharge', required: true },
    paymentId: {
      type: Schema.Types.ObjectId,
      ref: 'SpecialCollectionPayment',
      required: true,
      unique: true,
    },
    flatId: { type: Schema.Types.ObjectId, ref: 'Flat', required: true },
    receiptNumber: { type: String, required: true, trim: true },
    ownerUserId: { type: Schema.Types.ObjectId, ref: 'User' },
    ownerNameSnapshot: { type: String, required: true },
    flatNumberSnapshot: { type: String, required: true },
    wingCodeSnapshot: { type: String, required: true },
    societyNameSnapshot: { type: String, required: true },
    collectionTitleSnapshot: { type: String, required: true },
    collectionNumberSnapshot: { type: String, required: true },
    amountPaise: { type: Number, required: true, min: 1 },
    paymentMethod: { type: String, required: true },
    transactionReference: { type: String, trim: true },
    paidAt: { type: Date, required: true },
    generatedAt: { type: Date, required: true, default: Date.now },
  },
  { timestamps: true },
);

collectionReceiptSchema.index({ societyId: 1, receiptNumber: 1 }, { unique: true });
collectionReceiptSchema.index({ societyId: 1, ownerUserId: 1, generatedAt: -1 });
collectionReceiptSchema.index({ societyId: 1, collectionId: 1, generatedAt: -1 });

export const CollectionReceiptModel = model<CollectionReceiptDocument>(
  'SpecialCollectionReceipt',
  collectionReceiptSchema,
);
