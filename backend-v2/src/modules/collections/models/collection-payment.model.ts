import { Schema, model, type Document, type Types } from 'mongoose';
import { PAYMENT_METHODS, PAYMENT_STATUSES, type PaymentMethod, type PaymentStatus } from '../../billing/models/payment.model';

export interface CollectionPaymentDocument extends Document {
  societyId: Types.ObjectId;
  collectionId: Types.ObjectId;
  chargeId: Types.ObjectId;
  flatId: Types.ObjectId;
  ownerUserId?: Types.ObjectId;
  paymentNumber: string;
  amountPaise: number;
  paymentMethod: PaymentMethod;
  status: PaymentStatus;
  gateway?: string;
  gatewayOrderId?: string;
  gatewayPaymentId?: string;
  gatewaySignatureVerified?: boolean;
  paidAt?: Date;
  receivedAt?: Date;
  referenceNumber?: string;
  notes?: string;
  createdBy?: Types.ObjectId;
  idempotencyKey?: string;
  createdAt: Date;
  updatedAt: Date;
}

const collectionPaymentSchema = new Schema<CollectionPaymentDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    collectionId: { type: Schema.Types.ObjectId, ref: 'SpecialCollection', required: true },
    chargeId: { type: Schema.Types.ObjectId, ref: 'SpecialCollectionCharge', required: true },
    flatId: { type: Schema.Types.ObjectId, ref: 'Flat', required: true },
    ownerUserId: { type: Schema.Types.ObjectId, ref: 'User' },
    paymentNumber: { type: String, required: true, trim: true },
    amountPaise: { type: Number, required: true, min: 1 },
    paymentMethod: { type: String, enum: PAYMENT_METHODS, required: true },
    status: { type: String, enum: PAYMENT_STATUSES, required: true, default: 'PENDING' },
    gateway: { type: String, trim: true },
    gatewayOrderId: { type: String, trim: true },
    gatewayPaymentId: { type: String, trim: true },
    gatewaySignatureVerified: { type: Boolean },
    paidAt: { type: Date },
    receivedAt: { type: Date },
    referenceNumber: { type: String, trim: true, maxlength: 120 },
    notes: { type: String, trim: true, maxlength: 2000 },
    createdBy: { type: Schema.Types.ObjectId, ref: 'User' },
    idempotencyKey: { type: String, trim: true },
  },
  { timestamps: true },
);

collectionPaymentSchema.index({ societyId: 1, paymentNumber: 1 }, { unique: true });
collectionPaymentSchema.index(
  { societyId: 1, gatewayPaymentId: 1 },
  { unique: true, partialFilterExpression: { gatewayPaymentId: { $type: 'string' } } },
);
collectionPaymentSchema.index(
  { societyId: 1, idempotencyKey: 1 },
  { unique: true, partialFilterExpression: { idempotencyKey: { $type: 'string' } } },
);
collectionPaymentSchema.index(
  { gatewayOrderId: 1 },
  { unique: true, partialFilterExpression: { gatewayOrderId: { $type: 'string' } } },
);
collectionPaymentSchema.index({ societyId: 1, collectionId: 1, status: 1 });
collectionPaymentSchema.index({ societyId: 1, chargeId: 1, status: 1 });
collectionPaymentSchema.index({ societyId: 1, ownerUserId: 1, createdAt: -1 });

export const CollectionPaymentModel = model<CollectionPaymentDocument>(
  'SpecialCollectionPayment',
  collectionPaymentSchema,
);
