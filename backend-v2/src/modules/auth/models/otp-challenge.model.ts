import { Schema, model, type Document, type Types } from 'mongoose';

export interface OtpChallengeDocument extends Document {
  email: string;
  userId: Types.ObjectId;
  otpHash: string;
  expiresAt: Date;
  attemptCount: number;
  maxAttempts: number;
  consumedAt?: Date;
  lastSentAt: Date;
  requestCount: number;
  requestWindowStartedAt: Date;
  ipAddress?: string;
  userAgent?: string;
  createdAt: Date;
  updatedAt: Date;
}

const otpChallengeSchema = new Schema<OtpChallengeDocument>(
  {
    email: { type: String, required: true, lowercase: true, trim: true, index: true },
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    otpHash: { type: String, required: true, select: false },
    expiresAt: { type: Date, required: true },
    attemptCount: { type: Number, default: 0 },
    maxAttempts: { type: Number, default: 5 },
    consumedAt: { type: Date },
    lastSentAt: { type: Date, required: true },
    requestCount: { type: Number, default: 1 },
    requestWindowStartedAt: { type: Date, required: true },
    ipAddress: { type: String },
    userAgent: { type: String },
  },
  { timestamps: true },
);

otpChallengeSchema.index({ email: 1, consumedAt: 1, expiresAt: -1 });
otpChallengeSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

export const OtpChallengeModel = model<OtpChallengeDocument>('OtpChallenge', otpChallengeSchema);
