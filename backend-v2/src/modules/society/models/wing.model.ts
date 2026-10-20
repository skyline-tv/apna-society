import { Schema, model, type Document, type Types } from 'mongoose';

export interface WingDocument extends Document {
  societyId: Types.ObjectId;
  name: string;
  code: string;
  floors: number;
  flatsPerFloor: number;
  sortOrder: number;
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
}

const wingSchema = new Schema<WingDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true, index: true },
    name: { type: String, required: true, trim: true, maxlength: 120 },
    code: { type: String, required: true, uppercase: true, trim: true, maxlength: 16 },
    floors: { type: Number, required: true, min: 1, max: 200 },
    flatsPerFloor: { type: Number, required: true, min: 1, max: 50 },
    sortOrder: { type: Number, default: 0 },
    isActive: { type: Boolean, default: true },
  },
  { timestamps: true },
);

wingSchema.index({ societyId: 1, code: 1 }, { unique: true });
wingSchema.index({ societyId: 1, sortOrder: 1 });
wingSchema.index({ societyId: 1, isActive: 1, sortOrder: 1 });

export const WingModel = model<WingDocument>('Wing', wingSchema);
