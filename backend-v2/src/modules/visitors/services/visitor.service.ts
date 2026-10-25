import { DEMO_VISITOR_OTP, isDemoMode } from '../../../config/demo';
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
import { DEV_BYPASS_OTP } from '../../auth/providers/otp-dev-bypass';
import { FlatModel } from '../../society/models/flat.model';
import { SocietyModel } from '../../society/models/society.model';
import { WingModel } from '../../society/models/wing.model';
import { MembershipModel } from '../../users/models/membership.model';
import { UserModel } from '../../users/models/user.model';
import { getFlatAccess } from '../../users/services/access-control.service';
import { VisitorLogModel, type VisitorLogDocument } from '../models/visitor-log.model';
import { createParcelFromVisitor } from './parcel.service';
import { normalizeEmail } from '../../../utils/crypto';
import { notifyBusinessEvent } from '../../notifications/services/business-notify.service';
import { deliverVisitorEntryOtp } from '../providers/visitor-otp-email.provider';
import {
  emitVisitorEvent,
  visitorEventPayloadFromDoc,
} from './visitor-events.service';
import { formatFlatLabel } from '../../../utils/flat-label';
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

async function guardDisplayName(userId: string): Promise<string> {
  const user = await UserModel.findById(userId).select('name').lean();
  const name = user?.name?.trim();
  return name && name.length > 0 ? name : 'Security';
}

async function resolveNotifiedResidentIds(
  societyId: string,
  flat: {
    _id: { toString(): string };
    societyId: { toString(): string };
  },
  primaryUserId: string,
): Promise<string[]> {
  const ids = new Set<string>([primaryUserId]);
  const society = await SocietyModel.findById(societyId).select('config').lean();
  const policy = society?.config?.visitorApprovalPolicy ?? 'PRIMARY_OCCUPIER';
  if (policy !== 'ALL_AUTHORIZED') return [...ids];

  const members = await MembershipModel.find({
    societyId: flat.societyId,
    flatId: flat._id,
    isActive: true,
    role: { $in: ['OWNER', 'TENANT'] },
  })
    .select('userId')
    .lean();

  for (const member of members) {
    const access = await getFlatAccess({
      userId: String(member.userId),
      societyId,
      flatId: String(flat._id),
    });
    if (access.residential) ids.add(String(member.userId));
  }
  return [...ids];
}

function extraResidentIds(
  visitor: { assignedResidentUserId: { toString(): string }; notifiedResidentUserIds?: { toString(): string }[] },
): string[] {
  const assigned = String(visitor.assignedResidentUserId);
  return (visitor.notifiedResidentUserIds ?? [])
    .map((id) => String(id))
    .filter((id) => id !== assigned);
}

/** Stop ringing on every notified resident device, and tell the guard. */
async function notifyWalkInResolved(
  visitor: VisitorLogDocument,
  type: 'VISITOR_APPROVED' | 'VISITOR_REJECTED',
  title: string,
  body: string,
) {
  const societyId = String(visitor.societyId);
  const recipients = [
    String(visitor.assignedResidentUserId),
    ...extraResidentIds(visitor),
    String(visitor.requestedByGuardId),
  ];
  for (const recipientUserId of [...new Set(recipients)]) {
    await notifyBusinessEvent({
      societyId,
      recipientUserId,
      type,
      title,
      body,
      relatedEntityType: 'VisitorLog',
      relatedEntityId: String(visitor._id),
      idempotencyKey: `${type}:${String(visitor._id)}:${recipientUserId}`,
      metadata: {
        visitorName: visitor.visitorName,
        flatLabel: formatFlatLabel(visitor.wingCodeSnapshot, visitor.flatNumberSnapshot),
        entryMode: 'WALK_IN',
        callAction: 'stop',
        priority: 'high',
        deepLink: `apnasociety://visitor/${String(visitor._id)}`,
      },
    });
  }
}

function residentVisibilityFilter(userId: string) {
  const uid = parseObjectId(userId, 'assignedResidentUserId');
  return {
    $or: [{ assignedResidentUserId: uid }, { notifiedResidentUserIds: uid }],
  };
}

