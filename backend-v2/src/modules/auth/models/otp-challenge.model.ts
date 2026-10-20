import { Schema, model, type Document, type Types } from 'mongoose';

export interface OtpChallengeDocument extends Document {
  /** E.164 mobile digits (no '+') — login SMS OTP challenges. */
  mobileE164: string;
  userId: Types.ObjectId;
  /** Only used by memory SMS provider; MSG91-managed flows leave this unset. */
  otpHash?: string;
  providerRequestId?: string;
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
    mobileE164: { type: String, required: true, trim: true, index: true },
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    otpHash: { type: String, select: false },
    providerRequestId: { type: String },
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

otpChallengeSchema.index({ mobileE164: 1, consumedAt: 1, expiresAt: -1 });
otpChallengeSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

export const OtpChallengeModel = model<OtpChallengeDocument>('OtpChallenge', otpChallengeSchema);
