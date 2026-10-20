import { getEnv } from '../../../config/env';
import { withTransaction } from '../../../database/connection';
import {
  badRequest,
  conflict,
  forbidden,
  notFound,
} from '../../../shared/errors/app-error';
import { generateOtp, hashToken, safeEqualHex } from '../../../utils/crypto';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { FlatModel } from '../../society/models/flat.model';
import { WingModel } from '../../society/models/wing.model';
import { MembershipModel } from '../../users/models/membership.model';
import { UserModel } from '../../users/models/user.model';
import { VisitorLogModel } from '../models/visitor-log.model';
import { normalizeEmail } from '../../../utils/crypto';
import { notifyBusinessEvent } from '../../notifications/services/business-notify.service';
import { deliverVisitorEntryOtp } from '../providers/visitor-otp-email.provider';
import {
  emitVisitorEvent,
  visitorEventPayloadFromDoc,
} from './visitor-events.service';
import { serializeVisitor } from './visitor.serializers';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

async function resolveApprover(flat: {
  societyId: { toString(): string };
  occupancyStatus: string;
  activeOwnerUserId?: { toString(): string };
  activeTenantUserId?: { toString(): string };
  isActive: boolean;
}) {
  if (!flat.isActive) {
    throw badRequest('Flat is inactive', 'FLAT_INACTIVE');
  }
  if (flat.occupancyStatus === 'VACANT') {
    throw badRequest(
      'No active resident available for visitor approval on a vacant flat',
      'NO_ACTIVE_RESIDENT',
    );
  }

  if (flat.occupancyStatus === 'OWNER_OCCUPIED') {
    if (!flat.activeOwnerUserId) {
      throw badRequest('No active owner assigned to this flat', 'NO_ACTIVE_RESIDENT');
    }
    const ownerId = String(flat.activeOwnerUserId);
    const owner = await UserModel.findById(ownerId).lean();
    if (!owner?.isActive) {
      throw badRequest('Active owner account is not available', 'NO_ACTIVE_RESIDENT');
    }
    const membership = await MembershipModel.findOne({
      societyId: flat.societyId,
      userId: ownerId,
      role: 'OWNER',
      isActive: true,
    }).lean();
    if (!membership) {
      throw badRequest('Owner membership is not active', 'NO_ACTIVE_RESIDENT');
    }
    return { userId: ownerId, role: 'OWNER' as const };
  }

  if (flat.occupancyStatus === 'TENANT_OCCUPIED') {
    if (!flat.activeTenantUserId) {
      throw badRequest('No active tenant assigned to this flat', 'NO_ACTIVE_RESIDENT');
    }
    const tenantId = String(flat.activeTenantUserId);
    const tenant = await UserModel.findById(tenantId).lean();
    if (!tenant?.isActive) {
      throw badRequest('Active tenant account is not available', 'NO_ACTIVE_RESIDENT');
    }
    const membership = await MembershipModel.findOne({
      societyId: flat.societyId,
      userId: tenantId,
      role: 'TENANT',
      isActive: true,
    }).lean();
    if (!membership) {
      throw badRequest('Tenant membership is not active', 'NO_ACTIVE_RESIDENT');
    }
    return { userId: tenantId, role: 'TENANT' as const };
  }

  throw badRequest('Unsupported occupancy status for visitor routing', 'INVALID_OCCUPANCY');
}

