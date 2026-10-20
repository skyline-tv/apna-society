import { Schema, model, type ClientSession, type Document, type Types } from 'mongoose';

/**
 * Immutable principal ledger for a bill.
 * Interest is computed from chronological principal levels; past segments are never rewritten.
 */
export const PRINCIPAL_EVENT_TYPES = [
  'OPENING',
  'PAYMENT_ALLOCATION',
  'REFUND_RESTORATION',
  'ADJUSTMENT',
] as const;
export type PrincipalEventType = (typeof PRINCIPAL_EVENT_TYPES)[number];

export interface PrincipalLedgerDocument extends Document {
  societyId: Types.ObjectId;
  billId: Types.ObjectId;
  eventType: PrincipalEventType;
  /** Signed delta: negative reduces principal, positive restores/increases. */
  deltaPrincipalPaise: number;
  principalAfterPaise: number;
  /** Civil-day midnight (society TZ) when the new principal level takes effect for interest. */
  effectiveAt: Date;
  sourceType: 'bill' | 'payment' | 'refund' | 'adjustment';
  sourceId: string;
  paymentId?: Types.ObjectId;
  notes?: string;
  createdAt: Date;
  updatedAt: Date;
}

const principalLedgerSchema = new Schema<PrincipalLedgerDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    billId: { type: Schema.Types.ObjectId, ref: 'Bill', required: true },
    eventType: { type: String, enum: PRINCIPAL_EVENT_TYPES, required: true },
    deltaPrincipalPaise: { type: Number, required: true },
    principalAfterPaise: { type: Number, required: true, min: 0 },
    effectiveAt: { type: Date, required: true },
    sourceType: {
      type: String,
      enum: ['bill', 'payment', 'refund', 'adjustment'],
      required: true,
    },
    sourceId: { type: String, required: true },
    paymentId: { type: Schema.Types.ObjectId, ref: 'Payment' },
    notes: { type: String, trim: true, maxlength: 500 },
  },
  { timestamps: true },
);

principalLedgerSchema.index({ societyId: 1, billId: 1, effectiveAt: 1, createdAt: 1 });
principalLedgerSchema.index(
  { paymentId: 1, eventType: 1 },
  {
    unique: true,
    partialFilterExpression: { paymentId: { $type: 'objectId' } },
  },
);
principalLedgerSchema.index(
  { billId: 1, eventType: 1 },
  {
    unique: true,
    partialFilterExpression: { eventType: 'OPENING' },
  },
);

export const PrincipalLedgerModel = model<PrincipalLedgerDocument>(
  'PrincipalLedger',
  principalLedgerSchema,
);

export async function appendPrincipalEvent(
  input: {
    societyId: Types.ObjectId | string;
    billId: Types.ObjectId | string;
    eventType: PrincipalEventType;
    deltaPrincipalPaise: number;
    principalAfterPaise: number;
    effectiveAt: Date;
    sourceType: PrincipalLedgerDocument['sourceType'];
    sourceId: string;
    paymentId?: Types.ObjectId | string;
    notes?: string;
  },
  session?: ClientSession,
): Promise<PrincipalLedgerDocument> {
  const [doc] = await PrincipalLedgerModel.create(
    [
      {
        societyId: input.societyId,
        billId: input.billId,
        eventType: input.eventType,
        deltaPrincipalPaise: input.deltaPrincipalPaise,
        principalAfterPaise: input.principalAfterPaise,
        effectiveAt: input.effectiveAt,
        sourceType: input.sourceType,
        sourceId: input.sourceId,
        paymentId: input.paymentId,
        notes: input.notes,
      },
    ],
    { session },
  );
  return doc;
}
