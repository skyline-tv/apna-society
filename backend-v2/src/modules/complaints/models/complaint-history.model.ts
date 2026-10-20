import { Schema, model, type Document, type Types } from 'mongoose';
import type { ComplaintPriority, ComplaintStatus } from './complaint.model';

export const COMPLAINT_HISTORY_ACTIONS = [
  'CREATED',
  'PRIORITY_CHANGED',
  'ASSIGNED',
  'REASSIGNED',
  'UNASSIGNED',
  'STARTED',
  'RESOLVED',
  'CLOSED',
  'CANCELLED',
  'ATTACHMENT_ADDED',
] as const;
export type ComplaintHistoryAction = (typeof COMPLAINT_HISTORY_ACTIONS)[number];

export interface ComplaintHistoryDocument extends Document {
  complaintId: Types.ObjectId;
  societyId: Types.ObjectId;
  action: ComplaintHistoryAction;
  previousStatus?: ComplaintStatus;
  newStatus?: ComplaintStatus;
  previousPriority?: ComplaintPriority;
  newPriority?: ComplaintPriority;
  actorUserId: Types.ObjectId;
  actorRole: string;
  notes?: string;
  /** Resident-safe summary; never includes internalNotes. */
  publicNotes?: string;
  assignmentSnapshot?: {
    assignmentType?: string;
    assignedToUserId?: string;
    assignedToNameSnapshot?: string;
    externalAssigneeName?: string;
  };
  metadata?: Record<string, unknown>;
  createdAt: Date;
  updatedAt: Date;
}

const complaintHistorySchema = new Schema<ComplaintHistoryDocument>(
  {
    complaintId: { type: Schema.Types.ObjectId, ref: 'Complaint', required: true },
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    action: { type: String, enum: COMPLAINT_HISTORY_ACTIONS, required: true },
    previousStatus: { type: String },
    newStatus: { type: String },
    previousPriority: { type: String },
    newPriority: { type: String },
    actorUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    actorRole: { type: String, required: true },
    notes: { type: String, trim: true, maxlength: 4000 },
    publicNotes: { type: String, trim: true, maxlength: 4000 },
    assignmentSnapshot: { type: Schema.Types.Mixed },
    metadata: { type: Schema.Types.Mixed },
  },
  { timestamps: true },
);

complaintHistorySchema.index({ complaintId: 1, createdAt: 1 });
complaintHistorySchema.index({ societyId: 1, createdAt: -1 });

export const ComplaintHistoryModel = model<ComplaintHistoryDocument>(
  'ComplaintHistory',
  complaintHistorySchema,
);
