import { Schema, model, type Document, type Types } from 'mongoose';

export interface RefreshSessionDocument extends Document {
  userId: Types.ObjectId;
  tokenHash: string;
  familyId: string;
  expiresAt: Date;
  revokedAt?: Date;
  replacedByHash?: string;
  reuseDetectedAt?: Date;
  ipAddress?: string;
  userAgent?: string;
  createdAt: Date;
  updatedAt: Date;
}

const refreshSessionSchema = new Schema<RefreshSessionDocument>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    tokenHash: { type: String, required: true, unique: true, select: false },
    familyId: { type: String, required: true, index: true },
    expiresAt: { type: Date, required: true },
    revokedAt: { type: Date },
    replacedByHash: { type: String },
    reuseDetectedAt: { type: Date },
    ipAddress: { type: String },
    userAgent: { type: String },
  },
  { timestamps: true },
);

refreshSessionSchema.index({ userId: 1, revokedAt: 1, expiresAt: 1 });
refreshSessionSchema.index({ familyId: 1, revokedAt: 1 });
refreshSessionSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

export const RefreshSessionModel = model<RefreshSessionDocument>(
  'RefreshSession',
  refreshSessionSchema,
);
