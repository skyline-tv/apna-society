import { Schema, model, type Document, type Types } from 'mongoose';

export const INTEREST_JOB_STATUSES = ['RUNNING', 'COMPLETED', 'FAILED'] as const;
export type InterestJobStatus = (typeof INTEREST_JOB_STATUSES)[number];

/**
 * One accrual pass per society civil date.
 * Interest itself is derived (never += a day), so a retry cannot double-charge.
 * This collection only serializes the daily job across instances and restarts.
 */
export interface InterestJobRunDocument extends Document {
  societyId: Types.ObjectId;
  /** YYYY-MM-DD in the society timezone. */
  civilDate: string;
  status: InterestJobStatus;
  asOf: Date;
  startedAt: Date;
  finishedAt?: Date;
  billsUpdated: number;
  billsSkipped: number;
  error?: string;
  createdAt: Date;
  updatedAt: Date;
}

const interestJobRunSchema = new Schema<InterestJobRunDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    civilDate: { type: String, required: true, match: /^\d{4}-\d{2}-\d{2}$/ },
    status: { type: String, enum: INTEREST_JOB_STATUSES, required: true },
    asOf: { type: Date, required: true },
    startedAt: { type: Date, required: true },
    finishedAt: { type: Date },
    billsUpdated: { type: Number, required: true, default: 0, min: 0 },
    billsSkipped: { type: Number, required: true, default: 0, min: 0 },
    error: { type: String, trim: true, maxlength: 1000 },
  },
  { timestamps: true },
);

interestJobRunSchema.index({ societyId: 1, civilDate: 1 }, { unique: true });
interestJobRunSchema.index({ status: 1, startedAt: 1 });

export const InterestJobRunModel = model<InterestJobRunDocument>(
  'InterestJobRun',
  interestJobRunSchema,
);
