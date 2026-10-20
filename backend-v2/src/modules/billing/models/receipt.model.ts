import { Schema, model, type Document, type Types } from 'mongoose';

export interface ReceiptDocument extends Document {
  societyId: Types.ObjectId;
  billId: Types.ObjectId;
  paymentId: Types.ObjectId;
  flatId: Types.ObjectId;
  receiptNumber: string;
  ownerUserId: Types.ObjectId;
  ownerNameSnapshot: string;
  ownerEmailSnapshot: string;
  flatNumberSnapshot: string;
  wingCodeSnapshot: string;
  societyNameSnapshot: string;
  amountPaise: number;
  paymentMethod: string;
  transactionReference?: string;
  paidAt: Date;
  generatedAt: Date;
  pdfGenerated: boolean;
  createdAt: Date;
  updatedAt: Date;
}

const receiptSchema = new Schema<ReceiptDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    billId: { type: Schema.Types.ObjectId, ref: 'Bill', required: true },
    paymentId: { type: Schema.Types.ObjectId, ref: 'Payment', required: true, unique: true },
    flatId: { type: Schema.Types.ObjectId, ref: 'Flat', required: true },
    receiptNumber: { type: String, required: true, trim: true },
    ownerUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    ownerNameSnapshot: { type: String, required: true },
    ownerEmailSnapshot: { type: String, required: true },
    flatNumberSnapshot: { type: String, required: true },
    wingCodeSnapshot: { type: String, required: true },
    societyNameSnapshot: { type: String, required: true },
    amountPaise: { type: Number, required: true, min: 1 },
    paymentMethod: { type: String, required: true },
    transactionReference: { type: String, trim: true },
    paidAt: { type: Date, required: true },
    generatedAt: { type: Date, required: true, default: Date.now },
    pdfGenerated: { type: Boolean, default: false },
  },
  { timestamps: true },
);

receiptSchema.index({ societyId: 1, receiptNumber: 1 }, { unique: true });
receiptSchema.index({ societyId: 1, ownerUserId: 1, generatedAt: -1 });
receiptSchema.index({ societyId: 1, flatId: 1, generatedAt: -1 });

export const ReceiptModel = model<ReceiptDocument>('Receipt', receiptSchema);