export async function createVisitorRequest(
  societyId: string,
  guardUserId: string,
  input: {
    flatId: string;
    visitorName: string;
    visitorPhone: string;
    visitorEmail?: string;
    visitorType: string;
    purpose: string;
    vehicleNumber?: string;
    numberOfVisitors: number;
    notes?: string;
  },
  actor: Actor,
) {
  const flat = await FlatModel.findOne({
    _id: parseObjectId(input.flatId, 'flatId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!flat) throw notFound('Flat not found in this society');

  const approver = await resolveApprover(flat);
  const wing = await WingModel.findById(flat.wingId).select('code').lean();

  const visitor = await withTransaction(async (session) => {
    const [doc] = await VisitorLogModel.create(
      [
        {
          societyId,
          flatId: flat._id,
          wingId: flat.wingId,
          visitorName: input.visitorName.trim(),
          visitorPhone: input.visitorPhone.trim(),
          visitorEmail: input.visitorEmail
            ? normalizeEmail(input.visitorEmail)
            : undefined,
          visitorType: input.visitorType,
          purpose: input.purpose.trim(),
          vehicleNumber: input.vehicleNumber?.trim(),
          numberOfVisitors: input.numberOfVisitors,
          requestedByGuardId: guardUserId,
          assignedResidentUserId: approver.userId,
          assignedResidentRole: approver.role,
          approvalStatus: 'PENDING',
          entryStatus: 'NOT_ENTERED',
          otpAttempts: 0,
          notes: input.notes,
          flatNumberSnapshot: flat.number,
          wingCodeSnapshot: wing?.code ?? '',
        },
      ],
      { session },
    );

    await writeAuditLog(
      {
        action: 'VISITOR_REQUESTED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'VisitorLog',
        targetId: String(doc._id),
        metadata: {
          flatId: String(flat._id),
          assignedResidentUserId: approver.userId,
          assignedResidentRole: approver.role,
          visitorType: input.visitorType,
        },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );

    return doc;
  });

  emitVisitorEvent('visitor:approval_requested', visitorEventPayloadFromDoc(visitor), {
    includeGuards: true,
  });

  await notifyBusinessEvent({
    societyId,
    recipientUserId: String(visitor.assignedResidentUserId),
    type: 'VISITOR_REQUEST',
    title: 'Visitor approval requested',
    body: `${visitor.visitorName} is waiting at the gate for ${visitor.wingCodeSnapshot}-${visitor.flatNumberSnapshot}`,
    relatedEntityType: 'VisitorLog',
    relatedEntityId: String(visitor._id),
    idempotencyKey: `VISITOR_REQUEST:${String(visitor._id)}`,
  });

  return serializeVisitor(visitor, { forGuard: true, includeOtpMeta: true });
}

export async function listVisitorsForSociety(
  societyId: string,
  query: {
    approvalStatus?: string;
    entryStatus?: string;
    flatId?: string;
    wingCode?: string;
    visitorType?: string;
    visitorPhone?: string;
    visitorName?: string;
    from?: Date;
    to?: Date;
    assignedResidentUserId?: string;
    page?: number;
    limit?: number;
    forGuard?: boolean;
  },
) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (query.approvalStatus) filter.approvalStatus = query.approvalStatus;
  if (query.entryStatus) filter.entryStatus = query.entryStatus;
  if (query.flatId) filter.flatId = parseObjectId(query.flatId, 'flatId');
  if (query.wingCode) filter.wingCodeSnapshot = query.wingCode.toUpperCase();
  if (query.visitorType) filter.visitorType = query.visitorType;
  if (query.visitorPhone) filter.visitorPhone = query.visitorPhone.trim();
  if (query.assignedResidentUserId) {
    filter.assignedResidentUserId = parseObjectId(
      query.assignedResidentUserId,
      'assignedResidentUserId',
    );
  }
  if (query.visitorName) {
    const escaped = query.visitorName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    filter.visitorName = { $regex: escaped, $options: 'i' };
  }
  if (query.from || query.to) {
    filter.createdAt = {};
    if (query.from) (filter.createdAt as Record<string, Date>).$gte = query.from;
    if (query.to) (filter.createdAt as Record<string, Date>).$lte = query.to;
  }

  const [total, rows] = await Promise.all([
    VisitorLogModel.countDocuments(filter),
    VisitorLogModel.find(filter)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((row) =>
      serializeVisitor(row, { forGuard: query.forGuard, includeOtpMeta: true }),
    ),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function getVisitor(
  societyId: string,
  visitorId: string,
  options?: { forGuard?: boolean; assignedResidentUserId?: string },
) {
  const filter: Record<string, unknown> = {
    _id: parseObjectId(visitorId, 'visitorId'),
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (options?.assignedResidentUserId) {
    filter.assignedResidentUserId = options.assignedResidentUserId;
  }
  const doc = await VisitorLogModel.findOne(filter).lean();
  if (!doc) throw notFound('Visitor record not found');
  return serializeVisitor(doc, { forGuard: options?.forGuard, includeOtpMeta: true });
}

async function assertStillAssignedResident(visitor: {
  societyId: { toString(): string };
  flatId: { toString(): string };
  assignedResidentUserId: { toString(): string };
  assignedResidentRole: string;
}) {
  const flat = await FlatModel.findOne({
    _id: visitor.flatId,
    societyId: visitor.societyId,
  }).lean();
  if (!flat?.isActive) {
    throw forbidden('Flat is no longer active', 'FLAT_INACTIVE');
  }

  if (visitor.assignedResidentRole === 'OWNER') {
    if (flat.occupancyStatus !== 'OWNER_OCCUPIED') {
      throw forbidden('Owner is not the current approver for this flat', 'NOT_CURRENT_APPROVER');
    }
    if (String(flat.activeOwnerUserId) !== String(visitor.assignedResidentUserId)) {
      throw forbidden('Assigned owner is no longer active on this flat', 'NOT_CURRENT_APPROVER');
    }
  } else {
    if (flat.occupancyStatus !== 'TENANT_OCCUPIED') {
      throw forbidden('Tenant is not the current approver for this flat', 'NOT_CURRENT_APPROVER');
    }
    if (String(flat.activeTenantUserId) !== String(visitor.assignedResidentUserId)) {
      throw forbidden('Assigned tenant is no longer active on this flat', 'NOT_CURRENT_APPROVER');
    }
  }
}

export async function approveVisitor(
  societyId: string,
  visitorId: string,
  residentUserId: string,
  actor: Actor,
) {
  const existing = await VisitorLogModel.findOne({
    _id: parseObjectId(visitorId, 'visitorId'),
    societyId: parseObjectId(societyId, 'societyId'),
    assignedResidentUserId: residentUserId,
  });
  if (!existing) throw notFound('Visitor record not found');
  if (existing.approvalStatus === 'APPROVED') {
    return serializeVisitor(existing);
  }
  if (existing.approvalStatus !== 'PENDING') {
    throw conflict(`Cannot approve visitor in status ${existing.approvalStatus}`, 'INVALID_STATUS');
  }

  await assertStillAssignedResident(existing);

  const resident = await UserModel.findById(existing.assignedResidentUserId)
    .select('email')
    .lean();
  const deliveryEmail = existing.visitorEmail
    ? normalizeEmail(String(existing.visitorEmail))
    : resident?.email
      ? normalizeEmail(String(resident.email))
      : '';
  if (!deliveryEmail) {
    throw badRequest(
      'No usable email address for visitor OTP delivery. Provide visitorEmail on the request or ensure the assigned resident has an email.',
      'VISITOR_EMAIL_REQUIRED',
    );
  }

  const env = getEnv();
  const otp = generateOtp(6);
  const otpHash = hashToken(otp);
  const expiresAt = new Date(Date.now() + env.VISITOR_OTP_TTL_MS);

  const updated = await withTransaction(async (session) => {
    const claimed = await VisitorLogModel.findOneAndUpdate(
      {
        _id: existing._id,
        approvalStatus: 'PENDING',
        entryStatus: 'NOT_ENTERED',
      },
      {
        $set: {
          approvalStatus: 'APPROVED',
          approvedAt: new Date(),
          entryOtpHash: otpHash,
          entryOtpExpiresAt: expiresAt,
          otpAttempts: 0,
        },
      },
      { session, new: true },
    );
    if (!claimed) {
      const current = await VisitorLogModel.findById(existing._id).session(session);
      if (current?.approvalStatus === 'APPROVED') return current;
      throw conflict('Visitor request was already processed', 'ALREADY_PROCESSED');
    }

    await writeAuditLog(
      {
        action: 'VISITOR_APPROVED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'VisitorLog',
        targetId: visitorId,
        metadata: {
          flatId: String(claimed.flatId),
          otpExpiresAt: expiresAt.toISOString(),
        },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );

    return claimed;
  });

  const flatLabel = `${updated.wingCodeSnapshot}-${updated.flatNumberSnapshot}`;
  await deliverVisitorEntryOtp({
    toEmail: deliveryEmail,
    otp,
    visitorName: updated.visitorName,
    flatLabel,
  });

  emitVisitorEvent('visitor:approved', visitorEventPayloadFromDoc(updated));

  await notifyBusinessEvent({
    societyId,
    recipientUserId: String(updated.assignedResidentUserId),
    type: 'VISITOR_APPROVED',
    title: 'Visitor approved',
    body: `${updated.visitorName} was approved for ${updated.wingCodeSnapshot}-${updated.flatNumberSnapshot}`,
    relatedEntityType: 'VisitorLog',
    relatedEntityId: String(updated._id),
    idempotencyKey: `VISITOR_APPROVED:${String(updated._id)}`,
  });

  return serializeVisitor(updated, { includeOtpMeta: true });
}

export async function rejectVisitor(
  societyId: string,
  visitorId: string,
  residentUserId: string,
  reason: string | undefined,
  actor: Actor,
) {
  const existing = await VisitorLogModel.findOne({
    _id: parseObjectId(visitorId, 'visitorId'),
    societyId: parseObjectId(societyId, 'societyId'),
    assignedResidentUserId: residentUserId,
  });
  if (!existing) throw notFound('Visitor record not found');
  if (existing.approvalStatus === 'REJECTED') {
    return serializeVisitor(existing);
  }
  if (existing.approvalStatus !== 'PENDING') {
    throw conflict(`Cannot reject visitor in status ${existing.approvalStatus}`, 'INVALID_STATUS');
  }

  await assertStillAssignedResident(existing);

  const updated = await withTransaction(async (session) => {
    const claimed = await VisitorLogModel.findOneAndUpdate(
      { _id: existing._id, approvalStatus: 'PENDING' },
      {
        $set: {
          approvalStatus: 'REJECTED',
          rejectedAt: new Date(),
          rejectionReason: reason,
        },
        $unset: { entryOtpHash: 1, entryOtpExpiresAt: 1 },
      },
      { session, new: true },
    );
    if (!claimed) {
      const current = await VisitorLogModel.findById(existing._id).session(session);
      if (current?.approvalStatus === 'REJECTED') return current;
      throw conflict('Visitor request was already processed', 'ALREADY_PROCESSED');
    }

    await writeAuditLog(
      {
        action: 'VISITOR_REJECTED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'VisitorLog',
        targetId: visitorId,
        metadata: { reason, flatId: String(claimed.flatId) },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );
    return claimed;
  });

  emitVisitorEvent('visitor:rejected', visitorEventPayloadFromDoc(updated));

  await notifyBusinessEvent({
    societyId,
    recipientUserId: String(updated.assignedResidentUserId),
    type: 'VISITOR_REJECTED',
    title: 'Visitor rejected',
    body: `${updated.visitorName} was rejected for ${updated.wingCodeSnapshot}-${updated.flatNumberSnapshot}`,
    relatedEntityType: 'VisitorLog',
    relatedEntityId: String(updated._id),
    idempotencyKey: `VISITOR_REJECTED:${String(updated._id)}`,
  });

  return serializeVisitor(updated);
}

export async function cancelVisitor(
  societyId: string,
  visitorId: string,
  residentUserId: string,
  actor: Actor,
) {
  const existing = await VisitorLogModel.findOne({
    _id: parseObjectId(visitorId, 'visitorId'),
    societyId: parseObjectId(societyId, 'societyId'),
    assignedResidentUserId: residentUserId,
  });
  if (!existing) throw notFound('Visitor record not found');
  if (existing.approvalStatus === 'CANCELLED') {
    return serializeVisitor(existing);
  }
  if (!['PENDING', 'APPROVED'].includes(existing.approvalStatus)) {
    throw conflict(`Cannot cancel visitor in status ${existing.approvalStatus}`, 'INVALID_STATUS');
  }
  if (existing.entryStatus !== 'NOT_ENTERED') {
    throw conflict('Cannot cancel a visitor who has already entered', 'ALREADY_ENTERED');
  }

  const updated = await withTransaction(async (session) => {
    const claimed = await VisitorLogModel.findOneAndUpdate(
      {
        _id: existing._id,
        approvalStatus: { $in: ['PENDING', 'APPROVED'] },
        entryStatus: 'NOT_ENTERED',
      },
      {
        $set: { approvalStatus: 'CANCELLED' },
        $unset: { entryOtpHash: 1, entryOtpExpiresAt: 1 },
      },
      { session, new: true },
    );
    if (!claimed) {
      throw conflict('Visitor request was already processed', 'ALREADY_PROCESSED');
    }
    await writeAuditLog(
      {
        action: 'VISITOR_CANCELLED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'VisitorLog',
        targetId: visitorId,
        metadata: { flatId: String(claimed.flatId) },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );
    return claimed;
  });

  return serializeVisitor(updated);
}

export async function verifyEntryOtp(
  societyId: string,
  visitorId: string,
  otp: string,
  guardUserId: string,
  actor: Actor,
) {
  const env = getEnv();
  const visitor = await VisitorLogModel.findOne({
    _id: parseObjectId(visitorId, 'visitorId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!visitor) throw notFound('Visitor record not found');

  if (visitor.approvalStatus !== 'APPROVED') {
    throw badRequest('Visitor is not approved for entry', 'NOT_APPROVED');
  }
  if (visitor.entryStatus !== 'NOT_ENTERED') {
    throw conflict('Visitor has already entered or exited', 'ALREADY_ENTERED');
  }
  if (!visitor.entryOtpHash || !visitor.entryOtpExpiresAt) {
    throw badRequest('No active entry OTP for this visitor', 'OTP_MISSING');
  }
  if (visitor.entryOtpExpiresAt.getTime() < Date.now()) {
    throw badRequest('Entry OTP has expired', 'OTP_EXPIRED');
  }
  if (visitor.otpAttempts >= env.VISITOR_OTP_MAX_ATTEMPTS) {
    throw forbidden('Maximum OTP attempts exceeded', 'OTP_MAX_ATTEMPTS');
  }

  const providedHash = hashToken(otp.trim());
  if (!safeEqualHex(providedHash, visitor.entryOtpHash)) {
    visitor.otpAttempts += 1;
    await visitor.save();
    await writeAuditLog({
      action: 'VISITOR_OTP_VERIFIED',
      actorUserId: actor.userId,
      societyId,
      targetType: 'VisitorLog',
      targetId: visitorId,
      metadata: { success: false, attempts: visitor.otpAttempts },
      ipAddress: actor.ipAddress,
      userAgent: actor.userAgent,
    });
    throw forbidden('Invalid entry OTP', 'OTP_INVALID');
  }

  const updated = await withTransaction(async (session) => {
    const claimed = await VisitorLogModel.findOneAndUpdate(
      {
        _id: visitor._id,
        approvalStatus: 'APPROVED',
        entryStatus: 'NOT_ENTERED',
        entryOtpHash: visitor.entryOtpHash,
      },
      {
        $set: {
          entryStatus: 'ENTERED',
          entryAt: new Date(),
          checkedInBy: guardUserId,
        },
        $unset: { entryOtpHash: 1, entryOtpExpiresAt: 1 },
      },
      { session, new: true },
    );
    if (!claimed) {
      throw conflict('Visitor entry was already recorded', 'ALREADY_ENTERED');
    }

    await writeAuditLog(
      {
        action: 'VISITOR_OTP_VERIFIED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'VisitorLog',
        targetId: visitorId,
        metadata: { success: true },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );
    await writeAuditLog(
      {
        action: 'VISITOR_ENTERED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'VisitorLog',
        targetId: visitorId,
        metadata: {
          flatId: String(claimed.flatId),
          checkedInBy: guardUserId,
          entryAt: claimed.entryAt?.toISOString(),
        },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );
    return claimed;
  });

  emitVisitorEvent('visitor:entered', visitorEventPayloadFromDoc(updated));
  return serializeVisitor(updated, { forGuard: true, includeOtpMeta: true });
}

export async function checkoutVisitor(
  societyId: string,
  visitorId: string,
  guardUserId: string,
  actor: Actor,
) {
  const visitor = await VisitorLogModel.findOne({
    _id: parseObjectId(visitorId, 'visitorId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!visitor) throw notFound('Visitor record not found');
  if (visitor.entryStatus === 'EXITED') {
    return serializeVisitor(visitor, { forGuard: true });
  }
  if (visitor.entryStatus !== 'ENTERED') {
    throw badRequest('Visitor is not currently inside', 'NOT_ENTERED');
  }

  const updated = await withTransaction(async (session) => {
    const claimed = await VisitorLogModel.findOneAndUpdate(
      { _id: visitor._id, entryStatus: 'ENTERED' },
      {
        $set: {
          entryStatus: 'EXITED',
          exitAt: new Date(),
          checkedOutBy: guardUserId,
        },
      },
      { session, new: true },
    );
    if (!claimed) {
      const current = await VisitorLogModel.findById(visitor._id).session(session);
      if (current?.entryStatus === 'EXITED') return current;
      throw conflict('Visitor checkout race', 'CHECKOUT_CONFLICT');
    }

    await writeAuditLog(
      {
        action: 'VISITOR_EXITED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'VisitorLog',
        targetId: visitorId,
        metadata: {
          flatId: String(claimed.flatId),
          checkedOutBy: guardUserId,
          exitAt: claimed.exitAt?.toISOString(),
        },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );
    return claimed;
  });

  emitVisitorEvent('visitor:exited', visitorEventPayloadFromDoc(updated));
  return serializeVisitor(updated, { forGuard: true });
}

export async function getGuardDashboard(societyId: string) {
  const societyObjectId = parseObjectId(societyId, 'societyId');
  const startOfDay = new Date();
  startOfDay.setHours(0, 0, 0, 0);

  const [
    currentlyInside,
    pendingApprovals,
    awaitingEntry,
    enteredToday,
    exitedToday,
    recent,
  ] = await Promise.all([
    VisitorLogModel.countDocuments({
      societyId: societyObjectId,
      entryStatus: 'ENTERED',
    }),
    VisitorLogModel.countDocuments({
      societyId: societyObjectId,
      approvalStatus: 'PENDING',
    }),
    VisitorLogModel.countDocuments({
      societyId: societyObjectId,
      approvalStatus: 'APPROVED',
      entryStatus: 'NOT_ENTERED',
    }),
    VisitorLogModel.countDocuments({
      societyId: societyObjectId,
      entryAt: { $gte: startOfDay },
    }),
    VisitorLogModel.countDocuments({
      societyId: societyObjectId,
      exitAt: { $gte: startOfDay },
    }),
    VisitorLogModel.find({ societyId: societyObjectId })
      .sort({ createdAt: -1 })
      .limit(10)
      .lean(),
  ]);

  return {
    currentlyInside,
    pendingApprovals,
    awaitingEntry,
    enteredToday,
    exitedToday,
    recent: recent.map((row) => serializeVisitor(row, { forGuard: true, includeOtpMeta: true })),
  };
}

export async function getAdminVisitorSummary(societyId: string) {
  const societyObjectId = parseObjectId(societyId, 'societyId');
  const byApproval = await VisitorLogModel.aggregate<{ _id: string; count: number }>([
    { $match: { societyId: societyObjectId } },
    { $group: { _id: '$approvalStatus', count: { $sum: 1 } } },
  ]);
  const byEntry = await VisitorLogModel.aggregate<{ _id: string; count: number }>([
    { $match: { societyId: societyObjectId } },
    { $group: { _id: '$entryStatus', count: { $sum: 1 } } },
  ]);
  const total = await VisitorLogModel.countDocuments({ societyId: societyObjectId });
  return {
    total,
    byApprovalStatus: Object.fromEntries(byApproval.map((r) => [r._id, r.count])),
    byEntryStatus: Object.fromEntries(byEntry.map((r) => [r._id, r.count])),
  };
}
