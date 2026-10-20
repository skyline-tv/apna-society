import { Schema, model, type Document, type Types } from 'mongoose';

export const PAYMENT_STATUSES = ['PENDING', 'SUCCESS', 'FAILED', 'REFUNDED'] as const;
export type PaymentStatus = (typeof PAYMENT_STATUSES)[number];

export const PAYMENT_METHODS = ['UPI', 'OFFLINE', 'GATEWAY'] as const;
export type PaymentMethod = (typeof PAYMENT_METHODS)[number];

export interface PaymentDocument extends Document {
  societyId: Types.ObjectId;
  billId: Types.ObjectId;
  flatId: Types.ObjectId;
  ownerUserId: Types.ObjectId;
  paymentNumber: string;
  amountPaise: number;
  allocatedToPrincipalPaise: number;
  allocatedToInterestPaise: number;
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
  metadata?: Record<string, unknown>;
  refundedAt?: Date;
  refundReason?: string;
  createdAt: Date;
  updatedAt: Date;
}

const paymentSchema = new Schema<PaymentDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    billId: { type: Schema.Types.ObjectId, ref: 'Bill', required: true },
    flatId: { type: Schema.Types.ObjectId, ref: 'Flat', required: true },
    ownerUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    paymentNumber: { type: String, required: true, trim: true },
    amountPaise: { type: Number, required: true, min: 1 },
    allocatedToPrincipalPaise: { type: Number, required: true, default: 0, min: 0 },
    allocatedToInterestPaise: { type: Number, required: true, default: 0, min: 0 },
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
    metadata: { type: Schema.Types.Mixed },
    refundedAt: { type: Date },
    refundReason: { type: String, trim: true, maxlength: 500 },
  },
  { timestamps: true },
);

paymentSchema.index({ societyId: 1, paymentNumber: 1 }, { unique: true });
paymentSchema.index(
  { societyId: 1, gatewayPaymentId: 1 },
  {
    unique: true,
    partialFilterExpression: { gatewayPaymentId: { $type: 'string' } },
  },
);
paymentSchema.index(
  { societyId: 1, idempotencyKey: 1 },
  {
    unique: true,
    partialFilterExpression: { idempotencyKey: { $type: 'string' } },
  },
);
paymentSchema.index({ societyId: 1, billId: 1, status: 1 });
paymentSchema.index({ societyId: 1, ownerUserId: 1, status: 1 });
paymentSchema.index({ societyId: 1, flatId: 1, createdAt: -1 });
// Reports: payment method/status breakdowns and date filters
paymentSchema.index({ societyId: 1, status: 1, paidAt: -1 });
paymentSchema.index({ societyId: 1, paymentMethod: 1, status: 1, paidAt: -1 });
// Listing + webhook settlement lookups
paymentSchema.index({ societyId: 1, createdAt: -1 });
paymentSchema.index(
  { gatewayOrderId: 1 },
  {
    unique: true,
    partialFilterExpression: { gatewayOrderId: { $type: 'string' } },
  },
);

export const PaymentModel = model<PaymentDocument>('Payment', paymentSchema);
