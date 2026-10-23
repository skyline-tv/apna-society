import { Schema, model, type Document, type Types } from 'mongoose';

export const COLLECTION_STATUSES = ['ACTIVE', 'CLOSED', 'CANCELLED'] as const;
export type CollectionStatus = (typeof COLLECTION_STATUSES)[number];

export const COLLECTION_AMOUNT_MODES = ['PER_FLAT', 'TOTAL_SPLIT', 'CUSTOM'] as const;
export type CollectionAmountMode = (typeof COLLECTION_AMOUNT_MODES)[number];

export const COLLECTION_ASSIGNMENT_TYPES = ['ALL_FLATS', 'WINGS', 'SELECTED_FLATS'] as const;
export type CollectionAssignmentType = (typeof COLLECTION_ASSIGNMENT_TYPES)[number];

export interface CollectionDocument extends Document {
  societyId: Types.ObjectId;
  collectionNumber: string;
  title: string;
  description: string;
  amountMode: CollectionAmountMode;
  assignmentType: CollectionAssignmentType;
  amountPaise: number;
  allowPartialPayment: boolean;
  dueDate: Date;
  startDate?: Date;
  paymentInstructions?: string;
  status: CollectionStatus;
  expectedTotalPaise: number;
  collectedPaise: number;
  assignedFlatCount: number;
  closedAt?: Date;
  cancelledAt?: Date;
  cancellationReason?: string;
  createdBy: Types.ObjectId;
  updatedBy?: Types.ObjectId;
  createdAt: Date;
  updatedAt: Date;
}

const collectionSchema = new Schema<CollectionDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    collectionNumber: { type: String, required: true, trim: true },
    title: { type: String, required: true, trim: true, maxlength: 200 },
    description: { type: String, required: true, trim: true, maxlength: 4000 },
    amountMode: { type: String, enum: COLLECTION_AMOUNT_MODES, required: true },
    assignmentType: { type: String, enum: COLLECTION_ASSIGNMENT_TYPES, required: true },
    amountPaise: { type: Number, required: true, min: 0 },
    allowPartialPayment: { type: Boolean, required: true, default: false },
    dueDate: { type: Date, required: true },
    startDate: { type: Date },
    paymentInstructions: { type: String, trim: true, maxlength: 2000 },
    status: { type: String, enum: COLLECTION_STATUSES, required: true, default: 'ACTIVE' },
    expectedTotalPaise: { type: Number, required: true, min: 0 },
    collectedPaise: { type: Number, required: true, default: 0, min: 0 },
    assignedFlatCount: { type: Number, required: true, min: 0 },
    closedAt: { type: Date },
    cancelledAt: { type: Date },
    cancellationReason: { type: String, trim: true, maxlength: 500 },
    createdBy: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    updatedBy: { type: Schema.Types.ObjectId, ref: 'User' },
  },
  { timestamps: true },
);

collectionSchema.index({ societyId: 1, collectionNumber: 1 }, { unique: true });
collectionSchema.index({ societyId: 1, status: 1, dueDate: 1 });
collectionSchema.index({ societyId: 1, createdAt: -1 });

export const CollectionModel = model<CollectionDocument>('SpecialCollection', collectionSchema);
