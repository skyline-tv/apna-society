import { Schema, model, type Document, type Types } from 'mongoose';

export const BILL_STATUSES = [
  'DRAFT',
  'ISSUED',
  'PARTIALLY_PAID',
  'PAID',
  'OVERDUE',
  'CANCELLED',
] as const;
export type BillStatus = (typeof BILL_STATUSES)[number];

export const BILL_LINE_ITEM_TYPES = ['MAINTENANCE', 'ADDITIONAL_SERVICE', 'ADJUSTMENT'] as const;
export type BillLineItemType = (typeof BILL_LINE_ITEM_TYPES)[number];

export interface BillLineItem {
  type: BillLineItemType;
  serviceId?: Types.ObjectId;
  name: string;
  description?: string;
  quantity: number;
  unitAmountPaise: number;
  amountPaise: number;
  applicableDays?: number;
  billedDays?: number;
  prorationPolicy?: string;
}

export interface BillDocument extends Document {
  societyId: Types.ObjectId;
  flatId: Types.ObjectId;
  billNumber: string;
  billingPeriodStart: Date;
  billingPeriodEnd: Date;
  numberOfMonths: number;
  /** Present only when an owner is assigned to the flat at generation or later attach. */
  ownerUserId?: Types.ObjectId;
  ownerNameSnapshot: string;
  ownerEmailSnapshot: string;
  flatNumberSnapshot: string;
  wingCodeSnapshot: string;
  flatTypeSnapshot: string;
  occupancyStatusSnapshot?: string;
  floorSnapshot?: number;
  flatIsActiveSnapshot?: boolean;
  monthlyRatePaise: number;
  baseAmountPaise: number;
  additionalServicesTotalPaise: number;
  adjustmentsPaise: number;
  lineItems: BillLineItem[];
  totalAmountPaise: number;
  amountPaidPaise: number;
  outstandingPrincipalPaise: number;
  interestAccruedPaise: number;
  interestCalculatedAsOf?: Date;
  dueDate: Date;
  status: BillStatus;
  generatedAt: Date;
  notes?: string;
  createdBy: Types.ObjectId;
  updatedBy?: Types.ObjectId;
  cancelledAt?: Date;
  cancellationReason?: string;
  createdAt: Date;
  updatedAt: Date;
}

const billSchema = new Schema<BillDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    flatId: { type: Schema.Types.ObjectId, ref: 'Flat', required: true },
    billNumber: { type: String, required: true, trim: true },
    billingPeriodStart: { type: Date, required: true },
    billingPeriodEnd: { type: Date, required: true },
    numberOfMonths: { type: Number, required: true, enum: [1, 3] },
    ownerUserId: { type: Schema.Types.ObjectId, ref: 'User' },
    ownerNameSnapshot: { type: String, required: true, default: 'Unassigned' },
    ownerEmailSnapshot: { type: String, required: true, default: 'unassigned' },
    flatNumberSnapshot: { type: String, required: true },
    wingCodeSnapshot: { type: String, required: true },
    flatTypeSnapshot: { type: String, required: true },
    occupancyStatusSnapshot: { type: String, trim: true },
    floorSnapshot: { type: Number, min: 0 },
    flatIsActiveSnapshot: { type: Boolean },
    monthlyRatePaise: { type: Number, required: true, min: 0 },
    baseAmountPaise: { type: Number, required: true, min: 0 },
    additionalServicesTotalPaise: { type: Number, required: true, default: 0, min: 0 },
    adjustmentsPaise: { type: Number, required: true, default: 0 },
    lineItems: {
      type: [
        new Schema(
          {
            type: { type: String, enum: BILL_LINE_ITEM_TYPES, required: true },
            serviceId: { type: Schema.Types.ObjectId, ref: 'FlatAdditionalService' },
            name: { type: String, required: true, trim: true, maxlength: 160 },
            description: { type: String, trim: true, maxlength: 500 },
            quantity: { type: Number, required: true, min: 1 },
            unitAmountPaise: { type: Number, required: true, min: 0 },
            amountPaise: { type: Number, required: true, min: 0 },
            applicableDays: { type: Number, min: 0 },
            billedDays: { type: Number, min: 0 },
            prorationPolicy: { type: String, trim: true, maxlength: 80 },
          },
          { _id: false },
        ),
      ],
      default: [],
    },
    totalAmountPaise: { type: Number, required: true, min: 0 },
    amountPaidPaise: { type: Number, required: true, default: 0, min: 0 },
    outstandingPrincipalPaise: { type: Number, required: true, min: 0 },
    interestAccruedPaise: { type: Number, required: true, default: 0, min: 0 },
    interestCalculatedAsOf: { type: Date },
    dueDate: { type: Date, required: true },
    status: { type: String, enum: BILL_STATUSES, required: true, default: 'ISSUED' },
    generatedAt: { type: Date, required: true, default: Date.now },
    notes: { type: String, trim: true, maxlength: 2000 },
    createdBy: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    updatedBy: { type: Schema.Types.ObjectId, ref: 'User' },
    cancelledAt: { type: Date },
    cancellationReason: { type: String, trim: true, maxlength: 500 },
  },
  { timestamps: true },
);

billSchema.index({ societyId: 1, billNumber: 1 }, { unique: true });
billSchema.index(
  { societyId: 1, flatId: 1, billingPeriodStart: 1, billingPeriodEnd: 1 },
  {
    unique: true,
    // $ne is unsupported in partial indexes; enumerate active statuses instead.
    partialFilterExpression: {
      status: { $in: ['DRAFT', 'ISSUED', 'PARTIALLY_PAID', 'PAID', 'OVERDUE'] },
    },
  },
);
billSchema.index({ societyId: 1, status: 1, dueDate: 1 });
billSchema.index({ societyId: 1, ownerUserId: 1, status: 1 });
billSchema.index({ societyId: 1, flatId: 1, status: 1 });
billSchema.index({ societyId: 1, occupancyStatusSnapshot: 1, billingPeriodStart: 1 });
billSchema.index({ societyId: 1, floorSnapshot: 1, billingPeriodStart: 1 });
billSchema.index({ societyId: 1, billingPeriodStart: 1 });
// Reports: date-range + wing snapshot filters
billSchema.index({ societyId: 1, generatedAt: -1 });
billSchema.index({ societyId: 1, wingCodeSnapshot: 1, generatedAt: -1 });
billSchema.index({ societyId: 1, status: 1, generatedAt: -1 });
billSchema.index({ societyId: 1, outstandingPrincipalPaise: 1, generatedAt: -1 });
// Wing + billing period (financial reports / summaries)
billSchema.index({ societyId: 1, wingCodeSnapshot: 1, billingPeriodStart: 1 });

export const BillModel = model<BillDocument>('Bill', billSchema);
