import type { ComplaintDocument } from '../models/complaint.model';
import type { ComplaintHistoryDocument } from '../models/complaint-history.model';

type ComplaintLike = {
  _id: { toString(): string };
  societyId: { toString(): string };
  flatId: { toString(): string };
  complaintNumber: string;
  raisedByUserId: { toString(): string };
  raisedByRole: string;
  category: string;
  title: string;
  description: string;
  priority: string;
  status: string;
  assignmentType?: string;
  assignedToUserId?: { toString(): string };
  assignedToNameSnapshot?: string;
  externalAssignee?: { name: string; phone?: string; company?: string };
  resolutionNotes?: string;
  internalNotes?: string;
  cancellationReason?: string;
  resolvedAt?: Date;
  closedAt?: Date;
  cancelledAt?: Date;
  attachments?: Array<{
    _id: { toString(): string };
    mimeType: string;
    sizeBytes: number;
    originalFilename: string;
    uploadedByUserId: { toString(): string };
    createdAt: Date;
  }>;
  createdAt: Date;
  updatedAt: Date;
};

export function serializeAttachment(att: {
  _id: { toString(): string };
  mimeType: string;
  sizeBytes: number;
  originalFilename: string;
  uploadedByUserId: { toString(): string };
  createdAt: Date;
}) {
  return {
    id: String(att._id),
    mimeType: att.mimeType,
    sizeBytes: att.sizeBytes,
    originalFilename: att.originalFilename,
    uploadedByUserId: String(att.uploadedByUserId),
    createdAt: new Date(att.createdAt).toISOString(),
  };
}

export function serializeComplaint(
  doc: ComplaintLike | ComplaintDocument,
  options: { includeInternalNotes?: boolean } = {},
) {
  return {
    id: String(doc._id),
    societyId: String(doc.societyId),
    flatId: String(doc.flatId),
    complaintNumber: doc.complaintNumber,
    raisedByUserId: String(doc.raisedByUserId),
    raisedByRole: doc.raisedByRole,
    category: doc.category,
    title: doc.title,
    description: doc.description,
    priority: doc.priority,
    status: doc.status,
    assignmentType: doc.assignmentType,
    assignedToUserId: doc.assignedToUserId ? String(doc.assignedToUserId) : undefined,
    assignedToNameSnapshot: doc.assignedToNameSnapshot,
    externalAssignee: doc.externalAssignee
      ? {
          name: doc.externalAssignee.name,
          // Phone only for admin views.
          phone: options.includeInternalNotes ? doc.externalAssignee.phone : undefined,
          company: doc.externalAssignee.company,
        }
      : undefined,
    resolutionNotes: doc.resolutionNotes,
    internalNotes: options.includeInternalNotes ? doc.internalNotes : undefined,
    cancellationReason: doc.cancellationReason,
    resolvedAt: doc.resolvedAt?.toISOString(),
    closedAt: doc.closedAt?.toISOString(),
    cancelledAt: doc.cancelledAt?.toISOString(),
    attachments: (doc.attachments ?? []).map((a) => serializeAttachment(a)),
    createdAt: new Date(doc.createdAt).toISOString(),
    updatedAt: new Date(doc.updatedAt).toISOString(),
  };
}

export function serializeHistory(
  doc: ComplaintHistoryDocument | {
    _id: { toString(): string };
    complaintId: { toString(): string };
    societyId: { toString(): string };
    action: string;
    previousStatus?: string;
    newStatus?: string;
    previousPriority?: string;
    newPriority?: string;
    actorUserId: { toString(): string };
    actorRole: string;
    notes?: string;
    publicNotes?: string;
    assignmentSnapshot?: Record<string, unknown>;
    createdAt: Date;
  },
  options: { includeAdminNotes?: boolean } = {},
) {
  return {
    id: String(doc._id),
    complaintId: String(doc.complaintId),
    societyId: String(doc.societyId),
    action: doc.action,
    previousStatus: doc.previousStatus,
    newStatus: doc.newStatus,
    previousPriority: doc.previousPriority,
    newPriority: doc.newPriority,
    actorUserId: String(doc.actorUserId),
    actorRole: doc.actorRole,
    notes: options.includeAdminNotes ? doc.notes : undefined,
    publicNotes: doc.publicNotes,
    assignmentSnapshot: doc.assignmentSnapshot
      ? {
          assignmentType: doc.assignmentSnapshot.assignmentType,
          assignedToUserId: doc.assignmentSnapshot.assignedToUserId,
          assignedToNameSnapshot: doc.assignmentSnapshot.assignedToNameSnapshot,
          externalAssigneeName: doc.assignmentSnapshot.externalAssigneeName,
        }
      : undefined,
    createdAt: new Date(doc.createdAt).toISOString(),
  };
}
