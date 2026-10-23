import { formatFlatLabel } from '../../../utils/flat-label';
import type { VisitorLogDocument } from '../models/visitor-log.model';

type VisitorLean = {
  _id: { toString(): string };
  societyId: { toString(): string };
  flatId: { toString(): string };
  visitorName: string;
  visitorPhone: string;
  visitorType: string;
  purpose: string;
  vehicleNumber?: string;
  numberOfVisitors: number;
  requestedByGuardId: { toString(): string };
  assignedResidentUserId: { toString(): string };
  assignedResidentRole: string;
  notifiedResidentUserIds?: { toString(): string }[];
  approvalStatus: string;
  entryStatus: string;
  entryMode?: string;
  resolution?: string;
  pendingExpiresAt?: Date;
  actedByUserId?: { toString(): string };
  entryOtpExpiresAt?: Date;
  otpAttempts: number;
  otpVerifiedAt?: Date;
  approvedAt?: Date;
  rejectedAt?: Date;
  entryAt?: Date;
  exitAt?: Date;
  checkedInBy?: { toString(): string };
  checkedOutBy?: { toString(): string };
  rejectionReason?: string;
  notes?: string;
  flatNumberSnapshot: string;
  wingCodeSnapshot: string;
  expiredAt?: Date;
  createdAt: Date;
  updatedAt: Date;
  entryOtpHash?: string;
};

export function visitorRequestState(doc: {
  approvalStatus: string;
  entryStatus: string;
  resolution?: string;
}): string {
  if (doc.resolution === 'PARCEL') return 'CANCELLED';
  if (doc.entryStatus === 'ENTERED' || doc.entryStatus === 'EXITED') return 'ENTRY_COMPLETED';
  if (doc.approvalStatus === 'REJECTED') return 'DENIED';
  return doc.approvalStatus;
}

export function serializeVisitor(
  doc: VisitorLean | VisitorLogDocument,
  options?: { forGuard?: boolean; includeOtpMeta?: boolean; revealVisitorContact?: boolean },
) {
  const forGuard = options?.forGuard ?? false;
  const revealVisitorContact = options?.revealVisitorContact ?? false;
  const entryMode = doc.entryMode === 'WALK_IN' ? 'WALK_IN' : 'OTP';
  return {
    id: String(doc._id),
    societyId: String(doc.societyId),
    flatId: String(doc.flatId),
    visitorName: doc.visitorName,
    // Guards see masked phone until OTP succeeds or walk-in is approved; admins/residents see full.
    visitorPhone:
      forGuard && !revealVisitorContact && entryMode === 'OTP'
        ? maskPhone(doc.visitorPhone)
        : doc.visitorPhone,
    visitorType: doc.visitorType,
    purpose: doc.purpose,
    vehicleNumber: doc.vehicleNumber,
    numberOfVisitors: doc.numberOfVisitors,
    requestedByGuardId: String(doc.requestedByGuardId),
    assignedResidentUserId: forGuard ? undefined : String(doc.assignedResidentUserId),
    assignedResidentRole: forGuard ? undefined : doc.assignedResidentRole,
    approvalStatus: doc.approvalStatus,
    entryStatus: doc.entryStatus,
    entryMode,
    requestState: visitorRequestState(doc),
    resolution: doc.resolution,
    pendingExpiresAt: doc.pendingExpiresAt
      ? new Date(doc.pendingExpiresAt).toISOString()
      : undefined,
    otpExpiresAt:
      options?.includeOtpMeta && doc.entryOtpExpiresAt
        ? doc.entryOtpExpiresAt.toISOString()
        : undefined,
    hasActiveOtp: Boolean(doc.entryOtpHash && doc.entryOtpExpiresAt && doc.entryOtpExpiresAt > new Date()),
    otpVerified: Boolean(doc.otpVerifiedAt),
    otpAttempts: options?.includeOtpMeta ? doc.otpAttempts : undefined,
    approvedAt: doc.approvedAt?.toISOString(),
    rejectedAt: doc.rejectedAt?.toISOString(),
    entryAt: doc.entryAt?.toISOString(),
    exitAt: doc.exitAt?.toISOString(),
    checkedInBy: doc.checkedInBy ? String(doc.checkedInBy) : undefined,
    checkedOutBy: doc.checkedOutBy ? String(doc.checkedOutBy) : undefined,
    actedByUserId: forGuard
      ? undefined
      : doc.actedByUserId
        ? String(doc.actedByUserId)
        : undefined,
    rejectionReason: doc.rejectionReason,
    notes: doc.notes,
    flatNumberSnapshot: doc.flatNumberSnapshot,
    wingCodeSnapshot: doc.wingCodeSnapshot,
    flatLabel: formatFlatLabel(doc.wingCodeSnapshot, doc.flatNumberSnapshot),
    expiredAt: doc.expiredAt?.toISOString(),
    createdAt: new Date(doc.createdAt).toISOString(),
    updatedAt: new Date(doc.updatedAt).toISOString(),
  };
}

function maskPhone(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  if (digits.length < 4) return '****';
  return `${'*'.repeat(Math.max(0, digits.length - 4))}${digits.slice(-4)}`;
}
