import { Schema, model, type Document, type Types } from 'mongoose';

export interface FlatAdditionalServiceDocument extends Document {
  societyId: Types.ObjectId;
  flatId: Types.ObjectId;
  name: string;
  description?: string;
  monthlyChargePaise: number;
  quantity: number;
  effectiveFrom: Date;
  effectiveTo?: Date;
  isActive: boolean;
  /** Occupied only while isActive. Unique per flat in 1..10. */
  activeSlot?: number;
  createdBy: Types.ObjectId;
  updatedBy?: Types.ObjectId;
  deactivatedAt?: Date;
  deactivationReason?: string;
  createdAt: Date;
  updatedAt: Date;
}

const additionalServiceSchema = new Schema<FlatAdditionalServiceDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    flatId: { type: Schema.Types.ObjectId, ref: 'Flat', required: true },
    name: { type: String, required: true, trim: true, maxlength: 120 },
    description: { type: String, trim: true, maxlength: 500 },
    monthlyChargePaise: { type: Number, required: true, min: 0 },
    quantity: { type: Number, required: true, min: 1, max: 99, default: 1 },
    effectiveFrom: { type: Date, required: true },
    effectiveTo: { type: Date },
    isActive: { type: Boolean, required: true, default: true },
    activeSlot: { type: Number, min: 1, max: 10 },
    createdBy: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    updatedBy: { type: Schema.Types.ObjectId, ref: 'User' },
    deactivatedAt: { type: Date },
    deactivationReason: { type: String, trim: true, maxlength: 500 },
  },
  { timestamps: true },
);

additionalServiceSchema.index({ societyId: 1, flatId: 1, isActive: 1 });
additionalServiceSchema.index({ societyId: 1, flatId: 1, createdAt: -1 });
additionalServiceSchema.index({ societyId: 1, isActive: 1, effectiveFrom: 1 });
additionalServiceSchema.index(
  { societyId: 1, flatId: 1, activeSlot: 1 },
  {
    unique: true,
    name: 'uniq_flat_active_additional_service_slot',
    partialFilterExpression: { isActive: true, activeSlot: { $gte: 1 } },
  },
);

export const FlatAdditionalServiceModel = model<FlatAdditionalServiceDocument>(
  'FlatAdditionalService',
  additionalServiceSchema,
);