export async function createVisitorRequest(
  societyId: string,
  guardUserId: string,
  input: {
    flatId: string;
    visitorName: string;
    visitorPhone?: string;
    visitorEmail?: string;
    visitorType: string;
    purpose: string;
    vehicleNumber?: string;
    numberOfVisitors: number;
    notes?: string;
    entryMode?: 'OTP' | 'WALK_IN';
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
  const entryMode = input.entryMode === 'WALK_IN' ? 'WALK_IN' : 'OTP';
  const env = getEnv();
  const pendingExpiresAt =
    entryMode === 'WALK_IN' ? new Date(Date.now() + env.VISITOR_WALK_IN_TTL_MS) : undefined;
  const notifiedResidentUserIds = await resolveNotifiedResidentIds(
    societyId,
    flat,
    approver.userId,
  );

  const visitor = await withTransaction(async (session) => {
    const [doc] = await VisitorLogModel.create(
      [
        {
          societyId,
          flatId: flat._id,
          wingId: flat.wingId,
          visitorName: input.visitorName.trim(),
          visitorPhone: (input.visitorPhone ?? '').trim(),
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
          notifiedResidentUserIds,
          approvalStatus: 'PENDING',
          entryStatus: 'NOT_ENTERED',
          entryMode,
          pendingExpiresAt,
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
          entryMode,
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
    extraResidentUserIds: extraResidentIds(visitor),
  });

  const flatLabel = formatFlatLabel(visitor.wingCodeSnapshot, visitor.flatNumberSnapshot);
  const guardName = await guardDisplayName(guardUserId);
  const walkIn = entryMode === 'WALK_IN';
  const requestTime = new Date(visitor.createdAt).toISOString();
  for (const recipientUserId of notifiedResidentUserIds) {
    await notifyBusinessEvent({
      societyId,
      recipientUserId,
      type: 'VISITOR_REQUEST',
      title: walkIn ? 'Incoming visitor' : 'Visitor approval requested',
      body: walkIn
        ? `${visitor.visitorName} is at the gate for ${flatLabel}`
        : `${visitor.visitorName} is waiting at the gate for ${flatLabel}`,
      relatedEntityType: 'VisitorLog',
      relatedEntityId: String(visitor._id),
      idempotencyKey:
        recipientUserId === approver.userId
          ? `VISITOR_REQUEST:${String(visitor._id)}`
          : `VISITOR_REQUEST:${String(visitor._id)}:${recipientUserId}`,
      metadata: {
        visitorName: visitor.visitorName,
        visitorPhone: visitor.visitorPhone || '',
        visitorType: visitor.visitorType,
        purpose: visitor.purpose,
        flatLabel,
        guardName,
        requestId: String(visitor._id),
        requestTime,
        expiresAt: pendingExpiresAt?.toISOString() ?? '',
        entryMode,
        priority: walkIn ? 'high' : 'normal',
        channel: walkIn ? 'incoming_visitor_call' : 'visitors',
        deepLink: walkIn
          ? `apnasociety://visitor-approval/${String(visitor._id)}`
          : `apnasociety://visitor/${String(visitor._id)}`,
      },
    });
  }

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
    entryMode?: string;
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
  if (query.entryMode) filter.entryMode = query.entryMode;
  if (query.visitorPhone) filter.visitorPhone = query.visitorPhone.trim();
  if (query.assignedResidentUserId) {
    Object.assign(filter, residentVisibilityFilter(query.assignedResidentUserId));
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
    Object.assign(filter, residentVisibilityFilter(options.assignedResidentUserId));
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

async function assertCanActOnVisitor(
  visitor: {
    societyId: { toString(): string };
    flatId: { toString(): string };
    assignedResidentUserId: { toString(): string };
    assignedResidentRole: string;
    notifiedResidentUserIds?: { toString(): string }[];
  },
  residentUserId: string,
) {
  const notified = [
    String(visitor.assignedResidentUserId),
    ...(visitor.notifiedResidentUserIds ?? []).map((id) => String(id)),
  ];
  if (!notified.includes(residentUserId)) {
    throw notFound('Visitor record not found');
  }
  await assertStillAssignedResident(visitor);
  if (String(visitor.assignedResidentUserId) === residentUserId) return;
  const access = await getFlatAccess({
    userId: residentUserId,
    societyId: String(visitor.societyId),
    flatId: String(visitor.flatId),
  });
  if (!access.residential) {
    throw forbidden('You are not authorized to act on this visitor request', 'NOT_CURRENT_APPROVER');
  }
}

async function expirePendingIfTimedOut(existing: VisitorLogDocument) {
  if (existing.approvalStatus !== 'PENDING' || !existing.pendingExpiresAt) {
    return;
  }
  if (existing.pendingExpiresAt > new Date()) return;

  const now = new Date();
  const claimed = await VisitorLogModel.findOneAndUpdate(
    { _id: existing._id, approvalStatus: 'PENDING' },
    {
      $set: {
        approvalStatus: 'EXPIRED',
        expiredAt: now,
        resolution: 'EXPIRED',
      },
      $unset: { entryOtpHash: 1, entryOtpExpiresAt: 1 },
    },
    { new: true },
  );
  if (claimed) {
    emitVisitorEvent('visitor:expired', visitorEventPayloadFromDoc(claimed), {
      extraResidentUserIds: extraResidentIds(claimed),
    });
    await notifyVisitorExpired(claimed);
  }
  throw conflict('Visitor request has expired', 'REQUEST_EXPIRED');
}

async function notifyVisitorExpired(visitor: VisitorLogDocument) {
  const societyId = String(visitor.societyId);
  const flatLabel = formatFlatLabel(visitor.wingCodeSnapshot, visitor.flatNumberSnapshot);
  const recipients = [
    String(visitor.assignedResidentUserId),
    ...extraResidentIds(visitor),
    String(visitor.requestedByGuardId),
  ];
  for (const recipientUserId of [...new Set(recipients)]) {
    await notifyBusinessEvent({
      societyId,
      recipientUserId,
      type: 'VISITOR_EXPIRED',
      title: 'Visitor request expired',
      body: `The request for ${visitor.visitorName} at ${flatLabel} expired without a decision.`,
      relatedEntityType: 'VisitorLog',
      relatedEntityId: String(visitor._id),
      idempotencyKey: `VISITOR_EXPIRED:${String(visitor._id)}:${recipientUserId}`,
      metadata: {
        visitorName: visitor.visitorName,
        flatLabel,
        entryMode: visitor.entryMode ?? 'OTP',
        ...(visitor.entryMode === 'WALK_IN' ? { callAction: 'stop', priority: 'high' } : {}),
      },
    });
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
    ...residentVisibilityFilter(residentUserId),
  });
  if (!existing) throw notFound('Visitor record not found');
  if (existing.approvalStatus === 'APPROVED') {
    return serializeVisitor(existing);
  }
  if (existing.approvalStatus !== 'PENDING') {
    throw conflict(`Cannot approve visitor in status ${existing.approvalStatus}`, 'INVALID_STATUS');
  }

  await assertCanActOnVisitor(existing, residentUserId);
  await expirePendingIfTimedOut(existing);

  const env = getEnv();
  const isWalkIn = (existing.entryMode ?? 'OTP') === 'WALK_IN';

  if (isWalkIn) {
    const updatedWalkIn = await withTransaction(async (session) => {
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
            actedByUserId: residentUserId,
            resolution: 'ENTRY',
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
          metadata: { flatId: String(claimed.flatId), entryMode: 'WALK_IN' },
          ipAddress: actor.ipAddress,
          userAgent: actor.userAgent,
        },
        session,
      );
      return claimed;
    });

    emitVisitorEvent('visitor:approved', visitorEventPayloadFromDoc(updatedWalkIn), {
      extraResidentUserIds: extraResidentIds(updatedWalkIn),
    });
    await notifyWalkInResolved(
      updatedWalkIn,
      'VISITOR_APPROVED',
      'Visitor approved',
      `${updatedWalkIn.visitorName} was approved for ${formatFlatLabel(updatedWalkIn.wingCodeSnapshot, updatedWalkIn.flatNumberSnapshot)}. Confirm entry at the gate.`,
    );
    return serializeVisitor(updatedWalkIn, { includeOtpMeta: true });
  }
  const otpDevBypass = env.SMS_OTP_DEV_BYPASS && env.NODE_ENV !== 'production';

  const resident = await UserModel.findById(existing.assignedResidentUserId)
    .select('email')
    .lean();
  const deliveryEmail = existing.visitorEmail
    ? normalizeEmail(String(existing.visitorEmail))
    : resident?.email
      ? normalizeEmail(String(resident.email))
      : '';
  if (!deliveryEmail && !otpDevBypass && !isDemoMode()) {
    throw badRequest(
      'No usable email address for visitor OTP delivery. Provide visitorEmail on the request or ensure the assigned resident has an email.',
      'VISITOR_EMAIL_REQUIRED',
    );
  }

  const otp = isDemoMode() ? DEMO_VISITOR_OTP : otpDevBypass ? DEV_BYPASS_OTP : generateOtp(6);
  const otpHash = hashToken(otp);
  const expiresAt = isDemoMode()
    ? new Date('2099-12-31T23:59:59.999Z')
    : new Date(Date.now() + env.VISITOR_OTP_TTL_MS);

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

  const flatLabel = formatFlatLabel(updated.wingCodeSnapshot, updated.flatNumberSnapshot);
  if (otpDevBypass || isDemoMode()) {
    // Fixed reviewer OTP — skip email/MSG91 in demo or local bypass.
  } else {
    await deliverVisitorEntryOtp({
      toEmail: deliveryEmail,
      otp,
      visitorName: updated.visitorName,
      flatLabel,
    });
  }

  emitVisitorEvent('visitor:approved', visitorEventPayloadFromDoc(updated), {
    extraResidentUserIds: extraResidentIds(updated),
  });

  await notifyBusinessEvent({
    societyId,
    recipientUserId: String(updated.assignedResidentUserId),
    type: 'VISITOR_APPROVED',
    title: 'Visitor approved',
    body: `${updated.visitorName} was approved for ${formatFlatLabel(updated.wingCodeSnapshot, updated.flatNumberSnapshot)}`,
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
    ...residentVisibilityFilter(residentUserId),
  });
  if (!existing) throw notFound('Visitor record not found');
  if (existing.approvalStatus === 'REJECTED') {
    return serializeVisitor(existing);
  }
  if (existing.approvalStatus !== 'PENDING') {
    throw conflict(`Cannot reject visitor in status ${existing.approvalStatus}`, 'INVALID_STATUS');
  }

  await assertCanActOnVisitor(existing, residentUserId);
  await expirePendingIfTimedOut(existing);

  const updated = await withTransaction(async (session) => {
    const claimed = await VisitorLogModel.findOneAndUpdate(
      { _id: existing._id, approvalStatus: 'PENDING' },
      {
        $set: {
          approvalStatus: 'REJECTED',
          rejectedAt: new Date(),
          rejectionReason: reason,
          actedByUserId: residentUserId,
          resolution: 'DENIED',
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

  emitVisitorEvent('visitor:rejected', visitorEventPayloadFromDoc(updated), {
    extraResidentUserIds: extraResidentIds(updated),
  });

  if ((updated.entryMode ?? 'OTP') === 'WALK_IN') {
    await notifyWalkInResolved(
      updated,
      'VISITOR_REJECTED',
      'Visitor rejected',
      `${updated.visitorName} was denied entry to ${formatFlatLabel(updated.wingCodeSnapshot, updated.flatNumberSnapshot)}.`,
    );
  } else {
    await notifyBusinessEvent({
      societyId,
      recipientUserId: String(updated.assignedResidentUserId),
      type: 'VISITOR_REJECTED',
      title: 'Visitor rejected',
      body: `${updated.visitorName} was rejected for ${formatFlatLabel(updated.wingCodeSnapshot, updated.flatNumberSnapshot)}`,
      relatedEntityType: 'VisitorLog',
      relatedEntityId: String(updated._id),
      idempotencyKey: `VISITOR_REJECTED:${String(updated._id)}`,
    });
    await notifyBusinessEvent({
      societyId,
      recipientUserId: String(updated.requestedByGuardId),
      type: 'VISITOR_REJECTED',
      title: 'Visitor denied',
      body: `${updated.visitorName} was denied entry to ${formatFlatLabel(updated.wingCodeSnapshot, updated.flatNumberSnapshot)}.`,
      relatedEntityType: 'VisitorLog',
      relatedEntityId: String(updated._id),
      idempotencyKey: `VISITOR_REJECTED:${String(updated._id)}:guard`,
      metadata: {
        visitorName: updated.visitorName,
        entryMode: updated.entryMode ?? 'OTP',
        deepLink: `apnasociety://visitor/${String(updated._id)}`,
      },
    });
  }

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
    ...residentVisibilityFilter(residentUserId),
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

async function serializeAuthorizedVisitor(doc: VisitorLogDocument) {
  const society = await SocietyModel.findById(doc.societyId).select('name').lean();
  return {
    ...serializeVisitor(doc, {
      includeOtpMeta: true,
      forGuard: true,
      revealVisitorContact: true,
    }),
    societyName: society?.name,
    otpVerified: Boolean(doc.otpVerifiedAt),
  };
}

async function markOtpVerified(
  visitor: {
    _id: { toString(): string };
    societyId: { toString(): string };
    entryOtpHash?: string;
  },
  actor: Actor,
) {
  const updated = await withTransaction(async (session) => {
    const claimed = await VisitorLogModel.findOneAndUpdate(
      {
        _id: visitor._id,
        approvalStatus: 'APPROVED',
        entryStatus: 'NOT_ENTERED',
        entryOtpHash: visitor.entryOtpHash,
      },
      {
        $set: { otpVerifiedAt: new Date() },
        $unset: { entryOtpHash: 1, entryOtpExpiresAt: 1 },
      },
      { session, new: true },
    );
    if (!claimed) {
      throw conflict('Visitor OTP was already used or entry was recorded', 'ALREADY_ENTERED');
    }

    await writeAuditLog(
      {
        action: 'VISITOR_OTP_VERIFIED',
        actorUserId: actor.userId,
        societyId: String(visitor.societyId),
        targetType: 'VisitorLog',
        targetId: String(visitor._id),
        metadata: { success: true },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );
    return claimed;
  });

  return serializeAuthorizedVisitor(updated);
}

function assertOtpStillUsable(visitor: {
  approvalStatus: string;
  entryStatus: string;
  entryOtpHash?: string;
  entryOtpExpiresAt?: Date;
  otpAttempts: number;
}) {
  const env = getEnv();
  if (visitor.approvalStatus !== 'APPROVED') {
    throw badRequest('Visitor is not approved for entry', 'NOT_APPROVED');
  }
  if (visitor.entryStatus !== 'NOT_ENTERED') {
    throw conflict('Visitor has already entered or exited', 'ALREADY_ENTERED');
  }
  if (!visitor.entryOtpHash || !visitor.entryOtpExpiresAt) {
    throw badRequest('No active entry OTP for this visitor', 'OTP_MISSING');
  }
  if (!isDemoMode() && visitor.entryOtpExpiresAt.getTime() < Date.now()) {
    throw badRequest('Entry OTP has expired', 'OTP_EXPIRED');
  }
  if (visitor.otpAttempts >= env.VISITOR_OTP_MAX_ATTEMPTS) {
    throw forbidden('Maximum OTP attempts exceeded', 'OTP_MAX_ATTEMPTS');
  }
}

/** OTP-only verification. Does not record physical entry. */
export async function verifyEntryOtpByCode(societyId: string, otp: string, actor: Actor) {
  const providedHash = hashToken(otp.trim());
  const demoOtpOk = isDemoMode() && otp.trim() === DEMO_VISITOR_OTP;
  const matches = await VisitorLogModel.find({
    societyId: parseObjectId(societyId, 'societyId'),
    approvalStatus: 'APPROVED',
    entryStatus: 'NOT_ENTERED',
    ...(demoOtpOk ? {} : { entryOtpHash: providedHash }),
  });
  if (matches.length !== 1 && !(demoOtpOk && matches.length >= 1)) {
    throw forbidden('Invalid or expired entry OTP', 'OTP_INVALID');
  }
  const visitor = matches[0];
  assertOtpStillUsable(visitor);
  return markOtpVerified(visitor, actor);
}

export async function verifyEntryOtp(
  societyId: string,
  visitorId: string,
  otp: string,
  _guardUserId: string,
  actor: Actor,
) {
  const visitor = await VisitorLogModel.findOne({
    _id: parseObjectId(visitorId, 'visitorId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!visitor) throw notFound('Visitor record not found');

  assertOtpStillUsable(visitor);

  const providedHash = hashToken(otp.trim());
  const demoOtpOk = isDemoMode() && otp.trim() === DEMO_VISITOR_OTP;
  if (!demoOtpOk && !safeEqualHex(providedHash, visitor.entryOtpHash!)) {
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

  return markOtpVerified(visitor, actor);
}

export async function confirmVisitorEntry(
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
  if (visitor.resolution === 'PARCEL') {
    throw forbidden('Parcel authorization cannot grant visitor entry', 'PARCEL_NOT_ENTRY');
  }
  if (visitor.approvalStatus !== 'APPROVED') {
    throw badRequest('Visitor is not approved for entry', 'NOT_APPROVED');
  }
  if (visitor.entryStatus === 'ENTERED' || visitor.entryStatus === 'EXITED') {
    throw conflict('Visitor entry was already recorded', 'ALREADY_ENTERED');
  }
  const isWalkIn = (visitor.entryMode ?? 'OTP') === 'WALK_IN';
  if (!isWalkIn && !visitor.otpVerifiedAt) {
    throw forbidden('Verify the visitor OTP before recording entry', 'OTP_NOT_VERIFIED');
  }

  const entryFilter: Record<string, unknown> = {
    _id: visitor._id,
    approvalStatus: 'APPROVED',
    entryStatus: 'NOT_ENTERED',
  };
  if (!isWalkIn) {
    entryFilter.otpVerifiedAt = { $exists: true, $ne: null };
  }

  const updated = await withTransaction(async (session) => {
    const claimed = await VisitorLogModel.findOneAndUpdate(
      entryFilter,
      {
        $set: {
          entryStatus: 'ENTERED',
          entryAt: new Date(),
          checkedInBy: guardUserId,
          resolution: 'ENTRY',
        },
      },
      { session, new: true },
    );
    if (!claimed) {
      throw conflict('Visitor entry was already recorded', 'ALREADY_ENTERED');
    }

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

  emitVisitorEvent('visitor:entered', visitorEventPayloadFromDoc(updated), {
    extraResidentUserIds: extraResidentIds(updated),
  });
  const entryFlatLabel = formatFlatLabel(updated.wingCodeSnapshot, updated.flatNumberSnapshot);
  const entryGuardName = await guardDisplayName(guardUserId);
  const entryRecipients = [
    String(updated.assignedResidentUserId),
    ...extraResidentIds(updated),
  ];
  for (const recipientUserId of [...new Set(entryRecipients)]) {
    await notifyBusinessEvent({
      societyId,
      recipientUserId,
      type: 'VISITOR_ENTERED',
      title: 'Visitor Entered Society',
      body: 'Your visitor has entered the society.',
      relatedEntityType: 'VisitorLog',
      relatedEntityId: String(updated._id),
      idempotencyKey:
        recipientUserId === String(updated.assignedResidentUserId)
          ? `VISITOR_ENTERED:${String(updated._id)}`
          : `VISITOR_ENTERED:${String(updated._id)}:${recipientUserId}`,
      metadata: {
        visitorName: updated.visitorName,
        visitorPhone: updated.visitorPhone || '',
        visitorType: updated.visitorType,
        purpose: updated.purpose,
        flatLabel: entryFlatLabel,
        entryAt: updated.entryAt?.toISOString() ?? new Date().toISOString(),
        guardName: entryGuardName,
        entryMode: updated.entryMode ?? 'OTP',
        deepLink: `apnasociety://visitor/${String(updated._id)}`,
      },
    });
  }

  return serializeAuthorizedVisitor(updated);
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

export async function authorizeParcelHandover(
  societyId: string,
  visitorId: string,
  residentUserId: string,
  actor: Actor,
) {
  const existing = await VisitorLogModel.findOne({
    _id: parseObjectId(visitorId, 'visitorId'),
    societyId: parseObjectId(societyId, 'societyId'),
    ...residentVisibilityFilter(residentUserId),
  });
  if (!existing) throw notFound('Visitor record not found');
  if (existing.resolution === 'PARCEL') {
    const { ParcelHandoverModel } = await import('../models/parcel-handover.model');
    const parcel = await ParcelHandoverModel.findOne({ visitorLogId: existing._id }).lean();
    if (parcel) {
      const { serializeParcel } = await import('./parcel.service');
      return {
        visitor: serializeVisitor(existing),
        parcel: serializeParcel(parcel),
      };
    }
  }
  if (existing.approvalStatus !== 'PENDING') {
    throw conflict(
      `Cannot authorize a parcel from visitor status ${existing.approvalStatus}`,
      'INVALID_STATUS',
    );
  }
  if (existing.entryStatus !== 'NOT_ENTERED') {
    throw conflict('Cannot convert an entered visitor into a parcel', 'ALREADY_ENTERED');
  }

  await assertCanActOnVisitor(existing, residentUserId);
  await expirePendingIfTimedOut(existing);

  const { visitor: updated, parcel } = await withTransaction(async (session) => {
    const claimed = await VisitorLogModel.findOneAndUpdate(
      {
        _id: existing._id,
        approvalStatus: 'PENDING',
        entryStatus: 'NOT_ENTERED',
      },
      {
        $set: {
          approvalStatus: 'CANCELLED',
          actedByUserId: residentUserId,
          resolution: 'PARCEL',
        },
        $unset: { entryOtpHash: 1, entryOtpExpiresAt: 1 },
      },
      { session, new: true },
    );
    if (!claimed) {
      throw conflict('Visitor request was already processed', 'ALREADY_PROCESSED');
    }

    const created = await createParcelFromVisitor(claimed, actor, session);

    await writeAuditLog(
      {
        action: 'PARCEL_AUTHORIZED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'ParcelHandover',
        targetId: String(created._id),
        metadata: {
          visitorLogId: visitorId,
          flatId: String(claimed.flatId),
        },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );

    return { visitor: claimed, parcel: created };
  });

  emitVisitorEvent(
    'visitor:parcel_authorized',
    {
      ...visitorEventPayloadFromDoc(updated),
      parcelId: String(parcel._id),
    },
    { extraResidentUserIds: extraResidentIds(updated) },
  );

  const flatLabel = formatFlatLabel(updated.wingCodeSnapshot, updated.flatNumberSnapshot);
  await notifyBusinessEvent({
    societyId,
    recipientUserId: String(updated.requestedByGuardId),
    type: 'PARCEL_AWAITING_HANDOVER',
    title: 'Accept parcel at the gate',
    body: `${updated.visitorName} may leave a parcel for ${flatLabel}. Do not allow visitor entry.`,
    relatedEntityType: 'ParcelHandover',
    relatedEntityId: String(parcel._id),
    idempotencyKey: `PARCEL_AWAITING:${String(parcel._id)}:guard`,
    metadata: {
      visitorName: updated.visitorName,
      visitorPhone: updated.visitorPhone || '',
      flatLabel,
      parcelId: String(parcel._id),
      parcelStatus: 'AWAITING_HANDOVER',
      deepLink: `apnasociety://parcel/${String(parcel._id)}`,
    },
  });

  const { serializeParcel } = await import('./parcel.service');
  return {
    visitor: serializeVisitor(updated),
    parcel: serializeParcel(parcel),
  };
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
