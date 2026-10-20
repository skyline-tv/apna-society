import { Schema, model, type Document, type Types } from 'mongoose';

export const COMPLAINT_CATEGORIES = [
  'PLUMBING',
  'ELECTRICAL',
  'LIFT',
  'CLEANING',
  'SECURITY',
  'PARKING',
  'WATER_SUPPLY',
  'STRUCTURAL',
  'OTHER',
] as const;
export type ComplaintCategory = (typeof COMPLAINT_CATEGORIES)[number];

export const COMPLAINT_PRIORITIES = ['LOW', 'MEDIUM', 'HIGH', 'URGENT'] as const;
export type ComplaintPriority = (typeof COMPLAINT_PRIORITIES)[number];

export const COMPLAINT_STATUSES = [
  'OPEN',
  'ASSIGNED',
  'IN_PROGRESS',
  'RESOLVED',
  'CLOSED',
  'CANCELLED',
] as const;
export type ComplaintStatus = (typeof COMPLAINT_STATUSES)[number];

export const ASSIGNMENT_TYPES = ['INTERNAL', 'EXTERNAL'] as const;
export type AssignmentType = (typeof ASSIGNMENT_TYPES)[number];

export const RAISED_BY_ROLES = ['OWNER', 'TENANT', 'ADMIN'] as const;
export type RaisedByRole = (typeof RAISED_BY_ROLES)[number];

export interface ComplaintAttachment {
  _id: Types.ObjectId;
  storageKey: string;
  mimeType: string;
  sizeBytes: number;
  originalFilename: string;
  uploadedByUserId: Types.ObjectId;
  createdAt: Date;
}

export interface ExternalAssignee {
  name: string;
  phone?: string;
  company?: string;
}

export interface ComplaintDocument extends Document {
  societyId: Types.ObjectId;
  flatId: Types.ObjectId;
  complaintNumber: string;
  raisedByUserId: Types.ObjectId;
  raisedByRole: RaisedByRole;
  category: ComplaintCategory;
  title: string;
  description: string;
  priority: ComplaintPriority;
  status: ComplaintStatus;
  assignmentType?: AssignmentType;
  assignedToUserId?: Types.ObjectId;
  assignedToNameSnapshot?: string;
  externalAssignee?: ExternalAssignee;
  resolutionNotes?: string;
  /** Admin-only; never exposed to residents. */
  internalNotes?: string;
  cancellationReason?: string;
  resolvedAt?: Date;
  closedAt?: Date;
  cancelledAt?: Date;
  attachments: ComplaintAttachment[];
  createdAt: Date;
  updatedAt: Date;
}

const attachmentSchema = new Schema<ComplaintAttachment>(
  {
    storageKey: { type: String, required: true },
    mimeType: { type: String, required: true },
    sizeBytes: { type: Number, required: true },
    originalFilename: { type: String, required: true, maxlength: 255 },
    uploadedByUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    createdAt: { type: Date, required: true, default: Date.now },
  },
  { _id: true },
);

const externalAssigneeSchema = new Schema<ExternalAssignee>(
  {
    name: { type: String, required: true, trim: true, maxlength: 120 },
    phone: { type: String, trim: true, maxlength: 32 },
    company: { type: String, trim: true, maxlength: 120 },
  },
  { _id: false },
);

const complaintSchema = new Schema<ComplaintDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    flatId: { type: Schema.Types.ObjectId, ref: 'Flat', required: true },
    complaintNumber: { type: String, required: true, trim: true, maxlength: 40 },
    raisedByUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    raisedByRole: { type: String, enum: RAISED_BY_ROLES, required: true },
    category: { type: String, enum: COMPLAINT_CATEGORIES, required: true },
    title: { type: String, required: true, trim: true, maxlength: 160 },
    description: { type: String, required: true, trim: true, maxlength: 4000 },
    priority: { type: String, enum: COMPLAINT_PRIORITIES, required: true, default: 'MEDIUM' },
    status: { type: String, enum: COMPLAINT_STATUSES, required: true, default: 'OPEN' },
    assignmentType: { type: String, enum: ASSIGNMENT_TYPES },
    assignedToUserId: { type: Schema.Types.ObjectId, ref: 'User' },
    assignedToNameSnapshot: { type: String, trim: true, maxlength: 120 },
    externalAssignee: { type: externalAssigneeSchema },
    resolutionNotes: { type: String, trim: true, maxlength: 4000 },
    internalNotes: { type: String, trim: true, maxlength: 4000 },
    cancellationReason: { type: String, trim: true, maxlength: 1000 },
    resolvedAt: { type: Date },
    closedAt: { type: Date },
    cancelledAt: { type: Date },
    attachments: { type: [attachmentSchema], default: [] },
  },
  { timestamps: true },
);

complaintSchema.index({ societyId: 1, complaintNumber: 1 }, { unique: true });
complaintSchema.index({ societyId: 1, status: 1, createdAt: -1 });
complaintSchema.index({ societyId: 1, flatId: 1, createdAt: -1 });
complaintSchema.index({ societyId: 1, raisedByUserId: 1, createdAt: -1 });
complaintSchema.index({ societyId: 1, category: 1, status: 1 });
complaintSchema.index({ societyId: 1, priority: 1, status: 1 });
complaintSchema.index({ societyId: 1, assignedToUserId: 1, status: 1 });
// Unfiltered society listings / analytics date ranges
complaintSchema.index({ societyId: 1, createdAt: -1 });

export const ComplaintModel = model<ComplaintDocument>('Complaint', complaintSchema);
